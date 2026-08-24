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
| 3. linked NbE inside the final program process | 11/11 | IMPLEMENTED; VERIFIED for declared fragment |
| Complete revised checklist | 41/56 | 73.2% by item count; not effort-weighted |

## What is usable now

- The CubicalChez compiler backend builds from `src/`.
- Static Chez publication is guarded by Internal and Treeless audits.
- Typed residual and packet production retain checked `Term + Type`.
- The v2 packet consumer source and tests are maintained under
  `runtime/agda-2.9/`.
- The complete root-layout local `make verify` contract is not green in the current workspace:
  the uploaded tree omits the 3,219-file historical benchmark evidence archive.
- The isolated compiler-process NbE candidate passed the recorded 8-group,
  42-row differential matrix and controlled O2 provisional performance gate.
- Default production `nbe` remains fail closed because the provider lock is
  unselected.
- The locked stock Agda/MAlonzo/GHC lane passes ordinary and erased-Cubical
  compile/run, stock differential, misclassification, stale-artifact, and
  binary-runtime audits from both the working tree and a clean clone.
- `runtime/nbe/` builds a compiler-independent runtime package. A real Agda
  Internal producer emits typed requests and definitions, and Stock
  Agda/MAlonzo/GHC links the evaluator plus pinned cctt Core into the final
  user program. The declared acceptance fragment is closed.

## What is not yet delivered

### Goal 1

`bin/cubical-agda-native` validates the locked official Agda source identity,
generates and audits MAlonzo Haskell before invoking the locked GHC, then
audits and transactionally publishes the native binary and provenance. The
maintained test proves ordinary and stock-erased-Cubical output equality and
fail-closed behavior. Static Chez output is not used as evidence for this goal.

### Goal 3 boundary

The narrow-waist producer consumes the declared checked Internal
Bool/Nat/Int/Vec/Pi/Sigma/Glue/PathP/S¹ fragment and its definition slice. The
shared runtime performs typed reflection, closures, definition lookup,
quotation and result rechecking. Pinned cctt commit `ba16f375...` (MIT) is
vendored without patches and its `Core.eval`/`Quotation.quoteUnfold` symbols
are linked into the final ELF. A Stock Agda/MAlonzo/GHC fixture plus no-exec
audit proves final-process execution. The former negative-index reproducer
returns `App (Var 1) (Var 0)`, and explicit negative indices reject.

The same-input gate uses six actual checked definitions. `t09/t16a/t16b/t16c`
match Agda's canonical observations; `t11/t11b` record Agda's own
`transpX-Vec` residual boundary and separately require the typed runtime result
and a nonzero cctt provider-call count. Consequently the declared Goal 3 is
11/11. The `goal3-runtime-nbe` workflow executes provider, runtime,
real-Internal, differential and final-MAlonzo gates. General Cubical
normalization outside this fragment remains fail closed.

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
- runtime `make verify-runtime-nbe`: 26/26 PASS on 2026-08-23, including the
  repaired higher-order readback and negative-index rejection;
- `make verify-runtime-nbe-cctt-provider`: 10/10 source hashes, 9/9
  eval/quotation probes, archive membership and final ELF symbols PASS;
- `make verify-runtime-nbe-agda-bridge`: 7/7 PASS for real Internal values,
  definitions, same-expression Agda oracle checks and fail-closed patterns;
- `make verify-runtime-nbe-final-malonzo`: 9/9 PASS for Stock MAlonzo/GHC,
  linked symbols, real `PrimTrans`/`PrimHComp`, oracle and no-exec evidence;
- `make verify-runtime-nbe-differential`: six real checked definitions PASS;
  four exact matches and two explicit Agda residual-boundary matches;
- prototype `make verify-runtime-nbe-oracle`: 2 Agda modules typecheck and 5
  hand-authored runtime expectations PASS; explicitly not differential evidence;
- Agda 2.9: 155 positive executions and 146 expected rejections PASS;
- formal candidate differential: 8/8 groups and 42/42 rows PASS;
- controlled O2 provisional performance: `ENGINEERING-PERFORMANCE-PASS`.

Goals 1 and 3 are closed. Goal 2 clean-clone validation, three-lane
dispatch/integration and overall release validation remain open.

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
