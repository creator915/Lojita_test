#!/usr/bin/env python3
"""Build the immutable cctt source as a linkable runtime provider."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
ADAPTER = ROOT / "provider-adapter"
FIXTURE = ROOT / "fixtures" / "provider-slice.cctt"
LOCK = json.loads((ROOT / "provider.lock.json").read_text(encoding="utf-8"))


class BuildFailure(Exception):
    pass


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command, cwd, label, binary=False):
    result = subprocess.run(
        command,
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=not binary,
    )
    if result.returncode != 0:
        output = result.stdout.decode(errors="replace") if binary else result.stdout
        tail = "\n".join(output.splitlines()[-50:])
        raise BuildFailure(f"{label} failed:\n{tail}")
    return result.stdout


def tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildFailure(f"{label} executable not found: {requested}")
    return str(Path(resolved).resolve())


def canonical_remote(value):
    return value.removesuffix(".git").removesuffix("/")


def validate_source(source, git):
    provider = LOCK["provider"]
    required = ["src/Core.hs", "src/Quotation.hs", provider["license_file"]]
    if any(not (source / relative).is_file() for relative in required):
        raise BuildFailure("cctt source tree is incomplete")
    revision = run(
        [git, "-C", str(source), "rev-parse", "HEAD"], source, "provider revision"
    ).strip()
    if revision != provider["revision"]:
        raise BuildFailure(
            f"provider revision mismatch: expected {provider['revision']}, got {revision}"
        )
    dirty = run(
        [git, "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        source,
        "provider status",
    ).strip()
    if dirty:
        raise BuildFailure("provider source has tracked modifications")
    remote = run(
        [git, "-C", str(source), "remote", "get-url", "origin"],
        source,
        "provider origin",
    ).strip()
    if canonical_remote(remote) != canonical_remote(provider["repository"]):
        raise BuildFailure(f"provider origin mismatch: {remote}")
    archive = run(
        [git, "-C", str(source), "archive", "--format=tar", revision],
        source,
        "provider archive",
        binary=True,
    )
    if hashlib.sha256(archive).hexdigest() != provider["source_archive_sha256"]:
        raise BuildFailure("provider source archive hash mismatch")
    for field, hash_field in (
        (provider["license_file"], "license_sha256"),
        (provider["package_file"], "package_sha256"),
        (provider["stack_file"], "stack_sha256"),
    ):
        if sha256_file(source / field) != provider[hash_field]:
            raise BuildFailure(f"provider locked file mismatch: {field}")
    return revision


def clone_source(destination, git):
    provider = LOCK["provider"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    run(
        [git, "clone", "--no-checkout", provider["repository"], str(destination)],
        destination.parent,
        "provider clone",
    )
    run(
        [git, "-C", str(destination), "checkout", "--detach", provider["revision"]],
        destination,
        "provider checkout",
    )


def adapter_inputs():
    return sorted(
        [
            ROOT / "build-provider.py",
            ROOT / "provider.lock.json",
            *(ROOT / "licenses").glob("*.txt"),
            FIXTURE,
            ADAPTER / "stack.yaml",
            ADAPTER / "cctt-runtime-provider.cabal",
            *(ADAPTER / "src").rglob("*.hs"),
            *(ADAPTER / "app").rglob("*.hs"),
            *(ADAPTER / "policy-app").rglob("*.hs"),
        ]
    )


def validate_dependency_evidence():
    stack_text = (ADAPTER / "stack.yaml").read_text(encoding="utf-8")
    for dependency in LOCK["source_dependencies"]:
        revision = dependency["revision"]
        if revision not in stack_text:
            raise BuildFailure(
                f"source dependency revision is not pinned in stack.yaml: {dependency['name']}"
            )
        evidence = dependency.get("license_evidence")
        license_hash = dependency.get("license_sha256")
        if evidence and license_hash:
            evidence_path = ROOT / evidence
            if not evidence_path.is_file():
                raise BuildFailure(
                    f"source dependency license evidence is missing: {dependency['name']}"
                )
            if sha256_file(evidence_path) != license_hash:
                raise BuildFailure(
                    f"source dependency license evidence drift: {dependency['name']}"
                )


def validate_resolved_dependencies(stack_lock):
    if not stack_lock.is_file():
        raise BuildFailure("Stack dependency lock was not generated")
    lock_text = stack_lock.read_text(encoding="utf-8")
    for dependency in LOCK["source_dependencies"]:
        if f"commit: {dependency['revision']}" not in lock_text:
            raise BuildFailure(
                f"resolved source dependency revision drift: {dependency['name']}"
            )


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider-source", default=os.environ.get("CCTT_SOURCE_DIR"))
    parser.add_argument("--output", default=str(REPOSITORY / "build" / "runtime-nbe"))
    parser.add_argument("--stack", default=os.environ.get("STACK", "stack"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    parser.add_argument("--embedded-disabled-ir")
    parser.add_argument("--embedded-enabled-ir")
    return parser.parse_args(argv)


def main(argv=None):
    try:
        args = parse_args(argv)
        output = Path(args.output).expanduser().absolute()
        if output == output.parent:
            raise BuildFailure("refusing unsafe output directory")
        output.mkdir(parents=True, exist_ok=True)
        stack = tool(args.stack, "Stack")
        git = tool(args.git, "Git")
        validate_dependency_evidence()
        if args.provider_source:
            source = Path(args.provider_source).expanduser().resolve()
        else:
            source = output / "provider-source"
            if not (source / ".git").is_dir():
                clone_source(source, git)
        revision = validate_source(source, git)

        stage = output / "stage"
        if stage.exists():
            shutil.rmtree(stage)
        (stage / "src").mkdir(parents=True)
        shutil.copytree(source / "src", stage / "src", dirs_exist_ok=True)
        shutil.copytree(ADAPTER / "src", stage / "src", dirs_exist_ok=True)
        shutil.copytree(ADAPTER / "app", stage / "app")
        shutil.copytree(ADAPTER / "policy-app", stage / "policy-app")
        shutil.copy2(ADAPTER / "stack.yaml", stage / "stack.yaml")
        shutil.copy2(
            ADAPTER / "cctt-runtime-provider.cabal",
            stage / "cctt-runtime-provider.cabal",
        )

        provider_tests = output / "provider-tests"
        if provider_tests.exists():
            shutil.rmtree(provider_tests)
        provider_tests.mkdir()
        for name in ("basics.cctt", "bool.cctt"):
            shutil.copy2(source / "tests" / name, provider_tests / name)
        shutil.copy2(FIXTURE, provider_tests / FIXTURE.name)

        bin_dir = output / "bin"
        bin_dir.mkdir(exist_ok=True)
        embedded_arguments = (args.embedded_disabled_ir, args.embedded_enabled_ir)
        if any(embedded_arguments) and not all(embedded_arguments):
            raise BuildFailure("both embedded policy IR inputs are required")
        build_command = [
            stack,
            "--stack-yaml",
            str(stage / "stack.yaml"),
            "build",
            "--copy-bins",
            "--local-bin-path",
            str(bin_dir),
        ]
        embedded_inputs = None
        if all(embedded_arguments):
            disabled_ir = Path(args.embedded_disabled_ir).expanduser().resolve()
            enabled_ir = Path(args.embedded_enabled_ir).expanduser().resolve()
            if not disabled_ir.is_file() or not enabled_ir.is_file():
                raise BuildFailure("embedded policy IR input is missing")
            embedded = stage / "embedded"
            embedded.mkdir()
            shutil.copy2(disabled_ir, embedded / "preserve-disabled.ir")
            shutil.copy2(enabled_ir, embedded / "preserve-enabled.ir")
            embedded_inputs = {"disabled": disabled_ir, "enabled": enabled_ir}
            build_command.extend(["--flag", "cctt-runtime-provider:embedded-policy"])
        run(
            build_command,
            stage,
            "provider library build",
        )
        stack_lock = stage / "stack.yaml.lock"
        validate_resolved_dependencies(stack_lock)
        binary = bin_dir / "runtime-nbe-provider"
        if not binary.is_file():
            raise BuildFailure("provider executable was not published")
        policy_binary = bin_dir / "runtime-policy-user"
        if embedded_inputs is not None and not policy_binary.is_file():
            raise BuildFailure("embedded policy user executable was not published")
        archives = sorted(stage.glob(".stack-work/**/*.a"))
        provider_archives = [
            path for path in archives if "cctt-runtime-provider" in path.name
        ]
        if not provider_archives:
            raise BuildFailure("linkable provider archive was not produced")
        archive = provider_archives[-1]
        compiler = run(
            [stack, "--stack-yaml", str(stage / "stack.yaml"), "exec", "ghc", "--", "--numeric-version"],
            stage,
            "provider compiler identity",
        ).strip()
        if compiler != LOCK["toolchain"]["declared_ghc"]:
            raise BuildFailure(
                f"provider compiler mismatch: expected {LOCK['toolchain']['declared_ghc']}, got {compiler}"
            )

        provenance = {
            "schema": 1,
            "provider": {
                "repository": LOCK["provider"]["repository"],
                "revision": revision,
                "source_archive_sha256": LOCK["provider"]["source_archive_sha256"],
                "license": LOCK["provider"]["license"],
                "license_sha256": LOCK["provider"]["license_sha256"],
            },
            "source_dependencies": LOCK["source_dependencies"],
            "resolved_stack_lock_sha256": sha256_file(stack_lock),
            "adapter_source_sha256": {
                str(path.relative_to(ROOT)): sha256_file(path)
                for path in adapter_inputs()
            },
            "tools": {
                "stack": run([stack, "--numeric-version"], stage, "Stack version").strip(),
                "ghc": compiler,
            },
            "library": {
                "path": str(archive),
                "sha256": sha256_file(archive),
            },
            "binary": {
                "path": str(binary),
                "sha256": sha256_file(binary),
            },
        }
        if embedded_inputs is not None:
            provenance["embedded_policy"] = {
                "input_sha256": {
                    label: sha256_file(path) for label, path in embedded_inputs.items()
                },
                "binary": {
                    "path": str(policy_binary),
                    "sha256": sha256_file(policy_binary),
                },
            }
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"build-runtime-provider: PASS: {binary}")
        print(f"build-runtime-provider: archive={archive}")
        return 0
    except BuildFailure as error:
        print(f"build-runtime-provider: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
