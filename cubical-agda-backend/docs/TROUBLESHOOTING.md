# CubicalChez troubleshooting

Last updated: 2026-08-22 (Asia/Shanghai)

This guide diagnoses build, engine, residual, packet, Chez, performance, and
promotion failures without weakening a safety gate. Stable automation should
key on a `CCZ-*` code or a machine-readable result field, not on surrounding
human prose.

## First response: preserve and classify

1. Stop using the attempted output directory as a successful result.
   Do not reuse `program.ss`, a packet, or a proxy after the producing command
   returned nonzero.
2. Preserve both stdout and stderr. Agda may render a backend `user error` on
   stdout, so stderr alone is not a complete diagnostic.
3. Extract the stable codes:

   ```sh
   rg -o 'CCZ-[A-Z-]+' attempt.stdout attempt.stderr | sort -u
   ```

4. Inspect, when present, `staging.txt`, `typed-residual.txt`, `summary.tsv`,
   `invocation.tsv`, `environment.tsv`, and `publication.tsv`.
5. Reproduce into a new output/evidence directory. A new backend invocation
   deliberately clears publishable files in its selected output directory.

The expected top-level classifications are:

| Observation | Meaning |
| --- | --- |
| Exit 0 plus `decision: static-closed` | Static publication succeeded; still verify Chez output and erasure authorization. |
| Nonzero plus `CCZ-RESIDUAL-REQUIRED` and a manifest | Valid typed residual outcome under a policy that does not publish an executable. |
| Nonzero plus another `CCZ-*` code | Controlled backend rejection; use the sections below. |
| `ENGINEERING-PERFORMANCE-FAIL` with complete summaries and `TRANSACTIONAL-PASS` | Valid terminal benchmark evidence that crossed a configured threshold; not a corrupt run. |
| Host/schema/collection error with no publication | Incomplete benchmark; current evidence must remain unchanged. |

## Toolchain and build failures

| Symptom | Check | Safe resolution |
| --- | --- | --- |
| `brew --prefix` or a tool executable is missing | `agda --version`, `ghc --numeric-version`, `cabal --numeric-version`, `chez --version` | Install/select the documented toolchain or override `AGDA_PREFIX`, `GHC_PREFIX`, `AGDA_PACKAGE_DB`, and `GHC`. Do not mix an Agda package database with an incompatible GHC. |
| GHC reports that package `Agda` cannot be found | Confirm `AGDA_PACKAGE_DB` is the package DB belonging to the selected Agda/GHC pair | Point the build at the matching package database, then rerun `make build`. |
| Agda cannot find primitive data | Confirm `Agda_datadir` points to the selected Agda source/install data directory | Set `Agda_datadir` for the invocation. Local 2.8 normally uses the installed Agda data; pinned 2.9 uses `<source>/src/data`. |
| `Agda.cabal not found below AGDA29_SOURCE_DIR` | Check that the variable names the root of the pinned source tree | Correct `AGDA29_SOURCE_DIR`; do not point it at `src/` or a generated build directory. |
| `cubical.agda-lib not found below CUBICAL29_DIR` | Check the pinned Cubical source root | Correct `CUBICAL29_DIR` and keep the supplied tree separate from interface workspaces. |
| Cabal paths disagree through `/tmp` and `/private/tmp` aliases | Compare `pwd -P` for the source path | Use the maintained wrappers, which canonicalize the source root, and a fresh isolated Cabal build directory if the old cache already recorded an inconsistent root. |
| `chez: command not found` | Run `chez --version` | Install/select Chez Scheme 10.4.1 for the verified environment; do not treat missing execution as a compiler PASS. |

Use the local fast gate after resolving the toolchain:

```sh
make verify
```

## CLI and entry selection

| Code | Typical cause | Resolution |
| --- | --- | --- |
| `CCZ-INVALID-CONFIG` | Unknown engine/policy, empty entry/output, packet destination without packet policy, or a non-reject fallback on a non-NbE engine | Compare the invocation with `build/cubical-chez --help`. Public fallback policies are `reject` and `agda-baseline`; candidate-only typed residual disposition is exercised only by candidate gates. |
| `CCZ-ENTRY-REJECTED` | No exact requested entry, multiple suffix matches, arguments/clauses outside the current contract, or a surviving unresolved definition | Use an exact qualified QName when ambiguous. The current formal entry must be closed, zero-argument, and single-clause; module-wide compilation is not implemented. |

An unqualified entry matches one final QName segment. A qualified name is an
exact QName, not a suffix. Failure must leave no new executable Scheme.

## NbE engine failures

| Code | Meaning | Safe next action |
| --- | --- | --- |
| `CCZ-NBE-UNAVAILABLE` | The requested provider is not linked and selected. This is the expected default-binary result today. | Use `agda-baseline` only as an oracle or run the isolated candidate acceptance target. Do not edit the production lock merely to suppress this error. |
| `CCZ-NBE-UNSUPPORTED` | The linked evaluator does not implement the exact checked node/semantic shape. | Keep the default reject, request explicit baseline fallback for oracle-only work, or use the candidate typed-residual acceptance path. Record the node/QName/range evidence. |
| `CCZ-ENGINE-TIMEOUT` | Deterministic evaluator fuel/deadline was exceeded. | Retain the input and timeout evidence. Reducing the test case is valid; silent fallback is not. |
| `CCZ-NBE-FAILED` | Evaluator execution failed, including a detected recursive ground cycle. | Inspect the evaluator-stage/node/QName detail and reproduce with `make verify-failure-taxonomy`; this outcome is not eligible for fallback. |
| `CCZ-ENGINE-RESULT-INVALID` | Readback was open, contained metas, had an invalid type, or failed Agda's final `Term : Type` admission. | Treat it as an evaluator correctness failure. Do not send the term to Treeless or switch to erased Scheme. |

The fallback policy contract can be rerun independently:

```sh
make verify-nbe-fallback
make verify-failure-taxonomy
```

Only `CCZ-NBE-UNSUPPORTED` is eligible for an explicitly requested
`agda-baseline` fallback. Unavailable, timeout, failed, and invalid-result
outcomes never fall back.

## Binding-time, residual, and lowering failures

| Code | Meaning | Evidence to inspect |
| --- | --- | --- |
| `CCZ-UNSUPPORTED` | Internal semantic identity/catalog evidence disagrees, a primitive/definition is unknown, or the reachable closure cannot be classified safely | `staging.txt`, Internal/Treeless blocker inventories, semantic source, QName/range, and primitive catalog version |
| `CCZ-RESIDUAL-REQUIRED` | Checked runtime semantics remain but the selected residual policy does not produce an executable | `typed-residual.txt`, binding-time (`dynamic` or `mixed`), blockers, packet destination, dependency slice |
| `CCZ-RESIDUALIZATION-FAILED` | Packet/manifest construction, dependency recomputation, decode/type self-check, size/version support, or hole materialization failed | producer log, direct/transitive dependency inventories, interface identity, packet policy, Agda version |
| `CCZ-SCHEME-LOWERING-FAILED` | Complete reachable static lowering failed or `chez-core-abi-v1` declaration disagreed with implementation | `treeless.txt`, lowering detail, ABI inventory; no `program.ss` is valid for this attempt |

`manifest` is evidence, not successful executable compilation. A manifest
outcome can intentionally return nonzero while preserving the checked term and
type. `packet` additionally requires the pinned Agda 2.9 codec; the local Agda
2.8 build is expected to reject binary packet publication.

For `t11`/`t11b`, `transpX-Vec` is the current known
`EXPECTED-RESIDUAL`. It must not be erased merely to make Chez output exist.

## Packet producer and consumer failures

Check the boundary in this order:

1. Producer used Agda 2.9 and selected `--cubical-chez-residual=packet`.
2. A custom `--cubical-chez-packet-file` was used only with packet policy;
   `-` means stdout and should leave no packet file.
3. Producer self-decode/typecheck passed before publication.
4. Consumer loaded the same module and full interface identity.
5. Consumer domain matches the packet type before applying the value.

Common results:

| Symptom | Meaning | Action |
| --- | --- | --- |
| `packet output requires an Agda 2.9 build` | Local Agda 2.8 cannot encode the v2 packet | Use the pinned Agda 2.9 gate; do not invent a second packet codec. |
| Wrong magic/version or truncated input | Corrupt or incompatible packet | Regenerate from the pinned producer. The maintained consumer rejects before unsafe decode and caps input at 64 MiB. |
| Module/interface hash mismatch | Packet and consumer signature are not identical | Rebuild producer and consumer from the same pinned source/interface set. |
| Agda `UnequalTypes` or bridge `CCZ-TYPED-BRIDGE-RUNNER-EXIT` | The selected consumer/argument has the wrong checked type | Fix the consumer or codec/branch; do not coerce the erased representation. |
| Pipe produces extra stdout/stderr | Protocol contamination | Ensure the producer/consumer writes only the packet/result channel required by the protocol. |

The canonical higher-order file/pipe reproduction is:

```sh
make verify-formal-transport-higher
```

## Typed bridge and proxy failures

These codes occur after successful backend publication. They describe the
generated shell/bridge/store protocol rather than compiler admission.

| Code | Diagnose first |
| --- | --- |
| `CCZ-TYPED-BRIDGE-CONFIG` | Missing/invalid runner, Agda data, source, include, consumer, packet, or path configuration |
| `CCZ-TYPED-BRIDGE-HOLE-SELECTION` | Empty/unknown stable hole ID or conflicting forcing selectors |
| `CCZ-TYPED-BRIDGE-OBSERVATION` | Missing/duplicate/incomplete batch ID-to-consumer map or conflicting observation mode |
| `CCZ-TYPED-BRIDGE-CALL` | Unsupported callable capability, wrong codec/arity/value/QName/ID, or conflicting call/proxy action |
| `CCZ-TYPED-BRIDGE-ENVIRONMENT` | Lexical value, slot count/order/codec, bound hole, QName, or execution mode does not match the checked telescope |
| `CCZ-TYPED-BRIDGE-PROXY` | Invalid/duplicate/missing/released proxy, parent mismatch, publication conflict, or invalid lifecycle action |
| `CCZ-TYPED-BRIDGE-QUOTA` | Complete-pair count or byte quota would be exceeded, or the store publication lock cannot be acquired/recovered |
| `CCZ-TYPED-BRIDGE-TRANSACTION` | Shared lifecycle lock or atomic state transition could not be validated/completed |
| `CCZ-TYPED-BRIDGE-RUNNER-EXIT` | The checked Agda application/consumer rejected or exited nonzero |
| `CCZ-TYPED-BRIDGE-DIRTY-OUTPUT` | A successful runner emitted stderr, extra lines, or a non-advertised ground result |
| `CCZ-TYPED-BRIDGE-PROTOCOL` | Codec registry/descriptor fingerprint, helper frame, import handle, or decoded response violated the versioned ABI |

Do not manually edit proxy metadata to recover a store. Preserve the packet,
metadata, lock owner, command, and bridge output, then reproduce through the
maintained positive/negative gate. Failed publication must not leave a new
active pair.

## Chez generation and execution failures

| Symptom | Check | Resolution |
| --- | --- | --- |
| `program.ss` is absent | Read the producing exit status and `CCZ-*` code | Absence is expected after residual/unsupported/lowering failure. Fix the source/policy; never run an older file from the directory. |
| `CCZ-SCHEME-LOWERING-FAILED` | Compare declared `chez-core-abi-v1` and primitive inventory | Treat as compiler failure. The ABI mismatch controls intentionally publish zero Scheme. |
| Chez returns a different value | Confirm the exact `program.ss`, `treeless.txt`, `staging.txt`, source hash, and engine provenance belong to one attempt | Re-run the corresponding formal comparator; do not compare output from different directories/runs. |
| Mixed shell reports a bridge code | Use the bridge/proxy table above | The shell must not guess or reconstruct an Agda value outside the checked runner. |
| Chez process is missing or incompatible | `chez --version` | Use the verified Chez 10.4.1 environment or record the new environment as unverified. |

## Performance collection failures

The controlled collector is intentionally stricter than functional tests. Its
host must match `config/nbe-performance-host-profile.tsv`: Apple M4, 10 logical
CPUs, 25,769,803,776 bytes, AC Power, low-power mode off, nominal thermal
state, two consecutive samples with CPU idle at least 75% and memory free at
least 20%.

| Result | Meaning | Action |
| --- | --- | --- |
| Machine/power/thermal/CPU/memory rejection | Host was not comparable | Restore the declared condition and rerun later. The collector should stop before promotion. |
| No sibling pending directory after rejection | Cleanup worked | Confirm the previous current result and archive were unchanged. |
| `ENGINEERING-PERFORMANCE-FAIL` plus complete summary/publication | A measured ratio crossed a profile threshold | Keep and report it as valid failing evidence. Do not change thresholds during the run. |
| `ENGINEERING-PERFORMANCE-PASS` plus `TRANSACTIONAL-PASS` | All configured gates passed and the complete result was promoted | Verify `result-name`, variant, optimization, profile hash, host control, runs, and publication timestamp. |
| O0 and O2 values appear mixed | Wrong result/profile path | O0 uses `formal-transport-performance`; O2 uses `formal-transport-performance-release`. Comparators reject wrong optimization provenance. |

Validate the host contract mechanics without running the 30-minute benchmark:

```sh
make verify-formal-transport-performance-host-self
```

The current accepted O2 invocation records `HOST-PASS`, three runs, and
`ENGINEERING-PERFORMANCE-PASS`; the older O0 narrow threshold failure remains
separate historical evidence.

## Provider identity and promotion failures

`CCZ-NBE-PROMOTION-BLOCKED` is a release-gate diagnostic, not a runtime engine
code. The current content manifest can pass while promotion remains correctly
blocked.

| Diagnostic | Meaning | Required resolution |
| --- | --- | --- |
| Repository/revision/license/owner unresolved | Workspace sources are content-pinned but have no approved VCS/legal identity | Obtain the actual repository URI, immutable revision, approved SPDX/license file, owner, and approval date. Do not fabricate placeholders. |
| Source byte/manifest mismatch | A listed provider source changed | Review the change, regenerate the canonical manifest through the maintained identity workflow, and rerun all affected candidate evidence. Do not edit the hash by guesswork. |
| Eligible source is dirty or revision/origin differs | The claimed immutable identity does not match the worktree | Restore or create the approved clean revision and exact origin before promotion. |
| Selected lock and source identity disagree | Dual-key promotion evidence is inconsistent | Correct the approved records so provider/repository/revision/source/license/owner/date match exactly. |

Run the identity contract:

```sh
make verify-nbe-adapter-source-identity
make check-nbe-production-promotion
```

The second command is expected to return
`CCZ-NBE-PROMOTION-BLOCKED` in the current workspace. Do not change the default
lock to make a troubleshooting check green.

## Official-suite environment differences

Not every upstream-suite difference is a backend regression. Consult
`TEST-RESULTS.md` before changing code or goldens. Current classified examples
include missing GNU `gsed`, GHC REPL optimization/warning configuration for
doctests, and Darwin/toolchain golden differences. Preserve both the canonical
run and any explicitly labeled compatibility run; do not silently rewrite an
upstream expectation.

## Escalation bundle

When a problem remains, provide one self-contained bundle containing:

- the exact command and exit status;
- stdout and stderr;
- source path and SHA-256;
- `agda`, GHC, Cabal, Chez, OS, CPU, and memory versions;
- `staging.txt`, `typed-residual.txt`, `treeless.txt`, and `program.ss` when
  they belong to the same attempt;
- for packets, producer and consumer module/interface identities, packet size
  and SHA-256, and whether transport was file or pipe;
- for performance, profile/environment/invocation/publication files, all
  summaries, and the relevant raw engine/group directory;
- for promotion, the source identity, file list, lock, and validator output.

Keep secrets and unrelated personal paths out of the bundle. Generated
evidence belongs below `build/`; source fixtures must remain free of
`.agdai` files.

`FAILURE_CODES.md` is the normative code reference. `SUPPORT-MATRIX.md`
defines supported versus candidate-only behavior, and
`TEST-RESULTS.md`/`BENCHMARKS.md` contain the accepted evidence.
