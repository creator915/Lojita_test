# Static engine contract

The implementation currently lives in `src/CubicalChez/Backend.hs`; this
document fixes its typed boundary independently of future module splitting.

`EngineRequest` and `EngineResult` are the narrow integration boundary between
Agda elaboration and a static evaluator.

## Request

The request contains the original checked Internal `Term` and its `Type` in
the current Agda signature. The backend resolves the operator's requested
entry before constructing this request: an unqualified name matches one final
QName segment, and a qualified name must match exactly. No Treeless conversion
or type erasure has happened. An adapter must not reinterpret names using a
second elaborator.

## Result

The engine normally returns a normal/read-back `Term` paired with its normalized
`Type`. An explicitly requested NbE typed-residual disposition may instead
preserve the original checked request pair when the linked adapter reports
unsupported or its read-back type still contains a runtime blocker. Both forms
remain in the same signature and are available to the Internal audit and typed
packet path. `AgdaBaseline` is the correctness oracle. The default `MatureNbe`
build remains an explicit error until the provider identity is accepted, while
the isolated selected+linked candidate is available for acceptance testing.

Every returned pair passes `validateEngineResult` before blocker analysis or
Treeless conversion. The pair must be closed and contain no metavariables;
Agda then checks the returned `Type` and checks the returned `Term` against that
type in the current signature. A failure at any layer aborts before erasure and
before any Scheme, dump, staging, manifest, or packet artifact is published.
Successful staging records all three checks explicitly.

An NbE adapter is acceptable only if it:

1. preserves the checked type and signature identity;
2. uses typed read-back, including the existing record eta boundary;
3. returns unsupported Cubical structure explicitly instead of erasing it;
4. never silently calls Agda `normalise` as a production fallback;
5. can be compared against `AgdaBaseline` on closed acceptance cases.

## Test-only adapter spike

`CubicalChez.Nbe.AdapterSpike` implements the first restricted instance of the
request contract. It is reachable only in a binary built with
`CUBICAL_CHEZ_TEST_NBE_ADAPTER_SPIKE`, reports the effective engine as
`nbe-spike-test-only`, and independently evaluates/quotes the ordinary
`Type/Sort/Level/Pi` fragment without calling Agda `normalise` for the request
type. Its environment/closure evaluator and level-based readback handle the
locked ordinary Bool fixtures, structurally recursive builtin Nat, custom
recursive algebraic data, and proper record projections. Constructor record
fields reduce after metadata validation; projections on neutrals are quoted
back under ordinary and dependent binders. A
request-local definition cache and ground-call cycle detector publish explicit
evidence; Type/Sort/Level and record-projection counters prove the semantic
paths ran. Parameterized type aliases use the same checked clause evaluator;
the maximum-level-width counter proves neutral joins are preserved.
Postulated `DefS` sorts have the fixed `reject-v1` policy. Registered builtin
Nat arithmetic is keyed by exact Agda `PrimitiveId`; partial and non-ground
applications remain neutral and quote back to Internal. Unsupported primitive,
axiom, and other definition nodes carry stage/node/QName/source-range evidence,
including a same-rendered-name impostor control. Deterministic
fuel exhaustion and a repeated non-progressing call map to distinct failure
codes. All returned pairs still pass
`validateEngineResult`.

The registry's first Cubical slice recognizes exact builtin interval endpoints
and `PrimIMin`/`PrimIMax`/`PrimINeg`, including neutral annihilator/identity and
double-negation rules. It permits `PrimTrans` at the universally valid
`phi = i1` identity boundary and for a family proven to normalize to exact
builtin Nat or the exact non-dependent type `Nat -> Nat`; `PrimHComp` remains
restricted to exact builtin Nat at `phi = i0`. Path application beta-reduces
for semantic closures and reducible definition heads, and system `IApplyP`
patterns bind through the same checked clause environment.
`PrimComp` is deliberately not derived from these rules and remains a
structured unsupported result.

The v3 exact primitive registry also admits `PrimGlue`, `Prim_glue`, and
`Prim_unglue`. Glue type/introduction forms remain neutral unless an exact
`unglue (glue t a)` pair is observed, in which case the checked definitional
equality returns `a`. A second narrow rule admits canonical `ua` transport only
after checking the neutral face is exactly `i ∨ ~i`, both endpoint Glue faces
are total, the closed base is stable, the final partial type is that base, and
the final equivalence acts as identity on an opaque probe. It then applies the
starting equivalence function; no library QName is used for recognition.
General Glue Kan, path composition, and HCompU remain fail-closed.

The exact homogeneous-composition slice adds one guarded exception to that
general rule. When transport observes three universe `PrimHComp` views at a
neutral probe and the two interval endpoints, it requires the probe face to be
exactly `i ∨ ~i`, all side applications to share one definition head and
arity, the left boundary to be one stable closed type, and the centre and
right boundary each to pass the canonical Glue-path checks above. The centre
target must equal the right source. Only then are their two forward functions
applied in sequence. This is recognition by semantic geometry, not by the
QNames of `_∙_`, `doubleComp-faces`, or `ua`; arbitrary HCompU and general Glue
Kan remain unsupported.

A separate pinned Agda 2.9 test-only gate now proves exact original/projection
identity and byte-equal observed/Treeless/Scheme output for
`TransportBase.t01/t02/t07`. This closes those three feasibility cases for the spike,
not the formal production-NbE acceptance gate: its effective engine is still
`nbe-spike-test-only`, and the provider lock is still `unselected`.

## Isolated production candidate

The same adapter implementation can now be linked as an isolated production
candidate with `CUBICAL_CHEZ_NBE_ADAPTER_CANDIDATE`, but it becomes executable
only when `CUBICAL_CHEZ_NBE_PROVIDER_SELECTED` is also present. A linked-only
or selected-only binary returns `CCZ-NBE-UNAVAILABLE` and publishes no
artifacts. The supported build entry, `make build-nbe-production-candidate`,
first validates `NBE_ADAPTER_LOCK`, requires `status=selected`, binds
`provider=agda-specific-in-process-v1`, and requires `integration=in-process`
before it defines both keys. A schema-valid lock naming another provider cannot
authorize this candidate.

Successful candidate staging records `engine-effective: nbe`, implementation
identity `agda-specific-in-process-v1`, production-candidate linkage, and the
selected build key. It also records
`nbe-adapter-production-readiness: candidate-not-accepted`. Thus it can feed
candidate-only acceptance evidence without changing the default binary or
claiming final production approval. Every result still crosses the shared
closed/meta-free/Agda-typecheck admission boundary.

The candidate formal matrix uses the explicit
`--cubical-chez-nbe-fallback=typed-residual` policy. This policy is accepted
only for a linked adapter's `unsupported` outcome; it never invokes Agda
`normalise`, keeps `engine-effective: nbe`, preserves the original checked
term/type pair, and forces a dynamic whole-entry typed residual. Staging records
`nbe-unsupported-disposition: typed-residual-passthrough-v1`. If an otherwise
successful read-back leaves a type blocker, staging additionally records
`nbe-typed-residual-trigger: result-type-runtime-blocker-v1`. The default policy
remains `reject`; unavailable, timeout, failed, and invalid-read-back outcomes
still fail closed.

The parallel exact Glue gate closes test-only `TransportGlue.t03/t04/t08`
with results `false/true/false` and byte-equal observed/Treeless/Scheme
artifacts. `t08` uses a guarded semantic Pi transport only when the domain is a
canonical Glue path and the transported value is a closure. A syntactically
non-dependent codomain may be a stable closed type or another canonical Glue
path. A binder-mentioning codomain is admitted only when evaluation with an
opaque neutral binder yields the same closed definition at the probe and both
endpoints. Application extracts the inverse from checked four-field
isomorphism record metadata and admits it only after ground round-trip
validation; a varying codomain additionally maps the ground source result
forward. The local two-sided extension returns `true`; the semantic-constant
`ConstantType b = Bool` extension returns `false` and records its dedicated
counter. One genuinely dependent exception admits exact pointwise `b ≡ b`
only after checking the builtin `PathP` shell, opaque-binder endpoints,
an interval-independent inner closure with endpoint readback agreement, and
source proof at `i0`/neutral/`i1`. Its internal
target reflexive path must be endpoint-observed before readback and returns
`true`. A second exact exception admits
`Σ[ x ∈ notPath i ] b ≡ x` only when the Sigma first type and inner path
family match the Pi domain, the path has one of the two explicitly classified
binder/field endpoint orders, and the source value is exactly
`(source-b , refl)`; it rebuilds
`(target-b , refl)` and its `fst` observation returns `true`. The guarded
values cannot escape via unapplied readback. Nested shapes share a recursive
exact-depth classifier/rebuilder: every layer requires builtin Sigma and a
source point equal to `b`, while the terminal proof is direction-classified.
Depths two and three rebuild all target points plus `refl` in both terminal
directions, with separate direction counters. Distinct auxiliary points are
admitted only under an explicit plan checked jointly at the probe and both
endpoints. `canonical-path` requires canonical-forward plus checked-inverse
ground round-trip; `stable-identity` requires equal semantic readback across
all three views plus a recursively closed definition/level/index argument
spine without binder or field neutrals. It preserves ground values and closed
constructor spines only after `conPars`/`conArity` metadata separates closed
parameters from recursively closed payloads. An ordinary function payload is
eligible only when semantic readback yields an Agda-closed lambda, recorded by
`nbe-closed-stable-function-values-validated`; internal composition and
canonical-transport closures remain unsupported. Transformed and
preserved fields are counted separately. A field family
whose value is directly a Pi additionally requires closed semantic readback
for probe/i0/i1. The selected plan commits exactly three
`nbe-closed-stable-pi-type-views-validated` observations; speculative depth
search does not count. A Pi domain containing the earlier field neutral fails
this stable guard. A separate outer-indexed Pi plan accepts only a
non-indexed data domain whose parameters consist of closed values plus at most
one outer type-path slot and exactly one outer value slot. Runtime application
requires a constructor from that data family whose argument spine is exactly
`conArity` or `conPars + conArity`. Every payload field type must be closed
independently of all prior constructor binders, and every value must be an
exact ground `Nat`, literal, or builtin `Bool`; payloads are preserved while explicit target
type/value parameters are rewritten to the checked source type/value before
the closed ordinary source function is called. Forced constructor indices
missing from a clause pattern may be represented by an unreachable placeholder
only when Agda `freeIn` proves the clause body does not reference them. The
wrapper cannot escape unapplied. Custom nested constructor payloads,
prior-binder-dependent payload types, data
indices, dependent Pi codomains, primitives, postulates, and open source
functions remain unsupported.
A field family that syntactically mentions an earlier point is admitted only when its open
probe and the Pi domain are both Glue shells with the same base/face and have
equal `i0`/`i1` readbacks. The explicit `SameType (notPath i) x` alias passes
and records one fieldwise map; `ConstantType x = Bool` passes on the stable
plan and records one identity preservation. A parameterized `List Bool` field
also passes with its closed constructor spine. One three-layer positive keeps a
custom parameterized data value and record value, recording two preserved
fields; `Tagged x` rejects because the retained index is a field neutral, and a
function-record positive applies its preserved readback-closed identity
closure. An otherwise stable record containing an internal canonical-transport
function rejects because that semantic closure cannot escape its exact
application slice. Other non-ground auxiliary points and
depth four are explicit audit boundaries. A three-nontrivial-path
double-composition control, a reversed open-shell field, the binder-indexed
stable lookalike, the internal transport-function record, and four-level
nesting are rejected before publication. These remain bounded spike results,
not general HCompU, equivalence-proof normalization, or dependent Pi support.

The exact Int gate closes test-only `TransportInt.t05/t06` with results
`pos 1/negsuc 0` and byte-equal observed/Treeless/Scheme artifacts. Forward
transport requires identity at the end; reverse transport uses a distinct
classifier requiring identity at the start and the original equivalence at the
end. Its inverse is admitted only through checked four-field isomorphism
metadata and the same dual ground round-trip used by guarded Pi application.
The reverse staging counter is exactly one for `t06` and zero for `t05`. A
nested non-canonical endpoint family is rejected before publication. This is
bounded canonical `ua` evidence, not general bidirectional Glue Kan.

The exact Core gate closes test-only `TransportCoreB.t09/t10`. The adapter may
preserve applied type heads only when their checked identity is builtin Sigma
or builtin List. Sigma additionally requires a canonical first parameter, a
stable closed non-dependent second family at all three observations, its
checked record constructor, and ground fields; it transports only the first
field. List requires a canonical element parameter and a ground builtin
constructor spine, then maps the checked forward equivalence recursively.
Record/data staging counters are respectively `1/0` for `t09` and `0/1` for
`t10`. A varying-second-family Sigma and nested-endpoint List are rejected
before publication. No general recComp, dependent Sigma, or arbitrary
data/record rule follows from this gate.

The exact Hit gate closes `t12/t13` through a metadata-guarded S¹ slice.
Checked definition/primitive-head patterns and Agda's `mkComp` expansion enter
a recursive probe-HComp rule only when endpoint readback, constant left
boundary, direction-tagged canonical Glue segments, and closed intermediate
types all agree. `t12` takes two forward segments to `pos 2`; `t13` takes two
forward segments and one checked inverse to `pos 1`, with exactly one backward
Glue reduction. Non-canonical winding and inverse controls must fail with
`CCZ-NBE-UNSUPPORTED` and no publication.

The same gate closes `t14/t15` through already-admitted semantics. Cubical
Prelude `J` unfolds as a transport; exact `t14` fixes its path to `refl` and its
motive to constant Nat, so the result is 41 with two definition reductions,
one primitive registry hit/reduction, four path applications, and one exact-Nat
transport. A non-canonical universe-loop J must fail with
`CCZ-NBE-UNSUPPORTED` and no publication. For `t15`, call-by-value evaluation
makes the inner result the base of the outer canonical `ua notEq` transport.
It returns `true` with two transport/Glue reductions and eight path
applications; its canonical-inner/non-canonical-outer control also rejects
without publication. These checks add neither general S¹/HIT/J semantics nor a
broader Glue rule.

This spike is evidence about the adapter boundary, not the second enablement
key. The default binary contains no selectable spike engine and continues to
return `CCZ-NBE-UNAVAILABLE` for `nbe`. Full details and non-claims are in
`NBE_ADAPTER_SPIKE.md`.

## Unsupported-feature fallback policy

The default `--cubical-chez-nbe-fallback=reject` maps an adapter's explicit
unsupported-feature result to `CCZ-NBE-UNSUPPORTED`. An operator may instead
select `agda-baseline`, but only together with `--cubical-chez-engine=nbe`.
That policy invokes the oracle only for this one typed adapter outcome.

Unavailability, evaluator timeout, execution failure, and invalid read-back
are never eligible for fallback. They retain their own nonzero failure code.
In particular, enabling fallback cannot bypass the provider-lock/linked-adapter
two-key gate. Every fallback result still passes the common closedness,
meta-freedom, and Agda type-recheck gate.

Staging records requested and effective engine separately plus policy, use, and
reason. Its legacy `engine` field is the effective engine. Therefore an
`nbe` request completed by `agda-baseline` is visibly oracle output and is not
valid production-NbE differential or performance evidence.

## Failure outcome contract

All backend failures use the stable `CCZ-*` namespace documented in
`FAILURE_CODES.md` and exit nonzero. In particular,
`CCZ-NBE-UNAVAILABLE`, `CCZ-NBE-UNSUPPORTED`, `CCZ-ENGINE-TIMEOUT`, and
`CCZ-NBE-FAILED` are distinct engine outcomes. `CCZ-RESIDUAL-REQUIRED` means a sound typed residual remains
but policy declines it; `CCZ-RESIDUALIZATION-FAILED` means the requested packet
could not be safely built or validated. Human explanations may change or wrap,
but the bracketed code is the automation contract.

The current in-process adapter is the owner-approved productionization route,
but is not yet production-selected or linked, so production reaches only the
unavailable outcome. Test-only builds inject unsupported, timeout, execution failure, and
invalid read-back outcomes to validate the future adapter boundary and
fallback policy. This does not claim that production deadline or resource
enforcement is implemented.

## Chez publication ABI

A validated static `EngineResult` still cannot authorize Scheme merely by
having no runtime blocker. The complete reachable closure must lower under the
declared `chez-core-abi-v1`, and the producer checks that declaration against
the lowering implementation before returning the `StaticClosure` publication
capability. The same check runs before a mixed residual static shell is
returned.

The version fixes QName mangling, unary-curried closures and applications,
uniform tagged vectors for data and record constructors (tag index 0, field
base index 1), and explicit primitive application/first-class whitelists.
These fields are repeated in `staging.txt` and typed-residual manifests. A
declaration/implementation mismatch is a Scheme-lowering failure, never a
fallback or typed-residual request, because changing the advertised ABI cannot
change the checked source term's binding-time class.

## Provider identity and two-key enablement

`config/nbe-adapter.lock.tsv` is the machine-readable provider identity record.
Schema 1 fixes the provider, repository URI, full commit ID, source SHA-256,
license, process boundary, adapter API, acceptance profile, decision owner, and
approval date. Its current `unselected` state requires every provider-specific
field to remain exactly `UNRESOLVED`; partial selections are invalid.

`make verify-nbe-adapter-contract` checks both states and negative fixtures.
A selected record requires a full 40- or 64-hex revision, a 64-hex source hash,
`in-process` or `process` integration, and the `formal-transport-v1` acceptance
profile. Unknown and duplicate fields are rejected so schema drift is visible.

This is deliberately a two-key gate: a valid selected lock establishes source
identity but does not enable `MatureNbe`. Adapter code implementing
`engine-request-v1` must also be linked, recheck its read-back, and pass the
formal differential gate. The isolated candidate now exercises both keys, but
the checked-in lock remains `unselected`; therefore the normal production build
remains an explicit error and cannot silently fall back to `AgdaBaseline`.

## Differential acceptance contract

The formal matrix accepts `FORMAL_TRANSPORT_ENGINE=agda-baseline|nbe` and keeps
the evidence roots separate. `agda-baseline` remains under
`build/agda29/formal-transport/`; a candidate `nbe` run is written under
`build/agda29/formal-transport-nbe/` and cannot overwrite the oracle.

`verify-formal-transport-differential.sh` compares all seven exact-projection
groups plus the original-monolith group. Functional equality is the exact first
five summary columns: scenario, selected entry, expected observation, actual
observation, and PASS/residual/rejection status. A separate
`binding-time.tsv` compares each scenario's class, reason, and action. Any
independent candidate must publish that file; only legacy oracle evidence may
use the deterministic PASS→static and residual/protocol→dynamic migration.
The gate also requires equal source/projection hashes, exact fragments,
scenario inventories, expectations, and monolithic prewarm status, and
independently checks which engine produced the evidence. Timing and RSS remain
evidence but are excluded from functional equality so they can be evaluated by
the separate performance gate.

A baseline self-comparison is rejected by default. The explicitly named
`verify-formal-transport-differential-self` target only validates comparator
mechanics and writes `SELF-CHECK-PASS`; it is not acceptable NbE evidence.

The isolated candidate now passes this complete contract: all eight groups and
all 42 summary rows are `DIFFERENTIAL-PASS`. Static cases are byte/value equal;
Boundary and Higher unsupported cases use the checked typed-residual
passthrough above, with no Agda-baseline fallback. This closes functional
differential acceptance for the candidate, but not provider source/license
identity or owner approval of final production performance thresholds.

The separate performance gate repeats both engines three times with alternating
order and identical pinned inputs. It records group/aggregate median,
nearest-rank p95, min/max, MAD, peak RSS, timeouts, artifact sizes, and a fixed
stage-timing schema. The latest isolated `release-o2`
`engineering-provisional` profile passes: overall median times are 74.18
seconds for the oracle and 74.15 seconds for the candidate, with
time/RSS/allocation p95 ratios 1.016723/1.067052/0.999941. Higher RSS p95 is
1.194333 against the unchanged 1.30 ceiling. The earlier O0 narrow failure is
retained separately and neither result substitutes for owner-approved
production thresholds.

## Admission after the engine

Only a validated Internal term is scanned before Treeless conversion. This is
normally the read-back term and is the original checked term for explicit NbE
typed-residual passthrough. Runtime blockers are derived from Agda's registered Cubical
builtin/primitive identities and checked Kan-operation definition metadata.
That semantic set must agree with an explicit union of the Agda 2.8/2.9
Cubical QName catalogs. A primitive-shaped executable QName in the
Agda or Cubical primitive namespaces which is absent from that catalog is
recorded separately and rejected as `unknown-cubical-primitive`; upgrades
therefore cannot silently widen erased-code support. References occurring only
in the result type are reported but do not alone force residualization: a
runtime identity whose type mentions the interval is still safely erasable.
Treeless is then audited as a defense-in-depth check. A known blocker from
either executable-term layer retains the original `Term` and `Type`; otherwise
the term becomes only a static candidate. It may enter Chez generation only
when no unknown executable primitive was found and the separate static-closure
proof succeeds.

The binding-time classifier reports `static`, `dynamic`, `mixed`, or
`unsupported` with a stable reason/action. `dynamic` means a runtime blocker is
at the result head after binder/coercion wrappers. `mixed` means a blocker is
nested below a static constructor/control context. Its action is
`typed-residual-split-shell-ground-observation-by-id-whole-entry-reference`:
materialize uniquely matched typed holes, lambda-lift an open source over its
checked telescope, lower a static shell with an ID-addressed Bool/Nat
observation ABI, and retain the whole-entry packet as equivalence reference.
If the Internal semantic and catalog sets disagree, only one syntax layer
finds a blocker, or either layer finds an unknown executable Cubical primitive,
`unsupported` rejects without publishing a packet. True definition-internal
automatic capture of arbitrary erased-shell environments and general callable
value imports remain future work. The current typed exceptions are checked
Bool/Nat/Word64/Char/Int ground-unary elimination, explicit Bool/Nat/Word64/Char/Int
lambda-lifted unary environment application, one automatically rebound builtin
Bool, bounded Nat/Word64, Unicode-scalar Char, or signed-64 Int lexical slot, an ordered non-dependent
telescope of two to 64 Bool/Nat/Word64/Char/Int slots,
and the Bool/Nat/Word64/Char/Int length-generic ground-indexed dependent replay described
below. Ordered and dependent lambda-lifted packets also admit an explicit two-to-64-slot ground
vector without evaluating the enclosing erased entry. The complete application
from either explicit or automatic lexical paths may be consumed immediately or
published through the persistent typed-packet proxy capability documented
below.

All admitted ground codecs come from `ground-codec-registry-v1`. The producer
records `ground-codec-registry-version` and the canonical comma-separated
registry in every typed-residual manifest, and emits the same registry into the
Chez shell. Unary ABI names are derived as `<codec>-unary-ground-elimination-v1`.
The shell checks registry cardinality, uniqueness, order, and fingerprint before
validating handles or arguments; disagreement is a protocol failure, never an
implicit codec extension.

`ground-codec-descriptor-v1` must have exactly one descriptor in registry order.
Every descriptor contains `codec, unary-abi, cli-prefix, validator,
argument-reifier, entry-parser, value-reifier`; the first three fields must be
derivable from the registry member and the remaining four must be procedures.
Explicit unary/vector calls, entry vectors, and ordered/dependent replay obtain
validation and Agda literal construction through these fields. Descriptor
cardinality, ordering, prefix, ABI, or procedure disagreement fails before the
runner is invoked.

## Typed residual contract

The current `whole-entry-same-interface-v1` contract retains exactly the
checked Internal `Term` and its `Type` as executable payload. It derives and
records every direct QName referenced by that pair. Before manifest or packet
publication, the producer recomputes the inventory, repeats closed/meta/type
checks, and rejects any mismatch as `CCZ-RESIDUALIZATION-FAILED`.

Starting from that direct set, the producer resolves
`checked-type+definition-body-v1`: ordinary definitions contribute only names
from checked `defType` and `theDef` until a fixed point. Agda builtin and
primitive QNames are resolved but treated as non-expanded signature leaves.
Names appearing only in `DISPLAY`/presentation metadata are audited in a
separate excluded inventory and do not enlarge the executable slice. Missing
signature entries, a recomputed slice mismatch, and closures above 10,000
QNames fail before publication. The manifest separately records direct,
resolved, expanded, leaf, excluded-presentation, and unresolved inventories.

QName definitions and the whole signature are not embedded. The v2 envelope's
top-level module and full interface hash bind the packet to the exact consumer
signature, which supplies the transitive dependency closure and rechecks the
payload. Thus the packet carries the minimum signature identity needed by the
current same-interface consumer rather than duplicating `TCState` or the whole
program. This closes and audits the executable dependency graph for the
whole-entry contract without treating pretty-print metadata as a runtime
requirement.

For `mixed`, a second slicing contract scans Treeless in deterministic
constructor order and selects maximal blocker-headed subtrees. Stable
structural paths become hole IDs; the union of planned blocker QNames must equal
the Treeless blocker inventory.

Agda's Internal rechecker supplies the authoritative subterm and expected type.
Meta-free candidates are considered under the exact telescope observed by
Agda's Internal checker. A closed source is unchanged. An open source becomes
`teleLam telescope term : telePi telescope type`; this pair must be closed, and
its leading Treeless environment lambdas are stripped only for identity
comparison with the planned subtree. The planned subtree must have exactly one
structurally equal candidate containing its blocker inventory. The closed
packet candidate then repeats the whole typed-residual validation and
dependency-closure gates.
Zero holes, incomplete coverage, no unique typed match, a missing QName, or an
oversized graph fails as `CCZ-RESIDUALIZATION-FAILED` before publication.

The manifest records `materialized-checked-internal`, source/packet closedness,
environment ABI/arity, and the hole's type, term, validation flags, and
dependency inventories. `lambda-lifted-explicit-environment-v1` means the
packet is a closed function and its environment is supplied explicitly through
the checked call boundary; it does not claim live Chez capture. The manifest's
`residual-slice-open-hole-environment-arity-limit` is currently `64`; an open
candidate outside `1..64` is rejected before publication. Under Agda 2.9 packet
policy, each hole also gets a self-validated `typed-residual-hole-N.bin`; under
manifest policy the typed pair is recorded but `artifact` remains `none`. Static-shell
lowering is validated under manifest policy and published as
`residual-static-shell.ss` under packet policy. Exact paths become
`opaque-import-v1` handles; an incomplete import inventory or uncovered runtime
subtree fails as `CCZ-SCHEME-LOWERING-FAILED`. Packet policy also publishes
`typed-hole-ground-bridge.sh`. The shell registers all stable hole IDs,
rejects duplicates, and records `single-bool-chez-lexical-binding-v1`,
`single-nat-chez-lexical-binding-v1`, or
`single-word64-chez-lexical-binding-v1`, or
`single-char-chez-lexical-binding-v1`, or
`single-int-chez-lexical-binding-v1` only for an open arity-one builtin
ground domain. At that exact hole occurrence it captures the Chez variable,
validates the erased Bool constructor, bounded Nat/Word64 integer, Unicode
scalar Char, or signed-64 Int constructor, and later
constructs an Agda consumer that applies the captured literal before the named
result consumer.
For an open non-dependent telescope whose two to 64 leading checked Pi domains
are all builtin Bool/Nat/Word64/Char/Int, the manifest instead records
`ordered-*-chez-lexical-binding-v1`. Its codec vector is derived from the
checked type; lowering restores telescope order from the nearest-binder-first
Treeless environment, and replay requires exactly that ordered vector. Word64
accepts decimal `0..18446744073709551615` and is reconstructed through
`Agda.Builtin.Word.primWord64FromNat`, not as a Nat literal.
Char accepts decimal Unicode scalar values through `1114111`, excluding
surrogates `55296..57343`, and is reconstructed through
`Agda.Builtin.Char.primNatToChar`.
Int accepts canonical signed decimal values in the 64-bit range and is
reconstructed through `Agda.Builtin.Int.pos` or `Agda.Builtin.Int.negsuc`.
For two to 64 visible slots, when every closed domain is builtin
Bool/Nat/Word64/Char/Int and
at least one later domain contains an earlier binder, the manifest records
`dependent-ground-chez-lexical-binding-v1`. The runtime preserves all actual
representations, validates the explicit CLI codec, and reconstructs
Bool/Nat/Word64/Char/Int literals without guessing whether a small integer is Nat or
Word64. The checked runner accepts or rejects the complete dependent
application. Wrong-branch values therefore fail at the v2 type gate.
Missing, duplicate, malformed, or conflicting bindings reject as
`CCZ-TYPED-BRIDGE-ENVIRONMENT`. With explicit runner/module/consumer settings,
`--force-hole=<stable-id>` sends exactly that packet through the checked v2
consumer and accepts only a single `true`, `false`, or decimal Nat line. The bridge returns a
versioned S-expression; Chez verifies bridge exit status, rejects extra stdout
or any stderr, and decodes Bool/Nat into its existing representation. Missing
configuration, unknown/conflicting hole selector, runner failure, dirty output,
or an invalid response is a stable nonzero `CCZ-TYPED-BRIDGE-*` rejection.
`--observe-all-ground` additionally requires exactly one
`--hole-consumer=ID=QNAME` mapping for each planned ID and returns a
`cubical-chez-ground-observations-v1` bundle in stable planner order. Mapping
omissions, duplicates, unknown IDs, and selector conflicts reject before any
runner starts. The bundle contains observations, not values inhabiting the
hole domains, so it is not type-correct shell substitution.

Each hole also records `callable-abi`. The backend grants
`bool-unary-ground-elimination-v1`, `nat-unary-ground-elimination-v1`,
`word64-unary-ground-elimination-v1`, `char-unary-ground-elimination-v1`, or
`int-unary-ground-elimination-v1` only when the reduced checked hole type is
a Pi whose first visible domain is the corresponding builtin Bool, Nat,
Word64, Char, or Int. The
call CLI requires exactly one matching codec, hole ID, ground literal, named
hole-type alias, and result-consumer QName. Nat input is bounded to unsigned
decimal `0..4294967295`; Word64 accepts `0..18446744073709551615` and is
reconstructed with `Agda.Builtin.Word.primWord64FromNat`. Char accepts Unicode
scalar code points and is reconstructed with
`Agda.Builtin.Char.primNatToChar`.
Int accepts canonical signed-64 decimal values and reconstructs the builtin
`pos`/`negsuc` representation. Chez builds an annotated unary Agda consumer;
the v2 runtime checks the annotation against the packet domain, typechecks the ground
application and the result consumer, and returns only its final Bool/Nat
observation. Invalid local capability/configuration fails as
`CCZ-TYPED-BRIDGE-CALL`; typed disagreement fails in the runner. No intermediate
typed value is serialized into Chez.

For `ordered-*-ground-environment-elimination-v1` and
`dependent-ground-environment-elimination-v1`, the explicit vector CLI is
`--call-ground-hole=ID`, two to 64 repeated
`--ground-argument=bool:...|nat:...|word64:...|char:...|int:...`, and a safe hole-type QName.
Ordered calls
must reproduce the checked codec vector exactly. Dependent calls constrain only
the literal representations locally and delegate every instantiated domain to
Agda. Exactly one `--call-result-consumer=QNAME` or `--call-proxy-id=ID`
chooses immediate elimination or packet materialization. Missing/mixed options,
bad literals, ordered codec mismatch, and unsafe identifiers reject as
`CCZ-TYPED-BRIDGE-CALL`; dependent branch disagreement rejects as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`.

When a closed Bool/Nat/Word64/Char/Int unary callable or an automatic ground-environment
capability is present, the manifest additionally records
`persistent-typed-packet-v1` and
`parent-retained-recursive-gc-v1`. The explicit materialize CLI uses the same
checked Bool/Nat/Word64/Char/Int unary application. An explicit multi-slot call selects
`--call-proxy-id=ID`. The automatic lexical path instead accepts
exactly one of `--auto-bind-result-consumer=QNAME` or
`--auto-bind-proxy-id=ID`; the latter wraps the complete ordered/dependent
literal application in a checked Agda consumer. Both ask the maintained v2
runtime to normalize and serialize the typed result instead of printing it. A
validated 1–64 character
proxy ID deterministically names `typed-proxy-ID.bin` and
`typed-proxy-ID.meta`. The runtime embeds the same top-level
module/full-interface identity and `Term : Type`, refuses to overwrite an
existing result packet, and the bridge publishes same-directory packet and
metadata temporaries through no-clobber hard links. Later proxy consumption
reuses the ordinary v2 import/type-equality gate and can be repeated across
Chez processes.

`--derive-proxy=SOURCE --derive-proxy-consumer=QNAME --proxy-id=TARGET`
feeds the source packet to Agda, checks the named unary consumer, and exports
its typed result as the target packet. Metadata persists the parent ID and an
`active`/`released` state. Releasing a parent makes it unavailable for new
consume/derive operations but retains its pair while descendants exist.
Releasing the final leaf recursively collects released ancestors. Every proxy
operation first runs the same fixed-point collector; `--gc-proxies` exposes it
as an idempotent command and also removes incomplete pairs and descendants with
missing parents. Malformed metadata fails closed instead of being collected as
valid state.

All store readers that require an active pair and all lifecycle writers share
the bridge's `.typed-proxy-store.lock` owner protocol. Publication and derive
recheck target/parent state while holding it; consume and immediate map keep it
through the checked runner; drop and GC perform their complete fixed-point
transition inside it. An `active`/`released` update is written to a private
`.meta.state` file and installed by atomic rename. Dead owner PIDs and
interrupted state temporaries are recoverable. The manifest records this as
`store-lock+atomic-state-v1`.

The whole-entry packet remains the equivalence reference. Codecs beyond
Bool/Nat/Word64/Char/Int and direct insertion into erased Chez remain rejected until a
more general type-preserving value ABI exists.

For an explicit non-default entry, the normalized result must be
self-contained. A surviving definition reference is rejected by the
unresolved-closure gate; it is never silently omitted from the emitted Chez
program. This closed-entry mode is not the future module artifact protocol.

Static classification is not itself permission to erase types. The backend
constructs an opaque `StaticClosure` capability only after rechecking the
static/no-blocker invariants, resolving the entire reachable Treeless
definition closure, proving that no QName is missing, and successfully lowering
every reachable definition to Scheme. Only that capability carries Scheme to
the publisher. `staging.txt` reports `static-closure`, its reason, reachable and
unresolved definitions, Scheme-lowering status, and
`type-erasure-authorized`. An unresolved dependency is therefore recorded as
`static-closure: incomplete` and `decision: unsupported`, even though its
earlier binding-time class is correctly still `static`.
