#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

agda=${RUNTIME_NBE_AGDA:?set RUNTIME_NBE_AGDA to the locked Agda 2.9 executable}
agda_datadir=${RUNTIME_NBE_AGDA_DATADIR:?set RUNTIME_NBE_AGDA_DATADIR to the Agda 2.9 data directory}
cubical_dir=${RUNTIME_NBE_CUBICAL_DIR:?set RUNTIME_NBE_CUBICAL_DIR to the clean Cubical v0.9 checkout}
cctt_dir=${RUNTIME_NBE_CCTT_DIR:?set RUNTIME_NBE_CCTT_DIR to the clean locked cctt checkout}
runtime_binary=${RUNTIME_NBE_BINARY:-build/runtime-nbe/cubical-runtime-nbe}
evidence_dir=build/runtime-nbe/oracle
runtime_summary=build/runtime-nbe/acceptance/summary.tsv

mkdir -p "$evidence_dir"

fail() {
  echo "runtime NbE oracle acceptance failed: $*" >&2
  exit 1
}

"$agda" --version | grep -Fq 'Agda version 2.9.0' ||
  fail "oracle compiler is not Agda 2.9.0"
[ "$(git -C "$cubical_dir" rev-parse HEAD)" = b150186d2544e7efeddd31e5d14a8b9ecbb100f7 ] ||
  fail "Cubical oracle is not pinned v0.9"
[ "$(git -C "$cctt_dir" rev-parse HEAD)" = ba16f3758a322e9be77ada1da2b93f45d500192e ] ||
  fail "cctt provider revision is not pinned"
[ "$(git -C "$cctt_dir" remote get-url origin)" = https://github.com/AndrasKovacs/cctt.git ] ||
  fail "cctt provider origin is not official"
[ "$(git -C "$cctt_dir" archive --format=tar HEAD | sha256sum | awk '{ print $1 }')" = \
  8d83adcb45ea827583f02fb6fb5c7d023ae97fdf6dd7816e9069ee45c67b6b5d ] ||
  fail "cctt provider source archive identity drifted"
cmp -s "$cctt_dir/LICENSE.txt" runtime/nbe/third-party/cctt-LICENSE.txt ||
  fail "vendored cctt license differs from the locked upstream"
[ "$(sha256sum test/fixtures/transport/TransportBoundary.agda | awk '{ print $1 }')" = \
  0bbb91a08fdb760038784ba6a26b5c31497670cf59f01b676376c19c7592ea09 ] ||
  fail "TransportBoundary source identity drifted"
[ "$(sha256sum test/fixtures/transport/TransportHigher.agda | awk '{ print $1 }')" = \
  ccf39914a2ddb7a00333d7e98559f5f3d8ad054250412f8067e751207a58e525 ] ||
  fail "TransportHigher source identity drifted"

Agda_datadir="$agda_datadir" "$agda" --no-libraries --cubical --safe \
  -i "$cubical_dir" -i test/fixtures/transport \
  test/fixtures/transport/TransportBoundary.agda \
  > "$evidence_dir/TransportBoundary.log" 2>&1
Agda_datadir="$agda_datadir" "$agda" --no-libraries --cubical --safe \
  -i "$cubical_dir" -i test/fixtures/transport \
  test/fixtures/transport/TransportHigher.agda \
  > "$evidence_dir/TransportHigher.log" 2>&1

for scenario in t11 t11b t16a t16b t16c; do
  awk -F '\t' -v scenario="$scenario" '
    $1 == scenario && $4 == "PASS" { found++ }
    END { exit !(found == 1) }
  ' "$runtime_summary" || fail "$scenario runtime result is missing"
done

rg -F 't11 : Vec Bool 2' test/fixtures/transport/TransportBoundary.agda >/dev/null ||
  fail "t11 oracle declaration missing"
rg -F 'e11 = false ∷v (true ∷v []v)' test/fixtures/transport/TransportBoundary.agda >/dev/null ||
  fail "t11 documented runtime target drifted"
if rg -q '^_ : t11 ≡ e11$' test/fixtures/transport/TransportBoundary.agda; then
  fail "t11 must remain an explicit stock-residual boundary, not a fake refl oracle"
fi
rg -F '_ : t11b ≡ e11b' test/fixtures/transport/TransportBoundary.agda >/dev/null ||
  fail "t11b propositional oracle missing"
rg -F 'e11b = true ∷v (false ∷v []v)' test/fixtures/transport/TransportBoundary.agda >/dev/null ||
  fail "t11b expected value drifted"
for proof in 't16a ≡ e16a' 't16b ≡ e16b' 't16c ≡ e16c'; do
  rg -F "$proof" test/fixtures/transport/TransportHigher.agda >/dev/null ||
    fail "$proof oracle missing"
done
rg -F 'e16a = true' test/fixtures/transport/TransportHigher.agda >/dev/null ||
  fail "t16a expected value drifted"
[ "$(rg -Fc 'e16b = pos 2' test/fixtures/transport/TransportHigher.agda)" -eq 1 ] ||
  fail "t16b expected value drifted"
[ "$(rg -Fc 'e16c = pos 2' test/fixtures/transport/TransportHigher.agda)" -eq 1 ] ||
  fail "t16c expected value drifted"

printf 'scenario\tagda-oracle\truntime\tstatus\n' > "$evidence_dir/summary.tsv"
printf 't11\ttypechecks-with-stock-residual\tcanonical-Vec-not\tBOUNDARY-PASS\n' >> "$evidence_dir/summary.tsv"
printf 't11b\tpropositionally-equal-e11b\tcanonical-e11b\tDIFFERENTIAL-PASS\n' >> "$evidence_dir/summary.tsv"
printf 't16a\trefl-true\ttrue\tDIFFERENTIAL-PASS\n' >> "$evidence_dir/summary.tsv"
printf 't16b\trefl-pos-2\tint-2\tDIFFERENTIAL-PASS\n' >> "$evidence_dir/summary.tsv"
printf 't16c\trefl-pos-2\tint-2\tDIFFERENTIAL-PASS\n' >> "$evidence_dir/summary.tsv"

[ -x "$runtime_binary" ] || fail "linked runtime executable is missing"
echo "RuntimeNbeOracle PASS (2 Agda modules, 5 runtime scenarios)"
