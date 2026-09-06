#!/usr/bin/env python3
"""Instantiate fixed grammar/buffer data and GPU-compile the Lanius driver.

This script does no lexing, parsing, semantic analysis, or artifact emission.
The generated entry is part of the source that must ultimately be verified.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess


IMPORT_PATTERN = re.compile(
    r"^\s*import\s+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)\s*;",
    re.MULTILINE,
)


def discover_source_closure(entry: Path, source_root: Path,
                            stdlib_root: Path) -> list[Path]:
    """Return a deterministic bootstrap claim about the recursive import closure.

    This resolver is provenance tooling, not trusted language semantics. The
    eventual source-closure theorem must validate module identities and imports
    from the extracted syntax itself.
    """
    seen: set[Path] = set()
    ordered: list[Path] = []

    def visit(path: Path):
        path = path.resolve()
        if path in seen:
            return
        seen.add(path)
        ordered.append(path)
        for module in IMPORT_PATTERN.findall(path.read_text()):
            relative = Path(*module.split("::")).with_suffix(".lani")
            candidates = [source_root / relative, stdlib_root / relative]
            dependency = next((candidate for candidate in candidates
                               if candidate.is_file()), None)
            if dependency is None:
                raise FileNotFoundError(
                    f"cannot resolve bootstrap import {module!r} from {path}")
            visit(dependency)

    visit(entry)
    return ordered


def closure_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for path in paths:
        encoded = str(path.resolve()).encode("utf-8")
        digest.update(len(encoded).to_bytes(8, "little"))
        digest.update(encoded)
        data = path.read_bytes()
        digest.update(len(data).to_bytes(8, "little"))
        digest.update(data)
    return digest.hexdigest()


def main():
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=root / "target/lanius-extractor")
    parser.add_argument("--scale", type=int, default=1,
                        help="positive buffer-capacity multiplier; does not change the grammar")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--surface", action="store_true",
                        help="emit singular syntax-plus-Surface artifacts")
    parser.add_argument("--workspace-words", type=int,
                        help="override parser workspace independently of output/source buffers")
    parser.add_argument("--record-words", type=int,
                        help="override materialized parse-record storage")
    parser.add_argument("--node-words", type=int,
                        help="override materialized parse-node offset storage")
    parser.add_argument("--output-words", type=int,
                        help="override serialized artifact output storage")
    args = parser.parse_args()
    if not 1 <= args.scale <= 64:
        parser.error("--scale must be between 1 and 64")
    grammar = json.loads((root / "verified_compiler/data/grammar.json").read_text())
    capacities = {"SOURCE_CAP": 1024, "TOKEN_CAP": 1024, "WORK_CAP": 16384,
                  "RECORD_CAP": 4096, "NODE_CAP": 1024, "SEMANTIC_CAP": 2048,
                  "SURFACE_EXPR_CAP": 4096, "SURFACE_TYPE_CAP": 4096,
                  "OUTPUT_CAP": 32768}
    capacities = {key: value * args.scale for key, value in capacities.items()}
    if args.workspace_words is not None:
        if not 1 <= args.workspace_words <= 16777216:
            parser.error("--workspace-words must be between 1 and 16777216")
        capacities["WORK_CAP"] = args.workspace_words
    for argument, capacity in (
        (args.record_words, "RECORD_CAP"),
        (args.node_words, "NODE_CAP"),
        (args.output_words, "OUTPUT_CAP"),
    ):
        if argument is not None:
            if not 1 <= argument <= 16777216:
                option = capacity.removesuffix("_CAP").lower().replace("_", "-")
                parser.error(f"--{option}-words must be between 1 and 16777216")
            capacities[capacity] = argument
    values = {key: str(value) for key, value in capacities.items()}
    values.update({key.removesuffix("_CAP") + "_BYTES": str(value * 4)
                   for key, value in capacities.items()})
    encoded_grammar = "".join(f"{word:04x}" for word in grammar)
    values.update(GRAMMAR_LEN=str(len(grammar)),
                  GRAMMAR_BYTES=str(len(grammar) * 4),
                  GRAMMAR_ENCODED=encoded_grammar,
                  EMIT_SURFACE="true" if args.surface else "false",
                  DEPTH="1024", PATH_PACKED_BYTES="1024", PATH_BYTES="4096")
    source = (root / "verified_compiler/src/extractor.lani.in").read_text()
    for key, value in values.items():
        source = source.replace("@" + key + "@", value)
    if "@" in source:
        raise ValueError("unexpanded driver template placeholder")
    out = args.output_dir.resolve()
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "extractor.lani"
    entry.write_text(source)
    source_root = root / "verified_compiler/src"
    stdlib_root = root / "stdlib"
    source_closure = discover_source_closure(entry, source_root, stdlib_root)
    if args.prepare_only:
        print(entry)
        return
    executable = out / "extractor"
    # Conservative source-root snapshot (includes unused modules), not a
    # claim that the compiler or this bootstrap executable is verified.
    source_paths = [entry]
    for directory in [root / "verified_compiler/src/verified", stdlib_root]:
        source_paths.extend(sorted(directory.rglob("*.lani")))
    def snapshot():
        return {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_paths}
    sources_before = snapshot()
    command = ["cargo", "run", "-j", "1", "--bin", "laniusc", "--",
               "--emit", "x86_64", "--source-root", str(source_root),
               "--stdlib-root", str(stdlib_root), str(entry), "-o", str(executable)]
    subprocess.run(command, cwd=root, check=True)
    header = executable.read_bytes()[:20]
    if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
            or int.from_bytes(header[18:20], "little") != 62):
        raise RuntimeError("bootstrap compiler did not emit x86-64 ELF")
    executable.chmod(0o700)
    if snapshot() != sources_before:
        raise RuntimeError("source files changed during bootstrap; rebuild before using output")
    mode = "surface" if args.surface else "syntax"
    manifest = {"status": f"untrusted-{mode}-extractor", "mode": mode,
                "target": "x86_64-linux",
                "command": command,
                "entry": str(entry), "entry_sha256": hashlib.sha256(entry.read_bytes()).hexdigest(),
                "executable": str(executable),
                "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
                "source_closure": [
                    {"path": str(path),
                     "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                    for path in source_closure
                ],
                "source_closure_sha256": closure_digest(source_closure),
                "capacities": capacities, "source_root_snapshot": sources_before,
                "bootstrap_compiler_sha256": hashlib.sha256(
                    (root / "target/debug/laniusc").read_bytes()).hexdigest()}
    (out / "bootstrap.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(executable)


if __name__ == "__main__":
    main()
