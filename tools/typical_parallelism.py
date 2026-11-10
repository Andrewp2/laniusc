#!/usr/bin/env python3
"""Parallelism settings swept by the typical-project comparison.

Every compiler is measured at its fastest parallel configuration rather than
its default: the runner times each candidate below (a short pass), keeps the
one with the lowest median, and measures that one in full. A configuration is
a short label; `apply` turns the runner's default command for a lane into the
command for that label.

The knobs are each compiler's own:

- gcc, g++: ninja's job count (one compiler process per translation unit).
- tcc: one process, or byte-balanced partial-link shards built by ninja.
- rustc: the parallel frontend (-Zthreads) and the backend's codegen units.
- zig: the job limit (-j).
- go: packages built at once (-p) and per-package compile concurrency
  (-gcflags=-c) for the project's packages.
- dmd, LDC: the whole project in one invocation, or each module compiled
  with -c in parallel under ninja and then linked (dub's separate build mode
  with --parallel).
- V: its parallel C generation on or off (V has no thread-count option).
- tsc, tsrs: the number of checkers.
"""

from __future__ import annotations

import shutil
from pathlib import Path


def candidates(language: str, lane: str, source_files: int | None = None) -> tuple[str, ...]:
    if language in {"c", "cpp"}:
        return tuple(f"j{jobs}" for jobs in (8, 16, 32, 48, 64))
    if language == "tcc":
        # A shard needs at least one source file.
        return ("serial", *(
            f"shards{shards}"
            for shards in (4, 8, 16, 32)
            if source_files is None or shards <= source_files
        ))
    if language == "rust":
        units = (16, 64, 256) if lane == "o0" else (16, 32, 64, 256)
        return tuple(
            f"zthreads{threads}-cgu{unit}"
            for threads in (1, 4, 8, 16, 32)
            for unit in units
        )
    if language == "zig":
        return tuple(f"j{jobs}" for jobs in (1, 4, 8, 16, 32))
    if language == "go":
        return tuple(
            f"p{packages}-c{concurrency}"
            for packages in (8, 16, 32)
            for concurrency in (1, 4, 8, 32)
        )
    if language in {"d", "ldc"}:
        return ("single", *(f"separate-j{jobs}" for jobs in (8, 16, 32)))
    if language == "v":
        return ("parallel", "no-parallel")
    if language in {"tsc", "tsrs"}:
        return tuple(f"checkers{count}" for count in (1, 2, 4, 8, 16, 32))
    return ("default",)


def number(label: str, prefix: str) -> int:
    for part in label.split("-"):
        if part.startswith(prefix) and part[len(prefix):].isdigit():
            return int(part[len(prefix):])
    raise ValueError(f"{label!r} has no {prefix}<n> part")


def tcc_lane(config: str) -> str:
    """The runner's TCC lane for a configuration label."""
    if config in {"default", "serial"}:
        return "default"
    return f"parallel-{number(config, 'shards')}"


def apply(
    language: str,
    lane: str,
    config: str,
    command: list[str],
    env: dict[str, str],
) -> list[str]:
    """The default command for a lane, adjusted for a configuration. Updates
    env in place (Rust's settings are environment variables)."""
    if config == "default":
        return command
    if language in {"c", "cpp"}:
        return [*command, "-j", str(number(config, "j"))]
    if language == "rust":
        flags = [flag for flag in env.get("RUSTFLAGS", "").split() if not flag.startswith("-Zthreads=")]
        env["RUSTFLAGS"] = " ".join([*flags, f"-Zthreads={number(config, 'zthreads')}"])
        profile = "RELEASE" if lane == "optimized" else "DEV"
        env[f"CARGO_PROFILE_{profile}_CODEGEN_UNITS"] = str(number(config, "cgu"))
        return command
    if language == "zig":
        return [command[0], command[1], f"-j{number(config, 'j')}", *command[2:]]
    if language == "go":
        go, output = command[0], command[command.index("-o") + 1]
        flags = "-N -l " if lane == "o0" else ""
        return [
            go, "build",
            "-p", str(number(config, "p")),
            f"-gcflags=typical/...={flags}-c={number(config, 'c')}",
            "-o", output, ".",
        ]
    if language == "v":
        return [command[0], "-no-parallel", *command[1:]] if config == "no-parallel" else command
    if language in {"tsc", "tsrs"}:
        index = command.index("--checkers")
        return [*command[: index + 1], str(number(config, "checkers")), *command[index + 2:]]
    if language in {"d", "ldc"} and config == "single":
        return command
    raise ValueError(f"no command adjustment for {language} {config}")


def d_separate_build(
    root: Path, language: str, lane: str, compiler: Path, flags: list[str], jobs: int
) -> tuple[list[str], Path]:
    """Ninja file compiling every D module with -c in parallel, then linking
    once with the same compiler. Returns the build command and the output."""
    build = root / "build" / f"{language}-{lane}-separate"
    shutil.rmtree(build, ignore_errors=True)
    build.mkdir(parents=True)
    output = root / f"typical-project-{language}-{lane}"
    output.unlink(missing_ok=True)
    sources = ["main.d", *sorted(str(path.relative_to(root)) for path in (root / "typical").glob("*.d"))]
    objects = []
    lines = [
        f"compiler = {compiler}",
        f"flags = {' '.join(['-I.', *flags])}",
        "rule compile",
        "  command = $compiler $flags -c $in -of=$out",
        "rule link",
        "  command = $compiler $in -of=$out",
    ]
    for source in sources:
        relative_object = Path("build") / build.name / (source.replace("/", "_").removesuffix(".d") + ".o")
        objects.append(str(relative_object))
        lines.append(f"build {relative_object}: compile {source}")
    lines.append(f"build {output.name}: link {' '.join(objects)}")
    lines.append(f"default {output.name}")
    build_file = build / "build.ninja"
    build_file.write_text("\n".join(lines) + "\n")
    return ["ninja", "-f", str(build_file.relative_to(root)), "-j", str(jobs)], output
