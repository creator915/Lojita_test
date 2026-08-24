#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

provider_test=${RUNTIME_NBE_PROVIDER_TEST:?set RUNTIME_NBE_PROVIDER_TEST}
runtime_binary=${RUNTIME_NBE_BINARY:?set RUNTIME_NBE_BINARY}
runtime_library=${RUNTIME_NBE_LIBRARY:?set RUNTIME_NBE_LIBRARY}
manifest=config/runtime-nbe-cctt-sources.sha256
lock=config/runtime-nbe-provider.lock.tsv

fail() {
  echo "linked cctt provider FAIL: $*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

[ -x "$provider_test" ] || fail "provider test executable is missing"
[ -x "$runtime_binary" ] || fail "runtime executable is missing"
[ -s "$runtime_library" ] || fail "runtime archive is missing"
if grep -Eq 'providerAccepts|probe[[:space:]]*::[[:space:]]*ProviderPrimitive' \
  runtime/nbe/src/Cubical/Runtime/Nbe/Cctt.hs; then
  fail "fixed provider probes are forbidden"
fi
for required_constructor in \
  'Coe I0 I1' \
  'HCom I0 I1' \
  'GlueTy valueType' \
  'Glue (encode input) equivalenceSystem fiberSystem'; do
  grep -Fq "$required_constructor" runtime/nbe/src/Cubical/Runtime/Nbe/Cctt.hs ||
    fail "provider does not construct cctt $required_constructor syntax"
done
if grep -Eq 'familyFunction|mapVector|selector[[:space:]]*=[[:space:]]*case face' \
  runtime/nbe/src/Cubical/Runtime/Nbe/Cctt.hs; then
  fail "provider still contains a hand-written transport/composition substitute"
fi
[ "$(wc -l < "$manifest" | tr -d ' ')" -eq 10 ] ||
  fail "source manifest must contain exactly ten cctt core modules"
while read -r expected source_path; do
  [ -n "$expected" ] || continue
  [ "$(sha256_file "$source_path")" = "$expected" ] ||
    fail "vendored cctt source hash mismatch: $source_path"
done < "$manifest"

awk -F '\t' '
  $1 == "status" && $2 == "linked" { status++ }
  $1 == "upstream-provider" && $2 == "cctt" { provider++ }
  $1 == "upstream-revision" && $2 == "ba16f3758a322e9be77ada1da2b93f45d500192e" { revision++ }
  $1 == "integration" && $2 == "linked-core-input-normalization" { integration++ }
  $1 == "cubical-semantics" && $2 == "cctt-Coe-HCom-Glue" { cubical++ }
  $1 == "data-encoding" && $2 == "bounded-Church-only" { encoding++ }
  $1 == "goal3-acceptance" && $2 == "pending-independent-review" { acceptance++ }
  END { exit !(status == 1 && provider == 1 && revision == 1 && integration == 1 && cubical == 1 && encoding == 1 && acceptance == 1) }
' "$lock" || fail "provider lock does not authorize the linked cctt core"

[ "$(sha256_file runtime/nbe/vendor/cctt/LICENSE)" = \
  6d1af462b683165c1b10ed36a0d3c1e1b09f50924b30f16d85918402523210f9 ] ||
  fail "vendored MIT license hash mismatch"

[ "$($provider_test)" = 'CcttProvider PASS (15 Coe/HCom/Glue input-driven cases)' ] ||
  fail "one or more input-driven cctt normalizations failed"
ar t "$runtime_library" | grep -Fxq Cctt.o ||
  fail "runtime archive does not contain the cctt adapter object"
if ! sh test/scripts/check-ghc-symbols.sh "$runtime_binary" \
    _Core_eval_info \
    _Quotation_quoteUnfold_info \
    _CubicalziRuntimeziNbeziCctt_providerTransport_info; then
  fail "runtime executable does not link cctt eval/quotation/provider transport"
fi

echo 'RuntimeNbeCcttProvider PASS (10 source hashes; 15 Coe/HCom/Glue normalizations; linked symbols)'
