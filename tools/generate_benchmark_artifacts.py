#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import platform
import select
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


def grid_checksum(width: int, height: int, seed: int) -> int:
    total = 0
    for y in range(height):
        for x in range(width):
            distance = x - y if x > y else y - x
            mixed = (x * 17 + y * 31 + seed * 13) % 97
            total += distance - mixed if mixed < 0 else distance + mixed
    return total


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
    parser.add_argument("--width", type=int, default=WORKLOAD["width"])
    parser.add_argument("--height", type=int, default=WORKLOAD["height"])
    parser.add_argument("--seed", type=int, default=WORKLOAD["seed"])
    parser.add_argument("--warmups", type=int, default=1)
    parser.add_argument("--iters", type=int, default=3)
    args = parser.parse_args()

    if args.width <= 0 or args.height <= 0:
        parser.error("--width and --height must be positive")
    if args.warmups < 0 or args.iters <= 0:
        parser.error("--warmups must be nonnegative and --iters must be positive")
    WORKLOAD.update(
        width=args.width,
        height=args.height,
        seed=args.seed,
        expected_stdout=f"{grid_checksum(args.width, args.height, args.seed)}\n",
        warmups=args.warmups,
        iters=args.iters,
    )

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
            results.append(
                measure_language(
                    language,
                    commands[language],
                    out_dir,
                    repo,
                    args.warmups,
                    args.iters,
                )
            )
    else:
        for language in LANGUAGES:
            results.append(
                {
                    "language": language,
                    "status": "not_measured",
                    "compile_ms": "",
                    "compile_avg_ms": "",
                    "run_ms": "",
                    "run_avg_ms": "",
                    "compile_mode": "",
                    "daemon_load_ms": "",
                    "daemon_compile_ms": "",
                    "daemon_write_ms": "",
                    "startup_ms": "",
                    "startup_resident_set_bytes": "",
                    "final_resident_set_bytes": "",
                    "peak_resident_set_bytes": "",
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


def build_commands(repo: Path, out: Path) -> dict[str, dict[str, object]]:
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
                str(Path("target/release/laniusc")),
                "--stdlib-root",
                str(Path("stdlib")),
                "--emit",
                "x86_64",
                "-o",
                str(bin_dir / "grid_checksum_lanius"),
                str(src / "grid_checksum.lani"),
            ],
            "daemon_start": [
                str(Path("target/release/laniusc")),
                "daemon",
                "--stdio",
                "--backend",
                "x86_64",
                "--stdlib-root",
                str(Path("stdlib")),
            ],
            "compile_request": {
                "id": "benchmark",
                "command": "compile",
                "emit": "x86_64",
                "input": str(src / "grid_checksum.lani"),
                "output": str(bin_dir / "grid_checksum_lanius"),
            },
            "run": [str(bin_dir / "grid_checksum_lanius")],
        },
    }


def measure_language(
    language: str,
    command: dict[str, object],
    out_dir: Path,
    repo: Path,
    warmups: int,
    iters: int,
) -> dict[str, str]:
    if language == "lanius":
        compile_samples, startup = measure_lanius_daemon(command, repo, warmups, iters)
        compile_mode = "daemon_job"
    else:
        for _ in range(warmups):
            timed(command["compile"], repo)
        compile_samples = [timed(command["compile"], repo) for _ in range(iters)]
        startup = {
            "startup_ms": "",
            "resident_set_bytes": "",
            "final_resident_set_bytes": "",
            "peak_resident_set_bytes": "",
            "load_ms": "",
            "compile_ms": "",
            "write_ms": "",
        }
        compile_mode = "process"

    expected = WORKLOAD["expected_stdout"]
    run_samples = []
    run_stdout = ""
    for _ in range(iters):
        started = time.perf_counter()
        run = subprocess.run(
            command["run"],
            cwd=repo,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        run_samples.append((time.perf_counter() - started) * 1000.0)
        if run.returncode != 0:
            raise RuntimeError(f"{language} run failed: {run.stderr}")
        if run.stdout != expected:
            raise RuntimeError(f"{language} stdout mismatch: {run.stdout!r} != {expected!r}")
        run_stdout = run.stdout
    output_path = out_dir / f"{language}.stdout"
    output_path.write_text(run_stdout)
    return {
        "language": language,
        "status": "ok",
        "compile_ms": f"{min(compile_samples):.3f}",
        "compile_avg_ms": f"{sum(compile_samples) / len(compile_samples):.3f}",
        "run_ms": f"{min(run_samples):.3f}",
        "run_avg_ms": f"{sum(run_samples) / len(run_samples):.3f}",
        "compile_mode": compile_mode,
        "daemon_load_ms": format_optional_number(startup.get("load_ms")),
        "daemon_compile_ms": format_optional_number(startup.get("compile_ms")),
        "daemon_write_ms": format_optional_number(startup.get("write_ms")),
        "startup_ms": format_optional_number(startup.get("startup_ms")),
        "startup_resident_set_bytes": format_optional_integer(startup.get("resident_set_bytes")),
        "final_resident_set_bytes": format_optional_integer(
            startup.get("final_resident_set_bytes")
        ),
        "peak_resident_set_bytes": format_optional_integer(
            startup.get("peak_resident_set_bytes")
        ),
        "stdout_sha256": sha256_bytes(run_stdout.encode()),
        "source_sha256": sha256_file((out_dir.parent / "src" / source_file_name(language))),
    }


def measure_lanius_daemon(
    command: dict[str, object],
    repo: Path,
    warmups: int,
    iters: int,
) -> tuple[list[float], dict[str, object]]:
    process = subprocess.Popen(
        command["daemon_start"],
        cwd=repo,
        text=True,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=1,
    )
    if process.stdin is None or process.stdout is None or process.stderr is None:
        raise RuntimeError("lanius daemon did not expose stdio pipes")
    try:
        ready = read_daemon_response(process, 60.0)
        if ready.get("event") != "ready":
            raise RuntimeError(f"lanius daemon did not become ready: {ready}")
        samples = []
        load_samples = []
        compiler_samples = []
        write_samples = []
        resident_samples = [int(ready["resident_set_bytes"])]
        for iteration in range(warmups + iters):
            request = dict(command["compile_request"])
            request["id"] = f"benchmark-{iteration}"
            process.stdin.write(json.dumps(request, sort_keys=True) + "\n")
            process.stdin.flush()
            response = read_daemon_response(process, 60.0)
            if not response.get("ok"):
                raise RuntimeError(f"lanius daemon compile failed: {response}")
            resident_samples.append(int(response["resident_set_bytes"]))
            if iteration >= warmups:
                samples.append(float(response["elapsed_ms"]))
                load_samples.append(float(response["load_ms"]))
                compiler_samples.append(float(response["compile_ms"]))
                write_samples.append(float(response["write_ms"]))
        process.stdin.write(json.dumps({"id": "shutdown", "command": "shutdown"}) + "\n")
        process.stdin.flush()
        shutdown = read_daemon_response(process, 10.0)
        if shutdown.get("event") != "shutdown":
            raise RuntimeError(f"lanius daemon did not acknowledge shutdown: {shutdown}")
        process.wait(timeout=10.0)
        daemon_metrics = dict(ready)
        daemon_metrics["final_resident_set_bytes"] = resident_samples[-1]
        daemon_metrics["peak_resident_set_bytes"] = max(resident_samples)
        daemon_metrics["load_ms"] = min(load_samples)
        daemon_metrics["compile_ms"] = min(compiler_samples)
        daemon_metrics["write_ms"] = min(write_samples)
        return samples, daemon_metrics
    except Exception:
        process.kill()
        process.wait(timeout=10.0)
        stderr = process.stderr.read()
        if stderr:
            raise RuntimeError(f"lanius daemon failed\nstderr:\n{stderr}")
        raise


def read_daemon_response(process: subprocess.Popen[str], timeout: float) -> dict[str, object]:
    if process.stdout is None:
        raise RuntimeError("lanius daemon stdout is unavailable")
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if not readable:
        raise RuntimeError(f"lanius daemon response timed out after {timeout:.0f}s")
    line = process.stdout.readline()
    if not line:
        code = process.poll()
        raise RuntimeError(f"lanius daemon exited before responding (status={code})")
    return json.loads(line)


def format_optional_number(value: object) -> str:
    return "" if value is None or value == "" else f"{float(value):.3f}"


def format_optional_integer(value: object) -> str:
    return "" if value is None or value == "" else str(int(value))


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
        "cpu_model": proc_field("/proc/cpuinfo", "model name"),
        "logical_cpus": str(os.cpu_count() or "missing"),
        "memory_total_bytes": proc_kib_field_bytes("/proc/meminfo", "MemTotal"),
        "gpu": version_of(
            [
                "nvidia-smi",
                "--query-gpu=name,driver_version,memory.total",
                "--format=csv,noheader,nounits",
            ]
        ),
        "gpu_measurement_state": output_of(
            [
                "nvidia-smi",
                "--query-gpu=utilization.gpu,utilization.memory,memory.used,temperature.gpu,pstate",
                "--format=csv,noheader,nounits",
            ]
        ),
        "gpu_compute_processes": output_of(
            [
                "nvidia-smi",
                "--query-compute-apps=pid,process_name,used_gpu_memory",
                "--format=csv,noheader,nounits",
            ]
        ),
        "lanius_profile": "release",
        "python": platform.python_version(),
        "rustc": version_of(["rustc", "--version"]),
        "gcc": version_of(["gcc", "--version"]),
        "g++": version_of(["g++", "--version"]),
        "zig": version_of(["zig", "version"]),
        "laniusc": version_of([str(Path("target/release/laniusc").resolve()), "--version"]),
    }


def proc_field(path: str, key: str) -> str:
    try:
        for line in Path(path).read_text().splitlines():
            name, separator, value = line.partition(":")
            if separator and name.strip() == key:
                return value.strip() or "missing"
    except OSError:
        pass
    return "missing"


def proc_kib_field_bytes(path: str, key: str) -> str:
    value = proc_field(path, key)
    parts = value.split()
    if not parts or not parts[0].isdigit():
        return "missing"
    return str(int(parts[0]) * 1024)


def version_of(command: list[str]) -> str:
    if shutil.which(command[0]) is None and not Path(command[0]).exists():
        return "missing"
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return run.stdout.splitlines()[0] if run.stdout else f"exit={run.returncode}"


def output_of(command: list[str]) -> str:
    if shutil.which(command[0]) is None and not Path(command[0]).exists():
        return "missing"
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    output = run.stdout.strip()
    return output if output else f"exit={run.returncode}; no output"


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
    fields = [
        "language",
        "status",
        "compile_ms",
        "compile_avg_ms",
        "run_ms",
        "run_avg_ms",
        "compile_mode",
        "daemon_load_ms",
        "daemon_compile_ms",
        "daemon_write_ms",
        "startup_ms",
        "startup_resident_set_bytes",
        "final_resident_set_bytes",
        "peak_resident_set_bytes",
        "stdout_sha256",
        "source_sha256",
    ]
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
