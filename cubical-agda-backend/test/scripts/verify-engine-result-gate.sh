#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$backend_dir/test/fixtures/agda/StaticOrdinary.agda"
evidence_dir="$backend_dir/build/engine-result-gate"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

seed_publications() {
  output_dir=$1
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    printf 'stale engine-result artifact\n' > "$output_dir/$artifact"
  done
}

assert_no_publications() {
  output_dir=$1
  label=$2
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    if [ -e "$output_dir/$artifact" ]; then
      echo "$label: rejected engine result left $artifact" >&2
      exit 1
    fi
  done
}

accepted_dir="$evidence_dir/accepted"
mkdir -p "$accepted_dir"
cp "$fixture" "$accepted_dir/StaticOrdinary.agda"
Agda_datadir="$agda_data_dir" "$default_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$accepted_dir" \
  --no-libraries \
  -i "$accepted_dir" \
  "$accepted_dir/StaticOrdinary.agda" \
  > "$accepted_dir/producer.stdout" \
  2> "$accepted_dir/producer.stderr"

accepted_value=$(chez --script "$accepted_dir/program.ss")
if [ "$accepted_value" != 42 ] || \
   ! grep -q '^engine-result-closed: true$' "$accepted_dir/staging.txt" || \
   ! grep -q '^engine-result-meta-free: true$' "$accepted_dir/staging.txt" || \
   ! grep -q '^engine-result-agda-checked: true$' "$accepted_dir/staging.txt"
then
  echo "accepted: valid engine result lacks admission evidence" >&2
  exit 1
fi
printf 'accepted\tPASS\tPASS\n' >> "$summary"

verify_rejected_result() {
  label=$1
  macro=$2
  expected_error=$3
  case_dir="$evidence_dir/$label"
  object_dir="$backend_dir/build/ghc-engine-result-$label"
  binary="$evidence_dir/cubical-chez-$label"

  mkdir -p "$case_dir" "$object_dir"
  cp "$fixture" "$case_dir/StaticOrdinary.agda"
  "$ghc" -O0 -Wall -Werror -dynamic "$macro" \
    -package-db "$agda_package_db" -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$object_dir" \
    -o "$binary" \
    "$backend_dir/src/Main.hs" \
    > "$case_dir/build.stdout" \
    2> "$case_dir/build.stderr"

  seed_publications "$case_dir"
  set +e
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine=agda-baseline \
    --cubical-chez-output="$case_dir" \
    --no-libraries \
    -i "$case_dir" \
    "$case_dir/StaticOrdinary.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  status=$?
  set -e

  if [ "$status" -eq 0 ] || \
     ! grep -q "$expected_error" \
       "$case_dir/producer.stdout" "$case_dir/producer.stderr"
  then
    echo "$label: invalid engine result was not rejected by the expected gate" >&2
    exit 1
  fi
  assert_no_publications "$case_dir" "$label"
  printf '%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' "$label" >> "$summary"
}

verify_rejected_result \
  open-term \
  -DCUBICAL_CHEZ_TEST_ENGINE_OPEN_TERM \
  'static engine returned an open'
verify_rejected_result \
  unresolved-meta \
  -DCUBICAL_CHEZ_TEST_ENGINE_UNRESOLVED_META \
  'static engine returned unresolved'
verify_rejected_result \
  type-mismatch \
  -DCUBICAL_CHEZ_TEST_ENGINE_TYPE_MISMATCH \
  'Term/Type pair rejected by Agda'

if [ "$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 1 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $3 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 3 ]
then
  echo "Engine-result gate summary is incomplete" >&2
  exit 1
fi

echo "Engine result admission gate PASS (1 positive, 3 negative)"
