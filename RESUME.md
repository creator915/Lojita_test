# Resume at G1 scope review

G0 remains closed and valid. G1 is stopped and has not passed.

Current authoritative state:

- branch: `agent/haskell-orchestration-kernel`
- upstream: `98d28aab54ed86714901b6619400598598876dd0`
- G0 baseline and recovery: PASS
- G1 decision ledger: INCOMPLETE
- G1 status: `STOP_REVIEW`
- G2 implementation: FORBIDDEN

Two confirmed Authority branches hit domains that G1 explicitly forbids:

1. `core/src/tasks/regular.rs:64-70` — startup prewarm controls whether and
   how the Turn enters sampling.
2. `core/src/session/handlers.rs:864-870` — Guardian denial status controls
   whether an exact-action approval is injected into history.

Resume only by reviewing and explicitly revising the construction boundary.
Do not continue enumerating the remaining branches, assign Haskell
constructors to these triggers, or follow their call graphs before that review.

The evidence and the unchanged 17-file candidate ceiling are recorded in
`checkpoints/G1-decision-ledger/G1-decision-ledger-stop-review.zh-CN.md`.

Do not revive the former 36-file translation as an implementation baseline.
Do not substitute an npm binary or a different Codex version for the frozen
Rust oracle.
