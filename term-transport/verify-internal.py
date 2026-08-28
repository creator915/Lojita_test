#!/usr/bin/env python3
"""Verify the minimum real Agda Internal Term+Type cross-process bridge."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
FIXTURE = ROOT / "fixtures" / "InternalNat.agda"
BRIDGE_SOURCE = ROOT / "agda-bridge"
FORMAL_VERIFY = ROOT / "examples" / "approval-handoff" / "verify.py"


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def bridge_inputs():
    return sorted([
        ROOT / "build-internal.py",
        BRIDGE_SOURCE / "agda-source.lock.json",
        BRIDGE_SOURCE / "agda-term-bridge.cabal",
        *(BRIDGE_SOURCE / "src").rglob("*.hs"),
    ])


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def git_identity():
    result = subprocess.run(
        ["git", "-C", str(ROOT.parent), "rev-parse", "HEAD"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def bridge_command(binary, source, packet, mode, expression=None):
    command = [
        str(binary), "--no-libraries", "--ignore-interfaces",
        "-i", str(source.parent),
    ]
    if mode == "export":
        command.extend(["--term-export", expression])
    else:
        command.append("--term-import")
    command.extend(["--term-packet", str(packet), str(source)])
    return command


def run_bridge(command):
    process = subprocess.Popen(
        command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT
    )
    output, _ = process.communicate(timeout=30)
    return process.pid, process.returncode, output


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge-bin", default=os.environ.get("TERM_BRIDGE_BIN"))
    parser.add_argument("--provenance")
    return parser.parse_args(argv)


def verify_provenance(binary, requested):
    provenance_path = (
        Path(requested).expanduser().resolve()
        if requested else binary.parent.parent / "provenance.json"
    )
    require(provenance_path.is_file(), "bridge build provenance is missing")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    require(provenance["binary"]["sha256"] == sha256_file(binary), "bridge binary hash mismatch")
    lock = json.loads(
        (BRIDGE_SOURCE / "agda-source.lock.json").read_text(encoding="utf-8")
    )
    bridge_source = (
        BRIDGE_SOURCE / "src" / "TermTransport" / "Bridge.hs"
    ).read_text(encoding="utf-8")
    require(lock["revision"] in bridge_source, "packet does not bind the locked provider revision")
    require(provenance["agda"]["revision"] == lock["revision"], "Agda revision mismatch")
    require(
        provenance["agda"]["cabal_sha256"] == lock["agda_cabal_sha256"],
        "Agda.cabal evidence mismatch",
    )
    require(
        provenance["agda"]["license_sha256"] == lock["license_sha256"],
        "Agda license evidence mismatch",
    )
    actual_sources = {
        str(path.relative_to(ROOT)): sha256_file(path)
        for path in bridge_inputs()
    }
    require(
        provenance["bridge_source_sha256"] == actual_sources,
        "bridge source/provenance mismatch",
    )
    return provenance


def main(argv=None):
    args = parse_args(argv)
    require(args.bridge_bin, "provide --bridge-bin or TERM_BRIDGE_BIN")
    binary = Path(args.bridge_bin).expanduser().resolve()
    require(binary.is_file(), "bridge binary does not exist")
    provenance = verify_provenance(binary, args.provenance)
    fixture_before = sha256_file(FIXTURE)
    version = subprocess.run(
        [str(binary), "--version"], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    require(version.returncode == 0, "bridge --version failed")

    print("verify-term-internal: commit=" + git_identity())
    print("verify-term-internal: python=" + sys.version.splitlines()[0])
    print("evidence: bridge-sha256=" + sha256_file(binary))
    print("evidence: " + version.stdout.splitlines()[0])
    print("evidence: ghc=" + provenance["tools"]["ghc"])
    print("evidence: agda-revision=" + provenance["agda"]["revision"])
    print("evidence: fixture-sha256=" + sha256_file(FIXTURE))

    bridge_source = (
        BRIDGE_SOURCE / "src" / "TermTransport" / "Bridge.hs"
    ).read_text(encoding="utf-8")
    require("Agda.Syntax.Internal (Term, Type)" in bridge_source, "real Internal types are not imported")
    require("CheckInternal.checkType ty" in bridge_source, "Internal Type recheck is absent")
    require("CheckInternal.checkInternal term CmpLeq ty" in bridge_source, "Internal Term recheck is absent")
    wire_declarations = bridge_source.split("data WireTerm", 1)[1].split("bridgeMagic", 1)[0]
    require("TCState" not in wire_declarations and "TCM" not in wire_declarations, "process state entered packet type")
    print("PASS compiled bridge source binds real Internal Term+Type without process state")

    with tempfile.TemporaryDirectory(prefix="term-internal-verify-") as temporary:
        work = Path(temporary)
        source = work / "InternalNat.agda"
        shutil.copy2(FIXTURE, source)
        packet = work / "term.packet"

        producer_pid, code, output = run_bridge(
            bridge_command(binary, source, packet, "export", "value")
        )
        require(code == 0, output)
        require(packet.is_file() and packet.stat().st_size > 0, "producer emitted no packet")
        require("EXPORTED real Agda Internal Term+Type" in output, "producer bridge was not exercised")
        consumer_pid, code, output = run_bridge(
            bridge_command(binary, source, packet, "import")
        )
        require(code == 0, output)
        require(producer_pid != consumer_pid != os.getpid(), "producer/consumer were not separate processes")
        require("RECHECKED real Agda Internal Term+Type" in output, "consumer recheck was not exercised")
        require("7" in output.splitlines(), "reconstructed Internal Nat did not evaluate to 7")
        print("evidence: packet-sha256=" + sha256_file(packet))
        print("PASS real Agda Internal Nat Term+Type crosses two processes and rechecks")

        other_packet = work / "other.packet"
        _, code, output = run_bridge(
            bridge_command(binary, source, other_packet, "export", "other")
        )
        require(code == 0, output)
        original = bytearray(packet.read_bytes())
        alternative = other_packet.read_bytes()
        differences = [
            index for index, (left, right) in enumerate(zip(original, alternative))
            if left != right
        ]
        require(len(original) == len(alternative) and differences, "could not locate encoded Nat payload")
        original[differences[0]] = alternative[differences[0]]
        corrupted = work / "corrupted.packet"
        corrupted.write_bytes(original)
        _, code, output = run_bridge(
            bridge_command(binary, source, corrupted, "import")
        )
        require(code != 0 and "content integrity mismatch" in output, "decodable payload corruption was accepted")
        print("PASS decodable packet payload corruption fails content integrity")

        bool_packet = work / "bool.packet"
        _, code, output = run_bridge(
            bridge_command(binary, source, bool_packet, "export", "flag")
        )
        require(code == 0, output)
        _, code, output = run_bridge(
            bridge_command(binary, source, bool_packet, "import")
        )
        require(code == 0 and "true" in output.splitlines(), "Internal Bool did not round-trip")
        print("PASS real Agda Internal Bool Term+Type round-trips")

        function_packet = work / "function.packet"
        _, code, output = run_bridge(
            bridge_command(binary, source, function_packet, "export", "identity")
        )
        require(code == 0, output)
        _, code, output = run_bridge(
            bridge_command(binary, source, function_packet, "import")
        )
        require(code == 0 and "RECHECKED real Agda Internal Term+Type" in output, "closed function did not recheck")
        print("PASS closed Internal function Term+Type round-trips")

        meta_packet = work / "meta.packet"
        _, code, output = run_bridge(
            bridge_command(binary, source, meta_packet, "export", "λ value → value")
        )
        require(code != 0, "underconstrained term was accepted")
        require(not meta_packet.exists(), "underconstrained term published a packet")
        print("PASS underconstrained Internal term fails closed without a packet")

        truncated = work / "truncated.packet"
        truncated.write_bytes(packet.read_bytes()[:-3])
        _, code, output = run_bridge(
            bridge_command(binary, source, truncated, "import")
        )
        require(code != 0 and "malformed packet" in output, "truncated packet was accepted")
        print("PASS malformed real bridge packet fails closed")

        trailing = work / "trailing.packet"
        trailing.write_bytes(packet.read_bytes() + b"trailing")
        _, code, output = run_bridge(
            bridge_command(binary, source, trailing, "import")
        )
        require(code != 0 and "trailing bytes" in output, "trailing packet data was accepted")
        print("PASS trailing bridge packet data fails closed")

        oversized = work / "oversized.packet"
        oversized.write_bytes(b"x" * (1024 * 1024 + 1))
        _, code, output = run_bridge(
            bridge_command(binary, source, oversized, "import")
        )
        require(code != 0 and "byte limit" in output, "oversized packet was accepted")
        print("PASS bridge packet byte limit fails closed")

        source.write_text(
            source.read_text(encoding="utf-8").replace("value = 7", "value = 9"),
            encoding="utf-8",
        )
        _, code, output = run_bridge(
            bridge_command(binary, source, packet, "import")
        )
        require(code != 0 and "interface hash mismatch" in output, "changed module identity was accepted")
        print("PASS changed Agda module/interface identity fails closed")

        other_source = work / "OtherNat.agda"
        other_source.write_text(
            FIXTURE.read_text(encoding="utf-8").replace("module InternalNat", "module OtherNat"),
            encoding="utf-8",
        )
        _, code, output = run_bridge(
            bridge_command(binary, other_source, packet, "import")
        )
        require(code != 0 and "top-level module mismatch" in output, "wrong module was accepted")
        print("PASS top-level Agda module mismatch fails closed")

        stale_source = work / "stale" / "InternalNat.agda"
        stale_source.parent.mkdir()
        shutil.copy2(FIXTURE, stale_source)
        stale_packet = work / "stale.packet"
        stale_packet.write_text("keep", encoding="utf-8")
        _, code, output = run_bridge(
            bridge_command(binary, stale_source, stale_packet, "export", "value")
        )
        require(code != 0 and "already exists" in output, "stale packet was overwritten")
        require(stale_packet.read_text(encoding="utf-8") == "keep", "stale packet changed")
        print("PASS existing bridge packet is never overwritten")

    require(sha256_file(FIXTURE) == fixture_before, "fixture changed")
    print("PASS real bridge tests leave repository inputs unchanged")

    formal = subprocess.run(
        [sys.executable, str(FORMAL_VERIFY), "--bridge-bin", str(binary)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    require(formal.returncode == 0, formal.stdout)
    require("verify-approval-handoff: 7/7 PASS" in formal.stdout, "formal Term project did not finish")
    print(formal.stdout.rstrip())
    print("PASS formal structured approval handoff project")
    print("verify-term-internal: 14/14 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-term-internal: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
