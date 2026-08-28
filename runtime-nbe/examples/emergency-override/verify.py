#!/usr/bin/env python3
"""End-to-end verification for active Bool hcomp systems."""

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
ENTRY = "EmergencyOverride.agda"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, env=None):
    return subprocess.run(command, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def fields(path):
    pairs = [line.split("=", 1) for line in path.read_text(encoding="utf-8").splitlines()]
    require(all(len(pair) == 2 for pair in pairs), "malformed result packet")
    result = dict(pairs)
    require(len(result) == len(pairs), "duplicate result field")
    return result


def rebind_digest(packet, checked, output):
    digest = hashlib.sha256(packet.read_bytes()).hexdigest()
    output.write_text(checked.read_text(encoding="utf-8").replace(
        fields(checked)["runtime-input-sha256"], digest), encoding="utf-8")
    return output


def invoke(binary, project, entry, output, environment):
    return run([
        str(binary), "--cubical", "--no-libraries", "--ignore-interfaces",
        "-i", str(project), f"--runtime-nbe-entry=EmergencyOverride.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-emergency-override-") as temporary:
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
        for entry, expected in (("allowOverride", "true"), ("denyOverride", "false")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            packet_fields = fields(packet)
            require(packet_fields["schema"] == "runtime-nbe-ir-v14",
                    "active hcomp schema drift")
            require(packet_fields["term-ast"]
                    == f"hcomp(i1,constant-system({expected}),{expected})",
                    "active tube/base reflection drift")
            require(fields(checked)["term-syntax"] == expected, "active hcomp result drift")
            require(fields(checked)["term-syntax"] == fields(oracle_result)["term-syntax"],
                    "active hcomp differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == expected,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS two active boundary decisions traverse real primHComp/cctt/recheck")
        print("PASS same-input Agda oracle matches both active systems")
        print("PASS MAlonzo final program consumes both rechecked active systems")

        stale = root / "named.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedNamedTube", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unsupported named active tube was accepted or left stale output")
        print("PASS unsupported named tube fails closed without stale output")

        packet, checked = artifacts["allowOverride"]
        conflicting = root / "conflicting.ir"
        conflicting.write_text(
            packet.read_text(encoding="utf-8").replace(
                "constant-system(true)", "constant-system(false)"),
            encoding="utf-8",
        )
        conflicting_checked = rebind_digest(
            conflicting, checked, root / "conflicting.result")
        rejected = run(
            [str(malonzo), str(conflicting), str(conflicting_checked)], env=environment)
        require(rejected.returncode != 0 and "ProviderElaborationFailed" in rejected.stderr,
                "cctt accepted an incompatible active tube/base boundary")
        print("PASS incompatible active tube/base is rejected by cctt")

        wrong_face = root / "wrong-face.ir"
        wrong_face.write_text(
            packet.read_text(encoding="utf-8").replace("hcomp(i1,", "hcomp(i0,"),
            encoding="utf-8",
        )
        face_checked = rebind_digest(wrong_face, checked, root / "wrong-face.result")
        rejected = run(
            [str(malonzo), str(wrong_face), str(face_checked)], env=environment)
        require(rejected.returncode != 0 and "does not check" in rejected.stderr,
                "active face identity tampering was accepted")
        print("PASS active face identity tampering fails closed")

        require(not marker.exists(), "runtime path invoked an external tool")
        print("PASS active hcomp runtime invokes no PATH build tool")

    print("verify-emergency-override: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-emergency-override: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
