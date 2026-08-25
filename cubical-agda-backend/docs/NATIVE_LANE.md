# Stock Agda / MAlonzo / GHC native lane

This document is the acceptance definition for goal 1. The native lane is
implemented by `bin/cubical-agda-native`; it does not call the CubicalChez
backend and does not consume Scheme output.

## Auditable classification

The lane has exactly two accepted source classes:

1. `ordinary`: the entry module enables no Cubical language mode.
2. `erased-cubical`: the entry module explicitly enables stock Agda's
   `--cubical=erased` (or legacy `--erased-cubical`) mode. Full Cubical and
   `--cubical=no-glue` are rejected. In this class Agda's type checker is the
   authority that every imported full-Cubical definition is used only in an
   erased position.

Both classes must then pass a post-typechecking audit. The locked stock compiler
must emit a `MAlonzo/Code` Haskell tree containing the `MAlonzo.RTE.AgdaAny`
erasure witness. Generated Haskell is rejected if it refers to Agda
compiler/typechecker internals, `TCState`, the CubicalChez NbE implementation,
`primGlue`, or `transpX`. Ordinary output may not contain any Cubical primitive.
In erased-Cubical mode the only permitted `primComp`/`primTransp`/`primHComp`
spellings are the three exact identity stubs emitted by the locked stock Agda
version in its unreferenced `Agda.Primitive.Cubical` support module. A spelling
in any other module or a changed stub body is rejected. The final binary must
contain none of these names, including the permitted generated-only stubs.

This rule is intentionally conservative. “Cubical syntax but statically
eliminated” means only code accepted by stock Agda's erased-Cubical discipline
and absent from the generated runtime closure. It does not mean that an
arbitrary `--cubical` program is normalized by the Chez lane and relabeled as
native.

## Locked compilation and publication

`config/native-toolchain.lock.tsv` fixes the official Agda Git origin,
revision and version, plus the GHC release version and project revision. The
driver requires a clean checkout at that exact Agda revision, validates both
executables, invokes stock Agda once with `--ghc-dont-call-ghc`, audits the
MAlonzo result, and then invokes stock Agda with `--with-compiler` pointing to
the locked GHC. The generated Haskell hashes must remain unchanged across the
GHC invocation.

The final binary is scanned with `file`, `ldd` where available, `nm`, and
`strings`. Qualified Agda `Term`/`Type` implementation modules, `TCState`, the
Agda compiler, the CubicalChez NbE implementation, and `libHSAgda` are all
forbidden. The generic English words “term” and “type” are not meaningful
binary predicates; the audit uses their qualified compiler-runtime identities.

The binary and its provenance, MAlonzo hash manifest, MAlonzo source archive,
and binary audit are published only after every gate passes. A retry first
removes those exact artifact names, so a rejection cannot leave an older
binary presented as the current result.

## Acceptance command

```sh
NATIVE_AGDA=/absolute/path/to/agda \
NATIVE_AGDA_SOURCE_DIR=/absolute/path/to/clean/agda-source \
NATIVE_AGDA_DATA_DIR=/absolute/path/to/agda-data \
NATIVE_GHC=/absolute/path/to/ghc \
make verify-native-lane
```

The acceptance test compiles and runs an ordinary program and an
erased-Cubical program, compares program output and exit status with direct
stock Agda/MAlonzo/GHC baselines, compares a type-error case, verifies a full
Cubical misclassification fails closed, and audits all published evidence.
