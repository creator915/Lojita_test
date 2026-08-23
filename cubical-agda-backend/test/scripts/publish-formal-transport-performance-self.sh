#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
workspace=$(mktemp -d /private/tmp/formal-performance-publish-self.XXXXXX)
root="$workspace/root"
final="$root/formal-transport-performance"

cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$root" "$final/raw"
printf 'old evidence\n' > "$final/sentinel.txt"

create_staging() {
  label=$1
  result=$2
  staging_name=${3:-formal-transport-performance}
  staging="$root/$staging_name.pending.$label"
  mkdir -p "$staging/raw"
  printf 'result-name\t%s\nresult\t%s\n' "$staging_name" "$result" \
    > "$staging/invocation.tsv"
  printf 'summary\n' > "$staging/summary.tsv"
  printf 'samples\n' > "$staging/samples.tsv"
  printf 'stage-summary\n' > "$staging/stage-summary.tsv"
  printf 'allocation-summary\n' > "$staging/allocation-summary.tsv"
}

create_staging positive ENGINEERING-PERFORMANCE-PASS
PERFORMANCE_PUBLICATION_ROOT="$root" \
PERFORMANCE_STAGING_RESULT="$staging" \
PERFORMANCE_FINAL_RESULT="$final" \
PERFORMANCE_TERMINAL_RESULT=ENGINEERING-PERFORMANCE-PASS \
  sh "$script_dir/publish-formal-transport-performance.sh" \
  > "$workspace/positive.stdout" 2> "$workspace/positive.stderr"
if [ ! -s "$final/publication.tsv" ] || \
   ! awk -F '\t' '$1 == "publication" && $2 == "TRANSACTIONAL-PASS" {
     found=1
   } END { exit !found }' "$final/publication.tsv" || \
   [ "$(find "$root/formal-transport-performance-archive" -name sentinel.txt | wc -l | tr -d ' ')" -ne 1 ]; then
  echo "Transactional performance publication did not archive and promote" >&2
  exit 1
fi

create_staging terminal-fail ENGINEERING-PERFORMANCE-FAIL
PERFORMANCE_PUBLICATION_ROOT="$root" \
PERFORMANCE_STAGING_RESULT="$staging" \
PERFORMANCE_FINAL_RESULT="$final" \
PERFORMANCE_TERMINAL_RESULT=ENGINEERING-PERFORMANCE-FAIL \
  sh "$script_dir/publish-formal-transport-performance.sh" \
  > "$workspace/terminal-fail.stdout" 2> "$workspace/terminal-fail.stderr"
if ! awk -F '\t' '$1 == "result" && $2 == "ENGINEERING-PERFORMANCE-FAIL" {
     found=1
   } END { exit !found }' "$final/invocation.tsv" || \
   ! awk -F '\t' '$1 == "result" && $2 == "ENGINEERING-PERFORMANCE-FAIL" {
     found=1
   } END { exit !found }' "$final/publication.tsv" || \
   [ "$(find "$root/formal-transport-performance-archive" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" -ne 2 ]; then
  echo "Transactional performance publication did not publish a terminal failure" >&2
  exit 1
fi

release_final="$root/formal-transport-performance-release"
create_staging release-positive ENGINEERING-PERFORMANCE-PASS \
  formal-transport-performance-release
PERFORMANCE_PUBLICATION_ROOT="$root" \
PERFORMANCE_STAGING_RESULT="$staging" \
PERFORMANCE_FINAL_RESULT="$release_final" \
PERFORMANCE_TERMINAL_RESULT=ENGINEERING-PERFORMANCE-PASS \
  sh "$script_dir/publish-formal-transport-performance.sh" \
  > "$workspace/release-positive.stdout" \
  2> "$workspace/release-positive.stderr"
if [ ! -s "$release_final/publication.tsv" ]; then
  echo "Transactional release performance publication did not promote" >&2
  exit 1
fi

expect_reject() {
  label=$1
  expected=$2
  candidate=$3
  target=${4:-$final}
  if PERFORMANCE_PUBLICATION_ROOT="$root" \
       PERFORMANCE_STAGING_RESULT="$candidate" \
       PERFORMANCE_FINAL_RESULT="$target" \
       PERFORMANCE_TERMINAL_RESULT="$expected" \
       sh "$script_dir/publish-formal-transport-performance.sh" \
       > "$workspace/$label.stdout" 2> "$workspace/$label.stderr"
  then
    echo "Performance publication self-test unexpectedly accepted $label" >&2
    exit 1
  fi
  [ -s "$final/publication.tsv" ] || {
    echo "Performance publication reject damaged current evidence" >&2
    exit 1
  }
}

create_staging result-mismatch ENGINEERING-PERFORMANCE-FAIL
expect_reject result-mismatch ENGINEERING-PERFORMANCE-PASS "$staging"

create_staging missing-evidence ENGINEERING-PERFORMANCE-PASS
rm -f "$staging/stage-summary.tsv"
expect_reject missing-evidence ENGINEERING-PERFORMANCE-PASS "$staging"

create_staging missing-allocation-summary ENGINEERING-PERFORMANCE-PASS
rm -f "$staging/allocation-summary.tsv"
expect_reject missing-allocation-summary ENGINEERING-PERFORMANCE-PASS \
  "$staging"

create_staging path-escape ENGINEERING-PERFORMANCE-PASS
expect_reject path-escape ENGINEERING-PERFORMANCE-PASS "$staging" \
  "$workspace/outside"

echo "Formal performance publication self-test PASS (3 positive, 4 negative)"
