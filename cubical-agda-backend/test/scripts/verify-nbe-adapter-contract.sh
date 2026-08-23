#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
validator="$script_dir/verify-nbe-adapter-lock.sh"
fixture_dir="$backend_dir/test/fixtures/nbe-adapter-lock"
evidence_dir="$backend_dir/build/nbe-adapter-contract"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

run_pass() {
  name=$1
  input=$2
  sh "$validator" "$input" \
    > "$evidence_dir/$name.stdout" \
    2> "$evidence_dir/$name.stderr"
  printf '%s\tPASS\tPASS\n' "$name" >> "$summary"
}

run_reject() {
  name=$1
  input=$2
  set +e
  sh "$validator" "$input" \
    > "$evidence_dir/$name.stdout" \
    2> "$evidence_dir/$name.stderr"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "$name: invalid lock unexpectedly passed" >&2
    exit 1
  fi
  printf '%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' "$name" >> "$summary"
}

run_pass unselected "$backend_dir/config/nbe-adapter.lock.tsv"
run_pass selected-valid "$fixture_dir/selected-valid.tsv"
run_reject floating-revision "$fixture_dir/selected-floating-revision.tsv"
run_reject unknown-field "$fixture_dir/selected-unknown-field.tsv"
run_reject duplicate-field "$fixture_dir/selected-duplicate-field.tsv"
run_reject partial-unselected "$fixture_dir/unselected-with-provider.tsv"
run_reject noassertion-license "$fixture_dir/selected-noassertion-license.tsv"

if [ "$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 2 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $3 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 5 ]
then
  echo "NbE adapter contract summary is incomplete" >&2
  exit 1
fi

echo "NbE adapter lock contract PASS (2 positive, 5 negative)"
