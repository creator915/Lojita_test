#!/usr/bin/env python3
"""End-to-end verification for empty-system Bool Glue introduction/elimination."""

import argparse
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT = Path(__file__).resolve().parent
ENTRY = "GlueMigration.agda"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, env=None):
    return subprocess.run(command, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def fields(path):
    pairs = [line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines()]
    require(all(len(pair) == 2 for pair in pairs), "malformed packet")
    result = dict(pairs)
    require(len(result) == len(pairs), "duplicate packet field")
    return result


def rebind_digest(packet, checked, output):
    digest = hashlib.sha256(packet.read_bytes()).hexdigest()
    output.write_text(checked.read_text(encoding="utf-8").replace(
        fields(checked)["runtime-input-sha256"], digest), encoding="utf-8")
    return output


def invoke(binary, project, entry, output, environment):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project), f"--runtime-nbe-entry=GlueMigration.{entry}",
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
    for option in ("producer-bin", "runtime-bin", "oracle-bin", "malonzo-bin"):
        parser.add_argument("--" + option, required=True)
    args = parser.parse_args(argv)
    producer, runtime, oracle, malonzo = [
        Path(getattr(args, name.replace("-", "_"))).expanduser().resolve()
        for name in ("producer-bin", "runtime-bin", "oracle-bin", "malonzo-bin")
    ]
    require(all(path.is_file() for path in (producer, runtime, oracle, malonzo)),
            "required binary is missing")

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-glue-migration-") as temporary:
        root = Path(temporary)
        project = root / "project"
        project.mkdir()
        shutil.copy2(PROJECT / ENTRY, project / ENTRY)
        marker = root / "tool-invoked"
        trap_path = root / "path-traps"
        install_traps(trap_path, marker)
        environment = os.environ.copy()
        environment["PATH"] = str(trap_path)

        artifacts = {}
        for entry, expected in (("glueApproved", "true"), ("glueRejected", "false")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["term-ast"].startswith(
                        "unglue(glue(bool,i0,empty,"),
                    "Glue operation/schema drift")
            require(fields(checked)["term-syntax"] == expected, "Glue result drift")
            require(fields(checked)["term-syntax"] == fields(oracle_result)["term-syntax"],
                    "Glue result differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == expected,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS opposite Glue payloads traverse real prim^glue/unglue and cctt")
        print("PASS same-input Agda oracle matches both Glue normal forms")
        print("PASS MAlonzo final program consumes both rechecked Glue results")

        stale = root / "named.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedNamedPayload", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unsupported named Glue payload was accepted or left stale output")
        print("PASS unsupported named Glue payload fails closed without stale output")

        packet, checked = artifacts["glueApproved"]
        wrong_system = root / "wrong-system.ir"
        wrong_system.write_text(
            packet.read_text(encoding="utf-8").replace(
                "glue(bool,i0,empty,", "glue(bool,i0,guessed,"),
            encoding="utf-8",
        )
        system_checked = rebind_digest(
            wrong_system, checked, root / "wrong-system.result")
        rejected = run(
            [str(malonzo), str(wrong_system), str(system_checked)], env=environment)
        require(rejected.returncode != 0 and "does not check" in rejected.stderr,
                "Glue equivalence system tampering was accepted")
        print("PASS Glue equivalence-system tampering fails closed")

        opposite = root / "opposite.ir"
        opposite.write_text(
            packet.read_text(encoding="utf-8").replace(
                "glue(bool,i0,empty,true)", "glue(bool,i0,empty,false)"),
            encoding="utf-8",
        )
        opposite_checked = rebind_digest(opposite, checked, root / "opposite.result")
        rejected = run(
            [str(malonzo), str(opposite), str(opposite_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "opposite Glue value was accepted against the checked result")
        print("PASS rechecked Glue result is bound to its exact runtime packet")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS Glue runtime invokes no PATH build tool")

    print("verify-glue-migration: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-glue-migration: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
