# Thin three-lane dispatcher

`bin/cubical-agda-dispatch` is a deliberately small policy and execution
layer. It does not typecheck Agda, translate Internal terms, decode packets, or
implement runtime Cubical semantics. Instead, it consumes exactly one
`staging.txt` emitted by the existing checked Internal/Treeless binding-time
analysis and one explicit deployment boundary.

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

This layer does not broaden Goal 3. The runtime-nbe lane remains limited to the
already linked and tested Goal 3 runtime fragment. Supplying and validating a
production final-program adapter, cleaning every lane-specific artifact after
cancellation, and unified real-program end-to-end acceptance remain open
integration work; this dispatcher is not evidence that those checklist items
are complete.

Run the portable contract with:

```sh
make verify-three-lane-dispatch
```
