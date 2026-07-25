# Lost-work recovery audit

The two unidentified persistent objects were inspected before starting a fresh implementation:

- `22f04b26-b081-4a85-93f7-669a85088808.gz`
- `bb83ff2f-783c-468e-838d-e475e5d5f624.gz`

They are byte-identical:

- compressed SHA-256: `69695078460a99b87fd10d09ed484b43ff84045efe7f7b8f28ecb641180b19a1`
- compressed size: 2,781,183 bytes
- uncompressed tar size: 58,091,520 bytes

The archive manifest identifies a ProgramBench run:

- instance: `abishekvashok__cmatrix.5c082c6`
- ProgramBench version: `1.2.4`
- creation time: `2026-07-25T08:41:46Z`

An exact search for prior-project identifiers (`HaskellAuthority`, `AuthorityMode`,
`rust_decisions`, `TOOL_POLICY`, `codex-kernel-hs`, Haskell sidecar names) returned no matches.
The archives are unrelated benchmark traces and cannot reconstruct the lost Codex/Haskell patch.

The new implementation therefore starts from the fixed upstream archive and the separately
persisted Haskell semantic reference package. No claim is made that prior unpersisted source was
recovered.
