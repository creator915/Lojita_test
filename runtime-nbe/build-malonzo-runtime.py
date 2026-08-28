#!/usr/bin/env python3
"""Build a Stock Agda -> MAlonzo final client linked to the cctt runtime."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from agda_data import AgdaDataFailure, verify_agda_data


ROOT = Path(__file__).resolve().parent
REPOSITORY = ROOT.parent
CLIENT = ROOT / "examples" / "malonzo-runtime" / "RuntimeNbeClient.agda"
RUNTIME_SOURCE = ROOT / "malonzo-runtime" / "src"


class BuildFailure(Exception):
    pass


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, cwd, label, env=None):
    result = subprocess.run(
        command, cwd=str(cwd), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        raise BuildFailure(
            label + " failed:\n" + "\n".join(
                (result.stdout + result.stderr).splitlines()[-80:]
            )
        )
    return result.stdout.strip()


def tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildFailure(label + " executable not found: " + requested)
    return str(Path(resolved).resolve())


def tree_sha256(root):
    digest = hashlib.sha256()
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = str(path.relative_to(root))
        digest.update(relative.encode("utf-8") + b"\0")
        digest.update(path.read_bytes())
    return digest.hexdigest()


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--integrated-output", required=True)
    parser.add_argument("--agda-source", required=True)
    parser.add_argument(
        "--output", default=str(REPOSITORY / "build" / "runtime-nbe-malonzo")
    )
    parser.add_argument("--cabal", default=os.environ.get("CABAL", "cabal"))
    parser.add_argument("--ghc", default=os.environ.get("GHC", "ghc"))
    parser.add_argument("--git", default=os.environ.get("GIT", "git"))
    args = parser.parse_args(argv)
    try:
        output = Path(args.output).expanduser().absolute()
        if output == output.parent:
            raise BuildFailure("refusing unsafe output directory")
        integrated = Path(args.integrated_output).expanduser().resolve()
        provenance_path = integrated / "provenance.json"
        if not provenance_path.is_file():
            raise BuildFailure("integrated provenance is missing")
        provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
        agda_source = Path(args.agda_source).expanduser().resolve()
        git = tool(args.git, "Git")
        agda_revision = run(
            [git, "-C", str(agda_source), "rev-parse", "HEAD"],
            REPOSITORY,
            "Agda source identity",
        )
        if agda_revision != provenance["agda"]["revision"]:
            raise BuildFailure("Agda source revision mismatch")
        agda_data = integrated / "agda-data"
        if not (agda_data / "lib" / "prim" / "_build" / "2.8.0" / "agda"
                / "Agda" / "Primitive.agdai").is_file():
            raise BuildFailure("integrated cold Agda primitive interfaces are missing")
        if provenance["agda_data"]["relative_path"] != "agda-data":
            raise BuildFailure("integrated Agda data provenance relative path drift")
        try:
            verify_agda_data(agda_data, provenance["agda_data"])
        except AgdaDataFailure as error:
            raise BuildFailure(str(error)) from error
        agda = integrated / "bin" / "agda-locked"
        if not agda.is_file() or sha256_file(agda) != provenance["agda_binary"]["sha256"]:
            raise BuildFailure("locked Agda binary identity mismatch")
        ghc = tool(args.ghc, "GHC")
        cabal = tool(args.cabal, "Cabal")
        ghc_version = run([ghc, "--numeric-version"], REPOSITORY, "GHC identity")
        if ghc_version not in provenance["tools"]["ghc"]:
            raise BuildFailure("GHC differs from integrated provider ABI")

        stage = output / "stage"
        if stage.exists():
            shutil.rmtree(stage)
        generated = stage / "generated"
        objects = stage / "objects"
        project = stage / "project"
        generated.mkdir(parents=True, exist_ok=True)
        objects.mkdir(parents=True, exist_ok=True)
        project.mkdir(parents=True, exist_ok=True)
        staged_client = project / CLIENT.name
        shutil.copy2(CLIENT, staged_client)
        agda_environment = os.environ.copy()
        agda_environment["Agda_datadir"] = str(agda_data)
        run(
            [
                str(agda), "--no-libraries", "--ignore-interfaces",
                "-i", str(project),
                "--compile", "--ghc-dont-call-ghc",
                f"--compile-dir={generated}", str(staged_client),
            ],
            REPOSITORY,
            "Stock Agda MAlonzo generation",
            env=agda_environment,
        )
        generated_main = generated / "MAlonzo" / "Code" / "RuntimeNbeClient.hs"
        if not generated_main.is_file():
            raise BuildFailure("MAlonzo client module was not generated")

        cabal_paths = json.loads(run(
            [cabal, "path", f"--with-compiler={ghc}", "--output-format=json"],
            REPOSITORY,
            "Cabal store discovery",
        ))
        store = Path(cabal_paths["store-dir"])
        store_databases = sorted(store.glob(f"ghc-{ghc_version}*/package.db"))
        if len(store_databases) != 1:
            raise BuildFailure(
                f"expected one Cabal store package DB for GHC {ghc_version}, "
                f"found {len(store_databases)}"
            )
        local_database = integrated / "dist-newstyle" / "packagedb" / f"ghc-{ghc_version}"
        if not local_database.is_dir():
            raise BuildFailure("integrated local package DB is missing")

        binary = output / "bin" / "runtime-nbe-client"
        binary.parent.mkdir(parents=True, exist_ok=True)
        run(
            [
                ghc, "-O2", "-Wall", "-threaded",
                "-o", str(binary), f"-i{generated}", f"-i{RUNTIME_SOURCE}",
                "-odir", str(objects), "-hidir", str(objects),
                "-main-is", "MAlonzo.Code.RuntimeNbeClient", str(generated_main),
                "--make", "-package-db", str(store_databases[0]),
                "-package-db", str(local_database),
                "-package", "bytestring", "-package", "containers",
                "-package", "cctt-runtime-provider", "-package", "text",
            ],
            REPOSITORY,
            "MAlonzo final runtime link",
        )
        result = {
            "schema": 1,
            "builder_sha256": sha256_file(ROOT / "build-malonzo-runtime.py"),
            "agda_revision": agda_revision,
            "provider_revision": provenance["provider"]["revision"],
            "client_source_sha256": sha256_file(CLIENT),
            "runtime_source_sha256": tree_sha256(RUNTIME_SOURCE),
            "generated_tree_sha256": tree_sha256(generated),
            "tools": {
                "agda": run([str(agda), "--version"], REPOSITORY, "Agda version").splitlines()[0],
                "ghc": run([ghc, "--version"], REPOSITORY, "GHC version"),
            },
            "binary": {"path": str(binary), "sha256": sha256_file(binary)},
        }
        output.mkdir(parents=True, exist_ok=True)
        (output / "provenance.json").write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print("build-runtime-nbe-malonzo: PASS: " + str(binary))
        return 0
    except (BuildFailure, KeyError, json.JSONDecodeError) as error:
        print("build-runtime-nbe-malonzo: FAIL: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
