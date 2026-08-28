#!/usr/bin/env python3
"""Independent verification for the cross-module Bool policy Pi slice."""

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
REPOSITORY = PROJECT.parents[2]
ENTRY = "PolicyDecision.agda"
SOURCES = ("PolicyRules.agda", ENTRY)
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
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_tree_identity(directory):
    digest = hashlib.sha256()
    for name in SOURCES:
        digest.update(name.encode("utf-8") + b"\0")
        digest.update((directory / name).read_bytes())
    return digest.hexdigest()


def git_identity():
    result = run(["git", "rev-parse", "HEAD"])
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def parse_result(path):
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        require("=" in line, "result contains a malformed line")
        pairs.append(line.split("=", 1))
    fields = dict(pairs)
    require(len(fields) == len(pairs), "result contains duplicate fields")
    require(fields.get("schema") == "runtime-nbe-result-v1", "result schema drift")
    require(fields.get("provider") == "cctt", "provider identity missing")
    require(fields.get("provider-revision") == PROVIDER_REVISION, "provider revision drift")
    require(fields.get("type-syntax") == "Bool", "result is not an Agda Bool")
    require(fields.get("recheck") == "agda-check-internal", "Agda recheck missing")
    return fields


def parse_oracle(path, source_qname):
    pairs = []
    for line in path.read_text(encoding="utf-8").splitlines():
        require("=" in line, "oracle contains a malformed line")
        pairs.append(line.split("=", 1))
    fields = dict(pairs)
    require(len(fields) == len(pairs), "oracle contains duplicate fields")
    require(fields.get("schema") == "runtime-nbe-agda-oracle-v1", "oracle schema drift")
    require(fields.get("source-qname") == source_qname, "oracle input identity drift")
    return fields


def execute(binary, project, entry, output, path_directory):
    environment = os.environ.copy()
    environment["PATH"] = str(path_directory)
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project),
        f"--runtime-nbe-entry=PolicyDecision.{entry}",
        f"--runtime-nbe-output={output}", str(project / ENTRY),
    ], env=environment)


def execute_oracle(binary, project, entry, output):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project),
        f"--runtime-nbe-entry=PolicyDecision.{entry}",
        f"--runtime-nbe-output={output}", str(project / ENTRY),
    ])


def install_process_traps(directory, marker):
    directory.mkdir()
    script = "#!/bin/sh\nprintf invoked > '" + str(marker) + "'\nexit 97\n"
    for name in ("agda", "cabal", "ghc", "git", "stack"):
        path = directory / name
        path.write_text(script, encoding="utf-8")
        path.chmod(path.stat().st_mode | stat.S_IXUSR)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-bin", required=True)
    parser.add_argument("--oracle-bin", required=True)
    args = parser.parse_args(argv)
    binary = Path(args.runtime_bin).expanduser().resolve()
    oracle_binary = Path(args.oracle_bin).expanduser().resolve()
    require(binary.is_file(), "integrated runtime binary is missing")
    require(oracle_binary.is_file(), "independent Agda oracle binary is missing")

    print("verify-policy-rules: commit=" + git_identity())
    print("evidence: source-tree-sha256=" + source_tree_identity(PROJECT))
    print("evidence: runtime-binary-sha256=" + sha256_file(binary))
    print("evidence: provider-revision=" + PROVIDER_REVISION)

    with tempfile.TemporaryDirectory(prefix="runtime-policy-rules-") as temporary:
        temporary_path = Path(temporary)
        project = temporary_path / "project"
        project.mkdir()
        for name in SOURCES:
            shutil.copy2(PROJECT / name, project / name)
        path_traps = temporary_path / "path-traps"
        trap_marker = temporary_path / "external-tool-invoked"
        install_process_traps(path_traps, trap_marker)

        requested_path = temporary_path / "requested.result"
        requested = execute(
            binary, project, "requestedEscalation", requested_path, path_traps
        )
        require(requested.returncode == 0 and requested_path.is_file(),
                requested.stdout + requested.stderr)
        requested_result = parse_result(requested_path)
        require(requested_result["term-syntax"] == "true",
                "requested escalation was not preserved")
        print("PASS imported identity policy preserves an approved escalation")

        blocked_path = temporary_path / "blocked.result"
        blocked = execute(
            binary, project, "blockedDuringFreeze", blocked_path, path_traps
        )
        require(blocked.returncode == 0 and blocked_path.is_file(),
                blocked.stdout + blocked.stderr)
        blocked_result = parse_result(blocked_path)
        require(blocked_result["term-syntax"] == "false",
                "freeze policy did not deny escalation")
        require(requested_result["term-syntax"] != blocked_result["term-syntax"],
                "different imported definitions produced the same result")
        print("PASS imported constant-deny policy changes the rechecked decision")

        reviewed_path = temporary_path / "reviewed.result"
        reviewed = execute(
            binary, project, "reviewedEscalation", reviewed_path, path_traps
        )
        require(reviewed.returncode == 0 and reviewed_path.is_file(),
                reviewed.stdout + reviewed.stderr)
        reviewed_result = parse_result(reviewed_path)
        require(reviewed_result["term-syntax"] == "true",
                "reviewed escalation was not preserved")
        require(reviewed_result.get("runtime-input-schema") == "runtime-nbe-ir-v14",
                "recursive definition closure did not use the unified v14 typed AST")
        require(reviewed_result.get("definition-count") == "3",
                "recursive minimum definition closure is incomplete")
        print("PASS three-definition recursive closure drives the rechecked decision")

        for entry, runtime_result in (
            ("requestedEscalation", requested_result),
            ("blockedDuringFreeze", blocked_result),
            ("reviewedEscalation", reviewed_result),
        ):
            oracle_path = temporary_path / (entry + ".oracle")
            oracle = execute_oracle(oracle_binary, project, entry, oracle_path)
            require(oracle.returncode == 0 and oracle_path.is_file(),
                    oracle.stdout + oracle.stderr)
            oracle_result = parse_oracle(
                oracle_path, "PolicyDecision." + entry
            )
            require(
                oracle_result["term-syntax"] == runtime_result["term-syntax"]
                and oracle_result["type-syntax"] == runtime_result["type-syntax"],
                "runtime normal form differs from Agda oracle for " + entry,
            )
        print("PASS same-input Agda oracle matches three structured runtime normal forms")

        rules = project / "PolicyRules.agda"
        rules.write_text(
            rules.read_text(encoding="utf-8").replace(
                "preserveRequested requested = requested",
                "preserveRequested requested = false",
            ),
            encoding="utf-8",
        )
        decision = project / ENTRY
        decision.write_text(
            decision.read_text(encoding="utf-8").replace(
                "requestedExpected : requestedEscalation ≡ true\n"
                "requestedExpected _ = true",
                "requestedExpected : requestedEscalation ≡ false\n"
                "requestedExpected _ = false",
            ).replace(
                "reviewedExpected : reviewedEscalation ≡ true\n"
                "reviewedExpected _ = true",
                "reviewedExpected : reviewedEscalation ≡ false\n"
                "reviewedExpected _ = false",
            ),
            encoding="utf-8",
        )
        changed_path = temporary_path / "changed.result"
        changed = execute(
            binary, project, "requestedEscalation", changed_path, path_traps
        )
        require(changed.returncode == 0 and changed_path.is_file(),
                changed.stdout + changed.stderr)
        changed_result = parse_result(changed_path)
        require(changed_result["term-syntax"] == "false",
                "changed dependency did not drive the runtime result")
        print("PASS changing the real dependency changes the result through the same entry")

        unsupported_path = temporary_path / "unsupported.result"
        unsupported_path.write_text("stale-result\n", encoding="utf-8")
        unsupported = execute(
            binary, project, "unsupportedPatternDecision", unsupported_path, path_traps
        )
        require(unsupported.returncode != 0, "multi-clause function was accepted")
        require("supported single-clause function" in unsupported.stdout + unsupported.stderr,
                "multi-clause rejection is ambiguous")
        require(not unsupported_path.exists(), "unsupported slice left stale output")
        print("PASS unsupported multi-clause definition fails closed")

        rules.unlink()
        missing_path = temporary_path / "missing.result"
        missing = execute(
            binary, project, "requestedEscalation", missing_path, path_traps
        )
        require(missing.returncode != 0 and not missing_path.exists(),
                "missing policy module produced a result")
        print("PASS missing definition source fails before result publication")

        require(not trap_marker.exists(), "runtime invoked an external tool from PATH")
        print("PASS final process uses linked Agda/cctt without external tool invocation")

    print("verify-policy-rules: 8/8 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-policy-rules: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
