#!/usr/bin/env bash
set -euo pipefail

if (($# != 1)); then
  printf 'Usage: %s /absolute/path/to/materialized-assets\n' "$0" >&2
  exit 2
fi

asset_root="$1"
[[ "$asset_root" == /* ]] || {
  printf 'Asset root must be absolute: %s\n' "$asset_root" >&2
  exit 2
}

(
  cd "$asset_root"
  sha256sum -c <<'SUMS'
aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d  codex-main.zip
ff131f6b1f0d5d2d829e684c4d0e546620ac63c7410d23a4f89164bce78edc21  codex-kernel-hs-0.1.0.0.tar.gz
10c4983871cc80ce4819c96e0cb273bff0e9a0807f43994b3fac64bdcc9605f4  lojita-haskell-core-ghc-9.14.1-cabal-3.16.1.0-ubuntu24.04-x86_64.tar
f9939d0a235550f5d05d705b256c8cbf362893bac3628e62de0824f9a91c1cec  lojita-haskell-hls-2.14.0.0-ubuntu24.04-x86_64.tar
9a397a72d9262be71f0f263f77e198b806b5a5e1ad5509e898d8bb69eba2cbfc  lojita-rust-1.95.0-linux-x86_64.tar
65a71ebcdb849ed409645bd9c3a924b64dbd1bdb86b485a3a3d450e1cbd8dc68  Lojita_test/codex-g0-offline-deps-98d28a.tar.gz
da45948f6a2e4585e92867444c094756447ffae54aecd64f0c783012b9b449fd  Lojita_test/codex-98d28a-x86_64-unknown-linux-gnu-release.gz
SUMS
)

zip_comment="$(unzip -z "$asset_root/codex-main.zip" | tail -n 1)"
[[ "$zip_comment" == "98d28aab54ed86714901b6619400598598876dd0" ]]
unzip -t "$asset_root/codex-main.zip" >/dev/null

printf '%s\n' "G0 Library assets: PASS"
