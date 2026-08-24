# CubicalChez support matrix

Last updated: 2026-08-24 (Asia/Shanghai)

This document separates verified behavior from code that exists only in the
isolated production candidate, intentional typed residuals, and unsupported
input. It is a scope ledger, not a claim that the default `nbe` engine has been
released.

## Status vocabulary

| Status | Meaning |
| --- | --- |
| `VERIFIED` | The maintained command executes the behavior and its positive and negative gates pass. |
| `VERIFIED-CANDIDATE` | Verified only in the isolated selected+linked NbE candidate; the checked-in production lock remains unselected. |
| `EXPECTED-RESIDUAL` | Static erasure is not authorized; the checked Agda `Term : Type` is preserved through the documented typed path. |
| `FAIL-CLOSED` | The backend rejects before publishing executable Scheme or an invalid packet. |
| `NOT-VERIFIED` | The implementation or design is incomplete, or no acceptance evidence exists. |
| `OWNER-BLOCKED` | Engineering evidence exists, but an explicit product, license, or threshold decision is still required. |

## Engine and release status

| Surface | Status | Current behavior and evidence |
| --- | --- | --- |
| Goal 1 stock Agda/MAlonzo/GHC native lane | `VERIFIED` | Locked official Agda `84497d0` emits audited MAlonzo `AgdaAny` Haskell; locked GHC 9.10.3 builds the audited ELF. Ordinary and erased-Cubical compile/run, direct-stock differential, type-error, misclassification, stale-artifact, and clean-clone gates pass. Static Chez output is not used as evidence. |
| Goal 2 checked cross-process packet lane | `VERIFIED` | An independent locked Agda source checkout receives the maintained overlay, builds `agda-cubical-run` with the locked GHC/Cabal pair, and passes self-contained, file, pipe, wrong-consumer and residual tests in macOS clean-clone run `32753401570`. |
| Goal 3 NbE linked into the final program process | `OWNER-BLOCKED` | 11/11 implementation items and the full clean-clone gate pass. The adapter constructs cctt Coe/HCom/Glue terms for actual Bool/Int/Vec/Sigma inputs and the proof-linked same-input gate passes; independent acceptance remains pending and general Cubical normalization remains outside the claim. |
| Default binary, `agda-baseline` | `VERIFIED` | Uses Agda normalization as the correctness/performance oracle. It is not counted as NbE acceleration. |
| Default binary, `nbe` | `FAIL-CLOSED` | Returns `CCZ-NBE-UNAVAILABLE`; it never silently falls back and publishes no stale executable artifact. |
| Test-only adapter spike | `VERIFIED` | Fourteen baseline-equal results and nine fail-closed controls cover the narrow semantic domain. |
| Selected+linked in-process NbE candidate | `VERIFIED-CANDIDATE` | Eight formal groups and 42/42 differential rows pass; supported cases use effective engine `nbe`, and unsupported formal cases use checked typed-residual passthrough without baseline normalization. |
| Candidate release performance | `VERIFIED-CANDIDATE` | Controlled `release-o2` run passes all functional, time, RSS, allocation, artifact, stage, host, and publication gates. Overall time/RSS/allocation p95 is 1.016723/1.067052/0.999941. |
| Production provider promotion | `OWNER-BLOCKED` | The three source files and GitHub origin are recorded, but an approved immutable revision, license, decision owner, and final threshold approval are unresolved. `check-nbe-production-promotion` rejects this state. |

The exact lock state is recorded in `config/nbe-adapter.lock.tsv`; source
identity and its current legal/VCS block are recorded in
`config/nbe-adapter-source.identity.tsv`.

## Formal `TransportTests` matrix

All rows below start from Agda source. Static rows are checked through
Internal-term admission, Treeless audit, complete Scheme lowering, and Chez
execution. Residual rows retain the checked term and type instead of erasing
them.

| Group | Cases | Candidate result | Published form |
| --- | --- | --- | --- |
| Base | `t01`, `t02`, `t07` | `VERIFIED-CANDIDATE`; values `7`, `7`, `4` | Static Scheme |
| Glue | `t03`, `t04`, `t08` | `VERIFIED-CANDIDATE`; values `false`, `true`, `false` | Static Scheme |
| Int | `t05`, `t06` | `VERIFIED-CANDIDATE`; values `pos 1`, `negsuc 0` | Static Scheme |
| Core | `t09`, `t10` | `VERIFIED-CANDIDATE`; Sigma `(false, 3)` and List `false/true/false` | Static Scheme |
| Boundary | `t11`, `t11b` | `EXPECTED-RESIDUAL`; exact `transpX-Vec` blocker retained | Typed residual manifest/packet according to policy; no Scheme |
| Hit | `t12`-`t15` | `VERIFIED-CANDIDATE`; values `pos 2`, `pos 1`, `41`, `true` | Static Scheme |
| Higher | `p16a`-`p16c` with `c16a`-`c16c` | `EXPECTED-RESIDUAL`; file and pipe consumers pass, wrong consumer rejects | Agda 2.9 v2 typed packet/file or stdout pipe; no Scheme |
| Original monolith | Hash-pinned `test/fixtures/TransportTests.agda` | `VERIFIED-CANDIDATE`; all static, residual, pipe, and rejection expectations match the projections | Per-entry static Scheme or checked typed packet |

The candidate/oracle differential contract is functional rather than a
baseline self-comparison. It rechecks scenario inventories, input hashes,
fragments, binding-time classification, prewarm state, and requested/effective
engine provenance.

## NbE semantic coverage

| Capability | Status | Boundary |
| --- | --- | --- |
| Variables, lambdas, applications, literals, constructors, ordinary clauses, environments, and closures | `VERIFIED-CANDIDATE` | Covered by ordinary Bool, recursive Nat, custom recursive data, and formal cases. |
| Proper record projection and neutral projection readback | `VERIFIED-CANDIDATE` | Checked record/field metadata is required; invalid receivers fail closed. |
| `Type`/`Sort`/`Level`/`Pi` evaluation and readback | `VERIFIED-CANDIDATE` | Covers ordinary universe-polymorphic aliases and neutral levels; persisted postulated sorts reject. |
| Exact Nat add/sub/mul primitive identity | `VERIFIED-CANDIDATE` | Registry is keyed by Agda `PrimitiveId`, not rendered QName. Unknown or impostor primitives reject. |
| Ground interval/cofibration operations | `VERIFIED-CANDIDATE` | Exact endpoints and registered `IMin`/`IMax`/`INeg`; general open faces are not supported. |
| Exact `transp`, `hcomp`, `comp`, Glue and `ua` slice required by `t01`-`t15` | `VERIFIED-CANDIDATE` | Guarded semantic shapes, endpoint equality, checked equivalence maps, and bounded composition only. |
| Builtin Sigma/List transport | `VERIFIED-CANDIDATE` | Exact stable/ground forms used by `t09`/`t10`; general dependent Sigma and indexed data are not supported. |
| S¹/J/repeated Glue cases | `VERIFIED-CANDIDATE` | Exact checked definition/primitive patterns used by `t12`-`t15`; not a general HIT or J evaluator. |
| General open face, Kan, HCompU, Glue Kan, recComp, indexed data, or arbitrary HIT semantics | `NOT-VERIFIED` | No production support claim; unrecognized shapes return `CCZ-NBE-UNSUPPORTED` or remain typed residuals when explicitly allowed. |
| General module-wide normalization | `NOT-VERIFIED` | The current contract selects one closed, zero-argument entry; it is not a general whole-module compiler. |

## Static Chez output

| Capability | Status | Boundary |
| --- | --- | --- |
| Literals, lambdas/application, constructors, case, recursion, and exact arithmetic primitives | `VERIFIED` | Exercised by the toy regression, smoke fixtures, `chez-core-abi-v1`, and formal static cases. |
| Stable data/record/function/primitive ABI | `VERIFIED` | Tagged vectors, unary-curried closures, exact primitive arity/map, and deterministic QName mangling are versioned by `chez-core-abi-v1`. |
| Static erasure safety | `VERIFIED` | All engine results are closed, meta-free, and re-typechecked by Agda; Internal and Treeless audits must agree before `StaticClosure` authorizes publication. |
| Static artifact contains compiler/typechecker runtime | `FAIL-CLOSED` | Formal static outputs are checked not to carry `Term`, `Type`, `TCState`, typed runtime, or residual Cubical blockers. |
| Arbitrary reachable definition closure/module artifact protocol | `NOT-VERIFIED` | The selected-entry closure is deliberately narrow; a general stable module protocol remains open. |

## Typed residual and runtime support

| Capability | Status | Boundary |
| --- | --- | --- |
| Whole-entry v2 packet | `VERIFIED` | Agda 2.9 only; carries checked `Term + Type`, exact interface identity, and a checked type/body dependency slice rather than the whole signature. |
| Final-process runtime NbE | `VERIFIED-CANDIDATE` | For the declared fragment, checked Internal Bool/Nat/Int/Vec/Pi/Sigma/Glue/PathP/S¹ definitions translate without compiler normalization and execute through cctt Coe/HCom/Glue in a Stock Agda/MAlonzo/GHC final program under a no-exec guard. The full clean-clone gate passes; this row does not imply independent acceptance or general Cubical semantic coverage. |
| File and stdin/stdout packet transport | `VERIFIED` | Higher cases pass across independent processes; incompatible consumers reject before evaluation. |
| Mixed closed/open typed holes | `VERIFIED` | Stable hole IDs, unique Internal `Term : Type` matching, lambda lifting, and `opaque-import-v1` static shells are checked before publication. |
| Ground codecs | `VERIFIED` | Bool, bounded Nat, Word64, Unicode-scalar Char, and signed-64 Int across unary, single-slot lexical, ordered, and 2-64-slot dependent replay. |
| Persistent typed proxy and composition | `VERIFIED` | Checked packet references, parent retention, recursive GC, count/byte quotas, and shared publication/lifecycle transactions are covered. |
| Arbitrary non-ground values represented directly inside Chez | `FAIL-CLOSED` | Non-ground values remain in typed packets and may cross checked mapper/consumer boundaries; they are not inserted into erased Scheme values. |
| Additional codecs or a universal typed-value ABI | `NOT-VERIFIED` | New codecs require an explicit checked descriptor/reifier and acceptance tests. |

## Toolchain and host matrix

| Environment | Status | Scope |
| --- | --- | --- |
| Agda 2.8, GHC 9.12.3, Chez 10.4.1 | `VERIFIED` | Local smoke, contracts, static Scheme, failure taxonomy, and candidate spike. Binary v2 packet production intentionally rejects on Agda 2.8. |
| Pinned Agda 2.9 snapshot, GHC 9.6.7, Chez 10.4.1 | `VERIFIED` | Full archived v2 runtime, candidate gates, formal projections/monolith, typed packets, and official test evidence. |
| Official Agda `84497d0` (2.9.0), GHC 9.10.3, Linux x86-64 | `VERIFIED` | Goal 1 stock MAlonzo native lane, two compile/run cases, two fail-closed cases, provenance and binary audit, plus clean-clone replay. |
| macOS Apple M4, AC Power, GHC 9.6.7 `-O2` | `VERIFIED-CANDIDATE` | Controlled three-run release performance profile with 48/48 host preflights. |
| macOS 15 Intel clean clone, locked GHC 9.10.3 plus matching Homebrew legacy GHC | `VERIFIED` | Second-clone aggregate `make verify`, including the independent Goal 2 overlay build and all three path suites, passes in run `32753401570`. |
| Other OS/CPU/GHC/Agda combinations | `NOT-VERIFIED` | No compatibility or performance claim beyond the exact environments above. |

## Known residuals and rejection behavior

| Input/state | Required result |
| --- | --- |
| `t11`/`t11b` indexed `transpX-Vec` | `EXPECTED-RESIDUAL`; preserve checked type/path evidence, publish no executable Scheme. |
| Higher `t16` producer values | Checked v2 packet over file or pipe; wrong consumer is `EXPECTED-REJECT`. |
| Unregistered primitive, semantic/catalog disagreement, or unsupported Cubical shape | `FAIL-CLOSED` with stable `CCZ-NBE-UNSUPPORTED`/`CCZ-UNSUPPORTED` classification and no stale artifact. |
| Unavailable provider, evaluator timeout/failure, or invalid readback | `FAIL-CLOSED`; none is eligible for silent baseline fallback. |
| Explicit `agda-baseline` fallback after `CCZ-NBE-UNSUPPORTED` | Allowed only when requested; provenance records effective baseline and excludes it from NbE evidence. |
| Candidate-only `typed-residual` policy after candidate unsupported | In the selected+linked candidate, preserve the original checked pair, retain effective engine `nbe`, and do not invoke Agda normalization. It is not listed as a released default-CLI policy. |

Stable error-code meanings are defined in `FAILURE_CODES.md`.

## Acceptance work not represented as support

The following remain open even though the compiler candidate's engineering
gates pass:

- independently accept the implemented Goal 3 final-process runtime fragment;
- approve the final three-lane routing policy and official-test scope;
- approve an immutable provider revision and the license/NOTICE identity;
- approve final acceleration, RSS, allocation, and timeout thresholds;
- decide the final delivery form, deadline/timezone, and clean commit/package
  boundary.

Until those decisions are recorded, `VERIFIED-CANDIDATE` must not be relabeled
as released production support.

## Reproduction commands

```sh
make verify

AGDA29_SOURCE_DIR=/path/to/agda-source \
GHC29=/path/to/ghc-9.6.7 \
make verify-agda29

AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/clean-cubical-source \
GHC29=/path/to/ghc-9.6.7 \
CABAL29=/path/to/cabal \
make verify-formal-transport-production-candidate

AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/clean-cubical-source \
GHC29=/path/to/ghc-9.6.7 \
CABAL29=/path/to/cabal \
make verify-formal-transport-production-release-performance
```

The candidate target refreshes the baseline formal matrix first, so this
sequence also works from a clean evidence tree. The release-performance target
then recollects and transactionally publishes controlled evidence; use
`verify-benchmarks-guide` when only auditing the delivered result.

See `TEST-RESULTS.md` for full test counts and environment exceptions,
`BENCHMARKS.md` for controlled performance evidence, `ARCHITECTURE.md` for the
trust boundary, and `COMPATIBILITY.md` for pinned-source/toolchain details.
`TROUBLESHOOTING.md` maps every stable failure namespace to evidence and safe
recovery actions.
