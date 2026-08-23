#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the supplied Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
evidence_dir="$backend_dir/build/agda29/stock-baseline"
identity_file="$backend_dir/test/fixtures/agda29-stock-baseline.identity.tsv"
overlay_manifest="$backend_dir/test/fixtures/agda29-v2-overlay.sha256"
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)

if [ ! -f "$agda_source_dir/Agda.cabal" ]; then
  echo "Agda.cabal not found below AGDA29_SOURCE_DIR: $agda_source_dir" >&2
  exit 2
fi

if [ ! -f "$identity_file" ] || [ ! -f "$overlay_manifest" ]; then
  echo "Agda 2.9 stock baseline identity inputs are missing" >&2
  exit 2
fi

if ! grep -Eq '^version:[[:space:]]+2\.9\.0$' "$agda_source_dir/Agda.cabal"; then
  echo "The supplied source does not report Agda 2.9.0" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
summary_file="$evidence_dir/summary.tsv"
printf 'scope\tfiles\tstatus\tsha256\n' > "$summary_file"

stock_tree_hash() {
  stock_scope=$1
  (
    CDPATH= cd -- "$agda_source_dir"
    find "$stock_scope" -type f \
      ! -path './dist-newstyle/*' \
      ! -path './cubical/*' \
      ! -path './std-lib/*' \
      ! -path './Agda.cabal' \
      ! -path './src/data/lib/prim/_build/*' \
      ! -path './src/cubical-run/*' \
      ! -path './src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs' \
      ! -path './src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs.orig' \
      ! -path './test/CubicalRuntime/*' \
      -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 |
      shasum -a 256 | awk '{ print $1 }'
  )
}

stock_tree_count() {
  stock_scope=$1
  (
    CDPATH= cd -- "$agda_source_dir"
    find "$stock_scope" -type f \
      ! -path './dist-newstyle/*' \
      ! -path './cubical/*' \
      ! -path './std-lib/*' \
      ! -path './Agda.cabal' \
      ! -path './src/data/lib/prim/_build/*' \
      ! -path './src/cubical-run/*' \
      ! -path './src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs' \
      ! -path './src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs.orig' \
      ! -path './test/CubicalRuntime/*' |
      wc -l | tr -d ' '
  )
}

identity_failed=0
while read -r identity_kind identity_scope identity_count identity_expected
do
  [ "$identity_kind" = tree ] || continue
  identity_actual=$(stock_tree_hash "$identity_scope")
  identity_actual_count=$(stock_tree_count "$identity_scope")
  if [ "$identity_actual" = "$identity_expected" ] && \
     [ "$identity_actual_count" = "$identity_count" ]
  then
    printf '%s\t%s\tPASS\t%s\n' \
      "$identity_scope" "$identity_count" "$identity_actual" >> "$summary_file"
  else
    printf '%s\t%s\tFAIL\t%s\n' \
      "$identity_scope" "$identity_actual_count" "$identity_actual" >> "$summary_file"
    printf 'Stock projection mismatch for %s: expected files=%s sha256=%s; actual files=%s sha256=%s\n' \
      "$identity_scope" "$identity_count" "$identity_expected" \
      "$identity_actual_count" "$identity_actual" >&2
    identity_failed=1
  fi
done < "$identity_file"

if [ "$identity_failed" -ne 0 ]; then
  exit 1
fi

overlay_log="$evidence_dir/overlay-sha256.log"
if (CDPATH= cd -- "$agda_source_dir" && \
  shasum -a 256 -c "$overlay_manifest") > "$overlay_log" 2>&1
then
  overlay_hash=$(shasum -a 256 "$overlay_manifest" | awk '{ print $1 }')
  printf 'v2-overlay\t9\tPASS\t%s\n' "$overlay_hash" >> "$summary_file"
else
  printf 'v2-overlay\t-\tFAIL\t-\n' >> "$summary_file"
  echo "Supplied v2 overlay SHA-256 mismatch" >&2
  sed -n '1,120p' "$overlay_log" >&2
  exit 1
fi

awk -F '\t' '$1 == "metadata" { print $2 "\t" $3 }' "$identity_file" \
  > "$evidence_dir/provenance.tsv"

printf '%s\n' \
  'EXCLUDED generated: dist-newstyle and src/data/lib/prim/_build.' \
  'EXCLUDED submodule content: cubical and std-lib are not part of the parent commit archive.' \
  'SEPARATE overlay: Agda.cabal, src/cubical-run, Cubical Runtime module, and test/CubicalRuntime.' \
  > "$evidence_dir/exclusions.log"

echo "Agda 2.9 stock projection and supplied v2 overlay identity PASS"
echo "Evidence: $summary_file"
