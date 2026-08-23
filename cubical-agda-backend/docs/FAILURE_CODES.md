# Backend failure codes

Every backend-originated failure is a nonzero process result whose diagnostic
starts with `Cubical Chez backend [CODE]`. Consumers must key on `CODE`, not on
the following human explanation, which may be reflowed by Agda or expanded in
later releases.

| Code | Meaning |
| --- | --- |
| `CCZ-INVALID-CONFIG` | CLI or backend configuration is invalid |
| `CCZ-ENTRY-REJECTED` | no admissible requested entry was found |
| `CCZ-NBE-UNAVAILABLE` | the selected mature NbE adapter is not linked/configured |
| `CCZ-NBE-UNSUPPORTED` | a linked NbE explicitly reported an unsupported feature and policy rejected fallback |
| `CCZ-ENGINE-TIMEOUT` | a configured evaluator deadline was exceeded |
| `CCZ-NBE-FAILED` | the NbE adapter failed while evaluating a checked request |
| `CCZ-ENGINE-RESULT-INVALID` | engine readback failed closed/meta/type rechecking |
| `CCZ-UNSUPPORTED` | binding time, semantic/catalog identity, primitive, or reachable closure is unsupported |
| `CCZ-RESIDUAL-REQUIRED` | typed semantics remain but policy declines publication |
| `CCZ-RESIDUALIZATION-FAILED` | typed packet construction or self-validation failed |
| `CCZ-SCHEME-LOWERING-FAILED` | a static closure/shell could not lower completely, or its declared `chez-core-abi-v1` disagreed with the lowering implementation |

`CCZ-RESIDUAL-REQUIRED` is intentionally different from
`CCZ-RESIDUALIZATION-FAILED`: the first is a valid residual outcome rejected by
policy, while the second means the requested residual artifact could not be
safely produced. Neither is compilation success.

`CCZ-NBE-PROMOTION-BLOCKED` is a build/release-gate diagnostic, not a backend
runtime code. `check-nbe-production-promotion` emits it when source identity is
content-pinned but revision/license approval is absent, the
production lock is unselected, or the eligible source and lock disagree. It
therefore cannot be confused with `CCZ-NBE-UNAVAILABLE`, which is the runtime
behavior of a binary without an approved linked provider.

Residualization failure includes a direct-dependency inventory that does not
match the checked `Term + Type`. The inventory is recomputed before publication
and again compared with the decoded packet, so inconsistent signature evidence
cannot be emitted as a valid residual. It also covers a QName missing from the
producer's current signature or a dependency closure exceeding the fixed
10,000-node safety bound. It also covers a definition slice that differs from
the recomputed checked `defType + theDef` inventory; presentation-only metadata
cannot be promoted into the executable closure. For a mixed entry, it also includes a slice planner
that finds no blocker-headed hole or whose planned blocker inventory differs
from the Treeless audit. It also covers a hole with no unique closed checked
Internal `Term : Type` match. Such a plan, or any hole packet that fails its
own decode/type/dependency self-check, is never published as valid evidence.

The current production `nbe` branch reports `CCZ-NBE-UNAVAILABLE` because no
approved adapter is linked. The test-only adapter spike now exercises both
real outcomes: its ground-call shape detector maps a repeated non-progressing
call to `CCZ-NBE-FAILED`, while a separately compiled 32-step variant maps
deterministic fuel exhaustion to `CCZ-ENGINE-TIMEOUT`. Other compile-time fault
variants continue to test the same contract without exposing fault injection
in the production CLI. Wall-clock deadline and allocation enforcement remain
a separate open production task.

`CCZ-NBE-UNSUPPORTED` is the only engine outcome eligible for the explicit
`--cubical-chez-nbe-fallback=agda-baseline` policy. The default is `reject`.
Unavailable, timeout, execution-failed, and invalid-readback outcomes never
fall back. A successful explicit fallback records `nbe` as requested and
`agda-baseline` as effective, so it cannot be counted as NbE evidence.

`make verify-nbe-fallback` checks one explicit fallback and six
fail-closed cases. It proves unsupported rejection, fallback provenance,
unavailable/timeout/execution-failed non-fallback, invalid-readback rejection,
and the engine/policy configuration constraint.

For mixed residuals, `CCZ-SCHEME-LOWERING-FAILED` also protects the static-shell
boundary. A missing/duplicate typed-hole import path or a blocker-headed
Treeless subtree not replaced by `opaque-import-v1` prevents publication of the
shell, manifest, whole-entry packet, and hole packets.

The generated ground bridge has a separate runtime namespace because these
errors occur after successful backend publication:

| Code | Meaning |
| --- | --- |
| `CCZ-TYPED-BRIDGE-CONFIG` | required runner, Agda data, source, include, consumer, packet, or path configuration is absent/invalid |
| `CCZ-TYPED-BRIDGE-HOLE-SELECTION` | the requested stable hole ID is empty/unknown or forcing selectors conflict |
| `CCZ-TYPED-BRIDGE-OBSERVATION` | batch mode or its exact ID-to-consumer mapping is missing, duplicate, unknown, or conflicts with single-hole selection |
| `CCZ-TYPED-BRIDGE-CALL` | Bool/Nat/Word64/Char/Int unary, dependent, or ordered ground-vector callable elimination has incomplete/ambiguous options, an invalid/out-of-range argument or QName/ID, a codec/capability mismatch, a non-capable hole, or a conflicting execution mode |
| `CCZ-TYPED-BRIDGE-ENVIRONMENT` | automatic lexical replay saw an invalid Chez Bool constructor, bounded Nat/Word64 integer, Unicode-scalar Char code point, or signed-64 Int constructor; an ordered-slot count/codec/order mismatch; a missing/duplicate bound hole; an unsafe type/consumer QName; an unsupported entry shape; or an execution-mode conflict |
| `CCZ-TYPED-BRIDGE-PROXY` | typed proxy create/derive/consume/release/GC has an invalid or duplicate ID, missing or released pair, invalid metadata/parent, codec mismatch, publish conflict, duplicate GC flag, or conflicting execution mode |
| `CCZ-TYPED-BRIDGE-QUOTA` | proxy publication has an invalid count/byte limit, would exceed complete-pair count or aggregate bytes, or cannot acquire/recover the store publication lock |
| `CCZ-TYPED-BRIDGE-TRANSACTION` | a lifecycle transaction cannot write, acquire, validate, or release the shared proxy-store owner lock |
| `CCZ-TYPED-BRIDGE-RUNNER-EXIT` | the checked v2 runner exited nonzero, including a dependent branch/type mismatch |
| `CCZ-TYPED-BRIDGE-DIRTY-OUTPUT` | a successful runner emitted stderr, unexpected proxy stdout, multiple lines, or a non-Bool/Nat ground result |
| `CCZ-TYPED-BRIDGE-PROTOCOL` | the generated ground-codec registry or executable descriptor table failed its cardinality/order/ABI/prefix/procedure/fingerprint self-check, or the helper response, exit-status frame, import handle, or decoded payload violated the ground ABI |

`verify-agda29` exercises Bool/Nat observations and checked
single/unary/ordered/dependent Word64
arguments through the real archived runner, then proves missing configuration,
runner exit 1, and dirty output are nonzero rejections. The shell reads exactly
one response plus one exit-status frame and rejects any trailing datum or
stderr before decoding.

The same gate also publishes two independently typed holes with different
consumer domains. Both stable IDs force successfully with their matching
consumers. An unknown ID and conflicting selectors fail before runner startup;
using the second consumer on the first ID reaches the selected packet and is
rejected by the v2 type check, then reported as `CCZ-TYPED-BRIDGE-RUNNER-EXIT`.
Batch observation additionally proves a complete ID-to-consumer mapping emits a
deterministically ordered two-result bundle. Missing, duplicate, unknown, and
selector-conflicting mappings all reject as `CCZ-TYPED-BRIDGE-OBSERVATION`
before a runner starts.

The second hole also advertises a Bool-unary callable capability derived from
its checked Pi domain. Applying `false` and passing the typed intermediate to a
`Residual → Bool` consumer returns `true`. Selecting the non-capable first
hole, using an invalid Bool, omitting call fields, supplying a non-QName token,
or mixing call and force modes rejects as `CCZ-TYPED-BRIDGE-CALL` before the
runner. A deliberately wrong named domain forms a well-typed consumer locally
but disagrees with the packet domain; the v2 type gate rejects it and the shell
reports `CCZ-TYPED-BRIDGE-RUNNER-EXIT`.

The Nat fixture independently advertises
`nat-unary-ground-elimination-v1`; argument `7` is applied inside Agda and its
typed `Residual` result is consumed as Nat `42`. Negative, non-decimal, or
values above `4294967295`, Bool/Nat codec mismatch, and wrong packet domain all
fail under the same two stable call/runner error classes.

`MixedResidualWord64Callable` advertises
`word64-unary-ground-elimination-v1`. Zero and the maximum unsigned 64-bit
value are reconstructed with `Agda.Builtin.Word.primWord64FromNat`, applied
inside Agda, and produce distinct typed results. `18446744073709551616`, Nat
codec substitution, and overflow proxy materialization reject locally as
`CCZ-TYPED-BRIDGE-CALL`; a wrong named domain reaches the runner equality gate,
and duplicate proxy publication reports `CCZ-TYPED-BRIDGE-PROXY` without
changing the original bytes.

`MixedOpenResidual` proves the same namespace for explicit closure
environments. Its source hole is open in one checked Bool variable, but the
published packet is the closed lambda-lifted function `Bool → Residual`.
Supplying Bool `true` through the call ABI succeeds. Omitting the environment
by using a `Residual` consumer reaches Agda's packet-domain equality gate and
reports `CCZ-TYPED-BRIDGE-RUNNER-EXIT`; selecting the Nat codec for the
Bool-capable environment rejects locally as `CCZ-TYPED-BRIDGE-CALL`.

The same fixture also proves `CCZ-TYPED-BRIDGE-ENVIRONMENT` for automatic
lexical replay. The shell accepts only an arity-one builtin-Bool capability,
validates the Chez Agda constructor at the exact hole occurrence, and requires
exactly one selected bound handle. Invalid Bool input, a missing/duplicate
binding, unsafe type/consumer QName, or an execution-mode conflict rejects
before typed invocation. Captured `true` and `false` are applied inside the
Agda consumer and return the corresponding checked result.

`MixedOpenNatResidual` exercises the parallel Nat capability. The shell
accepts only a decimal `0..4294967295` entry value, validates the Chez exact
integer at the hole occurrence, and applies it inside Agda. Zero and successor
choose different transport inputs and return checked `true` and `false`.
Negative/overflow input, a missing binding, incomplete configuration, and a
mode conflict all reject as `CCZ-TYPED-BRIDGE-ENVIRONMENT`.

`MixedOpenWord64Residual` exercises the parallel Word64 capability. The shell
accepts only a decimal `0..18446744073709551615` entry value and reconstructs
it with `Agda.Builtin.Word.primWord64FromNat` inside the checked application.
Zero and the maximum value return checked `true` and `false`. Negative or
overflow input, Nat-codec substitution, a missing binding, incomplete
configuration, and a mode conflict all reject as
`CCZ-TYPED-BRIDGE-ENVIRONMENT`.

`MixedOpenGroundResidual` extends that namespace to an ordered non-dependent
`Bool, Nat` telescope. The shell accepts exactly the checked codec order and
slot count before reconstructing the Agda multi-application. Swapping the two
slots, omitting or adding one, using Bool in the Nat slot, duplicating the hole
selector, or overflowing Nat all reject as
`CCZ-TYPED-BRIDGE-ENVIRONMENT`; three valid value combinations prove that both
captured slots affect the checked transport result.

`MixedOpenWord64GroundResidual` proves the parallel checked ordered
`Bool, Word64` vector. Decimal values through `18446744073709551615` are
reified with `Agda.Builtin.Word.primWord64FromNat`; selecting `nat:0` for the
Word64 domain or using `18446744073709551616` rejects under the environment
namespace for lexical replay and the call namespace for explicit replay.

`MixedOpenDependentResidual` covers `Bool, Slot flag`, where `Slot true = Nat`
and `Slot false = Bool`. Four branch-correct applications pass through
`dependent-ground-chez-lexical-binding-v1`. Supplying Bool on the true branch,
Nat on the false branch, or swapping the arguments produces valid erased
ground representations but an invalid dependent application, so Agda rejects
them as `CCZ-TYPED-BRIDGE-RUNNER-EXIT`. Missing and extra slots still reject
locally as `CCZ-TYPED-BRIDGE-ENVIRONMENT`.

`MixedOpenDependentWord64Residual` covers `Slot true = Word64` and
`Slot false = Nat`. The captured erased integer is preserved without guessing
its codec; the explicit `word64:` or `nat:` selector determines the literal
submitted to Agda. Wrong-branch selectors reject as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`, while negative/overflow Word64 input rejects
locally as `CCZ-TYPED-BRIDGE-ENVIRONMENT` or `CCZ-TYPED-BRIDGE-CALL` according
to the lexical or explicit path.

`MixedOpenDependentChainResidual` extends the same contract to three slots,
where the third domain depends on both preceding values. Eight branch-correct
applications pass. A wrong second slot, any of four wrong third-branch codecs,
or a swapped first slot reaches Agda and rejects as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`; missing and extra chain slots reject locally as
`CCZ-TYPED-BRIDGE-ENVIRONMENT`.

The ordered and dependent packets also exercise explicit vector calls without
evaluating the enclosing entry. Ordered `nat,bool` against a checked
`bool,nat` capability, a one-slot vector, consumer/proxy action conflict, and an
unsafe explicit proxy ID reject as `CCZ-TYPED-BRIDGE-CALL`. A syntactically
valid but branch-incompatible dependent triple reaches Agda and rejects as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`. Positive ordered/dependent calls and explicit
proxy create/consume/drop prove that this path is independent of lexical
capture.

The same chain can replace its immediate result consumer with
`--auto-bind-proxy-id`. Creation, two later consumes, a typed derive, parent
retention, child consumption, and recursive collection pass. Six controls pin
the failure mapping: a duplicate or invalid ID rejects as
`CCZ-TYPED-BRIDGE-PROXY`; specifying both a result consumer and proxy ID rejects
as `CCZ-TYPED-BRIDGE-ENVIRONMENT`; a wrong dependent branch during
materialization and wrong root/derive consumer domains reject as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`. Failed derivation publishes no target pair.

The same Nat application is also persisted as a packet/metadata pair rooted at
`typed-proxy-nat-seven`. Creation and two later consumptions succeed across
separate Chez processes. A checked `wrapResidual` consumer derives a child
proxy; releasing the root retains its files but blocks further root
consume/derive operations, while the child still returns `42`. Releasing the
child recursively collects both child and released root, and repeated GC is
idempotent. Duplicate creation preserves the original packet byte-for-byte; an
invalid ID, a released/missing source, or malformed metadata rejects as
`CCZ-TYPED-BRIDGE-PROXY`. Wrong consume/derive domains reach the v2 equality
gate and report `CCZ-TYPED-BRIDGE-RUNNER-EXIT`. The bridge writes private
same-directory packet/metadata temporaries and publishes with no-clobber hard
links; a partial pair left by interruption is removed by the next fixed-point
GC without deleting a live graph.

Proxy publication additionally enforces a default 256-pair/64-MiB store bound
under an atomic directory lock. A byte-limit control completes the checked
runner into private files and then rejects before either public link exists.
Two concurrent distinct-ID publishers under a count limit of one produce
exactly one valid pair and one `CCZ-TYPED-BRIDGE-QUOTA` rejection. Dropping the
winner makes the capacity immediately reusable. Invalid limits, count/byte
overflow, and lock timeout therefore have a distinct stable failure class and
do not masquerade as type or proxy-identity failures.

Lifecycle readers and writers now use that same owner lock rather than a
publication-only critical section. A stale dead-PID lock is reclaimed;
publish/GC races preserve one complete active pair; consume holds the lock
through checked use; and two simultaneous drops produce one successful state
transition plus one ordinary `CCZ-TYPED-BRIDGE-PROXY` rejection. State updates
use a private `.meta.state` file followed by atomic rename, and GC removes an
interrupted temporary. Ownership/protocol failures are separately reported as
`CCZ-TYPED-BRIDGE-TRANSACTION`.

`make verify-failure-taxonomy` checks six critical, mutually
distinct non-success paths: unavailable NbE, engine timeout, NbE execution
failure, residual required, residualization failure, and unsupported input.
Each case extracts exactly one code and proves that no Scheme, manifest, or
packet artifact is published. Producer safety negatives in the Agda 2.9 gate
also assert `CCZ-RESIDUALIZATION-FAILED`. Errors emitted by the independent v2
consumer are outside this backend code namespace.
