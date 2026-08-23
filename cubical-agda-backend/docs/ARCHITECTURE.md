# CubicalChez staging architecture

Last updated: 2026-08-23 (Asia/Shanghai)

## Repository boundaries

```text
./
├── GOALS.md                        three-lane product boundary
├── DELIVERY_CHECKLIST.md           acceptance authority
├── src/
│   ├── Main.hs                       executable harness
│   ├── CubicalChez/Backend.hs        compiler policy and implementation
│   └── CubicalChez/Nbe/
│       └── AdapterSpike.hs           in-process adapter candidate core
├── runtime/agda-2.9/               maintained typed-Term runtime overlay
├── test/
│   ├── fixtures/agda/                source-level acceptance inputs
│   └── scripts/                      deterministic verification harness
├── compat/agda-2.9/                  isolated pinned-upstream adaptation
├── docs/                              architecture and compatibility ledger
├── build/                             generated binaries and evidence only
├── Makefile                           stable build/verification entry points
└── README.md                          operator-facing quick start
```

This document describes the implemented compiler/backend slice. The product
target is broader: goal 1 adds a stock Agda/MAlonzo/GHC lane, while goal 3 adds
an NbE component linked into the final program process. Neither lane is
implemented yet. The existing compiler-process adapter must not be presented
as goal 3, and static Chez publication must not be presented as goal 1.

The dependency direction is one-way: `src` depends on Agda APIs but never on
tests, compatibility patches, generated evidence, or documentation.  Test
scripts may build `src`, copy fixtures, temporarily apply `compat` patches,
and write only under `build`.  The compatibility layer may adapt the locked
external runtime but must be reversible and may not become an implicit source
dependency.  Files under `build` are observations, never build inputs.

`Main.hs` is isolated as the executable harness. Engine selection, audits,
packet production, and Scheme rendering remain in `CubicalChez.Backend`.
`CubicalChez.Nbe.AdapterSpike` is the first narrow module split: it depends on
Agda Internal/TCM and returns a semantic readback outcome, but it cannot select
an engine, publish artifacts, or change fallback policy. It is imported only
by an explicit test build or by the isolated production-candidate build. The
default binary does not link it, so it cannot act as an implicit production
provider.

This is the architecture ledger for the current slice:

| Dimension | Current decision |
|---|---|
| Goal | Produce verified static Chez output or a checked typed packet; never silently erase a residual Cubical value. |
| Context | Agda's checked `Term`, `Type`, signature, interface hash, and explicit backend options. |
| Action boundary | Static Scheme emission or typed packet emission; both are selected by deterministic backend code. |
| Constraints | Closed/meta-free packet payload, dual Internal/Treeless audit, canonical packet header, no stale executable artifact on failure. |
| Verification | Agda 2.8 smoke plus pinned Agda 2.9 cross-process positive and negative gates. |
| Correction | Fail closed, preserve diagnostics/evidence, restore temporary upstream patches through an exit trap. |
| Open decision | The provider content manifest and GitHub origin are reproducible; approved immutable revision and license identity, owner-approved performance thresholds, and a general type-preserving typed-value embedding beyond the versioned Chez core ABI and checked packet-reference boundary remain open. Formal functional differential, stage timing, and the provisional controlled O2 performance gate are complete. |

## Safety boundary

```text
Agda elaboration and type checking
              |
       Internal Term + Type
              |
         EngineRequest
               |
       static engine boundary
       /                    \
Agda baseline         in-process NbE adapter core
(oracle only)          /                     \
                 test-only build       production candidate
            effective=nbe-spike-*       selected lock + link
                                         effective=nbe
                                  readiness=candidate-not-accepted
       \                    /
        EngineResult: Term + Type
                 |
       Internal term audit
       (type refs recorded)
                 |
        candidate Treeless term
                 |
          Treeless audit
                 |
     four-way binding-time class
      /       /       \          \
 static  dynamic     mixed    unsupported
   |       |            |          |
 Chez   typed whole-entry residual  reject
             (bounded typed-hole specialization;
          no general definition-internal specialization)
```

Treeless is used as an audit candidate, not as the source of typed fallback.
If a typed blocker survives, the compiler must retain the original Internal
`Term` and `Type`; reconstructing Cubical semantics from erased Treeless is not
allowed.

## Current engine boundary

`EngineRequest` carries the checked Internal term and type, and `EngineResult`
returns the read-back term with its normalized type.  `normalizeEntry` owns
engine selection.  `agda-baseline` performs the v2 type-directed eta expansion
followed by Agda `normalise`; it provides the ground truth for differential
testing. The default production `nbe` branch is deliberately unavailable. An
isolated selected+linked candidate exercises that branch while retaining an
explicit not-accepted readiness marker; it is not emitted by the default build.
The test-only adapter spike exercises an environment/closure semantic domain
and Agda Internal readback for a small ordinary fragment including recursive
builtin Nat, custom recursive algebraic data, and proper record projections.
Constructor receivers project by checked record/field metadata; projections
from neutral values are preserved through readback, including dependent Pi
types. Definition lookup is cached per request; active ground calls and fuel
have separate fail-closed outcomes. Its ordinary `Type/Sort/Level/Pi` domain
also evaluates and quotes the request type without Agda `normalise`; staging
records semantic type provenance, node counts, projection counts, alias
reductions, and maximum neutral level width. Parameterized type aliases reduce
through their checked clauses; persisted postulated `DefS` sorts are rejected
under a fixed `reject-v1` policy. A separate exact-identity primitive registry
maps Agda `PrimitiveId` values for Nat addition, subtraction, and
multiplication; it does not classify by rendered QName. Partial and neutral
applications round-trip through Internal readback. Unsupported definition
nodes report evaluation stage, node kind, QName, and binding-site range. The
same exact registry now recognizes interval endpoints and
`PrimIMin`/`PrimIMax`/`PrimINeg`. Its Kan boundary is intentionally smaller
than Agda's: `PrimTrans` uses the generic `phi = i1` identity plus guarded
Nat/Nat-function/universe rules; `PrimHComp` uses exact builtin Nat at
`phi = i0` and the universal side-at-one rule at `phi = i1`; `PrimComp`
expands through Agda's `mkComp` equation. The v4 registry also
preserves Glue type/introduction/elimination shells, closes exact
`unglue (glue ...)`, and recognizes canonical `ua` transport by geometry. One
additional semantic matcher consumes the exact universe double-composition
shell only when its complement face, shared side head, constant left boundary,
two canonical Glue paths, and intermediate type all agree; this closes exact
`TransportGlue.t04` without matching a library QName. The locked fixtures also
admit exact `TransportGlue.t08` and a local varying-codomain extension through a
guarded semantic Pi-transport value. Its domain must be a canonical Glue path,
and its base must be a closure. A syntactically non-dependent codomain may be
semantically stable/closed or another canonical Glue path. A codomain that
mentions its binder is admitted only when evaluation with an opaque neutral
binder erases that dependency and returns the same closed definition for the
probe and both endpoints. The value cannot be quoted unapplied. At
application, the adapter finds the checked four-field
isomorphism record inside the canonical equivalence proof, applies its inverse,
and validates both available forward maps against the target ground value
before invoking the original closure. A varying codomain then maps the ground
source result through its checked forward equivalence and requires a ground
target result; no `ua` or isomorphism QName participates in recognition. A
semantic-constant codomain returns the source result unchanged and increments
a dedicated counter. The first genuinely dependent exception is an exact
self-path codomain: builtin `PathP`, the opaque Pi binder as both endpoints,
and an inner path closure syntactically independent of its interval binder and
checked equal to the Pi domain. After the domain inverse,
the source proof must return the source argument at `i0`, a neutral interval,
and `i1`; only then does an internal reflexive path return the target argument.
The second is an exact singleton Sigma codomain. Its first type must match the
Pi domain at both outer endpoints; applying its second family to a dedicated
field neutral must yield builtin `PathP` with one of two explicit endpoint
orders: binder-to-field or field-to-binder, with the same
interval-independent/domain-readback checks. At
application the source must be an exact builtin Sigma constructor whose fields
are `(source argument, reflexive proof)`; only then is `(target argument,
reflexive proof)` rebuilt. Internal reflexive paths cannot escape unapplied
readback. Nested singleton shapes use one exact-depth recursive Sigma-spine
classifier and value rebuilder rather than a branch per depth. Each layer must
be builtin Sigma and receives a plan checked jointly at the open probe and both
endpoints: `canonical-path` maps a ground point through the domain equivalence,
while `stable-identity` preserves it only when all three views have equal
semantic readback and every retained definition/level/index argument is closed
and contains no binder or field neutral. Stable constructor values then use
checked `conPars`/`conArity` metadata to separate closed parameters from exact
recursively closed payloads. Ordinary function closures are accepted only
when full semantic readback yields an Agda-closed lambda; internal
composition/canonical-transport closures and open neutrals remain rejected.
Direct Pi field types use the same principle at the type level: all three
probe/i0/i1 views must quote to closed Agda terms. The validated-view count is
carried in the chosen stable plan and committed only during reconstruction;
Pi domains that retain an earlier Sigma-field neutral do not pass stable
identity. A separate outer-indexed plan handles one audited contravariant
case: a non-indexed data domain may retain the outer type path and outer Sigma
point in identified parameter slots, while every remaining parameter and the
Pi codomain must be closed. Application checks `conData`/`conPars` and accepts
only the exact `conArity` or `conPars + conArity` argument-spine forms. It
rewrites explicit target type/value parameters to their source counterparts
and only then invokes a readback-closed ordinary function. The constructor
spine may contain payloads only when each checked constructor-field type is
closed independently of all earlier binders and each value is exact ground
`Nat`, literal, or builtin `Bool`,
which are preserved unchanged at the semantic level and
counted by `nbe-indexed-pi-ground-payload-fields-preserved`. Constructor
pattern clauses may omit forced telescope indices only when the body does not
refer to them. The internal wrapper rejects unapplied readback; custom nested
constructor payloads, prior-binder-dependent payload types, and true data
indices remain unsupported.
The outer field is always canonical and equals the
source point; only the terminal field may be the directed binder/outer-field
reflexive path. Both terminal directions and stable-field preservation have
separate telemetry. Canonically varying inner points are accepted only when
the checked inverse returns the original ground value. The audited maximum depth is three;
non-ground auxiliary points, four or more type layers, and broader dependent
codomains fail closed. Per-layer type matching also checks the open probe:
both sides must expose a Glue shell with the same base and face, and their
`i0`/`i1` specializations must read back equally. This admits an explicit
dependent alias such as `SameType (notPath i) x`, whose result is the same
domain path, without treating a stable `ConstantType x = Bool` field as if it
followed `notPath`. The latter now receives `stable-identity`, so its source
`true` stays `true`; a reversed `notPath (~ i)` shell is neither stable nor the
outer canonical path and rejects before publication. This is bounded
probe-shell identity. A closed `List Bool` application and constructor spine
are also stable, as are metadata-checked custom data/record spines; `Tagged x`
is rejected because its retained index is the prior field neutral. An ordinary
readback-closed function payload is admitted; `Tagged x -> Bool` is admitted
only through the outer-indexed plan above. `PayloadTagged x -> Bool` is also
admitted there when its Bool payload passes the exact ground whitelist, while
the same Bool value under a field type `A` is rejected because that field type
depends on the remapped outer binder. An internal
canonical-transport function rejects at value validation. This is not general
dependent-family or equivalence-proof normalization.
Direction-sensitive canonical `ua` transport has a separate reverse
classifier: the start partial type/equivalence must be the stable base and an
identity candidate, while the end supplies the original equivalence. Only
then may the existing checked isomorphism inverse and dual ground round-trip
gate run. This closes exact `TransportInt.t05/t06`; a nested non-canonical
endpoint expression remains unsupported with zero publication. Builtin
interval endpoint constructor patterns are matched by their evaluated endpoint
semantics, so `~ i1` can select the checked `i0` system clause without a QName
or fixture special case.
Structured transport adds exactly two type-constructor identities. Applied
builtin `Sigma` and `List` definitions may remain neutral; every other
record/data definition retains the previous unsupported outcome. Sigma
transport requires a canonical first-parameter Glue path, a non-dependent
second family that evaluates to the same stable closed type at probe/i0/i1,
the checked builtin Sigma constructor, and two ground fields. List transport
requires a canonical element path and a ground spine consisting only of the
checked builtin nil/cons constructors; constructor `conPars` validates the
stored parameter prefix before recursively mapping elements. These rules close
exact `TransportCoreB.t09/t10`. A varying-second-field Sigma and a List whose
element path uses a nested endpoint expression both fail before publication.
Ordinary reducible definitions may expose an already-supported primitive
boundary. Cubical Prelude `J` is defined using transport, so exact
`TransportHit.t14` at `refl` with a constant Nat motive reduces through the
existing definition evaluator and exact-Nat transport rule. A J over a
non-canonical universe loop is rejected; there is no separate general J
semantic value or elimination rule.
Nested use of an admitted primitive rule is evaluated compositionally. Exact
`TransportHit.t15` therefore needs no HIT semantic value: the inner canonical
Glue transport reduces first and its ground Bool result is passed to the outer
canonical Glue transport. A non-canonical outer family still rejects the whole
request after any inner work and leaves no publication artifacts. This check
does not expand the canonical path classifier.
Exact `TransportHit.t12/t13` add a metadata-guarded S¹ slice. `DefP` clauses match
only the checked definition or primitive head and recursively checked
subpatterns. `PrimComp` is expanded by Agda's `mkComp` equation into internal
transport/hcomp closures; universe transport and the universal `hcomp φ=i1`
rule are explicit. For the `intLoop` family, a probe HCompU shell is accepted
only when substitution of the probe by both endpoints readbacks exactly to the
observed endpoint types, its left boundary is constant, and each right boundary
recursively decomposes into canonical Glue steps with matching closed
intermediate types. Each step records its direction: forward applies the
equivalence map, while backward extracts the checked isomorphism inverse and
validates both forward round trips. Thus `t12` maps `pos 0` through two forward
steps to `pos 2`, while `t13` traverses two forward and one backward segment to
`pos 1`. Winding or inverse segments hidden behind `i ∨ ~i` fail these guards
and publish nothing. This does not implement arbitrary S¹ elimination or HIT
composition.
The locked fixtures leave no admitted Cubical primitive in Treeless or Scheme.
Open faces, general hcomp/HCompU and Glue Kan, dependent/general Pi transport,
general data/record/recComp, and HITs outside the exact definition-pattern/
probe-HComp slice remain fail-closed or neutral rather than being guessed. The
shared Agda
readback admission check remains mandatory. This restricted fragment is now
exercised through the isolated production candidate and accepted by the formal
functional differential; it is not yet a fully accepted production provider
because immutable revision identity, license approval, and owner-approved
performance thresholds remain open. Its three-file content manifest is pinned,
and the isolated controlled O2 release run passes all provisional gates;
Higher/typed-residual RSS p95 is `1.194333` against the unchanged `1.30`
ceiling. The historical O0 run remains recorded separately as a narrow fail.
An adapter can later return an explicit unsupported-feature result. That
result rejects by default; the operator-only `agda-baseline` fallback is
narrowly scoped to it and records the effective engine as baseline.
The explicit `typed-residual` alternative preserves the original checked pair,
forces dynamic whole-entry residual handling, retains effective engine `nbe`,
and does not invoke the baseline normalizer.
Unavailable, timeout, failed, and invalid-readback outcomes remain fail-closed.
See `ENGINE_CONTRACT.md`.
The inspected `AndrasKovacs/cctt` candidate is not a drop-in Agda library; see
`NBE_SELECTION.md` for the semantic and packaging gap.

The boundary does not trust either implementation's read-back. Before
Treeless conversion, `validateEngineResult` requires the returned term/type
pair to be closed and meta-free, then asks Agda to check the type and the term
against it in the current signature. Compile-time-only verifier binaries inject
an open variable, an unresolved meta, and a wrong-typed literal; all three are
rejected before any publication artifact survives.

Requested/effective engine and fallback provenance are carried with the
validated result into staging. This prevents an explicit oracle fallback from
being reported as the mature NbE deliverable.

## Entry selection and compilation scope

The operator may select an entry with `--cubical-chez-entry=NAME`; the default
remains `main`. Unqualified names match only the final QName segment, while a
name containing a dot is treated as fully qualified and must match exactly.
Zero or multiple matches fail closed. The selected definition must have one
closed, argument-free clause.

For the default entry, the existing backend still converts ordinary function
definitions and computes their reachable Treeless closure. A non-default entry
is the narrower formal-acceptance mode: only its normalized body is converted.
That normalized body must therefore be self-contained. Any surviving `TDef`
is reported by the same unresolved-definition gate before Scheme emission.
This avoids converting an entire imported Cubical signature merely to execute
one closed acceptance case, without claiming module-level compilation.

The maintained monolithic acceptance gate does use the complete hash-pinned
`TransportTests` source. It first builds reusable interfaces from the seven
independent stock-Agda shards and the original module, then invokes the formal
backend once per requested entry from that same module. This is an explicit
cache protocol: it proves whole-source functional behavior while keeping the
earlier 12 GB cold-load observation visible as a separate performance concern.

## Static admission rule

The primary audit scans the normalized Internal term while its full type is
still available. It resolves occurrences through Agda's registered Cubical
builtin/primitive identities; generated `transpX-*` definitions are recognized
from checked `Function` Kan-operation metadata. This semantic blocker set is
cross-checked against an explicit union of the Agda 2.8/2.9 QName catalogs. A
same-spelled postulate or stale catalog entry therefore cannot acquire runtime
authority by name alone. A
primitive-shaped executable QName in a Cubical primitive namespace but absent
from that catalog is separately recorded and immediately rejected; adding a
new primitive is an explicit review step, not an accidental widening of the
erased path. Type-only known or unknown references are recorded separately and
do not by themselves reject safe erasure. After conversion, the candidate
Treeless graph is audited again. Unsupported ordinary dependencies are still
rejected by the existing reachable-definition check.

The current structural classifier is stable and machine-readable:

| Class | Evidence | Current action |
| --- | --- | --- |
| `static` | both executable audits have no blocker | request static-closure proof; erase and emit only if complete |
| `dynamic` | both audits find a blocker at the result head, after lambda/coerce/let wrappers | retain the whole typed entry |
| `mixed` | both audits find a blocker nested under static construction/control | retain the whole typed entry; materialize closed or lambda-lifted holes and publish a Chez shell with opaque imports, ID-addressed observations, checked Bool/Nat/Word64/Char/Int ground-unary elimination, and checked Bool/Nat/Word64/Char/Int single-slot, ordered, or dependent environments where the packet type permits it |
| `unsupported` | Internal semantic evidence disagrees with the pinned catalog, Internal/Treeless disagree on blocker existence, or either executable audit sees an uncatalogued Cubical primitive | reject; never emit Scheme or packet |

Ground-value admission now has a versioned producer registry rather than
independent Haskell and Scheme whitelists. `allResidualGroundCodecs` drives
builtin QName resolution, the parameterized unary capability, ordered-domain
classification, manifest fields, and the generated Chez registry. Each shell
self-checks the emitted `bool,nat,word64,char,int` fingerprint before command
dispatch. `ground-codec-descriptor-v1` then attaches seven checked fields to
each member: codec, unary ABI, CLI prefix, validator, argument reifier, entry
parser, and runtime-value reifier. Unary and explicit/entry vector parsing plus
ordered/dependent literal construction use generic descriptor lookup. The
field procedures remain codec-specific, while their selection and coverage are
now uniform. Non-ground values use the separate
`checked-packet-reference-v1` carrier rather than acquiring an erased Chez
representation.

`binding-time-scope: whole-entry` prevents the structural `mixed` label from
being read as completed definition-internal specialization. The plan described
below now carries independently checked closed or lambda-lifted typed holes,
can persist a closed unary application or an explicitly/captured
ordered/dependent environment application as a typed packet, and can compose closed proxies
while retaining their parent graph. One open builtin-Bool, bounded-Nat/Word64,
Unicode-scalar Char, or signed-64 Int slot,
or a non-dependent ordered telescope of two to 64 Bool/Nat/Word64/Char/Int slots, can
bind its actual Chez lexical representations and replay them through an Agda-checked
consumer. A dependent telescope of two to 64 slots is also replayed when every
closed domain is builtin Bool/Nat/Word64/Char/Int and at least one later domain mentions an
earlier binder; Agda checks every instantiated dependent domain. Production
still needs additional ground argument codecs. Long-lived store admission is bounded by
`count-256+bytes-67108864-v1`, and lifecycle mutation is serialized by
`store-lock+atomic-state-v1`.

`static` is a binding-time candidate, not publication authority. The erased
writer accepts only a `StaticClosure` capability constructed after the complete
reachable Treeless graph has zero unresolved QNames and every reachable
definition has successfully lowered to Scheme. Staging exposes the proof as
`static-closure: complete`, `static-closure-scheme-lowering: checked`, and
`type-erasure-authorized: true`. Any incomplete proof changes the final
decision to `unsupported` and cannot carry Scheme to the writer; residual and
unsupported binding-time paths report the proof as not applicable and erasure
as unauthorized.

## Chez core ABI v1

Both the ordinary static program and the mixed residual static shell use the
single `chez-core-abi-v1` contract. The lowering implementation and the
published declaration are separate values; producer-side validation requires
them to be identical before any Scheme capability can be published. A
compile-time-only negative changes the declared function ABI to
`uncurried-closure-v0`; a second changes the v1 `PAdd` map to subtraction.
Both must fail with `CCZ-SCHEME-LOWERING-FAILED` while leaving no `program.ss`.

| Surface value | `chez-core-abi-v1` representation |
| --- | --- |
| QName | `agda_` prefix; every non-alphanumeric source character becomes `_<Unicode code point in hex>_` |
| Function | unary Chez closure; multiple Agda arguments are nested closures and left-associated one-argument calls |
| Data constructor | vector whose symbol tag is at index 0 and whose fields start at index 1 |
| Record constructor | the same tagged-vector layout as data constructors; Treeless supplies one constructor form for both |
| Case/projection | inspect index 0 for dispatch and bind fields from index 1 in constructor order |
| Primitive application | exact-arity explicit whitelist; v1 maps supported arithmetic, comparison, equality, conditional, sequencing, and integer/Word64 conversions directly |
| First-class primitive | only add, subtract, and multiply; each becomes a two-level curried closure |

The exact primitive application map is part of v1, not an implementation
example:

| Treeless primitive | Chez form |
| --- | --- |
| `PAdd`, `PAdd64` | binary `+` |
| `PSub`, `PSub64` | binary `-` |
| `PMul`, `PMul64` | binary `*` |
| `PQuot`, `PQuot64` | binary `quotient` |
| `PRem`, `PRem64` | binary `remainder` |
| `PGeq` | binary `>=` |
| `PLt`, `PLt64` | binary `<` |
| `PEqI`, `PEq64`, `PEqF` | binary `=` |
| `PEqS` | binary `string=?` |
| `PEqC` | binary `char=?` |
| `PIf` | three-argument `if` syntax |
| `PSeq` | two-argument `begin` syntax |
| `PITo64`, `P64ToI` | representation-preserving identity |

Any other primitive/arity pair rejects lowering. As first-class values, only
`PAdd`, `PSub`, and `PMul` are admitted and produce curried `+`, `-`, and `*`
closures respectively.

`staging.txt` and typed-residual manifests expose the version plus each
subcontract and the two vector indices. The `StaticCoreAbi` acceptance fixture
keeps a function and a `Choice(Box Nat)` value abstract so normalization cannot
erase the boundary. Generated Chez pattern-matches both data and record
vectors, applies `PAdd`, invokes a passed closure, reconstructs both vectors,
and returns 42. The lowering helpers for constructor construction, tag/field
access, lambdas, and applications are shared by the static and mixed paths.
This core ABI does not claim that arbitrary typed residual values can be
embedded into untyped Chez; those continue to use checked packet references.

## Mixed residual slicing and typed-hole materialization

For a `mixed` entry, the backend walks the Treeless term in a fixed constructor
order and selects each maximal subtree whose head is a known runtime blocker.
Traversal stops at a selected subtree, so nested nodes do not create overlapping
holes. Each hole receives a stable ID derived from its structural path, such as
`typed-hole@app-argument-1`; a replay test compares every `residual-slice-*`
manifest line byte-for-byte.

The planner checks that the set of blocker QNames covered by all holes exactly
matches the Treeless audit inventory. It then finds a separate authoritative
typed source for every hole without inferring a type from Treeless. It reruns
Agda's `CheckInternal` over the original whole-entry `Term : Type` with an
observation-only action. Meta-free closed candidates remain unchanged. For an
open candidate it records the current checked telescope and builds
`teleLam Γ term : telePi Γ type`; only a resulting closed pair is admitted.
Each candidate is compiled with the same Treeless configuration; leading
environment lambdas are stripped for identity comparison only. A hole must
have exactly one candidate whose compiled body is structurally equal to the
planned subtree and whose Internal blocker set contains the Treeless blocker
inventory.

The matched `Term + Type` is then independently checked for closedness, metas,
Agda typing, direct dependency integrity, and a
`checked-type+definition-body-v1` transitive slice under the same 10,000-QName
limit. Presentation-only definition metadata is audited but excluded. Manifest policy records this materialization
but emits no executable hole file. Agda 2.9 packet policy serializes each checked
closure as `typed-residual-hole-N.bin`, self-decodes/rechecks it before
publication, and marks independent artifacts `true`. The archived v2 consumer
executes the `MixedResidual` hole in a separate process and observes `true`.

After typed-hole validation, a path-aware compiler lowers the remaining
Treeless shell. All planned handles are registered before evaluating the entry;
at every exact path the shell emits a stable-ID reference. This makes holes
nested under a lambda addressable without depending on Scheme evaluation
order. All ordinary nodes reuse the Chez lowering, while any uncovered blocker-headed subtree fails with
`CCZ-SCHEME-LOWERING-FAILED`. The resulting
`residual-static-shell.ss` represents each import as an opaque vector. Chez
executes the shell and observes the static Bool field and the unique import
descriptor without containing `primTransp`.

The handle stays opaque during ordinary shell construction. The shell registers
every stable ID and rejects duplicates. On an explicit
`--force-hole=<stable-id>`, Chez selects exactly that handle, sets the packet
identity, and calls the generated
`typed-hole-ground-bridge.sh`. That helper invokes the checked v2 consumer with
operator-supplied runner/module/consumer settings, accepts exactly one Bool or
Nat line, and emits a versioned S-expression. Chez validates the response and
helper exit status before decoding it into the existing Bool constructor/Nat
representation. Missing configuration, nonzero runner exit, stderr, multiple
lines, and unknown values all fail closed. The original whole-entry packet
remains the semantic reference. Batch mode requires a complete one-to-one
consumer mapping and emits `(stable ID, ground observation)` pairs in planner
order. The observations are not values of the original hole types and therefore
cannot be substituted into the shell.

The handle additionally carries a capability derived from the authoritative
Internal type. A visible first Pi domain definitionally equal to builtin Bool,
Nat, or Word64 receives `bool-unary-ground-elimination-v1`,
`nat-unary-ground-elimination-v1`, or
`word64-unary-ground-elimination-v1`, respectively. Its call path accepts a
matching Bool, bounded unsigned decimal Nat, or unsigned 64-bit Word64, a safe QName naming the packet's
source-level type alias, and a safe QName for the result consumer. Chez
constructs an annotated Agda lambda, but Agda remains the authority: the
archived v2 runner compares the annotation with the packet domain and
typechecks both the application and result consumer. The typed intermediate
never enters Scheme; only the final Bool/Nat observation does.

Alternatively, `persistent-typed-packet-v1` sends a checked application result
to the runtime packet writer. The source can be the explicit closed Bool/Nat/Word64/Char/Int
unary call path, an explicit ordered/dependent ground vector, or an
automatically captured single-slot, ordered multi-slot, or dependent ground
environment. Its stable bounded proxy ID maps to a
`typed-proxy-ID.bin` packet and a `typed-proxy-ID.meta` lifecycle record; the
packet repeats v2 module/hash/`Term : Type` identity. Publication is
no-clobber, and consumption can be repeated by later Chez processes with a
newly checked consumer. `parent-retained-recursive-gc-v1` also permits Agda to
apply a checked named consumer to a source proxy and publish the typed result as
a child proxy. A released parent becomes inaccessible but remains physically
retained while descendants exist. Releasing the final leaf recursively removes
released ancestors; fixed-point GC also cleans incomplete pairs and children
whose parent disappeared. The proxy descriptor is therefore an address into a
typed packet graph, not an erased representation of the value.

`named-checked-function-v1` makes that graph operation explicit as
`--map-proxy`. A mapper can publish another typed child regardless of whether
its result is a function, record, data value, or Cubical residual. For an
immediate ground observation, the bridge applies the mapper into a private
temporary v2 packet and then applies the named result consumer in a second
Agda check. Its exit cleanup removes the temporary packet on both success and
failure. Thus each domain boundary is checked against a serialized
`Term : Type`, and no non-ground intermediate is decoded by Chez.

Persistent publication is serialized by `atomic-mkdir-v1`. The bridge holds a
store-local atomic directory lock while it rechecks target absence and parent
activity, measures complete packet/metadata pairs, invokes the checked runner,
and creates both no-clobber public links. Count quota is checked before runner
work; aggregate packet-plus-metadata bytes are checked on private temporary
files before publication. Defaults are 256 pairs and 64 MiB, with bounded
environment overrides. Quota failure removes all temporary files, and released
capacity is reusable. The same store-local lock now surrounds consume,
immediate map, drop, and fixed-point GC. Active/released rewrites go through a
private `.meta.state` file and atomic rename; GC removes interrupted state
temporaries. Dead-PID recovery, publish/GC serialization, locked consumption,
and concurrent double-drop are pinned by the Agda 2.9 gate.

An open planned subtree is lambda-lifted only from the telescope supplied by
Agda's Internal checker; no environment is guessed from Treeless. The current
`lambda-lifted-explicit-environment-v1` gate executes one Bool/Nat/Word64/Char/Int environment
through the existing checked unary call ABI. Publication accepts `1..64`
telescope entries and fails closed outside that bound.
`single-bool-chez-lexical-binding-v1`,
`single-nat-chez-lexical-binding-v1`, and
`single-word64-chez-lexical-binding-v1`, and
`single-char-chez-lexical-binding-v1`, and
`single-int-chez-lexical-binding-v1` additionally replace that exact hole
occurrence with a bound opaque handle carrying the validated Chez ground value.
For a non-dependent telescope of two to 64 builtin Bool/Nat/Word64/Char/Int domains,
`ordered-*-chez-lexical-binding-v1` derives the codec vector from the leading
checked Pi domains. Lowering reverses Treeless's nearest-binder-first stack
back into Agda telescope order, and the shell requires the same ordered CLI
vector before constructing the checked multi-application consumer.
For Word64, replay uses `Agda.Builtin.Word.primWord64FromNat` and accepts only
decimal values through `18446744073709551615`; the checked codec vector must
match before invocation.
For Char, replay uses `Agda.Builtin.Char.primNatToChar`; the codec accepts only
decimal Unicode scalar values through `1114111` and rejects surrogates.
For Int, the codec accepts canonical signed-64 decimal values and replay emits
`Agda.Builtin.Int.pos n` or `Agda.Builtin.Int.negsuc n`.
For a telescope of two to 64 slots where every closed domain is builtin
Bool/Nat/Word64/Char/Int and at least one later domain contains an earlier binder,
`dependent-ground-chez-lexical-binding-v1` captures all actual representations
without claiming static codecs for dependent domains. Chez preserves raw
values, uses the explicit CLI codec to distinguish ambiguous Nat/Word64 integer
representations, and reifies Bool/Nat/Word64/Char/Int literals; the archived runner
checks their complete dependent application, so a value from any wrong branch
fails at Agda's equality gate. Entry observation applies the captured literal
inside the typed runner; it never treats the residual value itself as erased
Scheme. Additional environment/result codecs and crash-safe concurrent metadata
updates are the next required generalizations. `--call-ground-hole=ID` with
two to 64 repeated `--ground-argument=bool:...|nat:...|word64:...|char:...|int:...` values
applies the same lambda-lifted packet without evaluating its enclosing Chez
entry. Ordered vectors must exactly match the manifest codec sequence; dependent vectors are
validated by Agda's complete application gate. Exactly one
`--call-result-consumer=QNAME` or `--call-proxy-id=ID` selects immediate
elimination or persistent materialization. With
`--auto-bind-proxy-id=ID`, the complete captured application is instead
wrapped as a checked Agda consumer and serialized directly to a v2 typed proxy;
the mutually exclusive `--auto-bind-result-consumer=QNAME` path still performs
an immediate ground observation.

## Typed packet boundary

The Agda 2.9 build serializes the retained `(Term, Type)` in the exact v2
envelope: magic, format version 2, full interface hash, top-level module name,
then the typed payload.  Before publishing bytes, the producer requires a
closed/meta-free payload, decodes its own bytes, validates the header, and
rechecks both the type and term with Agda.

The current residual contract is `whole-entry-same-interface-v1`. It derives
the direct QName dependency set from the retained term and type and rejects a
producer whose recorded inventory differs. It then resolves a fixed-point
slice through each ordinary definition's checked `defType` and `theDef`, while
retaining Agda builtins/primitives as resolved signature leaves. Names found
only in `DISPLAY`/presentation metadata are reported separately and excluded
from the executable slice. A missing QName, slice-integrity mismatch, or closure
above 10,000 nodes rejects before publication. The packet embeds neither
definitions nor the whole signature. Instead, the module name and full
interface hash require the consumer to load the exact signature in which those
QNames were checked. The manifest records payload, scope, direct/resolved/
expanded/leaf dependencies, signature identity, and closure completeness. This
is minimal for the existing whole-entry/v2 execution model. For a successfully
materialized mixed hole, packet policy additionally applies the same envelope
and validation to an independent hole payload, then publishes a Chez shell and
   ground bridge which import that filename as opaque data and can observe a closed
   hole as Bool/Nat through the v2 runtime. These split artifacts supplement rather
than replace the whole-entry packet until open environments and general typed
results have equivalence gates.

The destination is an explicit publication boundary. With packet policy active,
the default is `OUTPUT/typed-residual.bin`; `--cubical-chez-packet-file=FILE`
selects another path and `--cubical-chez-packet-file=-` publishes binary bytes
to stdout for a direct process pipe. Selecting a packet destination under any
other residual policy fails before compilation. The staging record identifies
`default`, `stdout`, or the exact path, allowing the harness to prove that the
Higher protocol cases use the intended channel and that direct pipes leave no
packet file.

The verification harness builds isolated test-only producer variants that
replace the packet candidate with a free variable or unresolved `MetaV`, or
mutate the declared dependency inventory. They prove the closedness,
`noMetas`, and dependency-consistency checks fail before serialization without
making malformed payload construction available through the production CLI.

`verify-agda29` then passes the file to the archived v2 runner in an independent
process.  That consumer repeats the checks against its own loaded signature
and checks the consumer domain before application.  The maintained
`compat/agda-2.9/runtime-safe-packet-decode.patch` also caps inputs at 64 MiB,
converts raw deserialization `ErrorCall`s into a controlled runtime diagnostic,
and adds the checked import-result packet output used by persistent proxies.
The gate applies this patch temporarily and restores the pinned source on exit.
Agda 2.8 builds fail explicitly on
`--cubical-chez-residual=packet`; they cannot emit a superficially compatible
artifact using the older serialization API.

## Next vertical slice

1. Move the already content-pinned in-process adapter into an approved Git
   repository/revision, add an approved license and decision evidence, then
   change `config/nbe-adapter-source.identity.tsv` from `blocked` to `eligible`
   and replace the corresponding `UNRESOLVED` fields in
   `config/nbe-adapter.lock.tsv`. `check-nbe-production-promotion` requires both
   records to match before promotion.
2. Preserve the completed 8-group/42-row candidate differential and controlled
   O2 release performance PASS, then obtain owner approval for the final
   acceleration/RSS/allocation/timeout thresholds. Collection uses a sibling
   staging directory and archives the prior complete result only at terminal
   publication; O0 and O2 results remain isolated.
3. Continue the codec generalization after single/unary/ordered/dependent
   Word64/Char/Int: add further checked environment/result codecs over the
   length-generic explicit and lexical dependent ground bindings. Keep
   `closed-hole-ground-observation-by-id-v1` as an observation-only contract;
   retain the whole-entry packet as reference until equivalence gates pass.
4. Allocation measurement and the optimized O2 release profile are now
   completed evidence contracts. Add direct upstream parser/typechecker
   instrumentation only if their split is required. The fixed timing contract
   already covers engine/NbE/readback/
   admission/audit/Treeless/residualization/Scheme publication/Chez/
   typed-consumer plus a derived Agda frontend remainder.
