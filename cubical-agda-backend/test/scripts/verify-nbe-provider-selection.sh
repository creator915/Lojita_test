#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
candidate_file="$backend_dir/config/nbe-provider-candidates.tsv"
lock_file="$backend_dir/config/nbe-adapter.lock.tsv"
evidence_dir="$backend_dir/build/nbe-provider-selection"
summary="$evidence_dir/summary.tsv"
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/cubical-chez-nbe-provider.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM

validate_candidates() {
  candidates=$1
  lock=$2

  awk -F '\t' '
    BEGIN {
      expected = "provider\trepository\trevision\tsource-archive-sha256\tlicense\tlanguage\tpackage-boundary\tcalculus\tcubical-capability\tagda-internal-adapter\tselection-role\tdisposition"
    }
    NR == 1 {
      if ($0 != expected) {
        print "invalid candidate header" > "/dev/stderr"
        failed = 1
      }
      next
    }
    {
      records++
      if (NF != 12) {
        print "candidate row must contain exactly 12 fields: " $1 > "/dev/stderr"
        failed = 1
      }
      if (seen[$1]++) {
        print "duplicate candidate: " $1 > "/dev/stderr"
        failed = 1
      }
      if ($2 !~ /^https:\/\/github.com\//) {
        print "candidate repository is not an exact GitHub URI: " $1 > "/dev/stderr"
        failed = 1
      }
      if (length($3) != 40 || $3 !~ /^[0-9a-f]+$/) {
        print "candidate revision is not a full commit: " $1 > "/dev/stderr"
        failed = 1
      }
      if (length($4) != 64 || $4 !~ /^[0-9a-f]+$/) {
        print "candidate source hash is not SHA-256: " $1 > "/dev/stderr"
        failed = 1
      }
      if ($9 != "yes" && $9 != "no") {
        print "invalid Cubical capability: " $1 > "/dev/stderr"
        failed = 1
      }
      if ($10 != "yes" && $10 != "no") {
        print "invalid Agda adapter capability: " $1 > "/dev/stderr"
        failed = 1
      }
      if ($10 == "yes") adapters++
      if ($11 == "preferred-algorithm-reference") preferred++
    }
    $1 == "cctt" {
      cctt++
      if ($2 != "https://github.com/AndrasKovacs/cctt" ||
          $3 != "ba16f3758a322e9be77ada1da2b93f45d500192e" ||
          $4 != "8d83adcb45ea827583f02fb6fb5c7d023ae97fdf6dd7816e9069ee45c67b6b5d" ||
          $5 != "MIT" || $6 != "Haskell" ||
          $7 != "executable-only" || $8 != "own-cartesian-cubical-core" ||
          $9 != "yes" || $10 != "no" ||
          $11 != "preferred-algorithm-reference" ||
          $12 != "requires-new-agda-adapter") {
        print "cctt audit identity or disposition drifted" > "/dev/stderr"
        failed = 1
      }
    }
    END {
      if (records != 4) {
        print "expected four audited candidates" > "/dev/stderr"
        failed = 1
      }
      if (cctt != 1 || preferred != 1) {
        print "candidate census must have one preferred algorithm reference" > "/dev/stderr"
        failed = 1
      }
      if (adapters != 0) {
        print "candidate census must not claim a drop-in Agda Internal adapter" > "/dev/stderr"
        failed = 1
      }
      exit failed
    }
  ' "$candidates" || return 1

  lock_status=$(awk -F '\t' '$1 == "status" { print $2 }' "$lock")
  if [ "$lock_status" != "unselected" ]; then
    echo "zero drop-in providers requires status=unselected" >&2
    return 1
  fi
}

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

validate_candidates "$candidate_file" "$lock_file" \
  > "$evidence_dir/audited-census.stdout" \
  2> "$evidence_dir/audited-census.stderr"
printf 'audited-census\tPASS\tPASS\n' >> "$summary"

run_reject() {
  name=$1
  candidates=$2
  lock=$3
  set +e
  validate_candidates "$candidates" "$lock" \
    > "$evidence_dir/$name.stdout" \
    2> "$evidence_dir/$name.stderr"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "$name: invalid provider census unexpectedly passed" >&2
    exit 1
  fi
  printf '%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' "$name" >> "$summary"
}

sed 's/ba16f3758a322e9be77ada1da2b93f45d500192e/main/' \
  "$candidate_file" > "$temporary_dir/floating-revision.tsv"
run_reject floating-revision "$temporary_dir/floating-revision.tsv" "$lock_file"

sed 's/\tcctt\t/\tcctt\t/' "$candidate_file" | \
  awk -F '\t' 'BEGIN { OFS="\t" } $1 == "cctt" { $10="yes" } { print }' \
  > "$temporary_dir/fake-drop-in.tsv"
run_reject fake-drop-in "$temporary_dir/fake-drop-in.tsv" "$lock_file"

awk -F '\t' 'BEGIN { OFS="\t" } $1 != "smalltt" { print }' \
  "$candidate_file" > "$temporary_dir/missing-candidate.tsv"
run_reject missing-candidate "$temporary_dir/missing-candidate.tsv" "$lock_file"

sed 's/status\tunselected/status\tselected/' \
  "$lock_file" > "$temporary_dir/premature-selection.tsv"
run_reject premature-selection "$candidate_file" "$temporary_dir/premature-selection.tsv"

if [ "$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 1 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $3 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 4 ]
then
  echo "NbE provider selection summary is incomplete" >&2
  exit 1
fi

echo "NbE provider selection gate PASS (1 census, 4 negative controls, 0 drop-in providers)"
