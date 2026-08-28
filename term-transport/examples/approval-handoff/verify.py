#!/usr/bin/env python3
"""Independent real-process verification for the approval handoff Term path."""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PROJECT = Path(__file__).resolve().parent
TERM_ROOT = PROJECT.parent.parent
SOURCE_ROOT = PROJECT / "src"
ENTRY_RELATIVE = Path("HandoffMain.agda")
BRIDGE_SOURCE = TERM_ROOT / "agda-bridge"


EXPECTED = {
    "approvedEnvelope": """envelope "REQ-300" "alice" 8000 sales true
(review "bob" operations accept "budget checked" ∷
 review "carol" operations accept "invoice checked" ∷
 review "diana" sales accept "strategic approval" ∷ [])
("customer-event" ∷ "priority" ∷ []) 4""",
    "pendingEnvelope": """envelope "REQ-301" "alice" 8000 engineering false
(review "bob" operations accept "budget checked" ∷ [])
("equipment" ∷ []) 2""",
    "deniedEnvelope": """envelope "REQ-302" "erin" 3200 operations false
(review "bob" operations accept "budget checked" ∷
 review "carol" operations deny "missing receipt" ∷ [])
("training" ∷ "receipt-required" ∷ []) 3""",
    "handoffBatch": """envelope "REQ-300" "alice" 8000 sales true
(review "bob" operations accept "budget checked" ∷
 review "carol" operations accept "invoice checked" ∷
 review "diana" sales accept "strategic approval" ∷ [])
("customer-event" ∷ "priority" ∷ []) 4
∷
envelope "REQ-301" "alice" 8000 engineering false
(review "bob" operations accept "budget checked" ∷ [])
("equipment" ∷ []) 2
∷
envelope "REQ-302" "erin" 3200 operations false
(review "bob" operations accept "budget checked" ∷
 review "carol" operations deny "missing receipt" ∷ [])
("training" ∷ "receipt-required" ∷ []) 3
∷ []""",
    "summarise approvedEnvelope": 'summary "REQ-300" 8000 3 readyToPay',
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def bridge_inputs():
    return sorted([
        TERM_ROOT / "build-internal.py",
        BRIDGE_SOURCE / "agda-source.lock.json",
        BRIDGE_SOURCE / "agda-term-bridge.cabal",
        *(BRIDGE_SOURCE / "src").rglob("*.hs"),
    ])


def verify_provenance(binary, requested):
    provenance_path = (
        Path(requested).expanduser().resolve()
        if requested else binary.parent.parent / "provenance.json"
    )
    require(provenance_path.is_file(), "bridge provenance is missing")
    provenance = json.loads(provenance_path.read_text(encoding="utf-8"))
    require(provenance["binary"]["sha256"] == digest(binary), "bridge binary hash mismatch")
    expected_sources = {
        str(path.relative_to(TERM_ROOT)): digest(path) for path in bridge_inputs()
    }
    require(
        provenance["bridge_source_sha256"] == expected_sources,
        "bridge source/provenance mismatch",
    )
    lock = json.loads((BRIDGE_SOURCE / "agda-source.lock.json").read_text(encoding="utf-8"))
    require(provenance["agda"]["revision"] == lock["revision"], "Agda revision mismatch")
    return provenance


def tree_digest(root):
    result = hashlib.sha256()
    for path in sorted(root.rglob("*.agda")):
        relative = path.relative_to(root).as_posix().encode("utf-8")
        content = path.read_bytes()
        result.update(len(relative).to_bytes(8, "big"))
        result.update(relative)
        result.update(len(content).to_bytes(8, "big"))
        result.update(content)
    return result.hexdigest()


def command(binary, root, packet, mode, expression=None, entry=None):
    source = entry or root / ENTRY_RELATIVE
    result = [
        str(binary), "--no-libraries", "--ignore-interfaces", "-i", str(root),
    ]
    if mode == "export":
        result.extend(["--term-export", expression])
    else:
        result.append("--term-import")
    result.extend(["--term-packet", str(packet), str(source)])
    return result


def run(arguments):
    process = subprocess.Popen(
        arguments, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    stdout, stderr = process.communicate(timeout=60)
    return process.pid, process.returncode, stdout, stderr


def rendered(stdout):
    lines = [
        line for line in stdout.splitlines()
        if not line.lstrip().startswith("Checking ")
    ]
    return "\n".join(lines).strip()


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--bridge-bin", default=os.environ.get("TERM_BRIDGE_BIN"))
    parser.add_argument("--provenance")
    return parser.parse_args(argv)


def git_identity():
    result = subprocess.run(
        ["git", "-C", str(TERM_ROOT.parent), "rev-parse", "HEAD"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    return result.stdout.strip() if result.returncode == 0 else "NOT-A-GIT-CHECKOUT"


def main(argv=None):
    args = parse_args(argv)
    require(args.bridge_bin, "provide --bridge-bin or TERM_BRIDGE_BIN")
    binary = Path(args.bridge_bin).expanduser().resolve()
    require(binary.is_file(), "bridge binary does not exist")
    provenance = verify_provenance(binary, args.provenance)
    source_before = tree_digest(SOURCE_ROOT)

    print("verify-approval-handoff: commit=" + git_identity())
    print("verify-approval-handoff: python=" + sys.version.splitlines()[0])
    print("evidence: bridge-sha256=" + digest(binary))
    print("evidence: agda-revision=" + provenance["agda"]["revision"])
    print("evidence: source-tree-sha256=" + source_before)
    require(len(list(SOURCE_ROOT.rglob("*.agda"))) == 7, "expected seven Agda modules")
    print("PASS bridge and seven-module formal source tree identities are bound")

    with tempfile.TemporaryDirectory(prefix="approval-handoff-verify-") as temporary:
        work = Path(temporary)
        source = work / "src"
        shutil.copytree(SOURCE_ROOT, source)
        packets = work / "packets"
        packets.mkdir()
        process_ids = set()

        for index, (expression, expected) in enumerate(EXPECTED.items()):
            packet = packets / f"case-{index}.packet"
            producer, code, stdout, stderr = run(
                command(binary, source, packet, "export", expression)
            )
            require(code == 0, stdout + stderr)
            require("EXPORTED real Agda Internal Term+Type" in stderr, "producer did not export Internal data")
            lowered_packet = packet.read_bytes().lower()
            require(
                not any(marker in lowered_packet for marker in (b"tcstate", b"tcm", b"closure", b"nbesemantic")),
                "compiler or NbE process state entered packet bytes",
            )
            consumer, code, stdout, stderr = run(
                command(binary, source, packet, "import")
            )
            require(code == 0, stdout + stderr)
            require("RECHECKED real Agda Internal Term+Type" in stderr, "consumer did not recheck Internal data")
            require(rendered(stdout) == expected, f"{expression} reconstructed value mismatch")
            require(producer != consumer != os.getpid(), "endpoints were not independent processes")
            process_ids.update((producer, consumer))
            print("evidence: " + expression.replace(" ", "-") + "-packet-sha256=" + digest(packet))
        require(len(process_ids) == len(EXPECTED) * 2, "process identity was reused")
        print("PASS five structured business values cross ten independent producer/consumer processes")

        approved = packets / "case-0.packet"
        alternate = packets / "alternate.packet"
        _, code, stdout, stderr = run(
            command(binary, source, alternate, "export", "approvedEnvelopeAlt")
        )
        require(code == 0, stdout + stderr)
        original = bytearray(approved.read_bytes())
        other = alternate.read_bytes()
        differences = [
            index for index, (left, right) in enumerate(zip(original, other))
            if left != right
        ]
        require(len(original) == len(other) and differences, "could not locate structured payload byte")
        original[differences[0]] = other[differences[0]]
        corrupted = packets / "corrupted.packet"
        corrupted.write_bytes(original)
        _, code, stdout, stderr = run(command(binary, source, corrupted, "import"))
        require(code != 0 and "content integrity mismatch" in stdout + stderr, "structured corruption was accepted")
        print("PASS decodable structured payload corruption fails content integrity")

        policy = source / "Handoff" / "Policy.agda"
        policy_text = policy.read_text(encoding="utf-8")
        policy.write_text(policy_text.replace("value < 5001", "value < 4001"), encoding="utf-8")
        _, code, stdout, stderr = run(command(binary, source, approved, "import"))
        require(code != 0 and "interface hash mismatch" in stdout + stderr, "dependency change was accepted")
        policy.write_text(policy_text, encoding="utf-8")
        print("PASS non-entry policy source changes invalidate the receiving context")

        other_entry = source / "OtherMain.agda"
        other_entry.write_text(
            (source / ENTRY_RELATIVE).read_text(encoding="utf-8").replace(
                "module HandoffMain", "module OtherMain"
            ),
            encoding="utf-8",
        )
        _, code, stdout, stderr = run(
            command(binary, source, approved, "import", entry=other_entry)
        )
        require(code != 0 and "top-level module mismatch" in stdout + stderr, "wrong module was accepted")
        print("PASS top-level receiving module mismatch fails closed")

        stale = packets / "stale.packet"
        stale.write_text("keep", encoding="utf-8")
        _, code, stdout, stderr = run(
            command(binary, source, stale, "export", "approvedEnvelope")
        )
        require(code != 0 and "already exists" in stdout + stderr, "stale packet was overwritten")
        require(stale.read_text(encoding="utf-8") == "keep", "stale packet changed")
        print("PASS failed structured export never overwrites an existing packet")

    require(tree_digest(SOURCE_ROOT) == source_before, "verification modified project sources")
    require(not list(SOURCE_ROOT.rglob("*.agdai")), "verification left interface files")
    print("PASS formal project sources remain unchanged and artifact-free")
    print("verify-approval-handoff: 7/7 PASS")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as error:
        print("verify-approval-handoff: FAIL: " + str(error), file=sys.stderr)
        sys.exit(1)
