# Runtime NbE ABI v1

`runtime-nbe-abi-v1` is a prototype wire format, not the accepted Goal 3 ABI.
The test harness links `libcubical-runtime-nbe.a`; an Agda/MAlonzo-generated
final user program does not. The prototype source is independent of the Agda
compiler package precisely because it defines a different `Ty`/`Term` AST.

## Provider identity

The pinned algorithm reference is `AndrasKovacs/cctt` at commit
`ba16f3758a322e9be77ada1da2b93f45d500192e`, MIT. cctt does not expose an Agda
library API and has a different core language. The current backend-owned
prototype borrows cctt's environment/closure/evaluation/quotation split, but
does not link cctt or adapt Agda Internal syntax. It must not be described as
an unmodified/drop-in cctt library or a selected Goal 3 provider. The reference
and license hashes are in `config/runtime-nbe-provider.lock.tsv`.

## Wire value

The prototype packet begins with `CCZ-RUNTIME-NBE<TAB>1<LF>` followed by one
canonical `Packet` value. It contains:

- ABI and provider identity;
- context/interface identity;
- one closed typed `Request`;
- the request's closed typed definition slice.

This is a repository-defined model, not `Agda.Syntax.Internal.Term/Type`. Its
typed core has Bool, Nat, Int, S1, Vec, non-dependent Pi/Sigma, paths,
lambda/application, definitions, Glue equivalences, `transp`, `hcomp`, record
transport and the audited S1 winding fragment. Unsupported or ill-typed shapes
are errors; no fallback normalizer exists in the runtime.

## Ownership and lifecycle

Packet bytes are owned by the caller and parsed into request-local syntax.
Semantic values, environments, closures, active-definition state and the
definition cache are allocated for one call and discarded with its result.
Nothing semantic is serializable. Results are either a reified `Term + Type`
or one stable `CCZ-RUNTIME-NBE-*` error.

The default caps are 1 MiB packet bytes, 200,000 evaluator steps and 200,000
semantic allocations. The command-line test harness may lower but never raise
these compiled caps. ABI/provider/context mismatch, malformed input, open or
ill-typed terms, definition cycles, fuel and allocation exhaustion all fail
closed.

## Trust boundary

Evaluation first validates every definition and checks `requestTerm :
requestType`. It evaluates into a closure/environment semantic domain, quotes
under the requested type, and infers the quoted term again. A readback whose
type changed is rejected. The prototype harness has no Agda package, `TCState`,
`TCM`, `normalise`, process-launch or network-provider dependency.

## Acceptance gaps

- no producer serializes checked Agda Internal `Term + Type` into this ABI;
- no decoder reconstructs the exact checked Agda syntax/definition closure;
- no Agda/MAlonzo user executable calls the archive in its own process;
- cctt code is not linked;
- the current oracle script does not perform a same-input differential; and
- the reduced higher-order counterexample reads back an invalid `Var (-2)`.

Until these gaps have executable evidence, this document and the prototype do
not close any Goal 3 item beyond the separately specified process/data boundary.
