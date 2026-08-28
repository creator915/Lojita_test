#!/usr/bin/env python3
"""Shared, deterministic helpers for runtime-nbe build frontends."""

from pathlib import Path


class BuildOutputError(Exception):
    pass


def select_list_bin_path(output, cwd, expected_name, label):
    """Select the one real executable path from Cabal's stdout.

    Some Cabal versions print cold-cache advisory text to stdout before the
    `list-bin` result.  Advisory text is ignored only when it cannot resolve to
    an existing file with the exact expected executable name.  Ambiguous or
    missing paths remain fail-closed.
    """

    base = Path(cwd).resolve()
    candidates = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        candidate = Path(line).expanduser()
        if not candidate.is_absolute():
            candidate = base / candidate
        try:
            candidate = candidate.resolve(strict=True)
        except (FileNotFoundError, OSError, RuntimeError):
            continue
        if candidate.is_file() and candidate.name == expected_name:
            candidates.append(candidate)

    unique = list(dict.fromkeys(candidates))
    if len(unique) != 1:
        raise BuildOutputError(
            f"{label} resolved {len(unique)} matching executable paths "
            f"from {len([line for line in output.splitlines() if line.strip()])} "
            "non-empty stdout lines"
        )
    return unique[0]
