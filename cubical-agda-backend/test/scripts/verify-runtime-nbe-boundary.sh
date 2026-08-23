#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
boundary="$repo_root/config/runtime-nbe-boundary.tsv"
guide="$repo_root/docs/RUNTIME_NBE_BOUNDARY.md"
goals="$repo_root/GOALS.md"
architecture="$repo_root/docs/ARCHITECTURE.md"

fail() {
  echo "Runtime NbE boundary contract FAIL: $*" >&2
  exit 1
}

value() {
  key=$1
  awk -F '\t' -v key="$key" '
    NR > 1 && $1 == key { count++; value=$2 }
    END { if (count != 1 || value == "") exit 1; print value }
  ' "$boundary" || fail "missing or duplicate boundary key: $key"
}

for file in "$boundary" "$guide" "$goals" "$architecture"
do
  [ -s "$file" ] || fail "required file is missing or empty: $file"
done

[ "$(value format)" = runtime-nbe-boundary-v1 ] || fail "wrong boundary format"
[ "$(value execution-process)" = final-user-program-process ] ||
  fail "execution process is not the final user program"
[ "$(value linkage)" = linked-library-in-final-executable ] ||
  fail "runtime linkage is not fixed"
[ "$(value request)" = checked-term+type+closed-definition-slice+context-identity ] ||
  fail "request boundary is not fixed"
[ "$(value result)" = reified-term+type-or-closed-error ] ||
  fail "result boundary is not fixed"
[ "$(value compile-runtime-transfer)" = versioned-immutable-bytes ] ||
  fail "compile/runtime transfer is not immutable and versioned"

for key in semantic-closure-transfer tcstate-transfer compiler-callback \
  agda-subprocess network-provider
do
  [ "$(value "$key")" = forbidden ] || fail "$key is not fail closed"
done

for fact in \
  'operating-system process created when the user executes' \
  'linked into that' \
  'may not spawn Agda' \
  'checked Internal `Term + Type` pair' \
  'Semantic values, environments, Haskell closures, `TCState`' \
  'goal remains unimplemented'
do
  grep -Fq -- "$fact" "$guide" || fail "guide is missing: $fact"
done

grep -Fq '最终用户程序的运行进程，不是 Agda' "$goals" ||
  fail "GOALS process definition drifted"
grep -Fq 'compiler-process' "$architecture" ||
  fail "architecture no longer distinguishes compiler process"

echo 'Runtime NbE boundary contract PASS (final process, immutable checked data, no compiler/closure crossing)'
