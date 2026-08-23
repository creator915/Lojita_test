#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
readme="$repo_root/README.md"
goals="$repo_root/GOALS.md"
checklist="$repo_root/DELIVERY_CHECKLIST.md"
makefile="$repo_root/Makefile"
smoke="$repo_root/test/scripts/verify-smoke.sh"
binary="$repo_root/build/cubical-chez"

fail() {
  echo "README contract FAIL: $*" >&2
  exit 1
}

require_text() {
  file=$1
  needle=$2
  grep -Fq -- "$needle" "$file" || fail "$file is missing: $needle"
}

for file in "$readme" "$goals" "$checklist" "$makefile" "$smoke"
do
  [ -s "$file" ] || fail "required input is missing or empty: $file"
done
[ -x "$binary" ] || fail "build/cubical-chez is missing; run make build"

for heading in \
  '# Cubical Agda backend' \
  '## 当前状态' \
  '## 目标数据流' \
  '## 仓库布局' \
  '## 依赖' \
  '## 快速开始' \
  '## CLI' \
  '## 主要验收命令' \
  '## 文档' \
  '## 当前边界'
do
  require_text "$readme" "$heading"
done

for fact in \
  'stock Agda -> MAlonzo -> Haskell -> GHC 二进制 | **未实现**' \
  '最终程序进程内 runtime NbE | **未实现**' \
  'runtime/agda-2.9/' \
  '不在 Git' \
  '`CCZ-NBE-UNAVAILABLE`' \
  '`FAIL-CLOSED`'
do
  require_text "$readme" "$fact"
done

for command in 'make build' 'make verify-readme-quickstart' 'make verify'
do
  require_text "$readme" "$command"
done

for outcome in \
  'StaticOrdinary PASS (42)' \
  'StaticTransport PASS (0)' \
  'TypedResidual EXPECTED-REJECT (CCZ-RESIDUAL-REQUIRED)'
do
  require_text "$readme" "$outcome"
done

for variable in AGDA_PREFIX AGDA_PACKAGE_DB AGDA_LIBRARY_REGISTRY GHC_PREFIX GHC
do
  require_text "$makefile" "$variable"
  require_text "$readme" "$variable"
done

for variable in AGDA29_SOURCE_DIR CUBICAL29_DIR GHC29 CABAL29
do
  require_text "$readme" "$variable=/path/to/"
done

cli_specs=$(mktemp /private/tmp/cubical-chez-readme-cli.XXXXXX)
cleanup() {
  rm -f "$cli_specs"
}
trap cleanup EXIT HUP INT TERM
printf '%s\n' \
  '--cubical-chez' \
  '--cubical-chez-engine=agda-baseline|nbe' \
  '--cubical-chez-nbe-fallback=reject|agda-baseline' \
  '--cubical-chez-residual=reject|manifest|packet' \
  '--cubical-chez-packet-file=FILE|-' \
  '--cubical-chez-output=DIRECTORY' \
  '--cubical-chez-entry=NAME' > "$cli_specs"

cli_rows=$(awk '
  /^## CLI$/ { in_cli=1; next }
  in_cli && /^## / { in_cli=0 }
  in_cli && /^--cubical-chez/ { print }
' "$readme")
printf '%s\n' "$cli_rows" | cmp -s - "$cli_specs" || \
  fail 'README public CLI block is not the exact seven-option contract'

help_output=$($binary --help 2>&1)
while IFS= read -r spec
do
  option=${spec%%=*}
  printf '%s\n' "$help_output" | grep -Fq -- "$option" || \
    fail "binary help is missing $option"
done < "$cli_specs"

for path in src runtime/agda-2.9 config compat test/fixtures test/scripts docs build
do
  [ -e "$repo_root/$path" ] || fail "repository-layout path is missing: $path"
done

for link in \
  '(GOALS.md)' \
  '(DELIVERY_CHECKLIST.md)' \
  '(docs/ARCHITECTURE.md)' \
  '(docs/ENGINE_CONTRACT.md)' \
  '(docs/SUPPORT-MATRIX.md)' \
  '(docs/STATUS.md)' \
  '(docs/TEST-RESULTS.md)' \
  '(docs/BENCHMARKS.md)' \
  '(docs/NBE_SELECTION.md)' \
  '(docs/TROUBLESHOOTING.md)'
do
  require_text "$readme" "$link"
done

require_text "$makefile" 'verify-readme-guide: build'
require_text "$makefile" 'verify-readme-quickstart: build'
require_text "$makefile" 'sh test/scripts/verify-readme-guide.sh'
require_text "$makefile" 'sh test/scripts/verify-smoke.sh'

echo 'README contract PASS (root layout, 3 goal states, 7 CLI options)'
