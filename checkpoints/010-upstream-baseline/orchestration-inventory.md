# Initial orchestration inventory

This is the starting inventory, not the final closure proof. Every row must be
re-audited against the fixed commit before its protocol is frozen.

| Decision family | Primary Rust anchors | Planned authority scope |
| --- | --- | --- |
| Thread/session admission | `core/src/thread_manager.rs`, `core/src/session/session.rs`, `core/src/session/handlers.rs` | `THREAD`, `TURN` |
| Turn feedback loop | `core/src/session/turn.rs`, `core/src/tasks/regular.rs`, `core/src/tasks/mod.rs` | `TURN`, `TASK` |
| Sampling/retry/stream | `core/src/client.rs`, `core/src/stream_events_utils.rs`, `core/src/client_common.rs` | `SAMPLING` |
| History and rollback | `core/src/session/mod.rs`, conversation/history modules, App Server rollback handlers | `HISTORY` |
| Compaction | core compaction modules and turn pre-compaction paths | `COMPACTION` |
| Tool routing/spec/admission | `core/src/tools/router.rs`, `registry.rs`, `parallel.rs`, `spec_plan.rs`, `context.rs` | `TOOL_POLICY`, `TOOL_EXECUTION` |
| Patch lifecycle | `core/src/tools/handlers/apply_patch.rs`, `runtimes/apply_patch.rs`, `apply-patch/src/lib.rs` | `TOOL_EXECUTION` |
| Process/code-mode adapters | unified-exec and code-mode handlers | Rust runner under `TOOL_EXECUTION` |
| Approval/permissions | session approval paths, MCP policy, request-permissions paths | `REVIEW`, `NETWORK_APPROVAL`, `PERMISSIONS` |
| Agent collaboration | collaboration/agent control paths and delegated-agent bridge | `AGENT` |
| Guardian | guardian and auto-review paths | `GUARDIAN` |
| User/tool injection | submission and in-turn injection paths | `INJECTION` |
| Diff/event projection | turn diff tracker and tool/session events | state in Haskell; rendering in Rust |

The earlier 36-file replay manifest remains useful for model/tool/history
semantics, namespaced routing, ordered tool-result reinjection, incremental
requests, patch semantics, and turn-diff fixtures. It is insufficient for the
full authority boundary because it omits several live lifecycle and
transactional decision families listed above.

