# Project status

Last updated: 2026-08-23 (Asia/Shanghai)

## Executive status

The repository now follows the three-lane product definition in
[`GOALS.md`](../GOALS.md). The old 224/321 counter described a narrower
Chez/compiler-process-NbE scope and is retired.

| Goal | Checklist | Status |
| --- | ---: | --- |
| 1. stock Agda -> MAlonzo -> erased Haskell -> native binary | 9/9 | IMPLEMENTED; VERIFIED |
| 2. cross-process checked `Term + Type` | 8/9 | IMPLEMENTED; clean-clone gate open |
| 3. linked NbE inside the final program process | 11/11 | IMPLEMENTED; VERIFIED |
| Complete revised checklist | 43/56 | 76.8% by item count; not effort-weighted |

## What is usable now

- The CubicalChez compiler backend builds from `src/`.
- Static Chez publication is guarded by Internal and Treeless audits.
- Typed residual and packet production retain checked `Term + Type`.
- The v2 packet consumer source and tests are maintained under
  `runtime/agda-2.9/`.
- The complete root-layout local `make verify` contract passes on 2026-08-23.
- The isolated compiler-process NbE candidate passed the recorded 8-group,
  42-row differential matrix and controlled O2 provisional performance gate.
- Default production `nbe` remains fail closed because the provider lock is
  unselected.
- The locked stock Agda/MAlonzo/GHC lane passes ordinary and erased-Cubical
  compile/run, stock differential, misclassification, stale-artifact, and
  binary-runtime audits from both the working tree and a clean clone.
- The final-process typed NbE library is locked to the cctt algorithm source,
  linked into its executable, and passes 24 in-process/negative/link tests plus
  the pinned Agda oracle gate for `t11/t11b/t16`.

## What is not yet delivered

### Goal 1

`bin/cubical-agda-native` validates the locked official Agda source identity,
generates and audits MAlonzo Haskell before invoking the locked GHC, then
audits and transactionally publishes the native binary and provenance. The
maintained test proves ordinary and stock-erased-Cubical output equality and
fail-closed behavior. Static Chez output is not used as evidence for this goal.

### Goal 3

`runtime/nbe/` supplies a standalone typed runtime core, static archive and
final executable. It validates the ABI/provider/context and definition slice,
evaluates with request-local environments, closures and cache, implements the
audited Glue/Pi/Sigma/Vec/HIT/Kan fragment, quotes by type and rechecks the
quoted term. Fuel, allocation and packet caps fail closed.

The selected algorithm source is cctt commit `ba16f375...`, MIT. cctt is not a
drop-in Agda library; the linked code is the approved backend-owned adapter.
The compiler-process candidate is still separate and supplies no Goal 3
evidence. Three-lane scheduling into this runtime remains open in checklist F.

## Repository state

The Git delivery tree contains project code, maintained tests, configuration,
runtime overlay source, technical documentation, and the two root-level
authority documents. Raw chats, temporary answers, old reports, generated
evidence, and ZIP archives are not tracked.

Generated files live under `build/` and are not build inputs.

## Verification snapshot

The current and retained candidate evidence is:

- root-layout local `make verify`: PASS on 2026-08-23;
- goal 1 `make verify-native-lane`: PASS on 2026-08-23, including a separate
  clean clone from local commit `7578f56`;
- goal 3 `make verify-runtime-nbe`: 24/24 PASS on 2026-08-23;
- goal 3 `make verify-runtime-nbe-oracle`: 2 Agda modules and 5 runtime
  scenarios PASS on 2026-08-23;
- Agda 2.9: 155 positive executions and 146 expected rejections PASS;
- formal candidate differential: 8/8 groups and 42/42 rows PASS;
- controlled O2 provisional performance: `ENGINEERING-PERFORMANCE-PASS`.

Goal 1 and Goal 3 component gates are closed. Goal 2 clean-clone validation,
three-lane dispatch/integration and overall release validation remain open.

## Reproduce the current root contract

```sh
make build
make verify-status-guide
make verify-readme-guide
make verify-readme-quickstart
```

Pinned Agda 2.9 and formal commands require the variables documented in
[`README.md`](../README.md).

## Maintenance contract

1. Update `GOALS.md` only when the product boundary changes.
2. Update `DELIVERY_CHECKLIST.md` whenever implementation or acceptance state
   changes.
3. Do not mark goal 1 complete using Chez output.
4. Do not mark goal 3 complete using compiler-process NbE evidence.
5. Record a new test result only after the corresponding command passes from
   the committed root layout.
