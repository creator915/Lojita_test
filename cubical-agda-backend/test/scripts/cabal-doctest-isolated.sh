#!/bin/sh

set -eu

: "${CABAL_DOCTEST_REAL:?Set CABAL_DOCTEST_REAL to the real cabal executable}"
: "${CABAL_DOCTEST_GHC:?Set CABAL_DOCTEST_GHC to the locked GHC executable}"
: "${CABAL_DOCTEST_BIN_DIR:?Set CABAL_DOCTEST_BIN_DIR to the isolated executable directory}"
: "${CABAL_DOCTEST_INSTALL_STORE:?Set CABAL_DOCTEST_INSTALL_STORE to the isolated install store}"
: "${CABAL_DOCTEST_INSTALL_DIST:?Set CABAL_DOCTEST_INSTALL_DIST to the isolated install build directory}"
: "${CABAL_DOCTEST_PROJECT_DIST:?Set CABAL_DOCTEST_PROJECT_DIST to the isolated project build directory}"
: "${CABAL_DOCTEST_VERSION_FILE:?Set CABAL_DOCTEST_VERSION_FILE to the version evidence path}"
CABAL_DOCTEST_DISABLE_OPTIMIZATION=${CABAL_DOCTEST_DISABLE_OPTIMIZATION:-0}

command_name=${1:-}
case "$command_name" in
  install)
    shift
    mkdir -p "$CABAL_DOCTEST_BIN_DIR" "$CABAL_DOCTEST_INSTALL_STORE" \
      "$CABAL_DOCTEST_INSTALL_DIST"
    "$CABAL_DOCTEST_REAL" \
      --store-dir="$CABAL_DOCTEST_INSTALL_STORE" \
      install \
      --builddir="$CABAL_DOCTEST_INSTALL_DIST" \
      -w "$CABAL_DOCTEST_GHC" \
      --installdir="$CABAL_DOCTEST_BIN_DIR" \
      --install-method=copy \
      --overwrite-policy=always \
      "$@"
    "$CABAL_DOCTEST_BIN_DIR/doctest" --version \
      > "$CABAL_DOCTEST_VERSION_FILE"
    ;;
  repl)
    shift
    if [ "$CABAL_DOCTEST_DISABLE_OPTIMIZATION" -eq 1 ]; then
      exec "$CABAL_DOCTEST_REAL" repl \
        --disable-optimization \
        --builddir="$CABAL_DOCTEST_PROJECT_DIST" \
        --repl-options=-Wwarn \
        "$@"
    fi
    exec "$CABAL_DOCTEST_REAL" repl \
      --builddir="$CABAL_DOCTEST_PROJECT_DIST" \
      "$@"
    ;;
  *)
    exec "$CABAL_DOCTEST_REAL" "$@"
    ;;
esac
