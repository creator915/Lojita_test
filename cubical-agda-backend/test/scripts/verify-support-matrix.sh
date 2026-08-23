#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
matrix="$backend_dir/docs/SUPPORT-MATRIX.md"
readme="$backend_dir/README.md"
backend_source="$backend_dir/src/CubicalChez/Backend.hs"
lock="$backend_dir/config/nbe-adapter.lock.tsv"
identity="$backend_dir/config/nbe-adapter-source.identity.tsv"

fail() {
  echo "Support matrix contract failed: $1" >&2
  exit 1
}

[ -f "$matrix" ] || fail "docs/SUPPORT-MATRIX.md is missing"

for heading in \
  '## Status vocabulary' \
  '## Engine and release status' \
  '## Formal `TransportTests` matrix' \
  '## NbE semantic coverage' \
  '## Static Chez output' \
  '## Typed residual and runtime support' \
  '## Toolchain and host matrix' \
  '## Known residuals and rejection behavior' \
  '## Acceptance work not represented as support'
do
  grep -Fqx "$heading" "$matrix" || fail "missing section: $heading"
done

for status in \
  VERIFIED \
  VERIFIED-CANDIDATE \
  EXPECTED-RESIDUAL \
  FAIL-CLOSED \
  NOT-VERIFIED \
  OWNER-BLOCKED
do
  status_pattern=$(printf '| `%s` |' "$status")
  grep -Fq "$status_pattern" "$matrix" || fail "missing status: $status"
done

formal_group_count=$(awk -F '|' '
  $2 ~ /^ (Base|Glue|Int|Core|Boundary|Hit|Higher|Original monolith) $/ {
    count++
  }
  END { print count + 0 }
' "$matrix")
[ "$formal_group_count" -eq 8 ] || \
  fail "expected 8 formal groups, found $formal_group_count"

lock_status=$(awk -F '\t' '$1 == "status" { print $2; exit }' "$lock")
identity_eligibility=$(
  awk -F '\t' '$1 == "selection-eligibility" { print $2; exit }' "$identity"
)
[ "$lock_status" = unselected ] || fail "production lock is no longer unselected"
[ "$identity_eligibility" = blocked ] || \
  fail "source identity is no longer owner-blocked"
grep -Fq 'checked-in production lock remains unselected' "$matrix" || \
  fail "matrix does not report the current production lock"
grep -Fq 'approved immutable revision, license' "$matrix" || \
  fail "matrix does not report the source-identity block"

grep -Fq \
  '[`SUPPORT-MATRIX.md`](docs/SUPPORT-MATRIX.md)' "$readme" || \
  fail "README does not link the matrix"
grep -Fq -- \
  '--cubical-chez-nbe-fallback=reject|agda-baseline' \
  "$readme" || fail "README fallback inventory is stale"
grep -Fq \
  'on NbE unsupported feature: reject or agda-baseline' \
  "$backend_source" || fail "backend help inventory is stale"
grep -Fq \
  'chezNbeFallback opts `notElem` ["reject", "agda-baseline", "typed-residual"]' \
  "$backend_source" || fail "backend fallback validator is stale"

for referenced_doc in \
  TEST-RESULTS.md \
  BENCHMARKS.md \
  ARCHITECTURE.md \
  COMPATIBILITY.md \
  FAILURE_CODES.md
do
  [ -f "$backend_dir/docs/$referenced_doc" ] || \
    fail "referenced document is missing: $referenced_doc"
done

grep -Fq '1.016723/1.067052/0.999941' "$matrix" || \
  fail "release-O2 evidence is missing"
grep -Fq '`t11`/`t11b` indexed `transpX-Vec`' "$matrix" || \
  fail "known indexed residual is missing"
for required_input in AGDA29_SOURCE_DIR CUBICAL29_DIR GHC29 CABAL29
do
  grep -Fq "$required_input=/path/to/" "$matrix" || \
    fail "reproduction commands omit $required_input"
done
grep -Fq 'candidate target refreshes the baseline formal matrix first' \
  "$matrix" || fail "clean-tree candidate prerequisite is undocumented"

echo "Support matrix contract PASS (6 statuses, 8 formal groups, CLI synchronized)"
