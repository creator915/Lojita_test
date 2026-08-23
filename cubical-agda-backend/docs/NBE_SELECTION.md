# NbE dependency selection record

Last updated: 2026-08-22 (Asia/Shanghai)

## Status

`ROUTE APPROVED — functional and provisional O2 performance gates passed; identity/owner thresholds pending`

On 2026-08-22 the owner approved option A: productionize the existing
Agda-specific in-process Haskell adapter, using cctt/Kovács as an algorithmic
reference rather than importing a third-party evaluator. The default
production `nbe` option remains fail-closed. The isolated candidate passes the
complete functional differential, but it cannot be accepted until it receives
an approved immutable revision identity, approved project license, and owner
confirmation of the final performance thresholds. Its current three-file
content identity is reproducible. The latest isolated O2 release-candidate run
passes the provisional gates: Higher/typed-residual RSS p95 is `1.194333`
against the unchanged `1.30` ceiling. The earlier O0 engineering dataset remains
an explicit historical failure at `1.303373`; neither result supplies owner
approval of the final thresholds.

The route decision does not by itself select a production provider. The strict
`config/nbe-adapter.lock.tsv` record therefore remains `status=unselected`;
all provider-specific values are `UNRESOLVED`, while the integration boundary
is now fixed by owner decision to in-process Haskell over `engine-request-v1`.

The first promotion slice is implemented. `make
verify-nbe-production-candidate` proves that the checked-in unselected lock
and a selected lock naming another provider cannot build this candidate,
either the link key or selection key alone fails closed, and a synthetic lock
selecting `agda-specific-in-process-v1` plus both keys executes recursive Nat
with byte-identical observed/Treeless/Scheme output versus the baseline. The
same selected+linked candidate also compiles and passes under pinned Agda 2.9.
Its staging is deliberately `candidate-not-accepted`; the synthetic test lock
does not substitute for a reproducible identity of this workspace's own
adapter source.

The workspace adapter now has a separate content-identity contract:
`config/nbe-adapter-source-files.tsv` names the engine boundary, evaluator/
readback, and plugin entry; `config/nbe-adapter-source.identity.tsv` pins three
files, 465,028 bytes, zero patches, and canonical manifest SHA-256
`3e0fa90e45f57a544b36f0041065c439a384d65a6e1ff19bf8a61ec4bdddfa9a`.
`verify-nbe-adapter-source-identity` passes three positive cases and six
negative controls, including an end-to-end synthetic eligible Git/license/lock
promotion. It rejects source mutation, stale manifest identity, path traversal,
a license claim without VCS provenance, a mismatched selection lock, and the
expected promotion attempt against the current blocked record.

This content pin does not invent ownership facts. The repository now records
the GitHub origin with `vcs-status=present`, but no immutable provider revision
or project `LICENSE`/`COPYING` has been approved. The identity therefore keeps
`revision=UNRESOLVED`, `license-spdx=NOASSERTION`, and
`selection-eligibility=blocked`. `check-nbe-production-promotion` fails with
`CCZ-NBE-PROMOTION-BLOCKED` until an owner supplies and approves the missing
revision, SPDX license evidence, decision owner, and date. At that
point the gate also checks Git `HEAD`, `origin`, clean pinned files, the license
file hash, and exact agreement with the selected provider lock.

The public-provider census was refreshed on 2026-08-21 and is checked in as
`config/nbe-provider-candidates.tsv`.  `make verify-nbe-provider-selection`
validates the exact revisions, deterministic source-archive SHA-256 values,
packaging, semantic scope, and the cross-invariant that a census containing
zero Agda Internal adapters cannot coexist with a selected provider lock.

## Candidate inspected

| Field | Evidence |
|---|---|
| Repository | [`AndrasKovacs/cctt`](https://github.com/AndrasKovacs/cctt) |
| Inspected commit | [`ba16f3758a322e9be77ada1da2b93f45d500192e`](https://github.com/AndrasKovacs/cctt/commit/ba16f3758a322e9be77ada1da2b93f45d500192e), 2026-06-09 |
| License | MIT, confirmed by [`LICENSE.txt`](https://github.com/AndrasKovacs/cctt/blob/ba16f3758a322e9be77ada1da2b93f45d500192e/LICENSE.txt) and package metadata |
| Declared purpose | Experiments on high-performance evaluation for Cubical type theories |
| Packaging | One `cctt` executable; no Cabal library target |
| Toolchain | `nightly-2024-04-08`, two Git-pinned extra dependencies, custom GHC plugin/options |

The commit is recorded for repeatable inspection only.  It is **not** an
approved or vendored project dependency.

The deterministic source identity in the candidate census is computed with
`git archive --format=tar REVISION | sha256sum`. At the inspected revision it
is `8d83adcb45ea827583f02fb6fb5c7d023ae97fdf6dd7816e9069ee45c67b6b5d`.
The repository's current `agda/` directory contains six `.agda` benchmark
programs; it does not contain an Agda compiler adapter.

## Public candidate census

| Candidate | Exact revision | Finding | Disposition |
|---|---|---|---|
| `cctt` | `ba16f3758a322e9be77ada1da2b93f45d500192e` | Haskell executable, own Cartesian Cubical core, MIT | Preferred algorithm/reference; requires a new Agda adapter |
| `cooltt` | `b39bf29900451cb43ae6fbd9af5aa33d59e18935` | OCaml executable, own Cartesian Cubical language, Apache-2.0 | Reference only; adds language and process boundaries |
| `cubicaltt` | `9baa6f2491cc61dbd4fd81d58323c04100381451` | Haskell executable, own Cubical syntax/core, MIT | Reference only; requires a new Agda adapter |
| `smalltt` | `ea99b0f478e50dcb81ea19e40bfb4262339b22aa` | Haskell library/executable, ordinary dependent core, MIT | Not a Cubical provider |

No audited public candidate exposes a drop-in evaluator over Agda
`Internal.Term` plus `TCState`. This is a negative feasibility result, not a
claim that no unpublished or future implementation can do so.

## Compatibility finding

Direct linking is not a safe minimal integration:

1. `cctt` is a ground-up Cartesian Cubical type theory implementation, not an
   evaluator over Agda `Internal.Term` and `TCState`.
2. It defines its own syntax, semantic `Val`, environments, definitions,
   cofibrations, interval substitutions, evaluator, and quotation pipeline.
3. Its package exposes an executable rather than a stable library API.
4. A translation would need to preserve Agda universes, definitions, records,
   inductive/HIT declarations, metas, relevance, interval algebra, `transp`,
   `hcomp`, Glue, and source/signature identity.  That is a semantic adapter,
   not a mechanical Haskell import.
5. Because the source and target Cubical theories are not identical, an
   unchecked constructor-to-constructor translation could silently change
   computation behavior.

The repository is a strong **algorithm and representation reference** for
closures, neutral values, shallow interval substitutions, forcing, evaluation,
and quotation.  It is not currently a drop-in mature NbE for this backend.

`AndrasKovacs/smalltt` was also considered and rejected as the Cubical engine:
its own documentation describes a minimal dependent type theory and explicitly
notes that Cubical type theories still require substitution.  It is useful for
ordinary NbE design, not for the required Cubical semantics.

## Decision options

### A. Agda-specific adapter informed by cctt — selected path

- Keep Agda `TCState` as the source of truth.
- Port only the semantic value/eval/quote ideas needed by the locked acceptance
  matrix.
- Recheck every read-back term with Agda.
- Fall back to the existing typed packet path outside the supported fragment.

This is the owner-approved, smallest semantics-preserving path, but it must not be described as
“directly linking cctt”. Approving this option means accepting a new
Agda-specific adapter whose semantic design is informed by a mature evaluator;
it does not mean that the existing `cctt` executable itself becomes the
production dependency.

The first test-only feasibility slice of this option now exists in
`src/CubicalChez/Nbe/AdapterSpike.hs`; see `NBE_ADAPTER_SPIKE.md`. It evaluates
ordinary checked functions through environments/closures and quotes back to
Agda Internal. Its second slice also evaluates structurally recursive builtin
Nat, caches signature definitions per request, and distinguishes repeated
ground-call cycles from fuel exhaustion. Its third slice moves type
normalization into an ordinary Type/Sort/Level/Pi semantic domain. Its fourth
slice proves custom recursive algebraic data and proper record projection
semantics, including neutral projection readback in dependent Pi types. It
also has a fifth slice for parameterized universe-polymorphic type aliases,
two-atom level joins, and explicit rejection of postulated `DefS` sorts. It
has a sixth slice whose exact Agda `PrimitiveId` registry reduces builtin Nat
addition/subtraction/multiplication, preserves partial/neutral applications,
and emits source-located diagnostics for unregistered or impostor definitions.
Its seventh slice recognizes interval endpoints and ground/open cofibration
identities, then closes narrow primitive-level and exact-source transport
cases. Subsequent slices preserve Glue introduction/elimination, recognize
canonical `ua` transport and one guarded double-composition shell, and keep a
canonical-domain Pi transport callable through checked isomorphism record
structure; its codomain may be stable or another canonical Glue path, in which
case a ground source result is mapped forward. A codomain may also mention its
binder syntactically when opaque-binder evaluation proves that the probe and
both endpoints reduce to the same closed definition. One exact dependent
self-path branch preserves builtin `PathP`, validates binder endpoints and a
syntactically interval-independent inner family against endpoint readback, and
checks source reflexivity at three interval
observations before producing an endpoint-observable target reflexive path.
A sibling canonical-singleton branch validates builtin Sigma, matches its
first type to the Pi domain, requires the second field family to be the exact
directed path in either explicitly classified binder/field order, checks a
source `(b , refl)` at three interval observations, and rebuilds the target
singleton inhabitant. The two directions have separate telemetry.
A third guarded mechanism recursively classifies exact-depth Sigma spines,
requiring the outer source point to equal `b`, assigning every layer an
explicit `canonical-path` or `stable-identity` plan, and requiring the final
proof to pass the same direction/reflexivity checks before rebuilding the
target structure. Plans are admitted only when the probe and both endpoint
views agree: canonical layers match the domain path, while stable layers
have equal semantic readback and a recursively binder-free closed
definition/level/index argument spine. The
audited bound is three Sigma layers and both terminal directions have separate
telemetry. Auxiliary ground points may differ from the source argument only
after canonical-forward and checked-inverse round-trip. A syntactically
dependent field alias is additionally accepted only under probe-shell
identity: both it and the domain must expose the same Glue base/face and equal
endpoint readbacks. This closes `SameType (notPath i) x`; a
`ConstantType x = Bool` field is preserved by stable identity instead of being
mapped through `not`; closed `List Bool` applications and constructor spines
are preserved too. `notPath (~ i)` remains a mismatched-shell control, and
`Tagged x` rejects because its index retains the prior field neutral.
Ordinary data/record constructor spines are also admitted when checked
`conPars`/`conArity` metadata separates closed parameters from recursively
closed payloads. An ordinary function closure in that spine is admitted only
after semantic readback produces an Agda-closed lambda; the dedicated
`nbe-closed-stable-function-values-validated` counter records this proof.
The stable type guard is monadic for Pi values: it quotes each probe/i0/i1
view at depth zero and requires Agda `closed`. Only the selected transport plan
publishes `nbe-closed-stable-pi-type-views-validated`, avoiding speculative
classifier counts. A direct `Bool -> Bool` field therefore passes with three
validated views, while `Tagged x -> Bool` rejects because `x` remains a field
neutral under the stable guard. It is handled only by the separate
outer-parameter indexed-Pi plan: `Tagged` must be a non-indexed data family,
its outer type/value parameter positions are jointly checked at probe/i0/i1,
and a target constructor is rewritten to source parameters before the closed
ordinary source function is called. A nonzero payload spine is accepted only
when every declared payload type is closed independently of all prior binders,
each field value is exact ground `Nat`, a literal, or builtin `Bool`, and those
fields are preserved unchanged. A custom nested constructor payload and a Bool
field declared at the remapped outer type `A` both remain fail-closed; forced constructor indices absent from patterns are tolerated only
when the clause body provably does not reference their telescope slots.
Internal composition/canonical-transport closures, open neutrals, other
non-ground values, unmatched probe shells, and four or more layers remain unsupported; this does
not choose or enable the production provider.
Canonical
`ua` is now also recognized in reverse
only after an independent endpoint/identity check and checked inverse
round-trip. General data/record type applications can remain neutral for
readback and stable classification; exact builtin Sigma/List identities remain
the only structured-transport heads. Two already-admitted canonical Glue
transports also compose by ordinary eager evaluation, closing exact
`TransportHit.t15` without adding a HIT value or a new matcher. Ordinary
definition unfolding likewise reduces exact `TransportHit.t14` by exposing
Prelude `J` as the already-supported constant-Nat transport at `refl`; this is
not a general J implementation. A guarded S¹ slice additionally closes exact
`TransportHit.t12/t13`: checked eliminator patterns and `PrimComp` expansion
feed a recursively endpoint-validated probe-HComp chain, with explicit
forward/backward Glue direction and checked inverse round trips. It still has
no general Kan operations, dependent/open Pi codomains beyond those exact
self-path/singleton/bounded-Sigma-spine slices, or HIT semantic values. Its effective engine is deliberately
`nbe-spike-test-only`, so owner approval selects its productionization route
without prematurely enabling the production engine.

### B. Refactor and embed cctt

- Fork the candidate at the inspected commit.
- Create a library boundary and an Agda-to-cctt semantic translation.
- Prove or differentially test every supported Cubical primitive mapping.

This has substantially higher schedule and maintenance risk.

### C. Use another internal/external NbE

The owner supplies the exact repository, commit, license, and expected adapter
boundary.  It must satisfy `ENGINE_CONTRACT.md` before the `nbe` CLI is enabled.

## Minimum-patch policy

The integration uses the following enforceable policy regardless of the
selected option:

1. Keep provider source outside the backend tree and identify it by repository,
   full commit, deterministic source SHA-256, and license in the selection lock.
2. Prefer a backend-owned adapter against the existing `engine-request-v1`
   boundary. Do not copy provider modules into `src/CubicalChez`.
3. Upstream patches default to zero. Any unavoidable patch must have its own
   file, purpose, upstream issue/reference, and SHA-256 in a reviewed patch
   manifest before it is applied.
4. A provider update is a lock change and must rerun adapter-contract,
   EngineResult, formal differential, and performance gates. It cannot be
   absorbed as an unrecorded source refresh.
5. Provider output remains untrusted until Agda accepts the closed, meta-free
   readback through the existing `validateEngineResult` gate.

The current census and lock satisfy this policy without vendoring or patching
any candidate.

## Acceptance harness readiness

The remaining owner decision no longer blocks construction of the acceptance
oracle. The full formal runner is parameterized by engine and writes candidate
evidence outside the `agda-baseline` tree. A machine-readable comparator covers
all seven exact projections and the hash-pinned original monolith. It requires
the same observed values, residual classifications, wrong-consumer rejection,
input hashes, fragments, binding-time class/reason/action, and prewarm
inventory, while keeping performance data separate. Independent candidate
evidence must provide `binding-time.tsv`; it cannot inherit the legacy oracle
migration.

The comparator self-check passes for all 8 groups. Negative controls reject an
unauthorized baseline self-comparison, a one-value mutation, and missing
candidate evidence. Additional controls reject a missing candidate
`binding-time.tsv` and a `static` to `mixed` mutation. The isolated
selected+linked candidate now passes the real comparison for all 8 groups and
42 summary rows. Its static cases match the oracle, while explicitly
unsupported Boundary/Higher cases preserve the checked request as a typed
residual without invoking Agda normalization. This is functional acceptance of
the candidate route, not final provider selection: the checked-in lock remains
`unselected`. Adapter content identity is pinned, but Git revision/license
approval and owner-approved performance thresholds remain open. The latest
isolated O2 three-run profile is `ENGINEERING-PERFORMANCE-PASS`; its Higher and
typed-residual RSS-ratio p95 is `1.194333` against `1.30`. The threshold was not
changed. The earlier O0 profile remains a historical
`ENGINEERING-PERFORMANCE-FAIL` at `1.303373`.

The backend-level unsupported-feature policy is fixed independently of provider
choice. A linked adapter must distinguish `unsupported` from `unavailable`,
`timeout`, `failed`, and invalid read-back. Unsupported rejects by default and
may use either the explicitly selected Agda-baseline oracle fallback or the
explicit `typed-residual` passthrough. The latter preserves the checked request,
forces dynamic publication, keeps the effective engine as `nbe`, and is the
only unsupported disposition admitted by candidate differential evidence. The
baseline fallback records the oracle as effective engine and is excluded from
NbE acceptance. All other outcomes fail closed.

## Remaining owner and acceptance decisions

Option A and the in-process boundary are approved. The remaining decisions are:

1. whether the target is still Chez Scheme;
2. the repository/revision and license identity assigned to the in-process
   adapter source;
3. the supported static fragment and provider-outcome mapping;
4. whether acceptance requires definition-internal specialization;
5. the required test scope and performance threshold.

Once those values are approved, they replace the `UNRESOLVED` fields in
the source-identity record and lock. `make check-nbe-production-promotion` must
report `READY-PASS`; a schema-only `SELECTED-PASS` is insufficient. The
separate linked-adapter, differential, and performance gates must still pass
before `--cubical-chez-engine=nbe` is usable.
