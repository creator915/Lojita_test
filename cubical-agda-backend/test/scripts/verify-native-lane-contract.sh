#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
driver="$repo_root/bin/cubical-agda-native"
lock="$repo_root/config/native-toolchain.lock.tsv"
guide="$repo_root/docs/NATIVE_LANE.md"
fixtures="$repo_root/test/fixtures/native"

fail() {
  echo "Native lane contract FAIL: $*" >&2
  exit 1
}

require_text() {
  file=$1
  needle=$2
  grep -Fq -- "$needle" "$file" || fail "$file is missing: $needle"
}

for file in "$driver" "$lock" "$guide" \
  "$fixtures/NativeOrdinary.agda" \
  "$fixtures/NativeErasedCubical.agda" \
  "$fixtures/NativeFullCubical.agda" \
  "$fixtures/NativeTypeError.agda"
do
  [ -s "$file" ] || fail "required file is missing or empty: $file"
done

bash -n "$driver" || fail "driver is not valid Bash"

for key in format stock-agda-origin stock-agda-revision stock-agda-version \
  ghc-version ghc-project-revision
do
  count=$(awk -F '\t' -v key="$key" '$1 == key { count++ } END { print count + 0 }' "$lock")
  [ "$count" -eq 1 ] || fail "lock key must occur exactly once: $key"
done

for fact in \
  '--ghc-dont-call-ghc' \
  '--with-compiler=' \
  'MAlonzo.RTE.AgdaAny' \
  'MAlonzo Haskell changed between the audited generation and GHC build' \
  'native-lane-provenance-v1' \
  'binary-internal-runtime' \
  'rm -f -- "$output_file"'
do
  require_text "$driver" "$fact"
done

for fact in \
  '`ordinary`' \
  '`erased-cubical`' \
  '`--cubical=erased`' \
  'Full Cubical and' \
  '`TCState`' \
  '`MAlonzo.RTE.AgdaAny`' \
  'make verify-native-lane'
do
  require_text "$guide" "$fact"
done

require_text "$fixtures/NativeErasedCubical.agda" '{-# OPTIONS --cubical=erased --erasure #-}'
require_text "$fixtures/NativeFullCubical.agda" '{-# OPTIONS --cubical #-}'

echo 'Native lane contract PASS (locked provenance, two fail-closed classes, MAlonzo/GHC and binary audits)'
