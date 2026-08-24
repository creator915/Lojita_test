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

[ -x "$provider_test" ] || fail "provider test executable is missing"
[ -x "$runtime_binary" ] || fail "runtime executable is missing"
[ -s "$runtime_library" ] || fail "runtime archive is missing"
[ "$(wc -l < "$manifest" | tr -d ' ')" -eq 10 ] ||
  fail "source manifest must contain exactly ten cctt core modules"
sha256sum -c "$manifest" >/dev/null || fail "vendored cctt source hash mismatch"

awk -F '\t' '
  $1 == "status" && $2 == "linked" { status++ }
  $1 == "upstream-provider" && $2 == "cctt" { provider++ }
  $1 == "upstream-revision" && $2 == "ba16f3758a322e9be77ada1da2b93f45d500192e" { revision++ }
  $1 == "integration" && $2 == "linked-core-eval-quotation" { integration++ }
  $1 == "goal3-acceptance" && $2 == "accepted" { acceptance++ }
  END { exit !(status == 1 && provider == 1 && revision == 1 && integration == 1 && acceptance == 1) }
' "$lock" || fail "provider lock does not authorize the linked cctt core"

[ "$(sha256sum runtime/nbe/vendor/cctt/LICENSE | awk '{ print $1 }')" = \
  6d1af462b683165c1b10ed36a0d3c1e1b09f50924b30f16d85918402523210f9 ] ||
  fail "vendored MIT license hash mismatch"

[ "$($provider_test)" = 'CcttProvider PASS (9)' ] ||
  fail "one or more cctt Core eval/quotation probes failed"
ar t "$runtime_library" | grep -Fxq Cctt.o ||
  fail "runtime archive does not contain the cctt adapter object"
nm -g "$runtime_binary" | grep -Fq '_Core_eval_info' ||
  fail "runtime executable does not link cctt Core.eval"
nm -g "$runtime_binary" | grep -Fq '_Quotation_quoteUnfold_info' ||
  fail "runtime executable does not link cctt Quotation.quoteUnfold"
nm -g "$runtime_binary" | grep -Fq '_CubicalziRuntimeziNbeziCctt_providerAccepts_info' ||
  fail "runtime executable does not link the fail-closed provider boundary"

echo 'RuntimeNbeCcttProvider PASS (10 source hashes; 9 eval/quotation probes; archive+ELF symbols)'
