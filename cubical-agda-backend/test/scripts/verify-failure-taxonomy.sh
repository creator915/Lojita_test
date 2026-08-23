#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/failure-taxonomy"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\tfailure_code\texpectation\tstatus\n' > "$summary"

build_variant() {
  label=$1
  macro=$2
  object_dir="$backend_dir/build/ghc-failure-$label"
  variant_binary="$evidence_dir/cubical-chez-$label"
  mkdir -p "$object_dir"
  "$ghc" -O0 -Wall -Werror -dynamic \
    "-D$macro" \
    -package-db "$agda_package_db" -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$object_dir" \
    -o "$variant_binary" \
    "$backend_dir/src/Main.hs" \
    > "$evidence_dir/build-$label.stdout" \
    2> "$evidence_dir/build-$label.stderr"
}

build_variant timeout CUBICAL_CHEZ_TEST_ENGINE_TIMEOUT
timeout_binary="$variant_binary"
build_variant nbe-failed CUBICAL_CHEZ_TEST_NBE_FAILURE
nbe_failed_binary="$variant_binary"

run_failure_case() {
  label=$1
  binary=$2
  engine=$3
  policy=$4
  fixture_relative=$5
  expected_code=$6
  output_dir="$evidence_dir/$label"
  source_path="$output_dir/$fixture_relative"
  source_parent=$(dirname "$source_path")

  mkdir -p "$source_parent"
  cp "$fixture_dir/$fixture_relative" "$source_path"
  for stale_artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    printf 'stale artifact that must not survive\n' > "$output_dir/$stale_artifact"
  done

  set +e
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-residual="$policy" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$output_dir" \
    "$source_path" \
    > "$output_dir/producer.stdout" \
    2> "$output_dir/producer.stderr"
  failure_status=$?
  set -e

  actual_codes=$(grep -Eho 'CCZ-[A-Z-]+' \
    "$output_dir/producer.stdout" "$output_dir/producer.stderr" \
    | sort -u || true)
  if [ "$failure_status" -eq 0 ] || \
     [ "$actual_codes" != "$expected_code" ] || \
     [ -e "$output_dir/program.ss" ] || \
     [ -e "$output_dir/typed-residual.txt" ] || \
     [ -e "$output_dir/typed-residual.bin" ]
  then
    echo "$label: expected only $expected_code with no publishable artifact" >&2
    exit 1
  fi
  printf '%s\t%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
    "$label" "$expected_code" >> "$summary"
}

run_failure_case \
  nbe-unavailable "$default_binary" nbe reject \
  StaticOrdinary.agda CCZ-NBE-UNAVAILABLE
run_failure_case \
  engine-timeout "$timeout_binary" nbe reject \
  StaticOrdinary.agda CCZ-ENGINE-TIMEOUT
run_failure_case \
  nbe-execution-failed "$nbe_failed_binary" nbe reject \
  StaticOrdinary.agda CCZ-NBE-FAILED
run_failure_case \
  residual-required "$default_binary" agda-baseline reject \
  PacketResidual.agda CCZ-RESIDUAL-REQUIRED
run_failure_case \
  residualization-failed "$default_binary" agda-baseline packet \
  PacketResidual.agda CCZ-RESIDUALIZATION-FAILED
run_failure_case \
  unsupported "$default_binary" agda-baseline packet \
  Cubical/Primitive/Unknown.agda CCZ-UNSUPPORTED

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 6 ] || \
   [ "$(awk -F '\t' 'NR > 1 { seen[$2]++ } END { print length(seen) }' "$summary")" -ne 6 ]
then
  echo "Failure taxonomy summary is incomplete or ambiguous" >&2
  exit 1
fi

echo "Failure taxonomy PASS (6 distinct non-success classes)"
