# Runtime NbE ABI v1

`runtime-nbe-abi-v1` is the implemented compiler/runtime narrow waist for the
currently supported Goal 3 fragment. The compiler-side producer consumes real,
checked `Agda.Syntax.Internal.Term` and `Type`; the final runtime deliberately
uses a compiler-independent immutable `Ty`/`Term` representation so it does not
link `TCState` or the Agda compiler package.

## Provider identity

The selected provider is `AndrasKovacs/cctt` commit
`ba16f3758a322e9be77ada1da2b93f45d500192e`, MIT. Ten unmodified Core modules
are vendored under `runtime/nbe/vendor/cctt/`; their individual hashes and the
upstream archive/license identities are locked in
`config/runtime-nbe-cctt-sources.sha256` and
`config/runtime-nbe-provider.lock.tsv`. A repository-owned Cabal library target
exposes the upstream `Core.eval` and `Quotation.quoteUnfold` implementation.
The Agda wire language remains deliberately smaller than cctt's own language:
the adapter encodes the actual bounded Bool/Nat/Int/Vec/Sigma value and its
family action as a closed cctt lambda/Sigma term. The value returned to runtime
readback is decoded from `quoteUnfold (eval term)`; no separate Haskell result
is authorized by a success flag. Pi transport is represented extensionally,
and its domain/codomain actions enter this same provider when applied. This is
not a claim that arbitrary Agda Internal syntax is cctt syntax. A translation,
shape, or provider rejection is fatal, never a fallback.

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
Internal pair, then translates the declared Bool/Nat/Int/Vec/Pi/Sigma/PathP/
Glue/S¹ slice, variables, lambdas, applications, single-clause definitions and
a checked definition slice. The Cubical slice recognizes primitives by
`PrimitiveId` and checked library definitions by stable semantic structure.
It covers constant, Vec, Pi, Sigma and Glue transports, ground hcomp, canonical
`ua` equivalences and the audited path-composition/winding cases. Unsupported
nodes fail before a packet is written, and this path does not call compiler
`normalise`.

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

## Acceptance boundary

The historical full-fixture correlation script remains non-differential and is
not acceptance evidence. The maintained same-input gate instead exports the
actual checked definitions `t11`, `t11b`, `t09`, and `t16a`-`t16c`, executes
the linked runtime, and invokes Agda's oracle. For `t11/t11b`, whose indexed
transport is intentionally residual, checked proofs connect the exported root
to a canonical Vec computed from the same named input and equivalence/path.
Agda observes that canonical value as a Bool pair. The runtime structurally
renders its typed Vec result to the same observation, and the gate requires
byte-for-byte equality. A missing proof or residual oracle is a failure, not an
accepted boundary.

The formerly failing higher-order readback regression is a PASS and negative
input indices reject. The replacement differential has 6/6 locked-CI evidence;
the declared Goal 3 fragment therefore has 11/11 technical evidence but remains
unaccepted pending independent review. General
open Kan systems, indexed data beyond the audited Vec case,
arbitrary records/HITs, and whole-module normalization remain outside the ABI
and fail closed.
