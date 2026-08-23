#!/bin/sh

set -eu

: "${AGDA29_SOURCE_DIR:?Set AGDA29_SOURCE_DIR to the pinned Agda 2.9 source tree}"
: "${OFFICIAL_SUITE_GROUP:?Set OFFICIAL_SUITE_GROUP to a maintained official Tasty group}"

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
agda_source_dir=$(CDPATH= cd -- "$AGDA29_SOURCE_DIR" && pwd -P)
ghc29=${GHC29:-ghc}
cabal29=${CABAL29:-cabal}
jobs=${OFFICIAL_SUITE_JOBS:-$(getconf _NPROCESSORS_ONLN)}
test_timeout=${OFFICIAL_SUITE_TEST_TIMEOUT:-20m}
exclude_regex=${OFFICIAL_SUITE_EXCLUDE_REGEX:-}
interaction_compat=${OFFICIAL_SUITE_INTERACTION_COMPAT:-0}
cubical_dir=${CUBICAL29_DIR:-"$(dirname -- "$agda_source_dir")/cubical-upstream"}
fdebug_dist="$backend_dir/build/agda29/official-compiler/fdebug-dist"
stdlib_source_dir=
stdlib_identity_file="$backend_dir/test/fixtures/agda29-stdlib.identity.tsv"
canonical_exclude_regex=
expected_tests=
expected_test_name=
expected_test_prefix=
expected_source_items=
expected_input_interfaces=
execution_count_label=
uses_stdlib=0
prepare_stdlib_interfaces=0
node_resolved=
node_version=

ghc29_resolved=$(command -v "$ghc29" 2>/dev/null || true)
if [ -z "$ghc29_resolved" ] || [ ! -x "$ghc29_resolved" ]; then
  echo "GHC29 is not executable: $ghc29" >&2
  exit 2
fi

case "$OFFICIAL_SUITE_GROUP" in
  build-fail) group_name=BuildFail; regex='all/BuildFail' ;;
  build-succeed) group_name=BuildSucceed; regex='all/BuildSucceed' ;;
  succeed) group_name=Succeed; regex='all/Succeed' ;;
  fail) group_name=Fail; regex='all/Fail' ;;
  bugs) group_name=Bugs; regex='all/Bugs' ;;
  interaction-simple) group_name=InteractionSimple; regex='all/Interaction/simple' ;;
  interactive) group_name=Interactive; regex='all/Interactive' ;;
  user-manual) group_name=UserManual; regex='all/UserManual' ;;
  latex-html) group_name=LaTeXAndHTML; regex='all/LaTeXAndHTML' ;;
  internal) group_name=Internal; regex='all/Internal' ;;
  cubical-succeed) group_name=CubicalSucceed; regex='all/CubicalSucceed' ;;
  std-lib-compiler)
    group_name=StdLibCompiler
    regex='AllStdLib'
    canonical_exclude_regex='AllStdLibJS'
    expected_tests=1
    expected_test_name='all.Compiler.MAlonzo_Lazy.with-stdlib.AllStdLib'
    execution_count_label=AllStdLib-tests
    uses_stdlib=1
    prepare_stdlib_interfaces=1
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
  std-lib-js-compiler)
    group_name=StdLibJSCompiler
    regex='AllStdLibJS'
    expected_tests=1
    expected_test_name='all.Compiler.JS_MinifiedOptimized.with-stdlib.AllStdLibJS'
    execution_count_label=AllStdLibJS-tests
    uses_stdlib=1
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    node_resolved=$(command -v node 2>/dev/null || true)
    if [ -z "$node_resolved" ] || [ ! -x "$node_resolved" ]; then
      echo "node is required by std-lib-js-compiler" >&2
      exit 2
    fi
    node_version=$($node_resolved --version)
    ;;
  std-lib-succeed)
    group_name=StdLibSucceed
    regex='all/LibSucceed'
    expected_tests=25
    expected_test_prefix='all.LibSucceed.'
    expected_source_items=32
    expected_input_interfaces=30
    execution_count_label=LibSucceed-tests
    uses_stdlib=1
    : "${STDLIB29_DIR:?Set STDLIB29_DIR to the pinned Agda std-lib gitlink source tree}"
    stdlib_source_dir=$(CDPATH= cd -- "$STDLIB29_DIR" && pwd -P)
    if [ ! -f "$stdlib_source_dir/standard-library.agda-lib" ] || \
       [ ! -f "$stdlib_identity_file" ]
    then
      echo "STDLIB29_DIR or its maintained identity is unavailable: $stdlib_source_dir" >&2
      exit 2
    fi
    ;;
  *)
    echo "Unsupported OFFICIAL_SUITE_GROUP: $OFFICIAL_SUITE_GROUP" >&2
    echo "Use: build-fail, build-succeed, succeed, fail, bugs, interaction-simple," >&2
    echo "     interactive, user-manual, latex-html, internal, cubical-succeed," >&2
    echo "     std-lib-compiler, std-lib-js-compiler, or std-lib-succeed." >&2
    exit 2
    ;;
esac

case "$jobs" in
  ''|*[!0-9]*|0)
    echo "OFFICIAL_SUITE_JOBS must be a positive integer: $jobs" >&2
    exit 2
    ;;
esac

case "$interaction_compat" in
  0|1) ;;
  *)
    echo "OFFICIAL_SUITE_INTERACTION_COMPAT must be 0 or 1" >&2
    exit 2
    ;;
esac
if [ "$interaction_compat" -eq 1 ] && \
   [ "$OFFICIAL_SUITE_GROUP" != interaction-simple ]
then
  echo "Interaction compatibility is only valid for interaction-simple" >&2
  exit 2
fi
if [ "$interaction_compat" -eq 1 ] && [ -n "$exclude_regex" ]; then
  echo "Do not combine interaction compatibility with a test exclusion" >&2
  exit 2
fi
if { [ "$OFFICIAL_SUITE_GROUP" = std-lib-compiler ] || \
     [ "$OFFICIAL_SUITE_GROUP" = std-lib-js-compiler ] || \
     [ "$OFFICIAL_SUITE_GROUP" = std-lib-succeed ]; } && \
   [ -n "$exclude_regex" ]
then
  echo "$OFFICIAL_SUITE_GROUP is an exact canonical target and does not accept a diagnostic exclusion" >&2
  exit 2
fi

if [ "$OFFICIAL_SUITE_GROUP" = cubical-succeed ] && \
   [ ! -f "$cubical_dir/cubical.agda-lib" ]
then
  echo "cubical.agda-lib not found below CUBICAL29_DIR: $cubical_dir" >&2
  exit 2
fi

if [ "$OFFICIAL_SUITE_GROUP" = latex-html ] && ! command -v latex >/dev/null 2>&1; then
  echo "latex is required for the complete LaTeXAndHTML group" >&2
  exit 2
fi

cabal29_resolved=
if [ "$OFFICIAL_SUITE_GROUP" = std-lib-compiler ]; then
  cabal29_resolved=$(command -v "$cabal29" 2>/dev/null || true)
  if [ -z "$cabal29_resolved" ] || [ ! -x "$cabal29_resolved" ]; then
    echo "cabal is required by std-lib-compiler: $cabal29" >&2
    exit 2
  fi
fi

evidence_dir="$backend_dir/build/agda29/official-suite/$OFFICIAL_SUITE_GROUP"
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

verify_stdlib_source_unchanged() {
  if [ "$uses_stdlib" -ne 1 ]; then
    return
  fi
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

if [ "$uses_stdlib" -eq 1 ]; then
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
tests_bin=$(CDPATH= cd -- "$agda_source_dir" && \
  cabal list-bin --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda-tests)
if [ ! -x "$agda_bin" ] || [ ! -x "$tests_bin" ]; then
  echo "Building the pinned stock Agda and official test driver with -fdebug..."
  (CDPATH= cd -- "$agda_source_dir" && \
    cabal build --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug \
      exe:agda exe:agda-tests)
  agda_bin=$(CDPATH= cd -- "$agda_source_dir" && \
    cabal list-bin --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda)
  tests_bin=$(CDPATH= cd -- "$agda_source_dir" && \
    cabal list-bin --builddir="$fdebug_dist" -w "$ghc29_resolved" -fdebug exe:agda-tests)
fi

if [ "$prepare_stdlib_interfaces" -eq 1 ]; then
  # Cabal passes the package source path to GHC while building
  # GenerateEverything. Keep that disposable path ASCII-only.
  workspace_dir=$(mktemp -d /private/tmp/agda29-stdlib-compiler-workspace.XXXXXX)
else
  workspace_dir=$(mktemp -d "$evidence_dir/workspace.XXXXXX")
fi
workspace_root="$workspace_dir/root"
cleanup() {
  rm -rf "$workspace_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$workspace_root"
for source_dir in test doc mk
do
  if ! cp -cR "$agda_source_dir/$source_dir" "$workspace_root/$source_dir" 2>/dev/null; then
    cp -R "$agda_source_dir/$source_dir" "$workspace_root/$source_dir"
  fi
done
mkdir -p "$workspace_root/src"
if ! cp -cR "$agda_source_dir/src/data" "$workspace_root/src/data" 2>/dev/null; then
  cp -R "$agda_source_dir/src/data" "$workspace_root/src/data"
fi
# The installed binaries need Agda's data files, but tests such as BuildSucceed
# can emit highlighting files next to them. Keep both those writes and reusable
# primitive interfaces inside the disposable workspace.
if [ "$OFFICIAL_SUITE_GROUP" = cubical-succeed ]; then
  if ! cp -cR "$cubical_dir" "$workspace_root/cubical" 2>/dev/null; then
    cp -R "$cubical_dir" "$workspace_root/cubical"
  fi
fi
if [ "$uses_stdlib" -eq 1 ]; then
  if ! cp -cR "$stdlib_source_dir" "$workspace_root/std-lib" 2>/dev/null; then
    cp -R "$stdlib_source_dir" "$workspace_root/std-lib"
  fi

  inventory_file="$evidence_dir/inventory.txt"
  if [ -n "$expected_test_name" ]; then
    (CDPATH= cd -- "$workspace_root" && \
      AGDA_BIN="$agda_bin" "$tests_bin" -l) |
        awk -v target="$expected_test_name" '$0 == target { print }' > "$inventory_file"
  else
    (CDPATH= cd -- "$workspace_root" && \
      AGDA_BIN="$agda_bin" "$tests_bin" -l) |
        awk -v prefix="$expected_test_prefix" 'index($0, prefix) == 1 { print }' > "$inventory_file"
  fi
  inventory_tests=$(wc -l < "$inventory_file" | tr -d ' ')
  if [ "$inventory_tests" -ne "$expected_tests" ]; then
    verify_stdlib_source_unchanged
    echo "$OFFICIAL_SUITE_GROUP inventory changed: expected $expected_tests, found $inventory_tests" >&2
    exit 1
  fi

  if [ "$OFFICIAL_SUITE_GROUP" = std-lib-succeed ]; then
    find "$workspace_root/test/LibSucceed" -type f -name '*.agdai' -delete
    source_inventory_file="$evidence_dir/source-inventory.txt"
    (
      CDPATH= cd -- "$workspace_root/test/LibSucceed"
      find . -type f \( -name '*.agda' -o -name '*.lagda' \) -print | LC_ALL=C sort
    ) > "$source_inventory_file"
    actual_source_items=$(wc -l < "$source_inventory_file" | tr -d ' ')
    if [ "$actual_source_items" -ne "$expected_source_items" ]; then
      verify_stdlib_source_unchanged
      echo "LibSucceed source inventory changed: expected $expected_source_items, found $actual_source_items" >&2
      exit 1
    fi
    expected_interface_inventory_file="$evidence_dir/expected-interface-inventory.txt"
    awk '
      $0 != "./Issue1382.agda" && $0 != "./Issue846.agda" { print }
    ' "$source_inventory_file" > "$expected_interface_inventory_file"
    expected_interface_items=$(wc -l < "$expected_interface_inventory_file" | tr -d ' ')
    if [ "$expected_interface_items" -ne "$expected_input_interfaces" ]; then
      verify_stdlib_source_unchanged
      echo "LibSucceed expected interface inventory changed: expected $expected_input_interfaces, found $expected_interface_items" >&2
      exit 1
    fi
  fi

fi

if [ "$prepare_stdlib_interfaces" -eq 1 ]; then

  # The upstream all-tests workflow runs std-lib-test before this target.
  # Recreate its generated umbrella and reusable interfaces in the isolated
  # std-lib copy so AllStdLib exercises the canonical --no-ignore-interfaces
  # path without touching the pinned source snapshot.
  generator_stdout="$evidence_dir/generator.stdout.log"
  generator_stderr="$evidence_dir/generator.stderr.log"
  if ! (CDPATH= cd -- "$workspace_root/std-lib" && \
    PATH="$(dirname -- "$ghc29_resolved"):$PATH" \
      "$cabal29_resolved" -v0 run --project-dir=. -w "$ghc29_resolved" GenerateEverything \
      > "$generator_stdout" 2> "$generator_stderr")
  then
    verify_stdlib_source_unchanged
    echo "GenerateEverything failed for the isolated std-lib copy" >&2
    tail -n 160 "$generator_stderr" >&2
    exit 1
  fi
  everything_imports=$(grep -c '^import ' "$workspace_root/std-lib/Everything.agda" || true)
  if [ "$everything_imports" -ne 1059 ]; then
    verify_stdlib_source_unchanged
    echo "Generated Everything.agda inventory changed: expected 1059 imports, found $everything_imports" >&2
    exit 1
  fi

  prepare_stdout="$evidence_dir/prepare-interfaces.stdout.log"
  prepare_stderr="$evidence_dir/prepare-interfaces.stderr.log"
  if ! (CDPATH= cd -- "$workspace_root/std-lib" && \
    /usr/bin/time -l env \
      PATH="$(dirname -- "$ghc29_resolved"):$PATH" \
      Agda_datadir="$workspace_root/src/data" \
      "$agda_bin" --ignore-interfaces --no-default-libraries \
        -i. -isrc Everything.agda +RTS -s \
      > "$prepare_stdout" 2> "$prepare_stderr")
  then
    verify_stdlib_source_unchanged
    echo "Preparing isolated standard-library interfaces failed" >&2
    tail -n 240 "$prepare_stderr" >&2
    exit 1
  fi
  prepare_real_seconds=$(awk '$2 == "real" { print $1; exit }' "$prepare_stderr")
  prepare_max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$prepare_stderr")
  if [ -z "$prepare_real_seconds" ] || [ -z "$prepare_max_rss" ]; then
    verify_stdlib_source_unchanged
    echo "Preparing isolated standard-library interfaces produced no resource summary" >&2
    exit 1
  fi
  printf 'stage\treal_seconds\tmax_rss_bytes\nprepare-interfaces\t%s\t%s\n' \
    "$prepare_real_seconds" "$prepare_max_rss" \
    > "$evidence_dir/preparation.tsv"
  prepared_interfaces=$(find "$workspace_root/std-lib" -type f -name '*.agdai' | wc -l | tr -d ' ')
  everything_interface=0
  if [ -f "$workspace_root/std-lib/Everything.agdai" ]; then
    everything_interface=1
  fi
  if [ "$prepared_interfaces" -ne 1091 ] || [ "$everything_interface" -ne 0 ]; then
    verify_stdlib_source_unchanged
    echo "Prepared std-lib interface inventory changed: $prepared_interfaces total, $everything_interface Everything.agdai" >&2
    exit 1
  fi

fi

printf '%s\n' "$agda_bin" > "$workspace_root/test/helpers/exec-tc/executables"
log_suffix=
pass_status=PASS
if [ -n "$exclude_regex" ]; then
  log_suffix=.with-exclusion
  pass_status=PASS-WITH-EXCLUSION
fi
test_path=$PATH
if [ "$prepare_stdlib_interfaces" -eq 1 ]; then
  test_path="$(dirname -- "$ghc29_resolved"):$test_path"
fi
if [ "$interaction_compat" -eq 1 ]; then
  log_suffix=.interaction-compat
  pass_status=PASS-WITH-ENV-COMPAT
  actual_interaction_dir=$(find "$workspace_root/test" -mindepth 1 -maxdepth 1 \
    -type d -iname interaction -print | head -n 1)
  if [ -n "$actual_interaction_dir" ] && \
     [ "$(basename -- "$actual_interaction_dir")" != interaction ]
  then
    mv "$actual_interaction_dir" "$workspace_root/test/interaction-case-rename"
    mv "$workspace_root/test/interaction-case-rename" "$workspace_root/test/interaction"
  fi
  mkdir -p "$workspace_root/compat-bin"
  cp "$script_dir/bsd-sed-gnu-bre-compat.sh" "$workspace_root/compat-bin/sed"
  chmod +x "$workspace_root/compat-bin/sed"
  test_path="$workspace_root/compat-bin:$PATH"
fi
stdout_log="$evidence_dir/stdout${log_suffix}.log"
stderr_log="$evidence_dir/stderr${log_suffix}.log"
summary_file="$evidence_dir/summary${log_suffix}.tsv"
printf 'suite\ttests\tdisabled\tstatus\treal_seconds\tmax_rss_bytes\n' > "$summary_file"
printf 'group\t%s\nregex\t%s\ncanonical-exclude-regex\t%s\nexclude-regex\t%s\ninteraction-compat\t%s\njobs\t%s\nper-test-timeout\t%s\nghc-bin\t%s\n' \
  "$OFFICIAL_SUITE_GROUP" "$regex" "$canonical_exclude_regex" "$exclude_regex" "$interaction_compat" "$jobs" "$test_timeout" "$ghc29_resolved" \
  > "$evidence_dir/invocation${log_suffix}.tsv"
if [ "$uses_stdlib" -eq 1 ]; then
  stdlib_gitlink_commit=$(awk -F '\t' '$1 == "metadata" && $2 == "stdlib-gitlink-commit" { print $3 }' "$stdlib_identity_file")
  printf 'expected-tests\t%s\nexpected-test-name\t%s\nstdlib-source-dir\t%s\nstdlib-gitlink-commit\t%s\nstdlib-source-manifest-sha256\t%s\n' \
    "$expected_tests" "$expected_test_name" "$stdlib_source_dir" \
    "$stdlib_gitlink_commit" "$actual_stdlib_manifest" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_SUITE_GROUP" = std-lib-succeed ]; then
  printf 'expected-test-prefix\t%s\nsource-inventory-items\t%s\nexpected-input-interfaces\t%s\n' \
    "$expected_test_prefix" "$actual_source_items" "$expected_input_interfaces" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$prepare_stdlib_interfaces" -eq 1 ]; then
  printf 'everything-imports\t%s\nprepared-interfaces\t%s\neverything-interface\t%s\nprepare-real-seconds\t%s\nprepare-max-rss-bytes\t%s\ncabal-bin\t%s\n' \
    "$everything_imports" "$prepared_interfaces" "$everything_interface" \
    "$prepare_real_seconds" "$prepare_max_rss" "$cabal29_resolved" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi
if [ "$OFFICIAL_SUITE_GROUP" = std-lib-js-compiler ]; then
  printf 'node-bin\t%s\nnode-version\t%s\n' "$node_resolved" "$node_version" \
    >> "$evidence_dir/invocation${log_suffix}.tsv"
fi

echo "official ${group_name} group (${jobs} jobs, per-test timeout ${test_timeout})"
run_group() {
  run_exclude_regex=$exclude_regex
  if [ -n "$canonical_exclude_regex" ]; then
    run_exclude_regex=$canonical_exclude_regex
  fi
  if [ -n "$run_exclude_regex" ]; then
    CDPATH= cd -- "$workspace_root" && \
      /usr/bin/time -l env \
        PATH="$test_path" \
        Agda_datadir="$workspace_root/src/data" \
        AGDA_BIN="$agda_bin" \
        "$tests_bin" -i -j"$jobs" -t"$test_timeout" \
          --regex-include "$regex" \
          --regex-exclude "$run_exclude_regex"
  else
    CDPATH= cd -- "$workspace_root" && \
      /usr/bin/time -l env \
        PATH="$test_path" \
        Agda_datadir="$workspace_root/src/data" \
        AGDA_BIN="$agda_bin" \
        "$tests_bin" -i -j"$jobs" -t"$test_timeout" \
          --regex-include "$regex"
  fi
}

if run_group > "$stdout_log" 2> "$stderr_log"
then
  passed_tests=$(sed -nE 's/^All ([0-9]+) tests passed.*$/\1/p' "$stdout_log" | tail -n 1)
  disabled_tests=$(awk '/: *DISABLED$/ { count++ } END { print count + 0 }' "$stdout_log")
  real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  if [ -z "$passed_tests" ]; then
    printf '%s\t-\t%s\tFAIL-NO-SUMMARY\t%s\t%s\n' \
      "$group_name" "$disabled_tests" "${real_seconds:--}" "${max_rss:--}" \
      >> "$summary_file"
    verify_stdlib_source_unchanged
    echo "Official ${group_name} group exited without a Tasty pass summary" >&2
    exit 1
  fi
  if [ -n "$expected_tests" ] && \
     { [ "$passed_tests" -ne "$expected_tests" ] || [ "$disabled_tests" -ne 0 ]; }
  then
    printf '%s\t%s\t%s\tFAIL-INCOMPLETE-INVENTORY\t%s\t%s\n' \
      "$group_name" "$passed_tests" "$disabled_tests" "$real_seconds" "$max_rss" \
      >> "$summary_file"
    verify_stdlib_source_unchanged
    echo "Official ${group_name} inventory mismatch: $passed_tests executed, $disabled_tests disabled" >&2
    exit 1
  fi
  verify_stdlib_source_unchanged
  if [ "$OFFICIAL_SUITE_GROUP" = std-lib-succeed ]; then
    actual_interface_inventory_file="$evidence_dir/actual-interface-inventory.txt"
    (
      CDPATH= cd -- "$workspace_root/test/LibSucceed"
      find . -type f -name '*.agdai' -print |
        sed -e 's#^\./_build/[^/]*/agda/#./#' -e 's/\.agdai$/.agda/' |
        LC_ALL=C sort
    ) > "$actual_interface_inventory_file"
    input_interfaces=$(wc -l < "$actual_interface_inventory_file" | tr -d ' ')
    stdlib_interfaces=$(find "$workspace_root/std-lib" -type f -name '*.agdai' | wc -l | tr -d ' ')
    if ! cmp -s "$expected_interface_inventory_file" "$actual_interface_inventory_file"; then
      printf '%s\t%s\t%s\tFAIL-INCOMPLETE-INTERFACES\t%s\t%s\n' \
        "$group_name" "$passed_tests" "$disabled_tests" "$real_seconds" "$max_rss" \
        >> "$summary_file"
      echo "LibSucceed reachable interface inventory mismatch: expected $expected_input_interfaces, found $input_interfaces" >&2
      diff -u "$expected_interface_inventory_file" "$actual_interface_inventory_file" >&2 || true
      exit 1
    fi
  fi
  if [ "$prepare_stdlib_interfaces" -eq 1 ]; then
    printf 'check\tcount\n%s\t%s\nEverything-imports\t%s\nprepared-interfaces\t%s\nEverything-interface\t%s\n' \
      "$execution_count_label" \
      "$passed_tests" "$everything_imports" "$prepared_interfaces" "$everything_interface" \
      > "$evidence_dir/execution-counts.tsv"
  elif [ "$uses_stdlib" -eq 1 ]; then
    if [ "$OFFICIAL_SUITE_GROUP" = std-lib-succeed ]; then
      printf 'check\tcount\n%s\t%s\nsource-modules\t%s\ninput-interfaces\t%s\nstdlib-interfaces\t%s\n' \
        "$execution_count_label" "$passed_tests" "$actual_source_items" \
        "$input_interfaces" "$stdlib_interfaces" \
        > "$evidence_dir/execution-counts.tsv"
    else
      printf 'check\tcount\n%s\t%s\n' \
        "$execution_count_label" "$passed_tests" \
        > "$evidence_dir/execution-counts.tsv"
    fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$group_name" "$passed_tests" "$disabled_tests" \
    "$pass_status" "$real_seconds" "$max_rss" >> "$summary_file"
  echo "Official ${group_name} ${pass_status}: ${passed_tests} executed, ${disabled_tests} upstream disabled"
  echo "Evidence: $summary_file"
else
  real_seconds=$(awk '$2 == "real" { print $1; exit }' "$stderr_log")
  max_rss=$(awk '/maximum resident set size/ { print $1; exit }' "$stderr_log")
  printf '%s\t-\t-\tFAIL\t%s\t%s\n' \
    "$group_name" "${real_seconds:--}" "${max_rss:--}" >> "$summary_file"
  verify_stdlib_source_unchanged
  echo "Official ${group_name} group failed" >&2
  tail -n 320 "$stdout_log" >&2
  tail -n 320 "$stderr_log" >&2
  exit 1
fi
