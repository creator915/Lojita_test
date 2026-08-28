#!/usr/bin/env python3
"""Build the compile-time Agda Internal lowerer used only by runtime-nbe."""

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
ADAPTER = ROOT / "agda-adapter"
LOCK = json.loads((ADAPTER / "agda-source.lock.json").read_text(encoding="utf-8"))


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
        command, cwd=str(cwd), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        combined = result.stdout + result.stderr
        tail = "\n".join(combined.splitlines()[-60:])
        raise BuildFailure(f"{label} failed:\n{tail}")
    return result.stdout.strip()


def tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildFailure(f"{label} executable not found: {requested}")
    return str(Path(resolved).resolve())


def canonical_remote(value):
    return value.removesuffix(".git").removesuffix("/")


def validate_source(source, git):
    if not (source / "Agda.cabal").is_file():
        raise BuildFailure("Agda source tree is incomplete")
    revision = run([git, "-C", str(source), "rev-parse", "HEAD"], source, "Agda revision")
    if revision != LOCK["revision"]:
        raise BuildFailure(f"Agda revision mismatch: expected {LOCK['revision']}, got {revision}")
    dirty = run(
        [git, "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        source,
        "Agda source status",
    )
    if dirty:
        raise BuildFailure("Agda source has tracked modifications")
    remote = run(
        [git, "-C", str(source), "remote", "get-url", "origin"],
        source,
        "Agda origin",
    )
    if canonical_remote(remote) != canonical_remote(LOCK["repository"]):
        raise BuildFailure(f"Agda origin mismatch: {remote}")
    if sha256_file(source / "Agda.cabal") != LOCK["agda_cabal_sha256"]:
        raise BuildFailure("locked Agda.cabal hash mismatch")
    if sha256_file(source / LOCK["license_file"]) != LOCK["license_sha256"]:
        raise BuildFailure("locked Agda license hash mismatch")
    return revision


def adapter_inputs():
    return sorted([
        ROOT / "build-agda-adapter.py",
        ROOT / "agda_data.py",
        ROOT / "build_support.py",
        ADAPTER / "agda-source.lock.json",
        ADAPTER / "agda-runtime-nbe-producer.cabal",
        *(ADAPTER / "src").rglob("*.hs"),
        *(ADAPTER / "app").rglob("*.hs"),
        *(ADAPTER / "oracle-app").rglob("*.hs"),
    ])


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--output", default=str(REPOSITORY / "build" / "runtime-nbe-agda-adapter"))
    parser.add_argument("--cabal", default=os.environ.get("CABAL", "cabal"))
    parser.add_argument("--ghc", default=os.environ.get("GHC", "ghc"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    parser.add_argument("--offline", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    try:
        args = parse_args(argv)
        if not args.agda_source:
            raise BuildFailure("provide --agda-source or AGDA_SOURCE_DIR")
        source = Path(args.agda_source).expanduser().resolve()
        output = Path(args.output).expanduser().absolute()
        if output == output.parent:
            raise BuildFailure("refusing unsafe output directory")
        output.mkdir(parents=True, exist_ok=True)
        cabal = tool(args.cabal, "cabal")
        ghc = tool(args.ghc, "GHC")
        git = tool(args.git, "git")
        revision = validate_source(source, git)

        project = output / "cabal.project"
        project.write_text(
            "packages:\n"
            f"  {source / 'Agda.cabal'}\n"
            f"  {ADAPTER / 'agda-runtime-nbe-producer.cabal'}\n\n"
            "package Agda\n"
            "  flags: -optimise-heavily\n"
            "  optimization: False\n\n"
            "package agda-runtime-nbe-producer\n"
            "  optimization: False\n",
            encoding="utf-8",
        )
        build_dir = output / "dist-newstyle"
        common = [
            f"--project-file={project}", f"--builddir={build_dir}",
            f"--with-compiler={ghc}",
        ]
        if args.offline:
            common.append("--offline")
        target = "agda-runtime-nbe-producer:exe:agda-runtime-nbe-producer"
        oracle_target = "agda-runtime-nbe-producer:exe:agda-runtime-nbe-oracle"
        run(
            [cabal, "build", *common, target, oracle_target],
            output,
            "Agda lowerer and oracle build",
        )
        listed_binary = run(
            [cabal, "list-bin", *common, target], output, "Agda lowerer path"
        )
        try:
            binary_path = select_list_bin_path(
                listed_binary,
                output,
                "agda-runtime-nbe-producer",
                "Agda lowerer path",
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
        try:
            agda_data = prepare_agda_data(source, output / "agda-data", published)
        except AgdaDataFailure as error:
            raise BuildFailure(str(error)) from error
        agda_data["relative_path"] = "agda-data"
        provenance = {
            "schema": 1,
            "agda_repository": LOCK["repository"],
            "agda_revision": revision,
            "agda_license": LOCK["license"],
            "binary": str(published),
            "binary_sha256": sha256_file(published),
            "oracle_binary": str(published_oracle),
            "oracle_binary_sha256": sha256_file(published_oracle),
            "agda_data": agda_data,
            "adapter_source_sha256": {
                str(path.relative_to(ROOT)): sha256_file(path)
                for path in adapter_inputs()
            },
            "tools": {
                "cabal": run([cabal, "--version"], output, "cabal version").splitlines()[0],
                "ghc": run([ghc, "--version"], output, "GHC version").splitlines()[0],
            },
        }
        (output / "provenance.json").write_text(
            json.dumps(provenance, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"build-runtime-nbe-agda-adapter: PASS: {published}")
        return 0
    except BuildFailure as error:
        print(f"build-runtime-nbe-agda-adapter: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
