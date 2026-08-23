# Runtime NbE ABI v1

`runtime-nbe-abi-v1` is the implemented compiler/runtime narrow waist for the
currently supported Goal 3 fragment. The compiler-side producer consumes real,
checked `Agda.Syntax.Internal.Term` and `Type`; the final runtime deliberately
uses a compiler-independent immutable `Ty`/`Term` representation so it does not
link `TCState` or the Agda compiler package.

## Provider identity

The pinned algorithm reference is `AndrasKovacs/cctt` at commit
`ba16f3758a322e9be77ada1da2b93f45d500192e`, MIT. cctt has a different core
language and does not expose an Agda runtime-library API. The current runtime
uses its environment/closure/evaluation/quotation architecture, but does not
yet link cctt code. It is not an unmodified/drop-in cctt library or a selected
Goal 3 provider. Reference and license hashes are in
`config/runtime-nbe-provider.lock.tsv`.

## Wire value

The packet begins with `CCZ-RUNTIME-NBE<TAB>1<LF>` followed by one canonical
`Packet` value containing:

- ABI and provider identity;
- complete interface/module context identity;
- one closed typed `Request`; and
- the request's closed typed definition slice.

This is a repository-defined runtime representation produced from checked
Internal syntax, not a serialization of compiler state. Its typed core has
Bool, Nat, Int, S1, Vec, non-dependent Pi/Sigma, paths,
lambda/application, definitions, Glue equivalences, `transp`, `hcomp`, record
transport and the audited S1 winding fragment. Unsupported or ill-typed shapes
are errors; no fallback normalizer exists in the runtime.

## Implemented producer and final link

`--cubical-runtime-nbe-export` checks closure/metavariables and rechecks the
Internal pair, then translates Bool, Nat, non-dependent Pi, variables, lambdas,
applications, single variable-pattern definitions and a checked definition
slice. The Cubical slice recognizes primitives by `PrimitiveId`, not rendered
QName: constant-family `PrimTrans` at `phi=i0`, plus canonical ground-face
`PrimHComp`. Unsupported nodes fail before a packet is written, and this path
does not call compiler `normalise`.

The runtime modules are registered as the static GHC package
`cubical-runtime-nbe-0.1.0`. `RuntimeNbeFinal.agda` is compiled by Stock Agda,
MAlonzo and GHC and calls `Cubical.Runtime.Nbe.Embedded.runEmbedded` in the
final process. Binary symbols, provider marker, no-exec interposition and
compiler-symbol audits are executable acceptance checks.

## Ownership, lifecycle and trust boundary

Packet bytes are owned by the caller and parsed into request-local syntax.
Semantic values, environments, closures, active-definition state and the
definition cache are allocated for one call and discarded with its result.
Nothing semantic is serializable. Results are either a reified `Term + Type`
or one stable `CCZ-RUNTIME-NBE-*` error.

The default caps are 1 MiB packet bytes, 200,000 evaluator steps and 200,000
semantic allocations. The command-line test harness may lower but never raise
these compiled caps. ABI/provider/context mismatch, malformed input, open or
ill-typed terms, negative indices, definition cycles, fuel and allocation
exhaustion all fail closed.

Evaluation first validates every definition and checks `requestTerm :
requestType`. It reflects into a closure/environment semantic domain, quotes
under the requested type, and infers the quoted term again. A readback whose
type changed is rejected. The final runtime has no Agda package, `TCState`,
`TCM`, `normalise`, process-launch or network-provider dependency.

## Acceptance gaps

- cctt code is not linked;
- Glue, records, HITs and the complete `t11/t11b/t16` producer slice are not
  translated from real Agda Internal syntax; and
- the historical full-fixture oracle script remains correlation-only. The new
  bridge/final-program gate performs actual same-expression differentials for
  the implemented ordinary and `PrimTrans`/`PrimHComp` slice, but not yet for
  the required full fixture set.

The formerly failing higher-order readback regression is now a PASS and
negative input indices are rejected. The implementation and evidence close the
ABI/link/semantic-domain, readback/resource/no-subprocess items, but these gaps
keep Goal 3 at 8/11 rather than complete.
