#!/usr/bin/env python3
"""Run every declared runtime-NbE semantic slice through one evidence entry."""

import argparse
import hashlib
import json
import os
import subprocess
import sys
from pathlib import Path

from agda_data import AgdaDataFailure, verify_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
SCENARIOS = (
    "policy-rules",
    "approval-evidence",
    "dependent-approval",
    "dependent-rules",
    "state-migration",
    "emergency-override",
    "glue-migration",
    "glue-family-migration",
    "audit-loop",
    "policy-representation-upgrade",
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def run(command, env=None):
    return subprocess.run(command, cwd=REPOSITORY, env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_sha256(directory):
    digest = hashlib.sha256()
    for path in sorted(item for item in directory.rglob("*") if item.is_file()):
        relative = path.relative_to(directory).as_posix()
        digest.update(relative.encode("utf-8") + b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser()
    for option in ("producer-bin", "runtime-bin", "oracle-bin", "malonzo-bin"):
        parser.add_argument("--" + option, required=True)
    parser.add_argument("--integrated-output")
    parser.add_argument("--malonzo-output")
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    args = parser.parse_args(argv)
    binaries = {
        name: Path(getattr(args, name.replace("-", "_"))).expanduser().resolve()
        for name in ("producer-bin", "runtime-bin", "oracle-bin", "malonzo-bin")
    }
    require(all(path.is_file() for path in binaries.values()),
            "a required matrix binary is missing")
    require(args.integrated_output, "provide the integrated output")
    agda_data_dir = Path(args.integrated_output).expanduser().resolve() / "agda-data"
    require(
        (agda_data_dir / "lib" / "prim" / "_build" / "2.8.0" / "agda"
         / "Agda" / "Primitive.agdai").is_file(),
        "integrated cold Agda primitive interfaces are missing",
    )
    matrix_environment = os.environ.copy()
    matrix_environment["Agda_datadir"] = str(agda_data_dir)

    commit = run(["git", "rev-parse", "HEAD"])
    require(commit.returncode == 0, "repository commit identity is unavailable")
    status = run(["git", "status", "--porcelain", "--untracked-files=all"])
    require(status.returncode == 0, "repository status is unavailable")
    identity = commit.stdout.strip() + ("+DIRTY" if status.stdout else "")
    print("verify-runtime-nbe-matrix: commit=" + identity)
    for name, path in binaries.items():
        print(f"evidence: {name}={path}")
        print(f"evidence: {name}-sha256={sha256(path)}")

    if args.integrated_output:
        provenance = Path(args.integrated_output).expanduser().resolve() / "provenance.json"
        require(provenance.is_file(), "integrated provenance is missing")
        identity = json.loads(provenance.read_text(encoding="utf-8"))
        try:
            verify_agda_data(agda_data_dir, identity["agda_data"])
        except AgdaDataFailure as error:
            require(False, str(error))
        print("evidence: integrated-ghc=" + identity["tools"]["ghc"])
        print("evidence: agda-revision=" + identity["agda"]["revision"])
        print("evidence: provider-revision=" + identity["provider"]["revision"])
    if args.malonzo_output:
        provenance = Path(args.malonzo_output).expanduser().resolve() / "provenance.json"
        require(provenance.is_file(), "MAlonzo provenance is missing")
        identity = json.loads(provenance.read_text(encoding="utf-8"))
        print("evidence: malonzo-ghc=" + identity["tools"]["ghc"])

    options = []
    for name, path in binaries.items():
        options.extend(["--" + name, str(path)])
    for scenario in SCENARIOS:
        verifier = ROOT / "examples" / scenario / "verify.py"
        require(verifier.is_file(), "matrix verifier missing: " + scenario)
        print("evidence: scenario=" + scenario
              + " source-tree-sha256=" + tree_sha256(verifier.parent))
        scenario_options = options
        if scenario == "policy-rules":
            scenario_options = [
                "--runtime-bin", str(binaries["runtime-bin"]),
                "--oracle-bin", str(binaries["oracle-bin"]),
            ]
        result = run(
            [sys.executable, "-B", str(verifier), *scenario_options],
            env=matrix_environment,
        )
        if result.stdout:
            print(result.stdout, end="")
        require(result.returncode == 0,
                f"scenario {scenario} failed\n{result.stdout}{result.stderr}")
        print("MATRIX-PASS scenario=" + scenario + " exit=0")

    print(f"verify-runtime-nbe-matrix: {len(SCENARIOS)}/{len(SCENARIOS)} PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-runtime-nbe-matrix: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
