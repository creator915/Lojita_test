#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
lock_file=${1:-"$backend_dir/config/nbe-adapter.lock.tsv"}

if [ ! -f "$lock_file" ]; then
  echo "NbE adapter lock is missing: $lock_file" >&2
  exit 2
fi

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/nbe-adapter-lock.XXXXXX")
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

expected_keys="$temporary_dir/expected-keys"
actual_keys="$temporary_dir/actual-keys"
sorted_keys="$temporary_dir/sorted-keys"

printf '%s\n' \
  acceptance-profile adapter-api approved-at decision-owner integration \
  license provider repository revision schema source-sha256 status \
  | LC_ALL=C sort > "$expected_keys"

if ! awk -F '\t' '
  NF != 2 { exit 1 }
  $1 == "" || $2 == "" { exit 1 }
  { print $1 }
' "$lock_file" > "$actual_keys"
then
  echo "NbE adapter lock must contain exactly one non-empty tab-separated key/value per line" >&2
  exit 1
fi

LC_ALL=C sort "$actual_keys" > "$sorted_keys"
if ! cmp -s "$expected_keys" "$sorted_keys"; then
  echo "NbE adapter lock fields are missing, duplicated, or unknown" >&2
  diff -u "$expected_keys" "$sorted_keys" >&2 || true
  exit 1
fi

lock_value() {
  key=$1
  awk -F '\t' -v wanted="$key" '$1 == wanted { print $2; exit }' "$lock_file"
}

schema=$(lock_value schema)
status=$(lock_value status)
provider=$(lock_value provider)
repository=$(lock_value repository)
revision=$(lock_value revision)
source_sha256=$(lock_value source-sha256)
license=$(lock_value license)
integration=$(lock_value integration)
adapter_api=$(lock_value adapter-api)
acceptance_profile=$(lock_value acceptance-profile)
decision_owner=$(lock_value decision-owner)
approved_at=$(lock_value approved-at)

if [ "$schema" != 1 ]; then
  echo "Unsupported NbE adapter lock schema: $schema" >&2
  exit 1
fi
if [ "$adapter_api" != engine-request-v1 ]; then
  echo "Unsupported NbE adapter API: $adapter_api" >&2
  exit 1
fi

case "$status" in
  unselected)
    for unresolved in \
      "$provider" "$repository" "$revision" "$source_sha256" "$license" \
      "$integration" "$acceptance_profile" "$decision_owner" "$approved_at"
    do
      if [ "$unresolved" != UNRESOLVED ]; then
        echo "An unselected NbE lock must not contain partial provider metadata" >&2
        exit 1
      fi
    done
    echo "NBE-ADAPTER-LOCK UNSELECTED-PASS"
    ;;
  selected)
    for selected_value in \
      "$provider" "$repository" "$revision" "$source_sha256" "$license" \
      "$integration" "$acceptance_profile" "$decision_owner" "$approved_at"
    do
      if [ "$selected_value" = UNRESOLVED ]; then
        echo "A selected NbE lock contains an unresolved field" >&2
        exit 1
      fi
    done
    if ! printf '%s\n' "$repository" | grep -Eq '^(https://|ssh://|git@|file://)'; then
      echo "Selected NbE repository is not an explicit repository URI" >&2
      exit 1
    fi
    if ! printf '%s\n' "$revision" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$'; then
      echo "Selected NbE revision must be a full 40- or 64-hex commit ID" >&2
      exit 1
    fi
    if ! printf '%s\n' "$source_sha256" | grep -Eq '^[0-9a-f]{64}$'; then
      echo "Selected NbE source-sha256 must be 64 lowercase hex characters" >&2
      exit 1
    fi
    case "$license" in
      NOASSERTION|NONE|UNKNOWN|UNRESOLVED)
        echo "Selected NbE license must be a concrete approved SPDX expression" >&2
        exit 1
        ;;
    esac
    case "$integration" in
      in-process|process) ;;
      *)
        echo "Selected NbE integration must be in-process or process" >&2
        exit 1
        ;;
    esac
    if [ "$acceptance_profile" != formal-transport-v1 ]; then
      echo "Selected NbE acceptance profile must be formal-transport-v1" >&2
      exit 1
    fi
    if ! printf '%s\n' "$approved_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      echo "Selected NbE approved-at must use YYYY-MM-DD" >&2
      exit 1
    fi
    echo "NBE-ADAPTER-LOCK SELECTED-PASS ($provider@$revision, $license, $integration)"
    ;;
  *)
    echo "Unknown NbE adapter lock status: $status" >&2
    exit 1
    ;;
esac
