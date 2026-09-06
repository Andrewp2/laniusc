#!/usr/bin/env python3
"""Compile a generated SelfClosure pack with bounded, phase-local Lean heaps."""

import argparse
import os
from pathlib import Path
import subprocess
import time


PHASES = ("Data", "View", "Nodes", "Metadata", "Valid")


def unit_directories(module_root: Path) -> list[Path]:
    closure = module_root / "SelfClosure"
    units = [path for path in closure.iterdir()
             if path.is_dir() and path.name.startswith("Unit") and
             path.name[4:].isdigit()]
    return sorted(units, key=lambda path: int(path.name[4:]))


def generated_dependencies(module_root: Path, source: Path) -> list[Path]:
    unit = source.parent
    phase = source.stem
    if phase == "View":
        return [unit / "Data.olean"]
    if phase in ("Nodes", "Metadata"):
        return [unit / "View.olean"]
    if phase == "Valid":
        return [unit / "Nodes.olean", unit / "Metadata.olean"]
    if source.name == "Pack.lean":
        return [path / "Valid.olean" for path in unit_directories(module_root)]
    return []


def is_fresh(output: Path, source: Path, dependencies: list[Path],
             formal_boundary: Path) -> bool:
    if not output.exists() or any(not dependency.exists()
                                  for dependency in dependencies):
        return False
    newest_input = max([source.stat().st_mtime, formal_boundary.stat().st_mtime] +
                       [dependency.stat().st_mtime for dependency in dependencies])
    return output.stat().st_mtime >= newest_input


def compile_module(lean: str, repo: Path, formal: Path, module_root: Path,
                   source: Path, memory_mb: int, lean_path: str) -> None:
    output = source.with_suffix(".olean")
    started = time.monotonic()
    environment = os.environ.copy()
    environment["LEAN_PATH"] = str(module_root) + os.pathsep + lean_path
    result = subprocess.run(
        [lean, "-R", str(repo), "-M", str(memory_mb),
         "-DElab.async=false", "-o", str(output), str(source)],
        cwd=formal, env=environment, text=True, capture_output=True)
    elapsed = time.monotonic() - started
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args)
    print(f"checked {source.relative_to(module_root)} in {elapsed:.2f}s",
          flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("module_root", type=Path)
    parser.add_argument("--memory", type=int, default=12000,
                        help="Lean memory ceiling in MiB (default: 12000)")
    parser.add_argument("--force", action="store_true",
                        help="recheck modules even when generated oleans are fresh")
    args = parser.parse_args()

    repo = Path(__file__).resolve().parent.parent
    formal = repo / "formal"
    module_root = args.module_root.resolve()
    pack = module_root / "SelfClosure" / "Pack.lean"
    if not pack.is_file():
        parser.error(f"missing generated pack: {pack}")
    units = unit_directories(module_root)
    if not units:
        parser.error("generated pack has no Unit directories")

    lean = subprocess.check_output(
        ["lake", "env", "which", "lean"], cwd=formal, text=True).strip()
    lean_path = subprocess.check_output(
        ["lake", "env", "printenv", "LEAN_PATH"], cwd=formal,
        text=True).strip()
    formal_boundary = (formal / ".lake/build/lib/lean/Lanius/Extraction/"
                       "ParseChunks.olean")
    if not formal_boundary.is_file():
        parser.error("build Lanius.Extraction.ParseChunks before checking a pack")

    checked = 0
    skipped = 0
    for unit in units:
        for phase in PHASES:
            source = unit / f"{phase}.lean"
            if not source.is_file():
                parser.error(f"missing generated phase: {source}")
            output = source.with_suffix(".olean")
            dependencies = generated_dependencies(module_root, source)
            if (not args.force and
                    is_fresh(output, source, dependencies, formal_boundary)):
                skipped += 1
                continue
            compile_module(lean, repo, formal, module_root, source,
                           args.memory, lean_path)
            checked += 1

    pack_output = pack.with_suffix(".olean")
    pack_dependencies = generated_dependencies(module_root, pack)
    if (not args.force and
            is_fresh(pack_output, pack, pack_dependencies, formal_boundary)):
        skipped += 1
    else:
        compile_module(lean, repo, formal, module_root, pack,
                       args.memory, lean_path)
        checked += 1
    print(f"pack accepted: {checked} checked, {skipped} fresh", flush=True)


if __name__ == "__main__":
    main()
