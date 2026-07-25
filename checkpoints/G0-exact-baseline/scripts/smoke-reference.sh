#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'Usage: %s /absolute/path/to/codex\n' "$0" >&2
  exit 2
fi

binary="$1"
[[ "$binary" == /* ]] || {
  printf 'Binary path must be absolute: %s\n' "$binary" >&2
  exit 2
}
[[ -x "$binary" ]] || {
  printf 'Binary is not executable: %s\n' "$binary" >&2
  exit 1
}

smoke_root="$(mktemp -d /tmp/codex-g0-smoke.XXXXXX)"
trap 'find "$smoke_root" -xdev -depth -delete' EXIT
mkdir -p "$smoke_root/.codex"

HOME="$smoke_root" CODEX_HOME="$smoke_root/.codex" "$binary" --version
HOME="$smoke_root" CODEX_HOME="$smoke_root/.codex" "$binary" --help >/dev/null
HOME="$smoke_root" CODEX_HOME="$smoke_root/.codex" "$binary" exec --help >/dev/null
HOME="$smoke_root" CODEX_HOME="$smoke_root/.codex" "$binary" app-server --help >/dev/null

printf '%s\n' "codex reference smoke: PASS"
