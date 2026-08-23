#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
guide="$backend_dir/docs/TROUBLESHOOTING.md"
failure_codes="$backend_dir/docs/FAILURE_CODES.md"
readme="$backend_dir/README.md"
makefile="$backend_dir/Makefile"

fail() {
  echo "Troubleshooting guide contract failed: $1" >&2
  exit 1
}

[ -f "$guide" ] || fail "docs/TROUBLESHOOTING.md is missing"

for heading in \
  '## First response: preserve and classify' \
  '## Toolchain and build failures' \
  '## CLI and entry selection' \
  '## NbE engine failures' \
  '## Binding-time, residual, and lowering failures' \
  '## Packet producer and consumer failures' \
  '## Typed bridge and proxy failures' \
  '## Chez generation and execution failures' \
  '## Performance collection failures' \
  '## Provider identity and promotion failures' \
  '## Official-suite environment differences' \
  '## Escalation bundle'
do
  grep -Fqx "$heading" "$guide" || fail "missing section: $heading"
done

stable_codes=$(awk -F '`' '/^\| `CCZ-[A-Z-]+`/ { print $2 }' \
  "$failure_codes" | LC_ALL=C sort -u)
code_count=$(printf '%s\n' "$stable_codes" | awk 'NF { count++ } END { print count + 0 }')
[ "$code_count" -eq 22 ] || fail "expected 22 normative codes, found $code_count"
for stable_code in $stable_codes
do
  grep -Fq "$stable_code" "$guide" || \
    fail "normative code is missing: $stable_code"
done

for result_marker in \
  CCZ-NBE-PROMOTION-BLOCKED \
  HOST-PASS \
  ENGINEERING-PERFORMANCE-FAIL \
  ENGINEERING-PERFORMANCE-PASS \
  TRANSACTIONAL-PASS
do
  grep -Fq "$result_marker" "$guide" || \
    fail "result classification is missing: $result_marker"
done

for target in \
  verify \
  verify-failure-taxonomy \
  verify-nbe-fallback \
  verify-formal-transport-performance-host-self \
  verify-nbe-adapter-source-identity \
  check-nbe-production-promotion
do
  grep -Fq "$target:" "$makefile" || fail "Make target is missing: $target"
  grep -Fq "make $target" "$guide" || \
    fail "recovery gate is missing: $target"
done

grep -Fq 'Do not reuse `program.ss`' "$guide" || \
  fail "stale executable warning is missing"
grep -Fq 'Do not edit the production lock' "$guide" || \
  fail "production lock warning is missing"
grep -Fq 'Do not change thresholds during the run' "$guide" || \
  fail "performance threshold warning is missing"
grep -Fq '[`TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)' "$readme" || \
  fail "README does not link the troubleshooting guide"

if grep -Eq 'git reset --hard|git checkout --|rm -rf' "$guide"; then
  fail "guide contains a destructive recovery command"
fi

for referenced_doc in \
  FAILURE_CODES.md \
  SUPPORT-MATRIX.md \
  TEST-RESULTS.md \
  BENCHMARKS.md
do
  [ -f "$backend_dir/docs/$referenced_doc" ] || \
    fail "referenced document is missing: $referenced_doc"
done

echo "Troubleshooting guide contract PASS (22 stable codes, 6 recovery gates)"
