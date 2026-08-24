#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
installer=$repo_root/test/scripts/install-v2-runtime-overlay.sh
workspace=$(mktemp -d "${TMPDIR:-/tmp}/v2-runtime-overlay.XXXXXX")
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "v2 runtime overlay install regression FAIL: $*" >&2
  exit 1
}

printf '%s\n' 'cabal-version: 3.0' 'name: Agda' 'version: 2.9.0' \
  'library' '  exposed-modules:' \
  '      Agda.TypeChecking.Primitive.Cubical.HCompU' \
  > "$workspace/Agda.cabal"
sh "$installer" "$workspace" > "$workspace/install.log" 2>&1 ||
  fail "fresh overlay installation failed"
grep -Fq 'V2RuntimeOverlayInstall PASS' "$workspace/install.log" ||
  fail "installer did not emit PASS evidence"
cmp "$repo_root/runtime/agda-2.9/src/cubical-run/Main.hs" \
  "$workspace/src/cubical-run/Main.hs" ||
  fail "runner was not copied byte-for-byte"
cmp "$repo_root/runtime/agda-2.9/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" \
  "$workspace/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" ||
  fail "runtime module was not copied byte-for-byte"
grep -Fq '#ifdef CUBICAL_RUNTIME_NBE' \
  "$workspace/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" ||
  fail "Goal 2 overlay does not isolate the Goal 3 wire adapter"
[ "$(find "$workspace/test/CubicalRuntime" -type f | wc -l | tr -d ' ')" -eq 3 ] ||
  fail "runtime test overlay is incomplete"
[ "$(grep -Ec '^[[:space:]]+Agda\.TypeChecking\.Primitive\.Cubical\.Runtime[[:space:]]*$' \
  "$workspace/Agda.cabal")" -eq 1 ] ||
  fail "runtime module was not registered exactly once"

if sh "$installer" "$workspace" > "$workspace/duplicate.log" 2>&1; then
  fail "duplicate installation unexpectedly succeeded"
fi
grep -Fq 'refusing a duplicate overlay' "$workspace/duplicate.log" ||
  fail "duplicate-install rejection is not stable"

echo 'V2RuntimeOverlayInstallRegression PASS (fresh install and duplicate rejection)'
