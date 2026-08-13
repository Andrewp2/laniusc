#!/usr/bin/env python3
"""Compare clean native builds with warm-daemon Lanius on typical projects."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

from generate_typical_project import generate
from run_typical_lanius_matrix import parse_counts


LANGUAGES = ("c", "cpp", "rust", "zig", "tcc")
LANES = ("o0", "optimized")


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
    }[language]
    return project / relative


def source_language(language: str) -> str:
    return "c" if language == "tcc" else language


def lanes_for(language: str) -> tuple[str, ...]:
    # TCC deliberately omits an optimizer, so separate optimization lanes would
    # measure the same compiler configuration under misleading names.
    return ("default",) if language == "tcc" else LANES


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


def timed_checked(command: list[str], cwd: Path, env: dict[str, str] | None = None) -> float:
    started = time.perf_counter_ns()
    run_checked(command, cwd, env)
    return (time.perf_counter_ns() - started) / 1_000_000.0


def command_for(
    project: Path,
    language: str,
    lane: str,
    sample: int,
    rust_frontend_threads: int,
    tcc: str = "tcc",
    tcc_runtime_path: Path | None = None,
) -> tuple[list[str], Path, Path, dict[str, str]]:
    env = os.environ.copy()
    if language == "tcc":
        root = project / "c"
        output = root / "typical-project-tcc"
        output.unlink(missing_ok=True)
        sources = sorted(
            str(path.relative_to(root)) for path in (root / "src").glob("*.c")
        )
        if not sources:
            raise RuntimeError(f"TCC project has no C sources: {root}")
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
        run_checked(["ninja", "-f", build_file, "-t", "clean"], root)
        return ["ninja", "-f", build_file], root, root / f"typical-project-{lane}", env
    if language == "rust":
        root = project / "rust"
        env["CARGO_INCREMENTAL"] = "0"
        env["RUSTFLAGS"] = f"-Awarnings -Zthreads={rust_frontend_threads}"
        run_checked(["cargo", "clean", "--quiet"], root, env)
        command = ["cargo", "build", "--quiet"]
        profile = "debug"
        if lane == "optimized":
            command.append("--release")
            profile = "release"
        return command, root, root / "target" / profile / "typical_project", env
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
                "zig",
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


def validate(path: Path, expected: str, cwd: Path) -> str:
    result = subprocess.run(
        [str(path)], cwd=cwd, capture_output=True, text=True, timeout=30
    )
    if result.returncode != 0 or result.stdout != expected:
        raise RuntimeError(
            f"artifact validation failed: {path}; status={result.returncode}; "
            f"stdout={result.stdout!r}; expected={expected!r}; stderr={result.stderr!r}"
        )
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tool_version(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True)
    return (result.stdout or result.stderr).splitlines()[0]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file-counts", default="1,10,100,1000,10000")
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--seed", type=int, default=20260808)
    parser.add_argument("--output", required=True)
    parser.add_argument("--languages", type=parse_languages, default=LANGUAGES)
    parser.add_argument("--rust-frontend-threads", type=int, default=16)
    parser.add_argument("--tcc", default="tcc", help="TCC executable")
    parser.add_argument(
        "--tcc-runtime-path",
        type=Path,
        help="optional TCC runtime directory for an extracted installation",
    )
    parser.add_argument("--skip-generation", action="store_true")
    parser.add_argument("--skip-lanius", action="store_true")
    args = parser.parse_args()
    if args.samples <= 0:
        parser.error("--samples must be positive")
    if args.rust_frontend_threads <= 0:
        parser.error("--rust-frontend-threads must be positive")

    repo = Path(__file__).resolve().parents[1]
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
            for lane in lanes_for(language):
                elapsed = []
                artifact_hashes = []
                source = entry_source(project, language)
                original = source.read_text()
                try:
                    if language == "zig":
                        write_variant(source, original, lane, -1)
                        command, cwd, artifact, env = command_for(
                            project, language, lane, -1, args.rust_frontend_threads
                        )
                        run_checked(command, cwd, env)
                        validate(artifact, expected, project)
                    for sample in range(args.samples):
                        write_variant(source, original, lane, sample)
                        command, cwd, artifact, env = command_for(
                            project,
                            language,
                            lane,
                            sample,
                            args.rust_frontend_threads,
                            args.tcc,
                            args.tcc_runtime_path,
                        )
                        wall_ms = timed_checked(command, cwd, env)
                        artifact_hashes.append(validate(artifact, expected, project))
                        elapsed.append(wall_ms)
                        samples.append(
                            {
                                "file_count": count,
                                "language": language,
                                "lane": lane,
                                "sample": sample,
                                "wall_ms": wall_ms,
                                "command": command,
                            }
                        )
                finally:
                    source.write_text(original)
                row = {
                    "file_count": count,
                    "source_files": manifest["languages"][source_language(language)]["source_file_count"],
                    "source_bytes": manifest["languages"][source_language(language)]["source_bytes"],
                    "language": language,
                    "lane": lane,
                    "compile": median_mad(elapsed),
                    "artifact_sha256_count": len(set(artifact_hashes)),
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
                if row["file_count"] == count:
                    row["speedup_vs_lanius"] = row["compile"]["median_ms"] / lanius_ms

    versions = {
        "gcc": tool_version(["gcc", "--version"]),
        "g++": tool_version(["g++", "--version"]),
        "rustc": tool_version(["rustc", "--version"]),
        "cargo": tool_version(["cargo", "--version"]),
        "zig": tool_version(["zig", "version"]),
        "ninja": tool_version(["ninja", "--version"]),
    }
    if "tcc" in args.languages:
        versions["tcc"] = tool_version([args.tcc, "-v"])

    document = {
        "schema": "lanius.typical-project-comparison.v1",
        "measurement_policy": {
            "native": "clean build; cleanup occurs before timed interval; default compiler parallelism",
            "native_source_variation": "a semantics-neutral entry-source marker changes for every sample",
            "tcc": "one TCC process compiles and links every generated C source; TCC has one default, non-optimizing lane",
            "zig_cache": "fresh local build cache per sample; persistent compiler-global cache; one unmeasured primer per lane",
            "lanius": "warm daemon edit job including request, source load, compile, and artifact write",
            "debug_info": "disabled",
            "rust": (
                "clean Cargo build with incremental compilation disabled, warnings "
                f"suppressed, and nightly parallel frontend -Zthreads={args.rust_frontend_threads}"
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
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"run_typical_comparison: {error}", file=sys.stderr)
        raise SystemExit(1)
