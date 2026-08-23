#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
evidence_dir="$backend_dir/build/agda29/official-compiler"
identity_file="$backend_dir/test/fixtures/agda29-official-compiler-tree.sha256"
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
ghc29=${GHC29:-ghc}
jobs=${OFFICIAL_COMPILER_JOBS:-$(getconf _NPROCESSORS_ONLN)}
fdebug_dist="$evidence_dir/fdebug-dist"
expected_passed_tests=687
expected_disabled_tests=41

if [ ! -f "$agda_source_dir/Agda.cabal" ]; then
  echo "Agda.cabal not found below AGDA29_SOURCE_DIR: $agda_source_dir" >&2
  exit 2
fi

if [ ! -f "$identity_file" ]; then
  echo "Official Compiler identity file is missing: $identity_file" >&2
  exit 2
fi

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "OFFICIAL_COMPILER_JOBS must be a positive integer: $jobs" >&2
    exit 2
    ;;
esac

if ! command -v node >/dev/null 2>&1; then
  echo "node is required for the complete official Compiler matrix" >&2
  exit 2
fi

if ! command -v runghc >/dev/null 2>&1; then
  echo "runghc is required for the complete official Compiler matrix" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
identity_log="$evidence_dir/input-sha256.log"
: > "$identity_log"
identity_failed=0
while read -r identity_kind identity_path identity_expected
do
  case "$identity_kind" in
    file)
      identity_actual=$(shasum -a 256 "$agda_source_dir/$identity_path" | awk '{ print $1 }')
      ;;
    tree)
      identity_actual=$(
        CDPATH= cd -- "$agda_source_dir" &&
        find "$identity_path" -type f -print | LC_ALL=C sort |
          while IFS= read -r input_file; do
            shasum -a 256 "$input_file"
          done |
          shasum -a 256 | awk '{ print $1 }'
      )
      ;;
    *)
      echo "Unknown identity kind: $identity_kind" >&2
      exit 2
      ;;
  esac

  if [ "$identity_actual" = "$identity_expected" ]; then
    printf 'PASS\t%s\t%s\t%s\n' "$identity_kind" "$identity_path" "$identity_actual" >> "$identity_log"
  else
    printf 'FAIL\t%s\t%s\texpected=%s\tactual=%s\n' \
      "$identity_kind" "$identity_path" "$identity_expected" "$identity_actual" >> "$identity_log"
    identity_failed=1
  fi
done < "$identity_file"

if [ "$identity_failed" -ne 0 ]; then
  echo "Official Compiler source SHA-256 mismatch" >&2
  sed -n '1,120p' "$identity_log" >&2
  exit 2
fi
echo "official Compiler source identity PASS"

agda_bin=$(CDPATH= cd -- "$agda_source_dir" && \
  cabal list-bin --builddir="$fdebug_dist" -w "$ghc29" -fdebug exe:agda)
tests_bin=$(CDPATH= cd -- "$agda_source_dir" && \
  cabal list-bin --builddir="$fdebug_dist" -w "$ghc29" -fdebug exe:agda-tests)
if [ ! -x "$agda_bin" ] || [ ! -x "$tests_bin" ]; then
  echo "Building the pinned stock Agda and official test driver with -fdebug..."
  (CDPATH= cd -- "$agda_source_dir" && \
    cabal build --builddir="$fdebug_dist" -w "$ghc29" -fdebug \
      exe:agda exe:agda-tests)
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && \
    cabal list-bin --builddir="$fdebug_dist" -w "$ghc29" -fdebug exe:agda)
  tests_bin=$(CDPATH= cd -- "$agda_source_dir" && \
    cabal list-bin --builddir="$fdebug_dist" -w "$ghc29" -fdebug exe:agda-tests)
fi

if [ ! -x "$agda_bin" ] || [ ! -x "$tests_bin" ]; then
  echo "Pinned Agda or official agda-tests executable is unavailable" >&2
  exit 2
fi

ghc_version=$($ghc29 --numeric-version)
node_version=$(node --version)
printf 'ghc\t%s\nnode\t%s\njobs\t%s\n' "$ghc_version" "$node_version" "$jobs" \
  > "$evidence_dir/environment.tsv"

workspace_dir=$(mktemp -d "$evidence_dir/workspace.XXXXXX")
workspace_root="$workspace_dir/root"
cleanup() {
  rm -rf "$workspace_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_root"
if ! cp -cR "$agda_source_dir/test" "$workspace_root/test" 2>/dev/null; then
  cp -R "$agda_source_dir/test" "$workspace_root/test"
fi
if ! cp -cR "$agda_source_dir/doc" "$workspace_root/doc" 2>/dev/null; then
  cp -R "$agda_source_dir/doc" "$workspace_root/doc"
fi
if ! cp -cR "$agda_source_dir/mk" "$workspace_root/mk" 2>/dev/null; then
  cp -R "$agda_source_dir/mk" "$workspace_root/mk"
fi

stdout_log="$evidence_dir/compiler.stdout.log"
stderr_log="$evidence_dir/compiler.stderr.log"
summary_file="$evidence_dir/summary.tsv"
printf 'suite\ttests\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"

echo "official complete Compiler group (${jobs} jobs)"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j"$jobs" \
      --regex-include all/Compiler \
      --regex-exclude AllStdLib \
    >"$stdout_log" 2>"$stderr_log")
then
  passed_tests=$(sed -nE 's/^All ([0-9]+) tests passed.*$/\1/p' "$stdout_log" | tail -n 1)
  if [ -z "$passed_tests" ]; then
    printf 'Compiler\t-\tFAIL-NO-SUMMARY\t-\t-\n' >> "$summary_file"
    echo "Official Compiler group exited successfully without a Tasty pass summary" >&2
    sed -n '1,260p' "$stdout_log" >&2
    sed -n '1,260p' "$stderr_log" >&2
    exit 1
  fi

  disabled_tests=$(grep -c ': *DISABLED$' "$stdout_log")
  if [ "$passed_tests" -ne "$expected_passed_tests" ] || \
     [ "$disabled_tests" -ne "$expected_disabled_tests" ]
  then
    printf 'Compiler\t%s\tFAIL-COUNT\t-\t-\n' "$passed_tests" >> "$summary_file"
    echo "Official Compiler selection count changed: passed=$passed_tests disabled=$disabled_tests" >&2
    echo "Expected: passed=$expected_passed_tests disabled=$expected_disabled_tests" >&2
    exit 1
  fi

  compiler_real=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  compiler_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  printf 'Compiler\t%s\tPASS\t%s\t%s\n' \
    "$passed_tests" "$compiler_real" "$compiler_rss" >> "$summary_file"
  echo "Complete Compiler group PASS: ${passed_tests} tests (${compiler_real}s, max RSS ${compiler_rss} bytes)"
else
  compiler_real=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  compiler_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  printf 'Compiler\t-\tFAIL\t%s\t%s\n' \
    "${compiler_real:--}" "${compiler_rss:--}" >> "$summary_file"
  echo "Official complete Compiler group failed" >&2
  tail -n 320 "$stdout_log" >&2
  tail -n 320 "$stderr_log" >&2
  exit 1
fi

matrix_file="$evidence_dir/matrix.tsv"
printf 'backend\tpassed\tdisabled\n' > "$matrix_file"
awk '
  /^    (MAlonzo|JS_)/ { backend=$1; next }
  /: +OK/ { passed[backend]++ }
  /: +DISABLED/ { disabled[backend]++ }
  END {
    for (backend in passed) {
      printf "%s\t%d\t%d\n", backend, passed[backend], disabled[backend] + 0
    }
  }
' "$stdout_log" | LC_ALL=C sort >> "$matrix_file"

classification_file="$evidence_dir/classification.tsv"
printf 'category\tcount\tclassification\tevidence\n' > "$classification_file"
printf 'executed\t687\tPASS\tcompiler.stdout.log\n' >> "$classification_file"
printf 'upstream-always-disabled\t41\tSKIP-UPSTREAM\tcompiler.stdout.log\n' >> "$classification_file"
printf 'stdlib-canonical-exclusion\t2\tSKIP-ENVIRONMENT\tskips.log\n' >> "$classification_file"
if [ -f "$evidence_dir/non-fdebug-probe.stdout.log" ]; then
  printf 'non-fdebug-CaseOnCase\t1\tENVIRONMENT-RESOLVED-BY-FDEBUG\tnon-fdebug-probe.stdout.log\n' \
    >> "$classification_file"
fi

printf '%s\n' \
  'SKIP AllStdLib and AllStdLibJS: excluded by the upstream compiler-test target; supplied std-lib submodule is empty.' \
  'INCLUDE fdebug-dependent Compiler tests: this target builds a separate pinned Agda/test driver with -fdebug.' \
  'SKIP upstream always-disabled Compiler cases: excluded by Compiler.Tests.disabledTests.' \
  > "$evidence_dir/skips.log"

echo "Evidence: $summary_file"
