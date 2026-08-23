#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
build_dir="$backend_dir/build/agda29"
baseline_root=${BASELINE_TRANSPORT_EVIDENCE_DIR:-"$build_dir/formal-transport"}
candidate_engine=${DIFFERENTIAL_CANDIDATE_ENGINE:-nbe}
candidate_root=${CANDIDATE_TRANSPORT_EVIDENCE_DIR:-"$build_dir/formal-transport-$candidate_engine"}
allow_self=${DIFFERENTIAL_ALLOW_SELF:-0}

case "$candidate_engine" in
  agda-baseline|nbe) ;;
  *)
    echo "Unknown differential candidate engine: $candidate_engine" >&2
    exit 2
    ;;
esac

if [ ! -d "$baseline_root" ]; then
  echo "Baseline formal evidence is unavailable: $baseline_root" >&2
  exit 2
fi
if [ ! -d "$candidate_root" ]; then
  echo "Candidate formal evidence is unavailable: $candidate_root" >&2
  echo "Generate it with FORMAL_TRANSPORT_ENGINE=$candidate_engine make verify-formal-transport" >&2
  exit 2
fi

baseline_root=$(CDPATH= cd -- "$baseline_root" && pwd -P)
candidate_root=$(CDPATH= cd -- "$candidate_root" && pwd -P)
if { [ "$baseline_root" = "$candidate_root" ] || \
     [ "$candidate_engine" = agda-baseline ]; } && \
   [ "$allow_self" != 1 ]
then
  echo "Refusing to report a baseline self-comparison as an NbE differential result" >&2
  exit 2
fi

if [ "$baseline_root" = "$candidate_root" ]; then
  result_name=self-check
  result_status=SELF-CHECK-PASS
else
  result_name=$candidate_engine
  result_status=DIFFERENTIAL-PASS
fi

evidence_dir="$build_dir/formal-transport-differential/$result_name"
mkdir -p "$evidence_dir"
comparison_summary="$evidence_dir/summary.tsv"
printf 'group\tbaseline_engine\tcandidate_engine\trows\tstatus\n' \
  > "$comparison_summary"

temporary_dir=$(mktemp -d /private/tmp/formal-transport-differential.XXXXXX)
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

read_invocation_value() {
  invocation_file=$1
  invocation_key=$2
  awk -F '\t' -v key="$invocation_key" \
    '$1 == key { print $2; found=1; exit }
     END { if (!found) exit 1 }' "$invocation_file"
}

verify_engine_evidence() {
  engine_root=$1
  engine_group=$2
  expected_engine=$3
  invocation_file="$engine_root/$engine_group/invocation.tsv"
  actual_engine=$(read_invocation_value "$invocation_file" engine 2>/dev/null || true)
  if [ -n "$actual_engine" ]; then
    if [ "$actual_engine" != "$expected_engine" ]; then
      echo "$engine_group evidence declares engine $actual_engine, expected $expected_engine" >&2
      exit 1
    fi
    return
  fi

  staging_engines="$temporary_dir/$engine_group.$expected_engine.engines"
  find "$engine_root/$engine_group" -type f -name staging.txt \
    -exec awk -F ': ' '$1 == "engine" { print $2 }' {} \; | \
    LC_ALL=C sort -u > "$staging_engines"
  if [ "$(wc -l < "$staging_engines" | tr -d ' ')" -ne 1 ] || \
     ! grep -Fqx "$expected_engine" "$staging_engines"
  then
    echo "$engine_group evidence does not consistently identify engine $expected_engine" >&2
    exit 1
  fi
}

validate_summary() {
  input_summary=$1
  expected_rows=$2
  awk -F '\t' -v expected_rows="$expected_rows" '
    NR == 1 {
      if ($0 != "scenario\tentry\texpected\tactual\tstatus\treal_seconds\tmax_rss_bytes") exit 2
      next
    }
    {
      if (NF != 7 || seen[$1]++) exit 3
      if ($5 != "PASS" && $5 != "EXPECTED-RESIDUAL" && $5 != "EXPECTED-REJECT") exit 4
      rows++
    }
    END { if (rows != expected_rows) exit 5 }
  ' "$input_summary"
}

write_binding_contract() {
  engine_root=$1
  engine_group=$2
  expected_rows=$3
  output_contract=$4
  require_native=$5
  binding_file="$engine_root/$engine_group/binding-time.tsv"

  if [ -s "$binding_file" ]; then
    awk -F '\t' -v expected_rows="$expected_rows" '
      NR == 1 {
        if ($0 != "scenario\tbinding_time\treason\taction") exit 2
        print
        next
      }
      {
        if (NF != 4 || seen[$1]++) exit 3
        if ($2 != "static" && $2 != "dynamic" && $2 != "mixed" && $2 != "unsupported") exit 4
        print
        rows++
      }
      END { if (rows != expected_rows) exit 5 }
    ' "$binding_file" > "$output_contract"
    return
  fi

  if [ "$require_native" = 1 ]; then
    echo "$engine_group candidate evidence is missing binding-time.tsv" >&2
    exit 2
  fi

  # Legacy oracle evidence predates the four-way classifier. Its completed
  # matrix has only static PASS rows and whole-entry dynamic residual/protocol
  # rows, so it can be migrated deterministically. Candidate evidence may not
  # use this fallback.
  awk -F '\t' '
    BEGIN { print "scenario\tbinding_time\treason\taction" }
    NR == 1 { next }
    $5 == "PASS" {
      print $1 "\tstatic\tno-runtime-blockers\terase-types-and-emit"
      next
    }
    $5 == "EXPECTED-RESIDUAL" || $5 == "EXPECTED-REJECT" {
      print $1 "\tdynamic\twhole-entry-runtime-head\ttyped-residual-whole-entry"
      next
    }
    { exit 2 }
  ' "$engine_root/$engine_group/summary.tsv" > "$output_contract"
}

groups='base glue int core boundary hit higher monolithic'
for group in $groups
do
  case "$group" in
    base|glue) expected_rows=3 ;;
    int|core|boundary) expected_rows=2 ;;
    hit) expected_rows=4 ;;
    higher) expected_rows=5 ;;
    monolithic) expected_rows=21 ;;
  esac

  baseline_group="$baseline_root/$group"
  candidate_group="$candidate_root/$group"
  for required_file in summary.tsv fragments.tsv source.sha256 invocation.tsv
  do
    if [ ! -s "$baseline_group/$required_file" ] || \
       [ ! -s "$candidate_group/$required_file" ]
    then
      echo "$group is missing required differential evidence: $required_file" >&2
      exit 2
    fi
  done

  validate_summary "$baseline_group/summary.tsv" "$expected_rows"
  validate_summary "$candidate_group/summary.tsv" "$expected_rows"
  verify_engine_evidence "$baseline_root" "$group" agda-baseline
  verify_engine_evidence "$candidate_root" "$group" "$candidate_engine"

  baseline_contract="$temporary_dir/$group.baseline.contract"
  candidate_contract="$temporary_dir/$group.candidate.contract"
  cut -f1-5 "$baseline_group/summary.tsv" > "$baseline_contract"
  cut -f1-5 "$candidate_group/summary.tsv" > "$candidate_contract"
  if ! cmp -s "$baseline_contract" "$candidate_contract"; then
    diff -u "$baseline_contract" "$candidate_contract" \
      > "$evidence_dir/$group.contract.diff" || true
    echo "$group differs from the agda-baseline functional contract" >&2
    echo "Diff: $evidence_dir/$group.contract.diff" >&2
    exit 1
  fi

  baseline_binding="$temporary_dir/$group.baseline.binding"
  candidate_binding="$temporary_dir/$group.candidate.binding"
  write_binding_contract "$baseline_root" "$group" "$expected_rows" \
    "$baseline_binding" 0
  require_candidate_binding=1
  if [ "$baseline_root" = "$candidate_root" ]; then
    require_candidate_binding=0
  fi
  write_binding_contract "$candidate_root" "$group" "$expected_rows" \
    "$candidate_binding" "$require_candidate_binding"
  if ! cmp -s "$baseline_binding" "$candidate_binding"; then
    diff -u "$baseline_binding" "$candidate_binding" \
      > "$evidence_dir/$group.binding-time.diff" || true
    echo "$group differs from the agda-baseline binding-time contract" >&2
    echo "Diff: $evidence_dir/$group.binding-time.diff" >&2
    exit 1
  fi

  if ! cmp -s "$baseline_group/fragments.tsv" "$candidate_group/fragments.tsv" || \
     ! cmp -s "$baseline_group/source.sha256" "$candidate_group/source.sha256"
  then
    echo "$group baseline and candidate did not use identical pinned inputs" >&2
    exit 1
  fi

  for input_key in source-sha256 projection-sha256 scenarios expectation
  do
    baseline_value=$(read_invocation_value "$baseline_group/invocation.tsv" "$input_key")
    candidate_value=$(read_invocation_value "$candidate_group/invocation.tsv" "$input_key")
    if [ "$baseline_value" != "$candidate_value" ]; then
      echo "$group invocation differs for $input_key" >&2
      exit 1
    fi
  done

  if [ "$group" = monolithic ]; then
    if [ ! -s "$baseline_group/prewarm.tsv" ] || \
       [ ! -s "$candidate_group/prewarm.tsv" ]
    then
      echo "Monolithic differential evidence is missing prewarm.tsv" >&2
      exit 2
    fi
    baseline_prewarm="$temporary_dir/monolithic.baseline.prewarm"
    candidate_prewarm="$temporary_dir/monolithic.candidate.prewarm"
    cut -f1-2 "$baseline_group/prewarm.tsv" > "$baseline_prewarm"
    cut -f1-2 "$candidate_group/prewarm.tsv" > "$candidate_prewarm"
    if ! cmp -s "$baseline_prewarm" "$candidate_prewarm"; then
      echo "Monolithic baseline and candidate prewarm contracts differ" >&2
      exit 1
    fi
  fi

  printf '%s\tagda-baseline\t%s\t%s\t%s\n' \
    "$group" "$candidate_engine" "$expected_rows" "$result_status" \
    >> "$comparison_summary"
done

printf 'baseline-root\t%s\ncandidate-root\t%s\nbaseline-engine\tagda-baseline\ncandidate-engine\t%s\nmode\t%s\n' \
  "$baseline_root" "$candidate_root" "$candidate_engine" "$result_name" \
  > "$evidence_dir/invocation.tsv"

echo "Formal Transport differential $result_status ($candidate_engine)"
echo "Evidence: $comparison_summary"
