#!/bin/sh

set -eu

: "${AGDA_BIN:?Set AGDA_BIN to the stock Agda executable}"
: "${CUBICAL_RUNNER:?Set CUBICAL_RUNNER to agda-cubical-run v2}"
: "${CUBICAL_DIR:?Set CUBICAL_DIR to the agda/cubical checkout}"
: "${TRANSPORT_TEST_FILE:?Set TRANSPORT_TEST_FILE to TransportTests.agda}"

if [ ! -x "$AGDA_BIN" ]; then
  echo "AGDA_BIN is not executable: $AGDA_BIN" >&2
  exit 2
fi

if [ ! -x "$CUBICAL_RUNNER" ]; then
  echo "CUBICAL_RUNNER is not executable: $CUBICAL_RUNNER" >&2
  exit 2
fi

if [ ! -f "$CUBICAL_DIR/cubical.agda-lib" ]; then
  echo "cubical.agda-lib not found below CUBICAL_DIR: $CUBICAL_DIR" >&2
  exit 2
fi

if [ ! -f "$TRANSPORT_TEST_FILE" ]; then
  echo "Transport test file not found: $TRANSPORT_TEST_FILE" >&2
  exit 2
fi

test_dir=$(CDPATH= cd -- "$(dirname -- "$TRANSPORT_TEST_FILE")" && pwd)
test_file="$test_dir/$(basename -- "$TRANSPORT_TEST_FILE")"
library_file=$(mktemp)
packet_file=$(mktemp)
trap 'rm -f "$library_file" "$packet_file"' EXIT HUP INT TERM
printf '%s\n' "$CUBICAL_DIR/cubical.agda-lib" > "$library_file"

echo "stock-agda baseline"
"$AGDA_BIN" \
  -v0 \
  --guardedness \
  --library-file="$library_file" \
  -l cubical \
  -i"$test_dir" \
  --no-write-interfaces \
  "$test_file"

run_expr() {
  "$CUBICAL_RUNNER" \
    -v0 \
    --guardedness \
    --library-file="$library_file" \
    -l cubical \
    -i"$test_dir" \
    --no-write-interfaces \
    "--cubical-run=$1" \
    "$test_file"
}

compare_expr() {
  actual=$(run_expr "$1")
  expected=$(run_expr "$2")
  if [ "$actual" != "$expected" ]; then
    echo "$1 differs from $2" >&2
    printf 'actual:\n%s\nexpected:\n%s\n' "$actual" "$expected" >&2
    exit 1
  fi
  printf '%s\tMATCH\n' "$1"
}

for suffix in 01 02 03 04 05 06 07 08 09 10 12 13 14 15
do
  compare_expr "t$suffix" "e$suffix"
done

t11_value=$(run_expr t11)
case "$t11_value" in
  Cubical.Data.Vec.Base.transpX-Vec*) echo "t11 EXPECTED-RESIDUAL" ;;
  *)
    echo "t11 did not retain the documented transpX-Vec boundary" >&2
    exit 1
    ;;
esac

t11b_value=$(run_expr t11b)
case "$t11b_value" in
  Cubical.Data.Vec.Base.transpX-Vec*) echo "t11b EXPECTED-RESIDUAL" ;;
  *)
    echo "t11b did not retain the documented transpX-Vec boundary" >&2
    exit 1
    ;;
esac

run_export() {
  "$CUBICAL_RUNNER" \
    -v0 \
    --guardedness \
    --library-file="$library_file" \
    -l cubical \
    -i"$test_dir" \
    --no-write-interfaces \
    "--cubical-export=$1" \
    "--cubical-term-file=$2" \
    "$test_file"
}

run_import() {
  "$CUBICAL_RUNNER" \
    -v0 \
    --guardedness \
    --library-file="$library_file" \
    -l cubical \
    -i"$test_dir" \
    --no-write-interfaces \
    "--cubical-import=$1" \
    "--cubical-term-file=$2" \
    "$test_file"
}

check_pipe() {
  actual=$(run_export "$1" - | run_import "$2" -)
  if [ "$actual" != "$3" ]; then
    echo "$1 -> $2 produced '$actual', expected '$3'" >&2
    exit 1
  fi
  printf '%s -> %s\t%s\n' "$1" "$2" "$actual"
}

echo "t16 cross-process pipe"
check_pipe p16a c16a "true"
check_pipe p16b c16b "pos 2"
check_pipe p16c c16c "pos 2"

echo "t16 cross-process file"
run_export p16a "$packet_file"
file_result=$(run_import c16a "$packet_file")
if [ "$file_result" != "true" ]; then
  echo "file packet produced '$file_result', expected 'true'" >&2
  exit 1
fi
echo "p16a -> c16a true"

set +e
wrong_consumer_output=$(run_import c16b "$packet_file" 2>&1)
wrong_consumer_status=$?
set -e
if [ "$wrong_consumer_status" -eq 0 ]; then
  echo "p16a was unexpectedly accepted by the c16b consumer" >&2
  exit 1
fi
case "$wrong_consumer_output" in
  *"UnequalTypes"*) echo "p16a -> c16b EXPECTED-REJECT" ;;
  *)
    echo "p16a -> c16b failed for an unexpected reason:" >&2
    echo "$wrong_consumer_output" >&2
    exit 1
    ;;
esac

echo "TransportTests v2 acceptance passed."
