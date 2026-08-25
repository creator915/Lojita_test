#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
fixture_dir="$backend_dir/test/fixtures/transport"
evidence_dir="$backend_dir/build/agda29/v2-runtime"
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
transport_source_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_dir=${CUBICAL29_DIR:-"$(dirname -- "$agda_source_dir")/cubical-upstream"}
cubical_dir=$(CDPATH= cd -- "$cubical_dir" && pwd -P)
runtime_test_dir="$agda_source_dir/test/CubicalRuntime"
self_test_script="$runtime_test_dir/run-tests.sh"
transport_test_script="$runtime_test_dir/run-transport-tests-v2.sh"
ghc29=${GHC29:-ghc}
cabal29=${CABAL29:-cabal}

if [ ! -f "$agda_source_dir/Agda.cabal" ]; then
  echo "Agda.cabal not found below AGDA29_SOURCE_DIR: $agda_source_dir" >&2
  exit 2
fi

if [ ! -f "$cubical_dir/cubical.agda-lib" ]; then
  echo "cubical.agda-lib not found below CUBICAL29_DIR: $cubical_dir" >&2
  exit 2
fi

if [ ! -f "$self_test_script" ] || [ ! -f "$transport_test_script" ]; then
  echo "The archived v2 runtime test scripts are missing below $runtime_test_dir" >&2
  exit 2
fi

cmp "$backend_dir/runtime/agda-2.9/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" \
  "$agda_source_dir/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs" || {
    echo "Installed Runtime.hs does not match the maintained v2 overlay" >&2
    exit 2
  }
cmp "$backend_dir/runtime/agda-2.9/src/cubical-run/Main.hs" \
  "$agda_source_dir/src/cubical-run/Main.hs" || {
    echo "Installed agda-cubical-run does not match the maintained v2 overlay" >&2
    exit 2
  }

if [ ! -f "$transport_source" ]; then
  echo "Original transport source is missing: $transport_source" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_source_sha256" ]; then
  echo "Original transport source SHA-256 mismatch: $actual_transport_sha256" >&2
  exit 2
fi

agda_bin=$(CDPATH= cd -- "$agda_source_dir" && "$cabal29" list-bin -w "$ghc29" exe:agda)
runner=$(CDPATH= cd -- "$agda_source_dir" && "$cabal29" list-bin -w "$ghc29" exe:agda-cubical-run)
if [ ! -x "$agda_bin" ] || [ ! -x "$runner" ]; then
  echo "Building the pinned stock Agda and archived v2 runner..."
  (CDPATH= cd -- "$agda_source_dir" && \
    "$cabal29" build -w "$ghc29" exe:agda exe:agda-cubical-run)
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && "$cabal29" list-bin -w "$ghc29" exe:agda)
  runner=$(CDPATH= cd -- "$agda_source_dir" && "$cabal29" list-bin -w "$ghc29" exe:agda-cubical-run)
fi

if [ ! -x "$agda_bin" ] || [ ! -x "$runner" ]; then
  echo "Pinned Agda or agda-cubical-run is not executable" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
summary_file="$evidence_dir/summary.tsv"
printf 'suite\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"

run_measured() {
  stderr_file=$1
  shift
  if [ ! -x /usr/bin/time ]; then
    "$@" 2>"$stderr_file"
    command_status=$?
    printf '\nCCZ_TIME_REAL=-\nCCZ_TIME_RSS_BYTES=-\n' >> "$stderr_file"
    return "$command_status"
  fi
  case $(uname -s) in
    Darwin)
      /usr/bin/time -l "$@" 2>"$stderr_file"
      ;;
    Linux)
      /usr/bin/time -f '\nCCZ_TIME_REAL=%e\nCCZ_TIME_RSS_KIB=%M' \
        "$@" 2>"$stderr_file"
      ;;
    *)
      "$@" 2>"$stderr_file"
      ;;
  esac
}

read_measurement() {
  measurement_file=$1
  case $(uname -s) in
    Darwin)
      measured_real=$(awk '$2 == "real" { print $1; exit }' "$measurement_file")
      measured_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$measurement_file")
      ;;
    Linux)
      measured_real=$(sed -n 's/^CCZ_TIME_REAL=//p' "$measurement_file" | tail -n 1)
      measured_rss_bytes=$(sed -n 's/^CCZ_TIME_RSS_BYTES=//p' "$measurement_file" | tail -n 1)
      if [ -n "$measured_rss_bytes" ]; then
        measured_rss=$measured_rss_bytes
      else
        measured_rss_kib=$(sed -n 's/^CCZ_TIME_RSS_KIB=//p' "$measurement_file" | tail -n 1)
        measured_rss=$(awk -v kib="${measured_rss_kib:-0}" 'BEGIN { printf "%.0f", kib * 1024 }')
      fi
      ;;
    *)
      measured_real=-
      measured_rss=-
      ;;
  esac
}

self_stdout="$evidence_dir/self-contained.stdout.log"
self_stderr="$evidence_dir/self-contained.stderr.log"
echo "archived v2 self-contained runtime suite"
if run_measured "$self_stderr" env Agda_datadir="$agda_source_dir/src/data" \
  sh "$self_test_script" "$runner" "$agda_bin" \
  >"$self_stdout"
then
  read_measurement "$self_stderr"
  self_real=$measured_real
  self_rss=$measured_rss
  printf 'self-contained\tPASS\t%s\t%s\n' "$self_real" "$self_rss" >> "$summary_file"
  echo "self-contained PASS (${self_real}s, max RSS ${self_rss} bytes)"
else
  printf 'self-contained\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Archived v2 self-contained suite failed" >&2
  sed -n '1,240p' "$self_stdout" >&2
  sed -n '1,240p' "$self_stderr" >&2
  exit 1
fi

workspace_dir=$(mktemp -d "$evidence_dir/workspace.XXXXXX")
workspace_cubical_dir="$workspace_dir/cubical"
workspace_fixture_dir="$workspace_dir/fixtures"
library_file="$workspace_dir/libraries"
cleanup() {
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

warmup_log="$evidence_dir/interface-warmup.log"
: > "$warmup_log"
echo "isolated Cubical interface warmup"
for module in \
  TransportBase \
  TransportGlue \
  TransportInt \
  TransportCoreB \
  TransportBoundary \
  TransportHit \
  TransportHigher \
  TransportTests
do
  env Agda_datadir="$agda_source_dir/src/data" \
    "$agda_bin" \
      -v0 \
      --guardedness \
      --library-file="$library_file" \
      -l cubical \
      -i"$workspace_fixture_dir" \
      "$workspace_fixture_dir/$module.agda" \
      >>"$warmup_log" 2>&1
done
echo "interface warmup PASS"

transport_stdout="$evidence_dir/transport-matrix.stdout.log"
transport_stderr="$evidence_dir/transport-matrix.stderr.log"
echo "archived v2 TransportTests runtime matrix"
if run_measured "$transport_stderr" env \
  Agda_datadir="$agda_source_dir/src/data" \
  AGDA_BIN="$agda_bin" \
  CUBICAL_RUNNER="$runner" \
  CUBICAL_DIR="$workspace_cubical_dir" \
  TRANSPORT_TEST_FILE="$workspace_fixture_dir/TransportTests.agda" \
  sh "$transport_test_script" \
  >"$transport_stdout"
then
  read_measurement "$transport_stderr"
  transport_real=$measured_real
  transport_rss=$measured_rss
  printf 'transport-matrix\tPASS\t%s\t%s\n' "$transport_real" "$transport_rss" >> "$summary_file"
  echo "transport-matrix PASS (${transport_real}s, max RSS ${transport_rss} bytes)"
else
  printf 'transport-matrix\tFAIL\t-\t-\n' >> "$summary_file"
  echo "Archived v2 TransportTests matrix failed" >&2
  sed -n '1,280p' "$transport_stdout" >&2
  sed -n '1,280p' "$transport_stderr" >&2
  exit 1
fi

echo "Archived v2 runtime acceptance passed."
echo "Evidence: $summary_file"
