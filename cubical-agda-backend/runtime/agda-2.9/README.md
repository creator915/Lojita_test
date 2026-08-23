# Agda 2.9 typed-Term runtime overlay

This directory contains the maintained source portion of the v2 runtime. It is
an overlay for the pinned Agda 2.9 source tree, not a copy of the upstream Agda
repository.

Copy the paths below into the same paths in the pinned Agda tree:

- `src/full/Agda/TypeChecking/Primitive/Cubical/Runtime.hs`
- `src/cubical-run/Main.hs`
- `test/CubicalRuntime/`

Append `agda-cubical-run.cabal.fragment` to the executable section of the
pinned `Agda.cabal`, then build `exe:agda-cubical-run`. The runtime source in
this repository already includes the bounded and exception-safe packet decode
changes represented by `compat/agda-2.9/runtime-safe-packet-decode.patch`.

This component implements checked cross-process `Term + Type` transport. It is
not the linked runtime NbE required by goal 3.

The upstream-derived files remain under the Agda license in `LICENSE`.
