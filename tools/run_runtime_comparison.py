#!/usr/bin/env python3
"""Generate, compile, execute, and record a runtime-only language comparison."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import random
import shutil
import statistics
import subprocess
import time
from pathlib import Path


LANGUAGES = ("c", "cpp", "rust", "zig", "lanius")
LANGUAGE_LANES = tuple(
    (language, lane)
    for language in LANGUAGES
    for lane in (("current",) if language == "lanius" else ("debug", "optimized"))
)
SCHEMA = "lanius.runtime-comparison.v1"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="benchmark_artifacts/runtime_integer_mix",
        help="checked artifact directory",
    )
    parser.add_argument("--iterations", type=int, default=25_000_000)
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--order-seed", type=int, default=0x52554E)
    parser.add_argument(
        "--measure",
        action="store_true",
        help="compile and measure rather than only regenerating sources/config",
    )
    args = parser.parse_args()
    if args.iterations <= 0 or args.iterations > 100_000_000:
        parser.error("--iterations must be in 1..=100000000")
    if args.warmups < 0 or args.samples <= 0:
        parser.error("--warmups must be nonnegative and --samples must be positive")

    repo = Path(__file__).resolve().parents[1]
    out = resolve(repo, args.out)
    src_dir = out / "src"
    output_dir = out / "outputs"
    bin_dir = repo / "target" / "runtime-comparison" / "integer_mix"
    src_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)
    for stale_output in output_dir.iterdir():
        if stale_output.is_file():
            stale_output.unlink()

    # Every executable sees exactly one process argument (argv[0]). Making the
    # trip count depend on argc prevents whole-program constant evaluation.
    expected = integer_mix(args.iterations + 1, 1)
    expected_stdout = f"{expected}\n"
    for language, source in sources(args.iterations).items():
        (src_dir / source_name(language)).write_text(source)

    commands = command_map(repo, out, bin_dir)
    config = {
        "schema": SCHEMA,
        "workload": "integer_mix",
        "base_iterations": args.iterations,
        "runtime_input": "argc; measured commands pass no extra arguments, so argc=1",
        "expected_stdout": expected_stdout,
        "warmups_per_language": args.warmups,
        "samples_per_language": args.samples,
        "order_seed": args.order_seed,
        "timed_region": "process spawn through process exit; compilation excluded",
        "optimization_policy": {
            "debug": "C/C++ -O0; Rust opt-level=0 with overflow checks; Zig Debug",
            "optimized": "C/C++ -O3; Rust opt-level=3; Zig ReleaseFast",
            "current": "current Lanius x86_64 output; no optimizer is implemented",
        },
        "validation_policy": "every warmup and measured execution must exit zero and match expected stdout",
        "generator_sha256": sha256_file(Path(__file__).resolve()),
    }
    write_json(out / "config.json", config)
    write_json(out / "commands.json", {"schema": SCHEMA, "commands": commands})

    if not args.measure:
        write_json(out / "machine_info.json", machine_info(None))
        write_json(out / "samples.json", {"schema": SCHEMA, "samples": []})
        write_json(out / "summary.json", {"schema": SCHEMA, "rows": []})
        write_tsv(out / "results.tsv", [])
        write_json(out / "manifest.json", manifest(out))
        return 0

    ensure_tools(commands)
    for language, lane in LANGUAGE_LANES:
        run_checked(commands[language][lane]["compile"], repo, None)

    affinity = sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else []
    cpu = affinity[0] if affinity else None
    run_commands = {
        (language, lane): pinned(commands[language][lane]["run"], cpu)
        for language, lane in LANGUAGE_LANES
    }

    for _ in range(args.warmups):
        for language, lane in LANGUAGE_LANES:
            stdout, _ = timed_run(run_commands[language, lane], repo)
            validate_output(language, stdout, expected_stdout)

    tasks = [
        (iteration, language, lane)
        for iteration in range(args.samples)
        for language, lane in LANGUAGE_LANES
    ]
    random.Random(args.order_seed).shuffle(tasks)
    samples = []
    last_stdout = {}
    for order, (iteration, language, lane) in enumerate(tasks):
        stdout, wall_ms = timed_run(run_commands[language, lane], repo)
        validate_output(language, stdout, expected_stdout)
        last_stdout[language, lane] = stdout
        samples.append(
            {
                "order": order,
                "iteration": iteration,
                "language": language,
                "lane": lane,
                "wall_ms": wall_ms,
                "stdout_sha256": sha256_bytes(stdout.encode()),
            }
        )

    for language, lane in LANGUAGE_LANES:
        (output_dir / f"{language}-{lane}.stdout").write_text(
            last_stdout[language, lane]
        )
    rows = summarize(samples)
    write_json(out / "machine_info.json", machine_info(cpu))
    write_json(out / "samples.json", {"schema": SCHEMA, "samples": samples})
    write_json(out / "summary.json", {"schema": SCHEMA, "rows": rows})
    write_tsv(out / "results.tsv", rows)
    write_json(out / "manifest.json", manifest(out))
    return 0


def integer_mix(iterations: int, salt: int) -> int:
    total = 0
    for index in range(iterations):
        lane = (index + salt) % 1021
        if lane % 4 < 2:
            total += lane
        else:
            total -= lane
        if total > 100_000:
            total -= 200_001
        if total < -100_000:
            total += 200_001
    return total


def sources(base_iterations: int) -> dict[str, str]:
    c = f"""#include <stdio.h>

static int integer_mix(int iterations, int salt) {{
    int total = 0;
    for (int index = 0; index < iterations; ++index) {{
        int lane = (index + salt) % 1021;
        if (lane % 4 < 2) total += lane; else total -= lane;
        if (total > 100000) total -= 200001;
        if (total < -100000) total += 200001;
    }}
    return total;
}}

int main(int argc, char **argv) {{
    (void)argv;
    printf("%d\\n", integer_mix({base_iterations} + argc, argc));
    return 0;
}}
"""
    cpp = c.replace("#include <stdio.h>", "#include <cstdio>").replace(
        "printf", "std::printf"
    )
    rust = f"""fn integer_mix(iterations: i32, salt: i32) -> i32 {{
    let mut total = 0;
    let mut index = 0;
    while index < iterations {{
        let lane = (index + salt) % 1021;
        if lane % 4 < 2 {{ total += lane; }} else {{ total -= lane; }}
        if total > 100_000 {{ total -= 200_001; }}
        if total < -100_000 {{ total += 200_001; }}
        index += 1;
    }}
    total
}}

fn main() {{
    let argc = std::env::args_os().count() as i32;
    println!("{{}}", integer_mix({base_iterations} + argc, argc));
}}
"""
    zig = f"""const std = @import("std");
const c = @cImport({{ @cInclude("stdio.h"); }});

fn integerMix(iterations: i32, salt: i32) i32 {{
    var total: i32 = 0;
    var index: i32 = 0;
    while (index < iterations) : (index += 1) {{
        const lane = @mod(index + salt, 1021);
        if (@mod(lane, 4) < 2) {{ total += lane; }} else {{ total -= lane; }}
        if (total > 100000) total -= 200001;
        if (total < -100000) total += 200001;
    }}
    return total;
}}

pub fn main(init: std.process.Init.Minimal) void {{
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\\n", integerMix({base_iterations} + argc, argc));
}}
"""
    lanius = f"""module app::main;

import std::io;
import std::process;

fn integer_mix(iterations: i32, salt: i32) -> i32 {{
    let total: i32 = 0;
    let index: i32 = 0;
    while (index < iterations) {{
        let lane: i32 = (index + salt) % 1021;
        if ((lane % 4) < 2) {{
            total += lane;
        }} else {{
            total -= lane;
        }}
        if (total > 100000) {{ total -= 200001; }}
        if (total < -100000) {{ total += 200001; }}
        index += 1;
    }}
    return total;
}}

fn main() -> i32 {{
    let argc: i32 = std::process::argc();
    std::io::print_i32(integer_mix({base_iterations} + argc, argc));
    return 0;
}}
"""
    return {"c": c, "cpp": cpp, "rust": rust, "zig": zig, "lanius": lanius}


def source_name(language: str) -> str:
    suffix = {"cpp": "cpp", "c": "c", "rust": "rs", "zig": "zig", "lanius": "lani"}
    return f"integer_mix.{suffix[language]}"


def command_map(
    repo: Path, out: Path, bin_dir: Path
) -> dict[str, dict[str, dict[str, list[str]]]]:
    src = portable_path(repo, out / "src")
    bin_dir = portable_path(repo, bin_dir)
    return {
        "c": {
            lane: {
                "compile": ["gcc", flag, "-g0", str(src / source_name("c")), "-o", str(bin_dir / f"c-{lane}")],
                "run": [str(bin_dir / f"c-{lane}")],
            }
            for lane, flag in (("debug", "-O0"), ("optimized", "-O3"))
        },
        "cpp": {
            lane: {
                "compile": ["g++", flag, "-g0", str(src / source_name("cpp")), "-o", str(bin_dir / f"cpp-{lane}")],
                "run": [str(bin_dir / f"cpp-{lane}")],
            }
            for lane, flag in (("debug", "-O0"), ("optimized", "-O3"))
        },
        "rust": {
            lane: {
                "compile": ["rustc", "-C", f"opt-level={level}", "-C", f"overflow-checks={'yes' if lane == 'debug' else 'no'}", "-C", "debuginfo=0", "-C", "strip=debuginfo", str(src / source_name("rust")), "-o", str(bin_dir / f"rust-{lane}")],
                "run": [str(bin_dir / f"rust-{lane}")],
            }
            for lane, level in (("debug", 0), ("optimized", 3))
        },
        "zig": {
            lane: {
                "compile": ["zig", "build-exe", "-lc", "-O", mode, "-fstrip", str(src / source_name("zig")), "-femit-bin=" + str(bin_dir / f"zig-{lane}")],
                "run": [str(bin_dir / f"zig-{lane}")],
            }
            for lane, mode in (("debug", "Debug"), ("optimized", "ReleaseFast"))
        },
        "lanius": {
            "current": {
                "compile": ["target/release/laniusc", "--stdlib-root", "stdlib", "--emit", "x86_64", "-o", str(bin_dir / "lanius-current"), str(src / source_name("lanius"))],
                "run": [str(bin_dir / "lanius-current")],
            },
        },
    }


def pinned(command: list[str], cpu: int | None) -> list[str]:
    if cpu is None or shutil.which("taskset") is None:
        return command
    return ["taskset", "-c", str(cpu), *command]


def portable_path(repo: Path, path: Path) -> Path:
    try:
        return path.relative_to(repo)
    except ValueError:
        return path


def ensure_tools(commands: dict[str, dict[str, dict[str, list[str]]]]) -> None:
    for language, lane in LANGUAGE_LANES:
        tool = commands[language][lane]["compile"][0]
        if shutil.which(tool) is None and not Path(tool).is_file():
            raise RuntimeError(f"required compiler for {language} is unavailable: {tool}")


def run_checked(command: list[str], cwd: Path, input_text: str | None) -> str:
    run = subprocess.run(
        command,
        cwd=cwd,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if run.returncode != 0:
        raise RuntimeError(f"command failed: {command!r}\n{run.stderr}")
    return run.stdout


def timed_run(command: list[str], cwd: Path) -> tuple[str, float]:
    started = time.perf_counter_ns()
    stdout = run_checked(command, cwd, None)
    return stdout, (time.perf_counter_ns() - started) / 1_000_000.0


def validate_output(language: str, actual: str, expected: str) -> None:
    if actual != expected:
        raise RuntimeError(f"{language} output mismatch: {actual!r} != {expected!r}")


def summarize(samples: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped = {
        (language, lane): [
            float(sample["wall_ms"])
            for sample in samples
            if sample["language"] == language and sample["lane"] == lane
        ]
        for language, lane in LANGUAGE_LANES
    }
    medians = {key: statistics.median(values) for key, values in grouped.items()}
    lanius = medians["lanius", "current"]
    return [
        {
            "language": language,
            "lane": lane,
            "samples": len(grouped[language, lane]),
            "median_ms": medians[language, lane],
            "mad_ms": statistics.median(
                abs(value - medians[language, lane])
                for value in grouped[language, lane]
            ),
            "min_ms": min(grouped[language, lane]),
            "max_ms": max(grouped[language, lane]),
            "lanius_runtime_ratio": lanius / medians[language, lane],
        }
        for language, lane in LANGUAGE_LANES
    ]


def machine_info(cpu: int | None) -> dict[str, object]:
    return {
        "schema": SCHEMA,
        "system": platform.platform(),
        "cpu_model": proc_field("/proc/cpuinfo", "model name"),
        "logical_cpus": os.cpu_count(),
        "pinned_cpu": cpu,
        "rustc": version(["rustc", "--version"]),
        "gcc": version(["gcc", "--version"]),
        "g++": version(["g++", "--version"]),
        "zig": version(["zig", "version"]),
        "laniusc": version([str(Path("target/release/laniusc").resolve()), "--version"]),
    }


def proc_field(path: str, key: str) -> str:
    try:
        for line in Path(path).read_text().splitlines():
            name, separator, value = line.partition(":")
            if separator and name.strip() == key:
                return value.strip()
    except OSError:
        pass
    return "missing"


def version(command: list[str]) -> str:
    if shutil.which(command[0]) is None and not Path(command[0]).is_file():
        return "missing"
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return run.stdout.splitlines()[0] if run.stdout else f"exit={run.returncode}"


def manifest(out: Path) -> dict[str, object]:
    files = []
    for path in sorted(out.rglob("*")):
        if path.is_file() and path.name != "manifest.json":
            files.append({"path": str(path.relative_to(out)), "sha256": sha256_file(path)})
    return {
        "schema": SCHEMA,
        "language_lanes": [
            {"language": language, "lane": lane}
            for language, lane in LANGUAGE_LANES
        ],
        "files": files,
    }


def write_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = (
        "language",
        "lane",
        "samples",
        "median_ms",
        "mad_ms",
        "min_ms",
        "max_ms",
        "lanius_runtime_ratio",
    )
    lines = ["\t".join(fields)]
    for row in rows:
        lines.append("\t".join(str(row[field]) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def resolve(repo: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else repo / path


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
