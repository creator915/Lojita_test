#!/usr/bin/env python3
"""Verify a multi-module dependent Pi definition slice."""

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
ENTRY = "DependentRules.agda"
SOURCES = ("EvidenceModel.agda", ENTRY)


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
        "-i", str(project), f"--runtime-nbe-entry=DependentRules.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-dependent-rules-") as temporary:
        root = Path(temporary)
        project = root / "project"
        project.mkdir()
        for source in SOURCES:
            shutil.copy2(PROJECT / source, project / source)
        marker = root / "tool-invoked"
        trap_path = root / "path-traps"
        install_traps(trap_path, marker)
        environment = os.environ.copy()
        environment["PATH"] = str(trap_path)

        artifacts = {}
        for entry, decision, evidence_kind in (
                ("approvedRequest", "true", "approved"),
                ("rejectedRequest", "false", "rejected")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["def3-type-ast"]
                    == "pi(bool,pi(app(def(0),var(0)),bool))"
                    and f",{decision}),{evidence_kind})" in reflected["term-ast"],
                    "dependent Pi reflection drift")
            require(fields(checked)["term-syntax"] == decision
                    and fields(oracle_result)["term-syntax"] == decision,
                    "dependent Pi runtime differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == decision,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS one dependent Pi function evaluates opposite evidence-indexed requests")
        print("PASS same-input Agda oracle matches both dependent calls")
        print("PASS MAlonzo consumes both rechecked dependent Pi results")

        stale = root / "unsupported.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedConstantRule", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unsupported dependent function body was accepted or left stale output")
        print("PASS unsupported dependent function body fails closed")

        packet, checked = artifacts["approvedRequest"]
        mismatched = root / "mismatched.ir"
        mismatched.write_text(packet.read_text(encoding="utf-8").replace(
            ",true),approved))", ",true),rejected))"),
            encoding="utf-8")
        mismatch_checked = rebind_digest(mismatched, checked, root / "mismatched.result")
        rejected = run([str(malonzo), str(mismatched), str(mismatch_checked)], env=environment)
        require(rejected.returncode != 0 and "indices do not correspond" in rejected.stderr,
                "mismatched dependent call indices were accepted")
        print("PASS dependent function call index mismatch fails closed")

        changed_body = root / "changed-body.ir"
        changed_body.write_text(packet.read_text(encoding="utf-8").replace(
            "def3-body-ast=case-evidence(true,false)",
            "def3-body-ast=case-evidence(false,false)"), encoding="utf-8")
        changed_checked = rebind_digest(changed_body, checked, root / "changed-body.result")
        rejected = run([str(malonzo), str(changed_body), str(changed_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "changed dependent function body escaped rechecked-result binding")
        print("PASS dependent function body is bound to its rechecked result")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS dependent Pi runtime invokes no PATH build tool")

    print("verify-dependent-rules: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-dependent-rules: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
