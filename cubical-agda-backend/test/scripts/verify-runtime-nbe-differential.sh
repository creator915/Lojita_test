#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

bridge=${RUNTIME_NBE_AGDA_BRIDGE:?set RUNTIME_NBE_AGDA_BRIDGE}
runtime=${RUNTIME_NBE_BINARY:?set RUNTIME_NBE_BINARY}
agda_datadir=${RUNTIME_NBE_AGDA_DATADIR:?set RUNTIME_NBE_AGDA_DATADIR}
cubical_dir=${RUNTIME_NBE_CUBICAL_DIR:?set RUNTIME_NBE_CUBICAL_DIR}
evidence_dir=build/runtime-nbe/differential
workspace=$(mktemp -d build/runtime-nbe/differential-workspace.XXXXXX)
cubical_workspace=$workspace/cubical
fixture_workspace=$workspace/fixtures
library_file=$workspace/libraries
summary=$evidence_dir/summary.tsv

cleanup() { rm -rf "$workspace"; }
trap cleanup EXIT HUP INT TERM
fail() { echo "runtime NbE same-input differential FAIL: $*" >&2; exit 1; }

[ -x "$bridge" ] || fail "Agda Internal bridge is missing"
[ -x "$runtime" ] || fail "linked runtime is missing"
[ "$(git -C "$cubical_dir" rev-parse HEAD)" = \
  b150186d2544e7efeddd31e5d14a8b9ecbb100f7 ] ||
  fail "Cubical oracle is not the locked v0.9 revision"
[ "$(git -C "$cubical_dir" remote get-url origin)" = \
  https://github.com/agda/cubical.git ] ||
  fail "Cubical oracle origin is not official"

mkdir -p "$evidence_dir" "$cubical_workspace" "$fixture_workspace"
git -C "$cubical_dir" archive HEAD | tar -x -C "$cubical_workspace"
cp test/fixtures/transport/TransportBoundary.agda "$fixture_workspace/"
cp test/fixtures/transport/TransportCoreB.agda "$fixture_workspace/"
cp test/fixtures/transport/TransportHigher.agda "$fixture_workspace/"

printf '%s\n' "$cubical_workspace/cubical.agda-lib" > "$library_file"
printf '%s\n' \
  'name: runtime-nbe-differential' \
  'include: .' \
  'depend: cubical-0.9' \
  'flags: --safe --cubical --no-import-sorts -WnoUnsupportedIndexedMatch --guardedness' \
  > "$fixture_workspace/runtime-nbe-differential.agda-lib"
printf '%s\n' "$fixture_workspace/runtime-nbe-differential.agda-lib" >> "$library_file"

printf 'scenario\tpacket-source\truntime-result\tagda-oracle\tstatus\n' > "$summary"

run_case() {
  scenario=$1; module=$2; expected_term=$3; expected_type=$4
  oracle_expression=$5
  oracle_mode=$6
  source=$fixture_workspace/$module.agda
  packet=$workspace/$scenario.packet
  evidence_packet=$evidence_dir/$scenario.packet
  bridge_log=$evidence_dir/$scenario.bridge.log
  runtime_out=$evidence_dir/$scenario.runtime.out
  runtime_observation=$evidence_dir/$scenario.runtime.observation
  oracle_out=$evidence_dir/$scenario.oracle.out

  Agda_datadir="$agda_datadir" "$bridge" -v0 \
    --library-file="$library_file" --library=runtime-nbe-differential \
    "--cubical-runtime-nbe-export=$scenario" \
    "--cubical-runtime-nbe-file=$packet" "$source" \
    > "$bridge_log" 2>&1 || fail "$scenario Internal export failed"
  grep -Fq "requestTerm = Def \"$module.$scenario\"" "$packet" ||
    fail "$scenario packet was not produced from the checked definition"
  case "$oracle_mode" in
    direct) [ "$oracle_expression" = "$scenario" ] ||
      fail "$scenario direct oracle does not name the exported definition" ;;
    proof-linked)
      grep -Fq "$scenario-sound : $scenario ≡ $scenario-oracle" "$source" ||
        fail "$scenario oracle is not propositionally linked to the exported definition"
      grep -Fq "$oracle_expression = head $scenario-oracle , head (tail $scenario-oracle)" "$source" ||
        fail "$scenario oracle observation is not applied to its proved canonical value" ;;
    *) fail "$scenario has an unknown oracle mode: $oracle_mode" ;;
  esac
  context=$(sed -n '2s/.*packetContext = "\([^"]*\)".*/\1/p' "$packet")
  [ -n "$context" ] || fail "$scenario packet lacks a context identity"
  cp "$packet" "$evidence_packet"
  "$runtime" "$context" "$packet" > "$runtime_out" ||
    fail "$scenario linked runtime execution failed"
  expected=$(printf 'OK\t%s\t%s\t' "$expected_term" "$expected_type")
  grep -Fq "$expected" "$runtime_out" || fail "$scenario runtime result mismatch"
  grep -Eq 'provider-calls=[1-9][0-9]*' "$runtime_out" ||
    fail "$scenario did not call the linked cctt provider"
  "$runtime" --observation "$context" "$packet" > "$runtime_observation" ||
    fail "$scenario runtime observation failed"

  Agda_datadir="$agda_datadir" "$bridge" -v0 \
    --library-file="$library_file" --library=runtime-nbe-differential \
    "--cubical-run=$oracle_expression" "$source" > "$oracle_out" 2>&1 ||
    fail "$scenario Agda oracle failed"
  [ "$(cat "$runtime_observation")" = "$(cat "$oracle_out")" ] ||
    fail "$scenario same-input observation mismatch: runtime=$(cat "$runtime_observation"), Agda=$(cat "$oracle_out")"
  status=$(if [ "$oracle_mode" = proof-linked ]; then
    printf PROOF-LINKED-SAME-INPUT-MATCH
  else
    printf SAME-INPUT-MATCH
  fi)
  printf '%s\t%s.%s\t%s\t%s\t%s\n' \
    "$scenario" "$module" "$scenario" "$expected_term" "$(cat "$oracle_out")" "$status" \
    >> "$summary"
}

run_case t11 TransportBoundary \
  'VecLit TyBool [BoolLit False,BoolLit True]' 'TyVec TyBool 2' \
  t11-oracle-observation proof-linked
run_case t11b TransportBoundary \
  'VecLit TyBool [BoolLit True,BoolLit False]' 'TyVec TyBool 2' \
  t11b-oracle-observation proof-linked
run_case t09 TransportCoreB \
  'Pair (BoolLit False) (NatLit 3)' 'TySigma TyBool TyNat' \
  t09 direct
run_case t16a TransportHigher 'BoolLit True' 'TyBool' t16a direct
run_case t16b TransportHigher 'IntLit 2' 'TyInt' t16b direct
run_case t16c TransportHigher 'IntLit 2' 'TyInt' t16c direct

pass_count=$(awk -F '\t' 'NR > 1 && $5 ~ /PASS|MATCH/ { count++ } END { print count + 0 }' "$summary")
[ "$pass_count" -eq 6 ] || fail "expected 6 same-input PASS/MATCH rows"
echo "RuntimeNbeDifferential PASS ($pass_count exact same-input observations; t11/t11b proof-linked to checked canonical Agda oracles)"
