#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
evidence_dir="$backend_dir/build/binding-time-contract"
default_binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\tbinding_time\texpectation\tstatus\n' > "$summary"

run_backend() {
  binary=$1
  output_dir=$2
  module=$3
  residual_policy=$4
  set +e
  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine=agda-baseline \
    --cubical-chez-residual="$residual_policy" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$output_dir" \
    "$output_dir/$module.agda" \
    > "$output_dir/producer.stdout" \
    2> "$output_dir/producer.stderr"
  backend_status=$?
  set -e
}

static_dir="$evidence_dir/static"
mkdir -p "$static_dir"
cp "$fixture_dir/StaticOrdinary.agda" "$static_dir/StaticOrdinary.agda"
run_backend "$default_binary" "$static_dir" StaticOrdinary reject
if [ "$backend_status" -ne 0 ] || \
   [ "$(chez --script "$static_dir/program.ss")" != 42 ] || \
   ! grep -Fqx 'binding-time: static' "$static_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-reason: no-runtime-blockers' "$static_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-action: erase-types-and-emit' "$static_dir/staging.txt" || \
   ! grep -Fqx 'decision: static-closed' "$static_dir/staging.txt"
then
  echo "binding static: valid closed term was misclassified" >&2
  exit 1
fi
printf 'static\tstatic\tPASS\tPASS\n' >> "$summary"

verify_residual_class() {
  label=$1
  module=$2
  expected_binding=$3
  expected_reason=$4
  expected_action=$5
  output_dir="$evidence_dir/$label"

  mkdir -p "$output_dir"
  cp "$fixture_dir/$module.agda" "$output_dir/$module.agda"
  run_backend "$default_binary" "$output_dir" "$module" manifest
  if [ "$backend_status" -eq 0 ] || \
     ! grep -Fqx "binding-time: $expected_binding" "$output_dir/staging.txt" || \
     ! grep -Fqx "binding-time-reason: $expected_reason" "$output_dir/staging.txt" || \
     ! grep -Fqx "binding-time-action: $expected_action" "$output_dir/staging.txt" || \
     ! grep -Fqx 'decision: typed-residual' "$output_dir/staging.txt" || \
     ! grep -Fqx "binding-time: $expected_binding" "$output_dir/typed-residual.txt" || \
     [ -e "$output_dir/program.ss" ] || \
     [ -e "$output_dir/typed-residual.bin" ] || \
     [ -e "$output_dir/residual-static-shell.ss" ] || \
     [ -e "$output_dir/typed-hole-ground-bridge.sh" ]
  then
    echo "binding $label: residual classification contract failed" >&2
    exit 1
  fi
  printf '%s\t%s\tEXPECTED-RESIDUAL\tEXPECTED-RESIDUAL\n' \
    "$label" "$expected_binding" >> "$summary"
}

verify_residual_class \
  dynamic \
  PacketResidual \
  dynamic \
  whole-entry-runtime-head \
  typed-residual-whole-entry
verify_residual_class \
  mixed \
  MixedResidual \
  mixed \
  static-context-around-runtime-blocker \
  typed-residual-split-shell-ground-observation-by-id-whole-entry-reference

unsupported_dir="$evidence_dir/unsupported"
unsupported_object_dir="$backend_dir/build/ghc-binding-time-unsupported"
unsupported_binary="$evidence_dir/cubical-chez-unsupported"
mkdir -p "$unsupported_dir" "$unsupported_object_dir"
cp "$fixture_dir/PacketResidual.agda" "$unsupported_dir/PacketResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_BINDING_AUDIT_DISAGREEMENT \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$unsupported_object_dir" \
  -o "$unsupported_binary" \
  "$backend_dir/src/Main.hs" \
  > "$unsupported_dir/build.stdout" \
  2> "$unsupported_dir/build.stderr"

# Packet policy makes this a safety test: an audit disagreement must reject
# before either a typed packet or an erased program can be published.
printf 'stale program\n' > "$unsupported_dir/program.ss"
printf 'stale packet\n' > "$unsupported_dir/typed-residual.bin"
printf 'stale shell\n' > "$unsupported_dir/residual-static-shell.ss"
printf 'stale bridge\n' > "$unsupported_dir/typed-hole-ground-bridge.sh"
run_backend "$unsupported_binary" "$unsupported_dir" PacketResidual packet
if [ "$backend_status" -eq 0 ] || \
   ! grep -Fqx 'binding-time: unsupported' "$unsupported_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-reason: internal-treeless-audit-disagreement' \
     "$unsupported_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-action: reject' "$unsupported_dir/staging.txt" || \
   ! grep -Fqx 'decision: unsupported' "$unsupported_dir/staging.txt" || \
   ! grep -q 'CCZ-UNSUPPORTED' \
     "$unsupported_dir/producer.stdout" "$unsupported_dir/producer.stderr" || \
   [ -e "$unsupported_dir/program.ss" ] || \
   [ -e "$unsupported_dir/typed-residual.txt" ] || \
   [ -e "$unsupported_dir/typed-residual.bin" ] || \
   [ -e "$unsupported_dir/residual-static-shell.ss" ] || \
   [ -e "$unsupported_dir/typed-hole-ground-bridge.sh" ]
then
  echo "binding unsupported: audit disagreement did not fail closed" >&2
  exit 1
fi
printf 'unsupported\tunsupported\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"

semantic_dir="$evidence_dir/semantic-catalog-disagreement"
semantic_object_dir="$backend_dir/build/ghc-binding-semantic-catalog-disagreement"
semantic_binary="$evidence_dir/cubical-chez-semantic-catalog-disagreement"
mkdir -p "$semantic_dir" "$semantic_object_dir"
cp "$fixture_dir/PacketResidual.agda" "$semantic_dir/PacketResidual.agda"
"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_INTERNAL_SEMANTIC_CATALOG_DISAGREEMENT \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$semantic_object_dir" \
  -o "$semantic_binary" \
  "$backend_dir/src/Main.hs" \
  > "$semantic_dir/build.stdout" \
  2> "$semantic_dir/build.stderr"

# A catalog spelling without Agda registry identity must not be enough to
# authorize either a typed residual or an erased publication.
printf 'stale program\n' > "$semantic_dir/program.ss"
printf 'stale packet\n' > "$semantic_dir/typed-residual.bin"
run_backend "$semantic_binary" "$semantic_dir" PacketResidual packet
if [ "$backend_status" -eq 0 ] || \
   ! grep -Fqx 'internal-term-blockers: none' "$semantic_dir/staging.txt" || \
   ! grep -q '^internal-term-catalog-blockers: .*Agda.Primitive.Cubical.primTransp' \
     "$semantic_dir/staging.txt" || \
   ! grep -q '^internal-term-semantic-catalog-disagreements: .*Agda.Primitive.Cubical.primTransp' \
     "$semantic_dir/staging.txt" || \
   ! grep -Fqx 'internal-term-semantic-catalog-status: disagree' \
     "$semantic_dir/staging.txt" || \
   ! grep -Fqx 'binding-time: unsupported' "$semantic_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-reason: internal-semantic-catalog-disagreement' \
     "$semantic_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-action: reject' "$semantic_dir/staging.txt" || \
   ! grep -Fqx 'decision: unsupported' "$semantic_dir/staging.txt" || \
   ! grep -q 'CCZ-UNSUPPORTED' \
     "$semantic_dir/producer.stdout" "$semantic_dir/producer.stderr" || \
   [ -e "$semantic_dir/program.ss" ] || \
   [ -e "$semantic_dir/typed-residual.txt" ] || \
   [ -e "$semantic_dir/typed-residual.bin" ]
then
  echo "binding semantic/catalog: spelling-only authority did not fail closed" >&2
  exit 1
fi
printf 'semantic-catalog-disagreement\tunsupported\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 5 ] || \
   [ "$(awk -F '\t' 'NR > 1 { seen[$2]++ } END { print length(seen) }' "$summary")" -ne 4 ]
then
  echo "Binding-time contract summary is incomplete" >&2
  exit 1
fi

echo "Binding-time classification PASS (static, dynamic, mixed, unsupported; semantic/catalog fail-closed)"
