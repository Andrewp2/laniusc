#!/usr/bin/env python3
"""Measure the controlled cross-language synthetic compiler stress matrix."""

import argparse
import hashlib
import json
import os
import platform
import random
import re
import select
import shutil
import statistics
import subprocess
import tempfile
import time
from pathlib import Path

from compiler_stress_model import WORKLOAD_PROFILES


EXTERNAL_COMPILERS = ("c", "cpp", "rust", "zig", "tcc", "pareas")
LANES = ("o0", "optimized")


def parse_external_compilers(value: str) -> tuple[str, ...]:
    languages = tuple(part.strip() for part in value.split(",") if part.strip())
    unknown = set(languages) - set(EXTERNAL_COMPILERS)
    if not languages or unknown:
        expected = ",".join(EXTERNAL_COMPILERS)
        raise argparse.ArgumentTypeError(
            f"external compilers must be a non-empty subset of {expected}; "
            f"unknown: {sorted(unknown)}"
        )
    return languages


def lanes_for(language: str) -> tuple[str, ...]:
    if language == "tcc":
        return ("default",)
    if language == "pareas":
        return ("cuda",)
    return LANES


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="target/compiler-stress-matrix")
    parser.add_argument("--size", type=int, default=1_000_000)
    parser.add_argument("--seeds", default=",".join(str(seed) for seed in range(20, 40)))
    parser.add_argument("--warm-seed", type=int, default=19)
    parser.add_argument("--order-seed", type=int, default=0x1A91_05)
    parser.add_argument("--rust-frontend-threads", type=int, default=16)
    parser.add_argument(
        "--external-compilers",
        type=parse_external_compilers,
        default=EXTERNAL_COMPILERS,
    )
    parser.add_argument("--tcc", default="tcc", help="TCC executable")
    parser.add_argument(
        "--pareas",
        default=str(Path.home() / "code/pareas/build-laniusc-cuda-futhark025/pareas"),
        help="Pareas CUDA executable",
    )
    parser.add_argument(
        "--tcc-runtime-path",
        type=Path,
        help="optional TCC runtime directory for an extracted installation",
    )
    parser.add_argument(
        "--profile",
        choices=tuple(WORKLOAD_PROFILES),
        default="pareas-common-subset",
    )
    args = parser.parse_args()
    seeds = [int(value) for value in args.seeds.split(",")]
    if args.size <= 0 or not seeds or len(set(seeds)) != len(seeds):
        parser.error("--size must be positive and --seeds must be unique")
    if args.warm_seed in seeds:
        parser.error("--warm-seed must not be a measured seed")
    if args.rust_frontend_threads <= 0:
        parser.error("--rust-frontend-threads must be positive")
    if "pareas" in args.external_compilers and args.profile != "pareas-common-subset":
        parser.error("Pareas requires --profile pareas-common-subset")

    repo = Path(__file__).resolve().parents[1]
    out = resolve(repo, args.out)
    source_root = out / "sources"
    bin_root = out / "bin"
    source_root.mkdir(parents=True, exist_ok=True)
    bin_root.mkdir(parents=True, exist_ok=True)
    expected, source_variants = generate_sources(
        repo, source_root, args.size, [args.warm_seed, *seeds], args.profile
    )

    command_templates = compiler_commands(
        repo,
        args.rust_frontend_threads,
        args.tcc,
        args.tcc_runtime_path,
        args.pareas,
    )
    provenance = collect_provenance(repo, command_templates, args.external_compilers)
    tasks = [
        (language, lane, seed)
        for seed in seeds
        for language in args.external_compilers
        for lane in lanes_for(language)
    ]
    random.Random(args.order_seed).shuffle(tasks)
    lanius_seeds = list(seeds)
    random.Random(args.order_seed ^ 0x4C41_4E49).shuffle(lanius_seeds)

    pareas_environment, pareas_environment_owner = (
        prepare_pareas_environment()
        if "pareas" in args.external_compilers
        else (None, None)
    )
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
            sample = compile_process(
                command,
                repo,
                environment=pareas_environment if language == "pareas" else None,
                parse_pareas_profile=language == "pareas",
            )
            if language == "pareas":
                validate_pareas_artifact(output)
                stdout = None
            else:
                stdout = validate_executable(output, expected[seed])
            samples.append(
                {
                    "order": order,
                    "phase": "external_randomized",
                    "language": language,
                    "lane": lane,
                    "seed": seed,
                    "source_bytes": source.stat().st_size,
                    "source_sha256": sha256_file(source),
                    "output_sha256": sha256_file(output),
                    "stdout_sha256": sha256_bytes(stdout.encode()) if stdout is not None else None,
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
        # End capacity preparation on a source that is not part of the measured
        # set. Otherwise the first randomized sample can accidentally measure
        # an immediate same-project recompile while every later sample switches
        # projects and rebuilds shape-dependent job resources.
        variable_project_primer = bin_root / f"lanius-variable-primer-{args.warm_seed}"
        compile_lanius(
            daemon,
            source_path(source_root, args.warm_seed, "lanius"),
            variable_project_primer,
            f"variable-primer-{args.warm_seed}",
        )
        validate_executable(variable_project_primer, expected[args.warm_seed])
        for seed in lanius_seeds:
            output = bin_root / f"lanius-variable-project-{seed}"
            source = source_path(source_root, seed, "lanius")
            sample = compile_lanius(daemon, source, output, f"measure-{seed}")
            stdout = validate_executable(output, expected[seed])
            samples.append({
                "order": len(samples),
                "phase": "lanius_hot_daemon_variable_project",
                "language": "lanius",
                "lane": "hot_daemon_variable_project",
                "seed": seed,
                "source_bytes": source.stat().st_size,
                "source_sha256": sha256_file(source),
                "output_sha256": sha256_file(output),
                "stdout_sha256": sha256_bytes(stdout.encode()),
                **sample,
            })
    finally:
        stop_daemon(daemon)
        if pareas_environment_owner is not None:
            pareas_environment_owner.cleanup()

    summary = summarize(samples)
    write_json(out / "config.json", {
        "schema": "lanius.compiler-stress-matrix-config.v1",
        "classification": "synthetic_stress",
        "representative_workload": False,
        "size": args.size,
        "seeds": seeds,
        "warm_seed": args.warm_seed,
        "order_seed": args.order_seed,
        "external_compilers": args.external_compilers,
        "workload_profile": args.profile,
        "timing_policy": "wall clock from request/process start through artifact write; Pareas compiler_ms is its synchronized frontend plus backend profile and excludes context initialization",
        "sample_policy": "all samples retained; median is primary, min/max/MAD are reported",
        "validation_policy": "C, C++, Rust, Zig, TCC, and Lanius artifacts execute with exact model-derived stdout; Pareas emits raw RISC-V bytes, which must be nonempty, instruction-aligned, and deterministic",
        "daemon_warmup_policy": "one pipeline warmup seed; after CPU trials, one unmeasured capacity warmup per measured seed, then a different-source primer before the contiguous randomized variable-project hot-daemon batch",
        "debug_info": "disabled in every applicable external compiler lane",
    })
    write_json(out / "commands.json", command_templates)
    write_json(out / "source_manifest.json", {
        "schema": "lanius.compiler-stress-source-manifest.v1",
        "generator_path": "tools/generate_compiler_stress.py",
        "model_path": "tools/compiler_stress_model.py",
        "workload_classification": "synthetic_stress",
        "representative_workload": False,
        "workload_profile": args.profile,
        "variants": source_variants,
    })
    outputs = out / "outputs"
    outputs.mkdir(exist_ok=True)
    for seed in seeds:
        (outputs / f"seed-{seed}.stdout").write_text(expected[seed])
    write_json(out / "machine_info.json", machine_info(ready))
    write_json(out / "provenance.json", provenance)
    write_json(out / "samples.json", {"schema": "lanius.compiler-stress-samples.v1", "samples": samples})
    write_json(out / "summary.json", {"schema": "lanius.compiler-stress-summary.v1", "rows": summary})
    write_tsv(out / "results.tsv", samples)
    write_json(out / "manifest.json", manifest(out))
    return 0


def generate_sources(
    repo: Path, out: Path, size: int, seeds: list[int], profile: str
):
    expected = {}
    variants = {}
    for seed in seeds:
        target = out / f"seed-{seed}"
        run = subprocess.run(
            ["python3", "tools/generate_compiler_stress.py", "--out", str(target),
             "--layout", "comparative-single-file", "--sizes", str(size),
             "--seed", str(seed), "--profile", profile],
            cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        if run.returncode != 0:
            raise RuntimeError(f"source generation failed for seed {seed}: {run.stderr}")
        document = json.loads((target / "manifest.json").read_text())
        source_set = document["source_sets"][0]
        expected[seed] = source_set["expected_stdout"]
        variants[str(seed)] = source_set
    return expected, variants


def compiler_commands(
    repo: Path,
    rust_frontend_threads: int = 16,
    tcc: str = "tcc",
    tcc_runtime_path: Path | None = None,
    pareas: str | None = None,
) -> dict:
    tcc_command = [tcc]
    if tcc_runtime_path is not None:
        tcc_command.append(f"-B{tcc_runtime_path}")
    pareas = pareas or str(
        Path.home() / "code/pareas/build-laniusc-cuda-futhark025/pareas"
    )
    return {
        "schema": "lanius.compiler-stress-command-templates.v1",
        "o0": {
            "c": ["gcc", "-O0", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O0", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-Awarnings", f"-Zthreads={rust_frontend_threads}", "-C", "opt-level=0", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "Debug", "-fstrip", "{source}", "-femit-bin={output}"],
        },
        "optimized": {
            "c": ["gcc", "-O2", "-g0", "{source}", "-o", "{output}"],
            "cpp": ["g++", "-O2", "-g0", "{source}", "-o", "{output}"],
            "rust": ["rustc", "-Awarnings", f"-Zthreads={rust_frontend_threads}", "-C", "opt-level=3", "-C", "debuginfo=0", "-C", "strip=debuginfo", "{source}", "-o", "{output}"],
            "zig": ["zig", "build-exe", "-lc", "-O", "ReleaseFast", "-fstrip", "{source}", "-femit-bin={output}"],
        },
        "default": {
            "tcc": [*tcc_command, "-std=c11", "{source}", "-o", "{output}"],
        },
        "cuda": {
            "pareas": [pareas, "-p", "1", "{source}", "-o", "{output}"],
        },
        "lanius_daemon": ["target/release/laniusc", "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", "stdlib"],
    }


def materialize(template: list[str], source: Path, output: Path) -> list[str]:
    return [part.format(source=source, output=output) for part in template]


def compile_process(
    command: list[str],
    repo: Path,
    environment: dict[str, str] | None = None,
    parse_pareas_profile: bool = False,
) -> dict:
    started = time.perf_counter_ns()
    run = subprocess.run(
        command,
        cwd=repo,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    elapsed = (time.perf_counter_ns() - started) / 1_000_000.0
    if run.returncode != 0:
        raise RuntimeError(f"compile failed: {command!r}\n{run.stderr}")
    compiler_ms = None
    context_init_ms = None
    if parse_pareas_profile:
        profile = parse_pareas_timings(run.stdout + "\n" + run.stderr)
        compiler_ms = profile["frontend_ms"] + profile["backend_ms"]
        context_init_ms = profile["context_init_ms"]
    return {
        "wall_ms": elapsed,
        "compiler_ms": compiler_ms,
        "context_init_ms": context_init_ms,
        "daemon_load_ms": None,
        "daemon_compile_ms": None,
        "daemon_write_ms": None,
    }


def parse_pareas_timings(output: str) -> dict[str, float]:
    timings = {
        match.group(1).replace(" ", "_") + "_ms": int(match.group(2)) / 1000.0
        for match in re.finditer(
            r"^(context init|frontend|backend):\s*([0-9]+)(?:µs|us)$",
            output,
            re.MULTILINE,
        )
    }
    required = {"context_init_ms", "frontend_ms", "backend_ms"}
    if timings.keys() != required:
        raise RuntimeError(
            f"Pareas profile did not contain exactly {sorted(required)}: {output!r}"
        )
    return timings


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
    return {"wall_ms": elapsed, "compiler_ms": response.get("compile_ms"), "context_init_ms": None, "daemon_load_ms": response.get("load_ms"), "daemon_compile_ms": response.get("compile_ms"), "daemon_write_ms": response.get("write_ms")}


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


def validate_pareas_artifact(path: Path) -> None:
    size = path.stat().st_size
    if size == 0 or size % 4 != 0:
        raise RuntimeError(
            f"Pareas RISC-V artifact must contain whole 32-bit instructions: {path} has {size} bytes"
        )


def summarize(samples: list[dict]) -> list[dict]:
    groups = {}
    for sample in samples:
        groups.setdefault((sample["language"], sample["lane"]), []).append(sample)
    rows = []
    for (language, lane), group in sorted(groups.items()):
        values = [sample["wall_ms"] for sample in group]
        median = statistics.median(values)
        compiler_values = [
            sample["compiler_ms"]
            for sample in group
            if sample.get("compiler_ms") is not None
        ]
        compiler_median = statistics.median(compiler_values) if compiler_values else None
        rows.append({
            "language": language,
            "lane": lane,
            "samples": len(values),
            "median_ms": median,
            "min_ms": min(values),
            "max_ms": max(values),
            "mad_ms": statistics.median(abs(value - median) for value in values),
            "compiler_median_ms": compiler_median,
            "compiler_mad_ms": (
                statistics.median(abs(value - compiler_median) for value in compiler_values)
                if compiler_values
                else None
            ),
        })
    lanius = next(row["median_ms"] for row in rows if row["language"] == "lanius")
    lanius_compiler = next(
        row["compiler_median_ms"] for row in rows if row["language"] == "lanius"
    )
    for row in rows:
        row["speedup_vs_lanius"] = row["median_ms"] / lanius
        row["compiler_speedup_vs_lanius"] = (
            row["compiler_median_ms"] / lanius_compiler
            if row["compiler_median_ms"] is not None and lanius_compiler is not None
            else None
        )
    return rows


def collect_provenance(
    repo: Path,
    commands: dict,
    external_compilers: tuple[str, ...] = EXTERNAL_COMPILERS,
) -> dict:
    tools = {
        commands[lane][language][0]: language
        for language in external_compilers
        for lane in lanes_for(language)
    }
    tools[str(repo / "target/release/laniusc")] = "lanius"
    rows = {}
    for tool, language in sorted(tools.items()):
        path = Path(shutil.which(tool) or tool).resolve()
        rows[tool] = {
            "path": str(path),
            "sha256": sha256_file(path),
            "version": tool_version(path, language),
        }
    return {"schema": "lanius.compiler-stress-provenance.v1", "tools": rows, "runner_sha256": sha256_file(repo / "tools/run_compiler_stress_matrix.py"), "generator_sha256": sha256_file(repo / "tools/generate_compiler_stress.py"), "model_sha256": sha256_file(repo / "tools/compiler_stress_model.py")}


def machine_info(ready: dict) -> dict:
    return {"schema": "lanius.compiler-stress-machine.v1", "system": platform.platform(), "cpu": platform.processor(), "logical_cpus": os.cpu_count(), "gpu": command_output(["nvidia-smi", "--query-gpu=name,driver_version,memory.total", "--format=csv,noheader,nounits"]), "daemon_ready": ready}


def command_output(command: list[str]) -> str:
    run = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return run.stdout.strip()


def tool_version(path: Path, language: str) -> str:
    if language == "pareas":
        for parent in path.parents:
            if (parent / ".git").exists():
                commit = command_output(["git", "-C", str(parent), "rev-parse", "HEAD"])
                return f"git {commit}"
        return "Pareas CLI has no version flag; executable hash recorded"
    lines = subprocess.run(
        [str(path), "--version"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout.splitlines()
    return lines[0] if lines else "no version output"


def prepare_pareas_environment():
    environment = os.environ.copy()
    cuda_home = environment.get("CUDA_HOME")
    if cuda_home and (Path(cuda_home) / "include/cuda_runtime.h").exists():
        return environment, None

    try:
        import nvidia.cuda_nvcc
        import nvidia.cuda_nvrtc
        import nvidia.cuda_runtime
    except ImportError as error:
        raise RuntimeError(
            "Pareas needs CUDA_HOME or the nvidia-cuda-runtime, nvidia-cuda-nvrtc, and nvidia-cuda-nvcc Python packages"
        ) from error

    runtime = Path(next(iter(nvidia.cuda_runtime.__path__)))
    nvrtc = Path(next(iter(nvidia.cuda_nvrtc.__path__)))
    nvcc = Path(next(iter(nvidia.cuda_nvcc.__path__)))
    owner = tempfile.TemporaryDirectory(prefix="lanius-pareas-cuda-")
    cuda_root = Path(owner.name)
    include = cuda_root / "include"
    include.mkdir()
    for source in (runtime / "include").iterdir():
        (include / source.name).symlink_to(source, target_is_directory=source.is_dir())
    (include / "crt").symlink_to(nvcc / "include/crt", target_is_directory=True)
    environment["CUDA_HOME"] = str(cuda_root)
    library_paths = [str(runtime / "lib"), str(nvrtc / "lib")]
    if environment.get("LD_LIBRARY_PATH"):
        library_paths.append(environment["LD_LIBRARY_PATH"])
    environment["LD_LIBRARY_PATH"] = os.pathsep.join(library_paths)
    return environment, owner


def source_path(root: Path, seed: int, language: str) -> Path:
    suffix = {"c": "c", "tcc": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "lanius": "lani", "pareas": "par"}[language]
    size_dirs = [path for path in (root / f"seed-{seed}").iterdir() if path.is_dir()]
    if len(size_dirs) != 1:
        raise RuntimeError(f"expected one size directory for seed {seed}")
    return size_dirs[0] / f"scaling.{suffix}"


def write_tsv(path: Path, samples: list[dict]) -> None:
    fields = ("order", "phase", "language", "lane", "seed", "source_bytes", "wall_ms", "compiler_ms", "context_init_ms", "daemon_load_ms", "daemon_compile_ms", "daemon_write_ms", "source_sha256", "output_sha256", "stdout_sha256")
    lines = ["\t".join(fields)]
    for row in samples:
        lines.append("\t".join("" if row[field] is None else (f"{row[field]:.3f}" if isinstance(row[field], float) else str(row[field])) for field in fields))
    path.write_text("\n".join(lines) + "\n")


def manifest(out: Path) -> dict:
    files = [{"path": str(path.relative_to(out)), "bytes": path.stat().st_size, "sha256": sha256_file(path)} for path in sorted(out.rglob("*")) if path.is_file() and "bin" not in path.relative_to(out).parts and "sources" not in path.relative_to(out).parts and path.name != "manifest.json"]
    return {"schema": "lanius.compiler-stress-matrix-manifest.v1", "files": files}


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
