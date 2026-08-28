#!/usr/bin/env python3
"""End-to-end verification for structured Bool Sigma approval evidence."""

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
ENTRY = "ApprovalEvidence.agda"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, env=None):
    return subprocess.run(
        command, text=True, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )


def fields(path):
    pairs = [line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines()]
    require(all(len(pair) == 2 for pair in pairs), "packet contains a malformed line")
    result = dict(pairs)
    require(len(result) == len(pairs), "packet contains duplicate fields")
    return result


def rebind_digest(packet, checked, output):
    digest = hashlib.sha256(packet.read_bytes()).hexdigest()
    output.write_text(checked.read_text(encoding="utf-8").replace(
        fields(checked)["runtime-input-sha256"], digest), encoding="utf-8")
    return output


def invoke(binary, project, entry, output, environment):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project), f"--runtime-nbe-entry=ApprovalEvidence.{entry}",
        f"--runtime-nbe-output={output}", str(project / ENTRY),
    ], env=environment)


def traps(directory, marker):
    directory.mkdir()
    script = "#!/bin/sh\nprintf invoked > '" + str(marker) + "'\nexit 97\n"
    for name in ("agda", "cabal", "ghc", "git", "stack"):
        target = directory / name
        target.write_text(script, encoding="utf-8")
        target.chmod(target.stat().st_mode | stat.S_IXUSR)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--producer-bin", required=True)
    parser.add_argument("--runtime-bin", required=True)
    parser.add_argument("--oracle-bin", required=True)
    parser.add_argument("--malonzo-bin", required=True)
    args = parser.parse_args(argv)
    binaries = [Path(value).expanduser().resolve() for value in (
        args.producer_bin, args.runtime_bin, args.oracle_bin, args.malonzo_bin
    )]
    require(all(path.is_file() for path in binaries), "a required binary is missing")
    producer, runtime, oracle, malonzo = binaries

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-approval-evidence-") as temporary:
        root = Path(temporary)
        project = root / "project"
        project.mkdir()
        shutil.copy2(PROJECT / ENTRY, project / ENTRY)
        marker = root / "tool-invoked"
        path_traps = root / "path-traps"
        traps(path_traps, marker)
        environment = os.environ.copy()
        environment["PATH"] = str(path_traps)

        artifacts = {}
        for entry, expected in (
            ("approvedWithEvidence", "true , true"),
            ("rejectedWithEvidence", "false , false"),
        ):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in (
                (producer, packet), (runtime, checked), (oracle, oracle_result)
            ):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            packet_fields = fields(packet)
            checked_fields = fields(checked)
            oracle_fields = fields(oracle_result)
            require(packet_fields["schema"] == "runtime-nbe-ir-v14"
                    and packet_fields["type-ast"] == "sigma(bool,bool)"
                    and packet_fields["term-ast"].startswith("hcomp(i0,empty,pair("),
                    "Sigma input did not use the unified typed AST")
            require(checked_fields["term-syntax"] == expected,
                    "rechecked Sigma result differs from expected structure")
            require(
                checked_fields["term-syntax"] == oracle_fields["term-syntax"]
                and checked_fields["type-syntax"] == oracle_fields["type-syntax"],
                "same-input Sigma runtime result differs from Agda oracle",
            )
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS opposite structured approvals traverse Agda/cctt/recheck")
        print("PASS same-input Agda oracle matches both Sigma Term+Type results")
        print("PASS MAlonzo final program consumes both rechecked Sigma results")

        packet, checked = artifacts["approvedWithEvidence"]
        tampered = root / "tampered.result"
        tampered.write_text(
            checked.read_text(encoding="utf-8").replace(
                "term-syntax=true , true", "term-syntax=true , false"
            ), encoding="utf-8",
        )
        rejected = run([str(malonzo), str(packet), str(tampered)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "tampered evidence pair was accepted")
        print("PASS decision/evidence result tampering fails closed")

        malformed = root / "malformed.ir"
        malformed.write_text(
            packet.read_text(encoding="utf-8").replace(
                "term-ast=hcomp(i0,empty,pair(true,true))\n", ""),
            encoding="utf-8",
        )
        malformed_checked = rebind_digest(
            malformed, checked, root / "malformed.result")
        rejected = run(
            [str(malonzo), str(malformed), str(malformed_checked)], env=environment)
        require(rejected.returncode != 0 and "field set" in rejected.stderr,
                "Sigma packet with a missing field was accepted")
        print("PASS missing structured field fails closed")

        bad_source = project / ENTRY
        bad_source.write_text(
            bad_source.read_text(encoding="utf-8").replace(
                "Σ Bool (λ _ → Bool)", "Σ Bool (λ _ → Bool → Bool)"
            ), encoding="utf-8",
        )
        stale = root / "stale.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "approvedWithEvidence", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "malformed Sigma source left a stale result")
        print("PASS unsupported Sigma shape rejects without stale output")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS structured runtime path invokes no PATH build tool")

    print("verify-approval-evidence: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-approval-evidence: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
