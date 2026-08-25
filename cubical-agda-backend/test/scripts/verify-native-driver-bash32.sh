#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

driver=bin/cubical-agda-native

fail() {
  echo "native driver Bash 3.2 FAIL: $*" >&2
  exit 1
}

[ -x "$driver" ] || fail "driver is missing or not executable"

# Bash 3.2 plus nounset rejects expansion of a truly empty array.  The driver
# uses a sentinel and skips it, so the no---include path remains portable.
grep -Fq "declare -a include_dirs=('')" "$driver" ||
  fail "optional include array lacks the Bash 3.2 sentinel"
grep -Fq '[[ -n $include_dir ]] || continue' "$driver" ||
  fail "optional include sentinel is not skipped"
if grep -Fq 'declare -a include_dirs=()' "$driver"; then
  fail "Bash 3.2-incompatible empty include array remains"
fi

BASH_COMPAT=3.2 bash --noprofile --norc "$driver" --help >/dev/null ||
  fail "driver cannot be parsed/executed in Bash 3.2 compatibility mode"

# Execute the exact empty-array pattern under nounset as a regression witness:
# it fails on Bash 3.2, while the sentinel form used by the driver succeeds.
BASH_COMPAT=3.2 bash --noprofile --norc -c \
  "set -u; declare -a xs=(''); for x in \"\${xs[@]}\"; do [[ -n \$x ]] || continue; false; done" ||
  fail "sentinel expansion is not safe under Bash 3.2 nounset semantics"

echo 'NativeDriverBash32 PASS (empty optional include list is nounset-safe)'
