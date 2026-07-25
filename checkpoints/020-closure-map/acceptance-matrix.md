# Acceptance matrix

All behavioral rows run the same model transcript, clock, UUID stream, tool results,
filesystem fixture, hooks, and persistence faults through Rust reference and Haskell authority.

Compare:

- normalized model request bodies;
- client events and stable causal order;
- rollout/history/window state and revisions;
- tool invocations, permits, results, and workspace delta;
- approval prompts, Guardian outcomes, permission/network caches;
- agent registry/edges/status and terminal result;
- `rust_decisions == 0`, `orphan_effects == 0`;
- `opens == terminals == closes` for every completed scope.

For genuinely concurrent tools, compare the causal partial order:

`call-record < tool-start < tool-end < matching-output-record`

and model-source order of output records. Do not use the Rust reference's racy begin/end
total order as an oracle.

## Reducer and real-sidecar gates

- Haskell builds with `-Wall -Wcompat -Werror`.
- Reducer table tests cover every fact/phase pair.
- Property tests cover sequence/revision monotonicity, idempotence, unique terminal/close,
  and poison permanence.
- Replay fixtures cover healthy, error, cancellation, retry, persistence, and restart traces.
- Rust-to-real-sidecar tests cover every tag/arity/enum plus EOF, timeout, malformed frames,
  wrong scope/revision, duplicate conflict, and process death at every transaction boundary.

## Session, turn, sampling

- every `Op`, including an unknown future operation;
- idle start, active Regular steer, Review/Compact rejection, expected-id mismatch, empty input;
- replacement and every cancel race (before install, after start, during run, before finish);
- graceful completion within 100 ms and forced abort;
- hook all-blocked, partially blocked, stop, block-with-prompt, block-without-prompt;
- assistant-only, commentary/final, single and multiple tools;
- stream EOF before/after tool call, retryable/non-retryable, WS fallback, usage/context errors;
- final answer plus late mail, commentary/reasoning preemption, trigger-turn;
- token count, cancellation, and TurnDiff order.

## History, rollback, compaction

- missing output, orphan output, image stripping, stable synthetic IDs, truncation;
- invalid-image rewrite and its current persistence behavior;
- rollback zero/active/out-of-range/incomplete/compacted/inter-agent/context-prefix;
- preflush/load/marker-flush failures and reconstruction of every metadata component;
- manual, pre-turn, and mid-turn compact;
- token threshold, new-context tool, comp-hash change, model downshift, missing hash;
- local partial/retry/failure; remote v1/v2 success/failure/zero/multiple compaction output;
- compact pre/post hook stop and persistence failure at each append.

## Tools, policy, approvals

- every feature/model/provider/code-mode/MCP exposure combination and exact tool order;
- unknown tool, wrong payload, duplicate registry, missing handler;
- pre-hook allow/deny/rewrite and post-hook output rewrite;
- two shared, two exclusive, mixed permits, cancellation, cleanup, panic;
- explicit exec policy allow/prompt/forbidden and heuristic cases on all approval policies;
- first success, ordinary failure, valid/malformed sandbox denial, denied reads, strict retry;
- approval cache empty/partial/all keys and one-turn/session results;
- apply-patch inside/outside roots, move, additional permissions, partial failure/retry/cancel;
- request-permissions gates, scope, intersection, strict session invalidation, cancel.

## Network, MCP, Guardian, delegated approvals

- explicit/implicit environment owner, ambiguous owner, host-key dedupe;
- allow/deny cache precedence, hook, persistence failure, immediate/deferred completion;
- MCP annotation truth table, Approve/Auto/Prompt, cache/hook order, remember persistence fallback;
- missing/unknown elicitation response and app-disabled paths;
- Guardian route off/on, allow/deny/timeout/cancel/parse/transient/retry exhausted;
- trunk idle/busy/config mismatch/broken stream, ephemeral cleanup, shared deadline;
- consecutive/recent circuit breaker thresholds and abort;
- delegated exec/patch/permissions/legacy MCP, ID routing, cancel while pending.

## Agent

- failure before create and failure after committed child before initial submit;
- manager death, reservation drop, residency eviction, execution capacity;
- V1 full-history fork and forbidden overrides;
- V1 interrupt then failed send; wait with all final classes and non-final Interrupted;
- V2 queue-only send, trigger-turn follow-up, root/self restrictions;
- completion watcher with live/dead parent;
- close/shutdown descendant tree and edge persistence failure;
- V1/V2 resume and unloaded-resident reload.

## Startup and no-fallback

- missing sidecar, failed spawn, bad handshake, timeout, EOF;
- no daemon, compatible Haskell daemon, old Rust daemon, protocol-hash mismatch;
- environment-only Haskell enforcement without CLI flag;
- strict and non-strict invalid-config recovery;
- explicit external remote;
- TUI, app-server, exec, review, resume, fork, archive entry points;
- staged packaged CLI reports actual authority and never reuses an unproven daemon.

## Mechanical release gates

- release dependency graph excludes Rust reference feature/crate;
- release symbol/static scan excludes Rust authority entry points and fallback strings;
- production `SessionServices` has a mandatory non-optional `AuthorityClient`;
- effect entry points require private `AuthorityPermit`;
- directive interpreter uses exhaustive matches;
- denylist catches authority calls outside adapters;
- mutation canaries prove changing a Haskell decision changes the result and changing disabled
  Rust reference logic does not;
- kill-sidecar fault injection at every transition has no effect after poison and no fallback;
- release CLI black box covers a real model mock, shell, patch, terminal, approval, compaction,
  agent, Guardian, resume, and cancellation flow.

## Build environment note

The restored Cargo cache contains the known workspace dependencies but not the new git dependency
`libwebrtc` from `juberti-oai/rust-sdks` revision
`e2d1d1d230c6fc9df171ccb181423f957bb3c1f0`, pulled only by workspace member
`realtime-webrtc`. Baseline `cargo check -p codex-core --offline` therefore stops during workspace
resolution before compiling `codex-core`. Any local build-only workaround must be isolated and
must not remove product behavior from the persisted source.
