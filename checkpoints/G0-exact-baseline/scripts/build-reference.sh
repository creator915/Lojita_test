#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'Usage: %s /absolute/path/to/recovery-root\n' "$0" >&2
  exit 2
fi

recovery_root="$1"
[[ "$recovery_root" == /* ]] || {
  printf 'Recovery root must be absolute: %s\n' "$recovery_root" >&2
  exit 2
}

source_root="$recovery_root/source/codex-main"
deps_root="$recovery_root/deps"
toolchain_env="$recovery_root/toolchains/env.sh"
target_dir="$recovery_root/target"
output_dir="$recovery_root/output"
cargo_home="$recovery_root/cargo-home"

for required in \
  "$source_root/codex-rs/Cargo.toml" \
  "$source_root/codex-rs/Cargo.lock" \
  "$deps_root/.cargo/config.toml" \
  "$deps_root/vendor" \
  "$deps_root/v8/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz" \
  "$deps_root/v8/src_binding_release_x86_64-unknown-linux-gnu.rs" \
  "$toolchain_env"
do
  [[ -e "$required" ]] || {
    printf 'Missing required recovery input: %s\n' "$required" >&2
    exit 1
  }
done

actual_lock="$(
  sha256sum "$source_root/codex-rs/Cargo.lock" | awk '{print $1}'
)"
expected_lock="d0751922957c36865b9b963926884e40ff7deb61ed2aa177979e8574bd353a88"
[[ "$actual_lock" == "$expected_lock" ]] || {
  printf 'Cargo.lock mismatch: %s\n' "$actual_lock" >&2
  exit 1
}

# shellcheck source=/dev/null
source "$toolchain_env"
[[ "$(ghc --numeric-version)" == "9.14.1" ]]
[[ "$(cabal --numeric-version)" == "3.16.1.0" ]]
[[ "$(rustc --version)" == rustc\ 1.95.0* ]]
[[ "$(cargo --version)" == cargo\ 1.95.0* ]]

(
  cd "$deps_root/v8"
  sha256sum -c rusty_v8_release_x86_64-unknown-linux-gnu.sha256
)

mkdir -p "$target_dir" "$output_dir" "$cargo_home"

export CARGO_HOME="$cargo_home"
export CARGO_NET_OFFLINE=true
export CARGO_TARGET_DIR="$target_dir"
export RUSTY_V8_ARCHIVE="$deps_root/v8/librusty_v8_release_x86_64-unknown-linux-gnu.a.gz"
export RUSTY_V8_SRC_BINDING_PATH="$deps_root/v8/src_binding_release_x86_64-unknown-linux-gnu.rs"
export OPENSSL_INCLUDE_DIR=/usr/include
export OPENSSL_LIB_DIR=/usr/lib/x86_64-linux-gnu
unset CODEX_BWRAP_SHA256

# Run from deps_root so Cargo discovers its ancestor .cargo/config.toml and
# resolves every registry/Git dependency from vendor/.
(
  cd "$deps_root"
  cargo build \
    --manifest-path "$source_root/codex-rs/Cargo.toml" \
    --frozen \
    --offline \
    --target x86_64-unknown-linux-gnu \
    --release \
    -p codex-cli \
    --bin codex
)

built_binary="$target_dir/x86_64-unknown-linux-gnu/release/codex"
install -m 0755 "$built_binary" "$output_dir/codex"
sha256sum "$output_dir/codex"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/smoke-reference.sh" "$output_dir/codex"
