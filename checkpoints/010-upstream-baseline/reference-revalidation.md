# Reference replay-kernel revalidation

The retained `codex-kernel-hs-0.1.0.0` source archive was restored from its
persistent copy and rebuilt from scratch with the locked toolchain.

Commands:

```text
cabal build all --offline --ghc-options=-Werror
cabal test differential --offline --test-show-details=direct
```

Environment:

- GHC 9.14.1
- Cabal 3.16.1.0
- no Hackage package index or network dependency

Results:

- all 38 library modules compiled with warnings treated as errors;
- the executable linked;
- 23/23 vendored Rust `apply_patch` golden scenarios passed;
- recorded model/tool turn replay passed;
- ordered parallel-output gate passed;
- incremental strict-extension check passed;
- namespaced router check passed;
- Responses Lite image normalization check passed;
- turn-diff normalization check passed.

This validates the old archive as a reusable semantic oracle and fixture set.
It does not promote it to a production authority: it remains a recorded-model
replay program and does not implement the live approval, compaction, agent,
guardian, persistence, or CLI adapter boundary.
