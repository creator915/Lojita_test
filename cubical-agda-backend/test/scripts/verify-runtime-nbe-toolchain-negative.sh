#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
workspace=$(mktemp -d "${TMPDIR:-/tmp}/runtime-nbe-toolchain-negative.XXXXXX")
cleanup() { rm -rf "$workspace"; }
trap cleanup EXIT HUP INT TERM

fail() {
  echo "runtime NbE toolchain negative test FAIL: $*" >&2
  exit 1
}

printf '%s\n' '#!/bin/sh' 'echo 9.10.3' > "$workspace/ghc"
printf '%s\n' '#!/bin/sh' 'echo GHC package manager version 9.12.2' > "$workspace/ghc-pkg"
printf '%s\n' '#!/bin/sh' 'exit 0' > "$workspace/cabal"
chmod +x "$workspace/ghc" "$workspace/ghc-pkg" "$workspace/cabal"

if RUNTIME_NBE_GHC="$workspace/ghc" \
   RUNTIME_NBE_GHC_PKG="$workspace/ghc-pkg" \
   RUNTIME_NBE_CABAL="$workspace/cabal" \
   sh "$repo_root/test/scripts/verify-runtime-nbe-toolchain.sh" \
     > "$workspace/output" 2>&1; then
  fail "mixed GHC/ghc-pkg versions were accepted"
fi
grep -Fq 'are from different toolchains' "$workspace/output" ||
  fail "mixed toolchain rejection is not stable"

echo 'RuntimeNbeToolchainNegative PASS (mixed GHC/ghc-pkg rejected)'
