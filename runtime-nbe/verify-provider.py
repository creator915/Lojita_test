#!/usr/bin/env python3
"""Verify the first real, linked cctt provider slice."""

import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from symbol_audit import (
    final_symbol_commands, missing_final_provider_symbols, missing_provider_symbols,
)


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
ADAPTER = ROOT / "provider-adapter"
LOCK_PATH = ROOT / "provider.lock.json"
BUILD = ROOT / "build-provider.py"
FIXTURE = ROOT / "fixtures" / "provider-slice.cctt"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_identity():
    result = subprocess.run(
        ["git", "-C", str(REPOSITORY), "rev-parse", "HEAD"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def adapter_inputs():
    return sorted(
        [
            BUILD,
            LOCK_PATH,
            FIXTURE,
            *(ROOT / "licenses").glob("*.txt"),
            ADAPTER / "stack.yaml",
            ADAPTER / "cctt-runtime-provider.cabal",
            *(ADAPTER / "src").rglob("*.hs"),
            *(ADAPTER / "app").rglob("*.hs"),
            *(ADAPTER / "policy-app").rglob("*.hs"),
        ]
    )


def run(command, cwd=None, env=None):
    return subprocess.run(
        command,
        cwd=str(cwd or REPOSITORY),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def run_provider(binary, source, definition, empty_path=False):
    environment = os.environ.copy()
    if empty_path:
        environment["PATH"] = "/path-intentionally-empty"
    return run([str(binary), str(source), definition], env=environment)


def run_provider_audit(binary, empty_path=False):
    environment = os.environ.copy()
    if empty_path:
        environment["PATH"] = "/path-intentionally-empty"
    return run([str(binary), "--audit-eval-quote"], env=environment)


def runtime_ir_v3(definitions, expression):
    lines = [
        "schema=runtime-nbe-ir-v3",
        "operation=hcomp-empty-face",
        "value-type=agda-builtin-bool",
        "base-expression=" + expression,
        "definition-count=" + str(len(definitions)),
    ]
    for index, body in enumerate(definitions):
        lines.extend([
            f"def{index}-qname=PacketBoundary.def{index}",
            f"def{index}-type=pi-bool-bool",
            f"def{index}-body={body}",
        ])
    lines.extend([
        "source-qname=PacketBoundary.result",
        "agda-revision=3d04bacca842729f9c0869b9287256321b5f450f",
        "provider-revision=ba16f3758a322e9be77ada1da2b93f45d500192e",
    ])
    return "\n".join(lines) + "\n"


def runtime_ir_v14(definitions, expression, result_type="bool"):
    lines = [
        "schema=runtime-nbe-ir-v14",
        "language=runtime-nbe-typed-ast-v1",
        "context-size=0",
        "type-ast=" + result_type,
        "term-ast=" + expression,
        "definition-count=" + str(len(definitions)),
    ]
    for index, (definition_type, body) in enumerate(definitions):
        lines.extend([
            f"def{index}-qname=PacketBoundary.def{index}",
            f"def{index}-type-ast={definition_type}",
            f"def{index}-body-ast={body}",
        ])
    lines.extend([
        "source-qname=PacketBoundary.result",
        "agda-revision=3d04bacca842729f9c0869b9287256321b5f450f",
        "provider-revision=ba16f3758a322e9be77ada1da2b93f45d500192e",
    ])
    return "\n".join(lines) + "\n"


def run_runtime_packet(binary, directory, name, contents, overrides=None):
    packet = directory / name
    packet.write_text(contents, encoding="utf-8")
    environment = os.environ.copy()
    environment["PATH"] = "/path-intentionally-empty"
    environment.update(overrides or {})
    return run([str(binary), "--runtime-ir", str(packet)], env=environment)


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider-source", default=os.environ.get("CCTT_SOURCE_DIR"))
    parser.add_argument("--output", default=str(REPOSITORY / "build" / "runtime-nbe"))
    parser.add_argument("--binary")
    parser.add_argument("--nm", default=os.environ.get("NM", "nm"))
    parser.add_argument("--strip", default=os.environ.get("STRIP", "strip"))
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    output = Path(args.output).expanduser().absolute()
    provider_source = (
        Path(args.provider_source).expanduser().resolve()
        if args.provider_source else output / "provider-source"
    )
    if args.binary:
        binary = Path(args.binary).expanduser().resolve()
        require(provider_source.is_dir(), "provider source is required with --binary")
    else:
        command = [sys.executable, "-B", str(BUILD), "--output", str(output)]
        if args.provider_source:
            command.extend(["--provider-source", str(provider_source)])
        built = run(command)
        require(built.returncode == 0, built.stdout + built.stderr)
        binary = output / "bin" / "runtime-nbe-provider"
    require(binary.is_file(), "runtime provider binary is missing")
    provenance_path = output / "provenance.json"
    require(provenance_path.is_file(), "runtime provider provenance is missing")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    lock = json.loads(LOCK_PATH.read_text(encoding="utf-8"))
    archive = Path(provenance["library"]["path"])

    print("verify-runtime-provider: commit=" + git_identity())
    print("verify-runtime-provider: python=" + sys.version.splitlines()[0])
    print("evidence: provider-revision=" + provenance["provider"]["revision"])
    print("evidence: provider-source-sha256=" + provenance["provider"]["source_archive_sha256"])
    print("evidence: ghc=" + provenance["tools"]["ghc"])
    print("evidence: binary-sha256=" + sha256_file(binary))

    require(provenance["provider"]["revision"] == lock["provider"]["revision"], "provider revision drift")
    require(provenance["provider"]["license"] == "MIT", "provider license drift")
    require(
        provenance["source_dependencies"] == lock["source_dependencies"],
        "provider source dependency identity or license drift",
    )
    stack_lock = output / "stage" / "stack.yaml.lock"
    require(stack_lock.is_file(), "resolved Stack dependency lock is missing")
    require(
        provenance["resolved_stack_lock_sha256"] == sha256_file(stack_lock),
        "resolved Stack dependency lock drift",
    )
    require(provenance["binary"]["sha256"] == sha256_file(binary), "provider binary hash mismatch")
    require(archive.is_file(), "linkable provider archive is missing")
    require(provenance["library"]["sha256"] == sha256_file(archive), "provider archive hash mismatch")
    actual_adapter = {
        str(path.relative_to(ROOT)): sha256_file(path) for path in adapter_inputs()
    }
    require(provenance["adapter_source_sha256"] == actual_adapter, "adapter source provenance drift")
    print("PASS locked repository, revision, license, source and build provenance")

    nm = shutil.which(args.nm)
    require(nm, f"nm executable not found: {args.nm}")
    archive_symbols = run([nm, "-g", str(archive)])
    require(archive_symbols.returncode == 0, archive_symbols.stderr)
    binary_tables = [run(command) for command in final_symbol_commands(nm, binary)]
    require(any(table.returncode == 0 for table in binary_tables),
            "no supported final provider symbol table is readable")
    binary_symbols = "\n".join(
        table.stdout for table in binary_tables if table.returncode == 0
    )
    missing = missing_provider_symbols(archive_symbols.stdout)
    require(not missing, "archive lacks " + ", ".join(missing))
    missing = missing_final_provider_symbols(binary_symbols)
    require(not missing, "final binary lacks " + ", ".join(missing))
    audit = run_provider_audit(binary, empty_path=True)
    require(
        audit.returncode == 0 and audit.stdout.strip() == "provider-eval-quote=ok",
        audit.stdout + audit.stderr,
    )
    strip_tool = shutil.which(args.strip)
    require(strip_tool, f"strip executable not found: {args.strip}")
    with tempfile.TemporaryDirectory(prefix="runtime-nbe-strip-audit-") as temporary:
        stripped_binary = Path(temporary) / binary.name
        shutil.copy2(binary, stripped_binary)
        strip_arguments = [strip_tool]
        strip_arguments.append("-x" if platform.system() == "Darwin" else "--strip-all")
        stripped = run([*strip_arguments, str(stripped_binary)])
        require(stripped.returncode == 0, stripped.stdout + stripped.stderr)
        stripped_tables = [
            run(command) for command in final_symbol_commands(nm, stripped_binary)
        ]
        require(any(table.returncode == 0 for table in stripped_tables),
                "no supported stripped-final symbol table is readable")
        stripped_symbols = "\n".join(
            table.stdout for table in stripped_tables if table.returncode == 0
        )
        missing = missing_final_provider_symbols(stripped_symbols)
        require(not missing, "stripped final binary lacks " + ", ".join(missing))
        stripped_audit = run_provider_audit(stripped_binary, empty_path=True)
        require(
            stripped_audit.returncode == 0
            and stripped_audit.stdout.strip() == "provider-eval-quote=ok",
            stripped_audit.stdout + stripped_audit.stderr,
        )
    print("PASS archive internals and stripped final ABI execute cctt eval/quote")

    identity = run([str(binary), "--identity"])
    require(identity.returncode == 0, identity.stderr)
    require("provider=cctt" in identity.stdout, "provider identity missing")
    require(lock["provider"]["revision"] in identity.stdout, "provider revision missing")
    print("PASS final binary reports the locked provider identity")

    provider_tests = output / "provider-tests"
    fixture = provider_tests / FIXTURE.name
    left = run_provider(binary, fixture, "transportFalse", empty_path=True)
    right = run_provider(binary, fixture, "transportTrue", empty_path=True)
    require(left.returncode == 0 and left.stdout.strip() == "true", left.stdout + left.stderr)
    require(right.returncode == 0 and right.stdout.strip() == "false", right.stdout + right.stderr)
    require(left.stdout != right.stdout, "opposite inputs did not affect provider output")
    print("PASS opposite checked inputs drive opposite cctt Coe/Glue normal forms")

    upstream = run_provider(binary, provider_tests / "bool.cctt", "test", empty_path=True)
    require(upstream.returncode == 0 and upstream.stdout.strip() == "true", upstream.stdout + upstream.stderr)
    require("definition=test" in upstream.stderr, "provider execution evidence missing")
    print("PASS locked upstream 11-step Glue transport reaches the final binary")

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-packet-boundary-") as temporary:
        boundary = Path(temporary)
        valid_v3 = runtime_ir_v3(
            ["arg0", "apply-def0(arg0)"], "apply-def1(true)"
        )
        valid = run_runtime_packet(binary, boundary, "valid-v3.ir", valid_v3)
        require(valid.returncode == 0 and valid.stdout.strip() == "true",
                valid.stdout + valid.stderr)
        print("PASS versioned multi-definition packet evaluates through cctt")

        valid_v14 = runtime_ir_v14(
            [("pi(bool,bool)", "var(0)"),
             ("pi(bool,bool)", "app(def(0),var(0))")],
            "hcomp(i0,empty,app(def(1),true))",
        )
        valid = run_runtime_packet(binary, boundary, "valid-v14.ir", valid_v14)
        require(valid.returncode == 0 and valid.stdout.strip() == "true",
                valid.stdout + valid.stderr)

        malformed = valid_v14.replace(
            "term-ast=hcomp(i0,empty,app(def(1),true))",
            "term-ast=hcomp(i0,empty,app(def(1),true))trailing",
        )
        rejected = run_runtime_packet(binary, boundary, "v14-trailing.ir", malformed)
        require(rejected.returncode != 0 and "trailing input" in rejected.stderr,
                "v14 AST with trailing input was accepted")

        open_term = runtime_ir_v14([], "hcomp(i0,empty,var(0))")
        rejected = run_runtime_packet(binary, boundary, "v14-open.ir", open_term)
        require(rejected.returncode != 0 and "open argument" in rejected.stderr,
                "v14 open top-level term was accepted")

        forward_v14 = runtime_ir_v14(
            [("pi(bool,bool)", "app(def(1),var(0))"),
             ("pi(bool,bool)", "var(0)")],
            "hcomp(i0,empty,app(def(1),true))",
        )
        rejected = run_runtime_packet(binary, boundary, "v14-forward.ir", forward_v14)
        require(rejected.returncode != 0 and "forward definition" in rejected.stderr,
                "v14 forward definition reference was accepted")

        ill_typed = runtime_ir_v14(
            [("sigma(bool,bool)", "var(0)")],
            "hcomp(i0,empty,app(def(0),true))",
        )
        rejected = run_runtime_packet(binary, boundary, "v14-ill-typed.ir", ill_typed)
        require(rejected.returncode != 0 and "definition type" in rejected.stderr,
                "v14 ill-typed definition was accepted")

        deeply_nested = "true"
        for _ in range(34):
            deeply_nested = "app(def(0)," + deeply_nested + ")"
        rejected = run_runtime_packet(
            binary, boundary, "v14-too-deep.ir",
            runtime_ir_v14(
                [("pi(bool,bool)", "var(0)")],
                "hcomp(i0,empty," + deeply_nested + ")",
            ),
        )
        require(rejected.returncode != 0 and "exceeds depth 32" in rejected.stderr,
                "v14 textual AST depth was not rejected before recursive parsing")
        print("PASS unified v14 AST accepts a real closure and rejects trailing, open, forward, ill-typed and over-deep terms")

        allocation_limited = run_runtime_packet(
            binary, boundary, "allocation-limited.ir", valid_v3,
            {"RUNTIME_NBE_MAX_ALLOCATION_BYTES": "1"},
        )
        require(allocation_limited.returncode != 0
                and "allocation budget exceeded" in allocation_limited.stderr,
                "real cctt execution escaped its allocation budget")
        print("PASS real cctt evaluation is interrupted by its allocation budget")

        timeout_limited = run_runtime_packet(
            binary, boundary, "timeout-limited.ir", valid_v3,
            {"RUNTIME_NBE_TIMEOUT_MICROS": "1"},
        )
        require(timeout_limited.returncode != 0
                and "wall timeout exceeded" in timeout_limited.stderr,
                "real cctt execution escaped its wall timeout")
        print("PASS real cctt evaluation is interrupted by its wall timeout")

        fuel_limited = run_runtime_packet(
            binary, boundary, "fuel-limited.ir", valid_v3,
            {"RUNTIME_NBE_MAX_FUEL": "1"},
        )
        require(fuel_limited.returncode != 0
                and "adapter semantic fuel exhausted" in fuel_limited.stderr,
                "semantic adapter workload escaped its fuel budget")
        print("PASS reflected semantic workload is rejected when adapter fuel is exhausted")

        invalid_limit = run_runtime_packet(
            binary, boundary, "invalid-limit.ir", valid_v3,
            {"RUNTIME_NBE_TIMEOUT_MICROS": "not-a-limit"},
        )
        require(invalid_limit.returncode != 0
                and "must be a positive decimal integer" in invalid_limit.stderr,
                "invalid resource configuration was accepted")
        print("PASS malformed resource configuration fails closed")

        invalid_fuel = run_runtime_packet(
            binary, boundary, "invalid-fuel.ir", valid_v3,
            {"RUNTIME_NBE_MAX_FUEL": "0"},
        )
        require(invalid_fuel.returncode != 0
                and "RUNTIME_NBE_MAX_FUEL must be a positive decimal integer"
                in invalid_fuel.stderr,
                "invalid semantic fuel configuration was accepted")
        print("PASS malformed semantic fuel configuration fails closed")

        forward = runtime_ir_v3(
            ["apply-def1(arg0)", "arg0"], "apply-def1(true)"
        )
        rejected = run_runtime_packet(binary, boundary, "forward.ir", forward)
        require(rejected.returncode != 0 and "forward definition" in rejected.stderr,
                "forward definition reference was accepted")
        print("PASS missing/forward definition reference fails closed")

        too_many = runtime_ir_v3(["true"] * 33, "true")
        rejected = run_runtime_packet(binary, boundary, "too-many.ir", too_many)
        require(rejected.returncode != 0 and "outside 1..32" in rejected.stderr,
                "definition-count limit was not enforced")
        print("PASS definition-count resource limit is enforced")

        deep_expression = "true"
        for _ in range(34):
            deep_expression = "apply-def0(" + deep_expression + ")"
        rejected = run_runtime_packet(
            binary, boundary, "too-deep.ir",
            runtime_ir_v3(["arg0"], deep_expression),
        )
        require(rejected.returncode != 0 and "exceeds depth 32" in rejected.stderr,
                "expression-depth limit was not enforced")
        print("PASS expression-depth resource limit is enforced")

    adapter_sources = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in [*(ADAPTER / "src").rglob("*.hs"), *(ADAPTER / "app").rglob("*.hs")]
    )
    provider_sources = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in (provider_source / "src").rglob("*.hs")
    )
    forbidden_process = ["System.Process", "createProcess", "callProcess", "rawSystem"]
    require(
        not any(token in adapter_sources + provider_sources for token in forbidden_process),
        "provider or adapter contains a subprocess callback",
    )
    require("normalise" not in adapter_sources
            and "import Agda." not in adapter_sources
            and "Agda.TypeChecking" not in adapter_sources,
            "adapter contains an Agda/compiler normalization callback")
    require(left.returncode == 0 and right.returncode == 0 and upstream.returncode == 0, "empty PATH execution failed")
    print("PASS provider runs with an empty PATH and adapter has no Agda/subprocess callback")

    missing = run_provider(binary, fixture, "notARealDefinition")
    require(missing.returncode != 0, "missing definition was accepted")
    require("CCNBE-PROVIDER-REJECT" in missing.stderr, "missing definition lacks stable rejection")
    print("PASS missing provider definition fails closed")

    with tempfile.TemporaryDirectory(prefix="runtime-provider-negative-") as temporary:
        temporary_path = Path(temporary)
        malformed = temporary_path / "malformed.cctt"
        malformed.write_text("broken := not-in-scope;\n", encoding="utf-8")
        rejected = run_provider(binary, malformed, "broken")
        require(rejected.returncode != 0, "malformed provider input was accepted")
        require("CCNBE-PROVIDER-REJECT" in rejected.stderr, "malformed input lacks stable rejection")
        print("PASS malformed provider source fails closed")

        dirty_source = temporary_path / "dirty-cctt"
        cloned = run(["git", "clone", "--shared", str(provider_source), str(dirty_source)])
        require(cloned.returncode == 0, cloned.stderr)
        readme = dirty_source / "README.md"
        readme.write_text(readme.read_text(encoding="utf-8") + "\nmutation\n", encoding="utf-8")
        dirty_build = run(
            [
                sys.executable,
                "-B",
                str(BUILD),
                "--provider-source",
                str(dirty_source),
                "--output",
                str(temporary_path / "dirty-output"),
            ]
        )
        require(dirty_build.returncode != 0, "dirty provider source was accepted")
        require("tracked modifications" in dirty_build.stderr, "dirty provider rejection was ambiguous")
        print("PASS modified provider source fails before compilation")

    print("verify-runtime-provider: 19/19 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-runtime-provider: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
