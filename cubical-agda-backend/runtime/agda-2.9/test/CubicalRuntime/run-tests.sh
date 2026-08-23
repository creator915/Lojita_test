#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

runner=${1:-$(cabal list-bin agda-cubical-run)}
agda=${2:-$(cabal list-bin agda)}
source_file=test/CubicalRuntime/RuntimeTransp.agda

# Hard gate: the source must first be accepted by stock Agda without loading
# the runtime backend.
"$agda" \
  -v0 \
  --no-libraries \
  --no-write-interfaces \
  -itest/CubicalRuntime \
  "$source_file"

run_cubical() {
  "$runner" \
    -v0 \
    --no-libraries \
    --no-write-interfaces \
    -itest/CubicalRuntime \
    --cubical-run="$1" \
    "$source_file"
}

expect_value() {
  expected=$1
  expression=$2
  actual=$(run_cubical "$expression")
  if [ "$actual" != "$expected" ]; then
    echo "expected '$expected' from '$expression', got '$actual'" >&2
    exit 1
  fi
}

expect_contains() {
  expected_fragment=$1
  expression=$2
  actual=$(run_cubical "$expression")
  case "$actual" in
    *"$expected_fragment"*) ;;
    *)
      echo "expected '$expression' to remain blocked on '$expected_fragment', got '$actual'" >&2
      exit 1
      ;;
  esac
}

# The operations remain blocked while their ordinary runtime selector is
# neutral, and resume once a concrete selector is supplied.
expect_contains "primTransp" "runtimeTransp"
expect_contains "primHComp" "runtimeHComp"
expect_contains "selectedEquiv selector" "runtimeGlueTransp"

expect_value "42"    "runtimeTransp true 42"
expect_value "true"  "runtimeTransp false true"
expect_value "17"    "runtimeHComp true 17"
expect_value "false" "runtimeGlueTransp true true"
expect_value "true"  "runtimeGlueTransp false true"
expect_value "false , 3" "runtimeSigmaTransp"
expect_value "true" "functionAcceptance"

# File-backed process boundary.
packet_file=$(mktemp)
trap 'rm -f "$packet_file"' EXIT HUP INT TERM

"$runner" \
  -v0 \
  --no-libraries \
  --no-write-interfaces \
  -itest/CubicalRuntime \
  --cubical-export=runtimeFunctionProducer \
  --cubical-term-file="$packet_file" \
  "$source_file"

packet_result=$(
  "$runner" \
    -v0 \
    --no-libraries \
    --no-write-interfaces \
    -itest/CubicalRuntime \
    --cubical-import=runtimeFunctionConsumer \
    --cubical-term-file="$packet_file" \
    "$source_file"
)

if [ "$packet_result" != "true" ]; then
  echo "file-backed Term round-trip produced '$packet_result'" >&2
  exit 1
fi

# Direct pipe between two independently type-checking processes.
pipe_result=$(
  "$runner" \
    -v0 \
    --no-libraries \
    --no-write-interfaces \
    -itest/CubicalRuntime \
    --cubical-export=runtimeFunctionProducer \
    --cubical-term-file=- \
    "$source_file" |
  "$runner" \
    -v0 \
    --no-libraries \
    --no-write-interfaces \
    -itest/CubicalRuntime \
    --cubical-import=runtimeFunctionConsumer \
    --cubical-term-file=- \
    "$source_file"
)

if [ "$pipe_result" != "true" ]; then
  echo "piped Term round-trip produced '$pipe_result'" >&2
  exit 1
fi

set +e
negative_output=$(
  "$agda" \
    -v0 \
    --compile \
    --no-libraries \
    --no-write-interfaces \
    -itest/CubicalRuntime \
    "$source_file" 2>&1
)
negative_status=$?
set -e

if [ "$negative_status" -eq 0 ]; then
  echo "the ordinary GHC backend unexpectedly accepted full Cubical Agda" >&2
  exit 1
fi

case "$negative_output" in
  *"CubicalCompilationNotSupported"*) ;;
  *)
    echo "the ordinary GHC backend failed for an unexpected reason:" >&2
    echo "$negative_output" >&2
    exit 1
    ;;
esac

echo "Cubical runtime acceptance tests passed."
