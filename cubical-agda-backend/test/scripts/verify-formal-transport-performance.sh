#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile=${PERFORMANCE_PROFILE:-"$backend_dir/config/nbe-performance-profile.tsv"}
host_profile=${PERFORMANCE_HOST_PROFILE:-"$backend_dir/config/nbe-performance-host-profile.tsv"}
raw_root=${PERFORMANCE_RUNS_ROOT:-"$backend_dir/build/agda29/formal-transport-performance/raw"}
result_dir=${PERFORMANCE_RESULT_DIR:-"$backend_dir/build/agda29/formal-transport-performance"}

if [ ! -f "$profile" ] || [ ! -f "$host_profile" ] || \
   [ ! -d "$raw_root" ]; then
  echo "Performance profile, host profile, or raw run root is unavailable" >&2
  exit 2
fi

temporary_dir=$(mktemp -d /private/tmp/formal-transport-performance.XXXXXX)
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! awk -F '\t' '
  BEGIN {
    allowed["schema"]=1
    allowed["status"]=1
    allowed["profile"]=1
    allowed["benchmark-variant"]=1
    allowed["result-name"]=1
    allowed["ghc-optimization"]=1
    allowed["candidate-engine"]=1
    allowed["required-runs"]=1
    allowed["group-timeout-seconds"]=1
    allowed["case-timeout-seconds"]=1
    allowed["aggregate-max-time-ratio"]=1
    allowed["static-max-time-ratio"]=1
    allowed["residual-max-time-ratio"]=1
    allowed["group-max-time-ratio"]=1
    allowed["prewarm-max-time-ratio"]=1
    allowed["aggregate-max-rss-ratio"]=1
    allowed["static-max-rss-ratio"]=1
    allowed["residual-max-rss-ratio"]=1
    allowed["group-max-rss-ratio"]=1
    allowed["prewarm-max-rss-ratio"]=1
    allowed["aggregate-max-allocation-ratio"]=1
    allowed["static-max-allocation-ratio"]=1
    allowed["residual-max-allocation-ratio"]=1
    allowed["group-max-allocation-ratio"]=1
    allowed["scheme-artifact-max-size-ratio"]=1
    allowed["packet-artifact-max-size-ratio"]=1
  }
  NR == 1 { if ($0 != "key\tvalue") exit 2; next }
  NF != 2 || !allowed[$1] || seen[$1]++ || $2 == "" { exit 3 }
  { count++ }
  END { if (count != 26) exit 4 }
' "$profile"
then
  echo "Invalid NbE performance profile schema" >&2
  exit 2
fi

profile_value() {
  awk -F '\t' -v key="$1" '$1 == key { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$profile"
}

schema=$(profile_value schema)
profile_status=$(profile_value status)
profile_name=$(profile_value profile)
benchmark_variant=$(profile_value benchmark-variant)
result_name=$(profile_value result-name)
ghc_optimization=$(profile_value ghc-optimization)
candidate_engine=$(profile_value candidate-engine)
required_runs=$(profile_value required-runs)
group_timeout=$(profile_value group-timeout-seconds)
case_timeout=$(profile_value case-timeout-seconds)
aggregate_time_threshold=$(profile_value aggregate-max-time-ratio)
static_time_threshold=$(profile_value static-max-time-ratio)
residual_time_threshold=$(profile_value residual-max-time-ratio)
group_time_threshold=$(profile_value group-max-time-ratio)
prewarm_time_threshold=$(profile_value prewarm-max-time-ratio)
aggregate_rss_threshold=$(profile_value aggregate-max-rss-ratio)
static_rss_threshold=$(profile_value static-max-rss-ratio)
residual_rss_threshold=$(profile_value residual-max-rss-ratio)
group_rss_threshold=$(profile_value group-max-rss-ratio)
prewarm_rss_threshold=$(profile_value prewarm-max-rss-ratio)
aggregate_allocation_threshold=$(profile_value aggregate-max-allocation-ratio)
static_allocation_threshold=$(profile_value static-max-allocation-ratio)
residual_allocation_threshold=$(profile_value residual-max-allocation-ratio)
group_allocation_threshold=$(profile_value group-max-allocation-ratio)
scheme_size_threshold=$(profile_value scheme-artifact-max-size-ratio)
packet_size_threshold=$(profile_value packet-artifact-max-size-ratio)
process_snapshot_count=$(awk -F '\t' \
  '$1 == "process-snapshot-count" { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$host_profile")

if [ "$schema" != 3 ] || [ "$profile_status" != engineering-provisional ] || \
   [ "$candidate_engine" != nbe ] || \
   ! awk -v runs="$required_runs" -v group_timeout="$group_timeout" \
     -v case_timeout="$case_timeout" \
     'BEGIN { exit !(runs ~ /^[1-9][0-9]*$/ && group_timeout ~ /^[1-9][0-9]*$/ &&
                     case_timeout ~ /^[1-9][0-9]*$/) }' || \
   ! awk -v a="$aggregate_time_threshold" -v s="$static_time_threshold" \
     -v r="$residual_time_threshold" -v g="$group_time_threshold" \
     -v p="$prewarm_time_threshold" -v ar="$aggregate_rss_threshold" \
     -v sr="$static_rss_threshold" -v rr="$residual_rss_threshold" \
     -v gr="$group_rss_threshold" -v pr="$prewarm_rss_threshold" \
     -v aa="$aggregate_allocation_threshold" \
     -v sa="$static_allocation_threshold" \
     -v ra="$residual_allocation_threshold" \
     -v ga="$group_allocation_threshold" \
     -v ss="$scheme_size_threshold" -v ps="$packet_size_threshold" \
     'BEGIN { exit !(a+0>0 && s+0>0 && r+0>0 && g+0>0 && p+0>0 &&
                     ar+0>0 && sr+0>0 && rr+0>0 && gr+0>0 && pr+0>0 &&
                     aa+0>0 && sa+0>0 && ra+0>0 && ga+0>0 &&
                     ss+0>0 && ps+0>0) }'
then
  echo "Invalid NbE performance profile values" >&2
  exit 2
fi
case "$benchmark_variant:$result_name:$ghc_optimization" in
  engineering-o0:formal-transport-performance:O0|\
  release-o2:formal-transport-performance-release:O2) ;;
  *)
    echo "Invalid benchmark variant, result name, or GHC optimization pairing" >&2
    exit 2
    ;;
esac
printf '%s\n' "$process_snapshot_count" | grep -Eq '^[1-9][0-9]*$' || {
  echo "Invalid performance host snapshot policy" >&2
  exit 2
}

mkdir -p "$result_dir"
samples="$temporary_dir/samples.tsv"
artifacts="$result_dir/artifacts.tsv"
printf 'scope\trun\tbaseline_seconds\tcandidate_seconds\ttime_ratio\tbaseline_peak_rss\tcandidate_peak_rss\trss_ratio\tbaseline_allocated_bytes\tcandidate_allocated_bytes\tallocation_ratio\n' > "$samples"
printf 'run\tkind\tbaseline_count\tcandidate_count\tbaseline_bytes\tcandidate_bytes\tsize_ratio\tthreshold\tstatus\n' > "$artifacts"

groups='base glue int core boundary hit higher monolithic'
run_count=0

read_invocation_engine() {
  awk -F '\t' '$1 == "engine" { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$1"
}

read_invocation_optimization() {
  awk -F '\t' '$1 == "ghc-optimization" { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$1"
}

measure_artifacts() {
  artifact_root=$1
  artifact_name=$2
  artifact_list="$temporary_dir/artifact-list.$$.txt"
  : > "$artifact_list"
  for artifact_group in $groups
  do
    find "$artifact_root/$artifact_group" -type f -name "$artifact_name" \
      -print >> "$artifact_list"
  done
  artifact_count=0
  artifact_bytes=0
  while IFS= read -r artifact_file
  do
    [ -n "$artifact_file" ] || continue
    artifact_count=$((artifact_count + 1))
    current_bytes=$(wc -c < "$artifact_file" | tr -d ' ')
    artifact_bytes=$((artifact_bytes + current_bytes))
  done < "$artifact_list"
  rm -f "$artifact_list"
  printf '%s %s\n' "$artifact_count" "$artifact_bytes"
}

for run_dir in "$raw_root"/run-*
do
  [ -d "$run_dir" ] || continue
  run_count=$((run_count + 1))
  run_name=$(basename "$run_dir")
  baseline_root="$run_dir/agda-baseline"
  candidate_root="$run_dir/$candidate_engine"
  if [ ! -d "$baseline_root" ] || [ ! -d "$candidate_root" ]; then
    echo "$run_name is missing baseline or candidate evidence" >&2
    exit 2
  fi

  run_groups="$temporary_dir/$run_name.groups.tsv"
  : > "$run_groups"
  for group in $groups
  do
    baseline_group="$baseline_root/$group"
    candidate_group="$candidate_root/$group"
    for required_file in summary.tsv binding-time.tsv invocation.tsv source.sha256 fragments.tsv \
      allocations.tsv host-preflight.tsv background-processes.tsv
    do
      if [ ! -s "$baseline_group/$required_file" ] || \
         [ ! -s "$candidate_group/$required_file" ]; then
        echo "$run_name/$group is missing $required_file" >&2
        exit 2
      fi
    done
    if ! PERFORMANCE_HOST_PROFILE="$host_profile" \
         PERFORMANCE_HOST_FACTS="$baseline_group/host-preflight.tsv" \
           sh "$script_dir/verify-formal-transport-performance-host.sh" \
           >/dev/null || \
       ! PERFORMANCE_HOST_PROFILE="$host_profile" \
         PERFORMANCE_HOST_FACTS="$candidate_group/host-preflight.tsv" \
           sh "$script_dir/verify-formal-transport-performance-host.sh" \
           >/dev/null
    then
      echo "$run_name/$group has invalid host preflight evidence" >&2
      exit 1
    fi
    for process_file in "$baseline_group/background-processes.tsv" \
      "$candidate_group/background-processes.tsv"
    do
      if ! awk -F '\t' -v expected="$process_snapshot_count" '
        NR == 1 {
          if ($0 != "pid\tcpu_percent\trss_kib\tcommand") exit 2
          next
        }
        NF != 4 || $1 !~ /^[0-9]+$/ ||
          $2 !~ /^[0-9]+([.][0-9]+)?$/ || $3 !~ /^[0-9]+$/ || $4 == "" {
          exit 3
        }
        { count++ }
        END { if (count != expected) exit 4 }
      ' "$process_file"
      then
        echo "$run_name/$group has invalid background process evidence" >&2
        exit 1
      fi
    done
    baseline_engine=$(read_invocation_engine "$baseline_group/invocation.tsv")
    actual_candidate_engine=$(read_invocation_engine "$candidate_group/invocation.tsv")
    baseline_optimization=$(read_invocation_optimization \
      "$baseline_group/invocation.tsv")
    candidate_optimization=$(read_invocation_optimization \
      "$candidate_group/invocation.tsv")
    if [ "$baseline_engine" != agda-baseline ] || \
       [ "$actual_candidate_engine" != "$candidate_engine" ] || \
       [ "$baseline_optimization" != "$ghc_optimization" ] || \
       [ "$candidate_optimization" != "$ghc_optimization" ]; then
      echo "$run_name/$group has invalid engine or optimization provenance" >&2
      exit 1
    fi
    if ! cmp -s "$baseline_group/source.sha256" "$candidate_group/source.sha256" || \
       ! cmp -s "$baseline_group/fragments.tsv" "$candidate_group/fragments.tsv" || \
       ! cmp -s "$baseline_group/binding-time.tsv" "$candidate_group/binding-time.tsv"; then
      echo "$run_name/$group does not share the functional input/binding contract" >&2
      exit 1
    fi
    baseline_contract="$temporary_dir/$run_name.$group.baseline.contract"
    candidate_contract="$temporary_dir/$run_name.$group.candidate.contract"
    cut -f1-5 "$baseline_group/summary.tsv" > "$baseline_contract"
    cut -f1-5 "$candidate_group/summary.tsv" > "$candidate_contract"
    if ! cmp -s "$baseline_contract" "$candidate_contract"; then
      echo "$run_name/$group differs from the functional baseline" >&2
      exit 1
    fi
    if ! awk -F '\t' -v timeout="$case_timeout" '
      NR == 1 {
        if ($0 != "scenario\tentry\texpected\tactual\tstatus\treal_seconds\tmax_rss_bytes") exit 2
        next
      }
      NF != 7 || seen[$1]++ { exit 3 }
      $6 != "-" && ($6 !~ /^[0-9]+([.][0-9]+)?$/ || $6 + 0 > timeout) { exit 4 }
      $7 != "-" && $7 !~ /^[0-9]+$/ { exit 5 }
    ' "$baseline_group/summary.tsv" || \
       ! awk -F '\t' -v timeout="$case_timeout" '
      NR == 1 { next }
      NF != 7 || seen[$1]++ { exit 3 }
      $6 != "-" && ($6 !~ /^[0-9]+([.][0-9]+)?$/ || $6 + 0 > timeout) { exit 4 }
      $7 != "-" && $7 !~ /^[0-9]+$/ { exit 5 }
    ' "$candidate_group/summary.tsv"
    then
      echo "$run_name/$group contains invalid or timed-out case metrics" >&2
      exit 1
    fi

    for allocation_file in "$baseline_group/allocations.tsv" \
      "$candidate_group/allocations.tsv"
    do
      if ! awk -F '\t' '
        NR == 1 {
          if ($0 != "scenario\tallocated_bytes\tgc_copied_bytes\tmaximum_residency_bytes\tstatus") exit 2
          next
        }
        NF != 5 || seen[$1]++ || $2 !~ /^[0-9]+$/ || $2 + 0 <= 0 ||
          $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $4 + 0 <= 0 ||
          $5 != "MEASURED" { exit 3 }
        { count++ }
        END { if (count == 0) exit 4 }
      ' "$allocation_file"
      then
        echo "$run_name/$group contains invalid allocation evidence" >&2
        exit 1
      fi
    done

    baseline_metrics="$temporary_dir/$run_name.$group.baseline.metrics"
    candidate_metrics="$temporary_dir/$run_name.$group.candidate.metrics"
    tail -n +2 "$baseline_group/summary.tsv" | cut -f1,6,7 > "$baseline_metrics"
    tail -n +2 "$candidate_group/summary.tsv" | cut -f1,6,7 > "$candidate_metrics"
    group_metrics=$(paste "$baseline_metrics" "$candidate_metrics" | \
      awk -F '\t' '
        $1 != $4 { exit 2 }
        $2 != "-" {
          if ($2 + 0 <= 0 || $5 + 0 <= 0 || $3 + 0 <= 0 || $6 + 0 <= 0) exit 3
          bt += $2; ct += $5
          if ($3 > br) br=$3
          if ($6 > cr) cr=$6
          rows++
        }
        END {
          if (rows == 0) exit 4
          printf "%.6f\t%.6f\t%.6f\t%d\t%d\t%.6f", bt,ct,ct/bt,br,cr,cr/br
        }')
    baseline_allocations="$temporary_dir/$run_name.$group.baseline.allocations"
    candidate_allocations="$temporary_dir/$run_name.$group.candidate.allocations"
    tail -n +2 "$baseline_group/allocations.tsv" | cut -f1,2 \
      > "$baseline_allocations"
    tail -n +2 "$candidate_group/allocations.tsv" | cut -f1,2 \
      > "$candidate_allocations"
    allocation_metrics=$(paste "$baseline_allocations" "$candidate_allocations" | \
      awk -F '\t' '
        $1 != $3 || $2 + 0 <= 0 || $4 + 0 <= 0 { exit 2 }
        { baseline += $2; candidate += $4; rows++ }
        END {
          if (rows == 0) exit 3
          printf "%.0f\t%.0f\t%.6f", baseline,candidate,candidate/baseline
        }')
    printf '%s\t%s\t%s\t%s\n' "$group" "$run_name" "$group_metrics" \
      "$allocation_metrics" >> "$samples"
    printf '%s\t%s\t%s\n' "$group" "$group_metrics" \
      "$allocation_metrics" >> "$run_groups"
  done

  for combined_scope in static-projections residual-projections overall
  do
    case "$combined_scope" in
      static-projections) selected='base|glue|int|core|hit' ;;
      residual-projections) selected='boundary|higher' ;;
      overall) selected='base|glue|int|core|boundary|hit|higher|monolithic' ;;
    esac
    combined_metrics=$(awk -F '\t' -v selected="$selected" '
      $1 ~ "^(" selected ")$" {
        bt += $2; ct += $3
        if ($5 > br) br=$5
        if ($6 > cr) cr=$6
        ba += $8; ca += $9
        rows++
      }
      END {
        if (rows == 0) exit 2
        printf "%.6f\t%.6f\t%.6f\t%d\t%d\t%.6f\t%.0f\t%.0f\t%.6f", bt,ct,ct/bt,br,cr,cr/br,ba,ca,ca/ba
      }' "$run_groups")
    printf '%s\t%s\t%s\n' "$combined_scope" "$run_name" "$combined_metrics" >> "$samples"
  done

  baseline_prewarm="$baseline_root/monolithic/prewarm.tsv"
  candidate_prewarm="$candidate_root/monolithic/prewarm.tsv"
  baseline_prewarm_contract="$temporary_dir/$run_name.baseline.prewarm.contract"
  candidate_prewarm_contract="$temporary_dir/$run_name.candidate.prewarm.contract"
  cut -f1-2 "$baseline_prewarm" > "$baseline_prewarm_contract"
  cut -f1-2 "$candidate_prewarm" > "$candidate_prewarm_contract"
  if [ ! -s "$baseline_prewarm" ] || [ ! -s "$candidate_prewarm" ] || \
     ! cmp -s "$baseline_prewarm_contract" "$candidate_prewarm_contract"; then
    echo "$run_name prewarm contract is missing or mismatched" >&2
    exit 1
  fi
  baseline_prewarm_metrics="$temporary_dir/$run_name.baseline.prewarm.metrics"
  candidate_prewarm_metrics="$temporary_dir/$run_name.candidate.prewarm.metrics"
  tail -n +2 "$baseline_prewarm" | cut -f1,3,4 > "$baseline_prewarm_metrics"
  tail -n +2 "$candidate_prewarm" | cut -f1,3,4 > "$candidate_prewarm_metrics"
  prewarm_metrics=$(paste "$baseline_prewarm_metrics" "$candidate_prewarm_metrics" | \
    awk -F '\t' -v timeout="$case_timeout" '
      $1 != $4 || $2 + 0 <= 0 || $5 + 0 <= 0 || $3 + 0 <= 0 || $6 + 0 <= 0 ||
        $2 + 0 > timeout || $5 + 0 > timeout { exit 2 }
      { bt += $2; ct += $5; if ($3 > br) br=$3; if ($6 > cr) cr=$6; rows++ }
      END {
        if (rows != 8) exit 3
        printf "%.6f\t%.6f\t%.6f\t%d\t%d\t%.6f", bt,ct,ct/bt,br,cr,cr/br
      }')
  printf 'prewarm\t%s\t%s\t-\t-\t-\n' "$run_name" "$prewarm_metrics" >> "$samples"

  set -- $(measure_artifacts "$baseline_root" program.ss)
  baseline_scheme_count=$1
  baseline_scheme_bytes=$2
  set -- $(measure_artifacts "$candidate_root" program.ss)
  candidate_scheme_count=$1
  candidate_scheme_bytes=$2
  if [ "$baseline_scheme_count" -ne "$candidate_scheme_count" ] || \
     [ "$baseline_scheme_bytes" -le 0 ]; then
    echo "$run_name Scheme artifact inventory mismatch" >&2
    exit 1
  fi
  scheme_ratio=$(awk -v b="$baseline_scheme_bytes" -v c="$candidate_scheme_bytes" \
    'BEGIN { printf "%.6f", c/b }')
  scheme_status=$(awk -v ratio="$scheme_ratio" -v limit="$scheme_size_threshold" \
    'BEGIN { print (ratio <= limit ? "PASS" : "FAIL") }')
  printf '%s\tscheme\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$run_name" "$baseline_scheme_count" "$candidate_scheme_count" \
    "$baseline_scheme_bytes" "$candidate_scheme_bytes" "$scheme_ratio" \
    "$scheme_size_threshold" "$scheme_status" >> "$artifacts"

  set -- $(measure_artifacts "$baseline_root" typed-term.bin)
  baseline_packet_count=$1
  baseline_packet_bytes=$2
  set -- $(measure_artifacts "$candidate_root" typed-term.bin)
  candidate_packet_count=$1
  candidate_packet_bytes=$2
  if [ "$baseline_packet_count" -ne "$candidate_packet_count" ] || \
     [ "$baseline_packet_bytes" -le 0 ]; then
    echo "$run_name packet artifact inventory mismatch" >&2
    exit 1
  fi
  packet_ratio=$(awk -v b="$baseline_packet_bytes" -v c="$candidate_packet_bytes" \
    'BEGIN { printf "%.6f", c/b }')
  packet_status=$(awk -v ratio="$packet_ratio" -v limit="$packet_size_threshold" \
    'BEGIN { print (ratio <= limit ? "PASS" : "FAIL") }')
  printf '%s\tpacket\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$run_name" "$baseline_packet_count" "$candidate_packet_count" \
    "$baseline_packet_bytes" "$candidate_packet_bytes" "$packet_ratio" \
    "$packet_size_threshold" "$packet_status" >> "$artifacts"
done

if [ "$run_count" -ne "$required_runs" ]; then
  echo "Performance evidence has $run_count runs; profile requires $required_runs" >&2
  exit 2
fi

summary="$result_dir/summary.tsv"
printf 'scope\tsamples\tbaseline_median_seconds\tcandidate_median_seconds\ttime_ratio_median\ttime_ratio_p95\ttime_ratio_min\ttime_ratio_max\ttime_ratio_mad\tbaseline_peak_rss\tcandidate_peak_rss\trss_ratio_median\trss_ratio_p95\trss_ratio_min\trss_ratio_max\trss_ratio_mad\ttime_threshold\trss_threshold\tstatus\n' > "$summary"

value_at_rank() {
  values_file=$1
  rank=$2
  LC_ALL=C sort -n "$values_file" | sed -n "${rank}p"
}

write_scope_statistics() {
  scope=$1
  time_threshold=$2
  rss_threshold=$3
  scope_rows="$temporary_dir/$scope.rows.tsv"
  awk -F '\t' -v scope="$scope" '$1 == scope { print }' "$samples" > "$scope_rows"
  count=$(wc -l < "$scope_rows" | tr -d ' ')
  if [ "$count" -ne "$required_runs" ]; then
    echo "$scope has $count samples; expected $required_runs" >&2
    exit 2
  fi
  median_rank=$(( (count + 1) / 2 ))
  p95_rank=$(( (95 * count + 99) / 100 ))
  baseline_values="$temporary_dir/$scope.baseline"
  candidate_values="$temporary_dir/$scope.candidate"
  time_values="$temporary_dir/$scope.time-ratio"
  rss_values="$temporary_dir/$scope.rss-ratio"
  cut -f3 "$scope_rows" > "$baseline_values"
  cut -f4 "$scope_rows" > "$candidate_values"
  cut -f5 "$scope_rows" > "$time_values"
  cut -f8 "$scope_rows" > "$rss_values"
  baseline_median=$(value_at_rank "$baseline_values" "$median_rank")
  candidate_median=$(value_at_rank "$candidate_values" "$median_rank")
  time_median=$(value_at_rank "$time_values" "$median_rank")
  time_p95=$(value_at_rank "$time_values" "$p95_rank")
  time_min=$(value_at_rank "$time_values" 1)
  time_max=$(value_at_rank "$time_values" "$count")
  time_deviations="$temporary_dir/$scope.time-deviations"
  awk -v median="$time_median" '{ d=$1-median; if (d<0) d=-d; print d }' \
    "$time_values" > "$time_deviations"
  time_mad=$(value_at_rank "$time_deviations" "$median_rank")
  baseline_peak=$(LC_ALL=C sort -n "$scope_rows" | awk -F '\t' \
    '{ if ($6 > peak) peak=$6 } END { print peak + 0 }')
  candidate_peak=$(awk -F '\t' '{ if ($7 > peak) peak=$7 } END { print peak + 0 }' \
    "$scope_rows")
  rss_median=$(value_at_rank "$rss_values" "$median_rank")
  rss_p95=$(value_at_rank "$rss_values" "$p95_rank")
  rss_min=$(value_at_rank "$rss_values" 1)
  rss_max=$(value_at_rank "$rss_values" "$count")
  rss_deviations="$temporary_dir/$scope.rss-deviations"
  awk -v median="$rss_median" '{ d=$1-median; if (d<0) d=-d; print d }' \
    "$rss_values" > "$rss_deviations"
  rss_mad=$(value_at_rank "$rss_deviations" "$median_rank")
  status=$(awk -v t="$time_p95" -v tl="$time_threshold" \
    -v r="$rss_p95" -v rl="$rss_threshold" \
    'BEGIN { print (t <= tl && r <= rl ? "PASS" : "FAIL") }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$scope" "$count" "$baseline_median" "$candidate_median" \
    "$time_median" "$time_p95" "$time_min" "$time_max" "$time_mad" \
    "$baseline_peak" "$candidate_peak" "$rss_median" "$rss_p95" \
    "$rss_min" "$rss_max" "$rss_mad" "$time_threshold" "$rss_threshold" \
    "$status" >> "$summary"
}

for scope in base glue int core boundary hit higher monolithic
do
  write_scope_statistics "$scope" "$group_time_threshold" "$group_rss_threshold"
done
write_scope_statistics static-projections "$static_time_threshold" "$static_rss_threshold"
write_scope_statistics residual-projections "$residual_time_threshold" "$residual_rss_threshold"
write_scope_statistics overall "$aggregate_time_threshold" "$aggregate_rss_threshold"
write_scope_statistics prewarm "$prewarm_time_threshold" "$prewarm_rss_threshold"

allocation_summary="$result_dir/allocation-summary.tsv"
printf 'scope\tsamples\tbaseline_median_allocated_bytes\tcandidate_median_allocated_bytes\tallocation_ratio_median\tallocation_ratio_p95\tallocation_ratio_min\tallocation_ratio_max\tallocation_ratio_mad\tthreshold\tstatus\n' \
  > "$allocation_summary"

write_allocation_statistics() {
  allocation_scope=$1
  allocation_threshold=$2
  allocation_rows="$temporary_dir/$allocation_scope.allocation-rows.tsv"
  awk -F '\t' -v scope="$allocation_scope" '$1 == scope { print }' \
    "$samples" > "$allocation_rows"
  allocation_count=$(wc -l < "$allocation_rows" | tr -d ' ')
  if [ "$allocation_count" -ne "$required_runs" ]; then
    echo "$allocation_scope has $allocation_count allocation samples; expected $required_runs" >&2
    exit 2
  fi
  allocation_median_rank=$(( (allocation_count + 1) / 2 ))
  allocation_p95_rank=$(( (95 * allocation_count + 99) / 100 ))
  baseline_allocation_values="$temporary_dir/$allocation_scope.baseline-allocation"
  candidate_allocation_values="$temporary_dir/$allocation_scope.candidate-allocation"
  allocation_ratio_values="$temporary_dir/$allocation_scope.allocation-ratio"
  cut -f9 "$allocation_rows" > "$baseline_allocation_values"
  cut -f10 "$allocation_rows" > "$candidate_allocation_values"
  cut -f11 "$allocation_rows" > "$allocation_ratio_values"
  baseline_allocation_median=$(value_at_rank "$baseline_allocation_values" \
    "$allocation_median_rank")
  candidate_allocation_median=$(value_at_rank "$candidate_allocation_values" \
    "$allocation_median_rank")
  allocation_ratio_median=$(value_at_rank "$allocation_ratio_values" \
    "$allocation_median_rank")
  allocation_ratio_p95=$(value_at_rank "$allocation_ratio_values" \
    "$allocation_p95_rank")
  allocation_ratio_min=$(value_at_rank "$allocation_ratio_values" 1)
  allocation_ratio_max=$(value_at_rank "$allocation_ratio_values" \
    "$allocation_count")
  allocation_deviations="$temporary_dir/$allocation_scope.allocation-deviations"
  awk -v median="$allocation_ratio_median" \
    '{ d=$1-median; if (d<0) d=-d; print d }' \
    "$allocation_ratio_values" > "$allocation_deviations"
  allocation_ratio_mad=$(value_at_rank "$allocation_deviations" \
    "$allocation_median_rank")
  allocation_status=$(awk -v ratio="$allocation_ratio_p95" \
    -v limit="$allocation_threshold" \
    'BEGIN { print (ratio <= limit ? "PASS" : "FAIL") }')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$allocation_scope" "$allocation_count" \
    "$baseline_allocation_median" "$candidate_allocation_median" \
    "$allocation_ratio_median" "$allocation_ratio_p95" \
    "$allocation_ratio_min" "$allocation_ratio_max" \
    "$allocation_ratio_mad" "$allocation_threshold" "$allocation_status" \
    >> "$allocation_summary"
}

for allocation_scope in base glue int core boundary hit higher monolithic
do
  write_allocation_statistics "$allocation_scope" \
    "$group_allocation_threshold"
done
write_allocation_statistics static-projections "$static_allocation_threshold"
write_allocation_statistics residual-projections "$residual_allocation_threshold"
write_allocation_statistics overall "$aggregate_allocation_threshold"

cp "$profile" "$result_dir/profile.tsv"
cp "$host_profile" "$result_dir/host-profile.tsv"
cp "$samples" "$result_dir/samples.tsv"
profile_sha256=$(shasum -a 256 "$profile" | awk '{ print $1 }')
host_profile_sha256=$(shasum -a 256 "$host_profile" | awk '{ print $1 }')
performance_result=ENGINEERING-PERFORMANCE-PASS
if awk -F '\t' '$19 == "FAIL" { found=1 } END { exit !found }' "$summary" || \
   awk -F '\t' '$9 == "FAIL" { found=1 } END { exit !found }' "$artifacts" || \
   awk -F '\t' '$11 == "FAIL" { found=1 } END { exit !found }' \
     "$allocation_summary"; then
  performance_result=ENGINEERING-PERFORMANCE-FAIL
fi
printf 'profile\t%s\nprofile-status\t%s\nbenchmark-variant\t%s\nresult-name\t%s\nghc-optimization\t%s\nprofile-sha256\t%s\nhost-profile\tformal-transport-host-v1\nhost-profile-sha256\t%s\nhost-control\tHOST-PASS\nallocation-metrics\tghc-rts-s-v1\nruns\t%s\ncandidate-engine\t%s\ngroup-timeout-seconds\t%s\ncase-timeout-seconds\t%s\nresult\t%s\n' \
  "$profile_name" "$profile_status" "$benchmark_variant" "$result_name" \
  "$ghc_optimization" "$profile_sha256" \
  "$host_profile_sha256" "$required_runs" \
  "$candidate_engine" "$group_timeout" "$case_timeout" \
  "$performance_result" \
  > "$result_dir/invocation.tsv"

if [ "$performance_result" = ENGINEERING-PERFORMANCE-FAIL ]; then
  echo "NbE production candidate performance threshold failed" >&2
  exit 1
fi

echo "NbE production candidate ENGINEERING-PERFORMANCE-PASS ($required_runs runs)"
echo "Evidence: $summary"
