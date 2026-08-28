#!/usr/bin/env python3
"""Regression tests for build output parsing used on cold Cabal caches."""

import tempfile
from pathlib import Path

from build_support import BuildOutputError, select_list_bin_path


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def expect_failure(output, cwd, expected, label):
    try:
        select_list_bin_path(output, cwd, expected, label)
    except BuildOutputError:
        return
    raise AssertionError(label + " unexpectedly succeeded")


def main():
    with tempfile.TemporaryDirectory(prefix="runtime-nbe-list-bin-") as temporary:
        root = Path(temporary)
        first = root / "first" / "agda-cctt-runtime"
        first.parent.mkdir()
        first.write_bytes(b"binary")

        cold_stdout = (
            "Warning: The package index is missing.\n"
            "Run 'cabal update' to download the latest package list.\n"
            f"{first}\n"
        )
        selected = select_list_bin_path(
            cold_stdout, root, "agda-cctt-runtime", "cold list-bin"
        )
        require(selected == first.resolve(), "cold-cache advisory changed selected path")
        print("PASS cold-cache advisory lines do not corrupt Cabal list-bin path")

        relative = root / "relative" / "agda-runtime-nbe-producer"
        relative.parent.mkdir()
        relative.write_bytes(b"binary")
        selected = select_list_bin_path(
            "relative/agda-runtime-nbe-producer\n",
            root,
            "agda-runtime-nbe-producer",
            "relative list-bin",
        )
        require(selected == relative.resolve(), "relative list-bin path was not resolved")
        print("PASS relative executable path is resolved against the build directory")

        wrong = root / "wrong-name"
        wrong.write_bytes(b"binary")
        expect_failure(str(wrong), root, "agda-cctt-runtime", "wrong-name list-bin")
        print("PASS an existing file with the wrong executable name is rejected")

        second = root / "second" / "agda-cctt-runtime"
        second.parent.mkdir()
        second.write_bytes(b"binary")
        expect_failure(
            f"{first}\n{second}\n", root, "agda-cctt-runtime", "ambiguous list-bin"
        )
        print("PASS multiple matching executable paths fail closed")

        expect_failure(
            "Warning: no build path available\n",
            root,
            "agda-cctt-runtime",
            "missing list-bin",
        )
        print("PASS advisory-only output fails closed")

    print("verify-runtime-nbe-build-support: 5/5 PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        raise SystemExit("verify-runtime-nbe-build-support: FAIL: " + str(error))
