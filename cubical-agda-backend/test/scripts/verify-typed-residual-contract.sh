#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/typed-residual-contract"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\tscope\tdirect_dependencies\tresolved_dependencies\texpanded_definitions\texcluded_presentation_dependencies\texpectation\tstatus\n' > "$summary"

seed_publications() {
  output_dir=$1
  for artifact in \
    program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin \
    typed-residual-hole-1.bin residual-static-shell.ss \
    typed-hole-ground-bridge.sh
  do
    printf 'stale residual-contract artifact\n' > "$output_dir/$artifact"
  done
}

run_manifest_case() {
  label=$1
  module=$2
  expected_binding=$3
  expected_dependency=$4
  expected_expanded=$5
  expected_presentation=$6
  output_dir="$evidence_dir/$label"

  mkdir -p "$output_dir"
  cp "$fixture_dir/$module.agda" "$output_dir/$module.agda"
  seed_publications "$output_dir"

  set +e
  Agda_datadir="$agda_data_dir" "$default_binary" \
    --cubical-chez \
    --cubical-chez-engine=agda-baseline \
    --cubical-chez-residual=manifest \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$output_dir" \
    "$output_dir/$module.agda" \
    > "$output_dir/producer.stdout" \
    2> "$output_dir/producer.stderr"
  producer_status=$?
  set -e

  manifest="$output_dir/typed-residual.txt"
  dependency_count=$(sed -n \
    's/^residual-direct-dependency-count: //p' "$manifest" 2>/dev/null || true)
  resolved_count=$(sed -n \
    's/^residual-resolved-dependency-count: //p' "$manifest" 2>/dev/null || true)
  expanded_count=$(sed -n \
    's/^residual-expanded-definition-count: //p' "$manifest" 2>/dev/null || true)
  excluded_presentation_count=$(sed -n \
    's/^residual-excluded-presentation-dependency-count: //p' \
    "$manifest" 2>/dev/null || true)
  if [ "$producer_status" -eq 0 ] || \
     ! grep -q 'CCZ-RESIDUAL-REQUIRED' \
       "$output_dir/producer.stdout" "$output_dir/producer.stderr" || \
     ! grep -Fqx 'residual-contract: whole-entry-same-interface-v1' "$manifest" || \
     ! grep -Fqx 'residual-scope: whole-entry' "$manifest" || \
     ! grep -Fqx 'residual-payload: internal-term+type' "$manifest" || \
     ! grep -Fqx \
       'residual-signature-identity: top-level-module+full-interface-hash' \
       "$manifest" || \
     ! grep -Fqx \
       'residual-dependency-closure: exact-consumer-interface' "$manifest" || \
     ! grep -Fqx \
       'residual-dependency-slice: checked-type+definition-body-v1' \
       "$manifest" || \
     ! grep -Fqx \
       'residual-presentation-metadata: excluded-from-executable-slice' \
       "$manifest" || \
     ! grep -Eq '^residual-direct-dependency-count: [1-9][0-9]*$' "$manifest" || \
     ! grep -q "^residual-direct-dependencies: .*$expected_dependency" "$manifest" || \
     ! grep -Fqx 'residual-closure-complete: true' "$manifest" || \
     ! grep -Eq '^residual-resolved-dependency-count: [1-9][0-9]*$' "$manifest" || \
     ! grep -q '^residual-resolved-dependencies: ' "$manifest" || \
     ! grep -Fqx 'residual-unresolved-dependencies: none' "$manifest" || \
     ! grep -Fqx 'residual-embedded-definitions: none' "$manifest" || \
     ! grep -Fqx 'residual-whole-signature-embedded: false' "$manifest" || \
     ! grep -Fqx "binding-time: $expected_binding" "$manifest" || \
     [ -e "$output_dir/program.ss" ] || \
     [ -e "$output_dir/typed-residual.bin" ] || \
     [ -e "$output_dir/typed-residual-hole-1.bin" ] || \
     [ -e "$output_dir/residual-static-shell.ss" ] || \
     [ -e "$output_dir/typed-hole-ground-bridge.sh" ]
  then
    echo "$label: typed residual manifest contract is incomplete" >&2
    exit 1
  fi
  if [ "$expected_presentation" = none ]; then
    if ! grep -Fqx \
         'residual-excluded-presentation-dependency-count: 0' "$manifest" || \
       ! grep -Fqx \
         'residual-excluded-presentation-dependencies: none' "$manifest"
    then
      echo "$label: presentation metadata unexpectedly entered the audit" >&2
      exit 1
    fi
  elif ! grep -Fqx \
         'residual-excluded-presentation-dependency-count: 1' "$manifest" || \
       ! grep -q \
         "^residual-excluded-presentation-dependencies: .*$expected_presentation" \
         "$manifest" || \
       grep '^residual-resolved-dependencies: ' "$manifest" | \
         grep -q "$expected_presentation"
  then
    echo "$label: presentation-only dependency was not precisely excluded" >&2
    exit 1
  fi
  if [ "$expected_expanded" = none ]; then
    if ! grep -Fqx 'residual-expanded-definitions: none' "$manifest"; then
      echo "$label: signature leaves were unexpectedly expanded" >&2
      exit 1
    fi
  elif ! grep -q \
    "^residual-expanded-definitions: .*$expected_expanded" "$manifest"
  then
    echo "$label: transitive definition closure was not expanded" >&2
    exit 1
  fi
  if [ "$expected_binding" = mixed ]; then
    if ! grep -Fqx 'residual-slice-plan: materialized-checked-internal' "$manifest" || \
       ! grep -Fqx 'residual-slice-static-shell: validated-not-published' "$manifest" || \
       ! grep -Fqx 'residual-slice-static-shell-artifact: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-bridge-artifact: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-import-contract: opaque-import-v1' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-hole-forcing: closed-hole-ground-observation-by-id-v1' \
         "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-typed-value-proxy: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-proxy-composition: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-open-hole-closure-conversion: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-static-shell-environment-binding: none' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-open-hole-environment-arity-limit: 64' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-typed-source: checked-internal-subterm+type' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-count: 1' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-ids: typed-hole@app-argument-1' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-1-path: app-argument-1' "$manifest" || \
       ! grep -q '^residual-slice-hole-1-blockers: .*primTransp' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-materialization: checked' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-closed: true' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-source-closed: true' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-packet-closed: true' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-environment-abi: none' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-environment-arity: 0' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-1-environment-binding-abi: none' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-meta-free: true' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-typechecked: true' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-artifact: none' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-direct-dependency-count: 4' "$manifest" || \
       ! grep -q '^residual-slice-hole-1-direct-dependencies: .*primTransp' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-1-dependency-slice: checked-type+definition-body-v1' \
         "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-1-resolved-dependency-count: 4' "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-1-excluded-presentation-dependency-count: 0' \
         "$manifest" || \
       ! grep -Fqx \
         'residual-slice-hole-1-excluded-presentation-dependencies: none' \
         "$manifest" || \
       ! grep -q '^residual-slice-hole-1-type: ' "$manifest" || \
       ! grep -q '^residual-slice-hole-1-term: ' "$manifest" || \
       ! grep -Fqx 'residual-slice-independent-artifacts: false' "$manifest" || \
       ! grep -Fqx 'residual-slice-execution: whole-entry' "$manifest"
    then
      echo "$label: mixed residual slice plan is incomplete" >&2
      exit 1
    fi
  elif ! grep -Fqx \
    'residual-slice-plan: not-applicable-whole-entry-dynamic' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-count: 0' "$manifest" || \
       ! grep -Fqx 'residual-slice-hole-ids: none' "$manifest"
  then
    echo "$label: dynamic residual should not claim a mixed slice plan" >&2
    exit 1
  fi
  printf '%s\twhole-entry\t%s\t%s\t%s\t%s\tEXPECTED-RESIDUAL\tEXPECTED-RESIDUAL\n' \
    "$label" "$dependency_count" "$resolved_count" "$expanded_count" \
    "$excluded_presentation_count" >> "$summary"
}

run_manifest_case dynamic PacketResidual dynamic primTransp none none
run_manifest_case mixed MixedResidual mixed primTransp none none
run_manifest_case \
  transitive-closure ResidualDependencyClosure mixed primTransp \
  ResidualDependencyClosure.Alias \
  ResidualDependencyClosure.presentationOnly

replay_dir="$evidence_dir/mixed-plan-replay"
mkdir -p "$replay_dir"
cp "$fixture_dir/MixedResidual.agda" "$replay_dir/MixedResidual.agda"
seed_publications "$replay_dir"
set +e
Agda_datadir="$agda_data_dir" "$default_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$replay_dir" \
  --no-libraries \
  -i "$replay_dir" \
  "$replay_dir/MixedResidual.agda" \
  > "$replay_dir/producer.stdout" \
  2> "$replay_dir/producer.stderr"
replay_status=$?
set -e
grep '^residual-slice-' "$evidence_dir/mixed/typed-residual.txt" \
  > "$replay_dir/expected-slice-plan.txt"
grep '^residual-slice-' "$replay_dir/typed-residual.txt" \
  > "$replay_dir/actual-slice-plan.txt"
if [ "$replay_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUAL-REQUIRED' \
     "$replay_dir/producer.stdout" "$replay_dir/producer.stderr" || \
   ! cmp -s \
     "$replay_dir/expected-slice-plan.txt" \
     "$replay_dir/actual-slice-plan.txt"
then
  echo "mixed-plan-replay: hole IDs or paths are not deterministic" >&2
  exit 1
fi
printf '%s\twhole-entry\t0\t0\t0\t0\tPASS\tPASS\n' \
  mixed-plan-replay >> "$summary"

mismatch_dir="$evidence_dir/dependency-inventory-mismatch"
mismatch_object_dir="$backend_dir/build/ghc-residual-contract-mismatch"
mismatch_binary="$evidence_dir/cubical-chez-dependency-mismatch"
mkdir -p "$mismatch_dir" "$mismatch_object_dir"
cp "$fixture_dir/PacketResidual.agda" "$mismatch_dir/PacketResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_DEPENDENCY_MISMATCH \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$mismatch_object_dir" \
  -o "$mismatch_binary" \
  "$backend_dir/src/Main.hs" \
  > "$mismatch_dir/build.stdout" \
  2> "$mismatch_dir/build.stderr"
seed_publications "$mismatch_dir"

set +e
Agda_datadir="$agda_data_dir" "$mismatch_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$mismatch_dir" \
  --no-libraries \
  -i "$mismatch_dir" \
  "$mismatch_dir/PacketResidual.agda" \
  > "$mismatch_dir/producer.stdout" \
  2> "$mismatch_dir/producer.stderr"
mismatch_status=$?
set -e

if [ "$mismatch_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUALIZATION-FAILED' \
     "$mismatch_dir/producer.stdout" "$mismatch_dir/producer.stderr" || \
   ! grep -q 'dependency inventory does not match' \
     "$mismatch_dir/producer.stdout" "$mismatch_dir/producer.stderr" || \
   [ -e "$mismatch_dir/program.ss" ] || \
   [ -e "$mismatch_dir/typed-residual.txt" ] || \
   [ -e "$mismatch_dir/typed-residual.bin" ] || \
   [ -e "$mismatch_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$mismatch_dir/residual-static-shell.ss" ] || \
   [ -e "$mismatch_dir/typed-hole-ground-bridge.sh" ]
then
  echo "dependency-inventory-mismatch: inconsistent evidence was published" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  dependency-inventory-mismatch >> "$summary"

unresolved_dir="$evidence_dir/unresolved-signature-dependency"
unresolved_object_dir="$backend_dir/build/ghc-residual-contract-unresolved"
unresolved_binary="$evidence_dir/cubical-chez-unresolved-dependency"
mkdir -p "$unresolved_dir" "$unresolved_object_dir"
cp "$fixture_dir/ResidualDependencyClosure.agda" \
  "$unresolved_dir/ResidualDependencyClosure.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_UNRESOLVED_DEPENDENCY \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$unresolved_object_dir" \
  -o "$unresolved_binary" \
  "$backend_dir/src/Main.hs" \
  > "$unresolved_dir/build.stdout" \
  2> "$unresolved_dir/build.stderr"
seed_publications "$unresolved_dir"

set +e
Agda_datadir="$agda_data_dir" "$unresolved_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$unresolved_dir" \
  --no-libraries \
  -i "$unresolved_dir" \
  "$unresolved_dir/ResidualDependencyClosure.agda" \
  > "$unresolved_dir/producer.stdout" \
  2> "$unresolved_dir/producer.stderr"
unresolved_status=$?
set -e

if [ "$unresolved_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUALIZATION-FAILED' \
     "$unresolved_dir/producer.stdout" "$unresolved_dir/producer.stderr" || \
   ! grep -q 'dependency is unavailable in the current signature' \
     "$unresolved_dir/producer.stdout" "$unresolved_dir/producer.stderr" || \
   [ -e "$unresolved_dir/program.ss" ] || \
   [ -e "$unresolved_dir/typed-residual.txt" ] || \
   [ -e "$unresolved_dir/typed-residual.bin" ] || \
   [ -e "$unresolved_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$unresolved_dir/residual-static-shell.ss" ] || \
   [ -e "$unresolved_dir/typed-hole-ground-bridge.sh" ]
then
  echo "unresolved-signature-dependency: incomplete closure was published" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  unresolved-signature-dependency >> "$summary"

presentation_leak_dir="$evidence_dir/presentation-dependency-leak"
presentation_leak_object_dir="$backend_dir/build/ghc-residual-presentation-leak"
presentation_leak_binary="$evidence_dir/cubical-chez-presentation-leak"
mkdir -p "$presentation_leak_dir" "$presentation_leak_object_dir"
cp "$fixture_dir/ResidualDependencyClosure.agda" \
  "$presentation_leak_dir/ResidualDependencyClosure.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_PRESENTATION_DEPENDENCY_LEAK \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$presentation_leak_object_dir" \
  -o "$presentation_leak_binary" \
  "$backend_dir/src/Main.hs" \
  > "$presentation_leak_dir/build.stdout" \
  2> "$presentation_leak_dir/build.stderr"
seed_publications "$presentation_leak_dir"

set +e
Agda_datadir="$agda_data_dir" "$presentation_leak_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$presentation_leak_dir" \
  --no-libraries \
  -i "$presentation_leak_dir" \
  "$presentation_leak_dir/ResidualDependencyClosure.agda" \
  > "$presentation_leak_dir/producer.stdout" \
  2> "$presentation_leak_dir/producer.stderr"
presentation_leak_status=$?
set -e

if [ "$presentation_leak_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUALIZATION-FAILED' \
     "$presentation_leak_dir/producer.stdout" \
     "$presentation_leak_dir/producer.stderr" || \
   ! grep -q 'dependency slice does not match' \
     "$presentation_leak_dir/producer.stdout" \
     "$presentation_leak_dir/producer.stderr" || \
   [ -e "$presentation_leak_dir/program.ss" ] || \
   [ -e "$presentation_leak_dir/typed-residual.txt" ] || \
   [ -e "$presentation_leak_dir/typed-residual.bin" ] || \
   [ -e "$presentation_leak_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$presentation_leak_dir/residual-static-shell.ss" ] || \
   [ -e "$presentation_leak_dir/typed-hole-ground-bridge.sh" ]
then
  echo "presentation-dependency-leak: broad metadata traversal was accepted" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  presentation-dependency-leak >> "$summary"

no_holes_dir="$evidence_dir/mixed-plan-no-holes"
no_holes_object_dir="$backend_dir/build/ghc-residual-slice-no-holes"
no_holes_binary="$evidence_dir/cubical-chez-slice-no-holes"
mkdir -p "$no_holes_dir" "$no_holes_object_dir"
cp "$fixture_dir/MixedResidual.agda" "$no_holes_dir/MixedResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_SLICE_NO_HOLES \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$no_holes_object_dir" \
  -o "$no_holes_binary" \
  "$backend_dir/src/Main.hs" \
  > "$no_holes_dir/build.stdout" \
  2> "$no_holes_dir/build.stderr"
seed_publications "$no_holes_dir"
set +e
Agda_datadir="$agda_data_dir" "$no_holes_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$no_holes_dir" \
  --no-libraries \
  -i "$no_holes_dir" \
  "$no_holes_dir/MixedResidual.agda" \
  > "$no_holes_dir/producer.stdout" \
  2> "$no_holes_dir/producer.stderr"
no_holes_status=$?
set -e
if [ "$no_holes_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUALIZATION-FAILED' \
     "$no_holes_dir/producer.stdout" "$no_holes_dir/producer.stderr" || \
   ! grep -q 'slice plan found no blocker-headed typed hole' \
     "$no_holes_dir/producer.stdout" "$no_holes_dir/producer.stderr" || \
   [ -e "$no_holes_dir/program.ss" ] || \
   [ -e "$no_holes_dir/typed-residual.txt" ] || \
   [ -e "$no_holes_dir/typed-residual.bin" ] || \
   [ -e "$no_holes_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$no_holes_dir/residual-static-shell.ss" ] || \
   [ -e "$no_holes_dir/typed-hole-ground-bridge.sh" ]
then
  echo "mixed-plan-no-holes: invalid slice plan was published" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  mixed-plan-no-holes >> "$summary"

no_match_dir="$evidence_dir/mixed-hole-no-typed-match"
no_match_object_dir="$backend_dir/build/ghc-residual-slice-no-typed-match"
no_match_binary="$evidence_dir/cubical-chez-slice-no-typed-match"
mkdir -p "$no_match_dir" "$no_match_object_dir"
cp "$fixture_dir/MixedResidual.agda" "$no_match_dir/MixedResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_SLICE_NO_TYPED_MATCH \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$no_match_object_dir" \
  -o "$no_match_binary" \
  "$backend_dir/src/Main.hs" \
  > "$no_match_dir/build.stdout" \
  2> "$no_match_dir/build.stderr"
seed_publications "$no_match_dir"
set +e
Agda_datadir="$agda_data_dir" "$no_match_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$no_match_dir" \
  --no-libraries \
  -i "$no_match_dir" \
  "$no_match_dir/MixedResidual.agda" \
  > "$no_match_dir/producer.stdout" \
  2> "$no_match_dir/producer.stderr"
no_match_status=$?
set -e
if [ "$no_match_status" -eq 0 ] || \
   ! grep -q 'CCZ-RESIDUALIZATION-FAILED' \
     "$no_match_dir/producer.stdout" "$no_match_dir/producer.stderr" || \
   ! grep -q 'no unique checked' \
     "$no_match_dir/producer.stdout" "$no_match_dir/producer.stderr" || \
   [ -e "$no_match_dir/program.ss" ] || \
   [ -e "$no_match_dir/typed-residual.txt" ] || \
   [ -e "$no_match_dir/typed-residual.bin" ] || \
   [ -e "$no_match_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$no_match_dir/residual-static-shell.ss" ] || \
   [ -e "$no_match_dir/typed-hole-ground-bridge.sh" ]
then
  echo "mixed-hole-no-typed-match: untyped or ambiguous hole was published" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  mixed-hole-no-typed-match >> "$summary"

shell_uncovered_dir="$evidence_dir/mixed-shell-uncovered-hole"
shell_uncovered_object_dir="$backend_dir/build/ghc-residual-shell-uncovered"
shell_uncovered_binary="$evidence_dir/cubical-chez-shell-uncovered"
mkdir -p "$shell_uncovered_dir" "$shell_uncovered_object_dir"
cp "$fixture_dir/MixedResidual.agda" "$shell_uncovered_dir/MixedResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_RESIDUAL_SHELL_UNCOVERED \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$shell_uncovered_object_dir" \
  -o "$shell_uncovered_binary" \
  "$backend_dir/src/Main.hs" \
  > "$shell_uncovered_dir/build.stdout" \
  2> "$shell_uncovered_dir/build.stderr"
seed_publications "$shell_uncovered_dir"
set +e
Agda_datadir="$agda_data_dir" "$shell_uncovered_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$shell_uncovered_dir" \
  --no-libraries \
  -i "$shell_uncovered_dir" \
  "$shell_uncovered_dir/MixedResidual.agda" \
  > "$shell_uncovered_dir/producer.stdout" \
  2> "$shell_uncovered_dir/producer.stderr"
shell_uncovered_status=$?
set -e
if [ "$shell_uncovered_status" -eq 0 ] || \
   ! grep -q 'CCZ-SCHEME-LOWERING-FAILED' \
     "$shell_uncovered_dir/producer.stdout" \
     "$shell_uncovered_dir/producer.stderr" || \
   ! grep -q 'static shell import inventory is incomplete' \
     "$shell_uncovered_dir/producer.stdout" \
     "$shell_uncovered_dir/producer.stderr" || \
   [ -e "$shell_uncovered_dir/program.ss" ] || \
   [ -e "$shell_uncovered_dir/typed-residual.txt" ] || \
   [ -e "$shell_uncovered_dir/typed-residual.bin" ] || \
   [ -e "$shell_uncovered_dir/typed-residual-hole-1.bin" ] || \
   [ -e "$shell_uncovered_dir/residual-static-shell.ss" ] || \
   [ -e "$shell_uncovered_dir/typed-hole-ground-bridge.sh" ]
then
  echo "mixed-shell-uncovered-hole: unsafe shell was published" >&2
  exit 1
fi
printf '%s\tnone\t0\t0\t0\t0\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  mixed-shell-uncovered-hole >> "$summary"

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 10 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $8 == "EXPECTED-RESIDUAL" { count++ } END { print count + 0 }' "$summary")" -ne 3 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $8 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")" -ne 6 ] || \
   [ "$(awk -F '\t' 'NR > 1 && $8 == "PASS" { count++ } END { print count + 0 }' "$summary")" -ne 1 ]
then
  echo "Typed residual contract summary is incomplete" >&2
  exit 1
fi

echo "Typed residual shell composition PASS (3 residuals, 1 replay, 6 fail-closed cases)"
