#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/transport"
evidence_dir="$backend_dir/build/agda29/transport-shards"
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
transport_source_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_dir=${CUBICAL29_DIR:-"$(dirname -- "$agda_source_dir")/cubical-upstream"}
cubical_dir=$(CDPATH= cd -- "$cubical_dir" && pwd -P)
ghc29=${GHC29:-ghc}

if [ ! -f "$agda_source_dir/Agda.cabal" ]; then
  echo "Agda.cabal not found below AGDA29_SOURCE_DIR: $agda_source_dir" >&2
  exit 2
fi

if [ ! -f "$cubical_dir/cubical.agda-lib" ]; then
  echo "cubical.agda-lib not found below CUBICAL29_DIR: $cubical_dir" >&2
  exit 2
fi

if [ ! -f "$transport_source" ]; then
  echo "Original transport source is missing: $transport_source" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_source_sha256" ]; then
  echo "Original transport source SHA-256 mismatch: $actual_transport_sha256" >&2
  exit 2
fi

if [ -n "${AGDA29_BIN:-}" ]; then
  agda_bin=$AGDA29_BIN
else
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda)
  if [ ! -x "$agda_bin" ]; then
    echo "Building the pinned stock Agda executable..."
    (CDPATH= cd -- "$agda_source_dir" && cabal build -w "$ghc29" exe:agda)
    agda_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda)
  fi
fi

if [ ! -x "$agda_bin" ]; then
  echo "Agda 2.9 executable is not available: $agda_bin" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
library_file=$(mktemp)
workspace_dir=$(mktemp -d "$evidence_dir/workspace.XXXXXX")
workspace_cubical_dir="$workspace_dir/cubical"
workspace_fixture_dir="$workspace_dir/fixtures"
cleanup() {
  rm -f "$library_file"
  rm -rf "$workspace_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_cubical_dir" "$workspace_fixture_dir"
if ! cp -cR "$cubical_dir/." "$workspace_cubical_dir" 2>/dev/null; then
  cp -R "$cubical_dir/." "$workspace_cubical_dir"
fi
cp "$fixture_dir"/*.agda "$workspace_fixture_dir"
cp "$transport_source" "$workspace_fixture_dir/TransportTests.agda"
printf '%s\n' "$workspace_cubical_dir/cubical.agda-lib" > "$library_file"

summary_file="$evidence_dir/summary.tsv"
printf 'kind\tmodule\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"

for entry in \
  shard:TransportBase \
  shard:TransportGlue \
  shard:TransportInt \
  shard:TransportCoreB \
  shard:TransportBoundary \
  shard:TransportHit \
  shard:TransportHigher \
  exact:TransportTests
do
  kind=${entry%%:*}
  module=${entry#*:}
  source_file="$workspace_fixture_dir/$module.agda"
  stdout_file="$evidence_dir/$module.stdout.log"
  stderr_file="$evidence_dir/$module.stderr.log"

  if [ ! -f "$source_file" ]; then
    echo "Missing transport shard: $source_file" >&2
    exit 2
  fi

  echo "stock-agda transport $kind: $module"
  if /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    "$agda_bin" \
      -v0 \
      --guardedness \
      --library-file="$library_file" \
      -l cubical \
      -i"$workspace_fixture_dir" \
      "$source_file" \
      >"$stdout_file" 2>"$stderr_file"
  then
    real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_file")
    max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_file")
    printf '%s\t%s\tPASS\t%s\t%s\n' "$kind" "$module" "$real_seconds" "$max_rss" >> "$summary_file"
    echo "$module PASS (${real_seconds}s, max RSS ${max_rss} bytes)"
  else
    printf '%s\t%s\tFAIL\t-\t-\n' "$kind" "$module" >> "$summary_file"
    echo "$module FAIL; see $stderr_file" >&2
    sed -n '1,200p' "$stderr_file" >&2
    exit 1
  fi
done

echo "TransportTests stock-Agda gate passed."
echo "Evidence: $summary_file"
