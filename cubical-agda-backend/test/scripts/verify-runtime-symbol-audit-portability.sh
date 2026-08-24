#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo_root"

tmp_dir=${TMPDIR:-/tmp}/runtime-symbol-audit.$$
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
mkdir -p "$tmp_dir"
: > "$tmp_dir/binary"

fake_nm=$tmp_dir/nm
printf '%s\n' \
  '#!/bin/sh' \
  'case ${FAKE_NM_MODE:?} in' \
  '  elf)' \
  "    printf '%s\\n' '0000 T _Core_eval_info' '0001 T _Quotation_quoteUnfold_info' '0002 T _CubicalziRuntimeziNbeziCctt_providerTransport_info' ;;" \
  '  macho)' \
  "    printf '%s\\n' '0000 T __Core_eval_info' '0001 T __Quotation_quoteUnfold_info' '0002 T __CubicalziRuntimeziNbeziCctt_providerTransport_info' ;;" \
  '  missing)' \
  "    printf '%s\\n' '0000 T __Core_eval_info' ;;" \
  'esac' > "$fake_nm"
chmod +x "$fake_nm"

for mode in elf macho; do
  FAKE_NM_MODE=$mode NM="$fake_nm" \
    sh test/scripts/check-ghc-symbols.sh "$tmp_dir/binary" \
      _Core_eval_info \
      _Quotation_quoteUnfold_info \
      _CubicalziRuntimeziNbeziCctt_providerTransport_info
done

if FAKE_NM_MODE=missing NM="$fake_nm" \
    sh test/scripts/check-ghc-symbols.sh "$tmp_dir/binary" \
      _Core_eval_info _Quotation_quoteUnfold_info >/dev/null 2>&1; then
  echo "RuntimeSymbolAuditPortability FAIL: missing symbol was accepted" >&2
  exit 1
fi

echo "RuntimeSymbolAuditPortability PASS (ELF and Mach-O GHC symbols; missing symbol rejected)"
