#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
validator="$script_dir/verify-formal-transport-stage-timings.sh"
evidence_dir="$backend_dir/build/formal-transport-stage-timings-self"
summary="$evidence_dir/summary.tsv"

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/formal-stage-timing-self.XXXXXX")
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

emit_stage_case() {
  output=$1
  engine=$2
  scenario=$3
  binding=$4
  runtime=$5
  printf '%s\tengine-total\t0.001000000\tmeasured\n' "$scenario" >> "$output"
  if [ "$engine" = nbe ]; then
    printf '%s\tnbe-evaluation\t0.000600000\tmeasured\n' "$scenario" >> "$output"
    if [ "$binding" = static ]; then
      printf '%s\tnbe-readback\t0.000200000\tmeasured\n' "$scenario" >> "$output"
    else
      printf '%s\tnbe-readback\t-\tnot-applicable\n' "$scenario" >> "$output"
    fi
  else
    printf '%s\tnbe-evaluation\t-\tnot-applicable\n' "$scenario" >> "$output"
    printf '%s\tnbe-readback\t-\tnot-applicable\n' "$scenario" >> "$output"
  fi
  printf '%s\tengine-result-admission\t0.000100000\tmeasured\n' "$scenario" >> "$output"
  printf '%s\tinternal-semantic-audit\t0.000100000\tmeasured\n' "$scenario" >> "$output"
  printf '%s\ttreeless-conversion\t0.000100000\tmeasured\n' "$scenario" >> "$output"
  if [ "$binding" = static ]; then
    printf '%s\tresidualization\t-\tnot-applicable\n' "$scenario" >> "$output"
    printf '%s\tscheme-codegen-publication\t0.000100000\tmeasured\n' "$scenario" >> "$output"
  else
    printf '%s\tresidualization\t0.000100000\tmeasured\n' "$scenario" >> "$output"
    printf '%s\tscheme-codegen-publication\t-\tnot-applicable\n' "$scenario" >> "$output"
  fi
  printf '%s\tagda-frontend-module-loading\t0.100000000\tderived-remainder\n' "$scenario" >> "$output"
  if [ "$runtime" = chez ]; then
    printf '%s\tchez-execution\t0.020000000\tmeasured\n' "$scenario" >> "$output"
    printf '%s\ttyped-residual-consumer-execution\t-\tnot-applicable\n' "$scenario" >> "$output"
  elif [ "$runtime" = consumer ]; then
    printf '%s\tchez-execution\t-\tnot-applicable\n' "$scenario" >> "$output"
    printf '%s\ttyped-residual-consumer-execution\t0.030000000\tmeasured\n' "$scenario" >> "$output"
  else
    printf '%s\tchez-execution\t-\tnot-applicable\n' "$scenario" >> "$output"
    printf '%s\ttyped-residual-consumer-execution\t-\tnot-applicable\n' "$scenario" >> "$output"
  fi
}

begin_group() {
  root=$1
  engine=$2
  group=$3
  group_dir="$root/$group"
  mkdir -p "$group_dir"
  printf 'scenario\tentry\texpected\tactual\tstatus\treal_seconds\tmax_rss_bytes\n' > "$group_dir/summary.tsv"
  printf 'scenario\tbinding_time\treason\taction\n' > "$group_dir/binding-time.tsv"
  printf 'engine\t%s\n' "$engine" > "$group_dir/invocation.tsv"
  printf 'scenario\tstage\telapsed_seconds\tstatus\n' > "$group_dir/stage-timings.tsv"
}

add_case() {
  root=$1
  engine=$2
  group=$3
  scenario=$4
  binding=$5
  runtime=$6
  group_dir="$root/$group"
  printf '%s\tSynthetic.%s\tok\tok\tPASS\t0.102\t1024\n' \
    "$scenario" "$scenario" >> "$group_dir/summary.tsv"
  printf '%s\t%s\tsynthetic\tsynthetic\n' \
    "$scenario" "$binding" >> "$group_dir/binding-time.tsv"
  emit_stage_case "$group_dir/stage-timings.tsv" \
    "$engine" "$scenario" "$binding" "$runtime"
}

make_fixture() {
  root=$1
  engine=$2
  for group in base glue int core boundary hit higher monolithic
  do
    begin_group "$root" "$engine" "$group"
  done
  for spec in 'base 3' 'glue 3' 'int 2' 'core 2' 'hit 4'
  do
    set -- $spec
    group=$1
    count=$2
    index=1
    while [ "$index" -le "$count" ]; do
      scenario=$(printf '%s-s%02d' "$group" "$index")
      add_case "$root" "$engine" "$group" "$scenario" static chez
      index=$((index + 1))
    done
  done
  add_case "$root" "$engine" boundary boundary-d01 dynamic none
  add_case "$root" "$engine" boundary boundary-d02 dynamic none
  add_case "$root" "$engine" higher higher-h01-file dynamic consumer
  add_case "$root" "$engine" higher higher-h02-pipe dynamic consumer
  add_case "$root" "$engine" higher higher-h03-pipe dynamic consumer
  add_case "$root" "$engine" higher higher-h04-pipe dynamic consumer
  index=1
  while [ "$index" -le 14 ]; do
    scenario=$(printf 'monolithic-s%02d' "$index")
    add_case "$root" "$engine" monolithic "$scenario" static chez
    index=$((index + 1))
  done
  add_case "$root" "$engine" monolithic monolithic-d01 dynamic none
  add_case "$root" "$engine" monolithic monolithic-d02 dynamic none
  add_case "$root" "$engine" monolithic monolithic-h01-file dynamic consumer
  add_case "$root" "$engine" monolithic monolithic-h02-pipe dynamic consumer
  add_case "$root" "$engine" monolithic monolithic-h03-pipe dynamic consumer
  add_case "$root" "$engine" monolithic monolithic-h04-pipe dynamic consumer
}

run_validator() {
  root=$1
  engine=$2
  result=$3
  STAGE_TIMING_EVIDENCE_ROOT="$root" \
  STAGE_TIMING_ENGINE="$engine" \
  STAGE_TIMING_RESULT_DIR="$result" \
    sh "$validator"
}

run_pass() {
  name=$1
  root=$2
  engine=$3
  run_validator "$root" "$engine" "$temporary_dir/result-$name" \
    > "$evidence_dir/$name.stdout" 2> "$evidence_dir/$name.stderr"
  printf '%s\tPASS\tPASS\n' "$name" >> "$summary"
}

run_reject() {
  name=$1
  root=$2
  engine=$3
  set +e
  run_validator "$root" "$engine" "$temporary_dir/result-$name" \
    > "$evidence_dir/$name.stdout" 2> "$evidence_dir/$name.stderr"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "$name: malformed stage timing evidence unexpectedly passed" >&2
    exit 1
  fi
  printf '%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' "$name" >> "$summary"
}

baseline_root="$temporary_dir/baseline"
nbe_root="$temporary_dir/nbe"
make_fixture "$baseline_root" agda-baseline
make_fixture "$nbe_root" nbe
run_pass baseline-valid "$baseline_root" agda-baseline
run_pass nbe-valid "$nbe_root" nbe

cp "$nbe_root/base/stage-timings.tsv" "$temporary_dir/base-stage.clean.tsv"
sed '/^base-s01\tnbe-readback\t/d' "$temporary_dir/base-stage.clean.tsv" \
  > "$nbe_root/base/stage-timings.tsv"
run_reject missing-stage "$nbe_root" nbe
cp "$temporary_dir/base-stage.clean.tsv" "$nbe_root/base/stage-timings.tsv"

sed 's/^base-s01\tnbe-evaluation\t[^\t]*\tmeasured$/base-s01\tnbe-evaluation\t-\tnot-applicable/' \
  "$temporary_dir/base-stage.clean.tsv" > "$nbe_root/base/stage-timings.tsv"
run_reject missing-nbe-evaluation "$nbe_root" nbe
cp "$temporary_dir/base-stage.clean.tsv" "$nbe_root/base/stage-timings.tsv"

sed 's/^base-s01\tchez-execution\t[^\t]*\tmeasured$/base-s01\tchez-execution\t-\tnot-applicable/' \
  "$temporary_dir/base-stage.clean.tsv" > "$nbe_root/base/stage-timings.tsv"
run_reject missing-static-runtime "$nbe_root" nbe

pass_count=$(awk -F '\t' 'NR > 1 && $3 == "PASS" { n++ } END { print n+0 }' "$summary")
reject_count=$(awk -F '\t' 'NR > 1 && $3 == "EXPECTED-REJECT" { n++ } END { print n+0 }' "$summary")
[ "$pass_count" -eq 2 ] && [ "$reject_count" -eq 3 ] || {
  echo "Formal stage timing self-test summary is incomplete" >&2
  exit 1
}

echo "Formal stage timing self-test PASS (2 positive, 3 negative)"
