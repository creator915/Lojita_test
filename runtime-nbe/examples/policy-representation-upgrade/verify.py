#!/usr/bin/env python3
"""Verify a real polarity-changing policy representation upgrade through Glue."""

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
ENTRY = "PolicyRepresentationUpgrade.agda"
SOURCES = (ENTRY, "PolicyEquivalence.agda")


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
        "-i", str(project),
        f"--runtime-nbe-entry=PolicyRepresentationUpgrade.{entry}",
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

    with tempfile.TemporaryDirectory(prefix="runtime-nbe-policy-upgrade-") as temporary:
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
        for entry, old_value, expected in (
                ("upgradeApproved", "true", "false"),
                ("upgradeRejected", "false", "true")):
            packet = root / (entry + ".ir")
            checked = root / (entry + ".result")
            oracle_result = root / (entry + ".oracle")
            for binary, output in ((producer, packet), (runtime, checked), (oracle, oracle_result)):
                result = invoke(binary, project, entry, output, environment)
                require(result.returncode == 0 and output.is_file(),
                        result.stdout + result.stderr)
            reflected = fields(packet)
            require(reflected["schema"] == "runtime-nbe-ir-v14"
                    and reflected["term-ast"] ==
                    f"transp(glue-family(negation,def(0),def(1)),i0,{old_value})"
                    and reflected["def0-body-ast"] == "negation-equiv(def(1))"
                    and reflected["def1-body-ast"] == "bool-not",
                    "nontrivial Glue packet identity drift")
            require(fields(checked)["term-syntax"] == expected,
                    "polarity upgrade result drift")
            require(fields(oracle_result)["term-syntax"] == expected,
                    "runtime upgrade differs from same-input Agda oracle")
            executed = run([str(malonzo), str(packet), str(checked)], env=environment)
            require(executed.returncode == 0 and executed.stdout.strip() == expected,
                    executed.stdout + executed.stderr)
            artifacts[entry] = (packet, checked)
        print("PASS old approved/rejected bits flip through a checked non-identity Glue equivalence")
        print("PASS same-input Agda oracle matches both representation upgrades")
        print("PASS MAlonzo final program consumes both rechecked upgraded decisions")

        stale = root / "unsupported.result"
        stale.write_text("stale\n", encoding="utf-8")
        rejected = invoke(runtime, project, "unsupportedIdentityUpgrade", stale, environment)
        require(rejected.returncode != 0 and not stale.exists(),
                "different Glue equivalence was mislabeled or left stale output")
        print("PASS different equivalence fails closed without stale output")

        packet, checked = artifacts["upgradeApproved"]
        wrong_table = root / "wrong-table.ir"
        wrong_table.write_text(packet.read_text(encoding="utf-8").replace(
            "def1-body-ast=bool-not", "def1-body-ast=var(0)"),
            encoding="utf-8")
        table_checked = rebind_digest(wrong_table, checked, root / "wrong-table.result")
        rejected = run([str(malonzo), str(wrong_table), str(table_checked)], env=environment)
        require(rejected.returncode != 0
                and "negation Glue definition closure" in rejected.stderr,
                "forged equivalence table was accepted")
        print("PASS forged equivalence truth table fails closed")

        opposite = root / "opposite.ir"
        opposite.write_text(packet.read_text(encoding="utf-8").replace(
            ",i0,true)", ",i0,false)"), encoding="utf-8")
        opposite_checked = rebind_digest(opposite, checked, root / "opposite.result")
        rejected = run([str(malonzo), str(opposite), str(opposite_checked)], env=environment)
        require(rejected.returncode != 0 and "term-syntax identity mismatch" in rejected.stderr,
                "opposite old representation was accepted against checked output")
        print("PASS upgraded result remains bound to exact old representation bytes")

        require(not marker.exists(), "runtime path invoked an external build tool")
        print("PASS policy representation runtime invokes no PATH build tool")

    print("verify-policy-representation-upgrade: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-policy-representation-upgrade: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
