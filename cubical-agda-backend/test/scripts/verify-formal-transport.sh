#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${CUBICAL29_DIR:?Set CUBICAL29_DIR to the pinned cubical source tree}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
transport_source="$backend_dir/test/fixtures/TransportTests.agda"
transport_sha256=8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b
formal_group=${FORMAL_TRANSPORT_GROUP:-base}
formal_engine=${FORMAL_TRANSPORT_ENGINE:-agda-baseline}
case "$formal_engine" in
  agda-baseline|nbe) ;;
  *)
    echo "Unknown FORMAL_TRANSPORT_ENGINE: $formal_engine (expected agda-baseline or nbe)" >&2
    exit 2
    ;;
esac
projection_evidence_path=
case "$formal_group" in
  base)
    transport_expectation=static
    fragment_mode=proof
    transport_module=TransportBase
    transport_scenarios='t01 t02 t07'
    transport_scenarios_csv='t01,t02,t07'
    transport_projection="$backend_dir/test/fixtures/transport/TransportBase.agda"
    transport_projection_sha256=109340fe11b48c742fb546ae1f506db7febbe882f9396f95c63c6a6123e7b543
    ;;
  glue)
    transport_expectation=static
    fragment_mode=proof
    transport_module=TransportGlue
    transport_scenarios='t03 t04 t08'
    transport_scenarios_csv='t03,t04,t08'
    transport_projection="$backend_dir/test/fixtures/transport/TransportGlue.agda"
    transport_projection_sha256=8b794b5d6d8423953386081cc6af921a6a2af343342bdfd6c0984ee1d9a04680
    ;;
  int)
    transport_expectation=static
    fragment_mode=proof
    transport_module=TransportInt
    transport_scenarios='t05 t06'
    transport_scenarios_csv='t05,t06'
    transport_projection="$backend_dir/test/fixtures/transport/TransportInt.agda"
    transport_projection_sha256=e3e03fb8fbd98f1f6f2c1e8467797815e80d4fdaa2f1684399793761f0ad6aab
    ;;
  core)
    transport_expectation=static
    fragment_mode=proof
    transport_module=TransportCoreB
    transport_scenarios='t09 t10'
    transport_scenarios_csv='t09,t10'
    transport_projection="$backend_dir/test/fixtures/transport/TransportCoreB.agda"
    transport_projection_sha256=e7d5339ff03e7153baf8b26a2178c8dc4c198b18144721e3a562a8153493c105
    ;;
  boundary)
    transport_expectation=residual
    fragment_mode=definition
    transport_module=TransportBoundary
    transport_scenarios='t11 t11b'
    transport_scenarios_csv='t11,t11b'
    transport_projection="$backend_dir/test/fixtures/transport/TransportBoundary.agda"
    transport_projection_sha256=a4a63ced26c47fe9de93b09ef98b0d7d28f15464bb7de71f523ceeae3b700588
    ;;
  hit)
    transport_expectation=static
    fragment_mode=proof
    transport_module=TransportHit
    transport_scenarios='t12 t13 t14 t15'
    transport_scenarios_csv='t12,t13,t14,t15'
    transport_projection="$backend_dir/test/fixtures/transport/TransportHit.agda"
    transport_projection_sha256=5939b8dace09ce5656660efda7f6afad76b05b3ebcc3b82c0de0a456c81f7a51
    ;;
  higher)
    transport_expectation=higher
    fragment_mode=definition
    transport_module=TransportHigher
    transport_scenarios='p16a p16b p16c'
    transport_scenarios_csv='p16a,p16b,p16c'
    transport_fragments='p16a p16b p16c c16a c16b c16c'
    transport_projection="$backend_dir/test/fixtures/transport/TransportHigher.agda"
    transport_projection_sha256=c7a1a45e12712c747746821230e3382de089916ba5a79e8c429f05dbbe7826aa
    ;;
  monolithic)
    transport_expectation=mixed
    fragment_mode=none
    transport_module=TransportTests
    transport_scenarios='t01 t02 t03 t04 t05 t06 t07 t08 t09 t10 t11 t11b t12 t13 t14 t15'
    transport_scenarios_csv='t01,t02,t03,t04,t05,t06,t07,t08,t09,t10,t11,t11b,t12,t13,t14,t15,p16a,p16b,p16c'
    transport_fragments=''
    transport_projection="$transport_source"
    transport_projection_sha256=$transport_sha256
    projection_evidence_path='test/fixtures/TransportTests.agda'
    ;;
  *)
    echo "Unknown FORMAL_TRANSPORT_GROUP: $formal_group (expected base, glue, int, core, boundary, hit, higher, or monolithic)" >&2
    exit 2
    ;;
esac
transport_fragments=${transport_fragments:-$transport_scenarios}
projection_evidence_path=${projection_evidence_path:-"test/fixtures/transport/$transport_module.agda"}
ghc29=${GHC29:-ghc}
cabal29=${CABAL29:-cabal}
chez_bin=${CHEZ_BIN:-chez}
formal_ghc_optimization=${FORMAL_GHC_OPTIMIZATION:-O0}
case "$formal_ghc_optimization" in
  O0) formal_build_suffix= ;;
  O2) formal_build_suffix=-release ;;
  *)
    echo "Invalid FORMAL_GHC_OPTIMIZATION: $formal_ghc_optimization (expected O0 or O2)" >&2
    exit 2
    ;;
esac
build_dir="$backend_dir/build/agda29"
binary="$build_dir/cubical-chez$formal_build_suffix"
formal_object_dir="$build_dir/ghc$formal_build_suffix"
formal_cpp_flags=''
formal_nbe_residual_option=''
formal_nbe_lock=${FORMAL_NBE_ADAPTER_LOCK:-"$backend_dir/config/nbe-adapter.lock.tsv"}
formal_nbe_source_identity=${FORMAL_NBE_SOURCE_IDENTITY:-"$backend_dir/config/nbe-adapter-source.identity.tsv"}
formal_nbe_provider=not-applicable
formal_nbe_lock_sha256=not-applicable
formal_nbe_source_manifest_sha256=not-applicable
formal_nbe_source_license_status=not-applicable
formal_nbe_source_selection_eligibility=not-applicable
if [ "$formal_engine" = agda-baseline ]; then
  evidence_root="$build_dir/formal-transport$formal_build_suffix"
else
  evidence_root="$build_dir/formal-transport-$formal_engine$formal_build_suffix"
  binary="$build_dir/cubical-chez-nbe-production-candidate$formal_build_suffix"
  formal_object_dir="$build_dir/ghc-nbe-production-candidate$formal_build_suffix"
  formal_cpp_flags='-DCUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE -DCUBICAL_CHEZ_NBE_PROVIDER_SELECTED'
  formal_nbe_residual_option='--cubical-chez-nbe-fallback=typed-residual'
fi
evidence_dir="$evidence_root/$formal_group"

ghc29_resolved=$(command -v "$ghc29" 2>/dev/null || true)
cabal29_resolved=$(command -v "$cabal29" 2>/dev/null || true)
chez_resolved=$(command -v "$chez_bin" 2>/dev/null || true)
if [ -z "$ghc29_resolved" ] || [ ! -x "$ghc29_resolved" ]; then
  echo "GHC29 is not executable: $ghc29" >&2
  exit 2
fi
if [ -z "$cabal29_resolved" ] || [ ! -x "$cabal29_resolved" ]; then
  echo "CABAL29 is not executable: $cabal29" >&2
  exit 2
fi
if { [ "$transport_expectation" = static ] || \
     [ "$transport_expectation" = mixed ]; } && \
   { [ -z "$chez_resolved" ] || [ ! -x "$chez_resolved" ]; }
then
  echo "Chez Scheme is not executable: $chez_bin" >&2
  exit 2
fi
if [ ! -f "$agda_source_dir/Agda.cabal" ] || \
   [ ! -f "$cubical_source_dir/cubical.agda-lib" ] || \
   [ ! -f "$transport_source" ] || \
   [ ! -f "$transport_projection" ]
then
  echo "Pinned Agda, cubical, or TransportTests source is unavailable" >&2
  exit 2
fi

actual_transport_sha256=$(shasum -a 256 "$transport_source" | awk '{ print $1 }')
actual_projection_sha256=$(shasum -a 256 "$transport_projection" | awk '{ print $1 }')
if [ "$actual_transport_sha256" != "$transport_sha256" ] || \
   [ "$actual_projection_sha256" != "$transport_projection_sha256" ]
then
  echo "TransportTests source or maintained projection SHA-256 mismatch" >&2
  exit 2
fi

write_manifest() {
  manifest_root=$1
  manifest_output=$2
  (
    CDPATH= cd -- "$manifest_root"
    find . -type f ! -path './.git/*' -print | LC_ALL=C sort |
      while IFS= read -r manifest_file
      do
        shasum -a 256 "$manifest_file"
      done
  ) > "$manifest_output"
}

mkdir -p "$formal_object_dir" "$evidence_dir"
if [ "$formal_engine" = nbe ]; then
  NBE_ADAPTER_SOURCE_IDENTITY="$formal_nbe_source_identity" \
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$evidence_dir/nbe-source-identity" \
    sh "$script_dir/verify-nbe-adapter-source-identity.sh" \
    > "$evidence_dir/nbe-source-identity.stdout" \
    2> "$evidence_dir/nbe-source-identity.stderr"
  sh "$script_dir/verify-nbe-adapter-lock.sh" "$formal_nbe_lock" \
    > "$evidence_dir/nbe-adapter-lock.stdout" \
    2> "$evidence_dir/nbe-adapter-lock.stderr"
  formal_nbe_status=$(awk -F '\t' '$1 == "status" { print $2; exit }' \
    "$formal_nbe_lock")
  formal_nbe_provider=$(awk -F '\t' '$1 == "provider" { print $2; exit }' \
    "$formal_nbe_lock")
  formal_nbe_integration=$(awk -F '\t' \
    '$1 == "integration" { print $2; exit }' "$formal_nbe_lock")
  if [ "$formal_nbe_status" != selected ] || \
     [ "$formal_nbe_provider" != agda-specific-in-process-v1 ] || \
     [ "$formal_nbe_integration" != in-process ]; then
    echo "Formal NbE candidate requires the selected in-process adapter lock" >&2
    exit 2
  fi
  formal_nbe_lock_sha256=$(shasum -a 256 "$formal_nbe_lock" | awk '{ print $1 }')
  formal_nbe_source_manifest_sha256=$(awk -F '\t' \
    '$1 == "source-manifest-sha256" { print $2; exit }' "$formal_nbe_source_identity")
  formal_nbe_source_license_status=$(awk -F '\t' \
    '$1 == "license-status" { print $2; exit }' "$formal_nbe_source_identity")
  formal_nbe_source_selection_eligibility=$(awk -F '\t' \
    '$1 == "selection-eligibility" { print $2; exit }' "$formal_nbe_source_identity")
fi
AGDA29_SOURCE_DIR="$agda_source_dir" \
  sh "$script_dir/verify-agda29-stock-baseline.sh" \
  > "$evidence_dir/stock-baseline.log"

cubical_manifest_before="$evidence_dir/cubical-source.before.sha256"
cubical_manifest_after="$evidence_dir/cubical-source.after.sha256"
cubical_agdai_before=$(find "$cubical_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
if [ "$cubical_agdai_before" -ne 0 ]; then
  echo "Supplied cubical source contains generated interfaces: $cubical_agdai_before" >&2
  exit 2
fi
write_manifest "$cubical_source_dir" "$cubical_manifest_before"

fragment_summary="$evidence_dir/fragments.tsv"
printf 'scenario\tfragment_sha256\tstatus\n' > "$fragment_summary"
extract_fragment() {
  fragment_scenario=$1
  fragment_input=$2
  fragment_output=$3
  case "$fragment_mode" in
    proof)
      awk -v target="$fragment_scenario" 'BEGIN { active=0 }
        $0 ~ "^" target " :" { active=1 }
        active {
          print
          if ($0 == "_ = refl") exit
        }
      ' "$fragment_input" > "$fragment_output"
      ;;
    definition)
      awk -v target="$fragment_scenario" 'BEGIN { active=0; body=0 }
        $0 ~ "^" target " :" { active=1 }
        active {
          if (body && $0 == "") exit
          print
          if ($0 ~ "^" target " [^:]*=") body=1
        }
      ' "$fragment_input" > "$fragment_output"
      ;;
    *)
      echo "Unknown fragment extraction mode: $fragment_mode" >&2
      exit 2
      ;;
  esac
}
if [ "$fragment_mode" = none ]; then
  printf '%s\t%s\tORIGINAL-HASH-PINNED\n' \
    "$transport_module" "$transport_sha256" >> "$fragment_summary"
else
  for scenario in $transport_fragments
  do
    original_fragment="$evidence_dir/$scenario.original.fragment.agda"
    projection_fragment="$evidence_dir/$scenario.projection.fragment.agda"
    extract_fragment "$scenario" "$transport_source" "$original_fragment"
    extract_fragment "$scenario" "$transport_projection" "$projection_fragment"
    if [ ! -s "$original_fragment" ] || \
       ! cmp -s "$original_fragment" "$projection_fragment"
    then
      echo "Maintained $scenario projection differs from the pinned original block" >&2
      diff -u "$original_fragment" "$projection_fragment" >&2 || true
      exit 2
    fi
    fragment_sha256=$(shasum -a 256 "$original_fragment" | awk '{ print $1 }')
    printf '%s\t%s\tBYTE-IDENTICAL\n' "$scenario" "$fragment_sha256" \
      >> "$fragment_summary"
  done
fi

workspace_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-formal-transport.XXXXXX")
workspace_cubical_dir="$workspace_dir/cubical"
workspace_input_dir="$workspace_dir/input"
library_file="$workspace_dir/libraries"
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
cp "$transport_projection" "$workspace_input_dir/$transport_module.agda"
printf '%s\n' "$workspace_cubical_dir/cubical.agda-lib" > "$library_file"
printf '%s  %s\n%s  %s\n' \
  "$transport_sha256" 'test/fixtures/TransportTests.agda' \
  "$transport_projection_sha256" "$projection_evidence_path" \
  > "$evidence_dir/source.sha256"

if [ "$transport_expectation" = mixed ]; then
  stock_agda=$(CDPATH= cd -- "$agda_source_dir" && \
    "$cabal29_resolved" list-bin -w "$ghc29_resolved" exe:agda)
  if [ ! -x "$stock_agda" ]; then
    echo "The pinned stock Agda executable is not available: $stock_agda" >&2
    exit 2
  fi
  cp "$backend_dir"/test/fixtures/transport/*.agda "$workspace_input_dir"
  prewarm_summary="$evidence_dir/prewarm.tsv"
  printf 'module\tstatus\treal_seconds\tmax_rss_bytes\n' > "$prewarm_summary"
  for prewarm_module in \
    TransportBase TransportGlue TransportInt TransportCoreB \
    TransportBoundary TransportHit TransportHigher TransportTests
  do
    prewarm_stdout="$evidence_dir/prewarm-$prewarm_module.stdout.log"
    prewarm_stderr="$evidence_dir/prewarm-$prewarm_module.stderr.log"
    echo "Prewarming exact monolithic gate with stock Agda: $prewarm_module"
    if ! /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
      "$stock_agda" \
        -v0 \
        --guardedness \
        --library-file="$library_file" \
        --no-default-libraries \
        -l cubical \
        -i "$workspace_input_dir" \
        "$workspace_input_dir/$prewarm_module.agda" \
        > "$prewarm_stdout" \
        2> "$prewarm_stderr"
    then
      echo "Stock Agda prewarm failed for $prewarm_module" >&2
      tail -n 200 "$prewarm_stdout" >&2
      tail -n 200 "$prewarm_stderr" >&2
      exit 1
    fi
    prewarm_real=$(awk '$2 == "real" { print $1; exit }' "$prewarm_stderr")
    prewarm_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$prewarm_stderr")
    printf '%s\tPASS\t%s\t%s\n' \
      "$prewarm_module" "$prewarm_real" "$prewarm_rss" >> "$prewarm_summary"
  done
fi

echo "Building the Agda 2.9 formal backend..."
if ! (CDPATH= cd -- "$agda_source_dir" && \
  /usr/bin/time -l "$cabal29_resolved" exec -w "$ghc29_resolved" -- \
    "$ghc29_resolved" \
      -"$formal_ghc_optimization" -Wall -Werror -rtsopts=some \
      -DCUBICAL_CHEZ_AGDA_29 \
      $formal_cpp_flags \
      -package Agda \
      -i"$backend_dir/src" \
      -outputdir "$formal_object_dir" \
      -o "$binary" \
      "$backend_dir/src/Main.hs" \
  > "$evidence_dir/build.stdout.log" \
  2> "$evidence_dir/build.stderr.log")
then
  echo "Formal backend build failed" >&2
  tail -n 160 "$evidence_dir/build.stderr.log" >&2
  exit 1
fi

summary_file="$evidence_dir/summary.tsv"
printf 'scenario\tentry\texpected\tactual\tstatus\treal_seconds\tmax_rss_bytes\n' \
  > "$summary_file"
binding_summary_file="$evidence_dir/binding-time.tsv"
printf 'scenario\tbinding_time\treason\taction\n' > "$binding_summary_file"
stage_timing_summary_file="$evidence_dir/stage-timings.tsv"
printf 'scenario\tstage\telapsed_seconds\tstatus\n' \
  > "$stage_timing_summary_file"
allocation_summary_file="$evidence_dir/allocations.tsv"
printf 'scenario\tallocated_bytes\tgc_copied_bytes\tmaximum_residency_bytes\tstatus\n' \
  > "$allocation_summary_file"

append_allocation_evidence() {
  allocation_scenario=$1
  allocation_stderr=$2
  allocated_bytes=$(awk '/bytes allocated in the heap/ {
    value=$1; gsub(/,/, "", value); print value; exit
  }' "$allocation_stderr")
  gc_copied_bytes=$(awk '/bytes copied during GC/ {
    value=$1; gsub(/,/, "", value); print value; exit
  }' "$allocation_stderr")
  maximum_residency_bytes=$(awk '/bytes maximum residency/ {
    value=$1; gsub(/,/, "", value); print value; exit
  }' "$allocation_stderr")
  if ! awk -v allocated="$allocated_bytes" -v copied="$gc_copied_bytes" \
    -v residency="$maximum_residency_bytes" 'BEGIN {
      exit !(allocated ~ /^[0-9]+$/ && allocated + 0 > 0 &&
        copied ~ /^[0-9]+$/ && residency ~ /^[0-9]+$/ &&
        residency + 0 > 0)
    }'
  then
    echo "Formal backend $allocation_scenario has malformed RTS allocation statistics" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\tMEASURED\n' \
    "$allocation_scenario" "$allocated_bytes" "$gc_copied_bytes" \
    "$maximum_residency_bytes" >> "$allocation_summary_file"
}

append_stage_timing_evidence() {
  timing_scenario=$1
  timing_output_dir=$2
  timing_process_seconds=$3
  timing_runtime_stage=$4
  timing_runtime_seconds=$5
  timing_file="$timing_output_dir/stage-timings.tsv"
  if [ ! -s "$timing_file" ] || ! awk -F '\t' '
    BEGIN {
      required["engine-total"]=1
      required["nbe-evaluation"]=1
      required["nbe-readback"]=1
      required["engine-result-admission"]=1
      required["internal-semantic-audit"]=1
      required["treeless-conversion"]=1
      required["residualization"]=1
      required["scheme-codegen-publication"]=1
    }
    NR == 1 {
      if ($0 != "stage\telapsed_nanoseconds\tstatus") exit 2
      next
    }
    NF != 3 || !required[$1] || seen[$1]++ { exit 3 }
    $3 == "measured" && $2 !~ /^[0-9]+$/ { exit 4 }
    $3 == "not-applicable" && $2 != "-" { exit 5 }
    $3 != "measured" && $3 != "not-applicable" { exit 6 }
    END {
      if (NR != 9) exit 7
      for (stage in required) if (!seen[stage]) exit 8
    }
  ' "$timing_file"
  then
    echo "$timing_scenario has invalid backend stage timing evidence" >&2
    exit 1
  fi

  awk -F '\t' -v scenario="$timing_scenario" 'NR > 1 {
    seconds = $2 == "-" ? "-" : sprintf("%.9f", $2 / 1000000000)
    print scenario "\t" $1 "\t" seconds "\t" $3
  }' "$timing_file" >> "$stage_timing_summary_file"

  measured_backend_nanoseconds=$(awk -F '\t' '
    $3 == "measured" &&
    ($1 == "engine-total" ||
     $1 == "engine-result-admission" ||
     $1 == "internal-semantic-audit" ||
     $1 == "treeless-conversion" ||
     $1 == "residualization" ||
     $1 == "scheme-codegen-publication") { total += $2 }
    END { printf "%.0f", total + 0 }
  ' "$timing_file")
  frontend_seconds=$(awk -v total="$timing_process_seconds" \
    -v backend_ns="$measured_backend_nanoseconds" 'BEGIN {
      remainder = total - backend_ns / 1000000000
      if (remainder < 0) remainder = 0
      printf "%.9f", remainder
    }')
  printf '%s\tagda-frontend-module-loading\t%s\tderived-remainder\n' \
    "$timing_scenario" "$frontend_seconds" >> "$stage_timing_summary_file"

  for runtime_stage in chez-execution typed-residual-consumer-execution
  do
    if [ "$runtime_stage" = "$timing_runtime_stage" ]; then
      printf '%s\t%s\t%s\tmeasured\n' \
        "$timing_scenario" "$runtime_stage" "$timing_runtime_seconds" \
        >> "$stage_timing_summary_file"
    else
      printf '%s\t%s\t-\tnot-applicable\n' \
        "$timing_scenario" "$runtime_stage" \
        >> "$stage_timing_summary_file"
    fi
  done
}

append_binding_evidence() {
  binding_scenario=$1
  binding_staging=$2
  binding_time=$(awk -F ': ' '$1 == "binding-time" { print $2; exit }' "$binding_staging")
  binding_reason=$(awk -F ': ' '$1 == "binding-time-reason" { print $2; exit }' "$binding_staging")
  binding_action=$(awk -F ': ' '$1 == "binding-time-action" { print $2; exit }' "$binding_staging")
  if [ -z "$binding_time" ] || [ -z "$binding_reason" ] || [ -z "$binding_action" ]; then
    echo "$binding_scenario is missing binding-time evidence" >&2
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\n' \
    "$binding_scenario" "$binding_time" "$binding_reason" "$binding_action" \
    >> "$binding_summary_file"
}

verify_formal_engine_provenance() {
  provenance_scenario=$1
  provenance_staging=$2
  if [ "$formal_engine" != nbe ]; then
    return
  fi
  if ! grep -Fqx 'engine-requested: nbe' "$provenance_staging" || \
     ! grep -Fqx 'engine-effective: nbe' "$provenance_staging" || \
     ! grep -Fqx 'nbe-adapter-status: production-candidate-selected' \
       "$provenance_staging" || \
     ! grep -Fqx 'nbe-adapter-production-readiness: candidate-not-accepted' \
       "$provenance_staging" || \
     ! grep -Fqx 'nbe-adapter-implementation: agda-specific-in-process-v1' \
       "$provenance_staging" || \
     ! grep -Fqx 'nbe-adapter-linkage: production-candidate' \
       "$provenance_staging" || \
     ! grep -Fqx 'nbe-provider-lock-status: selected-build-key' \
       "$provenance_staging" || \
     ! grep -Fqx 'engine-result-agda-checked: true' "$provenance_staging"
  then
    echo "$provenance_scenario is missing production-candidate provenance" >&2
    exit 1
  fi
}

verify_higher_packet_evidence() {
  higher_producer=$1
  higher_output_dir=$2
  higher_packet_destination=$3
  higher_entry="$transport_module.$higher_producer"
  if [ ! -f "$higher_output_dir/staging.txt" ] || \
     [ ! -f "$higher_output_dir/typed-residual.txt" ] || \
     ! grep -Fqx "requested-entry: $higher_entry" "$higher_output_dir/staging.txt" || \
     ! grep -Fqx "entry: $higher_entry" "$higher_output_dir/staging.txt" || \
     ! grep -Fqx "packet-destination: $higher_packet_destination" "$higher_output_dir/staging.txt" || \
     ! grep -Fqx 'binding-time: dynamic' "$higher_output_dir/staging.txt" || \
     ! grep -Fqx 'binding-time-action: typed-residual-whole-entry' "$higher_output_dir/staging.txt" || \
     ! grep -Fqx 'decision: typed-residual' "$higher_output_dir/staging.txt" || \
     ! grep -Fqx "entry: $higher_entry" "$higher_output_dir/typed-residual.txt" || \
     ! grep -Fqx 'artifact: packet-v2' "$higher_output_dir/typed-residual.txt" || \
     ! grep -Fqx 'packet-codec: agda-utils-serialize' "$higher_output_dir/typed-residual.txt" || \
     [ -e "$higher_output_dir/program.ss" ] || \
     [ -e "$higher_output_dir/typed-residual.bin" ]
  then
    echo "TransportTests.$higher_producer did not satisfy the typed packet contract" >&2
    exit 1
  fi
  if [ "$formal_engine" = agda-baseline ]; then
    if grep -Fqx 'internal-term-blockers: none' \
         "$higher_output_dir/staging.txt" || \
       grep -Fqx 'treeless-blockers: none' "$higher_output_dir/staging.txt"
    then
      echo "TransportTests.$higher_producer lost baseline packet blockers" >&2
      exit 1
    fi
  elif ! grep -Fqx \
    'nbe-unsupported-disposition: typed-residual-passthrough-v1' \
    "$higher_output_dir/staging.txt"
  then
    echo "TransportTests.$higher_producer lost NbE packet passthrough evidence" >&2
    exit 1
  fi
  verify_formal_engine_provenance \
    "$higher_producer" "$higher_output_dir/staging.txt"
}

emit_higher_packet() {
  higher_producer=$1
  higher_output_dir=$2
  higher_stderr_log=$3
  /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    "$binary" \
      +RTS -s -RTS \
      -v0 \
      --guardedness \
      --cubical-chez \
      --cubical-chez-engine="$formal_engine" \
      $formal_nbe_residual_option \
      --cubical-chez-residual=packet \
      --cubical-chez-packet-file=- \
      --cubical-chez-entry="$transport_module.$higher_producer" \
      --cubical-chez-output="$higher_output_dir" \
      --library-file="$library_file" \
      --no-default-libraries \
      -l cubical \
      -i "$workspace_input_dir" \
      "$workspace_input_dir/$transport_module.agda" \
      2> "$higher_stderr_log"
}

consume_higher_packet() {
  higher_consumer=$1
  higher_packet_file=$2
  /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    "$runtime_runner" \
      -v0 \
      --guardedness \
      --cubical-import="$higher_consumer" \
      --cubical-term-file="$higher_packet_file" \
      --library-file="$library_file" \
      --no-default-libraries \
      -l cubical \
      -i "$workspace_input_dir" \
      "$workspace_input_dir/$transport_module.agda"
}

run_higher_protocol() {
  runtime_runner=$(CDPATH= cd -- "$agda_source_dir" && \
    "$cabal29_resolved" list-bin -w "$ghc29_resolved" exe:agda-cubical-run)
  if [ ! -x "$runtime_runner" ]; then
    (CDPATH= cd -- "$agda_source_dir" && \
      "$cabal29_resolved" build -w "$ghc29_resolved" exe:agda-cubical-run)
    runtime_runner=$(CDPATH= cd -- "$agda_source_dir" && \
      "$cabal29_resolved" list-bin -w "$ghc29_resolved" exe:agda-cubical-run)
  fi
  if [ ! -x "$runtime_runner" ]; then
    echo "The archived v2 consumer is not executable" >&2
    exit 2
  fi

  file_case_dir="$evidence_dir/p16a-file"
  file_output_dir="$file_case_dir/output"
  file_packet="$file_case_dir/typed-term.bin"
  file_stdout="$file_case_dir/producer.stdout.log"
  file_stderr="$file_case_dir/producer.stderr.log"
  file_consumer_stderr="$file_case_dir/consumer.stderr.log"
  mkdir -p "$file_output_dir"
  rm -f "$file_packet" "$file_output_dir/program.ss" \
    "$file_output_dir/treeless.txt" "$file_output_dir/staging.txt" \
    "$file_output_dir/typed-residual.txt" "$file_output_dir/typed-residual.bin"
  echo "Formal backend $transport_module.p16a -> c16a (file packet)"
  set +e
  /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    "$binary" \
      +RTS -s -RTS \
      -v0 \
      --guardedness \
      --cubical-chez \
      --cubical-chez-engine="$formal_engine" \
      $formal_nbe_residual_option \
      --cubical-chez-residual=packet \
      --cubical-chez-packet-file="$file_packet" \
      --cubical-chez-entry="$transport_module.p16a" \
      --cubical-chez-output="$file_output_dir" \
      --library-file="$library_file" \
      --no-default-libraries \
      -l cubical \
      -i "$workspace_input_dir" \
      "$workspace_input_dir/$transport_module.agda" \
      > "$file_stdout" \
      2> "$file_stderr"
  file_producer_status=$?
  set -e
  if [ "$file_producer_status" -ne 0 ] || [ ! -s "$file_packet" ]; then
    echo "$transport_module.p16a file packet production failed" >&2
    tail -n 200 "$file_stdout" >&2
    tail -n 200 "$file_stderr" >&2
    exit 1
  fi
  verify_higher_packet_evidence p16a "$file_output_dir" "$file_packet"
  set +e
  file_actual=$(consume_higher_packet c16a "$file_packet" 2> "$file_consumer_stderr")
  file_consumer_status=$?
  set -e
  if [ "$file_consumer_status" -ne 0 ] || [ "$file_actual" != true ]; then
    echo "$transport_module.p16a -> c16a file packet did not produce true" >&2
    tail -n 200 "$file_consumer_stderr" >&2
    exit 1
  fi
  file_real=$(awk '$2 == "real" { print $1; exit }' "$file_stderr")
  file_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$file_stderr")
  file_consumer_real=$(awk '$2 == "real" { print $1; exit }' \
    "$file_consumer_stderr")
  append_allocation_evidence p16a-file "$file_stderr"
  file_packet_size=$(wc -c < "$file_packet" | tr -d ' ')
  file_packet_sha256=$(shasum -a 256 "$file_packet" | awk '{ print $1 }')
  printf 'p16a-file\t%s.p16a -> c16a\ttrue\t%s\tPASS\t%s\t%s\n' \
    "$transport_module" "$file_actual" "$file_real" "$file_rss" >> "$summary_file"
  append_binding_evidence p16a-file "$file_output_dir/staging.txt"
  append_stage_timing_evidence p16a-file "$file_output_dir" \
    "$file_real" typed-residual-consumer-execution "$file_consumer_real"
  printf 'channel\tproducer\tconsumer\tbytes\tsha256\nfile\tp16a\tc16a\t%s\t%s\n' \
    "$file_packet_size" "$file_packet_sha256" > "$evidence_dir/packets.tsv"

  for higher_producer in p16a p16b p16c
  do
    case "$higher_producer" in
      p16a)
        higher_consumer=c16a
        higher_expected=true
        ;;
      p16b)
        higher_consumer=c16b
        higher_expected='pos 2'
        ;;
      p16c)
        higher_consumer=c16c
        higher_expected='pos 2'
        ;;
    esac
    pipe_case_dir="$evidence_dir/$higher_producer-pipe"
    pipe_output_dir="$pipe_case_dir/output"
    pipe_producer_stderr="$pipe_case_dir/producer.stderr.log"
    pipe_consumer_stderr="$pipe_case_dir/consumer.stderr.log"
    mkdir -p "$pipe_output_dir"
    rm -f "$pipe_output_dir/program.ss" "$pipe_output_dir/treeless.txt" \
      "$pipe_output_dir/staging.txt" "$pipe_output_dir/typed-residual.txt" \
      "$pipe_output_dir/typed-residual.bin"
    echo "Formal backend $transport_module.$higher_producer -> $higher_consumer (pipe packet)"
    set +e
    pipe_actual=$(emit_higher_packet \
      "$higher_producer" "$pipe_output_dir" "$pipe_producer_stderr" | \
      consume_higher_packet "$higher_consumer" - \
        2> "$pipe_consumer_stderr")
    pipe_status=$?
    set -e
    if [ "$pipe_status" -ne 0 ] || [ "$pipe_actual" != "$higher_expected" ]; then
      echo "$transport_module.$higher_producer -> $higher_consumer pipe failed" >&2
      tail -n 200 "$pipe_producer_stderr" >&2
      tail -n 200 "$pipe_consumer_stderr" >&2
      exit 1
    fi
    verify_higher_packet_evidence "$higher_producer" "$pipe_output_dir" stdout
    pipe_real=$(awk '$2 == "real" { print $1; exit }' "$pipe_producer_stderr")
    pipe_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$pipe_producer_stderr")
    pipe_consumer_real=$(awk '$2 == "real" { print $1; exit }' \
      "$pipe_consumer_stderr")
    append_allocation_evidence "$higher_producer-pipe" \
      "$pipe_producer_stderr"
    printf '%s-pipe\t%s.%s -> %s\t%s\t%s\tPASS\t%s\t%s\n' \
      "$higher_producer" "$transport_module" "$higher_producer" "$higher_consumer" \
      "$higher_expected" "$pipe_actual" "$pipe_real" "$pipe_rss" \
      >> "$summary_file"
    append_binding_evidence "$higher_producer-pipe" "$pipe_output_dir/staging.txt"
    append_stage_timing_evidence "$higher_producer-pipe" "$pipe_output_dir" \
      "$pipe_real" typed-residual-consumer-execution \
      "$pipe_consumer_real"
  done

  wrong_stdout="$file_case_dir/wrong-consumer.stdout.log"
  wrong_stderr="$file_case_dir/wrong-consumer.stderr.log"
  set +e
  consume_higher_packet c16b "$file_packet" \
    > "$wrong_stdout" 2> "$wrong_stderr"
  wrong_status=$?
  set -e
  if [ "$wrong_status" -eq 0 ] || \
     ! grep -q 'UnequalTypes' "$wrong_stdout" "$wrong_stderr"
  then
    echo "$transport_module.p16a -> c16b was not rejected by type" >&2
    exit 1
  fi
  printf 'p16a-wrong\t%s.p16a -> c16b\tUnequalTypes\tUnequalTypes\tEXPECTED-REJECT\t-\t-\n' \
    "$transport_module" >> "$summary_file"
  append_binding_evidence p16a-wrong "$file_output_dir/staging.txt"
}

if [ "$transport_expectation" = higher ]; then
  run_higher_protocol
else
for scenario in $transport_scenarios
do
  scenario_expectation=$transport_expectation
  if [ "$transport_expectation" = mixed ]; then
    case "$scenario" in
      t11|t11b) scenario_expectation=residual ;;
      *) scenario_expectation=static ;;
    esac
  fi
  case "$scenario" in
    t01|t02)
      expected=7
      expected_treeless='  TLit(LitNat 7)'
      expected_scheme=7
      ;;
    t07)
      expected=4
      expected_treeless='  TLit(LitNat 4)'
      expected_scheme=4
      ;;
    t03|t08)
      expected=false
      expected_treeless='  TCon(Agda.Builtin.Bool.Bool.false)'
      expected_scheme='#(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false)'
      ;;
    t04|t15)
      expected=true
      expected_treeless='  TCon(Agda.Builtin.Bool.Bool.true)'
      expected_scheme='#(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true)'
      ;;
    t05|t13)
      expected='pos 1'
      expected_treeless='  TApp(TCon(Cubical.Data.Int.Base.ℤ.pos), [TLit(LitNat 1)])'
      expected_scheme='#(agda_Cubical_2e_Data_2e_Int_2e_Base_2e_ℤ_2e_pos 1)'
      ;;
    t12)
      expected='pos 2'
      expected_treeless='  TApp(TCon(Cubical.Data.Int.Base.ℤ.pos), [TLit(LitNat 2)])'
      expected_scheme='#(agda_Cubical_2e_Data_2e_Int_2e_Base_2e_ℤ_2e_pos 2)'
      ;;
    t06)
      expected='negsuc 0'
      expected_treeless='  TApp(TCon(Cubical.Data.Int.Base.ℤ.negsuc), [TLit(LitNat 0)])'
      expected_scheme='#(agda_Cubical_2e_Data_2e_Int_2e_Base_2e_ℤ_2e_negsuc 0)'
      ;;
    t09)
      expected='(false, 3)'
      expected_treeless='  TApp(TCon(Agda.Builtin.Sigma._,_), [TCon(Agda.Builtin.Bool.Bool.false), TLit(LitNat 3)])'
      expected_scheme='#(agda_Agda_2e_Builtin_2e_Sigma_2e__5f__2c__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) 3)'
      ;;
    t10)
      expected='false ∷ true ∷ false ∷ []'
      expected_treeless='  TApp(TCon(Agda.Builtin.List.List._∷_), [TCon(Agda.Builtin.Bool.Bool.false), TApp(TCon(Agda.Builtin.List.List._∷_), [TCon(Agda.Builtin.Bool.Bool.true), TApp(TCon(Agda.Builtin.List.List._∷_), [TCon(Agda.Builtin.Bool.Bool.false), TCon(Agda.Builtin.List.List.[])])])])'
      expected_scheme='#(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_true) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5f__2237__5f_ #(agda_Agda_2e_Builtin_2e_Bool_2e_Bool_2e_false) #(agda_Agda_2e_Builtin_2e_List_2e_List_2e__5b__5d_))))'
      ;;
    t11|t11b)
      expected='typed residual'
      ;;
    t14)
      expected=41
      expected_treeless='  TLit(LitNat 41)'
      expected_scheme=41
      ;;
    *)
      echo "No formal expectation is defined for $scenario" >&2
      exit 2
      ;;
  esac
  entry="$transport_module.$scenario"
  case_dir="$evidence_dir/$scenario"
  output_dir="$case_dir/output"
  stdout_log="$case_dir/agda.stdout.log"
  stderr_log="$case_dir/agda.stderr.log"
  mkdir -p "$output_dir"
  rm -f "$output_dir/program.ss" "$output_dir/treeless.txt" \
    "$output_dir/staging.txt" "$output_dir/typed-residual.txt" \
    "$output_dir/typed-residual.bin"

  if [ "$transport_expectation" = mixed ]; then
    echo "Formal backend $entry (pinned original monolithic source)"
  else
    echo "Formal backend $entry (exact TransportTests $scenario projection)"
  fi
  set -- "$binary" +RTS -s -RTS \
      -v0 \
      --guardedness \
      --cubical-chez \
      --cubical-chez-engine="$formal_engine" \
      $formal_nbe_residual_option \
      --cubical-chez-entry="$entry" \
      --cubical-chez-output="$output_dir"
  if [ "$scenario_expectation" = residual ]; then
    set -- "$@" --cubical-chez-residual=manifest
  fi
  set -- "$@" \
      --library-file="$library_file" \
      --no-default-libraries \
      -l cubical \
      -i "$workspace_input_dir" \
      "$workspace_input_dir/$transport_module.agda"
  set +e
  /usr/bin/time -l env Agda_datadir="$agda_source_dir/src/data" \
    "$@" \
      > "$stdout_log" \
      2> "$stderr_log"
  backend_status=$?
  set -e

  real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  append_allocation_evidence "$scenario" "$stderr_log"
  if [ "$scenario_expectation" = residual ]; then
    if [ "$backend_status" -eq 0 ]; then
      echo "Formal backend $entry unexpectedly erased a typed residual" >&2
      exit 1
    fi
    if [ ! -f "$output_dir/staging.txt" ] || \
       [ ! -f "$output_dir/typed-residual.txt" ] || \
       ! grep -Fqx "requested-entry: $entry" "$output_dir/staging.txt" || \
       ! grep -Fqx "entry: $entry" "$output_dir/staging.txt" || \
       ! grep -Fqx 'binding-time: dynamic' "$output_dir/staging.txt" || \
       ! grep -Fqx 'binding-time-action: typed-residual-whole-entry' "$output_dir/staging.txt" || \
       ! grep -Fqx 'decision: typed-residual' "$output_dir/staging.txt" || \
       ! grep -Fqx "entry: $entry" "$output_dir/typed-residual.txt" || \
       ! grep -Fqx 'artifact: manifest-only' "$output_dir/typed-residual.txt" || \
       ! grep -Fq 'CCZ-RESIDUAL-REQUIRED' "$stdout_log"
    then
      echo "TransportTests.$scenario did not preserve the expected typed residual contract" >&2
      tail -n 200 "$stdout_log" >&2
      tail -n 200 "$stderr_log" >&2
      exit 1
    fi
    if [ "$formal_engine" = agda-baseline ]; then
      if ! grep -E -q '^internal-term-blockers: .*transpX-Vec' \
           "$output_dir/staging.txt" || \
         ! grep -E -q '^treeless-blockers: .*transpX-Vec' \
           "$output_dir/staging.txt" || \
         ! grep -E -q '^blockers: .*transpX-Vec' \
           "$output_dir/typed-residual.txt" || \
         ! awk 'previous == "term:" && /transpX-Vec/ { found=1 }
           { previous=$0 }
           END { if (!found) exit 1 }
         ' "$output_dir/typed-residual.txt" || \
         ! grep -Fq 'transpX-Vec' "$stdout_log"
      then
        echo "TransportTests.$scenario lost the baseline transpX-Vec residual" >&2
        exit 1
      fi
    else
      if ! grep -Fqx \
           'nbe-unsupported-disposition: typed-residual-passthrough-v1' \
           "$output_dir/staging.txt"
      then
        echo "TransportTests.$scenario lost the NbE typed-residual passthrough" >&2
        exit 1
      fi
    fi
    if [ -e "$output_dir/program.ss" ] || \
       [ -e "$output_dir/typed-residual.bin" ]
    then
      echo "TransportTests.$scenario published an executable residual artifact" >&2
      exit 1
    fi
    printf '%s\t%s\t%s\t%s\tEXPECTED-RESIDUAL\t%s\t%s\n' \
      "$scenario" "$entry" "$expected" 'typed residual' \
      "$real_seconds" "$max_rss" >> "$summary_file"
    verify_formal_engine_provenance "$scenario" "$output_dir/staging.txt"
    append_binding_evidence "$scenario" "$output_dir/staging.txt"
    append_stage_timing_evidence "$scenario" "$output_dir" \
      "$real_seconds" none -
    continue
  fi

  if [ "$backend_status" -ne 0 ]; then
    echo "Formal backend $entry failed" >&2
    tail -n 200 "$stdout_log" >&2
    tail -n 200 "$stderr_log" >&2
    exit 1
  fi

  chez_stdout="$case_dir/chez.stdout.log"
  chez_stderr="$case_dir/chez.stderr.log"
  set +e
  /usr/bin/time -l "$chez_resolved" --script "$output_dir/program.ss" \
    > "$chez_stdout" 2> "$chez_stderr"
  chez_status=$?
  set -e
  actual=$(sed -n '1p' "$chez_stdout")
  chez_real_seconds=$(awk '$2 == "real" { print $1; exit }' "$chez_stderr")
  if [ "$chez_status" -ne 0 ] || [ -z "$chez_real_seconds" ]; then
    echo "TransportTests.$scenario Chez execution timing failed" >&2
    tail -n 80 "$chez_stderr" >&2
    exit 1
  fi
  if [ "$actual" != "$expected_scheme" ]; then
    echo "TransportTests.$scenario projection expected $expected_scheme, got $actual" >&2
    exit 1
  fi
  if ! grep -Fqx "$expected_treeless" "$output_dir/treeless.txt"; then
    echo "TransportTests.$scenario did not read back to $expected_treeless" >&2
    exit 1
  fi
  if ! grep -q "^requested-entry: $entry$" "$output_dir/staging.txt" || \
     ! grep -q "^entry: $entry$" "$output_dir/staging.txt" || \
     ! grep -q '^binding-time: static$' "$output_dir/staging.txt" || \
     ! grep -q '^binding-time-action: erase-types-and-emit$' "$output_dir/staging.txt" || \
     ! grep -q '^decision: static-closed$' "$output_dir/staging.txt" || \
     ! grep -q '^internal-term-blockers: none$' "$output_dir/staging.txt" || \
     ! grep -q '^treeless-blockers: none$' "$output_dir/staging.txt"
  then
    echo "TransportTests.$scenario projection did not satisfy the static admission contract" >&2
    exit 1
  fi
  verify_formal_engine_provenance "$scenario" "$output_dir/staging.txt"
  if grep -E -q 'primTransp|primHComp|primGlue|transpX-|typed-residual|TCState' \
       "$output_dir/program.ss" "$output_dir/treeless.txt" || \
     [ -e "$output_dir/typed-residual.txt" ] || \
     [ -e "$output_dir/typed-residual.bin" ]
  then
    echo "TransportTests.$scenario projection retained a typed/Cubical runtime artifact" >&2
    exit 1
  fi

  printf '%s\t%s\t%s\t%s\tPASS\t%s\t%s\n' \
    "$scenario" "$entry" "$expected" "$actual" "$real_seconds" "$max_rss" \
    >> "$summary_file"
  append_binding_evidence "$scenario" "$output_dir/staging.txt"
  append_stage_timing_evidence "$scenario" "$output_dir" \
    "$real_seconds" chez-execution "$chez_real_seconds"
done
if [ "$transport_expectation" = mixed ]; then
  run_higher_protocol
fi
fi

summary_rows=$(awk 'NR > 1 { count++ } END { print count + 0 }' "$summary_file")
binding_rows=$(awk -F '\t' '
  NR == 1 {
    if ($0 != "scenario\tbinding_time\treason\taction") exit 2
    next
  }
  NF != 4 || seen[$1]++ { exit 3 }
  $2 != "static" && $2 != "dynamic" && $2 != "mixed" && $2 != "unsupported" { exit 4 }
  { count++ }
  END { print count + 0 }
' "$binding_summary_file")
if [ "$binding_rows" -ne "$summary_rows" ]; then
  echo "Binding-time evidence rows do not match the formal summary" >&2
  exit 1
fi
timed_summary_rows=$(awk -F '\t' 'NR > 1 && $6 != "-" { count++ }
  END { print count + 0 }' "$summary_file")
stage_timing_scenarios=$(awk -F '\t' '
  NR == 1 {
    if ($0 != "scenario\tstage\telapsed_seconds\tstatus") exit 2
    next
  }
  NF != 4 || seen[$1 FS $2]++ { exit 3 }
  $4 == "measured" && $3 !~ /^[0-9]+([.][0-9]+)?$/ { exit 4 }
  $4 == "derived-remainder" && $3 !~ /^[0-9]+([.][0-9]+)?$/ { exit 5 }
  $4 == "not-applicable" && $3 != "-" { exit 6 }
  $4 != "measured" && $4 != "derived-remainder" &&
    $4 != "not-applicable" { exit 7 }
  { rows[$1]++ }
  END {
    for (scenario in rows) {
      if (rows[scenario] != 11) exit 8
      scenarios++
    }
    print scenarios + 0
  }
' "$stage_timing_summary_file") || {
  echo "Formal stage timing evidence is malformed" >&2
  exit 1
}
if [ "$stage_timing_scenarios" -ne "$timed_summary_rows" ]; then
  echo "Stage timing evidence does not cover every timed formal scenario" >&2
  exit 1
fi
allocation_scenarios=$(awk -F '\t' '
  NR == 1 {
    if ($0 != "scenario\tallocated_bytes\tgc_copied_bytes\tmaximum_residency_bytes\tstatus") exit 2
    next
  }
  NF != 5 || seen[$1]++ || $2 !~ /^[0-9]+$/ || $2 + 0 <= 0 ||
    $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $4 + 0 <= 0 ||
    $5 != "MEASURED" { exit 3 }
  { count++ }
  END { print count + 0 }
' "$allocation_summary_file") || {
  echo "Formal allocation evidence is malformed" >&2
  exit 1
}
if [ "$allocation_scenarios" -ne "$timed_summary_rows" ]; then
  echo "Allocation evidence does not cover every timed formal scenario" >&2
  exit 1
fi
timed_allocation_scenarios="$workspace_dir/timed-allocation-scenarios"
reported_allocation_scenarios="$workspace_dir/reported-allocation-scenarios"
awk -F '\t' 'NR > 1 && $6 != "-" { print $1 }' "$summary_file" | \
  LC_ALL=C sort > "$timed_allocation_scenarios"
awk -F '\t' 'NR > 1 { print $1 }' "$allocation_summary_file" | \
  LC_ALL=C sort > "$reported_allocation_scenarios"
if ! cmp -s "$timed_allocation_scenarios" \
  "$reported_allocation_scenarios"; then
  echo "Allocation evidence scenarios do not match timed formal scenarios" >&2
  exit 1
fi

write_manifest "$cubical_source_dir" "$cubical_manifest_after"
cubical_agdai_after=$(find "$cubical_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
if ! cmp -s "$cubical_manifest_before" "$cubical_manifest_after" || \
   [ "$cubical_agdai_after" -ne 0 ] || \
   [ "$(shasum -a 256 "$transport_source" | awk '{ print $1 }')" != "$transport_sha256" ] || \
   [ "$(shasum -a 256 "$transport_projection" | awk '{ print $1 }')" != "$transport_projection_sha256" ]
then
  echo "A supplied TransportTests or cubical source changed during verification" >&2
  exit 2
fi

workspace_interface_count=$(find "$workspace_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
printf 'backend-bin\t%s\nghc-bin\t%s\ncabal-bin\t%s\nchez-bin\t%s\nengine\t%s\nghc-optimization\t%s\nnbe-provider\t%s\nnbe-lock-sha256\t%s\nnbe-source-manifest-sha256\t%s\nnbe-source-license-status\t%s\nnbe-source-selection-eligibility\t%s\nsource-sha256\t%s\nprojection-sha256\t%s\ncubical-source-dir\t%s\nscenarios\t%s\nexpectation\t%s\nworkspace-interface-count\t%s\n' \
  "$binary" "$ghc29_resolved" "$cabal29_resolved" "${chez_resolved:-not-required}" \
  "$formal_engine" "$formal_ghc_optimization" "$formal_nbe_provider" \
  "$formal_nbe_lock_sha256" \
  "$formal_nbe_source_manifest_sha256" "$formal_nbe_source_license_status" \
  "$formal_nbe_source_selection_eligibility" \
  "$transport_sha256" "$transport_projection_sha256" "$cubical_source_dir" \
  "$transport_scenarios_csv" "$transport_expectation" "$workspace_interface_count" \
  > "$evidence_dir/invocation.tsv"

echo "Formal backend TransportTests $formal_group/$formal_engine expectations PASS ($transport_scenarios_csv)"
echo "Evidence: $summary_file"
