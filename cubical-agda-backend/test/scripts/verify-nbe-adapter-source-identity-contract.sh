#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend_dir=$(CDPATH= cd -- "$script_dir/../.." && pwd)
validator="$script_dir/verify-nbe-adapter-source-identity.sh"
promotion_checker="$script_dir/check-nbe-production-promotion.sh"
evidence_dir="$backend_dir/build/nbe-adapter-source-identity-contract"
summary="$evidence_dir/summary.tsv"

temporary_dir=$(mktemp -d /private/tmp/nbe-adapter-source-contract.XXXXXX)
cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{ print $1 }'
  else
    shasum -a 256 "$1" | awk '{ print $1 }'
  fi
}

mkdir -p "$evidence_dir"
printf 'case\texpectation\tstatus\n' > "$summary"

run_pass() {
  name=$1
  shift
  "$@" > "$evidence_dir/$name.stdout" 2> "$evidence_dir/$name.stderr"
  printf '%s\tPASS\tPASS\n' "$name" >> "$summary"
}

run_reject() {
  name=$1
  shift
  set +e
  "$@" > "$evidence_dir/$name.stdout" 2> "$evidence_dir/$name.stderr"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    echo "$name: invalid source identity or promotion unexpectedly passed" >&2
    exit 1
  fi
  printf '%s\tEXPECTED-REJECT\tEXPECTED-REJECT\n' "$name" >> "$summary"
}

write_eligible_identity() {
  root=$1
  revision=$2
  repository=$3
  license_sha256=$4
  manifest_sha256=$5
  source_bytes=$6
  cat > "$root/config/nbe-adapter-source.identity.tsv" <<EOF
key	value
schema	1
provider	agda-specific-in-process-v1
source-boundary	engine-request-v1-provider-source-v1
file-list	config/nbe-adapter-source-files.tsv
file-count	3
source-bytes	$source_bytes
source-manifest-sha256	$manifest_sha256
vcs-status	present
repository	$repository
revision	$revision
license-status	approved
license-spdx	MIT
license-file	LICENSE
license-file-sha256	$license_sha256
patch-count	0
selection-eligibility	eligible
decision-owner	test-owner
approved-at	2026-08-22
EOF
}

make_eligible_fixture() {
  root=$1
  repository=https://example.invalid/cubical-nbe.git
  mkdir -p "$root/config"
  cp -R "$backend_dir/src" "$root/src"
  cp "$backend_dir/config/nbe-adapter-source-files.tsv" "$root/config/nbe-adapter-source-files.tsv"
  printf '%s\n' 'Synthetic MIT license evidence for contract testing only.' > "$root/LICENSE"
  git -C "$root" init -q
  git -C "$root" config user.name 'NbE contract test'
  git -C "$root" config user.email 'nbe-contract@example.invalid'
  git -C "$root" remote add origin "$repository"
  git -C "$root" add src config/nbe-adapter-source-files.tsv LICENSE
  git -C "$root" commit -q -m 'synthetic source identity fixture'
  revision=$(git -C "$root" rev-parse HEAD)
  license_sha256=$(sha256_file "$root/LICENSE")
  manifest_sha256=$(awk -F '\t' '$1 == "source-manifest-sha256" { print $2; exit }' "$backend_dir/config/nbe-adapter-source.identity.tsv")
  source_bytes=$(awk -F '\t' '$1 == "source-bytes" { print $2; exit }' "$backend_dir/config/nbe-adapter-source.identity.tsv")
  write_eligible_identity "$root" "$revision" "$repository" "$license_sha256" "$manifest_sha256" "$source_bytes"
}

write_selected_lock() {
  root=$1
  source_hash=$2
  revision=$(git -C "$root" rev-parse HEAD)
  cat > "$root/config/nbe-adapter.lock.tsv" <<EOF
schema	1
status	selected
provider	agda-specific-in-process-v1
repository	https://example.invalid/cubical-nbe.git
revision	$revision
source-sha256	$source_hash
license	MIT
integration	in-process
adapter-api	engine-request-v1
acceptance-profile	formal-transport-v1
decision-owner	test-owner
approved-at	2026-08-22
EOF
}

run_current_validator() {
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$temporary_dir/current-evidence" \
    sh "$validator"
}

run_current_promotion() {
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$temporary_dir/current-promotion-evidence" \
    sh "$promotion_checker"
}

eligible_root="$temporary_dir/eligible/backend"
make_eligible_fixture "$eligible_root"
eligible_hash=$(awk -F '\t' '$1 == "source-manifest-sha256" { print $2; exit }' "$eligible_root/config/nbe-adapter-source.identity.tsv")
write_selected_lock "$eligible_root" "$eligible_hash"

run_eligible_validator() {
  NBE_ADAPTER_SOURCE_ROOT="$eligible_root" \
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$temporary_dir/eligible-evidence" \
    sh "$validator"
}

run_eligible_promotion() {
  NBE_ADAPTER_SOURCE_ROOT="$eligible_root" \
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$temporary_dir/eligible-promotion-evidence" \
    sh "$promotion_checker"
}

run_pass current-content-pinned run_current_validator
run_pass eligible-source run_eligible_validator
run_pass eligible-promotion run_eligible_promotion
run_reject current-promotion-blocked run_current_promotion

cp "$eligible_root/src/Main.hs" "$temporary_dir/Main.hs.clean"
printf '\n-- mutation used by the source identity negative control\n' >> "$eligible_root/src/Main.hs"
run_reject changed-source run_eligible_validator
cp "$temporary_dir/Main.hs.clean" "$eligible_root/src/Main.hs"

cp "$eligible_root/config/nbe-adapter-source.identity.tsv" "$temporary_dir/identity.clean.tsv"
sed 's/^source-manifest-sha256\t.*/source-manifest-sha256\tcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/' \
  "$temporary_dir/identity.clean.tsv" > "$eligible_root/config/nbe-adapter-source.identity.tsv"
run_reject stale-manifest-hash run_eligible_validator
cp "$temporary_dir/identity.clean.tsv" "$eligible_root/config/nbe-adapter-source.identity.tsv"

cp "$eligible_root/config/nbe-adapter-source-files.tsv" "$temporary_dir/source-files.clean.tsv"
printf 'path\trole\n../escape.hs\tengine-boundary\nsrc/CubicalChez/Nbe/AdapterSpike.hs\tevaluator-readback\nsrc/Main.hs\tplugin-entry\n' \
  > "$eligible_root/config/nbe-adapter-source-files.tsv"
run_reject path-traversal run_eligible_validator
cp "$temporary_dir/source-files.clean.tsv" "$eligible_root/config/nbe-adapter-source-files.tsv"

fake_root="$temporary_dir/fake-license/backend"
mkdir -p "$fake_root/config"
cp -R "$backend_dir/src" "$fake_root/src"
cp "$backend_dir/config/nbe-adapter-source-files.tsv" "$fake_root/config/nbe-adapter-source-files.tsv"
printf '%s\n' 'Unapproved license claim.' > "$fake_root/LICENSE"
fake_license_sha256=$(sha256_file "$fake_root/LICENSE")
write_eligible_identity \
  "$fake_root" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  https://example.invalid/fake.git "$fake_license_sha256" "$eligible_hash" \
  "$(awk -F '\t' '$1 == "source-bytes" { print $2; exit }' "$backend_dir/config/nbe-adapter-source.identity.tsv")"
run_fake_license() {
  NBE_ADAPTER_SOURCE_ROOT="$fake_root" \
  NBE_ADAPTER_SOURCE_EVIDENCE_DIR="$temporary_dir/fake-license-evidence" \
    sh "$validator"
}
run_reject fake-license-without-vcs run_fake_license

write_selected_lock "$eligible_root" cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
run_reject promotion-lock-mismatch run_eligible_promotion

pass_count=$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$summary")
reject_count=$(awk -F '\t' 'NR > 1 && $3 == "EXPECTED-REJECT" { count++ } END { print count + 0 }' "$summary")
if [ "$pass_count" -ne 3 ] || [ "$reject_count" -ne 6 ]; then
  echo "NbE adapter source identity contract summary is incomplete" >&2
  exit 1
fi

echo "NbE adapter source identity contract PASS (3 positive, 6 negative)"
