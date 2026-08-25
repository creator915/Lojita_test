#!/usr/bin/env bash

set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd -P)
driver="$repo_root/bin/cubical-agda-native"
lock=${NATIVE_TOOLCHAIN_LOCK:-$repo_root/config/native-toolchain.lock.tsv}
agda=${NATIVE_AGDA:?NATIVE_AGDA is required}
agda_source=${NATIVE_AGDA_SOURCE_DIR:?NATIVE_AGDA_SOURCE_DIR is required}
agda_data_dir=${NATIVE_AGDA_DATA_DIR:?NATIVE_AGDA_DATA_DIR is required}
ghc=${NATIVE_GHC:?NATIVE_GHC is required}
fixture_dir="$repo_root/test/fixtures/native"
evidence_dir="$repo_root/build/native-lane"

fail() {
  echo "Native lane acceptance FAIL: $*" >&2
  exit 1
}

rm -rf -- "$evidence_dir"
mkdir -p "$evidence_dir/native" "$evidence_dir/baseline" \
  "$evidence_dir/source-native" "$evidence_dir/source-baseline"
cp "$fixture_dir"/*.agda "$evidence_dir/source-native/"
cp "$fixture_dir"/*.agda "$evidence_dir/source-baseline/"

native_compile() {
  local class=$1
  local module=$2
  local output=$3
  "$driver" \
    --lock "$lock" \
    --agda "$agda" \
    --agda-source "$agda_source" \
    --agda-data-dir "$agda_data_dir" \
    --ghc "$ghc" \
    --classification "$class" \
    --source "$evidence_dir/source-native/$module.agda" \
    --output "$output"
}

baseline_compile() {
  local module=$1
  local output_dir=$2
  local output=$3
  mkdir -p "$output_dir"
  Agda_datadir="$agda_data_dir" "$agda" \
    --compile \
    --compile-dir="$output_dir" \
    --no-libraries \
    --with-compiler="$ghc" \
    --ghc-flag=-o \
    --ghc-flag="$output" \
    -i "$evidence_dir/source-baseline" \
    "$evidence_dir/source-baseline/$module.agda"
}

assert_publication() {
  local binary=$1
  [[ -x $binary ]] || fail "binary is missing: $binary"
  for suffix in provenance.tsv malonzo.sha256 malonzo.tar binary-audit.txt; do
    [[ -s $binary.$suffix ]] || fail "published evidence is missing: $binary.$suffix"
  done
  grep -Fqx $'lane\tnative-malonzo-ghc' "$binary.provenance.tsv" ||
    fail "native provenance lane is missing"
  grep -Fqx $'backend\tMAlonzo' "$binary.provenance.tsv" ||
    fail "MAlonzo provenance is missing"
  grep -Fqx $'haskell-erasure-witness\tMAlonzo.RTE.AgdaAny=GHC.Any' \
    "$binary.provenance.tsv" || fail "type-erasure provenance is missing"
  grep -Fqx $'generated-runtime-blockers\tnone' "$binary.provenance.tsv" ||
    fail "generated-Haskell audit did not pass"
  grep -Fqx $'binary-internal-runtime\tnone' "$binary.provenance.tsv" ||
    fail "binary runtime audit did not pass"
  tar -tf "$binary.malonzo.tar" | grep -Eq '^MAlonzo/Code/.+\.hs$' ||
    fail "MAlonzo archive contains no generated code"
  if grep -En 'Agda\.Syntax\.Internal|Agda\.TypeChecking|TCState|CubicalChez\.Nbe|RuntimeN[Bb][Ee]|libHSAgda|primTransp|primHComp|primComp|primGlue|transpX' \
      "$binary.binary-audit.txt"; then
    fail "binary audit contains compiler/typechecker/runtime NbE identity"
  fi
}

ordinary_native="$evidence_dir/native/ordinary"
ordinary_baseline="$evidence_dir/baseline/ordinary"
native_compile ordinary NativeOrdinary "$ordinary_native" \
  >"$evidence_dir/ordinary-native.compile.stdout" \
  2>"$evidence_dir/ordinary-native.compile.stderr"
baseline_compile NativeOrdinary "$evidence_dir/baseline/ordinary-build" \
  "$ordinary_baseline" \
  >"$evidence_dir/ordinary-baseline.compile.stdout" \
  2>"$evidence_dir/ordinary-baseline.compile.stderr"
assert_publication "$ordinary_native"
"$ordinary_native" >"$evidence_dir/ordinary-native.run.stdout" 2>"$evidence_dir/ordinary-native.run.stderr"
ordinary_native_status=$?
"$ordinary_baseline" >"$evidence_dir/ordinary-baseline.run.stdout" 2>"$evidence_dir/ordinary-baseline.run.stderr"
ordinary_baseline_status=$?
[[ $ordinary_native_status -eq $ordinary_baseline_status ]] ||
  fail "ordinary native/baseline exit status differs"
cmp -s "$evidence_dir/ordinary-native.run.stdout" \
  "$evidence_dir/ordinary-baseline.run.stdout" ||
  fail "ordinary native/baseline stdout differs"
cmp -s "$evidence_dir/ordinary-native.run.stderr" \
  "$evidence_dir/ordinary-baseline.run.stderr" ||
  fail "ordinary native/baseline stderr differs"
grep -Fqx 'goal1-native-42' "$evidence_dir/ordinary-native.run.stdout" ||
  fail "ordinary native output is wrong"

erased_native="$evidence_dir/native/erased-cubical"
erased_baseline="$evidence_dir/baseline/erased-cubical"
native_compile erased-cubical NativeErasedCubical "$erased_native" \
  >"$evidence_dir/erased-native.compile.stdout" \
  2>"$evidence_dir/erased-native.compile.stderr"
baseline_compile NativeErasedCubical "$evidence_dir/baseline/erased-build" \
  "$erased_baseline" \
  >"$evidence_dir/erased-baseline.compile.stdout" \
  2>"$evidence_dir/erased-baseline.compile.stderr"
assert_publication "$erased_native"
"$erased_native" >"$evidence_dir/erased-native.run.stdout" 2>"$evidence_dir/erased-native.run.stderr"
erased_native_status=$?
"$erased_baseline" >"$evidence_dir/erased-baseline.run.stdout" 2>"$evidence_dir/erased-baseline.run.stderr"
erased_baseline_status=$?
[[ $erased_native_status -eq $erased_baseline_status ]] ||
  fail "erased-Cubical native/baseline exit status differs"
cmp -s "$evidence_dir/erased-native.run.stdout" \
  "$evidence_dir/erased-baseline.run.stdout" ||
  fail "erased-Cubical native/baseline stdout differs"
cmp -s "$evidence_dir/erased-native.run.stderr" \
  "$evidence_dir/erased-baseline.run.stderr" ||
  fail "erased-Cubical native/baseline stderr differs"
grep -Fqx 'goal1-erased-cubical-42' "$evidence_dir/erased-native.run.stdout" ||
  fail "erased-Cubical native output is wrong"

full_output="$evidence_dir/native/full-cubical-misclassified"
for artifact in "$full_output" "$full_output.provenance.tsv" \
  "$full_output.malonzo.sha256" "$full_output.malonzo.tar" \
  "$full_output.binary-audit.txt"; do
  printf 'stale\n' > "$artifact"
done
set +e
native_compile erased-cubical NativeFullCubical "$full_output" \
  >"$evidence_dir/full-negative.stdout" \
  2>"$evidence_dir/full-negative.stderr"
full_status=$?
set -e
[[ $full_status -eq 65 ]] || fail "full Cubical misclassification did not return 65"
grep -Fq 'rejects full and no-glue Cubical modes' "$evidence_dir/full-negative.stderr" ||
  fail "full Cubical rejection reason is missing"
for artifact in "$full_output" "$full_output.provenance.tsv" \
  "$full_output.malonzo.sha256" "$full_output.malonzo.tar" \
  "$full_output.binary-audit.txt"; do
  [[ ! -e $artifact ]] || fail "misclassification left stale artifact: $artifact"
done

type_error_output="$evidence_dir/native/type-error"
set +e
native_compile ordinary NativeTypeError "$type_error_output" \
  >"$evidence_dir/type-error-native.stdout" \
  2>"$evidence_dir/type-error-native.stderr"
native_error_status=$?
Agda_datadir="$agda_data_dir" "$agda" \
  --compile --ghc-dont-call-ghc \
  --compile-dir="$evidence_dir/baseline/type-error-build" \
  --no-libraries -i "$evidence_dir/source-native" \
  "$evidence_dir/source-native/NativeTypeError.agda" \
  >"$evidence_dir/type-error-baseline.stdout" \
  2>"$evidence_dir/type-error-baseline.stderr"
baseline_error_status=$?
set -e
[[ $native_error_status -eq $baseline_error_status ]] ||
  fail "type-error native/baseline exit status differs ($native_error_status != $baseline_error_status)"
cmp -s "$evidence_dir/type-error-native.stdout" \
  "$evidence_dir/type-error-baseline.stdout" ||
  fail "type-error native/baseline stdout differs"
cmp -s "$evidence_dir/type-error-native.stderr" \
  "$evidence_dir/type-error-baseline.stderr" ||
  fail "type-error native/baseline stderr differs"
[[ ! -e $type_error_output ]] || fail "type error published a binary"

{
  printf 'case\tclassification\tbaseline-equal\texpected\tstatus\n'
  printf 'ordinary\tordinary\tyes\tgoal1-native-42\tPASS\n'
  printf 'erased-cubical\terased-cubical\tyes\tgoal1-erased-cubical-42\tPASS\n'
  printf 'full-cubical-misclassification\terased-cubical\tn/a\tFAIL-CLOSED\tPASS\n'
  printf 'type-error\tordinary\tyes\tEXPECTED-REJECT\tPASS\n'
} > "$evidence_dir/summary.tsv"

echo 'Native MAlonzo/GHC lane PASS (2 compile/run + 2 fail-closed; stock differential and binary audit)'
