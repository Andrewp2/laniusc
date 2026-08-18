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
import statistics
import subprocess
import sys
import time
from pathlib import Path

from generate_typical_project import generate
from perf_model import command_record, new_document, source_facts, summarize, write_document
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
    parser.add_argument("--tcc", default="tcc", help="TCC executable")
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
    parser.add_argument("--skip-generation", action="store_true")
    parser.add_argument("--skip-lanius", action="store_true")
    args = parser.parse_args()
    if args.samples <= 0:
        parser.error("--samples must be positive")
    if args.rust_frontend_threads <= 0:
        parser.error("--rust-frontend-threads must be positive")
    if args.skip_tcc_serial and not args.tcc_parallel_shards:
        parser.error("--skip-tcc-serial requires --tcc-parallel-shards")

    repo = Path(__file__).resolve().parents[1]
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
            "tcc": "serial TCC or byte-balanced parallel TCC partial-link shards followed by one TCC link; debug info disabled",
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
