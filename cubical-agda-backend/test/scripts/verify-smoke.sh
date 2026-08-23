#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:-$(brew --prefix agda)}
agda_data_dir="$agda_prefix/share/agda/prim"
library_registry=${AGDA_LIBRARY_REGISTRY:-$agda_prefix/share/agda/example-libraries}
evidence_dir="$backend_dir/build/evidence"

mkdir -p "$evidence_dir"

if [ ! -x "$binary" ]; then
  echo "backend binary is missing: $binary" >&2
  exit 2
fi

run_static() {
  name=$1
  source=$2
  expected=$3
  output_dir="$evidence_dir/$name"
  test_source="$output_dir/$name.agda"
  mkdir -p "$output_dir"
  cp "$source" "$test_source"

  Agda_datadir="$agda_data_dir" "$binary" \
    --cubical-chez \
    --cubical-chez-engine=agda-baseline \
    --cubical-chez-output="$output_dir" \
    --library-file="$library_registry" \
    --no-default-libraries \
    -l cubical \
    -i "$output_dir" \
    "$test_source" \
    > "$output_dir/agda.log"

  actual=$(chez --script "$output_dir/program.ss")
  if [ "$actual" != "$expected" ]; then
    echo "$name: expected '$expected', got '$actual'" >&2
    exit 1
  fi
  if ! grep -q '^decision: static-closed$' "$output_dir/staging.txt"; then
    echo "$name: staging decision was not static-closed" >&2
    exit 1
  fi
  if ! grep -q '^binding-time: static$' "$output_dir/staging.txt"; then
    echo "$name: binding-time classification was not static" >&2
    exit 1
  fi
  if ! grep -q '^internal-term-blockers: none$' "$output_dir/staging.txt" || \
     ! grep -q '^treeless-blockers: none$' "$output_dir/staging.txt"; then
    echo "$name: a blocker survived one of the static admission audits" >&2
    exit 1
  fi
  if grep -E -q 'primTransp|primHComp|primGlue|transpX-' \
    "$output_dir/program.ss" "$output_dir/treeless.txt"; then
    echo "$name: residual Cubical primitive reached the erased path" >&2
    exit 1
  fi
  echo "$name PASS ($actual)"
}

run_static \
  StaticOrdinary \
  "$fixture_dir/StaticOrdinary.agda" \
  42

run_static \
  StaticTransport \
  "$fixture_dir/StaticTransport.agda" \
  0

type_only_dir="$evidence_dir/StaticTypeOnlyCubical"
mkdir -p "$type_only_dir"
cp "$fixture_dir/StaticTypeOnlyCubical.agda" \
  "$type_only_dir/StaticTypeOnlyCubical.agda"
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$type_only_dir" \
  --no-libraries \
  -i "$type_only_dir" \
  "$type_only_dir/StaticTypeOnlyCubical.agda" \
  > "$type_only_dir/agda.log"

if ! grep -q '^decision: static-closed$' "$type_only_dir/staging.txt" || \
   ! grep -q '^binding-time: static$' "$type_only_dir/staging.txt" || \
   ! grep -q '^internal-term-blockers: none$' "$type_only_dir/staging.txt" || \
   ! grep -q '^internal-type-blockers: .*Agda.Primitive.Cubical' \
     "$type_only_dir/staging.txt" || \
   ! grep -q '^treeless-blockers: none$' "$type_only_dir/staging.txt"; then
  echo "StaticTypeOnlyCubical: type-only Cubical reference was misclassified" >&2
  exit 1
fi
if [ ! -s "$type_only_dir/program.ss" ] || \
   [ -e "$type_only_dir/typed-residual.txt" ]; then
  echo "StaticTypeOnlyCubical: static/residual artifact separation failed" >&2
  exit 1
fi
echo "StaticTypeOnlyCubical PASS (type-only Cubical reference erased)"

residual_dir="$evidence_dir/TypedResidual"
mkdir -p "$residual_dir"
cp "$fixture_dir/TypedResidual.agda" "$residual_dir/TypedResidual.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$residual_dir" \
  --library-file="$library_registry" \
  --no-default-libraries \
  -l cubical \
  -i "$residual_dir" \
  "$residual_dir/TypedResidual.agda" \
  > "$residual_dir/agda.log" \
  2> "$residual_dir/error.log"
residual_status=$?
set -e

if [ "$residual_status" -eq 0 ]; then
  echo "TypedResidual: erased compilation unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -q '^decision: typed-residual$' "$residual_dir/staging.txt"; then
  echo "TypedResidual: staging decision was not typed-residual" >&2
  exit 1
fi
if ! grep -q 'CCZ-RESIDUAL-REQUIRED' \
  "$residual_dir/agda.log" "$residual_dir/error.log"; then
  echo "TypedResidual: rejection did not expose CCZ-RESIDUAL-REQUIRED" >&2
  exit 1
fi
if ! grep -q '^binding-time: dynamic$' "$residual_dir/staging.txt"; then
  echo "TypedResidual: binding-time classification was not dynamic" >&2
  exit 1
fi
if ! grep -q 'transpX-' "$residual_dir/typed-residual.txt"; then
  echo "TypedResidual: manifest did not preserve the blocker" >&2
  exit 1
fi
if ! grep -q '^internal-term-blockers: .*transpX-' \
  "$residual_dir/typed-residual.txt" || \
   ! grep -q '^treeless-blockers: .*transpX-' \
  "$residual_dir/typed-residual.txt"; then
  echo "TypedResidual: dual-layer audit evidence is incomplete" >&2
  exit 1
fi
if [ -e "$residual_dir/program.ss" ]; then
  echo "TypedResidual: stale Scheme program survived rejection" >&2
  exit 1
fi
echo "TypedResidual EXPECTED-REJECT (CCZ-RESIDUAL-REQUIRED)"

packet_dir="$evidence_dir/PacketRequiresAgda29"
mkdir -p "$packet_dir"
cp "$fixture_dir/TypedResidual.agda" \
  "$packet_dir/TypedResidual.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$packet_dir" \
  --library-file="$library_registry" \
  --no-default-libraries \
  -l cubical \
  -i "$packet_dir" \
  "$packet_dir/TypedResidual.agda" \
  > "$packet_dir/agda.log" \
  2> "$packet_dir/error.log"
packet_status=$?
set -e

if [ "$packet_status" -eq 0 ]; then
  echo "PacketRequiresAgda29: unsupported packet output succeeded" >&2
  exit 1
fi
if ! grep -q 'packet output requires an Agda' \
  "$packet_dir/agda.log" "$packet_dir/error.log"; then
  echo "PacketRequiresAgda29: failure did not explain the version gate" >&2
  exit 1
fi
if [ -e "$packet_dir/typed-residual.bin" ] || \
   [ -e "$packet_dir/program.ss" ]; then
  echo "PacketRequiresAgda29: unsupported output left a runtime artifact" >&2
  exit 1
fi
echo "PacketRequiresAgda29 EXPECTED-REJECT"

packet_destination_dir="$evidence_dir/PacketDestinationRequiresPolicy"
mkdir -p "$packet_destination_dir"
cp "$fixture_dir/StaticOrdinary.agda" \
  "$packet_destination_dir/StaticOrdinary.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-packet-file="$packet_destination_dir/term.bin" \
  --cubical-chez-output="$packet_destination_dir" \
  --no-libraries \
  -i "$packet_destination_dir" \
  "$packet_destination_dir/StaticOrdinary.agda" \
  > "$packet_destination_dir/agda.log" \
  2> "$packet_destination_dir/error.log"
packet_destination_status=$?
set -e

if [ "$packet_destination_status" -eq 0 ] || \
   ! grep -q 'cubical-chez-packet-file' \
     "$packet_destination_dir/agda.log" \
     "$packet_destination_dir/error.log" || \
   ! grep -q 'requires --cubical-chez-residual=packet' \
     "$packet_destination_dir/agda.log" \
     "$packet_destination_dir/error.log" || \
   [ -e "$packet_destination_dir/term.bin" ] || \
   [ -e "$packet_destination_dir/program.ss" ]
then
  echo "PacketDestinationRequiresPolicy: invalid option combination was not rejected" >&2
  exit 1
fi
echo "PacketDestinationRequiresPolicy EXPECTED-REJECT"

nbe_dir="$evidence_dir/NbeUnconfigured"
mkdir -p "$nbe_dir"
cp "$fixture_dir/StaticOrdinary.agda" "$nbe_dir/StaticOrdinary.agda"
# Prove that the early engine failure removes publications from an older run.
for stale_artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
do
  printf 'stale artifact that must not survive\n' > "$nbe_dir/$stale_artifact"
done
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=nbe \
  --cubical-chez-output="$nbe_dir" \
  --no-libraries \
  -i "$nbe_dir" \
  "$nbe_dir/StaticOrdinary.agda" \
  > "$nbe_dir/agda.log" \
  2> "$nbe_dir/error.log"
nbe_status=$?
set -e

if [ "$nbe_status" -eq 0 ]; then
  echo "NbeUnconfigured: missing adapter unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -q 'CCZ-NBE-UNAVAILABLE' \
  "$nbe_dir/agda.log" "$nbe_dir/error.log"; then
  echo "NbeUnconfigured: failure did not identify the missing adapter" >&2
  exit 1
fi
for stale_artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
do
  if [ -e "$nbe_dir/$stale_artifact" ]; then
    echo "NbeUnconfigured: stale $stale_artifact survived fail-closed rejection" >&2
    exit 1
  fi
done
echo "NbeUnconfigured EXPECTED-REJECT"

empty_entry_dir="$evidence_dir/EmptyEntry"
mkdir -p "$empty_entry_dir"
cp "$fixture_dir/StaticOrdinary.agda" \
  "$empty_entry_dir/StaticOrdinary.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-entry= \
  --cubical-chez-output="$empty_entry_dir" \
  --no-libraries \
  -i "$empty_entry_dir" \
  "$empty_entry_dir/StaticOrdinary.agda" \
  > "$empty_entry_dir/agda.log" \
  2> "$empty_entry_dir/error.log"
empty_entry_status=$?
set -e

if [ "$empty_entry_status" -eq 0 ]; then
  echo "EmptyEntry: an empty entry name unexpectedly succeeded" >&2
  exit 1
fi
if ! grep -q 'CCZ-INVALID-CONFIG' \
  "$empty_entry_dir/agda.log" "$empty_entry_dir/error.log"; then
  echo "EmptyEntry: failure did not identify the invalid entry name" >&2
  exit 1
fi
if [ -e "$empty_entry_dir/program.ss" ]; then
  echo "EmptyEntry: invalid options left an executable artifact" >&2
  exit 1
fi
echo "EmptyEntry EXPECTED-REJECT"

qualified_entry_dir="$evidence_dir/QualifiedEntryMismatch"
mkdir -p "$qualified_entry_dir"
cp "$fixture_dir/StaticOrdinary.agda" \
  "$qualified_entry_dir/StaticOrdinary.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-entry=Wrong.StaticOrdinary.main \
  --cubical-chez-output="$qualified_entry_dir" \
  --no-libraries \
  -i "$qualified_entry_dir" \
  "$qualified_entry_dir/StaticOrdinary.agda" \
  > "$qualified_entry_dir/agda.log" \
  2> "$qualified_entry_dir/error.log"
qualified_entry_status=$?
set -e

if [ "$qualified_entry_status" -eq 0 ]; then
  echo "QualifiedEntryMismatch: a suffix-only QName match succeeded" >&2
  exit 1
fi
if ! grep -q 'CCZ-ENTRY-REJECTED' \
  "$qualified_entry_dir/agda.log" "$qualified_entry_dir/error.log"; then
  echo "QualifiedEntryMismatch: failure did not identify the missing entry" >&2
  exit 1
fi
if [ -e "$qualified_entry_dir/program.ss" ]; then
  echo "QualifiedEntryMismatch: invalid entry left an executable artifact" >&2
  exit 1
fi
echo "QualifiedEntryMismatch EXPECTED-REJECT"

echo "CubicalChez smoke verification passed."
