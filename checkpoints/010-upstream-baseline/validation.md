# Baseline validation

Validated on 2026-07-25:

- Both independently restored copies of `codex-main.zip` are 11,964,353 bytes
  and have identical SHA-256 values.
- ZIP comment is
  `98d28aab54ed86714901b6619400598598876dd0`.
- `unzip -t` reports no archive errors.
- Two independent extractions contain 5,316 files and 766 directories each.
- Their content-tree hashes are identical.
- `diff -qr` reports no differences between the two extracted source trees.
- Every Rust hash in the 36-file reference replay manifest matches this source
  extraction.
- The reference Haskell archive contains 40 `.hs` files and no binary or build
  output. Its own documentation explicitly rejects drop-in/full-CLI status.
- The locked GHC/Cabal/HLS/Rust payloads passed their archived checksum and
  signature verification before installation.

No claim of full CLI equivalence is made at this checkpoint. It fixes the
identity of the inputs and the acceptance contract only.

