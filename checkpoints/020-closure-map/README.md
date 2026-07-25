# Checkpoint 020 — orchestration closure

Status: closure frozen; implementation has not started at this checkpoint.

Upstream identity:

- Codex source commit recorded by the source archive: `98d28aab54ed86714901b6619400598598876dd0`
- Source archive SHA-256: `aa55787e86544740aaa3f068859479f4cca5655355975d81f02ff020c61ba21d`
- Extracted content-tree SHA-256: `5331dc5096238681b54657e4e394b041a4d558ee9fb09f75fee30088a9e51ffe`

The production target is a long-lived Haskell authority process. Rust remains the
effect adapter for networking, sandboxing, processes, terminals, persistence I/O,
model streams, clocks, UUIDs, and client transports.

The closure is wider than `run_turn`. It includes nine decision domains:

1. submission, session, task, injection, and mailbox lifecycle;
2. turn, sampling, retry, follow-up, cancellation, and terminal selection;
3. history, prompt normalization, rollback, durability barriers, and compaction;
4. tool exposure, routing, payload validation, concurrency permits, and lifecycle;
5. exec policy, sandbox choice, approval cache, permissions, and retry;
6. network approvals, MCP approvals, delegated approvals, and policy persistence;
7. multi-agent spawn, send, wait, interrupt, resume, completion, and teardown;
8. Guardian routing, review sessions, retry/deadline, terminal mapping, and circuit breaker;
9. startup/config/runtime selection, including daemon reuse and invalid-config recovery.

Release invariants:

- Haskell is the mandatory local production authority.
- There is no automatic Rust authority fallback.
- Explicit remote mode remains an external-runtime boundary and is labelled as such.
- A missing, dead, timed-out, malformed, or protocol-incompatible sidecar fails closed.
- Rust reference logic is permitted only in differential tests or a non-release test feature.
- Every effect requires a Haskell directive and every effect result returns as a fact.
- Durable state is confirmed only after the corresponding persistence result.
- Every scope has exactly one `OPEN`, one terminal, and one `CLOSE`.

Files:

- `closure-map.md` — exact Rust symbols and ownership boundary.
- `protocol-contract.md` — reducer, wire, transaction, and fail-closed contract.
- `acceptance-matrix.md` — differential, fault-injection, static, and release gates.
- `recovery-audit.md` — result of checking the only unidentified persistent archives.
