"""Prepare a cold, private Agda data directory for runtime-NbE binaries."""

import hashlib
import os
import shutil
import subprocess
from pathlib import Path


class AgdaDataFailure(Exception):
    pass


REQUIRED_INTERFACES = (
    "Agda/Primitive.agdai",
    "Agda/Primitive/Cubical.agdai",
    "Agda/Builtin/Bool.agdai",
    "Agda/Builtin/Cubical/Path.agdai",
)


def sha256_file(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def agda_data_identity(destination):
    destination = Path(destination)
    primitive_root = destination / "lib" / "prim"
    interface_root = primitive_root / "_build" / "2.8.0" / "agda"
    interfaces = {relative: interface_root / relative for relative in REQUIRED_INTERFACES}
    missing = [relative for relative, path in interfaces.items() if not path.is_file()]
    if missing:
        raise AgdaDataFailure(
            "locked Agda primitive data omitted " + ", ".join(missing)
        )
    primitive = primitive_root / "Agda" / "Primitive.agda"
    if not primitive.is_file():
        raise AgdaDataFailure("locked Agda primitive source is missing")
    return {
        "primitive_source_sha256": sha256_file(primitive),
        "interface_sha256": {
            relative: sha256_file(path) for relative, path in interfaces.items()
        },
    }


def verify_agda_data(destination, evidence):
    expected = {
        key: value for key, value in evidence.items() if key != "relative_path"
    }
    if agda_data_identity(destination) != expected:
        raise AgdaDataFailure("locked Agda primitive data identity drift")


def prepare_agda_data(agda_source, destination, agda_binary):
    source_data = Path(agda_source) / "src" / "data"
    destination = Path(destination)
    agda_binary = Path(agda_binary)
    primitive = source_data / "lib" / "prim" / "Agda" / "Primitive.agda"
    if not primitive.is_file():
        raise AgdaDataFailure("locked Agda primitive sources are incomplete")
    if not agda_binary.is_file():
        raise AgdaDataFailure("locked Agda executable is missing")
    if destination == destination.parent:
        raise AgdaDataFailure("refusing unsafe Agda data destination")
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source_data, destination, ignore=shutil.ignore_patterns("_build"))

    primitive_root = destination / "lib" / "prim"
    environment = os.environ.copy()
    environment["Agda_datadir"] = str(destination)
    result = subprocess.run(
        [str(agda_binary), "--build-library"],
        cwd=str(primitive_root), env=environment, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if result.returncode:
        combined = result.stdout + result.stderr
        raise AgdaDataFailure(
            "locked Agda primitive interface bootstrap failed:\n" +
            "\n".join(combined.splitlines()[-80:])
        )

    return agda_data_identity(destination)
