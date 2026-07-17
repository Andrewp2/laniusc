#!/usr/bin/env python3
"""Generate, measure, execute, and record the cross-language scaling matrix."""

import argparse
import hashlib
import json
import os
import platform
import random
import select
import shutil
import statistics
import subprocess
import time
from pathlib import Path


CPU_LANGUAGES = ("c", "cpp", "rust", "zig")
LANES = ("o0", "optimized")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="target/compile-scaling-matrix")
    parser.add_argument("--size", type=int, default=1_101_000)
    parser.add_argument("--seeds", default="20,21,22,23,24,25,26")
    parser.add_argument("--warm-seed", type=int, default=19)
    parser.add_argument("--order-seed", type=int, default=0x1A91_05)
    args = parser.parse_args()
    seeds = [int(value) for value in args.seeds.split(",")]
    if args.size <= 0 or not seeds or len(set(seeds)) != len(seeds):
        parser.error("--size must be positive and --seeds must be unique")
    if args.warm_seed in seeds:
        parser.error("--warm-seed must not be a measured seed")

    repo = Path(__file__).resolve().parents[1]
    out = resolve(repo, args.out)
    source_root = out / "sources"
    bin_root = out / "bin"
    source_root.mkdir(parents=True, exist_ok=True)
    bin_root.mkdir(parents=True, exist_ok=True)
    expected, source_variants = generate_sources(
        repo, source_root, args.size, [args.warm_seed, *seeds]
    )

    command_templates = compiler_commands(repo)
    provenance = collect_provenance(repo, command_templates)
    tasks = [
        (language, lane, seed)
        for seed in seeds
        for lane in LANES
        for language in CPU_LANGUAGES
    ]
    random.Random(args.order_seed).shuffle(tasks)
    lanius_seeds = list(seeds)
    random.Random(args.order_seed ^ 0x4C41_4E49).shuffle(lanius_seeds)

    daemon, ready = start_daemon(repo)
    samples = []
    try:
        warm_output = bin_root / f"lanius-warm-{args.warm_seed}"
        compile_lanius(
            daemon,
            source_path(source_root, args.warm_seed, "lanius"),
            warm_output,
            f"warm-{args.warm_seed}",
        )
        validate_executable(warm_output, expected[args.warm_seed])
        for order, (language, lane, seed) in enumerate(tasks):
            output = bin_root / f"{language}-{lane}-{seed}"
            source = source_path(source_root, seed, language)
            command = materialize(command_templates[lane][language], source, output)
            sample = compile_process(command, repo)
            stdout = validate_executable(output, expected[seed])
            samples.append(
                {
                    "order": order,
                    "phase": "cpu_randomized",
                    "language": language,
                    "lane": lane,
                    "seed": seed,
                    "source_bytes": source.stat().st_size,
                    "source_sha256": sha256_file(source),
                    "output_sha256": sha256_file(output),
                    "stdout_sha256": sha256_bytes(stdout.encode()),
                    **sample,
                }
            )
        for seed in seeds:
            capacity_output = bin_root / f"lanius-capacity-warm-{seed}"
            compile_lanius(
                daemon,
                source_path(source_root, seed, "lanius"),
                capacity_output,
                f"capacity-warm-{seed}",
            )
            validate_executable(capacity_output, expected[seed])
        for seed in lanius_seeds:
            output = bin_root / f"lanius-hot-daemon-{seed}"
            source = source_path(source_root, seed, "lanius")
            sample = compile_lanius(daemon, source, output, f"measure-{seed}")
            stdout = validate_executable(output, expected[seed])
            samples.append({
                "order": len(samples),
                "phase": "lanius_hot_daemon",
                "language": "lanius",
                "lane": "hot_daemon",
                "seed": seed,
                "source_bytes": source.stat().st_size,
                "source_sha256": sha256_file(source),
                "output_sha256": sha256_file(output),
                "stdout_sha256": sha256_bytes(stdout.encode()),
                **sample,
            })
    finally:
        stop_daemon(daemon)

    summary = summarize(samples)
    write_json(out / "config.json", {
        "schema": "lanius.compile-scaling-matrix-config.v1",
        "size": args.size,
        "seeds": seeds,
        "warm_seed": args.warm_seed,
        "order_seed": args.order_seed,
        "timing_policy": "wall clock from request/process start through artifact write",
        "sample_policy": "all samples retained; median is primary, min/max/MAD are reported",
        "validation_policy": "every artifact must execute with exact model-derived stdout",
        "daemon_warmup_policy": "one pipeline warmup seed; after CPU trials, one unmeasured capacity warmup per measured seed immediately precedes a contiguous randomized hot-daemon batch",
        "debug_info": "disabled in every CPU lane",
    })
    write_json(out / "commands.json", command_templates)
    write_json(out / "source_manifest.json", {
        "schema": "lanius.compile-scaling-source-manifest.v2",
        "generator_path": "tools/generate_compile_scaling_sources.py",
        "model_path": "tools/compile_workload_model.py",
        "variants": source_variants,
    })
    outputs = out / "outputs"
    outputs.mkdir(exist_ok=True)
    for seed in seeds:
        (outputs / f"seed-{seed}.stdout").write_text(expected[seed])
    write_json(out / "machine_info.json", machine_info(ready))
    write_json(out / "provenance.json", provenance)
    write_json(out / "samples.json", {"schema": "lanius.compile-scaling-samples.v1", "samples": samples})
    write_json(out / "summary.json", {"schema": "lanius.compile-scaling-summary.v1", "rows": summary})
    write_tsv(out / "results.tsv", samples)
    write_json(out / "manifest.json", manifest(out))
    return 0


def generate_sources(repo: Path, out: Path, size: int, seeds: list[int]):
    expected = {}
    variants = {}
    for seed in seeds:
        target = out / f"seed-{seed}"
        run = subprocess.run(
            ["python3", "tools/generate_compile_scaling_sources.py", "--out", str(target),
             "--sizes", str(size), "--seed", str(seed)],
            cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if run.returncode != 0:
            raise RuntimeError(f"source generation failed for seed {seed}: {run.stderr}")
        document = json.loads((target / "manifest.json").read_text())
        source_set = document["source_sets"][0]
        expected[seed] = source_set["expected_stdout"]
        variants[str(seed)] = source_set
    return expected, variants


def compiler_commands(repo: Path) -> dict:
    return {
        "schema": "lanius.compile-scaling-command-templates.v1",
        "o0": {
            "c": ["gcc", "-O0", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O0", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-C", "opt-level=0", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "Debug", "-fstrip", "{source}", "-femit-bin={output}"],
        },
        "optimized": {
            "c": ["gcc", "-O2", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O2", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-C", "opt-level=3", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "ReleaseFast", "-fstrip", "{source}", "-femit-bin={output}"],
        },
        "lanius_daemon": ["target/release/laniusc", "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", "stdlib"],
    }


def materialize(template: list[str], source: Path, output: Path) -> list[str]:
    return [part.format(source=source, output=output) for part in template]


def compile_process(command: list[str], repo: Path) -> dict:
    started = time.perf_counter_ns()
    run = subprocess.run(command, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if run.returncode != 0:
        raise RuntimeError(f"compile failed: {command!r}\n{run.stderr}")
    return {"wall_ms": elapsed, "daemon_load_ms": None, "daemon_compile_ms": None, "daemon_write_ms": None}


def start_daemon(repo: Path):
    command = compiler_commands(repo)["lanius_daemon"]
    process = subprocess.Popen(command, cwd=repo, text=True, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=1)
    ready = read_json_line(process, 900.0)
    if ready.get("event") != "ready":
        raise RuntimeError(f"daemon did not become ready: {ready}")
    return process, ready


def compile_lanius(process, source: Path, output: Path, request_id: str) -> dict:
    request = {"id": request_id, "command": "compile", "emit": "x86_64", "input": str(source), "output": str(output)}
    assert process.stdin is not None
    started = time.perf_counter_ns()
    process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
    process.stdin.flush()
    response = read_json_line(process, 180.0)
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if response.get("id") != request_id or response.get("ok") is not True:
        raise RuntimeError(f"daemon compile failed: {response}")
    return {"wall_ms": elapsed, "daemon_load_ms": response.get("load_ms"), "daemon_compile_ms": response.get("compile_ms"), "daemon_write_ms": response.get("write_ms")}


def stop_daemon(process) -> None:
    if process.poll() is not None:
        return
    assert process.stdin is not None
    process.stdin.write('{"id":"shutdown","command":"shutdown"}\n')
    process.stdin.flush()
    try:
        read_json_line(process, 10.0)
        process.wait(timeout=10.0)
    except Exception:
        process.kill()
        process.wait()


def read_json_line(process, timeout: float) -> dict:
    assert process.stdout is not None
    readable, _, _ = select.select([process.stdout], [], [], timeout)
    if not readable:
        raise TimeoutError(f"daemon response timed out after {timeout}s")
    line = process.stdout.readline()
    if not line:
        stderr = process.stderr.read() if process.stderr else ""
        raise RuntimeError(f"daemon exited early: {process.poll()}\n{stderr}")
    return json.loads(line)


def validate_executable(path: Path, expected: str) -> str:
    run = subprocess.run([str(path)], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30.0)
    if run.returncode != 0 or run.stdout != expected:
        raise RuntimeError(f"artifact validation failed for {path}: status={run.returncode}, stdout={run.stdout!r}, expected={expected!r}, stderr={run.stderr}")
    return run.stdout


def summarize(samples: list[dict]) -> list[dict]:
    groups = {}
    for sample in samples:
        groups.setdefault((sample["language"], sample["lane"]), []).append(sample["wall_ms"])
    rows = []
    for (language, lane), values in sorted(groups.items()):
        median = statistics.median(values)
        rows.append({"language": language, "lane": lane, "samples": len(values), "median_ms": median, "min_ms": min(values), "max_ms": max(values), "mad_ms": statistics.median(abs(value - median) for value in values)})
    lanius = next(row["median_ms"] for row in rows if row["language"] == "lanius")
    for row in rows:
        row["speedup_vs_lanius"] = row["median_ms"] / lanius
    return rows


def collect_provenance(repo: Path, commands: dict) -> dict:
    tools = {part[0] for lane in LANES for part in commands[lane].values()}
    tools.add(str(repo / "target/release/laniusc"))
    rows = {}
    for tool in sorted(tools):
        path = Path(shutil.which(tool) or tool).resolve()
        rows[tool] = {"path": str(path), "sha256": sha256_file(path), "version": subprocess.run([str(path), "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT).stdout.splitlines()[0]}
    return {"schema": "lanius.compile-scaling-provenance.v1", "tools": rows, "runner_sha256": sha256_file(repo / "tools/run_compile_scaling_matrix.py"), "generator_sha256": sha256_file(repo / "tools/generate_compile_scaling_sources.py"), "model_sha256": sha256_file(repo / "tools/compile_workload_model.py")}


def machine_info(ready: dict) -> dict:
    return {"schema": "lanius.compile-scaling-machine.v1", "system": platform.platform(), "cpu": platform.processor(), "logical_cpus": os.cpu_count(), "gpu": command_output(["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader,nounits"]), "daemon_ready": ready}


def command_output(command: list[str]) -> str:
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return run.stdout.strip()


def source_path(root: Path, seed: int, language: str) -> Path:
    suffix = {"c": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "lanius": "lani"}[language]
    size_dirs = [path for path in (root / f"seed-{seed}").iterdir() if path.is_dir()]
    if len(size_dirs) != 1:
        raise RuntimeError(f"expected one size directory for seed {seed}")
    return size_dirs[0] / f"scaling.{suffix}"


def write_tsv(path: Path, samples: list[dict]) -> None:
    fields = ("order", "phase", "language", "lane", "seed", "source_bytes", "wall_ms", "daemon_load_ms", "daemon_compile_ms", "daemon_write_ms", "source_sha256", "output_sha256", "stdout_sha256")
    lines = ["\t".join(fields)]
    for row in samples:
        lines.append("\t".join("" if row[field] is None else (f"{row[field]:.3f}" if isinstance(row[field], float) else str(row[field])) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def manifest(out: Path) -> dict:
    files = [{"path": str(path.relative_to(out)), "bytes": path.stat().st_size, "sha256": sha256_file(path)} for path in sorted(out.rglob("*")) if path.is_file() and "bin" not in path.relative_to(out).parts and "sources" not in path.relative_to(out).parts and path.name != "manifest.json"]
    return {"schema": "lanius.compile-scaling-matrix-manifest.v1", "files": files}


def resolve(repo: Path, raw: str) -> Path:
    path = Path(raw)
    return path if path.is_absolute() else repo / path


def write_json(path: Path, value) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


if __name__ == "__main__":
    raise SystemExit(main())
