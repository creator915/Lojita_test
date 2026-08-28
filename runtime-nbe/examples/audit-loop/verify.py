#!/usr/bin/env python3
"""End-to-end verification for the declared interval HIT slice."""

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
ENTRY = "AuditLoop.agda"


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
    previous = fields(checked)["runtime-input-sha256"]
    output.write_text(
        checked.read_text(encoding="utf-8").replace(previous, digest),
        encoding="utf-8",
    )
    return output


def alpha_canonical(term):
    return term.replace("(λ i → isOneEmpty)", "(λ _ → isOneEmpty)")


def invoke(binary, project, entry, output, environment):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project), f"--runtime-nbe-entry=AuditLoop.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-audit-loop-") as temporary:
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
        for entry, base_kind in (
                ("resumeFromCycleStart", "path-i0"),
                ("resumeFromCycleEnd", "path-i1")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            endpoint = "i0" if base_kind == "path-i0" else "i1"
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["type-ast"] == "def(0)"
                    and reflected["def0-body-ast"]
                    == "interval-hit-type(def(1),def(2),def(3))"
                    and reflected["term-ast"]
                    == f"hcomp(i0,empty,iapply(hit-path,{endpoint}))",
                    "HIT path endpoint reflection drift")
            checked_fields = fields(checked)
            oracle_fields = fields(oracle_result)
            require(checked_fields["type-syntax"] == "AuditTrace"
                    and oracle_fields["type-syntax"] == "AuditTrace",
                    "HIT result type drift")
            require(alpha_canonical(checked_fields["term-syntax"])
                    == alpha_canonical(oracle_fields["term-syntax"]),
                    "HIT runtime differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            expected_provider = (
                "hcom 0 1 [] runtimeLeft" if base_kind == "path-i0"
                else "hcom 0 1 [] runtimeRight"
            )
            require(executed.returncode == 0
                    and executed.stdout.strip() == expected_provider,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        require(fields(artifacts["resumeFromCycleStart"][0])["term-ast"]
                != fields(artifacts["resumeFromCycleEnd"][0])["term-ast"],
                "opposite path endpoints produced identical packets")
        require(alpha_canonical(fields(artifacts["resumeFromCycleStart"][1])["term-syntax"])
                != alpha_canonical(fields(artifacts["resumeFromCycleEnd"][1])["term-syntax"]),
                "opposite HIT endpoints did not produce observable distinct results")
        print("PASS both path endpoints traverse a real Agda interval HIT and cctt")
        print("PASS same-input Agda oracle is alpha-equivalent at original HIT type")
        print("PASS MAlonzo final program consumes both rechecked HIT results")

        active_artifacts = {}
        for entry, orientation, expected_term, expected_provider in (
                ("closeThroughActiveTube", "forward", "auditClosed", "runtimeRight"),
                ("reopenThroughActiveTube", "reverse", "auditOpened", "runtimeLeft")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["type-ast"] == "def(0)"
                    and reflected["def0-body-ast"]
                    == "interval-hit-type(def(1),def(2),def(3))"
                    and reflected["term-ast"].startswith(
                        f"hcomp(i1,hit-path-system({orientation}),"),
                    "active HIT tube reflection drift")
            require(fields(checked)["term-syntax"] == expected_term
                    and fields(oracle_result)["term-syntax"] == expected_term,
                    "active HIT runtime differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0
                    and executed.stdout.strip() == expected_provider,
                    executed.stdout + executed.stderr)
            active_artifacts[entry] = (packet, checked)
        print("PASS forward/reverse higher-dimensional active tubes reach opposite HIT points")
        print("PASS active HIT results match Agda oracle and final MAlonzo consumption")

        stale = root / "unsupported.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedMultiPoint", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unary-loop HIT was accepted or left stale output")
        print("PASS unary-loop HIT outside the declared shape fails closed")

        packet, checked = artifacts["resumeFromCycleStart"]
        wrong_boundary = root / "wrong-boundary.ir"
        wrong_boundary.write_text(
            packet.read_text(encoding="utf-8").replace(
                "iapply(hit-path,i0)", "iapply(guessed-path,i0)"),
            encoding="utf-8",
        )
        boundary_checked = rebind_digest(
            wrong_boundary, checked, root / "wrong-boundary.result")
        rejected = run(
            [str(malonzo), str(wrong_boundary), str(boundary_checked)], env=environment)
        require(rejected.returncode != 0 and "point/path grammar" in rejected.stderr,
                "HIT path-boundary tampering was accepted")
        print("PASS HIT path-boundary identity tampering fails closed")

        wrong_point = root / "wrong-point.ir"
        wrong_point.write_text(
            packet.read_text(encoding="utf-8").replace("auditOpened", "otherOpened"),
            encoding="utf-8",
        )
        point_checked = rebind_digest(wrong_point, checked, root / "wrong-point.result")
        rejected = run([str(malonzo), str(wrong_point), str(point_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "HIT point identity tampering was accepted")
        print("PASS HIT point identity is bound to the rechecked result")

        active_packet, active_checked = active_artifacts["closeThroughActiveTube"]
        wrong_orientation = root / "wrong-orientation.ir"
        wrong_orientation.write_text(
            active_packet.read_text(encoding="utf-8").replace(
                "hit-path-system(forward)", "hit-path-system(sideways)"),
            encoding="utf-8",
        )
        orientation_checked = rebind_digest(
            wrong_orientation, active_checked, root / "wrong-orientation.result")
        rejected = run(
            [str(malonzo), str(wrong_orientation), str(orientation_checked)],
            env=environment)
        require(rejected.returncode != 0
                and "tube orientation is malformed" in rejected.stderr,
                "active HIT tube-orientation tampering was accepted")
        print("PASS active HIT tube orientation tampering fails closed")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS HIT runtime invokes no PATH build tool")

    print("verify-audit-loop: 10/10 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-audit-loop: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
