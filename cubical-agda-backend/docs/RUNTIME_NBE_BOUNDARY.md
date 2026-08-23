# Final-process runtime NbE boundary

This document fixes the process and data boundary for goal 3. The boundary is
implemented by `runtime/nbe/`; `make verify-runtime-nbe` supplies linked
library, final-process and negative-path evidence.

## Process identity

“In process” means the operating-system process created when the user executes
the final published program. The runtime evaluator must be linked into that
executable and called as a library in the same process. The Agda compiler,
`bin/cubical-agda-native`, the CubicalChez compiler plugin, a packet producer,
and a helper executable are not the final user-program process.

The runtime call may not spawn Agda or another evaluator, invoke a network
provider, load the Agda compiler library, call `TCM`/`normalise`, or delegate
through a compiler-process callback. A passing compiler-process adapter test is
therefore never goal 3 evidence.

## Data boundary

The canonical machine-readable boundary is
`config/runtime-nbe-boundary.tsv`. At compile/runtime publication, only
versioned immutable bytes may cross into the final executable. Logically those
bytes contain:

- a checked Internal `Term + Type` pair;
- the closed definition slice required by that pair; and
- a context/interface identity sufficient to reject a mismatched runtime.

The runtime result is either a reified `Term + Type` result or a closed,
versioned error. Semantic values, environments, Haskell closures, `TCState`,
`TCM` actions, live definition handles, and compiler callbacks may not cross
the boundary. `docs/RUNTIME_NBE_ABI.md` assigns concrete encodings, ownership,
versioning and error codes without weakening these rules.

## Acceptance consequence

A goal 3 executable must prove, from final-binary and runtime-trace evidence,
that the linked runtime library handled the request in the final process and
that no Agda/compiler subprocess or callback occurred. The acceptance gate
interposes the supported process-launch entry points and audits source and
binary identities while executing the linked evaluator.
