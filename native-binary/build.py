#!/usr/bin/env python3
"""Build a controlled Agda project through MAlonzo and GHC."""

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


class BuildError(Exception):
    def __init__(self, tag, message, exit_code):
        super().__init__(message)
        self.tag = tag
        self.exit_code = exit_code


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def tree_sha256(files):
    digest = hashlib.sha256()
    for relative, _path, content in files:
        name = relative.as_posix().encode("utf-8")
        digest.update(len(name).to_bytes(8, "big"))
        digest.update(name)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def resolve_tool(requested, label):
    resolved = shutil.which(requested)
    if not resolved:
        raise BuildError("E_TOOL", f"{label} executable not found: {requested}", 69)
    return str(Path(resolved).resolve())


def tool_version(path):
    result = subprocess.run(
        [path, "--version"], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False,
    )
    if result.returncode != 0:
        raise BuildError("E_TOOL", f"cannot query tool version: {path}", 69)
    return result.stdout.strip()


def run_logged(command, cwd, log_path, failure_tag):
    result = subprocess.run(
        command, cwd=str(cwd), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, check=False,
    )
    log_path.write_text(
        json.dumps(command, ensure_ascii=False) + "\n\n" + result.stdout,
        encoding="utf-8",
    )
    if result.returncode != 0:
        tail = "\n".join(result.stdout.splitlines()[-20:])
        raise BuildError(failure_tag, tail or "command failed without output", 70)
    return result.stdout


def read_source(source):
    try:
        source_bytes = source.read_bytes()
        text = source_bytes.decode("utf-8")
    except (OSError, UnicodeError) as error:
        raise BuildError("E_INPUT", f"cannot read UTF-8 source: {error}", 65)
    return source_bytes, text


def source_contract(source, project_root, project_mode, profile):
    if project_mode:
        try:
            source.relative_to(project_root)
        except ValueError:
            raise BuildError("E_INPUT", "entry source must be inside --project-root", 65)
        paths = sorted(project_root.rglob("*.agda"))
        if not paths:
            raise BuildError("E_INPUT", "project contains no Agda sources", 65)
    else:
        project_root = source.parent
        paths = [source]

    files = []
    modules = {}
    texts = {}
    for path in paths:
        if not path.is_file() or path.is_symlink():
            raise BuildError("E_INPUT", f"project source must be a regular file: {path}", 65)
        relative = path.relative_to(project_root)
        source_bytes, text = read_source(path)
        module_match = re.search(
            r"(?m)^\s*module\s+([A-Za-z][A-Za-z0-9_.]*)\s+where\s*$", text
        )
        if not module_match:
            raise BuildError("E_INPUT", f"source has no simple module declaration: {relative}", 65)
        module_name = module_match.group(1)
        expected_module = ".".join(relative.with_suffix("").parts)
        if module_name != expected_module:
            raise BuildError(
                "E_INPUT",
                f"module/path mismatch: expected {expected_module}, got {module_name}",
                65,
            )
        if module_name in modules:
            raise BuildError("E_INPUT", f"duplicate module: {module_name}", 65)
        modules[module_name] = path
        texts[module_name] = text
        files.append((relative, path, source_bytes))

        option_blocks = re.findall(r"\{-#\s*OPTIONS\s+(.*?)#-\}", text, re.DOTALL)
        options = {token for block in option_blocks for token in block.split()}
        unsafe = {
            "--allow-incomplete-matches", "--allow-unsolved-metas",
            "--type-in-type", "--omega-in-omega",
        }
        rejected = sorted(options & unsafe)
        if rejected:
            raise BuildError("E_PROFILE", f"unsafe Agda option: {rejected[0]}", 65)
        if "--cubical" in options:
            raise BuildError(
                "E_PROFILE", "full --cubical runtime terms do not belong to native-binary", 65
            )
        if profile == "ordinary" and any("cubical" in item for item in options):
            raise BuildError("E_PROFILE", "cubical option requires erased-cubical profile", 65)

    entry_relative = source.relative_to(project_root)
    entry_module = ".".join(entry_relative.with_suffix("").parts)
    entry_text = texts[entry_module]
    if not re.search(r"(?m)^\s*main\s*:", entry_text):
        raise BuildError("E_INPUT", "entry module must declare main", 65)

    for module_name, text in texts.items():
        imports = re.findall(r"(?m)^\s*(?:open\s+)?import\s+([^\s]+)", text)
        for imported in imports:
            builtin = (
                imported == "Agda.Primitive"
                or imported.startswith("Agda.Primitive.")
                or imported.startswith("Agda.Builtin.")
            )
            if not builtin and imported not in modules:
                raise BuildError(
                    "E_INPUT",
                    f"module {module_name} imports source outside the project: {imported}",
                    65,
                )
            if profile == "ordinary" and ".Cubical" in imported:
                raise BuildError("E_PROFILE", "Cubical import requires erased-cubical profile", 65)

    manifest = {
        relative.as_posix(): hashlib.sha256(content).hexdigest()
        for relative, _path, content in files
    }
    return {
        "root": project_root,
        "files": files,
        "manifest": manifest,
        "tree_sha256": tree_sha256(files),
        "entry_relative": entry_relative,
        "entry_module": entry_module,
        "entry_text": entry_text,
        "entry_sha256": manifest[entry_relative.as_posix()],
        "modules": sorted(modules),
    }


def find_audit_tools(nm_request, deps_request, deps_style):
    nm_tool = resolve_tool(nm_request or os.environ.get("NM", "nm"), "nm")
    if deps_request:
        deps_tool = resolve_tool(deps_request, "dependency audit")
        style = deps_style
        if not style:
            raise BuildError("E_TOOL", "--deps-style is required with --deps-tool", 69)
        return nm_tool, deps_tool, style

    candidates = (
        (os.environ.get("OTOOL", "otool"), "otool"),
        (os.environ.get("LDD", "ldd"), "ldd"),
        (os.environ.get("OBJDUMP", "objdump"), "objdump"),
        (os.environ.get("DUMPBIN", "dumpbin"), "dumpbin"),
    )
    for requested, style in candidates:
        resolved = shutil.which(requested)
        if resolved:
            return nm_tool, str(Path(resolved).resolve()), style
    raise BuildError("E_TOOL", "no supported binary dependency audit tool found", 69)


def dependency_command(style, tool, binary):
    if style == "otool":
        return [tool, "-L", str(binary)]
    if style == "ldd":
        return [tool, str(binary)]
    if style == "objdump":
        return [tool, "-p", str(binary)]
    if style == "dumpbin":
        return [tool, "/DEPENDENTS", str(binary)]
    raise BuildError("E_TOOL", f"unsupported dependency audit style: {style}", 69)


def repository_state():
    root = Path(__file__).resolve().parent.parent
    head = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    status = subprocess.run(
        ["git", "-C", str(root), "status", "--porcelain"], text=True,
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
    )
    return {
        "commit": head.stdout.strip() if head.returncode == 0 else None,
        "dirty": bool(status.stdout.strip()) if status.returncode == 0 else None,
    }


def build(args):
    source = Path(args.source).expanduser().resolve()
    if not source.is_file():
        raise BuildError("E_INPUT", f"source file not found: {source}", 65)
    project_mode = args.project_root is not None
    project_root = (
        Path(args.project_root).expanduser().resolve()
        if project_mode else source.parent
    )
    if not project_root.is_dir():
        raise BuildError("E_INPUT", f"project root not found: {project_root}", 65)
    contract = source_contract(source, project_root, project_mode, args.profile)
    module_name = contract["entry_module"]
    source_digest = contract["tree_sha256"]

    output = Path(args.output).expanduser().absolute()
    if output.exists():
        raise BuildError("E_OUTPUT", f"output already exists: {output}", 73)
    output.parent.mkdir(parents=True, exist_ok=True)

    agda = resolve_tool(args.agda or os.environ.get("AGDA", "agda"), "Agda")
    ghc = resolve_tool(args.ghc or os.environ.get("GHC", "ghc"), "GHC")
    nm_tool, deps_tool, deps_style = find_audit_tools(
        args.nm, args.deps_tool, args.deps_style
    )

    lock = output.parent / ("." + output.name + ".lock")
    try:
        lock_fd = os.open(str(lock), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(lock_fd)
    except FileExistsError:
        raise BuildError("E_OUTPUT", f"output is locked: {output}", 73)

    stage = Path(tempfile.mkdtemp(prefix="." + output.name + ".staging-", dir=output.parent))
    try:
        input_dir = stage / "input"
        generated = stage / "generated"
        object_dir = stage / "objects"
        binary_dir = stage / "bin"
        audit_dir = stage / "audit"
        log_dir = stage / "logs"
        for directory in (input_dir, generated, object_dir, binary_dir, audit_dir, log_dir):
            directory.mkdir()

        for relative, _project_source, source_bytes in contract["files"]:
            staged_project_source = input_dir / relative
            staged_project_source.parent.mkdir(parents=True, exist_ok=True)
            staged_project_source.write_bytes(source_bytes)
        staged_source = input_dir / contract["entry_relative"]
        binary_name = args.binary_name or module_name.replace(".", "-")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", binary_name):
            raise BuildError("E_INPUT", "invalid binary name", 65)
        if os.name == "nt" and not binary_name.lower().endswith(".exe"):
            binary_name += ".exe"
        binary = binary_dir / binary_name

        agda_command = [
            agda, "--no-libraries", "--ignore-interfaces", "--compile",
            "--ghc-dont-call-ghc", f"--compile-dir={generated}",
            f"--include-path={input_dir}",
        ]
        if args.profile == "erased-cubical":
            agda_command.extend(["--erased-cubical", "--erasure"])
        agda_command.append(str(staged_source))
        run_logged(agda_command, input_dir, log_dir / "agda.log", "E_AGDA")

        entry_haskell = (
            generated / "MAlonzo" / "Code"
            / Path(*module_name.split(".")).with_suffix(".hs")
        )
        if not entry_haskell.is_file():
            raise BuildError("E_AUDIT", "MAlonzo entry module was not generated", 70)
        entry_text = entry_haskell.read_text(encoding="utf-8")
        if "MAlonzo.RTE" not in entry_text or "AgdaAny" not in entry_text:
            raise BuildError("E_AUDIT", "generated entry lacks MAlonzo erasure markers", 70)

        ghc_command = [
            ghc, "-O", "-Werror", "-i" + str(generated),
            "-main-is", "MAlonzo.Code." + module_name, str(entry_haskell),
            "--make", "-fwarn-incomplete-patterns", "-odir", str(object_dir),
            "-hidir", str(object_dir), "-o", str(binary),
        ]
        run_logged(ghc_command, input_dir, log_dir / "ghc.log", "E_GHC")
        if not binary.is_file():
            raise BuildError("E_AUDIT", "GHC did not produce the requested binary", 70)

        haskell_files = sorted(generated.rglob("*.hs"))
        forbidden = (
            "Agda.TypeChecking", "TCState", "RuntimeNbe", "runtime-nbe",
            "term-transport",
        )
        forbidden_matches = []
        for haskell in haskell_files:
            content = haskell.read_text(encoding="utf-8")
            for marker in forbidden:
                if marker in content:
                    forbidden_matches.append(
                        f"{haskell.relative_to(generated).as_posix()}:{marker}"
                    )
        if forbidden_matches:
            raise BuildError("E_AUDIT", "forbidden runtime/compiler marker in output", 70)

        nm_command = [nm_tool, str(binary)]
        symbols = run_logged(nm_command, input_dir, audit_dir / "symbols.txt", "E_AUDIT")
        if any(marker in symbols for marker in forbidden):
            raise BuildError("E_AUDIT", "forbidden runtime/compiler symbol in binary", 70)
        deps_command = dependency_command(deps_style, deps_tool, binary)
        run_logged(
            deps_command, input_dir, audit_dir / "dependencies.txt", "E_AUDIT"
        )

        current = source_contract(source, project_root, project_mode, args.profile)
        if (
            current["tree_sha256"] != source_digest
            or current["manifest"] != contract["manifest"]
        ):
            raise BuildError("E_IDENTITY", "source project changed during build", 65)

        audit = {
            "entry_module": module_name,
            "project_source_count": len(contract["files"]),
            "project_modules": contract["modules"],
            "generated_haskell_count": len(haskell_files),
            "generated_haskell": {
                path.relative_to(generated).as_posix(): sha256_file(path)
                for path in haskell_files
            },
            "malonzo_erasure_markers": {
                "AgdaAny": entry_text.count("AgdaAny"),
                "erased": entry_text.count("erased"),
            },
            "forbidden_matches": forbidden_matches,
            "symbol_audit": "audit/symbols.txt",
            "dependency_audit": "audit/dependencies.txt",
        }
        (audit_dir / "summary.json").write_text(
            json.dumps(audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        provenance = {
            "schema": 1,
            "profile": args.profile,
            "source": {
                "name": source.name,
                "entry": contract["entry_relative"].as_posix(),
                "sha256": contract["entry_sha256"],
                "tree_sha256": source_digest,
                "files": contract["manifest"],
            },
            "binary": {
                "path": "bin/" + binary.name,
                "sha256": sha256_file(binary),
            },
            "tools": {
                "agda": {
                    "path": agda, "sha256": sha256_file(Path(agda)),
                    "version": tool_version(agda),
                },
                "ghc": {
                    "path": ghc, "sha256": sha256_file(Path(ghc)),
                    "version": tool_version(ghc),
                },
                "nm": nm_tool,
                "dependency_audit": {"path": deps_tool, "style": deps_style},
            },
            "commands": {"agda": agda_command, "ghc": ghc_command},
            "host": {"system": platform.system(), "machine": platform.machine()},
            "repository": repository_state(),
            "audit": "audit/summary.json",
        }
        (stage / "provenance.json").write_text(
            json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )

        if output.exists():
            raise BuildError("E_OUTPUT", f"output appeared during build: {output}", 73)
        stage.rename(output)
        stage = None
        print(f"native-build: PASS: {output}")
    finally:
        if stage is not None:
            shutil.rmtree(stage, ignore_errors=True)
        try:
            lock.unlink()
        except FileNotFoundError:
            pass


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--project-root")
    parser.add_argument("--output", required=True)
    parser.add_argument("--profile", choices=("ordinary", "erased-cubical"), required=True)
    parser.add_argument("--binary-name")
    parser.add_argument("--agda")
    parser.add_argument("--ghc")
    parser.add_argument("--nm")
    parser.add_argument("--deps-tool")
    parser.add_argument("--deps-style", choices=("otool", "ldd", "objdump", "dumpbin"))
    return parser.parse_args(argv)


def main(argv=None):
    try:
        build(parse_args(argv))
        return 0
    except BuildError as error:
        print(f"native-build: {error.tag}: {error}", file=sys.stderr)
        return error.exit_code


if __name__ == "__main__":
    sys.exit(main())
