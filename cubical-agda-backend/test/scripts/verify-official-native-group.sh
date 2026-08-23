#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${OFFICIAL_NATIVE_GROUP:?Set OFFICIAL_NATIVE_GROUP to source-checks, common, coverage-checks, interaction-custom, std-lib-interaction, examples, cubical-test, benchmark-without-logs, std-lib-test, api-test, or doc-test}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
ghc29=${GHC29:-ghc}
cabal29=${CABAL29:-cabal}
fdebug_dist="$backend_dir/build/agda29/official-compiler/fdebug-dist"
interaction_compat=${OFFICIAL_NATIVE_INTERACTION_COMPAT:-0}
doctest_compat=${OFFICIAL_NATIVE_DOCTEST_COMPAT:-0}
exclude_stem=${OFFICIAL_NATIVE_EXCLUDE_STEM:-}
cubical_source_dir=
stdlib_source_dir=
stdlib_identity_file="$backend_dir/test/fixtures/agda29-stdlib.identity.tsv"

ghc29_resolved=$(command -v "$ghc29" 2>/dev/null || true)
if [ -z "$ghc29_resolved" ] || [ ! -x "$ghc29_resolved" ]; then
  echo "GHC29 is not executable: $ghc29" >&2
  exit 2
fi

case "$OFFICIAL_NATIVE_GROUP" in
  source-checks)
    group_name=SourceChecks
    upstream_targets='check-encoding check-mdo'
    expected_items=2
    item_kind=upstream-targets
    ;;
  common)
    group_name=Common
    upstream_targets=common
    expected_items=24
    item_kind=Agda-modules
    ;;
  coverage-checks)
    group_name=CoverageChecks
    upstream_targets='test-suite-covers-errors test-suite-covers-warnings user-manual-covers-options user-manual-covers-warnings'
    expected_items=4
    item_kind=upstream-targets
    ;;
  interaction-custom)
    group_name=InteractionCustom
    upstream_targets=interaction-custom
    expected_items=59
    item_kind=golden-tests
    ;;
  std-lib-interaction)
    group_name=StdLibInteraction
    upstream_targets=std-lib-interaction
    expected_items=3
    item_kind=golden-tests
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    ;;
  examples)
    group_name=Examples
    upstream_targets=examples
    expected_items=44
    item_kind=example-checks
    ;;
  cubical-test)
    group_name=CubicalLibrary
    upstream_targets=cubical-test
    expected_items=1192
    item_kind=Agda-modules
    : "${CUBICAL29_DIR:?Set CUBICAL29_DIR to the pinned cubical library source tree}"
    cubical_source_dir=$(CDPATH= cd -- "$CUBICAL29_DIR" && pwd -P)
    if [ ! -f "$cubical_source_dir/cubical.agda-lib" ] || \
       [ ! -f "$cubical_source_dir/GNUmakefile" ]
    then
      echo "CUBICAL29_DIR is not a cubical library source tree: $cubical_source_dir" >&2
      exit 2
    fi
    ;;
  benchmark-without-logs)
    group_name=BenchmarkWithoutLogs
    upstream_targets=benchmark-without-logs
    expected_items=18
    item_kind=benchmark-cases
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    ;;
  std-lib-test)
    group_name=StandardLibrary
    upstream_targets=std-lib-test
    expected_items=1059
    expected_safe_items=952
    expected_interfaces=1091
    expected_everything_interface=0
    expected_source_items=1182
    item_kind=Everything-imports
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_source_dir/agda-stdlib-utils.cabal" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    ;;
  api-test)
    group_name=ApiTest
    upstream_targets=api-test
    expected_items=4
    item_kind=API-tests
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_source_dir/src/Data/List/Relation/Unary/Any.agda" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    ;;
  doc-test)
    group_name=DocTest
    upstream_targets=doc-test
    expected_items=5
    expected_modules=3
    expected_examples=5
    item_kind=doctest-directives
    ;;
  *)
    echo "Unsupported OFFICIAL_NATIVE_GROUP: $OFFICIAL_NATIVE_GROUP" >&2
    echo "Use: source-checks, common, coverage-checks, interaction-custom, std-lib-interaction, examples, cubical-test, benchmark-without-logs, std-lib-test, api-test, or doc-test." >&2
    exit 2
    ;;
esac
run_items=$expected_items

case "$interaction_compat" in
  0|1) ;;
  *)
    echo "OFFICIAL_NATIVE_INTERACTION_COMPAT must be 0 or 1" >&2
    exit 2
    ;;
esac
case "$doctest_compat" in
  0|1) ;;
  *)
    echo "OFFICIAL_NATIVE_DOCTEST_COMPAT must be 0 or 1" >&2
    exit 2
    ;;
esac
if [ "$doctest_compat" -eq 1 ] && [ "$OFFICIAL_NATIVE_GROUP" != doc-test ]; then
  echo "Native doctest compatibility is only valid for doc-test" >&2
  exit 2
fi
if [ "$interaction_compat" -eq 1 ] && \
   [ "$OFFICIAL_NATIVE_GROUP" != interaction-custom ] && \
   [ "$OFFICIAL_NATIVE_GROUP" != std-lib-interaction ]
then
  echo "Native interaction compatibility is only valid for interaction-custom or std-lib-interaction" >&2
  exit 2
fi
case "$exclude_stem" in
  '') ;;
  Issue8634)
    if [ "$OFFICIAL_NATIVE_GROUP" != interaction-custom ]; then
      echo "Native exclusions are only valid for interaction-custom" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unsupported diagnostic native exclusion: $exclude_stem" >&2
    echo "Use only the classified Issue8634 exclusion." >&2
    exit 2
    ;;
esac

if [ "$OFFICIAL_NATIVE_GROUP" = source-checks ] && \
   ! command -v iconv >/dev/null 2>&1
then
  echo "iconv is required by the upstream check-encoding target" >&2
  exit 2
fi

cabal29_resolved=
if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = api-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]
then
  cabal29_resolved=$(command -v "$cabal29" 2>/dev/null || true)
  if [ -z "$cabal29_resolved" ] || [ ! -x "$cabal29_resolved" ]; then
    echo "cabal is required by the native group: $cabal29" >&2
    exit 2
  fi
fi

evidence_dir="$backend_dir/build/agda29/official-native/$OFFICIAL_NATIVE_GROUP"
mkdir -p "$evidence_dir"
AGDA29_SOURCE_DIR="$agda_source_dir" \
  sh "$script_dir/verify-agda29-stock-baseline.sh" \
  > "$evidence_dir/stock-baseline.log"

write_source_manifest() {
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

verify_cubical_source_unchanged() {
  if [ "$OFFICIAL_NATIVE_GROUP" != cubical-test ]; then
    return
  fi
  cubical_manifest_after="$evidence_dir/cubical-source.after.sha256"
  write_source_manifest "$cubical_source_dir" "$cubical_manifest_after"
  if ! cmp -s "$cubical_manifest_before" "$cubical_manifest_after"; then
    echo "Supplied cubical source tree changed during the isolated run" >&2
    diff -u "$cubical_manifest_before" "$cubical_manifest_after" >&2 || true
    exit 2
  fi
  cubical_agdai_after=$(find "$cubical_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
  if [ "$cubical_agdai_after" -ne 0 ]; then
    echo "Supplied cubical source tree contains generated .agdai files after the run: $cubical_agdai_after" >&2
    exit 2
  fi
}

if [ "$OFFICIAL_NATIVE_GROUP" = cubical-test ]; then
  cubical_manifest_before="$evidence_dir/cubical-source.before.sha256"
  cubical_agdai_before=$(find "$cubical_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
  if [ "$cubical_agdai_before" -ne 0 ]; then
    echo "Supplied cubical source tree is contaminated with .agdai files: $cubical_agdai_before" >&2
    exit 2
  fi
  write_source_manifest "$cubical_source_dir" "$cubical_manifest_before"
fi

verify_stdlib_source_unchanged() {
  case "$OFFICIAL_NATIVE_GROUP" in
    benchmark-without-logs|std-lib-test|api-test|std-lib-interaction) ;;
    *) return ;;
  esac
  stdlib_manifest_after="$evidence_dir/stdlib-source.after.sha256"
  write_source_manifest "$stdlib_source_dir" "$stdlib_manifest_after"
  if ! cmp -s "$stdlib_manifest_before" "$stdlib_manifest_after"; then
    echo "Supplied std-lib source tree changed during the isolated run" >&2
    diff -u "$stdlib_manifest_before" "$stdlib_manifest_after" >&2 || true
    exit 2
  fi
  stdlib_agdai_after=$(find "$stdlib_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
  if [ "$stdlib_agdai_after" -ne 0 ]; then
    echo "Supplied std-lib source tree contains generated .agdai files after the run: $stdlib_agdai_after" >&2
    exit 2
  fi
}

if [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = api-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]
then
  stdlib_manifest_before="$evidence_dir/stdlib-source.before.sha256"
  stdlib_agdai_before=$(find "$stdlib_source_dir" -type f -name '*.agdai' | wc -l | tr -d ' ')
  if [ "$stdlib_agdai_before" -ne 0 ]; then
    echo "Supplied std-lib source tree is contaminated with .agdai files: $stdlib_agdai_before" >&2
    exit 2
  fi
  write_source_manifest "$stdlib_source_dir" "$stdlib_manifest_before"
  expected_stdlib_files=$(awk -F '\t' '$1 == "projection" && $2 == "files" { print $3 }' "$stdlib_identity_file")
  expected_stdlib_manifest=$(awk -F '\t' '$1 == "projection" && $2 == "manifest-sha256" { print $3 }' "$stdlib_identity_file")
  actual_stdlib_files=$(wc -l < "$stdlib_manifest_before" | tr -d ' ')
  actual_stdlib_manifest=$(shasum -a 256 "$stdlib_manifest_before" | awk '{ print $1 }')
  if [ "$actual_stdlib_files" -ne "$expected_stdlib_files" ] || \
     [ "$actual_stdlib_manifest" != "$expected_stdlib_manifest" ]
  then
    echo "STDLIB29_DIR does not match the pinned Agda parent gitlink snapshot" >&2
    echo "Expected: $expected_stdlib_files files, $expected_stdlib_manifest" >&2
    echo "Actual:   $actual_stdlib_files files, $actual_stdlib_manifest" >&2
    exit 2
  fi
fi

agda_bin=$(CDPATH= cd -- "$agda_source_dir" && \
  cabal list-bin --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda)
if [ ! -x "$agda_bin" ]; then
  echo "Building the pinned stock Agda with -fdebug..."
  (CDPATH= cd -- "$agda_source_dir" && \
    cabal build --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda)
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && \
    cabal list-bin --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda)
fi
if [ ! -x "$agda_bin" ]; then
  echo "Pinned stock Agda executable is unavailable" >&2
  exit 2
fi

if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]
then
  # Cabal passes the package source path to GHC 9.6 while building the
  # generator. Keep this disposable workspace ASCII-only on a host whose
  # project path is non-ASCII.
  workspace_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-stdlib-workspace.XXXXXX")
else
  workspace_dir=$(mktemp -d "$evidence_dir/workspace.XXXXXX")
fi

workspace_root="$workspace_dir/root"
cabal_alias_dir=
cleanup() {
  rm -rf "$workspace_dir"
  if [ -n "$cabal_alias_dir" ]; then
    rm -rf "$cabal_alias_dir"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_root"
cp "$agda_source_dir/Makefile" "$workspace_root/Makefile"
source_dirs='mk src test doc'
if [ "$OFFICIAL_NATIVE_GROUP" = examples ]; then
  source_dirs="$source_dirs examples"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ]; then
  source_dirs="$source_dirs benchmark"
fi
for source_dir in $source_dirs
do
  if ! cp -cR "$agda_source_dir/$source_dir" "$workspace_root/$source_dir" 2>/dev/null; then
    cp -R "$agda_source_dir/$source_dir" "$workspace_root/$source_dir"
  fi
done

if [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]; then
  for source_file in Agda.cabal cabal.project LICENSE README.md CHANGELOG.md
  do
    cp "$agda_source_dir/$source_file" "$workspace_root/$source_file"
  done

  inventory_file="$evidence_dir/inventory.txt"
  modules_file="$evidence_dir/modules.txt"
  (
    CDPATH= cd -- "$workspace_root"
    find src/full -type f -name '*.hs' -exec \
      grep -nHE '^--[[:space:]]*>>>' {} + | LC_ALL=C sort
  ) > "$inventory_file"
  cut -d: -f1 "$inventory_file" | LC_ALL=C sort -u > "$modules_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  actual_modules=$(wc -l < "$modules_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ] || \
     [ "$actual_modules" -ne "$expected_modules" ]
  then
    echo "Doctest inventory changed: expected $expected_modules modules/$expected_items directives, found $actual_modules/$actual_items" >&2
    exit 2
  fi
fi

if [ "$OFFICIAL_NATIVE_GROUP" = cubical-test ]; then
  if ! cp -cR "$cubical_source_dir" "$workspace_root/cubical" 2>/dev/null; then
    cp -R "$cubical_source_dir" "$workspace_root/cubical"
  fi
  inventory_file="$evidence_dir/inventory.txt"
  (
    CDPATH= cd -- "$workspace_root/cubical"
    find . -type f -name '*.agda' -print | LC_ALL=C sort
  ) > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    echo "Cubical library inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi
fi

if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ]; then
  if ! cp -cR "$stdlib_source_dir" "$workspace_root/std-lib" 2>/dev/null; then
    cp -R "$stdlib_source_dir" "$workspace_root/std-lib"
  fi
  source_inventory_file="$evidence_dir/source-inventory.txt"
  (
    CDPATH= cd -- "$workspace_root/std-lib"
    find src -type f \( -name '*.agda' -o -name '*.lagda' \) -print | LC_ALL=C sort
  ) > "$source_inventory_file"
  actual_source_items=$(wc -l < "$source_inventory_file" | tr -d ' ')
  if [ "$actual_source_items" -ne "$expected_source_items" ]; then
    echo "Standard-library source inventory changed: expected $expected_source_items, found $actual_source_items" >&2
    exit 2
  fi
fi

if [ "$OFFICIAL_NATIVE_GROUP" = api-test ]; then
  if ! cp -cR "$stdlib_source_dir" "$workspace_root/std-lib" 2>/dev/null; then
    cp -R "$stdlib_source_dir" "$workspace_root/std-lib"
  fi
  inventory_file="$evidence_dir/inventory.txt"
  awk '
    /^all[[:space:]]*:/ {
      line=$0
      sub(/^[^:]*:[[:space:]]*/, "", line)
      count=split(line, fields, /[[:space:]]+/)
      for (field_index=1; field_index<=count; field_index++)
        if (fields[field_index] != "") print fields[field_index]
      exit
    }
  ' "$workspace_root/test/api/Makefile" > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    echo "API inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi
fi

if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]; then
  if ! cp -cR "$stdlib_source_dir" "$workspace_root/std-lib" 2>/dev/null; then
    cp -R "$stdlib_source_dir" "$workspace_root/std-lib"
  fi
  inventory_file="$evidence_dir/inventory.txt"
  (
    CDPATH= cd -- "$workspace_root/test/lib-interaction"
    find . -maxdepth 1 -type f -name '*.agda' -print |
      sed 's#^\./##' | LC_ALL=C sort
  ) > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    verify_stdlib_source_unchanged
    echo "Std-lib interaction inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi
  while IFS= read -r interaction_file
  do
    interaction_stem=${interaction_file%.agda}
    if [ ! -f "$workspace_root/test/lib-interaction/$interaction_stem.in" ] || \
       [ ! -f "$workspace_root/test/lib-interaction/$interaction_stem.out" ]
    then
      verify_stdlib_source_unchanged
      echo "Std-lib interaction fixture is incomplete: $interaction_stem" >&2
      exit 2
    fi
  done < "$inventory_file"
fi

if [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ]; then
  if ! cp -cR "$stdlib_source_dir" "$workspace_root/std-lib" 2>/dev/null; then
    cp -R "$stdlib_source_dir" "$workspace_root/std-lib"
  fi
  inventory_file="$evidence_dir/inventory.txt"
  make -C "$workspace_root/benchmark" -s debug \
    AGDA_BIN="$agda_bin" RUNGHC=/usr/bin/true 2>/dev/null |
    awk '
      /^logFiles = / {
        sub(/^logFiles = /, "")
        for (field_index=1; field_index<=NF; field_index++) {
          sub(/^.*\//, "", $field_index)
          print $field_index
        }
        exit
      }
    ' > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    echo "Benchmark inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi
fi

native_runghc=
native_ghc=$ghc29_resolved
if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ]
then
  ghc_version=$("$ghc29_resolved" --numeric-version)
  runghc29=${RUNGHC29:-"$(dirname -- "$ghc29_resolved")/runghc-$ghc_version"}
  if [ ! -x "$runghc29" ]; then
    runghc29=$(command -v "runghc-$ghc_version" 2>/dev/null || true)
  fi
  if [ -z "$runghc29" ] || [ ! -x "$runghc29" ]; then
    echo "runghc $ghc_version is required by the native group" >&2
    exit 2
  fi
fi

if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ]; then
  inventory_file="$evidence_dir/inventory.txt"
  (
    CDPATH= cd -- "$workspace_root/test/interaction"
    for agda_file in *agda
    do
      stem=${agda_file%.*}
      if [ ! -f "$stem.in" ] || [ -f "$stem.sh" ]; then
        printf '%s\n' "$agda_file"
      fi
    done
  ) | LC_ALL=C sort > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    echo "Interaction custom inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi

  if [ -n "$exclude_stem" ]; then
    excluded_name=$(awk -v stem="$exclude_stem" '
      $0 == stem ".agda" || $0 == stem ".lagda" { print; exit }
    ' "$inventory_file")
    if [ -z "$excluded_name" ]; then
      echo "Excluded custom interaction test is not in the inventory: $exclude_stem" >&2
      exit 2
    fi
    mv "$workspace_root/test/interaction/$excluded_name" \
      "$workspace_root/test/interaction/$excluded_name.diagnostic-excluded"
    run_items=$((expected_items - 1))
  fi

  # Cabal's generated GHC environment cannot decode the non-ASCII workspace
  # path with this GHC release. Point it at the existing build through a
  # disposable ASCII-only alias; all test inputs still run in the isolated
  # workspace below build.
  cabal_alias_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-native-cabal.XXXXXX")
  ln -s "$fdebug_dist" "$cabal_alias_dir/fdebug-dist"
  native_runghc="$cabal29_resolved -v0 exec --project-dir=$agda_source_dir --builddir=$cabal_alias_dir/fdebug-dist -w $ghc29_resolved -- $runghc29 --ghc-arg=-package=Agda"
elif [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ]; then
  native_runghc=$runghc29
fi
if [ "$OFFICIAL_NATIVE_GROUP" = api-test ]; then
  cabal_alias_dir=$(mktemp -d "${TMPDIR:-/tmp}/agda29-api-cabal.XXXXXX")
  ln -s "$fdebug_dist" "$cabal_alias_dir/fdebug-dist"
  native_ghc="$cabal29_resolved -v0 exec --project-dir=$agda_source_dir --builddir=$cabal_alias_dir/fdebug-dist -w $ghc29_resolved -- $ghc29_resolved"
fi

if [ "$OFFICIAL_NATIVE_GROUP" = examples ]; then
  inventory_file="$evidence_dir/inventory.txt"
  make -C "$workspace_root/examples" -np default AGDA_BIN="$agda_bin" 2>/dev/null |
    awk '
      /^default:/ {
        for (field_index=2; field_index<=NF; field_index++)
          if ($field_index != "other-examples") print $field_index
      }
      /^other-examples:/ {
        for (field_index=2; field_index<=NF; field_index++) print $field_index
      }
    ' | LC_ALL=C sort > "$inventory_file"
  actual_items=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$actual_items" -ne "$expected_items" ]; then
    echo "Examples inventory changed: expected $expected_items, found $actual_items" >&2
    exit 2
  fi
fi

log_suffix=
pass_status=PASS
run_path=$PATH
make_cabal=${cabal29_resolved:-cabal}
if [ "$interaction_compat" -eq 1 ]; then
  log_suffix=.interaction-compat
  pass_status=PASS-WITH-ENV-COMPAT
  mkdir -p "$workspace_root/compat-bin"
  cp "$script_dir/bsd-sed-gnu-bre-compat.sh" "$workspace_root/compat-bin/gsed"
  chmod +x "$workspace_root/compat-bin/gsed"
  run_path="$workspace_root/compat-bin:$PATH"
fi
if [ -n "$exclude_stem" ]; then
  log_suffix="${log_suffix}.with-exclusion"
  if [ "$interaction_compat" -eq 1 ]; then
    pass_status=PASS-WITH-ENV-COMPAT-AND-EXCLUSION
  else
    pass_status=PASS-WITH-EXCLUSION
  fi
fi
if [ "$doctest_compat" -eq 1 ]; then
  log_suffix=.doctest-compat
  pass_status=PASS-WITH-ENV-COMPAT
fi
if [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]; then
  doctest_bin_dir="$workspace_root/doctest-bin"
  doctest_install_store="$workspace_root/doctest-store"
  doctest_install_dist="$workspace_root/doctest-install-dist"
  doctest_project_dist="$workspace_root/doctest-project-dist"
  doctest_version_file="$evidence_dir/doctest-version${log_suffix}.txt"
  make_cabal="$script_dir/cabal-doctest-isolated.sh"
  run_path="$doctest_bin_dir:$(dirname -- "$ghc29_resolved"):$run_path"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = examples ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = api-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]
then
  # Keep native compiler subprocesses on the compiler used to build the stock
  # Agda test binary.
  run_path="$(dirname -- "$ghc29_resolved"):$run_path"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ]; then
  mkdir -p "$workspace_root/locked-native-bin"
  ln -s "$cabal29_resolved" "$workspace_root/locked-native-bin/cabal"
  run_path="$workspace_root/locked-native-bin:$run_path"
fi

stdout_log="$evidence_dir/stdout${log_suffix}.log"
stderr_log="$evidence_dir/stderr${log_suffix}.log"
summary_file="$evidence_dir/summary${log_suffix}.tsv"
printf 'suite\titems\titem_kind\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"
printf 'group\t%s\nupstream-targets\t%s\ninventory-items\t%s\nrun-items\t%s\nitem-kind\t%s\ninteraction-compat\t%s\ndoctest-compat\t%s\nexclude-stem\t%s\nghc-bin\t%s\nnative-runghc\t%s\nagda-bin\t%s\n' \
  "$OFFICIAL_NATIVE_GROUP" "$upstream_targets" "$expected_items" "$run_items" "$item_kind" \
  "$interaction_compat" "$doctest_compat" "$exclude_stem" "$ghc29_resolved" "$native_runghc" "$agda_bin" \
  > "$evidence_dir/invocation${log_suffix}.tsv"
if [ "$OFFICIAL_NATIVE_GROUP" = cubical-test ]; then
  cubical_manifest_sha256=$(shasum -a 256 "$cubical_manifest_before" | awk '{ print $1 }')
  printf 'cubical-source-dir\t%s\ncubical-source-manifest-sha256\t%s\n' \
    "$cubical_source_dir" "$cubical_manifest_sha256" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = api-test ] || \
   [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]
then
  stdlib_gitlink_commit=$(awk -F '\t' '$1 == "metadata" && $2 == "stdlib-gitlink-commit" { print $3 }' "$stdlib_identity_file")
  printf 'stdlib-source-dir\t%s\nstdlib-gitlink-commit\t%s\nstdlib-source-manifest-sha256\t%s\n' \
    "$stdlib_source_dir" "$stdlib_gitlink_commit" "$actual_stdlib_manifest" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ]; then
  printf 'source-inventory-items\t%s\ncabal-bin\t%s\n' \
    "$actual_source_items" "$cabal29_resolved" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = api-test ]; then
  printf 'cabal-bin\t%s\nnative-ghc\t%s\n' \
    "$cabal29_resolved" "$native_ghc" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]; then
  printf 'cabal-bin\t%s\nexpected-modules\t%s\nexpected-examples\t%s\nisolated-doctest-bin\t%s\nisolated-doctest-store\t%s\n' \
    "$cabal29_resolved" "$expected_modules" "$expected_examples" \
    "$doctest_bin_dir" "$doctest_install_store" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi

echo "official native ${group_name}: ${upstream_targets}"
# The target list is a fixed, internal whitelist selected by the case above.
# shellcheck disable=SC2086
if (CDPATH= cd -- "$workspace_root" && \
  /usr/bin/time -l env \
    PATH="$run_path" \
    Agda_datadir="$workspace_root/src/data" \
    CABAL_DOCTEST_REAL="$cabal29_resolved" \
    CABAL_DOCTEST_GHC="$ghc29_resolved" \
    CABAL_DOCTEST_BIN_DIR="${doctest_bin_dir:-}" \
    CABAL_DOCTEST_INSTALL_STORE="${doctest_install_store:-}" \
    CABAL_DOCTEST_INSTALL_DIST="${doctest_install_dist:-}" \
    CABAL_DOCTEST_PROJECT_DIST="${doctest_project_dist:-}" \
    CABAL_DOCTEST_VERSION_FILE="${doctest_version_file:-}" \
    CABAL_DOCTEST_DISABLE_OPTIMIZATION="$doctest_compat" \
    make --no-print-directory \
      AGDA_BIN="$agda_bin" \
      CABAL="$make_cabal" \
      GHC="$native_ghc" \
      RUNGHC="$native_runghc" \
      $upstream_targets \
    > "$stdout_log" 2> "$stderr_log")
then
  real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  if [ "$OFFICIAL_NATIVE_GROUP" = doc-test ]; then
    doctest_summary=$(awk '
      /^Examples:[[:space:]]+[0-9]+[[:space:]]+Tried:[[:space:]]+[0-9]+[[:space:]]+Errors:[[:space:]]+[0-9]+[[:space:]]+Failures:[[:space:]]+[0-9]+$/ {
        summary=$0
      }
      END { print summary }
    ' "$stdout_log" "$stderr_log")
    examples=$(printf '%s\n' "$doctest_summary" | awk '{ print $2 + 0 }')
    tried=$(printf '%s\n' "$doctest_summary" | awk '{ print $4 + 0 }')
    errors=$(printf '%s\n' "$doctest_summary" | awk '{ print $6 + 0 }')
    failures=$(printf '%s\n' "$doctest_summary" | awk '{ print $8 + 0 }')
    printf 'check\tcount\ndoctest-modules\t%s\ndoctest-directives\t%s\nexamples\t%s\ntried\t%s\nerrors\t%s\nfailures\t%s\n' \
      "$actual_modules" "$actual_items" "$examples" "$tried" "$errors" "$failures" \
      > "$evidence_dir/execution-counts${log_suffix}.tsv"
    if [ "$examples" -ne "$expected_examples" ] || \
       [ "$tried" -ne "$expected_examples" ] || \
       [ "$errors" -ne 0 ] || [ "$failures" -ne 0 ] || \
       [ ! -s "$doctest_version_file" ]
    then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$actual_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      echo "Doctest output mismatch: $examples examples, $tried tried, $errors errors, $failures failures" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = examples ]; then
    executed_items=$(grep -c '^Testing ' "$stdout_log" || true)
    malonzo_compiles=$(grep -c '^Calling: ghc ' "$stdout_log" || true)
    printf 'check\tcount\nexample-checks\t%s\nmalonzo-compiles\t%s\n' \
      "$executed_items" "$malonzo_compiles" > "$evidence_dir/execution-counts.tsv"
    if [ "$executed_items" -ne "$run_items" ] || [ "$malonzo_compiles" -ne 2 ]; then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$executed_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      echo "Examples output count mismatch: $executed_items checks, $malonzo_compiles MAlonzo compiles" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = cubical-test ]; then
    generated_interfaces=$(find "$workspace_root/cubical" -type f -name '*.agdai' | wc -l | tr -d ' ')
    printf 'check\tcount\ninput-modules\t%s\ngenerated-interfaces\t%s\n' \
      "$actual_items" "$generated_interfaces" > "$evidence_dir/execution-counts.tsv"
    if [ "$generated_interfaces" -ne "$run_items" ]; then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$generated_interfaces" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      verify_cubical_source_unchanged
      echo "Cubical output count mismatch: $generated_interfaces generated interfaces" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = benchmark-without-logs ]; then
    executed_items=$(grep -c '^Running benchmark ' "$stdout_log" || true)
    residual_log_files=$(find "$workspace_root/benchmark/logs" -type f 2>/dev/null | wc -l | tr -d ' ')
    printf 'check\tcount\nbenchmark-cases\t%s\nresidual-log-files\t%s\n' \
      "$executed_items" "$residual_log_files" > "$evidence_dir/execution-counts.tsv"
    if [ "$executed_items" -ne "$run_items" ] || [ "$residual_log_files" -ne 0 ]; then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$executed_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      verify_stdlib_source_unchanged
      echo "Benchmark output mismatch: $executed_items cases, $residual_log_files residual log files" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-test ]; then
    inventory_file="$evidence_dir/inventory.txt"
    if [ -f "$workspace_root/std-lib/Everything.agda" ]; then
      sed -n 's/^import //p' "$workspace_root/std-lib/Everything.agda" > "$inventory_file"
    else
      : > "$inventory_file"
    fi
    executed_items=$(wc -l < "$inventory_file" | tr -d ' ')
    everything_safe_generated=0
    safe_imports=0
    if [ -f "$workspace_root/std-lib/EverythingSafe.agda" ]; then
      everything_safe_generated=1
      safe_imports=$(grep -c '^import ' "$workspace_root/std-lib/EverythingSafe.agda" || true)
    fi
    generated_interfaces=$(find "$workspace_root/std-lib" -type f -name '*.agdai' | wc -l | tr -d ' ')
    everything_interface=0
    if [ -f "$workspace_root/std-lib/Everything.agdai" ]; then
      everything_interface=1
    fi
    printf 'check\tcount\nsource-modules\t%s\neverything-imports\t%s\neverything-safe-imports\t%s\neverything-safe-generated\t%s\ngenerated-interfaces\t%s\neverything-interface\t%s\n' \
      "$actual_source_items" "$executed_items" "$safe_imports" \
      "$everything_safe_generated" "$generated_interfaces" "$everything_interface" \
      > "$evidence_dir/execution-counts.tsv"
    if [ "$executed_items" -ne "$run_items" ] || \
       [ "$safe_imports" -ne "$expected_safe_items" ] || \
       [ "$everything_safe_generated" -ne 1 ] || \
       [ "$everything_interface" -ne "$expected_everything_interface" ] || \
       [ "$generated_interfaces" -ne "$expected_interfaces" ]
    then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$executed_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      verify_stdlib_source_unchanged
      echo "Standard-library output mismatch: $executed_items imports, $safe_imports safe imports, $generated_interfaces interfaces, entry interface $everything_interface" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = api-test ]; then
    ghc_compiles=$(grep -c -- '-Wall -Werror' "$stdout_log" || true)
    api_markers=$(find "$workspace_root/test/api" -maxdepth 1 -type f -name '*.api' | wc -l | tr -d ' ')
    generated_interfaces=$(find "$workspace_root/test/api" -maxdepth 1 -type f -name '*.agdai' | wc -l | tr -d ' ')
    print_import_headers=$(grep -c '^../../std-lib/src/Data/List/Relation/Unary/Any.agda imports the following modules:$' "$stdout_log" || true)
    print_imports=$(grep -c '^- ' "$stdout_log" || true)
    printf 'check\tcount\nAPI-tests\t%s\nGHC-compiles\t%s\napi-markers\t%s\ngenerated-interfaces\t%s\nPrintImports-headers\t%s\nPrintImports-imports\t%s\n' \
      "$run_items" "$ghc_compiles" "$api_markers" "$generated_interfaces" \
      "$print_import_headers" "$print_imports" \
      > "$evidence_dir/execution-counts.tsv"
    if [ "$ghc_compiles" -ne "$run_items" ] || \
       [ "$api_markers" -ne 3 ] || \
       [ "$generated_interfaces" -ne 0 ] || \
       [ "$print_import_headers" -ne 1 ] || \
       [ "$print_imports" -ne 8 ]
    then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$run_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      verify_stdlib_source_unchanged
      echo "API output mismatch: $ghc_compiles compiles, $api_markers markers, $generated_interfaces interfaces, $print_imports printed imports" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]; then
    executed_items=$(awk '
      NR == FNR {
        stem=$0
        sub(/\.agda$/, "", stem)
        test[stem]=1
        next
      }
      $0 in test { count++ }
      END { print count + 0 }
    ' "$inventory_file" "$stdout_log")
    residual_tmp_files=$(find "$workspace_root/test/lib-interaction" -maxdepth 1 \
      -type f \( -name '*.tmp' -o -name '*.tmp_out' \) | wc -l | tr -d ' ')
    input_interfaces=$(find "$workspace_root/test/lib-interaction" -type f -name '*.agdai' | wc -l | tr -d ' ')
    stdlib_interfaces=$(find "$workspace_root/std-lib" -type f -name '*.agdai' | wc -l | tr -d ' ')
    printf 'check\tcount\ngolden-tests\t%s\nresidual-tmp-files\t%s\ninput-interfaces\t%s\nstdlib-interfaces\t%s\n' \
      "$executed_items" "$residual_tmp_files" "$input_interfaces" "$stdlib_interfaces" \
      > "$evidence_dir/execution-counts${log_suffix}.tsv"
    if [ "$executed_items" -ne "$run_items" ] || [ "$residual_tmp_files" -ne 0 ]; then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-OUTPUT\t%s\t%s\n' \
        "$group_name" "$executed_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      verify_stdlib_source_unchanged
      echo "Std-lib interaction output mismatch: $executed_items tests, $residual_tmp_files residual temporary files" >&2
      exit 1
    fi
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] || \
     [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]
  then
    golden_difference_count=$(grep -c '^=== Diff ===$' "$stdout_log" || true)
    if [ "$golden_difference_count" -ne 0 ]; then
      differences_file="$evidence_dir/golden-differences${log_suffix}.txt"
      awk '
        NR == FNR {
          stem=$0
          sub(/\.(l)?agda$/, "", stem)
          test[stem]=1
          next
        }
        $0 in test { current=$0 }
        /^=== Diff ===$/ { print current }
      ' "$inventory_file" "$stdout_log" > "$differences_file"
      printf '%s\t%s\t%s\tFAIL-GOLDEN-DIFFERENCE\t%s\t%s\n' \
        "$group_name" "$run_items" "$item_kind" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      if [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] && \
         [ "$golden_difference_count" -eq 1 ] && \
         [ "$(cat "$differences_file")" = Issue8634 ]
      then
        printf 'classification\treason\nENVIRONMENT-GOLDEN-DIFFERENCE\tabsolute-workspace-path-shifts-warning-annotation-offsets\n' \
          > "$evidence_dir/classification${log_suffix}.tsv"
      fi
      echo "Official native ${group_name} found ${golden_difference_count} golden differences" >&2
      echo "Evidence: $differences_file" >&2
      verify_stdlib_source_unchanged
      exit 1
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$group_name" "$run_items" "$item_kind" "$pass_status" "$real_seconds" "$max_rss" \
    >> "$summary_file"
  verify_cubical_source_unchanged
  verify_stdlib_source_unchanged
  echo "Official native ${group_name} ${pass_status}: ${run_items} ${item_kind}"
  echo "Evidence: $summary_file"
else
  real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  printf '%s\t%s\t%s\tFAIL\t%s\t%s\n' \
    "$group_name" "$run_items" "$item_kind" "${real_seconds:--}" "${max_rss:--}" \
    >> "$summary_file"
  if { [ "$OFFICIAL_NATIVE_GROUP" = interaction-custom ] || \
       [ "$OFFICIAL_NATIVE_GROUP" = std-lib-interaction ]; } && \
     [ "$interaction_compat" -eq 0 ] && \
     grep -q 'gsed: command not found' "$stderr_log"
  then
    printf 'classification\treason\nENVIRONMENT-MISSING-TOOL\tupstream-Darwin-path-requires-gsed\n' \
      > "$evidence_dir/classification.tsv"
  fi
  if [ "$OFFICIAL_NATIVE_GROUP" = doc-test ] && \
     [ "$doctest_compat" -eq 0 ] && \
     grep -q 'Optimization flags are incompatible with the byte-code interpreter' "$stderr_log"
  then
    printf 'classification\treason\nENVIRONMENT-GHC-REPL-CONFIG\tlocked-GHC-9.6-rejects-O1-bytecode-warning-under-upstream-Werror\n' \
      > "$evidence_dir/classification.tsv"
  fi
  echo "Official native ${group_name} failed" >&2
  tail -n 240 "$stdout_log" >&2
  tail -n 240 "$stderr_log" >&2
  verify_cubical_source_unchanged
  verify_stdlib_source_unchanged
  exit 1
fi
