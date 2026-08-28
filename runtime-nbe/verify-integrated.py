#!/usr/bin/env python3
"""Verify the in-process Agda -> cctt -> Agda recheck vertical slice."""

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

from symbol_audit import missing_provider_symbols
from agda_data import AgdaDataFailure, verify_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
BUILD = ROOT / "build-integrated.py"
FIXTURE = ROOT / "fixtures" / "RuntimePolicyOverride.agda"
POLICY_RULES_VERIFY = ROOT / "examples" / "policy-rules" / "verify.py"
AGDA_REVISION = "3d04bacca842729f9c0869b9287256321b5f450f"
PROVIDER_REVISION = "ba16f3758a322e9be77ada1da2b93f45d500192e"
LOCKED_CABAL_PACKAGES = json.loads(
    (ROOT / "cabal-packages.lock.json").read_text(encoding="utf-8")
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, cwd=None, env=None):
    return subprocess.run(
        command,
        cwd=str(cwd or REPOSITORY),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_identity():
    head = run(["git", "rev-parse", "HEAD"])
    if head.returncode != 0:
        return "NOT-A-GIT-CHECKOUT"
    status = run(["git", "status", "--porcelain", "--untracked-files=all"])
    return head.stdout.strip() + ("+DIRTY" if status.returncode or status.stdout else "")


def parse_result(path):
    fields = []
    for line in path.read_text(encoding="utf-8").splitlines():
        require("=" in line, "result packet contains a line without '='")
        key, value = line.split("=", 1)
        require(key and value, "result packet contains an empty key or value")
        fields.append((key, value))
    result = dict(fields)
    require(len(fields) == len(result), "result packet contains duplicate fields")
    require(
        set(result) == {
            "schema", "provider", "provider-revision", "source-qname",
            "runtime-input-schema", "runtime-input-sha256", "definition-count",
            "term-syntax", "type-syntax", "recheck",
        },
        "result packet field set is incomplete or unknown",
    )
    require(result["schema"] == "runtime-nbe-result-v1", "result schema drift")
    require(result["provider"] == "cctt", "result provider drift")
    require(result["provider-revision"] == PROVIDER_REVISION, "result revision drift")
    require(result["recheck"] == "agda-check-internal", "Agda recheck evidence missing")
    return result


def execute(binary, fixture, entry, output, path_directory, agda_data_dir):
    environment = os.environ.copy()
    environment["PATH"] = str(path_directory)
    environment["Agda_datadir"] = str(agda_data_dir)
    return run([
        str(binary), "--cubical", "--no-libraries", "-i", str(fixture.parent),
        f"--runtime-nbe-entry={fixture.stem}.{entry}",
        f"--runtime-nbe-output={output}", str(fixture),
    ], env=environment)


def install_process_traps(directory, marker):
    directory.mkdir()
    script = "#!/bin/sh\nprintf invoked > '" + str(marker) + "'\nexit 97\n"
    for name in ("agda", "cabal", "ghc", "git", "stack"):
        path = directory / name
        path.write_text(script, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--provider-source", default=os.environ.get("CCTT_SOURCE_DIR"))
    parser.add_argument(
        "--output", default=str(REPOSITORY / "build" / "runtime-nbe-integrated")
    )
    parser.add_argument("--binary")
    parser.add_argument("--cabal", default=os.environ.get("CABAL", "cabal"))
    parser.add_argument("--ghc", default=os.environ.get("GHC", "ghc"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    parser.add_argument(
        "--strict-impl-params-source",
        default=os.environ.get("STRICT_IMPL_PARAMS_SOURCE_DIR"),
    )
    parser.add_argument(
        "--primdata-source", default=os.environ.get("PRIMDATA_SOURCE_DIR")
    )
    parser.add_argument("--nm", default=os.environ.get("NM", "nm"))
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    output = Path(args.output).expanduser().absolute()
    if args.binary:
        binary = Path(args.binary).expanduser().resolve()
    else:
        require(args.agda_source and args.provider_source,
                "provide both locked source trees when building")
        command = [
            sys.executable, "-B", str(BUILD),
            "--agda-source", args.agda_source,
            "--provider-source", args.provider_source,
            "--output", str(output), "--cabal", args.cabal,
            "--ghc", args.ghc, "--git", args.git,
        ]
        if args.strict_impl_params_source:
            command.extend(
                ["--strict-impl-params-source", args.strict_impl_params_source]
            )
        if args.primdata_source:
            command.extend(["--primdata-source", args.primdata_source])
        if args.offline:
            command.append("--offline")
        built = run(command)
        require(built.returncode == 0, built.stdout + built.stderr)
        binary = output / "bin" / "agda-cctt-runtime"
    require(binary.is_file(), "integrated runtime binary is missing")
    provenance_path = output / "provenance.json"
    require(provenance_path.is_file(), "integrated provenance is missing")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    configured_data_dir = output / "agda-data"
    require(
        (configured_data_dir / "lib" / "prim" / "_build" / "2.8.0" / "agda"
         / "Agda" / "Primitive.agdai").is_file(),
        "integrated cold Agda primitive interfaces are missing",
    )
    require(provenance["agda_data"]["relative_path"] == "agda-data",
            "integrated Agda data provenance relative path drift")
    try:
        verify_agda_data(configured_data_dir, provenance["agda_data"])
    except AgdaDataFailure as error:
        require(False, str(error))
    require(provenance["agda"]["revision"] == AGDA_REVISION, "Agda revision drift")
    require(provenance["provider"]["revision"] == PROVIDER_REVISION,
            "provider revision drift")
    require(
        provenance["locked_cabal_packages"] == LOCKED_CABAL_PACKAGES,
        "locked Cabal package identity drift",
    )
    require(provenance["binary"]["sha256"] == sha256_file(binary),
            "integrated binary hash drift")
    oracle_binary = output / "bin" / "agda-runtime-nbe-oracle"
    require(oracle_binary.is_file(), "independent Agda oracle binary is missing")
    require(
        provenance["oracle_binary"]["sha256"] == sha256_file(oracle_binary),
        "Agda oracle binary hash drift",
    )

    print("verify-runtime-nbe-integrated: commit=" + git_identity())
    print("evidence: fixture-sha256=" + sha256_file(FIXTURE))
    print("evidence: agda-revision=" + AGDA_REVISION)
    print("evidence: provider-revision=" + PROVIDER_REVISION)
    print("evidence: ghc=" + provenance["tools"]["ghc"])
    print("evidence: binary-sha256=" + sha256_file(binary))
    print("PASS locked Agda, cctt, dependency, source and binary identities")

    nm = shutil.which(args.nm)
    require(nm, f"nm executable not found: {args.nm}")
    symbols = run([nm, "-g", str(binary)])
    require(symbols.returncode == 0, symbols.stderr)
    missing = missing_provider_symbols(symbols.stdout, require_adapter=False)
    require(not missing, "integrated binary lacks " + ", ".join(missing))
    require("CheckInternal_checkInternal" in symbols.stdout,
            "integrated binary lacks Agda checkInternal")
    require("CheckInternal_checkType" in symbols.stdout,
            "integrated binary lacks Agda checkType")
    require("RuntimeNbeziIntegrated" in symbols.stdout,
            "integrated binary lacks runtime integration module")
    print("PASS final binary links cctt eval/quote and Agda checkInternal/checkType")

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-integrated-") as temporary:
        temporary_path = Path(temporary)
        fixture = temporary_path / FIXTURE.name
        shutil.copy2(FIXTURE, fixture)
        trap_path = temporary_path / "path-traps"
        trap_marker = temporary_path / "subprocess-invoked"
        install_process_traps(trap_path, trap_marker)

        disabled_path = temporary_path / "disabled.result"
        disabled = execute(
            binary, fixture, "preserveDisabled", disabled_path, trap_path,
            configured_data_dir,
        )
        require(disabled.returncode == 0 and disabled_path.is_file(),
                disabled.stdout + disabled.stderr)
        disabled_result = parse_result(disabled_path)
        require(disabled_result["term-syntax"] == "false", "disabled policy changed")
        require(disabled_result["type-syntax"] == "Bool", "disabled result type changed")
        print("PASS disabled policy evaluates in cctt and rechecks as Agda Bool false")

        enabled_path = temporary_path / "enabled.result"
        enabled = execute(
            binary, fixture, "preserveEnabled", enabled_path, trap_path,
            configured_data_dir,
        )
        require(enabled.returncode == 0 and enabled_path.is_file(),
                enabled.stdout + enabled.stderr)
        enabled_result = parse_result(enabled_path)
        require(enabled_result["term-syntax"] == "true", "enabled policy changed")
        require(enabled_result["type-syntax"] == "Bool", "enabled result type changed")
        require(disabled_result["term-syntax"] != enabled_result["term-syntax"],
                "opposite checked Agda inputs did not affect the rechecked result")
        print("PASS opposite real Agda inputs produce opposite rechecked Terms")

        require(not trap_marker.exists(), "runtime invoked an external tool from PATH")
        print("PASS integrated runtime uses no Agda/cabal/GHC/git/Stack subprocess")

        active_path = temporary_path / "active.result"
        active = execute(
            binary, fixture, "activeOverride", active_path, trap_path,
            configured_data_dir,
        )
        require(active.returncode == 0 and active_path.is_file(),
                active.stdout + active.stderr)
        active_result = parse_result(active_path)
        require(active_result["runtime-input-schema"] == "runtime-nbe-ir-v14"
                and active_result["term-syntax"] == "true",
                "active hcomp did not traverse v14 cctt/recheck")
        print("PASS active face evaluates through non-empty cctt hcom and Agda recheck")

        unsupported_path = temporary_path / "unsupported.result"
        unsupported_path.write_text("stale-result-must-be-removed\n", encoding="utf-8")
        unsupported = execute(
            binary, fixture, "unsupportedNamedActiveTube", unsupported_path, trap_path,
            configured_data_dir,
        )
        require(unsupported.returncode != 0, "unsupported named active tube was accepted")
        require("CCNBE-AGDA-LOWER-REJECT" in unsupported.stdout + unsupported.stderr,
                "unsupported input lacks stable rejection")
        require(not unsupported_path.exists(), "unsupported input left a stale result")
        print("PASS unsupported named active tube fails closed without stale result")

        broken_fixture = temporary_path / "BrokenPolicy.agda"
        broken_fixture.write_text(
            fixture.read_text(encoding="utf-8").replace(
                "module RuntimePolicyOverride where", "module BrokenPolicy where"
            ).replace("primHComp {A = Bool}", "primHComp {A = Bool"),
            encoding="utf-8",
        )
        broken_path = temporary_path / "broken.result"
        broken = execute(
            binary, broken_fixture, "preserveDisabled", broken_path, trap_path,
            configured_data_dir,
        )
        require(broken.returncode != 0 and not broken_path.exists(),
                "malformed Agda source produced a result")
        print("PASS malformed source fails before runtime result publication")

    formal_environment = os.environ.copy()
    formal_environment["Agda_datadir"] = str(configured_data_dir)
    formal = run([
        sys.executable, "-B", str(POLICY_RULES_VERIFY),
        "--runtime-bin", str(binary), "--oracle-bin", str(oracle_binary),
    ], env=formal_environment)
    require(formal.returncode == 0 and "verify-policy-rules: 8/8 PASS" in formal.stdout,
            formal.stdout + formal.stderr)
    print(formal.stdout.rstrip())
    print("PASS cross-module policy-rules project independent entry")

    print("verify-runtime-nbe-integrated: 9/9 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-runtime-nbe-integrated: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
