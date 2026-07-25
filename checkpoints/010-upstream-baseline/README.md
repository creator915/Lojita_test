# Codex Haskell authority — upstream baseline

This checkpoint starts the formal rerun of the Codex orchestration-kernel
migration.

## Fixed target

Rewrite the Codex CLI orchestration and scheduling decision closure in Haskell.
The production candidate must use Haskell as the sole authority for turn,
sampling, tool-admission, history, task, approval, compaction, agent, guardian,
and related lifecycle decisions.

Rust remains the effect adapter for HTTP/WebSocket transport, sandboxing,
processes, terminals, persistence I/O, and other platform integration. Rust may
collect facts and execute Haskell directives; it may not silently make a
duplicated orchestration decision or fall back to its original orchestration
kernel.

Observable behavior must remain unchanged. The original Rust implementation is
retained only as a differential-test oracle until acceptance is complete.

## Baseline

- Upstream source archive: `codex-main.zip`
- ZIP comment / source commit:
  `98d28aab54ed86714901b6619400598598876dd0`
- Archive SHA-256:
  `aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d`
- Extracted source tree SHA-256:
  `5331dc5096238681b54657e4e394b041a4d558ee9fb09f75fee30088a9e51ffe`
- Locked Haskell toolchain: GHC 9.14.1, Cabal 3.16.1.0
- Locked Rust toolchain: Rust/Cargo 1.95.0

The 2026-07-25 `codex-kernel-hs-0.1.0.0` archive is retained as a reference
replay kernel and fixture source. It is explicitly not treated as a production
authority or a drop-in CLI.

## Persistence rule

Text source, manifests, protocols, tests, and reconstruction scripts are
checkpointed on `agent/haskell-orchestration-kernel`. Large source archives,
toolchains, binaries, raw logs, and release bundles are stored as persistent
artifacts with recorded SHA-256 values.

