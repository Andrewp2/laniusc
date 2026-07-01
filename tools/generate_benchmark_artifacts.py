#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import platform
import shutil
import subprocess
import time
from pathlib import Path


LANGUAGES = ["rust", "c", "cpp", "zig", "lanius"]
WORKLOAD = {
    "name": "grid_checksum",
    "width": 32,
    "height": 24,
    "seed": 19,
    "expected_stdout": "44483\n",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--out",
        default="benchmark_artifacts/grid_checksum",
        help="artifact directory to create",
    )
    parser.add_argument(
        "--measure",
        action="store_true",
        help="compile and run artifacts, recording local timings",
    )
    args = parser.parse_args()

    repo = Path(__file__).resolve().parents[1]
    out = (repo / args.out).resolve()
    src_dir = out / "src"
    bin_dir = repo / "target" / "lanius-benchmark-artifacts" / WORKLOAD["name"]
    out_dir = out / "outputs"
    src_dir.mkdir(parents=True, exist_ok=True)
    bin_dir.mkdir(parents=True, exist_ok=True)
    out_dir.mkdir(parents=True, exist_ok=True)

    sources = source_texts()
    for language, text in sources.items():
        (src_dir / source_file_name(language)).write_text(text)

    commands = build_commands(repo, out)
    write_json(out / "generator_config.json", {"schema": "lanius.benchmark-generator.v1", **WORKLOAD})
    write_json(out / "commands.json", {"schema": "lanius.benchmark-commands.v1", "commands": commands})
    write_json(out / "machine_info.json", machine_info())

    results = []
    if args.measure:
        for language in LANGUAGES:
            results.append(measure_language(language, commands[language], out_dir, repo))
    else:
        for language in LANGUAGES:
            results.append(
                {
                    "language": language,
                    "status": "not_measured",
                    "compile_ms": "",
                    "run_ms": "",
                    "stdout_sha256": "",
                    "source_sha256": sha256_file(src_dir / source_file_name(language)),
                }
            )
    write_results(out / "results.tsv", results)
    write_json(out / "manifest.json", manifest(out, results))
    return 0


def source_file_name(language: str) -> str:
    return {
        "rust": "grid_checksum.rs",
        "c": "grid_checksum.c",
        "cpp": "grid_checksum.cpp",
        "zig": "grid_checksum.zig",
        "lanius": "grid_checksum.lani",
    }[language]


def source_texts() -> dict[str, str]:
    width = WORKLOAD["width"]
    height = WORKLOAD["height"]
    seed = WORKLOAD["seed"]
    rust = f"""fn cell_score(x: i32, y: i32, seed: i32) -> i32 {{
    let distance = if x > y {{ x - y }} else {{ y - x }};
    let mixed = (x * 17 + y * 31 + seed * 13) % 97;
    if mixed < 0 {{
        distance - mixed
    }} else {{
        distance + mixed
    }}
}}

fn checksum(width: i32, height: i32, seed: i32) -> i32 {{
    let mut total = 0;
    let mut y = 0;
    while y < height {{
        let mut x = 0;
        while x < width {{
            total += cell_score(x, y, seed);
            x += 1;
        }}
        y += 1;
    }}
    total
}}

fn main() {{
    println!("{{}}", checksum({width}, {height}, {seed}));
}}
"""
    c = f"""#include <stdio.h>

static int cell_score(int x, int y, int seed) {{
    int distance = x > y ? x - y : y - x;
    int mixed = (x * 17 + y * 31 + seed * 13) % 97;
    if (mixed < 0) {{
        return distance - mixed;
    }}
    return distance + mixed;
}}

static int checksum(int width, int height, int seed) {{
    int total = 0;
    int y = 0;
    while (y < height) {{
        int x = 0;
        while (x < width) {{
            total += cell_score(x, y, seed);
            x += 1;
        }}
        y += 1;
    }}
    return total;
}}

int main(void) {{
    printf("%d\\n", checksum({width}, {height}, {seed}));
    return 0;
}}
"""
    cpp = c.replace("#include <stdio.h>", "#include <cstdio>").replace("printf", "std::printf")
    zig = f"""const c = @cImport({{
    @cInclude("stdio.h");
}});

fn cell_score(x: i32, y: i32, seed: i32) i32 {{
    const distance: i32 = if (x > y) x - y else y - x;
    const mixed: i32 = @mod(x * 17 + y * 31 + seed * 13, 97);
    if (mixed < 0) {{
        return distance - mixed;
    }}
    return distance + mixed;
}}

fn checksum(width: i32, height: i32, seed: i32) i32 {{
    var total: i32 = 0;
    var y: i32 = 0;
    while (y < height) : (y += 1) {{
        var x: i32 = 0;
        while (x < width) : (x += 1) {{
            total += cell_score(x, y, seed);
        }}
    }}
    return total;
}}

pub fn main() void {{
    _ = c.printf("%d\\n", checksum({width}, {height}, {seed}));
}}
"""
    lanius = f"""module app::main;

import std::io;

fn cell_score(x: i32, y: i32, seed: i32) -> i32 {{
    let distance: i32 = 0;
    if (x > y) {{
        distance = x - y;
    }} else {{
        distance = y - x;
    }}
    let mixed: i32 = (x * 17 + y * 31 + seed * 13) % 97;
    if (mixed < 0) {{
        return distance - mixed;
    }}
    return distance + mixed;
}}

fn checksum(width: i32, height: i32, seed: i32) -> i32 {{
    let total: i32 = 0;
    let y: i32 = 0;
    while (y < height) {{
        let x: i32 = 0;
        while (x < width) {{
            total += cell_score(x, y, seed);
            x += 1;
        }}
        y += 1;
    }}
    return total;
}}

fn main() -> i32 {{
    std::io::print_i32(checksum({width}, {height}, {seed}));
    return 0;
}}
"""
    return {"rust": rust, "c": c, "cpp": cpp, "zig": zig, "lanius": lanius}


def build_commands(repo: Path, out: Path) -> dict[str, dict[str, list[str]]]:
    try:
        artifact_dir = out.relative_to(repo)
    except ValueError:
        artifact_dir = out
    src = artifact_dir / "src"
    bin_dir = Path("target") / "lanius-benchmark-artifacts" / WORKLOAD["name"]
    return {
        "rust": {
            "compile": ["rustc", "-O", str(src / "grid_checksum.rs"), "-o", str(bin_dir / "grid_checksum_rust")],
            "run": [str(bin_dir / "grid_checksum_rust")],
        },
        "c": {
            "compile": ["gcc", "-O2", str(src / "grid_checksum.c"), "-o", str(bin_dir / "grid_checksum_c")],
            "run": [str(bin_dir / "grid_checksum_c")],
        },
        "cpp": {
            "compile": ["g++", "-O2", str(src / "grid_checksum.cpp"), "-o", str(bin_dir / "grid_checksum_cpp")],
            "run": [str(bin_dir / "grid_checksum_cpp")],
        },
        "zig": {
            "compile": ["zig", "build-exe", "-lc", "-O", "ReleaseFast", str(src / "grid_checksum.zig"), "-femit-bin=" + str(bin_dir / "grid_checksum_zig")],
            "run": [str(bin_dir / "grid_checksum_zig")],
        },
        "lanius": {
                "compile": [
                str(Path("target/debug/laniusc")),
                "--stdlib-root",
                str(Path("stdlib")),
                "--emit",
                "x86_64",
                "-o",
                str(bin_dir / "grid_checksum_lanius"),
                str(src / "grid_checksum.lani"),
            ],
            "run": [str(bin_dir / "grid_checksum_lanius")],
        },
    }


def measure_language(language: str, command: dict[str, list[str]], out_dir: Path, repo: Path) -> dict[str, str]:
    compile_ms = timed(command["compile"], repo)
    started = time.perf_counter()
    run = subprocess.run(command["run"], cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    run_ms = (time.perf_counter() - started) * 1000.0
    if run.returncode != 0:
        raise RuntimeError(f"{language} run failed: {run.stderr}")
    expected = WORKLOAD["expected_stdout"]
    if run.stdout != expected:
        raise RuntimeError(f"{language} stdout mismatch: {run.stdout!r} != {expected!r}")
    output_path = out_dir / f"{language}.stdout"
    output_path.write_text(run.stdout)
    return {
        "language": language,
        "status": "ok",
        "compile_ms": f"{compile_ms:.3f}",
        "run_ms": f"{run_ms:.3f}",
        "stdout_sha256": sha256_bytes(run.stdout.encode()),
        "source_sha256": sha256_file((out_dir.parent / "src" / source_file_name(language))),
    }


def timed(command: list[str], cwd: Path) -> float:
    started = time.perf_counter()
    run = subprocess.run(command, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    elapsed = (time.perf_counter() - started) * 1000.0
    if run.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(command)}\n{run.stderr}")
    return elapsed


def machine_info() -> dict[str, str]:
    return {
        "schema": "lanius.benchmark-machine.v1",
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "processor": platform.processor(),
        "python": platform.python_version(),
        "rustc": version_of(["rustc", "--version"]),
        "gcc": version_of(["gcc", "--version"]),
        "g++": version_of(["g++", "--version"]),
        "zig": version_of(["zig", "version"]),
        "laniusc": version_of([str(Path("target/debug/laniusc").resolve()), "--version"]),
    }


def version_of(command: list[str]) -> str:
    if shutil.which(command[0]) is None and not Path(command[0]).exists():
        return "missing"
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return run.stdout.splitlines()[0] if run.stdout else f"exit={run.returncode}"


def manifest(out: Path, results: list[dict[str, str]]) -> dict[str, object]:
    files = []
    for path in sorted(out.rglob("*")):
        if path.is_file() and path.name != "manifest.json" and "/bin/" not in str(path):
            files.append({"path": str(path.relative_to(out)), "sha256": sha256_file(path)})
    return {
        "schema": "lanius.benchmark-artifacts.v1",
        "workload": WORKLOAD["name"],
        "languages": LANGUAGES,
        "files": files,
        "result_status": {row["language"]: row["status"] for row in results},
    }


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def write_results(path: Path, rows: list[dict[str, str]]) -> None:
    fields = ["language", "status", "compile_ms", "run_ms", "stdout_sha256", "source_sha256"]
    lines = ["\t".join(fields)]
    for row in rows:
        lines.append("\t".join(str(row[field]) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
