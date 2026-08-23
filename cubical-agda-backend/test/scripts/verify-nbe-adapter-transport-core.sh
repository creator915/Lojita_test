#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?set CUBICAL29_DIR to the pinned Cubical source tree}"

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
projection="$backend_dir/test/fixtures/transport/TransportCoreB.agda"
binary="$backend_dir/build/agda29/cubical-chez"
spike_binary="$backend_dir/build/agda29/cubical-chez-nbe-adapter-spike"
evidence_dir="$backend_dir/build/agda29/evidence/NbeAdapterTransportCore"
transport_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
projection_sha256=e7d5339ff03e7153baf8b26a2178c8dc4c198b18144721e3a562a8153493c105

if [ ! -f "$agda_source_dir/Agda.cabal" ] || \
   [ ! -f "$cubical_source_dir/cubical.agda-lib" ] || \
   [ ! -x "$binary" ] || [ ! -x "$spike_binary" ]
then
  echo "Pinned sources or Agda 2.9 adapter binaries are unavailable; run verify-agda29 first" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
actual_projection_sha256=$(shasum -a 256 "$projection" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_sha256" ] || \
   [ "$actual_projection_sha256" != "$projection_sha256" ]
then
  echo "TransportTests source or TransportCoreB projection SHA-256 mismatch" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
for scenario in t09 t10
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

workspace_dir=$(mktemp -d /private/tmp/agda29-nbe-transport-core.XXXXXX)
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
cp "$projection" "$workspace_input_dir/TransportCoreB.agda"

run_success() {
  label=$1
  engine=$2
  runner=$3
  entry=$4
  case_dir="$evidence_dir/$label"
  output_dir="$case_dir/output"

  mkdir -p "$output_dir"
  rm -f "$workspace_input_dir/TransportCoreB.agdai" \
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
    --cubical-chez-entry="TransportCoreB.$entry" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportCoreB.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$output_dir/program.ss" > "$case_dir/observed.txt"
}

for scenario in t09 t10
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

sigma_staging="$evidence_dir/spike-t09/output/staging.txt"
if ! grep -Fqx \
     '#(agda_Agda_2e_Builtin_2e_Sigma_2e__5f__2c__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) 3)' \
     "$evidence_dir/spike-t09/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$sigma_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$sigma_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$sigma_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$sigma_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 1' "$sigma_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 0' "$sigma_staging" || \
   ! grep -Fqx \
     'nbe-structured-transport-normalizer: builtin-sigma-stable-second+list-parameter-map-v1' \
     "$sigma_staging"
then
  echo "t09 did not exercise canonical Sigma transport" >&2
  exit 1
fi

list_staging="$evidence_dir/spike-t10/output/staging.txt"
expected_list='#(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5b__5d_))))'
if ! grep -Fqx "$expected_list" "$evidence_dir/spike-t10/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$list_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$list_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$list_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$list_staging" || \
   ! grep -Fqx 'nbe-record-transports-reduced: 0' "$list_staging" || \
   ! grep -Fqx 'nbe-data-transports-reduced: 1' "$list_staging"
then
  echo "t10 did not exercise canonical builtin List transport" >&2
  exit 1
fi

run_reject_control() {
  label=$1
  entry=$2
  control_dir="$evidence_dir/reject-$label"
  control_output="$control_dir/output"
  mkdir -p "$control_output"
  rm -f "$workspace_input_dir/TransportCoreB.agdai" \
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
    --cubical-chez-entry="TransportCoreB.$entry" \
    --cubical-chez-output="$control_output" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportCoreB.agda" \
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

run_reject_control noncanonical-sigma nonCanonicalSigma
run_reject_control noncanonical-list nonCanonicalList

printf 'scenario\tresult\ttreeless\tscheme\tfragment\texpectation\n' \
  > "$evidence_dir/summary.tsv"
printf 't09\tfalse-pair-3\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't10\tfalse-true-false-list\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-sigma\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-list\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"

echo "NbE adapter exact TransportCore PASS (t09=Sigma false/3; t10=List false/true/false; 2 controls rejected)"
