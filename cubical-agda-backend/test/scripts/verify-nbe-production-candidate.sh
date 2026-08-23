#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$backend_dir/test/fixtures/agda/StaticOrdinary.agda"
unsupported_fixture="$backend_dir/test/fixtures/agda/NbeAdapterSpikeUnsupported.agda"
selected_lock="$backend_dir/test/fixtures/nbe-adapter-lock/selected-valid.tsv"
unselected_lock="$backend_dir/config/nbe-adapter.lock.tsv"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/nbe-production-candidate"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\tlinked\tselected\texpectation\tstatus\n' > "$summary"

build_variant() {
  label=$1
  shift
  object_dir="$evidence_dir/ghc-$label"
  variant_binary="$evidence_dir/cubical-chez-$label"
  mkdir -p "$object_dir"
  "$ghc" -O0 -Wall -Werror -dynamic "$@" \
    -package-db "$agda_package_db" -package Agda \
    -i"$backend_dir/src" \
    -outputdir "$object_dir" \
    -o "$variant_binary" \
    "$backend_dir/src/Main.hs" \
    > "$evidence_dir/build-$label.stdout" \
    2> "$evidence_dir/build-$label.stderr"
}

build_variant linked-only -DCUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE
linked_only_binary=$variant_binary
build_variant selected-only -DCUBICAL_CHEZ_NBE_PROVIDER_SELECTED
selected_only_binary=$variant_binary

# The checked-in unselected lock must fail before a candidate can be built.
unselected_binary="$evidence_dir/cubical-chez-unselected-lock"
rm -f "$unselected_binary"
set +e
make -C "$backend_dir" build-nbe-production-candidate \
  AGDA_PREFIX="$agda_prefix" \
  AGDA_PACKAGE_DB="$agda_package_db" \
  GHC="$ghc" \
  NBE_ADAPTER_LOCK="$unselected_lock" \
  NBE_CANDIDATE_BINARY="$unselected_binary" \
  NBE_CANDIDATE_OBJECT_DIR="$evidence_dir/ghc-unselected-lock" \
  > "$evidence_dir/build-unselected-lock.stdout" \
  2> "$evidence_dir/build-unselected-lock.stderr"
unselected_status=$?
set -e
if [ "$unselected_status" -eq 0 ] || [ -e "$unselected_binary" ] || \
   ! grep -q 'requires a selected adapter lock' \
     "$evidence_dir/build-unselected-lock.stderr"
then
  echo "unselected lock did not stop the production candidate build" >&2
  exit 1
fi
printf 'unselected-lock\tno\tno\tbuild-rejected\tEXPECTED-REJECT\n' \
  >> "$summary"

# A schema-valid selected lock for another provider must not authorize this
# adapter candidate.
mismatched_lock="$evidence_dir/selected-provider-mismatch.tsv"
sed 's/^provider\tagda-specific-in-process-v1$/provider\tdifferent-provider/' \
  "$selected_lock" > "$mismatched_lock"
mismatched_binary="$evidence_dir/cubical-chez-selected-provider-mismatch"
rm -f "$mismatched_binary"
set +e
make -C "$backend_dir" build-nbe-production-candidate \
  AGDA_PREFIX="$agda_prefix" \
  AGDA_PACKAGE_DB="$agda_package_db" \
  GHC="$ghc" \
  NBE_ADAPTER_LOCK="$mismatched_lock" \
  NBE_CANDIDATE_BINARY="$mismatched_binary" \
  NBE_CANDIDATE_OBJECT_DIR="$evidence_dir/ghc-selected-provider-mismatch" \
  > "$evidence_dir/build-selected-provider-mismatch.stdout" \
  2> "$evidence_dir/build-selected-provider-mismatch.stderr"
mismatched_status=$?
set -e
if [ "$mismatched_status" -eq 0 ] || [ -e "$mismatched_binary" ] || \
   ! grep -q 'does not identify the in-process production candidate' \
     "$evidence_dir/build-selected-provider-mismatch.stderr"
then
  echo "mismatched selected provider authorized the production candidate" >&2
  exit 1
fi
printf 'selected-provider-mismatch\tno\tyes\tbuild-rejected\tEXPECTED-REJECT\n' \
  >> "$summary"

# A complete selected lock is the only supported build entry for the isolated
# production candidate. The fixture is synthetic and does not alter the
# checked-in unselected production lock.
selected_linked_binary="$evidence_dir/cubical-chez-selected-linked"
make -C "$backend_dir" build-nbe-production-candidate \
  AGDA_PREFIX="$agda_prefix" \
  AGDA_PACKAGE_DB="$agda_package_db" \
  GHC="$ghc" \
  NBE_ADAPTER_LOCK="$selected_lock" \
  NBE_CANDIDATE_BINARY="$selected_linked_binary" \
  NBE_CANDIDATE_OBJECT_DIR="$evidence_dir/ghc-selected-linked" \
  > "$evidence_dir/build-selected-linked.stdout" \
  2> "$evidence_dir/build-selected-linked.stderr"

assert_no_publications() {
  output_dir=$1
  label=$2
  for artifact in program.ss treeless.txt staging.txt stage-timings.tsv \
    typed-residual.txt typed-residual.bin
  do
    if [ -e "$output_dir/$artifact" ]; then
      echo "$label: rejected invocation left $artifact" >&2
      exit 1
    fi
  done
}

run_unavailable() {
  label=$1
  runner=$2
  expected_message=$3
  case_dir="$evidence_dir/$label"
  mkdir -p "$case_dir"
  cp "$fixture" "$case_dir/StaticOrdinary.agda"
  for artifact in program.ss treeless.txt staging.txt stage-timings.tsv \
    typed-residual.txt typed-residual.bin
  do
    printf 'stale production-candidate artifact\n' > "$case_dir/$artifact"
  done
  set +e
  Agda_datadir="$agda_data_dir" "$runner" \
    --cubical-chez \
    --cubical-chez-engine=nbe \
    --cubical-chez-output="$case_dir" \
    --no-libraries \
    -i "$case_dir" \
    "$case_dir/StaticOrdinary.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  status=$?
  set -e
  if [ "$status" -eq 0 ] || \
     ! grep -q 'CCZ-NBE-UNAVAILABLE' "$case_dir/producer.stdout" || \
     ! grep -q "$expected_message" "$case_dir/producer.stdout"
  then
    echo "$label: incomplete two-key build did not fail closed" >&2
    exit 1
  fi
  assert_no_publications "$case_dir" "$label"
}

run_unavailable linked-only "$linked_only_binary" \
  'production candidate is linked but not selected'
printf 'linked-only\tyes\tno\tCCZ-NBE-UNAVAILABLE\tEXPECTED-REJECT\n' \
  >> "$summary"

run_unavailable selected-only "$selected_only_binary" \
  'selection build key is present but no adapter is linked'
printf 'selected-only\tno\tyes\tCCZ-NBE-UNAVAILABLE\tEXPECTED-REJECT\n' \
  >> "$summary"

run_success() {
  label=$1
  runner=$2
  engine=$3
  case_dir="$evidence_dir/$label"
  mkdir -p "$case_dir"
  cp "$fixture" "$case_dir/StaticOrdinary.agda"
  rm -f "$case_dir/StaticOrdinary.agdai" \
    "$case_dir/program.ss" "$case_dir/treeless.txt" \
    "$case_dir/staging.txt" "$case_dir/stage-timings.tsv"
  Agda_datadir="$agda_data_dir" "$runner" \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-output="$case_dir" \
    --no-libraries \
    -i "$case_dir" \
    "$case_dir/StaticOrdinary.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$case_dir/program.ss" > "$case_dir/observed.txt"
}

assert_stage_timings() {
  timing_file=$1
  label=$2
  expected_evaluation=$3
  expected_readback=$4
  expected_residualization=$5
  expected_codegen=$6
  if ! awk -F '\t' \
    -v evaluation="$expected_evaluation" \
    -v readback="$expected_readback" \
    -v residualization="$expected_residualization" \
    -v codegen="$expected_codegen" '
      NR == 1 {
        if ($0 != "stage\telapsed_nanoseconds\tstatus") exit 2
        next
      }
      {
        stage=$1; elapsed=$2; status=$3
        allowed = stage == "engine-total" || stage == "nbe-evaluation" ||
          stage == "nbe-readback" || stage == "engine-result-admission" ||
          stage == "internal-semantic-audit" ||
          stage == "treeless-conversion" || stage == "residualization" ||
          stage == "scheme-codegen-publication"
        if (NF != 3 || !allowed || seen[stage]++) exit 3
        if (status == "measured" && elapsed !~ /^[0-9]+$/) exit 4
        if (status == "not-applicable" && elapsed != "-") exit 5
        if (status != "measured" && status != "not-applicable") exit 6
        state[stage]=status
      }
      END {
        if (NR != 9 ||
            state["engine-total"] != "measured" ||
            state["engine-result-admission"] != "measured" ||
            state["internal-semantic-audit"] != "measured" ||
            state["treeless-conversion"] != "measured" ||
            state["nbe-evaluation"] != evaluation ||
            state["nbe-readback"] != readback ||
            state["residualization"] != residualization ||
            state["scheme-codegen-publication"] != codegen) exit 7
      }
    ' "$timing_file"
  then
    echo "$label: stage timing evidence is incomplete" >&2
    exit 1
  fi
}

run_success baseline "$default_binary" agda-baseline
run_success selected-linked "$selected_linked_binary" nbe

assert_stage_timings "$evidence_dir/baseline/stage-timings.tsv" baseline \
  not-applicable not-applicable not-applicable measured
assert_stage_timings "$evidence_dir/selected-linked/stage-timings.tsv" \
  selected-linked measured measured not-applicable measured

for artifact in observed.txt treeless.txt program.ss
do
  if ! cmp -s "$evidence_dir/baseline/$artifact" \
       "$evidence_dir/selected-linked/$artifact"
  then
    echo "selected-linked: production candidate differs from baseline in $artifact" >&2
    exit 1
  fi
done

candidate_staging="$evidence_dir/selected-linked/staging.txt"
if ! grep -Fqx 'engine-requested: nbe' "$candidate_staging" || \
   ! grep -Fqx 'engine-effective: nbe' "$candidate_staging" || \
   ! grep -Fqx 'nbe-adapter-status: production-candidate-selected' \
     "$candidate_staging" || \
   ! grep -Fqx 'nbe-adapter-production-readiness: candidate-not-accepted' \
     "$candidate_staging" || \
   ! grep -Fqx 'nbe-adapter-implementation: agda-specific-in-process-v1' \
     "$candidate_staging" || \
   ! grep -Fqx 'nbe-adapter-linkage: production-candidate' \
     "$candidate_staging" || \
   ! grep -Fqx 'nbe-provider-lock-status: selected-build-key' \
     "$candidate_staging" || \
   ! grep -Fqx 'engine-result-agda-checked: true' "$candidate_staging" || \
   [ -e "$evidence_dir/selected-linked/typed-residual.txt" ] || \
   [ -e "$evidence_dir/selected-linked/typed-residual.bin" ]
then
  echo "selected-linked: production candidate provenance is incomplete" >&2
  exit 1
fi
printf 'selected-linked\tyes\tyes\tbaseline-equal-42\tPASS\n' >> "$summary"

typed_residual_dir="$evidence_dir/selected-linked-typed-residual"
mkdir -p "$typed_residual_dir"
cp "$unsupported_fixture" \
  "$typed_residual_dir/NbeAdapterSpikeUnsupported.agda"
for artifact in program.ss treeless.txt staging.txt stage-timings.tsv \
  typed-residual.txt typed-residual.bin
do
  printf 'stale typed-residual candidate artifact\n' \
    > "$typed_residual_dir/$artifact"
done
set +e
Agda_datadir="$agda_data_dir" "$selected_linked_binary" \
  --cubical-chez \
  --cubical-chez-engine=nbe \
  --cubical-chez-nbe-fallback=typed-residual \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$typed_residual_dir" \
  --no-libraries \
  -i "$typed_residual_dir" \
  "$typed_residual_dir/NbeAdapterSpikeUnsupported.agda" \
  > "$typed_residual_dir/producer.stdout" \
  2> "$typed_residual_dir/producer.stderr"
typed_residual_status=$?
set -e
if [ "$typed_residual_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUAL-REQUIRED' \
     "$typed_residual_dir/producer.stdout" || \
   ! grep -Fqx 'engine-effective: nbe' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'nbe-fallback-policy: typed-residual' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'nbe-fallback-used: true' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'nbe-fallback-reason: nbe-unsupported-typed-residual' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx \
     'nbe-unsupported-disposition: typed-residual-passthrough-v1' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'binding-time: dynamic' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'decision: typed-residual' \
     "$typed_residual_dir/staging.txt" || \
   ! grep -Fqx 'artifact: manifest-only' \
     "$typed_residual_dir/typed-residual.txt" || \
   [ -e "$typed_residual_dir/program.ss" ] || \
   [ -e "$typed_residual_dir/typed-residual.bin" ]
then
  echo "selected-linked: typed residual passthrough is incomplete" >&2
  exit 1
fi
assert_stage_timings "$typed_residual_dir/stage-timings.tsv" \
  selected-linked-typed-residual measured not-applicable measured \
  not-applicable
printf 'selected-linked-typed-residual\tyes\tyes\tchecked-passthrough\tPASS\n' \
  >> "$summary"

if [ "$(awk -F '\t' 'NR > 1 && $5 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 2 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $5 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 4 ]
then
  echo "NbE production candidate summary is incomplete" >&2
  exit 1
fi

echo "NbE production candidate gate PASS (baseline-equal + checked typed residual; 4 identity/lock/key rejects)"
