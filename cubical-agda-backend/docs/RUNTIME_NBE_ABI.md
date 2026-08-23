# Runtime NbE ABI v1

Goal 3 uses `runtime-nbe-abi-v1`. The final program links
`libcubical-runtime-nbe.a` and calls it in the user process. The runtime source
is independent of the Agda compiler package.

## Provider identity

The selected mature algorithm source is `AndrasKovacs/cctt` at commit
`ba16f3758a322e9be77ada1da2b93f45d500192e`, MIT. cctt does not expose an Agda
library API and has a different core language, so this repository follows the
previously approved route A: a backend-owned Agda runtime adapter using cctt's
environment/closure/evaluation/quotation split. It must not be described as an
unmodified or drop-in cctt library. The exact selection and license hashes are
in `config/runtime-nbe-provider.lock.tsv`.

## Wire value

The immutable packet begins with `CCZ-RUNTIME-NBE<TAB>1<LF>` followed by one
canonical `Packet` value. It contains:

- ABI and provider identity;
- context/interface identity;
- one closed typed `Request`;
- the request's closed typed definition slice.

The typed core has Bool, Nat, Int, S1, Vec, non-dependent Pi/Sigma, paths,
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
type changed is rejected. The final executable has no Agda package, `TCState`,
`TCM`, `normalise`, process-launch or network-provider dependency.
