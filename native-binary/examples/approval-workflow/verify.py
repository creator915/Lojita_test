#!/usr/bin/env python3
"""Independent acceptance test for the formal approval-workflow binary."""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT = Path(__file__).resolve().parent
SOURCE_ROOT = PROJECT / "src"
ENTRY = SOURCE_ROOT / "ApprovalMain.agda"
BUILD = PROJECT.parent.parent / "build.py"


EXPECTED = {
    "small": """scenario=small
request=REQ-100
requester=alice
amount=750
category=travel
result=ok:approved
status=approved
events=submit:alice:draft->submitted,manager-approve:bob:submitted->approved""",
    "medium": """scenario=medium
request=REQ-200
requester=alice
amount=3200
category=equipment
result=ok:approved
status=approved
events=submit:alice:draft->submitted,manager-approve:bob:submitted->manager-approved,finance-approve:carol:manager-approved->approved""",
    "large": """scenario=large
request=REQ-300
requester=alice
amount=8000
category=customer-event
result=ok:approved
status=approved
events=submit:alice:draft->submitted,manager-approve:bob:submitted->manager-approved,finance-approve:carol:manager-approved->finance-approved,director-approve:diana:finance-approved->approved""",
    "reject": """scenario=reject
request=REQ-200
requester=alice
amount=3200
category=equipment
result=ok:rejected
status=rejected
events=submit:alice:draft->submitted,reject:bob:submitted->rejected""",
    "unauthorized": """scenario=unauthorized
request=REQ-200
requester=alice
amount=3200
category=equipment
result=error:permission-denied
status=submitted
events=submit:alice:draft->submitted""",
    "self-approval": """scenario=self-approval
request=REQ-200
requester=alice
amount=3200
category=equipment
result=error:self-approval
status=submitted
events=submit:alice:draft->submitted""",
    "invalid-order": """scenario=invalid-order
request=REQ-200
requester=alice
amount=3200
category=equipment
result=error:invalid-transition
status=submitted
events=submit:alice:draft->submitted""",
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def git_identity():
    result = subprocess.run(
        ["git", "-C", str(PROJECT.parent.parent.parent), "rev-parse", "HEAD"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def build(output):
    result = subprocess.run(
        [
            sys.executable, str(BUILD), "--project-root", str(SOURCE_ROOT),
            "--source", str(ENTRY), "--profile", "ordinary",
            "--binary-name", "approval-workflow", "--output", str(output),
        ],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    require(result.returncode == 0, result.stdout)


def verify(artifact):
    provenance_path = artifact / "provenance.json"
    require(provenance_path.is_file(), "provenance.json is missing")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    binary = artifact / provenance["binary"]["path"]
    require(binary.is_file(), "approval binary is missing")
    require(digest(binary) == provenance["binary"]["sha256"], "binary hash mismatch")

    sources = sorted(SOURCE_ROOT.rglob("*.agda"))
    actual_manifest = {
        path.relative_to(SOURCE_ROOT).as_posix(): digest(path) for path in sources
    }
    require(provenance["source"]["files"] == actual_manifest, "source manifest mismatch")
    require(len(actual_manifest) == 8, "expected eight Agda source modules")
    print("PASS artifact binds all eight Agda source modules")

    audit = json.loads((artifact / provenance["audit"]).read_text(encoding="utf-8"))
    require(audit["project_source_count"] == 8, "audit source count mismatch")
    require(audit["generated_haskell_count"] >= 8, "MAlonzo output is incomplete")
    require(audit["forbidden_matches"] == [], "compiler/runtime marker entered output")
    require((artifact / audit["symbol_audit"]).stat().st_size > 0, "symbol audit is empty")
    require((artifact / audit["dependency_audit"]).stat().st_size > 0, "dependency audit is empty")
    proof_haskell = artifact / "generated" / "MAlonzo" / "Code" / "Approval" / "Proofs.hs"
    require(proof_haskell.is_file(), "generated proof module is missing")
    require(
        proof_haskell.read_text(encoding="utf-8").count("= erased") >= 6,
        "compile-time approval proofs survived runtime erasure",
    )
    print("PASS MAlonzo, symbol and dynamic dependency audits are present")

    for scenario, expected in EXPECTED.items():
        result = subprocess.run(
            [str(binary), scenario], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        require(result.returncode == 0, f"{scenario} failed: {result.stderr}")
        require(result.stdout.strip() == expected, f"{scenario} report mismatch")
        require(not result.stderr, f"{scenario} wrote unexpected stderr")
        print("PASS scenario " + scenario)

    unknown = subprocess.run(
        [str(binary), "not-a-command"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    require(unknown.returncode != 0, "unknown command succeeded")
    require(not unknown.stdout, "unknown command wrote stdout")
    require("usage: approval-workflow" in unknown.stderr, "usage contract is missing")
    print("PASS unknown command fails closed")
    print("verify-approval-workflow: 10/10 PASS")


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifact")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    print("verify-approval-workflow: commit=" + git_identity())
    print("verify-approval-workflow: python=" + sys.version.splitlines()[0])
    if args.artifact:
        verify(Path(args.artifact).expanduser().resolve())
    else:
        with tempfile.TemporaryDirectory(prefix="approval-workflow-verify-") as temporary:
            artifact = Path(temporary) / "artifact"
            build(artifact)
            verify(artifact)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-approval-workflow: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
