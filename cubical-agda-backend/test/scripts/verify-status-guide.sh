#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
goals="$repo_root/GOALS.md"
checklist="$repo_root/DELIVERY_CHECKLIST.md"
readme="$repo_root/README.md"
status_doc="$repo_root/docs/STATUS.md"
support_matrix="$repo_root/docs/SUPPORT-MATRIX.md"
test_results="$repo_root/docs/TEST-RESULTS.md"
selection_doc="$repo_root/docs/NBE_SELECTION.md"
runtime_lock="$repo_root/config/runtime-nbe-provider.lock.tsv"
runtime_prototype="$repo_root/runtime/nbe/src/Cubical/Runtime/Nbe.hs"
workflow="$repo_root/../.github/workflows/goal1-native.yml"
runtime_source="$repo_root/runtime/agda-2.9/src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs"

fail() {
  echo "Project status contract FAIL: $*" >&2
  exit 1
}

require_text() {
  file=$1
  needle=$2
  grep -Fq -- "$needle" "$file" || fail "$file is missing: $needle"
}

for file in "$goals" "$checklist" "$readme" "$status_doc" "$support_matrix" \
  "$test_results" "$selection_doc" "$runtime_lock" "$runtime_prototype" "$runtime_source"
do
  [ -s "$file" ] || fail "required file is missing or empty: $file"
done

for path in src runtime config compat test docs Makefile
do
  [ -e "$repo_root/$path" ] || fail "root layout path is missing: $path"
done

for raw in chat.md answer.md Cubical-Agda-后端技术结论.md 'TransportTests (4).agda'
do
  [ ! -e "$repo_root/$raw" ] || fail "raw input remains at repository root: $raw"
done

require_text "$goals" '## 目标 1：原版编译器的本地二进制路径'
require_text "$goals" '## 目标 2：跨进程 Term 搬运'
require_text "$goals" '## 目标 3：最终程序进程内的 runtime NbE'
require_text "$goals" '**状态：已实现并通过专项及 clean-clone 验收。**'
require_text "$goals" '**状态：未完成；当前仅完成进程与数据边界定义。**'
require_text "$goals" '现有 compiler-process NbE candidate 不等于目标 3'
require_text "$goals" '目标 1 使用独立的 stock MAlonzo/GHC 路径'

done_count=$(awk '/^- \[[xX]\] / { count++ } END { print count + 0 }' "$checklist")
open_count=$(awk '/^- \[ \] / { count++ } END { print count + 0 }' "$checklist")
total_count=$((done_count + open_count))
completion_pct=$(awk -v done="$done_count" -v total="$total_count" \
  'BEGIN { printf "%.1f", 100 * done / total }')
[ "$done_count" -eq 31 ] || fail "completed checklist count is $done_count, expected 31"
[ "$open_count" -eq 25 ] || fail "open checklist count is $open_count, expected 25"
require_text "$checklist" \
  "新范围统计：$done_count/$total_count 项已完成（$completion_pct%）"
require_text "$checklist" '目标 1 为 9/9'
require_text "$checklist" '目标 2 为 8/9'
require_text "$checklist" '目标 3 为 1/11'
require_text "$checklist" 'static Chez 结果未被用于本节验收'
require_text "$checklist" '自定义 `Ty`/`Term` AST 的原型'

require_text "$readme" '| 1. stock Agda -> MAlonzo -> Haskell -> GHC 二进制 | **已实现并验收** |'
require_text "$readme" '| 3. 最终程序进程内 runtime NbE | **未完成（1/11）** |'
require_text "$status_doc" '| Complete revised checklist | 31/56 | 55.4% by item count; not effort-weighted |'
require_text "$status_doc" '| 3. linked NbE inside the final program process | 1/11 | NOT IMPLEMENTED; boundary only |'
require_text "$support_matrix" '| Goal 3 NbE linked into the final program process | `NOT-VERIFIED` |'
require_text "$test_results" 'Goal 3 remains at 1/11.'
require_text "$test_results" '`KNOWN-SEMANTIC-BUG`'
require_text "$selection_doc" 'GOAL 3 PROVIDER NOT SELECTED'
require_text "$status_doc" 'it covers Goal'
require_text "$status_doc" '1 and provides no Goal 3 CI evidence.'
[ -s "$workflow" ] || fail "Goal 1 workflow is missing"
require_text "$workflow" 'locked-stock-native'
if grep -Eq 'verify-runtime-nbe|verify-goal3|Goal 3|goal3' "$workflow"; then
  fail "status documentation must be revised if Goal 3 CI coverage is added"
fi

lock_status=$(awk -F '\t' '$1 == "status" { print $2; exit }' "$runtime_lock")
[ "$lock_status" = reference-only ] || fail "Goal 3 provider lock must remain reference-only"
lock_acceptance=$(awk -F '\t' '$1 == "goal3-acceptance" { print $2; exit }' "$runtime_lock")
[ "$lock_acceptance" = blocked ] || fail "Goal 3 provider acceptance must remain blocked"
require_text "$runtime_prototype" 'data Ty'
require_text "$runtime_prototype" 'data Term'
require_text "$runtime_prototype" 'This is not a Goal 3 runtime'
if grep -Eq 'import[[:space:]]+Agda\.Syntax\.Internal' "$runtime_prototype"; then
  fail "status contract must be revised before claiming the prototype is Agda-connected"
fi

goal3_checked=$(awk '
  /^## E\. / { in_goal=1; next }
  /^## / && in_goal { exit }
  in_goal && /^- \[[xX]\] / { count++ }
  END { print count + 0 }
' "$checklist")
[ "$goal3_checked" -eq 1 ] || fail "Goal 3 has $goal3_checked checked items, expected boundary-only 1"

require_text "$runtime_source" 'maxRuntimePacketBytes = 64 * 1024 * 1024'
require_text "$runtime_source" 'cubicalRuntimeResultTermFile'
[ -s "$repo_root/test/fixtures/TransportTests.agda" ] || \
  fail "maintained monolithic fixture is missing"

if command -v git >/dev/null 2>&1 && git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git -C "$repo_root" ls-files | grep -Eq '^(backend/|chat\.md$|answer\.md$|.*\.zip$)'; then
    fail "Git delivery tree contains a retired root or raw material"
  fi
fi

if grep -Fq 'make -C backend' \
  "$readme" "$goals" "$checklist" "$repo_root"/docs/*.md "$repo_root/Makefile"; then
  fail "pre-flattening make command remains"
fi

echo "Project status contract PASS ($done_count/$total_count; goal 1 closed, goal 3 boundary-only 1/11)"
