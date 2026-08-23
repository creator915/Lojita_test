# Compatibility status

## Local development build

- macOS 26.3.1, arm64, Apple M4, 24 GiB RAM
- Agda 2.8.0 and GHC 9.12.3 from Homebrew
- Chez Scheme 10.4.1

Commands:

```sh
make -B build
make verify
```

The `-Wall -Werror` build and smoke suite pass ordinary static compilation,
closed Cubical transport, typed-residual rejection, the Agda 2.8 packet version
gate, the type-only Cubical erasure control, explicit-entry validation, the
packet-destination policy gate, and the unconfigured-NbE negative control.

The pinned Agda 2.9 official targeted gate passes `CubicalSucceed` 1/1, the
Interface/Serialise API subset 3/3, Internal compiler properties 3/3, and stock
MAlonzo Cubical compilation negatives 4/4. It also passes Internal TypeChecking
properties 11/11 plus conversion success and golden failure regressions 5/5
each, for 32/32 selected tests overall. It runs in a temporary source copy, so
official `.agdai`, `.api`, `.hi`, and `.o` files do not pollute the supplied
snapshot. `PrintImports.run` is skipped because the supplied `std-lib` submodule
is empty; see `TEST-RESULTS.md`.

The separate complete Compiler gate uses a source-hashed, isolated `-fdebug`
build and the upstream non-stdlib command. It passes all 687 executed tests
across three MAlonzo and three JavaScript configurations. The remaining 43 of
the static 730-test inventory are exactly 41 upstream-disabled cases plus the
two canonical `AllStdLib` exclusions; see the recorded matrix and
classification in `TEST-RESULTS.md`.

The source identity gate independently compared the supplied parent tree with
the official `d8a73ff...` commit archive. Its 10,084-file stock projection
matches exactly; the local `Agda.cabal`, Cubical runtime module/runner, and five
runtime-test files are tracked separately as a nine-file v2 overlay. Run
`make verify-agda29-stock-baseline` before official groups.

## Pinned Agda 2.9 delivery tree

The supplied archive contains Agda 2.9.0 with a stock parent matching commit
`d8a73ff720197796fb64c7652202d33e7abb3eb6`. It was built from a separate
temporary extraction with GHC 9.6.7 and Cabal 3.14.2.0. All 488 Agda library
modules compiled, and the archived `agda-cubical-run` executable was built.

The backend then passed a real `-Wall -Werror` build with
`CUBICAL_CHEZ_AGDA_29`.  The reusable gate is:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
GHC29=/path/to/ghc-9.6.7 \
make verify-agda29
```

Result:

```text
Agda29Packet PASS (v2 consumer: true)
Agda29MixedPacket PASS (static shell observation: true)
Agda29MixedHolePacket PASS (independent typed hole: true)
Agda29MixedShell PASS (opaque hole import observation)
Agda29MixedBridge PASS (Bool/Nat forcing + 3 expected rejects)
Agda29OpenClosureBridge PASS (lambda-lifted Bool environment + 2 expected rejects)
Agda29LexicalBoolCapture PASS (true/false Chez capture + 4 expected rejects)
Agda29LexicalNatCapture PASS (whole/direct/explicit + zero/suc Chez capture + 5 expected rejects)
Agda29LexicalWord64Capture PASS (whole/direct/explicit + zero/max Chez capture + 6 expected rejects)
Agda29OrderedGroundCapture PASS (whole/direct + 3 ordered Chez captures + 6 expected rejects)
Agda29Word64GroundCapture PASS (whole/direct + lexical 0/1 + explicit + 4 expected rejects)
Agda29DependentGroundCapture PASS (whole/direct + 4 dependent captures + 5 expected rejects)
Agda29DependentWord64Capture PASS (whole/direct + 4 captures + 2 explicit + 6 expected rejects)
Agda29DependentGroundChainCapture PASS (whole/direct + 8 dependent captures + 8 expected rejects)
Agda29DependentGroundProxy PASS (create + consume twice + derive + retain/recursive-GC + 6 expected rejects; root 3462 bytes, child 4452 bytes)
Agda29ExplicitGroundCall PASS (ordered + dependent + proxy/consume/drop + 5 expected rejects; proxy 3462 bytes)
Agda29MultiHolePacket PASS (two typed packets + whole-entry reference)
Agda29MultiHoleBridge PASS (two IDs + batch + typed Bool call + 13 expected rejects)
Agda29NatCallableBridge PASS (typed Nat call: 42 + 4 expected rejects)
Agda29Word64CallableBridge PASS (whole/direct + zero/max + proxy/consume/drop + 5 expected rejects)
Agda29TypedProxy PASS (create + consume twice + derive + retain/recursive-GC + 6 expected rejects; root 3234 bytes, child 4212 bytes)
Agda29TypedCarrier PASS (whole/direct + residual/record/data map + ground observation + 5 expected rejects; packets 3422/3567/4343 bytes)
Agda29ProxyStoreQuota PASS (byte rejection + concurrent count 1/2 + released-capacity reuse; proxy 3422 bytes; 2 expected rejects)
Agda29ProxyStateTransaction PASS (stale-lock recovery + publish/GC + atomic-state recovery + locked consume + concurrent drop 1/2; 1 expected reject)
Agda29DependencySlice PASS (checked type/body closure 9 resolved/2 expanded + 1 presentation-only exclusion + 1 expected reject)
Agda29PacketModuleMismatch EXPECTED-REJECT (module identity)
Agda29PacketHashMismatch EXPECTED-REJECT (interface identity)
Agda29PacketWrongConsumer EXPECTED-REJECT (UnequalTypes)
Agda29PacketTruncated EXPECTED-REJECT (controlled diagnostic)
Agda29PacketOversized EXPECTED-REJECT (64 MiB limit)
Agda29PacketBadMagic EXPECTED-REJECT (producer self-check)
Agda29PacketBadVersion EXPECTED-REJECT (producer self-check)
Agda29PacketOpenTerm EXPECTED-REJECT (closedness gate)
Agda29PacketUnresolvedMeta EXPECTED-REJECT (meta gate)
Agda29PacketDependencyMismatch EXPECTED-REJECT (dependency inventory gate)
Agda29PacketPresentationDependencyLeak EXPECTED-REJECT (executable slice gate)
```

The test retains an unreduced, closed higher-order `primTransp`, writes a
3,194-byte v2 packet, self-decodes and rechecks it, and then has the archived
v2 runner independently consume it. It additionally materializes the closed
mixed hole through Agda's Internal rechecker, writes a separately validated
3,270-byte v2 hole packet, and executes it through a second independent
consumer. It also runs the generated Chez shell and checks that its static Bool
field and unique opaque import descriptor are preserved without a Cubical
primitive. The shell then forces the hole through the checked v2 runner as both
Bool and Nat; missing configuration, a nonzero runner, and dirty output are
three additional expected bridge rejections. It also rejects a different top-level
module, the same module name with a changed full interface hash, a consumer
with the wrong domain, a 64-byte truncation, a sparse 64 MiB + 1 byte input,
test-only producers with an invalid magic or version, an open payload, and an
unresolved meta.  Producer negatives are rejected before publishing either a
packet or executable Scheme.  The evidence is under
`build/agda29/evidence/`.

The two-hole fixture publishes different checked domains under two stable
structural IDs. Both IDs force with matching consumers; unknown/conflicting
selection rejects before invocation, and a cross-consumer attempt is rejected
by the selected packet's v2 type check. Batch mode requires exactly one consumer
mapping per stable ID and emits a deterministic
`cubical-chez-ground-observations-v1` bundle; missing, duplicate, unknown, and
selector-conflicting mappings reject before runner invocation. This establishes
addressable multi-hole publication and joint ground observation. The checked
`Bool → Residual` hole now also receives a capability-gated call path: Agda
applies a Bool, keeps the intermediate `Residual` typed, and passes it directly
to a named result consumer. Capability, argument, configuration, QName, and
mode-conflict negatives reject locally; a wrong named packet domain is rejected
by the v2 type gate. The intermediate is not serialized into Chez.

The open-hole fixture is open in one checked Bool at its source occurrence.
The same backend compiles on Agda 2.8 and 2.9 while abstracting the current
Internal telescope into a closed `Bool → Residual` packet. Agda 2.9 validates
the packet with an independent consumer, ID-addressed force, and an explicit
Bool-environment call; omitted and wrong-codec environments reject. The mixed
shell also binds the actual Bool constructor at the hole occurrence. Automatic
observation with entry arguments `true` and `false` returns the corresponding
typed Bool, while malformed input and an absent selected binding reject as
`CCZ-TYPED-BRIDGE-ENVIRONMENT`.

`MixedOpenNatResidual` similarly closes an open checked Nat telescope into a
`Nat → Residual` packet. Whole-entry, independent-hole, and explicit Nat
application succeed; automatic entry values `0` and `1` preserve the actual
Chez integer and return different typed Bool results. Negative/overflow input,
missing binding, incomplete configuration, and mode conflict reject locally.

`MixedOpenWord64Residual` closes the corresponding checked Word64 telescope
into a `Word64 → Residual` packet and publishes
`single-word64-chez-lexical-binding-v1`. Whole-entry, independent-hole, and
explicit maximum-value application succeed; automatic entry values `0` and
`18446744073709551615` return different typed Bool results. Negative/overflow
input, Nat-codec substitution, missing binding, incomplete configuration, and
mode conflict reject locally.

`MixedOpenGroundResidual` closes a checked non-dependent `Bool, Nat`
telescope into `Bool → Nat → Residual`. Its manifest and handle retain that
order even though the lowering environment stores the nearest binder first.
Automatic `true/0`, `true/1`, and `false/0` executions return typed
`true/false/false`. Swapped order, missing/extra slots, a mismatched codec,
duplicate selector, and Nat overflow all reject under
`CCZ-TYPED-BRIDGE-ENVIRONMENT`.

`MixedOpenWord64GroundResidual` adds a checked non-dependent
`Bool, Word64` telescope. The manifest publishes
`ordered-bool+word64-ground-environment-elimination-v1`; lexical
`word64:0`/`word64:1` and explicit `bool:true,word64:0` applications pass.
Replay constructs `Agda.Builtin.Word.primWord64FromNat`, and both entry and
explicit paths reject the Nat codec or values above
`18446744073709551615` before the checked consumer runs.

The companion dependent `Bool, Slot flag` telescope uses
`dependent-ground-chez-lexical-binding-v1`. Whole/direct consumption and four
branch-correct automatic applications pass. Bool on the `true`/Nat branch,
Nat on the `false`/Bool branch, and swapped arguments reach Agda and fail the
dependent type check; missing/extra slots reject locally.

`MixedOpenDependentWord64Residual` changes the dependent branch to
`Slot true = Word64` and `Slot false = Nat`. Whole/direct, automatic Word64
zero/maximum, automatic Nat zero/one, and explicit Word64 zero/maximum all
pass. The shell preserves raw values and uses the explicit codec when building
the checked literal, so erased integer zero is not guessed to be Nat. Wrong
branch codecs reach Agda and reject; negative/overflow Word64 rejects locally.

`MixedOpenDependentChainResidual` proves that the same ABI is length-generic:
its third domain depends on both the Bool and the selected second slot. Whole
and independent-hole consumers plus all eight branch-correct Bool/Nat triples
pass. Wrong second/third branch representations and a swapped first slot reach
Agda's dependent type gate; missing/extra triples reject locally.

That three-slot dependent application can also select
`--auto-bind-proxy-id=dependent-chain` instead of an immediate result consumer.
Agda serializes the checked result as a 3,462-byte root proxy, two later
processes consume it, and a checked `wrapResidual` derives a 4,452-byte child.
Releasing the root retains it for the child; releasing the child recursively
collects both. Duplicate/invalid IDs, action conflict, a wrong dependent branch,
and wrong root/derive domains provide six expected rejections.

The same ordered and dependent packets can now be applied explicitly without
running the enclosing erased entry. Repeated `--ground-argument` values are
checked against the ordered capability or submitted as one dependent
application to Agda. Ordered and dependent immediate consumption pass; the
dependent result also materializes as a 3,462-byte proxy, is consumed from a
later process, and drops cleanly. Ordered codec mismatch, a short vector,
action conflict, unsafe proxy ID, and a wrong dependent branch provide five
additional expected rejections.

The independent Nat-callable fixture grants
`nat-unary-ground-elimination-v1` only for a checked builtin-Nat Pi domain.
Applying `7` and passing the typed intermediate to a `Residual → Nat` consumer
returns `42`. Negative input, the bounded-codec overflow value `4294967296`, a
Bool/Nat codec mismatch, and a wrong named packet domain are all rejected. The
same application can now be retained as a
`persistent-typed-packet-v1` proxy. Its 3,234-byte packet is consumed twice
from later Chez processes. A checked unary consumer derives a 4,212-byte child
packet under `parent-retained-recursive-gc-v1`; releasing the root retains it
for the child while disabling root access, and releasing the child recursively
collects both pairs. Duplicate IDs preserve the original bytes, invalid IDs and
released access reject locally, and wrong consume/derive domains are rejected
by the v2 type gate.

`MixedResidualWord64Callable` grants
`word64-unary-ground-elimination-v1` to a checked `Word64 → Residual` hole.
Calls at zero and `18446744073709551615` preserve the argument and return
different typed results. The maximum-value application also materializes a
3,446-byte persistent packet, which a later process consumes before clean
drop. Overflow, Nat codec substitution, wrong named packet domain, overflow
while requesting a proxy, and duplicate proxy publication all reject. Word64
now supports single-slot automatic capture, unary calls, non-dependent ordered
multi-slot calls, and dependent vectors.

Builtin Char now follows the same single/unary/ordered/dependent path, but its
CLI representation is a decimal Unicode scalar code point rather than raw
text. Values `0..1114111` pass except surrogates `55296..57343`; checked replay
constructs `Agda.Builtin.Char.primNatToChar N`. The three Char fixtures cover
single-slot, `Bool → Char` ordered, and `Bool → Slot flag` dependent
capture, including codec mismatch, surrogate, and overflow rejection. At that
checkpoint the pinned gate recorded 106 positive executions and 112 expected
packet/bridge rejections.

Builtin Int now uses a canonical signed-decimal codec bounded to
`-9223372036854775808..9223372036854775807`. Chez validates the actual
`Agda.Builtin.Int.pos`/`negsuc` constructor vector, while checked replay emits
the corresponding constructor application. Single/unary, ordered `Bool → Int`,
and dependent Int/Nat fixtures add 18 positive executions and 14 expected
rejections. Subsequent generic checked-value mapping, quota, publication-lock,
and lifecycle-transaction controls, followed by the exact definition
dependency slice and `chez-core-abi-v1` cross-version acceptance case, bring
the pre-spike pinned gate to 140 positive executions and 139 expected
packet/bridge/producer rejections. The added producer negative changes only
the declared function ABI; another changes `PAdd` to subtraction without a
version bump. Both confirm that the Scheme lowering gate rejects before
publication.

The test-only in-process NbE adapter now adds fourteen Agda 2.9 differential cases
(`true`, `false`, recursive Nat 42, a polymorphic Pi procedure, custom
recursive data 9, record projection 42, a dependent-record procedure, and a
two-level universe-polymorphic alias procedure, plus exact-`PrimitiveId` Nat
arithmetic 42, a ground interval/`transp`/Nat-`hcomp` result 42, an open neutral
cofibration procedure, exact Nat-family transport at `i0`, and exact
`Nat -> Nat` transport/application producing 4, and exact
`unglue (glue t 42)` cancellation) with
byte-equal Treeless/Scheme output versus the oracle. The request type uses the
adapter's own Type/Sort/Level/Pi evaluator, and record fields reduce or remain
neutral according to the receiver. Ground-cycle, low-fuel, fault-injected
invalid projection receiver, postulated `DefS`, unregistered primitive,
same-name impostor, and unsupported `PrimComp` controls add seven distinct
fail-closed outcomes. Primitive
diagnostics retain the exact node kind, QName, and binding-site range. The
established pinned matrix remains 154 positive executions and 146 expected
rejections. In addition, the isolated selected+linked production candidate
executes recursive Nat 42 as effective `nbe`, with byte-equal observed,
Treeless, and Scheme artifacts versus the oracle and complete provenance. Thus
the current full invocation performs 155 positive executions plus 146 expected
rejections. The default binary remains unavailable, and candidate staging is
explicitly `candidate-not-accepted`.

A separate pinned-Cubical exact gate now covers canonical
`TransportGlue.t03/t04/t08`. It checks byte identity with all three original
source blocks, then requires adapter/baseline equality for observed output,
Treeless, and Scheme; the entries produce `false/true/false`. A local
`notPath i → notPath i` extension is also baseline-equal and returns `true`
after domain-inverse/source-call/codomain-forward evaluation. A second local
`(b : notPath i) → ConstantType b` extension is baseline-equal and returns
`false`: opaque-binder evaluation proves that its syntactic dependency erases
to the same closed `Bool` definition at all three observations. The exact
dependent self-path `(b : notPath i) → b ≡ b` is also baseline-equal after an
`i0` observation and returns `true`; admission checks the builtin `PathP`
shape, source reflexivity at three interval views, and a syntactically
interval-independent inner family with endpoint readback agreement.
A canonical dependent singleton
`(b : notPath i) → Σ[ x ∈ notPath i ] b ≡ x` is baseline-equal and returns
`true` through `fst`; its symmetric `x ≡ b` orientation is now independently
classified and returns the same result. Both require exact builtin Sigma/PathP
structure, matching domain types, an explicit binder/field endpoint order, and
a source `(b , refl)` validated at three interval views before rebuilding the
target pair; their telemetry is separate.
A one-layer nested canonical Sigma
`Σ x ∈ A. Σ y ∈ A. b ≡ x` is also baseline-equal at `true`; admission
requires both Sigma identities, the outer source point equal to `b`, checked
transport for the auxiliary point, and the final three-view reflexivity check
before rebuilding both target points and proof;
both final path orientations are supported with separate telemetry. The same
exact-depth recursion admits both `Σ x. Σ y. Σ z. b ≡ x` and its `x ≡ b`
orientation and rebuilds all target points; the two directions have dedicated
telemetry. Auxiliary points distinct from the binder are transported by the
canonical forward and must pass a checked inverse ground round-trip. The local
two-field example transforms `true/true` to `false/false` and counts both maps.
An explicit `SameType (notPath i) x` field alias is baseline-equal at `true`:
probe-shell base/face and both endpoint readbacks match the Pi domain, its
independent point maps once, and staging records 31 path applications plus
nested/fieldwise counters `1/1`. The stable `ConstantType x = Bool` dependent
field now receives an explicit stable-identity plan: its source `true` remains
`true` and staging records one preserved field with zero canonical field maps.
A closed parameterized `List Bool` type application and its constructor spine
receive the same plan and remain baseline-equal at `true`. In contrast,
`Tagged x` retains the prior Sigma-field neutral as an index and is rejected;
equal readback caused by reusing that neutral at all three observations does
not establish stability.
Custom parameterized data and record fields are also baseline-equal at `true`
when `conPars`/`conArity` metadata exposes recursively closed constructor
payloads; their three-layer case records two stable preservations and no
canonical field maps. A record whose payload is an ordinary identity closure
is now baseline-equal at `true`: complete semantic readback proves an
Agda-closed lambda, the observer applies it, and staging records one validated
closed function plus one stable preservation. A record containing an internal
canonical-transport function remains an expected rejection with zero publication.
A direct `Bool -> Bool` stable field is also baseline-equal at `true`: its
probe/i0/i1 Pi views are all closed, the identity closure is applied, and
staging records Pi-type/function/stable counts `3/1/1`. The control
`Tagged x -> Bool` reuses the same field neutral in classifier observations but
cannot pass stable Agda closed readback. It now passes only through the
outer-parameter indexed-Pi plan: the `Tagged` type/value parameter slots are
checked jointly and the target nullary constructor is remapped to source
parameters before the pattern-matching source function runs. Staging records
indexed-field/application counts `1/1`. `PayloadTagged x -> Bool` now also
passes through that plan: its builtin `true` field is preserved, the source
constructor clause reads it back, and staging records ground-payload count `1`.
Only fields whose declared constructor type is independent of all prior
binders and whose value is exact `Nat`, literal, or builtin `Bool` are admitted.
A nested custom payload and a Bool value whose declared field type is the outer
`A` are separate zero-publication controls.
A reversed `notPath (~ i)` auxiliary shell is a negative compatibility control
because it is neither stable nor the outer canonical path. It, a double
composition whose left boundary is another non-trivial `ua` path, and the
nested-payload indexed Pi, dependent-payload-type indexed Pi,
internal-transport-function, and over-limit four-level nested controls are expected
`CCZ-NBE-UNSUPPORTED` cases
with zero publication artifacts. These cases are
outside the 154/146 `verify-agda29` count and do not enable the production
provider lock or claim general HCompU, equivalence-proof normalization, or
dependent Pi transport.

The corresponding exact Int gate covers `TransportInt.t05/t06`, again with
byte-identical original/projection blocks and adapter/baseline equality for all
three artifacts. It produces `pos 1/negsuc 0`; staging distinguishes forward
and backward canonical Glue transport as `0/1` backward reductions. A nested
non-canonical endpoint control is `CCZ-NBE-UNSUPPORTED` with zero publication.
These cases are also outside the 154/146 aggregate and do not select a
production provider.

The exact Core gate covers `TransportCoreB.t09/t10` with byte-identical source
blocks and adapter/baseline equality for observed, Treeless, and Scheme. It
returns the Sigma pair `(false, 3)` and the complete three-cell Bool List while
recording structured record/data transport as `1/0` and `0/1`. Controls where
the Sigma second field also varies or the List parameter has nested endpoint
geometry are `CCZ-NBE-UNSUPPORTED` with zero publication. These cases remain
outside the aggregate 154/146 count and do not imply general recComp.

The exact Hit gate covers byte-identical original/projection blocks for
`TransportHit.t12`-`t15`. `t12/t13` traverse a guarded recursive probe-HComp
slice and return `pos 2/pos 1`; `t13` records exactly one checked backward Glue
step. `t14` unfolds Prelude `J` at `refl` into an exact
constant-Nat transport and returns 41; staging records definitions=2,
primitive/transport/constant-Nat=1/1/1, and four path applications. `t15`
invokes the existing canonical Glue rule twice and returns `true`, with
transport/Glue counters `2/2` and eight path applications. Both entries are
baseline-equal across observed, Treeless, and Scheme. Non-canonical
winding/inverse/J and canonical-inner/non-canonical-outer controls are
`CCZ-NBE-UNSUPPORTED` with zero publication. These cases are outside the
154/146 aggregate and add no general S¹/HIT/J or Glue Kan operation.

The residual closure now publishes `checked-type+definition-body-v1`.
`ResidualDependencyClosure` keeps its 9 resolved/2 expanded executable graph
while reporting the one QName referenced only by a `DISPLAY` form in an
excluded-presentation inventory. A fault-injected return to broad
`NamesIn Definition` traversal is rejected before publication.

The erased Chez boundary is now independently versioned as
`chez-core-abi-v1`. Agda 2.8 and the pinned 2.9 tree both lower
`StaticCoreAbi` to unary-curried functions and uniform tagged vectors for its
data and record constructors, retain the exact primitive map in staging, and
return the nested value containing 42. The 2.9 fault build advertises an
uncurried function contract against the unchanged implementation; a second
fault build changes the v1 `PAdd` mapping. Both are rejected with
`CCZ-SCHEME-LOWERING-FAILED` before `program.ss` publication.

The proxy-store manifest now includes `store-lock+atomic-state-v1` in addition
to its count/byte quota and atomic publication contracts. The same owner lock
serializes publish/derive/consume/map/drop/GC; state rewrites use a private
`.meta.state` file followed by atomic rename. Controls recover a dead-PID lock
and an interrupted state temporary, preserve a live pair across publish/GC,
and prove that only one of two concurrent drops succeeds.

The five ground types now share `ground-codec-registry-v1`. Haskell builtin
classification, unary capability naming, manifest evidence, and the emitted
Chez admission list enumerate the same ordered registry. A tampered shell with
a duplicated/replaced registry entry is rejected at startup with
`CCZ-TYPED-BRIDGE-PROTOCOL`; no runner invocation or typed application occurs.

`ground-codec-descriptor-v1` now carries the executable validator, CLI argument
reifier, entry parser, and Chez-value reifier for each registry member. The
formerly separate unary/vector/entry dispatch conditionals use descriptor
lookup. Replacing the Int descriptor prefix with `char:` fails the descriptor
self-check at startup with the same protocol code.

The current producer also builds with `-Wall -Werror` against both Agda 2.8
and this pinned Agda 2.9 tree after the Internal blocker gate was changed from
rendered-name authority to Agda builtin/primitive registry identity plus
checked Kan-operation metadata. `primTransp` records
`primitive:transport`; the fixed QName catalog remains a separate compatibility
cross-check.

The archive's original raw deserializer leaked an `ErrorCall` and call stack
for truncated data.  The gate temporarily applies
`compat/agda-2.9/runtime-safe-packet-decode.patch`, which enforces the 64 MiB
limit, turns the raw decode failure into a controlled `Cubical runtime`
diagnostic, and adds checked import-result packet export for persistent
proxies. A trap restores the pinned source file on every exit; the script also
accepts a source tree where the maintained overlay is already integrated.

The typed engine contract and `Agda.Syntax.Internal.Names.namesIn` audit compile
unchanged on both tested Agda versions.  Two API differences remain isolated
behind CPP compatibility points:

- Agda 2.9 record eta expansion returns `Maybe`;
- Agda 2.9 Treeless `CCConfig` adds a compiler pipeline and uses
  `mkDefaultCCConfig`.

## Environment failures and remaining gates

The first dependency fetch paused on `STMonadTrans`; a later retry succeeded.
An attempted build with Homebrew GHC 9.14.1 failed before Agda compilation due
to local SDK/libffi mismatches (`posix_spawn_file_actions_addchdir` and missing
`ffi.h`).  Selecting the archive-supported GHC 9.6.7 resolved that toolchain
problem.

A cold, no-interface run that loaded the full pinned cubical checkout was
terminated by signal 9 after several minutes and did not produce a packet. The
replacement low-memory gate now typechecks seven independent diagnostic shards
and then the exact original `TransportTests` source, using an isolated shared
interface cache. All eight checks pass; see `BASELINE.md` and run
`make verify-transport-shards` with the pinned paths.

This closes the stock-Agda typechecking gate. It does not close the v2 runtime
normalisation/residual/cross-process matrix by itself. That separate matrix now
also passes through `make verify-v2-runtime`: the archived
self-contained suite passes in 1.17 seconds, and the unchanged archived full
TransportTests script passes in 22.25 seconds with a 328,663,040-byte peak RSS.

The formal backend now reuses the same isolated prewarm strategy for the
hash-pinned original module. `verify-formal-transport-monolithic` passes all
static, expected-residual, file/pipe, and wrong-consumer cases from the single
`TransportTests` source; prewarm peaks at 548,552,704 bytes and formal execution
peaks at 266,010,624 bytes. The supplied cubical tree remains interface-free.
The complete output is recorded in `BASELINE.md`.

The isolated selected+linked production candidate now repeats all seven formal
projection groups and the original monolith under effective engine `nbe`.
`verify-formal-transport-production-candidate` reports 8/8 groups and 42/42
summary rows `DIFFERENTIAL-PASS`. Static observations match the oracle;
unsupported Boundary/Higher inputs preserve their original Agda-checked pair
through explicit typed-residual passthrough, without an Agda-baseline
normalization fallback. This is the functional compatibility result; provider
content identity is pinned, while Git revision/license approval and
owner-approved production performance thresholds remain open.

The follow-up controlled release collector alternates engine order and uses the
same pinned source, GHC 9.6.7, isolated `-O2` binaries/objects/evidence,
AC-powered Apple M4 host, per-group 180-second hard timeout, and per-case
30-second evidence ceiling. The latest run reports
`ENGINEERING-PERFORMANCE-PASS`: overall median baseline/candidate times are
74.18/74.15 seconds and overall time/RSS/allocation p95 ratios are
1.016723/1.067052/0.999941. Higher and typed-residual RSS p95 is 1.194333
against the unchanged 1.30 ceiling. The earlier O0 dataset remains an honest
historical fail at 1.303373; owner approval of production thresholds is still
open. See `BENCHMARKS.md`.
The controlled path requires exact machine identity, AC power, low-power mode
off, nominal thermal state, two consecutive quiescent CPU/memory samples, and
a per-group background-process snapshot. An earlier invocation was rejected
on battery before staging; the subsequent O2 run passed all 48 host preflights.
Completed PASS and threshold-FAIL datasets are published transactionally; the
previous result is archived, while incomplete collection or validation leaves
it untouched.
Performance profile v2 also requires GHC RTS allocation evidence for exactly
the timed backend scenarios and compares allocated-byte ratios independently
of OS peak RSS. The earlier Base one-shot battery-powered values remain
diagnostic only. The accepted O2 three-run result contains all 48 allocation
datasets; static, typed-residual, and overall allocation p95 ratios are
1.000046/0.999802/0.999941.

The verification script canonicalizes `AGDA29_SOURCE_DIR` with `pwd -P` before
calling Cabal.  This avoids treating macOS `/tmp` and `/private/tmp` aliases as
different build roots; an already-invalid Cabal state cache may still require
one mechanical rebuild.

The upstream archive also contains both `test/Interaction` and
`test/interaction`. The supplied macOS extraction merges these on its
case-insensitive filesystem, while the Interaction/simple test driver expects
the lowercase runtime path and GNU sed's BRE `\+` extension. The maintained
group runner can reproduce the Linux semantics inside its temporary workspace
with `OFFICIAL_SUITE_INTERACTION_COMPAT=1`; 462/462 tests pass and the result is
explicitly labelled `PASS-WITH-ENV-COMPAT`.
