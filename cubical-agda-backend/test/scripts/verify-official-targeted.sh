#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
evidence_dir="$backend_dir/build/agda29/official-targeted"
input_manifest="$backend_dir/test/fixtures/agda29-official-targeted.sha256"
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

if [ ! -f "$input_manifest" ]; then
  echo "Official targeted-test manifest is missing: $input_manifest" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
input_log="$evidence_dir/input-sha256.log"
if (CDPATH= cd -- "$agda_source_dir" && \
  shasum -a 256 -c "$input_manifest") >"$input_log" 2>&1
then
  echo "official targeted-test source identity PASS"
else
  echo "Official targeted-test source SHA-256 mismatch" >&2
  sed -n '1,200p' "$input_log" >&2
  exit 2
fi

agda_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda)
tests_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda-tests)
if [ ! -x "$agda_bin" ] || [ ! -x "$tests_bin" ]; then
  echo "Building the pinned stock Agda and official test driver..."
  (CDPATH= cd -- "$agda_source_dir" && \
    cabal build -w "$ghc29" exe:agda exe:agda-tests)
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda)
  tests_bin=$(CDPATH= cd -- "$agda_source_dir" && cabal list-bin -w "$ghc29" exe:agda-tests)
fi

if [ ! -x "$agda_bin" ] || [ ! -x "$tests_bin" ]; then
  echo "Pinned Agda or official agda-tests executable is unavailable" >&2
  exit 2
fi

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
if ! cp -cR "$cubical_dir" "$workspace_root/cubical" 2>/dev/null; then
  cp -R "$cubical_dir" "$workspace_root/cubical"
fi

summary_file="$evidence_dir/summary.tsv"
printf 'suite\ttests\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"

cubical_stdout="$evidence_dir/cubical-succeed.stdout.log"
cubical_stderr="$evidence_dir/cubical-succeed.stderr.log"
echo "official CubicalSucceed suite"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 --regex-include all/CubicalSucceed \
    >"$cubical_stdout" 2>"$cubical_stderr") && \
   grep -q 'All 1 tests passed' "$cubical_stdout"
then
  cubical_real=$(awk '$2 == "real" { print $1; exit }' "$cubical_stderr")
  cubical_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$cubical_stderr")
  printf 'CubicalSucceed\t1\tPASS\t%s\t%s\n' "$cubical_real" "$cubical_rss" >> "$summary_file"
  echo "CubicalSucceed PASS (${cubical_real}s, max RSS ${cubical_rss} bytes)"
else
  printf 'CubicalSucceed\t1\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official CubicalSucceed suite failed" >&2
  sed -n '1,260p' "$cubical_stdout" >&2
  sed -n '1,260p' "$cubical_stderr" >&2
  exit 1
fi

api_stdout="$evidence_dir/api-interface.stdout.log"
api_stderr="$evidence_dir/api-interface.stderr.log"
cabal_ghc="cabal --project-dir=$agda_source_dir exec -w $ghc29 -- ghc"
echo "official API interface/serialise subset"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    make -C test/api \
      AGDA_BIN="$agda_bin" \
      GHC="$cabal_ghc" \
      Issue1168.api PrettyInterface.api ScopeFromInterface.api \
      >"$api_stdout" 2>"$api_stderr") && \
   test -f "$workspace_root/test/api/Issue1168.api" && \
   test -f "$workspace_root/test/api/PrettyInterface.api" && \
   test -f "$workspace_root/test/api/ScopeFromInterface.api"
then
  api_real=$(awk '$2 == "real" { print $1; exit }' "$api_stderr")
  api_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$api_stderr")
  printf 'API-Interface-Serialise\t3\tPASS\t%s\t%s\n' "$api_real" "$api_rss" >> "$summary_file"
  echo "API interface/serialise PASS (${api_real}s, max RSS ${api_rss} bytes)"
else
  printf 'API-Interface-Serialise\t3\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official API interface/serialise subset failed" >&2
  sed -n '1,320p' "$api_stdout" >&2
  sed -n '1,320p' "$api_stderr" >&2
  exit 1
fi

internal_stdout="$evidence_dir/internal-compiler.stdout.log"
internal_stderr="$evidence_dir/internal-compiler.stderr.log"
echo "official Internal MAlonzo encoder properties"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 \
      --regex-include all/Internal/Internal.Compiler.MAlonzo.Encode \
    >"$internal_stdout" 2>"$internal_stderr") && \
   grep -q 'All 3 tests passed' "$internal_stdout"
then
  internal_real=$(awk '$2 == "real" { print $1; exit }' "$internal_stderr")
  internal_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$internal_stderr")
  printf 'Internal-MAlonzo-Encode\t3\tPASS\t%s\t%s\n' "$internal_real" "$internal_rss" >> "$summary_file"
  echo "Internal MAlonzo encoder PASS (${internal_real}s, max RSS ${internal_rss} bytes)"
else
  printf 'Internal-MAlonzo-Encode\t3\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official Internal MAlonzo encoder properties failed" >&2
  sed -n '1,260p' "$internal_stdout" >&2
  sed -n '1,260p' "$internal_stderr" >&2
  exit 1
fi

compiler_stdout="$evidence_dir/compiler-cubical-negatives.stdout.log"
compiler_stderr="$evidence_dir/compiler-cubical-negatives.stderr.log"
compiler_regex='all/Compiler/MAlonzo_Lazy/simple/(Cubical-is-not-supported|Cubical-primitives-are-not-supported|Erased-cubical-Pattern-matching|Higher-inductive-types-are-not-supported)'
echo "official MAlonzo Cubical compilation negatives"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 --regex-include "$compiler_regex" \
    >"$compiler_stdout" 2>"$compiler_stderr") && \
   grep -q 'All 4 tests passed' "$compiler_stdout"
then
  compiler_real=$(awk '$2 == "real" { print $1; exit }' "$compiler_stderr")
  compiler_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$compiler_stderr")
  printf 'Compiler-Cubical-Negatives\t4\tPASS\t%s\t%s\n' "$compiler_real" "$compiler_rss" >> "$summary_file"
  echo "MAlonzo Cubical negatives PASS (${compiler_real}s, max RSS ${compiler_rss} bytes)"
else
  printf 'Compiler-Cubical-Negatives\t4\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official MAlonzo Cubical compilation negatives failed" >&2
  sed -n '1,320p' "$compiler_stdout" >&2
  sed -n '1,320p' "$compiler_stderr" >&2
  exit 1
fi

typechecking_stdout="$evidence_dir/internal-typechecking.stdout.log"
typechecking_stderr="$evidence_dir/internal-typechecking.stderr.log"
typechecking_regex='all/Internal/Internal.TypeChecking/prop_'
echo "official Internal TypeChecking properties"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 --regex-include "$typechecking_regex" \
    >"$typechecking_stdout" 2>"$typechecking_stderr") && \
   grep -q 'All 11 tests passed' "$typechecking_stdout"
then
  typechecking_real=$(awk '$2 == "real" { print $1; exit }' "$typechecking_stderr")
  typechecking_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$typechecking_stderr")
  printf 'Internal-TypeChecking\t11\tPASS\t%s\t%s\n' "$typechecking_real" "$typechecking_rss" >> "$summary_file"
  echo "Internal TypeChecking PASS (${typechecking_real}s, max RSS ${typechecking_rss} bytes)"
else
  printf 'Internal-TypeChecking\t11\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official Internal TypeChecking properties failed" >&2
  sed -n '1,360p' "$typechecking_stdout" >&2
  sed -n '1,360p' "$typechecking_stderr" >&2
  exit 1
fi

conversion_succeed_stdout="$evidence_dir/conversion-succeed.stdout.log"
conversion_succeed_stderr="$evidence_dir/conversion-succeed.stderr.log"
conversion_succeed_regex='all/Succeed/(EtaSingletonField|Issue6720|Issue7853|NatEquals|TranspReflPair)'
echo "official conversion success regressions"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 --regex-include "$conversion_succeed_regex" \
    >"$conversion_succeed_stdout" 2>"$conversion_succeed_stderr") && \
   grep -q 'All 5 tests passed' "$conversion_succeed_stdout"
then
  conversion_succeed_real=$(awk '$2 == "real" { print $1; exit }' "$conversion_succeed_stderr")
  conversion_succeed_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$conversion_succeed_stderr")
  printf 'Conversion-Succeed\t5\tPASS\t%s\t%s\n' "$conversion_succeed_real" "$conversion_succeed_rss" >> "$summary_file"
  echo "Conversion success regressions PASS (${conversion_succeed_real}s, max RSS ${conversion_succeed_rss} bytes)"
else
  printf 'Conversion-Succeed\t5\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official conversion success regressions failed" >&2
  sed -n '1,360p' "$conversion_succeed_stdout" >&2
  sed -n '1,360p' "$conversion_succeed_stderr" >&2
  exit 1
fi

conversion_fail_stdout="$evidence_dir/conversion-fail.stdout.log"
conversion_fail_stderr="$evidence_dir/conversion-fail.stderr.log"
conversion_fail_regex='all/Fail/(ConvErrCtxLam|ConvErrCtxLevels|Issue3572|Issue8037|UnequalTerms)'
echo "official conversion golden failure regressions"
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    Agda_datadir="$agda_source_dir/src/data" \
    AGDA_BIN="$agda_bin" \
    "$tests_bin" -i -j1 --regex-include "$conversion_fail_regex" \
    >"$conversion_fail_stdout" 2>"$conversion_fail_stderr") && \
   grep -q 'All 5 tests passed' "$conversion_fail_stdout"
then
  conversion_fail_real=$(awk '$2 == "real" { print $1; exit }' "$conversion_fail_stderr")
  conversion_fail_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$conversion_fail_stderr")
  printf 'Conversion-Fail-Golden\t5\tPASS\t%s\t%s\n' "$conversion_fail_real" "$conversion_fail_rss" >> "$summary_file"
  echo "Conversion golden failures PASS (${conversion_fail_real}s, max RSS ${conversion_fail_rss} bytes)"
else
  printf 'Conversion-Fail-Golden\t5\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Official conversion golden failure regressions failed" >&2
  sed -n '1,360p' "$conversion_fail_stdout" >&2
  sed -n '1,360p' "$conversion_fail_stderr" >&2
  exit 1
fi

printf '%s\n' \
  'SKIP PrintImports.run: the supplied pinned std-lib submodule is empty.' \
  > "$evidence_dir/skips.log"

echo "Agda official targeted tests passed."
echo "Evidence: $summary_file"
