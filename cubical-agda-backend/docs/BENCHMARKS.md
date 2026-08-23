# NbE production-candidate benchmarks

Last updated: 2026-08-22 (Asia/Shanghai)

## Status

The latest isolated selected+linked release-candidate run is
`ENGINEERING-PERFORMANCE-PASS` under the `release-o2`
`engineering-provisional` profile. All functional, time, RSS, allocation,
artifact, host, and publication gates pass, and the stage-evidence integrity
contract passes. Stage ratios are diagnostic and have no performance
threshold. The formerly failing Higher RSS p95 is `1.194333` against the
unchanged `1.30` ceiling. The checked-in
provider lock and default `nbe` build remain unselected and fail-closed because
Git/revision/license identity and owner threshold approval are separate gates.

**Release recommendation:** do not enable `nbe` by default yet. Treat this
result as evidence that the isolated candidate meets the provisional
regression ceilings, not as evidence of a material speedup or production
approval.

The earlier engineering `-O0` dataset remains retained at
`formal-transport-performance/` with its honest
`ENGINEERING-PERFORMANCE-FAIL` (`1.303373 > 1.30`). The controlled release run
uses a distinct profile, binary/object/evidence tree, result name, and archive;
it does not overwrite or reclassify that historical result. The two runs show
that the O2 candidate clears the current ceiling; they do not isolate whether
the difference came from optimization, host control, ordinary measurement
variation, or another build difference.

## Method

Audit the delivered profiles, documentation, summaries, raw-evidence census,
and publication result without recollecting the benchmark:

```sh
make verify-benchmarks-guide
```

This audit is deterministic and fast. It does not replace collection; it
checks that the report still describes the delivered O0 and O2 evidence.

Recollect the historical engineering O0 profile with:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/clean-cubical-source \
GHC29=/path/to/ghc-9.6.7 \
make verify-formal-transport-production-performance
```

Recollect the accepted release O2 profile with:

```sh
AGDA29_SOURCE_DIR=/path/to/agda-source \
CUBICAL29_DIR=/path/to/clean-cubical-source \
GHC29=/path/to/ghc-9.6.7 \
make verify-formal-transport-production-release-performance
```

Both collection commands are long-running, state-changing operations: a
structurally complete terminal result is transactionally published and the
previous result is archived. The release command writes
`build/agda29/formal-transport-performance-release/`; a host other than the
exact configured Apple M4 profile fails closed before publication. Use the
audit command above when no new measurement is intended. Build dependencies
and pinned-source preparation are documented in `README.md` and `BASELINE.md`;
collection requires the exact Agda 2.9/GHC 9.6.7/Cubical inputs rather than a
nearby local toolchain.

The collector executes three complete baseline/candidate repetitions. Runs 1
and 3 use `agda-baseline -> nbe`; run 2 reverses the order to distribute cache
and host drift. Every repetition covers Base, Glue, Int, Core, Boundary, Hit,
Higher, and the hash-pinned original monolith. Each group uses a disposable
Cubical interface workspace; the monolith explicitly prewarms the seven shards
and original module. A group has a hard 180-second timeout, and every recorded
case/prewarm module must remain within 30 seconds.

Before collection and before every engine/group pair, the collector now checks
`config/nbe-performance-host-profile.tsv`. It fixes the machine to Apple M4,
10 logical CPUs and 25,769,803,776 bytes of memory; requires AC power, disabled
low-power mode and nominal thermal state; and requires two consecutive samples
with at least 75% CPU idle and 20% system memory free. Up to 12 samples are
allowed. The accepted facts and the 12 highest-CPU processes are retained with
each group, the collector retains the sampling attempts under `raw/`, and
`caffeinate -dimsu` prevents sleep. The comparator revalidates the accepted
sample and requires the process snapshot; it does not reconstruct the
collector's consecutive-sample decision from the attempt history.

All new evidence is collected in a sibling result-specific `.pending.*`
directory. Only a complete comparator
terminal result (`ENGINEERING-PERFORMANCE-PASS` or a valid threshold
`ENGINEERING-PERFORMANCE-FAIL`) can be promoted. Promotion records
`publication.tsv`, moves the previous current result into its timestamped
archive, and then installs the staged result.
Any host, collection, stage, schema, or comparator error removes only the
pending directory and leaves the current evidence untouched.

The compared time is end-to-end backend process time for each formal case. The
backend also publishes a fixed eight-row `stage-timings.tsv` for engine total,
NbE evaluation, NbE readback, result admission, Internal audit, Treeless
conversion, residualization, and Scheme publication. The formal runner adds
Chez execution and archived typed-residual-consumer execution. It derives the
combined `agda-frontend-module-loading` remainder by subtracting the
non-overlapping backend phases from process elapsed time. That remainder
includes process startup and does not pretend to distinguish parsing from type
checking without upstream Agda instrumentation.

For each scope the end-to-end gate records median, nearest-rank p95 (the
maximum with three samples), min/max, and median absolute deviation. Time and
allocation baseline/candidate columns are independent medians across the three
runs; their ratio columns are medians/p95 of the three paired per-run ratios,
not quotients of the displayed aggregate columns. RSS baseline/candidate
columns are independent maxima across runs, while the RSS ratio columns again
come from paired per-run ratios. Time, RSS, and allocation ratios are
`candidate / baseline`, so lower is better. The v2 profile invokes every
backend process with GHC `+RTS -s`: `allocations.tsv` must contain allocated
heap bytes, bytes copied during GC, and maximum heap residency for exactly the
timed scenario set. Stage totals remain diagnostic evidence and do not impose
independent thresholds.

The `static-projections` scope is Base, Glue, Int, Core, and Hit;
`residual-projections` (labelled “Typed-residual projections” in the result
table) is Boundary and Higher. `overall`/“all eight groups”
adds the original monolith to those seven projections. Each engine therefore
contributes 40 timed formal scenarios per repetition; stock prewarm is tracked
separately.

## Environment

| Dimension | Value |
| --- | --- |
| Host | `fengqixingdeMacBook-Air.local` |
| CPU / memory | Apple M4 / 25,769,803,776 bytes |
| Power | AC Power |
| OS | Darwin 25.3.0, arm64 |
| GHC / optimization | 9.6.7 / `-O2` (`release-o2`) |
| Repetitions | 3, alternating engine order |
| Inputs | Identical pinned Agda 2.9, Cubical and `test/fixtures/TransportTests.agda` hashes per pair |
| Host policy | `formal-transport-host-v1`; all 48 group preflights PASS |

The top-level captured collection environment is in
`build/agda29/formal-transport-performance-release/environment.tsv`.
The original input SHA-256 is
`8dc43da819617ae66cee4b975cb12c10bef25e928fa395b6bf18f7d612914e0b`.
The supplied Agda projection is content-matched to upstream
`d8a73ff720197796fb64c7652202d33e7abb3eb6`; its standard-library gitlink is
`9a543dc8eb1abce4853c356de35c870d66a27984`. The supplied Cubical tree remains
identified by maintained content/input hashes because an independent upstream
revision match is still open; `BASELINE.md` is the provenance source of truth.

## Provisional thresholds

The accepted machine-readable release profile is
`config/nbe-performance-release-profile.tsv`. The engineering O0 profile is
kept separately in `config/nbe-performance-profile.tsv`.

| Scope | Maximum p95 time ratio | Maximum p95 RSS ratio | Maximum p95 allocation ratio |
| --- | ---: | ---: | ---: |
| All formal evidence | 1.15 | 1.20 | 1.20 |
| Static projections | 1.15 | 1.20 | 1.20 |
| Typed-residual projections | 1.25 | 1.30 | 1.30 |
| Individual group | 1.35 | 1.30 | 1.30 |
| Stock prewarm | 1.20 | 1.10 | not measured |

Scheme and typed-packet artifact totals may be at most 1.10 times their
baseline size, with equal artifact counts. These are conservative regression
ceilings, not a promise that the candidate provides a particular speedup.

## Results

The latest three-run result is:

The baseline/candidate aggregate columns and paired-ratio columns use the
different aggregation rules described in Method; readers must not divide the
two displayed medians or maxima to reconstruct a ratio. With only three runs,
p95 is the worst observed paired ratio, not a stable tail-latency estimate.

| Scope | Baseline median | Candidate median | Time ratio median / p95 | RSS ratio median / p95 | Allocation ratio median / p95 | Result |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| Static projections | 43.03 s | 43.00 s | 1.0014 / 1.0271 | 0.9757 / 1.0059 | 1.000044 / 1.000046 | PASS |
| Typed-residual projections | 20.28 s | 20.20 s | 0.9961 / 0.9995 | 1.0715 / 1.1943 | 0.999800 / 0.999802 | PASS |
| All eight groups | 74.18 s | 74.15 s | 0.9996 / 1.0167 | 0.9757 / 1.0671 | 0.999940 / 0.999941 | PASS |
| Monolith prewarm | 14.75 s | 14.71 s | 0.9973 / 1.0061 | 1.0001 / 1.0021 | not measured | PASS |

All p95 gates pass without changing a threshold. The Higher group now has
time/RSS/allocation p95 ratios 1.007692/1.194333/0.999569, closing the narrow
RSS threshold failure seen in the historical O0 run. It does not remove the
approximately 19.4% worst-observed Higher RSS increase versus baseline.
Overall allocation is slightly lower for the candidate: median totals are
232,114,571,664 baseline and
232,100,679,720 candidate bytes.

The stage medians below are independently selected baseline and candidate
medians of the per-run totals over all 40 timed scenarios. Different stages or
engines may select different runs; this table does not represent one concrete
“median run.” The ratio is candidate independent median divided by baseline
independent median:

| Stage | Baseline | Candidate | Ratio / classification |
| --- | ---: | ---: | --- |
| Agda frontend/module-loading derived remainder | 74.0993 s | 74.0735 s | 0.9997 |
| Engine total | 0.0313 s | 0.0235 s | 0.7528 |
| NbE evaluation | n/a | 0.0233 s | candidate-only |
| NbE readback | n/a | 0.0001 s across 32 supported cases | candidate-only |
| Result admission | 0.0053 s | 0.0029 s | 0.5402 |
| Internal semantic audit | 0.0004 s | 0.0002 s | 0.5545 |
| Treeless conversion | 0.0090 s | 0.0107 s | 1.1946 |
| Residualization | 0.0237 s | 0.0224 s | 0.9451 |
| Scheme publication | 0.0120 s | 0.0160 s | 1.3269 |
| Chez execution | 0.5600 s | 0.5600 s | 1.0000 |
| Typed-residual consumer | 4.7100 s | 4.7500 s | 1.0085 |

Agda frontend/module loading still dominates the workload. The candidate's
measured engine total is about 7.7 ms lower across 40 cases, but the end-to-end
result remains effectively neutral rather than demonstrating a large speedup.

Each run publishes exactly 28 Scheme artifacts. Candidate and baseline Scheme
totals are both 7,878 bytes. Each publishes two typed packets; the baseline
total is 26,775 bytes and the candidate total is 10,165 bytes (ratio 0.3796).
Both packet sets pass the same archived v2 consumers and wrong-consumer type
rejection.

All 48 engine/group results contain exact timed-scenario allocation evidence.
Every group and aggregate scope passes. Static allocation p95 is 1.000046,
typed-residual p95 is 0.999802, and overall p95 is 0.999941. The independent
one-shot O0 Base instrumentation result remains diagnostic only and is not
mixed into these accepted O2 statistics.

## Evidence and limits

- `build/agda29/formal-transport-performance-release/summary.tsv`: aggregate statistics
  and thresholds;
- `samples.tsv`: all group and combined per-run samples;
- `allocation-summary.tsv`: v2 allocation ratio statistics and thresholds;
- `artifacts.tsv`: Scheme/packet count and size comparisons;
- `raw/run-01` through `raw/run-03`: 48 engine/group summaries plus full
  invocation, source, binding-time, allocation, staging, and log evidence;
- `stage-comparisons.tsv`, `stage-runs.tsv`, and `stage-summary.tsv`: per-case,
  per-run, and median stage evidence;
- `invocation.tsv`: profile identity and final
  `ENGINEERING-PERFORMANCE-PASS` result;
- `publication.tsv`: transactional publication time and accepted terminal
  result.

The accepted release tree contains 3,219 raw files, 48 group summaries, 48
`host-preflight.tsv` files, 48 background-process snapshots, and 48
`allocations.tsv` files. Its invocation records `release-o2`, `-O2`,
`formal-transport-host-v1`, and `HOST-PASS`. The historical O0 tree predates
the host/allocation contract and remains diagnostic evidence for its narrow
RSS failure; its top-level invocation also predates the newer explicit
optimization/host fields. It is classified by its original collection path
and retained profile history, but cannot be accepted as a new controlled
result or used to establish why O0 and O2 differ.

The host validator has one positive and six fail-closed controls. The
end-to-end comparator has two positives and nine rejects: elapsed-time, RSS,
and allocation regressions, wrong engine provenance, non-quiescent host
evidence, missing background-process or allocation evidence, a missing run,
and wrong optimization provenance. The stage comparator adds one positive and
two rejects for malformed and missing stage evidence. The publication gate has
three positives (O0 PASS, O2 PASS, and terminal threshold FAIL) and four
rejects (result mismatch, incomplete stage evidence, missing allocation
summary, and path escape), while preserving the current result in every
reject. Remaining performance work is owner confirmation of the production
acceleration/RSS/allocation/timeout thresholds; the measured provisional O2
gate itself is complete and passing.

These results are host- and input-specific. Three samples make nearest-rank
p95 equal to the worst observed sample, so the report is a regression gate,
not a population-level latency study. The derived Agda frontend remainder
includes process startup and module loading, and cannot identify parser versus
type-checker cost. Finally, passing the isolated selected+linked O2 candidate
does not select the checked-in production lock or prove a general speedup;
approved revision/license identity and owner threshold approval remain
independent release conditions.

### Release decision checklist

Production selection remains blocked until all of the following are recorded:

1. The owner approves or replaces the provisional time, RSS, allocation, and
   timeout ceilings, and states whether a minimum acceleration is required.
2. The provider exact revision, license file/SPDX identifier,
   decision owner, and approval time replace every unresolved identity field.
3. `make check-nbe-production-promotion` passes against that exact
   identity and the selected lock.
4. The reviewed selected-lock build reruns the complete functional and
   controlled release-performance gates before any default is changed.

The [`DELIVERY_CHECKLIST.md`](../DELIVERY_CHECKLIST.md) records ownership
and sign-off; this benchmark report does not invent an approver or silently
turn provisional ceilings into policy.
