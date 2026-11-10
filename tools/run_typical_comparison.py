#!/usr/bin/env python3
"""Compare clean native builds with warm-daemon Lanius on typical projects."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shlex
import shutil
import signal
import statistics
import subprocess
import sys
import time
from pathlib import Path

import moonbit_project
import typical_parallelism
from generate_typical_project import generate
from run_compiler_stress_matrix import (
    DEFAULT_TOOLCHAINS,
    DMD,
    GO_ROOT,
    LDC2,
    TSC_NATIVE,
    TSRS_NATIVE,
    TYPESCRIPT_CHECKERS,
    V_ROOT,
    compiler_environment,
)
from perf_model import command_record, new_document, source_facts, summarize, write_document
from run_typical_lanius_matrix import parse_counts


LANGUAGES = (
    "c", "cpp", "rust", "zig", "tcc", "moonbit",
    "d", "ldc", "go", "v", "tsc", "tsrs",
)
LANES = ("o0", "optimized")
TYPESCRIPT_COMPILERS = ("tsc", "tsrs")
# Compilers that build another compiler's rendering of the project.
SOURCE_LANGUAGE = {"tcc": "c", "ldc": "d", "tsc": "ts", "tsrs": "ts"}
# Toolchains installed in the --toolchains directory (as for the single-file
# runner); each is dropped, with a message, when its executable is missing.
# Compilers outside the system packages are installed in the toolchains
# directory; each falls back to the one on PATH when it is not there.
ZIG = "zig/zig-x86_64-linux-0.17.1/zig"
TCC = "tcc/bin/tcc"
# The newest GCC installed side by side with the system compiler (for example
# from the ubuntu-toolchain-r PPA), else the system cc/c++.
GCC_VERSIONS = (16, 15, 14)


def zig_executable(toolchains: Path) -> str:
    pinned = toolchains / ZIG
    return str(pinned) if pinned.is_file() else "zig"


def default_tcc(toolchains: Path = DEFAULT_TOOLCHAINS) -> str:
    built = toolchains / TCC
    return str(built) if built.is_file() else "tcc"


def default_c_compilers() -> tuple[str, str]:
    for version in GCC_VERSIONS:
        if shutil.which(f"gcc-{version}") and shutil.which(f"g++-{version}"):
            return f"gcc-{version}", f"g++-{version}"
    return "cc", "c++"


def select_ninja_compiler(build_file: Path, compiler: str) -> None:
    """Point a generated ninja file at the selected C or C++ compiler."""
    lines = build_file.read_text().splitlines(keepends=True)
    if not lines or not lines[0].startswith("compiler = "):
        raise RuntimeError(f"unexpected ninja file header: {build_file}")
    lines[0] = f"compiler = {compiler}\n"
    build_file.write_text("".join(lines))


TOOLCHAIN_EXECUTABLES = {
    "d": DMD,
    "ldc": LDC2,
    "go": f"{GO_ROOT}/bin/go",
    "v": f"{V_ROOT}/v",
    "tsc": TSC_NATIVE,
    "tsrs": TSRS_NATIVE,
}
# The Go standard-library packages the rendered project imports are compiled
# once into a run-private cache snapshot; every sample starts from a copy of it,
# so project packages are always compiled and the standard library never is.
GO_STD_PRIMER = """package main

import (
{imports})

func main() {{
}}
"""
# V's counterpart: a program importing the same vlib modules as the project's
# main.v warms V's module cache with its runtime (builtin, the Boehm GC, os,
# time, crypto.rand) but none of the project's modules.
V_STD_PRIMER = """module main

{imports}
fn main() {{
}}
"""
# One rule for every compiler: a build still running after this many seconds
# is stopped and its lane recorded as did-not-finish (DNF).
DEFAULT_BUILD_TIMEOUT_SECONDS = 600
# A lane whose first measured build takes longer than this keeps only
# SLOW_LANE_SAMPLES samples; the row records that the count was reduced.
SLOW_LANE_THRESHOLD_MS = 30_000
SLOW_LANE_SAMPLES = 5


def parse_languages(value: str) -> tuple[str, ...]:
    languages = tuple(part.strip() for part in value.split(",") if part.strip())
    unknown = set(languages) - set(LANGUAGES)
    if not languages or unknown:
        expected = ",".join(LANGUAGES)
        raise argparse.ArgumentTypeError(
            f"languages must be a non-empty subset of {expected}; unknown: {sorted(unknown)}"
        )
    return languages


def entry_source(project: Path, language: str) -> Path:
    relative = {
        "c": "c/src/main.c",
        "tcc": "c/src/main.c",
        "cpp": "cpp/src/main.cpp",
        "rust": "rust/src/main.rs",
        "zig": "zig/main.zig",
        "moonbit": "moonbit/main/main.mbt",
        "d": "d/main.d",
        "ldc": "d/main.d",
        "go": "go/main.go",
        "v": "v/main.v",
        "tsc": "ts/src/main.ts",
        "tsrs": "ts/src/main.ts",
    }[language]
    return project / relative


def source_language(language: str) -> str:
    return SOURCE_LANGUAGE.get(language, language)


def available_languages(
    languages: tuple[str, ...], toolchains: Path = DEFAULT_TOOLCHAINS
) -> tuple[str, ...]:
    """Drop MoonBit and the toolchains-directory compilers, with a message,
    when they are not installed."""
    available = []
    for language in languages:
        if language == "moonbit" and not moonbit_project.moon_available():
            print(f"run_typical_comparison: {moonbit_project.MISSING_MESSAGE}", file=sys.stderr)
            continue
        executable = TOOLCHAIN_EXECUTABLES.get(language)
        if executable is not None and not (toolchains / executable).is_file():
            print(
                f"run_typical_comparison: {language} is not installed at "
                f"{toolchains / executable}; skipping it",
                file=sys.stderr,
            )
            continue
        if language in TYPESCRIPT_COMPILERS and shutil.which("node") is None:
            print(f"run_typical_comparison: node is required to run {language} output; skipping it", file=sys.stderr)
            continue
        available.append(language)
    return tuple(available)


def moonbit_profile(lane: str) -> str:
    return "release" if lane == "optimized" else "debug"


def lanes_for(language: str) -> tuple[str, ...]:
    # TCC deliberately omits an optimizer, so separate optimization lanes would
    # measure the same compiler configuration under misleading names.
    if language == "tcc":
        return ("default",)
    # TypeScript has one configuration: a full type check plus JavaScript emit.
    if language in TYPESCRIPT_COMPILERS:
        return ("check_emit",)
    return LANES


def parse_tcc_parallel_shards(value: str) -> tuple[int, ...]:
    if not value.strip():
        return ()
    try:
        shards = tuple(int(part.strip()) for part in value.split(",") if part.strip())
    except ValueError as error:
        raise argparse.ArgumentTypeError(
            "TCC parallel shard counts must be comma-separated positive integers"
        ) from error
    if not shards or any(shard <= 0 for shard in shards) or len(set(shards)) != len(shards):
        raise argparse.ArgumentTypeError(
            "TCC parallel shard counts must be distinct positive integers"
        )
    return shards


def tcc_lanes(
    parallel_shards: tuple[int, ...], include_serial: bool = True
) -> tuple[str, ...]:
    serial = ("default",) if include_serial else ()
    return (*serial, *(f"parallel-{shards}" for shards in parallel_shards))


def tcc_parallel_shard_count(lane: str) -> int | None:
    prefix = "parallel-"
    if not lane.startswith(prefix):
        return None
    try:
        shards = int(lane.removeprefix(prefix))
    except ValueError as error:
        raise ValueError(f"invalid TCC parallel lane {lane!r}") from error
    if shards <= 0:
        raise ValueError(f"invalid TCC parallel lane {lane!r}")
    return shards


def partition_tcc_sources(sources: list[Path], shard_count: int) -> list[list[Path]]:
    """Split sorted translation units into contiguous, approximately byte-balanced shards."""
    if shard_count <= 0 or shard_count > len(sources):
        raise ValueError(
            f"TCC shard count must be between 1 and {len(sources)}, got {shard_count}"
        )
    weights = [source.stat().st_size for source in sources]
    shards: list[list[Path]] = []
    cursor = 0
    remaining_weight = sum(weights)
    for shard_index in range(shard_count):
        remaining_shards = shard_count - shard_index
        if remaining_shards == 1:
            end = len(sources)
        else:
            target = (remaining_weight + remaining_shards - 1) // remaining_shards
            end = cursor
            shard_weight = 0
            maximum_end = len(sources) - (remaining_shards - 1)
            while end < maximum_end and (end == cursor or shard_weight < target):
                shard_weight += weights[end]
                end += 1
        shard = sources[cursor:end]
        shards.append(shard)
        consumed = sum(weights[cursor:end])
        remaining_weight -= consumed
        cursor = end
    assert cursor == len(sources)
    assert all(shards)
    return shards


def ninja_command(command: list[str]) -> str:
    return " ".join(
        token if token in {"$in", "$out"} else shlex.quote(token).replace("$", "$$")
        for token in command
    )


def write_tcc_parallel_ninja(
    root: Path,
    sources: list[Path],
    shard_count: int,
    tcc: str,
    tcc_runtime_path: Path | None,
) -> tuple[Path, Path]:
    build_file = root / f"build-tcc-parallel-{shard_count}.ninja"
    build_root = root / ".benchmark-cache" / f"tcc-parallel-{shard_count}"
    build_root.mkdir(parents=True, exist_ok=True)
    output = root / f"typical-project-tcc-parallel-{shard_count}"
    base = [tcc]
    if tcc_runtime_path is not None:
        base.append(f"-B{tcc_runtime_path}")
    shard_command = ninja_command(
        [*base, "-std=c11", "-Iinclude", "-r", "-o", "$out", "$in"]
    )
    link_command = ninja_command([*base, "-o", "$out", "$in"])
    lines = [
        "rule tcc_shard",
        f"  command = {shard_command}",
        "  description = TCC-R $out",
        "rule tcc_link",
        f"  command = {link_command}",
        "  description = TCC-LINK $out",
    ]
    objects = []
    for index, shard in enumerate(partition_tcc_sources(sources, shard_count)):
        object_path = build_root / f"shard-{index:03}.o"
        object_relative = object_path.relative_to(root)
        source_relative = [source.relative_to(root) for source in shard]
        objects.append(object_relative)
        lines.append(
            f"build {object_relative}: tcc_shard "
            + " ".join(map(str, source_relative))
        )
    lines.append(f"build {output.name}: tcc_link " + " ".join(map(str, objects)))
    lines.append(f"default {output.name}")
    build_file.write_text("\n".join(lines) + "\n")
    return build_file, output


def write_variant(path: Path, original: str, lane: str, sample: int) -> None:
    path.write_text(original + f"\n// lanius benchmark variant {lane} {sample}\n")


def median_mad(values: list[float]) -> dict[str, float | int]:
    median = statistics.median(values)
    return {
        "samples": len(values),
        "median_ms": median,
        "mad_ms": statistics.median(abs(value - median) for value in values),
        "min_ms": min(values),
        "max_ms": max(values),
    }


def run_checked(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> None:
    result = subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {command!r}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def timed_checked(
    command: list[str],
    cwd: Path,
    env: dict[str, str] | None = None,
    timeout: float | None = None,
) -> float:
    """Wall time of one build; raises subprocess.TimeoutExpired past timeout."""
    started = time.perf_counter_ns()
    # Its own session, so a timeout stops the compiler's children (ninja jobs,
    # V's cc processes) as well as the driver.
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if process.returncode != 0:
        raise RuntimeError(
            f"command failed ({process.returncode}): {command!r}\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )
    return elapsed


def command_for(
    project: Path,
    language: str,
    lane: str,
    sample: int,
    rust_frontend_threads: int,
    tcc: str = "tcc",
    tcc_runtime_path: Path | None = None,
    toolchains: Path = DEFAULT_TOOLCHAINS,
    c_compilers: tuple[str, str] = ("cc", "c++"),
    rust_toolchain: str | None = None,
) -> tuple[list[str], Path, Path, dict[str, str]]:
    env = os.environ.copy()
    if language in {"d", "ldc"}:
        return d_command(project, language, lane, toolchains), project / "d", project / "d" / f"typical-project-{language}-{lane}", env
    if language == "go":
        return go_command(project, lane, sample, toolchains)
    if language == "v":
        return v_command(project, lane, sample, toolchains)
    if language in TYPESCRIPT_COMPILERS:
        root = project / "ts"
        shutil.rmtree(root / "out", ignore_errors=True)
        executable = TSC_NATIVE if language == "tsc" else TSRS_NATIVE
        return (
            [str(toolchains / executable), "-p", "tsconfig.json", "--checkers", str(TYPESCRIPT_CHECKERS)],
            root,
            root / "out" / "main.js",
            env,
        )
    if language == "tcc":
        root = project / "c"
        source_paths = sorted((root / "src").glob("*.c"))
        sources = [str(path.relative_to(root)) for path in source_paths]
        if not sources:
            raise RuntimeError(f"TCC project has no C sources: {root}")
        parallel_shards = tcc_parallel_shard_count(lane)
        if parallel_shards is not None:
            build_file, output = write_tcc_parallel_ninja(
                root,
                source_paths,
                parallel_shards,
                tcc,
                tcc_runtime_path,
            )
            run_checked(["ninja", "-f", build_file.name, "-t", "clean"], root)
            return (
                ["ninja", "-f", build_file.name, "-j", str(parallel_shards)],
                root,
                output,
                env,
            )
        output = root / "typical-project-tcc"
        output.unlink(missing_ok=True)
        command = [tcc]
        if tcc_runtime_path is not None:
            command.append(f"-B{tcc_runtime_path}")
        return (
            [*command, "-std=c11", "-Iinclude", "-o", str(output), *sources],
            root,
            output,
            env,
        )
    if language in {"c", "cpp"}:
        root = project / language
        build_file = f"build-{lane}.ninja"
        select_ninja_compiler(root / build_file, c_compilers[language == "cpp"])
        run_checked(["ninja", "-f", build_file, "-t", "clean"], root)
        return ["ninja", "-f", build_file], root, root / f"typical-project-{lane}", env
    if language == "rust":
        root = project / "rust"
        env["CARGO_INCREMENTAL"] = "0"
        if rust_toolchain is not None:
            env["RUSTUP_TOOLCHAIN"] = rust_toolchain
        env["RUSTFLAGS"] = f"-Awarnings -Zthreads={rust_frontend_threads}"
        run_checked(["cargo", "clean", "--quiet"], root, env)
        command = ["cargo", "build", "--quiet"]
        profile = "debug"
        if lane == "optimized":
            command.append("--release")
            profile = "release"
        return command, root, root / "target" / profile / "typical_project", env
    if language == "moonbit":
        root = project / "moonbit"
        run_checked([moonbit_project.MOON, "clean"], root, env)
        profile = moonbit_profile(lane)
        return (
            moonbit_project.build_command("native", profile),
            root,
            moonbit_project.artifact_candidates(root, "native", profile)[0],
            env,
        )
    if language == "zig":
        root = project / "zig"
        cache = project / ".benchmark-cache" / f"zig-{lane}"
        local_cache = cache / f"local-{sample}"
        shutil.rmtree(local_cache, ignore_errors=True)
        local_cache.mkdir(parents=True)
        (cache / "global").mkdir(parents=True, exist_ok=True)
        output = root / f"typical-project-{lane}"
        output.unlink(missing_ok=True)
        mode = "Debug" if lane == "o0" else "ReleaseFast"
        return (
            [
                zig_executable(toolchains),
                "build-exe",
                "-lc",
                "-O",
                mode,
                "-fstrip",
                "main.zig",
                "--cache-dir",
                str(local_cache),
                "--global-cache-dir",
                str(cache / "global"),
                f"-femit-bin={output}",
            ],
            root,
            output,
            env,
        )
    raise AssertionError(language)


def d_command(project: Path, language: str, lane: str, toolchains: Path) -> list[str]:
    """dmd and LDC compile and link the whole project in one invocation, the
    way dub and hand-written D builds do; neither keeps a cache."""
    root = project / "d"
    objects = root / "build" / f"{language}-{lane}"
    shutil.rmtree(objects, ignore_errors=True)
    output = root / f"typical-project-{language}-{lane}"
    output.unlink(missing_ok=True)
    sources = ["main.d", *sorted(str(path.relative_to(root)) for path in (root / "typical").glob("*.d"))]
    compiler, flags = d_compiler_flags(language, lane, toolchains)
    return [str(compiler), *flags, f"-od={objects.relative_to(root)}", f"-of={output.name}", *sources]


def d_compiler_flags(language: str, lane: str, toolchains: Path) -> tuple[Path, list[str]]:
    if language == "d":
        return toolchains / DMD, (["-O", "-release", "-inline"] if lane == "optimized" else [])
    return toolchains / LDC2, (["-O3", "-release"] if lane == "optimized" else ["-O0"])


def configured_command(
    project: Path,
    language: str,
    lane: str,
    sample: int,
    config: str,
    **options,
) -> tuple[list[str], Path, Path, dict[str, str]]:
    """command_for, adjusted for one parallelism configuration
    (typical_parallelism); "default" is the compiler's default parallelism."""
    if language == "tcc":
        return command_for(project, language, typical_parallelism.tcc_lane(config) if config != "default" else lane, sample, **options)
    if language in {"d", "ldc"} and config.startswith("separate-j"):
        root = project / "d"
        compiler, flags = d_compiler_flags(language, lane, options["toolchains"])
        command, output = typical_parallelism.d_separate_build(
            root, language, lane, compiler, flags, typical_parallelism.number(config, "j")
        )
        return command, root, output, os.environ.copy()
    command, cwd, artifact, env = command_for(project, language, lane, sample, **options)
    return typical_parallelism.apply(language, lane, config, command, env), cwd, artifact, env


def go_std_imports(root: Path) -> list[str]:
    imports = set()
    for source in root.rglob("*.go"):
        in_block = False
        for line in source.read_text().splitlines():
            stripped = line.strip()
            if stripped.startswith("import ("):
                in_block = True
                continue
            if in_block and stripped == ")":
                in_block = False
                continue
            if in_block or stripped.startswith("import "):
                quoted = stripped.split('"')
                if len(quoted) >= 3 and not quoted[1].startswith("typical"):
                    imports.add(quoted[1])
    return sorted(imports)


def go_command(
    project: Path, lane: str, sample: int, toolchains: Path
) -> tuple[list[str], Path, Path, dict[str, str]]:
    root = project / "go"
    cache = project / ".benchmark-cache" / "go"
    snapshot = cache / "std"
    env = compiler_environment("go", toolchains, cache)
    go = str(toolchains / GO_ROOT / "bin/go")
    if not snapshot.is_dir():
        primer = cache / "std-primer"
        shutil.rmtree(primer, ignore_errors=True)
        primer.mkdir(parents=True)
        imports = go_std_imports(root)
        (primer / "go.mod").write_text("module primer\n\ngo 1.27\n")
        (primer / "main.go").write_text(GO_STD_PRIMER.format(
            imports="".join(f'\t_ "{name}"\n' for name in imports)
        ))
        partial = cache / "std.partial"
        shutil.rmtree(partial, ignore_errors=True)
        env["GOCACHE"] = str(partial)
        run_checked([go, "build", "-o", "primer", "."], primer, env)
        partial.rename(snapshot)
    sample_cache = fresh_cache_copy(snapshot, cache / f"sample-{lane}-{sample}")
    env["GOCACHE"] = str(sample_cache)
    output = root / f"typical-project-{lane}"
    output.unlink(missing_ok=True)
    # -N -l (no optimisation, no inlining) for the project's own packages only,
    # not the standard library, as in the single-file runner.
    flags = ["-gcflags=typical/...=-N -l"] if lane == "o0" else []
    return [go, "build", *flags, "-o", output.name, "."], root, output, env


def fresh_cache_copy(snapshot: Path, sample_cache: Path) -> Path:
    """Replace every earlier per-sample copy with a new copy of the snapshot,
    so a run keeps one copy on disk rather than one per sample."""
    for previous in sample_cache.parent.glob("sample-*"):
        shutil.rmtree(previous, ignore_errors=True)
    shutil.copytree(snapshot, sample_cache)
    return sample_cache


def v_imports(source: Path) -> list[str]:
    """vlib modules imported by main.v (project modules have no dot and live
    beside v.mod; vlib modules the probe uses are os, time and crypto.rand)."""
    project_modules = {path.name for path in source.parent.iterdir() if path.is_dir()}
    return sorted(
        line.split()[1]
        for line in source.read_text().splitlines()
        if line.startswith("import ") and line.split()[1] not in project_modules
    )


def v_command(
    project: Path, lane: str, sample: int, toolchains: Path
) -> tuple[list[str], Path, Path, dict[str, str]]:
    """V generates C for the program and compiles it (its bundled TCC by
    default, the system cc at -O3 with -prod); some V versions cache one C
    object per module. Every sample starts from a copy of a run-private cache
    holding only V's runtime, so every project module is compiled every time."""
    root = project / "v"
    cache = project / ".benchmark-cache" / f"v-{lane}"
    snapshot = cache / "std"
    v = str(toolchains / V_ROOT / "v")
    flags = ["-prod"] if lane == "optimized" else []
    if not snapshot.is_dir():
        primer = cache / "std-primer"
        shutil.rmtree(primer, ignore_errors=True)
        primer.mkdir(parents=True)
        (primer / "v.mod").write_text("Module {\n\tname: 'primer'\n}\n")
        (primer / "main.v").write_text(V_STD_PRIMER.format(
            imports="".join(f"import {name}\n" for name in v_imports(root / "main.v"))
        ))
        partial = cache / "std.partial"
        shutil.rmtree(partial, ignore_errors=True)
        primer_env = compiler_environment("v", toolchains, partial)
        run_checked([v, "-w", "-n", *flags, "-o", "primer", "."], primer, primer_env)
        partial.rename(snapshot)
    sample_cache = fresh_cache_copy(snapshot, cache / f"sample-{sample}")
    env = compiler_environment("v", toolchains, sample_cache)
    output = root / f"typical-project-{lane}"
    output.unlink(missing_ok=True)
    return [v, "-w", "-n", *flags, "-o", output.name, "."], root, output, env


def validate(path: Path, expected: str, cwd: Path) -> str:
    command = ["node", str(path)] if path.suffix == ".js" else [str(path)]
    result = subprocess.run(
        command, cwd=cwd, capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0 or result.stdout != expected:
        raise RuntimeError(
            f"artifact validation failed: {path}; status={result.returncode}; "
            f"stdout={result.stdout!r}; expected={expected!r}; stderr={result.stderr!r}"
        )
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_version(command: list[str]) -> str:
    if shutil.which(command[0]) is None and not Path(command[0]).is_file():
        return "not installed"
    result = subprocess.run(command, capture_output=True, text=True)
    return (result.stdout or result.stderr).splitlines()[0]


def write_canonical_tcc_results(
    repo: Path,
    result_root: Path,
    raw_output: Path,
    counts: list[int],
    seed: int,
    samples: list[dict[str, object]],
    machine: dict[str, object],
) -> list[Path]:
    """Write compact viewer-ready TCC baselines from retained raw samples."""
    written = []
    for count in counts:
        project = repo / f"target/typical-project-{count}"
        source_paths = sorted((project / "c/src").glob("*.c"))
        facts = source_facts(source_paths, repo)
        # Per-file facts make a 10,000-file result needlessly large. The aggregate
        # facts retain every value displayed by the performance viewer.
        facts.pop("file_records", None)
        retained = [
            sample
            for sample in samples
            if sample["file_count"] == count
            and sample["language"] == "tcc"
        ]
        if not retained:
            raise ValueError(f"no retained TCC samples for {count} files")
        run_id = f"frozen-typical-project-{count}-files-tcc"
        document = new_document(
            repo,
            run_id,
            {
                "id": f"typical-project-{count}-files-seed-{seed}",
                "kind": "typical_project",
                "classification": "frozen external compiler baseline for the corpus-calibrated typical project",
                "generator": "tools/generate_typical_project.py",
                "seed": seed,
                "requested_source_files": count,
                "baseline_only": True,
                "comparison_group": f"typical-project/v1/seed-{seed}/files-{count}",
            },
            {
                "platform": machine["platform"],
                "logical_cpus": machine["logical_cpus"],
                "gpu": machine["gpu"],
            },
        )
        try:
            source_artifact = str(raw_output.relative_to(repo))
        except ValueError:
            source_artifact = str(raw_output)
        retained_lanes = sorted({str(sample["lane"]) for sample in retained})
        path = result_root / f"{run_id}.json"
        if path.is_file():
            previous = json.loads(path.read_text())
            if (
                previous.get("workload", {}).get("comparison_group")
                != document["workload"]["comparison_group"]
            ):
                raise ValueError(
                    f"existing TCC result has a different workload identity: {path}"
                )
            document["measurements"].extend(
                measurement
                for measurement in previous.get("measurements", [])
                if measurement.get("compiler", {}).get("name") == "tcc"
                and measurement.get("configuration") not in retained_lanes
            )
        for lane in retained_lanes:
            lane_samples = [sample for sample in retained if sample["lane"] == lane]
            measurement_samples = [
                {
                    "index": index,
                    "wall_ms": float(sample["wall_ms"]),
                    "compiler_ms": None,
                }
                for index, sample in enumerate(lane_samples)
            ]
            command = [str(part) for part in lane_samples[0]["command"]]
            parallel_shards = tcc_parallel_shard_count(lane)
            configuration_display = (
                f"parallel, {parallel_shards} shards"
                if parallel_shards is not None
                else None
            )
            document["measurements"].append(
                {
                    "id": f"tcc-{lane}",
                    "compiler": {
                        "name": "tcc",
                        "version": machine["versions"]["tcc"],
                    },
                    "target": "x86_64",
                    "configuration": lane,
                    "configuration_display": configuration_display,
                    "source": facts,
                    "commands": {
                        "command": command_record(command, project / "c"),
                    },
                    "measurement_semantics": {
                        "build": (
                            f"Ninja runs {parallel_shards} byte-balanced TCC partial-link "
                            "shards in parallel, followed by one TCC link"
                            if parallel_shards is not None
                            else "one TCC process compiles and links every generated C source"
                        ),
                        "debug_info": "disabled",
                        "frozen_baseline": True,
                        "samples": "exact retained wall-time samples",
                        "source_artifact": source_artifact,
                    },
                    "samples": measurement_samples,
                    "summary": summarize(measurement_samples, facts),
                    "validation": {
                        "artifacts_validated": True,
                        "expected_output_validated": True,
                    },
                }
            )
        document["measurements"].sort(
            key=lambda measurement: measurement["configuration"]
        )
        write_document(path, document)
        written.append(path)
    return written


def measure_configuration(
    project: Path,
    language: str,
    lane: str,
    config: str,
    sample_count: int,
    source: Path,
    original: str,
    expected: str,
    options: dict[str, object],
    build_timeout: float,
) -> dict[str, object]:
    """Time sample_count clean builds of one configuration, validating each
    artifact; stops at the first build past build_timeout (DNF)."""
    elapsed: list[float] = []
    hashes: list[str] = []
    retained: list[dict[str, object]] = []
    dnf = False
    sample_target = sample_count
    sample = 0
    while sample < sample_target:
        write_variant(source, original, lane, sample)
        command, cwd, artifact, env = configured_command(
            project, language, lane, sample, config, **options
        )
        try:
            wall_ms = timed_checked(command, cwd, env, build_timeout)
        except subprocess.TimeoutExpired:
            dnf = True
            print(
                f"run_typical_comparison: {language} {lane} {config} exceeded "
                f"{build_timeout:g}s: DNF",
                file=sys.stderr,
                flush=True,
            )
            break
        if language == "moonbit":
            # Older moon toolchains write target/, not _build/.
            artifact = moonbit_project.artifact_path(cwd, "native", moonbit_profile(lane))
        hashes.append(validate(artifact, expected, project))
        elapsed.append(wall_ms)
        retained.append(
            {
                "language": language,
                "lane": lane,
                "parallelism": config,
                "sample": sample,
                "wall_ms": wall_ms,
                "command": command,
            }
        )
        if sample == 0 and wall_ms > SLOW_LANE_THRESHOLD_MS and sample_target > SLOW_LANE_SAMPLES:
            sample_target = SLOW_LANE_SAMPLES
        sample += 1
    return {"elapsed": elapsed, "hashes": hashes, "samples": retained, "dnf": dnf}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file-counts", default="1,10,100,1000,10000")
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--seed", type=int, default=20260808)
    parser.add_argument("--output", required=True)
    parser.add_argument(
        "--canonical-result-dir",
        type=Path,
        help="also write one canonical TCC performance-viewer result per workload",
    )
    parser.add_argument("--languages", type=parse_languages, default=LANGUAGES)
    parser.add_argument("--rust-frontend-threads", type=int, default=16)
    parser.add_argument("--tcc", help="TCC executable (default: the toolchains build, else tcc)")
    parser.add_argument("--cc", help="C compiler (default: newest gcc-N installed, else cc)")
    parser.add_argument("--cxx", help="C++ compiler (default: newest g++-N installed, else c++)")
    parser.add_argument(
        "--rust-toolchain",
        help="rustup toolchain for the Rust lanes (default: the rustup default)",
    )
    parser.add_argument(
        "--tcc-runtime-path",
        type=Path,
        help="optional TCC runtime directory for an extracted installation",
    )
    parser.add_argument(
        "--tcc-parallel-shards",
        type=parse_tcc_parallel_shards,
        default=(),
        help="comma-separated TCC partial-link shard counts to benchmark",
    )
    parser.add_argument(
        "--skip-tcc-serial",
        action="store_true",
        help="benchmark only the requested parallel TCC configurations",
    )
    parser.add_argument(
        "--toolchains",
        type=Path,
        default=DEFAULT_TOOLCHAINS,
        help="directory holding the go, dmd, ldc, v and ts toolchains",
    )
    parser.add_argument(
        "--build-timeout",
        type=float,
        default=DEFAULT_BUILD_TIMEOUT_SECONDS,
        help="seconds after which any build is stopped and its lane recorded as DNF",
    )
    parser.add_argument(
        "--tune-parallelism",
        action="store_true",
        help=(
            "sweep each compiler's parallelism settings (typical_parallelism), "
            "then measure the fastest one"
        ),
    )
    parser.add_argument(
        "--sweep-samples",
        type=int,
        default=5,
        help="samples per candidate configuration in the parallelism sweep",
    )
    parser.add_argument("--skip-generation", action="store_true")
    parser.add_argument("--skip-lanius", action="store_true")
    args = parser.parse_args()
    if args.samples <= 0:
        parser.error("--samples must be positive")
    if args.rust_frontend_threads <= 0:
        parser.error("--rust-frontend-threads must be positive")
    if args.skip_tcc_serial and not args.tcc_parallel_shards:
        parser.error("--skip-tcc-serial requires --tcc-parallel-shards")

    args.toolchains = args.toolchains.resolve()
    args.languages = available_languages(args.languages, args.toolchains)
    if not args.languages and args.skip_lanius:
        parser.error("no requested compiler is available")

    repo = Path(__file__).resolve().parents[1]
    default_cc, default_cxx = default_c_compilers()
    args.cc = args.cc or default_cc
    args.cxx = args.cxx or default_cxx
    args.tcc = args.tcc or default_tcc(args.toolchains)
    if Path(args.tcc).parent != Path("."):
        args.tcc = str((repo / args.tcc).resolve())
    if args.tcc_runtime_path is not None:
        args.tcc_runtime_path = (repo / args.tcc_runtime_path).resolve()
    counts = parse_counts(args.file_counts)
    output = (repo / args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    for count in counts:
        project = repo / f"target/typical-project-{count}"
        if not args.skip_generation:
            generate(project, count, args.seed)

    lanius_output = output.with_name(output.stem + "-lanius.json")
    lanius = None
    if not args.skip_lanius:
        run_checked(
            [
                sys.executable,
                str(repo / "tools/run_typical_lanius_matrix.py"),
                "--file-counts",
                ",".join(map(str, counts)),
                "--samples",
                str(args.samples),
                "--target",
                "x86_64",
                "--output",
                str(lanius_output),
            ],
            repo,
        )
        lanius = json.loads(lanius_output.read_text())

    rows: list[dict[str, object]] = []
    samples: list[dict[str, object]] = []
    for count in counts:
        project = repo / f"target/typical-project-{count}"
        manifest = json.loads((project / "manifest.json").read_text())
        expected = manifest["expected_stdout"]
        for language in args.languages:
            language_lanes = (
                tcc_lanes(args.tcc_parallel_shards, not args.skip_tcc_serial)
                if language == "tcc"
                else lanes_for(language)
            )
            for lane in language_lanes:
                source = entry_source(project, language)
                original = source.read_text()
                options = {
                    "rust_frontend_threads": args.rust_frontend_threads,
                    "tcc": args.tcc,
                    "tcc_runtime_path": args.tcc_runtime_path,
                    "toolchains": args.toolchains,
                    "c_compilers": (args.cc, args.cxx),
                    "rust_toolchain": args.rust_toolchain,
                }
                sweep: dict[str, dict[str, object]] = {}
                try:
                    if language == "zig":
                        write_variant(source, original, lane, -1)
                        command, cwd, artifact, env = command_for(project, language, lane, -1, **options)
                        run_checked(command, cwd, env)
                        validate(artifact, expected, project)
                    config = "default"
                    if args.tune_parallelism:
                        for candidate in typical_parallelism.candidates(
                            language,
                            lane,
                            manifest["languages"][source_language(language)]["source_file_count"],
                        ):
                            trial = measure_configuration(
                                project, language, lane, candidate, args.sweep_samples,
                                source, original, expected, options, args.build_timeout,
                            )
                            sweep[candidate] = (
                                {"dnf": True}
                                if trial["dnf"]
                                else median_mad(trial["elapsed"])
                            )
                            print(
                                f"run_typical_comparison: sweep {count} {language} {lane} {candidate}: "
                                + ("DNF" if trial["dnf"] else f"{sweep[candidate]['median_ms']:.1f} ms"),
                                file=sys.stderr,
                                flush=True,
                            )
                        finished = [name for name, result in sweep.items() if "median_ms" in result]
                        if finished:
                            config = min(finished, key=lambda name: sweep[name]["median_ms"])
                    result = measure_configuration(
                        project, language, lane, config, args.samples,
                        source, original, expected, options, args.build_timeout,
                    )
                finally:
                    source.write_text(original)
                elapsed = result["elapsed"]
                dnf = result["dnf"]
                for sample in result["samples"]:
                    samples.append({"file_count": count, **sample})
                row = {
                    "file_count": count,
                    "source_files": manifest["languages"][source_language(language)]["source_file_count"],
                    "source_bytes": manifest["languages"][source_language(language)]["source_bytes"],
                    "language": language,
                    "lane": lane,
                    "parallelism": config,
                    "compile": median_mad(elapsed) if elapsed and not dnf else None,
                    "artifact_sha256_count": len(set(result["hashes"])),
                    "requested_samples": args.samples,
                }
                if sweep:
                    row["parallelism_sweep"] = sweep
                if dnf:
                    row["dnf"] = {
                        "timeout_seconds": args.build_timeout,
                        "completed_samples": len(elapsed),
                    }
                elif len(elapsed) < args.samples:
                    row["samples_reduced"] = {
                        "reason": (
                            f"first build exceeded {SLOW_LANE_THRESHOLD_MS / 1000:g}s; "
                            f"lane limited to {SLOW_LANE_SAMPLES} samples"
                        ),
                    }
                rows.append(row)
                print(json.dumps(row, sort_keys=True), flush=True)

    if lanius is not None:
        for row in lanius["rows"]:
            rows.append(
                {
                    "file_count": row["file_count"],
                    "source_files": row["source_files"],
                    "source_bytes": row["source_bytes"],
                    "language": "lanius",
                    "lane": "warm_daemon",
                    "compile": row["warm_job"],
                    "compiler_only": row["warm_compile"],
                    "cold_capacity_job_ms": row["cold_capacity_job_ms"],
                }
            )
        for count in counts:
            lanius_ms = next(
                row["compile"]["median_ms"]
                for row in rows
                if row["file_count"] == count and row["language"] == "lanius"
            )
            for row in rows:
                if row["file_count"] == count and row["compile"] is not None:
                    row["speedup_vs_lanius"] = row["compile"]["median_ms"] / lanius_ms

    versions = {
        "gcc": tool_version([args.cc, "--version"]),
        "g++": tool_version([args.cxx, "--version"]),
        "rustc": tool_version(["rustc", *([f"+{args.rust_toolchain}"] if args.rust_toolchain else []), "--version"]),
        "cargo": tool_version(["cargo", *([f"+{args.rust_toolchain}"] if args.rust_toolchain else []), "--version"]),
        "zig": tool_version([zig_executable(args.toolchains), "version"]),
        "ninja": tool_version(["ninja", "--version"]),
    }
    if "tcc" in args.languages:
        versions["tcc"] = tool_version([args.tcc, "-v"])
    if "moonbit" in args.languages:
        versions["moon"] = moonbit_project.version()
    toolchain_versions = {
        "d": ("dmd", [str(args.toolchains / DMD), "--version"]),
        "ldc": ("ldc2", [str(args.toolchains / LDC2), "--version"]),
        "go": ("go", [str(args.toolchains / GO_ROOT / "bin/go"), "version"]),
        "v": ("v", [str(args.toolchains / V_ROOT / "v"), "version"]),
        "tsc": ("tsc", [str(args.toolchains / TSC_NATIVE), "--version"]),
        "tsrs": ("tsrs", [str(args.toolchains / TSRS_NATIVE), "--version"]),
    }
    for language, (name, command) in toolchain_versions.items():
        if language in args.languages:
            versions[name] = tool_version(command)
    if any(language in TYPESCRIPT_COMPILERS for language in args.languages):
        versions["node"] = tool_version(["node", "--version"])

    document = {
        "schema": "lanius.typical-project-comparison.v1",
        "measurement_policy": {
            "native": "clean build; cleanup occurs before timed interval",
            "native_source_variation": "a semantics-neutral entry-source marker changes for every sample",
            "tcc": "serial TCC or byte-balanced parallel TCC partial-link shards followed by one TCC link; debug info disabled",
            "zig_cache": "fresh local build cache per sample; persistent compiler-global cache; one unmeasured primer per lane",
            "lanius": "warm daemon edit job including request, source load, compile, and artifact write",
            "debug_info": "disabled",
            "rust": (
                "clean Cargo build with incremental compilation disabled, warnings "
                f"suppressed, and nightly parallel frontend -Zthreads={args.rust_frontend_threads}"
            ),
            "moonbit": (
                "clean moon build of the native backend (moon clean before the timed "
                "interval); one package per module; o0 is --debug, optimized is --release"
            ),
            "d": (
                "dmd and LDC compile and link every module in one invocation; "
                "o0 is dmd's default or ldc2 -O0, optimized is dmd -O -release -inline "
                "or ldc2 -O3 -release"
            ),
            "go": (
                "go build of one module with one package per project module and the "
                "go command's default package parallelism; every sample starts from a "
                "copy of a run-private GOCACHE holding only the standard-library "
                "packages the project imports; o0 is -gcflags=typical/...=-N -l"
            ),
            "v": (
                "v builds the project with its default strategy, compiling the "
                "generated C with its bundled TCC, or the system cc at -O3 with "
                "-prod; every sample starts from a copy of a "
                "run-private cache holding only V's runtime and the vlib modules the "
                "project imports"
            ),
            "typescript": (
                "tsc and tsrs type-check every module and emit ES2022 JavaScript "
                f"(--checkers {TYPESCRIPT_CHECKERS}); node runs the output; no native code"
            ),
            "dnf": (
                f"any build still running after {args.build_timeout:g}s is stopped and "
                "its lane recorded as did-not-finish, for every compiler"
            ),
            "slow_lanes": (
                f"a lane whose first measured build exceeds {SLOW_LANE_THRESHOLD_MS / 1000:g}s "
                f"keeps {SLOW_LANE_SAMPLES} samples instead of the requested count"
            ),
            "parallelism": (
                "each compiler measured at the fastest of its parallelism settings "
                f"(tools/typical_parallelism.py), chosen by the lowest median of "
                f"{args.sweep_samples} samples per candidate; the sweep is retained per row"
                if args.tune_parallelism
                else "default compiler parallelism"
            ),
            "validation": "every emitted artifact executed and exact stdout checked",
        },
        "machine": {
            "platform": platform.platform(),
            "logical_cpus": os.cpu_count(),
            "gpu": subprocess.run(
                ["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True,
            ).stdout.strip(),
            "versions": versions,
        },
        "rows": rows,
        "native_samples": samples,
        "lanius_results": (
            str(lanius_output.relative_to(repo)) if lanius is not None else None
        ),
    }
    output.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    if args.canonical_result_dir is not None and "tcc" in args.languages:
        result_root = (repo / args.canonical_result_dir).resolve()
        for path in write_canonical_tcc_results(
            repo, result_root, output, counts, args.seed, samples, document["machine"]
        ):
            print(path, flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"run_typical_comparison: {error}", file=sys.stderr)
        raise SystemExit(1)
