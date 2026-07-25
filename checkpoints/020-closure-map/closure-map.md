# Orchestration closure map

## Session, submission, task, injection, mailbox

| Rust path | Authority-bearing symbols | Haskell-owned decision |
|---|---|---|
| `codex-rs/protocol/src/protocol.rs` | `Op`, `InterAgentCommunication`, `AgentStatus`, `TurnAbortReason` | operation classification and compatibility disposition |
| `core/src/session/handlers.rs` | `submission_loop`, `user_input_or_turn_inner`, `inter_agent_communication`, `shutdown_session_runtime`, `compact`, `thread_rollback`, `interrupt` | dispatch, steer-versus-start, teardown, rollback admission |
| `core/src/session/mod.rs` | `Codex::spawn`, `Codex::spawn_internal`, `Session::steer_input`, `Session::interrupt_task`, `resolve_multi_agent_version` | session admission, steer validation, interruption |
| `core/src/tasks/mod.rs` | `spawn_task`, `start_task`, `maybe_start_turn_for_pending_work*`, `abort_all_tasks`, `abort_turn_if_active`, `on_task_finished`, `handle_task_abort` | replacement, start, cancel/grace/force-abort, unique terminal |
| `core/src/state/turn.rs` | `ActiveTurn`, `TaskKind`, `RunningTask`, `TurnState`, `MailboxDeliveryPhase` | task phase and mailbox phase transitions |
| `core/src/session/inject.rs` | `inject_if_running`, `try_start_turn_if_idle`, `clear_reserved_idle_turn`, `inject_no_new_turn` | busy/idle reservation, injection target, race rechecks |
| `core/src/session/input_queue.rs` | `get_pending_input`, `has_trigger_turn_mailbox_items`, delivery phase methods | CurrentTurn/NextTurn, trigger-turn, drain eligibility |

Compatibility facts to preserve:

- A session has at most one running task, while a reserved `ActiveTurn { task: None }` may exist briefly.
- Replacement completes the old task's abort sequence before starting the new task.
- Only `CodexErr::TurnAborted` maps to interrupted/`TurnAborted`; many other task errors still finish through the normal `TurnComplete` path.
- The interrupted history marker is recorded and flushed before `TurnAborted`.
- A future `Op` may be compatibility-ignored only by an explicit Haskell directive; Rust's current wildcard no-op must disappear.

## Turn, sampling, retry, hooks

| Rust path | Authority-bearing symbols | Haskell-owned decision |
|---|---|---|
| `core/src/session/turn.rs` | `run_turn`, `run_hooks_and_record_inputs`, `run_pre_sampling_compact`, `maybe_run_previous_model_inline_compact`, `run_auto_compact` | turn loop, pending-input gate, follow-up, compaction, stop |
| same | `run_sampling_request`, `try_run_sampling_request`, `drain_in_flight` | retry/fallback, stream FSM, tool drain, cancellation/terminal ordering |
| `core/src/responses_retry.rs` | `handle_retryable_response_stream_error` | retryability, count, WS-to-HTTP fallback, delay |
| `core/src/stream_events_utils.rs` | `handle_output_item_done`, `record_completed_response_item_with_finalized_facts` | item classification, tool admission, final-answer mailbox phase |
| `core/src/hook_runtime.rs` | session-start, input, stop, pre/post compact, permission hooks | allow/block/rewrite aggregation and continuation |

Compatibility facts to preserve:

- The first sampling request uses its captured input; retries rebuild from live history using the same `ModelClientSession`.
- Tool calls are recorded before execution and may begin before `response.completed`.
- All in-flight tools drain even when the stream fails; results are recorded in model-source order.
- Concurrent begin/end events are racy in the Rust reference, so equality is causal partial order rather than unstable total order.
- TokenCount occurs after tool drain and before the final cancellation check; TurnDiff follows the cancellation check.
- Fresh-turn sampling precedes steer draining. After compaction, model continuation precedes steer when both are pending.

## History, rollback, durability, compaction

| Rust path | Authority-bearing symbols | Haskell-owned decision |
|---|---|---|
| `core/src/context_manager/history.rs` | `ContextManager`, `record_items`, `for_prompt`, `remove_first_item`, `replace`, `replace_last_turn_images`, `drop_last_n_user_turns` | history reducer, revision, rewrite |
| `core/src/context_manager/normalize.rs` | prompt normalization | synthetic missing output, orphan removal, modality normalization |
| `core/src/session/mod.rs` | `record_conversation_items`, `record_step_world_state_if_changed`, `replace_compacted_history`, `persist_rollout_items`, `flush_rollout`, context-update methods, `send_event*` | mutation order, persistence effects, compatibility continuation |
| `core/src/session/rollout_reconstruction.rs` | `reconstruct_history_from_rollout` | surviving rollback segment and state reconstruction |
| `core/src/session/handlers.rs` | `thread_rollback` | preflush/load admission, reconstruction, marker/flush outcome |
| `core/src/compact.rs` | local compact entry points and `build_compacted_history` | trigger, retry/truncation, install |
| `core/src/compact_remote.rs` | remote-v1 compact entry points | trim, canonical injection, install |
| `core/src/compact_remote_v2.rs` | remote-v2 compact entry points | retry cap, exactly-one output, budget/install |
| `core/src/compact_token_budget.rs` | token-budget compaction | new window and canonical full context |

Compatibility facts to preserve:

- Prompt normalization never mutates durable history; missing-output synthetic IDs remain stable.
- `history_version` advances on rewrite/replace, not simple append.
- Existing append failures are often warning/continue; this must be an explicit Haskell compatibility transition, never an adapter default.
- Explicit flush is the durability barrier.
- Rollback preflush/load failure is hard and leaves memory unchanged; rollback marker flush failure warns and continues.
- Rollback reconstruction restores history, previous-turn settings, reference context, world baseline, and window lineage from the same surviving segments.
- Local compaction can leave partial streamed items in live history across retry/final failure.
- Compact install advances the window before replacement and appends `Compacted`, full `WorldState`, then `TurnContext`.

## Tool plan, routing, execution, policy

| Rust path | Authority-bearing symbols | Haskell-owned decision |
|---|---|---|
| `core/src/tools/spec_plan.rs` | `build_tool_router`, `build_tool_specs_and_registry`, exposure/gate/source combinators | final tool set, order, exposure, runner identity |
| `codex-rs/tools/src/tool_executor.rs` | `ToolExposure`, `ToolExecutor::supports_parallel_tool_calls` | exposure and concurrency classification |
| `core/src/tools/router.rs` | `tool_supports_parallel`, `build_tool_call`, `dispatch_tool_call_with_terminal_outcome` | payload validity, handler selection, terminal |
| `core/src/tools/registry.rs` | registry construction and dispatch | duplicate/unknown handling and runner selection |
| `core/src/tools/parallel.rs` | `ToolCallRuntime::handle_tool_call_with_source` | Shared/Exclusive permit; Rust only applies the lock |
| `core/src/tools/orchestrator.rs` | `ToolOrchestrator::run`, `run_attempt`, `request_approval`, `reject_if_not_approved` | approval/sandbox/retry state machine |
| `core/src/tools/sandboxing.rs` | approval cache, approval requirement, sandbox override, unsandboxed permission | cache, sandbox, escalation, retry |
| `core/src/exec_policy.rs` | policy load/evaluation/amendment | Allow/Prompt/Forbidden and amendment |
| `core/src/tools/runtimes/shell/unix_escalation.rs` | execve prompt/action/policy | intercepted exec decision |
| apply-patch safety/handler/runtime | patch safety and approval entry points | safety class, approval, permissions, retry |

Rust effect adapters retained:

- shell/unified-exec/apply-patch process execution and partial delta collection;
- PTY creation, stdin/resize/wait, process cleanup;
- sandbox and managed-network enforcement;
- parsing and canonicalization returned as facts.

The adapter may not execute before `InvokeRunner` and may not choose Shared/Exclusive, approval, sandbox, retry, or terminal.

## Approval, permissions, network, MCP

| Rust path | Authority-bearing symbols | Haskell-owned decision |
|---|---|---|
| `core/src/session/mod.rs` | command/patch approval, permissions request/response/grants | prompt route, normalization, grant scope |
| `core/src/session/handlers.rs` | `exec_approval`, `patch_approval` | approval result transition |
| `core/src/tools/handlers/mod.rs` | additional-permission validation/preapproval | intersection, sticky grant, preapproval |
| `core/src/tools/network_approval.rs` | host key, pending dedupe, outcome, inline request, decider | owner, dedupe, cache, route, cancel/outcome |
| `core/src/network_policy_decision.rs` | payload interpretation | allow/deny meaning and malformed handling |
| `core/src/mcp_tool_call.rs` | MCP approval, execution, remember/persist | risk mode, cache, hook/Guardian/user route |
| `codex-rs/codex-mcp/src/mcp/mod.rs` and connectors policy | auto approval and app policy | policy result |
| `core/src/codex_delegate.rs` | delegated exec/patch/MCP/permissions approval | parent routing, cancellation, child response |

Compatibility facts to preserve:

- Strict auto-review runs for each attempt, including an otherwise skipped requirement; retry cannot reuse first-attempt preapproval.
- Empty approval keys do not cache; only all-session-approved keys skip; only session approval writes cache.
- Denied reads never escalate to unsandboxed execution.
- A malformed network-denial payload never causes escalation.
- Network session denial outranks allow; one exact host key has one prompt with shared result.
- Current persistence quirks (live proxy before disk, MCP persistence fallback to session, some amendment writes warning/continue) become explicit Haskell transitions.
- Delegated cancellation clears the parent's pending request and returns the legacy child-visible cancel/empty result.

## Agent

Authority-bearing paths include:

- `core/src/agent/control.rs`, `control/spawn.rs`, `control/legacy.rs`, `control/execution.rs`, `control/residency.rs`;
- `core/src/agent/registry.rs`, `agent/status.rs`;
- V1 handlers under `tools/handlers/multi_agents/`;
- V2 handlers under `tools/handlers/multi_agents_v2/`.

Compatibility facts to preserve:

- A child committed before its initial-message submission fails remains registered.
- V1 interrupt-and-send is two effects; failure of send does not roll back interrupt.
- V1 full-history fork rejects role/model/reasoning override.
- V1 wait completes on any final status; `Interrupted` is not final.
- V2 `send_message` is queue-only; `followup_task` triggers a turn.
- V2 follow-up cannot target root; interrupt cannot target root or self.
- Reservation, residency, and execution tokens release at most once and are tied to Haskell scopes.

## Guardian

Authority-bearing paths include:

- `core/src/guardian/approval_request.rs`;
- `guardian/review.rs`: route, review, spawn, deadline, retry;
- `guardian/review_session.rs`: trunk/ephemeral lifecycle and cleanup;
- `guardian/mod.rs`: denial/circuit-breaker state;
- direct entries in session, MCP, and delegated approval paths.

Haskell owns route, trunk reuse versus ephemeral fork, shared deadline, retry, parse mapping,
rationale, terminal, circuit-breaker update, and abort-turn. Rust retains reviewer model I/O,
session creation/shutdown, timer effects, and event transport.

Timeout, cancellation, malformed output, session failure, sidecar failure, or exhausted retries
must never approve a dangerous operation.

## Startup, config, runtime

Authority-bearing paths:

- `codex-rs/tui/src/lib.rs`: `AppServerTarget`, daemon probing, `start_app_server`,
  `app_server_target_for_launch`, `can_reuse_implicit_local_daemon`, `run_main`;
- `tui/src/app_server_session.rs`: embedded/external thread mode;
- `app-server/src/lib.rs`: `run_main` and invalid-config fallback;
- `app-server/src/config_manager.rs`: `load_default_config`;
- `cli/src/main.rs`: remote-mode resolution and subcommand routing.

Release rules:

- Local TUI/CLI/app-server/exec/review/resume/fork/archive all enforce Haskell authority.
- An implicit daemon is reusable only after a handshake proves implementation `Haskell` and exact protocol hash compatibility.
- Invalid-config fallback reapplies the non-overridable Haskell invariant.
- Explicit remote mode is `ExternalRemote` and makes no claim about the server implementation.
