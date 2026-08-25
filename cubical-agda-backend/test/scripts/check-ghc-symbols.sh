#!/bin/sh
set -eu

binary=${1:?usage: check-ghc-symbols.sh BINARY SYMBOL...}
shift
[ "$#" -gt 0 ] || {
  echo "check-ghc-symbols: no symbols requested" >&2
  exit 2
}

nm_tool=${NM:-nm}
symbols=$($nm_tool -g "$binary") || {
  echo "check-ghc-symbols: nm failed for $binary" >&2
  exit 1
}

for symbol in "$@"; do
  # GHC prepends a package/unit identifier, and Mach-O adds an external-symbol
  # underscore. Match the stable GHC symbol suffix so both object formats are
  # accepted without weakening the check to an arbitrary substring.
  if ! printf '%s\n' "$symbols" | awk -v wanted="$symbol" '
      length($NF) >= length(wanted) &&
        substr($NF, length($NF) - length(wanted) + 1) == wanted { found = 1 }
      END { exit !found }
    '; then
    echo "check-ghc-symbols: missing $symbol in $binary" >&2
    exit 1
  fi
done
