#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_root=${NBE_ADAPTER_SOURCE_ROOT:-$backend_dir}
identity_file=${NBE_ADAPTER_SOURCE_IDENTITY:-$source_root/config/nbe-adapter-source.identity.tsv}
lock_file=${NBE_ADAPTER_LOCK:-$source_root/config/nbe-adapter.lock.tsv}

identity_value() {
  wanted=$1
  awk -F '\t' -v wanted="$wanted" 'NR > 1 && $1 == wanted { print $2; exit }' "$identity_file"
}

lock_value() {
  wanted=$1
  awk -F '\t' -v wanted="$wanted" '$1 == wanted { print $2; exit }' "$lock_file"
}

NBE_ADAPTER_SOURCE_ROOT="$source_root" \
NBE_ADAPTER_SOURCE_IDENTITY="$identity_file" \
  sh "$script_dir/verify-nbe-adapter-source-identity.sh"

if [ "$(identity_value selection-eligibility)" != eligible ]; then
  echo "CCZ-NBE-PROMOTION-BLOCKED: revision, license, and owner approval remain unresolved" >&2
  exit 1
fi

sh "$script_dir/verify-nbe-adapter-lock.sh" "$lock_file"
[ "$(lock_value status)" = selected ] || {
  echo "CCZ-NBE-PROMOTION-BLOCKED: adapter lock is not selected" >&2
  exit 1
}

compare_field() {
  identity_key=$1
  lock_key=$2
  identity_result=$(identity_value "$identity_key")
  lock_result=$(lock_value "$lock_key")
  [ "$identity_result" = "$lock_result" ] || {
    echo "CCZ-NBE-PROMOTION-BLOCKED: $lock_key does not match source identity" >&2
    exit 1
  }
}

compare_field provider provider
compare_field repository repository
compare_field revision revision
compare_field source-manifest-sha256 source-sha256
compare_field license-spdx license
compare_field decision-owner decision-owner
compare_field approved-at approved-at

[ "$(lock_value integration)" = in-process ] || {
  echo "CCZ-NBE-PROMOTION-BLOCKED: this provider requires in-process integration" >&2
  exit 1
}
[ "$(lock_value adapter-api)" = engine-request-v1 ] || {
  echo "CCZ-NBE-PROMOTION-BLOCKED: adapter API does not match the source boundary" >&2
  exit 1
}
[ "$(lock_value acceptance-profile)" = formal-transport-v1 ] || {
  echo "CCZ-NBE-PROMOTION-BLOCKED: acceptance profile is not formal-transport-v1" >&2
  exit 1
}

echo "NBE-PRODUCTION-PROMOTION READY-PASS ($(lock_value provider)@$(lock_value revision))"
