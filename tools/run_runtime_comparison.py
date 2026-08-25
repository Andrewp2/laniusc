#!/usr/bin/env python3
"""Generate, compile, execute, and record a runtime-only language comparison."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
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


LANGUAGE_LANES = (
    ("c", "debug"),
    ("c", "o2"),
    ("c", "optimized"),
    ("cpp", "debug"),
    ("cpp", "optimized"),
    ("rust", "debug"),
    ("rust", "optimized"),
    ("zig", "debug"),
    ("zig", "optimized"),
    ("tcc", "default"),
    ("lanius", "default"),
)
SCHEMA = "lanius.runtime-comparison.v2"
SUITE_SCHEMA = "lanius.runtime-suite.v1"


@dataclass(frozen=True)
class Workload:
    name: str
    description: str
    default_iterations: int
    operations_per_iteration: int

    def expected_stdout(self, iterations: int) -> str:
        result = {
            "integer_mix": integer_mix,
            "grid_checksum": grid_checksum,
            "array_walk": array_walk,
        }[self.name](iterations, 1)
        return f"{result}\n"

    def sources(self, iterations: int) -> dict[str, str]:
        return {
            "integer_mix": integer_mix_sources,
            "grid_checksum": grid_checksum_sources,
            "array_walk": array_walk_sources,
        }[self.name](iterations)


WORKLOADS = {
    workload.name: workload
    for workload in (
        Workload(
            "integer_mix",
            "scalar integer arithmetic with data-dependent branches",
            25_000_000,
            1,
        ),
        Workload(
            "grid_checksum",
            "nested loops and repeated helper calls over a two-dimensional domain",
            32_000,
            251,
        ),
        Workload(
            "array_walk",
            "indexed stack-array mutation and reduction over a 64-element working set",
            100_000,
            64,
        ),
    )
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--workload",
        choices=[*WORKLOADS, "all"],
        default="integer_mix",
        help="runtime workload to materialize or measure",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="checked artifact directory",
    )
    parser.add_argument(
        "--iterations",
        type=int,
        default=None,
        help="override the selected workload's outer iteration count",
    )
    parser.add_argument("--warmups", type=int, default=3)
    parser.add_argument("--samples", type=int, default=20)
    parser.add_argument("--order-seed", type=int, default=0x52554E)
    parser.add_argument(
        "--measure",
        action="store_true",
        help="compile and measure rather than only regenerating sources/config",
    )
    args = parser.parse_args()
    if args.iterations is not None and not 0 < args.iterations <= 100_000_000:
        parser.error("--iterations must be in 1..=100000000")
    if args.workload == "all" and args.iterations is not None:
        parser.error("--iterations may only be used with one workload")
    if args.warmups < 0 or args.samples <= 0:
        parser.error("--warmups must be nonnegative and --samples must be positive")

    repo = Path(__file__).resolve().parents[1]
    default_out = (
        "benchmark_artifacts/runtime_suite"
        if args.workload == "all"
        else f"benchmark_artifacts/runtime_{args.workload}"
    )
    out = resolve(repo, args.out or default_out)
    selected = list(WORKLOADS.values()) if args.workload == "all" else [WORKLOADS[args.workload]]
    suite_rows = []
    suite_summary = []
    for workload in selected:
        workload_out = out / workload.name if args.workload == "all" else out
        iterations = args.iterations or workload.default_iterations
        rows = run_workload(repo, workload_out, workload, iterations, args)
        suite_summary.extend({"workload": workload.name, **row} for row in rows)
        suite_rows.append(
            {
                "workload": workload.name,
                "description": workload.description,
                "artifact_path": str(workload_out.relative_to(out)),
                "iterations": iterations,
                "operation_count": iterations * workload.operations_per_iteration,
            }
        )
    if args.workload == "all":
        write_json(
            out / "suite.json",
            {
                "schema": SUITE_SCHEMA,
                "runtime_schema": SCHEMA,
                "generator_sha256": sha256_file(Path(__file__).resolve()),
                "measured": args.measure,
                "workloads": suite_rows,
            },
        )
        write_json(
            out / "summary.json",
            {"schema": SUITE_SCHEMA, "rows": suite_summary},
        )
        write_suite_tsv(out / "results.tsv", suite_summary)
    return 0


def run_workload(
    repo: Path,
    out: Path,
    workload: Workload,
    iterations: int,
    args: argparse.Namespace,
) -> list[dict[str, object]]:
    src_dir = out / "src"
    output_dir = out / "outputs"
    bin_dir = repo / "target" / "runtime-comparison" / workload.name
    src_dir.mkdir(parents=True, exist_ok=True)
    output_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)
    for stale_output in output_dir.iterdir():
        if stale_output.is_file():
            stale_output.unlink()

    # Every executable sees exactly one process argument (argv[0]). Making the
    # trip count depend on argc prevents whole-program constant evaluation.
    expected_stdout = workload.expected_stdout(iterations)
    for language, source in workload.sources(iterations).items():
        (src_dir / source_name(workload.name, language)).write_text(source)

    commands = command_map(repo, out, bin_dir, workload.name)
    config = {
        "schema": SCHEMA,
        "workload": workload.name,
        "description": workload.description,
        "base_iterations": iterations,
        "operations_per_iteration": workload.operations_per_iteration,
        "operation_count": iterations * workload.operations_per_iteration,
        "runtime_input": "argc; measured commands pass no extra arguments, so argc=1",
        "expected_stdout": expected_stdout,
        "warmups_per_language": args.warmups,
        "samples_per_language": args.samples,
        "order_seed": args.order_seed,
        "timed_region": "process spawn through process exit; compilation excluded",
        "optimization_policy": {
            "debug": "C/C++ -O0; Rust opt-level=0 with overflow checks; Zig Debug",
            "optimized": "C/C++ -O3; Rust opt-level=3; Zig ReleaseFast",
            "o2": "GCC -O2 with debug information disabled",
            "default": "compiler defaults for Lanius and TCC",
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
        return []

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
    return rows


def integer_mix(iterations: int, salt: int) -> int:
    total = 0
    for index in range(iterations + salt):
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


def integer_mix_sources(base_iterations: int) -> dict[str, str]:
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

extern "lanius_std" fn argc() -> i32;

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
    let argument_count: i32 = argc();
    print(integer_mix({base_iterations} + argument_count, argument_count));
    return 0;
}}
"""
    return {"c": c, "cpp": cpp, "rust": rust, "zig": zig, "lanius": lanius}


def grid_checksum(rows: int, salt: int) -> int:
    total = 0
    for y in range(rows + salt):
        for x in range(251):
            distance = x - y if x > y else y - x
            mixed = (x * 17 + y * 31 + salt * 13) % 97
            total += distance + mixed
            if total > 100_000:
                total -= 200_001
            if total < -100_000:
                total += 200_001
    return total


def grid_checksum_sources(base_rows: int) -> dict[str, str]:
    c = f"""#include <stdio.h>

static int cell_score(int x, int y, int salt) {{
    int distance = x > y ? x - y : y - x;
    int mixed = (x * 17 + y * 31 + salt * 13) % 97;
    return distance + mixed;
}}

static int grid_checksum(int rows, int salt) {{
    int total = 0;
    for (int y = 0; y < rows; ++y) {{
        for (int x = 0; x < 251; ++x) {{
            total += cell_score(x, y, salt);
            if (total > 100000) total -= 200001;
            if (total < -100000) total += 200001;
        }}
    }}
    return total;
}}

int main(int argc, char **argv) {{
    (void)argv;
    printf("%d\\n", grid_checksum({base_rows} + argc, argc));
    return 0;
}}
"""
    cpp = c.replace("#include <stdio.h>", "#include <cstdio>").replace(
        "printf", "std::printf"
    )
    rust = f"""fn cell_score(x: i32, y: i32, salt: i32) -> i32 {{
    let distance = if x > y {{ x - y }} else {{ y - x }};
    let mixed = (x * 17 + y * 31 + salt * 13) % 97;
    distance + mixed
}}

fn grid_checksum(rows: i32, salt: i32) -> i32 {{
    let mut total = 0;
    let mut y = 0;
    while y < rows {{
        let mut x = 0;
        while x < 251 {{
            total += cell_score(x, y, salt);
            if total > 100_000 {{ total -= 200_001; }}
            if total < -100_000 {{ total += 200_001; }}
            x += 1;
        }}
        y += 1;
    }}
    total
}}

fn main() {{
    let argc = std::env::args_os().count() as i32;
    println!("{{}}", grid_checksum({base_rows} + argc, argc));
}}
"""
    zig = f"""const std = @import("std");
const c = @cImport({{ @cInclude("stdio.h"); }});

fn cellScore(x: i32, y: i32, salt: i32) i32 {{
    const distance = if (x > y) x - y else y - x;
    const mixed = @mod(x * 17 + y * 31 + salt * 13, 97);
    return distance + mixed;
}}

fn gridChecksum(rows: i32, salt: i32) i32 {{
    var total: i32 = 0;
    var y: i32 = 0;
    while (y < rows) : (y += 1) {{
        var x: i32 = 0;
        while (x < 251) : (x += 1) {{
            total += cellScore(x, y, salt);
            if (total > 100000) total -= 200001;
            if (total < -100000) total += 200001;
        }}
    }}
    return total;
}}

pub fn main(init: std.process.Init.Minimal) void {{
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\\n", gridChecksum({base_rows} + argc, argc));
}}
"""
    lanius = f"""module app::main;

extern "lanius_std" fn argc() -> i32;

fn cell_score(x: i32, y: i32, salt: i32) -> i32 {{
    let distance: i32 = 0;
    if (x > y) {{ distance = x - y; }} else {{ distance = y - x; }}
    let mixed: i32 = (x * 17 + y * 31 + salt * 13) % 97;
    return distance + mixed;
}}

fn grid_checksum(rows: i32, salt: i32) -> i32 {{
    let total: i32 = 0;
    let y: i32 = 0;
    while (y < rows) {{
        let x: i32 = 0;
        while (x < 251) {{
            total += cell_score(x, y, salt);
            if (total > 100000) {{ total -= 200001; }}
            if (total < -100000) {{ total += 200001; }}
            x += 1;
        }}
        y += 1;
    }}
    return total;
}}

fn main() -> i32 {{
    let argument_count: i32 = argc();
    print(grid_checksum({base_rows} + argument_count, argument_count));
    return 0;
}}
"""
    return {"c": c, "cpp": cpp, "rust": rust, "zig": zig, "lanius": lanius}


def array_walk(rounds: int, salt: int) -> int:
    values = [index * 17 + 3 for index in range(64)]
    checksum = 0
    for round_index in range(rounds + salt):
        for index, previous in enumerate(values):
            value = (previous * 33 + round_index + index + salt) % 10_007
            values[index] = value
            checksum = (checksum + value) % 1_000_003
    return checksum


def array_walk_sources(base_rounds: int) -> dict[str, str]:
    initial = ", ".join(str(index * 17 + 3) for index in range(64))
    c = f"""#include <stdio.h>

static int array_walk(int rounds, int salt) {{
    int values[64] = {{{initial}}};
    int checksum = 0;
    for (int round = 0; round < rounds; ++round) {{
        for (int index = 0; index < 64; ++index) {{
            int value = (values[index] * 33 + round + index + salt) % 10007;
            values[index] = value;
            checksum = (checksum + value) % 1000003;
        }}
    }}
    return checksum;
}}

int main(int argc, char **argv) {{
    (void)argv;
    printf("%d\\n", array_walk({base_rounds} + argc, argc));
    return 0;
}}
"""
    cpp = c.replace("#include <stdio.h>", "#include <cstdio>").replace(
        "printf", "std::printf"
    )
    rust = f"""fn array_walk(rounds: i32, salt: i32) -> i32 {{
    let mut values: [i32; 64] = [{initial}];
    let mut checksum = 0;
    let mut round = 0;
    while round < rounds {{
        let mut index = 0;
        while index < 64 {{
            let value = (values[index] * 33 + round + index as i32 + salt) % 10_007;
            values[index] = value;
            checksum = (checksum + value) % 1_000_003;
            index += 1;
        }}
        round += 1;
    }}
    checksum
}}

fn main() {{
    let argc = std::env::args_os().count() as i32;
    println!("{{}}", array_walk({base_rounds} + argc, argc));
}}
"""
    zig = f"""const std = @import("std");
const c = @cImport({{ @cInclude("stdio.h"); }});

fn arrayWalk(rounds: i32, salt: i32) i32 {{
    var values = [_]i32{{{initial}}};
    var checksum: i32 = 0;
    var round: i32 = 0;
    while (round < rounds) : (round += 1) {{
        var index: usize = 0;
        while (index < 64) : (index += 1) {{
            const value = @mod(values[index] * 33 + round + @as(i32, @intCast(index)) + salt, 10007);
            values[index] = value;
            checksum = @mod(checksum + value, 1000003);
        }}
    }}
    return checksum;
}}

pub fn main(init: std.process.Init.Minimal) void {{
    const argc: i32 = @intCast(init.args.vector.len);
    _ = c.printf("%d\\n", arrayWalk({base_rounds} + argc, argc));
}}
"""
    lanius = f"""module app::main;

extern "lanius_std" fn argc() -> i32;

fn array_walk(rounds: i32, salt: i32) -> i32 {{
    let values: [i32; 64] = [{initial}];
    let checksum: i32 = 0;
    let round: i32 = 0;
    while (round < rounds) {{
        let index: i32 = 0;
        while (index < 64) {{
            let value: i32 = (values[index] * 33 + round + index + salt) % 10007;
            values[index] = value;
            checksum = (checksum + value) % 1000003;
            index += 1;
        }}
        round += 1;
    }}
    return checksum;
}}

fn main() -> i32 {{
    let argument_count: i32 = argc();
    print(array_walk({base_rounds} + argument_count, argument_count));
    return 0;
}}
"""
    return {"c": c, "cpp": cpp, "rust": rust, "zig": zig, "lanius": lanius}


def source_name(workload: str, language: str) -> str:
    suffix = {"cpp": "cpp", "c": "c", "rust": "rs", "zig": "zig", "lanius": "lani"}
    return f"{workload}.{suffix[language]}"


def command_map(
    repo: Path, out: Path, bin_dir: Path, workload: str
) -> dict[str, dict[str, dict[str, list[str]]]]:
    src = portable_path(repo, out / "src")
    bin_dir = portable_path(repo, bin_dir)
    return {
        "c": {
            lane: {
                "compile": ["gcc", flag, "-g0", str(src / source_name(workload, "c")), "-o", str(bin_dir / f"c-{lane}")],
                "run": [str(bin_dir / f"c-{lane}")],
            }
            for lane, flag in (("debug", "-O0"), ("o2", "-O2"), ("optimized", "-O3"))
        },
        "cpp": {
            lane: {
                "compile": ["g++", flag, "-g0", str(src / source_name(workload, "cpp")), "-o", str(bin_dir / f"cpp-{lane}")],
                "run": [str(bin_dir / f"cpp-{lane}")],
            }
            for lane, flag in (("debug", "-O0"), ("optimized", "-O3"))
        },
        "rust": {
            lane: {
                "compile": ["rustc", "-C", f"opt-level={level}", "-C", f"overflow-checks={'yes' if lane == 'debug' else 'no'}", "-C", "debuginfo=0", "-C", "strip=debuginfo", str(src / source_name(workload, "rust")), "-o", str(bin_dir / f"rust-{lane}")],
                "run": [str(bin_dir / f"rust-{lane}")],
            }
            for lane, level in (("debug", 0), ("optimized", 3))
        },
        "zig": {
            lane: {
                "compile": ["zig", "build-exe", "-lc", "-O", mode, "-fstrip", str(src / source_name(workload, "zig")), "-femit-bin=" + str(bin_dir / f"zig-{lane}")],
                "run": [str(bin_dir / f"zig-{lane}")],
            }
            for lane, mode in (("debug", "Debug"), ("optimized", "ReleaseFast"))
        },
        "tcc": {
            "default": {
                "compile": ["tcc", str(src / source_name(workload, "c")), "-o", str(bin_dir / "tcc-default")],
                "run": [str(bin_dir / "tcc-default")],
            },
        },
        "lanius": {
            "default": {
                "compile": ["target/release/laniusc", "--stdlib-root", "stdlib", "--emit", "x86_64", "-o", str(bin_dir / "lanius-default"), str(src / source_name(workload, "lanius"))],
                "run": [str(bin_dir / "lanius-default")],
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
    lanius = medians["lanius", "default"]
    return [
        {
            "language": language,
            "lane": lane,
            "samples": len(grouped[language, lane]),
            "median_ms": medians[language, lane],
            "mean_ms": statistics.mean(grouped[language, lane]),
            "mad_ms": statistics.median(
                abs(value - medians[language, lane])
                for value in grouped[language, lane]
            ),
            "min_ms": min(grouped[language, lane]),
            "max_ms": max(grouped[language, lane]),
            "lanius_speedup": medians[language, lane] / lanius,
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
        "tcc": version(["tcc", "-v"]),
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
        "mean_ms",
        "mad_ms",
        "min_ms",
        "max_ms",
        "lanius_speedup",
    )
    lines = ["\t".join(fields)]
    for row in rows:
        lines.append("\t".join(str(row[field]) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def write_suite_tsv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = (
        "workload",
        "language",
        "lane",
        "samples",
        "median_ms",
        "mean_ms",
        "mad_ms",
        "min_ms",
        "max_ms",
        "lanius_speedup",
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
