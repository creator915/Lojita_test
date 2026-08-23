#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile=${PERFORMANCE_PROFILE:-$backend_dir/config/nbe-performance-profile.tsv}
raw_root=${PERFORMANCE_RUNS_ROOT:-$backend_dir/build/agda29/formal-transport-performance/raw}
result_dir=${PERFORMANCE_RESULT_DIR:-$backend_dir/build/agda29/formal-transport-performance}
candidate_engine=${STAGE_PERFORMANCE_CANDIDATE_ENGINE:-nbe}
groups='base glue int core boundary hit higher monolithic'
stages='agda-frontend-module-loading engine-total nbe-evaluation nbe-readback engine-result-admission internal-semantic-audit treeless-conversion residualization scheme-codegen-publication chez-execution typed-residual-consumer-execution'

[ -f "$profile" ] && [ -d "$raw_root" ] || {
  echo "Stage performance profile or raw evidence is unavailable" >&2
  exit 2
}
required_runs=$(awk -F '\t' '$1 == "required-runs" { print $2; found=1; exit }
  END { if (!found) exit 1 }' "$profile")
printf '%s\n' "$required_runs" | grep -Eq '^[1-9][0-9]*$' || {
  echo "Stage performance required-runs is invalid" >&2
  exit 2
}

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/formal-stage-performance.XXXXXX")
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$result_dir"
comparisons="$result_dir/stage-comparisons.tsv"
run_stages="$result_dir/stage-runs.tsv"
summary="$result_dir/stage-summary.tsv"
printf 'run\tgroup\tscenario\tstage\tbaseline_seconds\tcandidate_seconds\tbaseline_status\tcandidate_status\tratio\n' > "$comparisons"
printf 'run\tstage\tbaseline_measured_count\tcandidate_measured_count\tbaseline_total_seconds\tcandidate_total_seconds\tratio\tcomparison\n' > "$run_stages"

normalize_stage_file() {
  group=$1
  input=$2
  output=$3
  if ! awk -F '\t' -v group="$group" '
    NR == 1 {
      if ($0 != "scenario\tstage\telapsed_seconds\tstatus") exit 2
      next
    }
    NF != 4 || seen[$1 SUBSEP $2]++ { exit 3 }
    ($4 == "measured" || $4 == "derived-remainder") &&
      $3 !~ /^[0-9]+([.][0-9]+)?$/ { exit 4 }
    $4 == "not-applicable" && $3 != "-" { exit 5 }
    $4 != "measured" && $4 != "derived-remainder" &&
      $4 != "not-applicable" { exit 6 }
    { print group "\t" $1 "\t" $2 "\t" $3 "\t" $4 }
    END { if (NR < 2) exit 7 }
  ' "$input" | LC_ALL=C sort > "$output"
  then
    echo "Malformed stage performance input: $input" >&2
    exit 1
  fi
}

run_count=0
for run_dir in "$raw_root"/run-*
do
  [ -d "$run_dir" ] || continue
  run_count=$((run_count + 1))
  run_name=$(basename "$run_dir")
  baseline_all="$temporary_dir/$run_name.baseline.tsv"
  candidate_all="$temporary_dir/$run_name.candidate.tsv"
  : > "$baseline_all"
  : > "$candidate_all"
  for group in $groups
  do
    baseline_file="$run_dir/agda-baseline/$group/stage-timings.tsv"
    candidate_file="$run_dir/$candidate_engine/$group/stage-timings.tsv"
    [ -s "$baseline_file" ] && [ -s "$candidate_file" ] || {
      echo "$run_name/$group is missing baseline or candidate stage timings" >&2
      exit 2
    }
    normalize_stage_file "$group" "$baseline_file" \
      "$temporary_dir/$run_name.$group.baseline.tsv"
    normalize_stage_file "$group" "$candidate_file" \
      "$temporary_dir/$run_name.$group.candidate.tsv"
    cat "$temporary_dir/$run_name.$group.baseline.tsv" >> "$baseline_all"
    cat "$temporary_dir/$run_name.$group.candidate.tsv" >> "$candidate_all"
  done
  LC_ALL=C sort "$baseline_all" > "$baseline_all.sorted"
  LC_ALL=C sort "$candidate_all" > "$candidate_all.sorted"
  mv "$baseline_all.sorted" "$baseline_all"
  mv "$candidate_all.sorted" "$candidate_all"
  if [ "$(wc -l < "$baseline_all" | tr -d ' ')" -ne \
       "$(wc -l < "$candidate_all" | tr -d ' ')" ]; then
    echo "$run_name stage timing row counts differ" >&2
    exit 1
  fi

  run_comparisons="$temporary_dir/$run_name.comparisons.tsv"
  if ! paste "$baseline_all" "$candidate_all" | awk -F '\t' -v run="$run_name" '
    $1 != $6 || $2 != $7 || $3 != $8 { exit 2 }
    {
      baseline=$4; candidate=$9
      ratio="-"
      if (baseline != "-" && candidate != "-" && baseline + 0 > 0)
        ratio=sprintf("%.6f", candidate / baseline)
      print run "\t" $1 "\t" $2 "\t" $3 "\t" baseline "\t" candidate "\t" $5 "\t" $10 "\t" ratio
    }
  ' > "$run_comparisons"
  then
    echo "$run_name baseline/candidate stage keys differ" >&2
    exit 1
  fi
  cat "$run_comparisons" >> "$comparisons"

  for stage in $stages
  do
    stage_metrics=$(awk -F '\t' -v stage="$stage" '
      $4 == stage {
        rows++
        if ($5 != "-") { bc++; bt += $5 }
        if ($6 != "-") { cc++; ct += $6 }
      }
      END {
        if (rows == 0) exit 2
        ratio = bc > 0 && cc == bc && bt > 0 ? sprintf("%.6f", ct/bt) : "-"
        if (bc > 0 && cc == bc) comparison="comparable"
        else if (bc == 0 && cc > 0) comparison="candidate-only"
        else if (bc == 0 && cc == 0) comparison="not-applicable"
        else comparison="mismatched"
        printf "%d\t%d\t%.9f\t%.9f\t%s\t%s", bc,cc,bt,ct,ratio,comparison
      }
    ' "$run_comparisons")
    if printf '%s\n' "$stage_metrics" | grep -Fq 'mismatched'; then
      echo "$run_name/$stage has mismatched applicability" >&2
      exit 1
    fi
    printf '%s\t%s\t%s\n' "$run_name" "$stage" "$stage_metrics" >> "$run_stages"
  done
done

[ "$run_count" -eq "$required_runs" ] || {
  echo "Stage performance evidence has $run_count runs; expected $required_runs" >&2
  exit 2
}

value_at_rank() {
  values_file=$1
  rank=$2
  LC_ALL=C sort -n "$values_file" | sed -n "${rank}p"
}

printf 'stage\truns\tbaseline_measured_per_run\tcandidate_measured_per_run\tbaseline_median_total_seconds\tcandidate_median_total_seconds\tmedian_total_ratio\tcomparison\n' > "$summary"
median_rank=$(( (required_runs + 1) / 2 ))
for stage in $stages
do
  stage_rows="$temporary_dir/$stage.rows.tsv"
  awk -F '\t' -v stage="$stage" '$2 == stage { print }' "$run_stages" > "$stage_rows"
  [ "$(wc -l < "$stage_rows" | tr -d ' ')" -eq "$required_runs" ] || {
    echo "$stage is missing per-run stage totals" >&2
    exit 1
  }
  baseline_counts=$(cut -f3 "$stage_rows" | LC_ALL=C sort -u)
  candidate_counts=$(cut -f4 "$stage_rows" | LC_ALL=C sort -u)
  comparison=$(cut -f8 "$stage_rows" | LC_ALL=C sort -u)
  [ "$(printf '%s\n' "$baseline_counts" | wc -l | tr -d ' ')" -eq 1 ] && \
  [ "$(printf '%s\n' "$candidate_counts" | wc -l | tr -d ' ')" -eq 1 ] && \
  [ "$(printf '%s\n' "$comparison" | wc -l | tr -d ' ')" -eq 1 ] || {
    echo "$stage applicability changed across runs" >&2
    exit 1
  }
  baseline_values="$temporary_dir/$stage.baseline-values"
  candidate_values="$temporary_dir/$stage.candidate-values"
  cut -f5 "$stage_rows" > "$baseline_values"
  cut -f6 "$stage_rows" > "$candidate_values"
  baseline_median=$(value_at_rank "$baseline_values" "$median_rank")
  candidate_median=$(value_at_rank "$candidate_values" "$median_rank")
  median_ratio=$(awk -v b="$baseline_median" -v c="$candidate_median" \
    'BEGIN { if (b > 0) printf "%.6f", c/b; else printf "-" }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$stage" "$required_runs" "$baseline_counts" "$candidate_counts" \
    "$baseline_median" "$candidate_median" "$median_ratio" "$comparison" \
    >> "$summary"
done

echo "Formal stage performance STAGE-PERFORMANCE-PASS ($required_runs runs)"
echo "Evidence: $summary"
