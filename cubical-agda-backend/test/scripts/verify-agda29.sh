#!/bin/sh

set -eu

unset CUBICAL_CHEZ_TYPED_PROXY_MAX_COUNT \
  CUBICAL_CHEZ_TYPED_PROXY_MAX_BYTES || true

: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
agda29_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
ghc29=${GHC29:-ghc}
build_dir="$backend_dir/build/agda29"
evidence_dir="$build_dir/evidence/PacketPrimTransp"
binary="$build_dir/cubical-chez"
spike29_binary="$build_dir/cubical-chez-nbe-adapter-spike"
spike29_object_dir="$build_dir/ghc-nbe-adapter-spike"
candidate29_binary="$build_dir/cubical-chez-nbe-production-candidate"
candidate29_object_dir="$build_dir/ghc-nbe-production-candidate"
spike29_low_fuel_binary="$build_dir/cubical-chez-nbe-adapter-low-fuel"
spike29_low_fuel_object_dir="$build_dir/ghc-nbe-adapter-low-fuel"
spike29_bad_projection_binary="$build_dir/cubical-chez-nbe-adapter-bad-projection"
spike29_bad_projection_object_dir="$build_dir/ghc-nbe-adapter-bad-projection"
spike29_postulated_sort_binary="$build_dir/cubical-chez-nbe-adapter-postulated-sort"
spike29_postulated_sort_object_dir="$build_dir/ghc-nbe-adapter-postulated-sort"
spike29_evidence_dir="$build_dir/evidence/NbeAdapterSpike"
source_file="$evidence_dir/PacketResidual.agda"
packet_file="$evidence_dir/typed-residual.bin"
runtime_source_rel="src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs"
runtime_source="$agda29_source_dir/$runtime_source_rel"
runtime_patch="$backend_dir/compat/agda-2.9/runtime-safe-packet-decode.patch"

mkdir -p "$build_dir/ghc" "$evidence_dir" \
  "$spike29_object_dir" "$candidate29_object_dir" \
  "$spike29_low_fuel_object_dir" \
  "$spike29_bad_projection_object_dir" \
  "$spike29_postulated_sort_object_dir" \
  "$spike29_evidence_dir"
cp "$fixture_dir/PacketResidual.agda" "$source_file"

if [ ! -f "$runtime_source" ] || [ ! -f "$runtime_patch" ]; then
  echo "Agda29Packet: pinned runtime source or safety patch is missing" >&2
  exit 1
fi

# The locked v2 archive predates bounded/exception-safe packet decoding.  Apply
# the maintained backend patch for this build only, then restore the checkout
# even if compilation or a negative test fails.
runtime_backup=$(mktemp "$build_dir/runtime-source.XXXXXX")
runtime_source_changed=0
restore_runtime_source() {
  if [ "$runtime_source_changed" -eq 1 ]; then
    cp "$runtime_backup" "$runtime_source"
  fi
  rm -f "$runtime_backup"
}
trap restore_runtime_source EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if patch -s -f --dry-run -d "$agda29_source_dir" -p1 < "$runtime_patch"; then
  cp "$runtime_source" "$runtime_backup"
  runtime_source_changed=1
  patch -s -d "$agda29_source_dir" -p1 < "$runtime_patch"
elif patch -s -f -R --dry-run -d "$agda29_source_dir" -p1 < "$runtime_patch"; then
  : # The caller supplied an already-hardened source tree.
else
  echo "Agda29Packet: runtime safety patch does not match the pinned source" >&2
  exit 1
fi

(
  cd "$agda29_source_dir"
  cabal build -w "$ghc29" lib:Agda exe:agda-cubical-run
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror -DCUBICAL_CHEZ_AGDA_29 \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$build_dir/ghc" \
    -o "$binary" \
    "$backend_dir/src/Main.hs"
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror \
    -DCUBICAL_CHEZ_AGDA_29 \
    -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$spike29_object_dir" \
    -o "$spike29_binary" \
    "$backend_dir/src/Main.hs"
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror \
    -DCUBICAL_CHEZ_AGDA_29 \
    -DCUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE \
    -DCUBICAL_CHEZ_NBE_PROVIDER_SELECTED \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$candidate29_object_dir" \
    -o "$candidate29_binary" \
    "$backend_dir/src/Main.hs"
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror \
    -DCUBICAL_CHEZ_AGDA_29 \
    -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
    -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_LOW_FUEL \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$spike29_low_fuel_object_dir" \
    -o "$spike29_low_fuel_binary" \
    "$backend_dir/src/Main.hs"
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror \
    -DCUBICAL_CHEZ_AGDA_29 \
    -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
    -DCUBICAL_CHEZ_TEST_NBE_BAD_PROJECTION_RECEIVER \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$spike29_bad_projection_object_dir" \
    -o "$spike29_bad_projection_binary" \
    "$backend_dir/src/Main.hs"
  cabal exec -w "$ghc29" -- "$ghc29" \
    -O0 -Wall -Werror \
    -DCUBICAL_CHEZ_AGDA_29 \
    -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
    -DCUBICAL_CHEZ_TEST_NBE_POSTULATED_SORT \
    -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$spike29_postulated_sort_object_dir" \
    -o "$spike29_postulated_sort_binary" \
    "$backend_dir/src/Main.hs"
)

run_spike29_case() {
  label=$1
  engine=$2
  entry=$3
  runner_binary=$4
  source_fixture=${5:-$fixture_dir/NbeAdapterSpike.agda}
  module_file=${6:-NbeAdapterSpike.agda}
  module_name=${module_file%.agda}
  case_dir="$spike29_evidence_dir/$label"

  mkdir -p "$case_dir"
  cp "$source_fixture" "$case_dir/$module_file"
  Agda_datadir="$agda29_source_dir/src/data" "$runner_binary" \
    -v0 \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-output="$case_dir" \
    --cubical-chez-entry="$module_name.$entry" \
    --no-libraries \
    --no-write-interfaces \
    -i "$case_dir" \
    "$case_dir/$module_file" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$case_dir/program.ss" > "$case_dir/observed.txt"
}

run_spike29_case baseline-main agda-baseline main "$binary"
run_spike29_case spike-main nbe main "$spike29_binary"
run_spike29_case baseline-once agda-baseline once "$binary"
run_spike29_case spike-once nbe once "$spike29_binary"
run_spike29_case baseline-recursive-nat agda-baseline main "$binary" \
  "$fixture_dir/StaticOrdinary.agda" StaticOrdinary.agda
run_spike29_case spike-recursive-nat nbe main "$spike29_binary" \
  "$fixture_dir/StaticOrdinary.agda" StaticOrdinary.agda
run_spike29_case production-candidate-recursive-nat \
  nbe main "$candidate29_binary" \
  "$fixture_dir/StaticOrdinary.agda" StaticOrdinary.agda
run_spike29_case baseline-pi-universe agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikePi.agda" NbeAdapterSpikePi.agda
run_spike29_case spike-pi-universe nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikePi.agda" NbeAdapterSpikePi.agda
run_spike29_case baseline-general-data agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeData.agda" NbeAdapterSpikeData.agda
run_spike29_case spike-general-data nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeData.agda" NbeAdapterSpikeData.agda
run_spike29_case baseline-record agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeRecord.agda" NbeAdapterSpikeRecord.agda
run_spike29_case spike-record nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeRecord.agda" NbeAdapterSpikeRecord.agda
run_spike29_case baseline-dependent-record agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeDependentRecord.agda" \
  NbeAdapterSpikeDependentRecord.agda
run_spike29_case spike-dependent-record nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeDependentRecord.agda" \
  NbeAdapterSpikeDependentRecord.agda
run_spike29_case baseline-universe-alias agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeUniverseAlias.agda" \
  NbeAdapterSpikeUniverseAlias.agda
run_spike29_case spike-universe-alias nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeUniverseAlias.agda" \
  NbeAdapterSpikeUniverseAlias.agda
run_spike29_case baseline-primitive-nat agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikePrimitiveNat.agda" \
  NbeAdapterSpikePrimitiveNat.agda
run_spike29_case spike-primitive-nat nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikePrimitiveNat.agda" \
  NbeAdapterSpikePrimitiveNat.agda
run_spike29_case baseline-cubical-ground agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeCubicalGround.agda" \
  NbeAdapterSpikeCubicalGround.agda
run_spike29_case spike-cubical-ground nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeCubicalGround.agda" \
  NbeAdapterSpikeCubicalGround.agda
run_spike29_case baseline-neutral-cofibration agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case spike-neutral-cofibration nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case baseline-constant-nat-transport agda-baseline groundZero "$binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case spike-constant-nat-transport nbe groundZero "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case baseline-constant-nat-function-transport \
  agda-baseline functionZero "$binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case spike-constant-nat-function-transport \
  nbe functionZero "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeNeutralCofibration.agda" \
  NbeAdapterSpikeNeutralCofibration.agda
run_spike29_case baseline-glue-cancellation agda-baseline main "$binary" \
  "$fixture_dir/NbeAdapterSpikeGlueCancellation.agda" \
  NbeAdapterSpikeGlueCancellation.agda
run_spike29_case spike-glue-cancellation nbe main "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeGlueCancellation.agda" \
  NbeAdapterSpikeGlueCancellation.agda

for spike29_entry in main once
do
  if ! cmp -s \
       "$spike29_evidence_dir/baseline-$spike29_entry/observed.txt" \
       "$spike29_evidence_dir/spike-$spike29_entry/observed.txt" || \
     ! cmp -s \
       "$spike29_evidence_dir/baseline-$spike29_entry/treeless.txt" \
       "$spike29_evidence_dir/spike-$spike29_entry/treeless.txt" || \
     ! cmp -s \
       "$spike29_evidence_dir/baseline-$spike29_entry/program.ss" \
       "$spike29_evidence_dir/spike-$spike29_entry/program.ss"
  then
    echo "Agda29NbeAdapterSpike: $spike29_entry differs from baseline" >&2
    exit 1
  fi
done


for spike29_artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s \
       "$spike29_evidence_dir/baseline-pi-universe/$spike29_artifact" \
       "$spike29_evidence_dir/spike-pi-universe/$spike29_artifact"
  then
    echo "Agda29NbeAdapterSpike: Pi/Universe differs in $spike29_artifact" >&2
    exit 1
  fi
done

for candidate29_artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s \
       "$spike29_evidence_dir/baseline-recursive-nat/$candidate29_artifact" \
       "$spike29_evidence_dir/production-candidate-recursive-nat/$candidate29_artifact"
  then
    echo "Agda29NbeProductionCandidate: recursive Nat differs in $candidate29_artifact" >&2
    exit 1
  fi
done

candidate29_staging="$spike29_evidence_dir/production-candidate-recursive-nat/staging.txt"
if ! grep -Fqx 'engine-requested: nbe' "$candidate29_staging" || \
   ! grep -Fqx 'engine-effective: nbe' "$candidate29_staging" || \
   ! grep -Fqx 'nbe-adapter-status: production-candidate-selected' \
     "$candidate29_staging" || \
   ! grep -Fqx 'nbe-adapter-production-readiness: candidate-not-accepted' \
     "$candidate29_staging" || \
   ! grep -Fqx 'nbe-adapter-implementation: agda-specific-in-process-v1' \
     "$candidate29_staging" || \
   ! grep -Fqx 'nbe-adapter-linkage: production-candidate' \
     "$candidate29_staging" || \
   ! grep -Fqx 'nbe-provider-lock-status: selected-build-key' \
     "$candidate29_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$candidate29_staging" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/production-candidate-recursive-nat/observed.txt"
then
  echo "Agda29NbeProductionCandidate: provenance is incomplete" >&2
  exit 1
fi

for spike29_case in \
  general-data record dependent-record universe-alias primitive-nat \
  cubical-ground neutral-cofibration constant-nat-transport \
  constant-nat-function-transport glue-cancellation
do
  for spike29_artifact in observed.txt treeless.txt program.ss
  do
    if ! cmp -s \
         "$spike29_evidence_dir/baseline-$spike29_case/$spike29_artifact" \
         "$spike29_evidence_dir/spike-$spike29_case/$spike29_artifact"
    then
      echo "Agda29NbeAdapterSpike: $spike29_case differs in $spike29_artifact" >&2
      exit 1
    fi
  done
done

for spike29_artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s \
       "$spike29_evidence_dir/baseline-recursive-nat/$spike29_artifact" \
       "$spike29_evidence_dir/spike-recursive-nat/$spike29_artifact"
  then
    echo "Agda29NbeAdapterSpike: recursive Nat differs in $spike29_artifact" >&2
    exit 1
  fi
done

if ! grep -q 'Bool_2e_true)' \
     "$spike29_evidence_dir/spike-main/observed.txt" || \
   ! grep -q 'Bool_2e_false)' \
     "$spike29_evidence_dir/spike-once/observed.txt" || \
   ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-adapter-status: experimental-test-only' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-adapter-profile: ordinary-closures-data-record-universe-primitive-cubical-glue-ua-hit-v36' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-term-normalizer: environment-closure-data-record+primitive+neutral-cubical-glue-ua-hit-eval-readback-v35' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-hit-pattern-policy: exact-definition-or-primitive-head+checked-subpatterns-v2' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx \
     'nbe-type-normalizer: semantic-type+sort+level+alias-eval-readback-v1' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   grep -q 'agda-oracle' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'engine-result-agda-checked: true' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/spike-recursive-nat/observed.txt" || \
   ! grep -Eq '^nbe-definition-cache-hits: ([1-9][0-9]*)$' \
     "$spike29_evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -Fqx 'nbe-definition-cache-misses: 1' \
     "$spike29_evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -Fqx 'nbe-maximum-call-depth: 22' \
     "$spike29_evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -Fqx 'nbe-type-nodes-evaluated: 5' \
     "$spike29_evidence_dir/spike-pi-universe/staging.txt" || \
   ! grep -Fqx 'nbe-sort-nodes-evaluated: 6' \
     "$spike29_evidence_dir/spike-pi-universe/staging.txt" || \
   ! grep -Fqx 'nbe-level-nodes-evaluated: 6' \
     "$spike29_evidence_dir/spike-pi-universe/staging.txt" || \
   ! grep -Fqx '9' \
     "$spike29_evidence_dir/spike-general-data/observed.txt" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/spike-record/observed.txt" || \
   ! grep -Fqx 'nbe-record-projections-evaluated: 1' \
     "$spike29_evidence_dir/spike-record/staging.txt" || \
   ! grep -Fqx 'nbe-record-projections-evaluated: 2' \
     "$spike29_evidence_dir/spike-dependent-record/staging.txt" || \
   ! grep -Fqx 'nbe-definitions-reduced: 1' \
     "$spike29_evidence_dir/spike-universe-alias/staging.txt" || \
   ! grep -Fqx 'nbe-maximum-level-atom-count: 2' \
     "$spike29_evidence_dir/spike-universe-alias/staging.txt" || \
   ! grep -Fqx 'nbe-postulated-sort-policy: reject-v1' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-primitive-registry: agda-primitive-id-v4' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-cofibration-normalizer: endpoint+neutral-identities-v1' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-constant-family-transport: exact-builtin-nat+nat-to-nat+universe-v3' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-path-application-policy: closure+constructor+definition+primitive+comp-beta-v3' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-glue-normalizer: introduction-elimination-cancellation+canonical-ua-bidirectional+double-composition+probe-hcomp-v6' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-pi-transport-normalizer: canonical-domain+stable+semantic-constant+canonical+self-path+bidirectional-singleton+bidirectional-nested-singleton+probe-shell-identity+dependent-alias+per-layer-stable-identity+parameterized-stable-identity+metadata-constructor-stable-identity+closed-function-readback+closed-pi-type-readback+outer-parameter-indexed-pi-field+ground-payload-indexed-pi-field+fieldwise-bidirectional-bounded-sigma-spine-codomain+opaque-binder+isomorphism-proof-roundtrip-v19' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-structured-transport-normalizer: builtin-sigma-stable-second+list-parameter-map-v1' \
     "$spike29_evidence_dir/spike-main/staging.txt" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 3' \
     "$spike29_evidence_dir/spike-primitive-nat/staging.txt" || \
   ! grep -Fqx 'nbe-primitives-reduced: 3' \
     "$spike29_evidence_dir/spike-primitive-nat/staging.txt" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/spike-cubical-ground/observed.txt" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 6' \
     "$spike29_evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -Fqx 'nbe-primitives-reduced: 6' \
     "$spike29_evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -Fqx 'nbe-interval-operations-evaluated: 4' \
     "$spike29_evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$spike29_evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -Fqx 'nbe-hcomps-reduced: 1' \
     "$spike29_evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 5' \
     "$spike29_evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -Fqx 'nbe-primitives-reduced: 4' \
     "$spike29_evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -Fqx 'nbe-interval-operations-evaluated: 3' \
     "$spike29_evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -Fqx 'nbe-neutral-cofibration-simplifications: 3' \
     "$spike29_evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -Fqx 'nbe-constant-nat-transports-reduced: 1' \
     "$spike29_evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/spike-constant-nat-transport/observed.txt" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 1' \
     "$spike29_evidence_dir/spike-constant-nat-transport/staging.txt" || \
   ! grep -Fqx 'nbe-constant-nat-transports-reduced: 1' \
     "$spike29_evidence_dir/spike-constant-nat-transport/staging.txt" || \
   ! grep -Fqx '4' \
     "$spike29_evidence_dir/spike-constant-nat-function-transport/observed.txt" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$spike29_evidence_dir/spike-constant-nat-function-transport/staging.txt" || \
   ! grep -Fqx 'nbe-constant-nat-function-transports-reduced: 1' \
     "$spike29_evidence_dir/spike-constant-nat-function-transport/staging.txt" || \
   ! grep -Fqx '42' \
     "$spike29_evidence_dir/spike-glue-cancellation/observed.txt" || \
   ! grep -Fqx 'nbe-primitive-registry-hits: 2' \
     "$spike29_evidence_dir/spike-glue-cancellation/staging.txt" || \
   ! grep -Fqx 'nbe-primitives-reduced: 1' \
     "$spike29_evidence_dir/spike-glue-cancellation/staging.txt" || \
   ! grep -Fqx 'nbe-glue-unglue-cancellations: 1' \
     "$spike29_evidence_dir/spike-glue-cancellation/staging.txt"
then
  echo "Agda29NbeAdapterSpike: capability or admission evidence is incomplete" >&2
  exit 1
fi

run_spike29_reject() {
  label=$1
  runner_binary=$2
  source_fixture=$3
  module_file=$4
  expected_code=$5
  module_name=${module_file%.agda}
  case_dir="$spike29_evidence_dir/$label"

  mkdir -p "$case_dir"
  cp "$source_fixture" "$case_dir/$module_file"
  for publication in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    printf 'stale adapter spike artifact\n' > "$case_dir/$publication"
  done
  set +e
  Agda_datadir="$agda29_source_dir/src/data" "$runner_binary" \
    -v0 \
    --cubical-chez \
    --cubical-chez-engine=nbe \
    --cubical-chez-output="$case_dir" \
    --cubical-chez-entry="$module_name.main" \
    --no-libraries \
    --no-write-interfaces \
    -i "$case_dir" \
    "$case_dir/$module_file" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  producer_status=$?
  set -e

  actual_codes=$(grep -Eho 'CCZ-[A-Z-]+' \
    "$case_dir/producer.stdout" "$case_dir/producer.stderr" \
    | sort -u || true)
  if [ "$producer_status" -eq 0 ] || [ "$actual_codes" != "$expected_code" ]; then
    echo "Agda29NbeAdapterSpike: $label expected only $expected_code" >&2
    exit 1
  fi
  for publication in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    if [ -e "$case_dir/$publication" ]; then
      echo "Agda29NbeAdapterSpike: $label left $publication" >&2
      exit 1
    fi
  done
}

run_spike29_reject recursive-ground-cycle "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeCycle.agda" \
  NbeAdapterSpikeCycle.agda CCZ-NBE-FAILED
if ! grep -q 'recursive-cycle:' \
     "$spike29_evidence_dir/recursive-ground-cycle/producer.stdout" || \
   ! grep -q 'NbeAdapterSpikeCycle.loop' \
     "$spike29_evidence_dir/recursive-ground-cycle/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: recursive-cycle diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject deterministic-fuel-exhaustion \
  "$spike29_low_fuel_binary" "$fixture_dir/StaticOrdinary.agda" \
  StaticOrdinary.agda CCZ-ENGINE-TIMEOUT
if ! grep -q 'fuel-exhausted:' \
     "$spike29_evidence_dir/deterministic-fuel-exhaustion/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: fuel diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject invalid-record-projection-receiver \
  "$spike29_bad_projection_binary" \
  "$fixture_dir/NbeAdapterSpikeRecord.agda" \
  NbeAdapterSpikeRecord.agda CCZ-NBE-UNSUPPORTED
if ! grep -q 'receiver is neither a record constructor' \
     "$spike29_evidence_dir/invalid-record-projection-receiver/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: invalid projection receiver diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject postulated-sort-policy \
  "$spike29_postulated_sort_binary" \
  "$fixture_dir/NbeAdapterSpike.agda" \
  NbeAdapterSpike.agda CCZ-NBE-UNSUPPORTED
if ! grep -q 'postulated-sort-policy=reject-v1' \
     "$spike29_evidence_dir/postulated-sort-policy/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: postulated sort policy diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject unsupported-primitive "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikePrimitiveUnsupported.agda" \
  NbeAdapterSpikePrimitiveUnsupported.agda CCZ-NBE-UNSUPPORTED
if ! grep -q 'node-kind=Primitive(PrimStringAppend)' \
     "$spike29_evidence_dir/unsupported-primitive/producer.stdout" || \
   ! grep -q 'qname=Agda.Builtin.String.primStringAppend' \
     "$spike29_evidence_dir/unsupported-primitive/producer.stdout" || \
   ! grep -Eq 'source-range=.*Agda/Builtin/String.agda:[0-9]' \
     "$spike29_evidence_dir/unsupported-primitive/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: unsupported primitive diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject primitive-name-impostor "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikePrimitiveImpostor.agda" \
  NbeAdapterSpikePrimitiveImpostor.agda CCZ-NBE-UNSUPPORTED
if ! grep -q 'node-kind=Axiom' \
     "$spike29_evidence_dir/primitive-name-impostor/producer.stdout" || \
   ! grep -q 'qname=NbeAdapterSpikePrimitiveImpostor._+_' \
     "$spike29_evidence_dir/primitive-name-impostor/producer.stdout" || \
   ! grep -Eq 'source-range=.*NbeAdapterSpikePrimitiveImpostor.agda:[0-9]' \
     "$spike29_evidence_dir/primitive-name-impostor/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: primitive impostor diagnostic is missing" >&2
  exit 1
fi

run_spike29_reject unsupported-cubical-primitive "$spike29_binary" \
  "$fixture_dir/NbeAdapterSpikeCubicalUnsupported.agda" \
  NbeAdapterSpikeCubicalUnsupported.agda CCZ-NBE-UNSUPPORTED
if ! grep -q 'node-kind=Primitive(PrimFaceForall)' \
     "$spike29_evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -q 'qname=Agda.Builtin.Cubical.HCompU.primFaceForall' \
     "$spike29_evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -Eq 'source-range=.*Agda/Builtin/Cubical/HCompU.agda:[0-9]' \
     "$spike29_evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -q 'primitive is absent from agda-primitive-id-v4' \
     "$spike29_evidence_dir/unsupported-cubical-primitive/producer.stdout"
then
  echo "Agda29NbeAdapterSpike: unsupported Cubical primitive diagnostic is missing" >&2
  exit 1
fi

printf 'case\tresult\ttreeless\tscheme\nmain\ttrue\tbaseline-equal\tbaseline-equal\nonce\tfalse\tbaseline-equal\tbaseline-equal\nrecursive-nat\t42\tbaseline-equal\tbaseline-equal\npi-universe\tprocedure\tbaseline-equal\tbaseline-equal\ngeneral-data\t9\tbaseline-equal\tbaseline-equal\nrecord\t42\tbaseline-equal\tbaseline-equal\ndependent-record\tprocedure\tbaseline-equal\tbaseline-equal\nuniverse-alias\tprocedure\tbaseline-equal\tbaseline-equal\nprimitive-nat\t42\tbaseline-equal\tbaseline-equal\ncubical-ground\t42\tbaseline-equal\tbaseline-equal\nneutral-cofibration\tprocedure\tbaseline-equal\tbaseline-equal\nconstant-nat-transport\t42\tbaseline-equal\tbaseline-equal\nconstant-nat-function-transport\t4\tbaseline-equal\tbaseline-equal\nglue-cancellation\t42\tbaseline-equal\tbaseline-equal\n' \
  > "$spike29_evidence_dir/adapter-spike.tsv"
printf 'case\terror-code\tpublication\nrecursive-ground-cycle\tCCZ-NBE-FAILED\tnone\ndeterministic-fuel-exhaustion\tCCZ-ENGINE-TIMEOUT\tnone\ninvalid-record-projection-receiver\tCCZ-NBE-UNSUPPORTED\tnone\npostulated-sort-policy\tCCZ-NBE-UNSUPPORTED\tnone\nunsupported-primitive\tCCZ-NBE-UNSUPPORTED\tnone\nprimitive-name-impostor\tCCZ-NBE-UNSUPPORTED\tnone\nunsupported-cubical-primitive\tCCZ-NBE-UNSUPPORTED\tnone\n' \
  > "$spike29_evidence_dir/adapter-spike-rejections.tsv"

Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$evidence_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$evidence_dir" \
  "$source_file" \
  > "$evidence_dir/producer.log"

if [ ! -s "$packet_file" ]; then
  echo "Agda29Packet: producer did not write a non-empty packet" >&2
  exit 1
fi
if ! grep -q '^decision: typed-residual$' "$evidence_dir/staging.txt"; then
  echo "Agda29Packet: staging decision was not typed-residual" >&2
  exit 1
fi
if ! grep -q '^binding-time: dynamic$' "$evidence_dir/staging.txt"; then
  echo "Agda29Packet: binding-time classification was not dynamic" >&2
  exit 1
fi
if ! grep -q '^packet-codec: agda-utils-serialize$' \
  "$evidence_dir/typed-residual.txt"; then
  echo "Agda29Packet: manifest did not identify the v2 codec" >&2
  exit 1
fi
if ! grep -Fqx 'residual-contract: whole-entry-same-interface-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'chez-core-abi: chez-core-abi-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'chez-function-abi: unary-curried-closure-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'chez-data-constructor-abi: tagged-vector-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'chez-record-abi: tagged-vector-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'chez-primitive-application-abi: exact-arity-whitelist-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'chez-primitive-first-class-abi: curried-add-sub-mul-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -q '^chez-primitive-application-map: PAdd/2=+.*P64ToI/1=identity$' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'chez-primitive-first-class-map: PAdd=curried:+,PSub=curried:-,PMul=curried:*' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'residual-signature-identity: top-level-module+full-interface-hash' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-dependency-closure: exact-consumer-interface' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'residual-dependency-slice: checked-type+definition-body-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'residual-presentation-metadata: excluded-from-executable-slice' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Eq '^residual-direct-dependency-count: [1-9][0-9]*$' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -q '^residual-direct-dependencies: .*primTransp' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-closure-complete: true' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Eq '^residual-resolved-dependency-count: [1-9][0-9]*$' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-unresolved-dependencies: none' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-embedded-definitions: none' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-whole-signature-embedded: false' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'ground-codec-registry-version: ground-codec-registry-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx 'ground-codec-registry: bool,nat,word64,char,int' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'ground-codec-descriptor-version: ground-codec-descriptor-v1' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -Fqx \
  'ground-codec-descriptor-fields: codec,unary-abi,cli-prefix,validator,argument-reifier,entry-parser,value-reifier' \
  "$evidence_dir/typed-residual.txt"; then
  echo "Agda29Packet: minimal typed residual contract is incomplete" >&2
  exit 1
fi
if ! grep -q '^internal-term-blockers: .*primTransp' \
  "$evidence_dir/typed-residual.txt" || \
   ! grep -q '^treeless-blockers: .*primTransp' \
  "$evidence_dir/typed-residual.txt"; then
  echo "Agda29Packet: dual-layer audit did not retain primTransp" >&2
  exit 1
fi
if [ -e "$evidence_dir/program.ss" ]; then
  echo "Agda29Packet: typed residual incorrectly reached erased Scheme" >&2
  exit 1
fi

runner=$(
  cd "$agda29_source_dir"
  cabal list-bin -w "$ghc29" exe:agda-cubical-run
)
consumer_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$packet_file" \
    --no-libraries \
    --no-write-interfaces \
    -i "$evidence_dir" \
    "$source_file"
)

if [ "$consumer_result" != "true" ]; then
  echo "Agda29Packet: archived v2 consumer returned '$consumer_result'" >&2
  exit 1
fi

mixed_dir="$build_dir/evidence/MixedResidualSlicePlan"
mixed_source="$mixed_dir/MixedResidual.agda"
mixed_packet="$mixed_dir/typed-residual.bin"
mixed_hole_packet="$mixed_dir/typed-residual-hole-1.bin"
mixed_shell="$mixed_dir/residual-static-shell.ss"
mixed_bridge="$mixed_dir/typed-hole-ground-bridge.sh"
mixed_hole_id=typed-hole@app-argument-1
mkdir -p "$mixed_dir"
cp "$fixture_dir/MixedResidual.agda" "$mixed_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$mixed_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$mixed_dir" \
  "$mixed_source" \
  > "$mixed_dir/producer.log"
if [ ! -s "$mixed_packet" ] || \
   [ ! -s "$mixed_hole_packet" ] || \
   [ ! -s "$mixed_shell" ] || \
   [ ! -s "$mixed_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$mixed_dir/staging.txt" || \
   ! grep -Fqx 'residual-slice-plan: materialized-checked-internal' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-static-shell: emitted-ground-call-chez' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-artifact: residual-static-shell.ss' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-bridge-artifact: typed-hole-ground-bridge.sh' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-import-contract: opaque-import-v1' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-hole-forcing: closed-hole-ground-observation-by-id-v1' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: none' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-typed-source: checked-internal-subterm+type' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-count: 1' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-ids: typed-hole@app-argument-1' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -q '^residual-slice-hole-1-blockers: .*primTransp' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-materialization: checked' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-closed: true' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-source-closed: true' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 0' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-open-hole-closure-conversion: none' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-static-shell-environment-binding: none' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-binding-abi: none' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-meta-free: true' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-typechecked: true' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-callable-abi: none' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-artifact: typed-residual-hole-1.bin' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-direct-dependency-count: 4' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-resolved-dependency-count: 4' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-independent-artifacts: true' \
     "$mixed_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-ground-observation-by-id-whole-entry-reference' \
     "$mixed_dir/typed-residual.txt" || \
   [ -e "$mixed_dir/program.ss" ]
then
  echo "Agda29MixedPacket: mixed slice plan or whole-entry packet is invalid" >&2
  exit 1
fi
mixed_shell_result=$(chez --script "$mixed_shell")
if ! printf '%s\n' "$mixed_shell_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$mixed_shell_result" | \
     grep -q 'cubical-chez-typed-hole-import-v1' || \
   ! printf '%s\n' "$mixed_shell_result" | \
     grep -q 'typed-hole@app-argument-1' || \
   ! printf '%s\n' "$mixed_shell_result" | \
     grep -q 'typed-residual-hole-1.bin' || \
   grep -q 'primTransp' "$mixed_shell"
then
  echo "Agda29MixedShell: static shell/import output is invalid" >&2
  exit 1
fi
mixed_forced_bool=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$mixed_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$mixed_dir" \
  CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole \
  chez --script "$mixed_shell" --force-hole="$mixed_hole_id"
)
if ! printf '%s\n' "$mixed_forced_bool" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'; then
  echo "Agda29MixedBridge: forced Bool result is invalid" >&2
  exit 1
fi
mixed_forced_nat=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$mixed_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$mixed_dir" \
  CUBICAL_CHEZ_TYPED_CONSUMER=consumeHoleNat \
  chez --script "$mixed_shell" --force-hole="$mixed_hole_id"
)
if [ "$mixed_forced_nat" != 42 ]; then
  echo "Agda29MixedBridge: forced Nat result was '$mixed_forced_nat'" >&2
  exit 1
fi

set +e
chez --script "$mixed_shell" --force-hole="$mixed_hole_id" \
  > "$mixed_dir/bridge-missing-config.stdout" \
  2> "$mixed_dir/bridge-missing-config.stderr"
bridge_missing_status=$?
CUBICAL_CHEZ_TYPED_RUNNER=/usr/bin/false \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$mixed_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$mixed_dir" \
CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole \
chez --script "$mixed_shell" --force-hole="$mixed_hole_id" \
  > "$mixed_dir/bridge-runner-exit.stdout" \
  2> "$mixed_dir/bridge-runner-exit.stderr"
bridge_runner_status=$?
CUBICAL_CHEZ_TYPED_RUNNER=/bin/echo \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$mixed_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$mixed_dir" \
CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole \
chez --script "$mixed_shell" --force-hole="$mixed_hole_id" \
  > "$mixed_dir/bridge-dirty-output.stdout" \
  2> "$mixed_dir/bridge-dirty-output.stderr"
bridge_dirty_status=$?
set -e
if [ "$bridge_missing_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CONFIG' \
     "$mixed_dir/bridge-missing-config.stdout" \
     "$mixed_dir/bridge-missing-config.stderr" || \
   [ "$bridge_runner_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$mixed_dir/bridge-runner-exit.stdout" \
     "$mixed_dir/bridge-runner-exit.stderr" || \
   [ "$bridge_dirty_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-DIRTY-OUTPUT' \
     "$mixed_dir/bridge-dirty-output.stdout" \
     "$mixed_dir/bridge-dirty-output.stderr"
then
  echo "Agda29MixedBridge: forcing bridge did not fail closed" >&2
  exit 1
fi
mixed_consumer_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$mixed_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$mixed_dir" \
    "$mixed_source"
)
if [ "$mixed_consumer_result" != "true" ]; then
  echo "Agda29MixedPacket: consumer returned '$mixed_consumer_result'" >&2
  exit 1
fi
mixed_hole_consumer_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeHole \
    --cubical-term-file="$mixed_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$mixed_dir" \
    "$mixed_source"
)
if [ "$mixed_hole_consumer_result" != "true" ]; then
  echo "Agda29MixedHolePacket: consumer returned '$mixed_hole_consumer_result'" >&2
  exit 1
fi

open_dir="$build_dir/evidence/MixedOpenResidual"
open_source="$open_dir/MixedOpenResidual.agda"
open_packet="$open_dir/typed-residual.bin"
open_hole_packet="$open_dir/typed-residual-hole-1.bin"
open_shell="$open_dir/residual-static-shell.ss"
open_bridge="$open_dir/typed-hole-ground-bridge.sh"
open_hole_id=typed-hole@lambda-body.app-argument-1
mkdir -p "$open_dir"
cp "$fixture_dir/MixedOpenResidual.agda" "$open_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_dir" \
  "$open_source" \
  > "$open_dir/producer.log"
if [ ! -s "$open_packet" ] || \
   [ ! -s "$open_hole_packet" ] || \
   [ ! -s "$open_shell" ] || \
   [ ! -s "$open_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$open_dir/staging.txt" || \
   ! grep -Fqx 'residual-slice-plan: materialized-checked-internal' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-open-hole-closure-conversion: lambda-lifted-explicit-environment-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: single-bool-chez-lexical-binding-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-open-hole-environment-arity-limit: 64' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-typed-source: checked-internal-subterm+telescope+type' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-import-contract: opaque-lambda-lifted-import-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-hole-forcing: lambda-lifted-explicit-environment-observation-by-id-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: lambda-lifted-explicit-environment-ground-unary-elimination-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-single-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx "residual-slice-hole-ids: $open_hole_id" \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-source-closed: false' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-packet-closed: true' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-abi: lambda-lifted-explicit-environment-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: single-bool-chez-lexical-binding-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: bool-unary-ground-elimination-v1' \
     "$open_dir/typed-residual.txt" || \
   ! grep -q '^residual-slice-hole-1-term: λ captured' \
     "$open_dir/typed-residual.txt" || \
   [ -e "$open_dir/program.ss" ]
then
  echo "Agda29OpenClosurePacket: lambda-lifted publication is invalid" >&2
  exit 1
fi

open_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_dir" \
    "$open_source"
)
open_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_dir" \
    "$open_source"
)
open_forced_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_dir" \
  CUBICAL_CHEZ_TYPED_CONSUMER=consumeClosure \
  chez --script "$open_shell" --force-hole="$open_hole_id"
)
open_called_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_dir" \
  chez --script "$open_shell" \
    --call-bool-hole="$open_hole_id" \
    --bool-argument=true \
    --call-hole-type=OpenResidualClosure \
    --call-result-consumer=consumeResidual
)
if [ "$open_whole_result" != true ] || [ "$open_hole_result" != true ] || \
   ! printf '%s\n' "$open_forced_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_called_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'; then
  echo "Agda29OpenClosureBridge: explicit environment application failed" >&2
  exit 1
fi

set +e
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_dir" \
CUBICAL_CHEZ_TYPED_CONSUMER=consumeResidual \
chez --script "$open_shell" --force-hole="$open_hole_id" \
  > "$open_dir/open-environment-omitted.stdout" \
  2> "$open_dir/open-environment-omitted.stderr"
open_environment_omitted_status=$?
chez --script "$open_shell" \
  --call-nat-hole="$open_hole_id" \
  --nat-argument=1 \
  --call-hole-type=OpenResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$open_dir/open-environment-codec.stdout" \
  2> "$open_dir/open-environment-codec.stderr"
open_environment_codec_status=$?
set -e
if [ "$open_environment_omitted_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$open_dir/open-environment-omitted.stdout" \
     "$open_dir/open-environment-omitted.stderr" || \
   [ "$open_environment_codec_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$open_dir/open-environment-codec.stdout" \
     "$open_dir/open-environment-codec.stderr"
then
  echo "Agda29OpenClosureBridge: missing/wrong environment did not reject" >&2
  exit 1
fi

capture_dir="$open_dir"
capture_source="$open_source"
capture_shell="$open_shell"
capture_hole_id="$open_hole_id"
if ! grep -Fq \
     '(cubical-chez-bind-bool-environment (cubical-chez-typed-hole-reference' \
     "$capture_shell"
then
  echo "Agda29LexicalBoolCapture: binding capability is invalid" >&2
  exit 1
fi

capture_true_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$capture_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$capture_dir" \
  chez --script "$capture_shell" \
    --auto-bind-bool-hole="$capture_hole_id" \
    --entry-bool-argument=true \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
capture_false_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$capture_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$capture_dir" \
  chez --script "$capture_shell" \
    --auto-bind-bool-hole="$capture_hole_id" \
    --entry-bool-argument=false \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
if ! printf '%s\n' "$capture_true_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$capture_false_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29LexicalBoolCapture: Chez lexical values were not preserved" >&2
  exit 1
fi

set +e
chez --script "$capture_shell" \
  --auto-bind-bool-hole="$capture_hole_id" \
  --entry-bool-argument=invalid \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$capture_dir/invalid-environment.stdout" \
  2> "$capture_dir/invalid-environment.stderr"
capture_invalid_environment_status=$?
chez --script "$capture_shell" \
  --auto-bind-bool-hole=typed-hole@missing \
  --entry-bool-argument=true \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$capture_dir/missing-bound-hole.stdout" \
  2> "$capture_dir/missing-bound-hole.stderr"
capture_missing_hole_status=$?
chez --script "$capture_shell" \
  --auto-bind-bool-hole="$capture_hole_id" \
  > "$capture_dir/incomplete-auto-binding.stdout" \
  2> "$capture_dir/incomplete-auto-binding.stderr"
capture_incomplete_status=$?
chez --script "$capture_shell" \
  --auto-bind-bool-hole="$capture_hole_id" \
  --entry-bool-argument=true \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  --force-hole="$capture_hole_id" \
  > "$capture_dir/conflicting-auto-binding.stdout" \
  2> "$capture_dir/conflicting-auto-binding.stderr"
capture_conflict_status=$?
set -e
if [ "$capture_invalid_environment_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
     "$capture_dir/invalid-environment.stdout" \
     "$capture_dir/invalid-environment.stderr" || \
   [ "$capture_missing_hole_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
     "$capture_dir/missing-bound-hole.stdout" \
     "$capture_dir/missing-bound-hole.stderr" || \
   [ "$capture_incomplete_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
     "$capture_dir/incomplete-auto-binding.stdout" \
     "$capture_dir/incomplete-auto-binding.stderr" || \
   [ "$capture_conflict_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
     "$capture_dir/conflicting-auto-binding.stdout" \
     "$capture_dir/conflicting-auto-binding.stderr"
then
  echo "Agda29LexicalBoolCapture: invalid environment did not reject" >&2
  exit 1
fi

open_nat_dir="$build_dir/evidence/MixedOpenNatResidual"
open_nat_source="$open_nat_dir/MixedOpenNatResidual.agda"
open_nat_packet="$open_nat_dir/typed-residual.bin"
open_nat_hole_packet="$open_nat_dir/typed-residual-hole-1.bin"
open_nat_shell="$open_nat_dir/residual-static-shell.ss"
open_nat_bridge="$open_nat_dir/typed-hole-ground-bridge.sh"
open_nat_hole_id=typed-hole@lambda-body.app-argument-1
mkdir -p "$open_nat_dir"
cp "$fixture_dir/MixedOpenNatResidual.agda" "$open_nat_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_nat_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_nat_dir" \
  "$open_nat_source" \
  > "$open_nat_dir/producer.log"
if [ ! -s "$open_nat_packet" ] || \
   [ ! -s "$open_nat_hole_packet" ] || \
   [ ! -s "$open_nat_shell" ] || \
   [ ! -s "$open_nat_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$open_nat_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: single-nat-chez-lexical-binding-v1' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-single-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-source-closed: false' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 1' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: single-nat-chez-lexical-binding-v1' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: nat-unary-ground-elimination-v1' \
     "$open_nat_dir/typed-residual.txt" || \
   ! grep -Fq \
     '(cubical-chez-bind-nat-environment (cubical-chez-typed-hole-reference' \
     "$open_nat_shell"
then
  echo "Agda29LexicalNatCapture: binding capability is invalid" >&2
  exit 1
fi

open_nat_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_nat_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_nat_dir" \
    "$open_nat_source"
)
open_nat_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_nat_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_nat_dir" \
    "$open_nat_source"
)
open_nat_explicit_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_nat_dir" \
  chez --script "$open_nat_shell" \
    --call-nat-hole="$open_nat_hole_id" \
    --nat-argument=1 \
    --call-hole-type=OpenResidualClosure \
    --call-result-consumer=consumeResidual
)
open_nat_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_nat_dir" \
  chez --script "$open_nat_shell" \
    --auto-bind-nat-hole="$open_nat_hole_id" \
    --entry-nat-argument=0 \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
open_nat_one_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_nat_dir" \
  chez --script "$open_nat_shell" \
    --auto-bind-nat-hole="$open_nat_hole_id" \
    --entry-nat-argument=1 \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
if [ "$open_nat_whole_result" != true ] || \
   [ "$open_nat_hole_result" != true ] || \
   ! printf '%s\n' "$open_nat_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_nat_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_nat_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29LexicalNatCapture: Chez lexical values were not preserved" >&2
  exit 1
fi

set +e
chez --script "$open_nat_shell" \
  --auto-bind-nat-hole="$open_nat_hole_id" \
  --entry-nat-argument=-1 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_nat_dir/negative-environment.stdout" \
  2> "$open_nat_dir/negative-environment.stderr"
open_nat_negative_status=$?
chez --script "$open_nat_shell" \
  --auto-bind-nat-hole="$open_nat_hole_id" \
  --entry-nat-argument=4294967296 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_nat_dir/overflow-environment.stdout" \
  2> "$open_nat_dir/overflow-environment.stderr"
open_nat_overflow_status=$?
chez --script "$open_nat_shell" \
  --auto-bind-nat-hole=typed-hole@missing \
  --entry-nat-argument=0 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_nat_dir/missing-bound-hole.stdout" \
  2> "$open_nat_dir/missing-bound-hole.stderr"
open_nat_missing_status=$?
chez --script "$open_nat_shell" \
  --auto-bind-nat-hole="$open_nat_hole_id" \
  > "$open_nat_dir/incomplete-auto-binding.stdout" \
  2> "$open_nat_dir/incomplete-auto-binding.stderr"
open_nat_incomplete_status=$?
chez --script "$open_nat_shell" \
  --auto-bind-nat-hole="$open_nat_hole_id" \
  --entry-nat-argument=0 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  --force-hole="$open_nat_hole_id" \
  > "$open_nat_dir/conflicting-auto-binding.stdout" \
  2> "$open_nat_dir/conflicting-auto-binding.stderr"
open_nat_conflict_status=$?
set -e
for rejected in \
  negative-environment \
  overflow-environment \
  missing-bound-hole \
  incomplete-auto-binding \
  conflicting-auto-binding
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$open_nat_dir/$rejected.stdout" "$open_nat_dir/$rejected.stderr"
  then
    echo "Agda29LexicalNatCapture: $rejected has wrong failure code" >&2
    exit 1
  fi
done
if [ "$open_nat_negative_status" -eq 0 ] || \
   [ "$open_nat_overflow_status" -eq 0 ] || \
   [ "$open_nat_missing_status" -eq 0 ] || \
   [ "$open_nat_incomplete_status" -eq 0 ] || \
   [ "$open_nat_conflict_status" -eq 0 ]
then
  echo "Agda29LexicalNatCapture: invalid environment did not reject" >&2
  exit 1
fi

open_word64_dir="$build_dir/evidence/MixedOpenWord64Residual"
open_word64_source="$open_word64_dir/MixedOpenWord64Residual.agda"
open_word64_packet="$open_word64_dir/typed-residual.bin"
open_word64_hole_packet="$open_word64_dir/typed-residual-hole-1.bin"
open_word64_shell="$open_word64_dir/residual-static-shell.ss"
open_word64_bridge="$open_word64_dir/typed-hole-ground-bridge.sh"
open_word64_hole_id=typed-hole@lambda-body.app-argument-1
open_word64_max=18446744073709551615
open_word64_overflow=18446744073709551616
mkdir -p "$open_word64_dir"
cp "$fixture_dir/MixedOpenWord64Residual.agda" "$open_word64_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_word64_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_word64_dir" \
  "$open_word64_source" \
  > "$open_word64_dir/producer.log"
if [ ! -s "$open_word64_packet" ] || \
   [ ! -s "$open_word64_hole_packet" ] || \
   [ ! -s "$open_word64_shell" ] || \
   [ ! -s "$open_word64_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' \
     "$open_word64_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: single-word64-chez-lexical-binding-v1' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-single-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-source-closed: false' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 1' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: single-word64-chez-lexical-binding-v1' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: word64-unary-ground-elimination-v1' \
     "$open_word64_dir/typed-residual.txt" || \
   ! grep -Fq \
     '(cubical-chez-bind-word64-environment (cubical-chez-typed-hole-reference' \
     "$open_word64_shell"
then
  echo "Agda29LexicalWord64Capture: binding capability is invalid" >&2
  exit 1
fi

open_word64_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_word64_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_word64_dir" \
    "$open_word64_source"
)
open_word64_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_word64_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_word64_dir" \
    "$open_word64_source"
)
open_word64_explicit_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_word64_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_word64_dir" \
  chez --script "$open_word64_shell" \
    --call-word64-hole="$open_word64_hole_id" \
    --word64-argument="$open_word64_max" \
    --call-hole-type=OpenResidualClosure \
    --call-result-consumer=consumeResidual
)
open_word64_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_word64_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_word64_dir" \
  chez --script "$open_word64_shell" \
    --auto-bind-word64-hole="$open_word64_hole_id" \
    --entry-word64-argument=0 \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
open_word64_max_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_word64_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_word64_dir" \
  chez --script "$open_word64_shell" \
    --auto-bind-word64-hole="$open_word64_hole_id" \
    --entry-word64-argument="$open_word64_max" \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
if [ "$open_word64_whole_result" != true ] || \
   [ "$open_word64_hole_result" != true ] || \
   ! printf '%s\n' "$open_word64_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_word64_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_word64_max_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29LexicalWord64Capture: Chez lexical values were not preserved" >&2
  exit 1
fi

set +e
chez --script "$open_word64_shell" \
  --auto-bind-word64-hole="$open_word64_hole_id" \
  --entry-word64-argument=-1 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_word64_dir/negative-environment.stdout" \
  2> "$open_word64_dir/negative-environment.stderr"
open_word64_negative_status=$?
chez --script "$open_word64_shell" \
  --auto-bind-word64-hole="$open_word64_hole_id" \
  --entry-word64-argument="$open_word64_overflow" \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_word64_dir/overflow-environment.stdout" \
  2> "$open_word64_dir/overflow-environment.stderr"
open_word64_overflow_status=$?
chez --script "$open_word64_shell" \
  --auto-bind-nat-hole="$open_word64_hole_id" \
  --entry-nat-argument=0 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_word64_dir/wrong-codec.stdout" \
  2> "$open_word64_dir/wrong-codec.stderr"
open_word64_codec_status=$?
chez --script "$open_word64_shell" \
  --auto-bind-word64-hole=typed-hole@missing \
  --entry-word64-argument=0 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_word64_dir/missing-bound-hole.stdout" \
  2> "$open_word64_dir/missing-bound-hole.stderr"
open_word64_missing_status=$?
chez --script "$open_word64_shell" \
  --auto-bind-word64-hole="$open_word64_hole_id" \
  > "$open_word64_dir/incomplete-auto-binding.stdout" \
  2> "$open_word64_dir/incomplete-auto-binding.stderr"
open_word64_incomplete_status=$?
chez --script "$open_word64_shell" \
  --auto-bind-word64-hole="$open_word64_hole_id" \
  --entry-word64-argument=0 \
  --auto-bind-hole-type=OpenResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  --force-hole="$open_word64_hole_id" \
  > "$open_word64_dir/conflicting-auto-binding.stdout" \
  2> "$open_word64_dir/conflicting-auto-binding.stderr"
open_word64_conflict_status=$?
set -e
for rejected in \
  negative-environment \
  overflow-environment \
  wrong-codec \
  missing-bound-hole \
  incomplete-auto-binding \
  conflicting-auto-binding
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$open_word64_dir/$rejected.stdout" \
    "$open_word64_dir/$rejected.stderr"
  then
    echo "Agda29LexicalWord64Capture: $rejected has wrong failure code" >&2
    exit 1
  fi
done
if [ "$open_word64_negative_status" -eq 0 ] || \
   [ "$open_word64_overflow_status" -eq 0 ] || \
   [ "$open_word64_codec_status" -eq 0 ] || \
   [ "$open_word64_missing_status" -eq 0 ] || \
   [ "$open_word64_incomplete_status" -eq 0 ] || \
   [ "$open_word64_conflict_status" -eq 0 ]
then
  echo "Agda29LexicalWord64Capture: invalid environment did not reject" >&2
  exit 1
fi
printf 'mode\targument\tresult\nlexical\t0\ttrue\nlexical\t%s\tfalse\nexplicit\t%s\tfalse\nrejects\t-\t6\n' \
  "$open_word64_max" "$open_word64_max" \
  > "$open_word64_dir/word64-lexical.tsv"

open_ground_dir="$build_dir/evidence/MixedOpenGroundResidual"
open_ground_source="$open_ground_dir/MixedOpenGroundResidual.agda"
open_ground_packet="$open_ground_dir/typed-residual.bin"
open_ground_hole_packet="$open_ground_dir/typed-residual-hole-1.bin"
open_ground_shell="$open_ground_dir/residual-static-shell.ss"
open_ground_bridge="$open_ground_dir/typed-hole-ground-bridge.sh"
open_ground_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$open_ground_dir"
cp "$fixture_dir/MixedOpenGroundResidual.agda" "$open_ground_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_ground_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_ground_dir" \
  "$open_ground_source" \
  > "$open_ground_dir/producer.log"
if [ ! -s "$open_ground_packet" ] || \
   [ ! -s "$open_ground_hole_packet" ] || \
   [ ! -s "$open_ground_shell" ] || \
   [ ! -s "$open_ground_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$open_ground_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: ordered-ground-chez-lexical-binding-v1' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: lambda-lifted-explicit+lexical-ordered-ground-elimination-v1' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-ordered-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-source-closed: false' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 2' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: ordered-bool+nat-chez-lexical-binding-v1' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: ordered-bool+nat-ground-environment-elimination-v1' \
     "$open_ground_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-ground-environment' \
     "$open_ground_shell" || \
   ! grep -Fq '(vector "bool" "nat")' "$open_ground_shell"
then
  echo "Agda29OrderedGroundCapture: binding capability is invalid" >&2
  exit 1
fi

open_ground_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_ground_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_ground_dir" \
    "$open_ground_source"
)
open_ground_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_ground_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_ground_dir" \
    "$open_ground_source"
)
open_ground_true_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_ground_dir" \
  chez --script "$open_ground_shell" \
    --auto-bind-ground-hole="$open_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=nat:0 \
    --auto-bind-hole-type=OpenGroundResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
open_ground_true_one_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_ground_dir" \
  chez --script "$open_ground_shell" \
    --auto-bind-ground-hole="$open_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=nat:1 \
    --auto-bind-hole-type=OpenGroundResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
open_ground_false_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_ground_dir" \
  chez --script "$open_ground_shell" \
    --auto-bind-ground-hole="$open_ground_hole_id" \
    --entry-ground-argument=bool:false \
    --entry-ground-argument=nat:0 \
    --auto-bind-hole-type=OpenGroundResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
open_ground_explicit_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_ground_dir" \
  chez --script "$open_ground_shell" \
    --call-ground-hole="$open_ground_hole_id" \
    --ground-argument=bool:true \
    --ground-argument=nat:0 \
    --call-hole-type=OpenGroundResidualClosure \
    --call-result-consumer=consumeResidual
)
if [ "$open_ground_whole_result" != true ] || \
   [ "$open_ground_hole_result" != true ] || \
   ! printf '%s\n' "$open_ground_true_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_ground_true_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_ground_false_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_ground_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29OrderedGroundCapture: ordered Chez values were not preserved" >&2
  exit 1
fi

set +e
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/swapped-environment.stdout" \
  2> "$open_ground_dir/swapped-environment.stderr"
open_ground_swapped_status=$?
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/missing-slot.stdout" \
  2> "$open_ground_dir/missing-slot.stderr"
open_ground_missing_status=$?
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:false \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/extra-slot.stdout" \
  2> "$open_ground_dir/extra-slot.stderr"
open_ground_extra_status=$?
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=bool:false \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/wrong-codec.stdout" \
  2> "$open_ground_dir/wrong-codec.stderr"
open_ground_codec_status=$?
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/duplicate-selector.stdout" \
  2> "$open_ground_dir/duplicate-selector.stderr"
open_ground_duplicate_status=$?
chez --script "$open_ground_shell" \
  --auto-bind-ground-hole="$open_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:4294967296 \
  --auto-bind-hole-type=OpenGroundResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_ground_dir/overflow-slot.stdout" \
  2> "$open_ground_dir/overflow-slot.stderr"
open_ground_overflow_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_ground_dir" \
chez --script "$open_ground_shell" \
  --call-ground-hole="$open_ground_hole_id" \
  --ground-argument=nat:0 \
  --ground-argument=bool:true \
  --call-hole-type=OpenGroundResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$open_ground_dir/explicit-wrong-codec.stdout" \
  2> "$open_ground_dir/explicit-wrong-codec.stderr"
open_ground_explicit_codec_status=$?
set -e
for rejected in \
  swapped-environment \
  missing-slot \
  extra-slot \
  wrong-codec \
  duplicate-selector \
  overflow-slot
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$open_ground_dir/$rejected.stdout" "$open_ground_dir/$rejected.stderr"
  then
    echo "Agda29OrderedGroundCapture: $rejected has wrong failure code" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$open_ground_dir/explicit-wrong-codec.stdout" \
     "$open_ground_dir/explicit-wrong-codec.stderr"
then
  echo "Agda29ExplicitGroundCall: ordered codec mismatch has wrong failure code" >&2
  exit 1
fi
if [ "$open_ground_swapped_status" -eq 0 ] || \
   [ "$open_ground_missing_status" -eq 0 ] || \
   [ "$open_ground_extra_status" -eq 0 ] || \
   [ "$open_ground_codec_status" -eq 0 ] || \
   [ "$open_ground_duplicate_status" -eq 0 ] || \
   [ "$open_ground_overflow_status" -eq 0 ] || \
   [ "$open_ground_explicit_codec_status" -eq 0 ]
then
  echo "Agda29OrderedGroundCapture: invalid ordered environment did not reject" >&2
  exit 1
fi

word64_ground_dir="$build_dir/evidence/MixedOpenWord64GroundResidual"
word64_ground_source="$word64_ground_dir/MixedOpenWord64GroundResidual.agda"
word64_ground_packet="$word64_ground_dir/typed-residual.bin"
word64_ground_hole_packet="$word64_ground_dir/typed-residual-hole-1.bin"
word64_ground_shell="$word64_ground_dir/residual-static-shell.ss"
word64_ground_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$word64_ground_dir"
cp "$fixture_dir/MixedOpenWord64GroundResidual.agda" "$word64_ground_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$word64_ground_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$word64_ground_dir" \
  "$word64_ground_source" \
  > "$word64_ground_dir/producer.log"
if [ ! -s "$word64_ground_packet" ] || \
   [ ! -s "$word64_ground_hole_packet" ] || \
   [ ! -s "$word64_ground_shell" ] || \
   ! grep -Fqx 'binding-time: mixed' "$word64_ground_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-arity: 2' \
     "$word64_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: ordered-bool+word64-chez-lexical-binding-v1' \
     "$word64_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: ordered-bool+word64-ground-environment-elimination-v1' \
     "$word64_ground_dir/typed-residual.txt" || \
   ! grep -Fq '(vector "bool" "word64")' "$word64_ground_shell"
then
  echo "Agda29Word64GroundCapture: binding capability is invalid" >&2
  exit 1
fi

word64_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$word64_ground_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$word64_ground_dir" \
    "$word64_ground_source"
)
word64_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$word64_ground_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$word64_ground_dir" \
    "$word64_ground_source"
)
word64_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_ground_dir" \
  chez --script "$word64_ground_shell" \
    --auto-bind-ground-hole="$word64_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=word64:0 \
    --auto-bind-hole-type=OpenWord64ResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
word64_one_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_ground_dir" \
  chez --script "$word64_ground_shell" \
    --auto-bind-ground-hole="$word64_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=word64:1 \
    --auto-bind-hole-type=OpenWord64ResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
word64_explicit_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_ground_dir" \
  chez --script "$word64_ground_shell" \
    --call-ground-hole="$word64_ground_hole_id" \
    --ground-argument=bool:true \
    --ground-argument=word64:0 \
    --call-hole-type=OpenWord64ResidualClosure \
    --call-result-consumer=consumeResidual
)
if [ "$word64_whole_result" != true ] || \
   [ "$word64_hole_result" != true ] || \
   ! printf '%s\n' "$word64_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$word64_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$word64_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29Word64GroundCapture: Word64 values were not preserved" >&2
  exit 1
fi

set +e
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$word64_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$word64_ground_dir" \
chez --script "$word64_ground_shell" \
  --auto-bind-ground-hole="$word64_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --auto-bind-hole-type=OpenWord64ResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$word64_ground_dir/lexical-wrong-codec.stdout" \
  2> "$word64_ground_dir/lexical-wrong-codec.stderr"
word64_lexical_codec_status=$?
chez --script "$word64_ground_shell" \
  --auto-bind-ground-hole="$word64_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=word64:18446744073709551616 \
  --auto-bind-hole-type=OpenWord64ResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$word64_ground_dir/lexical-overflow.stdout" \
  2> "$word64_ground_dir/lexical-overflow.stderr"
word64_lexical_overflow_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$word64_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$word64_ground_dir" \
chez --script "$word64_ground_shell" \
  --call-ground-hole="$word64_ground_hole_id" \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  --call-hole-type=OpenWord64ResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$word64_ground_dir/explicit-wrong-codec.stdout" \
  2> "$word64_ground_dir/explicit-wrong-codec.stderr"
word64_explicit_codec_status=$?
chez --script "$word64_ground_shell" \
  --call-ground-hole="$word64_ground_hole_id" \
  --ground-argument=bool:true \
  --ground-argument=word64:18446744073709551616 \
  --call-hole-type=OpenWord64ResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$word64_ground_dir/explicit-overflow.stdout" \
  2> "$word64_ground_dir/explicit-overflow.stderr"
word64_explicit_overflow_status=$?
set -e
for rejected in lexical-wrong-codec lexical-overflow
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$word64_ground_dir/$rejected.stdout" \
    "$word64_ground_dir/$rejected.stderr"
  then
    echo "Agda29Word64GroundCapture: $rejected has wrong failure code" >&2
    exit 1
  fi
done
for rejected in explicit-wrong-codec explicit-overflow
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$word64_ground_dir/$rejected.stdout" \
    "$word64_ground_dir/$rejected.stderr"
  then
    echo "Agda29Word64GroundCapture: $rejected has wrong failure code" >&2
    exit 1
  fi
done
if [ "$word64_lexical_codec_status" -eq 0 ] || \
   [ "$word64_lexical_overflow_status" -eq 0 ] || \
   [ "$word64_explicit_codec_status" -eq 0 ] || \
   [ "$word64_explicit_overflow_status" -eq 0 ]
then
  echo "Agda29Word64GroundCapture: invalid Word64 input did not reject" >&2
  exit 1
fi

dependent_ground_dir="$build_dir/evidence/MixedOpenDependentResidual"
dependent_ground_source="$dependent_ground_dir/MixedOpenDependentResidual.agda"
dependent_ground_packet="$dependent_ground_dir/typed-residual.bin"
dependent_ground_hole_packet="$dependent_ground_dir/typed-residual-hole-1.bin"
dependent_ground_shell="$dependent_ground_dir/residual-static-shell.ss"
dependent_ground_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$dependent_ground_dir"
cp "$fixture_dir/MixedOpenDependentResidual.agda" "$dependent_ground_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$dependent_ground_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependent_ground_dir" \
  "$dependent_ground_source" \
  > "$dependent_ground_dir/producer.log"
if [ ! -s "$dependent_ground_packet" ] || \
   [ ! -s "$dependent_ground_hole_packet" ] || \
   [ ! -s "$dependent_ground_shell" ] || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-dependent-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$dependent_ground_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 2' \
     "$dependent_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: dependent-ground-environment-elimination-v1' \
     "$dependent_ground_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-dependent-ground-environment' \
     "$dependent_ground_shell"
then
  echo "Agda29DependentGroundCapture: dependent capability is invalid" >&2
  exit 1
fi

dependent_ground_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$dependent_ground_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_ground_dir" \
    "$dependent_ground_source"
)
dependent_ground_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$dependent_ground_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_ground_dir" \
    "$dependent_ground_source"
)
dependent_ground_true_zero_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
  chez --script "$dependent_ground_shell" \
    --auto-bind-ground-hole="$dependent_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=nat:0 \
    --auto-bind-hole-type=OpenDependentResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
dependent_ground_true_one_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
  chez --script "$dependent_ground_shell" \
    --auto-bind-ground-hole="$dependent_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument=nat:1 \
    --auto-bind-hole-type=OpenDependentResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
dependent_ground_false_true_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
  chez --script "$dependent_ground_shell" \
    --auto-bind-ground-hole="$dependent_ground_hole_id" \
    --entry-ground-argument=bool:false \
    --entry-ground-argument=bool:true \
    --auto-bind-hole-type=OpenDependentResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
dependent_ground_false_false_result=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
  chez --script "$dependent_ground_shell" \
    --auto-bind-ground-hole="$dependent_ground_hole_id" \
    --entry-ground-argument=bool:false \
    --entry-ground-argument=bool:false \
    --auto-bind-hole-type=OpenDependentResidualClosure \
    --auto-bind-result-consumer=consumeResidual
)
if [ "$dependent_ground_whole_result" != true ] || \
   [ "$dependent_ground_hole_result" != true ] || \
   ! printf '%s\n' "$dependent_ground_true_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_ground_true_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_ground_false_true_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_ground_false_false_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29DependentGroundCapture: dependent values were not preserved" >&2
  exit 1
fi

set +e
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
chez --script "$dependent_ground_shell" \
  --auto-bind-ground-hole="$dependent_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=bool:true \
  --auto-bind-hole-type=OpenDependentResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_ground_dir/true-wrong-branch.stdout" \
  2> "$dependent_ground_dir/true-wrong-branch.stderr"
dependent_ground_true_wrong_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
chez --script "$dependent_ground_shell" \
  --auto-bind-ground-hole="$dependent_ground_hole_id" \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=nat:0 \
  --auto-bind-hole-type=OpenDependentResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_ground_dir/false-wrong-branch.stdout" \
  2> "$dependent_ground_dir/false-wrong-branch.stderr"
dependent_ground_false_wrong_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_ground_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_ground_dir" \
chez --script "$dependent_ground_shell" \
  --auto-bind-ground-hole="$dependent_ground_hole_id" \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  --auto-bind-hole-type=OpenDependentResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_ground_dir/swapped-dependent.stdout" \
  2> "$dependent_ground_dir/swapped-dependent.stderr"
dependent_ground_swapped_status=$?
chez --script "$dependent_ground_shell" \
  --auto-bind-ground-hole="$dependent_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --auto-bind-hole-type=OpenDependentResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_ground_dir/missing-dependent-slot.stdout" \
  2> "$dependent_ground_dir/missing-dependent-slot.stderr"
dependent_ground_missing_status=$?
chez --script "$dependent_ground_shell" \
  --auto-bind-ground-hole="$dependent_ground_hole_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:false \
  --auto-bind-hole-type=OpenDependentResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_ground_dir/extra-dependent-slot.stdout" \
  2> "$dependent_ground_dir/extra-dependent-slot.stderr"
dependent_ground_extra_status=$?
set -e
for rejected in true-wrong-branch false-wrong-branch swapped-dependent
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_ground_dir/$rejected.stdout" \
    "$dependent_ground_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundCapture: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
for rejected in missing-dependent-slot extra-dependent-slot
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$dependent_ground_dir/$rejected.stdout" \
    "$dependent_ground_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundCapture: $rejected has wrong local failure code" >&2
    exit 1
  fi
done
if [ "$dependent_ground_true_wrong_status" -eq 0 ] || \
   [ "$dependent_ground_false_wrong_status" -eq 0 ] || \
   [ "$dependent_ground_swapped_status" -eq 0 ] || \
   [ "$dependent_ground_missing_status" -eq 0 ] || \
   [ "$dependent_ground_extra_status" -eq 0 ]
then
  echo "Agda29DependentGroundCapture: invalid dependent replay did not reject" >&2
  exit 1
fi

dependent_word64_dir="$build_dir/evidence/MixedOpenDependentWord64Residual"
dependent_word64_source="$dependent_word64_dir/MixedOpenDependentWord64Residual.agda"
dependent_word64_packet="$dependent_word64_dir/typed-residual.bin"
dependent_word64_hole_packet="$dependent_word64_dir/typed-residual-hole-1.bin"
dependent_word64_shell="$dependent_word64_dir/residual-static-shell.ss"
dependent_word64_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$dependent_word64_dir"
cp "$fixture_dir/MixedOpenDependentWord64Residual.agda" \
  "$dependent_word64_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$dependent_word64_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependent_word64_dir" \
  "$dependent_word64_source" \
  > "$dependent_word64_dir/producer.log"
if [ ! -s "$dependent_word64_packet" ] || \
   [ ! -s "$dependent_word64_hole_packet" ] || \
   [ ! -s "$dependent_word64_shell" ] || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_word64_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 2' \
     "$dependent_word64_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: dependent-ground-environment-elimination-v1' \
     "$dependent_word64_dir/typed-residual.txt" || \
   ! grep -Fq \
     "'cubical-chez-typed-hole-bound-dependent-ground-environment-v1" \
     "$dependent_word64_shell"
then
  echo "Agda29DependentWord64Capture: dependent capability is invalid" >&2
  exit 1
fi

dependent_word64_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$dependent_word64_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_word64_dir" \
    "$dependent_word64_source"
)
dependent_word64_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$dependent_word64_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_word64_dir" \
    "$dependent_word64_source"
)
run_dependent_word64_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_word64_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_word64_dir" \
  chez --script "$dependent_word64_shell" \
    --auto-bind-ground-hole="$dependent_word64_hole_id" \
    "$@" \
    --auto-bind-hole-type=OpenDependentWord64ResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_dependent_word64_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_word64_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_word64_dir" \
  chez --script "$dependent_word64_shell" \
    --call-ground-hole="$dependent_word64_hole_id" \
    "$@" \
    --call-hole-type=OpenDependentWord64ResidualClosure \
    --call-result-consumer=consumeResidual
}
dependent_word64_zero_result=$(run_dependent_word64_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=word64:0)
dependent_word64_max_result=$(run_dependent_word64_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=word64:18446744073709551615)
dependent_word64_nat_zero_result=$(run_dependent_word64_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=nat:0)
dependent_word64_nat_one_result=$(run_dependent_word64_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=nat:1)
dependent_word64_explicit_zero_result=$(run_dependent_word64_call \
  --ground-argument=bool:true \
  --ground-argument=word64:0)
dependent_word64_explicit_max_result=$(run_dependent_word64_call \
  --ground-argument=bool:true \
  --ground-argument=word64:18446744073709551615)
if [ "$dependent_word64_whole_result" != true ] || \
   [ "$dependent_word64_hole_result" != true ] || \
   ! printf '%s\n' "$dependent_word64_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_word64_max_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_word64_nat_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_word64_nat_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_word64_explicit_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_word64_explicit_max_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29DependentWord64Capture: dependent values were not preserved" >&2
  exit 1
fi

set +e
run_dependent_word64_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  > "$dependent_word64_dir/word64-as-nat.stdout" \
  2> "$dependent_word64_dir/word64-as-nat.stderr"
dependent_word64_as_nat_status=$?
run_dependent_word64_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=word64:0 \
  > "$dependent_word64_dir/nat-as-word64.stdout" \
  2> "$dependent_word64_dir/nat-as-word64.stderr"
dependent_nat_as_word64_status=$?
run_dependent_word64_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=word64:18446744073709551616 \
  > "$dependent_word64_dir/word64-overflow.stdout" \
  2> "$dependent_word64_dir/word64-overflow.stderr"
dependent_word64_overflow_status=$?
run_dependent_word64_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=word64:-1 \
  > "$dependent_word64_dir/word64-negative.stdout" \
  2> "$dependent_word64_dir/word64-negative.stderr"
dependent_word64_negative_status=$?
run_dependent_word64_call \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  > "$dependent_word64_dir/explicit-word64-as-nat.stdout" \
  2> "$dependent_word64_dir/explicit-word64-as-nat.stderr"
dependent_word64_explicit_codec_status=$?
run_dependent_word64_call \
  --ground-argument=bool:true \
  --ground-argument=word64:18446744073709551616 \
  > "$dependent_word64_dir/explicit-word64-overflow.stdout" \
  2> "$dependent_word64_dir/explicit-word64-overflow.stderr"
dependent_word64_explicit_overflow_status=$?
set -e
for rejected in word64-as-nat nat-as-word64 explicit-word64-as-nat
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_word64_dir/$rejected.stdout" \
    "$dependent_word64_dir/$rejected.stderr"
  then
    echo "Agda29DependentWord64Capture: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
for rejected in word64-overflow word64-negative
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$dependent_word64_dir/$rejected.stdout" \
    "$dependent_word64_dir/$rejected.stderr"
  then
    echo "Agda29DependentWord64Capture: $rejected has wrong environment failure" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
  "$dependent_word64_dir/explicit-word64-overflow.stdout" \
  "$dependent_word64_dir/explicit-word64-overflow.stderr"
then
  echo "Agda29DependentWord64Capture: explicit overflow has wrong failure" >&2
  exit 1
fi
if [ "$dependent_word64_as_nat_status" -eq 0 ] || \
   [ "$dependent_nat_as_word64_status" -eq 0 ] || \
   [ "$dependent_word64_overflow_status" -eq 0 ] || \
   [ "$dependent_word64_negative_status" -eq 0 ] || \
   [ "$dependent_word64_explicit_codec_status" -eq 0 ] || \
   [ "$dependent_word64_explicit_overflow_status" -eq 0 ]
then
  echo "Agda29DependentWord64Capture: invalid replay did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-word64-zero\ttrue\nlexical-word64-max\tfalse\nlexical-nat-zero\ttrue\nlexical-nat-one\tfalse\nexplicit-word64-zero\ttrue\nexplicit-word64-max\tfalse\n' \
  > "$dependent_word64_dir/dependent-word64.tsv"

open_char_dir="$build_dir/evidence/MixedOpenCharResidual"
open_char_source="$open_char_dir/MixedOpenCharResidual.agda"
open_char_packet="$open_char_dir/typed-residual.bin"
open_char_hole_packet="$open_char_dir/typed-residual-hole-1.bin"
open_char_shell="$open_char_dir/residual-static-shell.ss"
open_char_hole_id=typed-hole@lambda-body.app-argument-1
mkdir -p "$open_char_dir"
cp "$fixture_dir/MixedOpenCharResidual.agda" "$open_char_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_char_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_char_dir" \
  "$open_char_source" \
  > "$open_char_dir/producer.log"
if [ ! -s "$open_char_packet" ] || \
   [ ! -s "$open_char_hole_packet" ] || \
   [ ! -s "$open_char_shell" ] || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: single-char-chez-lexical-binding-v1' \
     "$open_char_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: char-unary-ground-elimination-v1' \
     "$open_char_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-char-environment' "$open_char_shell"
then
  echo "Agda29LexicalCharCapture: Char capability is invalid" >&2
  exit 1
fi
open_char_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_char_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_char_dir" \
    "$open_char_source"
)
open_char_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_char_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_char_dir" \
    "$open_char_source"
)
run_open_char_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_char_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_char_dir" \
  chez --script "$open_char_shell" \
    --auto-bind-char-hole="$open_char_hole_id" \
    --entry-char-codepoint="$1" \
    --auto-bind-hole-type=OpenCharResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_open_char_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_char_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_char_dir" \
  chez --script "$open_char_shell" \
    --call-char-hole="$open_char_hole_id" \
    --char-codepoint="$1" \
    --call-hole-type=OpenCharResidualClosure \
    --call-result-consumer=consumeResidual
}
open_char_a_result=$(run_open_char_capture 65)
open_char_b_result=$(run_open_char_capture 66)
open_char_explicit_a_result=$(run_open_char_call 65)
open_char_explicit_b_result=$(run_open_char_call 66)
if [ "$open_char_whole_result" != true ] || \
   [ "$open_char_hole_result" != true ] || \
   ! printf '%s\n' "$open_char_a_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_char_b_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_char_explicit_a_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_char_explicit_b_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29LexicalCharCapture: Char values were not preserved" >&2
  exit 1
fi
set +e
run_open_char_capture 55296 \
  > "$open_char_dir/surrogate-environment.stdout" \
  2> "$open_char_dir/surrogate-environment.stderr"
open_char_surrogate_status=$?
run_open_char_capture 1114112 \
  > "$open_char_dir/overflow-environment.stdout" \
  2> "$open_char_dir/overflow-environment.stderr"
open_char_overflow_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_char_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_char_dir" \
chez --script "$open_char_shell" \
  --auto-bind-nat-hole="$open_char_hole_id" \
  --entry-nat-argument=65 \
  --auto-bind-hole-type=OpenCharResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_char_dir/wrong-auto-codec.stdout" \
  2> "$open_char_dir/wrong-auto-codec.stderr"
open_char_wrong_auto_status=$?
run_open_char_call 55296 \
  > "$open_char_dir/surrogate-call.stdout" \
  2> "$open_char_dir/surrogate-call.stderr"
open_char_surrogate_call_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_char_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_char_dir" \
chez --script "$open_char_shell" \
  --call-nat-hole="$open_char_hole_id" \
  --nat-argument=65 \
  --call-hole-type=OpenCharResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$open_char_dir/wrong-call-codec.stdout" \
  2> "$open_char_dir/wrong-call-codec.stderr"
open_char_wrong_call_status=$?
set -e
for rejected in surrogate-environment overflow-environment wrong-auto-codec
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$open_char_dir/$rejected.stdout" "$open_char_dir/$rejected.stderr"
  then
    echo "Agda29LexicalCharCapture: $rejected has wrong environment failure" >&2
    exit 1
  fi
done
for rejected in surrogate-call wrong-call-codec
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$open_char_dir/$rejected.stdout" "$open_char_dir/$rejected.stderr"
  then
    echo "Agda29LexicalCharCapture: $rejected has wrong call failure" >&2
    exit 1
  fi
done
if [ "$open_char_surrogate_status" -eq 0 ] || \
   [ "$open_char_overflow_status" -eq 0 ] || \
   [ "$open_char_wrong_auto_status" -eq 0 ] || \
   [ "$open_char_surrogate_call_status" -eq 0 ] || \
   [ "$open_char_wrong_call_status" -eq 0 ]
then
  echo "Agda29LexicalCharCapture: invalid Char input did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-u0041\ttrue\nlexical-u0042\tfalse\nexplicit-u0041\ttrue\nexplicit-u0042\tfalse\n' \
  > "$open_char_dir/char-single.tsv"

char_ground_dir="$build_dir/evidence/MixedOpenCharGroundResidual"
char_ground_source="$char_ground_dir/MixedOpenCharGroundResidual.agda"
char_ground_packet="$char_ground_dir/typed-residual.bin"
char_ground_hole_packet="$char_ground_dir/typed-residual-hole-1.bin"
char_ground_shell="$char_ground_dir/residual-static-shell.ss"
char_ground_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$char_ground_dir"
cp "$fixture_dir/MixedOpenCharGroundResidual.agda" "$char_ground_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$char_ground_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$char_ground_dir" \
  "$char_ground_source" \
  > "$char_ground_dir/producer.log"
if [ ! -s "$char_ground_packet" ] || \
   [ ! -s "$char_ground_hole_packet" ] || \
   [ ! -s "$char_ground_shell" ] || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: ordered-bool+char-chez-lexical-binding-v1' \
     "$char_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: ordered-bool+char-ground-environment-elimination-v1' \
     "$char_ground_dir/typed-residual.txt" || \
   ! grep -Fq '(vector "bool" "char")' "$char_ground_shell"
then
  echo "Agda29OrderedCharCapture: Char capability is invalid" >&2
  exit 1
fi
char_ground_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$char_ground_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$char_ground_dir" \
    "$char_ground_source"
)
char_ground_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$char_ground_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$char_ground_dir" \
    "$char_ground_source"
)
run_char_ground_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$char_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$char_ground_dir" \
  chez --script "$char_ground_shell" \
    --auto-bind-ground-hole="$char_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument="$1" \
    --auto-bind-hole-type=OpenCharGroundResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_char_ground_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$char_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$char_ground_dir" \
  chez --script "$char_ground_shell" \
    --call-ground-hole="$char_ground_hole_id" \
    --ground-argument=bool:true \
    --ground-argument="$1" \
    --call-hole-type=OpenCharGroundResidualClosure \
    --call-result-consumer=consumeResidual
}
char_ground_a_result=$(run_char_ground_capture char:65)
char_ground_b_result=$(run_char_ground_capture char:66)
char_ground_explicit_result=$(run_char_ground_call char:65)
if [ "$char_ground_whole_result" != true ] || \
   [ "$char_ground_hole_result" != true ] || \
   ! printf '%s\n' "$char_ground_a_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$char_ground_b_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$char_ground_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29OrderedCharCapture: Char values were not preserved" >&2
  exit 1
fi
set +e
run_char_ground_capture nat:65 \
  > "$char_ground_dir/wrong-auto-codec.stdout" \
  2> "$char_ground_dir/wrong-auto-codec.stderr"
char_ground_wrong_auto_status=$?
run_char_ground_capture char:55296 \
  > "$char_ground_dir/surrogate-environment.stdout" \
  2> "$char_ground_dir/surrogate-environment.stderr"
char_ground_surrogate_status=$?
run_char_ground_call nat:65 \
  > "$char_ground_dir/wrong-call-codec.stdout" \
  2> "$char_ground_dir/wrong-call-codec.stderr"
char_ground_wrong_call_status=$?
run_char_ground_call char:55296 \
  > "$char_ground_dir/surrogate-call.stdout" \
  2> "$char_ground_dir/surrogate-call.stderr"
char_ground_surrogate_call_status=$?
set -e
for rejected in wrong-auto-codec surrogate-environment
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$char_ground_dir/$rejected.stdout" "$char_ground_dir/$rejected.stderr"
  then
    echo "Agda29OrderedCharCapture: $rejected has wrong environment failure" >&2
    exit 1
  fi
done
for rejected in wrong-call-codec surrogate-call
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$char_ground_dir/$rejected.stdout" "$char_ground_dir/$rejected.stderr"
  then
    echo "Agda29OrderedCharCapture: $rejected has wrong call failure" >&2
    exit 1
  fi
done
if [ "$char_ground_wrong_auto_status" -eq 0 ] || \
   [ "$char_ground_surrogate_status" -eq 0 ] || \
   [ "$char_ground_wrong_call_status" -eq 0 ] || \
   [ "$char_ground_surrogate_call_status" -eq 0 ]
then
  echo "Agda29OrderedCharCapture: invalid Char replay did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-u0041\ttrue\nlexical-u0042\tfalse\nexplicit-u0041\ttrue\n' \
  > "$char_ground_dir/char-ordered.tsv"

dependent_char_dir="$build_dir/evidence/MixedOpenDependentCharResidual"
dependent_char_source="$dependent_char_dir/MixedOpenDependentCharResidual.agda"
dependent_char_packet="$dependent_char_dir/typed-residual.bin"
dependent_char_hole_packet="$dependent_char_dir/typed-residual-hole-1.bin"
dependent_char_shell="$dependent_char_dir/residual-static-shell.ss"
dependent_char_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$dependent_char_dir"
cp "$fixture_dir/MixedOpenDependentCharResidual.agda" "$dependent_char_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$dependent_char_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependent_char_dir" \
  "$dependent_char_source" \
  > "$dependent_char_dir/producer.log"
if [ ! -s "$dependent_char_packet" ] || \
   [ ! -s "$dependent_char_hole_packet" ] || \
   [ ! -s "$dependent_char_shell" ] || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_char_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: dependent-ground-environment-elimination-v1' \
     "$dependent_char_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-dependent-ground-environment' \
     "$dependent_char_shell"
then
  echo "Agda29DependentCharCapture: dependent Char capability is invalid" >&2
  exit 1
fi
dependent_char_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$dependent_char_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_char_dir" \
    "$dependent_char_source"
)
dependent_char_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$dependent_char_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_char_dir" \
    "$dependent_char_source"
)
run_dependent_char_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_char_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_char_dir" \
  chez --script "$dependent_char_shell" \
    --auto-bind-ground-hole="$dependent_char_hole_id" \
    --entry-ground-argument="$1" \
    --entry-ground-argument="$2" \
    --auto-bind-hole-type=OpenDependentCharResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_dependent_char_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_char_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_char_dir" \
  chez --script "$dependent_char_shell" \
    --call-ground-hole="$dependent_char_hole_id" \
    --ground-argument="$1" \
    --ground-argument="$2" \
    --call-hole-type=OpenDependentCharResidualClosure \
    --call-result-consumer=consumeResidual
}
dependent_char_a_result=$(run_dependent_char_capture bool:true char:65)
dependent_char_b_result=$(run_dependent_char_capture bool:true char:66)
dependent_char_nat_zero_result=$(run_dependent_char_capture bool:false nat:0)
dependent_char_nat_one_result=$(run_dependent_char_capture bool:false nat:1)
dependent_char_explicit_result=$(run_dependent_char_call bool:true char:65)
if [ "$dependent_char_whole_result" != true ] || \
   [ "$dependent_char_hole_result" != true ] || \
   ! printf '%s\n' "$dependent_char_a_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_char_b_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_char_nat_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_char_nat_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_char_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29DependentCharCapture: dependent values were not preserved" >&2
  exit 1
fi
set +e
run_dependent_char_capture bool:true nat:65 \
  > "$dependent_char_dir/char-as-nat.stdout" \
  2> "$dependent_char_dir/char-as-nat.stderr"
dependent_char_as_nat_status=$?
run_dependent_char_capture bool:false char:65 \
  > "$dependent_char_dir/nat-as-char.stdout" \
  2> "$dependent_char_dir/nat-as-char.stderr"
dependent_nat_as_char_status=$?
run_dependent_char_capture bool:true char:55296 \
  > "$dependent_char_dir/surrogate-environment.stdout" \
  2> "$dependent_char_dir/surrogate-environment.stderr"
dependent_char_surrogate_status=$?
run_dependent_char_call bool:true nat:65 \
  > "$dependent_char_dir/explicit-char-as-nat.stdout" \
  2> "$dependent_char_dir/explicit-char-as-nat.stderr"
dependent_char_explicit_codec_status=$?
run_dependent_char_call bool:true char:55296 \
  > "$dependent_char_dir/surrogate-call.stdout" \
  2> "$dependent_char_dir/surrogate-call.stderr"
dependent_char_surrogate_call_status=$?
set -e
for rejected in char-as-nat nat-as-char explicit-char-as-nat
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_char_dir/$rejected.stdout" \
    "$dependent_char_dir/$rejected.stderr"
  then
    echo "Agda29DependentCharCapture: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
  "$dependent_char_dir/surrogate-environment.stdout" \
  "$dependent_char_dir/surrogate-environment.stderr"
then
  echo "Agda29DependentCharCapture: surrogate has wrong environment failure" >&2
  exit 1
fi
if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
  "$dependent_char_dir/surrogate-call.stdout" \
  "$dependent_char_dir/surrogate-call.stderr"
then
  echo "Agda29DependentCharCapture: explicit surrogate has wrong call failure" >&2
  exit 1
fi
if [ "$dependent_char_as_nat_status" -eq 0 ] || \
   [ "$dependent_nat_as_char_status" -eq 0 ] || \
   [ "$dependent_char_surrogate_status" -eq 0 ] || \
   [ "$dependent_char_explicit_codec_status" -eq 0 ] || \
   [ "$dependent_char_surrogate_call_status" -eq 0 ]
then
  echo "Agda29DependentCharCapture: invalid dependent replay did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-char-u0041\ttrue\nlexical-char-u0042\tfalse\nlexical-nat-zero\ttrue\nlexical-nat-one\tfalse\nexplicit-char-u0041\ttrue\n' \
  > "$dependent_char_dir/char-dependent.tsv"

open_int_dir="$build_dir/evidence/MixedOpenIntResidual"
open_int_source="$open_int_dir/MixedOpenIntResidual.agda"
open_int_packet="$open_int_dir/typed-residual.bin"
open_int_hole_packet="$open_int_dir/typed-residual-hole-1.bin"
open_int_shell="$open_int_dir/residual-static-shell.ss"
open_int_hole_id=typed-hole@lambda-body.app-argument-1
mkdir -p "$open_int_dir"
cp "$fixture_dir/MixedOpenIntResidual.agda" "$open_int_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$open_int_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$open_int_dir" \
  "$open_int_source" \
  > "$open_int_dir/producer.log"
if [ ! -s "$open_int_packet" ] || \
   [ ! -s "$open_int_hole_packet" ] || \
   [ ! -s "$open_int_shell" ] || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: single-int-chez-lexical-binding-v1' \
     "$open_int_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: int-unary-ground-elimination-v1' \
     "$open_int_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-int-environment' "$open_int_shell" || \
   ! grep -Fqx \
     '(define cubical-chez-ground-codec-registry-v1 '\''("bool" "nat" "word64" "char" "int"))' \
     "$open_int_shell" || \
   ! grep -Fq \
     '(vector "int" "int-unary-ground-elimination-v1" "int:" cubical-chez-valid-int-argument?' \
     "$open_int_shell"
then
  echo "Agda29LexicalIntCapture: Int capability is invalid" >&2
  exit 1
fi
open_int_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$open_int_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_int_dir" \
    "$open_int_source"
)
open_int_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$open_int_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$open_int_dir" \
    "$open_int_source"
)
run_open_int_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
  chez --script "$open_int_shell" \
    --auto-bind-int-hole="$open_int_hole_id" \
    --entry-int-argument="$1" \
    --auto-bind-hole-type=OpenIntResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_open_int_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
  chez --script "$open_int_shell" \
    --call-int-hole="$open_int_hole_id" \
    --int-argument="$1" \
    --call-hole-type=OpenIntResidualClosure \
    --call-result-consumer=consumeResidual
}
open_int_zero_result=$(run_open_int_capture 0)
open_int_negative_result=$(run_open_int_capture -1)
open_int_explicit_max_result=$(run_open_int_call 9223372036854775807)
open_int_explicit_min_result=$(run_open_int_call -9223372036854775808)
if [ "$open_int_whole_result" != true ] || \
   [ "$open_int_hole_result" != true ] || \
   ! printf '%s\n' "$open_int_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_int_negative_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$open_int_explicit_max_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$open_int_explicit_min_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29LexicalIntCapture: Int values were not preserved" >&2
  exit 1
fi
open_int_tampered_registry_shell="$open_int_dir/registry-tampered.ss"
sed 's/"int"))$/"char"))/' \
  "$open_int_shell" > "$open_int_tampered_registry_shell"
open_int_tampered_descriptor_shell="$open_int_dir/descriptor-tampered.ss"
sed '/(vector "int"/s/"int:"/"char:"/' \
  "$open_int_shell" > "$open_int_tampered_descriptor_shell"
set +e
run_open_int_capture 9223372036854775808 \
  > "$open_int_dir/overflow-environment.stdout" \
  2> "$open_int_dir/overflow-environment.stderr"
open_int_overflow_status=$?
run_open_int_capture -9223372036854775809 \
  > "$open_int_dir/underflow-environment.stdout" \
  2> "$open_int_dir/underflow-environment.stderr"
open_int_underflow_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
chez --script "$open_int_shell" \
  --auto-bind-nat-hole="$open_int_hole_id" \
  --entry-nat-argument=0 \
  --auto-bind-hole-type=OpenIntResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_int_dir/wrong-auto-codec.stdout" \
  2> "$open_int_dir/wrong-auto-codec.stderr"
open_int_wrong_auto_status=$?
run_open_int_call 9223372036854775808 \
  > "$open_int_dir/overflow-call.stdout" \
  2> "$open_int_dir/overflow-call.stderr"
open_int_overflow_call_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
chez --script "$open_int_shell" \
  --call-nat-hole="$open_int_hole_id" \
  --nat-argument=0 \
  --call-hole-type=OpenIntResidualClosure \
  --call-result-consumer=consumeResidual \
  > "$open_int_dir/wrong-call-codec.stdout" \
  2> "$open_int_dir/wrong-call-codec.stderr"
open_int_wrong_call_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
chez --script "$open_int_tampered_registry_shell" \
  --auto-bind-int-hole="$open_int_hole_id" \
  --entry-int-argument=0 \
  --auto-bind-hole-type=OpenIntResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_int_dir/tampered-registry.stdout" \
  2> "$open_int_dir/tampered-registry.stderr"
open_int_tampered_registry_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$open_int_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$open_int_dir" \
chez --script "$open_int_tampered_descriptor_shell" \
  --auto-bind-int-hole="$open_int_hole_id" \
  --entry-int-argument=0 \
  --auto-bind-hole-type=OpenIntResidualClosure \
  --auto-bind-result-consumer=consumeResidual \
  > "$open_int_dir/tampered-descriptor.stdout" \
  2> "$open_int_dir/tampered-descriptor.stderr"
open_int_tampered_descriptor_status=$?
set -e
for rejected in overflow-environment underflow-environment wrong-auto-codec
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$open_int_dir/$rejected.stdout" "$open_int_dir/$rejected.stderr"
  then
    echo "Agda29LexicalIntCapture: $rejected has wrong environment failure" >&2
    exit 1
  fi
done
for rejected in overflow-call wrong-call-codec
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$open_int_dir/$rejected.stdout" "$open_int_dir/$rejected.stderr"
  then
    echo "Agda29LexicalIntCapture: $rejected has wrong call failure" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-PROTOCOL' \
  "$open_int_dir/tampered-registry.stdout" \
  "$open_int_dir/tampered-registry.stderr"
then
  echo "Agda29LexicalIntCapture: tampered registry has wrong failure" >&2
  exit 1
fi
if ! grep -q 'CCZ-TYPED-BRIDGE-PROTOCOL' \
  "$open_int_dir/tampered-descriptor.stdout" \
  "$open_int_dir/tampered-descriptor.stderr"
then
  echo "Agda29LexicalIntCapture: tampered descriptor has wrong failure" >&2
  exit 1
fi
if [ "$open_int_overflow_status" -eq 0 ] || \
   [ "$open_int_underflow_status" -eq 0 ] || \
   [ "$open_int_wrong_auto_status" -eq 0 ] || \
   [ "$open_int_overflow_call_status" -eq 0 ] || \
   [ "$open_int_wrong_call_status" -eq 0 ] || \
   [ "$open_int_tampered_registry_status" -eq 0 ] || \
   [ "$open_int_tampered_descriptor_status" -eq 0 ]
then
  echo "Agda29LexicalIntCapture: invalid Int input did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-zero\ttrue\nlexical-negative-one\tfalse\nexplicit-max\ttrue\nexplicit-min\tfalse\n' \
  > "$open_int_dir/int-single.tsv"

int_ground_dir="$build_dir/evidence/MixedOpenIntGroundResidual"
int_ground_source="$int_ground_dir/MixedOpenIntGroundResidual.agda"
int_ground_packet="$int_ground_dir/typed-residual.bin"
int_ground_hole_packet="$int_ground_dir/typed-residual-hole-1.bin"
int_ground_shell="$int_ground_dir/residual-static-shell.ss"
int_ground_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$int_ground_dir"
cp "$fixture_dir/MixedOpenIntGroundResidual.agda" "$int_ground_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$int_ground_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$int_ground_dir" \
  "$int_ground_source" \
  > "$int_ground_dir/producer.log"
if [ ! -s "$int_ground_packet" ] || \
   [ ! -s "$int_ground_hole_packet" ] || \
   [ ! -s "$int_ground_shell" ] || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: ordered-bool+int-chez-lexical-binding-v1' \
     "$int_ground_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: ordered-bool+int-ground-environment-elimination-v1' \
     "$int_ground_dir/typed-residual.txt" || \
   ! grep -Fq '(vector "bool" "int")' "$int_ground_shell"
then
  echo "Agda29OrderedIntCapture: Int capability is invalid" >&2
  exit 1
fi
int_ground_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$int_ground_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$int_ground_dir" \
    "$int_ground_source"
)
int_ground_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$int_ground_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$int_ground_dir" \
    "$int_ground_source"
)
run_int_ground_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$int_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$int_ground_dir" \
  chez --script "$int_ground_shell" \
    --auto-bind-ground-hole="$int_ground_hole_id" \
    --entry-ground-argument=bool:true \
    --entry-ground-argument="$1" \
    --auto-bind-hole-type=OpenIntGroundResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_int_ground_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$int_ground_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$int_ground_dir" \
  chez --script "$int_ground_shell" \
    --call-ground-hole="$int_ground_hole_id" \
    --ground-argument=bool:true \
    --ground-argument="$1" \
    --call-hole-type=OpenIntGroundResidualClosure \
    --call-result-consumer=consumeResidual
}
int_ground_zero_result=$(run_int_ground_capture int:0)
int_ground_negative_result=$(run_int_ground_capture int:-1)
int_ground_explicit_result=$(run_int_ground_call int:-9223372036854775808)
if [ "$int_ground_whole_result" != true ] || \
   [ "$int_ground_hole_result" != true ] || \
   ! printf '%s\n' "$int_ground_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$int_ground_negative_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$int_ground_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29OrderedIntCapture: Int values were not preserved" >&2
  exit 1
fi
set +e
run_int_ground_capture nat:0 \
  > "$int_ground_dir/wrong-auto-codec.stdout" \
  2> "$int_ground_dir/wrong-auto-codec.stderr"
int_ground_wrong_auto_status=$?
run_int_ground_capture int:9223372036854775808 \
  > "$int_ground_dir/overflow-environment.stdout" \
  2> "$int_ground_dir/overflow-environment.stderr"
int_ground_overflow_status=$?
run_int_ground_call nat:0 \
  > "$int_ground_dir/wrong-call-codec.stdout" \
  2> "$int_ground_dir/wrong-call-codec.stderr"
int_ground_wrong_call_status=$?
run_int_ground_call int:-9223372036854775809 \
  > "$int_ground_dir/underflow-call.stdout" \
  2> "$int_ground_dir/underflow-call.stderr"
int_ground_underflow_call_status=$?
set -e
for rejected in wrong-auto-codec overflow-environment
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$int_ground_dir/$rejected.stdout" "$int_ground_dir/$rejected.stderr"
  then
    echo "Agda29OrderedIntCapture: $rejected has wrong environment failure" >&2
    exit 1
  fi
done
for rejected in wrong-call-codec underflow-call
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$int_ground_dir/$rejected.stdout" "$int_ground_dir/$rejected.stderr"
  then
    echo "Agda29OrderedIntCapture: $rejected has wrong call failure" >&2
    exit 1
  fi
done
if [ "$int_ground_wrong_auto_status" -eq 0 ] || \
   [ "$int_ground_overflow_status" -eq 0 ] || \
   [ "$int_ground_wrong_call_status" -eq 0 ] || \
   [ "$int_ground_underflow_call_status" -eq 0 ]
then
  echo "Agda29OrderedIntCapture: invalid Int replay did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-zero\ttrue\nlexical-negative-one\tfalse\nexplicit-min\tfalse\n' \
  > "$int_ground_dir/int-ordered.tsv"

dependent_int_dir="$build_dir/evidence/MixedOpenDependentIntResidual"
dependent_int_source="$dependent_int_dir/MixedOpenDependentIntResidual.agda"
dependent_int_packet="$dependent_int_dir/typed-residual.bin"
dependent_int_hole_packet="$dependent_int_dir/typed-residual-hole-1.bin"
dependent_int_shell="$dependent_int_dir/residual-static-shell.ss"
dependent_int_hole_id=typed-hole@lambda-body.lambda-body.app-argument-1
mkdir -p "$dependent_int_dir"
cp "$fixture_dir/MixedOpenDependentIntResidual.agda" "$dependent_int_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$dependent_int_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependent_int_dir" \
  "$dependent_int_source" \
  > "$dependent_int_dir/producer.log"
if [ ! -s "$dependent_int_packet" ] || \
   [ ! -s "$dependent_int_hole_packet" ] || \
   [ ! -s "$dependent_int_shell" ] || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_int_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: dependent-ground-environment-elimination-v1' \
     "$dependent_int_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-dependent-ground-environment' \
     "$dependent_int_shell"
then
  echo "Agda29DependentIntCapture: dependent Int capability is invalid" >&2
  exit 1
fi
dependent_int_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$dependent_int_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_int_dir" \
    "$dependent_int_source"
)
dependent_int_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$dependent_int_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_int_dir" \
    "$dependent_int_source"
)
run_dependent_int_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_int_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_int_dir" \
  chez --script "$dependent_int_shell" \
    --auto-bind-ground-hole="$dependent_int_hole_id" \
    --entry-ground-argument="$1" \
    --entry-ground-argument="$2" \
    --auto-bind-hole-type=OpenDependentIntResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
run_dependent_int_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_int_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_int_dir" \
  chez --script "$dependent_int_shell" \
    --call-ground-hole="$dependent_int_hole_id" \
    --ground-argument="$1" \
    --ground-argument="$2" \
    --call-hole-type=OpenDependentIntResidualClosure \
    --call-result-consumer=consumeResidual
}
dependent_int_zero_result=$(run_dependent_int_capture bool:true int:0)
dependent_int_negative_result=$(run_dependent_int_capture bool:true int:-1)
dependent_int_nat_zero_result=$(run_dependent_int_capture bool:false nat:0)
dependent_int_nat_one_result=$(run_dependent_int_capture bool:false nat:1)
dependent_int_explicit_result=$(run_dependent_int_call bool:true int:-9223372036854775808)
if [ "$dependent_int_whole_result" != true ] || \
   [ "$dependent_int_hole_result" != true ] || \
   ! printf '%s\n' "$dependent_int_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_int_negative_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_int_nat_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_int_nat_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_int_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29DependentIntCapture: dependent values were not preserved" >&2
  exit 1
fi
set +e
run_dependent_int_capture bool:true nat:0 \
  > "$dependent_int_dir/int-as-nat.stdout" \
  2> "$dependent_int_dir/int-as-nat.stderr"
dependent_int_as_nat_status=$?
run_dependent_int_capture bool:false int:0 \
  > "$dependent_int_dir/nat-as-int.stdout" \
  2> "$dependent_int_dir/nat-as-int.stderr"
dependent_nat_as_int_status=$?
run_dependent_int_capture bool:true int:9223372036854775808 \
  > "$dependent_int_dir/overflow-environment.stdout" \
  2> "$dependent_int_dir/overflow-environment.stderr"
dependent_int_overflow_status=$?
run_dependent_int_call bool:true nat:0 \
  > "$dependent_int_dir/explicit-int-as-nat.stdout" \
  2> "$dependent_int_dir/explicit-int-as-nat.stderr"
dependent_int_explicit_codec_status=$?
run_dependent_int_call bool:true int:-9223372036854775809 \
  > "$dependent_int_dir/underflow-call.stdout" \
  2> "$dependent_int_dir/underflow-call.stderr"
dependent_int_underflow_call_status=$?
set -e
for rejected in int-as-nat nat-as-int explicit-int-as-nat
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_int_dir/$rejected.stdout" \
    "$dependent_int_dir/$rejected.stderr"
  then
    echo "Agda29DependentIntCapture: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
  "$dependent_int_dir/overflow-environment.stdout" \
  "$dependent_int_dir/overflow-environment.stderr"
then
  echo "Agda29DependentIntCapture: overflow has wrong environment failure" >&2
  exit 1
fi
if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
  "$dependent_int_dir/underflow-call.stdout" \
  "$dependent_int_dir/underflow-call.stderr"
then
  echo "Agda29DependentIntCapture: explicit underflow has wrong call failure" >&2
  exit 1
fi
if [ "$dependent_int_as_nat_status" -eq 0 ] || \
   [ "$dependent_nat_as_int_status" -eq 0 ] || \
   [ "$dependent_int_overflow_status" -eq 0 ] || \
   [ "$dependent_int_explicit_codec_status" -eq 0 ] || \
   [ "$dependent_int_underflow_call_status" -eq 0 ]
then
  echo "Agda29DependentIntCapture: invalid dependent replay did not reject" >&2
  exit 1
fi
printf 'path\tresult\nlexical-int-zero\ttrue\nlexical-int-negative-one\tfalse\nlexical-nat-zero\ttrue\nlexical-nat-one\tfalse\nexplicit-int-min\tfalse\n' \
  > "$dependent_int_dir/int-dependent.tsv"

dependent_chain_dir="$build_dir/evidence/MixedOpenDependentChainResidual"
dependent_chain_source="$dependent_chain_dir/MixedOpenDependentChainResidual.agda"
dependent_chain_packet="$dependent_chain_dir/typed-residual.bin"
dependent_chain_hole_packet="$dependent_chain_dir/typed-residual-hole-1.bin"
dependent_chain_shell="$dependent_chain_dir/residual-static-shell.ss"
dependent_chain_hole_id=typed-hole@lambda-body.lambda-body.lambda-body.app-argument-1
dependent_chain_proxy_id=dependent-chain
dependent_chain_proxy_packet="$dependent_chain_dir/typed-proxy-$dependent_chain_proxy_id.bin"
dependent_chain_proxy_meta="$dependent_chain_dir/typed-proxy-$dependent_chain_proxy_id.meta"
dependent_chain_child_proxy_id=dependent-chain-wrapped
dependent_chain_child_proxy_packet="$dependent_chain_dir/typed-proxy-$dependent_chain_child_proxy_id.bin"
dependent_chain_child_proxy_meta="$dependent_chain_dir/typed-proxy-$dependent_chain_child_proxy_id.meta"
dependent_chain_wrong_proxy_id=dependent-chain-wrong
dependent_chain_wrong_proxy_packet="$dependent_chain_dir/typed-proxy-$dependent_chain_wrong_proxy_id.bin"
dependent_chain_wrong_proxy_meta="$dependent_chain_dir/typed-proxy-$dependent_chain_wrong_proxy_id.meta"
dependent_chain_explicit_proxy_id=dependent-chain-explicit
dependent_chain_explicit_proxy_packet="$dependent_chain_dir/typed-proxy-$dependent_chain_explicit_proxy_id.bin"
dependent_chain_explicit_proxy_meta="$dependent_chain_dir/typed-proxy-$dependent_chain_explicit_proxy_id.meta"
mkdir -p "$dependent_chain_dir"
rm -f \
  "$dependent_chain_proxy_packet" "$dependent_chain_proxy_meta" \
  "$dependent_chain_child_proxy_packet" "$dependent_chain_child_proxy_meta" \
  "$dependent_chain_wrong_proxy_packet" "$dependent_chain_wrong_proxy_meta" \
  "$dependent_chain_explicit_proxy_packet" \
  "$dependent_chain_explicit_proxy_meta"
cp "$fixture_dir/MixedOpenDependentChainResidual.agda" "$dependent_chain_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$dependent_chain_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependent_chain_dir" \
  "$dependent_chain_source" \
  > "$dependent_chain_dir/producer.log"
if [ ! -s "$dependent_chain_packet" ] || \
   [ ! -s "$dependent_chain_hole_packet" ] || \
   [ ! -s "$dependent_chain_shell" ] || \
   ! grep -Fqx \
     'residual-slice-static-shell-environment-binding: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: lambda-lifted-explicit+lexical-dependent-ground-elimination-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-explicit-and-dependent-ground-lexical-environment-observation-by-id-whole-entry-reference' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-environment-arity: 3' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-environment-binding-abi: dependent-ground-chez-lexical-binding-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: dependent-ground-environment-elimination-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-typed-value-proxy: persistent-typed-packet-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-composition: parent-retained-recursive-gc-v1' \
     "$dependent_chain_dir/typed-residual.txt" || \
   ! grep -Fq '(cubical-chez-bind-dependent-ground-environment' \
     "$dependent_chain_shell"
then
  echo "Agda29DependentGroundChainCapture: dependent chain capability is invalid" >&2
  exit 1
fi

dependent_chain_whole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$dependent_chain_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_chain_dir" \
    "$dependent_chain_source"
)
dependent_chain_hole_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$dependent_chain_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$dependent_chain_dir" \
    "$dependent_chain_source"
)
run_dependent_chain_capture() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --auto-bind-ground-hole="$dependent_chain_hole_id" \
    "$@" \
    --auto-bind-hole-type=OpenDependentChainResidualClosure \
    --auto-bind-result-consumer=consumeResidual
}
dependent_chain_true_zero_true_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true)
dependent_chain_true_zero_false_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:false)
dependent_chain_true_one_zero_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:1 \
  --entry-ground-argument=nat:0)
dependent_chain_true_one_one_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:1 \
  --entry-ground-argument=nat:1)
dependent_chain_false_true_zero_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0)
dependent_chain_false_true_one_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:1)
dependent_chain_false_false_true_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:true)
dependent_chain_false_false_false_result=$(run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:false)
if [ "$dependent_chain_whole_result" != true ] || \
   [ "$dependent_chain_hole_result" != true ] || \
   ! printf '%s\n' "$dependent_chain_true_zero_true_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_chain_true_zero_false_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_chain_true_one_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_chain_true_one_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_chain_false_true_zero_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_chain_false_true_one_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false' || \
   ! printf '%s\n' "$dependent_chain_false_false_true_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_chain_false_false_false_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false'
then
  echo "Agda29DependentGroundChainCapture: dependent chain values were not preserved" >&2
  exit 1
fi

run_dependent_chain_explicit_call() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --call-ground-hole="$dependent_chain_hole_id" \
    "$@" \
    --call-hole-type=OpenDependentChainResidualClosure \
    --call-result-consumer=consumeResidual
}
dependent_chain_explicit_result=$(run_dependent_chain_explicit_call \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  --ground-argument=bool:true)
if ! printf '%s\n' "$dependent_chain_explicit_result" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29ExplicitGroundCall: dependent explicit call failed" >&2
  exit 1
fi

run_dependent_chain_proxy() {
  proxy_id=$1
  shift
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --auto-bind-ground-hole="$dependent_chain_hole_id" \
    "$@" \
    --auto-bind-hole-type=OpenDependentChainResidualClosure \
    --auto-bind-proxy-id="$proxy_id"
}
dependent_chain_proxy_created=$(run_dependent_chain_proxy \
  "$dependent_chain_proxy_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true)
dependent_chain_expected_proxy="#(cubical-chez-typed-value-proxy-v1 $dependent_chain_proxy_id typed-proxy-$dependent_chain_proxy_id.bin)"
if [ "$dependent_chain_proxy_created" != "$dependent_chain_expected_proxy" ] || \
   [ ! -s "$dependent_chain_proxy_packet" ] || \
   [ ! -s "$dependent_chain_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$dependent_chain_proxy_id\" \".\" active)" \
     "$dependent_chain_proxy_meta"
then
  echo "Agda29DependentGroundProxy: materialized proxy is invalid" >&2
  exit 1
fi
dependent_chain_proxy_hash=$(shasum -a 256 \
  "$dependent_chain_proxy_packet" | awk '{print $1}')
dependent_chain_proxy_bytes=$(wc -c < \
  "$dependent_chain_proxy_packet" | tr -d ' ')
dependent_chain_proxy_first=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --consume-proxy="$dependent_chain_proxy_id" \
    --proxy-consumer=consumeResidual
)
dependent_chain_proxy_second=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --consume-proxy="$dependent_chain_proxy_id" \
    --proxy-consumer=consumeResidual
)
if ! printf '%s\n' "$dependent_chain_proxy_first" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true' || \
   ! printf '%s\n' "$dependent_chain_proxy_second" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29DependentGroundProxy: persistent result was not reusable" >&2
  exit 1
fi

set +e
run_dependent_chain_proxy \
  "$dependent_chain_proxy_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  > "$dependent_chain_dir/proxy-duplicate.stdout" \
  2> "$dependent_chain_dir/proxy-duplicate.stderr"
dependent_chain_proxy_duplicate_status=$?
run_dependent_chain_proxy \
  ../escape \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  > "$dependent_chain_dir/proxy-invalid-id.stdout" \
  2> "$dependent_chain_dir/proxy-invalid-id.stderr"
dependent_chain_proxy_invalid_id_status=$?
run_dependent_chain_proxy \
  dependent-chain-conflict \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  --auto-bind-result-consumer=consumeResidual \
  > "$dependent_chain_dir/proxy-action-conflict.stdout" \
  2> "$dependent_chain_dir/proxy-action-conflict.stderr"
dependent_chain_proxy_action_conflict_status=$?
run_dependent_chain_proxy \
  "$dependent_chain_wrong_proxy_id" \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/proxy-wrong-branch.stdout" \
  2> "$dependent_chain_dir/proxy-wrong-branch.stderr"
dependent_chain_proxy_wrong_branch_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
chez --script "$dependent_chain_shell" \
  --consume-proxy="$dependent_chain_proxy_id" \
  --proxy-consumer=consumeResidualWithCount \
  > "$dependent_chain_dir/proxy-wrong-consumer.stdout" \
  2> "$dependent_chain_dir/proxy-wrong-consumer.stderr"
dependent_chain_proxy_wrong_consumer_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
chez --script "$dependent_chain_shell" \
  --derive-proxy="$dependent_chain_proxy_id" \
  --derive-proxy-consumer=consumeResidualWithCount \
  --proxy-id="$dependent_chain_wrong_proxy_id" \
  > "$dependent_chain_dir/proxy-wrong-derive.stdout" \
  2> "$dependent_chain_dir/proxy-wrong-derive.stderr"
dependent_chain_proxy_wrong_derive_status=$?
run_dependent_chain_explicit_call \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  --ground-argument=nat:0 \
  > "$dependent_chain_dir/explicit-wrong-branch.stdout" \
  2> "$dependent_chain_dir/explicit-wrong-branch.stderr"
dependent_chain_explicit_wrong_branch_status=$?
run_dependent_chain_explicit_call \
  --ground-argument=bool:true \
  > "$dependent_chain_dir/explicit-missing-slot.stdout" \
  2> "$dependent_chain_dir/explicit-missing-slot.stderr"
dependent_chain_explicit_missing_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
chez --script "$dependent_chain_shell" \
  --call-ground-hole="$dependent_chain_hole_id" \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  --ground-argument=bool:true \
  --call-hole-type=OpenDependentChainResidualClosure \
  --call-result-consumer=consumeResidual \
  --call-proxy-id=dependent-chain-explicit-conflict \
  > "$dependent_chain_dir/explicit-action-conflict.stdout" \
  2> "$dependent_chain_dir/explicit-action-conflict.stderr"
dependent_chain_explicit_action_conflict_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
chez --script "$dependent_chain_shell" \
  --call-ground-hole="$dependent_chain_hole_id" \
  --ground-argument=bool:true \
  --ground-argument=nat:0 \
  --ground-argument=bool:true \
  --call-hole-type=OpenDependentChainResidualClosure \
  --call-proxy-id=../escape \
  > "$dependent_chain_dir/explicit-invalid-proxy-id.stdout" \
  2> "$dependent_chain_dir/explicit-invalid-proxy-id.stderr"
dependent_chain_explicit_invalid_proxy_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=bool:true \
  > "$dependent_chain_dir/wrong-second-slot.stdout" \
  2> "$dependent_chain_dir/wrong-second-slot.stderr"
dependent_chain_wrong_second_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/true-zero-wrong-third.stdout" \
  2> "$dependent_chain_dir/true-zero-wrong-third.stderr"
dependent_chain_true_zero_wrong_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:1 \
  --entry-ground-argument=bool:true \
  > "$dependent_chain_dir/true-one-wrong-third.stdout" \
  2> "$dependent_chain_dir/true-one-wrong-third.stderr"
dependent_chain_true_one_wrong_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=bool:true \
  > "$dependent_chain_dir/false-true-wrong-third.stdout" \
  2> "$dependent_chain_dir/false-true-wrong-third.stderr"
dependent_chain_false_true_wrong_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=bool:false \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/false-false-wrong-third.stdout" \
  2> "$dependent_chain_dir/false-false-wrong-third.stderr"
dependent_chain_false_false_wrong_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/swapped-chain.stdout" \
  2> "$dependent_chain_dir/swapped-chain.stderr"
dependent_chain_swapped_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/missing-chain-slot.stdout" \
  2> "$dependent_chain_dir/missing-chain-slot.stderr"
dependent_chain_missing_status=$?
run_dependent_chain_capture \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  --entry-ground-argument=bool:true \
  --entry-ground-argument=nat:0 \
  > "$dependent_chain_dir/extra-chain-slot.stdout" \
  2> "$dependent_chain_dir/extra-chain-slot.stderr"
dependent_chain_extra_status=$?
set -e
for rejected in \
  wrong-second-slot \
  true-zero-wrong-third \
  true-one-wrong-third \
  false-true-wrong-third \
  false-false-wrong-third \
  swapped-chain
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_chain_dir/$rejected.stdout" \
    "$dependent_chain_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundChainCapture: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
for rejected in missing-chain-slot extra-chain-slot
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
    "$dependent_chain_dir/$rejected.stdout" \
    "$dependent_chain_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundChainCapture: $rejected has wrong local failure code" >&2
    exit 1
  fi
done
for rejected in proxy-wrong-branch proxy-wrong-consumer proxy-wrong-derive
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
    "$dependent_chain_dir/$rejected.stdout" \
    "$dependent_chain_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundProxy: $rejected bypassed the Agda type gate" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$dependent_chain_dir/explicit-wrong-branch.stdout" \
     "$dependent_chain_dir/explicit-wrong-branch.stderr"
then
  echo "Agda29ExplicitGroundCall: wrong branch bypassed the Agda type gate" >&2
  exit 1
fi
for rejected in \
  explicit-missing-slot \
  explicit-action-conflict \
  explicit-invalid-proxy-id
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
    "$dependent_chain_dir/$rejected.stdout" \
    "$dependent_chain_dir/$rejected.stderr"
  then
    echo "Agda29ExplicitGroundCall: $rejected has wrong local failure code" >&2
    exit 1
  fi
done
for rejected in proxy-duplicate proxy-invalid-id
do
  if ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
    "$dependent_chain_dir/$rejected.stdout" \
    "$dependent_chain_dir/$rejected.stderr"
  then
    echo "Agda29DependentGroundProxy: $rejected has wrong proxy failure code" >&2
    exit 1
  fi
done
if ! grep -q 'CCZ-TYPED-BRIDGE-ENVIRONMENT' \
     "$dependent_chain_dir/proxy-action-conflict.stdout" \
     "$dependent_chain_dir/proxy-action-conflict.stderr" || \
   [ "$dependent_chain_proxy_duplicate_status" -eq 0 ] || \
   [ "$dependent_chain_proxy_invalid_id_status" -eq 0 ] || \
   [ "$dependent_chain_proxy_action_conflict_status" -eq 0 ] || \
   [ "$dependent_chain_proxy_wrong_branch_status" -eq 0 ] || \
   [ "$dependent_chain_proxy_wrong_consumer_status" -eq 0 ] || \
   [ "$dependent_chain_proxy_wrong_derive_status" -eq 0 ] || \
   [ -e "$dependent_chain_wrong_proxy_packet" ] || \
   [ -e "$dependent_chain_wrong_proxy_meta" ]
then
  echo "Agda29DependentGroundProxy: invalid proxy operation did not reject" >&2
  exit 1
fi
if [ "$dependent_chain_explicit_wrong_branch_status" -eq 0 ] || \
   [ "$dependent_chain_explicit_missing_status" -eq 0 ] || \
   [ "$dependent_chain_explicit_action_conflict_status" -eq 0 ] || \
   [ "$dependent_chain_explicit_invalid_proxy_status" -eq 0 ]
then
  echo "Agda29ExplicitGroundCall: invalid explicit call did not reject" >&2
  exit 1
fi
if [ "$dependent_chain_wrong_second_status" -eq 0 ] || \
   [ "$dependent_chain_true_zero_wrong_status" -eq 0 ] || \
   [ "$dependent_chain_true_one_wrong_status" -eq 0 ] || \
   [ "$dependent_chain_false_true_wrong_status" -eq 0 ] || \
   [ "$dependent_chain_false_false_wrong_status" -eq 0 ] || \
   [ "$dependent_chain_swapped_status" -eq 0 ] || \
   [ "$dependent_chain_missing_status" -eq 0 ] || \
   [ "$dependent_chain_extra_status" -eq 0 ]
then
  echo "Agda29DependentGroundChainCapture: invalid dependent chain replay did not reject" >&2
  exit 1
fi

dependent_chain_child_proxy_created=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --derive-proxy="$dependent_chain_proxy_id" \
    --derive-proxy-consumer=wrapResidual \
    --proxy-id="$dependent_chain_child_proxy_id"
)
dependent_chain_expected_child_proxy="#(cubical-chez-typed-value-proxy-v1 $dependent_chain_child_proxy_id typed-proxy-$dependent_chain_child_proxy_id.bin)"
if [ "$dependent_chain_child_proxy_created" != \
     "$dependent_chain_expected_child_proxy" ] || \
   [ ! -s "$dependent_chain_child_proxy_packet" ] || \
   [ ! -s "$dependent_chain_child_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$dependent_chain_child_proxy_id\" \"$dependent_chain_proxy_id\" active)" \
     "$dependent_chain_child_proxy_meta"
then
  echo "Agda29DependentGroundProxy: derived proxy is invalid" >&2
  exit 1
fi
dependent_chain_child_proxy_hash=$(shasum -a 256 \
  "$dependent_chain_child_proxy_packet" | awk '{print $1}')
dependent_chain_child_proxy_bytes=$(wc -c < \
  "$dependent_chain_child_proxy_packet" | tr -d ' ')
dependent_chain_proxy_released=$(chez --script "$dependent_chain_shell" \
  --drop-proxy="$dependent_chain_proxy_id")
dependent_chain_expected_retain="#(cubical-chez-typed-value-proxy-retained-v1 $dependent_chain_proxy_id)"
if [ "$dependent_chain_proxy_released" != "$dependent_chain_expected_retain" ] || \
   [ ! -s "$dependent_chain_proxy_packet" ] || \
   [ ! -s "$dependent_chain_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$dependent_chain_proxy_id\" \".\" released)" \
     "$dependent_chain_proxy_meta"
then
  echo "Agda29DependentGroundProxy: released parent was not retained" >&2
  exit 1
fi
dependent_chain_child_consumed=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --consume-proxy="$dependent_chain_child_proxy_id" \
    --proxy-consumer=consumeResidualWithCount
)
if ! printf '%s\n' "$dependent_chain_child_consumed" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29DependentGroundProxy: derived proxy was not consumable" >&2
  exit 1
fi
printf 'proxy-id\tparent\tpacket-bytes\tpacket-sha256\tresult\n%s\t.\t%s\t%s\t%s\n%s\t%s\t%s\t%s\t%s\n' \
  "$dependent_chain_proxy_id" \
  "$dependent_chain_proxy_bytes" "$dependent_chain_proxy_hash" \
  "$dependent_chain_proxy_first" \
  "$dependent_chain_child_proxy_id" "$dependent_chain_proxy_id" \
  "$dependent_chain_child_proxy_bytes" "$dependent_chain_child_proxy_hash" \
  "$dependent_chain_child_consumed" \
  > "$dependent_chain_dir/typed-proxy-lifecycle.tsv"
dependent_chain_child_dropped=$(chez --script "$dependent_chain_shell" \
  --drop-proxy="$dependent_chain_child_proxy_id")
dependent_chain_expected_child_drop="#(cubical-chez-typed-value-proxy-dropped-v1 $dependent_chain_child_proxy_id)"
if [ "$dependent_chain_child_dropped" != \
     "$dependent_chain_expected_child_drop" ] || \
   [ -e "$dependent_chain_proxy_packet" ] || \
   [ -e "$dependent_chain_proxy_meta" ] || \
   [ -e "$dependent_chain_child_proxy_packet" ] || \
   [ -e "$dependent_chain_child_proxy_meta" ]
then
  echo "Agda29DependentGroundProxy: recursive collection failed" >&2
  exit 1
fi

dependent_chain_explicit_proxy_created=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --call-ground-hole="$dependent_chain_hole_id" \
    --ground-argument=bool:true \
    --ground-argument=nat:0 \
    --ground-argument=bool:true \
    --call-hole-type=OpenDependentChainResidualClosure \
    --call-proxy-id="$dependent_chain_explicit_proxy_id"
)
dependent_chain_expected_explicit_proxy="#(cubical-chez-typed-value-proxy-v1 $dependent_chain_explicit_proxy_id typed-proxy-$dependent_chain_explicit_proxy_id.bin)"
if [ "$dependent_chain_explicit_proxy_created" != \
     "$dependent_chain_expected_explicit_proxy" ] || \
   [ ! -s "$dependent_chain_explicit_proxy_packet" ] || \
   [ ! -s "$dependent_chain_explicit_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$dependent_chain_explicit_proxy_id\" \".\" active)" \
     "$dependent_chain_explicit_proxy_meta"
then
  echo "Agda29ExplicitGroundCall: explicit proxy is invalid" >&2
  exit 1
fi
dependent_chain_explicit_proxy_hash=$(shasum -a 256 \
  "$dependent_chain_explicit_proxy_packet" | awk '{print $1}')
dependent_chain_explicit_proxy_bytes=$(wc -c < \
  "$dependent_chain_explicit_proxy_packet" | tr -d ' ')
dependent_chain_explicit_proxy_consumed=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$dependent_chain_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$dependent_chain_dir" \
  chez --script "$dependent_chain_shell" \
    --consume-proxy="$dependent_chain_explicit_proxy_id" \
    --proxy-consumer=consumeResidual
)
if ! printf '%s\n' "$dependent_chain_explicit_proxy_consumed" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29ExplicitGroundCall: explicit proxy was not consumable" >&2
  exit 1
fi
printf 'case\tresult\tpacket-bytes\tpacket-sha256\nordered-consume\t%s\t.\t.\ndependent-consume\t%s\t.\t.\ndependent-proxy\t%s\t%s\t%s\n' \
  "$open_ground_explicit_result" \
  "$dependent_chain_explicit_result" \
  "$dependent_chain_explicit_proxy_consumed" \
  "$dependent_chain_explicit_proxy_bytes" \
  "$dependent_chain_explicit_proxy_hash" \
  > "$dependent_chain_dir/explicit-ground-call.tsv"
dependent_chain_explicit_proxy_dropped=$(chez --script \
  "$dependent_chain_shell" \
  --drop-proxy="$dependent_chain_explicit_proxy_id")
dependent_chain_expected_explicit_drop="#(cubical-chez-typed-value-proxy-dropped-v1 $dependent_chain_explicit_proxy_id)"
if [ "$dependent_chain_explicit_proxy_dropped" != \
     "$dependent_chain_expected_explicit_drop" ] || \
   [ -e "$dependent_chain_explicit_proxy_packet" ] || \
   [ -e "$dependent_chain_explicit_proxy_meta" ]
then
  echo "Agda29ExplicitGroundCall: explicit proxy drop failed" >&2
  exit 1
fi

multi_dir="$build_dir/evidence/MixedResidualTwoHoles"
multi_source="$multi_dir/MixedResidualTwoHoles.agda"
multi_packet="$multi_dir/typed-residual.bin"
multi_hole_1_packet="$multi_dir/typed-residual-hole-1.bin"
multi_hole_2_packet="$multi_dir/typed-residual-hole-2.bin"
multi_shell="$multi_dir/residual-static-shell.ss"
multi_bridge="$multi_dir/typed-hole-ground-bridge.sh"
multi_hole_1_id=typed-hole@app-argument-1.app-argument-0
multi_hole_2_id=typed-hole@app-argument-1.app-argument-1
mkdir -p "$multi_dir"
cp "$fixture_dir/MixedResidualTwoHoles.agda" "$multi_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$multi_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$multi_dir" \
  "$multi_source" \
  > "$multi_dir/producer.log"
if [ ! -s "$multi_packet" ] || \
   [ ! -s "$multi_hole_1_packet" ] || \
   [ ! -s "$multi_hole_2_packet" ] || \
   [ -e "$multi_dir/typed-residual-hole-3.bin" ] || \
   [ ! -s "$multi_shell" ] || \
   [ ! -s "$multi_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$multi_dir/staging.txt" || \
   ! grep -Fqx 'residual-slice-hole-count: 2' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     "residual-slice-hole-ids: $multi_hole_1_id, $multi_hole_2_id" \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx "residual-slice-hole-1-id: $multi_hole_1_id" \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx "residual-slice-hole-2-id: $multi_hole_2_id" \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-artifact: typed-residual-hole-1.bin' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-2-artifact: typed-residual-hole-2.bin' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-hole-forcing: closed-hole-ground-observation-by-id-v1' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: closed-ground-unary-elimination-v1' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-hole-1-callable-abi: none' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-2-callable-abi: bool-unary-ground-elimination-v1' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-typed-value-proxy: persistent-typed-packet-v1' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-composition: parent-retained-recursive-gc-v1' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-open-hole-closure-conversion: none' \
     "$multi_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-execution: split-ground-observation-by-id-whole-entry-reference' \
     "$multi_dir/typed-residual.txt" || \
   [ -e "$multi_dir/program.ss" ]
then
  echo "Agda29MultiHolePacket: two-hole publication is invalid" >&2
  exit 1
fi

multi_shell_result=$(chez --script "$multi_shell")
if ! printf '%s\n' "$multi_shell_result" | grep -Fq "$multi_hole_1_id" || \
   ! printf '%s\n' "$multi_shell_result" | grep -Fq "$multi_hole_2_id" || \
   ! printf '%s\n' "$multi_shell_result" | \
     grep -q 'typed-residual-hole-1.bin' || \
   ! printf '%s\n' "$multi_shell_result" | \
     grep -q 'typed-residual-hole-2.bin' || \
   grep -q 'primTransp' "$multi_shell"
then
  echo "Agda29MultiHoleShell: opaque registry output is invalid" >&2
  exit 1
fi

multi_forced_bool=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
  CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole1 \
  chez --script "$multi_shell" --force-hole="$multi_hole_1_id"
)
if ! printf '%s\n' "$multi_forced_bool" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'; then
  echo "Agda29MultiHoleBridge: first ID did not return Bool true" >&2
  exit 1
fi
multi_forced_nat=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
  CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole2 \
  chez --script "$multi_shell" --force-hole="$multi_hole_2_id"
)
if [ "$multi_forced_nat" != 42 ]; then
  echo "Agda29MultiHoleBridge: second ID returned '$multi_forced_nat'" >&2
  exit 1
fi
multi_called_bool=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
  chez --script "$multi_shell" \
    --call-bool-hole="$multi_hole_2_id" \
    --bool-argument=false \
    --call-hole-type=ResidualWithFlag \
    --call-result-consumer=consumeHole1
)
if ! printf '%s\n' "$multi_called_bool" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'; then
  echo "Agda29MultiHoleBridge: typed Bool call did not return true" >&2
  exit 1
fi
multi_batch_observation=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
  chez --script "$multi_shell" \
    --observe-all-ground \
    --hole-consumer="$multi_hole_1_id=consumeHole1" \
    --hole-consumer="$multi_hole_2_id=consumeHole2"
)
multi_expected_batch="#(cubical-chez-ground-observations-v1 #($multi_hole_1_id #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true)) #($multi_hole_2_id 42))"
if [ "$multi_batch_observation" != "$multi_expected_batch" ]; then
  echo "Agda29MultiHoleBridge: batch observation bundle is invalid" >&2
  exit 1
fi
multi_reference_result=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$multi_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$multi_dir" \
    "$multi_source"
)
if [ "$multi_reference_result" != true ]; then
  echo "Agda29MultiHolePacket: whole-entry reference is invalid" >&2
  exit 1
fi

set +e
chez --script "$multi_shell" --force-hole=typed-hole@missing \
  > "$multi_dir/unknown-id.stdout" \
  2> "$multi_dir/unknown-id.stderr"
multi_unknown_status=$?
chez --script "$multi_shell" --force-first-hole \
  --force-hole="$multi_hole_1_id" \
  > "$multi_dir/conflicting-selector.stdout" \
  2> "$multi_dir/conflicting-selector.stderr"
multi_conflict_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
CUBICAL_CHEZ_TYPED_CONSUMER=consumeHole2 \
chez --script "$multi_shell" --force-hole="$multi_hole_1_id" \
  > "$multi_dir/cross-consumer.stdout" \
  2> "$multi_dir/cross-consumer.stderr"
multi_cross_status=$?
chez --script "$multi_shell" \
  --observe-all-ground \
  --hole-consumer="$multi_hole_1_id=consumeHole1" \
  > "$multi_dir/batch-missing.stdout" \
  2> "$multi_dir/batch-missing.stderr"
multi_batch_missing_status=$?
chez --script "$multi_shell" \
  --observe-all-ground \
  --hole-consumer="$multi_hole_1_id=consumeHole1" \
  --hole-consumer="$multi_hole_1_id=consumeHole1" \
  --hole-consumer="$multi_hole_2_id=consumeHole2" \
  > "$multi_dir/batch-duplicate.stdout" \
  2> "$multi_dir/batch-duplicate.stderr"
multi_batch_duplicate_status=$?
chez --script "$multi_shell" \
  --observe-all-ground \
  --hole-consumer="$multi_hole_1_id=consumeHole1" \
  --hole-consumer="$multi_hole_2_id=consumeHole2" \
  --hole-consumer=typed-hole@missing=consumeHole1 \
  > "$multi_dir/batch-unknown.stdout" \
  2> "$multi_dir/batch-unknown.stderr"
multi_batch_unknown_status=$?
chez --script "$multi_shell" \
  --observe-all-ground \
  --force-hole="$multi_hole_1_id" \
  --hole-consumer="$multi_hole_1_id=consumeHole1" \
  --hole-consumer="$multi_hole_2_id=consumeHole2" \
  > "$multi_dir/batch-conflict.stdout" \
  2> "$multi_dir/batch-conflict.stderr"
multi_batch_conflict_status=$?
chez --script "$multi_shell" \
  --call-bool-hole="$multi_hole_1_id" \
  --bool-argument=false \
  --call-hole-type=Residual \
  --call-result-consumer=consumeHole1 \
  > "$multi_dir/call-no-capability.stdout" \
  2> "$multi_dir/call-no-capability.stderr"
multi_call_no_capability_status=$?
chez --script "$multi_shell" \
  --call-bool-hole="$multi_hole_2_id" \
  --bool-argument=not-bool \
  --call-hole-type=ResidualWithFlag \
  --call-result-consumer=consumeHole1 \
  > "$multi_dir/call-invalid-bool.stdout" \
  2> "$multi_dir/call-invalid-bool.stderr"
multi_call_invalid_bool_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$multi_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$multi_dir" \
chez --script "$multi_shell" \
  --call-bool-hole="$multi_hole_2_id" \
  --bool-argument=false \
  --call-hole-type=NestedResidualWithFlag \
  --call-result-consumer=consumeHole2 \
  > "$multi_dir/call-wrong-domain.stdout" \
  2> "$multi_dir/call-wrong-domain.stderr"
multi_call_wrong_domain_status=$?
chez --script "$multi_shell" \
  --call-bool-hole="$multi_hole_2_id" \
  --bool-argument=false \
  --call-hole-type=ResidualWithFlag \
  > "$multi_dir/call-incomplete.stdout" \
  2> "$multi_dir/call-incomplete.stderr"
multi_call_incomplete_status=$?
chez --script "$multi_shell" \
  --call-bool-hole="$multi_hole_2_id" \
  --bool-argument=false \
  --call-hole-type=ResidualWithFlag \
  '--call-result-consumer=consumeHole1)' \
  > "$multi_dir/call-unsafe-qname.stdout" \
  2> "$multi_dir/call-unsafe-qname.stderr"
multi_call_unsafe_qname_status=$?
chez --script "$multi_shell" \
  --force-hole="$multi_hole_2_id" \
  --call-bool-hole="$multi_hole_2_id" \
  --bool-argument=false \
  --call-hole-type=ResidualWithFlag \
  --call-result-consumer=consumeHole1 \
  > "$multi_dir/call-conflict.stdout" \
  2> "$multi_dir/call-conflict.stderr"
multi_call_conflict_status=$?
set -e
if [ "$multi_unknown_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-HOLE-SELECTION' \
     "$multi_dir/unknown-id.stdout" "$multi_dir/unknown-id.stderr" || \
   [ "$multi_conflict_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-HOLE-SELECTION' \
     "$multi_dir/conflicting-selector.stdout" \
     "$multi_dir/conflicting-selector.stderr" || \
   [ "$multi_cross_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$multi_dir/cross-consumer.stdout" "$multi_dir/cross-consumer.stderr" || \
   [ "$multi_batch_missing_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-OBSERVATION' \
     "$multi_dir/batch-missing.stdout" "$multi_dir/batch-missing.stderr" || \
   [ "$multi_batch_duplicate_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-OBSERVATION' \
     "$multi_dir/batch-duplicate.stdout" \
     "$multi_dir/batch-duplicate.stderr" || \
   [ "$multi_batch_unknown_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-OBSERVATION' \
     "$multi_dir/batch-unknown.stdout" "$multi_dir/batch-unknown.stderr" || \
   [ "$multi_batch_conflict_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-OBSERVATION' \
     "$multi_dir/batch-conflict.stdout" "$multi_dir/batch-conflict.stderr" || \
   [ "$multi_call_no_capability_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$multi_dir/call-no-capability.stdout" \
     "$multi_dir/call-no-capability.stderr" || \
   [ "$multi_call_invalid_bool_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$multi_dir/call-invalid-bool.stdout" \
     "$multi_dir/call-invalid-bool.stderr" || \
   [ "$multi_call_wrong_domain_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$multi_dir/call-wrong-domain.stdout" \
     "$multi_dir/call-wrong-domain.stderr" || \
   [ "$multi_call_incomplete_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$multi_dir/call-incomplete.stdout" \
     "$multi_dir/call-incomplete.stderr" || \
   [ "$multi_call_unsafe_qname_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$multi_dir/call-unsafe-qname.stdout" \
     "$multi_dir/call-unsafe-qname.stderr" || \
   [ "$multi_call_conflict_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$multi_dir/call-conflict.stdout" \
     "$multi_dir/call-conflict.stderr"
then
  echo "Agda29MultiHoleBridge: ID selection did not fail closed" >&2
  exit 1
fi

nat_dir="$build_dir/evidence/MixedResidualNatCallable"
nat_source="$nat_dir/MixedResidualNatCallable.agda"
nat_packet="$nat_dir/typed-residual.bin"
nat_hole_packet="$nat_dir/typed-residual-hole-1.bin"
nat_shell="$nat_dir/residual-static-shell.ss"
nat_bridge="$nat_dir/typed-hole-ground-bridge.sh"
nat_hole_id=typed-hole@app-argument-1
nat_proxy_id=nat-seven
nat_proxy_packet="$nat_dir/typed-proxy-$nat_proxy_id.bin"
nat_proxy_meta="$nat_dir/typed-proxy-$nat_proxy_id.meta"
nat_child_proxy_id=nat-seven-wrapped
nat_child_proxy_packet="$nat_dir/typed-proxy-$nat_child_proxy_id.bin"
nat_child_proxy_meta="$nat_dir/typed-proxy-$nat_child_proxy_id.meta"
nat_wrong_derived_id=nat-seven-wrong-derived
nat_wrong_derived_packet="$nat_dir/typed-proxy-$nat_wrong_derived_id.bin"
nat_wrong_derived_meta="$nat_dir/typed-proxy-$nat_wrong_derived_id.meta"
mkdir -p "$nat_dir"
rm -f \
  "$nat_proxy_packet" "$nat_proxy_meta" \
  "$nat_child_proxy_packet" "$nat_child_proxy_meta" \
  "$nat_wrong_derived_packet" "$nat_wrong_derived_meta"
cp "$fixture_dir/MixedResidualNatCallable.agda" "$nat_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$nat_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$nat_dir" \
  "$nat_source" \
  > "$nat_dir/producer.log"
if [ ! -s "$nat_packet" ] || \
   [ ! -s "$nat_hole_packet" ] || \
   [ -e "$nat_dir/typed-residual-hole-2.bin" ] || \
   [ ! -s "$nat_shell" ] || \
   [ ! -s "$nat_bridge" ] || \
   ! grep -Fqx 'binding-time: mixed' "$nat_dir/staging.txt" || \
   ! grep -Fqx 'residual-slice-hole-count: 1' \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx "residual-slice-hole-ids: $nat_hole_id" \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-callable-elimination: closed-ground-unary-elimination-v1' \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: nat-unary-ground-elimination-v1' \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-typed-value-proxy: persistent-typed-packet-v1' \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-composition: parent-retained-recursive-gc-v1' \
     "$nat_dir/typed-residual.txt" || \
   ! grep -Fqx 'residual-slice-open-hole-closure-conversion: none' \
     "$nat_dir/typed-residual.txt" || \
   [ -e "$nat_dir/program.ss" ]
then
  echo "Agda29NatCallablePacket: Nat-callable publication is invalid" >&2
  exit 1
fi

nat_shell_result=$(chez --script "$nat_shell")
if ! printf '%s\n' "$nat_shell_result" | grep -Fq "$nat_hole_id" || \
   ! printf '%s\n' "$nat_shell_result" | \
     grep -q 'nat-unary-ground-elimination-v1' || \
   grep -q 'primTransp' "$nat_shell"
then
  echo "Agda29NatCallableShell: opaque registry output is invalid" >&2
  exit 1
fi

nat_called=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --call-nat-hole="$nat_hole_id" \
    --nat-argument=7 \
    --call-hole-type=ResidualWithCount \
    --call-result-consumer=consumeResidualNat
)
if [ "$nat_called" != 42 ]; then
  echo "Agda29NatCallableBridge: typed Nat call returned '$nat_called'" >&2
  exit 1
fi

nat_proxy_created=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --materialize-nat-hole="$nat_hole_id" \
    --materialize-nat-argument=7 \
    --materialize-hole-type=ResidualWithCount \
    --proxy-id="$nat_proxy_id"
)
nat_expected_proxy="#(cubical-chez-typed-value-proxy-v1 $nat_proxy_id typed-proxy-$nat_proxy_id.bin)"
if [ "$nat_proxy_created" != "$nat_expected_proxy" ] || \
   [ ! -s "$nat_proxy_packet" ] || [ ! -s "$nat_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$nat_proxy_id\" \".\" active)" \
     "$nat_proxy_meta"; then
  echo "Agda29TypedProxy: materialized proxy is invalid" >&2
  exit 1
fi
nat_proxy_hash_before=$(shasum -a 256 "$nat_proxy_packet" | awk '{print $1}')
nat_proxy_bytes=$(wc -c < "$nat_proxy_packet" | tr -d ' ')

nat_proxy_first=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --consume-proxy="$nat_proxy_id" \
    --proxy-consumer=consumeResidualNat
)
nat_proxy_second=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --consume-proxy="$nat_proxy_id" \
    --proxy-consumer=consumeResidualNat
)
if [ "$nat_proxy_first" != 42 ] || [ "$nat_proxy_second" != 42 ]; then
  echo "Agda29TypedProxy: persistent proxy was not reusable" >&2
  exit 1
fi

set +e
chez --script "$nat_shell" \
  --call-nat-hole="$nat_hole_id" \
  --nat-argument=-1 \
  --call-hole-type=ResidualWithCount \
  --call-result-consumer=consumeResidualNat \
  > "$nat_dir/call-invalid-nat.stdout" \
  2> "$nat_dir/call-invalid-nat.stderr"
nat_invalid_status=$?
chez --script "$nat_shell" \
  --call-nat-hole="$nat_hole_id" \
  --nat-argument=4294967296 \
  --call-hole-type=ResidualWithCount \
  --call-result-consumer=consumeResidualNat \
  > "$nat_dir/call-overflow.stdout" \
  2> "$nat_dir/call-overflow.stderr"
nat_overflow_status=$?
chez --script "$nat_shell" \
  --call-bool-hole="$nat_hole_id" \
  --bool-argument=false \
  --call-hole-type=ResidualWithCount \
  --call-result-consumer=consumeResidualNat \
  > "$nat_dir/call-codec-mismatch.stdout" \
  2> "$nat_dir/call-codec-mismatch.stderr"
nat_codec_mismatch_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
chez --script "$nat_shell" \
  --call-nat-hole="$nat_hole_id" \
  --nat-argument=7 \
  --call-hole-type=NestedResidualWithCount \
  --call-result-consumer=consumeResidualWithCountNat \
  > "$nat_dir/call-wrong-domain.stdout" \
  2> "$nat_dir/call-wrong-domain.stderr"
nat_wrong_domain_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
chez --script "$nat_shell" \
  --materialize-nat-hole="$nat_hole_id" \
  --materialize-nat-argument=7 \
  --materialize-hole-type=ResidualWithCount \
  --proxy-id="$nat_proxy_id" \
  > "$nat_dir/proxy-duplicate.stdout" \
  2> "$nat_dir/proxy-duplicate.stderr"
nat_proxy_duplicate_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
chez --script "$nat_shell" \
  --consume-proxy="$nat_proxy_id" \
  --proxy-consumer=consumeResidualWithCountNat \
  > "$nat_dir/proxy-wrong-consumer.stdout" \
  2> "$nat_dir/proxy-wrong-consumer.stderr"
nat_proxy_wrong_consumer_status=$?
chez --script "$nat_shell" \
  --materialize-nat-hole="$nat_hole_id" \
  --materialize-nat-argument=7 \
  --materialize-hole-type=ResidualWithCount \
  --proxy-id=../escape \
  > "$nat_dir/proxy-invalid-id.stdout" \
  2> "$nat_dir/proxy-invalid-id.stderr"
nat_proxy_invalid_id_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
chez --script "$nat_shell" \
  --derive-proxy="$nat_proxy_id" \
  --derive-proxy-consumer=consumeResidualWithCountNat \
  --proxy-id="$nat_wrong_derived_id" \
  > "$nat_dir/proxy-derive-wrong-domain.stdout" \
  2> "$nat_dir/proxy-derive-wrong-domain.stderr"
nat_proxy_derive_wrong_domain_status=$?
set -e
nat_proxy_hash_after=$(shasum -a 256 "$nat_proxy_packet" | awk '{print $1}')
if [ "$nat_invalid_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$nat_dir/call-invalid-nat.stdout" \
     "$nat_dir/call-invalid-nat.stderr" || \
   [ "$nat_overflow_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$nat_dir/call-overflow.stdout" \
     "$nat_dir/call-overflow.stderr" || \
   [ "$nat_codec_mismatch_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$nat_dir/call-codec-mismatch.stdout" \
     "$nat_dir/call-codec-mismatch.stderr" || \
   [ "$nat_wrong_domain_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$nat_dir/call-wrong-domain.stdout" \
     "$nat_dir/call-wrong-domain.stderr" || \
   [ "$nat_proxy_duplicate_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$nat_dir/proxy-duplicate.stdout" \
     "$nat_dir/proxy-duplicate.stderr" || \
   [ "$nat_proxy_hash_before" != "$nat_proxy_hash_after" ] || \
   [ "$nat_proxy_wrong_consumer_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$nat_dir/proxy-wrong-consumer.stdout" \
     "$nat_dir/proxy-wrong-consumer.stderr" || \
   [ "$nat_proxy_invalid_id_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$nat_dir/proxy-invalid-id.stdout" \
     "$nat_dir/proxy-invalid-id.stderr" || \
   [ "$nat_proxy_derive_wrong_domain_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$nat_dir/proxy-derive-wrong-domain.stdout" \
     "$nat_dir/proxy-derive-wrong-domain.stderr" || \
   [ -e "$nat_wrong_derived_packet" ] || \
   [ -e "$nat_wrong_derived_meta" ]
then
  echo "Agda29NatCallableBridge: Nat call/proxy did not fail closed" >&2
  exit 1
fi

nat_child_proxy_created=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --derive-proxy="$nat_proxy_id" \
    --derive-proxy-consumer=wrapResidual \
    --proxy-id="$nat_child_proxy_id"
)
nat_expected_child_proxy="#(cubical-chez-typed-value-proxy-v1 $nat_child_proxy_id typed-proxy-$nat_child_proxy_id.bin)"
if [ "$nat_child_proxy_created" != "$nat_expected_child_proxy" ] || \
   [ ! -s "$nat_child_proxy_packet" ] || \
   [ ! -s "$nat_child_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$nat_child_proxy_id\" \"$nat_proxy_id\" active)" \
     "$nat_child_proxy_meta"; then
  echo "Agda29TypedProxy: derived proxy is invalid" >&2
  exit 1
fi
nat_child_proxy_hash=$(shasum -a 256 "$nat_child_proxy_packet" | awk '{print $1}')
nat_child_proxy_bytes=$(wc -c < "$nat_child_proxy_packet" | tr -d ' ')
nat_proxy_meta_bytes=$(wc -c < "$nat_proxy_meta" | tr -d ' ')
nat_proxy_meta_hash=$(shasum -a 256 "$nat_proxy_meta" | awk '{print $1}')
nat_child_proxy_meta_bytes=$(wc -c < "$nat_child_proxy_meta" | tr -d ' ')
nat_child_proxy_meta_hash=$(shasum -a 256 "$nat_child_proxy_meta" | awk '{print $1}')

nat_proxy_released=$(
  chez --script "$nat_shell" --drop-proxy="$nat_proxy_id"
)
nat_expected_retain="#(cubical-chez-typed-value-proxy-retained-v1 $nat_proxy_id)"
if [ "$nat_proxy_released" != "$nat_expected_retain" ] || \
   [ ! -s "$nat_proxy_packet" ] || [ ! -s "$nat_proxy_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$nat_proxy_id\" \".\" released)" \
     "$nat_proxy_meta"; then
  echo "Agda29TypedProxy: parent retention after release failed" >&2
  exit 1
fi

set +e
chez --script "$nat_shell" \
  --consume-proxy="$nat_proxy_id" \
  --proxy-consumer=consumeResidualNat \
  > "$nat_dir/proxy-after-release.stdout" \
  2> "$nat_dir/proxy-after-release.stderr"
nat_proxy_after_release_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
chez --script "$nat_shell" \
  --derive-proxy="$nat_proxy_id" \
  --derive-proxy-consumer=wrapResidual \
  --proxy-id=nat-seven-after-release \
  > "$nat_dir/proxy-derive-after-release.stdout" \
  2> "$nat_dir/proxy-derive-after-release.stderr"
nat_proxy_derive_after_release_status=$?
set -e
if [ "$nat_proxy_after_release_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$nat_dir/proxy-after-release.stdout" \
     "$nat_dir/proxy-after-release.stderr" || \
   [ "$nat_proxy_derive_after_release_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$nat_dir/proxy-derive-after-release.stdout" \
     "$nat_dir/proxy-derive-after-release.stderr" || \
   [ -e "$nat_dir/typed-proxy-nat-seven-after-release.bin" ] || \
   [ -e "$nat_dir/typed-proxy-nat-seven-after-release.meta" ]; then
  echo "Agda29TypedProxy: released parent remained addressable" >&2
  exit 1
fi

nat_child_proxy_consumed=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$nat_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$nat_dir" \
  chez --script "$nat_shell" \
    --consume-proxy="$nat_child_proxy_id" \
    --proxy-consumer=consumeResidualWithCountNat
)
if [ "$nat_child_proxy_consumed" != 42 ]; then
  echo "Agda29TypedProxy: derived proxy consumer returned '$nat_child_proxy_consumed'" >&2
  exit 1
fi

nat_gc_active=$(chez --script "$nat_shell" --gc-proxies)
if [ "$nat_gc_active" != \
     '#(cubical-chez-typed-value-proxy-gc-v1 0)' ] || \
   [ ! -s "$nat_proxy_packet" ] || [ ! -s "$nat_proxy_meta" ] || \
   [ ! -s "$nat_child_proxy_packet" ] || \
   [ ! -s "$nat_child_proxy_meta" ]; then
  echo "Agda29TypedProxy: GC collected a live proxy graph" >&2
  exit 1
fi

nat_child_proxy_dropped=$(
  chez --script "$nat_shell" --drop-proxy="$nat_child_proxy_id"
)
nat_expected_child_drop="#(cubical-chez-typed-value-proxy-dropped-v1 $nat_child_proxy_id)"
if [ "$nat_child_proxy_dropped" != "$nat_expected_child_drop" ] || \
   [ -e "$nat_proxy_packet" ] || [ -e "$nat_proxy_meta" ] || \
   [ -e "$nat_child_proxy_packet" ] || \
   [ -e "$nat_child_proxy_meta" ]; then
  echo "Agda29TypedProxy: recursive proxy GC failed" >&2
  exit 1
fi

nat_gc_idempotent=$(chez --script "$nat_shell" --gc-proxies)
if [ "$nat_gc_idempotent" != \
     '#(cubical-chez-typed-value-proxy-gc-v1 0)' ]; then
  echo "Agda29TypedProxy: proxy GC is not idempotent" >&2
  exit 1
fi

set +e
chez --script "$nat_shell" \
  --consume-proxy="$nat_proxy_id" \
  --proxy-consumer=consumeResidualNat \
  > "$nat_dir/proxy-after-drop.stdout" \
  2> "$nat_dir/proxy-after-drop.stderr"
nat_proxy_after_drop_status=$?
set -e
if [ "$nat_proxy_after_drop_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$nat_dir/proxy-after-drop.stdout" \
     "$nat_dir/proxy-after-drop.stderr"; then
  echo "Agda29TypedProxy: collected proxy remained addressable" >&2
  exit 1
fi

printf 'proxy-id\tparent\tpacket-bytes\tpacket-sha256\tmeta-bytes\tmeta-sha256\tfirst\tsecond\treleased\n%s\t.\t%s\t%s\t%s\t%s\t%s\t%s\ttrue\n%s\t%s\t%s\t%s\t%s\t%s\t%s\t-\ttrue\n' \
  "$nat_proxy_id" "$nat_proxy_bytes" "$nat_proxy_hash_before" \
  "$nat_proxy_meta_bytes" "$nat_proxy_meta_hash" \
  "$nat_proxy_first" "$nat_proxy_second" \
  "$nat_child_proxy_id" "$nat_proxy_id" \
  "$nat_child_proxy_bytes" "$nat_child_proxy_hash" \
  "$nat_child_proxy_meta_bytes" "$nat_child_proxy_meta_hash" \
  "$nat_child_proxy_consumed" \
  > "$nat_dir/typed-proxy-lifecycle.tsv"

word64_callable_dir="$build_dir/evidence/MixedResidualWord64Callable"
word64_callable_source="$word64_callable_dir/MixedResidualWord64Callable.agda"
word64_callable_packet="$word64_callable_dir/typed-residual.bin"
word64_callable_hole_packet="$word64_callable_dir/typed-residual-hole-1.bin"
word64_callable_shell="$word64_callable_dir/residual-static-shell.ss"
word64_callable_hole_id=typed-hole@app-argument-1
word64_callable_proxy_id=word64-max
word64_callable_proxy_packet="$word64_callable_dir/typed-proxy-$word64_callable_proxy_id.bin"
word64_callable_proxy_meta="$word64_callable_dir/typed-proxy-$word64_callable_proxy_id.meta"
word64_callable_overflow_proxy_id=word64-overflow
word64_callable_overflow_proxy_packet="$word64_callable_dir/typed-proxy-$word64_callable_overflow_proxy_id.bin"
word64_callable_overflow_proxy_meta="$word64_callable_dir/typed-proxy-$word64_callable_overflow_proxy_id.meta"
word64_max=18446744073709551615
word64_overflow=18446744073709551616
mkdir -p "$word64_callable_dir"
rm -f \
  "$word64_callable_proxy_packet" "$word64_callable_proxy_meta" \
  "$word64_callable_overflow_proxy_packet" \
  "$word64_callable_overflow_proxy_meta"
cp "$fixture_dir/MixedResidualWord64Callable.agda" "$word64_callable_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$word64_callable_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$word64_callable_dir" \
  "$word64_callable_source" \
  > "$word64_callable_dir/producer.log"
if [ ! -s "$word64_callable_packet" ] || \
   [ ! -s "$word64_callable_hole_packet" ] || \
   [ ! -s "$word64_callable_shell" ] || \
   ! grep -Fqx 'binding-time: mixed' \
     "$word64_callable_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-hole-1-callable-abi: word64-unary-ground-elimination-v1' \
     "$word64_callable_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-typed-value-proxy: persistent-typed-packet-v1' \
     "$word64_callable_dir/typed-residual.txt" || \
   [ -e "$word64_callable_dir/program.ss" ]
then
  echo "Agda29Word64CallablePacket: publication is invalid" >&2
  exit 1
fi

word64_callable_whole=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$word64_callable_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$word64_callable_dir" \
    "$word64_callable_source"
)
word64_callable_direct=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$word64_callable_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$word64_callable_dir" \
    "$word64_callable_source"
)
word64_callable_zero=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
  chez --script "$word64_callable_shell" \
    --call-word64-hole="$word64_callable_hole_id" \
    --word64-argument=0 \
    --call-hole-type=ResidualWithWord64 \
    --call-result-consumer=consumeResidualNat
)
word64_callable_max=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
  chez --script "$word64_callable_shell" \
    --call-word64-hole="$word64_callable_hole_id" \
    --word64-argument="$word64_max" \
    --call-hole-type=ResidualWithWord64 \
    --call-result-consumer=consumeResidualNat
)
if [ "$word64_callable_whole" != true ] || \
   [ "$word64_callable_direct" != true ] || \
   [ "$word64_callable_zero" != 42 ] || \
   [ "$word64_callable_max" != 0 ]
then
  echo "Agda29Word64CallableBridge: Word64 argument was not preserved" >&2
  exit 1
fi

word64_callable_proxy_created=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
  chez --script "$word64_callable_shell" \
    --call-word64-hole="$word64_callable_hole_id" \
    --word64-argument="$word64_max" \
    --call-hole-type=ResidualWithWord64 \
    --call-proxy-id="$word64_callable_proxy_id"
)
word64_callable_expected_proxy="#(cubical-chez-typed-value-proxy-v1 $word64_callable_proxy_id typed-proxy-$word64_callable_proxy_id.bin)"
if [ "$word64_callable_proxy_created" != \
     "$word64_callable_expected_proxy" ] || \
   [ ! -s "$word64_callable_proxy_packet" ] || \
   [ ! -s "$word64_callable_proxy_meta" ]
then
  echo "Agda29Word64CallableProxy: materialization failed" >&2
  exit 1
fi
word64_callable_proxy_hash_before=$(
  shasum -a 256 "$word64_callable_proxy_packet" | awk '{print $1}'
)
word64_callable_proxy_bytes=$(
  wc -c < "$word64_callable_proxy_packet" | tr -d ' '
)
word64_callable_proxy_consumed=$(
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
  chez --script "$word64_callable_shell" \
    --consume-proxy="$word64_callable_proxy_id" \
    --proxy-consumer=consumeResidualNat
)
if [ "$word64_callable_proxy_consumed" != 0 ]; then
  echo "Agda29Word64CallableProxy: consumer returned '$word64_callable_proxy_consumed'" >&2
  exit 1
fi

set +e
chez --script "$word64_callable_shell" \
  --call-word64-hole="$word64_callable_hole_id" \
  --word64-argument="$word64_overflow" \
  --call-hole-type=ResidualWithWord64 \
  --call-result-consumer=consumeResidualNat \
  > "$word64_callable_dir/call-overflow.stdout" \
  2> "$word64_callable_dir/call-overflow.stderr"
word64_callable_overflow_status=$?
chez --script "$word64_callable_shell" \
  --call-nat-hole="$word64_callable_hole_id" \
  --nat-argument=0 \
  --call-hole-type=ResidualWithWord64 \
  --call-result-consumer=consumeResidualNat \
  > "$word64_callable_dir/call-codec-mismatch.stdout" \
  2> "$word64_callable_dir/call-codec-mismatch.stderr"
word64_callable_codec_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
chez --script "$word64_callable_shell" \
  --call-word64-hole="$word64_callable_hole_id" \
  --word64-argument=0 \
  --call-hole-type=NestedResidualWithWord64 \
  --call-result-consumer=consumeResidualWithWord64Nat \
  > "$word64_callable_dir/call-wrong-domain.stdout" \
  2> "$word64_callable_dir/call-wrong-domain.stderr"
word64_callable_wrong_domain_status=$?
chez --script "$word64_callable_shell" \
  --call-word64-hole="$word64_callable_hole_id" \
  --word64-argument="$word64_overflow" \
  --call-hole-type=ResidualWithWord64 \
  --call-proxy-id="$word64_callable_overflow_proxy_id" \
  > "$word64_callable_dir/proxy-overflow.stdout" \
  2> "$word64_callable_dir/proxy-overflow.stderr"
word64_callable_proxy_overflow_status=$?
CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
CUBICAL_CHEZ_TYPED_SOURCE="$word64_callable_source" \
CUBICAL_CHEZ_TYPED_INCLUDE="$word64_callable_dir" \
chez --script "$word64_callable_shell" \
  --call-word64-hole="$word64_callable_hole_id" \
  --word64-argument="$word64_max" \
  --call-hole-type=ResidualWithWord64 \
  --call-proxy-id="$word64_callable_proxy_id" \
  > "$word64_callable_dir/proxy-duplicate.stdout" \
  2> "$word64_callable_dir/proxy-duplicate.stderr"
word64_callable_proxy_duplicate_status=$?
set -e
word64_callable_proxy_hash_after=$(
  shasum -a 256 "$word64_callable_proxy_packet" | awk '{print $1}'
)
if [ "$word64_callable_overflow_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$word64_callable_dir/call-overflow.stdout" \
     "$word64_callable_dir/call-overflow.stderr" || \
   [ "$word64_callable_codec_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$word64_callable_dir/call-codec-mismatch.stdout" \
     "$word64_callable_dir/call-codec-mismatch.stderr" || \
   [ "$word64_callable_wrong_domain_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$word64_callable_dir/call-wrong-domain.stdout" \
     "$word64_callable_dir/call-wrong-domain.stderr" || \
   [ "$word64_callable_proxy_overflow_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-CALL' \
     "$word64_callable_dir/proxy-overflow.stdout" \
     "$word64_callable_dir/proxy-overflow.stderr" || \
   [ -e "$word64_callable_overflow_proxy_packet" ] || \
   [ -e "$word64_callable_overflow_proxy_meta" ] || \
   [ "$word64_callable_proxy_duplicate_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$word64_callable_dir/proxy-duplicate.stdout" \
     "$word64_callable_dir/proxy-duplicate.stderr" || \
   [ "$word64_callable_proxy_hash_before" != \
     "$word64_callable_proxy_hash_after" ]
then
  echo "Agda29Word64CallableBridge: call/proxy did not fail closed" >&2
  exit 1
fi

word64_callable_proxy_dropped=$(
  chez --script "$word64_callable_shell" \
    --drop-proxy="$word64_callable_proxy_id"
)
word64_callable_expected_drop="#(cubical-chez-typed-value-proxy-dropped-v1 $word64_callable_proxy_id)"
if [ "$word64_callable_proxy_dropped" != \
     "$word64_callable_expected_drop" ] || \
   [ -e "$word64_callable_proxy_packet" ] || \
   [ -e "$word64_callable_proxy_meta" ]
then
  echo "Agda29Word64CallableProxy: drop failed" >&2
  exit 1
fi

printf 'zero\tmax\tproxy-bytes\tproxy-sha256\tproxy-consumed\tproxy-dropped\n%s\t%s\t%s\t%s\t%s\ttrue\n' \
  "$word64_callable_zero" "$word64_callable_max" \
  "$word64_callable_proxy_bytes" "$word64_callable_proxy_hash_before" \
  "$word64_callable_proxy_consumed" \
  > "$word64_callable_dir/word64-unary.tsv"

typed_carrier_dir="$build_dir/evidence/MixedOpenTypedCarrier"
typed_carrier_source="$typed_carrier_dir/MixedOpenTypedCarrier.agda"
typed_carrier_packet="$typed_carrier_dir/typed-residual.bin"
typed_carrier_hole_packet="$typed_carrier_dir/typed-residual-hole-1.bin"
typed_carrier_shell="$typed_carrier_dir/residual-static-shell.ss"
typed_carrier_hole_id=typed-hole@lambda-body.app-argument-1
typed_carrier_root_id=carrier-residual
typed_carrier_payload_id=carrier-payload
typed_carrier_wrapped_id=carrier-wrapped
typed_carrier_root_packet="$typed_carrier_dir/typed-proxy-$typed_carrier_root_id.bin"
typed_carrier_root_meta="$typed_carrier_dir/typed-proxy-$typed_carrier_root_id.meta"
typed_carrier_payload_packet="$typed_carrier_dir/typed-proxy-$typed_carrier_payload_id.bin"
typed_carrier_payload_meta="$typed_carrier_dir/typed-proxy-$typed_carrier_payload_id.meta"
typed_carrier_wrapped_packet="$typed_carrier_dir/typed-proxy-$typed_carrier_wrapped_id.bin"
typed_carrier_wrapped_meta="$typed_carrier_dir/typed-proxy-$typed_carrier_wrapped_id.meta"
mkdir -p "$typed_carrier_dir"
cp "$fixture_dir/MixedOpenTypedCarrier.agda" "$typed_carrier_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$typed_carrier_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$typed_carrier_dir" \
  "$typed_carrier_source" \
  > "$typed_carrier_dir/producer.log"
if [ ! -s "$typed_carrier_packet" ] || \
   [ ! -s "$typed_carrier_hole_packet" ] || \
   [ ! -s "$typed_carrier_shell" ] || \
   ! grep -Fqx 'binding-time: mixed' \
     "$typed_carrier_dir/staging.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-typed-value-carrier: checked-packet-reference-v1' \
     "$typed_carrier_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-mapping: named-checked-function-v1' \
     "$typed_carrier_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-store-quota: count-256+bytes-67108864-v1' \
     "$typed_carrier_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-publication-lock: atomic-mkdir-v1' \
     "$typed_carrier_dir/typed-residual.txt" || \
   ! grep -Fqx \
     'residual-slice-static-shell-proxy-state-transactions: store-lock+atomic-state-v1' \
     "$typed_carrier_dir/typed-residual.txt" || \
   grep -q 'primTransp' "$typed_carrier_shell"
then
  echo "Agda29TypedCarrier: capability publication is invalid" >&2
  exit 1
fi

typed_carrier_whole=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$typed_carrier_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$typed_carrier_dir" \
    "$typed_carrier_source"
)
typed_carrier_direct=$(
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consumeClosure \
    --cubical-term-file="$typed_carrier_hole_packet" \
    --no-libraries \
    --no-write-interfaces \
    -i "$typed_carrier_dir" \
    "$typed_carrier_source"
)
if [ "$typed_carrier_whole" != true ] || \
   [ "$typed_carrier_direct" != true ]; then
  echo "Agda29TypedCarrier: whole/direct typed references failed" >&2
  exit 1
fi

run_typed_carrier_shell() {
  CUBICAL_CHEZ_TYPED_RUNNER="$runner" \
  CUBICAL_CHEZ_AGDA_DATADIR="$agda29_source_dir/src/data" \
  CUBICAL_CHEZ_TYPED_SOURCE="$typed_carrier_source" \
  CUBICAL_CHEZ_TYPED_INCLUDE="$typed_carrier_dir" \
  chez --script "$typed_carrier_shell" "$@"
}

typed_carrier_root_created=$(
  run_typed_carrier_shell \
    --auto-bind-nat-hole="$typed_carrier_hole_id" \
    --entry-nat-argument=0 \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-proxy-id="$typed_carrier_root_id"
)
typed_carrier_expected_root="#(cubical-chez-typed-value-proxy-v1 $typed_carrier_root_id typed-proxy-$typed_carrier_root_id.bin)"
if [ "$typed_carrier_root_created" != "$typed_carrier_expected_root" ] || \
   [ ! -s "$typed_carrier_root_packet" ] || \
   [ ! -s "$typed_carrier_root_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$typed_carrier_root_id\" \".\" active)" \
     "$typed_carrier_root_meta"
then
  echo "Agda29TypedCarrier: root proxy is invalid" >&2
  exit 1
fi

typed_carrier_payload_created=$(
  run_typed_carrier_shell \
    --map-proxy="$typed_carrier_root_id" \
    --map-proxy-function=toPayload \
    --proxy-id="$typed_carrier_payload_id"
)
typed_carrier_expected_payload="#(cubical-chez-typed-value-proxy-v1 $typed_carrier_payload_id typed-proxy-$typed_carrier_payload_id.bin)"
typed_carrier_wrapped_created=$(
  run_typed_carrier_shell \
    --map-proxy="$typed_carrier_payload_id" \
    --map-proxy-function=toWrapped \
    --proxy-id="$typed_carrier_wrapped_id"
)
typed_carrier_expected_wrapped="#(cubical-chez-typed-value-proxy-v1 $typed_carrier_wrapped_id typed-proxy-$typed_carrier_wrapped_id.bin)"
if [ "$typed_carrier_payload_created" != \
     "$typed_carrier_expected_payload" ] || \
   [ "$typed_carrier_wrapped_created" != \
     "$typed_carrier_expected_wrapped" ] || \
   [ ! -s "$typed_carrier_payload_packet" ] || \
   [ ! -s "$typed_carrier_payload_meta" ] || \
   [ ! -s "$typed_carrier_wrapped_packet" ] || \
   [ ! -s "$typed_carrier_wrapped_meta" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$typed_carrier_payload_id\" \"$typed_carrier_root_id\" active)" \
     "$typed_carrier_payload_meta" || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$typed_carrier_wrapped_id\" \"$typed_carrier_payload_id\" active)" \
     "$typed_carrier_wrapped_meta"
then
  echo "Agda29TypedCarrier: record/data proxy mapping is invalid" >&2
  exit 1
fi

typed_carrier_observed=$(
  run_typed_carrier_shell \
    --map-proxy="$typed_carrier_wrapped_id" \
    --map-proxy-function=consumeWrapped \
    --map-proxy-result-consumer=idBool
)
if ! printf '%s\n' "$typed_carrier_observed" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29TypedCarrier: mapped ground observation returned '$typed_carrier_observed'" >&2
  exit 1
fi

set +e
run_typed_carrier_shell \
  --map-proxy="$typed_carrier_root_id" \
  --map-proxy-function=consumeWrapped \
  --proxy-id=carrier-wrong-domain \
  > "$typed_carrier_dir/map-wrong-domain.stdout" \
  2> "$typed_carrier_dir/map-wrong-domain.stderr"
typed_carrier_wrong_domain_status=$?
run_typed_carrier_shell \
  --map-proxy="$typed_carrier_wrapped_id" \
  --map-proxy-function=consumeWrapped \
  --map-proxy-result-consumer=consumeResidual \
  > "$typed_carrier_dir/map-wrong-result.stdout" \
  2> "$typed_carrier_dir/map-wrong-result.stderr"
typed_carrier_wrong_result_status=$?
run_typed_carrier_shell \
  --map-proxy="$typed_carrier_root_id" \
  '--map-proxy-function=toPayload)' \
  --proxy-id=carrier-unsafe-function \
  > "$typed_carrier_dir/map-unsafe-function.stdout" \
  2> "$typed_carrier_dir/map-unsafe-function.stderr"
typed_carrier_unsafe_function_status=$?
run_typed_carrier_shell \
  --map-proxy="$typed_carrier_root_id" \
  --map-proxy-function=toPayload \
  --proxy-id=carrier-conflict \
  --map-proxy-result-consumer=idBool \
  > "$typed_carrier_dir/map-action-conflict.stdout" \
  2> "$typed_carrier_dir/map-action-conflict.stderr"
typed_carrier_action_conflict_status=$?
set -e
if [ "$typed_carrier_wrong_domain_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$typed_carrier_dir/map-wrong-domain.stdout" \
     "$typed_carrier_dir/map-wrong-domain.stderr" || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-wrong-domain.bin" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-wrong-domain.meta" ] || \
   [ "$typed_carrier_wrong_result_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-RUNNER-EXIT' \
     "$typed_carrier_dir/map-wrong-result.stdout" \
     "$typed_carrier_dir/map-wrong-result.stderr" || \
   [ "$typed_carrier_unsafe_function_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$typed_carrier_dir/map-unsafe-function.stdout" \
     "$typed_carrier_dir/map-unsafe-function.stderr" || \
   [ "$typed_carrier_action_conflict_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$typed_carrier_dir/map-action-conflict.stdout" \
     "$typed_carrier_dir/map-action-conflict.stderr"
then
  echo "Agda29TypedCarrier: map type/configuration gate failed" >&2
  exit 1
fi

typed_carrier_root_released=$(
  chez --script "$typed_carrier_shell" \
    --drop-proxy="$typed_carrier_root_id"
)
typed_carrier_expected_retain="#(cubical-chez-typed-value-proxy-retained-v1 $typed_carrier_root_id)"
if [ "$typed_carrier_root_released" != \
     "$typed_carrier_expected_retain" ] || \
   ! grep -Fqx \
     "#(ccz-proxy-meta-v1 \"$typed_carrier_root_id\" \".\" released)" \
     "$typed_carrier_root_meta"
then
  echo "Agda29TypedCarrier: released carrier root was not retained" >&2
  exit 1
fi

set +e
run_typed_carrier_shell \
  --map-proxy="$typed_carrier_root_id" \
  --map-proxy-function=toPayload \
  --proxy-id=carrier-after-release \
  > "$typed_carrier_dir/map-after-release.stdout" \
  2> "$typed_carrier_dir/map-after-release.stderr"
typed_carrier_after_release_status=$?
set -e
if [ "$typed_carrier_after_release_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$typed_carrier_dir/map-after-release.stdout" \
     "$typed_carrier_dir/map-after-release.stderr" || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-after-release.bin" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-after-release.meta" ]
then
  echo "Agda29TypedCarrier: released source remained mappable" >&2
  exit 1
fi

typed_carrier_root_bytes=$(wc -c < "$typed_carrier_root_packet" | tr -d ' ')
typed_carrier_payload_bytes=$(wc -c < "$typed_carrier_payload_packet" | tr -d ' ')
typed_carrier_wrapped_bytes=$(wc -c < "$typed_carrier_wrapped_packet" | tr -d ' ')
typed_carrier_wrapped_dropped=$(
  chez --script "$typed_carrier_shell" \
    --drop-proxy="$typed_carrier_wrapped_id"
)
typed_carrier_payload_dropped=$(
  chez --script "$typed_carrier_shell" \
    --drop-proxy="$typed_carrier_payload_id"
)
if [ "$typed_carrier_wrapped_dropped" != \
     "#(cubical-chez-typed-value-proxy-dropped-v1 $typed_carrier_wrapped_id)" ] || \
   [ "$typed_carrier_payload_dropped" != \
     "#(cubical-chez-typed-value-proxy-dropped-v1 $typed_carrier_payload_id)" ] || \
   [ -e "$typed_carrier_root_packet" ] || \
   [ -e "$typed_carrier_root_meta" ] || \
   [ -e "$typed_carrier_payload_packet" ] || \
   [ -e "$typed_carrier_payload_meta" ] || \
   [ -e "$typed_carrier_wrapped_packet" ] || \
   [ -e "$typed_carrier_wrapped_meta" ]
then
  echo "Agda29TypedCarrier: recursive carrier cleanup failed" >&2
  exit 1
fi

printf 'kind\tpacket-bytes\tparent\nresidual\t%s\t.\npayload\t%s\t%s\nwrapped\t%s\t%s\n' \
  "$typed_carrier_root_bytes" \
  "$typed_carrier_payload_bytes" "$typed_carrier_root_id" \
  "$typed_carrier_wrapped_bytes" "$typed_carrier_payload_id" \
  > "$typed_carrier_dir/typed-carrier.tsv"

typed_carrier_create_root() {
  quota_proxy_id=$1
  run_typed_carrier_shell \
    --auto-bind-nat-hole="$typed_carrier_hole_id" \
    --entry-nat-argument=0 \
    --auto-bind-hole-type=OpenResidualClosure \
    --auto-bind-proxy-id="$quota_proxy_id"
}

set +e
(
  export CUBICAL_CHEZ_TYPED_PROXY_MAX_BYTES=1024
  typed_carrier_create_root carrier-quota-bytes
) > "$typed_carrier_dir/quota-bytes.stdout" \
  2> "$typed_carrier_dir/quota-bytes.stderr"
typed_carrier_quota_bytes_status=$?
set -e
if [ "$typed_carrier_quota_bytes_status" -eq 0 ] || \
   ! grep -q 'CCZ-TYPED-BRIDGE-QUOTA' \
     "$typed_carrier_dir/quota-bytes.stdout" \
     "$typed_carrier_dir/quota-bytes.stderr" || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-quota-bytes.bin" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-quota-bytes.meta" ] || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]
then
  echo "Agda29ProxyStoreQuota: byte quota did not fail cleanly" >&2
  exit 1
fi

set +e
(
  export CUBICAL_CHEZ_TYPED_PROXY_MAX_COUNT=1
  typed_carrier_create_root carrier-quota-race-a
) > "$typed_carrier_dir/quota-race-a.stdout" \
  2> "$typed_carrier_dir/quota-race-a.stderr" &
typed_carrier_quota_race_a_pid=$!
(
  export CUBICAL_CHEZ_TYPED_PROXY_MAX_COUNT=1
  typed_carrier_create_root carrier-quota-race-b
) > "$typed_carrier_dir/quota-race-b.stdout" \
  2> "$typed_carrier_dir/quota-race-b.stderr" &
typed_carrier_quota_race_b_pid=$!
wait "$typed_carrier_quota_race_a_pid"
typed_carrier_quota_race_a_status=$?
wait "$typed_carrier_quota_race_b_pid"
typed_carrier_quota_race_b_status=$?
set -e
if [ "$typed_carrier_quota_race_a_status" -eq 0 ] && \
   [ "$typed_carrier_quota_race_b_status" -ne 0 ]; then
  typed_carrier_quota_winner=carrier-quota-race-a
  typed_carrier_quota_loser_output="$typed_carrier_dir/quota-race-b"
elif [ "$typed_carrier_quota_race_b_status" -eq 0 ] && \
     [ "$typed_carrier_quota_race_a_status" -ne 0 ]; then
  typed_carrier_quota_winner=carrier-quota-race-b
  typed_carrier_quota_loser_output="$typed_carrier_dir/quota-race-a"
else
  echo "Agda29ProxyStoreQuota: concurrent count gate was not exclusive" >&2
  exit 1
fi
if ! grep -q 'cubical-chez-typed-value-proxy-v1' \
     "$typed_carrier_dir/quota-race-a.stdout" \
     "$typed_carrier_dir/quota-race-b.stdout" || \
   ! grep -q 'CCZ-TYPED-BRIDGE-QUOTA' \
     "$typed_carrier_quota_loser_output.stdout" \
     "$typed_carrier_quota_loser_output.stderr" || \
   [ ! -s "$typed_carrier_dir/typed-proxy-$typed_carrier_quota_winner.bin" ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-$typed_carrier_quota_winner.meta" ] || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]
then
  echo "Agda29ProxyStoreQuota: concurrent publication exceeded the count quota" >&2
  exit 1
fi

chez --script "$typed_carrier_shell" \
  --drop-proxy="$typed_carrier_quota_winner" \
  > "$typed_carrier_dir/quota-winner-drop.stdout"
typed_carrier_quota_reused=$(
  CUBICAL_CHEZ_TYPED_PROXY_MAX_COUNT=1 \
    typed_carrier_create_root carrier-quota-reused
)
if [ "$typed_carrier_quota_reused" != \
     '#(cubical-chez-typed-value-proxy-v1 carrier-quota-reused typed-proxy-carrier-quota-reused.bin)' ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-quota-reused.bin" ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-quota-reused.meta" ]
then
  echo "Agda29ProxyStoreQuota: released capacity was not reusable" >&2
  exit 1
fi
typed_carrier_quota_reused_bytes=$(
  wc -c < "$typed_carrier_dir/typed-proxy-carrier-quota-reused.bin" | \
    tr -d ' '
)
chez --script "$typed_carrier_shell" \
  --drop-proxy=carrier-quota-reused \
  > "$typed_carrier_dir/quota-reused-drop.stdout"
if [ -e "$typed_carrier_dir/typed-proxy-carrier-quota-reused.bin" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-quota-reused.meta" ] || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]; then
  echo "Agda29ProxyStoreQuota: quota evidence left store artifacts" >&2
  exit 1
fi
printf 'default-count\tdefault-bytes\trace-winner\treused-bytes\n256\t67108864\t%s\t%s\n' \
  "$typed_carrier_quota_winner" "$typed_carrier_quota_reused_bytes" \
  > "$typed_carrier_dir/proxy-store-quota.tsv"

mkdir "$typed_carrier_dir/.typed-proxy-store.lock"
printf '999999999\n' \
  > "$typed_carrier_dir/.typed-proxy-store.lock/owner"
typed_carrier_stale_lock_gc=$(
  chez --script "$typed_carrier_shell" --gc-proxies
)
if [ "$typed_carrier_stale_lock_gc" != \
     '#(cubical-chez-typed-value-proxy-gc-v1 0)' ] || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]; then
  echo "Agda29ProxyStateTransaction: stale lock was not recovered" >&2
  exit 1
fi

set +e
typed_carrier_create_root carrier-state-race \
  > "$typed_carrier_dir/state-race-create.stdout" \
  2> "$typed_carrier_dir/state-race-create.stderr" &
typed_carrier_state_create_pid=$!
chez --script "$typed_carrier_shell" --gc-proxies \
  > "$typed_carrier_dir/state-race-gc.stdout" \
  2> "$typed_carrier_dir/state-race-gc.stderr" &
typed_carrier_state_gc_pid=$!
wait "$typed_carrier_state_create_pid"
typed_carrier_state_create_status=$?
wait "$typed_carrier_state_gc_pid"
typed_carrier_state_gc_status=$?
set -e
if [ "$typed_carrier_state_create_status" -ne 0 ] || \
   [ "$typed_carrier_state_gc_status" -ne 0 ] || \
   ! grep -q 'cubical-chez-typed-value-proxy-v1' \
     "$typed_carrier_dir/state-race-create.stdout" || \
   ! grep -Fqx '#(cubical-chez-typed-value-proxy-gc-v1 0)' \
     "$typed_carrier_dir/state-race-gc.stdout" || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-state-race.bin" ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-state-race.meta" ] || \
   ! grep -Fqx \
     '#(ccz-proxy-meta-v1 "carrier-state-race" "." active)' \
     "$typed_carrier_dir/typed-proxy-carrier-state-race.meta" || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]
then
  echo "Agda29ProxyStateTransaction: publish/GC race was not serializable" >&2
  exit 1
fi

printf 'interrupted-state-write\n' \
  > "$typed_carrier_dir/typed-proxy-carrier-state-race.meta.state"
typed_carrier_state_temp_gc=$(
  chez --script "$typed_carrier_shell" --gc-proxies
)
if [ "$typed_carrier_state_temp_gc" != \
     '#(cubical-chez-typed-value-proxy-gc-v1 1)' ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-state-race.meta.state" ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-state-race.bin" ] || \
   [ ! -s "$typed_carrier_dir/typed-proxy-carrier-state-race.meta" ]; then
  echo "Agda29ProxyStateTransaction: interrupted state temp was not recovered" >&2
  exit 1
fi

typed_carrier_state_consumed=$(
  run_typed_carrier_shell \
    --consume-proxy=carrier-state-race \
    --proxy-consumer=consumeResidual
)
if ! printf '%s\n' "$typed_carrier_state_consumed" | \
     grep -q 'agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true'
then
  echo "Agda29ProxyStateTransaction: locked consume failed" >&2
  exit 1
fi

set +e
chez --script "$typed_carrier_shell" \
  --drop-proxy=carrier-state-race \
  > "$typed_carrier_dir/state-drop-a.stdout" \
  2> "$typed_carrier_dir/state-drop-a.stderr" &
typed_carrier_state_drop_a_pid=$!
chez --script "$typed_carrier_shell" \
  --drop-proxy=carrier-state-race \
  > "$typed_carrier_dir/state-drop-b.stdout" \
  2> "$typed_carrier_dir/state-drop-b.stderr" &
typed_carrier_state_drop_b_pid=$!
wait "$typed_carrier_state_drop_a_pid"
typed_carrier_state_drop_a_status=$?
wait "$typed_carrier_state_drop_b_pid"
typed_carrier_state_drop_b_status=$?
set -e
if [ "$typed_carrier_state_drop_a_status" -eq 0 ] && \
   [ "$typed_carrier_state_drop_b_status" -ne 0 ]; then
  typed_carrier_state_drop_loser="$typed_carrier_dir/state-drop-b"
elif [ "$typed_carrier_state_drop_b_status" -eq 0 ] && \
     [ "$typed_carrier_state_drop_a_status" -ne 0 ]; then
  typed_carrier_state_drop_loser="$typed_carrier_dir/state-drop-a"
else
  echo "Agda29ProxyStateTransaction: concurrent drop was not exclusive" >&2
  exit 1
fi
if ! grep -q 'cubical-chez-typed-value-proxy-dropped-v1' \
     "$typed_carrier_dir/state-drop-a.stdout" \
     "$typed_carrier_dir/state-drop-b.stdout" || \
   ! grep -q 'CCZ-TYPED-BRIDGE-PROXY' \
     "$typed_carrier_state_drop_loser.stdout" \
     "$typed_carrier_state_drop_loser.stderr" || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-state-race.bin" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-state-race.meta" ] || \
   [ -e "$typed_carrier_dir/typed-proxy-carrier-state-race.meta.state" ] || \
   [ -d "$typed_carrier_dir/.typed-proxy-store.lock" ]
then
  echo "Agda29ProxyStateTransaction: concurrent drop corrupted store state" >&2
  exit 1
fi
printf 'stale-lock-recovered\tpublish-gc\tstate-temp-recovered\tconsume\tdrop-winner\ntrue\ttrue\ttrue\ttrue\t1/2\n' \
  > "$typed_carrier_dir/proxy-state-transaction.tsv"

core_abi_dir="$build_dir/evidence/StaticCoreAbi"
core_abi_source="$core_abi_dir/StaticCoreAbi.agda"
mkdir -p "$core_abi_dir"
rm -f "$core_abi_dir/program.ss" "$core_abi_dir/staging.txt" \
  "$core_abi_dir/runner.ss" "$core_abi_dir/core-abi.tsv"
cp "$fixture_dir/StaticCoreAbi.agda" "$core_abi_source"
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$core_abi_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$core_abi_dir" \
  "$core_abi_source" \
  > "$core_abi_dir/producer.stdout" \
  2> "$core_abi_dir/producer.stderr"
if ! grep -Fqx 'chez-core-abi: chez-core-abi-v1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx 'chez-function-abi: unary-curried-closure-v1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx 'chez-data-constructor-abi: tagged-vector-v1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx 'chez-record-abi: tagged-vector-v1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx 'chez-constructor-tag-index: 0' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx 'chez-constructor-field-base-index: 1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx \
     'chez-primitive-application-abi: exact-arity-whitelist-v1' \
     "$core_abi_dir/staging.txt" || \
   ! grep -q \
     '^chez-primitive-application-map: PAdd/2=+.*P64ToI/1=identity$' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fqx \
     'chez-primitive-first-class-map: PAdd=curried:+,PSub=curried:-,PMul=curried:*' \
     "$core_abi_dir/staging.txt" || \
   ! grep -Fq '; Chez core ABI: chez-core-abi-v1.' \
     "$core_abi_dir/program.ss"
then
  echo "Agda29CoreAbi: versioned ABI contract is incomplete" >&2
  exit 1
fi
cp "$core_abi_dir/program.ss" "$core_abi_dir/runner.ss"
printf '%s\n' \
  "(display ((agda_StaticCoreAbi_2e_main (lambda (x) (* x 2))) (vector 'agda_StaticCoreAbi_2e_Choice_2e_picked (vector 'agda_StaticCoreAbi_2e_box 19))))" \
  '(newline)' \
  >> "$core_abi_dir/runner.ss"
core_abi_actual=$(chez --script "$core_abi_dir/runner.ss" | tail -n 1)
core_abi_expected='#(agda_StaticCoreAbi_2e_Choice_2e_picked #(agda_StaticCoreAbi_2e_box 42))'
if [ "$core_abi_actual" != "$core_abi_expected" ]; then
  echo "Agda29CoreAbi: expected '$core_abi_expected', got '$core_abi_actual'" >&2
  exit 1
fi
printf 'abi\tfunction\tdata\trecord\tprimitive\tresult\nchez-core-abi-v1\tcurried\ttagged-vector\ttagged-vector\texact-arity-whitelist\t42\n' \
  > "$core_abi_dir/core-abi.tsv"

verify_consumer_identity() {
  identity_label=$1
  identity_fixture=$2
  identity_error=$3
  identity_dir="$build_dir/evidence/$identity_label"
  identity_source="$identity_dir/$(basename "$identity_fixture")"

  mkdir -p "$identity_dir"
  cp "$identity_fixture" "$identity_source"
  set +e
  Agda_datadir="$agda29_source_dir/src/data" "$runner" \
    -v0 \
    --cubical-import=consume \
    --cubical-term-file="$packet_file" \
    --no-libraries \
    --no-write-interfaces \
    -i "$identity_dir" \
    "$identity_source" \
    > "$identity_dir/consumer.stdout" \
    2> "$identity_dir/consumer.stderr"
  identity_code=$?
  set -e

  if [ "$identity_code" -eq 0 ] || \
     ! grep -q "$identity_error" \
       "$identity_dir/consumer.stdout" \
       "$identity_dir/consumer.stderr"; then
    echo "Agda29Packet: $identity_label identity check did not reject" >&2
    exit 1
  fi
}

verify_consumer_identity \
  module-mismatch \
  "$fixture_dir/PacketOtherModule.agda" \
  'different top-level'
verify_consumer_identity \
  hash-mismatch \
  "$fixture_dir/hash-mismatch/PacketResidual.agda" \
  'signature hash'

set +e
Agda_datadir="$agda29_source_dir/src/data" "$runner" \
  -v0 \
  --cubical-import=consumeWrong \
  --cubical-term-file="$packet_file" \
  --no-libraries \
  --no-write-interfaces \
  -i "$evidence_dir" \
  "$source_file" \
  > "$evidence_dir/wrong-consumer.stdout" \
  2> "$evidence_dir/wrong-consumer.stderr"
wrong_consumer_code=$?
set -e

if [ "$wrong_consumer_code" -eq 0 ] || \
   ! grep -q 'UnequalTypes' \
     "$evidence_dir/wrong-consumer.stdout" \
     "$evidence_dir/wrong-consumer.stderr"; then
  echo "Agda29Packet: wrong consumer type was not safely rejected" >&2
  exit 1
fi

dd if="$packet_file" \
  of="$evidence_dir/typed-residual.truncated.bin" \
  bs=1 count=64 2>/dev/null
set +e
Agda_datadir="$agda29_source_dir/src/data" "$runner" \
  -v0 \
  --cubical-import=consume \
  --cubical-term-file="$evidence_dir/typed-residual.truncated.bin" \
  --no-libraries \
  --no-write-interfaces \
  -i "$evidence_dir" \
  "$source_file" \
  > "$evidence_dir/truncated.stdout" \
  2> "$evidence_dir/truncated.stderr"
truncated_code=$?
set -e

if [ "$truncated_code" -eq 0 ] || \
   ! grep -q 'Cubical runtime: malformed or truncated Term packet' \
     "$evidence_dir/truncated.stdout" \
     "$evidence_dir/truncated.stderr" || \
   grep -q 'CallStack' \
     "$evidence_dir/truncated.stdout" \
     "$evidence_dir/truncated.stderr"; then
  echo "Agda29Packet: truncated packet was not safely rejected" >&2
  exit 1
fi

# A sparse file proves the size check happens before the decoder allocates or
# traverses a packet body.
dd if=/dev/zero \
  of="$evidence_dir/typed-residual.oversized.bin" \
  bs=1 count=0 seek=67108865 2>/dev/null
set +e
Agda_datadir="$agda29_source_dir/src/data" "$runner" \
  -v0 \
  --cubical-import=consume \
  --cubical-term-file="$evidence_dir/typed-residual.oversized.bin" \
  --no-libraries \
  --no-write-interfaces \
  -i "$evidence_dir" \
  "$source_file" \
  > "$evidence_dir/oversized.stdout" \
  2> "$evidence_dir/oversized.stderr"
oversized_code=$?
set -e

if [ "$oversized_code" -eq 0 ] || \
   ! grep -q 'Cubical runtime: Term packet exceeds the 64 MiB size' \
     "$evidence_dir/oversized.stdout" \
     "$evidence_dir/oversized.stderr"; then
  echo "Agda29Packet: oversized packet was not rejected before decoding" >&2
  exit 1
fi

dependency_slice_dir="$build_dir/evidence/ResidualDependencySlice"
dependency_slice_source="$dependency_slice_dir/ResidualDependencyClosure.agda"
mkdir -p "$dependency_slice_dir"
rm -f "$dependency_slice_dir/typed-residual.txt" \
  "$dependency_slice_dir/dependency-slice.tsv"
cp "$fixture_dir/ResidualDependencyClosure.agda" "$dependency_slice_source"
set +e
Agda_datadir="$agda29_source_dir/src/data" "$binary" \
  -v0 \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$dependency_slice_dir" \
  --no-libraries \
  --no-write-interfaces \
  -i "$dependency_slice_dir" \
  "$dependency_slice_source" \
  > "$dependency_slice_dir/producer.stdout" \
  2> "$dependency_slice_dir/producer.stderr"
dependency_slice_status=$?
set -e
dependency_slice_manifest="$dependency_slice_dir/typed-residual.txt"
if [ "$dependency_slice_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUAL-REQUIRED' \
     "$dependency_slice_dir/producer.stdout" \
     "$dependency_slice_dir/producer.stderr" || \
   ! grep -Fqx \
     'residual-dependency-slice: checked-type+definition-body-v1' \
     "$dependency_slice_manifest" || \
   ! grep -Fqx \
     'residual-excluded-presentation-dependency-count: 1' \
     "$dependency_slice_manifest" || \
   ! grep -Fqx \
     'residual-excluded-presentation-dependencies: ResidualDependencyClosure.presentationOnly' \
     "$dependency_slice_manifest" || \
   grep '^residual-resolved-dependencies: ' "$dependency_slice_manifest" | \
     grep -q 'ResidualDependencyClosure.presentationOnly'
then
  echo "Agda29DependencySlice: presentation metadata entered the executable closure" >&2
  exit 1
fi
dependency_slice_resolved=$(sed -n \
  's/^residual-resolved-dependency-count: //p' "$dependency_slice_manifest")
dependency_slice_expanded=$(sed -n \
  's/^residual-expanded-definition-count: //p' "$dependency_slice_manifest")
printf 'contract\tresolved\texpanded\texcluded-presentation\nchecked-type+definition-body-v1\t%s\t%s\t1\n' \
  "$dependency_slice_resolved" "$dependency_slice_expanded" \
  > "$dependency_slice_dir/dependency-slice.tsv"

verify_invalid_producer() {
  label=$1
  macro=$2
  expected_code=$3
  module=${4:-PacketResidual}
  invalid_dir="$build_dir/evidence/$label"
  invalid_binary="$build_dir/cubical-chez-$label"

  mkdir -p "$build_dir/ghc-$label" "$invalid_dir"
  cp "$fixture_dir/$module.agda" "$invalid_dir/$module.agda"
  (
    cd "$agda29_source_dir"
    cabal exec -w "$ghc29" -- "$ghc29" \
      -O0 -Wall -Werror -DCUBICAL_CHEZ_AGDA_29 "$macro" \
      -package Agda \
      -i"$backend_dir/src" \
      -outputdir "$build_dir/ghc-$label" \
      -o "$invalid_binary" \
      "$backend_dir/src/Main.hs"
  )

  set +e
  Agda_datadir="$agda29_source_dir/src/data" "$invalid_binary" \
    -v0 \
    --cubical-chez \
    --cubical-chez-engine=agda-baseline \
    --cubical-chez-residual=packet \
    --cubical-chez-output="$invalid_dir" \
    --no-libraries \
    --no-write-interfaces \
    -i "$invalid_dir" \
    "$invalid_dir/$module.agda" \
    > "$invalid_dir/producer.stdout" \
    2> "$invalid_dir/producer.stderr"
  invalid_code=$?
  set -e

  if [ "$invalid_code" -eq 0 ] || \
     ! grep -q "$expected_code" \
       "$invalid_dir/producer.stdout" \
       "$invalid_dir/producer.stderr" || \
     [ -e "$invalid_dir/typed-residual.bin" ] || \
     [ -e "$invalid_dir/typed-residual-hole-1.bin" ] || \
     [ -e "$invalid_dir/residual-static-shell.ss" ] || \
     [ -e "$invalid_dir/typed-hole-ground-bridge.sh" ] || \
     [ -e "$invalid_dir/program.ss" ]; then
    echo "Agda29Packet: $label producer negative did not reject safely" >&2
    exit 1
  fi
}

verify_invalid_producer \
  bad-magic \
  -DCUBICAL_CHEZ_TEST_BAD_MAGIC \
  'CCZ-RESIDUALIZATION-FAILED'
verify_invalid_producer \
  bad-version \
  -DCUBICAL_CHEZ_TEST_BAD_VERSION \
  'CCZ-RESIDUALIZATION-FAILED'
verify_invalid_producer \
  open-term \
  -DCUBICAL_CHEZ_TEST_OPEN_TERM \
  'CCZ-RESIDUALIZATION-FAILED'
verify_invalid_producer \
  unresolved-meta \
  -DCUBICAL_CHEZ_TEST_UNRESOLVED_META \
  'CCZ-RESIDUALIZATION-FAILED'
verify_invalid_producer \
  dependency-mismatch \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_DEPENDENCY_MISMATCH \
  'CCZ-RESIDUALIZATION-FAILED'
verify_invalid_producer \
  presentation-dependency-leak \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_PRESENTATION_DEPENDENCY_LEAK \
  'CCZ-RESIDUALIZATION-FAILED' \
  ResidualDependencyClosure
verify_invalid_producer \
  core-abi-mismatch \
  -DCUBICAL_CHEZ_TEST_CORE_ABI_MISMATCH \
  'CCZ-SCHEME-LOWERING-FAILED' \
  StaticCoreAbi
verify_invalid_producer \
  core-abi-primitive-drift \
  -DCUBICAL_CHEZ_TEST_CORE_ABI_PRIMITIVE_DRIFT \
  'CCZ-SCHEME-LOWERING-FAILED' \
  StaticCoreAbi

echo "Agda29Packet PASS (v2 consumer: $consumer_result)"
echo "Agda29NbeAdapterSpike PASS (14 baseline-equal test-only results + 7 expected rejects)"
echo "Agda29NbeProductionCandidate PASS (1 selected+linked baseline-equal result)"
echo "Agda29MixedPacket PASS (static shell observation: $mixed_consumer_result)"
echo "Agda29MixedHolePacket PASS (independent typed hole: $mixed_hole_consumer_result)"
echo "Agda29MixedShell PASS (opaque hole import observation)"
echo "Agda29MixedBridge PASS (Bool/Nat forcing + 3 expected rejects)"
echo "Agda29OpenClosureBridge PASS (lambda-lifted Bool environment + 2 expected rejects)"
echo "Agda29LexicalBoolCapture PASS (true/false Chez capture + 4 expected rejects)"
echo "Agda29LexicalNatCapture PASS (whole/direct/explicit + zero/suc Chez capture + 5 expected rejects)"
echo "Agda29LexicalWord64Capture PASS (whole/direct/explicit + zero/max Chez capture + 6 expected rejects)"
echo "Agda29LexicalCharCapture PASS (whole/direct + 2 lexical + 2 explicit + 5 expected rejects)"
echo "Agda29LexicalIntCapture PASS (whole/direct + 2 lexical + 2 explicit + 7 expected rejects)"
echo "Agda29OrderedGroundCapture PASS (whole/direct + 3 ordered Chez captures + 6 expected rejects)"
echo "Agda29OrderedCharCapture PASS (whole/direct + 2 lexical + explicit + 4 expected rejects)"
echo "Agda29OrderedIntCapture PASS (whole/direct + 2 lexical + explicit + 4 expected rejects)"
echo "Agda29Word64GroundCapture PASS (whole/direct + lexical 0/1 + explicit + 4 expected rejects)"
echo "Agda29DependentGroundCapture PASS (whole/direct + 4 dependent captures + 5 expected rejects)"
echo "Agda29DependentWord64Capture PASS (whole/direct + 4 captures + 2 explicit + 6 expected rejects)"
echo "Agda29DependentCharCapture PASS (whole/direct + 4 captures + explicit + 5 expected rejects)"
echo "Agda29DependentIntCapture PASS (whole/direct + 4 captures + explicit + 5 expected rejects)"
echo "Agda29DependentGroundChainCapture PASS (whole/direct + 8 dependent captures + 8 expected rejects)"
echo "Agda29DependentGroundProxy PASS (create + consume twice + derive + retain/recursive-GC + 6 expected rejects; root $dependent_chain_proxy_bytes bytes, child $dependent_chain_child_proxy_bytes bytes)"
echo "Agda29ExplicitGroundCall PASS (ordered + dependent + proxy/consume/drop + 5 expected rejects; proxy $dependent_chain_explicit_proxy_bytes bytes)"
echo "Agda29MultiHolePacket PASS (two typed packets + whole-entry reference)"
echo "Agda29MultiHoleBridge PASS (two IDs + batch + typed Bool call + 13 expected rejects)"
echo "Agda29NatCallableBridge PASS (typed Nat call: $nat_called + 4 expected rejects)"
echo "Agda29TypedProxy PASS (create + consume twice + derive + retain/recursive-GC + 6 expected rejects; root $nat_proxy_bytes bytes, child $nat_child_proxy_bytes bytes)"
echo "Agda29Word64CallableBridge PASS (whole/direct + zero/max + proxy/consume/drop + 5 expected rejects; proxy $word64_callable_proxy_bytes bytes)"
echo "Agda29TypedCarrier PASS (whole/direct + residual/record/data map + ground observation + 5 expected rejects; packets $typed_carrier_root_bytes/$typed_carrier_payload_bytes/$typed_carrier_wrapped_bytes bytes)"
echo "Agda29ProxyStoreQuota PASS (byte rejection + concurrent count 1/2 + released-capacity reuse; proxy $typed_carrier_quota_reused_bytes bytes; 2 expected rejects)"
echo "Agda29ProxyStateTransaction PASS (stale-lock recovery + publish/GC + atomic-state recovery + locked consume + concurrent drop 1/2; 1 expected reject)"
echo "Agda29DependencySlice PASS (checked type/body closure $dependency_slice_resolved resolved/$dependency_slice_expanded expanded + 1 presentation-only exclusion + 1 expected reject)"
echo "Agda29CoreAbi PASS (record/data/function/primitive = 42 + 2 expected rejects)"
echo "Agda29PacketModuleMismatch EXPECTED-REJECT (module identity)"
echo "Agda29PacketHashMismatch EXPECTED-REJECT (interface identity)"
echo "Agda29PacketWrongConsumer EXPECTED-REJECT (UnequalTypes)"
echo "Agda29PacketTruncated EXPECTED-REJECT (controlled diagnostic)"
echo "Agda29PacketOversized EXPECTED-REJECT (64 MiB limit)"
echo "Agda29PacketBadMagic EXPECTED-REJECT (producer self-check)"
echo "Agda29PacketBadVersion EXPECTED-REJECT (producer self-check)"
echo "Agda29PacketOpenTerm EXPECTED-REJECT (closedness gate)"
echo "Agda29PacketUnresolvedMeta EXPECTED-REJECT (meta gate)"
echo "Agda29PacketDependencyMismatch EXPECTED-REJECT (dependency inventory gate)"
echo "Agda29PacketPresentationDependencyLeak EXPECTED-REJECT (executable slice gate)"
echo "Agda29CoreAbiMismatch EXPECTED-REJECT (producer self-check)"
echo "Agda29CoreAbiPrimitiveDrift EXPECTED-REJECT (v1 inventory self-check)"
