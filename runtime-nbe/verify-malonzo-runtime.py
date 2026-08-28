#!/usr/bin/env python3
"""Verify the final Stock Agda/MAlonzo client consumes rechecked cctt results."""

import argparse
import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

from symbol_audit import final_symbol_commands, missing_final_provider_symbols
from agda_data import AgdaDataFailure, verify_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
POLICY = ROOT / "examples" / "policy-rules"
ENTRY = "PolicyDecision.agda"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, cwd=None, env=None):
    return subprocess.run(
        command, cwd=str(cwd or REPOSITORY), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke_backend(binary, project, entry, output, environment):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project), f"--runtime-nbe-entry=PolicyDecision.{entry}",
        f"--runtime-nbe-output={output}", str(project / ENTRY),
    ], env=environment)


def install_traps(directory, marker):
    directory.mkdir()
    script = "#!/bin/sh\nprintf invoked > '" + str(marker) + "'\nexit 97\n"
    for name in ("agda", "cabal", "ghc", "git", "stack"):
        path = directory / name
        path.write_text(script, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--producer-bin", required=True)
    parser.add_argument("--integrated-bin", required=True)
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--nm", default=os.environ.get("NM", "nm"))
    args = parser.parse_args(argv)
    output = Path(args.output).expanduser().resolve()
    binary = output / "bin" / "runtime-nbe-client"
    producer = Path(args.producer_bin).expanduser().resolve()
    integrated = Path(args.integrated_bin).expanduser().resolve()
    agda_data_dir = integrated.parent.parent / "agda-data"
    require(
        (agda_data_dir / "lib" / "prim" / "_build" / "2.8.0" / "agda"
         / "Agda" / "Primitive.agdai").is_file(),
        "integrated cold Agda primitive interfaces are missing",
    )
    require(binary.is_file() and producer.is_file() and integrated.is_file(),
            "required runtime binary is missing")
    provenance = json.loads((output / "provenance.json").read_text(encoding="utf-8"))
    integrated_provenance = json.loads(
        (integrated.parent.parent / "provenance.json").read_text(encoding="utf-8")
    )
    try:
        verify_agda_data(agda_data_dir, integrated_provenance["agda_data"])
    except AgdaDataFailure as error:
        require(False, str(error))
    require(provenance["binary"]["sha256"] == digest(binary), "binary identity drift")
    require(provenance["agda_revision"] ==
            "3d04bacca842729f9c0869b9287256321b5f450f", "Agda revision drift")
    require(provenance["provider_revision"] ==
            "ba16f3758a322e9be77ada1da2b93f45d500192e", "provider revision drift")
    print("PASS locked Stock Agda, generated MAlonzo, provider and binary identities")

    nm = shutil.which(args.nm)
    require(nm, "nm is unavailable")
    symbol_tables = [run(command) for command in final_symbol_commands(nm, binary)]
    require(any(table.returncode == 0 for table in symbol_tables),
            "no supported MAlonzo final symbol table is readable")
    symbols = "\n".join(
        table.stdout for table in symbol_tables if table.returncode == 0
    )
    require(not missing_final_provider_symbols(symbols),
            "MAlonzo final binary lacks stable cctt ABI")
    require("MAlonzzoziCodeziRuntimeNbeClient" in symbols,
            "final binary lacks generated MAlonzo client")
    print("PASS final binary contains MAlonzo client and stable cctt runtime ABI")

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-malonzo-verify-") as temporary:
        root = Path(temporary)
        project = root / "project"
        project.mkdir()
        for name in ("PolicyRules.agda", ENTRY):
            shutil.copy2(POLICY / name, project / name)
        trap_path = root / "path-traps"
        marker = root / "external-tool-invoked"
        install_traps(trap_path, marker)
        environment = os.environ.copy()
        environment["PATH"] = str(trap_path)
        environment["Agda_datadir"] = str(agda_data_dir)

        results = {}
        for entry, expected in (
            ("reviewedEscalation", "true"),
            ("blockedDuringFreeze", "false"),
        ):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            produced = invoke_backend(producer, project, entry, packet, environment)
            require(produced.returncode == 0 and packet.is_file(),
                    produced.stdout + produced.stderr)
            rechecked = invoke_backend(integrated, project, entry, checked, environment)
            require(rechecked.returncode == 0 and checked.is_file(),
                    rechecked.stdout + rechecked.stderr)
            executed = run([str(binary), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == expected,
                    executed.stdout + executed.stderr)
            results[entry] = (packet, checked)
        print("PASS dynamic true/false packets reach cctt and checked results in MAlonzo")

        packet, checked = results["reviewedEscalation"]
        changed = root / "changed.result"
        changed.write_text(
            checked.read_text(encoding="utf-8").replace("term-syntax=true", "term-syntax=false"),
            encoding="utf-8",
        )
        rejected = run([str(binary), str(packet), str(changed)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "tampered checked result was accepted")
        print("PASS checked normal-form tampering fails closed")

        wrong_packet = root / "wrong.ir"
        wrong_packet.write_text(
            packet.read_text(encoding="utf-8").replace(
                "source-qname=PolicyDecision.reviewedEscalation",
                "source-qname=PolicyDecision.otherEscalation",
            ), encoding="utf-8",
        )
        rejected = run([str(binary), str(wrong_packet), str(checked)], env=environment)
        require(rejected.returncode != 0 and "source-qname" in rejected.stderr,
                "packet/result identity mismatch was accepted")
        print("PASS packet and rechecked source identities are bound")

        byte_changed = root / "byte-changed.ir"
        byte_changed.write_bytes(packet.read_bytes() + b"\n")
        rejected = run([str(binary), str(byte_changed), str(checked)], env=environment)
        require(rejected.returncode != 0
                and "runtime-input-sha256 identity mismatch" in rejected.stderr,
                "semantically equivalent packet byte tampering escaped SHA-256 binding")
        print("PASS exact runtime IR bytes are SHA-256-bound to the Agda recheck")

        oversized = root / "oversized.result"
        oversized.write_bytes(b"x" * (64 * 1024 + 1))
        rejected = run([str(binary), str(packet), str(oversized)], env=environment)
        require(rejected.returncode != 0 and "exceeds 64 KiB" in rejected.stderr,
                "oversized checked result was accepted")
        print("PASS checked-result size limit is enforced")

        require(not marker.exists(), "runtime path invoked an external build tool")
        print("PASS producer, integrated recheck and final client use no PATH tool callback")

    print("verify-runtime-nbe-malonzo: 8/8 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-runtime-nbe-malonzo: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
