#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile="$backend_dir/config/nbe-performance-profile.tsv"
release_profile="$backend_dir/config/nbe-performance-release-profile.tsv"
host_profile="$backend_dir/config/nbe-performance-host-profile.tsv"
workspace=$(mktemp -d "${TMPDIR:-/tmp}/formal-performance-self.XXXXXX")
raw_root="$workspace/raw"
result_dir="$workspace/result"
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

groups='base glue int core boundary hit higher monolithic'
write_host_evidence() {
  group_root=$1
  printf 'key\tvalue\nschema\t1\ncaptured-at\t2026-08-22T00:00:00Z\ncpu-model\tApple M4\nlogical-cpus\t10\nmemory-bytes\t25769803776\npower-source\tAC Power\nlow-power-mode\t0\nthermal-state\tnominal\ncpu-idle-percent\t90\nmemory-free-percent\t80\nload-average-1m\t1.00\n' \
    > "$group_root/host-preflight.tsv"
  printf 'pid\tcpu_percent\trss_kib\tcommand\n' \
    > "$group_root/background-processes.tsv"
  process_number=1
  while [ "$process_number" -le 12 ]
  do
    printf '%s\t0.0\t100\tfixture-process-%s\n' \
      "$process_number" "$process_number" \
      >> "$group_root/background-processes.tsv"
    process_number=$((process_number + 1))
  done
}

for run_label in run-01 run-02 run-03
do
  for engine in agda-baseline nbe
  do
    engine_root="$raw_root/$run_label/$engine"
    mkdir -p "$engine_root"
    for group in $groups
    do
      group_root="$engine_root/$group"
      mkdir -p "$group_root/output"
      printf 'scenario\tentry\texpected\tactual\tstatus\treal_seconds\tmax_rss_bytes\n%s\tFixture.%s\tok\tok\tPASS\t1.00\t100\n' \
        "$group" "$group" > "$group_root/summary.tsv"
      printf 'scenario\tallocated_bytes\tgc_copied_bytes\tmaximum_residency_bytes\tstatus\n%s\t1000\t100\t500\tMEASURED\n' \
        "$group" > "$group_root/allocations.tsv"
      printf 'scenario\tbinding_time\treason\taction\n%s\tstatic\tno-runtime-blockers\terase-types-and-emit\n' \
        "$group" > "$group_root/binding-time.tsv"
      printf 'engine\t%s\nghc-optimization\tO0\nsource-sha256\tfixture\nprojection-sha256\tfixture\nscenarios\t%s\nexpectation\tstatic\n' \
        "$engine" "$group" > "$group_root/invocation.tsv"
      printf 'fixture  Fixture.agda\n' > "$group_root/source.sha256"
      printf 'scenario\tfragment_sha256\tstatus\n%s\tfixture\tBYTE-IDENTICAL\n' \
        "$group" > "$group_root/fragments.tsv"
      write_host_evidence "$group_root"
      printf 'scenario\tstage\telapsed_seconds\tstatus\n' \
        > "$group_root/stage-timings.tsv"
      printf '%s\tengine-total\t0.001000000\tmeasured\n' "$group" \
        >> "$group_root/stage-timings.tsv"
      if [ "$engine" = nbe ]; then
        printf '%s\tnbe-evaluation\t0.000600000\tmeasured\n' "$group" \
          >> "$group_root/stage-timings.tsv"
        printf '%s\tnbe-readback\t0.000200000\tmeasured\n' "$group" \
          >> "$group_root/stage-timings.tsv"
      else
        printf '%s\tnbe-evaluation\t-\tnot-applicable\n' "$group" \
          >> "$group_root/stage-timings.tsv"
        printf '%s\tnbe-readback\t-\tnot-applicable\n' "$group" \
          >> "$group_root/stage-timings.tsv"
      fi
      printf '%s\tengine-result-admission\t0.000100000\tmeasured\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\tinternal-semantic-audit\t0.000100000\tmeasured\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\ttreeless-conversion\t0.000100000\tmeasured\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\tresidualization\t-\tnot-applicable\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\tscheme-codegen-publication\t0.000100000\tmeasured\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\tagda-frontend-module-loading\t0.100000000\tderived-remainder\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\tchez-execution\t0.020000000\tmeasured\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '%s\ttyped-residual-consumer-execution\t-\tnot-applicable\n' "$group" >> "$group_root/stage-timings.tsv"
      printf '(display "ok")\n' > "$group_root/output/program.ss"
    done
    printf 'packet\n' > "$engine_root/higher/output/typed-term.bin"
    printf 'module\tstatus\treal_seconds\tmax_rss_bytes\n' \
      > "$engine_root/monolithic/prewarm.tsv"
    for module in TransportBase TransportGlue TransportInt TransportCoreB \
      TransportBoundary TransportHit TransportHigher TransportTests
    do
      printf '%s\tPASS\t1.00\t100\n' "$module" \
        >> "$engine_root/monolithic/prewarm.tsv"
    done
  done
done

PERFORMANCE_PROFILE="$profile" PERFORMANCE_HOST_PROFILE="$host_profile" \
PERFORMANCE_RUNS_ROOT="$raw_root" \
PERFORMANCE_RESULT_DIR="$result_dir" \
  sh "$script_dir/verify-formal-transport-performance.sh" \
  > "$workspace/positive.stdout" 2> "$workspace/positive.stderr"
find "$raw_root" -name invocation.tsv -type f -exec \
  perl -pi -e 's/^ghc-optimization\tO0$/ghc-optimization\tO2/' {} +
PERFORMANCE_PROFILE="$release_profile" PERFORMANCE_HOST_PROFILE="$host_profile" \
PERFORMANCE_RUNS_ROOT="$raw_root" \
PERFORMANCE_RESULT_DIR="$result_dir" \
  sh "$script_dir/verify-formal-transport-performance.sh" \
  > "$workspace/release-positive.stdout" \
  2> "$workspace/release-positive.stderr"
find "$raw_root" -name invocation.tsv -type f -exec \
  perl -pi -e 's/^ghc-optimization\tO2$/ghc-optimization\tO0/' {} +
if ! PERFORMANCE_PROFILE="$profile" PERFORMANCE_RUNS_ROOT="$raw_root" \
  PERFORMANCE_RESULT_DIR="$result_dir" \
    sh "$script_dir/verify-formal-transport-stage-performance.sh" \
    > "$workspace/stage-positive.stdout" 2> "$workspace/stage-positive.stderr"
then
  echo "Stage performance positive self-test failed" >&2
  tail -n 80 "$workspace/stage-positive.stdout" >&2
  tail -n 80 "$workspace/stage-positive.stderr" >&2
  exit 1
fi

expect_reject() {
  reject_name=$1
  if PERFORMANCE_PROFILE="$profile" PERFORMANCE_HOST_PROFILE="$host_profile" \
       PERFORMANCE_RUNS_ROOT="$raw_root" \
       PERFORMANCE_RESULT_DIR="$result_dir" \
       sh "$script_dir/verify-formal-transport-performance.sh" \
       > "$workspace/$reject_name.stdout" 2> "$workspace/$reject_name.stderr"
  then
    echo "Performance self-test unexpectedly accepted $reject_name" >&2
    exit 1
  fi
}

expect_stage_reject() {
  reject_name=$1
  if PERFORMANCE_PROFILE="$profile" PERFORMANCE_RUNS_ROOT="$raw_root" \
       PERFORMANCE_RESULT_DIR="$result_dir" \
       sh "$script_dir/verify-formal-transport-stage-performance.sh" \
       > "$workspace/$reject_name.stdout" 2> "$workspace/$reject_name.stderr"
  then
    echo "Stage performance self-test unexpectedly accepted $reject_name" >&2
    exit 1
  fi
}

cp "$raw_root/run-01/nbe/base/stage-timings.tsv" \
  "$workspace/base.stage-timings.saved"
sed 's/^base\tengine-total\t[^\t]*\tmeasured$/base\tengine-total\tinvalid\tmeasured/' \
  "$workspace/base.stage-timings.saved" \
  > "$raw_root/run-01/nbe/base/stage-timings.tsv"
expect_stage_reject invalid-stage-elapsed
cp "$workspace/base.stage-timings.saved" \
  "$raw_root/run-01/nbe/base/stage-timings.tsv"

mv "$raw_root/run-01/nbe/base/stage-timings.tsv" \
  "$workspace/base.stage-timings.missing"
expect_stage_reject missing-stage-evidence
mv "$workspace/base.stage-timings.missing" \
  "$raw_root/run-01/nbe/base/stage-timings.tsv"

cp "$raw_root/run-01/nbe/base/summary.tsv" "$workspace/base.summary.saved"
perl -pi -e 's/\t1[.]00\t100$/\t2.00\t100/' \
  "$raw_root/run-01/nbe/base/summary.tsv"
expect_reject elapsed-regression
cp "$workspace/base.summary.saved" "$raw_root/run-01/nbe/base/summary.tsv"

cp "$raw_root/run-01/nbe/base/allocations.tsv" \
  "$workspace/base.allocations.saved"
perl -pi -e 's/\t1000\t100\t500\tMEASURED$/\t2000\t100\t500\tMEASURED/' \
  "$raw_root/run-01/nbe/base/allocations.tsv"
expect_reject allocation-regression
cp "$workspace/base.allocations.saved" \
  "$raw_root/run-01/nbe/base/allocations.tsv"

mv "$raw_root/run-01/nbe/base/allocations.tsv" \
  "$workspace/base.allocations.missing"
expect_reject missing-allocation-evidence
mv "$workspace/base.allocations.missing" \
  "$raw_root/run-01/nbe/base/allocations.tsv"

perl -pi -e 's/\t1[.]00\t100$/\t1.00\t999/' \
  "$raw_root/run-01/nbe/base/summary.tsv"
expect_reject rss-regression
cp "$workspace/base.summary.saved" "$raw_root/run-01/nbe/base/summary.tsv"

cp "$raw_root/run-01/nbe/base/invocation.tsv" "$workspace/base.invocation.saved"
perl -pi -e 's/^engine\tnbe$/engine\tagda-baseline/' \
  "$raw_root/run-01/nbe/base/invocation.tsv"
expect_reject engine-provenance
cp "$workspace/base.invocation.saved" "$raw_root/run-01/nbe/base/invocation.tsv"

perl -pi -e 's/^ghc-optimization\tO0$/ghc-optimization\tO2/' \
  "$raw_root/run-01/nbe/base/invocation.tsv"
expect_reject optimization-provenance
cp "$workspace/base.invocation.saved" "$raw_root/run-01/nbe/base/invocation.tsv"

cp "$raw_root/run-01/nbe/base/host-preflight.tsv" \
  "$workspace/base.host-preflight.saved"
sed 's/^cpu-idle-percent\t90$/cpu-idle-percent\t10/' \
  "$workspace/base.host-preflight.saved" \
  > "$raw_root/run-01/nbe/base/host-preflight.tsv"
expect_reject non-quiescent-host
cp "$workspace/base.host-preflight.saved" \
  "$raw_root/run-01/nbe/base/host-preflight.tsv"

mv "$raw_root/run-01/nbe/base/background-processes.tsv" \
  "$workspace/base.background-processes.missing"
expect_reject missing-background-processes
mv "$workspace/base.background-processes.missing" \
  "$raw_root/run-01/nbe/base/background-processes.tsv"

mv "$raw_root/run-03" "$workspace/run-03.saved"
expect_reject missing-run

echo "Formal Transport performance comparator SELF-CHECK-PASS (2 positive + 9 rejects; stage performance 1 positive + 2 rejects)"
