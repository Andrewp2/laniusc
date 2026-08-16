#!/usr/bin/env python3
"""Run, validate, catalog, and view canonical Lanius performance results."""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import select
import shutil
import socketserver
import subprocess
import sys
import time
from pathlib import Path

from generate_typical_project import generate as generate_typical_project
from perf_model import (
    SCHEMA,
    command_output,
    command_record,
    new_document,
    source_facts,
    summarize,
    validate_document,
    write_document,
)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESULT_ROOT = ROOT / "benchmark_artifacts" / "performance"
VIEWER_SOURCE = ROOT / "tools" / "perf-viewer"
VIEWER_OUTPUT = ROOT / "benchmark_artifacts" / "performance-viewer"
VIEWER_DATA_START = "<!-- lanius-performance-data:start -->"
VIEWER_DATA_END = "<!-- lanius-performance-data:end -->"
LANIUS_MODES = ("process_cold", "daemon_cold_workspace", "daemon_warm_workspace")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    run = subparsers.add_parser("run-lanius", help="run a canonical Lanius benchmark")
    run.add_argument("--workload", choices=("single-file", "typical-project"), required=True)
    run.add_argument("--size", type=int, default=1_000_000, help="single-file target bytes")
    run.add_argument("--files", type=int, default=100, help="typical-project source-file count")
    run.add_argument("--seed", type=int, default=20260808)
    run.add_argument("--samples", type=int, default=20)
    run.add_argument("--target", choices=("x86_64", "wasm"), default="x86_64")
    run.add_argument("--modes", default=",".join(LANIUS_MODES))
    run.add_argument("--output", type=Path)
    run.add_argument("--skip-profile", action="store_true")
    run.add_argument("--startup-timeout", type=float, default=900.0)
    run.add_argument("--job-timeout", type=float, default=900.0)

    validate = subparsers.add_parser("validate", help="validate canonical result JSON")
    validate.add_argument("paths", nargs="+", type=Path)

    legacy = subparsers.add_parser(
        "import-stress", help="normalize retained compiler-stress samples into the canonical schema"
    )
    legacy.add_argument("directories", nargs="+", type=Path)
    legacy.add_argument("--source-corpus", type=Path, required=True)
    legacy.add_argument("--output", type=Path, required=True)

    catalog = subparsers.add_parser("catalog", help="rebuild the viewer data catalog")
    catalog.add_argument("--result-root", type=Path, default=DEFAULT_RESULT_ROOT)

    build_viewer_parser = subparsers.add_parser("build-viewer", help="build the static Svelte performance viewer")
    build_viewer_parser.add_argument("--result-root", type=Path, default=DEFAULT_RESULT_ROOT)

    serve = subparsers.add_parser("serve", help="catalog results and serve the performance viewer")
    serve.add_argument("--result-root", type=Path, default=DEFAULT_RESULT_ROOT)
    serve.add_argument("--port", type=int, default=8765)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.action == "run-lanius":
        return run_lanius(args)
    if args.action == "validate":
        for path in args.paths:
            document = json.loads(resolve(path).read_text())
            if document.get("schema") == "lanius.performance-catalog.v1":
                for entry in document.get("results", []):
                    validate_document(entry["document"])
            else:
                validate_document(document)
            print(resolve(path))
        return 0
    if args.action == "import-stress":
        import_stress(args)
        return 0
    if args.action == "catalog":
        catalog_results(resolve(args.result_root))
        return 0
    if args.action == "build-viewer":
        catalog_results(resolve(args.result_root))
        build_viewer()
        return 0
    if args.action == "serve":
        result_root = resolve(args.result_root)
        catalog_results(result_root)
        serve_viewer(args.port)
        return 0
    raise AssertionError(args.action)


def run_lanius(args: argparse.Namespace) -> int:
    if args.samples <= 0 or args.size <= 0 or args.files <= 0:
        raise ValueError("--samples, --size, and --files must be positive")
    modes = tuple(part.strip() for part in args.modes.split(",") if part.strip())
    unknown = set(modes) - set(LANIUS_MODES)
    if not modes or unknown:
        raise ValueError(f"--modes must be a subset of {','.join(LANIUS_MODES)}; unknown={sorted(unknown)}")
    laniusc = ROOT / "target" / "release" / "laniusc"
    if not laniusc.is_file():
        raise ValueError(f"release compiler is missing: {laniusc}; build it before benchmarking")

    run_id, workload, input_path, source_root, sources, generation_command = prepare_workload(args)
    facts = source_facts(sources, ROOT)
    workload["generation_command"] = command_record(generation_command, ROOT)
    output = resolve(args.output) if args.output else DEFAULT_RESULT_ROOT / f"{run_id}.json"
    document = new_document(ROOT, run_id, workload)
    version = command_output([str(laniusc), "--version"], ROOT)
    artifact_dir = ROOT / "target" / "lanius-perf-artifacts" / run_id
    artifact_dir.mkdir(parents=True, exist_ok=True)

    for mode in modes:
        print(f"lanius_perf: {run_id} {mode} ({args.samples} samples)", flush=True)
        measurement = measure_mode(
            mode,
            laniusc,
            version,
            input_path,
            source_root,
            args.target,
            args.samples,
            artifact_dir,
            facts,
            args.startup_timeout,
            args.job_timeout,
        )
        if not args.skip_profile and mode == "daemon_warm_workspace":
            measurement["profile"] = profile_warm_job(
                laniusc,
                input_path,
                source_root,
                args.target,
                artifact_dir,
                args.startup_timeout,
                args.job_timeout,
            )
        document["measurements"].append(measurement)

    write_document(output, document)
    catalog_results(DEFAULT_RESULT_ROOT)
    print(output)
    return 0


def prepare_workload(args: argparse.Namespace):
    if args.workload == "single-file":
        run_id = f"single-file-{args.size}-seed-{args.seed}-{args.target}"
        root = ROOT / "target" / "lanius-perf-workloads" / run_id
        command = [
            sys.executable,
            "tools/generate_compiler_stress.py",
            "--out",
            str(root),
            "--layout",
            "comparative-single-file",
            "--sizes",
            str(args.size),
            "--seed",
            str(args.seed),
            "--profile",
            "mixed-function-sizes",
        ]
        checked(command, ROOT)
        input_path = root / str(args.size) / "scaling.lani"
        workload = {
            "id": run_id,
            "kind": "single_file",
            "classification": "synthetic compiler stress with a realistic function-size distribution",
            "generator": "tools/generate_compiler_stress.py",
            "seed": args.seed,
            "target_source_bytes": args.size,
        }
        return run_id, workload, input_path, None, [input_path], command

    run_id = f"typical-project-{args.files}-files-seed-{args.seed}-{args.target}"
    root = ROOT / "target" / "lanius-perf-workloads" / run_id
    generate_typical_project(root, args.files, args.seed)
    command = [
        sys.executable,
        "tools/generate_typical_project.py",
        "--out",
        str(root),
        "--files",
        str(args.files),
        "--seed",
        str(args.seed),
    ]
    input_path = root / "lanius" / "main.lani"
    source_root = root / "lanius" / "src"
    sources = [input_path, *source_root.rglob("*.lani")]
    workload = {
        "id": run_id,
        "kind": "typical_project",
        "classification": "corpus-calibrated typical project",
        "generator": "tools/generate_typical_project.py",
        "seed": args.seed,
        "requested_source_files": args.files,
    }
    return run_id, workload, input_path, source_root, sources, command


def import_stress(args: argparse.Namespace) -> None:
    directories = [resolve(path) for path in args.directories]
    corpus = resolve(args.source_corpus)
    documents = [
        (
            directory,
            json.loads((directory / "samples.json").read_text()),
            json.loads((directory / "commands.json").read_text()),
        )
        for directory in directories
    ]
    all_samples = [sample for _, document, _ in documents for sample in document["samples"]]
    if not all_samples:
        raise ValueError("legacy compiler-stress inputs have no samples")
    corpus_config = corpus / "config.json"
    target_bytes = (
        int(json.loads(corpus_config.read_text())["size"])
        if corpus_config.is_file()
        else int(all_samples[0]["source_bytes"])
    )
    run_id = f"imported-single-file-{target_bytes}-comparison"
    result = new_document(
        ROOT,
        run_id,
        {
            "id": run_id,
            "kind": "single_file",
            "classification": "imported controlled cross-language compiler stress",
            "generator": "tools/generate_compiler_stress.py",
            "legacy_import": True,
        },
    )
    grouped: dict[tuple[str, str], list[dict]] = {}
    command_sets = {}
    for directory, sample_document, commands in documents:
        local: dict[tuple[str, str], list[dict]] = {}
        for sample in sample_document["samples"]:
            local.setdefault((sample["language"], sample["lane"]), []).append(sample)
            command_sets[(sample["language"], sample["lane"])] = (directory, commands)
        # Later inputs deliberately replace an earlier measurement with the
        # same compiler/configuration. This lets a fresh Lanius-only run update
        # a frozen cross-language comparison without duplicating samples.
        grouped.update(local)
    extension = {
        "lanius": "lani",
        "c": "c",
        "tcc": "c",
        "cpp": "cpp",
        "rust": "rs",
        "zig": "zig",
        "pareas": "par",
    }
    for (language, lane), legacy_samples in sorted(grouped.items()):
        seed = legacy_samples[0].get("seed")
        source = next(
            iter((corpus / "sources" / f"seed-{seed}").rglob(f"*.{extension[language]}")),
            None,
        )
        if source is None:
            raise ValueError(f"source corpus has no {language} source for seed {seed}")
        facts = source_facts([source], ROOT)
        rows = []
        for index, sample in enumerate(legacy_samples):
            sample_source = next(
                iter(
                    (corpus / "sources" / f"seed-{sample.get('seed')}").rglob(
                        f"*.{extension[language]}"
                    )
                ),
                source,
            )
            sample_facts = source_facts([sample_source], ROOT)
            rows.append(
                {
                    "index": index,
                    "wall_ms": sample["wall_ms"],
                    "compiler_ms": sample.get("compiler_ms"),
                    "source_bytes": sample.get("source_bytes", sample_facts["bytes"]),
                    "source_sloc": sample_facts["sloc"],
                    "seed": sample.get("seed"),
                    "request_phases_ms": (
                        {
                            "load": sample.get("daemon_load_ms"),
                            "compile": sample.get("daemon_compile_ms"),
                            "write": sample.get("daemon_write_ms"),
                        }
                        if sample.get("daemon_compile_ms") is not None
                        else None
                    ),
                }
            )
        directory, commands = command_sets[(language, lane)]
        template = (
            commands.get(lane, {}).get(language)
            if language != "lanius"
            else commands.get("lanius_daemon")
        )
        result["measurements"].append(
            {
                "id": f"{language}-{lane}",
                "compiler": {"name": language, "version": "recorded in legacy provenance"},
                "target": "x86_64" if language != "pareas" else "riscv32",
                "configuration": lane,
                "configuration_display": (
                    "preallocated (legacy variable-project run)"
                    if language == "lanius" and lane == "hot_daemon_variable_project"
                    else lane
                ),
                "source": facts,
                "commands": {
                    "legacy_template": template,
                    "source": str(directory.relative_to(ROOT)),
                },
                "measurement_semantics": {
                    "imported": True,
                    "note": "raw timing samples are exact; old runner retained a command template rather than a materialized command per sample",
                },
                "samples": rows,
                "summary": summarize(rows, facts),
                "validation": {"legacy_artifacts_validated": True},
            }
        )
    output = resolve(args.output)
    write_document(output, result)
    catalog_results(DEFAULT_RESULT_ROOT)
    print(output)


def measure_mode(
    mode: str,
    laniusc: Path,
    version: str,
    input_path: Path,
    source_root: Path | None,
    target: str,
    samples: int,
    artifact_dir: Path,
    facts: dict,
    startup_timeout: float,
    job_timeout: float,
) -> dict:
    output = artifact_dir / f"{mode}.{'wasm' if target == 'wasm' else 'bin'}"
    direct = direct_command(laniusc, input_path, source_root, target, output)
    daemon_argv = daemon_command(laniusc, target)
    request = compile_request("measure-N", input_path, source_root, target, output)
    raw_samples: list[dict] = []
    ready_samples = []

    if mode == "process_cold":
        for index in range(samples):
            started = time.perf_counter_ns()
            checked(direct, ROOT)
            wall_ms = (time.perf_counter_ns() - started) / 1_000_000.0
            raw_samples.append({"index": index, "wall_ms": wall_ms, "compiler_ms": None})
        commands = {"compile": command_record(direct, ROOT)}
        semantics = {
            "process": "new compiler process for every measured sample",
            "daemon_started_before_timer": False,
            "gpu_workspace_preallocated": False,
            "compiled_unit_results_reused": False,
            "driver_shader_cache": "ambient machine state",
        }
    elif mode == "daemon_cold_workspace":
        for index in range(samples):
            daemon = Daemon(daemon_argv, ROOT, {}, startup_timeout, artifact_dir / f"{mode}-{index}.stderr")
            ready_samples.append(daemon.ready)
            try:
                wall_ms, response = daemon.request(
                    compile_request(f"measure-{index}", input_path, source_root, target, output),
                    job_timeout,
                )
                raw_samples.append(sample_from_response(index, wall_ms, response))
            finally:
                daemon.shutdown(job_timeout)
        commands = {
            "daemon_start": command_record(daemon_argv, ROOT),
            "compile_request": request,
        }
        semantics = {
            "process": "fresh ready daemon for every measured sample",
            "daemon_started_before_timer": True,
            "gpu_workspace_preallocated": False,
            "compiled_unit_results_reused": False,
            "driver_shader_cache": "ambient machine state",
        }
    else:
        daemon = Daemon(daemon_argv, ROOT, {}, startup_timeout, artifact_dir / f"{mode}.stderr")
        ready_samples.append(daemon.ready)
        try:
            primer_count = prime_workspace_until_stable(
                daemon, input_path, source_root, target, output, job_timeout
            )
            for index in range(samples):
                _, cleared = daemon.request(
                    {"id": f"clear-{index}", "command": "clear-compiled-unit-cache"}, job_timeout
                )
                if cleared.get("event") != "compiled-unit-cache-cleared":
                    raise RuntimeError(f"cache clear failed: {cleared}")
                wall_ms, response = daemon.request(
                    compile_request(f"measure-{index}", input_path, source_root, target, output),
                    job_timeout,
                )
                cache = response.get("compiled_unit_cache", {})
                if cache.get("hits_during_job", 0) != 0:
                    raise RuntimeError(f"warm full-build sample reused compiled units: {response}")
                created = response.get("resources_created_during_job", {})
                if any(created.get(kind, 0) for kind in ("buffers", "bind_groups", "compute_pipelines")):
                    raise RuntimeError(
                        f"warm workspace sample created GPU job resources after {primer_count} primers: {response}"
                    )
                raw_samples.append(sample_from_response(index, wall_ms, response))
        finally:
            daemon.shutdown(job_timeout)
        commands = {
            "daemon_start": command_record(daemon_argv, ROOT),
            "workspace_primer_request": compile_request(
                "workspace-primer", input_path, source_root, target, output
            ),
            "workspace_primer_repeated_until_stable": primer_count,
            "before_each_sample": {"command": "clear-compiled-unit-cache"},
            "compile_request": request,
        }
        semantics = {
            "process": "one daemon for primer and every measured sample",
            "daemon_started_before_timer": True,
            "gpu_workspace_preallocated": True,
            "compiled_unit_results_reused": False,
            "source_manifest_metadata_may_be_resident": True,
            "driver_shader_cache": "ambient machine state",
        }

    return {
        "id": f"lanius-{target}-{mode}",
        "compiler": {"name": "lanius", "version": version},
        "target": target,
        "configuration": mode,
        "source": facts,
        "commands": commands,
        "measurement_semantics": semantics,
        "samples": raw_samples,
        "summary": summarize(raw_samples, facts),
        "daemon_ready_samples": ready_samples,
        "validation": {"compile_exit_status": 0, "artifact_bytes": output.stat().st_size},
    }


def sample_from_response(index: int, wall_ms: float, response: dict) -> dict:
    if response.get("ok") is not True:
        raise RuntimeError(f"daemon compile failed: {response}")
    return {
        "index": index,
        "wall_ms": wall_ms,
        "compiler_ms": response.get("compile_ms"),
        "request_phases_ms": {
            "load": response.get("load_ms"),
            "compile": response.get("compile_ms"),
            "write": response.get("write_ms"),
        },
        "gpu_memory": response.get("tracked_gpu_buffers"),
        "wgpu_resources": response.get("wgpu_resources"),
        "resources_created": response.get("resources_created_during_job"),
        "workspace_request_kind": response.get("workspace_request_kind"),
        "recorded_compute_passes": response.get("recorded_compute_passes_during_job"),
        "compiled_unit_cache": response.get("compiled_unit_cache"),
    }


def profile_warm_job(
    laniusc: Path,
    input_path: Path,
    source_root: Path | None,
    target: str,
    artifact_dir: Path,
    startup_timeout: float,
    job_timeout: float,
) -> dict:
    output = artifact_dir / f"profile.{'wasm' if target == 'wasm' else 'bin'}"
    trace_path = artifact_dir / "profile-trace.json"
    env = os.environ.copy()
    env.update(
        {
            "LANIUS_PERFETTO_TRACE": str(trace_path),
            "LANIUS_GPU_COMPUTE_PASS_BREAKDOWN": "1",
            "LANIUS_GPU_BUFFER_BREAKDOWN": "1",
        }
    )
    daemon = Daemon(
        daemon_command(laniusc, target), ROOT, env, startup_timeout, artifact_dir / "profile.stderr"
    )
    try:
        prime_workspace_until_stable(
            daemon, input_path, source_root, target, output, job_timeout, "profile-primer"
        )
        daemon.request({"id": "profile-clear", "command": "clear-compiled-unit-cache"}, job_timeout)
        wall_ms, response = daemon.request(
            compile_request("profile", input_path, source_root, target, output), job_timeout
        )
    finally:
        daemon.shutdown(job_timeout)
    trace = json.loads(trace_path.read_text())
    timeline = profile_timeline(trace, "daemon.job.profile")
    return {
        "excluded_from_timing_statistics": True,
        "reason": "named pass accounting and tracing add measurement overhead",
        "wall_ms": wall_ms,
        "response": response,
        "timeline": timeline,
        "execution_graph": execution_graph(timeline),
        "trace_path": str(trace_path.relative_to(ROOT)),
    }


def prime_workspace_until_stable(
    daemon: "Daemon",
    input_path: Path,
    source_root: Path | None,
    target: str,
    output: Path,
    timeout: float,
    request_prefix: str = "workspace-primer",
) -> int:
    """Prime until one complete recompile creates no job-time GPU resources."""
    for index in range(1, 7):
        daemon.request(
            {"id": f"{request_prefix}-clear-{index}", "command": "clear-compiled-unit-cache"},
            timeout,
        )
        _, response = daemon.request(
            compile_request(
                f"{request_prefix}-{index}", input_path, source_root, target, output
            ),
            timeout,
        )
        created = response.get("resources_created_during_job", {})
        if not any(
            created.get(kind, 0) for kind in ("buffers", "bind_groups", "compute_pipelines")
        ):
            return index
    raise RuntimeError("GPU workspace and bind groups did not stabilize after six full primers")


def profile_timeline(trace: dict, boundary_name: str) -> list[dict]:
    events = trace.get("traceEvents", [])
    lane_by_tid = {
        event["tid"]: event.get("args", {}).get("name", str(event["tid"]))
        for event in events
        if event.get("ph") == "M" and event.get("name") == "thread_name"
    }
    boundary = next(
        (event for event in events if event.get("ph") == "X" and event.get("name") == boundary_name),
        None,
    )
    if boundary is None:
        raise RuntimeError(f"trace has no {boundary_name!r} job boundary")
    start = float(boundary["ts"])
    end = start + float(boundary.get("dur", 0.0))
    rows = []
    for event in events:
        if event.get("ph") != "X" or event is boundary:
            continue
        event_start = float(event.get("ts", 0.0))
        event_duration = float(event.get("dur", 0.0))
        if event_start < start or event_start + event_duration > end:
            continue
        rows.append(
            {
                "name": event.get("name", "<unnamed>"),
                "category": event.get("cat", ""),
                "lane": lane_by_tid.get(event.get("tid"), str(event.get("tid"))),
                "start_ms": (event_start - start) / 1000.0,
                "duration_ms": event_duration / 1000.0,
            }
        )
    rows.sort(key=lambda row: (row["start_ms"], row["lane"], row["name"]))
    return rows


def execution_graph(timeline: list[dict]) -> dict:
    nodes: dict[tuple[str, str], dict] = {}
    by_lane: dict[str, list[dict]] = {}
    for event in timeline:
        by_lane.setdefault(event["lane"], []).append(event)
        key = (event["lane"], event["name"])
        node = nodes.setdefault(
            key,
            {
                "id": hashlib.sha256(f"{key[0]}\0{key[1]}".encode()).hexdigest()[:16],
                "lane": key[0],
                "name": key[1],
                "invocations": 0,
                "total_duration_ms": 0.0,
            },
        )
        node["invocations"] += 1
        node["total_duration_ms"] += event["duration_ms"]
    edges: dict[tuple[str, str], int] = {}
    for events in by_lane.values():
        for left, right in zip(events, events[1:]):
            left_id = nodes[(left["lane"], left["name"])]["id"]
            right_id = nodes[(right["lane"], right["name"])]["id"]
            if left_id != right_id:
                edges[(left_id, right_id)] = edges.get((left_id, right_id), 0) + 1
    return {
        "nodes": sorted(nodes.values(), key=lambda node: (node["lane"], node["name"])),
        "edges": [
            {"source": source, "target": target, "transitions": count}
            for (source, target), count in sorted(edges.items())
        ],
        "semantics": "consecutive traced operations within each execution lane; repeated nodes and edges are collapsed",
    }


def direct_command(
    laniusc: Path, input_path: Path, source_root: Path | None, target: str, output: Path
) -> list[str]:
    command = [
        str(laniusc),
        "--emit",
        target,
        "--stdlib-root",
        str(ROOT / "stdlib"),
    ]
    if source_root is not None:
        command.extend(["--source-root", str(source_root)])
    command.extend(["-o", str(output), str(input_path)])
    return command


def daemon_command(laniusc: Path, target: str) -> list[str]:
    return [
        str(laniusc),
        "daemon",
        "--stdio",
        "--backend",
        target,
        "--stdlib-root",
        str(ROOT / "stdlib"),
        "--idle-buffer-timeout-ms",
        "0",
    ]


def compile_request(
    request_id: str, input_path: Path, source_root: Path | None, target: str, output: Path
) -> dict:
    request = {
        "id": request_id,
        "command": "compile",
        "emit": target,
        "input": str(input_path),
        "output": str(output),
    }
    if source_root is not None:
        request["source_root"] = str(source_root)
    return request


class Daemon:
    def __init__(
        self,
        argv: list[str],
        cwd: Path,
        env: dict[str, str],
        timeout: float,
        stderr_path: Path,
    ):
        stderr_path.parent.mkdir(parents=True, exist_ok=True)
        self.stderr_file = stderr_path.open("wb")
        self.process = subprocess.Popen(
            argv,
            cwd=cwd,
            env=env or None,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=self.stderr_file,
            text=True,
            bufsize=1,
        )
        self.ready = self.read(timeout, "daemon ready event")
        if self.ready.get("event") != "ready":
            raise RuntimeError(f"daemon did not become ready: {self.ready}")

    def request(self, request: dict, timeout: float) -> tuple[float, dict]:
        assert self.process.stdin is not None
        started = time.perf_counter_ns()
        self.process.stdin.write(json.dumps(request, separators=(",", ":")) + "\n")
        self.process.stdin.flush()
        response = self.read(timeout, f"response to {request.get('id')}")
        return (time.perf_counter_ns() - started) / 1_000_000.0, response

    def read(self, timeout: float, description: str) -> dict:
        assert self.process.stdout is not None
        readable, _, _ = select.select([self.process.stdout], [], [], timeout)
        if not readable:
            raise TimeoutError(f"timed out waiting for {description}")
        line = self.process.stdout.readline()
        if not line:
            raise RuntimeError(f"daemon exited before {description}; status={self.process.poll()}")
        value = json.loads(line)
        if not isinstance(value, dict):
            raise RuntimeError(f"{description} was not a JSON object")
        return value

    def shutdown(self, timeout: float) -> None:
        if self.process.poll() is None:
            try:
                self.request({"id": "shutdown", "command": "shutdown"}, timeout)
                assert self.process.stdin is not None
                self.process.stdin.close()
                self.process.wait(timeout=timeout)
            except Exception:
                self.process.kill()
                self.process.wait()
                raise
        self.stderr_file.close()


def catalog_results(result_root: Path) -> Path:
    result_root.mkdir(parents=True, exist_ok=True)
    documents = []
    invalid = []
    for path in sorted(result_root.rglob("*.json")):
        if path.name == "catalog.json":
            continue
        try:
            document = json.loads(path.read_text())
            validate_document(document)
            documents.append({"path": str(path.relative_to(ROOT)), "document": document})
        except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
            invalid.append({"path": str(path.relative_to(ROOT)), "error": str(error)})
    catalog = {
        "schema": "lanius.performance-catalog.v1",
        "generated_at_unix_seconds": int(time.time()),
        "results": documents,
        "invalid_results": invalid,
    }
    path = result_root / "catalog.json"
    path.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n")
    viewer_data = "window.LANIUS_PERFORMANCE_CATALOG = " + json.dumps(catalog, separators=(",", ":")) + ";\n"
    source_data = VIEWER_SOURCE / "public" / "performance-data.js"
    source_data.parent.mkdir(parents=True, exist_ok=True)
    source_data.write_text(viewer_data)
    update_built_viewer_catalog(viewer_data)
    print(f"lanius_perf: cataloged {len(documents)} result files ({len(invalid)} invalid)")
    return path


def build_viewer() -> None:
    if shutil.which("npm") is None:
        raise RuntimeError("npm is required to build the performance viewer")
    if not (VIEWER_SOURCE / "node_modules").is_dir():
        raise RuntimeError(f"viewer dependencies are missing; run `npm install` in {VIEWER_SOURCE}")
    checked(["npm", "run", "build:bundle"], VIEWER_SOURCE)
    viewer_data = (VIEWER_SOURCE / "public" / "performance-data.js").read_text()
    if not update_built_viewer_catalog(viewer_data):
        raise RuntimeError("built viewer is missing its performance-data insertion markers")
    print(VIEWER_OUTPUT / "index.html")


def update_built_viewer_catalog(viewer_data: str) -> bool:
    index = VIEWER_OUTPUT / "index.html"
    if not index.is_file():
        return False
    html = index.read_text()
    start = html.find(VIEWER_DATA_START)
    end = html.find(VIEWER_DATA_END)
    if start < 0 and end < 0:
        return False
    if start < 0 or end < start:
        raise RuntimeError("built viewer has malformed performance-data insertion markers")
    end += len(VIEWER_DATA_END)
    safe_data = viewer_data.replace("</script", "<\\/script")
    replacement = f"{VIEWER_DATA_START}\n<script>{safe_data}</script>\n{VIEWER_DATA_END}"
    index.write_text(html[:start] + replacement + html[end:])
    (VIEWER_OUTPUT / "performance-data.js").unlink(missing_ok=True)
    return True


def serve_viewer(port: int) -> None:
    if not 1 <= port <= 65535:
        raise ValueError("--port must be between 1 and 65535")
    viewer_index = VIEWER_OUTPUT / "index.html"
    if not viewer_index.is_file():
        raise RuntimeError("performance viewer is not built; run `python3 tools/lanius_perf.py build-viewer`")
    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(
        *args, directory=str(ROOT), **kwargs
    )
    with socketserver.TCPServer(("127.0.0.1", port), handler) as server:
        url = f"http://127.0.0.1:{port}/benchmark_artifacts/performance-viewer/index.html"
        print(url, flush=True)
        server.serve_forever()


def checked(argv: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(argv, cwd=cwd, text=True, capture_output=True, check=False)
    if completed.returncode != 0:
        raise RuntimeError(
            f"command failed ({completed.returncode}): {argv!r}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def resolve(path: Path) -> Path:
    return path.resolve() if path.is_absolute() else (ROOT / path).resolve()


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, RuntimeError, TimeoutError, json.JSONDecodeError) as error:
        print(f"lanius_perf: {error}", file=sys.stderr)
        raise SystemExit(1)
