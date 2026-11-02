#!/usr/bin/env python3
"""Shared MoonBit (`moon`) project layout for the cross-language benchmarks.

MoonBit builds packages, not loose files, so every benchmark materializes a
moon module: a `moon.mod` at the root and a `main` package whose `moon.pkg`
declares it executable. Both files use the current DSL formats; the toolchain
no longer accepts the legacy `moon.mod.json` and `moon.pkg.json`.
"""

from __future__ import annotations

import shutil
import subprocess
from pathlib import Path


MOON = "moon"
MISSING_MESSAGE = "moon not found; install MoonBit to include it"
MODULE_NAME = "lanius/bench"
ENTRY_PACKAGE = "main"
BACKEND_SUFFIX = {"native": ".exe", "wasm-gc": ".wasm", "js": ".js"}
PROFILES = ("debug", "release")


def moon_available(moon: str = MOON) -> bool:
    return shutil.which(moon) is not None or Path(moon).is_file()


def module_manifest(name: str = MODULE_NAME) -> str:
    return f'name = "{name}"\nversion = "0.1.0"\n'


def package_manifest(imports: list[str] | tuple[str, ...], executable: bool = False) -> str:
    lines = []
    if imports:
        lines.append("import {")
        lines.extend(f'  "{package}",' for package in imports)
        lines.extend(("}", ""))
    if executable:
        lines.extend(('pkgtype(kind: "executable")', ""))
    return "\n".join(lines)


def write_single_file_project(
    root: Path, source: str, imports: tuple[str, ...] = ()
) -> Path:
    """Write a one-package moon module around a single-file workload."""
    package = root / ENTRY_PACKAGE
    package.mkdir(parents=True, exist_ok=True)
    (root / "moon.mod").write_text(module_manifest())
    (package / "moon.pkg").write_text(package_manifest(imports, executable=True))
    entry = package / "main.mbt"
    entry.write_text(source)
    return entry


def build_command(backend: str, profile: str, moon: str = MOON) -> list[str]:
    if backend not in BACKEND_SUFFIX:
        raise ValueError(f"unsupported MoonBit backend {backend!r}")
    if profile not in PROFILES:
        raise ValueError(f"unsupported MoonBit profile {profile!r}")
    return [moon, "build", "--target", backend, f"--{profile}"]


def artifact_candidates(
    root: Path, backend: str, profile: str, package: str = ENTRY_PACKAGE
) -> list[Path]:
    """Where `moon build` writes the package artifact: `_build/` in current
    toolchains, `target/` in older ones."""
    name = package.rsplit("/", 1)[-1] + BACKEND_SUFFIX[backend]
    return [
        root / directory / backend / profile / "build" / package / name
        for directory in ("_build", "target")
    ]


def artifact_path(
    root: Path, backend: str, profile: str, package: str = ENTRY_PACKAGE
) -> Path:
    candidates = artifact_candidates(root, backend, profile, package)
    return next((path for path in candidates if path.is_file()), candidates[0])


def version(moon: str = MOON) -> str:
    """`moon version --all` names moon, moonc and moonrun on separate lines."""
    if not moon_available(moon):
        return "missing"
    run = subprocess.run(
        [moon, "version", "--all"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    lines = [line.strip() for line in run.stdout.splitlines() if line.strip()]
    return "; ".join(lines) if lines else f"exit={run.returncode}"
