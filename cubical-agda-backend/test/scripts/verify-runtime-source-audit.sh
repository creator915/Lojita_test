#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
audit=$repo_root/test/scripts/audit-runtime-source.sh
workspace=$(mktemp -d "${TMPDIR:-/tmp}/runtime-source-audit-test.XXXXXX")
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "runtime source audit regression FAIL: $*" >&2
  exit 1
}

grep -Fq "grep -R -n -E" "$audit" ||
  fail "portable grep implementation is missing"
if grep -Eq '(^|[^[:alnum:]_])rg([^[:alnum:]_]|$)' "$audit"; then
  fail "security audit still depends on ripgrep"
fi

mkdir -p "$workspace/clean" "$workspace/forbidden"
printf '%s\n' 'module Clean where' 'identity value = value' > "$workspace/clean/Clean.hs"
printf '%s\n' 'module Forbidden where' 'import System.Process' > "$workspace/forbidden/Forbidden.hs"

sh "$audit" "$workspace/clean" > "$workspace/clean.log" 2>&1 ||
  fail "clean source was rejected"
grep -Fq 'RuntimeSourceAudit PASS' "$workspace/clean.log" ||
  fail "clean audit did not emit PASS evidence"

if sh "$audit" "$workspace/forbidden" > "$workspace/forbidden.log" 2>&1; then
  fail "forbidden source escaped the audit"
fi
grep -Fq 'Forbidden.hs' "$workspace/forbidden.log" ||
  fail "forbidden-source evidence is missing"
grep -Fq 'runtime source audit FAIL' "$workspace/forbidden.log" ||
  fail "forbidden-source rejection is not stable"

echo 'RuntimeSourceAuditRegression PASS (works without rg; malicious source rejected)'
