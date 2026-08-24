#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

bridge=${RUNTIME_NBE_AGDA_BRIDGE:?set RUNTIME_NBE_AGDA_BRIDGE}
runtime=${RUNTIME_NBE_BINARY:?set RUNTIME_NBE_BINARY}
runtime_library=${RUNTIME_NBE_LIBRARY:?set RUNTIME_NBE_LIBRARY}
package_db=${RUNTIME_NBE_PACKAGE_DB:?set RUNTIME_NBE_PACKAGE_DB}
stock_agda=${RUNTIME_NBE_STOCK_AGDA:?set RUNTIME_NBE_STOCK_AGDA}
ghc=${RUNTIME_NBE_GHC:?set RUNTIME_NBE_GHC}
agda_datadir=${RUNTIME_NBE_AGDA_DATADIR:?set RUNTIME_NBE_AGDA_DATADIR}
ldflags=${RUNTIME_NBE_LDFLAGS:-}
bridge_fixture=test/fixtures/runtime-nbe/RuntimeNbeBridge.agda
cubical_fixture=test/fixtures/runtime-nbe/RuntimeNbeCubical.agda
final_fixture=test/fixtures/runtime-nbe/RuntimeNbeFinal.agda
evidence_dir=$(mktemp -d build/runtime-nbe/final-malonzo.XXXXXX)
compile_dir=$evidence_dir/malonzo
packet=$evidence_dir/identity.packet
transp_packet=$evidence_dir/transp.packet
hcomp_packet=$evidence_dir/hcomp.packet
summary=$evidence_dir/summary.tsv

fail() {
  echo "Stock Agda/MAlonzo linked runtime FAIL: $*" >&2
  exit 1
}

ghc_path=$(command -v "$ghc" 2>/dev/null) ||
  fail "GHC command is not available: $ghc"

for file in "$bridge" "$runtime" "$runtime_library" "$stock_agda" \
  "$bridge_fixture" "$cubical_fixture" "$final_fixture"; do
  [ -s "$file" ] || fail "missing input: $file"
done
[ -d "$package_db" ] || fail "missing runtime package DB: $package_db"
[ -x "$bridge" ] || fail "Agda Internal bridge is not executable"
[ -x "$stock_agda" ] || fail "Stock Agda is not executable"
[ -x "$ghc_path" ] || fail "GHC command is not executable: $ghc_path"

printf 'case\tevidence\tstatus\n' > "$summary"

Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries \
  -i test/fixtures/runtime-nbe --no-write-interfaces \
  '--cubical-runtime-nbe-export=λ (value : Bool) → value' \
  "--cubical-runtime-nbe-file=$packet" "$bridge_fixture" \
  > "$evidence_dir/bridge.log" 2>&1 || fail "real Agda Internal export failed"
context=$(sed -n '2s/.*packetContext = "\([^"]*\)".*/\1/p' "$packet")
[ -n "$context" ] || fail "real Agda packet has no compiled-context identity"
printf 'real-internal-packet\t%s\tPASS\n' "$context" >> "$summary"

export_cubical() {
  expression=$1
  output_packet=$2
  wire_constructor=$3
  Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries --cubical \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    "--cubical-runtime-nbe-export=$expression" \
    "--cubical-runtime-nbe-file=$output_packet" "$cubical_fixture" \
    > "$evidence_dir/$expression.bridge.log" 2>&1 ||
    fail "$expression real Agda Cubical export failed"
  grep -Fq "definitionTerm = $wire_constructor" "$output_packet" ||
    fail "$expression was compiler-reduced instead of preserving $wire_constructor"
  Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries --cubical \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    "--cubical-run=$expression" "$cubical_fixture" \
    > "$evidence_dir/$expression.oracle" 2>&1 ||
    fail "$expression Agda oracle failed"
  [ "$(cat "$evidence_dir/$expression.oracle")" = true ] ||
    fail "$expression Agda oracle did not produce true"
}

export_cubical transpBool "$transp_packet" Transp
export_cubical hcompBool "$hcomp_packet" HComp
printf 'real-cubical-internal-oracle\ttransp+hcomp-preserved-and-differential\tPASS\n' >> "$summary"

if Agda_datadir="$agda_datadir" "$bridge" -v0 --no-libraries --cubical \
    -i test/fixtures/runtime-nbe --no-write-interfaces \
    '--cubical-runtime-nbe-export=transpFaceOne' \
    "--cubical-runtime-nbe-file=$evidence_dir/unsupported-face.packet" \
    "$cubical_fixture" > "$evidence_dir/unsupported-face.log" 2>&1; then
  fail "unsupported PrimTrans face was silently accepted"
fi
grep -Fq 'only the canonical phi=i0 rule is supported' \
  "$evidence_dir/unsupported-face.log" ||
  fail "unsupported PrimTrans face did not produce a stable rejection"
[ ! -e "$evidence_dir/unsupported-face.packet" ] ||
  fail "unsupported PrimTrans face published a packet"
printf 'cubical-unsupported-face\tfail-closed-no-packet\tPASS\n' >> "$summary"

set -- --ghc-flag=-hide-all-packages --ghc-flag=-package=base \
  --ghc-flag=-package=text --ghc-flag=-package-db \
  "--ghc-flag=$package_db" --ghc-flag=-package=cubical-runtime-nbe
for flag in $ldflags; do
  set -- "$@" "--ghc-flag=$flag"
done
Agda_datadir="$agda_datadir" "$stock_agda" -v1 --no-libraries \
  -i test/fixtures/runtime-nbe --compile --compile-dir="$compile_dir" \
  "--with-compiler=$ghc" "$@" "$final_fixture" \
  > "$evidence_dir/compile.log" 2>&1 || fail "Stock Agda/MAlonzo/GHC compile failed"

final_binary=$compile_dir/RuntimeNbeFinal
generated_source=$compile_dir/MAlonzo/Code/RuntimeNbeFinal.hs
[ -x "$final_binary" ] || fail "MAlonzo final executable is missing"
grep -Fq 'import qualified Cubical.Runtime.Nbe.Embedded as RuntimeNbe' "$generated_source" ||
  fail "generated MAlonzo module does not import the linked runtime"
grep -Fq 'RuntimeNbe.runEmbedded' "$generated_source" ||
  fail "generated MAlonzo main does not call the linked runtime"
printf 'stock-agda-malonzo-ghc\t%s\tPASS\n' "$final_binary" >> "$summary"

ar t "$runtime_library" | grep -Fxq 'Embedded.o' ||
  fail "static runtime package lacks Embedded.o"
ar t "$runtime_library" | grep -Fxq 'Wire.o' ||
  fail "static runtime package lacks the shared wire implementation"
nm -g "$final_binary" | grep -Fq 'CubicalziRuntimeziNbeziEmbedded_runEmbedded' ||
  fail "final executable lacks the in-process runtime entry-point symbol"
strings "$final_binary" | grep -Fq 'cctt-informed-agda-runtime-v1@ba16f3758a322e9be77ada1da2b93f45d500192e' ||
  fail "final executable lacks the locked provider marker"
if strings "$final_binary" | grep -Eq 'Agda\.TypeChecking|TCState|normalise|Agda\.Compiler'; then
  fail "final executable contains an Agda compiler identity"
fi
if rg -n 'System\.Process|createProcess|callProcess|readProcess|unsafePerformIO' \
    runtime/nbe/src "$final_fixture"; then
  fail "linked runtime source contains a process/compiler escape"
fi
printf 'linked-runtime-symbols\tarchive-and-final-ELF\tPASS\n' >> "$summary"

cc -shared -fPIC -Wall -Werror -o "$evidence_dir/noexec.so" \
  test/fixtures/runtime-nbe/noexec.c
: > "$evidence_dir/noexec.log"
CCZ_NOEXEC_LOG="$evidence_dir/noexec.log" \
LD_PRELOAD="$repo_root/$evidence_dir/noexec.so" \
  "$final_binary" "$context" "$packet" > "$evidence_dir/final.out" ||
  fail "no-exec guarded MAlonzo final program failed"
[ ! -s "$evidence_dir/noexec.log" ] || fail "final program attempted a subprocess"
expected=$(printf 'OK\tLam TyBool (Var 0)\tTyPi TyBool TyBool\t')
grep -Fq "$expected" "$evidence_dir/final.out" ||
  fail "final program output mismatch"
printf 'in-process-no-exec\tzero-exec-attempts\tPASS\n' >> "$summary"

for cubical_packet in "$transp_packet" "$hcomp_packet"; do
  cubical_context=$(sed -n '2s/.*packetContext = "\([^"]*\)".*/\1/p' "$cubical_packet")
  CCZ_NOEXEC_LOG="$evidence_dir/noexec.log" \
  LD_PRELOAD="$repo_root/$evidence_dir/noexec.so" \
    "$final_binary" "$cubical_context" "$cubical_packet" \
    > "$cubical_packet.final.out" ||
    fail "MAlonzo final program rejected a real Cubical packet"
  cubical_expected=$(printf 'OK\tBoolLit True\tTyBool\t')
  grep -Fq "$cubical_expected" "$cubical_packet.final.out" ||
    fail "MAlonzo final program produced the wrong Cubical result"
done
[ ! -s "$evidence_dir/noexec.log" ] ||
  fail "final Cubical evaluation attempted a subprocess"
printf 'cubical-final-in-process\ttransp+hcomp-zero-exec\tPASS\n' >> "$summary"

"$runtime" "$context" "$packet" > "$evidence_dir/standalone.out" ||
  fail "standalone runtime rejected the same real packet"
cmp -s "$evidence_dir/final.out" "$evidence_dir/standalone.out" ||
  fail "linked and standalone runtimes disagree on the same real packet"
printf 'same-packet-equivalence\tlinked-equals-standalone\tPASS\n' >> "$summary"

if "$final_binary" wrong-compiled-context-v1 "$packet" \
    > "$evidence_dir/context-mismatch.out" 2>&1; then
  fail "final program accepted the wrong compiled context"
fi
grep -Fq 'CCZ-RUNTIME-NBE-CONTEXT-MISMATCH' "$evidence_dir/context-mismatch.out" ||
  fail "final program did not fail closed on context mismatch"
printf 'context-mismatch\tfail-closed\tPASS\n' >> "$summary"

pass_count=$(awk -F '\t' 'NR > 1 && $3 == "PASS" { count++ } END { print count + 0 }' "$summary")
[ "$pass_count" -eq 9 ] || fail "expected 9 PASS rows, observed $pass_count"

echo "RuntimeNbeFinalMalonzo PASS ($pass_count; evidence $evidence_dir)"
