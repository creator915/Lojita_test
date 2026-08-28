#!/usr/bin/env python3
"""Verify a Bool-indexed evidence family inside a dependent Sigma result."""

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
ENTRY = "DependentApproval.agda"


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
        "-i", str(project), f"--runtime-nbe-entry=DependentApproval.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-dependent-approval-") as temporary:
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
        cases = (
            ("approvedResult", "true", "approved", "approvedEvidence"),
            ("rejectedResult", "false", "rejected", "rejectedEvidence"),
        )
        for entry, decision, evidence_kind, constructor in cases:
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            checked_fields = fields(checked)
            oracle_fields = fields(oracle_result)
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["type-ast"]
                    == "sigma(bool,app(def(0),var(0)))"
                    and reflected["def0-body-ast"]
                    == "evidence-family(def(1),def(2))"
                    and reflected["term-ast"]
                    == f"hcomp(i0,empty,pair({decision},{evidence_kind}))",
                    "dependent evidence reflection drift")
            require(checked_fields["term-syntax"] == f"{decision} , {constructor}"
                    and checked_fields["type-syntax"] == "Σ Bool DecisionEvidence",
                    "dependent rechecked Term+Type drift")
            require(oracle_fields["type-syntax"] == checked_fields["type-syntax"]
                    and oracle_fields["term-syntax"].startswith(decision + " , ")
                    and constructor in oracle_fields["term-syntax"],
                    "Agda oracle disagrees on decision, evidence constructor, or index type")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0
                    and f"pair {decision} ({evidence_kind} " in executed.stdout,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS opposite decisions carry differently indexed evidence through cctt/recheck")
        print("PASS Agda oracle agrees on decision, evidence constructor and dependent type")
        print("PASS MAlonzo consumes both indexed evidence results")

        stale = root / "unsupported.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedFamily", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unsupported indexed family was accepted or left stale output")
        print("PASS unsupported indexed evidence family fails closed")

        packet, checked = artifacts["approvedResult"]
        mismatched = root / "mismatched.ir"
        mismatched.write_text(packet.read_text(encoding="utf-8").replace(
            "pair(true,approved)", "pair(true,rejected)"), encoding="utf-8")
        mismatch_checked = rebind_digest(mismatched, checked, root / "mismatched.result")
        rejected = run([str(malonzo), str(mismatched), str(mismatch_checked)], env=environment)
        require(rejected.returncode != 0
                and "indices do not correspond" in rejected.stderr,
                "decision/evidence index mismatch was accepted")
        print("PASS decision/evidence index mismatch fails closed")

        wrong_constructor = root / "wrong-constructor.ir"
        wrong_constructor.write_text(packet.read_text(encoding="utf-8").replace(
            "approvedEvidence", "forgedEvidence"), encoding="utf-8")
        constructor_checked = rebind_digest(
            wrong_constructor, checked, root / "wrong-constructor.result")
        rejected = run(
            [str(malonzo), str(wrong_constructor), str(constructor_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "evidence constructor identity tampering was accepted")
        print("PASS evidence constructor identity is bound to the rechecked result")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS dependent evidence runtime invokes no PATH build tool")

    print("verify-dependent-approval: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-dependent-approval: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
