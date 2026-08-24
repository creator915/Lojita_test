#!/bin/sh
set -eu

target=${1:?usage: install-v2-runtime-overlay.sh AGDA_SOURCE_DIR}
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
overlay=$repo_root/runtime/agda-2.9

fail() {
  echo "v2 runtime overlay install FAIL: $*" >&2
  exit 1
}

[ -f "$target/Agda.cabal" ] || fail "Agda.cabal is missing below $target"
if grep -Eq '^[[:space:]]*executable[[:space:]]+agda-cubical-run[[:space:]]*$' \
    "$target/Agda.cabal"; then
  fail "agda-cubical-run is already present; refusing a duplicate overlay"
fi
if grep -Eq '^[[:space:]]+Agda\.TypeChecking\.Primitive\.Cubical\.Runtime[[:space:]]*$' \
    "$target/Agda.cabal"; then
  fail "Cubical.Runtime is already registered; refusing a duplicate overlay"
fi

mkdir -p \
  "$target/src/full/Agda/TypeChecking/Primitive/Cubical" \
  "$target/src/cubical-run" \
  "$target/test/CubicalRuntime"
cp "$overlay/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" \
  "$target/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs"
cp "$overlay/src/cubical-run/Main.hs" "$target/src/cubical-run/Main.hs"
cp "$overlay/test/CubicalRuntime/RuntimeTransp.agda" \
  "$overlay/test/CubicalRuntime/run-tests.sh" \
  "$overlay/test/CubicalRuntime/run-transport-tests-v2.sh" \
  "$target/test/CubicalRuntime/"

cabal_with_runtime=$target/Agda.cabal.v2-runtime
awk '
  /^[[:space:]]+Agda\.TypeChecking\.Primitive\.Cubical\.HCompU[[:space:]]*$/ {
    print
    print "      Agda.TypeChecking.Primitive.Cubical.Runtime"
    inserted++
    next
  }
  { print }
  END { if (inserted != 1) exit 42 }
' "$target/Agda.cabal" > "$cabal_with_runtime" || {
  rm -f "$cabal_with_runtime"
  fail "could not register Cubical.Runtime in the Agda library module list"
}
mv "$cabal_with_runtime" "$target/Agda.cabal"
printf '\n' >> "$target/Agda.cabal"
cat "$overlay/agda-cubical-run.cabal.fragment" >> "$target/Agda.cabal"

cmp "$overlay/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" \
  "$target/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" ||
  fail "installed Runtime.hs differs from the maintained overlay"
cmp "$overlay/src/cubical-run/Main.hs" "$target/src/cubical-run/Main.hs" ||
  fail "installed runner differs from the maintained overlay"
[ "$(grep -Ec '^[[:space:]]*executable[[:space:]]+agda-cubical-run[[:space:]]*$' \
  "$target/Agda.cabal")" -eq 1 ] ||
  fail "Agda.cabal does not contain exactly one v2 runner stanza"
[ "$(grep -Ec '^[[:space:]]+Agda\.TypeChecking\.Primitive\.Cubical\.Runtime[[:space:]]*$' \
  "$target/Agda.cabal")" -eq 1 ] ||
  fail "Agda.cabal does not register exactly one v2 runtime module"

echo "V2RuntimeOverlayInstall PASS ($target)"
