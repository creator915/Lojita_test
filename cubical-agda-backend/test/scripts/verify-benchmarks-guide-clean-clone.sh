#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tmp_dir=${TMPDIR:-/tmp}/benchmark-guide-clean.$$
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
mkdir -p "$tmp_dir"

output=$(BENCHMARK_EVIDENCE_ROOT="$tmp_dir" \
  sh "$repo_root/test/scripts/verify-benchmarks-guide.sh")
[ "$output" = \
  'Benchmark guide contract PASS (clean clone; locked aggregate snapshot, generated raw evidence absent)' ] || {
  echo "BenchmarkGuideCleanClone FAIL: $output" >&2
  exit 1
}

bad_lock=$tmp_dir/bad-evidence.lock.tsv
sed 's/^raw-files[[:space:]].*/raw-files\t3218/' \
  "$repo_root/config/nbe-performance-evidence.lock.tsv" > "$bad_lock"
if BENCHMARK_EVIDENCE_ROOT="$tmp_dir" BENCHMARK_EVIDENCE_LOCK="$bad_lock" \
    sh "$repo_root/test/scripts/verify-benchmarks-guide.sh" >/dev/null 2>&1; then
  echo 'BenchmarkGuideCleanClone FAIL: tampered aggregate lock was accepted' >&2
  exit 1
fi

echo 'BenchmarkGuideCleanClone PASS (no ignored build evidence required; tampered lock rejected)'
