# Production three-lane dispatch and execution

`bin/cubical-agda-run` is the production entry point. It performs one real
checked-entry binding-time analysis, verifies that the requested expression is
the checked entry, clears prior publications, and hands exactly one stable
decision to `bin/cubical-agda-dispatch`. The dispatcher remains a small policy
layer: it consumes that single `staging.txt` plus an explicit deployment
boundary and invokes only the selected production adapter.

The deterministic mapping is:

| Binding time | Boundary | Lane |
| --- | --- | --- |
| `static` with `static-closed` evidence | `none` | `native` |
| `dynamic` or `mixed` with `typed-residual` evidence | `cross-process` | `packet` |
| `dynamic` or `mixed` with `typed-residual` evidence | `in-process` | `runtime-nbe` |

Every other combination rejects before a lane executable is called. The
dispatcher invokes only the selected executable and passes its repeated lane
arguments literally, without `eval`. On success it atomically publishes
`three-lane-dispatch-v1` provenance containing the source, analysis, and
executor SHA-256 identities plus a literal argument-vector hash. Before that
analysis, the unified entry copies the source tree, optional consumer tree,
and every explicit include tree into a read-only private snapshot. It binds
the decision to one deterministic aggregate tree SHA-256 and rejects symlinks,
library-registry arguments, input mutation, or any later snapshot mismatch. A
rejection or lane failure removes prior success provenance.

The checked manifest also carries the top-level module and Agda full-interface
hash obtained from the real `Interface`. Dispatch requires both fields and
every adapter records them. Packet production/consumption rechecks the packet
envelope; the runtime bridge embeds the same identity in its context and the
linked final program receives that exact context.

The selected adapters are real execution paths:

- `native` invokes locked Stock Agda/MAlonzo and locked GHC, bypassing packet
  and runtime NbE;
- `packet` invokes the maintained v2 producer and a separate consumer, carrying
  checked Internal `Term + Type` and no semantic closure or `TCState`;
- `runtime-nbe` runs the Stock-MAlonzo final program linked to the pinned cctt
  provider, never the compiler-process candidate.

Each lane publishes its own auditable provenance. Synchronous failures and
HUP/INT/TERM forward to the child process and remove partial or prior binary,
Scheme, packet, result, and provenance publications. This does not broaden
Goal 3 beyond its linked and tested fragment or replace independent semantic
acceptance.

Runtime limits are selected only through `bin/cubical-agda-run` with
`--runtime-fuel`, `--runtime-allocations`, and `--runtime-packet-bytes`. They
pass through dispatch to the linked final program, where the real evaluator
enforces them. Analysis remains private until the selected lane succeeds, and
native compile/program, packet producer/consumer, and runtime bridge/final
subprocesses all participate in the same signal-forwarding cleanup contract.

Run the portable contract with:

```sh
make verify-three-lane-dispatch
make verify-three-lane-e2e
```

The second target uses real locked Agda/GHC/Cubical toolchains and no mock
executor. It covers all three positives, real native/packet/bridge failures,
type and module mismatch, source/dependency mutation, linked-runtime fuel
exhaustion, analyzer cancellation, cancellation in every native, packet, and
runtime subprocess stage, process-tree termination, and stale-publication
cleanup.
Commit `6ddd859` passed Linux and macOS clean-clone aggregates; remote runs
`32829677733`, `32829677729`, and `32829677728` are the retained CI evidence.
Reliability hardening commit `e6d44ca` additionally passed the specialized
real-toolchain target locally; no new release approval is implied.
