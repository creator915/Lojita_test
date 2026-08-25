#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
source_root=${NBE_ADAPTER_SOURCE_ROOT:-$backend_dir}
identity_file=${NBE_ADAPTER_SOURCE_IDENTITY:-$source_root/config/nbe-adapter-source.identity.tsv}
evidence_dir=${NBE_ADAPTER_SOURCE_EVIDENCE_DIR:-$backend_dir/build/nbe-adapter-source-identity}

fail() {
  echo "NbE adapter source identity rejected: $*" >&2
  exit 1
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

identity_value() {
  wanted=$1
  awk -F '\t' -v wanted="$wanted" 'NR > 1 && $1 == wanted { print $2; exit }' "$identity_file"
}

safe_relative_path() {
  printf '%s\n' "$1" | awk '
    /^\// { exit 1 }
    /(^|\/)\.\.?(\/|$)/ { exit 1 }
    /\/\// { exit 1 }
    /\/$/ { exit 1 }
    !/^[A-Za-z0-9._\/-]+$/ { exit 1 }
    { exit 0 }
  '
}

[ -d "$source_root" ] || fail "source root is missing: $source_root"
[ -f "$identity_file" ] || fail "identity record is missing: $identity_file"

temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/nbe-adapter-source-identity.XXXXXX")
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
  approved-at decision-owner file-count file-list license-file \
  license-file-sha256 license-spdx license-status patch-count provider \
  repository revision schema selection-eligibility source-boundary \
  source-bytes source-manifest-sha256 vcs-status \
  | LC_ALL=C sort > "$expected_keys"

if ! awk -F '\t' '
  NR == 1 {
    if ($0 != "key\tvalue") exit 1
    next
  }
  NF != 2 || $1 == "" || $2 == "" { exit 1 }
  { print $1 }
' "$identity_file" > "$actual_keys"
then
  fail "identity must have the key/value header and one non-empty tab-separated value per row"
fi

LC_ALL=C sort "$actual_keys" > "$sorted_keys"
if ! cmp -s "$expected_keys" "$sorted_keys"; then
  diff -u "$expected_keys" "$sorted_keys" >&2 || true
  fail "identity fields are missing, duplicated, or unknown"
fi

schema=$(identity_value schema)
provider=$(identity_value provider)
source_boundary=$(identity_value source-boundary)
file_list_rel=$(identity_value file-list)
expected_file_count=$(identity_value file-count)
expected_source_bytes=$(identity_value source-bytes)
expected_manifest_sha256=$(identity_value source-manifest-sha256)
vcs_status=$(identity_value vcs-status)
repository=$(identity_value repository)
revision=$(identity_value revision)
license_status=$(identity_value license-status)
license_spdx=$(identity_value license-spdx)
license_file_rel=$(identity_value license-file)
expected_license_sha256=$(identity_value license-file-sha256)
expected_patch_count=$(identity_value patch-count)
selection_eligibility=$(identity_value selection-eligibility)
decision_owner=$(identity_value decision-owner)
approved_at=$(identity_value approved-at)

[ "$schema" = 1 ] || fail "unsupported schema: $schema"
[ "$provider" = agda-specific-in-process-v1 ] || fail "unexpected provider: $provider"
[ "$source_boundary" = engine-request-v1-provider-source-v1 ] || fail "unexpected source boundary: $source_boundary"
printf '%s\n' "$expected_file_count" | grep -Eq '^[1-9][0-9]*$' || fail "file-count is not a positive integer"
printf '%s\n' "$expected_source_bytes" | grep -Eq '^[1-9][0-9]*$' || fail "source-bytes is not a positive integer"
printf '%s\n' "$expected_manifest_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail "source manifest hash is malformed"
printf '%s\n' "$expected_patch_count" | grep -Eq '^[0-9]+$' || fail "patch-count is not a non-negative integer"
safe_relative_path "$file_list_rel" || fail "unsafe file-list path: $file_list_rel"

file_list="$source_root/$file_list_rel"
[ -f "$file_list" ] || fail "source file list is missing: $file_list_rel"
[ ! -L "$file_list" ] || fail "source file list must not be a symlink"

source_rows="$temporary_dir/source-rows.tsv"
source_paths="$temporary_dir/source-paths"
sorted_paths="$temporary_dir/source-paths.sorted"

if ! awk -F '\t' '
  NR == 1 {
    if ($0 != "path\trole") exit 1
    next
  }
  NF != 2 || $1 == "" || $2 == "" { exit 1 }
  $1 ~ /^\// || $1 ~ /(^|\/)\.\.?(\/|$)/ || $1 ~ /\/\// || $1 ~ /\/$/ { exit 1 }
  $1 !~ /^[A-Za-z0-9._\/-]+$/ { exit 1 }
  $2 !~ /^(engine-boundary|evaluator-readback|plugin-entry|patch)$/ { exit 1 }
  seen[$1]++ { exit 1 }
  { print $1 "\t" $2 }
  END {
    if (NR < 2) exit 1
  }
' "$file_list" > "$source_rows"
then
  fail "source file list is malformed, unsafe, duplicated, or contains an unknown role"
fi

cut -f 1 "$source_rows" > "$source_paths"
LC_ALL=C sort "$source_paths" > "$sorted_paths"
cmp -s "$source_paths" "$sorted_paths" || fail "source file list must be sorted by path"

for required_role in engine-boundary evaluator-readback plugin-entry
do
  awk -F '\t' -v role="$required_role" '$2 == role { found = 1 } END { exit !found }' "$source_rows" \
    || fail "source file list is missing required role: $required_role"
done

mkdir -p "$evidence_dir"
manifest="$evidence_dir/source.manifest.tsv"
printf 'path\trole\tbytes\tsha256\n' > "$manifest"

tab=$(printf '\t')
actual_file_count=0
actual_source_bytes=0
actual_patch_count=0
while IFS="$tab" read -r relative_path role
do
  source_file="$source_root/$relative_path"
  [ -f "$source_file" ] || fail "listed source file is missing: $relative_path"
  [ ! -L "$source_file" ] || fail "listed source file must not be a symlink: $relative_path"
  file_bytes=$(wc -c < "$source_file" | tr -d ' ')
  file_sha256=$(sha256_file "$source_file")
  printf '%s\t%s\t%s\t%s\n' "$relative_path" "$role" "$file_bytes" "$file_sha256" >> "$manifest"
  actual_file_count=$((actual_file_count + 1))
  actual_source_bytes=$((actual_source_bytes + file_bytes))
  if [ "$role" = patch ]; then
    case "$relative_path" in
      patches/nbe/*) ;;
      *) fail "patch role must live below patches/nbe: $relative_path" ;;
    esac
    actual_patch_count=$((actual_patch_count + 1))
  fi
done < "$source_rows"

actual_manifest_sha256=$(sha256_file "$manifest")
[ "$actual_file_count" = "$expected_file_count" ] || fail "file-count mismatch: expected $expected_file_count, found $actual_file_count"
[ "$actual_source_bytes" = "$expected_source_bytes" ] || fail "source-bytes mismatch: expected $expected_source_bytes, found $actual_source_bytes"
[ "$actual_manifest_sha256" = "$expected_manifest_sha256" ] || fail "source manifest hash mismatch: expected $expected_manifest_sha256, found $actual_manifest_sha256"
[ "$actual_patch_count" = "$expected_patch_count" ] || fail "patch-count mismatch: expected $expected_patch_count, found $actual_patch_count"

if [ -d "$source_root/patches/nbe" ]; then
  on_disk_patch_count=$(find "$source_root/patches/nbe" -type f | wc -l | tr -d ' ')
else
  on_disk_patch_count=0
fi
[ "$on_disk_patch_count" = "$actual_patch_count" ] || fail "unlisted files exist below patches/nbe"

case "$selection_eligibility" in
  blocked)
    case "$vcs_status" in
      absent)
        [ "$repository" = UNRESOLVED ] || fail "absent VCS must not claim a repository"
        [ "$revision" = UNRESOLVED ] || fail "absent VCS must not claim a revision"
        if git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
          fail "vcs-status absent conflicts with a discovered Git worktree"
        fi
        ;;
      present)
        printf '%s\n' "$repository" | grep -Eq '^(https://|ssh://|git@|file://)' || \
          fail "present VCS needs an explicit repository URI"
        [ "$revision" = UNRESOLVED ] || \
          printf '%s\n' "$revision" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' || \
          fail "blocked VCS revision must be UNRESOLVED or a full commit ID"
        git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
          fail "vcs-status present but source is not in a Git worktree"
        # A blocked, unresolved identity pins the checked content but is not a
        # production provenance claim.  Clean clones of forks therefore need
        # not have the upstream repository as their origin.  Eligible sources
        # below remain pinned to both the exact repository and revision.
        git -C "$source_root" remote get-url origin >/dev/null 2>&1 || \
          fail "vcs-status present but source has no origin remote"
        ;;
      *) fail "blocked identity vcs-status must be absent or present" ;;
    esac
    [ "$license_status" = owner-action-required ] || fail "blocked identity must require owner license action"
    [ "$license_spdx" = NOASSERTION ] || fail "blocked identity must use license-spdx NOASSERTION"
    [ "$license_file_rel" = UNRESOLVED ] || fail "blocked identity must not claim a license file"
    [ "$expected_license_sha256" = UNRESOLVED ] || fail "blocked identity must not claim a license hash"
    [ "$decision_owner" = UNRESOLVED ] || fail "blocked identity must not claim an approving owner"
    [ "$approved_at" = UNRESOLVED ] || fail "blocked identity must not claim an approval date"
    for license_scope in "$source_root" "$(dirname -- "$source_root")"
    do
      if find "$license_scope" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \) -print -quit | grep -q .; then
        fail "license evidence exists but the identity still records owner-action-required"
      fi
    done
    ;;
  eligible)
    [ "$vcs_status" = present ] || fail "eligible identity must record vcs-status present"
    printf '%s\n' "$repository" | grep -Eq '^(https://|ssh://|git@|file://)' || fail "eligible identity needs an explicit repository URI"
    printf '%s\n' "$revision" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' || fail "eligible identity needs a full commit ID"
    [ "$license_status" = approved ] || fail "eligible identity needs license-status approved"
    case "$license_spdx" in
      NOASSERTION|NONE|UNKNOWN|UNRESOLVED) fail "eligible identity needs a concrete SPDX license expression" ;;
    esac
    safe_relative_path "$license_file_rel" || fail "unsafe license file path: $license_file_rel"
    license_file="$source_root/$license_file_rel"
    [ -f "$license_file" ] || fail "approved license file is missing: $license_file_rel"
    [ ! -L "$license_file" ] || fail "approved license file must not be a symlink"
    printf '%s\n' "$expected_license_sha256" | grep -Eq '^[0-9a-f]{64}$' || fail "approved license hash is malformed"
    actual_license_sha256=$(sha256_file "$license_file")
    [ "$actual_license_sha256" = "$expected_license_sha256" ] || fail "approved license hash mismatch"
    case "$decision_owner" in UNRESOLVED|UNKNOWN|'') fail "eligible identity needs a decision owner" ;; esac
    printf '%s\n' "$approved_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || fail "eligible identity needs an approval date"
    git -C "$source_root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "eligible source is not in a Git worktree"
    actual_revision=$(git -C "$source_root" rev-parse HEAD)
    [ "$actual_revision" = "$revision" ] || fail "Git revision mismatch: expected $revision, found $actual_revision"
    actual_repository=$(git -C "$source_root" remote get-url origin 2>/dev/null) || fail "eligible source has no origin remote"
    [ "$actual_repository" = "$repository" ] || fail "Git origin mismatch: expected $repository, found $actual_repository"
    set --
    while IFS="$tab" read -r relative_path role
    do
      set -- "$@" "$relative_path"
    done < "$source_rows"
    set -- "$@" "$file_list_rel" "$license_file_rel"
    [ -z "$(git -C "$source_root" status --porcelain -- "$@")" ] || fail "eligible source or license differs from the pinned revision"
    ;;
  *)
    fail "selection-eligibility must be blocked or eligible"
    ;;
esac

cp "$identity_file" "$evidence_dir/source.identity.tsv"
{
  printf 'key\tvalue\n'
  printf 'schema\t1\n'
  printf 'provider\t%s\n' "$provider"
  printf 'source-manifest-sha256\t%s\n' "$actual_manifest_sha256"
  printf 'source-files\t%s\n' "$actual_file_count"
  printf 'source-bytes\t%s\n' "$actual_source_bytes"
  printf 'patch-count\t%s\n' "$actual_patch_count"
  printf 'license-status\t%s\n' "$license_status"
  printf 'selection-eligibility\t%s\n' "$selection_eligibility"
  printf 'verification\tpass\n'
} > "$evidence_dir/verification.tsv"

if [ "$selection_eligibility" = eligible ]; then
  echo "NBE-ADAPTER-SOURCE-IDENTITY ELIGIBLE-PASS ($provider@$revision, $license_spdx)"
else
  echo "NBE-ADAPTER-SOURCE-IDENTITY CONTENT-PASS (promotion blocked: revision/license owner action required)"
fi
