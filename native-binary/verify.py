#!/usr/bin/env python3
"""Independent real-tool verification for the native-binary MVP."""

import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parent
BUILD = ROOT / "build.py"
FIXTURES = ROOT / "fixtures"
APPROVAL_ROOT = ROOT / "examples" / "approval-workflow" / "src"
APPROVAL_ENTRY = APPROVAL_ROOT / "ApprovalMain.agda"
APPROVAL_VERIFY = ROOT / "examples" / "approval-workflow" / "verify.py"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(source, profile, output, *extra):
    command = [
        sys.executable, str(BUILD), "--source", str(source),
        "--profile", profile, "--output", str(output), *extra,
    ]
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def binary_path(output):
    provenance = json.loads((output / "provenance.json").read_text(encoding="utf-8"))
    return output / provenance["binary"]["path"]


def run_binary(output, expected, *arguments):
    provenance = json.loads((output / "provenance.json").read_text(encoding="utf-8"))
    binary = binary_path(output)
    result = subprocess.run(
        [str(binary), *arguments], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    require(result.returncode == 0, "generated binary failed")
    require(result.stdout.strip() == expected, "generated binary returned unexpected output")
    require(provenance["binary"]["sha256"] == digest(binary), "binary digest mismatch")
    require("--ghc-dont-call-ghc" in provenance["commands"]["agda"], "Agda invoked GHC")
    require(provenance["commands"]["ghc"][0] == provenance["tools"]["ghc"]["path"], "GHC evidence mismatch")
    audit = json.loads((output / provenance["audit"]).read_text(encoding="utf-8"))
    require(audit["generated_haskell_count"] > 0, "no generated Haskell audited")
    require(audit["malonzo_erasure_markers"]["AgdaAny"] > 0, "no erasure marker")
    require(audit["forbidden_matches"] == [], "forbidden runtime marker present")
    require((output / audit["symbol_audit"]).stat().st_size > 0, "empty symbol audit")
    require((output / audit["dependency_audit"]).stat().st_size > 0, "empty dependency audit")
    return provenance


def expect_failure(source, profile, output, code, marker):
    result = invoke(source, profile, output)
    require(result.returncode == code, f"expected exit {code}, got {result.returncode}\n{result.stdout}")
    require(marker in result.stdout, f"missing stable failure marker {marker}")
    require(not output.exists(), "failed build published output")
    require(not list(output.parent.glob("." + output.name + ".staging-*")), "failed build left staging")


def git_identity():
    result = subprocess.run(
        ["git", "-C", str(ROOT.parent), "rev-parse", "HEAD"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def main():
    before = {path.name: digest(path) for path in FIXTURES.glob("*.agda")}
    before_names = sorted(path.name for path in FIXTURES.iterdir())
    approval_before = {
        str(path.relative_to(APPROVAL_ROOT)): digest(path)
        for path in APPROVAL_ROOT.rglob("*.agda")
    }
    print("verify-native-binary: commit=" + git_identity())
    print("verify-native-binary: python=" + sys.version.splitlines()[0])

    with tempfile.TemporaryDirectory(prefix="native-binary-verify-") as temporary:
        root = Path(temporary)

        ordinary = root / "ordinary"
        result = invoke(FIXTURES / "OrdinaryMain.agda", "ordinary", ordinary)
        require(result.returncode == 0, result.stdout)
        ordinary_evidence = run_binary(ordinary, "ordinary-ok")
        require(
            ordinary_evidence["source"]["sha256"] == digest(FIXTURES / "OrdinaryMain.agda"),
            "ordinary source identity mismatch",
        )
        print("evidence: source-sha256=" + ordinary_evidence["source"]["sha256"])
        print("evidence: agda=" + ordinary_evidence["tools"]["agda"]["version"].splitlines()[0])
        print("evidence: agda-sha256=" + ordinary_evidence["tools"]["agda"]["sha256"])
        print("evidence: ghc=" + ordinary_evidence["tools"]["ghc"]["version"].splitlines()[0])
        print("evidence: ghc-sha256=" + ordinary_evidence["tools"]["ghc"]["sha256"])
        print("evidence: dependency-audit=" + ordinary_evidence["tools"]["dependency_audit"]["style"])
        print("PASS ordinary Stock Agda -> MAlonzo -> GHC -> binary")

        approval = root / "approval-workflow"
        result = invoke(
            APPROVAL_ENTRY, "ordinary", approval,
            "--project-root", str(APPROVAL_ROOT),
            "--binary-name", "approval-workflow",
        )
        require(result.returncode == 0, result.stdout)
        approval_provenance = json.loads(
            (approval / "provenance.json").read_text(encoding="utf-8")
        )
        approval_audit = json.loads(
            (approval / approval_provenance["audit"]).read_text(encoding="utf-8")
        )
        require(approval_audit["project_source_count"] == 8, "approval source count mismatch")
        require(len(approval_provenance["source"]["files"]) == 8, "project manifest incomplete")
        require(
            approval_provenance["source"]["files"] == approval_before,
            "approval project source hashes are not bound",
        )
        generated_names = set(approval_audit["generated_haskell"])
        required_generated = {
            "MAlonzo/Code/Approval/Domain.hs",
            "MAlonzo/Code/Approval/Engine.hs",
            "MAlonzo/Code/Approval/Policy.hs",
            "MAlonzo/Code/Approval/Proofs.hs",
            "MAlonzo/Code/Approval/Render.hs",
            "MAlonzo/Code/Approval/Scenarios.hs",
            "MAlonzo/Code/Approval/Util.hs",
            "MAlonzo/Code/ApprovalMain.hs",
        }
        require(required_generated <= generated_names, "business modules missing from MAlonzo output")
        require(not list(APPROVAL_ROOT.rglob("*.hs")), "project contains pre-generated Haskell")
        project_verification = subprocess.run(
            [sys.executable, str(APPROVAL_VERIFY), "--artifact", str(approval)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        require(project_verification.returncode == 0, project_verification.stdout)
        require("verify-approval-workflow: 10/10 PASS" in project_verification.stdout, "project verifier did not complete")
        print("evidence: approval-tree-sha256=" + approval_provenance["source"]["tree_sha256"])
        print("PASS formal eight-module approval project compiles through the real native lane")

        expected_reports = {
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
        }
        for scenario, expected in expected_reports.items():
            run_binary(approval, expected, scenario)
        print("PASS manager, finance and director approval tiers produce exact audited reports")

        run_binary(
            approval,
            """scenario=reject
request=REQ-200
requester=alice
amount=3200
category=equipment
result=ok:rejected
status=rejected
events=submit:alice:draft->submitted,reject:bob:submitted->rejected""",
            "reject",
        )
        print("PASS normal business rejection reaches a final rejected state")

        negative_reports = {
            "unauthorized": "permission-denied",
            "self-approval": "self-approval",
            "invalid-order": "invalid-transition",
        }
        for scenario, problem in negative_reports.items():
            expected = (
                "scenario=" + scenario + "\n"
                "request=REQ-200\nrequester=alice\namount=3200\ncategory=equipment\n"
                "result=error:" + problem + "\nstatus=submitted\n"
                "events=submit:alice:draft->submitted"
            )
            run_binary(approval, expected, scenario)
        print("PASS permission, self-approval and transition failures preserve audited state")

        unknown = subprocess.run(
            [str(binary_path(approval)), "not-a-command"], text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        require(unknown.returncode != 0, "unknown CLI command succeeded")
        require(not unknown.stdout and "usage: approval-workflow" in unknown.stderr, "CLI usage failure is unstable")
        print("PASS unknown approval CLI commands fail with a stable usage contract")

        external_project = root / "external-import-project"
        shutil.copytree(APPROVAL_ROOT, external_project)
        external_entry = external_project / "ApprovalMain.agda"
        external_entry.write_text(
            external_entry.read_text(encoding="utf-8") + "\nopen import Outside.Uncontrolled\n",
            encoding="utf-8",
        )
        external_output = root / "external-import-output"
        result = invoke(
            external_entry, "ordinary", external_output,
            "--project-root", str(external_project),
        )
        require(result.returncode == 65 and "E_INPUT" in result.stdout, "external source import was accepted")
        require(not external_output.exists(), "external import failure published output")
        print("PASS multi-module build rejects source dependencies outside the declared project")

        cubical = root / "erased-cubical"
        result = invoke(FIXTURES / "ErasedCubicalMain.agda", "erased-cubical", cubical)
        require(result.returncode == 0, result.stdout)
        run_binary(cubical, "erased-cubical-ok")
        entry = cubical / "generated" / "MAlonzo" / "Code" / "ErasedCubicalMain.hs"
        require("erasedPath" not in entry.read_text(encoding="utf-8"), "erased proof survived in Haskell")
        print("PASS erased Cubical proof is absent from executable Haskell")

        expect_failure(
            FIXTURES / "UnsupportedCubical.agda", "erased-cubical",
            root / "unsupported", 65, "E_PROFILE",
        )
        print("PASS full Cubical runtime input fails closed")

        expect_failure(
            FIXTURES / "TypeError.agda", "ordinary", root / "type-error",
            70, "E_AGDA",
        )
        print("PASS type error fails closed")

        existing = root / "existing"
        existing.mkdir()
        sentinel = existing / "sentinel"
        sentinel.write_text("keep", encoding="utf-8")
        result = invoke(FIXTURES / "OrdinaryMain.agda", "ordinary", existing)
        require(result.returncode == 73 and "E_OUTPUT" in result.stdout, "existing output was not rejected")
        require(sentinel.read_text(encoding="utf-8") == "keep", "existing output was modified")
        print("PASS existing/stale output is never overwritten")

        missing = root / "missing-tool"
        result = invoke(
            FIXTURES / "OrdinaryMain.agda", "ordinary", missing,
            "--agda", "definitely-not-an-agda-executable",
        )
        require(result.returncode == 69 and "E_TOOL" in result.stdout, "missing tool did not fail closed")
        require(not missing.exists(), "missing-tool failure published output")
        print("PASS missing tool cannot fall back to mock or stale output")

        changing_dir = root / "changing-input"
        changing_dir.mkdir()
        changing_source = changing_dir / "OrdinaryMain.agda"
        shutil.copy2(FIXTURES / "OrdinaryMain.agda", changing_source)
        changing_output = root / "identity-change"
        command = [
            sys.executable, str(BUILD), "--source", str(changing_source),
            "--profile", "ordinary", "--output", str(changing_output),
        ]
        process = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        deadline = time.monotonic() + 10
        staged_copy_seen = False
        while time.monotonic() < deadline:
            stages = list(root.glob(".identity-change.staging-*"))
            if stages and (stages[0] / "input" / "OrdinaryMain.agda").is_file():
                staged_copy_seen = True
                break
            if process.poll() is not None:
                break
            time.sleep(0.01)
        require(staged_copy_seen, "could not observe isolated source snapshot")
        changing_source.write_text(
            changing_source.read_text(encoding="utf-8").replace("ordinary-ok", "changed"),
            encoding="utf-8",
        )
        identity_output, _ = process.communicate(timeout=30)
        require(process.returncode == 65 and "E_IDENTITY" in identity_output, "source change was not rejected")
        require(not changing_output.exists(), "identity failure published output")
        require(not list(root.glob(".identity-change.staging-*")), "identity failure left staging")
        print("PASS source identity change during build fails closed")

        changing_project = root / "changing-project"
        shutil.copytree(APPROVAL_ROOT, changing_project)
        changing_entry = changing_project / "ApprovalMain.agda"
        changing_project_output = root / "changing-project-output"
        command = [
            sys.executable, str(BUILD), "--source", str(changing_entry),
            "--project-root", str(changing_project), "--profile", "ordinary",
            "--output", str(changing_project_output),
        ]
        process = subprocess.Popen(
            command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
        )
        deadline = time.monotonic() + 10
        staged_copy_seen = False
        while time.monotonic() < deadline:
            stages = list(root.glob(".changing-project-output.staging-*"))
            if stages and (stages[0] / "input" / "Approval" / "Policy.agda").is_file():
                staged_copy_seen = True
                break
            if process.poll() is not None:
                break
            time.sleep(0.01)
        require(staged_copy_seen, "could not observe isolated project snapshot")
        policy = changing_project / "Approval" / "Policy.agda"
        policy.write_text(
            policy.read_text(encoding="utf-8").replace("managerLimit = 1000", "managerLimit = 999"),
            encoding="utf-8",
        )
        identity_output, _ = process.communicate(timeout=30)
        require(
            process.returncode == 65 and "E_IDENTITY" in identity_output,
            "non-entry project source change was not rejected",
        )
        require(not changing_project_output.exists(), "project identity failure published output")
        require(not list(root.glob(".changing-project-output.staging-*")), "project identity failure left staging")
        print("PASS every module in the project tree is identity-bound during the build")

    after = {path.name: digest(path) for path in FIXTURES.glob("*.agda")}
    after_names = sorted(path.name for path in FIXTURES.iterdir())
    require(before == after and before_names == after_names, "verification modified source fixtures")
    approval_after = {
        str(path.relative_to(APPROVAL_ROOT)): digest(path)
        for path in APPROVAL_ROOT.rglob("*.agda")
    }
    require(approval_before == approval_after, "verification modified approval project")
    require(not list(FIXTURES.glob("*.agdai")), "verification left Agda interfaces in source")
    print("PASS input tree unchanged and temporary products cleaned")
    print("verify-native-binary: 15/15 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-native-binary: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
