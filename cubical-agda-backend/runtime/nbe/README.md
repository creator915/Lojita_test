# Runtime NbE narrow waist

`src/Cubical/Runtime/Nbe.hs` implements the compiler-independent semantic
domain. The compiler overlay translates a fail-closed subset of checked Agda
Internal `Term + Type` into `Nbe.Wire`; `Nbe.Embedded` is statically linked into
a Stock Agda/MAlonzo-generated final user program. cctt code is not yet linked.
`app/Main.hs` and `test/GeneratePackets.hs` remain standalone test helpers.

Build and run the self-contained prototype gate from the repository root:

```sh
make verify-runtime-nbe
make verify-runtime-nbe-agda-bridge
make verify-runtime-nbe-final-malonzo
```

Run the external fixture/typecheck correlation gate with pinned Agda 2.9 and
Cubical v0.9 checkouts:

```sh
RUNTIME_NBE_AGDA=/path/to/agda \
RUNTIME_NBE_AGDA_DATADIR=/path/to/Agda-2.9.0/share \
RUNTIME_NBE_CUBICAL_DIR=/path/to/cubical-v0.9 \
RUNTIME_NBE_CCTT_DIR=/path/to/cctt-ba16f375 \
make verify-runtime-nbe-oracle
```

The second gate is deliberately separate because it consumes locked external
source checkouts. It is not a same-input differential test: it typechecks Agda
fixtures and then checks separately hand-written prototype expectations.
That historical correlation command does not close the required full oracle
item. The real bridge/final-program gates are same-expression differentials for
the implemented narrow slice. Goal 3 remains partial at 8/11.
