# Linked runtime NbE

`src/Cubical/Runtime/Nbe.hs` implements the closed typed Goal 3 runtime core.
`app/Main.hs` is the final-process harness, and `test/GeneratePackets.hs`
constructs audited acceptance packets containing terms rather than scenario
IDs.

Build and run the self-contained gate from the repository root:

```sh
make verify-runtime-nbe
```

Run the external Agda oracle gate with pinned Agda 2.9 and Cubical v0.9
checkouts:

```sh
RUNTIME_NBE_AGDA=/path/to/agda \
RUNTIME_NBE_AGDA_DATADIR=/path/to/Agda-2.9.0/share \
RUNTIME_NBE_CUBICAL_DIR=/path/to/cubical-v0.9 \
RUNTIME_NBE_CCTT_DIR=/path/to/cctt-ba16f375 \
make verify-runtime-nbe-oracle
```

The second gate is deliberately separate because it consumes locked external
source checkouts. Neither command starts Agda from the final runtime binary.
