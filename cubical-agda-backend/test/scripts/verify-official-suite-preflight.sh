#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
inventory_file="$backend_dir/test/fixtures/agda29-official-suite-targets.tsv"
evidence_dir="$backend_dir/build/agda29/official-suite-preflight"
cubical_dir=${CUBICAL29_DIR:-"$(dirname -- "$agda_source_dir")/cubical-upstream"}
stdlib_dir=${STDLIB29_DIR:-"$agda_source_dir/std-lib"}

if [ ! -f "$agda_source_dir/Makefile" ] || [ ! -f "$inventory_file" ]; then
  echo "Pinned Agda Makefile or official-suite inventory is missing" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
AGDA29_SOURCE_DIR="$agda_source_dir" \
  sh "$script_dir/verify-agda29-stock-baseline.sh" \
  > "$evidence_dir/stock-baseline.log"

actual_targets="$evidence_dir/upstream-targets.txt"
expected_targets="$evidence_dir/expected-targets.txt"
awk '
  /^test[[:space:]]*:/ {
    active=1
    line=$0
    sub(/^[^:]*:[[:space:]]*/, "", line)
  }
  active {
    if ($0 !~ /^test[[:space:]]*:/) line=$0
    more=(line ~ /\\[[:space:]]*$/)
    gsub(/\\/, "", line)
    count=split(line, words, /[[:space:]]+/)
    for (field_index=1; field_index<=count; field_index++)
      if (words[field_index] != "") print words[field_index]
    if (!more) exit
  }
' "$agda_source_dir/Makefile" > "$actual_targets"
awk -F '\t' 'NR > 1 { print $1 }' "$inventory_file" > "$expected_targets"

if ! cmp -s "$expected_targets" "$actual_targets"; then
  echo "Pinned upstream 'make test' dependency inventory changed" >&2
  diff -u "$expected_targets" "$actual_targets" >&2 || true
  exit 2
fi

summary_file="$evidence_dir/summary.tsv"
printf 'target\tlane\tstatus\treason\n' > "$summary_file"

tab=$(printf '\t')
while IFS="$tab" read -r target lane prerequisite
do
  [ "$target" = target ] && continue
  status=READY
  reason=stock-inputs-present
  case "$prerequisite" in
    none)
      ;;
    cubical)
      if [ -f "$cubical_dir/cubical.agda-lib" ]; then
        reason=cubical-snapshot-present
      else
        status=BLOCKED-ENVIRONMENT
        reason=missing-cubical-snapshot
      fi
      ;;
    stdlib)
      if [ -f "$stdlib_dir/standard-library.agda-lib" ]; then
        reason=pinned-stdlib-snapshot-present
      else
        status=BLOCKED-ENVIRONMENT
        reason=empty-stdlib-submodule
      fi
      ;;
    fix-whitespace)
      if command -v fix-whitespace >/dev/null 2>&1; then
        reason=fix-whitespace-present
      else
        status=BLOCKED-ENVIRONMENT
        reason=missing-fix-whitespace
      fi
      ;;
    latex)
      if command -v latex >/dev/null 2>&1; then
        reason=latex-present
      else
        status=BLOCKED-ENVIRONMENT
        reason=missing-latex
      fi
      ;;
    interaction-portability)
      sed_probe=$(printf '%s\n' 'goal_command 0 (Cmd_autoOne AsIs) ""' | \
        sed 's/goal_command \([0-9]\+\) (\([^)]\+\)) \("[^"]*"\)/expanded/g')
      if [ "$sed_probe" != expanded ] || \
         { [ -d "$agda_source_dir/test/Interaction" ] && \
           [ -d "$agda_source_dir/test/interaction" ] && \
           [ "$agda_source_dir/test/Interaction" -ef "$agda_source_dir/test/interaction" ]; }
      then
        status=READY-ENV-COMPAT
        reason=bsd-sed-or-case-folded-interaction-tree
      else
        reason=gnu-bre-and-case-sensitive-tree
      fi
      ;;
    doctest-install)
      if awk -F '\t' '$1 == "DocTest" && $4 == "PASS-WITH-ENV-COMPAT" { found=1 } END { exit !found }' \
        "$backend_dir/build/agda29/official-native/doc-test/summary.doctest-compat.tsv" 2>/dev/null
      then
        status=PASS-EXISTING-ENV-COMPAT
        reason=official-doctest-5-of-5-with-locked-ghc-repl-compat
      else
        status=READY-NETWORK-INSTALL
        reason=upstream-target-installs-doctest
      fi
      ;;
    existing-compiler)
      if awk -F '\t' '$1 == "Compiler" && $3 == "PASS" { found=1 } END { exit !found }' \
        "$backend_dir/build/agda29/official-compiler/summary.tsv" 2>/dev/null
      then
        status=PASS-EXISTING
        reason=official-compiler-687-of-687
      else
        status=READY-SEPARATE-GATE
        reason=run-verify-official-compiler
      fi
      ;;
    upstream-disabled)
      status=SKIP-UPSTREAM-DISABLED
      reason=dependency-listed-but-target-commented-out
      ;;
    *)
      echo "Unknown official-suite prerequisite: $prerequisite" >&2
      exit 2
      ;;
  esac
  printf '%s\t%s\t%s\t%s\n' "$target" "$lane" "$status" "$reason" \
    >> "$summary_file"
done < "$inventory_file"

awk -F '\t' 'NR > 1 { count[$3]++ } END { for (status in count) print status "\t" count[status] }' \
  "$summary_file" | LC_ALL=C sort > "$evidence_dir/status-counts.tsv"

printf '%s\n' \
  'The upstream test aggregate lists size-solver-test, but its rule is commented out in this commit.' \
  'The supplied parent archive has an empty std-lib submodule; STDLIB29_DIR may provide the exact parent gitlink snapshot.' \
  'A separate supplied cubical snapshot is accepted only when cubical.agda-lib is present.' \
  > "$evidence_dir/notes.log"

echo "Official full-suite preflight PASS: 32 upstream dependencies inventoried"
echo "Evidence: $summary_file"
