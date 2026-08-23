#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpike.agda"
recursive_fixture="$backend_dir/test/fixtures/agda/StaticOrdinary.agda"
pi_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikePi.agda"
data_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeData.agda"
record_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeRecord.agda"
dependent_record_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeDependentRecord.agda"
universe_alias_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeUniverseAlias.agda"
primitive_nat_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikePrimitiveNat.agda"
primitive_unsupported_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikePrimitiveUnsupported.agda"
primitive_impostor_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikePrimitiveImpostor.agda"
cubical_ground_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeCubicalGround.agda"
cubical_unsupported_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeCubicalUnsupported.agda"
neutral_cofibration_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeNeutralCofibration.agda"
glue_cancellation_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeGlueCancellation.agda"
unsupported_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeUnsupported.agda"
cycle_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeCycle.agda"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/nbe-adapter-spike"
object_dir="$backend_dir/build/ghc-nbe-adapter-spike"
spike_binary="$evidence_dir/cubical-chez-nbe-adapter-spike"
low_fuel_binary="$evidence_dir/cubical-chez-nbe-adapter-low-fuel"
bad_projection_binary="$evidence_dir/cubical-chez-nbe-adapter-bad-projection"
postulated_sort_binary="$evidence_dir/cubical-chez-nbe-adapter-postulated-sort"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir" "$object_dir" "$object_dir-low-fuel" \
  "$object_dir-bad-projection" "$object_dir-postulated-sort"
printf 'case\trequested-engine\teffective-engine\texpectation\tstatus\n' > "$summary"

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$object_dir" \
  -o "$spike_binary" \
  "$backend_dir/src/Main.hs" \
  > "$evidence_dir/build.stdout" \
  2> "$evidence_dir/build.stderr"

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
  -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_LOW_FUEL \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$object_dir-low-fuel" \
  -o "$low_fuel_binary" \
  "$backend_dir/src/Main.hs" \
  > "$evidence_dir/build-low-fuel.stdout" \
  2> "$evidence_dir/build-low-fuel.stderr"

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
  -DCUBICAL_CHEZ_TEST_NBE_BAD_PROJECTION_RECEIVER \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$object_dir-bad-projection" \
  -o "$bad_projection_binary" \
  "$backend_dir/src/Main.hs" \
  > "$evidence_dir/build-bad-projection.stdout" \
  2> "$evidence_dir/build-bad-projection.stderr"

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE \
  -DCUBICAL_CHEZ_TEST_NBE_POSTULATED_SORT \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$object_dir-postulated-sort" \
  -o "$postulated_sort_binary" \
  "$backend_dir/src/Main.hs" \
  > "$evidence_dir/build-postulated-sort.stdout" \
  2> "$evidence_dir/build-postulated-sort.stderr"

run_success() {
  label=$1
  binary=$2
  engine=$3
  effective=$4
  entry=$5
  source_fixture=${6:-$fixture}
  module_file=${7:-NbeAdapterSpike.agda}
  module_name=${module_file%.agda}
  case_dir="$evidence_dir/$label"

  mkdir -p "$case_dir"
  cp "$source_fixture" "$case_dir/$module_file"
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-output="$case_dir" \
    --cubical-chez-entry="$module_name.$entry" \
    --no-libraries \
    -i "$case_dir" \
    "$case_dir/$module_file" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"

  chez --script "$case_dir/program.ss" > "$case_dir/observed.txt"
  if ! grep -q "^engine-requested: $engine\$" "$case_dir/staging.txt" || \
     ! grep -q "^engine-effective: $effective\$" "$case_dir/staging.txt" || \
     ! grep -q '^engine-result-closed: true$' "$case_dir/staging.txt" || \
     ! grep -q '^engine-result-meta-free: true$' "$case_dir/staging.txt" || \
     ! grep -q '^engine-result-agda-checked: true$' "$case_dir/staging.txt"
  then
    echo "$label: engine provenance or readback admission evidence is invalid" >&2
    exit 1
  fi
}

run_success baseline-main "$default_binary" agda-baseline agda-baseline main
run_success spike-main "$spike_binary" nbe nbe-spike-test-only main
run_success baseline-once "$default_binary" agda-baseline agda-baseline once
run_success spike-once "$spike_binary" nbe nbe-spike-test-only once
run_success baseline-recursive-nat "$default_binary" \
  agda-baseline agda-baseline main "$recursive_fixture" StaticOrdinary.agda
run_success spike-recursive-nat "$spike_binary" \
  nbe nbe-spike-test-only main "$recursive_fixture" StaticOrdinary.agda
run_success baseline-pi-universe "$default_binary" \
  agda-baseline agda-baseline main "$pi_fixture" NbeAdapterSpikePi.agda
run_success spike-pi-universe "$spike_binary" \
  nbe nbe-spike-test-only main "$pi_fixture" NbeAdapterSpikePi.agda
run_success baseline-general-data "$default_binary" \
  agda-baseline agda-baseline main "$data_fixture" NbeAdapterSpikeData.agda
run_success spike-general-data "$spike_binary" \
  nbe nbe-spike-test-only main "$data_fixture" NbeAdapterSpikeData.agda
run_success baseline-record "$default_binary" \
  agda-baseline agda-baseline main "$record_fixture" NbeAdapterSpikeRecord.agda
run_success spike-record "$spike_binary" \
  nbe nbe-spike-test-only main "$record_fixture" NbeAdapterSpikeRecord.agda
run_success baseline-dependent-record "$default_binary" \
  agda-baseline agda-baseline main \
  "$dependent_record_fixture" NbeAdapterSpikeDependentRecord.agda
run_success spike-dependent-record "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$dependent_record_fixture" NbeAdapterSpikeDependentRecord.agda
run_success baseline-universe-alias "$default_binary" \
  agda-baseline agda-baseline main \
  "$universe_alias_fixture" NbeAdapterSpikeUniverseAlias.agda
run_success spike-universe-alias "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$universe_alias_fixture" NbeAdapterSpikeUniverseAlias.agda
run_success baseline-primitive-nat "$default_binary" \
  agda-baseline agda-baseline main \
  "$primitive_nat_fixture" NbeAdapterSpikePrimitiveNat.agda
run_success spike-primitive-nat "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$primitive_nat_fixture" NbeAdapterSpikePrimitiveNat.agda
run_success baseline-cubical-ground "$default_binary" \
  agda-baseline agda-baseline main \
  "$cubical_ground_fixture" NbeAdapterSpikeCubicalGround.agda
run_success spike-cubical-ground "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$cubical_ground_fixture" NbeAdapterSpikeCubicalGround.agda
run_success baseline-neutral-cofibration "$default_binary" \
  agda-baseline agda-baseline main \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success spike-neutral-cofibration "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success baseline-constant-nat-transport "$default_binary" \
  agda-baseline agda-baseline groundZero \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success spike-constant-nat-transport "$spike_binary" \
  nbe nbe-spike-test-only groundZero \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success baseline-constant-nat-function-transport "$default_binary" \
  agda-baseline agda-baseline functionZero \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success spike-constant-nat-function-transport "$spike_binary" \
  nbe nbe-spike-test-only functionZero \
  "$neutral_cofibration_fixture" NbeAdapterSpikeNeutralCofibration.agda
run_success baseline-glue-cancellation "$default_binary" \
  agda-baseline agda-baseline main \
  "$glue_cancellation_fixture" NbeAdapterSpikeGlueCancellation.agda
run_success spike-glue-cancellation "$spike_binary" \
  nbe nbe-spike-test-only main \
  "$glue_cancellation_fixture" NbeAdapterSpikeGlueCancellation.agda

for entry in main once
do
  if ! cmp -s \
       "$evidence_dir/baseline-$entry/observed.txt" \
       "$evidence_dir/spike-$entry/observed.txt" || \
     ! cmp -s \
       "$evidence_dir/baseline-$entry/treeless.txt" \
       "$evidence_dir/spike-$entry/treeless.txt" || \
     ! cmp -s \
       "$evidence_dir/baseline-$entry/program.ss" \
       "$evidence_dir/spike-$entry/program.ss"
  then
    echo "$entry: adapter spike differs from the Agda baseline" >&2
    exit 1
  fi
done


for artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s \
       "$evidence_dir/baseline-pi-universe/$artifact" \
       "$evidence_dir/spike-pi-universe/$artifact"
  then
    echo "pi-universe: adapter spike differs from the Agda baseline in $artifact" >&2
    exit 1
  fi
done

for differential_case in \
  general-data record dependent-record universe-alias primitive-nat \
  cubical-ground neutral-cofibration constant-nat-transport \
  constant-nat-function-transport glue-cancellation
do
  for artifact in observed.txt treeless.txt program.ss
  do
    if ! cmp -s \
         "$evidence_dir/baseline-$differential_case/$artifact" \
         "$evidence_dir/spike-$differential_case/$artifact"
    then
      echo "$differential_case: adapter spike differs from the Agda baseline in $artifact" >&2
      exit 1
    fi
  done
done

for artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s \
       "$evidence_dir/baseline-recursive-nat/$artifact" \
       "$evidence_dir/spike-recursive-nat/$artifact"
  then
    echo "recursive-nat: adapter spike differs from the Agda baseline in $artifact" >&2
    exit 1
  fi
done

if ! grep -q 'Bool_2e_true)' "$evidence_dir/spike-main/observed.txt" || \
   ! grep -q 'Bool_2e_false)' "$evidence_dir/spike-once/observed.txt" || \
   ! grep -q '^nbe-adapter-status: experimental-test-only$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-adapter-profile: ordinary-closures-data-record-universe-primitive-cubical-glue-ua-hit-v36$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-term-normalizer: environment-closure-data-record+primitive+neutral-cubical-glue-ua-hit-eval-readback-v35$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-hit-pattern-policy: exact-definition-or-primitive-head+checked-subpatterns-v2$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-type-normalizer: semantic-type+sort+level+alias-eval-readback-v1$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-postulated-sort-policy: reject-v1$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-primitive-registry: agda-primitive-id-v4$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-cofibration-normalizer: endpoint+neutral-identities-v1$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-constant-family-transport: exact-builtin-nat+nat-to-nat+universe-v3$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-path-application-policy: closure+constructor+definition+primitive+comp-beta-v3$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-glue-normalizer: introduction-elimination-cancellation+canonical-ua-bidirectional+double-composition+probe-hcomp-v6$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-pi-transport-normalizer: canonical-domain+stable+semantic-constant+canonical+self-path+bidirectional-singleton+bidirectional-nested-singleton+probe-shell-identity+dependent-alias+per-layer-stable-identity+parameterized-stable-identity+metadata-constructor-stable-identity+closed-function-readback+closed-pi-type-readback+outer-parameter-indexed-pi-field+ground-payload-indexed-pi-field+fieldwise-bidirectional-bounded-sigma-spine-codomain+opaque-binder+isomorphism-proof-roundtrip-v19$' \
     "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-structured-transport-normalizer: builtin-sigma-stable-second+list-parameter-map-v1$' \
     "$evidence_dir/spike-main/staging.txt" || \
   grep -q 'agda-oracle' "$evidence_dir/spike-main/staging.txt" || \
   ! grep -q '^nbe-fuel-limit: 100000$' \
     "$evidence_dir/spike-main/staging.txt"
then
  echo "adapter spike capability/provenance evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^nbe-primitive-registry-hits: 5$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^nbe-primitives-reduced: 4$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^nbe-interval-operations-evaluated: 3$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^nbe-neutral-cofibration-simplifications: 3$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^nbe-transports-reduced: 1$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^nbe-constant-nat-transports-reduced: 1$' \
     "$evidence_dir/spike-neutral-cofibration/staging.txt" || \
   ! grep -q '^42$' \
     "$evidence_dir/spike-constant-nat-transport/observed.txt" || \
   ! grep -q '^nbe-primitive-registry-hits: 1$' \
     "$evidence_dir/spike-constant-nat-transport/staging.txt" || \
   ! grep -q '^nbe-constant-nat-transports-reduced: 1$' \
     "$evidence_dir/spike-constant-nat-transport/staging.txt" || \
   ! grep -q '^4$' \
     "$evidence_dir/spike-constant-nat-function-transport/observed.txt" || \
   ! grep -q '^nbe-transports-reduced: 1$' \
     "$evidence_dir/spike-constant-nat-function-transport/staging.txt" || \
   ! grep -q '^nbe-constant-nat-function-transports-reduced: 1$' \
     "$evidence_dir/spike-constant-nat-function-transport/staging.txt"
then
  echo "neutral cofibration/Nat transport evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^42$' "$evidence_dir/spike-glue-cancellation/observed.txt" || \
   ! grep -q '^nbe-primitive-registry-hits: 2$' \
     "$evidence_dir/spike-glue-cancellation/staging.txt" || \
   ! grep -q '^nbe-primitives-reduced: 1$' \
     "$evidence_dir/spike-glue-cancellation/staging.txt" || \
   ! grep -q '^nbe-glue-unglue-cancellations: 1$' \
     "$evidence_dir/spike-glue-cancellation/staging.txt"
then
  echo "Glue introduction/elimination cancellation evidence is incomplete" >&2
  exit 1
fi

if ! grep -Eq '^nbe-type-nodes-evaluated: ([2-9]|[1-9][0-9]+)$' \
     "$evidence_dir/spike-pi-universe/staging.txt" || \
   ! grep -Eq '^nbe-sort-nodes-evaluated: ([2-9]|[1-9][0-9]+)$' \
     "$evidence_dir/spike-pi-universe/staging.txt" || \
   ! grep -Eq '^nbe-level-nodes-evaluated: ([2-9]|[1-9][0-9]+)$' \
     "$evidence_dir/spike-pi-universe/staging.txt"
then
  echo "Pi/Universe semantic type evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^42$' "$evidence_dir/spike-recursive-nat/observed.txt" || \
   ! grep -q '^nbe-definition-cache: per-request-qname-v1$' \
     "$evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -Eq '^nbe-definition-cache-hits: ([1-9][0-9]*)$' \
     "$evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -q '^nbe-definition-cache-misses: 1$' \
     "$evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -q '^nbe-recursion-cycle-policy: ground-call-shape-v1$' \
     "$evidence_dir/spike-recursive-nat/staging.txt" || \
   ! grep -q '^nbe-maximum-call-depth: 22$' \
     "$evidence_dir/spike-recursive-nat/staging.txt"
then
  echo "recursive Nat/cache/call-depth evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^9$' "$evidence_dir/spike-general-data/observed.txt" || \
   ! grep -q '^42$' "$evidence_dir/spike-record/observed.txt" || \
   ! grep -q '^nbe-record-projections-evaluated: 1$' \
     "$evidence_dir/spike-record/staging.txt" || \
   ! grep -q '^nbe-record-projections-evaluated: 2$' \
     "$evidence_dir/spike-dependent-record/staging.txt"
then
  echo "general data/record/projection evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^nbe-definitions-reduced: 1$' \
     "$evidence_dir/spike-universe-alias/staging.txt" || \
   ! grep -q '^nbe-maximum-level-atom-count: 2$' \
     "$evidence_dir/spike-universe-alias/staging.txt" || \
   ! grep -Eq '^nbe-type-nodes-evaluated: ([1-9][0-9]+)$' \
     "$evidence_dir/spike-universe-alias/staging.txt"
then
  echo "universe-polymorphic alias evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^42$' "$evidence_dir/spike-primitive-nat/observed.txt" || \
   ! grep -q '^nbe-primitive-registry-hits: 3$' \
     "$evidence_dir/spike-primitive-nat/staging.txt" || \
   ! grep -q '^nbe-primitives-reduced: 3$' \
     "$evidence_dir/spike-primitive-nat/staging.txt"
then
  echo "exact primitive registry evidence is incomplete" >&2
  exit 1
fi

if ! grep -q '^42$' "$evidence_dir/spike-cubical-ground/observed.txt" || \
   ! grep -q '^nbe-primitive-registry-hits: 6$' \
     "$evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -q '^nbe-primitives-reduced: 6$' \
     "$evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -q '^nbe-interval-operations-evaluated: 4$' \
     "$evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -q '^nbe-transports-reduced: 1$' \
     "$evidence_dir/spike-cubical-ground/staging.txt" || \
   ! grep -q '^nbe-hcomps-reduced: 1$' \
     "$evidence_dir/spike-cubical-ground/staging.txt"
then
  echo "ground Cubical interval/transp/hcomp evidence is incomplete" >&2
  exit 1
fi

printf 'main\tnbe\tnbe-spike-test-only\tbaseline-equal-true\tPASS\n' >> "$summary"
printf 'once\tnbe\tnbe-spike-test-only\tbaseline-equal-false\tPASS\n' >> "$summary"
printf 'recursive-nat\tnbe\tnbe-spike-test-only\tbaseline-equal-42+cache\tPASS\n' >> "$summary"
printf 'pi-universe\tnbe\tnbe-spike-test-only\tbaseline-equal-semantic-type\tPASS\n' >> "$summary"
printf 'general-data\tnbe\tnbe-spike-test-only\tbaseline-equal-9\tPASS\n' >> "$summary"
printf 'record\tnbe\tnbe-spike-test-only\tbaseline-equal-42+projection\tPASS\n' >> "$summary"
printf 'dependent-record\tnbe\tnbe-spike-test-only\tbaseline-equal-neutral-type-projection\tPASS\n' >> "$summary"
printf 'universe-alias\tnbe\tnbe-spike-test-only\tbaseline-equal-level-join+alias\tPASS\n' >> "$summary"
printf 'primitive-nat\tnbe\tnbe-spike-test-only\tbaseline-equal-42+primitive-id\tPASS\n' >> "$summary"
printf 'cubical-ground\tnbe\tnbe-spike-test-only\tbaseline-equal-42+interval-transp-hcomp\tPASS\n' >> "$summary"
printf 'neutral-cofibration\tnbe\tnbe-spike-test-only\tbaseline-equal-procedure+neutral-identities\tPASS\n' >> "$summary"
printf 'constant-nat-transport\tnbe\tnbe-spike-test-only\tbaseline-equal-42+constant-nat-family\tPASS\n' >> "$summary"
printf 'constant-nat-function-transport\tnbe\tnbe-spike-test-only\tbaseline-equal-4+exact-nat-function-family\tPASS\n' >> "$summary"
printf 'glue-cancellation\tnbe\tnbe-spike-test-only\tbaseline-equal-42+glue-unglue\tPASS\n' >> "$summary"

seed_publications() {
  output_dir=$1
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    printf 'stale adapter spike artifact\n' > "$output_dir/$artifact"
  done
}

assert_no_publications() {
  output_dir=$1
  label=$2
  for artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
  do
    if [ -e "$output_dir/$artifact" ]; then
      echo "$label: rejected adapter invocation left $artifact" >&2
      exit 1
    fi
  done
}

run_reject() {
  label=$1
  binary=$2
  source_fixture=$3
  module_file=$4
  expected_code=$5
  effective=$6
  case_dir="$evidence_dir/$label"

  mkdir -p "$case_dir"
  cp "$source_fixture" "$case_dir/$module_file"
  seed_publications "$case_dir"
  set +e
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine=nbe \
    --cubical-chez-output="$case_dir" \
    --no-libraries \
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
    echo "$label: expected only $expected_code" >&2
    exit 1
  fi
  assert_no_publications "$case_dir" "$label"
  printf '%s\tnbe\t%s\t%s\tEXPECTED-REJECT\n' \
    "$label" "$effective" "$expected_code" >> "$summary"
}

run_reject \
  unsupported-postulate-application \
  "$spike_binary" \
  "$unsupported_fixture" \
  NbeAdapterSpikeUnsupported.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

run_reject \
  invalid-record-projection-receiver \
  "$bad_projection_binary" \
  "$record_fixture" \
  NbeAdapterSpikeRecord.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

if ! grep -q 'receiver is neither a record constructor' \
  "$evidence_dir/invalid-record-projection-receiver/producer.stdout"
then
  echo "invalid-record-projection-receiver: stable diagnostic is missing" >&2
  exit 1
fi

run_reject \
  postulated-sort-policy \
  "$postulated_sort_binary" \
  "$fixture" \
  NbeAdapterSpike.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

if ! grep -q 'postulated-sort-policy=reject-v1' \
  "$evidence_dir/postulated-sort-policy/producer.stdout"
then
  echo "postulated-sort-policy: stable diagnostic is missing" >&2
  exit 1
fi

run_reject \
  unsupported-primitive \
  "$spike_binary" \
  "$primitive_unsupported_fixture" \
  NbeAdapterSpikePrimitiveUnsupported.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

if ! grep -q 'node-kind=Primitive(PrimStringAppend)' \
     "$evidence_dir/unsupported-primitive/producer.stdout" || \
   ! grep -q 'qname=Agda.Builtin.String.primStringAppend' \
     "$evidence_dir/unsupported-primitive/producer.stdout" || \
   ! grep -Eq 'source-range=.*Agda/Builtin/String.agda:[0-9]' \
     "$evidence_dir/unsupported-primitive/producer.stdout"
then
  echo "unsupported-primitive: structured source diagnostic is missing" >&2
  exit 1
fi

run_reject \
  primitive-name-impostor \
  "$spike_binary" \
  "$primitive_impostor_fixture" \
  NbeAdapterSpikePrimitiveImpostor.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

if ! grep -q 'node-kind=Axiom' \
     "$evidence_dir/primitive-name-impostor/producer.stdout" || \
   ! grep -q 'qname=NbeAdapterSpikePrimitiveImpostor._+_' \
     "$evidence_dir/primitive-name-impostor/producer.stdout" || \
   ! grep -Eq 'source-range=.*NbeAdapterSpikePrimitiveImpostor.agda:[0-9]' \
     "$evidence_dir/primitive-name-impostor/producer.stdout"
then
  echo "primitive-name-impostor: structured source diagnostic is missing" >&2
  exit 1
fi

run_reject \
  unsupported-cubical-primitive \
  "$spike_binary" \
  "$cubical_unsupported_fixture" \
  NbeAdapterSpikeCubicalUnsupported.agda \
  CCZ-NBE-UNSUPPORTED \
  nbe-spike-test-only

if ! grep -q 'node-kind=Primitive(PrimFaceForall)' \
     "$evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -q 'qname=Agda.Builtin.Cubical.HCompU.primFaceForall' \
     "$evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -Eq 'source-range=.*Agda/Builtin/Cubical/HCompU.agda:[0-9]' \
     "$evidence_dir/unsupported-cubical-primitive/producer.stdout" || \
   ! grep -q 'primitive is absent from agda-primitive-id-v4' \
     "$evidence_dir/unsupported-cubical-primitive/producer.stdout"
then
  echo "unsupported-cubical-primitive: structured source diagnostic is missing" >&2
  exit 1
fi

run_reject \
  recursive-ground-cycle \
  "$spike_binary" \
  "$cycle_fixture" \
  NbeAdapterSpikeCycle.agda \
  CCZ-NBE-FAILED \
  nbe-spike-test-only

if ! grep -q 'recursive-cycle:' \
  "$evidence_dir/recursive-ground-cycle/producer.stdout" || \
   ! grep -q 'NbeAdapterSpikeCycle.loop' \
  "$evidence_dir/recursive-ground-cycle/producer.stdout"
then
  echo "recursive-ground-cycle: stable cycle diagnostic is missing" >&2
  exit 1
fi

run_reject \
  deterministic-fuel-exhaustion \
  "$low_fuel_binary" \
  "$recursive_fixture" \
  StaticOrdinary.agda \
  CCZ-ENGINE-TIMEOUT \
  nbe-spike-test-only

if ! grep -q 'fuel-exhausted: adapter spike exhausted its deterministic fuel' \
  "$evidence_dir/deterministic-fuel-exhaustion/producer.stdout"
then
  echo "deterministic-fuel-exhaustion: stable fuel diagnostic is missing" >&2
  exit 1
fi

run_reject \
  production-engine-still-unavailable \
  "$default_binary" \
  "$fixture" \
  NbeAdapterSpike.agda \
  CCZ-NBE-UNAVAILABLE \
  unavailable

if [ "$(awk -F '\t' 'NR > 1 && $5 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 14 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $5 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 9 ]
then
  echo "NbE adapter spike summary is incomplete" >&2
  exit 1
fi

echo "NbE adapter spike PASS (14 baseline-equal results, 9 fail-closed controls)"
