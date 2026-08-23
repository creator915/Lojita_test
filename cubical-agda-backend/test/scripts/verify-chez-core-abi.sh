#!/bin/sh

set -eu

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
fixture="$backend_dir/test/fixtures/agda/StaticCoreAbi.agda"
binary="$backend_dir/build/cubical-chez"
agda_prefix=${AGDA_PREFIX:?AGDA_PREFIX is required}
agda_package_db=${AGDA_PACKAGE_DB:?AGDA_PACKAGE_DB is required}
ghc=${GHC:?GHC is required}
agda_data_dir="$agda_prefix/share/agda/prim"
evidence_dir="$backend_dir/build/chez-core-abi"
positive_dir="$evidence_dir/positive"
negative_dir="$evidence_dir/declared-implementation-mismatch"
negative_binary="$evidence_dir/cubical-chez-abi-mismatch"
primitive_negative_dir="$evidence_dir/primitive-map-drift"
primitive_negative_binary="$evidence_dir/cubical-chez-primitive-drift"
summary="$evidence_dir/summary.tsv"

mkdir -p "$positive_dir" "$negative_dir" "$primitive_negative_dir" \
  "$evidence_dir/ghc-mismatch" "$evidence_dir/ghc-primitive-drift"
cp "$fixture" "$positive_dir/StaticCoreAbi.agda"

Agda_datadir="$agda_data_dir" "$binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$positive_dir" \
  --no-libraries \
  -i "$positive_dir" \
  "$positive_dir/StaticCoreAbi.agda" \
  > "$positive_dir/producer.stdout" \
  2> "$positive_dir/producer.stderr"

manifest="$positive_dir/staging.txt"
program="$positive_dir/program.ss"
if ! grep -Fqx 'chez-core-abi: chez-core-abi-v1' "$manifest" || \
   ! grep -Fqx \
     'chez-qname-abi: agda-prefix+non-alphanumeric-codepoint-hex-v1' \
     "$manifest" || \
   ! grep -Fqx 'chez-function-abi: unary-curried-closure-v1' "$manifest" || \
   ! grep -Fqx 'chez-data-constructor-abi: tagged-vector-v1' "$manifest" || \
   ! grep -Fqx 'chez-record-abi: tagged-vector-v1' "$manifest" || \
   ! grep -Fqx 'chez-constructor-tag-index: 0' "$manifest" || \
   ! grep -Fqx 'chez-constructor-field-base-index: 1' "$manifest" || \
   ! grep -Fqx \
     'chez-primitive-application-abi: exact-arity-whitelist-v1' "$manifest" || \
   ! grep -Fqx \
     'chez-primitive-application-map: PAdd/2=+,PAdd64/2=+,PSub/2=-,PSub64/2=-,PMul/2=*,PMul64/2=*,PQuot/2=quotient,PQuot64/2=quotient,PRem/2=remainder,PRem64/2=remainder,PGeq/2=>=,PLt/2=<,PLt64/2=<,PEqI/2==,PEq64/2==,PEqF/2==,PEqS/2=string=?,PEqC/2=char=?,PIf/3=if,PSeq/2=begin,PITo64/1=identity,P64ToI/1=identity' \
     "$manifest" || \
   ! grep -Fqx \
     'chez-primitive-first-class-abi: curried-add-sub-mul-v1' "$manifest" || \
   ! grep -Fqx \
     'chez-primitive-first-class-map: PAdd=curried:+,PSub=curried:-,PMul=curried:*' \
     "$manifest"
then
  echo "Chez core ABI: versioned staging contract is incomplete" >&2
  exit 1
fi

if ! grep -Fq '; Chez core ABI: chez-core-abi-v1.' "$program" || \
   ! grep -Fq '(lambda (v0) (lambda (v1)' "$program" || \
   ! grep -Fq '(case (vector-ref v1 0)' "$program" || \
   ! grep -Fq '(vector-ref v1 1)' "$program" || \
   ! grep -Fq '(vector-ref field2_0 0)' "$program" || \
   ! grep -Fq '(vector-ref field2_0 1)' "$program" || \
   ! grep -Fq \
     "(vector 'agda_StaticCoreAbi_2e_Choice_2e_picked" "$program" || \
   ! grep -Fq "(vector 'agda_StaticCoreAbi_2e_box" "$program" || \
   ! grep -Fq '(v0 (+ 2 field3_0))' "$program"
then
  echo "Chez core ABI: generated function/data/record/primitive layout drifted" >&2
  exit 1
fi

cp "$program" "$positive_dir/runner.ss"
printf '%s\n' \
  "(display ((agda_StaticCoreAbi_2e_main (lambda (x) (* x 2))) (vector 'agda_StaticCoreAbi_2e_Choice_2e_picked (vector 'agda_StaticCoreAbi_2e_box 19))))" \
  '(newline)' \
  >> "$positive_dir/runner.ss"
actual=$(chez --script "$positive_dir/runner.ss" | tail -n 1)
expected='#(agda_StaticCoreAbi_2e_Choice_2e_picked #(agda_StaticCoreAbi_2e_box 42))'
if [ "$actual" != "$expected" ]; then
  echo "Chez core ABI: expected '$expected', got '$actual'" >&2
  exit 1
fi

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_CORE_ABI_MISMATCH \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$evidence_dir/ghc-mismatch" \
  -o "$negative_binary" \
  "$backend_dir/src/Main.hs"

cp "$fixture" "$negative_dir/StaticCoreAbi.agda"
printf 'stale executable that must not survive\n' > "$negative_dir/program.ss"
set +e
Agda_datadir="$agda_data_dir" "$negative_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$negative_dir" \
  --no-libraries \
  -i "$negative_dir" \
  "$negative_dir/StaticCoreAbi.agda" \
  > "$negative_dir/producer.stdout" \
  2> "$negative_dir/producer.stderr"
negative_status=$?
set -e

if [ "$negative_status" -eq 0 ] || \
   ! grep -q 'CCZ-SCHEME-LOWERING-FAILED' \
     "$negative_dir/producer.stdout" "$negative_dir/producer.stderr" || \
   ! grep -q 'declared Chez core ABI does not match' \
     "$negative_dir/producer.stdout" "$negative_dir/producer.stderr" || \
   ! grep -Fqx 'static-closure-reason: scheme-lowering-rejected' \
     "$negative_dir/staging.txt" || \
   [ -e "$negative_dir/program.ss" ]
then
  echo "Chez core ABI: declared/implemented mismatch did not fail closed" >&2
  exit 1
fi

"$ghc" -O0 -Wall -Werror -dynamic \
  -DCUBICAL_CHEZ_TEST_CORE_ABI_PRIMITIVE_DRIFT \
  -package-db "$agda_package_db" -package Agda \
  -i"$backend_dir/src" \
  -outputdir "$evidence_dir/ghc-primitive-drift" \
  -o "$primitive_negative_binary" \
  "$backend_dir/src/Main.hs"

cp "$fixture" "$primitive_negative_dir/StaticCoreAbi.agda"
printf 'stale executable that must not survive\n' \
  > "$primitive_negative_dir/program.ss"
set +e
Agda_datadir="$agda_data_dir" "$primitive_negative_binary" \
  --cubical-chez \
  --cubical-chez-engine=agda-baseline \
  --cubical-chez-output="$primitive_negative_dir" \
  --no-libraries \
  -i "$primitive_negative_dir" \
  "$primitive_negative_dir/StaticCoreAbi.agda" \
  > "$primitive_negative_dir/producer.stdout" \
  2> "$primitive_negative_dir/producer.stderr"
primitive_negative_status=$?
set -e

if [ "$primitive_negative_status" -eq 0 ] || \
   ! grep -q 'CCZ-SCHEME-LOWERING-FAILED' \
     "$primitive_negative_dir/producer.stdout" \
     "$primitive_negative_dir/producer.stderr" || \
   ! grep -q 'primitive application map changed' \
     "$primitive_negative_dir/producer.stdout" \
     "$primitive_negative_dir/producer.stderr" || \
   [ -e "$primitive_negative_dir/program.ss" ]
then
  echo "Chez core ABI: primitive map drift did not fail closed" >&2
  exit 1
fi

printf 'case\tabi\tchez-result\texpectation\tstatus\n' > "$summary"
printf 'record-data-function-primitive\tchez-core-abi-v1\t42\tPASS\tPASS\n' \
  >> "$summary"
printf 'declared-implementation-mismatch\tuncurried-closure-v0\tnone\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"
printf 'primitive-map-drift\tPAdd-to-subtract\tnone\tEXPECTED-REJECT\tEXPECTED-REJECT\n' \
  >> "$summary"

echo "Chez core ABI PASS (record/data/function/primitive + 2 mismatch rejects)"
