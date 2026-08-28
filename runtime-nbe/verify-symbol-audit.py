#!/usr/bin/env python3
"""Regression tests for cross-GHC and cross-object-format symbol auditing."""

import sys
from pathlib import Path

from symbol_audit import (
    final_symbol_commands, missing_final_provider_symbols, missing_provider_symbols,
)


DARWIN_DIRECT = """
000000010009fc08 T _unit_Core_eval_info
0000000100eb7080 D _unit_Quotation_quoteUnfold_closure
000000010000b498 T _unit_RuntimeNbeziCcttProvider_normalizzeCheckedDefinition_info
"""

ELF_WORKERS = """
000000000009fc08 T unit_Core_zdweval_info
0000000000280c28 T unit_Quotation_zdwquoteUnfold_info
000000000000b498 T unit_RuntimeNbeziCcttProvider_normalizzeCheckedDefinition_info
"""

STRIPPED_FINAL = """
0000000000000000 T runtime_nbe_cctt_eval_quote_v1
"""

PROVIDER_CABAL = (
    Path(__file__).resolve().parent / "provider-adapter" /
    "cctt-runtime-provider.cabal"
)


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def main():
    require(not missing_provider_symbols(DARWIN_DIRECT),
            "Darwin direct symbols were rejected")
    print("PASS Darwin direct eval/quote/adapter symbols")

    require(not missing_provider_symbols(ELF_WORKERS),
            "ELF worker symbols were rejected")
    print("PASS ELF worker eval/quote/adapter symbols")

    require(not missing_final_provider_symbols(STRIPPED_FINAL),
            "stable stripped-final provider ABI was rejected")
    print("PASS stripped final binary stable provider ABI")

    require(
        "runtime_nbe_cctt_eval_quote_v1" in missing_final_provider_symbols(
            "000 T runtime_nbe_cctt_eval_quote_v1_helper"
        ),
        "similarly named stable ABI helper was accepted",
    )
    print("PASS similarly named stable ABI helper is rejected")

    quote_helper = ELF_WORKERS.replace(
        "Quotation_zdwquoteUnfold_info", "Quotation_quoteUnfoldHelper_info"
    )
    require("cctt Quotation.quoteUnfold" in missing_provider_symbols(quote_helper),
            "quoteUnfold helper was accepted as the provider operation")
    print("PASS similarly named quote helper is rejected")

    eval_helper = ELF_WORKERS.replace("Core_zdweval_info", "Core_evalBoundary_info")
    require("cctt Core.eval" in missing_provider_symbols(eval_helper),
            "eval boundary helper was accepted as Core.eval")
    print("PASS similarly named eval helper is rejected")

    no_adapter = "\n".join(ELF_WORKERS.splitlines()[:3])
    require("runtime provider adapter" in missing_provider_symbols(no_adapter),
            "provider symbols without the adapter were accepted")
    require(not missing_provider_symbols(no_adapter, require_adapter=False),
            "policy binary incorrectly required an exported adapter symbol")
    print("PASS adapter requirement is explicit for archive/provider audits")

    cabal = PROVIDER_CABAL.read_text(encoding="utf-8")
    require(
        cabal.count(
            "-optl-Wl,--undefined=runtime_nbe_cctt_eval_quote_v1"
        ) == 2,
        "both Linux final executables must force the stable ABI archive member",
    )
    require(
        cabal.count(
            "-optl-Wl,--export-dynamic-symbol=runtime_nbe_cctt_eval_quote_v1"
        ) == 2,
        "both Linux final executables must export the stable ABI",
    )
    print("PASS Linux final links force and export the stable provider ABI")

    require(final_symbol_commands("nm", "program", "Darwin") ==
            [["nm", "-g", "program"]],
            "Darwin final audit unexpectedly selected a GNU dynamic table")
    require(final_symbol_commands("nm", "program", "Linux") == [
        ["nm", "-g", "program"], ["nm", "-D", "-g", "program"],
    ], "Linux final audit did not merge regular and dynamic tables")
    print("PASS final symbol-table probing follows Darwin and GNU nm contracts")

    print("verify-symbol-audit: 9/9 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-symbol-audit: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
