# Resume after G0

G0 is closed. The exact Rust baseline and its recovery path are usable.

Current authoritative state:

- branch: `agent/haskell-orchestration-kernel`
- upstream: `98d28aab54ed86714901b6619400598598876dd0`
- baseline release build: PASS
- persistent vendor/V8 and exact reference binary: PASS
- fresh recovery rehearsal: PASS
- Haskell reference offline build and differential: PASS

The next allowed activity is G1:

1. build the branch-level decision ledger from the frozen source;
2. classify each candidate branch as Authority, Effect, Invariant, or
   Presentation;
3. review the resulting minimum Turn decision boundary;
4. only then decide whether G2 Rust reference-machine implementation begins.

Do not revive the former 36-file translation as an implementation baseline.
Do not substitute an npm binary or a different Codex version for the frozen
Rust oracle.
