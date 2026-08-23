# Runtime NbE prototype

`src/Cubical/Runtime/Nbe.hs` implements a closed custom-AST evaluator prototype.
It does not consume Agda Internal `Term + Type` and does not link cctt code.
`app/Main.hs` is a command-line test harness, not an Agda/MAlonzo-generated
final user program. `test/GeneratePackets.hs` hand-constructs prototype packets.

Build and run the self-contained prototype gate from the repository root:

```sh
make verify-runtime-nbe
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
Neither command is Goal 3 acceptance evidence.
