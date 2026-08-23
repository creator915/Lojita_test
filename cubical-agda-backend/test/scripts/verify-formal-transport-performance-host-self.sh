#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
profile="$backend_dir/config/nbe-performance-host-profile.tsv"
workspace=$(mktemp -d /private/tmp/formal-performance-host-self.XXXXXX)
valid="$workspace/valid.tsv"

cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf 'key\tvalue\nschema\t1\ncaptured-at\t2026-08-22T00:00:00Z\ncpu-model\tApple M4\nlogical-cpus\t10\nmemory-bytes\t25769803776\npower-source\tAC Power\nlow-power-mode\t0\nthermal-state\tnominal\ncpu-idle-percent\t90\nmemory-free-percent\t80\nload-average-1m\t1.00\n' \
  > "$valid"

PERFORMANCE_HOST_PROFILE="$profile" PERFORMANCE_HOST_FACTS="$valid" \
  sh "$script_dir/verify-formal-transport-performance-host.sh" \
  > "$workspace/positive.stdout" 2> "$workspace/positive.stderr"

expect_reject() {
  label=$1
  facts=$2
  if PERFORMANCE_HOST_PROFILE="$profile" PERFORMANCE_HOST_FACTS="$facts" \
       sh "$script_dir/verify-formal-transport-performance-host.sh" \
       > "$workspace/$label.stdout" 2> "$workspace/$label.stderr"
  then
    echo "Performance host self-test unexpectedly accepted $label" >&2
    exit 1
  fi
}

sed '/^load-average-1m\t/d' "$valid" > "$workspace/missing-field.tsv"
expect_reject missing-field "$workspace/missing-field.tsv"
sed 's/^cpu-model\tApple M4$/cpu-model\tDifferent CPU/' "$valid" \
  > "$workspace/wrong-machine.tsv"
expect_reject wrong-machine "$workspace/wrong-machine.tsv"
sed 's/^power-source\tAC Power$/power-source\tBattery Power/' "$valid" \
  > "$workspace/battery.tsv"
expect_reject battery-power "$workspace/battery.tsv"
sed 's/^thermal-state\tnominal$/thermal-state\twarning/' "$valid" \
  > "$workspace/thermal.tsv"
expect_reject thermal-warning "$workspace/thermal.tsv"
sed 's/^cpu-idle-percent\t90$/cpu-idle-percent\t10/' "$valid" \
  > "$workspace/busy-cpu.tsv"
expect_reject busy-cpu "$workspace/busy-cpu.tsv"
sed 's/^memory-free-percent\t80$/memory-free-percent\t10/' "$valid" \
  > "$workspace/memory-pressure.tsv"
expect_reject memory-pressure "$workspace/memory-pressure.tsv"

echo "Formal performance host self-test PASS (1 positive, 6 negative)"
