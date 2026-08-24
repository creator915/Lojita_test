#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
repository_root=$(CDPATH= cd -- "$repo_root/.." && pwd)
makefile=$repo_root/Makefile
macos_workflow=$repository_root/.github/workflows/macos-clean-clone-verify.yml

fail() {
  echo "delivery aggregation FAIL: $*" >&2
  exit 1
}

verify_dependencies=$(sed -n 's/^verify:[[:space:]]*//p' "$makefile")
for target in \
  verify-native-lane \
  verify-runtime-symbol-audit-portability \
  verify-runtime-nbe \
  verify-runtime-nbe-cctt-provider \
  verify-runtime-nbe-agda-bridge \
  verify-runtime-nbe-final-malonzo \
  verify-runtime-nbe-differential \
  verify-benchmarks-guide-clean-clone; do
  printf '%s\n' "$verify_dependencies" | grep -Eq "(^|[[:space:]])$target([[:space:]]|$)" ||
    fail "make verify omits $target"
done

grep -Fq -- '-w "$(RUNTIME_NBE_GHC_RESOLVED)"' "$makefile" ||
  fail "Cabal is not pinned to the resolved runtime GHC"
grep -Fq -- '$(foreach flag,$(RUNTIME_NBE_LDFLAGS),--ghc-option="$(flag)")' "$makefile" ||
  fail "Cabal does not receive the runtime linker flags on a first build"
grep -Fq -- '-fforce-recomp -fignore-interface-pragmas' "$makefile" ||
  fail "cctt adapter does not preserve imported eval/quotation link symbols"
grep -Fq 'RUNTIME_NBE_GHC_PKG ?= $(if $(RUNTIME_NBE_GHC_RESOLVED)' "$makefile" ||
  fail "ghc-pkg is not derived from the resolved runtime GHC"

[ -s "$macos_workflow" ] || fail "macOS clean-clone workflow is missing"
for fact in \
  'runs-on: macos-15-intel' \
  'git clone --no-local' \
  'test -z "$(git -C "$RUNNER_TEMP/acceptance-clone" status --porcelain)"' \
  'make verify \' \
  'RUNTIME_NBE_CABAL="$LOCKED_CABAL"'; do
  grep -Fq "$fact" "$macos_workflow" ||
    fail "macOS clean-clone workflow is missing: $fact"
done

echo 'DeliveryAggregation PASS (native/provider/bridge/MAlonzo/differential in make verify; macOS clean clone)'
