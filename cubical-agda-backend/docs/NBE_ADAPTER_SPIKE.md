# In-process NbE adapter feasibility spike

## Status

`EXPERIMENTAL — test-only, not a selected production provider`

The spike proves a real `Agda Internal Term + Type -> semantic evaluation ->
Agda Internal readback` path. It is compiled only with
`CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE`; the production binary still maps
`--cubical-chez-engine=nbe` to `CCZ-NBE-UNAVAILABLE` while the provider lock is
`unselected`.

Successful spike evidence uses the effective engine name
`nbe-spike-test-only`, never `nbe`. This keeps its results out of the formal
production-NbE differential and performance gates.

## Implemented semantic slice

`src/CubicalChez/Nbe/AdapterSpike.hs` implements a cctt-informed semantic
domain without calling Agda's term normalizer:

- de Bruijn environments;
- closures retaining the checked body and its environment;
- literal and constructor semantic values;
- level-based neutrals for open readback under lambdas;
- application and beta evaluation;
- ordinary definition lookup through the current Agda signature;
- request-local `QName -> Definition` caching with hit/miss evidence;
- variable, constructor, literal, and dot clause-pattern matching;
- canonical builtin Nat values, including literal/`zero`/`suc` pattern
  interoperability and structurally recursive ordinary definitions;
- exact primitive classification through Agda `PrimitiveId`, with registered
  `PrimNatPlus`/`PrimNatMinus`/`PrimNatTimes` evaluation, partial application,
  neutral preservation, Internal readback, and a checked `PrimComp` expansion
  using the same transport-plus-hcomp equation as Agda's `mkComp`;
- builtin interval endpoint recognition plus exact `PrimIMin`/`PrimIMax`/
  `PrimINeg` cofibration evaluation, including one-known-endpoint
  annihilator/identity rules and double-negation over a neutral face;
- a deliberately narrow Kan slice: `PrimTrans` reduces for the generic
  `phi = i1` identity rule and for a family proven to normalize to exact
  builtin Nat, the exact non-dependent function type `Nat -> Nat`, or a
  universe; `PrimHComp` reduces for exact builtin Nat at `phi = i0` and uses
  the universal side-at-one rule at `phi = i1`;
- `IApply` beta evaluation for closures, path constructors, reducible
  definition/primitive heads, and internal composition closures, plus
  variable-like `IApplyP` binding for checked system/path clauses; an internal
  interval probe may be used while proving a supported family shape and must
  not escape that check;
- exact `PrimGlue`/`Prim_glue`/`Prim_unglue` registry entries with neutral
  preservation/readback, the checked definitional cancellation
  `unglue (glue t a) = a`, and bidirectional canonical `ua` transport guarded
  by exact `i ∨ ~i`, endpoint, closed-base, and direction-specific identity
  checks; reverse use additionally requires an isomorphism-backed checked
  inverse and dual ground round-trip; general Glue Kan transport and HCompU
  remain unsupported;
- guarded canonical-domain Pi transport plus a closure base; a syntactically
  non-dependent codomain may be stable closed or another canonical Glue path,
  while a binder-mentioning codomain is admitted only if opaque-binder
  evaluation yields the same closed definition at the probe and both
  endpoints; application extracts a checked inverse, validates two ground
  forward round trips, invokes the source closure, and for a varying codomain
  applies its checked forward map to a ground result; one exact dependent
  self-path codomain additionally validates builtin `PathP`, equal opaque
  binder endpoints, an interval-independent inner path closure with endpoint
  readback agreement, and source reflexivity at three
  interval observations before returning an internal target reflexive path;
  a sibling singleton codomain validates builtin Sigma, a first type matching
  the Pi domain, and a `PathP` in either explicitly classified binder/field
  endpoint order, then requires the source to be `(source-b , refl)` before
  rebuilding `(target-b , refl)`; the directions have separate telemetry;
  nested Sigma codomains use an exact-depth recursive spine classifier and
  value rebuilder: every layer validates a builtin Sigma shell, Pi-domain first
  type, and canonical source point, while only the final field may be the
  direction-classified reflexive path; the audited bound is three layers, so
  unapplied readback, four or more layers, and broader dependent codomains fail
  closed;
- data/record type applications preserved as neutral type heads; exact builtin
  Sigma/List identities still gate structured transport, while dependent
  stable-identity additionally requires equal closed type readback and validates
  ordinary constructor parameters/payload arity through `conPars`/`conArity`;
  an ordinary function payload is accepted only when semantic readback yields
  an Agda-closed lambda, while internal composition/transport closures remain
  non-readable and fail closed;
- direct Pi field types admitted only after all probe/i0/i1 semantic views
  read back to Agda-closed terms; the selected stable plan carries the count
  until value reconstruction, so speculative classifier branches do not alter
  telemetry, while a Pi domain retaining a prior field neutral rejects;
- general algebraic constructors and recursive constructor-pattern clauses,
  exercised by a separate `Tree` rather than only builtin Nat;
- proper record projection lookup through `Function.funProjection`,
  `Record.recFields`, and constructor `conData`/`conPars` metadata;
- projection reduction on fully constructed records and neutral projection
  preservation/readback under lambdas and dependent Pi types;
- an active-call set keyed by definition QName plus finite ground argument
  shape, so a repeated non-progressing call is distinguished from ordinary
  structural recursion;
- quotation back to Agda `Term`;
- a separate semantic `Type = El Sort Term` domain;
- ordinary `Pi`, universe, `PiSort`/`FunSort`/`UnivSort`, and
  `Max`/`Plus` level evaluation and level-based readback;
- parameterized type-alias unfolding through ordinary checked clauses and
  universe-polymorphic level joins with multiple neutral atoms;
- per-request Type/Sort/Level node counters proving that type readback used the
  adapter path;
- definition-reduction and maximum-level-atom counters proving that alias
  unfolding and the two-atom `a ⊔ b` path actually executed;
- primitive-registry-hit and primitive-reduction counters proving that builtin
  arithmetic used registered identity rather than rendered QName text;
- interval-operation, transport, and hcomp counters proving that the locked
  ground Cubical fixture traversed each semantic branch;
- neutral-cofibration, path-application, exact-Nat-transport, and exact
  Nat-function-transport counters proving that the open-face and exact
  `TransportBase.t02/t07` paths executed;
- a Glue cancellation counter proving that the result did not come from QName
  text matching or the Agda normalizer;
- a Glue-transport counter proving that exact `TransportGlue.t03` applied its
  starting equivalence rather than returning the input unchanged;
- composed-Glue and Pi-transport counters proving that exact
  `TransportGlue.t04/t08` traversed their guarded semantic rules;
- a varying-Pi-codomain counter proving that the local two-sided function
  transport applied its codomain forward map after the source closure;
- a backward-Glue counter distinguishing exact reverse `TransportInt.t06`
  from forward `t05`;
- record/data transport counters distinguishing exact Sigma `t09` from List
  `t10`;
- exact checked definition/primitive-head `DefP` matching, `PrimComp`
  expansion, universe-transport, and nested probe-HComp counters used by the
  guarded S¹ `TransportHit.t12/t13` slice, including a backward-Glue counter
  for the final inverse segment of `t13`;
- a deterministic 100,000-step fuel ceiling.

The request `Type` no longer calls Agda `normalise` in the spike branch.
Staging records
`nbe-type-normalizer: semantic-type+sort+level+alias-eval-readback-v1`. The locked
polymorphic Pi fixture evaluates 5 Type, 6 Sort, and 6 Level nodes and produces
byte-identical Treeless/Scheme output versus the oracle. Every readback is
still checked by Agda's shared closed/meta/type admission gate; that check is a
validator, not the spike's normalizer.

Postulated `DefS` sorts are unconditionally rejected under
`postulated-sort-policy=reject-v1`; this Internal form is produced when
unsolved sort metas are persisted as postulates, not by ordinary closed
well-typed source. A fault build injects an actual `DefS` to keep this branch
under both version gates. Non-record or inconsistent projections, path
applications outside the admitted heads, path patterns, unmatched HIT
definition patterns, term/sort metas, dummy
terms/sorts, postulated sorts, unregistered primitives, axioms, other
unsupported definition nodes, and unmatched clauses fail
closed. The test fixture applies a postulate and receives
`CCZ-NBE-UNSUPPORTED` before any Scheme, Treeless, staging, manifest, or packet
publication survives. A repeated ground call reports `CCZ-NBE-FAILED` with a
`recursive-cycle` diagnostic. A separately compiled 32-step verifier variant
reports deterministic exhaustion as `CCZ-ENGINE-TIMEOUT` with a
`fuel-exhausted` diagnostic. Neither failure leaves a publication artifact.
A separate fault build replaces a checked record receiver after projection
metadata validation. It receives `CCZ-NBE-UNSUPPORTED` with a stable invalid
receiver diagnostic and zero publication artifacts. This validates the branch
without requiring an ill-typed Agda source fixture.

Successful staging records the cache policy and per-request hit/miss counts,
the ground-call cycle policy, maximum call depth, and fuel consumed. For
`double 21`, the locked evidence is 1 cache miss, 21 hits, maximum depth 22,
and result 42.

Unsupported definition diagnostics carry the evaluation stage, exact Internal
node kind, checked QName, and binding-site source range. `primStringAppend` is
therefore rejected as `Primitive(PrimStringAppend)` at its Agda builtin source
location. A local postulated `_+_` is separately rejected as an `Axiom` at the
fixture location, proving that a same-rendered-name impostor cannot enter the
primitive registry.

The ground Cubical fixture evaluates
`hcomp {A = Nat} {phi = i0} ... (transp (lambda _ -> Nat) i1 42)` where both
faces are built from `i0`, `i1`, `primIMin`, `primIMax`, and `primINeg`. It
returns 42 and records four interval operations, one transport, and one hcomp.

A second fixture normalizes
`~~((phi ∧ i1) ∨ i0)` back to the neutral `phi`, records three neutral
cofibration simplifications, and transports 42 through an exact Nat family at
that open face. Its `groundZero` entry separately proves exact Nat-family
transport at `i0`; `functionZero` proves that exact non-dependent `Nat -> Nat`
transport remains callable and maps `suc 3` to 4.

The pinned Agda 2.9-only exact-source gate extracts `t01`, `t02`, and `t07`
proof blocks from `test/fixtures/TransportTests.agda`, requires byte identity with the
maintained `TransportBase.agda` projection, and compares the adapter with the
Agda baseline. The entries return 7/7/4; observed output, Treeless, and Scheme
are byte-identical. `t02` records exact-Nat transport and `t07` records one
exact Nat-function transport followed by ordinary application. Non-Nat hcomp,
general dependent Kan, non-canonical Glue Kan/HCompU outside the exact
double-composition/probe-HComp shells, and general HIT semantics remain
unsupported.

The first Glue fixture works at the empty face `i0`. It constructs explicit
empty partial type/equivalence/value systems, forms `prim^glue t 42`, and then
applies `prim^unglue`. The adapter records two exact Glue primitive registry
hits and one introduction/elimination cancellation, returns 42, and remains
byte-identical to the baseline. The cancellation remains independent of the
transport rules; `Prim_glueU`, `Prim_unglueU`, general Glue Kan, and general
HCompU are still unsupported.

The separate pinned Agda 2.9 exact Glue gate extracts the original `t03`,
`t04`, and `t08` proof blocks and requires byte identity with
`TransportGlue.agda`.
For `t03`, the adapter evaluates definition-headed path applications, selects
the proper Sigma copattern, validates the canonical `ua` geometry at a neutral
interval and both endpoints, and applies `notEq` to `true`. The result is
`false`; observed output, Treeless, and Scheme are byte-identical to the Agda
baseline, with four path applications, one transport, and one Glue transport
recorded. For `t04`, the adapter observes the outer universe `hcomp` at a
neutral probe and both endpoints. It admits the composition only when the
probe face is exactly `i ∨ ~i`, all three side spines share one definition
head/arity, the left boundary is a stable closed type, the centre and right
boundary independently pass the canonical Glue checks, and their intermediate
types agree. It then applies both forward functions, yielding `true` with 14
path applications, one transport, one Glue transport, and one composed-Glue
transport. Observed output, Treeless, and Scheme are byte-identical to the
baseline. A local three-nontrivial-path double composition violates the
constant-left-boundary guard and remains a zero-publication expected rejection.

For `t08`, the transported family has canonical `ua notEq` as its domain and
the stable closed builtin `Bool` as its syntactically non-dependent codomain.
The transported identity closure is represented by a guarded semantic value
that deliberately has no standalone readback. On application, the adapter
finds the checked record-constructor argument in the canonical equivalence's
proof, validates the expected four-field isomorphism metadata, and uses its
inverse to move the target argument back to the source domain. It accepts the
application only when both the isomorphism forward field and the canonical
equivalence forward map return the original ground target. The source closure
then maps the recovered argument to `false`. No `ua`, isomorphism, or fixture
QName is used for recognition. The result, Treeless, and Scheme are
byte-identical to baseline; staging records one transport, one Glue transport,
and one Pi transport. The local `notPath i → notPath i` extension uses the same
domain inverse, invokes the identity at the recovered `false`, then maps that
source result through the codomain forward equivalence to return `true`.
Observed output, Treeless, and Scheme are again baseline-equal; staging records
13 path applications and varying-Pi-codomain=1. Both intermediate and final
results must be ground. The additional
`(b : notPath i) → ConstantType b` family mentions `b`, but `ConstantType _ =
Bool`; opaque-binder evaluation therefore produces the same closed `Bool` at
all three observations. Its transported identity returns `false`, remains
baseline-equal, and records semantic-constant-Pi-codomain=1 while the varying
counter stays zero. The genuinely dependent
`(b : notPath i) → b ≡ b` shape is now a separate guarded branch. The builtin
`PathP` endpoints must both be the opaque binder, its inner closure must not
reference its interval binder, its family must remain the Pi domain at two
outer and three inner interval observations, and the
source proof must evaluate to the source argument at `i0`, a neutral probe,
and `i1`. The returned internal reflexive path is immediately observed at
`i0`, yielding `true`; staging records 11 path applications and
dependent-self-path-Pi-codomain=1. The canonical dependent singleton
`(b : notPath i) → Σ[ x ∈ notPath i ] b ≡ x` matches the Sigma first type
and its directed `PathP` second family against the Pi domain, validates a
source `(b , refl)`, then rebuilds the target pair. Its `fst` observation is
baseline-equal at `true`; staging records 13 path applications and
dependent-singleton-Pi-codomain=1. Its symmetric `x ≡ b` orientation now
passes the same structural/value guards under an explicit reverse direction,
also returns `true`, and records 13 path applications plus
dependent-reversed-singleton-Pi-codomain=1 while the forward counter remains
zero. The exact nested
`Σ x ∈ A. Σ y ∈ A. b ≡ x` shape validates both Sigma first types,
the outer source point, the auxiliary point's checked transport, and the final
proof before rebuilding
`(target,(target,refl))`; it returns `true`, records 31 path applications and
dependent-nested-singleton-Pi-codomain=1, with both single-layer counters zero.
The reversed nested path now passes under an explicit direction, also returns
`true`, and records 31 path applications plus
dependent-reversed-nested-singleton-Pi-codomain=1 while the forward nested
counter is zero. The same recursive mechanism admits the exact three-level
`Σ x. Σ y. Σ z. b ≡ x` spine and its reversed `x ≡ b` orientation,
rebuilds `(target,(target,(target,refl)))`, and returns `true` in both cases.
Each records 43 path applications and only its dedicated forward/reverse
Sigma-spine counter `1`. Auxiliary ground points may differ from the binder:
each goes through canonical forward and checked inverse round-trip. The local
`not b`/`not b` source transforms both points from `true` to `false`, returns
`true`, records 43 path applications, and increments the fieldwise counter by
two. An explicit `SameType (notPath i) x` field family may mention `x` while
evaluating to the same domain path: the per-layer guard requires matching open
Glue shells, base/face identity, and equal endpoint readbacks. Its independent
source `true` maps to `false`; the observer returns `true`, records 31 path
applications, nested-singleton=1, and fieldwise=1. The stable
`ConstantType x = Bool` control has equal closed endpoint types but no matching
open Glue shell, so it is rejected with zero publication. Non-ground auxiliary
points, unmatched probe shells, and four-level nesting remain unsupported.

The separate exact Int gate applies the same geometry to `ua sucEq`. `t05`
uses the checked forward map and returns `pos 1`. For `t06`, evaluating
`sym sucPath` first uses builtin endpoint semantics to match the `i0/i1`
system constructor patterns. A distinct reverse classifier then requires the
start partial type to be the stable base and its equivalence to act as
identity, while the end supplies `sucEq`. Only after these checks does the
adapter extract `predℤ` from the checked four-field isomorphism record, map
`pos 0` back to `negsuc 0`, and verify both `sucℤ` forward paths return
`pos 0`. The output, Treeless, and Scheme artifacts are byte-identical to the
baseline; the backward counter is zero/one for `t05/t06`. A nested
`sucPath (i ∨ ~i)` endpoint family is a zero-publication expected rejection.

The exact Core gate handles two structured outer families. For `t09`, the
probe/i0/i1 values must all be exact builtin Sigma applications. Their first
parameters must form a canonical `notPath`; applying each second-family value
to an opaque field probe must produce the same stable closed Nat type. The
base must be the checked builtin Sigma constructor with two ground fields, so
only `true` is transported and `3` is retained, producing `(false, 3)`. For
`t10`, all three outer values must be exact builtin List applications whose
element arguments form the canonical path. Checked nil/cons identities and
`conPars` validate the ground three-cell spine before `not` is recursively
mapped over it, producing `false/true/false`. Both entries are baseline-equal
in observed, Treeless, and Scheme artifacts. A Sigma whose second family also
varies and a List with nested `i ∨ ~i` element geometry are zero-publication
expected rejections.

The exact Hit gate checks metadata-guarded HIT composition, reuse, and eager
composition rather than fixture QNames. For `t12/t13`, exact definition/primitive
head patterns enter the generated S¹ eliminator clauses. `PrimComp` expands to
transport plus hcomp; universe transport and `hcomp φ=i1` reduce the generated
composition endpoints. At an internal interval probe the family must be a
nested HCompU shell whose substitution at i0/i1 readbacks exactly to the
observed endpoints, whose left boundary is constant, and whose right
boundaries recursively decompose into canonical Glue steps with matching
intermediate closed types. Each step is direction-tagged so reverse transport
cannot accidentally use the forward map. `t12` uses two forward steps and
returns `pos 2`. `t13` uses two forward steps followed by the existing checked
isomorphism inverse, returns `pos 1`, and records exactly one backward Glue
transport. For `t12`, staging records 4 checked HIT definition
patterns, 4 comp expansions, 12 universe transports, 1 direct and 1 composed
Glue transport, and 38 endpoint hcomps. For `t13`, the corresponding counts are
3 patterns, 3 comp expansions, 11 universe transports, 1 direct, 1 backward,
1 composed Glue transport, and 16 endpoint hcomps. Closed non-canonical
winding and inverse-segment controls reject with zero publication, so this is
not general S¹/HIT evaluation.

For `t14`, ordinary definition reduction unfolds Cubical
Prelude `J` to `transport (λ i → P (p i) (λ j → p (i ∧ j))) d`.
With `p = refl` and a constant Nat motive, the existing exact-Nat transport
returns 41. The original/projection block is byte-identical; staging records
two definition reductions, one primitive registry hit/reduction, four path
applications, and one transport/constant-Nat reduction. A J over the closed
non-canonical universe loop `λ i → notPath (i ∨ ~ i)` is rejected with
zero publication, so this is not general path induction.

For `t15`, the evaluator first reduces the inner `transport notPath true` to
`false`, then uses that ground result as the base of the outer identical
transport and returns `true`. The original/projection block is byte-identical
and observed/Treeless/Scheme artifacts match the baseline. Staging records
eight path applications, two transports, and two Glue transports; backward,
composed, Pi, record, and data transport counters are all zero. A separate
control retains the canonical inner transport but hides the outer family behind
`notPath (i ∨ ~ i)`. It is `CCZ-NBE-UNSUPPORTED` with zero publication, so
successful inner evaluation cannot leak a partial result.

## Differential evidence

`make verify-nbe-adapter-spike` builds isolated normal-fuel,
low-fuel, invalid-projection-receiver, and postulated-sort spike binaries and
checks twenty-three
cases:

| Case | Result |
|---|---|
| `flip (flip true)` | spike and Agda baseline both return `true`; Treeless and Scheme are byte-identical |
| `flip true` | spike and Agda baseline both return `false`; Treeless and Scheme are byte-identical |
| recursive `double 21` | spike and Agda baseline both return 42; Treeless and Scheme are byte-identical; cache/depth evidence is checked |
| polymorphic `(A : Set) → A → A` | spike and baseline procedure, Treeless, and Scheme are byte-identical; Type/Sort/Level counters are 5/6/6 |
| recursive custom `Tree` | spike and baseline both return 9; Treeless and Scheme are byte-identical |
| `Pair.right (pair 7 42)` | spike and baseline both return 42; one constructor projection is recorded |
| `(family : Family) → Carrier family → Carrier family` | spike and baseline procedures, Treeless, and Scheme are byte-identical; two neutral type projections are recorded and read back |
| `(a b : Level) → Alias (A → B) → A → B` | spike and baseline procedures, Treeless, and Scheme are byte-identical; one alias reduction and a maximum level width of two are recorded |
| registered builtin Nat arithmetic | `6 * 7 + (5 - 5)` returns 42 with three exact `PrimitiveId` registry hits and three reductions; Treeless and Scheme are byte-identical |
| ground interval/`transp`/`hcomp` | returns 42 with 4 interval operations, 1 transport, and 1 Nat hcomp; Treeless and Scheme are byte-identical |
| open/neutral cofibration function | adapter and baseline procedures, Treeless, and Scheme are byte-identical; 3 neutral identities and 1 exact Nat transport are recorded |
| exact Nat transport at `i0` | returns 42 with one exact Nat-family transport; Treeless and Scheme are byte-identical |
| exact `Nat -> Nat` transport at `i0` | transported `suc` remains callable and returns 4 at argument 3; one exact Nat-function transport is recorded; Treeless and Scheme are byte-identical |
| Glue introduction/elimination cancellation | `unglue (glue t 42)` at the empty face returns 42 with two exact Glue registry hits and one cancellation; Treeless and Scheme are byte-identical |
| postulate application | `CCZ-NBE-UNSUPPORTED`, zero publication artifacts |
| fault-injected non-record projection receiver | `CCZ-NBE-UNSUPPORTED`, zero publication artifacts |
| fault-injected postulated `DefS` | `CCZ-NBE-UNSUPPORTED` with `postulated-sort-policy=reject-v1`, zero publication artifacts |
| unregistered `PrimStringAppend` | `CCZ-NBE-UNSUPPORTED` with exact primitive ID, QName, and builtin source range; zero publication artifacts |
| local postulated `_+_` impostor | `CCZ-NBE-UNSUPPORTED` as `Axiom` with fixture QName/source range; zero registry hits and zero publication artifacts |
| unregistered `PrimFaceForall` | `CCZ-NBE-UNSUPPORTED` with exact primitive identity, QName, and Cubical HCompU source range; zero publication artifacts |
| `loop 0 = loop 0` | `CCZ-NBE-FAILED` with `recursive-cycle`, zero publication artifacts |
| `double 21` under 32-step fuel | `CCZ-ENGINE-TIMEOUT` with `fuel-exhausted`, zero publication artifacts |
| default production binary with `nbe` | `CCZ-NBE-UNAVAILABLE`, proving the spike did not unlock production |

The same fourteen differential cases and the cycle/fuel/invalid-receiver/
postulated-sort/unregistered-primitive/impostor/`PrimFaceForall` negatives compile and execute
under the pinned Agda 2.9 tree as part of
`verify-agda29`. Every
successful readback still passes the shared closedness, meta-freedom, and Agda
type-check admission gate.

`make verify-nbe-adapter-transport-base` is a separate pinned Agda
2.9 formal gate for the exact original `t01/t02/t07` blocks. It does not count the
test-only spike as production acceptance: staging names the effective engine
`nbe-spike-test-only`, and the production provider lock remains `unselected`.

`make verify-nbe-adapter-transport-glue` is the corresponding exact
gate for `t03/t04/t08`, plus a baseline-equal local varying-codomain Pi
extension, a baseline-equal binder-mentioning/semantic-constant Pi extension,
endpoint-observed dependent self-path, both directed canonical-singleton, two
directed nested-singleton Pi extensions, both directions of a bounded
three-Sigma spine, fieldwise auxiliary-point transport, and the dependent alias
positive, plus closed, parameterized, and metadata-checked data/record stable
dependent-field identity preservation, direct closed-Pi identity, and one
outer-parameter indexed-Pi nullary application plus one ground-Bool-payload
indexed-Pi application, and non-canonical
double-composition/mismatched-dependent-field/binder-indexed-stable-lookalike/
nested-payload-indexed-function/dependent-payload-type-indexed-function/
function-payload-record/
over-limit four-Sigma fail-closed controls. Passing these
cases is test-only
feasibility evidence and does not claim general Glue Kan, HCompU, or dependent
Pi transport.

`make verify-nbe-adapter-transport-int` is the exact bidirectional
canonical `ua` gate for `t05/t06`, plus the nested-endpoint fail-closed control.
It likewise does not claim general inverse transport or Glue Kan.

`make verify-nbe-adapter-transport-core` is the exact builtin
Sigma/List gate for `t09/t10`, plus varying-second-Sigma and nested-endpoint
List controls. It does not claim general data/record transport or recComp.

`make verify-nbe-adapter-transport-hit` is the exact
`t12`-`t15` gate. It combines canonical `intLoop` winding and inverse
composition,
J-at-refl/constant-Nat, and repeated canonical Glue positives with
non-canonical winding/inverse, non-canonical J, and
canonical-inner/non-canonical-outer fail-closed controls. It does not claim
general J, S¹/HIT elimination, or Glue Kan semantics.

## Non-claims and next expansion

This is not a new complete compiler, a direct embedding of `cctt`, a mature
Cubical evaluator, or approval of a production dependency. It is the smallest
backend-owned semantic adapter slice needed to measure the actual integration
gap.

The next expansion order is:

1. an explicit per-layer transport plan that distinguishes identity/stable/
   canonical-path field families, followed by broader HCompU/dependent Kan and
   dependent/open Pi codomains beyond the exact
   self-path/singleton/bounded-Sigma-spine slices;
2. approved Git revision/license identity and production lock approval (the
   three-file content manifest is already reproducible);
3. owner approval of the final speed/RSS/timeout thresholds. The isolated
   candidate already passes the formal `t01`-`t16` differential and provisional
   three-run engineering performance profile, but neither enables the default
   production CLI by itself.
