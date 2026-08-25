#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?set CUBICAL29_DIR to the pinned Cubical source tree}"

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
projection="$backend_dir/test/fixtures/transport/TransportHit.agda"
control="$backend_dir/test/fixtures/NbeTransportHitControl.agda"
j_control="$backend_dir/test/fixtures/NbeTransportJControl.agda"
s1_control="$backend_dir/test/fixtures/NbeTransportS1Control.agda"
binary="$backend_dir/build/agda29/cubical-chez"
spike_binary="$backend_dir/build/agda29/cubical-chez-nbe-adapter-spike"
evidence_dir="$backend_dir/build/agda29/evidence/NbeAdapterTransportHit"
transport_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
projection_sha256=5939b8dace09ce5656660efda7f6afad76b05b3ebcc3b82c0de0a456c81f7a51
control_sha256=1679b66385b33d404d4bac01b540028bb037bf2ff3e8bc4bc17496257d59488d
j_control_sha256=b5dbdee45a6123500ba1b9b659b445694d6783645e62b869637a725dbc423f01
s1_control_sha256=3a65b3d9989798cd78e1ba2c30aa168e3dead092d54d92b29c1fbee712efd497

if [ ! -f "$agda_source_dir/Agda.cabal" ] || \
   [ ! -f "$cubical_source_dir/cubical.agda-lib" ] || \
   [ ! -x "$binary" ] || [ ! -x "$spike_binary" ]
then
  echo "Pinned sources or Agda 2.9 adapter binaries are unavailable; run verify-agda29 first" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
actual_projection_sha256=$(shasum -a 256 "$projection" | awk '{ print $1 }')
actual_control_sha256=$(shasum -a 256 "$control" | awk '{ print $1 }')
actual_j_control_sha256=$(shasum -a 256 "$j_control" | awk '{ print $1 }')
actual_s1_control_sha256=$(shasum -a 256 "$s1_control" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_sha256" ] || \
   [ "$actual_projection_sha256" != "$projection_sha256" ] || \
   [ "$actual_control_sha256" != "$control_sha256" ] || \
   [ "$actual_j_control_sha256" != "$j_control_sha256" ] || \
   [ "$actual_s1_control_sha256" != "$s1_control_sha256" ]
then
  echo "TransportTests source, TransportHit projection, or control SHA-256 mismatch" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
for scenario in t12 t13 t14 t15
do
  original_fragment="$evidence_dir/$scenario.original.fragment.agda"
  projection_fragment="$evidence_dir/$scenario.projection.fragment.agda"
  awk -v target="$scenario" 'BEGIN { active=0 }
    $0 ~ "^" target " :" { active=1 }
    active {
      print
      if ($0 == "_ = refl") exit
    }
  ' "$transport_source" > "$original_fragment"
  awk -v target="$scenario" 'BEGIN { active=0 }
    $0 ~ "^" target " :" { active=1 }
    active {
      print
      if ($0 == "_ = refl") exit
    }
  ' "$projection" > "$projection_fragment"
  if [ ! -s "$original_fragment" ] || \
     ! cmp -s "$original_fragment" "$projection_fragment"
  then
    echo "$scenario projection is not byte-identical to the pinned original block" >&2
    exit 2
  fi
done

workspace_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-nbe-transport-hit.XXXXXX")
workspace_cubical_dir="$workspace_dir/cubical"
workspace_input_dir="$workspace_dir/input"
cleanup() {
  rm -rf "$workspace_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_cubical_dir" "$workspace_input_dir"
if ! cp -cR "$cubical_source_dir/." "$workspace_cubical_dir" 2>/dev/null; then
  cp -R "$cubical_source_dir/." "$workspace_cubical_dir"
fi
cp "$projection" "$workspace_input_dir/TransportHit.agda"
cp "$control" "$workspace_input_dir/NbeTransportHitControl.agda"
cp "$j_control" "$workspace_input_dir/NbeTransportJControl.agda"
cp "$s1_control" "$workspace_input_dir/NbeTransportS1Control.agda"

run_success() {
  label=$1
  engine=$2
  runner=$3
  entry=$4
  case_dir="$evidence_dir/$label"
  output_dir="$case_dir/output"

  mkdir -p "$output_dir"
  rm -f "$workspace_input_dir/TransportHit.agdai" \
    "$output_dir/program.ss" "$output_dir/treeless.txt" \
    "$output_dir/staging.txt"
  Agda_datadir="$agda_source_dir/src/data" "$runner" \
    -v0 \
    --cubical \
    --safe \
    --guardedness \
    --no-import-sorts \
    -WnoUnsupportedIndexedMatch \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-entry="TransportHit.$entry" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportHit.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$output_dir/program.ss" > "$case_dir/observed.txt"
}

for scenario in t12 t13 t14 t15
do
  run_success "baseline-$scenario" agda-baseline "$binary" "$scenario"
  run_success "spike-$scenario" nbe "$spike_binary" "$scenario"
  for artifact in observed.txt output/treeless.txt output/program.ss
  do
    if ! cmp -s "$evidence_dir/baseline-$scenario/$artifact" \
         "$evidence_dir/spike-$scenario/$artifact"
    then
      echo "$scenario adapter result differs from the pinned Agda baseline in $artifact" >&2
      exit 1
    fi
  done
done

t12_staging="$evidence_dir/spike-t12/output/staging.txt"
if ! grep -Fqx \
     '#(agda_Cubical_2e_Data_2e_Int_2e_Base_2e_ℤ_2e_pos 2)' \
     "$evidence_dir/spike-t12/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$t12_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$t12_staging" || \
   ! grep -Fqx 'nbe-hit-definition-patterns-matched: 4' "$t12_staging" || \
   ! grep -Fqx 'nbe-comps-expanded: 4' "$t12_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 29' "$t12_staging" || \
   ! grep -Fqx 'nbe-universe-transports-reduced: 12' "$t12_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$t12_staging" || \
   ! grep -Fqx 'nbe-backward-glue-transports-reduced: 0' "$t12_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 1' "$t12_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 0' "$t12_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 0' "$t12_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 0' "$t12_staging" || \
   ! grep -Fqx 'nbe-hcomps-reduced: 38' "$t12_staging"
then
  echo "t12 did not reduce the exact canonical S1 winding composition slice" >&2
  exit 1
fi

t13_staging="$evidence_dir/spike-t13/output/staging.txt"
if ! grep -Fqx \
     '#(agda_Cubical_2e_Data_2e_Int_2e_Base_2e_ℤ_2e_pos 1)' \
     "$evidence_dir/spike-t13/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$t13_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$t13_staging" || \
   ! grep -Fqx 'nbe-hit-definition-patterns-matched: 3' "$t13_staging" || \
   ! grep -Fqx 'nbe-comps-expanded: 3' "$t13_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 22' "$t13_staging" || \
   ! grep -Fqx 'nbe-universe-transports-reduced: 11' "$t13_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$t13_staging" || \
   ! grep -Fqx 'nbe-backward-glue-transports-reduced: 1' "$t13_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 1' "$t13_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 0' "$t13_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 0' "$t13_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 0' "$t13_staging" || \
   ! grep -Fqx 'nbe-hcomps-reduced: 16' "$t13_staging"
then
  echo "t13 did not reduce the exact canonical S1 winding inverse-composition slice" >&2
  exit 1
fi

t14_staging="$evidence_dir/spike-t14/output/staging.txt"
if ! grep -Fqx '41' "$evidence_dir/spike-t14/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$t14_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$t14_staging" || \
   ! grep -Fqx 'nbe-definitions-reduced: 2' "$t14_staging" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 1' "$t14_staging" || \
   ! grep -Fqx 'nbe-primitives-reduced: 1' "$t14_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 4' "$t14_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$t14_staging" || \
   ! grep -Fqx 'nbe-constant-nat-transports-reduced: 1' "$t14_staging" || \
   ! grep -Fqx 'nbe-constant-nat-function-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-backward-glue-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 0' "$t14_staging" || \
   ! grep -Fqx 'nbe-hcomps-reduced: 0' "$t14_staging"
then
  echo "t14 did not reduce J-at-refl through the exact constant-Nat transport slice" >&2
  exit 1
fi

t15_staging="$evidence_dir/spike-t15/output/staging.txt"
if ! grep -Fqx \
     '#(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true)' \
     "$evidence_dir/spike-t15/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$t15_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$t15_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 8' "$t15_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 2' "$t15_staging" || \
   ! grep -Fqx 'nbe-constant-nat-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-constant-nat-function-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 2' "$t15_staging" || \
   ! grep -Fqx 'nbe-backward-glue-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 0' "$t15_staging" || \
   ! grep -Fqx 'nbe-hcomps-reduced: 0' "$t15_staging"
then
  echo "t15 did not exercise exactly two nested canonical Glue transports" >&2
  exit 1
fi

run_reject_control() {
  label=$1
  module_name=$2
  entry=$3
  control_dir="$evidence_dir/reject-$label"
  control_output="$control_dir/output"
  control_source="$workspace_input_dir/$module_name.agda"
  control_interface="$workspace_input_dir/$module_name.agdai"

  mkdir -p "$control_output"
  rm -f "$control_interface" \
    "$control_output/program.ss" "$control_output/treeless.txt" \
    "$control_output/staging.txt"
  set +e
  Agda_datadir="$agda_source_dir/src/data" "$spike_binary" \
    -v0 \
    --cubical \
    --safe \
    --guardedness \
    --no-import-sorts \
    -WnoUnsupportedIndexedMatch \
    --cubical-chez \
    --cubical-chez-engine=nbe \
    --cubical-chez-entry="$module_name.$entry" \
    --cubical-chez-output="$control_output" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$control_source" \
    > "$control_dir/producer.stdout" \
    2> "$control_dir/producer.stderr"
  control_status=$?
  set -e

  if [ "$control_status" -eq 0 ] || \
     ! grep -q 'CCZ-NBE-UNSUPPORTED' "$control_dir/producer.stdout" || \
     [ -e "$control_output/program.ss" ] || \
     [ -e "$control_output/treeless.txt" ] || \
     [ -e "$control_output/staging.txt" ]
  then
    echo "$label must fail closed without publication" >&2
    exit 1
  fi
}

run_reject_control noncanonical-j NbeTransportJControl nonCanonicalJ
run_reject_control noncanonical-repeated NbeTransportHitControl nonCanonicalRepeated
run_reject_control noncanonical-winding NbeTransportS1Control nonCanonicalWinding
run_reject_control noncanonical-inverse NbeTransportS1Control nonCanonicalInverse

printf 'scenario\tresult\ttreeless\tscheme\tfragment\texpectation\n' \
  > "$evidence_dir/summary.tsv"
printf 't12\tpos-2\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't13\tpos-1\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't14\t41\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't15\ttrue\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-j\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-repeated\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-winding\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-inverse\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"

echo "NbE adapter exact TransportHit PASS (t12/t13=pos 2/pos 1 via S1 winding; t14=41; t15=true; 4 controls rejected)"
