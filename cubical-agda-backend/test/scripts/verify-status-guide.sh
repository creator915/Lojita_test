#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
goals="$repo_root/GOALS.md"
checklist="$repo_root/DELIVERY_CHECKLIST.md"
readme="$repo_root/README.md"
status_doc="$repo_root/docs/STATUS.md"
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

for file in "$goals" "$checklist" "$readme" "$status_doc" "$runtime_source"
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
goal_open_count=$(grep -Fxc '**状态：未实现。**' "$goals" || true)
[ "$goal_open_count" -eq 0 ] || fail "a component goal is still marked wholly unimplemented"
require_text "$goals" '**状态：已实现并通过专项及 clean-clone 验收。**'
require_text "$goals" '**状态：已实现并通过专项验收；三路调度集成仍在 F 节开放。**'
require_text "$goals" '现有 compiler-process NbE candidate 不等于目标 3'
require_text "$goals" '目标 1 使用独立的 stock MAlonzo/GHC 路径'

done_count=$(awk '/^- \[[xX]\] / { count++ } END { print count + 0 }' "$checklist")
open_count=$(awk '/^- \[ \] / { count++ } END { print count + 0 }' "$checklist")
total_count=$((done_count + open_count))
completion_pct=$(awk -v done="$done_count" -v total="$total_count" \
  'BEGIN { printf "%.1f", 100 * done / total }')
[ "$done_count" -eq 43 ] || fail "completed checklist count is $done_count, expected 43"
[ "$open_count" -eq 13 ] || fail "open checklist count is $open_count, expected 13"
require_text "$checklist" \
  "新范围统计：$done_count/$total_count 项已完成（$completion_pct%）"
require_text "$checklist" '目标 1 为 9/9'
require_text "$checklist" '目标 2 为 8/9'
require_text "$checklist" '目标 3 为 11/11'
require_text "$checklist" 'static Chez 结果未被用于本节验收'
require_text "$checklist" 'compiler-process candidate 未被用于本节验收'

require_text "$readme" '| 1. stock Agda -> MAlonzo -> Haskell -> GHC 二进制 | **已实现并验收** |'
require_text "$readme" '| 3. 最终程序进程内 runtime NbE | **已实现并验收** |'
require_text "$status_doc" '| Complete revised checklist | 43/56 | 76.8% by item count; not effort-weighted |'

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

echo "Project status contract PASS ($done_count/$total_count; goals 1 and 3 closed, integration open)"
