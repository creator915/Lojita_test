#!/usr/bin/env python3
"""Build the in-process Agda Term+Type -> cctt -> Agda recheck slice."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from build_support import BuildOutputError, select_list_bin_path
from agda_data import AgdaDataFailure, prepare_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
AGDA_ADAPTER = ROOT / "agda-adapter"
PROVIDER_ADAPTER = ROOT / "provider-adapter"
INTEGRATED_ADAPTER = ROOT / "integrated-adapter"
AGDA_LOCK = json.loads(
    (AGDA_ADAPTER / "agda-source.lock.json").read_text(encoding="utf-8")
)
PROVIDER_LOCK = json.loads(
    (ROOT / "provider.lock.json").read_text(encoding="utf-8")
)
LOCKED_CABAL_PACKAGES = json.loads(
    (ROOT / "cabal-packages.lock.json").read_text(encoding="utf-8")
)


class BuildFailure(Exception):
    pass


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def run(command, cwd, label):
    result = subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        combined = result.stdout + result.stderr
        raise BuildFailure(
            f"{label} failed:\n" + "\n".join(combined.splitlines()[-80:])
        )
    return result.stdout.strip()


def git_archive_sha256(source, revision, git, label):
    result = subprocess.run(
        [git, "-C", str(source), "archive", "--format=tar", revision],
        cwd=str(source), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise BuildFailure(
            f"{label} archive failed: " + result.stderr.decode(errors="replace")
        )
    return hashlib.sha256(result.stdout).hexdigest()


def tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildFailure(f"{label} executable not found: {requested}")
    return str(Path(resolved).resolve())


def canonical_remote(value):
    return value.removesuffix(".git").removesuffix("/")


def validate_git_source(source, lock, required, git, label):
    if any(not (source / relative).is_file() for relative in required):
        raise BuildFailure(f"{label} source tree is incomplete")
    revision = run(
        [git, "-C", str(source), "rev-parse", "HEAD"], source, f"{label} revision"
    )
    if revision != lock["revision"]:
        raise BuildFailure(
            f"{label} revision mismatch: expected {lock['revision']}, got {revision}"
        )
    dirty = run(
        [git, "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        source,
        f"{label} status",
    )
    if dirty:
        raise BuildFailure(f"{label} source has tracked modifications")
    remote = run(
        [git, "-C", str(source), "remote", "get-url", "origin"],
        source,
        f"{label} origin",
    )
    if canonical_remote(remote) != canonical_remote(lock["repository"]):
        raise BuildFailure(f"{label} origin mismatch: {remote}")
    return revision


def validate_dependency_source(source, lock, package_file, git):
    revision = validate_git_source(
        source,
        lock,
        [lock["license_file"], package_file],
        git,
        lock["name"],
    )
    if sha256_file(source / lock["license_file"]) != lock["license_sha256"]:
        raise BuildFailure(f"{lock['name']} license hash mismatch")
    if sha256_file(source / package_file) != lock["package_sha256"]:
        raise BuildFailure(f"{lock['name']} package hash mismatch")
    return revision


def copy_package(source, destination):
    shutil.copytree(source, destination, ignore=shutil.ignore_patterns("__pycache__"))


def locked_cabal_package_evidence(plan_path):
    plan = json.loads(plan_path.read_text(encoding="utf-8"))
    evidence = {}
    for name, expected in LOCKED_CABAL_PACKAGES.items():
        version = expected["version"]
        matches = [
            item for item in plan["install-plan"]
            if item.get("pkg-name") == name and item.get("pkg-version") == version
        ]
        if len(matches) != 1:
            raise BuildFailure(
                f"expected one locked Cabal package {name}-{version}, found {len(matches)}"
            )
        item = matches[0]
        source_hash = item.get("pkg-src-sha256")
        cabal_hash = item.get("pkg-cabal-sha256")
        if not source_hash or not cabal_hash:
            raise BuildFailure(f"locked Cabal package lacks source identity: {name}")
        actual = {
            "version": version,
            "source_sha256": source_hash,
            "cabal_sha256": cabal_hash,
        }
        if actual != expected:
            raise BuildFailure(f"locked Cabal package identity mismatch: {name}")
        evidence[name] = actual
    return evidence


def input_files():
    return sorted(
        [
            ROOT / "build-integrated.py",
            ROOT / "agda_data.py",
            ROOT / "build_support.py",
            ROOT / "provider.lock.json",
            ROOT / "cabal-packages.lock.json",
            AGDA_ADAPTER / "agda-source.lock.json",
            *(AGDA_ADAPTER / "src").rglob("*.hs"),
            *(AGDA_ADAPTER / "app").rglob("*.hs"),
            *(AGDA_ADAPTER / "oracle-app").rglob("*.hs"),
            AGDA_ADAPTER / "agda-runtime-nbe-producer.cabal",
            *(PROVIDER_ADAPTER / "src").rglob("*.hs"),
            PROVIDER_ADAPTER / "cctt-runtime-provider.cabal",
            *(INTEGRATED_ADAPTER / "src").rglob("*.hs"),
            INTEGRATED_ADAPTER / "agda-cctt-runtime.cabal",
            *(ROOT / "licenses").glob("*.txt"),
        ]
    )


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--provider-source", default=os.environ.get("CCTT_SOURCE_DIR"))
    parser.add_argument(
        "--output", default=str(REPOSITORY / "build" / "runtime-nbe-integrated")
    )
    parser.add_argument("--cabal", default=os.environ.get("CABAL", "cabal"))
    parser.add_argument("--ghc", default=os.environ.get("GHC", "ghc"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    parser.add_argument(
        "--strict-impl-params-source",
        default=os.environ.get("STRICT_IMPL_PARAMS_SOURCE_DIR"),
    )
    parser.add_argument(
        "--primdata-source", default=os.environ.get("PRIMDATA_SOURCE_DIR")
    )
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    try:
        args = parse_args(argv)
        if not args.agda_source or not args.provider_source:
            raise BuildFailure(
                "provide --agda-source/AGDA_SOURCE_DIR and --provider-source/CCTT_SOURCE_DIR"
            )
        output = Path(args.output).expanduser().absolute()
        if output == output.parent:
            raise BuildFailure("refusing unsafe output directory")
        output.mkdir(parents=True, exist_ok=True)
        agda_source = Path(args.agda_source).expanduser().resolve()
        provider_source = Path(args.provider_source).expanduser().resolve()
        cabal = tool(args.cabal, "cabal")
        ghc = tool(args.ghc, "GHC")
        git = tool(args.git, "git")

        agda_revision = validate_git_source(
            agda_source,
            AGDA_LOCK,
            ["Agda.cabal", AGDA_LOCK["license_file"]],
            git,
            "Agda",
        )
        if sha256_file(agda_source / "Agda.cabal") != AGDA_LOCK["agda_cabal_sha256"]:
            raise BuildFailure("locked Agda.cabal hash mismatch")
        if sha256_file(agda_source / AGDA_LOCK["license_file"]) != AGDA_LOCK["license_sha256"]:
            raise BuildFailure("locked Agda license hash mismatch")
        provider_revision = validate_git_source(
            provider_source,
            PROVIDER_LOCK["provider"],
            ["src/Core.hs", "src/Quotation.hs", PROVIDER_LOCK["provider"]["license_file"]],
            git,
            "cctt",
        )
        provider = PROVIDER_LOCK["provider"]
        if git_archive_sha256(provider_source, provider_revision, git, "cctt") \
                != provider["source_archive_sha256"]:
            raise BuildFailure("cctt source archive hash mismatch")
        for field, hash_field in (
            (provider["license_file"], "license_sha256"),
            (provider["package_file"], "package_sha256"),
            (provider["stack_file"], "stack_sha256"),
        ):
            if sha256_file(provider_source / field) != provider[hash_field]:
                raise BuildFailure(f"cctt locked file mismatch: {field}")
        for dependency in PROVIDER_LOCK["source_dependencies"]:
            evidence = ROOT / dependency["license_evidence"]
            if not evidence.is_file():
                raise BuildFailure(
                    f"dependency license evidence missing: {dependency['name']}"
                )
            if sha256_file(evidence) != dependency["license_sha256"]:
                raise BuildFailure(
                    f"dependency license evidence drift: {dependency['name']}"
                )

        stage = output / "stage"
        if stage.exists():
            shutil.rmtree(stage)
        producer_stage = stage / "producer"
        provider_stage = stage / "provider"
        integrated_stage = stage / "integrated"
        copy_package(AGDA_ADAPTER, producer_stage)
        copy_package(INTEGRATED_ADAPTER, integrated_stage)
        (provider_stage / "src").mkdir(parents=True)
        shutil.copytree(provider_source / "src", provider_stage / "src", dirs_exist_ok=True)
        shutil.copytree(PROVIDER_ADAPTER / "src", provider_stage / "src", dirs_exist_ok=True)
        shutil.copytree(PROVIDER_ADAPTER / "app", provider_stage / "app")
        shutil.copytree(PROVIDER_ADAPTER / "policy-app", provider_stage / "policy-app")
        shutil.copy2(
            PROVIDER_ADAPTER / "cctt-runtime-provider.cabal",
            provider_stage / "cctt-runtime-provider.cabal",
        )

        dependencies = {item["name"]: item for item in PROVIDER_LOCK["source_dependencies"]}
        strict = dependencies["strict-impl-params"]
        primdata = dependencies["primdata"]
        local_dependency_arguments = (
            args.strict_impl_params_source,
            args.primdata_source,
        )
        if any(local_dependency_arguments) and not all(local_dependency_arguments):
            raise BuildFailure(
                "provide both --strict-impl-params-source and --primdata-source"
            )
        dependency_packages = ""
        dependency_stanzas = (
            "source-repository-package\n"
            "  type: git\n"
            f"  location: {strict['repository']}\n"
            f"  tag: {strict['revision']}\n\n"
            "source-repository-package\n"
            "  type: git\n"
            f"  location: {primdata['repository']}\n"
            f"  tag: {primdata['revision']}\n\n"
        )
        dependency_source_evidence = None
        if all(local_dependency_arguments):
            strict_source = Path(args.strict_impl_params_source).expanduser().resolve()
            primdata_source = Path(args.primdata_source).expanduser().resolve()
            validate_dependency_source(
                strict_source, strict, "strict-impl-params.cabal", git
            )
            validate_dependency_source(primdata_source, primdata, "package.yaml", git)
            dependency_packages = (
                f"  {strict_source / 'strict-impl-params.cabal'}\n"
                f"  {primdata_source / 'primdata.cabal'}\n"
            )
            dependency_stanzas = ""
            dependency_source_evidence = {
                "strict-impl-params": strict["revision"],
                "primdata": primdata["revision"],
            }
        elif args.offline:
            raise BuildFailure(
                "offline cold builds require both locked dependency source trees"
            )
        project = output / "cabal.project"
        project.write_text(
            "packages:\n"
            f"  {agda_source / 'Agda.cabal'}\n"
            f"  {producer_stage / 'agda-runtime-nbe-producer.cabal'}\n"
            f"  {provider_stage / 'cctt-runtime-provider.cabal'}\n"
            f"  {integrated_stage / 'agda-cctt-runtime.cabal'}\n"
            f"{dependency_packages}\n"
            f"{dependency_stanzas}"
            "constraints: "
            + ", ".join(
                f"{name} == {locked['version']}"
                for name, locked in LOCKED_CABAL_PACKAGES.items()
            )
            + "\n\n"
            "package Agda\n"
            "  flags: -optimise-heavily\n"
            "  optimization: False\n\n"
            "package agda-runtime-nbe-producer\n"
            "  optimization: False\n\n"
            "package cctt-runtime-provider\n"
            "  optimization: True\n\n"
            "package agda-cctt-runtime\n"
            "  optimization: False\n",
            encoding="utf-8",
        )
        build_dir = output / "dist-newstyle"
        common = [
            f"--project-file={project}",
            f"--builddir={build_dir}",
            f"--with-compiler={ghc}",
        ]
        if args.offline:
            common.append("--offline")
        target = "agda-cctt-runtime:exe:agda-cctt-runtime"
        oracle_target = "agda-runtime-nbe-producer:exe:agda-runtime-nbe-oracle"
        agda_target = "Agda:exe:agda"
        run(
            [cabal, "build", *common, target, oracle_target, agda_target],
            output,
            "integrated runtime and independent oracle build",
        )
        cabal_packages = locked_cabal_package_evidence(
            build_dir / "cache" / "plan.json"
        )
        listed = run([cabal, "list-bin", *common, target], output, "integrated runtime path")
        try:
            binary_path = select_list_bin_path(
                listed, output, "agda-cctt-runtime", "integrated runtime path"
            )
        except BuildOutputError as error:
            raise BuildFailure(str(error)) from error
        published = output / "bin" / binary_path.name
        published.parent.mkdir(exist_ok=True)
        shutil.copy2(binary_path, published)
        listed_oracle = run(
            [cabal, "list-bin", *common, oracle_target], output, "Agda oracle path"
        )
        try:
            oracle_path = select_list_bin_path(
                listed_oracle, output, "agda-runtime-nbe-oracle", "Agda oracle path"
            )
        except BuildOutputError as error:
            raise BuildFailure(str(error)) from error
        published_oracle = output / "bin" / oracle_path.name
        shutil.copy2(oracle_path, published_oracle)
        listed_agda = run(
            [cabal, "list-bin", *common, agda_target], output, "locked Agda path"
        )
        try:
            agda_path = select_list_bin_path(
                listed_agda, output, "agda", "locked Agda path"
            )
        except BuildOutputError as error:
            raise BuildFailure(str(error)) from error
        published_agda = output / "bin" / "agda-locked"
        shutil.copy2(agda_path, published_agda)
        try:
            agda_data = prepare_agda_data(
                agda_source, output / "agda-data", published_agda
            )
        except AgdaDataFailure as error:
            raise BuildFailure(str(error)) from error
        agda_data["relative_path"] = "agda-data"
        provenance = {
            "schema": 1,
            "agda": {"repository": AGDA_LOCK["repository"], "revision": agda_revision},
            "provider": {
                "repository": PROVIDER_LOCK["provider"]["repository"],
                "revision": provider_revision,
            },
            "source_dependencies": PROVIDER_LOCK["source_dependencies"],
            "locked_cabal_packages": cabal_packages,
            "local_dependency_sources": dependency_source_evidence,
            "inputs": {
                str(path.relative_to(ROOT)): sha256_file(path) for path in input_files()
            },
            "tools": {
                "cabal": run([cabal, "--version"], output, "cabal version").splitlines()[0],
                "ghc": run([ghc, "--version"], output, "GHC version").splitlines()[0],
            },
            "binary": {"path": str(published), "sha256": sha256_file(published)},
            "oracle_binary": {
                "path": str(published_oracle),
                "sha256": sha256_file(published_oracle),
            },
            "agda_binary": {
                "path": str(published_agda),
                "sha256": sha256_file(published_agda),
            },
            "agda_data": agda_data,
        }
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"build-runtime-nbe-integrated: PASS: {published}")
        return 0
    except BuildFailure as error:
        print(f"build-runtime-nbe-integrated: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
