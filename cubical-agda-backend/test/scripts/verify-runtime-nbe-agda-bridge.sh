#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

bridge=${RUNTIME_NBE_AGDA_BRIDGE:?set RUNTIME_NBE_AGDA_BRIDGE}
runtime=${RUNTIME_NBE_BINARY:?set RUNTIME_NBE_BINARY}
agda_datadir=${RUNTIME_NBE_AGDA_DATADIR:?set RUNTIME_NBE_AGDA_DATADIR}
fixture=test/fixtures/runtime-nbe/RuntimeNbeBridge.agda
source_file=runtime/agda-2.9/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs
evidence_dir=$(mktemp -d build/runtime-nbe/agda-bridge.XXXXXX)
summary=$evidence_dir/summary.tsv

fail() {
  echo "Agda Internal runtime NbE bridge FAIL: $*" >&2
  exit 1
}

for file in "$bridge" "$runtime" "$fixture" "$source_file"; do
  [ -s "$file" ] || fail "missing input: $file"
done
[ -x "$bridge" ] || fail "Agda bridge is not executable"
[ -x "$runtime" ] || fail "runtime is not executable"

grep -Fq 'import qualified Agda.Syntax.Internal as Internal' "$source_file" ||
  fail "producer does not import real Agda Internal syntax"
grep -Fq 'import qualified Cubical.Runtime.Nbe.Wire as Wire' "$source_file" ||
  fail "producer and runtime do not share the wire model"
bridge_body=$(sed -n '/^runtimeNbeExport ::/,/^bridgeType ::/p' "$source_file")
if printf '%s\n' "$bridge_body" | grep -Eq '^[[:space:]]*(term|ty|value)[[:space:]]*<-[[:space:]]*normalise|^[[:space:]]*normalise[[:space:]]'; then
  fail "runtime bridge calls compiler normalise"
fi

printf 'case\tproducer\truntime-result\tstatus\n' > "$summary"

export_and_run() {
  label=$1
  expression=$2
  expected_term=$3
  expected_type=$4
  expected_oracle=$5
  packet=$evidence_dir/$label.packet
  Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    "--cubical-runtime-nbe-export=$expression" \
    "--cubical-runtime-nbe-file=$packet" "$fixture" \
    > "$evidence_dir/$label.producer.log" 2>&1 ||
    fail "$label producer failed"
  head -n 1 "$packet" | grep -Fq "CCZ-RUNTIME-NBE" ||
    fail "$label packet magic is missing"
  context=$(sed -n '2s/.*packetContext = "\([^"]*\)".*/\1/p' "$packet")
  [ -n "$context" ] || fail "$label context identity is missing"
  output=$($runtime "$context" "$packet") || fail "$label runtime failed"
  expected=$(printf 'OK\t%s\t%s\t' "$expected_term" "$expected_type")
  printf '%s\n' "$output" | grep -Fq "$expected" ||
    fail "$label output mismatch: $output"
  Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    "--cubical-run=$expression" "$fixture" \
    > "$evidence_dir/$label.oracle" 2>&1 ||
    fail "$label Agda oracle failed"
  oracle=$(cat "$evidence_dir/$label.oracle")
  [ "$oracle" = "$expected_oracle" ] ||
    fail "$label Agda oracle mismatch: $oracle"
  printf '%s\treal-Agda-Internal+Agda-oracle\t%s : %s\tPASS\n' \
    "$label" "$expected_term" "$expected_type" >> "$summary"
}

export_and_run bool-true true 'BoolLit True' TyBool true
export_and_run nat-seven 7 'NatLit 7' TyNat 7
export_and_run bool-identity 'λ (value : Bool) → value' \
  'Lam TyBool (Var 0)' 'TyPi TyBool TyBool' 'λ value → value'
export_and_run definition-identity bridgeIdentity \
  'Lam TyBool (Var 0)' 'TyPi TyBool TyBool' 'λ value → value'
export_and_run definition-application 'bridgeIdentity true' \
  'BoolLit True' TyBool true

grep -Fq 'requestTerm = Def "RuntimeNbeBridge.bridgeIdentity"' \
  "$evidence_dir/definition-identity.packet" ||
  fail "definition export was compiler-reduced instead of preserving Internal Def"
grep -Fq 'requestDefinitions = [Definition' \
  "$evidence_dir/definition-identity.packet" ||
  fail "definition export omitted the checked definition slice"

lambda_packet=$evidence_dir/bool-identity.packet
lambda_context=$(sed -n '2s/.*packetContext = "\([^"]*\)".*/\1/p' "$lambda_packet")
if $runtime wrong-agda-context-v1 "$lambda_packet" > "$evidence_dir/context-mismatch.log" 2>&1; then
  fail "runtime accepted the real packet under the wrong compiled context"
fi
grep -Fq 'CCZ-RUNTIME-NBE-CONTEXT-MISMATCH' "$evidence_dir/context-mismatch.log" ||
  fail "context mismatch did not fail closed"
printf 'context-mismatch\treal-Agda-Internal\tCCZ-RUNTIME-NBE-CONTEXT-MISMATCH\tPASS\n' >> "$summary"

if Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    '--cubical-runtime-nbe-export=bridgeNot' \
    "--cubical-runtime-nbe-file=$evidence_dir/unsupported.packet" "$fixture" \
    > "$evidence_dir/unsupported.log" 2>&1; then
  fail "unsupported pattern-matching Internal Def was silently accepted"
fi
grep -Fq 'runtime NbE bridge does not support' "$evidence_dir/unsupported.log" ||
  fail "unsupported Internal node did not produce the stable bridge rejection"
grep -Fq 'definition:' "$evidence_dir/unsupported.log" ||
  fail "unsupported Internal node did not produce the stable bridge rejection"
[ ! -e "$evidence_dir/unsupported.packet" ] ||
  fail "unsupported Internal node published a packet"
printf 'unsupported-def\treal-Agda-Internal\tbridge-reject-no-packet\tPASS\n' >> "$summary"

pass_count=$(awk -F '\t' 'NR > 1 && $4 == "PASS" { count++ } END { print count + 0 }' "$summary")
[ "$pass_count" -eq 7 ] || fail "expected 7 PASS rows, observed $pass_count"

echo "RuntimeNbeAgdaBridge PASS ($pass_count; evidence $evidence_dir)"
