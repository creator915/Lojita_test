#!/usr/bin/env python3
"""End-to-end verification for transport through an active Glue family."""

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
ENTRY = "GlueFamilyMigration.agda"
EQUIVALENCE = "Agda.Builtin.Cubical.Equiv._.pathToEquiv"


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
        "-i", str(project), f"--runtime-nbe-entry=GlueFamilyMigration.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-glue-family-") as temporary:
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
        for entry, expected in (("migrateApproved", "true"), ("migrateRejected", "false")):
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
                        "transp(glue-family(identity,def(0)),i0,")
                    and reflected["def0-qname"] == EQUIVALENCE,
                    "active Glue-family transport identity drift")
            require(fields(checked)["term-syntax"] == expected,
                    "Glue-family transport result drift")
            require(fields(checked)["term-syntax"] == fields(oracle_result)["term-syntax"],
                    "Glue-family result differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == expected,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS opposite records transport through a real active Glue family")
        print("PASS same-input Agda oracle matches both Glue-family results")
        print("PASS MAlonzo final program consumes both rechecked migrations")

        stale = root / "unsupported.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedNamedFamily", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "unsupported named family was accepted or left stale output")
        print("PASS unsupported named family fails closed without stale output")

        packet, checked = artifacts["migrateApproved"]
        wrong_equivalence = root / "wrong-equivalence.ir"
        wrong_equivalence.write_text(packet.read_text(encoding="utf-8").replace(
            "def0-qname=" + EQUIVALENCE,
            "def0-qname=Application.Policy.claimedEquivalence"), encoding="utf-8")
        wrong_checked = rebind_digest(
            wrong_equivalence, checked, root / "wrong-equivalence.result")
        rejected = run([str(malonzo), str(wrong_equivalence), str(wrong_checked)],
                       env=environment)
        require(rejected.returncode != 0
                and "equivalence declaration closure" in rejected.stderr,
                "forged Glue equivalence identity was accepted")
        print("PASS forged Glue equivalence identity fails closed")

        opposite = root / "opposite.ir"
        opposite.write_text(packet.read_text(encoding="utf-8").replace(
            ",i0,true)", ",i0,false)"), encoding="utf-8")
        opposite_checked = rebind_digest(opposite, checked, root / "opposite.result")
        rejected = run([str(malonzo), str(opposite), str(opposite_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "opposite transport value was accepted against checked result")
        print("PASS checked result is bound to the exact transported value")

        require(not marker.exists(), "runtime path invoked an external build tool")
        print("PASS Glue-family runtime invokes no PATH build tool")

    print("verify-glue-family-migration: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-glue-family-migration: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
