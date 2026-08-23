#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?set CUBICAL29_DIR to the pinned Cubical source tree}"

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
projection="$backend_dir/test/fixtures/transport/TransportBase.agda"
binary="$backend_dir/build/agda29/cubical-chez"
spike_binary="$backend_dir/build/agda29/cubical-chez-nbe-adapter-spike"
evidence_dir="$backend_dir/build/agda29/evidence/NbeAdapterTransportBase"
transport_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
projection_sha256=109340fe11b48c742fb546ae1f506db7febbe882f9396f95c63c6a6123e7b543

if [ ! -f "$agda_source_dir/Agda.cabal" ] || \
   [ ! -f "$cubical_source_dir/cubical.agda-lib" ] || \
   [ ! -x "$binary" ] || [ ! -x "$spike_binary" ]
then
  echo "Pinned sources or Agda 2.9 adapter binaries are unavailable; run verify-agda29 first" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
actual_projection_sha256=$(shasum -a 256 "$projection" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_sha256" ] || \
   [ "$actual_projection_sha256" != "$projection_sha256" ]
then
  echo "TransportTests source or TransportBase projection SHA-256 mismatch" >&2
  exit 2
fi

mkdir -p "$evidence_dir"
for scenario in t01 t02 t07
do
  original_fragment="$evidence_dir/$scenario.original.fragment.agda"
  projection_fragment="$evidence_dir/$scenario.projection.fragment.agda"
  awk -v target="$scenario" 'BEGIN { active=0 }
    $0 ~ "^" target " :" { active=1 }
    active {
      print
      if ($0 == "_ = refl") exit
    }
  ' "$transport_source" > "$original_fragment"
  awk -v target="$scenario" 'BEGIN { active=0 }
    $0 ~ "^" target " :" { active=1 }
    active {
      print
      if ($0 == "_ = refl") exit
    }
  ' "$projection" > "$projection_fragment"
  if [ ! -s "$original_fragment" ] || \
     ! cmp -s "$original_fragment" "$projection_fragment"
  then
    echo "$scenario projection is not byte-identical to the pinned original block" >&2
    exit 2
  fi
done

workspace_dir=$(mktemp -d /private/tmp/agda29-nbe-transport-base.XXXXXX)
workspace_cubical_dir="$workspace_dir/cubical"
workspace_input_dir="$workspace_dir/input"
cleanup() {
  rm -rf "$workspace_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_cubical_dir" "$workspace_input_dir"
if ! cp -cR "$cubical_source_dir/." "$workspace_cubical_dir" 2>/dev/null; then
  cp -R "$cubical_source_dir/." "$workspace_cubical_dir"
fi
cp "$projection" "$workspace_input_dir/TransportBase.agda"

run_case() {
  label=$1
  engine=$2
  entry=$3
  runner=$4
  case_dir="$evidence_dir/$label"
  output_dir="$case_dir/output"

  mkdir -p "$output_dir"
  rm -f "$workspace_input_dir/TransportBase.agdai" \
    "$output_dir/program.ss" "$output_dir/treeless.txt" \
    "$output_dir/staging.txt"
  Agda_datadir="$agda_source_dir/src/data" "$runner" \
    -v0 \
    --cubical \
    --safe \
    --guardedness \
    --no-import-sorts \
    -WnoUnsupportedIndexedMatch \
    --cubical-chez \
    --cubical-chez-engine="$engine" \
    --cubical-chez-entry="TransportBase.$entry" \
    --cubical-chez-output="$output_dir" \
    --no-libraries \
    -i "$workspace_input_dir" \
    -i "$workspace_cubical_dir" \
    "$workspace_input_dir/TransportBase.agda" \
    > "$case_dir/producer.stdout" \
    2> "$case_dir/producer.stderr"
  chez --script "$output_dir/program.ss" > "$case_dir/observed.txt"
}

run_case baseline-t01 agda-baseline t01 "$binary"
run_case spike-t01 nbe t01 "$spike_binary"
run_case baseline-t02 agda-baseline t02 "$binary"
run_case spike-t02 nbe t02 "$spike_binary"
run_case baseline-t07 agda-baseline t07 "$binary"
run_case spike-t07 nbe t07 "$spike_binary"

for scenario in t01 t02 t07
do
  case "$scenario" in
    t07) expected=4 ;;
    *) expected=7 ;;
  esac
  for artifact in observed.txt
  do
    if ! cmp -s \
      "$evidence_dir/baseline-$scenario/$artifact" \
      "$evidence_dir/spike-$scenario/$artifact"
    then
      echo "$scenario adapter result differs from the pinned Agda baseline" >&2
      exit 1
    fi
  done
  for artifact in treeless.txt program.ss
  do
    if ! cmp -s \
      "$evidence_dir/baseline-$scenario/output/$artifact" \
      "$evidence_dir/spike-$scenario/output/$artifact"
    then
      echo "$scenario adapter output differs from the pinned Agda baseline in $artifact" >&2
      exit 1
    fi
  done
  if ! grep -Fqx "$expected" "$evidence_dir/spike-$scenario/observed.txt" || \
     ! grep -Fqx 'engine-effective: nbe-spike-test-only' \
       "$evidence_dir/spike-$scenario/output/staging.txt" || \
     ! grep -Fqx 'engine-result-agda-checked: true' \
       "$evidence_dir/spike-$scenario/output/staging.txt"
  then
    echo "$scenario result or adapter provenance is incomplete" >&2
    exit 1
  fi
done

if ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$evidence_dir/spike-t01/output/staging.txt" || \
   ! grep -Fqx 'nbe-constant-nat-transports-reduced: 1' \
     "$evidence_dir/spike-t02/output/staging.txt" || \
   ! grep -Eq '^nbe-path-applications-evaluated: ([1-9][0-9]*)$' \
     "$evidence_dir/spike-t02/output/staging.txt" || \
   ! grep -Fqx 'nbe-transports-reduced: 1' \
     "$evidence_dir/spike-t07/output/staging.txt" || \
   ! grep -Fqx 'nbe-constant-nat-function-transports-reduced: 1' \
     "$evidence_dir/spike-t07/output/staging.txt"
then
  echo "TransportBase t01/t02/t07 did not exercise the expected transport/path rules" >&2
  exit 1
fi

printf 'scenario\tresult\ttreeless\tscheme\tfragment\n' \
  > "$evidence_dir/summary.tsv"
printf 't01\t7\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\n' \
  >> "$evidence_dir/summary.tsv"
printf 't02\t7\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\n' \
  >> "$evidence_dir/summary.tsv"
printf 't07\t4\tbaseline-equal\tbaseline-equal\tBYTE-IDENTICAL\n' \
  >> "$evidence_dir/summary.tsv"

echo "NbE adapter exact TransportBase PASS (t01/t02/t07 = 7/7/4)"
