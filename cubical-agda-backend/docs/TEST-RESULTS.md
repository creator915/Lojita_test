Warning: truncated output (original token count: 26785)
Total output lines: 1565

# Test results

Last updated: 2026-08-23 (Asia/Shanghai)

This is the current evidence ledger, not a claim that final acceptance is
complete. An isolated selected+linked production candidate is now connected,
while the checked-in production lock and default binary remain unselected;
formal-backend TransportTests `t01`-`t10` are statically closed and `t11/t11b`
are closed as expected typed residuals; `t12`-`t15` are also statically closed;
and the `t16` file/pipe protocol is closed. The same matrix also passes from the
hash-pinned original monolithic source under the maintained prewarm protocol.
The isolated production candidate passes the complete functional differential.
The latest controlled three-run release-candidate performance run passes every
functional, time, RSS, allocation, artifact, stage, host, and publication gate
under isolated GHC `-O2`. Its Higher/typed-residual RSS p95 is `1.194333`
against the unchanged `1.30` ceiling. The earlier O0 result remains retained
as an honest historical fail (`1.303373 > 1.30`). The compiler-process
candidate's promotion identity and owner-approved production thresholds remain
open for the separate compiler-process candidate. Goal 3 instead uses an
independent final-process lock: ten unmodified cctt Core modules are pinned,
packaged as a library, and linked behind the Agda runtime adapter.
Goal 1 now has separate Linux x86-64 evidence from official stock Agda commit
`84497d0`, MAlonzo and GHC 9.10.3. The maintained lane and a clone of local
commit `7578f56` both pass two compile/run cases and two fail-closed cases.
The controlled collector now fails closed before staging or replacing prior
evidence when the fixed host/power/quiescence contract is not met. An earlier
Battery Power retry was correctly rejected without staging or replacement;
the subsequent AC-powered release run published 3,219 raw evidence files.
Goal 3 is currently 10/11 for its declared fragment. The runtime passes 27 self-tests;
the real Agda bridge passes seven cases for literals, Pi, checked definitions,
same-expression oracle comparison and fail-closed pattern definitions. The
Stock Agda/MAlonzo/GHC final-program gate passes nine rows, including static
runtime symbols, no compiler symbols, zero exec attempts and preserved
`PrimTrans`/`PrimHComp` packets whose outputs agree with the Agda oracle.
The maintained `semantic-negative-index.packet` regression now returns the
correct `App (Var 1) (Var 0)`, and a malicious negative-index packet rejects.
cctt linkage passes ten source hashes, eleven actual-input eval/quotation cases
and final-ELF symbol checks. The replacement same-input gate covers
`t11/t11b/t09/t16a/t16b/t16c`; t11/t11b now eliminate the exported definition
to canonical Bool-pair observations and compare them exactly. Its locked-CI
result is pending, so this ledger does not record Goal 3 acceptance.

## Environment

- Current goal-1 replay: Linux x86-64, official Agda `84497d0`, GHC 9.10.3.
- Host: macOS 26.3.1, arm64 Apple M4, 24 GiB RAM.
- Local slice: Agda 2.8.0, GHC 9.12.3, Chez Scheme 10.4.1.
- Pinned delivery tree: supplied Agda 2.9.0 snapshot, exact parent std-lib
  gitlink snapshot, GHC 9.6.7, and supplied cubical snapshot.
- `test/fixtures/TransportTests.agda` SHA-256:
  `8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b`.

The supplied Agda and cubical snapshots have no `.git` metadata. The Agda stock
projection has been independently matched to the official `d8a73ff...` commit
archive by content. The reported cubical commit is still verified only through
the maintained source/input hashes and awaits an independent upstream match.

## Results summary

| Target | Scope | Result | Time / peak RSS |
| --- | --- | --- | --- |
| `make verify-runtime-nbe` | runtime semantic domain, typed requests, input-dependence control, cache, limits, archive/harness link, no-exec and higher-order readback regression | 27/27 PASS | not measured |
| `make verify-runtime-nbe-cctt-provider` | exact cctt Core source/license identity, input-driven eval/quotation, runtime archive and ELF linkage | 10 source hashes + 11 actual-input cases + symbol audits PASS | local Linux run |
| `make verify-runtime-nbe-agda-bridge` | real checked Agda Internal Bool/Nat/Pi and single-clause definition slice, same-expression Agda oracle, unsupported-pattern rejection | 7/7 PASS | local Linux run |
| `make verify-runtime-nbe-differential` | same checked Agda definitions exported to the linked runtime and observed by Agda: `t11/t11b/t09/t16a/t16b/t16c` | replacement exact 6/6 comparison implemented; locked-CI result pending | pending |
| `make verify-runtime-nbe-final-malonzo` | Stock Agda -> MAlonzo -> GHC user program with linked runtime; real `PrimTrans`/`PrimHComp`, unsupported-face rejection, oracle, symbol and no-exec audits | 9/9 PASS | local Linux run |
| `make verify-runtime-nbe-oracle` | pinned Agda 2.9 + Cubical v0.9 typecheck plus five separately hand-written prototype expectations | 2 modules / 5 expectations PROTOTYPE-PASS; not a differential test | not measured |
| `make verify-native-lane` | locked official Agda -> MAlonzo erased Haskell -> locked GHC ELF; ordinary and erased-Cubical compile/run, direct-stock differential, full-Cubical misclassification, stale publication and type-error comparison | 2 compile/run PASS + 2 fail-closed PASS; 28 generated Haskell files audited; no compiler, `TCState`, runtime NbE, Agda library or residual transport identity in either ELF; identical PASS from clean clone of `7578f56` | current Linux x86-64 run PASS on 2026-08-23; resources not benchmarked |
| `make verify-runtime-nbe-boundary` | goal 3 final-process identity, linked-library requirement, immutable checked request/result boundary, and compiler/closure/subprocess/network prohibitions | boundary contract PASS; acceptance pending | under 1 s; resources not benchmarked |
| `make verify` / `make -k verify` | current uploaded snapshot on Linux with the available Agda 2.9/GHC 9.10.3 toolchain | NOT PASS: the archive omits the 3,219-file historical benchmark evidence required by `verify-benchmarks-guide`; the fork origin does not match the still-unapproved provider identity; the remaining local smoke gates require the documented Agda 2.8/Cubical environment. Status, README, support, troubleshooting, native-lane, runtime-boundary, provider-census and four synthetic timing/performance/publication contracts PASS. | current Linux run on 2026-08-23; 15.6 s for keep-going audit |
| `make verify-agda29-stock-baseline` | official stock parent projection plus supplied v2 overlay | 10,084/10,084 stock files and 9/9 overlay files PASS | not benchmarked |
| historical `make verify` | root-layout local Agda 2.8 static, goal/checklist/README/support/troubleshooting/benchmark documentation contracts, NbE provider census/source identity/test-only adapter spike/production candidate/lock/fallback policy, engine-result recheck, four-way binding time, typed-residual shell composition, primitive catalog, static-closure authorization, Chez core ABI, failure taxonomy, timing/host/performance/publication self-tests, Cubical static, typed rejection and safety smoke | pre-goal-1 status 20/56 with goals 1 and 3 explicitly open; root layout and seven-option CLI synchronized; source identity 3 positive + 6 negative; adapter spike 14 baseline-equal + 9 fail-closed; production candidate, lock, fallback, EngineResult, binding-time, residual, primitive, closure, ABI, failure, timing, performance, publication and smoke gates all PASS | supplied historical root-layout run PASS on 2026-08-23; wall time and peak RSS not separately captured |
| `make verify-agda29` | test-only ordinary/recursive-Nat/custom-data/record/Pi-Universe/alias/exact-primitive/ground+neutral-Cubical+Glue-cancellation NbE adapter differential, one isolated selected+linked production-candidate differential, cycle/fuel/invalid-projection/postulated-sort/unregistered-primitive/impostor/PrimFaceForall controls, ordinary/mixed whole-entry, closed and lambda-lifted open-hole packets, exact type/body dependency slicing, versioned Chez record/data/function/primitive ABI, opaque-shell observation, ID-addressed and batch observation, explicit Bool/Nat/Word64/Char/Int unary/vector plus single-slot, ordered, and dependent Bool/Nat/Word64/Char/Int lexical replay, registry/descriptor self-checks, general checked packet-reference mapping, quota/lock/state-transaction controls, typed proxies with composition/retention/recursive GC, and packet/bridge/producer safety negatives | 155 positive executions + 146 expected rejections PASS | current full dependency/backend fault-build recompilation PASS; wall time/peak RSS not captured |
| `make verify-nbe-adapter-transport-base` | pinned original/projection byte identity plus test-only NbE/Agda-baseline comparison for exact `TransportBase.t01/t02/t07` | 3/3 PASS; observed/Treeless/Scheme byte-identical; `t01/t02/t07 = 7/7/4`; exact Nat and exact Nat-function transport counters verified | 4.03 s; peak RSS not measured |
| `make verify-nbe-adapter-transport-glue` | pinned original/projection byte identity plus test-only NbE/Agda-baseline comparison for canonical `TransportGlue.t03/t04/t08`, eighteen local varying/semantic-constant/dependent-self-path/directed singleton/nested/bounded-spine/fieldwise/dependent-alias/closed-parameterized/metadata-data-record/readback-closed-function/direct-closed-Pi/outer-indexed-Pi/ground-payload-indexed-Pi positives, and non-canonical double-composition/mismatched-dependent-field/binder-indexed-stable-lookalike/nested-payload-indexed-Pi/dependent-payload-type/internal-transport-function-record/over-limit controls | all eighteen local extensions PASS with observed/Treeless/Scheme byte-identical; direct Pi/function/stable counts 3/1/1, indexed-field/application counts 1/1, and the payload case records one preserved ground field; all seven controls EXPECTED-REJECT with zero publication | current changed-source run PASS; peak RSS not measured |
| `make verify-nbe-adapter-transport-int` | pinned original/projection byte identity plus test-only NbE/Agda-baseline comparison for bidirectional canonical `TransportInt.t05/t06`, with a nested-endpoint fail-closed control | `t05/t06=pos 1/negsuc 0` PASS with observed/Treeless/Scheme byte-identical; backward Glue counter 0/1; control EXPECTED-REJECT with zero publication | current changed-source run PASS; peak RSS not measured |
| `make verify-nbe-adapter-transport-core` | pinned original/projection byte identity plus test-only NbE/Agda-baseline comparison for builtin Sigma/List `TransportCoreB.t09/t10`, with varying-second-Sigma and nested-endpoint-List fail-closed controls | `t09=(false,3)`, `t10=false/true/false` PASS with observed/Treeless/Scheme byte-identical; record/data counters 1/0 and 0/1; both controls EXPECTED-REJECT with zero publication | current changed-source run PASS; peak RSS not measured |
| `make verify-nbe-adapter-transport-hit` | pinned original/projection byte identity plus test-only NbE/Agda-baseline comparison for S¹ winding/composition `t12/t13`, J-at-refl `t14`, and repeated canonical Glue `t15`, with non-canonical winding/inverse/J/outer-family controls | `t12/t13/t14/t15=pos 2/pos 1/41/true` PASS with observed/Treeless/Scheme byte-identical; t13 direct/backward/composed Glue=1/1/1; t12, t14, and t15 retain their pinned counters; all 4 controls EXPECTED-REJECT with zero publication | current changed-source run PASS; peak RSS not measured |
| `make verify-transport-shards` | 7 diagnostic shards plus exact original stock-Agda typecheck | 8/8 PASS | 15.8 s overall; highest child RSS 548,552,704 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportBase` group, then Chez | 3/3 PASS; `t01/t02/t07 = 7/7/4`; binding time static; zero executable blockers | case total 3.50 s; highest child RSS 223,625,216 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportGlue` group, then Chez | 3/3 PASS; `t03/t04/t08 = false/true/false`; zero executable blockers | case total 7.57 s; highest child RSS 367,722,496 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportInt` group, then Chez | 2/2 PASS; `t05/t06 = pos 1/negsuc 0`; zero executable blockers | case total 12.02 s; highest child RSS 492,617,728 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportCoreB` group, then Chez | 2/2 PASS; Σ `(false,3)` and List `false/true/false`; zero executable blockers | case total 7.75 s; highest child RSS 307,953,664 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportBoundary` group | 2/2 dynamic EXPECTED-RESIDUAL; dual-layer `transpX-Vec`; manifest only, no Scheme/packet | case total 7.74 s; highest child RSS 311,574,528 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportHit` group, then Chez | 4/4 PASS; `pos 2/pos 1/41/true`; zero executable blockers | case total 13.25 s; highest child RSS 494,698,496 B |
| `make verify-formal-transport` | formal backend, exact-projected `TransportHigher` producers plus independent archived-v2 consumers | 4/4 dynamic file/pipe PASS; wrong consumer EXPECTED-REJECT; no Scheme or pipe packet file | positive case total 13.38 s; highest child RSS 431,783,936 B |
| `make verify-formal-transport-monolithic` | hash-pinned original `TransportTests`, formal backend and independent v2 consumers | 18 PASS; 2 EXPECTED-RESIDUAL; 1 EXPECTED-REJECT | prewarm 15.30 s / 548,552,704 B; 20 timed formal cases 11.55 s / 266,010,624 B |
| `make verify-formal-transport-differential-self` | differential comparator mechanics over projections plus monolith | 8/8 SELF-CHECK-PASS; not NbE evidence | under 1 s; resources not benchmarked |
| `make verify-formal-transport-production-candidate` | selected+linked production candidate over all seven projections plus original monolith, followed by the real oracle/candidate comparator | 8/8 groups and 42/42 summary rows DIFFERENTIAL-PASS; static values match; unsupported Boundary/Higher cases preserve checked typed residuals with effective `nbe`; no baseline normalization fallback | functional acceptance PASS; performance reported separately below |
| `make verify-formal-transport-production-performance` | historical engineering O0 three-run dataset | retained `ENGINEERING-PERFORMANCE-FAIL`; overall 74.27/74.24 s median, time ratio p95 1.0031, RSS ratio p95 1.0304; Higher/residual RSS ratio p95 1.303373 exceeds 1.30 | historical diagnostic result retained; superseded for release evaluation by the isolated O2 run below |
| `make verify-formal-transport-production-release-performance` | isolated GHC `-O2` binaries/objects/evidence, three alternating-order complete repetitions, host/allocation/stage/transaction gates | `ENGINEERING-PERFORMANCE-PASS`; overall 74.18/74.15 s median, time/RSS/allocation p95 1.016723/1.067052/0.999941; Higher RSS p95 1.194333 against 1.30 | controlled release gate PASS; 3,219 raw files transactionally published |
| `make verify-formal-transport-performance-host-self` | fixed machine/power/thermal/CPU-idle/memory-pressure evidence contract | 1 positive + missing field/wrong machine/battery/thermal/busy CPU/memory pressure 6 rejects PASS | all 48 release-run preflights PASS on AC Power |
| `make verify-formal-transport-performance-self` | end-to-end time/RSS/allocation/artifact/host/optimization comparator plus stage aggregation | O0 and O2 2 positives + elapsed/RSS/allocation/provenance/host/missing-process/missing-allocation/missing-run/wrong-optimization 9 rejects; stage 1 positive + 2 rejects PASS | synthetic contract evidence |
| `make verify-formal-transport-performance-publication-self` | result-specific transactional staging/archive/promotion contract | O0 PASS, O2 PASS, and terminal threshold FAIL 3 positives + result mismatch/incomplete stage/missing allocation summary/path escape 4 rejects PASS | every rejection preserves current evidence |
| `make verify-v2-runtime` | archived self-contained runtime suite | PASS | 1.17 s / 144,375,808 B |
| `make verify-v2-runtime` | archived full TransportTests runtime matrix | PASS | 22.25 s / 328,663,040 B |
| `make verify-official-targeted` | official `CubicalSucceed` | 1/1 PASS | 1.82 s / 1,190,969,344 B |
| `make verify-official-targeted` | official API Interface/Serialise subset | 3/3 PASS | 10.08 s / 1,196,015,616 B |
| `make verify-official-targeted` | Internal MAlonzo encoder properties | 3/3 PASS | 0.43 s / 67,649,536 B |
| `make verify-official-targeted` | MAlonzo_Lazy Cubical compilation negatives | 4/4 PASS | 1.32 s / 72,105,984 B |
| `make verify-official-targeted` | Internal TypeChecking properties | 11/11 PASS | 0.94 s / 68,976,640 B |
| `make verify-official-targeted` | conversion success regressions | 5/5 PASS | 0.90 s / 75,841,536 B |
| `make verify-official-targeted` | conversion golden failure regressions | 5/5 PASS | 0.85 s / 71,122,944 B |
| `make verify-official-compiler` | complete official Compiler group | 687/687 PASS | 307.75 s / 261,013,504 B |
| `make verify-official-suite-preflight` | exact upstream `make test` dependency inventory | 32/32 classified | 26 READY, 1 READY-ENV-COMPAT, 1 existing PASS, 1 existing ENV-COMPAT PASS, 2 blocked, 1 upstream-disabled |
| `make verify-official-suite-group` | official BuildFail group | 4/4 PASS | 0.52 s / 79,003,648 B |
| `make verify-official-suite-group` | official BuildSucceed group | 8/8 PASS | 0.57 s / 143,114,240 B |
| `make verify-official-suite-group` | official Succeed group | 2052/2052 PASS | 31.63 s / 3,549,872,128 B |
| `make verify-official-suite-group` | official Bugs group | 13 PASS; `Issue8182` ENVIRONMENT-GOLDEN-DIFFERENCE | canonical 0.44 s / 90,652,672 B; diagnostic 3.87 s / 3,556,114,432 B |
| `make verify-official-suite-group` | official Fail group | 1816 PASS; 3 internal-error goldens ENVIRONMENT-GOLDEN-DIFFERENCE | canonical 2.26 s / 93,863,936 B; diagnostic 19.23 s / 132,710,400 B |
| `make verify-official-suite-group` | official Interaction/simple group | 462/462 PASS-WITH-ENV-COMPAT | 12.47 s / 198,672,384 B |
| `make verify-official-suite-group` | official Interactive group | 3/3 PASS | 0.36 s / 82,591,744 B |
| `make verify-official-suite-group` | official Internal group | 538/538 PASS | 4.06 s / 74,170,368 B |
| `make verify-official-suite-group` | official UserManual group | 55/55 PASS | 1.66 s / 138,969,088 B |
| `make verify-official-suite-group` | official CubicalSucceed group | 1/1 PASS | 2.04 s / 1,202,733,056 B |
| `make verify-official-native-group` | upstream encoding and RecursiveDo source checks | 2/2 PASS | 1.21 s / 35,471,360 B |
| `make verify-official-native-group` | Common mini-library | 24/24 modules PASS | 1.88 s / 89,341,952 B |
| `make verify-official-native-group` | error/warning and user-manual coverage checks | 4/4 PASS | 3.22 s / 35,471,360 B |
| `make verify-official-native-group` | custom interaction goldens | 58 match; `Issue8634` ENVIRONMENT-GOLDEN-DIFFERENCE | canonical 0.88 s / 33,013,760 B; adapted full 28.81 s / 524,976,128 B; diagnostic remainder 31.83 s / 525,107,200 B |
| `make verify-official-native-group` | standard-library interaction goldens | 3/3 PASS-WITH-ENV-COMPAT | canonical missing-`gsed` 0.29 s / 33,046,528 B; adapted 12.02 s / 643,809,280 B |
| `make verify-official-native-group` | official examples | 44/44 PASS | 10.00 s / 211,501,056 B |
| `make verify-official-native-group` | external cubical library `--build-library` | 1192/1192 modules PASS | 342.97 s / 4,458,266,624 B |
| `make verify-official-native-group` | benchmark suite without retained logs | 18/18 PASS | 11.02 s / 326,516,736 B |
| `make verify-official-native-group` | complete pinned standard library | 1059/1059 `Everything` imports PASS | 105.84 s / 3,460,743,168 B |
| `make verify-official-native-group` | complete Haskell API target | 4/4 PASS | 12.35 s / 1,375,289,344 B |
| `make verify-official-native-group` | Haskell library doctests | 5/5 PASS-WITH-ENV-COMPAT | canonical 35.16 s / 1,357,856,768 B; adapted 65.44 s / 2,148,286,464 B |
| `make verify-official-suite-group` | MAlonzo `AllStdLib` compiler target | 1/1 PASS | target 64.43 s / 2,550,235,136 B; interface prep 98.22 s / 3,335,979,008 B |
| `make verify-official-suite-group` | JS `AllStdLibJS` compiler target | 1/1 PASS | 38.87 s / 2,368,667,648 B |
| `make verify-official-suite-group` | standard-library success regressions | 25/25 PASS | 25.73 s / 1,285,783,552 B |

## Official source and full-suite inventory

The stock identity gate compares stable tree hashes rather than trusting the
snapshot's reported commit string. Excluding generated files, empty submodule
contents, and the explicit v2 overlay, the complete 10,084-file projection and
the separate `src`, `test`, `doc`, and `mk` projections all match the official
commit archive. The nine-file overlay also passes its maintained SHA-256
manifest.

The full-suite preflight parses the upstream `test` aggregate and verifies its
exact 32-target order against a maintained inventory. With the exact
standard-library gitlink snapshot supplied separately and the doctest evidence
present, it reports 26 `READY`, one `READY-ENV-COMPAT`, one existing Compiler
`PASS`, one existing doctest `PASS-EXISTING-ENV-COMPAT`, two
`BLOCKED-ENVIRONMENT`, and one `SKIP-UPSTREAM-DISABLED`. The remaining blockers
are missing LaTeX and fix-whitespace tools. The listed `size-solver-test` rule
is commented out in this upstream commit.

The corresponding group runner reuses the source-hashed `-fdebug` binaries,
copies test inputs and Agda data files to an isolated workspace, applies a
per-test timeout, and records stdout, stderr, elapsed time, and peak RSS.
BuildFail passes 4/4 and BuildSucceed passes 8/8 without disabled cases. The
post-BuildSucceed stock identity rerun also passes, proving that generated
highlighting files no longer escape into the supplied source tree.

The complete Succeed group passes all 2,052 tests with the canonical upstream
regex, ten workers, and no exclusions or disabled cases. A subsequent stock
identity rerun passes, so this much larger group also leaves the supplied source
projection unchanged.

The canonical Bugs group has 14 tests. Thirteen pass in a transparent
diagnostic rerun that excludes only `all/Bugs/Issue8182$`. `Issue8182` differs
from its unchanged upstream golden solely by one final formatted `out >` line.
It is classified `ENVIRONMENT-GOLDEN-DIFFERENCE`, not a CubicalChez regression:
the case invokes the pinned stock Agda binary and no backend source. The
canonical `summary.tsv` remains `FAIL`; the diagnostic rerun is separately
labelled `PASS-WITH-EXCLUSION`, so it cannot be mistaken for a full-group pass.

The canonical Fail group first stops at `Impossible` with the same additional
final formatted `out >` line. The pinned group contains exactly three golden
cases that deliberately trigger this internal-error printer: `Impossible`,
`ImpossibleVerbose`, and `ImpossibleVerboseReduceM`. A diagnostic rerun records
the exact exclusion regex and passes all other 1,816 tests. These three cases
are classified in the same `ENVIRONMENT-GOLDEN-DIFFERENCE` bucket; upstream
goldens remain untouched, the canonical summary remains `FAIL`, and the
diagnostic summary remains `PASS-WITH-EXCLUSION`.

The canonical Interaction/simple run exposes two host portability assumptions
in the upstream test harness. Its script expander uses GNU basic-regexp `\+`,
which BSD sed does not implement, and the official archive contains both
`test/Interaction` and `test/interaction`, which collapse into one preserved-
case directory on the host's case-insensitive filesystem. A temporary-workspace
compatibility mode translates only `\+` to portable BRE interval syntax and
renames the merged runtime directory to lowercase. With no test exclusion and
no golden modification, all 462 tests pass. The canonical environment result
remains `FAIL`; the adapted result is separately labelled
`PASS-WITH-ENV-COMPAT`.

The separate Interactive group passes 3/3 and the complete Internal group
passes 538/538, both with the canonical regex and no exclusions or disabled
cases. The Internal count includes the full property inventory rather than only
the previously targeted MAlonzo and TypeChecking subsets.

The UserManual group passes all 55 embedded examples. CubicalSucceed also
passes 1/1 through the unified full-suite group runner using the supplied
cubical snapshot, confirming the earlier targeted result under the common
source-identity, isolation, timeout, and evidence protocol.

The separate `std-lib-compiler` group follows the upstream
`--regex-include AllStdLib --regex-exclude AllStdLibJS` target. Its isolated
prerequisite phase regenerates the 1,059-import `Everything.agda` and prepares
exactly 1,091 dependency interfaces; as in the upstream std-lib check, the
command-line entry itself has no interface. The sole MAlonzo Lazy test then
compiles and executes `AllStdLib`, and its complete runtime output matches the
unchanged upstream golden. It passes 1/1 with zero disabled cases in 64.43
seconds and peaks at 2,550,235,136 bytes. Its isolated interface prerequisite
takes 98.22 seconds and peaks at 3,335,979,008 bytes. The supplied 1,408-file
std-lib tree has the same manifest before and after the run and retains zero
`.agdai` files.

The distinct `std-lib-js-compiler` group follows the upstream
`--regex-include AllStdLibJS` target. The selected source intentionally has no
`Everything` import and uses `--no-main`; the JS MinifiedOptimized backend
compiles its exact std-lib dependency closure and Node 24.13.0 executes the
result with the expected empty output and successful exit. The sole test passes
1/1 with zero disabled cases in 38.87 seconds and peaks at 2,368,667,648 bytes.
The supplied 1,408-file std-lib manifest remains identical and free of
`.agdai` files.

The `std-lib-succeed` group runs the canonical `all/LibSucceed` selection with
four workers. Its recursive source inventory contains 32 Agda files and the
official driver selects 25 tests with no disabled cases. All 25 pass in 25.73
seconds with peak RSS 1,285,783,552 bytes. The run produces exactly the 30
reachable input interfaces and 258 std-lib dependency interfaces; `Issue1382`
and `Issue846` are successful `--allow-unsolved-metas` command-line entries and
intentionally have no interface. The normalized 30-file interface set matches
the maintained source-derived expectation exactly. The supplied std-lib tree
remains unchanged and contains no `.agdai` files.

## Official Makefile-native groups

The native runner copies the upstream Makefile plus `mk`, `src`, `test`, and `doc`
trees into a disposable workspace and invokes the original targets with the
same source-identity gate and cached stock Agda binary. The combined
`check-encoding`/`check-mdo` group passes 2/2, confirming that `Parser.y` is
ASCII and that the source tree does not use the `RecursiveDo` extension. The
upstream `common` target then typechecks all 24 modules in the Common
mini-library. The four coverage targets also pass: the test suite covers every
declared error and warning, and the user manual mentions every command-line
option and warning.

The `interaction-custom` target inventories 59 golden tests. Its canonical
Darwin run stops before comparison because upstream `mk/common.mk` requires
`gsed`. The isolated compatibility run supplies only the needed GNU BRE
semantics, pins both `runghc` and compiler subprocesses to GHC 9.6.7, and adds
a zero-diff assertion because the upstream interactive Makefile otherwise
returns success after keeping a mismatched golden at EOF. Fifty-eight goldens
match exactly. `Issue8634` has identical warning text, warning kind, and URL,
but its four annotation ranges are uniformly shifted by 112 because they were
calculated before the absolute disposable-workspace prefix was filtered. It is
classified `ENVIRONMENT-GOLDEN-DIFFERENCE`; the canonical/adapted full result
remains FAIL, while the exact diagnostic exclusion passes the remaining 58/58
as `PASS-WITH-ENV-COMPAT-AND-EXCLUSION`. No upstream golden is modified, and no
`.agdai` or highlighting output is written to the supplied tree.

The `std-lib-interaction` target has three complete `.agda`/`.in`/`.out`
triples: `ClashingDefinition`, `EqReasoning`, and `Issue2066`. Its canonical
Darwin run is retained as `ENVIRONMENT-MISSING-TOOL` because upstream selects
`gsed`. With the same minimal GNU-BRE compatibility wrapper used by the custom
interaction target, all 3/3 goldens match with no exclusions or modified
outputs. The adapted run takes 12.02 seconds, peaks at 643,809,280 bytes,
leaves zero temporary files and zero input interfaces, and creates 121 std-lib
dependency interfaces only in the disposable copy. The supplied 1,408-file
manifest matches before and after and remains free of `.agdai` files.

The upstream `examples` target expands to 20 top-level Make prerequisites;
replacing `other-examples` with its 25 concrete file targets yields 44 leaf
checks. The runner stores that inventory and requires exactly 44 corresponding
`Testing` records in stdout. All 44 pass. This covers the ordinary examples,
HTML output in default/custom directories, malformed-interface recovery,
relocatable interfaces, already-imported-module freshness, highlighting, and
two successful MAlonzo compile-and-run passes. The latter are explicitly
counted and use the locked GHC 9.6.7 executable. All generated interfaces,
HTML, copied sources, and compiler output remain in the disposable workspace.

The upstream `cubical-test` target delegates to the supplied cubical
library's canonical `agda -j --build-library` check. The runner inventories
exactly 1,192 `.agda` inputs, copies the complete library into the disposable
workspace, and requires exactly 1,192 generated `.agdai` interfaces after a
successful run. All 1,192 modules pass in 342.97 seconds with peak RSS
4,458,266,624 bytes. The maintained input-manifest digest is
`596ad446da61025b5b0474dca67349cd5c3f3cdc4684e1976a491cd4d8bc4dcb`;
the before/after manifests match, the supplied tree retains zero `.agdai`
files, and the subsequent Agda stock/overlay identity gate passes.

The `benchmark-without-logs` target contains 18 cases: category, AC,
Syntacticosmos, CwF, standard-library-backed parser monad, miscellaneous, and
projection benchmarks. The standard-library dependency is fixed to parent
gitlink commit `9a543dc8eb1abce4853c356de35c870d66a27984`; its 1,408-file
manifest passes the maintained digest before and after execution. All 18
benchmarks run and their profiling output is parsed by upstream
`Benchmark.hs`; the target removes its timestamped logs, and the runner
confirms zero residual log files. The final verification run passes in 11.02
seconds with peak RSS 326,516,736 bytes, and the subsequent stock identity gate
passes.

The upstream `std-lib-test` first builds and runs the library's own
`GenerateEverything` executable, then typechecks the generated aggregate with
`--ignore-interfaces --no-default-libraries`. The fixed source inventory has
1,182 Agda modules. Generation produces exactly 1,059 direct imports in
`Everything.agda` and 952 in `EverythingSafe.agda`; the clean typecheck writes
1,091 dependency interfaces. Agda intentionally does not write an interface
for the command-line entry module in this mode, so the entry-interface count
is fixed at zero rather than misclassified as incomplete output. All 1,059
aggregate imports pass in 105.84 seconds with peak RSS 3,460,743,168 bytes.
The 1,408-file external std-lib manifest matches before and after execution,
the supplied tree retains zero `.agdai`, and the subsequent Agda stock/overlay
identity gate passes.

The complete `api-test` target runs `Issue1168.api`, `PrettyInterface.api`,
`PrintImports.run`, and `ScopeFromInterface.api`. All four compile with
`-Wall -Werror` against the locked fdebug Agda 2.9 package and execute
successfully. The runner requires four compiler invocations, three `.api`
completion markers, and the eight import records parsed by `PrintImports` from
the exact std-lib gitlink input. The upstream Makefile treats the three
`.agdai` files as intermediate products and removes them after the dependent
`.api` markers are complete; the post-run interface count is therefore fixed
at zero. The group passes in 12.35 seconds with peak RSS 1,375,289,344 bytes.
The external std-lib manifest matches before and after, its supplied tree
retains zero `.agdai`, and the subsequent Agda stock identity gate passes.

The `doc-test` target installs `doctest 0.25.0` for the locked GHC 9.6.7 and
runs the original `cabal repl Agda -w doctest --repl-options=-w` path. The
runner inventories the only three modules containing examples—`Agda.Utils.List`,
`Agda.Utils.List1`, and `Agda.Utils.String`—and fixes all five `>>>` directives.
The canonical GHC 9.6 run stops before assertions because Agda's `-Werror`
promotes the interpreter's optimization warning; it remains recorded as
`ENVIRONMENT-GHC-REPL-CONFIG`. In the separately labelled compatibility run,
`-O0 -Wwarn` restores the upstream warning-suppression intent and all five
examples are tried with zero errors and zero failures. That run takes 65.44
seconds and peaks at 2,148,286,464 bytes. The executable, package store, and
project build are disposable; only inventories, versions, logs, counts, and
resource evidence remain.

Evidence:

- `build/agda29/official-native/source-checks/`
- `build/agda29/official-native/common/`
- `build/agda29/official-native/coverage-checks/`
- `build/agda29/official-native/interaction-custom/`
- `build/agda29/official-native/std-lib-interaction/`
- `build/agda29/official-native/examples/`
- `build/agda29/official-native/cubical-test/`
- `build/agda29/official-native/benchmark-without-logs/`
- `build/agda29/official-native/std-lib-test/`
- `build/agda29/official-native/api-test/`
- `build/agda29/official-native/doc-test/`

Evidence:

- `build/agda29/stock-baseline/`
- `build/agda29/official-suite-preflight/`
- `build/agda29/official-suite/build-fail/`
- `build/agda29/official-suite/build-succeed/`
- `build/agda29/official-suite/succeed/`
- `build/agda29/official-suite/bugs/`
- `build/agda29/official-suite/fail/`
- `build/agda29/official-suite/interaction-simple/`
- `build/agda29/official-suite/interactive/`
- `build/agda29/official-suite/internal/`
- `build/agda29/official-suite/user-manual/`
- `build/agda29/official-suite/cubical-succeed/`
- `build/agda29/official-suite/std-lib-compiler/`
- `build/agda29/official-suite/std-lib-js-compiler/`
- `build/agda29/official-suite/std-lib-succeed/`

## TransportTests details

The stock Agda gate first typechecks independent t01-t16 shards and then the
exact hash-pinned monolithic source. The unchanged archived v2 runtime script
then reports:

- t01-t10 and t12-t15: `MATCH`;
- t11 and t11b: `EXPECTED-RESIDUAL` on `transpX-Vec`;
- p16a/c16a, p16b/c16b and p16c/c16c pipe checks: expected first-order values;
- p16a/c16a file packet: `true`;
- p16a/c16b: `EXPECTED-REJECT` due to unequal types.

These are stock/oracle and archived-v2 baselines. By themselves they do not
close formal-backend entries; the exact-projection gates below now separately
close all `t01`-`t16` functional classifications.

The current formal backend now closes `t01`, `t02`, and `t07` through
`make verify-formal-transport`. The gate verifies both the original
source hash and the maintained `TransportBase.agda` hash, mechanically extracts
each complete definition through final `_ = refl` block from both files, and
requires byte identity. The `t01`, `t02`, and `t07` fragment SHA-256 values are
respectively `fecdea78bbe99de8a9d3b2c610709c1e72743ef8b97d634cbc07114989c3b800`,
`ba69d96a7268e24a6d627b8b6b87e0a3acbbcfd4999ecdc91f2fef602067d037`,
and `f44f5ce3bcfec1b6d0c0ecea68b198943fa426bc8d206206b1a2e17573e33e3d`.
It selects each qualified entry independently, requires literal Treeless
read-back `7`, `7`, and `4`, executes Chez for the same values, and requires
zero Internal-term or Treeless blockers and no typed/Cubical runtime artifact.

The same target also closes `t03`, `t04`, and `t08` through the independently
hash-pinned `TransportGlue.agda` projection. Their exact fragment SHA-256 values
are `4ea584b01209595514b5410b463ad80be2ad5eb8353f7845ea8bda3c4ab2fce6`,
`7b2d2e0dfd02b65214be73817db4a315f727170dc8e10a4c70555825f63b2db6`,
and `1a4b76633b78c074e92135f4c779a005f5ce9c3fdef43ac80db5f0ec673e6af2`.
Treeless read-back produces the canonical built-in Bool constructors
`false`, `true`, and `false`; Chez produces the corresponding constructor
vectors. This covers ua/not transport, the composite HCompU/Glue path, and the
Pi+Glue mixed case without retaining a Cubical runtime.

The Int group closes `t05` and `t06` through `TransportInt.agda`. Their exact
fragment SHA-256 values are
`1bd8c1336103775d452558bf42e3b5195c42edc0d5eb43091436a5bcfedb242b`
and `7e5eff544f039ad53129633aab5d03abcf2152fe0f5397795bcd515303da1b28`.
Treeless and Chez both retain the constructor tags and Nat arguments, producing
`Cubical.Data.Int.Base.ℤ.pos 1` and `ℤ.negsuc 0`. This checks both directions of
the `sucEq` Glue transport and the parameterized data-constructor ABI.

The Core group closes `t09` and `t10` through `TransportCoreB.agda`. Their
exact fragment SHA-256 values are
`3e06340fc82d0dc077e0bc476649985a3c296ec710a83f12d25a0af68b5db4e9`
and `8307023c9f72b043e4538a883069975378befbdf594cbdc83ef3c45b4077836e`.
The first reads back the Σ record `(false, 3)` using
`Agda.Builtin.Sigma._,_`; the second reads back the complete built-in List
spine `false ∷ true ∷ false ∷ []`. Chez output preserves every nested
constructor tag and field.

The Boundary group closes the special harness classification for `t11` and
`t11b` through `TransportBoundary.agda`. Their definition-only fragment hashes
are `6f50f503096acb98c33667b11bce59a1565e7f3625602924beb1183ed354da30`
and `26d8875a65f7ea8bccbc374daae934659f03319e456e88484ac78b18af645392`.
Both normalizations terminate and retain
`Cubical.Data.Vec.Base.transpX-Vec` in the Internal and Treeless audits. The
backend exits nonzero by policy, records `decision: typed-residual`, writes a
manifest-only diagnostic, and emits neither `program.ss` nor a binary packet.

The Hit group closes `t12`-`t15` through `TransportHit.agda`. The exact
definition/proof fragment hashes are
`5e8bae5d57ab5253be39335e229138c942e9f5b2ab2377e8b3f681f48ccf48b4`,
`8a94cbfa5423c6d7953e2955a8a672649c36bddb313cbdd4b06e74c848e0a293`,
`68b10cf5b938324374cfd21a2919a1da031d46780f2d2c3e7df968440890abb4`,
and `78a63841883a9c8e718b2aa8d9a940ad97b693b2627badd34b62485f78447cd1`.
Treeless and Chez agree on `ℤ.pos 2`, `ℤ.pos 1`, Nat literal `41`, and built-in
Bool `true`; all four entries are static-closed with zero blockers.

The Higher group closes the `t16` process boundary through
`TransportHigher.agda`. Its full projection hash is
`c7a1a45e12712c747746821230e3382de089916ba5a79e8c429f05dbbe7826aa`.
The mechanically extracted `p16a`, `p16b`, `p16c`, `c16a`, `c16b`, and `c16c`
definition hashes are respectively
`ba431e84122f768cb2be58eaeb5cacd1cbe531ea2d38d8d748f0f67b96fde41b`,
`243a2b59ffbe766fe4caa27c2cccf14f48d5c7a421095deec5fa8ed6015fa343`,
`18f001d7e069fa7c1d9287d3fdcdca531f55b73879253c39996120b7629644a2`,
`d3d3c51917d14a60f7937c7baff1a5701fd222804d74836a94142d71d1c2bc90`,
`dc9ef41dafb738f304d36d1f52c4ba88443bb3d2fe06c036b06200b8741e44da`,
and `802e787f8a9cb870945b4d86dd6627cfb598a68f2beb517e1654f66495241e55`.
The backend classifies each producer as a typed residual, self-validates its v2
packet, and sends it to an independently built archived consumer. `p16a/c16a`
returns `true` by file and direct pipe, while `p16b/c16b` and `p16c/c16c`
return `pos 2` by direct pipe. `p16a/c16b` is rejected before application with
`UnequalTypes`. The retained fil…6785 tokens truncated…oundary transformations are
canonical Glue paths with matching closed intermediate types. It returns
`pos 2`, and observed/Treeless/Scheme are baseline-equal. Staging reports HIT
definition patterns=4, comp expansions=4, universe transports=12,
direct/composed Glue transports=1/1, and endpoint hcomps=38. The non-canonical
`winding (λ i → loop (i ∨ ~ i))` control rejects with zero publication.

The gate then exercises `t13`. Its right boundary is itself a nested HCompU
shell, so the same endpoint-specialized recursive checker decomposes it into
direction-tagged canonical Glue steps. The final reverse step uses the checked
isomorphism inverse and dual forward round-trip validation, producing `pos 1`
without applying a forward map in the wrong direction. The original/projection
block is byte-identical and observed/Treeless/Scheme remain baseline-equal.
Staging reports definition patterns=3, comp expansions=3, universe
transports=11, direct/backward/composed Glue transports=1/1/1, and endpoint
hcomps=16. Reversing the non-canonical `i ∨ ~i` winding control is rejected
with zero publication.

The gate next exercises `t14`. Ordinary definition evaluation
unfolds Prelude `J` to transport; `refl` and the constant Nat motive let the
existing exact-Nat rule return 41. The original/projection block is
byte-identical and observed/Treeless/Scheme are baseline-equal. Staging reports
two definition reductions, one primitive registry hit/reduction, four path
applications, and transport/constant-Nat counters `1/1`. A J over a
non-canonical universe loop rejects with zero publication, so this is not a
general J implementation.

The same gate reuses the canonical Glue rule twice for `t15`. The inner
transport maps `true` to `false`; eager argument evaluation feeds that result
to the outer transport, which maps it back to `true`. Its original/projection
block is also byte-identical and observed/Treeless/Scheme remain baseline-equal.
Staging reports eight path applications and transport/Glue counters `2/2`,
with backward/composed/Pi/record/data transport counters all zero. A control
with the same canonical inner transport and a non-canonical outer family is
rejected with zero publication. Beyond the guarded `t12/t13` shell, general S¹/HIT
semantics remain unsupported. The generic Cubical primitive rejection control
now uses unregistered `PrimFaceForall`, with its exact primitive ID, QName, and
HCompU builtin source range.
An applied postulate reports `CCZ-NBE-UNSUPPORTED`, and a fault-injected invalid
record receiver reports the same stable class. An injected `DefS` also reports
that class with `postulated-sort-policy=reject-v1`. A repeated ground call
reports `CCZ-NBE-FAILED`, the low-fuel build reports `CCZ-ENGINE-TIMEOUT`, and
the default binary still reports `CCZ-NBE-UNAVAILABLE`. The spike staging is visibly
`nbe-spike-test-only`, says term normalization uses environment/closure
evaluation plus level readback, and says type normalization uses the independent
semantic Type/Sort/Level path. Evidence is in `build/nbe-adapter-spike/summary.tsv` and the
pinned 2.9 replay is in
`build/agda29/evidence/NbeAdapterSpike/adapter-spike.tsv`; its cycle and
fuel evidence is in `adapter-spike-rejections.tsv` beside it.

The local twenty-three-case summary is 1,894 bytes with SHA-256
`9a1bf0769ec906ad38a7097f3c75f2f30555c6c23bcbbffa43415a6306a948c9`.
The pinned 2.9 positive TSV is 731 bytes with SHA-256
`73dbfedbb38640154dca738a462a24f36adf159c679e8c9a2cd21521876630cc`;
the rejection TSV is 384 bytes with SHA-256
`ddea0fdd9d8b95e177e6341958d477fe2fb01e4318c11fd4fe019839ee2107b8`.

The separate exact-source gate pins the original and projection hashes,
requires byte-identical `t01/t02/t07` blocks, and compares observed output,
Treeless, and Scheme under Agda 2.9. They return 7/7/4 and are byte-identical.
`t02` records one closure-only path application, one transport, and one exact
Nat-family transport; `t07` records one exact Nat-function transport before
applying `suc`. Its 194-byte summary has SHA-256
`df243c22a2371c496a428ed3e4b6763d8386c405cf8ed4f016a90015c5592d8f`.
The effective engine remains `nbe-spike-test-only`, not production `nbe`.

The exact Glue gate's 642-byte summary has SHA-256
`0c4bf74ea554816e2ba371ebe62720b6e856ab1be26e7b286952260eaa9c3d7e`.
Its executable gate script is 13,256 bytes with SHA-256
`f1342898ca137022f681424dfbd7be6014c04f9563a2fcb03ba3c7c73d591fa1`;
the shared final adapter source is recorded with the Hit gate below.
The maintained Glue fixture is 3,184 bytes with SHA-256
`a5fe68b3bf7ed4c4c384f076789e06c8c9c08e201072890a7d09ea4891cd8502`.

The exact Int gate's 258-byte summary has SHA-256
`257b75010c1ba6854e3a994b51128cc62a09df40c5080b1d9307744be7c4b73f`.
Its executable gate script is 7,551 bytes with SHA-256
`c2ce537c1ff8fe855032d0762a60f276c3facbe259cb49a957aca7dae43dca31`;
the maintained Int fixture is 1,104 bytes with SHA-256
`e3e03fb8fbd98f1f6f2c1e8467797815e80d4fdaa2f1684399793761f0ad6aab`.
The shared final adapter source is recorded with the Core gate below.

The exact Core gate's 353-byte summary has SHA-256
`a171cf7838bed248338f47c614576d2d4f7c60f4b52c6e45906595d10d237bc6`.
Its executable gate script is 8,175 bytes with SHA-256
`b1785947094f1e23bfc07ecfa375b39a26954623f76859f799b7fd3b8f2df034`;
the maintained Core fixture is 1,421 bytes with SHA-256
`e7d5339ff03e7153baf8b26a2178c8dc4c198b18144721e3a562a8153493c105`.
The adapter source used by the final Glue/Int/Core/Hit-t12-through-t15 runs is
recorded with the Hit gate below.

The exact Hit gate's 608-byte summary has SHA-256
`6b3e5ac4694697b0efc84c4a3e4dd8b4102274fdbc33202062f0069e26be5ad5`.
Its executable gate script is 13,018 bytes with SHA-256
`9f4fff6d2e79e9c7853f6eba2848c1de4de56f967a9d655af6e814268cfe6a40`;
the 881-byte non-canonical J control has SHA-256
`b5dbdee45a6123500ba1b9b659b445694d6783645e62b869637a725dbc423f01`,
and the 942-byte repeated-transport control has SHA-256
`1679b66385b33d404d4bac01b540028bb037bf2ff3e8bc4bc17496257d59488d`.
The 892-byte non-canonical S¹ winding/inverse control has SHA-256
`3a65b3d9989798cd78e1ba2c30aa168e3dead092d54d92b29c1fbee712efd497`.
The shared adapter source is 112,721 bytes with SHA-256
`3a01e33cca0ee234e81fefe0bed02d10754437b72a5ca123587b1ecc2c1325a9`.
The unchanged maintained Hit projection is 1,221 bytes with SHA-256
`5939b8dace09ce5656660efda7f6afad76b05b3ebcc3b82c0de0a456c81f7a51`;
its 91-byte `t12`, 102-byte `t13`, 100-byte `t14`, and 109-byte `t15` fragments
have SHA-256
`5e8bae5d57ab5253be39335e229138c942e9f5b2ab2377e8b3f681f48ccf48b4`,
`8a94cbfa5423c6d7953e2955a8a672649c36bddb313cbdd4b06e74c848e0a293`,
`68b10cf5b938324374cfd21a2919a1da031d46780f2d2c3e7df968440890abb4`, and
`78a63841883a9c8e718b2aa8d9a940ad97b693b2627badd34b62485f78447cd1`.

`make verify-nbe-adapter-contract` passes seven schema cases. The
checked-in `unselected` record and a complete synthetic `selected` record pass.
Floating revisions, unknown fields, duplicate fields, and an unselected record
containing partial provider metadata, plus a selected record claiming
`NOASSERTION`, are all `EXPECTED-REJECT`. Evidence is in
`build/nbe-adapter-contract/summary.tsv`.

The contract is also a prerequisite of `make verify`; after adding
it, the nine backend smoke cases still pass. `NbeUnconfigured` confirms the
second enablement key remains absent: provider metadata alone cannot link or
enable an adapter. That negative pre-seeds old Scheme, Treeless, staging,
manifest, and packet files and proves all five are removed before the early
engine rejection, so no stale executable can masquerade as new NbE output.

## Engine-result admission contract

`make verify-engine-result-gate` passes one valid result and three
compile-time-only fault variants. `StaticOrdinary` is accepted, Chez prints
`42`, and staging records `engine-result-closed`, `engine-result-meta-free`, and
`engine-result-agda-checked` as true. An injected free variable, unresolved
`MetaV`, and string literal returned at `Nat` are independently
`EXPECTED-REJECT`; each case pre-seeds five publication artifacts and proves
none survives. Evidence is in `build/engine-result-gate/summary.tsv`.

The same implementation compiles against the pinned Agda 2.9 tree. A 2.9
ordinary positive prints `42`; reruns of the exact-projected Base cases
`t01/t02/t07` remain 3/3 PASS, while typed Boundary cases `t11/t11b` remain 2/2
`EXPECTED-RESIDUAL` after the new check. This is admission-gate evidence, not a
claim that a mature NbE adapter has been selected or differentially accepted.

## Four-way binding-time contract

`make verify-binding-time` passes five end-to-end cases. An ordinary
Nat result is `static` and emits Chez. A lambda headed by `primTransp` is
`dynamic` and becomes a whole-entry typed residual. `MixedResidual` retains a
static Sigma constructor around that dynamic function, reports `mixed`, and
explicitly records
`typed-residual-split-shell-ground-observation-by-id-whole-entry-reference`. A test-only
Treeless audit omission produces `unsupported`. A second test-only producer
removes the Agda registry evidence while retaining the pinned spellings;
`primTransp` is then rejected with reason
`internal-semantic-catalog-disagreement`. Both negative cases publish zero
Scheme, manifest, or packet. Evidence is in
`build/binding-time-contract/summary.tsv`.

The pinned Agda 2.9 Base rerun publishes three `static` rows, Boundary publishes
two `dynamic` rows, and Higher publishes five `dynamic` rows in their respective
`binding-time.tsv` files while retaining the prior functional outcomes. The
differential self-check remains 8/8. Separate negative controls reject an
independent candidate missing `binding-time.tsv` and a mutation from `static`
to `mixed`. Legacy oracle groups may use deterministic status migration;
independent NbE candidates may not.

## Typed residual dependency closure, hole materialization, and shell composition

`make verify-typed-residual-contract` passes three expected
residuals, one deterministic replay, and six expected rejections (10/10). The
dynamic `PacketResidual` records
four direct/resolved signature leaves; `MixedResidual` records eight. The
two-hop `ResidualDependencyClosure` fixture directly names eight QNames, then
producer traversal resolves nine nodes and expands two ordinary definitions:
`hiddenValue` and its type dependency `Alias`. A `DISPLAY` form also names
`presentationOnly`; `checked-type+definition-body-v1` records that single name
as excluded presentation metadata while keeping the resolved closure at nine
nodes. All manifests fix the
`whole-entry-same-interface-v1` payload, scope, signature identity, dependency
closure source, zero embedded definitions, and zero embedded whole signature.
For the mixed fixture, the planner identifies one maximal blocker-headed
Treeless subtree at `app-argument-1`, assigns the stable ID
`typed-hole@app-argument-1`, proves that it covers the audited `primTransp`
inventory, and uniquely matches it to the closed `Residual` lambda and expected
type observed by Agda's Internal rechecker. The hole repeats closed/meta/type
validation and resolves four direct/resolved dependencies: `I`, `i0`, `i1`,
and `primTransp`. A second compilation produces byte-identical
`residual-slice-*` lines. Manifest-only policy records the checked pair without
a binary artifact, validates static-shell lowering, and keeps execution
whole-entry.

One fault variant replaces the derived direct inventory; another simulates a
missing ordinary signature dependency; a third restores the former broad
`NamesIn Definition` traversal and proves presentation metadata cannot enter
the executable slice; a fourth forces a mixed plan with no holes; a fifth
removes all checked Internal candidates so the Treeless hole has no typed
match. A sixth removes the shell import inventory; it returns
`CCZ-SCHEME-LOWERING-FAILED`. Every fault rejects before a manifest, packet,
static shell, or Scheme program is published. Evidence is in
`build/typed-residual-contract/summary.tsv`.

The pinned Agda 2.9 packet retains the same 3,194-byte payload and SHA-256
`f43788742c9c26fcec355ae00ba2f319c25e980f22884de7ccb0c5afce2a0c13`.
Its independent consumer still returns `true`; module/hash mismatch proves the
dependency closure cannot be resolved from another signature, and the producer
inventory-mismatch negative fails before packet publication. A second Agda 2.9
positive builds `MixedResidual`, validates/materializes its one-hole plan, and
lets the archived consumer observe the whole-entry static Bool field as `true`.
It also emits a separately self-validated 3,270-byte
`typed-residual-hole-1.bin` with SHA-256
`b81fe22cb3852ce2fca8436f462da97c74947001cfcc0e7bb67fcc2684513549`;
the independent `consumeHole` process executes that payload and returns `true`.
The producer also emits a 74,163-byte `residual-static-shell.ss` with SHA-256
`b17fcf406a9c8e5abf8fac18a306772d9eac123dc0dab30f3827d8d3f0fb070d`
and a 5,864-byte `typed-hole-ground-bridge.sh` with SHA-256
`b2c02930b735267e2554bf5cfb0bb686bbc626ab32a511d8f6004d3dd5469d5c`.
Chez first constructs the Sigma shell containing the static `true` constructor
and exactly one `opaque-import-v1` descriptor; the shell contains no
`primTransp`. It then forces that descriptor through the actual v2 runner:
`consumeHole` decodes to the Chez Bool `true` constructor and
`consumeHoleNat` decodes to `42`. Missing configuration, runner exit 1, and
dirty output are three additional nonzero expected rejections. The helper
accepts one Bool/Nat line, emits one versioned response, and the shell validates
both response framing and helper exit status. The whole-entry packet remains
the semantic equivalence reference.

`MixedOpenResidual` places a blocker-headed `Residual` under a lambda where it
is open in one Bool. The Internal observation action captures that checked
telescope and publishes `λ captured → ... : Bool → Residual`; the source is
recorded open, environment arity is `1`, and the 5,330-byte packet is closed,
meta-free, and independently rechecked. Its SHA-256 is
`4ae37847f48bb0a87a5772ba1293a8b1ab1557679e2e331d79d21818d3c08140`.
The 7,407-byte whole-entry reference has SHA-256
`a452c220fca18e54309a673ec0acc933e79379475926aa964b44b1b1642827f3`.
The pre-registered 74,309-byte shell has SHA-256
`191b898e33a57efa67057e1b87b7fbda7a98cf2f5577a42391312130500cefb7`.
The whole consumer, independent closure consumer, ID-addressed force, and
explicit Bool-environment call all return `true`. Omitting the environment is
rejected by the v2 domain gate; choosing the Nat environment codec is rejected
locally. The shell additionally replaces the hole occurrence with a
`single-bool-chez-lexical-binding-v1` handle. Invoking the erased entry with
Chez Agda Bool `true` and `false` produces the corresponding typed result
after Agda replay; invalid input and a missing binding reject locally. This
proves one-slot automatic lexical capture without erasing the residual value.

`MixedOpenNatResidual` proves the parallel bounded-Nat slot. Its 8,045-byte
whole-entry reference has SHA-256
`7dbd89590c0ec193806bb4a4c140c798fed0524f4af9e7eaa436290dd28d997f`;
the closed 5,352-byte `Nat → Residual` hole packet has SHA-256
`7f6f29b06bfec5f95892838ccf78df814f68da94fbd031848db9088cb40ead7f`.
The 74,316-byte shell has SHA-256
`231745d474afe1aa9e4d88dd4e66cf01bc4e67c2c6ba0cf729a463b27a410ebe`.
Whole/direct consumption and explicit Nat application pass. Automatic Chez
values `0` and `1` select different transport inputs and return typed
`true` and `false`; negative/overflow input, missing binding, incomplete
configuration, and mode conflict reject under the environment namespace.

`MixedOpenWord64Residual` proves the bounded-Word64 single-slot path. Its
8,425-byte whole-entry reference has SHA-256
`15e46d4d9c68b52ed0a0bfde4976174421504ae38a4007282f6425af2b99dcef`;
the closed 5,776-byte `Word64 → Residual` hole packet has SHA-256
`925a6003fe20742d3ee3fa4983c007ec3e1e1b6d646c5294c2c17c7a529510df`.
The 83,132-byte shell has SHA-256
`6b80f112312659fe375513bab7a542c69f7e1179524b28371ca531685e57184c`;
its 5,864-byte bridge has SHA-256
`b2c02930b735267e2554bf5cfb0bb686bbc626ab32a511d8f6004d3dd5469d5c`.
Whole/direct consumption and explicit maximum-value application pass.
Automatic Chez values `0` and `18446744073709551615` select different
transport inputs and return typed `true` and `false`; negative/overflow input,
Nat-codec substitution, missing binding, incomplete configuration, and mode
conflict reject under `CCZ-TYPED-BRIDGE-ENVIRONMENT`. The 119-byte result TSV
has SHA-256
`50da7cd80a204bf1244f8e9967e5c0ff7c7b0dfb05721b3dde59fb6215f23e65`.

`MixedOpenGroundResidual` proves ordered non-dependent multi-slot capture. Its
8,348-byte whole-entry reference has SHA-256
`9e927a8f803883dea3c8a5bb14eae3382fb64cf4897b00a6b72819f58733c519`;
the closed 6,255-byte `Bool → Nat → Residual` hole packet has SHA-256
`2e6763bd168f352e268ec1452cda00cd997cfec0253e8255ac45f005b866135f`.
The 74,431-byte shell has SHA-256
`3cbcbd3edeac5687cbc7221bb4a617ff7d436f126c9d8ee2ffcfd22abd473843`.
The manifest derives `ordered-bool+nat-ground-environment-elimination-v1`
from the first two checked Pi domains; the shell binds `(v0,v1)` in that Agda
telescope order. Automatic `true/0`, `true/1`, and `false/0` replay returns
typed `true/false/false`. Swapped, missing, extra, wrong-codec, duplicate-selector,
and overflow configurations add six environment-namespace rejections.

`MixedOpenWord64GroundResidual` extends the non-dependent ordered contract to
the checked `Bool → Word64 → Residual` packet. Its 8,307-byte whole-entry
reference, 6,558-byte hole packet, and 76,991-byte shell have SHA-256
`b9bceb1af4dd5a6e034f9bb7dbe60b6abc57fe5b89ec3dcce7dec9d5d7124002`,
`640276a9d956a9d043ecdf97c779b4108b73c5f916224d19f866c85af72fdf3f`,
and `6d935ca983c4bb91adf2b432ecaa9eacdc7d3c9180dce168f7a927b9361da392`.
Whole-entry and independent-hole consumers pass; lexical `word64:0`/`word64:1`
return typed `true`/`false`, and explicit `bool:true,word64:0` returns `true`.
The runtime reifies Word64 as `Agda.Builtin.Word.primWord64FromNat N` and
checks the manifest codec vector before forcing. Nat-for-Word64 mismatch and
the overflow value `18446744073709551616` reject in both lexical and explicit
paths, adding five positive executions and four expected rejections.

`MixedOpenDependentResidual` covers a ground-indexed dependent telescope with
`Slot true = Nat` and `Slot false = Bool`. Its 8,004-byte whole-entry packet,
5,911-byte hole packet, and 74,423-byte shell have SHA-256
`9ad42939844fb73906182bf6ffc8c51d9362e58704ff8948be53887614580ca8`,
`866af381191922aa8bfd43adf342d18886c78949ebeededaeb2bd4d34b818a8f`,
and `01e682088f4f1439507c099372606c41d916cfea249e010cf30faeb02ec3c5be`.
The manifest grants `dependent-ground-environment-elimination-v1`. Whole and
independent-hole consumers pass; automatic `true/0`, `true/1`, `false/true`,
and `false/false` return typed `true/false/true/false`. Bool on the true branch,
Nat on the false branch, and swapped arguments reach Agda and fail its
dependent type check. Missing and extra slots reject locally.

`MixedOpenDependentWord64Residual` covers the ambiguous erased-integer case
with `Slot true = Word64` and `Slot false = Nat`. Its 8,034-byte whole-entry
packet, 5,941-byte hole packet, and 86,090-byte shell have SHA-256
`700aa1fc6c176a9c77ee7b36e202f83d24c6a33d8325a4e2d2a5b1ba3cb60cb9`,
`d86103891066a13feb912a7b079a79f7500672c05b1e2bdb66155a340a499079`,
and `09e5638dd7198a9671063be3ca7e23a0b68ac213fa4080e0f4f9a9768ff1c716`.
The 5,864-byte bridge has SHA-256
`b2c02930b735267e2554bf5cfb0bb686bbc626ab32a511d8f6004d3dd5469d5c`.
Whole/direct consumption, automatic Word64 zero/maximum, automatic Nat
zero/one, and explicit Word64 zero/maximum all pass. The dependent binding
stores raw ground values and uses the requested codec only when constructing
the checked application, so `word64:0` is not guessed to be Nat. Three
wrong-branch codec applications reach the Agda type gate; negative and
overflow lexical Word64 plus explicit overflow reject locally. The 158-byte
ledger has SHA-256
`140986d457048625d35c392aea977c814d7ded9c665b4df4f6d81fa468cbf46d`.

`MixedOpenDependentChainResidual` extends that proof to a three-slot telescope
whose final `NextSlot flag slot` domain depends on both preceding values. Its
8,541-byte whole-entry packet, 6,456-byte hole packet, and 74,491-byte shell
have SHA-256
`bbbcff1d804f964599b1dc84eef3f74f34243430eb1af68d5702e6f810ca1a3c`,
`ccb76e63b13112a850e712a9789e7813b03c8cc7ddcbf1bc7ae04e42ac0c99a4`,
and `a2717e4cc0a348dac84ebb59a62a61fc802c63f587cb7b761164ceebc69234e5`.
Whole and independent-hole consumers pass; all eight branch-correct triples
return the expected alternating typed Bool. Six wrong second/third/ordering
applications reach Agda and reject at its dependent type gate, while missing
and extra slots reject locally.

The same captured triple can replace its immediate result consumer with
`--auto-bind-proxy-id=dependent-chain`. Agda materializes a 3,462-byte root
proxy with SHA-256
`687c036c72f3f0efed9f0936cac105d61df87587b8b4fcf9d940d34b2a8f00fc`;
two later processes consume it successfully. A checked `wrapResidual` derive
publishes a 4,452-byte child with SHA-256
`03438f0b97c0ffc0a734bd880549f1b60f42fca6aa59cff7efe64c1348a4c6d3`.
Root release retains the parent for the child, child consumption succeeds, and
child release recursively removes both pairs. The 344-byte lifecycle ledger
has SHA-256
`b83930e0771a01be3c00f13e6abf456bc815f42c738769a078373d0479390b96`.
Six controls reject duplicate/invalid IDs, a consumer/proxy action conflict, a
wrong dependent branch, and wrong root/derive domains; failed derivation leaves
no target files.

The ordered and dependent lambda-lifted packets also expose an explicit vector
path independent of lexical entry evaluation. `--call-ground-hole` with
`bool:true,nat:0` consumes the ordered packet as `true`; the three-slot
dependent vector `bool:true,nat:0,bool:true` also returns `true`. Replacing the
result consumer with `--call-proxy-id` writes a 3,462-byte packet with SHA-256
`687c036c72f3f0efed9f0936cac105d61df87587b8b4fcf9d940d34b2a8f00fc`,
which a later process consumes before clean drop. Five controls cover ordered
codec mismatch, a short vector, action conflict, unsafe proxy ID, and a
dependent branch mismatch; the first four reject locally and the last reaches
Agda. The 311-byte evidence ledger has SHA-256
`42bb0893cffc919dc8e1c7f10b14c33c93f4cb3e972df6bc1b2bf6cd8a7bf338`.

`MixedResidualTwoHoles` adds two different checked domains at stable IDs
`typed-hole@app-argument-1.app-argument-0` and
`typed-hole@app-argument-1.app-argument-1`. Packet policy emits 3,302-byte and
4,269-byte hole packets, plus a 74,551-byte shell with SHA-256
`92e4c69150d8d49d4bacb163c8eb678f279f2b1ec157756ccd9faff223de03b2`.
The matching consumers return
Bool `true` and Nat `42`; the whole-entry packet still returns static `true`.
The normal shell exposes both IDs and filenames without `primTransp`. Unknown
ID and conflicting selectors reject before runner startup, while applying the
second consumer to the first selected packet reaches the v2 type gate and exits
42, surfaced as `CCZ-TYPED-BRIDGE-RUNNER-EXIT`. This combination proves the
registry is selecting by ID rather than silently forcing its first entry. Batch
mode maps each ID to an explicit consumer and emits the exact planner-ordered
bundle `#(cubical-chez-ground-observations-v1 #(ID-1 true) #(ID-2 42))`.
Missing, duplicate, unknown, and selector-conflicting mappings reject as
`CCZ-TYPED-BRIDGE-OBSERVATION`. This bundle contains ground observations; it is
not a type-preserving replacement for the original `Residual` and
`Bool → Residual` hole values.

The manifest classifies the first hole as non-callable and the second as
`bool-unary-ground-elimination-v1` from their checked Pi domains. The positive
call applies `false` to the second packet inside Agda, then feeds the resulting
typed `Residual` directly to `consumeHole1`; Chez receives Bool `true`.
Six negatives cover a non-capable hole, invalid Bool, incomplete call fields,
unsafe QName, call/force conflict, and a deliberately wrong named packet
domain. The first five reject as `CCZ-TYPED-BRIDGE-CALL` before invocation;
the wrong domain reaches Agda's equality gate and surfaces as
`CCZ-TYPED-BRIDGE-RUNNER-EXIT`. No intermediate `Residual` is serialized
into Scheme.

`MixedResidualNatCallable` adds a one-hole `Nat → Residual` control. Its
7,077-byte whole packet and 4,276-byte hole packet have SHA-256
`adc7c964c8eb3334e188c198428eb271900b2930e907bef6cbe7f74d8b4c9ff3`
and `95446879fa982bae55b5bb9df98986815a976c4d612983b7567394188dcc0c0d`.
The manifest grants `nat-unary-ground-elimination-v1`; its 74,223-byte shell
has SHA-256
`91da50b9ce04bd0f7e84b6a514cb9a1de4316b4b6e8e54e67363cff9c1969b65`.
Applying decimal `7` inside Agda and consuming the typed `Residual` returns Nat
`42`. A negative argument, `4294967296` overflow, Bool/Nat codec mismatch, and
a deliberately wrong named domain add four expected rejections. The first
three fail locally as `CCZ-TYPED-BRIDGE-CALL`; the last reaches the v2 equality
gate and reports `CCZ-TYPED-BRIDGE-RUNNER-EXIT`.

The same fixture advertises `persistent-typed-packet-v1` and
`parent-retained-recursive-gc-v1`. Applying Nat `7` without a final consumer
materializes a 3,234-byte `Residual` root proxy with SHA-256
`235532befe43eb6cafd1fab29744d07228d27bcacdd5e527244388281f5dfbe2`.
Two later Chez processes independently consume that packet and both return
`42`. Agda then checks `wrapResidual : Residual → ResidualWithCount` and
publishes a 4,212-byte child proxy with SHA-256
`a95a89345adbbede8d64dc7e50627202754bc0fd986b9ced141b3922adeea4a4`.
The 44-byte root and 60-byte child metadata record their exact IDs, parent,
and active state. Releasing the root retains its pair but blocks root access;
the child remains consumable and returns `42`. Releasing the child recursively
removes both pairs, while explicit GC before release and again after collection
returns zero. Duplicate creation preserves the original hash, invalid IDs and
released access reject locally, and wrong consume/derive domains reach the v2
equality gate. The lifecycle evidence is
`build/agda29/evidence/MixedResidualNatCallable/typed-proxy-lifecycle.tsv`.

`MixedResidualWord64Callable` adds the checked unary Word64 boundary. Its
8,385-byte whole packet, 5,692-byte `Word64 → Residual` hole packet, and
78,456-byte shell have SHA-256
`f97946ee9e379b439a4ab8fdc3c99c13e9fbd34438c6a4648d45e7aa758d37e3`,
`dba578a9e9dd11ab436e4523f701787c9ebc6f92c0c0dcf253e505eca338120b`,
and `0620a8e733e7cca1bfde8a908289c41b166bb0c22c81f640b1e36ae4b6689f00`.
The manifest grants `word64-unary-ground-elimination-v1`. Calls with zero and
`18446744073709551615` reconstruct their arguments through
`Agda.Builtin.Word.primWord64FromNat` and return typed Nat `42` and `0`.
The maximum application also materializes a 3,446-byte proxy with SHA-256
`6c3140201096756347cb61c9f8b88bfca5bb8c23df8385924a801bfdcd8e5fb7`;
a later process consumes it as `0`, then drop removes the packet/metadata pair.
Five controls reject overflow, Nat codec substitution, wrong named packet
domain, overflow proxy creation, and duplicate proxy publication. The
145-byte evidence ledger has SHA-256
`86ffbef2b3c8ce9d9362b752f94459049c94291b0a7d66be986975a61e3328ef`.

`MixedOpenCharResidual` closes the builtin-Char single-slot and unary paths.
Its whole-entry packet, `Char → Residual` hole packet, and generated shell are
8,411, 5,790, and 93,803 bytes with SHA-256
`39e2cb7b69ffcc2d20435bcd8302376313491e6def4d8de8cd7dac16159ff92c`,
`93fcaadbdd4644593838e336b142f9e881b70afb2eb3c21810eb20068990ec60`,
and `e693eab819e0a99991b3d9473f9609dd78abebab252f80d29794ef4858ea7f9c`.
Whole/direct replay, lexical U+0041/U+0042, and explicit U+0041/U+0042 calls
all pass. The CLI accepts a decimal code point only when it is a Unicode scalar
value; surrogate, overflow, and Nat-codec substitution add five expected
rejections. The 92-byte ledger has SHA-256
`045f19aca8ee893da96c1d0357a99ea3b5e29ca0edbfdb531352a2ebd154087f`.

`MixedOpenCharGroundResidual` covers the ordered `Bool → Char → Residual`
telescope. Its 8,293/6,560/93,875-byte whole/hole/shell artifacts have SHA-256
`c6784d45f78bf36773ff97f6d7e8b35adb7d4895263157b699a852589a2b0932`,
`c21c1f0d852fd8c28e6a624b16ab6dae94572ea79c21e369025d0d1c1d042c3e`,
and `ac331d190455d5aa22e8d467d25ad8299163bfe98444bed9e213d3af69c329c7`.
Whole/direct, lexical U+0041/U+0042, and explicit U+0041 pass; Nat substitution
and surrogate input reject in both lexical and explicit paths. The 71-byte
ledger has SHA-256
`0e8063f90a058c6387ece5b387943c5f9c187abddf6bbe434269a1d8309625a6`.

`MixedOpenDependentCharResidual` covers `Slot true = Char` and
`Slot false = Nat`. Its 8,008/5,931/93,917-byte whole/hole/shell artifacts have
SHA-256
`d16394c32f8023673d084b9ec75f7b6018339de19a747dd92312243d4b53c1e8`,
`10fca8b1017b6ddc8cd7e2a5ae75b68c1dce6ee1bd50ad1cc2cd2e6facc5576a`,
and `d58a777339f709fc0b6d1048c15c0126430ece43dc17809e46ffa1bd4da2a1aa`.
Whole/direct, the four valid Char/Nat branch captures, and an explicit Char
call pass. Wrong-branch codecs reach the Agda type gate; surrogate values are
rejected locally in lexical and explicit modes. The 130-byte ledger has
SHA-256
`f7bf1705a6cff0d13c2ae33d0c3cbc201e0eb602ea6eb391fbbe32f809e71a97`.

`MixedOpenIntResidual` closes the builtin-Int single-slot and unary paths.
Its whole-entry packet, `Int → Residual` hole packet, and generated shell are
8,041, 5,348, and 102,998 bytes with SHA-256
`d09a8154eb5cb125a2d75863a9b1ffacbe21dedf966a2f97e5718a22ea7ace52`,
`7322c170fb4cdb943cfb4351147b176dfd921a675ca45f7b05e56d396216b11f`,
and `ae193f11b20dda9fc2eb1088ce2484d1794079f9be5298a5752b3f6a1b2bd4c9`.
Whole/direct replay, lexical `0/-1`, and explicit signed-64 maximum/minimum
calls pass. Overflow, underflow, and Nat-codec substitution add five expected
rejections. The 94-byte ledger has SHA-256
`dfd199fea0cd9ffd4766efc7136beeb8ed1516e577d4cb5419cf58234ea8b15b`.

`MixedOpenIntGroundResidual` covers ordered `Bool → Int → Residual`.
Its 7,923/6,322/103,070-byte whole/hole/shell artifacts have SHA-256
`612dc6a4712a3ca3ce25aadcb21461d6472de24094759b885d2112141bcd73ca`,
`13573379e0977d08a00e5ef27c5c24729dc762cd8eb050b63a5ca28c3e5bf0d4`,
and `ce1ce6b205e9a63f07a019ab59c681f65fafede9bf0c21f4afc48f1b1327d13c`.
Whole/direct, lexical `0/-1`, and explicit signed minimum pass; Nat substitution
and range violations reject in lexical and explicit paths. The 76-byte ledger
has SHA-256
`6ea634495c75206998cec45fe8d785ef1503d654886db16fbbdcda43375aa2ab`.

`MixedOpenDependentIntResidual` covers `Slot true = Int` and
`Slot false = Nat`. Its 8,003/5,926/103,114-byte whole/hole/shell artifacts
have SHA-256
`5974b7225b92a002c69ab25f30092e7a19534c6812c336260c25c1c1b83f1448`,
`6eefc0e992c553a12617f51628aea952b8db6be19e609bcc47bb0bd0548927b8`,
and `8bdc51767000387271eaa4298eef7acb073b983d5c37783821ae83aa6409bfe0`.
Whole/direct, four valid Int/Nat branch captures, and an explicit signed-minimum
call pass. Wrong-branch codecs reach Agda; overflow and underflow reject
locally. The 132-byte ledger has SHA-256
`57ebdaa436042eed1218b748ed0233c2f5071e0aa4705ed30a5a7539c717479e`.

The exact-projected formal Boundary and Higher groups were also replayed.
`t11/t11b` remain two expected whole-entry residuals, while `p16a/p16b/p16c`
retain all file/pipe consumer outcomes. The Boundary harness now keys on the
stable `CCZ-RESIDUAL-REQUIRED` code rather than Agda's line-wrapped prose.
Each Boundary residual resolves 26 QNames from 8 direct dependencies and
expands 8 ordinary definitions. The four Higher producer runs resolve
75, 75, 88, and 21 QNames respectively; all are well below the 10,000-node
safety bound. These are producer-side conservative closure proofs; the dynamic
formal entries correctly report slice planning as not applicable, and no
resolved definition is claimed to be serialized.

## Fail-closed Cubical primitive catalog

`make verify-primitive-audit` passes two end-to-end cases. The
Internal audit derives semantic identity from Agda's registry and cross-checks
the pinned catalog; Treeless uses the catalog as an independent audit. The
pinned `Agda.Primitive.Cubical.primTransp` control records
`primitive:transport`, agrees with the catalog, remains `dynamic`, and produces only
a typed residual diagnostic under manifest policy. A synthetic future QName,
`Cubical.Primitive.Unknown.primFuture`, is found by both executable audits but
is absent from the pinned Agda 2.8/2.9 catalog, so it is classified
`unsupported` with reason `unknown-cubical-primitive`. Under packet policy the
backend removes pre-seeded stale artifacts and publishes zero Scheme,
Treeless dump, manifest, or packet. Evidence is in
`build/primitive-audit/summary.tsv`.

The complete local `make verify` suite remains green. The established pinned
Agda 2.9 packet/adapter matrix contributes 154 positive executions and 146
expected packet/bridge/producer rejections; the isolated selected+linked
production-candidate differential adds one positive. The current full invocation
is 155 positive executions plus 146 expected rejections. Formal Boundary
remains 2/2 and Higher file/pipe remains 4/4; the changes do not alter their
typed residual outcomes.

`ResidualDependencySlice/dependency-slice.tsv` records 9 resolved, 2 expanded,
and 1 excluded-presentation dependency under
`checked-type+definition-body-v1`. It is 87 bytes with SHA-256
`4d00c588d23cfe8fe6abd01658b2eed132f3fffd813acf37047a01784e7ccd68`.
The Agda 2.8 ten-case summary is 811 bytes with SHA-256
`e10745c2f26744f978f419acc6b1ff80e7e4535cc9b4093fd58824facd53937a`.

`MixedOpenTypedCarrier/proxy-state-transaction.tsv` records stale-lock
recovery, serialized publish/GC, interrupted-state cleanup, locked consume, and
the one-of-two concurrent drop result. It is 97 bytes with SHA-256
`eeee22c5e31002eb68722febf2cfd16d11870b6b8087ff0b8fba2beae367e4ef`.
The generated manifest publishes `store-lock+atomic-state-v1`; the 113,925-byte
shell and 11,874-byte bridge have SHA-256
`e6512cecdba1d4ecf994157bfb31e474fd68256bcd4c6b2c6636c03c9576032a`
and `14978c60022ef033ba3b646b5df5fd62dc9d86ead081121165ac06ae3550804a`.

The ground-codec registry and descriptor checks are included in that rejection
count. The producer manifest records both versioned contracts and the generated
Int shell is 105,004 bytes with SHA-256
`b1bd8dae2d2283834f4ac8f45e125c337efd18bd981c0c3ce12b0ba5f0382dfc`.
Replacing the Int descriptor prefix with `char:` produces a 105,005-byte shell
and is rejected before dispatch with `CCZ-TYPED-BRIDGE-PROTOCOL`; its 118-byte
stderr hash is
`63844bb8cdfbcd32e2ce0597622352cd1405a90adc8dc06b972270c10317c396`.

## Static-closure authorization

`make verify-static-closure` passes one publication case and one
expected rejection. `StaticOrdinary.main` has a complete reachable closure,
all reachable definitions lower to Scheme, staging records
`type-erasure-authorized: true`, and Chez prints `42`. The negative fixture is
also a closed, meta-free, Agda-checked `Nat` term with no Cubical blocker, but
its runtime body references the postulate `StaticUnresolved.opaqueNat`.
Binding-time classification remains accurately `static`; closure proof records
the missing QName, marks Scheme lowering `not-run`, changes the final decision
to `unsupported`, and authorizes no erasure. Pre-seeded stale artifacts are
removed and no program, residual manifest, or packet is published. Evidence is
in `build/static-closure/summary.tsv`.

The implementation represents successful proof as a `StaticClosure`
capability carrying the already-lowered program. The Scheme publisher consumes
that capability rather than a Boolean, so an incomplete code path has no
program value available to publish. The same `StaticOrdinary` replay through
the rebuilt pinned Agda 2.9 backend records a complete closure, authorizes
erasure, and prints `42` under Chez.

## Chez core ABI v1

`make verify-chez-core-abi` passes one executable acceptance case
and two expected producer rejections. `StaticCoreAbi` retains a two-argument
curried function over `Choice (Box Nat)` after normalization. The generated
program dispatches on tag index 0, reads both data and record fields from index
1, maps `PAdd` to exact-arity Chez `+`, invokes the passed closure, and rebuilds
both tagged vectors. A runner supplies 19 and doubling; the final nested vector
contains 42.

Staging publishes `chez-core-abi-v1` plus the QName, function, data, record,
index, primitive-application, and first-class-primitive subcontracts. The
program carries the same version comment. A separate verifier binary declares
`uncurried-closure-v0` while retaining the v1 lowering implementation. Another
maps `PAdd` to subtraction without changing the v1 expected inventory. Both
producer self-checks fail with `CCZ-SCHEME-LOWERING-FAILED`, remove seeded
stale programs, and publish no replacement. Evidence is in
`build/chez-core-abi/summary.tsv`; the pinned Agda 2.9 gate repeats the
executable case and mismatch rejection under `evidence/StaticCoreAbi` and
`evidence/core-abi-mismatch` and `evidence/core-abi-primitive-drift`. The local
summary is 266 bytes with SHA-256
`262e4635d16c4899d21922ef46ed4905a14feb972943d8de92c917882f44efe3`;
the 2.9 ABI TSV is 120 bytes with SHA-256
`4772bf0c801d34b5f908262e4029ae8759995c85e68891f7653802ef6c04fc02`.

## NbE unsupported-feature fallback policy

`make verify-nbe-fallback` passes seven cases. A test-only linked
adapter outcome first proves that the default policy rejects with
`CCZ-NBE-UNSUPPORTED`; the explicit `agda-baseline` policy then produces `42`
while staging records requested `nbe`, effective `agda-baseline`, policy use,
and reason. Unavailable, timeout, and execution-failed outcomes retain their
own error codes even when fallback is requested. An invalid fallback read-back
is rejected by the common engine-result gate, and the fallback option is
invalid with a directly requested baseline engine.

The six rejection cases remove pre-seeded Scheme, Treeless, staging, manifest,
and packet artifacts. Evidence is in
`build/nbe-fallback/summary.tsv`. The successful fallback is oracle
evidence only and is deliberately distinguishable from an NbE result. The full
Agda 2.8 suite and current pinned Agda 2.9 gate remain green; the latter now
contains sixty-three positive executions and seventy-seven packet/bridge rejection
controls, including one-variable Bool/Nat, ordered two-variable, and
ground-indexed dependent two-/three-variable lambda-lifted closures, two
ID-addressed closed holes, one deterministic batch bundle, checked Bool/Nat
ground-unary/environment elimination, explicit ordered/dependent vector calls,
and closed-unary plus explicit/captured dependent typed-proxy
create/reuse/derive/retain/recursive-GC lifecycles.

## Stable failure taxonomy

`make verify-failure-taxonomy` passes six distinct expected
rejections: `CCZ-NBE-UNAVAILABLE`, `CCZ-ENGINE-TIMEOUT`, `CCZ-NBE-FAILED`,
`CCZ-RESIDUAL-REQUIRED`, `CCZ-RESIDUALIZATION-FAILED`, and
`CCZ-UNSUPPORTED`. Every case exits nonzero, emits exactly its expected code,
and leaves no Scheme, manifest, or packet. Evidence is in
`build/failure-taxonomy/summary.tsv`.

The timeout and NbE-failed paths are compile-time-only fault variants used to
fix the adapter outcome contract; no fault selector exists in the production
CLI. The existing unconfigured `nbe` path exercises the production
unavailable code. The pinned Agda 2.9 packet gate was rerun after the taxonomy
change: producer header/closedness/meta failures retain
`CCZ-RESIDUALIZATION-FAILED`, independent consumer negatives retain their own
protocol diagnostics, and the newer opaque-shell, Bool/Nat forcing, and
stable-ID multi-hole controls remain green.
