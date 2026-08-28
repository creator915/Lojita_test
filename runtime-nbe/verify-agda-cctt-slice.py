#!/usr/bin/env python3
"""Verify the first real Agda Internal -> runtime IR -> in-process cctt slice."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from symbol_audit import final_symbol_commands, missing_final_provider_symbols
from agda_data import AgdaDataFailure, verify_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
AGDA_BUILD = ROOT / "build-agda-adapter.py"
PROVIDER_BUILD = ROOT / "build-provider.py"
FIXTURE = ROOT / "fixtures" / "RuntimePolicyOverride.agda"
AGDA_REVISION = "3d04bacca842729f9c0869b9287256321b5f450f"
PROVIDER_REVISION = "ba16f3758a322e9be77ada1da2b93f45d500192e"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, cwd=None, env=None):
    return subprocess.run(
        command, cwd=str(cwd or REPOSITORY), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_identity():
    result = run(["git", "rev-parse", "HEAD"])
    if result.returncode != 0:
        return "NOT-A-GIT-CHECKOUT"
    identity = result.stdout.strip()
    status = run(["git", "status", "--porcelain", "--untracked-files=all"])
    return identity + ("+DIRTY" if status.returncode != 0 or status.stdout else "")


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--provider-source", default=os.environ.get("CCTT_SOURCE_DIR"))
    parser.add_argument(
        "--output", default=str(REPOSITORY / "build" / "runtime-nbe-agda-cctt-slice")
    )
    parser.add_argument("--cabal", default=os.environ.get("CABAL", "cabal"))
    parser.add_argument("--ghc", default=os.environ.get("GHC", "ghc"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    parser.add_argument("--nm", default=os.environ.get("NM", "nm"))
    parser.add_argument("--stack", default=os.environ.get("STACK", "stack"))
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def lower(lowerer, fixture, entry, output, agda_data_dir):
    environment = os.environ.copy()
    environment["Agda_datadir"] = str(agda_data_dir)
    return run([
        str(lowerer), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-v", "impossible:100",
        "-i", str(fixture.parent),
        f"--runtime-nbe-entry=RuntimePolicyOverride.{entry}",
        f"--runtime-nbe-output={output}", str(fixture),
    ], env=environment)


def execute_runtime(provider, runtime_ir, empty_path=False):
    environment = os.environ.copy()
    if empty_path:
        environment["PATH"] = "/path-intentionally-empty"
    return run([str(provider), "--runtime-ir", str(runtime_ir)], env=environment)


def execute_policy(policy_binary, scenario, temporary_directory):
    environment = os.environ.copy()
    environment["PATH"] = "/path-intentionally-empty"
    environment["TMPDIR"] = str(temporary_directory)
    return run([str(policy_binary), scenario], env=environment)


def main(argv=None):
    args = parse_args(argv)
    require(args.agda_source, "provide --agda-source or AGDA_SOURCE_DIR")
    output = Path(args.output).expanduser().absolute()
    output.mkdir(parents=True, exist_ok=True)
    agda_output = output / "agda-lowerer"
    provider_output = output / "provider"

    agda_command = [
        sys.executable, "-B", str(AGDA_BUILD), "--agda-source", args.agda_source,
        "--output", str(agda_output), "--cabal", args.cabal,
        "--ghc", args.ghc, "--git", args.git,
    ]
    if args.offline:
        agda_command.append("--offline")
    built_agda = run(agda_command)
    require(built_agda.returncode == 0, built_agda.stdout + built_agda.stderr)

    lowerer = agda_output / "bin" / "agda-runtime-nbe-producer"
    agda_data_dir = agda_output / "agda-data"
    require(
        (agda_data_dir / "lib" / "prim" / "_build" / "2.8.0" / "agda"
         / "Agda" / "Primitive.agdai").is_file(),
        "cold Agda primitive interfaces are missing",
    )
    agda_provenance = json.loads((agda_output / "provenance.json").read_text())
    require(agda_provenance["agda_revision"] == AGDA_REVISION, "Agda identity drift")
    require(agda_provenance["binary_sha256"] == sha256_file(lowerer),
            "Agda lowerer binary hash drift")
    require(agda_provenance["agda_data"]["relative_path"] == "agda-data",
            "Agda data provenance relative path drift")
    try:
        verify_agda_data(agda_data_dir, agda_provenance["agda_data"])
    except AgdaDataFailure as error:
        require(False, str(error))

    with tempfile.TemporaryDirectory(prefix="agda-cctt-slice-", dir=output) as temporary:
        temporary_path = Path(temporary)
        fixture_copy = temporary_path / FIXTURE.name
        shutil.copy2(FIXTURE, fixture_copy)
        disabled_ir = temporary_path / "disabled.ir"
        enabled_ir = temporary_path / "enabled.ir"
        disabled_lower = lower(
            lowerer, fixture_copy, "preserveDisabled", disabled_ir, agda_data_dir
        )
        require(disabled_lower.returncode == 0 and disabled_ir.is_file(),
                disabled_lower.stdout + disabled_lower.stderr)
        require("schema=runtime-nbe-ir-v14" in disabled_ir.read_text()
                and "term-ast=hcomp(i0,empty,false)" in disabled_ir.read_text(),
                "disabled Internal term lowered incorrectly")
        print("PASS real Agda Internal primHComp/Bool/i0/empty-system lowers disabled input")

        enabled_lower = lower(
            lowerer, fixture_copy, "preserveEnabled", enabled_ir, agda_data_dir
        )
        require(enabled_lower.returncode == 0 and enabled_ir.is_file(),
                enabled_lower.stdout + enabled_lower.stderr)
        require("schema=runtime-nbe-ir-v14" in enabled_ir.read_text()
                and "term-ast=hcomp(i0,empty,true)" in enabled_ir.read_text(),
                "enabled Internal term lowered incorrectly")
        require(disabled_ir.read_bytes() != enabled_ir.read_bytes(),
                "opposite Agda inputs produced identical runtime IR")
        print("PASS opposite checked Agda input changes the structured runtime IR")

        provider_command = [
            sys.executable, "-B", str(PROVIDER_BUILD),
            "--output", str(provider_output),
            "--stack", args.stack, "--git", args.git,
            "--embedded-disabled-ir", str(disabled_ir),
            "--embedded-enabled-ir", str(enabled_ir),
        ]
        if args.provider_source:
            provider_command.extend(["--provider-source", args.provider_source])
        built_provider = run(provider_command)
        require(built_provider.returncode == 0,
                built_provider.stdout + built_provider.stderr)
        provider = provider_output / "bin" / "runtime-nbe-provider"
        policy_binary = provider_output / "bin" / "runtime-policy-user"
        provider_provenance = json.loads(
            (provider_output / "provenance.json").read_text()
        )
        require(provider_provenance["provider"]["revision"] == PROVIDER_REVISION,
                "provider identity drift")
        require(provider_provenance["binary"]["sha256"] == sha256_file(provider),
                "provider binary hash drift")
        require(policy_binary.is_file(), "embedded final user binary is missing")
        require(
            provider_provenance["embedded_policy"]["binary"]["sha256"]
            == sha256_file(policy_binary), "embedded user binary hash drift"
        )
        require(
            provider_provenance["embedded_policy"]["input_sha256"]
            == {"disabled": sha256_file(disabled_ir), "enabled": sha256_file(enabled_ir)},
            "embedded IR identity drift",
        )
        nm = shutil.which(args.nm)
        require(nm, f"nm executable not found: {args.nm}")
        policy_tables = [run(command) for command in final_symbol_commands(
            nm, policy_binary
        )]
        require(any(table.returncode == 0 for table in policy_tables),
                "no supported final symbol table is readable")
        policy_symbols = "\n".join(
            table.stdout for table in policy_tables if table.returncode == 0
        )
        missing = missing_final_provider_symbols(policy_symbols)
        require(not missing, "final user binary lacks " + ", ".join(missing))

        print("verify-agda-cctt-slice: commit=" + git_identity())
        print("evidence: fixture-sha256=" + sha256_file(FIXTURE))
        print("evidence: agda-revision=" + AGDA_REVISION)
        print("evidence: provider-revision=" + PROVIDER_REVISION)
        print("evidence: agda-ghc=" + agda_provenance["tools"]["ghc"])
        print("evidence: provider-ghc=" + provider_provenance["tools"]["ghc"])
        print("evidence: user-binary-sha256=" + sha256_file(policy_binary))
        print("PASS locked Agda lowerer, linked cctt and embedded user binary identities")

        before = set(temporary_path.glob("runtime-nbe-reflect*.cctt"))
        disabled = execute_policy(policy_binary, "disabled", temporary_path)
        require(disabled.returncode == 0 and disabled.stdout.strip() == "false",
                disabled.stdout + disabled.stderr)
        require("input=compile-time-embedded-agda-runtime-ir" in disabled.stderr,
                "final process lacks runtime IR evidence")
        print("PASS final user binary reflects embedded disabled IR through cctt HCom")

        enabled = execute_policy(policy_binary, "enabled", temporary_path)
        require(enabled.returncode == 0 and enabled.stdout.strip() == "true",
                enabled.stdout + enabled.stderr)
        require(disabled.stdout != enabled.stdout, "provider result is not input-sensitive")
        print("PASS final user binary reflects embedded enabled IR through cctt HCom")

        active_ir = temporary_path / "active.ir"
        active = lower(
            lowerer, fixture_copy, "activeOverride", active_ir, agda_data_dir
        )
        require(active.returncode == 0 and active_ir.is_file(),
                active.stdout + active.stderr)
        require("schema=runtime-nbe-ir-v14" in active_ir.read_text()
                and "term-ast=hcomp(i1,constant-system(true),true)"
                in active_ir.read_text(),
                "active Internal system lowered incorrectly")
        active_result = execute_runtime(provider, active_ir, empty_path=True)
        require(active_result.returncode == 0 and active_result.stdout.strip() == "true",
                active_result.stdout + active_result.stderr)
        print("PASS active-face hcomp lowers to and evaluates as a real non-empty cctt system")

        unsupported_ir = temporary_path / "unsupported.ir"
        unsupported_ir.write_text("stale-artifact-must-be-removed\n", encoding="utf-8")
        unsupported = lower(
            lowerer, fixture_copy, "unsupportedNamedActiveTube", unsupported_ir,
            agda_data_dir,
        )
        require(unsupported.returncode != 0, "unsupported named active tube was accepted")
        require("CCNBE-AGDA-LOWER-REJECT" in unsupported.stdout + unsupported.stderr,
                "unsupported Agda term lacks stable rejection")
        require(not unsupported_ir.exists(), "unsupported lowering left a runtime IR artifact")
        print("PASS unsupported named active tube fails closed before publication")

        tampered_ir = temporary_path / "tampered.ir"
        tampered_ir.write_text(
            enabled_ir.read_text().replace(PROVIDER_REVISION, "0" * 40), encoding="utf-8"
        )
        tampered = execute_runtime(provider, tampered_ir, empty_path=True)
        require(tampered.returncode != 0, "provider identity tamper was accepted")
        require("CCNBE-PROVIDER-REJECT" in tampered.stderr,
                "provider identity tamper lacks stable rejection")
        print("PASS provider identity mismatch fails closed")

        duplicate_ir = temporary_path / "duplicate.ir"
        duplicate_ir.write_text(
            enabled_ir.read_text() + "term-ast=hcomp(i0,empty,false)\n",
            encoding="utf-8")
        duplicate = execute_runtime(provider, duplicate_ir, empty_path=True)
        require(duplicate.returncode != 0, "duplicate runtime IR field was accepted")
        require("duplicate fields" in duplicate.stderr, "duplicate rejection is ambiguous")
        print("PASS malformed runtime IR fails closed")

        after = set(temporary_path.glob("runtime-nbe-reflect*.cctt"))
        require(before == after, "runtime reflection left a source or staging artifact")
        provider_sources = "\n".join(
            path.read_text(encoding="utf-8")
            for path in [
                *(ROOT / "provider-adapter" / "src").rglob("*.hs"),
                *(ROOT / "provider-adapter" / "app").rglob("*.hs"),
            ]
        )
        require("System.Process" not in provider_sources
                and "import Agda." not in provider_sources
                and "Agda.TypeChecking" not in provider_sources,
                "final provider contains a subprocess or Agda callback")
        print("PASS empty-PATH execution uses no Agda/subprocess and leaves no reflected source")

    print("verify-agda-cctt-slice: 10/10 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-agda-cctt-slice: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
