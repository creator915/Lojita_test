# Baseline ledger

Last updated: 2026-08-22 (Asia/Shanghai)

This ledger distinguishes the stock Agda typechecking gate from the runtime
normalisation and cross-process acceptance matrix. A typechecking PASS does not
claim that the v2 runtime matrix has run.

## Fixed inputs

- Agda: supplied 2.9.0 source snapshot. Its stock projection matches the
  official `d8a73ff720197796fb64c7652202d33e7abb3eb6` archive.
- cubical: supplied source snapshot, reported commit
  `92166033326aa59800a580b428125f3c654b5e45`.
- std-lib: official archive of the Agda parent gitlink commit
  `9a543dc8eb1abce4853c356de35c870d66a27984`; 1,408-file manifest SHA-256
  `33ffd9bd0f4c62c6c4c402f35bdb684c3fc1fe88a31c2b7c52edd629c70a6e7a`.
- GHC: 9.6.7.
- Host: macOS 26.3.1, arm64 Apple M4, 24 GiB RAM.
- Test source: `test/fixtures/TransportTests.agda`, SHA-256
  `8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b`.

The extracted source snapshots do not contain `.git`. The Agda parent identity
is therefore checked against the official commit archive by content. The
std-lib snapshot is checked against the parent commit's official gitlink and a
maintained content manifest, while the reported cubical commit remains pending
independent verification.

## Stock Agda source identity gate

Command:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
make verify-agda29-stock-baseline
```

The official commit archive has SHA-256
`03f587904de6db00d101b189800c44a1fa41f763ac071e62a84340bff12227ea`
and size 5,346,291 bytes. After excluding submodule contents, generated build
artifacts, and the explicit local v2 overlay, all 10,084 stock files match the
official archive. The stock `src`, `test`, `doc`, and `mk` projections are
independently summarized, and all nine overlay files pass their own manifest.

Evidence is under `build/agda29/stock-baseline/`; durable expected
identities are in `test/fixtures/agda29-stock-baseline.identity.tsv`
and `test/fixtures/agda29-v2-overlay.sha256`.

## Stock Agda TransportTests gate

Command:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/cubical-upstream \
GHC29=/path/to/ghc-9.6.7 \
make verify-transport-shards
```

The gate verifies the original source hash, copies cubical and the fixtures to
an isolated temporary directory below `build/`, and typechecks seven
independent diagnostic shards. Their generated interfaces are reused only
inside that temporary directory. The final step copies the original content to
the required `TransportTests.agda` module filename and typechecks that exact
monolithic source with stock Agda. The temporary source/interface tree is then
removed; neither supplied snapshot receives `.agdai` files.

Result on 2026-08-20:

| Kind | Module | Result | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| shard | `TransportBase` (t01/t02/t07) | PASS | 3.24 s | 222,183,424 |
| shard | `TransportGlue` (t03/t04/t08) | PASS | 4.30 s | 366,166,016 |
| shard | `TransportInt` (t05/t06) | PASS | 5.00 s | 548,552,704 |
| shard | `TransportCoreB` (t09/t10) | PASS | 0.37 s | 181,108,736 |
| shard | `TransportBoundary` (t11/t11b) | PASS | 0.48 s | 202,604,544 |
| shard | `TransportHit` (t12-t15) | PASS | 0.80 s | 276,676,608 |
| shard | `TransportHigher` (t16a-c) | PASS | 0.56 s | 252,526,592 |
| exact | `TransportTests` | PASS | 0.60 s | 255,836,160 |

Machine-readable results and per-module stdout/stderr/time logs are written to
`build/agda29/transport-shards/`. The highest successful per-process
RSS in this run was 548,552,704 bytes (about 523 MiB).

A preliminary no-interface combined shard was manually stopped after 558.97 s;
`/usr/bin/time -l` recorded a 7,198,539,776-byte maximum RSS. It was an
engineering measurement, not a typechecking failure. This is why the maintained
gate uses independent shards and an isolated shared interface cache.

## Formal backend TransportTests projections and original-monolith gate

Command:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/cubical-upstream \
GHC29=/path/to/ghc-9.6.7 \
CABAL29=/path/to/cabal \
make verify-formal-transport
```

This gate is separate from stock typechecking and the archived v2 runtime. It
hash-pins the original source and `TransportBase.agda`, extracts the exact
`t01`, `t02`, and `t07` definition/proof blocks from both, and requires byte
equality before using the projection. Their fragment SHA-256 values are
`fecdea78bbe99de8a9d3b2c610709c1e72743ef8b97d634cbc07114989c3b800`,
`ba69d96a7268e24a6d627b8b6b87e0a3acbbcfd4999ecdc91f2fef602067d037`,
and `f44f5ce3bcfec1b6d0c0ecea68b198943fa426bc8d206206b1a2e17573e33e3d`.

The Agda 2.9 formal backend is built with `-Wall -Werror`, explicitly selects
each qualified entry, and passes each normalized result to Chez. On 2026-08-20:

| Case | Expected / actual | Treeless | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t01` | `7 / 7` | `TLit 7` | 3.16 s | 223,625,216 |
| `t02` | `7 / 7` | `TLit 7` | 0.17 s | 110,264,320 |
| `t07` | `4 / 4` | `TLit 4` | 0.17 s | 110,166,016 |

The second group hash-pins `TransportGlue.agda` and proves exact source-block
identity for `t03`, `t04`, and `t08`, with fragment SHA-256 values
`4ea584b01209595514b5410b463ad80be2ad5eb8353f7845ea8bda3c4ab2fce6`,
`7b2d2e0dfd02b65214be73817db4a315f727170dc8e10a4c70555825f63b2db6`,
and `1a4b76633b78c074e92135f4c779a005f5ce9c3fdef43ac80db5f0ec673e6af2`.

| Case | Expected / actual | Treeless | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t03` | `false / false` | built-in `false` | 6.87 s | 367,722,496 |
| `t04` | `true / true` | built-in `true` | 0.35 s | 181,649,408 |
| `t08` | `false / false` | built-in `false` | 0.35 s | 181,583,872 |

The third group hash-pins `TransportInt.agda` and proves exact source-block
identity for `t05` and `t06`, with fragment SHA-256 values
`1bd8c1336103775d452558bf42e3b5195c42edc0d5eb43091436a5bcfedb242b` and
`7e5eff544f039ad53129633aab5d03abcf2152fe0f5397795bcd515303da1b28`.

| Case | Expected / actual | Treeless | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t05` | `pos 1 / pos 1` | `ℤ.pos 1` | 11.49 s | 492,617,728 |
| `t06` | `negsuc 0 / negsuc 0` | `ℤ.negsuc 0` | 0.53 s | 241,451,008 |

The fourth group hash-pins `TransportCoreB.agda` and proves exact source-block
identity for `t09` and `t10`, with fragment SHA-256 values
`3e06340fc82d0dc077e0bc476649985a3c296ec710a83f12d25a0af68b5db4e9` and
`8307023c9f72b043e4538a883069975378befbdf594cbdc83ef3c45b4077836e`.

| Case | Expected / actual | Treeless | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t09` | `(false,3) / (false,3)` | built-in Σ pair | 7.38 s | 307,953,664 |
| `t10` | Bool List / Bool List | complete three-cell spine | 0.37 s | 183,746,560 |

The fifth group hash-pins `TransportBoundary.agda` and proves exact
definition-block identity for `t11` and `t11b`, with fragment SHA-256 values
`6f50f503096acb98c33667b11bce59a1565e7f3625602924beb1183ed354da30` and
`26d8875a65f7ea8bccbc374daae934659f03319e456e88484ac78b18af645392`.

| Case | Expected / actual | Audit result | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t11` | residual / residual | dual-layer `transpX-Vec` | 7.35 s | 311,574,528 |
| `t11b` | residual / residual | dual-layer `transpX-Vec` | 0.39 s | 180,928,512 |

The sixth group hash-pins `TransportHit.agda` and proves exact source-block
identity for `t12`-`t15`, with fragment SHA-256 values
`5e8bae5d57ab5253be39335e229138c942e9f5b2ab2377e8b3f681f48ccf48b4`,
`8a94cbfa5423c6d7953e2955a8a672649c36bddb313cbdd4b06e74c848e0a293`,
`68b10cf5b938324374cfd21a2919a1da031d46780f2d2c3e7df968440890abb4`,
and `78a63841883a9c8e718b2aa8d9a940ad97b693b2627badd34b62485f78447cd1`.

| Case | Expected / actual | Treeless | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `t12` | `pos 2 / pos 2` | `ℤ.pos 2` | 11.59 s | 494,698,496 |
| `t13` | `pos 1 / pos 1` | `ℤ.pos 1` | 0.55 s | 249,856,000 |
| `t14` | `41 / 41` | `TLit 41` | 0.57 s | 266,469,376 |
| `t15` | `true / true` | built-in `true` | 0.54 s | 249,790,464 |

The seventh group hash-pins `TransportHigher.agda` (SHA-256
`c7a1a45e12712c747746821230e3382de089916ba5a79e8c429f05dbbe7826aa`)
and proves exact definition identity for all three producer/consumer pairs. The
`p16a/p16b/p16c` fragment hashes are
`ba431e84122f768cb2be58eaeb5cacd1cbe531ea2d38d8d748f0f67b96fde41b`,
`243a2b59ffbe766fe4caa27c2cccf14f48d5c7a421095deec5fa8ed6015fa343`, and
`18f001d7e069fa7c1d9287d3fdcdca531f55b73879253c39996120b7629644a2`;
the `c16a/c16b/c16c` hashes are
`d3d3c51917d14a60f7937c7baff1a5701fd222804d74836a94142d71d1c2bc90`,
`dc9ef41dafb738f304d36d1f52c4ba88443bb3d2fe06c036b06200b8741e44da`, and
`802e787f8a9cb870945b4d86dd6627cfb598a68f2beb517e1654f66495241e55`.

| Case | Expected / actual | Channel | Real time | Peak RSS (bytes) |
| --- | --- | --- | ---: | ---: |
| `p16a → c16a` | `true / true` | file | 11.58 s | 431,783,936 |
| `p16a → c16a` | `true / true` | direct pipe | 0.60 s | 252,035,072 |
| `p16b → c16b` | `pos 2 / pos 2` | direct pipe | 0.60 s | 252,411,904 |
| `p16c → c16c` | `pos 2 / pos 2` | direct pipe | 0.60 s | 252,280,832 |
| `p16a → c16b` | `UnequalTypes` | expected reject | not timed | not timed |

The retained file packet is 13,390 bytes with SHA-256
`57c7f7ca3100ec98618ea353184a2dbe4de4d1ab110d1e56adb43b2c618b6caa`.
All pipe cases leave zero packet files, and all Higher cases leave zero Scheme.

All static executable blocker sets were empty; no Cubical primitive, typed
residual, or `TCState` artifact reached their generated programs. Boundary
cases instead terminate with the required typed-residual decision and publish
only a diagnostic manifest, never Scheme or a packet. The base, Glue, Int,
Core, Boundary, Hit, and Higher gates created 35, 76, 122, 81, 78, 125, and 125
interfaces respectively, only in disposable workspaces. Source manifests were
unchanged and the supplied cubical tree retained zero `.agdai` files. The 20
timed projection cases total 65.21 seconds; highest child RSS is 494,698,496
bytes.

The formal runner now also writes `binding-time.tsv`. The latest Base evidence
contains three `static` rows; Boundary contains two `dynamic` rows; Higher
contains five `dynamic` rows. The differential gate compares scenario, class,
reason, and action independently of timing.

The aggregate also runs the hash-pinned original `TransportTests` module rather
than a projection. In one disposable workspace, stock Agda first checks the
seven projections and then the original module. This 8-step prewarm creates 134
interfaces in 15.30 seconds with a 548,552,704-byte peak. The formal backend
then executes all entries from that original module: 14 static PASS, 2
`EXPECTED-RESIDUAL`, 4 packet PASS, and one `EXPECTED-REJECT`. Its 20 timed
cases take 11.55 seconds with a 266,010,624-byte peak. The file packet is 13,385
bytes with SHA-256
`11ae3c9f9be97e43e656f417f756e36765b9269a5c3f6b0e53ead71885d3c60d`;
three direct pipes leave no packet file.

A direct cold attempt on the full monolithic source was manually terminated
after 906.67 seconds at 12,254,330,880 bytes maximum RSS. It did not report a
semantic failure. An earlier `t01` projection with interface writing disabled
also took 254.24 seconds and 11,722,457,088 bytes. The maintained isolated
interface cache resolves that harness cost, but it is not a production-NbE
performance claim. The exact-projection gates and original-monolith gate close
all `t01`-`t16` functional classifications. The selected+linked candidate now
passes both the complete functional differential and the provisional three-run
engineering performance comparison; production provider identity and
owner-approved thresholds remain open. Current oracle evidence is
under `build/agda29/formal-transport/base/`, `glue/`, `int/`, `core/`,
`boundary/`, `hit/`, `higher/`, and `monolithic/`; cold diagnostics remain under
`build/agda29/formal-transport/t01/`.

## Formal-engine differential comparator baseline

`make verify-formal-transport-differential-self` validates the
comparator against all 8 baseline groups and records 8/8 `SELF-CHECK-PASS` under
`build/agda29/formal-transport-differential/self-check/`. This mode is
explicitly not NbE evidence. The default differential target expects an `nbe`
evidence root and refuses missing/incomplete results. Separate negative controls
confirm that an unauthorized baseline self-comparison and a one-value mutation
are rejected.

The formal runner routes `FORMAL_TRANSPORT_ENGINE=nbe` to a separate evidence
root. With the current deliberately unconfigured adapter, the Base control exits
nonzero with the NbE configuration diagnostic and leaves zero Scheme/packet
artifacts without changing the baseline summaries.

## Other verified baselines

- `make verify`: PASS on installed Agda 2.8.0 and Chez 10.4.1.
- `make verify-agda29`: PASS for the v2-compatible packet producer,
  ordinary/mixed whole-entry consumers, independent mixed-hole consumer, and
  one-/two-hole mixed Chez shells with ID-addressed Bool/Nat ground forcing plus
  single-slot Bool/Nat/Word64/Char/Int, ordered non-dependent Bool/Nat/Word64/Char/Int, and length-generic
  ground-indexed dependent Bool/Nat/Word64/Char/Int lexical replay; closed Bool/Nat/Word64/Char/Int unary calls and captured
  dependent applications exercise persistent typed-proxy
  create/reuse/derive/parent-retention/recursive-GC lifecycles; ordered and
  dependent packets also pass explicit ground-vector call/proxy operations
  without lexical entry evaluation, plus
  packet/bridge safety negatives. See
  `COMPATIBILITY.md`.

## Archived v2 runtime baseline

Command:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/cubical-upstream \
GHC29=/path/to/ghc-9.6.7 \
make verify-v2-runtime
```

The maintained wrapper does not reimplement the v2 assertions. It runs the
archived `run-tests.sh` and `run-transport-tests-v2.sh` unchanged, while
providing an isolated interface cache and collecting their output and resource
measurements.

| Suite | Result | Real time | Peak RSS (bytes) |
| --- | --- | ---: | ---: |
| archived self-contained runtime | PASS | 1.17 s | 144,375,808 |
| archived full TransportTests matrix | PASS | 22.25 s | 328,663,040 |

The full matrix reported t01-t10 and t12-t15 `MATCH`, t11/t11b
`EXPECTED-RESIDUAL`, all three t16 pipe consumers with their expected values,
the t16 file round-trip, and the wrong-consumer `EXPECTED-REJECT`. Logs and the
machine-readable summary are under `build/agda29/v2-runtime/`.

## Still open

- the official full Agda suite outside the completed Compiler, BuildFail,
  BuildSucceed, Succeed, Interactive, Internal, UserManual, and CubicalSucceed
  groups plus the native source, Common, coverage, examples, external
  cubical-library, complete standard-library, MAlonzo `AllStdLib`, JS
  `AllStdLibJS`, `LibSucceed`, and official benchmark checks remains open where
  environment prerequisites are still missing. Final owner-approved NbE
  performance thresholds also remain open; the engineering comparison is in
  `BENCHMARKS.md`. The Bugs
  group is accounted for but not marked PASS because
  `Issue8182` has one environment-specific golden-line difference. The Fail
  group is likewise accounted for but not marked PASS:
  1,816 tests pass, while its three intentional internal-error goldens have the
  same environment-specific final-line difference. Interaction/simple passes
  462/462 with a separately labelled BSD-sed/case-folding compatibility mode.
  Interaction/custom is also accounted for but not marked PASS: 58 goldens
  match, while `Issue8634` has one absolute-workspace annotation-offset golden
  difference. Standard-library interaction passes all 3/3 goldens under the
  separately labelled Darwin `gsed` compatibility mode.

The official targeted baseline is recorded in `TEST-RESULTS.md`:
CubicalSucceed passes 1/1, the earlier API Interface/Serialise subset passes 3/3,
Internal MAlonzo encoder properties pass 3/3, and stock MAlonzo Cubical
compilation negatives pass 4/4. Internal TypeChecking properties pass 11/11,
conversion success regressions pass 5/5, and conversion golden failure
regressions pass 5/5, for 32/32 selected tests overall. The separate canonical
full API target now passes 4/4, including the formerly unavailable
std-lib-backed `PrintImports.run`. The separate canonical Compiler gate passes
687/687 executed tests; 41 upstream-disabled and two
canonical std-lib exclusions account for the full static inventory of 730.
The separately maintained `std-lib-compiler-test` and
`std-lib-js-compiler-test` now close the MAlonzo `AllStdLib` and JS
MinifiedOptimized `AllStdLibJS` exclusions 1/1 each with no disabled cases.
The full-suite preflight additionally accounts for all 32 dependencies of the
upstream aggregate. The maintained isolated BuildFail, BuildSucceed, and
Succeed shards pass 4/4, 8/8, and 2052/2052. The remaining 13 Bugs cases pass
when the separately recorded `Issue8182` golden difference is diagnostically
excluded. The Fail diagnostic shard passes its remaining 1,816 cases after the
exact three internal-error goldens are recorded and excluded. Broader
conversion and full-suite coverage remain open.

The canonical Interactive and complete Internal groups additionally pass 3/3
and 538/538 without exclusions or disabled cases.

UserManual passes 55/55, and CubicalSucceed passes 1/1 through the same unified
group runner without exclusions or disabled cases.

The Makefile-native source policy checks pass 2/2, and the Common mini-library
typechecks all 24/24 modules in its isolated workspace. The four native
coverage checks pass 4/4, covering declared errors, declared warnings,
user-manual options, and user-manual warnings. The Makefile-native custom
interaction inventory contains 59 tests: its adapted full result retains one
classified `Issue8634` environment golden difference, and the exact diagnostic
exclusion passes the other 58/58.

The Makefile-native standard-library interaction inventory contains three
complete source/input/golden triples. Its canonical Darwin result is
`ENVIRONMENT-MISSING-TOOL` because upstream requires `gsed`; the minimal BRE
compatibility run passes 3/3 with zero exclusions, golden differences, or
residual temporary files.

The official examples target passes all 44/44 inventoried Make leaf checks,
including two locked-GHC MAlonzo compile-and-run passes. The stdout execution
count, static dependency inventory, and subsequent stock source identity gate
all pass.

The external cubical library target passes all 1,192/1,192 inventoried Agda
modules through the upstream `--build-library` command. The isolated run
generates exactly 1,192 interfaces in 342.97 seconds with peak RSS
4,458,266,624 bytes. Its complete supplied-source manifest matches before and
after the run, the input tree remains free of `.agdai` files, and the
subsequent Agda stock/overlay identity gate passes.

The official `benchmark-without-logs` target passes all 18/18 cases in 11.02
seconds with peak RSS 326,516,736 bytes. Its two parser-monad cases use the
exact std-lib gitlink commit selected by the pinned Agda parent rather than a
host-installed substitute. The maintained 1,408-file std-lib manifest matches
before and after execution, the target leaves zero benchmark log files, and
the subsequent Agda stock/overlay identity gate passes.

The complete standard-library target passes all 1,059/1,059 generated
`Everything` imports in 105.84 seconds with peak RSS 3,460,743,168 bytes. The
library generator also produces exactly 952 safe imports, and the clean
`--ignore-interfaces` check writes 1,091 dependency interfaces from the 1,182
source-module inventory. The external 1,408-file source manifest matches
before and after execution, the supplied std-lib tree remains free of
`.agdai`, and the subsequent Agda stock/overlay identity gate passes.

The complete upstream API target passes 4/4 in 12.35 seconds with peak RSS
1,375,289,344 bytes. It performs four locked-GHC `-Wall -Werror` compilations,
creates the expected three `.api` completion markers, and parses eight import
records from the exact std-lib input in `PrintImports.run`. Upstream removes
its three intermediate interfaces after the markers are complete. The std-lib
manifest and subsequent Agda stock identity gates both pass.

The upstream MAlonzo standard-library compiler target passes its sole
`AllStdLib` test in 64.43 seconds with peak RSS 2,550,235,136 bytes. The
isolated prerequisite rebuild fixes 1,059 `Everything` imports and 1,091
dependency interfaces in 98.22 seconds with peak RSS 3,335,979,008 bytes
before the canonical test driver compiles, runs, and golden-checks the program.
`AllStdLibJS` is canonically excluded from this target. The external 1,408-file
std-lib manifest matches before and after and the supplied tree remains free of
`.agdai` files.

The upstream JavaScript standard-library compiler target passes its sole
`AllStdLibJS` test in 38.87 seconds with peak RSS 2,368,667,648 bytes. The
source intentionally omits `Everything` and uses `--no-main`; JS
MinifiedOptimized compiles the exact std-lib dependency closure and Node
24.13.0 executes it with the expected empty output and successful exit. The
external 1,408-file manifest again matches before and after and remains free of
`.agdai` files.

The official standard-library success group passes all 25/25 `LibSucceed`
tests in 25.73 seconds with peak RSS 1,285,783,552 bytes. The recursive input
inventory has 32 source modules; the exact normalized output set has 30 input
interfaces because the successful `Issue1382` and `Issue846`
`--allow-unsolved-metas` entries intentionally do not write interfaces. The
shared isolated std-lib copy produces 258 dependency interfaces. The supplied
1,408-file std-lib manifest matches before and after and remains free of
`.agdai` files.

The standard-library interaction target passes `ClashingDefinition`,
`EqReasoning`, and `Issue2066` 3/3 under the labelled Darwin compatibility mode
in 12.02 seconds with peak RSS 643,809,280 bytes. It leaves zero input
interfaces and produces 121 dependency interfaces only in the isolated std-lib
copy. The canonical missing-`gsed` result remains recorded separately. The
supplied 1,408-file manifest matches before and after and remains free of
`.agdai` files.

The official Haskell doctest inventory contains five `>>>` directives across
`Agda.Utils.List`, `Agda.Utils.List1`, and `Agda.Utils.String`. With isolated
`doctest 0.25.0` built against the locked GHC 9.6.7 API, the canonical run is
classified `ENVIRONMENT-GHC-REPL-CONFIG`: the interpreter's optimization
warning is promoted by the package-level `-Werror`. The separately labelled
`-O0 -Wwarn` compatibility run tries all 5/5 examples with zero errors and zero
failures in 65.44 seconds at 2,148,286,464 bytes peak RSS. All install and build
state is disposable, while version, inventory, output, timing, and resource
evidence is retained.

The official archive has distinct `test/Interaction` and `test/interaction`
directories. They collapse in the supplied extraction on this case-insensitive
host, so the stock identity is explicitly a host-filesystem projection. The
Interaction/simple gate restores the expected lowercase runtime directory only
inside its disposable workspace and leaves the supplied tree unchanged.
