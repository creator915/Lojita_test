#!/usr/bin/env python3
"""Build the real structured Agda Internal bridge against locked sources."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent
BRIDGE = ROOT / "agda-bridge"
LOCK = json.loads((BRIDGE / "agda-source.lock.json").read_text(encoding="utf-8"))


class BuildFailure(Exception):
    pass


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bridge_inputs():
    return sorted([
        ROOT / "build-internal.py",
        BRIDGE / "agda-source.lock.json",
        BRIDGE / "agda-term-bridge.cabal",
        *(BRIDGE / "src").rglob("*.hs"),
    ])


def tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildFailure(f"{label} executable not found: {requested}")
    return str(Path(resolved).resolve())


def run(command, cwd, label):
    result = subprocess.run(
        command, cwd=str(cwd), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-40:])
        raise BuildFailure(f"{label} failed:\n{tail}")
    return result.stdout.strip()


def validate_source(source, git):
    if not (source / "Agda.cabal").is_file() or not (source / LOCK["license_file"]).is_file():
        raise BuildFailure("Agda source tree is incomplete")
    revision = run([git, "-C", str(source), "rev-parse", "HEAD"], source, "source identity")
    if revision != LOCK["revision"]:
        raise BuildFailure(f"Agda revision mismatch: expected {LOCK['revision']}, got {revision}")
    dirty = run(
        [git, "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        source, "source status",
    )
    if dirty:
        raise BuildFailure("Agda source has tracked modifications")
    cabal_hash = sha256_file(source / "Agda.cabal")
    if cabal_hash != LOCK["agda_cabal_sha256"]:
        raise BuildFailure("locked Agda.cabal content mismatch")
    license_hash = sha256_file(source / LOCK["license_file"])
    if license_hash != LOCK["license_sha256"]:
        raise BuildFailure("locked Agda license evidence mismatch")
    return revision


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--agda-source", default=os.environ.get("AGDA_SOURCE_DIR"))
    parser.add_argument("--output", default=str(ROOT.parent / "build" / "term-internal-bridge"))
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
        output.mkdir(parents=True, exist_ok=True)
        cabal = tool(args.cabal, "cabal")
        ghc = tool(args.ghc, "GHC")
        git = tool(args.git, "git")
        revision = validate_source(source, git)

        project = output / "cabal.project"
        project.write_text(
            "packages:\n"
            f"  {source / 'Agda.cabal'}\n"
            f"  {BRIDGE / 'agda-term-bridge.cabal'}\n\n"
            "package Agda\n"
            "  flags: -optimise-heavily\n"
            "  optimization: False\n\n"
            "package agda-term-bridge\n"
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
        target = "agda-term-bridge:exe:agda-term-bridge"
        run([cabal, "build", *common, target], output, "cabal build")
        binary_path = Path(run([cabal, "list-bin", *common, target], output, "cabal list-bin"))
        if not binary_path.is_file():
            raise BuildFailure("cabal reported no bridge binary")
        published = output / "bin" / binary_path.name
        published.parent.mkdir(exist_ok=True)
        shutil.copy2(binary_path, published)

        provenance = {
            "schema": 1,
            "agda": {
                "repository": LOCK["repository"],
                "revision": revision,
                "license": LOCK["license"],
                "cabal_sha256": LOCK["agda_cabal_sha256"],
                "license_sha256": LOCK["license_sha256"],
            },
            "bridge_source_sha256": {
                str(path.relative_to(ROOT)): sha256_file(path)
                for path in bridge_inputs()
            },
            "tools": {
                "cabal": run([cabal, "--version"], output, "cabal version").splitlines()[0],
                "ghc": run([ghc, "--version"], output, "GHC version").splitlines()[0],
            },
            "binary": {"path": str(published), "sha256": sha256_file(published)},
        }
        (output / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        print(f"build-term-internal: PASS: {published}")
        return 0
    except BuildFailure as error:
        print(f"build-term-internal: FAIL: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
