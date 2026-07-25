# Authority boundary and acceptance contract

## Haskell owns decisions

The following decisions belong to the Haskell authority:

1. Thread, turn, task, and sampling lifecycle transitions.
2. Prompt/history state transitions and follow-up/stop decisions.
3. Retry, cancellation, interruption, and failure-state transitions.
4. Tool routing, admission mode, ordering, and lifecycle transitions.
5. Approval-policy interpretation and whether an approval is required.
6. Compaction admission, commit/abort, and history-revision transitions.
7. Agent spawn/send/wake/interrupt/completion lifecycle decisions.
8. Guardian/review lifecycle and decision propagation.
9. Network-permission and request-permission lifecycle decisions.
10. Transactional confirmation after required external effects succeed.

## Rust owns effects

Rust remains responsible for executing directives against the outside world:

- HTTP, SSE, and WebSocket transport;
- authentication and credential plumbing;
- sandbox creation and enforcement;
- process and terminal lifecycle;
- filesystem and persistence I/O;
- TUI/App Server rendering and protocol transport;
- V8/code-mode hosting and other platform-specific runtimes.

Rust may normalize raw platform results into protocol facts. It must not infer a
second orchestration transition from those facts.

## Mechanical constraints

- Production mode defaults to Haskell authority.
- Failure to start, contact, decode, or validate the Haskell authority is
  fail-closed.
- There is no automatic fallback to the Rust orchestration kernel.
- Rust-reference mode may exist only behind an explicit test/development
  boundary used for differential comparison.
- Each authority scope has exactly one terminal transition and one close.
- A directive is confirmed only after its required Rust-side effect and
  persistence operation succeed.
- Cancellation or early future drop poisons/abandons an open authority scope;
  it cannot be silently reused.

## Equality standard

For the same initial state, recorded model stream, fake tool runner, filesystem
runner, clock/ID oracle, configuration, and user events, Rust-reference and
Haskell-authority runs must agree on normalized:

- model requests;
- externally visible events and causal ordering;
- tool invocations and results;
- approval requests and outcomes;
- history and persistence revisions;
- workspace/file results;
- turn outcome and stop reason.

Concurrent events are compared by required causal partial order when the Rust
reference itself has no deterministic total order.

