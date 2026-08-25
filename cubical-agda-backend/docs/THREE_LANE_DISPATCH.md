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
executor SHA-256 identities plus a literal argument-vector hash. A rejection
or lane failure removes prior success provenance.

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

Run the portable contract with:

```sh
make verify-three-lane-dispatch
make verify-three-lane-e2e
```

The second target uses real locked Agda/GHC/Chez/Cubical toolchains. It covers
all three positives, type mismatch, top-level module identity mismatch, NbE
fuel exhaustion, TERM cancellation, and cross-lane stale-publication cleanup.
Commit `6ddd859` passed Linux and macOS clean-clone aggregates; remote runs
`32829677733`, `32829677729`, and `32829677728` are the retained CI evidence.
