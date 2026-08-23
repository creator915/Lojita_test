#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/agda"
binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/primitive-audit"
summary="$evidence_dir/summary.tsv"

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

known_dir="$evidence_dir/known"
mkdir -p "$known_dir"
cp "$fixture_dir/PacketResidual.agda" "$known_dir/PacketResidual.agda"
set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=manifest \
  --cubical-chez-output="$known_dir" \
  --no-libraries \
  -i "$known_dir" \
  "$known_dir/PacketResidual.agda" \
  > "$known_dir/producer.stdout" \
  2> "$known_dir/producer.stderr"
known_status=$?
set -e

if [ "$known_status" -eq 0 ] || \
   ! grep -Fqx 'binding-time: dynamic' "$known_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-reason: whole-entry-runtime-head' \
     "$known_dir/staging.txt" || \
   ! grep -Fqx 'internal-term-semantic-catalog-status: agree' \
     "$known_dir/staging.txt" || \
   ! grep -q '^internal-term-semantic-sources: .*Agda.Primitive.Cubical.primTransp=primitive:transport' \
     "$known_dir/staging.txt" || \
   ! grep -q '^internal-term-catalog-blockers: .*Agda.Primitive.Cubical.primTransp' \
     "$known_dir/staging.txt" || \
   ! grep -Fqx 'internal-term-unknown-cubical-primitives: none' \
     "$known_dir/staging.txt" || \
   ! grep -Fqx 'treeless-unknown-cubical-primitives: none' \
     "$known_dir/staging.txt" || \
   ! grep -Fqx 'static-closure: not-applicable' \
     "$known_dir/staging.txt" || \
   ! grep -Fqx 'type-erasure-authorized: false' \
     "$known_dir/staging.txt" || \
   ! grep -q 'Agda.Primitive.Cubical.primTransp' \
     "$known_dir/typed-residual.txt" || \
   [ -e "$known_dir/program.ss" ] || \
   [ -e "$known_dir/typed-residual.bin" ]
then
  echo "known primitive: pinned primTransp classification regressed" >&2
  exit 1
fi
printf 'known-primTransp\tEXPECTED-RESIDUAL\tEXPECTED-RESIDUAL\n' \
  >> "$summary"

unknown_dir="$evidence_dir/unknown"
unknown_source_dir="$unknown_dir/Cubical/Primitive"
mkdir -p "$unknown_source_dir"
cp "$fixture_dir/Cubical/Primitive/Unknown.agda" \
  "$unknown_source_dir/Unknown.agda"

# Prove the fail-closed path removes prior publications and rejects before the
# Agda-2.9-only packet encoder can publish bytes.
for stale_artifact in program.ss treeless.txt staging.txt typed-residual.txt typed-residual.bin
do
  printf 'stale artifact that must not survive\n' > "$unknown_dir/$stale_artifact"
done

set +e
Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-residual=packet \
  --cubical-chez-output="$unknown_dir" \
  --no-libraries \
  -i "$unknown_dir" \
  "$unknown_source_dir/Unknown.agda" \
  > "$unknown_dir/producer.stdout" \
  2> "$unknown_dir/producer.stderr"
unknown_status=$?
set -e

if [ "$unknown_status" -eq 0 ] || \
   ! grep -Fqx 'binding-time: unsupported' "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-reason: unknown-cubical-primitive' \
     "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'binding-time-action: reject' "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'internal-term-semantic-catalog-status: agree' \
     "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'internal-term-semantic-sources: none' \
     "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'static-closure: not-applicable' \
     "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'type-erasure-authorized: false' \
     "$unknown_dir/staging.txt" || \
   ! grep -Fqx 'decision: unsupported' "$unknown_dir/staging.txt" || \
   ! grep -q 'internal-term-unknown-cubical-primitives: .*Cubical.Primitive.Unknown.primFuture' \
     "$unknown_dir/staging.txt" || \
   ! grep -q 'treeless-unknown-cubical-primitives: .*Cubical.Primitive.Unknown.primFuture' \
     "$unknown_dir/staging.txt" || \
   ! grep -q 'CCZ-UNSUPPORTED' \
     "$unknown_dir/producer.stdout" "$unknown_dir/producer.stderr" || \
   [ -e "$unknown_dir/program.ss" ] || \
   [ -e "$unknown_dir/treeless.txt" ] || \
   [ -e "$unknown_dir/typed-residual.txt" ] || \
   [ -e "$unknown_dir/typed-residual.bin" ]
then
  echo "unknown primitive: executable future QName did not fail closed" >&2
  exit 1
fi
printf 'unknown-future-primitive\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"

if [ "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary")" -ne 2 ]
then
  echo "Primitive audit summary is incomplete" >&2
  exit 1
fi

echo "Cubical primitive audit PASS (known residual, unknown fail-closed)"
