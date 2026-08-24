#!/bin/sh
set -eu

fail() {
  echo "runtime NbE toolchain FAIL: $*" >&2
  exit 1
}

resolve_command() {
  candidate=$1
  case $candidate in
    */*) [ -x "$candidate" ] && printf '%s\n' "$candidate" ;;
    *) command -v "$candidate" 2>/dev/null || true ;;
  esac
}

ghc=$(resolve_command "${RUNTIME_NBE_GHC:?set RUNTIME_NBE_GHC}")
ghc_pkg=$(resolve_command "${RUNTIME_NBE_GHC_PKG:?set RUNTIME_NBE_GHC_PKG}")
cabal=$(resolve_command "${RUNTIME_NBE_CABAL:?set RUNTIME_NBE_CABAL}")

[ -n "$ghc" ] || fail "GHC is not executable: $RUNTIME_NBE_GHC"
[ -n "$ghc_pkg" ] || fail "ghc-pkg is not executable: $RUNTIME_NBE_GHC_PKG"
[ -n "$cabal" ] || fail "Cabal is not executable: $RUNTIME_NBE_CABAL"

ghc_version=$($ghc --numeric-version 2>/dev/null) ||
  fail "cannot query GHC version"
ghc_pkg_version=$($ghc_pkg --version 2>/dev/null | awk '{ print $NF }') ||
  fail "cannot query ghc-pkg version"
[ "$ghc_version" = "$ghc_pkg_version" ] ||
  fail "GHC $ghc_version and ghc-pkg $ghc_pkg_version are from different toolchains"

# Cabal is forced to use this exact compiler by `cabal build -w`; keep that
# contract executable so PATH order cannot silently select another GHC.
case $ghc in
  /*) ;;
  *) fail "resolved GHC path is not absolute: $ghc" ;;
esac

echo "RuntimeNbeToolchain PASS (GHC/ghc-pkg $ghc_version; Cabal uses -w $ghc)"
