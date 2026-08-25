#!/usr/bin/env bash

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
program=$repo_root/bin/cubical-agda-run
dispatcher=$repo_root/bin/cubical-agda-dispatch
lane_exec=$repo_root/bin/cubical-agda-lane-exec
analyzer=$repo_root/build/cubical-chez-agda29
native_fixture=$repo_root/test/fixtures/three-lane/NativeProgram.agda
packet_fixture=$repo_root/test/fixtures/agda/PacketResidual.agda
packet_other_module=$repo_root/test/fixtures/agda/PacketOtherModule.agda
runtime_fixture=$repo_root/test/fixtures/transport/TransportBoundary.agda
native_lock=$repo_root/config/native-toolchain.lock.tsv

: "${ANALYZER_AGDA_DATADIR:?set ANALYZER_AGDA_DATADIR}"
: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR}"
: "${CUBICAL29_DIR:?set CUBICAL29_DIR}"
: "${GHC29:?set GHC29}"
: "${CABAL29:?set CABAL29}"
: "${NATIVE_AGDA:?set NATIVE_AGDA}"
: "${NATIVE_AGDA_SOURCE_DIR:?set NATIVE_AGDA_SOURCE_DIR}"
: "${NATIVE_AGDA_DATA_DIR:?set NATIVE_AGDA_DATA_DIR}"
: "${NATIVE_GHC:?set NATIVE_GHC}"
: "${RUNTIME_NBE_AGDA_DATADIR:?set RUNTIME_NBE_AGDA_DATADIR}"

packet_runner=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" &&
  "$CABAL29" list-bin -w "$GHC29" exe:agda-cubical-run)
runtime_bridge=$repo_root/build/runtime-nbe/agda-runtime-nbe-bridge
runtime_final=$repo_root/build/runtime-nbe/final-program/RuntimeNbeFinal
runtime_standalone=$repo_root/build/runtime-nbe/cubical-runtime-nbe

evidence_root=$repo_root/build/three-lane-e2e
mkdir -p "$evidence_root"
workspace=$(mktemp -d "$evidence_root/run.XXXXXX")
execution_root=$(mktemp -d "${TMPDIR:-/tmp}/cubical-agda-three-lane-e2e.XXXXXX")
archive_execution() {
  status=$?
  set +e
  for directory in program-output cancel-output; do
    [[ -d $execution_root/$directory ]] && cp -a -- "$execution_root/$directory" "$workspace/"
  done
  rm -rf -- "$execution_root"
  return "$status"
}
trap archive_execution EXIT

fail() { echo "ThreeLaneE2E FAIL: $*" >&2; exit 1; }
for executable in "$program" "$dispatcher" "$lane_exec" "$analyzer" "$packet_runner" "$runtime_bridge" \
  "$runtime_final" "$runtime_standalone" "$NATIVE_AGDA" "$NATIVE_GHC"; do
  [[ -x $executable ]] || fail "required executable is missing: $executable"
done
[[ -d $NATIVE_AGDA_SOURCE_DIR/.git ]] || fail "locked Agda source is missing"
[[ -f $CUBICAL29_DIR/cubical.agda-lib ]] || fail "locked Cubical library is missing"

library_file=$workspace/libraries
shared_output=$execution_root/program-output
mkdir -p "$shared_output"
declare -a program_environment=(
  "CUBICAL_ANALYZER=$analyzer"
  "CUBICAL_ANALYZER_AGDA_DATA=$ANALYZER_AGDA_DATADIR"
  "CUBICAL_NATIVE_LOCK=$native_lock"
  "CUBICAL_NATIVE_AGDA=$NATIVE_AGDA"
  "CUBICAL_NATIVE_AGDA_SOURCE=$NATIVE_AGDA_SOURCE_DIR"
  "CUBICAL_NATIVE_AGDA_DATA=$NATIVE_AGDA_DATA_DIR"
  "CUBICAL_NATIVE_GHC=$NATIVE_GHC"
  "CUBICAL_PACKET_RUNNER=$packet_runner"
  "CUBICAL_PACKET_AGDA_DATA=$AGDA29_SOURCE_DIR/src/data"
  "CUBICAL_RUNTIME_BRIDGE=$runtime_bridge"
  "CUBICAL_RUNTIME_AGDA_DATA=$RUNTIME_NBE_AGDA_DATADIR"
  "CUBICAL_RUNTIME_FINAL_PROGRAM=$runtime_final"
)
run_program() { env "${program_environment[@]}" "$program" "$@" --agda-arg -v0; }
require_field() {
  local file=$1 key=$2 expected=$3
  awk -F '\t' -v key="$key" -v expected="$expected" '
    $1 == key && $2 == expected { count++ }
    END { if (count != 1) exit 1 }
  ' "$file" || fail "$file lacks $key=$expected"
}
sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}
assert_no_staging() {
  local directory=$1
  if find "$directory" -mindepth 1 -maxdepth 1 \
      \( -name '.program-analysis.*' -o -name '.lane-exec.*' \
         -o -name '.cubical-agda-native.*' -o -name '.three-lane-dispatch.*' \) \
      -print -quit | grep -q .; then
    fail "run retained a private staging directory below $directory"
  fi
}
assert_no_publications() {
  local directory=$1 name
  for name in analysis.txt dispatch.provenance.tsv native-program \
    native-program.provenance.tsv native-program.malonzo.sha256 \
    native-program.malonzo.tar native-program.binary-audit.txt \
    native.observation native.provenance.tsv term.packet packet.observation \
    packet.provenance.tsv runtime-nbe.packet runtime-nbe.observation \
    runtime-nbe.provenance.tsv; do
    [[ ! -e $directory/$name ]] || fail "failed/cancelled run retained $directory/$name"
  done
  assert_no_staging "$directory"
}

cubical_workspace=$workspace/cubical
runtime_source_dir=$workspace/runtime-source
mkdir -p "$cubical_workspace" "$runtime_source_dir"
git -C "$CUBICAL29_DIR" archive HEAD | tar -x -C "$cubical_workspace"
cp "$runtime_fixture" "$runtime_source_dir/TransportBoundary.agda"
runtime_fixture=$runtime_source_dir/TransportBoundary.agda
printf '%s\n' "$cubical_workspace/cubical.agda-lib" > "$library_file"
Agda_datadir="$NATIVE_AGDA_DATA_DIR" "$NATIVE_AGDA" -v0 \
  --library-file="$library_file" -l cubical --guardedness \
  -i "$runtime_source_dir" "$runtime_fixture" \
  > "$workspace/runtime-warmup.stdout" 2> "$workspace/runtime-warmup.stderr" ||
  fail "locked Stock Agda interface warmup failed"

# Real v2 producer and independent consumer.
run_program --source "$packet_fixture" --entry main --boundary cross-process \
  --output-dir "$shared_output" --packet-expression main --packet-consumer consume \
  --agda-arg --no-libraries > "$workspace/packet.stdout" 2> "$workspace/packet.stderr"
[[ $(cat "$shared_output/packet.observation") == true ]] || fail "packet observation mismatch"
require_field "$shared_output/dispatch.provenance.tsv" lane packet
require_field "$shared_output/packet.provenance.tsv" payload checked-internal-term+type
require_field "$shared_output/packet.provenance.tsv" semantic-closure none
[[ ! -e $shared_output/native-program && ! -e $shared_output/runtime-nbe.packet ]] ||
  fail "packet run retained a different lane"
assert_no_staging "$shared_output"

# Real consumer type mismatch, then real module identity mismatch.
if run_program --source "$packet_fixture" --entry main --boundary cross-process \
  --output-dir "$shared_output" --packet-expression main --packet-consumer consumeWrong \
  --agda-arg --no-libraries > "$workspace/type-mismatch.stdout" 2> "$workspace/type-mismatch.stderr"; then
  fail "wrong packet consumer type unexpectedly succeeded"
fi
grep -Fq UnequalTypes "$workspace/type-mismatch.stdout" "$workspace/type-mismatch.stderr" ||
  fail "type negative did not reach UnequalTypes"
assert_no_publications "$shared_output"

if run_program --source "$packet_fixture" --entry main --boundary cross-process \
  --output-dir "$shared_output" --packet-expression main --packet-consumer consume \
  --packet-consumer-source "$packet_other_module" --agda-arg --no-libraries \
  > "$workspace/identity-mismatch.stdout" 2> "$workspace/identity-mismatch.stderr"; then
  fail "wrong packet module identity unexpectedly succeeded"
fi
grep -Fq 'different top-level module' "$workspace/identity-mismatch.stdout" \
  "$workspace/identity-mismatch.stderr" || fail "identity negative missed the real module check"
assert_no_publications "$shared_output"

# Real Agda Internal export and linked Stock-MAlonzo final program/cctt provider.
run_program --source "$runtime_fixture" --entry t11 --boundary in-process \
  --output-dir "$shared_output" --runtime-expression t11 \
  --agda-arg "--library-file=$library_file" --agda-arg -l --agda-arg cubical \
  --agda-arg --guardedness > "$workspace/runtime.stdout" 2> "$workspace/runtime.stderr"
require_field "$shared_output/dispatch.provenance.tsv" lane runtime-nbe
require_field "$shared_output/runtime-nbe.provenance.tsv" execution linked-final-program-process
grep -Eq 'provider-calls=[1-9][0-9]*' "$shared_output/runtime-nbe.observation" ||
  fail "linked runtime did not execute the cctt provider"
[[ ! -e $shared_output/term.packet && ! -e $shared_output/native-program ]] ||
  fail "runtime run retained a different lane"
assert_no_staging "$shared_output"

runtime_context=$(awk -F '\t' '$1 == "compiled-context" { print $2; exit }' \
  "$shared_output/runtime-nbe.provenance.tsv")
if "$runtime_standalone" --fuel=1 "$runtime_context" "$shared_output/runtime-nbe.packet" \
  > "$workspace/resource.stdout" 2> "$workspace/resource.stderr"; then
  fail "runtime packet unexpectedly fit a one-step fuel budget"
fi
grep -Fq CCZ-RUNTIME-NBE-FUEL "$workspace/resource.stdout" ||
  fail "resource negative missed the real runtime fuel gate"

# Real Stock Agda -> MAlonzo -> locked GHC executable, reusing one boundary.
run_program --source "$native_fixture" --entry analysis --boundary none \
  --output-dir "$shared_output" --native-classification ordinary \
  --agda-arg --no-libraries > "$workspace/native.stdout" 2> "$workspace/native.stderr"
[[ $(cat "$shared_output/native.observation") == three-lane-native-42 ]] ||
  fail "native binary output mismatch"
require_field "$shared_output/dispatch.provenance.tsv" lane native
require_field "$shared_output/native.provenance.tsv" term-packet none
grep -Fqx "source-sha256: $(sha256_file "$native_fixture")" \
  "$shared_output/analysis.txt" || fail "analysis was not bound to the native source bytes"
[[ -x $shared_output/native-program ]] || fail "native executable was not published"
[[ ! -e $shared_output/term.packet && ! -e $shared_output/runtime-nbe.packet ]] ||
  fail "native run retained a different lane"
assert_no_staging "$shared_output"

# A real analysis must not authorize any production lane after its source bytes
# change. Reuse the checked native analysis with an initially byte-identical
# source copy, mutate that copy, and configure the real production executor.
mutation_source_dir=$execution_root/mutated-source
mutation_output=$execution_root/mutation-output
mkdir -p "$mutation_source_dir" "$mutation_output"
mutation_source=$mutation_source_dir/NativeProgram.agda
cp -- "$native_fixture" "$mutation_source"
cp -- "$shared_output/analysis.txt" "$workspace/native.analysis.txt"
printf '\n-- changed after analysis\n' >> "$mutation_source"
set +e
env "${program_environment[@]}" "$dispatcher" \
  --analysis "$workspace/native.analysis.txt" --source "$mutation_source" \
  --boundary none --provenance "$mutation_output/dispatch.provenance.tsv" \
  --native-exec "$lane_exec" --native-arg --output-dir \
  --native-arg "$mutation_output" --native-arg --classification \
  --native-arg ordinary \
  > "$workspace/source-mutation.stdout" 2> "$workspace/source-mutation.stderr"
mutation_status=$?
set -e
[[ $mutation_status -eq 65 ]] ||
  fail "post-analysis source mutation returned $mutation_status instead of 65"
grep -Fq 'analysis source SHA-256 does not match the current source' \
  "$workspace/source-mutation.stderr" ||
  fail "post-analysis source mutation missed the stable hash rejection"
assert_no_publications "$mutation_output"

# TERM during the real analyzer must remove every private and public artifact.
cancel_output=$execution_root/cancel-output
mkdir -p "$cancel_output"
env "${program_environment[@]}" "$program" --source "$runtime_fixture" --entry t11 \
  --boundary cross-process --output-dir "$cancel_output" --packet-expression t11 \
  --packet-consumer c16a --agda-arg "--library-file=$library_file" \
  --agda-arg -l --agda-arg cubical --agda-arg --guardedness --agda-arg -v0 \
  > "$workspace/cancel.stdout" 2> "$workspace/cancel.stderr" &
cancel_pid=$!
analysis_stage_seen=no
for _ in $(seq 1 600); do
  if find "$cancel_output" -mindepth 1 -maxdepth 1 -type d \
      -name '.program-analysis.*' -print -quit | grep -q .; then
    analysis_stage_seen=yes; break
  fi
  kill -0 "$cancel_pid" 2>/dev/null || break
  sleep 0.05
done
[[ $analysis_stage_seen == yes ]] || fail "cancellation missed real analysis staging"
kill -TERM "$cancel_pid" 2>/dev/null || fail "cancellation process already exited"
set +e
wait "$cancel_pid"
cancel_status=$?
set -e
[[ $cancel_status -ne 0 ]] || fail "cancelled production run returned success"
assert_no_publications "$cancel_output"

printf '%s\n' \
  'ThreeLaneE2E PASS (real analysis; native/Term-packet/linked-NbE; mismatch/resource/cancel cleanup)' \
  "ThreeLaneE2E evidence: $workspace"
