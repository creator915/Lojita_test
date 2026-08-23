#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile=${PERFORMANCE_HOST_PROFILE:-$backend_dir/config/nbe-performance-host-profile.tsv}
facts=${PERFORMANCE_HOST_FACTS:?PERFORMANCE_HOST_FACTS is required}

validate_profile_schema() {
  awk -F '\t' '
    BEGIN {
      allowed["schema"]=1
      allowed["status"]=1
      allowed["profile"]=1
      allowed["cpu-model"]=1
      allowed["logical-cpus"]=1
      allowed["memory-bytes"]=1
      allowed["required-power-source"]=1
      allowed["required-low-power-mode"]=1
      allowed["required-thermal-state"]=1
      allowed["minimum-cpu-idle-percent"]=1
      allowed["minimum-memory-free-percent"]=1
      allowed["required-consecutive-samples"]=1
      allowed["maximum-sample-attempts"]=1
      allowed["process-snapshot-count"]=1
    }
    NR == 1 { if ($0 != "key\tvalue") exit 2; next }
    NF != 2 || !allowed[$1] || seen[$1]++ || $2 == "" { exit 3 }
    { count++ }
    END { if (count != 14) exit 4 }
  ' "$profile"
}

validate_facts_schema() {
  awk -F '\t' '
    BEGIN {
      allowed["schema"]=1
      allowed["captured-at"]=1
      allowed["cpu-model"]=1
      allowed["logical-cpus"]=1
      allowed["memory-bytes"]=1
      allowed["power-source"]=1
      allowed["low-power-mode"]=1
      allowed["thermal-state"]=1
      allowed["cpu-idle-percent"]=1
      allowed["memory-free-percent"]=1
      allowed["load-average-1m"]=1
    }
    NR == 1 { if ($0 != "key\tvalue") exit 2; next }
    NF != 2 || !allowed[$1] || seen[$1]++ || $2 == "" { exit 3 }
    { count++ }
    END { if (count != 11) exit 4 }
  ' "$facts"
}

value_from() {
  input=$1
  key=$2
  awk -F '\t' -v key="$key" '$1 == key { print $2; found=1; exit }
    END { if (!found) exit 1 }' "$input"
}

if [ ! -s "$profile" ] || ! validate_profile_schema; then
  echo "Invalid performance host profile" >&2
  exit 2
fi
if [ ! -s "$facts" ] || ! validate_facts_schema; then
  echo "Invalid performance host facts" >&2
  exit 2
fi

profile_schema=$(value_from "$profile" schema)
profile_status=$(value_from "$profile" status)
profile_name=$(value_from "$profile" profile)
expected_cpu=$(value_from "$profile" cpu-model)
expected_logical_cpus=$(value_from "$profile" logical-cpus)
expected_memory=$(value_from "$profile" memory-bytes)
expected_power=$(value_from "$profile" required-power-source)
expected_low_power=$(value_from "$profile" required-low-power-mode)
expected_thermal=$(value_from "$profile" required-thermal-state)
minimum_idle=$(value_from "$profile" minimum-cpu-idle-percent)
minimum_memory_free=$(value_from "$profile" minimum-memory-free-percent)
required_consecutive=$(value_from "$profile" required-consecutive-samples)
maximum_attempts=$(value_from "$profile" maximum-sample-attempts)
snapshot_count=$(value_from "$profile" process-snapshot-count)

actual_schema=$(value_from "$facts" schema)
actual_cpu=$(value_from "$facts" cpu-model)
actual_logical_cpus=$(value_from "$facts" logical-cpus)
actual_memory=$(value_from "$facts" memory-bytes)
actual_power=$(value_from "$facts" power-source)
actual_low_power=$(value_from "$facts" low-power-mode)
actual_thermal=$(value_from "$facts" thermal-state)
actual_idle=$(value_from "$facts" cpu-idle-percent)
actual_memory_free=$(value_from "$facts" memory-free-percent)
actual_load=$(value_from "$facts" load-average-1m)

if [ "$profile_schema" != 1 ] || [ "$actual_schema" != 1 ] || \
   [ "$profile_status" != engineering-provisional ] || \
   [ "$profile_name" != formal-transport-host-v1 ] || \
   ! awk -v cpus="$expected_logical_cpus" -v memory="$expected_memory" \
     -v idle="$minimum_idle" -v free="$minimum_memory_free" \
     -v consecutive="$required_consecutive" -v attempts="$maximum_attempts" \
     -v snapshots="$snapshot_count" '
       BEGIN {
         exit !(cpus ~ /^[1-9][0-9]*$/ && memory ~ /^[1-9][0-9]*$/ &&
           idle ~ /^[0-9]+([.][0-9]+)?$/ && idle + 0 <= 100 &&
           free ~ /^[0-9]+([.][0-9]+)?$/ && free + 0 <= 100 &&
           consecutive ~ /^[1-9][0-9]*$/ && attempts ~ /^[1-9][0-9]*$/ &&
           attempts + 0 >= consecutive + 0 && snapshots ~ /^[1-9][0-9]*$/)
       }'
then
  echo "Invalid performance host profile values" >&2
  exit 2
fi

if ! awk -v idle="$actual_idle" -v free="$actual_memory_free" \
  -v load="$actual_load" '
    BEGIN {
      number="^[0-9]+([.][0-9]+)?$"
      exit !(idle ~ number && idle + 0 <= 100 && free ~ number &&
        free + 0 <= 100 && load ~ number)
    }'
then
  echo "Invalid performance host measurement values" >&2
  exit 2
fi

if [ "$actual_cpu" != "$expected_cpu" ] || \
   [ "$actual_logical_cpus" != "$expected_logical_cpus" ] || \
   [ "$actual_memory" != "$expected_memory" ]; then
  echo "Performance host machine identity mismatch" >&2
  exit 1
fi
if [ "$actual_power" != "$expected_power" ] || \
   [ "$actual_low_power" != "$expected_low_power" ]; then
  echo "Performance host power policy mismatch" >&2
  exit 1
fi
if [ "$actual_thermal" != "$expected_thermal" ]; then
  echo "Performance host thermal policy mismatch" >&2
  exit 1
fi
if ! awk -v actual="$actual_idle" -v minimum="$minimum_idle" \
  'BEGIN { exit !(actual + 0 >= minimum + 0) }'; then
  echo "Performance host CPU is not quiescent" >&2
  exit 1
fi
if ! awk -v actual="$actual_memory_free" -v minimum="$minimum_memory_free" \
  'BEGIN { exit !(actual + 0 >= minimum + 0) }'; then
  echo "Performance host memory pressure is too high" >&2
  exit 1
fi

echo "Performance host sample HOST-PASS ($actual_idle% idle, $actual_memory_free% memory free)"
