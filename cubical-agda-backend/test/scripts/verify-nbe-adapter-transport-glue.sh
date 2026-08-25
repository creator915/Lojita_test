#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?set CUBICAL29_DIR to the pinned Cubical source tree}"

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
projection="$backend_dir/test/fixtures/transport/TransportGlue.agda"
binary="$backend_dir/build/agda29/cubical-chez"
spike_binary="$backend_dir/build/agda29/cubical-chez-nbe-adapter-spike"
evidence_dir="$backend_dir/build/agda29/evidence/NbeAdapterTransportGlue"
transport_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
projection_sha256=8b794b5d6d8423953386081cc6af921a6a2af343342bdfd6c0984ee1d9a04680

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
  echo "TransportTests source or TransportGlue projection SHA-256 mismatch" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
for scenario in t03 t04 t08
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

workspace_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-nbe-transport-glue.XXXXXX")
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
cp "$projection" "$workspace_input_dir/TransportGlue.agda"

run_success() {
  label=$1
  engine=$2
  runner=$3
  entry=$4
  case_dir="$evidence_dir/$label"
  output_dir="$case_dir/output"

  mkdir -p "$output_dir"
  rm -f "$workspace_input_dir/TransportGlue.agdai" \
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
    --cubical-chez-entry="TransportGlue.$entry" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportGlue.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$output_dir/program.ss" > "$case_dir/observed.txt"
}

for scenario in t03 t04 t08 varyingCodomainPi semanticConstantCodomainPi dependentSelfPathPi dependentSingletonPi reversedDependentSingletonPi nestedDependentSingletonPi reversedNestedDependentSingletonPi dependentSigmaSpinePi reversedDependentSigmaSpinePi varyingSigmaSpineFieldsPi dependentAliasSigmaFieldPi stableDependentSigmaFieldPi parameterizedStableDependentSigmaFieldPi stableDataRecordDependentSigmaFieldPi stableFunctionRecordDependentSigmaFieldPi stableDirectFunctionDependentSigmaFieldPi outerIndexedFunctionDependentSigmaFieldPi groundPayloadIndexedFunctionDependentSigmaFieldPi
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

spike_staging="$evidence_dir/spike-t03/output/staging.txt"
if ! grep -q 'Bool_2e_false)' "$evidence_dir/spike-t03/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$spike_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$spike_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$spike_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$spike_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 0' "$spike_staging" || \
   ! grep -Eq '^nbe-path-applications-evaluated: ([1-9][0-9]*)$' "$spike_staging" || \
   ! grep -Fqx \
     'nbe-path-application-policy: closure+constructor+definition+primitive+comp-beta-v3' \
     "$spike_staging" || \
   ! grep -Fqx \
     'nbe-glue-normalizer: introduction-elimination-cancellation+canonical-ua-bidirectional+double-composition+probe-hcomp-v6' \
     "$spike_staging"
then
  echo "t03 did not exercise the canonical Glue/ua transport rule" >&2
  exit 1
fi

composed_staging="$evidence_dir/spike-t04/output/staging.txt"
if ! grep -q 'Bool_2e_true)' "$evidence_dir/spike-t04/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$composed_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$composed_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$composed_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$composed_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 1' "$composed_staging" || \
   ! grep -Eq '^nbe-path-applications-evaluated: ([1-9][0-9]*)$' \
     "$composed_staging"
then
  echo "t04 did not exercise the canonical double-composition Glue rule" >&2
  exit 1
fi

pi_staging="$evidence_dir/spike-t08/output/staging.txt"
if ! grep -q 'Bool_2e_false)' "$evidence_dir/spike-t08/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' "$pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$pi_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 0' "$pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' "$pi_staging" || \
   ! grep -Fqx 'nbe-varying-pi-codomain-transports-reduced: 0' "$pi_staging" || \
   ! grep -Fqx 'nbe-semantic-constant-pi-codomain-transports-reduced: 0' \
     "$pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 0' \
     "$pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$pi_staging" || \
   ! grep -Fqx \
     'nbe-pi-transport-normalizer: canonical-domain+stable+semantic-constant+canonical+self-path+bidirectional-singleton+bidirectional-nested-singleton+probe-shell-identity+dependent-alias+per-layer-stable-identity+parameterized-stable-identity+metadata-constructor-stable-identity+closed-function-readback+closed-pi-type-readback+outer-parameter-indexed-pi-field+ground-payload-indexed-pi-field+fieldwise-bidirectional-bounded-sigma-spine-codomain+opaque-binder+isomorphism-proof-roundtrip-v19' \
     "$pi_staging"
then
  echo "t08 did not exercise canonical-domain Pi transport" >&2
  exit 1
fi

varying_pi_staging="$evidence_dir/spike-varyingCodomainPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-varyingCodomainPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$varying_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-composed-glue-transports-reduced: 0' \
     "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-varying-pi-codomain-transports-reduced: 1' \
     "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-semantic-constant-pi-codomain-transports-reduced: 0' \
     "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 0' \
     "$varying_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$varying_pi_staging"
then
  echo "varyingCodomainPi did not exercise canonical domain/codomain Pi transport" >&2
  exit 1
fi

semantic_constant_pi_staging="$evidence_dir/spike-semanticConstantCodomainPi/output/staging.txt"
if ! grep -q 'Bool_2e_false)' \
     "$evidence_dir/spike-semanticConstantCodomainPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 10' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-varying-pi-codomain-transports-reduced: 0' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-semantic-constant-pi-codomain-transports-reduced: 1' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 0' \
     "$semantic_constant_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$semantic_constant_pi_staging"
then
  echo "semanticConstantCodomainPi did not exercise opaque-binder semantic stability" >&2
  exit 1
fi

dependent_self_path_pi_staging="$evidence_dir/spike-dependentSelfPathPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-dependentSelfPathPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 11' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-varying-pi-codomain-transports-reduced: 0' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-semantic-constant-pi-codomain-transports-reduced: 0' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 1' \
     "$dependent_self_path_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_self_path_pi_staging"
then
  echo "dependentSelfPathPi did not exercise guarded dependent self-path transport" >&2
  exit 1
fi

dependent_singleton_pi_staging="$evidence_dir/spike-dependentSingletonPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-dependentSingletonPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-varying-pi-codomain-transports-reduced: 0' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-semantic-constant-pi-codomain-transports-reduced: 0' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 0' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 1' \
     "$dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_singleton_pi_staging"
then
  echo "dependentSingletonPi did not exercise guarded dependent singleton transport" >&2
  exit 1
fi

reversed_dependent_singleton_pi_staging="$evidence_dir/spike-reversedDependentSingletonPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-reversedDependentSingletonPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-self-path-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: 1' \
     "$reversed_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_singleton_pi_staging"
then
  echo "reversedDependentSingletonPi did not exercise its directed singleton transport" >&2
  exit 1
fi

nested_dependent_singleton_pi_staging="$evidence_dir/spike-nestedDependentSingletonPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-nestedDependentSingletonPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 31' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: 0' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$nested_dependent_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$nested_dependent_singleton_pi_staging"
then
  echo "nestedDependentSingletonPi did not exercise guarded nested singleton transport" >&2
  exit 1
fi

reversed_nested_singleton_pi_staging="$evidence_dir/spike-reversedNestedDependentSingletonPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-reversedNestedDependentSingletonPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 31' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_nested_singleton_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$reversed_nested_singleton_pi_staging"
then
  echo "reversedNestedDependentSingletonPi did not exercise its directed nested transport" >&2
  exit 1
fi

dependent_sigma_spine_pi_staging="$evidence_dir/spike-dependentSigmaSpinePi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-dependentSigmaSpinePi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 43' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 1' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-sigma-spine-pi-codomain-transports-reduced: 0' \
     "$dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 0' \
     "$dependent_sigma_spine_pi_staging"
then
  echo "dependentSigmaSpinePi did not exercise bounded recursive Sigma transport" >&2
  exit 1
fi

reversed_dependent_sigma_spine_pi_staging="$evidence_dir/spike-reversedDependentSigmaSpinePi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-reversedDependentSigmaSpinePi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 43' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 0' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-sigma-spine-pi-codomain-transports-reduced: 1' \
     "$reversed_dependent_sigma_spine_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 0' \
     "$reversed_dependent_sigma_spine_pi_staging"
then
  echo "reversedDependentSigmaSpinePi did not exercise directed recursive Sigma transport" >&2
  exit 1
fi

varying_sigma_spine_fields_pi_staging="$evidence_dir/spike-varyingSigmaSpineFieldsPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-varyingSigmaSpineFieldsPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 43' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 1' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-sigma-spine-pi-codomain-transports-reduced: 0' \
     "$varying_sigma_spine_fields_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 2' \
     "$varying_sigma_spine_fields_pi_staging"
then
  echo "varyingSigmaSpineFieldsPi did not transport both auxiliary points" >&2
  exit 1
fi

dependent_alias_sigma_field_pi_staging="$evidence_dir/spike-dependentAliasSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-dependentAliasSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 31' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-reversed-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 0' \
     "$dependent_alias_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 1' \
     "$dependent_alias_sigma_field_pi_staging"
then
  echo "dependentAliasSigmaFieldPi did not preserve probe-identical dependent field transport" >&2
  exit 1
fi

stable_dependent_sigma_field_pi_staging="$evidence_dir/spike-stableDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-stableDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 0' \
     "$stable_dependent_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 1' \
     "$stable_dependent_sigma_field_pi_staging"
then
  echo "stableDependentSigmaFieldPi did not preserve its stable auxiliary field" >&2
  exit 1
fi

parameterized_stable_sigma_field_pi_staging="$evidence_dir/spike-parameterizedStableDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-parameterizedStableDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 0' \
     "$parameterized_stable_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 1' \
     "$parameterized_stable_sigma_field_pi_staging"
then
  echo "parameterizedStableDependentSigmaFieldPi did not preserve its closed List field" >&2
  exit 1
fi

stable_data_record_sigma_field_pi_staging="$evidence_dir/spike-stableDataRecordDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-stableDataRecordDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Eq '^nbe-neutral-record-type-heads-preserved: ([1-9][0-9]*)$' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Eq '^nbe-neutral-data-type-heads-preserved: ([1-9][0-9]*)$' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 0' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 1' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-fields-transported: 0' \
     "$stable_data_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 2' \
     "$stable_data_record_sigma_field_pi_staging"
then
  echo "stableDataRecordDependentSigmaFieldPi did not preserve both metadata-checked fields" >&2
  exit 1
fi

stable_function_record_sigma_field_pi_staging="$evidence_dir/spike-stableFunctionRecordDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-stableFunctionRecordDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-pi-codomain-transports-reduced: 0' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 1' \
     "$stable_function_record_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-function-values-validated: 1' \
     "$stable_function_record_sigma_field_pi_staging"
then
  echo "stableFunctionRecordDependentSigmaFieldPi did not validate and apply its closed function" >&2
  exit 1
fi

stable_direct_function_sigma_field_pi_staging="$evidence_dir/spike-stableDirectFunctionDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-stableDirectFunctionDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-function-values-validated: 1' \
     "$stable_direct_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-pi-type-views-validated: 3' \
     "$stable_direct_function_sigma_field_pi_staging"
then
  echo "stableDirectFunctionDependentSigmaFieldPi did not validate its closed Pi type and function" >&2
  exit 1
fi

outer_indexed_function_sigma_field_pi_staging="$evidence_dir/spike-outerIndexedFunctionDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-outerIndexedFunctionDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 0' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-indexed-pi-fields-transported: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-indexed-pi-field-applications-evaluated: 1' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-indexed-pi-ground-payload-fields-preserved: 0' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-function-values-validated: 0' \
     "$outer_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-pi-type-views-validated: 0' \
     "$outer_indexed_function_sigma_field_pi_staging"
then
  echo "outerIndexedFunctionDependentSigmaFieldPi did not remap and apply its indexed function" >&2
  exit 1
fi

ground_payload_indexed_function_sigma_field_pi_staging="$evidence_dir/spike-groundPayloadIndexedFunctionDependentSigmaFieldPi/output/staging.txt"
if ! grep -q 'Bool_2e_true)' \
     "$evidence_dir/spike-groundPayloadIndexedFunctionDependentSigmaFieldPi/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-path-applications-evaluated: 13' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-glue-transports-reduced: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-pi-transports-reduced: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-nested-singleton-pi-codomain-transports-reduced: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-stable-fields-preserved: 0' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-dependent-sigma-spine-indexed-pi-fields-transported: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-indexed-pi-field-applications-evaluated: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-indexed-pi-ground-payload-fields-preserved: 1' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-function-values-validated: 0' \
     "$ground_payload_indexed_function_sigma_field_pi_staging" || \
   ! grep -Fqx 'nbe-closed-stable-pi-type-views-validated: 0' \
     "$ground_payload_indexed_function_sigma_field_pi_staging"
then
  echo "groundPayloadIndexedFunctionDependentSigmaFieldPi did not preserve and pattern-match its Bool payload" >&2
  exit 1
fi

run_reject_control() {
  label=$1
  entry=$2
  control_dir="$evidence_dir/reject-$label"
  control_output="$control_dir/output"
  mkdir -p "$control_output"
  rm -f "$workspace_input_dir/TransportGlue.agdai" \
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
    --cubical-chez-entry="TransportGlue.$entry" \
    --cubical-chez-output="$control_output" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportGlue.agda" \
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

run_reject_control noncanonical-double-comp nonCanonicalDoubleComp
run_reject_control mismatched-dependent-sigma-field unsupportedMismatchedDependentSigmaFieldPi
run_reject_control binder-indexed-stable-sigma-field unsupportedBinderIndexedStableSigmaFieldPi
run_reject_control nested-payload-indexed-function-sigma-field unsupportedNestedPayloadIndexedFunctionSigmaFieldPi
if ! grep -q 'field argument has an unsupported constructor payload' \
  "$evidence_dir/reject-nested-payload-indexed-function-sigma-field/producer.stdout"
then
  echo "nested payload control did not reach the exact payload whitelist" >&2
  exit 1
fi
run_reject_control dependent-payload-type-indexed-function-sigma-field unsupportedDependentPayloadTypeIndexedFunctionSigmaFieldPi
if ! grep -q 'payload types depend on prior binders' \
  "$evidence_dir/reject-dependent-payload-type-indexed-function-sigma-field/producer.stdout"
then
  echo "dependent payload type control did not reach constructor-type independence" >&2
  exit 1
fi
run_reject_control transport-function-record-sigma-field unsupportedTransportFunctionRecordSigmaFieldPi
run_reject_control over-limit-dependent-sigma-pi unsupportedOverLimitDependentSigmaPi

printf 'scenario\tresult\ttreeless\tscheme\tfragment\texpectation\n' \
  > "$evidence_dir/summary.tsv"
printf 't03\tfalse\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't04\ttrue\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 't08\tfalse\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'varying-codomain-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'semantic-constant-codomain-pi\tfalse\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'dependent-self-path-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'dependent-singleton-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'reversed-dependent-singleton-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'nested-dependent-singleton-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'reversed-nested-dependent-singleton-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'dependent-sigma-spine-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'reversed-dependent-sigma-spine-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'varying-sigma-spine-fields-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'dependent-alias-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'stable-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'parameterized-stable-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'stable-data-record-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'stable-function-record-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'stable-direct-function-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'outer-indexed-function-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'ground-payload-indexed-function-dependent-sigma-field-pi\ttrue\tbaseline-equal\tbaseline-equal\tLOCAL-EXTENSION\tPASS\n' \
  >> "$evidence_dir/summary.tsv"
printf 'noncanonical-double-comp\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'mismatched-dependent-sigma-field\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'binder-indexed-stable-sigma-field\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'nested-payload-indexed-function-sigma-field\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'dependent-payload-type-indexed-function-sigma-field\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'transport-function-record-sigma-field\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"
printf 'over-limit-dependent-sigma-pi\tCCZ-NBE-UNSUPPORTED\tnone\tnone\tLOCAL-CONTROL\tEXPECTED-REJECT\n' \
  >> "$evidence_dir/summary.tsv"

echo "NbE adapter exact TransportGlue PASS (t03=false; t04=true; t08=false; varying Pi=true; semantic-constant Pi=false; dependent self-path Pi=true; dependent singleton Pi=true; reversed singleton Pi=true; nested singleton Pi=true; reversed nested singleton Pi=true; bounded Sigma spine Pi=true; reversed bounded Sigma spine Pi=true; fieldwise Sigma spine Pi=true; dependent alias Sigma field Pi=true; stable dependent Sigma field Pi=true; parameterized stable Sigma field Pi=true; stable data/record Sigma fields Pi=true; stable function record Sigma field Pi=true; stable direct function Sigma field Pi=true; outer-indexed function Sigma field Pi=true; ground-payload indexed function Sigma field Pi=true; 7 controls rejected)"
