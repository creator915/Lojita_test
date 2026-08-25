#!/bin/sh
set -eu

if [ "$#" -eq 0 ]; then
  echo "usage: audit-runtime-source.sh PATH..." >&2
  exit 2
fi

pattern='System\.Process|createProcess|callProcess|readProcess|unsafePerformIO'
matches=$(mktemp "${TMPDIR:-/tmp}/runtime-source-audit.XXXXXX")
errors=$matches.errors
cleanup() {
  rm -f "$matches" "$errors"
}
trap cleanup EXIT HUP INT TERM

set +e
grep -R -n -E "$pattern" "$@" >"$matches" 2>"$errors"
status=$?
set -e

case $status in
  0)
    cat "$matches" >&2
    echo "runtime source audit FAIL: forbidden process/compiler escape found" >&2
    exit 1
    ;;
  1)
    echo "RuntimeSourceAudit PASS (portable grep; no forbidden process/compiler escape)"
    ;;
  *)
    cat "$errors" >&2
    echo "runtime source audit FAIL: grep could not complete" >&2
    exit 2
    ;;
esac
