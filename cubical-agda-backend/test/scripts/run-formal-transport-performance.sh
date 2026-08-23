#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?Set CUBICAL29_DIR to a clean pinned cubical source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
profile=${PERFORMANCE_PROFILE:-"$backend_dir/config/nbe-performance-profile.tsv"}
host_profile=${PERFORMANCE_HOST_PROFILE:-"$backend_dir/config/nbe-performance-host-profile.tsv"}
ghc29=${GHC29:-ghc}
selected_lock="$backend_dir/test/fixtures/nbe-adapter-lock/selected-valid.tsv"

profile_value() {
  awk -F '\t' -v key="$1" '$1 == key { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$profile"
}

host_profile_value() {
  awk -F '\t' -v key="$1" '$1 == key { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$host_profile"
}

if [ ! -f "$profile" ] || [ ! -f "$host_profile" ] || \
   [ ! -f "$selected_lock" ]; then
  echo "Performance profile, host profile, or selected candidate lock is unavailable" >&2
  exit 2
fi
required_runs=$(profile_value required-runs)
group_timeout=$(profile_value group-timeout-seconds)
benchmark_variant=$(profile_value benchmark-variant)
result_name=$(profile_value result-name)
ghc_optimization=$(profile_value ghc-optimization)
required_consecutive_samples=$(host_profile_value required-consecutive-samples)
maximum_sample_attempts=$(host_profile_value maximum-sample-attempts)
process_snapshot_count=$(host_profile_value process-snapshot-count)
if ! awk -v runs="$required_runs" -v timeout="$group_timeout" \
  -v consecutive="$required_consecutive_samples" \
  -v attempts="$maximum_sample_attempts" -v snapshots="$process_snapshot_count" '
    BEGIN {
      exit !(runs ~ /^[1-9][0-9]*$/ && timeout ~ /^[1-9][0-9]*$/ &&
        consecutive ~ /^[1-9][0-9]*$/ && attempts ~ /^[1-9][0-9]*$/ &&
        attempts + 0 >= consecutive + 0 && snapshots ~ /^[1-9][0-9]*$/)
    }'
then
  echo "Performance run, timeout, or host sampling policy is invalid" >&2
  exit 2
fi
case "$benchmark_variant:$result_name:$ghc_optimization" in
  engineering-o0:formal-transport-performance:O0)
    formal_build_suffix=
    ;;
  release-o2:formal-transport-performance-release:O2)
    formal_build_suffix=-release
    ;;
  *)
    echo "Invalid benchmark variant, result name, or GHC optimization pairing" >&2
    exit 2
    ;;
esac
final_result_dir="$backend_dir/build/agda29/$result_name"

timeout_bin=$(command -v gtimeout 2>/dev/null || command -v timeout 2>/dev/null || true)
if [ -z "$timeout_bin" ] || [ ! -x "$timeout_bin" ]; then
  echo "A timeout executable is required for performance collection" >&2
  exit 2
fi
if [ "$(find "$cubical_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')" -ne 0 ]; then
  echo "Performance collection requires a clean Cubical source without .agdai files" >&2
  exit 2
fi

pending_host_dir=$(mktemp -d /private/tmp/formal-transport-host.XXXXXX)
caffeinate_pid=
staging_result=
cleanup() {
  rm -rf "$pending_host_dir"
  if [ -n "$staging_result" ] && [ -d "$staging_result" ]; then
    rm -rf "$staging_result"
  fi
  if [ -n "$caffeinate_pid" ]; then
    kill "$caffeinate_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sleep_prevention=unavailable
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu -w $$ >/dev/null 2>&1 &
  caffeinate_pid=$!
  sleep_prevention=caffeinate-dimsu
fi

capture_host_facts() {
  output=$1
  captured_cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
  captured_logical_cpus=$(sysctl -n hw.logicalcpu 2>/dev/null || echo unknown)
  captured_memory=$(sysctl -n hw.memsize 2>/dev/null || echo unknown)
  captured_power=$(pmset -g batt 2>/dev/null | \
    sed -n "1s/^Now drawing from '\(.*\)'$/\1/p" || true)
  captured_power=${captured_power:-unknown}
  captured_low_power=$(pmset -g 2>/dev/null | \
    awk '$1 == "lowpowermode" { print $2; found=1; exit }
      END { if (!found) print "unknown" }')
  thermal_report=$(pmset -g therm 2>/dev/null || true)
  if printf '%s\n' "$thermal_report" | \
       grep -Fq 'No thermal warning level has been recorded' && \
     printf '%s\n' "$thermal_report" | \
       grep -Fq 'No performance warning level has been recorded'; then
    captured_thermal=nominal
  else
    captured_thermal=warning
  fi
  captured_idle=$(LC_ALL=C top -l 2 -s 1 -n 0 2>/dev/null | \
    awk '/CPU usage:/ { value=$7; gsub(/%/, "", value); idle=value }
      END { if (idle == "") exit 1; print idle }')
  captured_memory_free=$(LC_ALL=C memory_pressure -Q 2>/dev/null | \
    awk -F ': ' '/System-wide memory free percentage:/ {
      value=$2; gsub(/%/, "", value); free=value
    } END { if (free == "") exit 1; print free }')
  captured_load=$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | \
    awk '{ print $1 }')
  printf 'key\tvalue\nschema\t1\ncaptured-at\t%s\ncpu-model\t%s\nlogical-cpus\t%s\nmemory-bytes\t%s\npower-source\t%s\nlow-power-mode\t%s\nthermal-state\t%s\ncpu-idle-percent\t%s\nmemory-free-percent\t%s\nload-average-1m\t%s\n' \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$captured_cpu" \
    "$captured_logical_cpus" "$captured_memory" "$captured_power" \
    "$captured_low_power" "$captured_thermal" "$captured_idle" \
    "$captured_memory_free" "$captured_load" > "$output"
}

capture_process_snapshot() {
  output=$1
  printf 'pid\tcpu_percent\trss_kib\tcommand\n' > "$output"
  ps -A -o pid=,pcpu=,rss=,comm= | LC_ALL=C sort -k2,2nr | \
    awk -v count="$process_snapshot_count" 'NR <= count {
      pid=$1; cpu=$2; rss=$3
      $1=""; $2=""; $3=""; sub(/^ +/, "")
      printf "%s\t%s\t%s\t%s\n", pid,cpu,rss,$0
    }' >> "$output"
}

wait_for_quiescent_host() {
  label=$1
  attempts_dir=$2
  accepted_output=$3
  snapshot_output=$4
  mkdir -p "$attempts_dir"
  attempt=1
  consecutive=0
  while [ "$attempt" -le "$maximum_sample_attempts" ]
  do
    attempt_label=$(printf '%02d' "$attempt")
    facts_file="$attempts_dir/$label-attempt-$attempt_label.tsv"
    validation_log="$attempts_dir/$label-attempt-$attempt_label.log"
    capture_host_facts "$facts_file"
    set +e
    PERFORMANCE_HOST_PROFILE="$host_profile" \
    PERFORMANCE_HOST_FACTS="$facts_file" \
      sh "$script_dir/verify-formal-transport-performance-host.sh" \
      > "$validation_log" 2>&1
    sample_status=$?
    set -e
    if [ "$sample_status" -eq 0 ]; then
      consecutive=$((consecutive + 1))
      if [ "$consecutive" -eq "$required_consecutive_samples" ]; then
        cp "$facts_file" "$accepted_output"
        capture_process_snapshot "$snapshot_output"
        return 0
      fi
    else
      consecutive=0
      if ! grep -Eq \
        'Performance host CPU is not quiescent|Performance host memory pressure is too high' \
        "$validation_log"
      then
        echo "$label has a non-retriable host policy mismatch" >&2
        tail -n 1 "$validation_log" >&2
        return 1
      fi
    fi
    attempt=$((attempt + 1))
  done
  echo "$label did not reach $required_consecutive_samples consecutive quiescent host samples" >&2
  tail -n 1 "$validation_log" >&2
  return 1
}

initial_attempts="$pending_host_dir/attempts"
initial_facts="$pending_host_dir/host-preflight.tsv"
initial_processes="$pending_host_dir/background-processes.tsv"
wait_for_quiescent_host initial "$initial_attempts" "$initial_facts" \
  "$initial_processes"

case "$final_result_dir" in
  "$backend_dir"/build/agda29/formal-transport-performance|\
  "$backend_dir"/build/agda29/formal-transport-performance-release) ;;
  *)
    echo "Refusing to publish to unexpected performance evidence path: $final_result_dir" >&2
    exit 2
    ;;
esac
staging_result=$(mktemp -d \
  "$backend_dir/build/agda29/$result_name.pending.XXXXXX")
result_dir=$staging_result
raw_root="$result_dir/raw"
mkdir -p "$raw_root"
cp -R "$initial_attempts" "$raw_root/initial-host-attempts"
cp "$initial_facts" "$raw_root/initial-host-preflight.tsv"
cp "$initial_processes" "$raw_root/initial-background-processes.tsv"

cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)
memory_bytes=$(sysctl -n hw.memsize 2>/dev/null || echo unknown)
power_source=$(pmset -g batt 2>/dev/null | sed -n "1s/^Now drawing from '\(.*\)'$/\1/p" || true)
power_source=${power_source:-unknown}
ghc_version=$($ghc29 --numeric-version)
profile_sha256=$(shasum -a 256 "$profile" | awk '{ print $1 }')
host_profile_sha256=$(shasum -a 256 "$host_profile" | awk '{ print $1 }')
printf 'key\tvalue\ncollected-at\t%s\nhostname\t%s\nkernel\t%s\ncpu\t%s\nmemory-bytes\t%s\npower-source\t%s\nghc-version\t%s\nghc-optimization\t%s\nbenchmark-variant\t%s\nresult-name\t%s\nrequired-runs\t%s\ngroup-timeout-seconds\t%s\nprofile-sha256\t%s\nhost-profile-sha256\t%s\nsleep-prevention\t%s\n' \
  "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(hostname)" "$(uname -srvmo 2>/dev/null || uname -a)" \
  "$cpu_model" "$memory_bytes" "$power_source" "$ghc_version" \
  "$ghc_optimization" "$benchmark_variant" "$result_name" \
  "$required_runs" "$group_timeout" "$profile_sha256" \
  "$host_profile_sha256" "$sleep_prevention" \
  > "$result_dir/environment.tsv"

groups='base glue int core boundary hit higher monolithic'
run_number=1
while [ "$run_number" -le "$required_runs" ]
do
  run_label=$(printf 'run-%02d' "$run_number")
  run_dir="$raw_root/$run_label"
  mkdir -p "$run_dir"
  if [ $((run_number % 2)) -eq 1 ]; then
    engine_order='agda-baseline nbe'
  else
    engine_order='nbe agda-baseline'
  fi
  printf 'run\tengine-order\n%s\t%s\n' "$run_label" \
    "$(printf '%s' "$engine_order" | tr ' ' ',')" > "$run_dir/order.tsv"

  for engine in $engine_order
  do
    engine_dir="$run_dir/$engine"
    mkdir -p "$engine_dir"
    for group in $groups
    do
      host_label="$run_label-$engine-$group"
      host_attempts="$run_dir/host-attempts/$engine/$group"
      accepted_host_facts="$engine_dir/$group.host-preflight.pending.tsv"
      accepted_processes="$engine_dir/$group.background-processes.pending.tsv"
      wait_for_quiescent_host "$host_label" "$host_attempts" \
        "$accepted_host_facts" "$accepted_processes"
      echo "Performance $run_label: $engine/$group"
      group_log="$engine_dir/$group.collect.log"
      set +e
      "$timeout_bin" "$group_timeout" env \
        AGDA29_SOURCE_DIR="$agda_source_dir" \
        CUBICAL29_DIR="$cubical_source_dir" \
        GHC29="$ghc29" \
        FORMAL_TRANSPORT_ENGINE="$engine" \
        FORMAL_TRANSPORT_GROUP="$group" \
        FORMAL_GHC_OPTIMIZATION="$ghc_optimization" \
        FORMAL_NBE_ADAPTER_LOCK="$selected_lock" \
        sh "$script_dir/verify-formal-transport.sh" \
        > "$group_log" 2>&1
      group_status=$?
      set -e
      if [ "$group_status" -ne 0 ]; then
        if [ "$group_status" -eq 124 ]; then
          echo "$run_label $engine/$group exceeded ${group_timeout}s" >&2
        else
          echo "$run_label $engine/$group failed with status $group_status" >&2
        fi
        tail -n 200 "$group_log" >&2
        exit 1
      fi
      if [ "$engine" = agda-baseline ]; then
        source_group="$backend_dir/build/agda29/formal-transport$formal_build_suffix/$group"
      else
        source_group="$backend_dir/build/agda29/formal-transport-nbe$formal_build_suffix/$group"
      fi
      if [ ! -s "$source_group/summary.tsv" ]; then
        echo "$run_label $engine/$group did not publish a summary" >&2
        exit 1
      fi
      cp -R "$source_group" "$engine_dir/$group"
      mv "$accepted_host_facts" "$engine_dir/$group/host-preflight.tsv"
      mv "$accepted_processes" "$engine_dir/$group/background-processes.tsv"
    done
  done
  run_number=$((run_number + 1))
done

PERFORMANCE_PROFILE="$profile" \
PERFORMANCE_HOST_PROFILE="$host_profile" \
PERFORMANCE_RUNS_ROOT="$raw_root" \
PERFORMANCE_RESULT_DIR="$result_dir" \
  sh "$script_dir/verify-formal-transport-stage-performance.sh"
set +e
PERFORMANCE_PROFILE="$profile" \
PERFORMANCE_HOST_PROFILE="$host_profile" \
PERFORMANCE_RUNS_ROOT="$raw_root" \
PERFORMANCE_RESULT_DIR="$result_dir" \
  sh "$script_dir/verify-formal-transport-performance.sh"
comparison_status=$?
set -e

comparison_result=$(awk -F '\t' '$1 == "result" { print $2; found=1; exit }
  END { if (!found) exit 1 }' "$result_dir/invocation.tsv" 2>/dev/null || true)
case "$comparison_result:$comparison_status" in
  ENGINEERING-PERFORMANCE-PASS:0) ;;
  ENGINEERING-PERFORMANCE-FAIL:1) ;;
  *)
    echo "Performance comparison did not publish a valid terminal result" >&2
    exit 1
    ;;
esac

PERFORMANCE_PUBLICATION_ROOT="$backend_dir/build/agda29" \
PERFORMANCE_STAGING_RESULT="$staging_result" \
PERFORMANCE_FINAL_RESULT="$final_result_dir" \
PERFORMANCE_TERMINAL_RESULT="$comparison_result" \
  sh "$script_dir/publish-formal-transport-performance.sh"
staging_result=

if [ "$comparison_result" = ENGINEERING-PERFORMANCE-FAIL ]; then
  exit 1
fi
