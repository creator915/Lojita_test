#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
dispatcher=$repo_root/bin/cubical-agda-dispatch
workspace=$(mktemp -d "${TMPDIR:-/tmp}/three-lane-dispatch.XXXXXX")
cleanup() {
  rm -rf "$workspace"
}
trap cleanup EXIT HUP INT TERM

fail() {
  echo "ThreeLaneDispatchRegression FAIL: $*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

require_field() {
  file=$1
  key=$2
  expected=$3
  awk -F '\t' -v key="$key" -v expected="$expected" '
    $1 == key && $2 == expected { found++ }
    END { if (found != 1) exit 1 }
  ' "$file" || fail "$file is missing $key=$expected"
}

write_analysis() {
  file=$1
  binding=$2
  reason=$3
  action=$4
  decision=$5
  if [ "$binding" = static ]; then
    erasure=true
  else
    erasure=false
  fi
  {
    printf 'binding-time: %s\n' "$binding"
    printf 'binding-time-scope: whole-entry\n'
    printf 'binding-time-reason: %s\n' "$reason"
    printf 'binding-time-action: %s\n' "$action"
    printf 'decision: %s\n' "$decision"
    printf 'type-erasure-authorized: %s\n' "$erasure"
    printf 'source-sha256: %s\n' "$(sha256_file "$workspace/source.agda")"
  } > "$file"
}

make_executor() {
  path=$1
  name=$2
  cat > "$path" <<EOF
#!/bin/sh
printf '%s|%s|%s\n' '$name' "\$CUBICAL_DISPATCH_LANE" "\${1-}" >> "\$DISPATCH_LOG"
EOF
  chmod +x "$path"
}

printf '%s\n' 'module DispatchFixture where' > "$workspace/source.agda"
write_analysis "$workspace/static.txt" static no-runtime-blockers \
  erase-types-and-emit static-closed
write_analysis "$workspace/dynamic.txt" dynamic whole-entry-runtime-head \
  typed-residual-whole-entry typed-residual
write_analysis "$workspace/mixed.txt" mixed static-context-around-runtime-blocker \
  typed-residual-split-shell-ground-observation-by-id-whole-entry-reference \
  typed-residual
write_analysis "$workspace/unsupported.txt" unsupported \
  internal-treeless-audit-disagreement reject unsupported

make_executor "$workspace/native" native
make_executor "$workspace/packet" packet
make_executor "$workspace/runtime-nbe" runtime-nbe
cat > "$workspace/failing" <<'EOF'
#!/bin/sh
exit 23
EOF
chmod +x "$workspace/failing"

export DISPATCH_LOG=$workspace/dispatch.log
: > "$DISPATCH_LOG"

"$dispatcher" \
  --analysis "$workspace/static.txt" \
  --source "$workspace/source.agda" \
  --boundary none \
  --provenance "$workspace/native.provenance.tsv" \
  --native-exec "$workspace/native" \
  --native-arg 'native argument with spaces' \
  > "$workspace/native.stdout"
grep -Fqx 'native|native|native argument with spaces' "$DISPATCH_LOG" ||
  fail "native decision did not execute only the native lane"
require_field "$workspace/native.provenance.tsv" lane native
cp "$workspace/native.provenance.tsv" "$workspace/native.first.tsv"
"$dispatcher" \
  --analysis "$workspace/static.txt" \
  --source "$workspace/source.agda" \
  --boundary none \
  --provenance "$workspace/native.provenance.tsv" \
  --native-exec "$workspace/native" \
  --native-arg 'native argument with spaces' \
  > /dev/null
cmp "$workspace/native.first.tsv" "$workspace/native.provenance.tsv" ||
  fail "identical analysis did not produce stable provenance"

: > "$DISPATCH_LOG"
"$dispatcher" \
  --analysis "$workspace/dynamic.txt" \
  --source "$workspace/source.agda" \
  --boundary cross-process \
  --provenance "$workspace/packet.provenance.tsv" \
  --packet-exec "$workspace/packet" \
  --packet-arg packet.bin \
  > "$workspace/packet.stdout"
grep -Fqx 'packet|packet|packet.bin' "$DISPATCH_LOG" ||
  fail "cross-process decision did not execute only the packet lane"
require_field "$workspace/packet.provenance.tsv" boundary cross-process

: > "$DISPATCH_LOG"
"$dispatcher" \
  --analysis "$workspace/mixed.txt" \
  --source "$workspace/source.agda" \
  --boundary in-process \
  --provenance "$workspace/runtime.provenance.tsv" \
  --runtime-nbe-exec "$workspace/runtime-nbe" \
  --runtime-nbe-arg runtime.packet \
  > "$workspace/runtime.stdout"
grep -Fqx 'runtime-nbe|runtime-nbe|runtime.packet' "$DISPATCH_LOG" ||
  fail "in-process decision did not execute only the runtime-nbe lane"
require_field "$workspace/runtime.provenance.tsv" lane runtime-nbe

expect_reject() {
  label=$1
  shift
  : > "$DISPATCH_LOG"
  if "$dispatcher" "$@" > "$workspace/$label.stdout" 2> "$workspace/$label.stderr"; then
    fail "$label unexpectedly dispatched"
  fi
  [ ! -s "$DISPATCH_LOG" ] || fail "$label executed a lane before rejection"
  grep -Fq 'CCZ-DISPATCH-REJECT' "$workspace/$label.stderr" ||
    fail "$label did not emit the stable rejection class"
}

expect_reject static-cross \
  --analysis "$workspace/static.txt" --source "$workspace/source.agda" \
  --boundary cross-process --provenance "$workspace/reject.tsv" \
  --packet-exec "$workspace/packet"
expect_reject dynamic-none \
  --analysis "$workspace/dynamic.txt" --source "$workspace/source.agda" \
  --boundary none --provenance "$workspace/reject.tsv" \
  --native-exec "$workspace/native"
expect_reject unsupported \
  --analysis "$workspace/unsupported.txt" --source "$workspace/source.agda" \
  --boundary in-process --provenance "$workspace/reject.tsv" \
  --runtime-nbe-exec "$workspace/runtime-nbe"

cp "$workspace/dynamic.txt" "$workspace/duplicate.txt"
printf 'binding-time: dynamic\n' >> "$workspace/duplicate.txt"
expect_reject duplicate-analysis \
  --analysis "$workspace/duplicate.txt" --source "$workspace/source.agda" \
  --boundary cross-process --provenance "$workspace/reject.tsv" \
  --packet-exec "$workspace/packet"

printf 'stale provenance\n' > "$workspace/failure.provenance.tsv"
set +e
"$dispatcher" \
  --analysis "$workspace/dynamic.txt" \
  --source "$workspace/source.agda" \
  --boundary cross-process \
  --provenance "$workspace/failure.provenance.tsv" \
  --packet-exec "$workspace/failing" \
  > "$workspace/failure.stdout" 2> "$workspace/failure.stderr"
failure_status=$?
set -e
[ "$failure_status" -eq 23 ] ||
  fail "lane failure status changed: $failure_status"
[ ! -e "$workspace/failure.provenance.tsv" ] ||
  fail "failed lane left stale success provenance"

for provenance in \
  "$workspace/native.provenance.tsv" \
  "$workspace/packet.provenance.tsv" \
  "$workspace/runtime.provenance.tsv"
do
  for identity in source-sha256 analysis-sha256 executor-sha256 arguments-sha256
  do
    awk -F '\t' -v key="$identity" '
      $1 == key && length($2) == 64 && $2 !~ /[^0-9a-f]/ { found++ }
      END { if (found != 1) exit 1 }
    ' "$provenance" || fail "$provenance has no valid $identity"
  done
done

if grep -Eq '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)' "$dispatcher"; then
  fail "dispatcher contains shell eval"
fi

echo 'ThreeLaneDispatchRegression PASS (native/packet/runtime-nbe; stable provenance; fail closed)'
