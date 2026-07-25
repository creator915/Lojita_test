# Resume from G0

Do not edit the Haskell authority or Rust orchestration code yet.

Current authoritative state:

- branch: `agent/haskell-orchestration-kernel`
- upstream: `98d28aab54ed86714901b6619400598598876dd0`
- baseline release build: PASS
- persistent vendor/V8 and exact binary: PASS
- fresh recovery rehearsal: pending

Resume only by:

1. cloning this branch into a new directory;
2. materializing the seven Library assets named in
   `checkpoints/G0-exact-baseline/README.md`;
3. running `verify-library-assets.sh`;
4. restoring the toolchains under a new prefix;
5. verifying and smoking the restored exact binary;
6. rebuilding the exact source with `build-reference.sh`;
7. rebuilding/testing the frozen Haskell reference;
8. recording all hashes and closing G0.

If any step fails, leave `development_allowed=false` and stop at G0.
