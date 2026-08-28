#!/usr/bin/env python3
"""Portable checks for the cctt symbols retained in GHC link products."""

import re
import platform


_CORE_EVAL = re.compile(r"Core_(?:zdw)?eval_(?:info|closure)(?:\s|$)")
_QUOTE_UNFOLD = re.compile(
    r"Quotation_(?:zdw)?quoteUnfold_(?:info|closure)(?:\s|$)"
)
_ADAPTER_NORMALIZE = re.compile(r"RuntimeNbe\S*normaliz\S*(?:\s|$)")
_STABLE_EVAL_QUOTE = re.compile(
    r"(?:^|\s)_?runtime_nbe_cctt_eval_quote_v1(?:\s|$)"
)


def missing_provider_symbols(symbols, require_adapter=True):
    """Return stable capability names absent from nm output.

    GHC can retain either a public closure/info symbol or only its worker (`$w`,
    encoded as `zdw`) depending on compiler, optimization and object format.  The
    package/unit prefix and Mach-O leading underscore are intentionally ignored,
    while helper names and unrelated quotation/evaluation symbols do not match.
    """

    required = [
        ("cctt Core.eval", _CORE_EVAL),
        ("cctt Quotation.quoteUnfold", _QUOTE_UNFOLD),
    ]
    if require_adapter:
        required.append(("runtime provider adapter", _ADAPTER_NORMALIZE))
    return [label for label, pattern in required if not pattern.search(symbols)]


def missing_final_provider_symbols(symbols):
    """Check the stable C ABI retained by stripped final executables."""

    if _STABLE_EVAL_QUOTE.search(symbols):
        return []
    return ["runtime_nbe_cctt_eval_quote_v1"]


def final_symbol_commands(nm, binary, system=None):
    """Return capability-probed symbol-table commands for a final executable."""

    host = system or platform.system()
    commands = [[nm, "-g", str(binary)]]
    if host != "Darwin":
        commands.append([nm, "-D", "-g", str(binary)])
    return commands
