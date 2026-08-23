#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
guide="$backend_dir/docs/BENCHMARKS.md"
readme="$backend_dir/README.md"
makefile="$backend_dir/Makefile"
release="$backend_dir/build/agda29/formal-transport-performance-release"
historical="$backend_dir/build/agda29/formal-transport-performance"
release_profile="$backend_dir/config/nbe-performance-release-profile.tsv"
historical_profile="$backend_dir/config/nbe-performance-profile.tsv"
host_profile="$backend_dir/config/nbe-performance-host-profile.tsv"

fail() {
  echo "Benchmark guide contract FAIL: $*" >&2
  exit 1
}

require_text() {
  file=$1
  needle=$2
  grep -Fq -- "$needle" "$file" || fail "$file is missing: $needle"
}

value() {
  file=$1
  key=$2
  awk -F '\t' -v key="$key" '
    $1 == key { count++; result = $2 }
    END { if (count != 1) exit 1; print result }
  ' "$file" || fail "$file must contain exactly one $key row"
}

field() {
  file=$1
  row=$2
  column=$3
  awk -F '\t' -v row="$row" -v column="$column" '
    NR == 1 {
      for (i = 1; i <= NF; i++) columns[$i] = i
      if (!(column in columns)) exit 2
      next
    }
    $1 == row { count++; result = $columns[column] }
    END { if (count != 1) exit 1; print result }
  ' "$file" || fail "$file must contain one $row row and a $column column"
}

assert_equal() {
  label=$1
  actual=$2
  expected=$3
  [ "$actual" = "$expected" ] || \
    fail "$label mismatch: expected $expected, got $actual"
}

for file in \
  "$guide" \
  "$readme" \
  "$makefile" \
  "$release_profile" \
  "$historical_profile" \
  "$host_profile" \
  "$release/invocation.tsv" \
  "$release/environment.tsv" \
  "$release/summary.tsv" \
  "$release/allocation-summary.tsv" \
  "$release/artifacts.tsv" \
  "$release/stage-summary.tsv" \
  "$release/publication.tsv" \
  "$historical/invocation.tsv" \
  "$historical/summary.tsv"
do
  [ -s "$file" ] || fail "required evidence is missing or empty: $file"
done

for heading in \
  '# NbE production-candidate benchmarks' \
  '## Status' \
  '## Method' \
  '## Environment' \
  '## Provisional thresholds' \
  '## Results' \
  '## Evidence and limits'
do
  require_text "$guide" "$heading"
done

for command in \
  'make verify-benchmarks-guide' \
  'make verify-formal-transport-production-performance' \
  'make verify-formal-transport-production-release-performance'
do
  require_text "$guide" "$command"
done

require_text "$readme" '[`BENCHMARKS.md`](docs/BENCHMARKS.md)'
require_text "$makefile" 'verify-benchmarks-guide:'

assert_equal release-schema "$(value "$release_profile" schema)" 3
assert_equal release-status "$(value "$release_profile" status)" engineering-provisional
assert_equal historical-variant \
  "$(value "$historical_profile" benchmark-variant)" engineering-o0
assert_equal historical-optimization \
  "$(value "$historical_profile" ghc-optimization)" O0
assert_equal host-schema "$(value "$host_profile" schema)" 1

for key in profile status benchmark-variant result-name ghc-optimization \
  candidate-engine required-runs group-timeout-seconds case-timeout-seconds
do
  invocation_key=$key
  case "$key" in
    status) invocation_key=profile-status ;;
    required-runs) invocation_key=runs ;;
  esac
  assert_equal "release invocation $invocation_key" \
    "$(value "$release/invocation.tsv" "$invocation_key")" \
    "$(value "$release_profile" "$key")"
done

profile_hash=$(shasum -a 256 "$release_profile" | awk '{ print $1 }')
host_hash=$(shasum -a 256 "$host_profile" | awk '{ print $1 }')
assert_equal release-profile-sha256 \
  "$(value "$release/invocation.tsv" profile-sha256)" "$profile_hash"
assert_equal host-profile-sha256 \
  "$(value "$release/invocation.tsv" host-profile-sha256)" "$host_hash"
assert_equal release-host-control \
  "$(value "$release/invocation.tsv" host-control)" HOST-PASS
assert_equal release-result \
  "$(value "$release/invocation.tsv" result)" ENGINEERING-PERFORMANCE-PASS
assert_equal publication-result \
  "$(value "$release/publication.tsv" result)" ENGINEERING-PERFORMANCE-PASS
assert_equal publication-contract \
  "$(value "$release/publication.tsv" publication)" TRANSACTIONAL-PASS

assert_equal release-host "$(value "$release/environment.tsv" cpu)" 'Apple M4'
assert_equal release-memory \
  "$(value "$release/environment.tsv" memory-bytes)" 25769803776
assert_equal release-power \
  "$(value "$release/environment.tsv" power-source)" 'AC Power'
assert_equal release-optimization \
  "$(value "$release/environment.tsv" ghc-optimization)" O2

assert_equal release-summary-rows \
  "$(awk 'END { print NR - 1 }' "$release/summary.tsv")" 12
assert_equal release-summary-status \
  "$(awk -F '\t' 'NR > 1 && $NF != "PASS" { bad++ } END { print bad + 0 }' "$release/summary.tsv")" 0
assert_equal overall-baseline \
  "$(field "$release/summary.tsv" overall baseline_median_seconds)" 74.180000
assert_equal overall-candidate \
  "$(field "$release/summary.tsv" overall candidate_median_seconds)" 74.150000
assert_equal overall-time-p95 \
  "$(field "$release/summary.tsv" overall time_ratio_p95)" 1.016723
assert_equal overall-rss-p95 \
  "$(field "$release/summary.tsv" overall rss_ratio_p95)" 1.067052
assert_equal higher-rss-p95 \
  "$(field "$release/summary.tsv" higher rss_ratio_p95)" 1.194333
assert_equal higher-rss-threshold \
  "$(field "$release/summary.tsv" higher rss_threshold)" 1.30

assert_equal overall-allocation-p95 \
  "$(field "$release/allocation-summary.tsv" overall allocation_ratio_p95)" 0.999941
assert_equal static-allocation-p95 \
  "$(field "$release/allocation-summary.tsv" static-projections allocation_ratio_p95)" 1.000046
assert_equal residual-allocation-p95 \
  "$(field "$release/allocation-summary.tsv" residual-projections allocation_ratio_p95)" 0.999802
assert_equal artifact-rows \
  "$(awk 'END { print NR - 1 }' "$release/artifacts.tsv")" 6
assert_equal artifact-status \
  "$(awk -F '\t' 'NR > 1 && $NF != "PASS" { bad++ } END { print bad + 0 }' "$release/artifacts.tsv")" 0
assert_equal stage-rows \
  "$(awk 'END { print NR - 1 }' "$release/stage-summary.tsv")" 11

assert_equal historical-result \
  "$(value "$historical/invocation.tsv" result)" ENGINEERING-PERFORMANCE-FAIL
assert_equal historical-higher-rss-p95 \
  "$(field "$historical/summary.tsv" higher rss_ratio_p95)" 1.303373
assert_equal historical-higher-rss-threshold \
  "$(field "$historical/summary.tsv" higher rss_threshold)" 1.30

assert_equal raw-files \
  "$(find "$release/raw" -type f | wc -l | tr -d ' ')" 3219
for entry in \
  'summary.tsv:48' \
  'host-preflight.tsv:48' \
  'background-processes.tsv:48' \
  'allocations.tsv:48'
do
  name=${entry%%:*}
  expected=${entry#*:}
  assert_equal "raw $name files" \
    "$(find "$release/raw" -type f -name "$name" | wc -l | tr -d ' ')" \
    "$expected"
done

for fact in \
  '74.18 s' \
  '74.15 s' \
  '1.0167' \
  '1.0671' \
  '1.194333' \
  '0.999941' \
  '3,219 raw files' \
  '48 group summaries' \
  'owner confirmation' \
  'effectively neutral rather than demonstrating a large speedup' \
  'do not enable `nbe` by default yet' \
  'not quotients of the displayed aggregate columns' \
  'does not represent one concrete' \
  'does not reconstruct the' \
  'RSS threshold failure' \
  'check-nbe-production-promotion'
do
  require_text "$guide" "$fact"
done

echo 'Benchmark guide contract PASS (O0/O2 profiles, 12 scopes, 3,219 raw files)'
