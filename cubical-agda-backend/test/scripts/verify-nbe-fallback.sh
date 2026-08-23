#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$backend_dir/test/fixtures/agda/StaticOrdinary.agda"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/nbe-fallback"
summary="$evidence_dir/summary.tsv"
help_output="$evidence_dir/help.stdout"

mkdir -p "$evidence_dir"
printf 'case\trequested_engine\tfallback_policy\texpected\tstatus\n' > "$summary"

"$default_binary" --help > "$help_output"
if ! grep -Fq \
  'on NbE unsupported feature: reject or agda-baseline' \
  "$help_output"
then
  echo "NbE fallback help does not enumerate the implemented policies" >&2
  exit 1
fi

build_variant() {
  label=$1
  shift
  object_dir="$backend_dir/build/ghc-nbe-fallback-$label"
  variant_binary="$evidence_dir/cubical-chez-$label"
  mkdir -p "$object_dir"
  "$ghc" -O0 -Wall -Werror -dynamic "$@" \
    -package-db "$agda_package_db" -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$object_dir" \
    -o "$variant_binary" \
    "$backend_dir/src/Main.hs" \
    > "$evidence_dir/build-$label.stdout" \
    2> "$evidence_dir/build-$label.stderr"
}

build_variant unsupported -DCUBICAL_CHEZ_TEST_NBE_UNSUPPORTED
unsupported_binary=$variant_binary
build_variant timeout -DCUBICAL_CHEZ_TEST_ENGINE_TIMEOUT
timeout_binary=$variant_binary
build_variant failed -DCUBICAL_CHEZ_TEST_NBE_FAILURE
failed_binary=$variant_binary
build_variant invalid-readback \
  -DCUBICAL_CHEZ_TEST_NBE_UNSUPPORTED \
  -DCUBICAL_CHEZ_TEST_ENGINE_TYPE_MISMATCH
invalid_readback_binary=$variant_binary

seed_publications() {
  output_dir=$1
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    printf 'stale fallback artifact that must not survive\n' > "$output_dir/$artifact"
  done
}

assert_no_publications() {
  output_dir=$1
  label=$2
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    if [ -e "$output_dir/$artifact" ]; then
      echo "$label: rejected invocation left $artifact" >&2
      exit 1
    fi
  done
}

run_failure_case() {
  label=$1
  binary=$2
  engine=$3
  fallback=$4
  expected_code=$5
  output_dir="$evidence_dir/$label"

  mkdir -p "$output_dir"
  cp "$fixture" "$output_dir/StaticOrdinary.agda"
  seed_publications "$output_dir"

  set +e
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-nbe-fallback="$fallback" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$output_dir" \
    "$output_dir/StaticOrdinary.agda" \
    > "$output_dir/producer.stdout" \
    2> "$output_dir/producer.stderr"
  producer_status=$?
  set -e

  actual_codes=$(grep -Eho 'CCZ-[A-Z-]+' \
    "$output_dir/producer.stdout" "$output_dir/producer.stderr" \
    | sort -u || true)
  if [ "$producer_status" -eq 0 ] || [ "$actual_codes" != "$expected_code" ]; then
    echo "$label: expected only $expected_code" >&2
    exit 1
  fi
  assert_no_publications "$output_dir" "$label"
  printf '%s\t%s\t%s\t%s\tEXPECTED-REJECT\n' \
    "$label" "$engine" "$fallback" "$expected_code" >> "$summary"
}

run_failure_case \
  unsupported-default-reject "$unsupported_binary" nbe reject \
  CCZ-NBE-UNSUPPORTED

fallback_dir="$evidence_dir/unsupported-explicit-fallback"
mkdir -p "$fallback_dir"
cp "$fixture" "$fallback_dir/StaticOrdinary.agda"
seed_publications "$fallback_dir"
Agda_datadir="$agda_data_dir" "$unsupported_binary" \
  --cubical-chez \
  --cubical-chez-engine=nbe \
  --cubical-chez-nbe-fallback=agda-baseline \
  --cubical-chez-output="$fallback_dir" \
  --no-libraries \
  -i "$fallback_dir" \
  "$fallback_dir/StaticOrdinary.agda" \
  > "$fallback_dir/producer.stdout" \
  2> "$fallback_dir/producer.stderr"

fallback_value=$(chez --script "$fallback_dir/program.ss")
if [ "$fallback_value" != 42 ] || \
   ! grep -q '^engine: agda-baseline$' "$fallback_dir/staging.txt" || \
   ! grep -q '^engine-requested: nbe$' "$fallback_dir/staging.txt" || \
   ! grep -q '^engine-effective: agda-baseline$' "$fallback_dir/staging.txt" || \
   ! grep -q '^nbe-fallback-policy: agda-baseline$' "$fallback_dir/staging.txt" || \
   ! grep -q '^nbe-fallback-used: true$' "$fallback_dir/staging.txt" || \
   ! grep -q '^nbe-fallback-reason: nbe-unsupported-feature$' "$fallback_dir/staging.txt" || \
   ! grep -q '^type-erasure-authorized: true$' "$fallback_dir/staging.txt" || \
   [ -e "$fallback_dir/typed-residual.txt" ] || \
   [ -e "$fallback_dir/typed-residual.bin" ]
then
  echo "unsupported-explicit-fallback: fallback provenance or output is invalid" >&2
  exit 1
fi
printf '%s\t%s\t%s\t%s\tPASS\n' \
  unsupported-explicit-fallback nbe agda-baseline agda-baseline-42 >> "$summary"

run_failure_case \
  unavailable-never-falls-back "$default_binary" nbe agda-baseline \
  CCZ-NBE-UNAVAILABLE
run_failure_case \
  timeout-never-falls-back "$timeout_binary" nbe agda-baseline \
  CCZ-ENGINE-TIMEOUT
run_failure_case \
  execution-failure-never-falls-back "$failed_binary" nbe agda-baseline \
  CCZ-NBE-FAILED
run_failure_case \
  invalid-readback-never-publishes "$invalid_readback_binary" nbe agda-baseline \
  CCZ-ENGINE-RESULT-INVALID
run_failure_case \
  baseline-cannot-request-nbe-fallback "$default_binary" agda-baseline agda-baseline \
  CCZ-INVALID-CONFIG

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 7 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $5 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 1 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $5 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 6 ]
then
  echo "NbE fallback summary is incomplete" >&2
  exit 1
fi

echo "NbE fallback policy PASS (public help contract, 1 explicit fallback, 6 fail-closed cases)"
