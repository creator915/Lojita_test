#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

runtime_binary=${RUNTIME_NBE_BINARY:-build/runtime-nbe/cubical-runtime-nbe}
runtime_library=${RUNTIME_NBE_LIBRARY:-build/runtime-nbe/libcubical-runtime-nbe.a}
packet_generator=${RUNTIME_NBE_GENERATOR:-build/runtime-nbe/generate-packets}
evidence_dir=build/runtime-nbe/acceptance
packet_dir=$evidence_dir/packets
summary=$evidence_dir/summary.tsv
context='transport-fixtures-v1:b150186d2544e7ef'
provider_lock=config/runtime-nbe-provider.lock.tsv
provider_license=runtime/nbe/third-party/cctt-LICENSE.txt

fail() {
  echo "runtime NbE acceptance failed: $*" >&2
  exit 1
}

mkdir -p "$packet_dir"

awk -F '\t' '
  $1 == "status" && $2 == "selected" { status++ }
  $1 == "upstream-provider" && $2 == "cctt" { provider++ }
  $1 == "upstream-revision" && $2 == "ba16f3758a322e9be77ada1da2b93f45d500192e" { revision++ }
  $1 == "upstream-source-archive-sha256" && $2 == "8d83adcb45ea827583f02fb6fb5c7d023ae97fdf6dd7816e9069ee45c67b6b5d" { source++ }
  $1 == "upstream-license-spdx" && $2 == "MIT" { license++ }
  $1 == "integration" && $2 == "backend-owned-agda-runtime-adapter" { integration++ }
  END { exit !(status == 1 && provider == 1 && revision == 1 && source == 1 && license == 1 && integration == 1) }
' "$provider_lock" || fail "selected runtime provider lock is incomplete"
[ "$(sha256sum "$provider_license" | awk '{ print $1 }')" = \
  6d1af462b683165c1b10ed36a0d3c1e1b09f50924b30f16d85918402523210f9 ] ||
  fail "cctt MIT license hash drifted"

"$packet_generator" "$packet_dir"
printf 'scenario\tresult\texpected\tstatus\n' > "$summary"
printf 'provider-lock\tselected-cctt-ba16f375\tselected-cctt-ba16f375\tPASS\n' >> "$summary"

while IFS='	' read -r scenario expected_term expected_type agda_evidence; do
  [ "$scenario" = scenario ] && continue
  output=$($runtime_binary "$context" "$packet_dir/$scenario.packet") ||
    fail "$scenario returned a failure"
  expected=$(printf 'OK\t%s\t%s\t' "$expected_term" "$expected_type")
  case "$output" in
    "$expected"*) ;;
    *) fail "$scenario output mismatch: $output" ;;
  esac
  printf '%s\t%s\t%s\tPASS\n' "$scenario" "$expected_term" "$agda_evidence" >> "$summary"
done < test/fixtures/runtime-nbe/oracle.tsv

expect_error() {
  label=$1
  code=$2
  shift 2
  output_file=$evidence_dir/$label.out
  if "$@" > "$output_file" 2>&1; then
    fail "$label unexpectedly succeeded"
  fi
  error_prefix=$(printf 'ERROR\t%s\t' "$code")
  grep -Fq "$error_prefix" "$output_file" ||
    fail "$label did not report $code"
  printf '%s\t%s\t%s\tPASS\n' "$label" "$code" "$code" >> "$summary"
}

expect_error context-mismatch CCZ-RUNTIME-NBE-CONTEXT-MISMATCH \
  "$runtime_binary" 'wrong-context-v1:0000000000000000' "$packet_dir/t11.packet"
expect_error wrong-type CCZ-RUNTIME-NBE-TYPE-MISMATCH \
  "$runtime_binary" "$context" "$packet_dir/wrong-type.packet"
expect_error definition-cycle CCZ-RUNTIME-NBE-DEFINITION-CYCLE \
  "$runtime_binary" "$context" "$packet_dir/cycle.packet"
expect_error fuel-limit CCZ-RUNTIME-NBE-FUEL \
  "$runtime_binary" --fuel=1 "$context" "$packet_dir/t16a.packet"
expect_error allocation-limit CCZ-RUNTIME-NBE-MEMORY \
  "$runtime_binary" --allocations=1 "$context" "$packet_dir/t16a.packet"
expect_error packet-limit CCZ-RUNTIME-NBE-PACKET-LIMIT \
  "$runtime_binary" --packet-bytes=64 "$context" "$packet_dir/t11.packet"

printf 'broken packet\n' > "$packet_dir/malformed.packet"
expect_error malformed CCZ-RUNTIME-NBE-BAD-MAGIC \
  "$runtime_binary" "$context" "$packet_dir/malformed.packet"

sed 's/runtime-nbe-abi-v1/runtime-nbe-abi-v0/' "$packet_dir/t11.packet" > "$packet_dir/bad-abi.packet"
expect_error abi-mismatch CCZ-RUNTIME-NBE-ABI-MISMATCH \
  "$runtime_binary" "$context" "$packet_dir/bad-abi.packet"

sed 's/cctt-informed-agda-runtime-v1/cctt-unselected-runtime-v0/' \
  "$packet_dir/t11.packet" > "$packet_dir/bad-provider.packet"
expect_error provider-mismatch CCZ-RUNTIME-NBE-PROVIDER-MISMATCH \
  "$runtime_binary" "$context" "$packet_dir/bad-provider.packet"

cache_first=$($runtime_binary "$context" "$packet_dir/cache.packet")
cache_second=$($runtime_binary "$context" "$packet_dir/cache.packet")
printf '%s\n' "$cache_first" | grep -Fq 'definition-lookups=2,cache-hits=1' ||
  fail "definition cache was not used within the first request"
[ "$cache_first" = "$cache_second" ] ||
  fail "per-request cache state leaked across process invocations"
printf 'cache-lifecycle\trequest-local\trequest-local\tPASS\n' >> "$summary"

ar t "$runtime_library" | grep -Fq 'Nbe.o' ||
  fail "runtime archive does not contain the NbE object"
strings "$runtime_binary" | grep -Fq 'cctt-informed-agda-runtime-v1@ba16f3758a322e9be77ada1da2b93f45d500192e' ||
  fail "final executable does not contain the locked provider marker"
if strings "$runtime_binary" | grep -Eq 'Agda\.TypeChecking|TCState|normalise|Agda\.Compiler'; then
  fail "final executable contains a forbidden Agda compiler identity"
fi
if rg -n 'System\.Process|createProcess|callProcess|readProcess|unsafePerformIO' \
    runtime/nbe/src runtime/nbe/app; then
  fail "runtime source contains a forbidden process/compiler escape"
fi
printf 'linked-library\tprovider-marker\tprovider-marker\tPASS\n' >> "$summary"
printf 'compiler-symbol-audit\tno-Agda-TCState-normalise\tno-Agda-TCState-normalise\tPASS\n' >> "$summary"

cc -shared -fPIC -Wall -Werror -o "$evidence_dir/noexec.so" \
  test/fixtures/runtime-nbe/noexec.c
noexec_log=$evidence_dir/noexec.log
: > "$noexec_log"
CCZ_NOEXEC_LOG="$noexec_log" LD_PRELOAD="$repo_root/$evidence_dir/noexec.so" \
  "$runtime_binary" "$context" "$packet_dir/t16c.packet" > "$evidence_dir/noexec.out"
[ ! -s "$noexec_log" ] || fail "runtime attempted to start a subprocess"
noexec_expected=$(printf 'OK\tIntLit 2\tTyInt\t')
grep -Fq "$noexec_expected" "$evidence_dir/noexec.out" ||
  fail "no-exec guarded runtime did not produce the oracle result"
printf 'no-subprocess-trace\tzero-exec-attempts\tzero-exec-attempts\tPASS\n' >> "$summary"

positive_count=$(awk -F '\t' 'NR > 1 && $4 == "PASS" { count++ } END { print count + 0 }' "$summary")
[ "$positive_count" -eq 24 ] || fail "expected 24 PASS rows, observed $positive_count"

echo "RuntimeNbe PASS ($positive_count)"
