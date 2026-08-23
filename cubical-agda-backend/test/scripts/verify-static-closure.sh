#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/static-closure"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\tclosure\terasure\texpectation\tstatus\n' > "$summary"

complete_dir="$evidence_dir/complete"
mkdir -p "$complete_dir"
cp "$fixture_dir/StaticOrdinary.agda" "$complete_dir/StaticOrdinary.agda"
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$complete_dir" \
  --no-libraries \
  -i "$complete_dir" \
  "$complete_dir/StaticOrdinary.agda" \
  > "$complete_dir/producer.stdout" \
  2> "$complete_dir/producer.stderr"

if [ "$(chez --script "$complete_dir/program.ss")" != 42 ] || \
   ! grep -Fqx 'static-closure: complete' "$complete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-reason: reachable-closure-and-lowering-verified' \
     "$complete_dir/staging.txt" || \
   ! grep -Eq '^static-closure-reachable-definitions: [1-9][0-9]*$' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-unresolved-definitions: none' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-runtime-blockers: none' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-unknown-cubical-primitives: none' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-scheme-lowering: checked' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'type-erasure-authorized: true' \
     "$complete_dir/staging.txt" || \
   ! grep -Fqx 'decision: static-closed' "$complete_dir/staging.txt"
then
  echo "static closure complete: evidence did not authorize valid erasure" >&2
  exit 1
fi
printf 'complete\tcomplete\ttrue\tPASS\tPASS\n' >> "$summary"

incomplete_dir="$evidence_dir/incomplete"
mkdir -p "$incomplete_dir"
cp "$fixture_dir/StaticUnresolved.agda" \
  "$incomplete_dir/StaticUnresolved.agda"
for stale_artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
do
  printf 'stale artifact that must not survive\n' > "$incomplete_dir/$stale_artifact"
done

set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$incomplete_dir" \
  --no-libraries \
  -i "$incomplete_dir" \
  "$incomplete_dir/StaticUnresolved.agda" \
  > "$incomplete_dir/producer.stdout" \
  2> "$incomplete_dir/producer.stderr"
incomplete_status=$?
set -e

if [ "$incomplete_status" -eq 0 ] || \
   ! grep -Fqx 'binding-time: static' "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure: incomplete' "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-reason: unresolved-definitions' \
     "$incomplete_dir/staging.txt" || \
   ! grep -q 'static-closure-unresolved-definitions: .*StaticUnresolved.opaqueNat' \
     "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-runtime-blockers: none' \
     "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-unknown-cubical-primitives: none' \
     "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'static-closure-scheme-lowering: not-run' \
     "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'type-erasure-authorized: false' \
     "$incomplete_dir/staging.txt" || \
   ! grep -Fqx 'decision: unsupported' "$incomplete_dir/staging.txt" || \
   ! grep -q 'CCZ-UNSUPPORTED' \
     "$incomplete_dir/producer.stdout" "$incomplete_dir/producer.stderr" || \
   ! grep -q 'StaticUnresolved.opaqueNat' "$incomplete_dir/treeless.txt" || \
   [ -e "$incomplete_dir/program.ss" ] || \
   [ -e "$incomplete_dir/typed-residual.txt" ] || \
   [ -e "$incomplete_dir/typed-residual.bin" ]
then
  echo "static closure incomplete: unresolved dependency did not fail closed" >&2
  exit 1
fi
printf 'unresolved\tincomplete\tfalse\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 2 ]
then
  echo "Static closure summary is incomplete" >&2
  exit 1
fi

echo "Static closure authorization PASS (complete publish, incomplete reject)"
