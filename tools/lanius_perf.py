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
from dataclasses import dataclass
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
from summarize_nsight_gpu_trace import build_nsight_profile


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESULT_ROOT = ROOT / "benchmark_artifacts" / "performance"
VIEWER_SOURCE = ROOT / "tools" / "perf-viewer"
VIEWER_OUTPUT = ROOT / "benchmark_artifacts" / "performance-viewer"
VIEWER_DATA_START = "<!-- lanius-performance-data:start -->"
VIEWER_DATA_END = "<!-- lanius-performance-data:end -->"
LANIUS_MODES = ("process_cold", "daemon_cold_workspace", "daemon_warm_workspace")
DEFAULT_BENCHMARK_SEED = 20260808
DEFAULT_SAMPLE_COUNT = 20
CANONICAL_SINGLE_FILE_PRESET = "single-file-1mb"


@dataclass(frozen=True)
class WorkloadSpec:
    kind: str
    seeds: tuple[int, ...]
    sample_count: int
    preset: str | None = None
    target_bytes: int | None = None
    file_count: int | None = None
    profile: str | None = None
    primer_seed: int | None = None


@dataclass(frozen=True)
class WorkloadCase:
    seed: int
    input_path: Path
    source_root: Path | None
    facts: dict


CANONICAL_WORKLOAD_PRESETS = {
    CANONICAL_SINGLE_FILE_PRESET: WorkloadSpec(
        kind="single_file",
        seeds=tuple(range(20, 40)),
        sample_count=20,
        preset=CANONICAL_SINGLE_FILE_PRESET,
        target_bytes=1_000_000,
        profile="pareas-common-subset",
        primer_seed=19,
    ),
}


def timeline_execution_domain(category: str, lane: str, name: str = "") -> str:
    """Classify a trace event by the kind of execution it represents."""
    if category == "submission_gap" or (
        category == "gpu"
        and name
        in {
            "parser.tokens.impl_header.begin",
        }
    ):
        return "submission_gap"
    if category == "gpu":
        return "gpu_execution"
    if lane == "host.submit":
        return "queue_submission"
    if lane == "host.readback":
        return "host_readback_wait"
    return "host_orchestration"


def timeline_compiler_phase(name: str) -> str:
    """Classify a trace label into a stable compiler phase for the viewer."""
    label = name.lower().replace("-", "_")

    if (
        label.startswith(
            (
                "lex.",
                "lexer.",
                "dfa_",
                "pair_",
                "compact_boundaries",
                "source_file_boundaries",
                "tokens_build",
            )
        )
        or ".lexer" in label
    ):
        return "lexing"
    if label.startswith(("typecheck.", "type_check.")) or any(
        marker in label for marker in (".typecheck", "_typecheck", ".type_check", "_type_check")
    ):
        return "type_checking"
    if "semantic_interface" in label:
        return "semantic_interface"
    if (
        label.startswith(("codegen.x86", "x86."))
        or "x86_object" in label
        or name.lower().startswith("x86 object")
    ):
        return "x86_emission"
    if label.startswith(("codegen.wasm", "wasm.")) or "wasm_object" in label:
        return "wasm_emission"
    if "lowering" in label or label.startswith("lower."):
        return "lowering"
    if label.startswith("codegen.") or "artifact" in label or ".link." in label:
        return "artifact_emission"
    if (
        label.startswith("compile.source_pack.record.parser_")
        or label == "parser.recorded_ll1_hir.status"
    ):
        return "orchestration"
    if label.startswith((
        "hir.",
        "parser.hir_",
        "parser.tree_depth_",
        "parser.source_file_token_end",
        "parser.done",
        "parser.ll1_hir",
        "parser.end",
    )):
        return "hir_construction"
    if label.startswith(("parser.", "parse.")) or any(
        marker in label for marker in (".parser", "_parser")
    ):
        return "parsing"
    return "orchestration"


def annotate_timeline_event(event: dict) -> None:
    """Add viewer-facing semantics while retaining the original trace lane."""
    name = str(event.get("name", ""))
    event["execution_domain"] = timeline_execution_domain(
        str(event.get("category", "")), str(event.get("lane", "")), name
    )
    event["phase"] = (
        "orchestration"
        if event["execution_domain"] == "submission_gap"
        else timeline_compiler_phase(name)
    )
    if event["execution_domain"] == "submission_gap":
        event["name"] = "Between Lanius GPU submissions"


def annotate_document_timeline(document: dict) -> None:
    """Normalize historical profiles when constructing the generated catalog."""
    for measurement in document.get("measurements", []):
        profile = measurement.get("profile")
        if not isinstance(profile, dict):
            continue
        for event in profile.get("timeline", []):
            if isinstance(event, dict):
                annotate_timeline_event(event)


def single_file_comparison_group(
    target_bytes: int, profile: str, seeds: tuple[int, ...]
) -> str:
    seed_identity = ",".join(str(seed) for seed in seeds)
    return (
        "compiler-stress/comparative-single-file/"
        f"{profile}/{target_bytes}/seeds-{seed_identity}"
    )


def typical_project_comparison_group(file_count: int, seed: int) -> str:
    return f"typical-project/v1/seed-{seed}/files-{file_count}"


def resolve_workload_spec(args: argparse.Namespace) -> WorkloadSpec:
    if args.preset:
        conflicting = [
            name
            for name, value in (
                ("--custom-size", args.custom_size),
                ("--files", args.files),
                ("--seed", args.seed),
                ("--samples", args.samples),
            )
            if value is not None
        ]
        if conflicting:
            raise ValueError(
                f"--preset {args.preset} fixes its workload; remove {', '.join(conflicting)}"
            )
        return CANONICAL_WORKLOAD_PRESETS[args.preset]

    seed = args.seed if args.seed is not None else DEFAULT_BENCHMARK_SEED
    sample_count = args.samples if args.samples is not None else DEFAULT_SAMPLE_COUNT
    if sample_count <= 0:
        raise ValueError("--samples must be positive")

    if args.workload == "single-file":
        if args.custom_size is None:
            raise ValueError(
                "custom single-file workloads require --custom-size; "
                f"use --preset {CANONICAL_SINGLE_FILE_PRESET} for the comparable 1 MB corpus"
            )
        if args.custom_size <= 0:
            raise ValueError("--custom-size must be positive")
        if args.files is not None:
            raise ValueError("--files only applies to typical-project workloads")
        return WorkloadSpec(
            kind="single_file",
            seeds=(seed,),
            sample_count=sample_count,
            target_bytes=args.custom_size,
            profile="mixed-function-sizes",
        )

    if args.custom_size is not None:
        raise ValueError("--custom-size only applies to single-file workloads")
    file_count = args.files if args.files is not None else 100
    if file_count <= 0:
        raise ValueError("--files must be positive")
    return WorkloadSpec(
        kind="typical_project",
        seeds=(seed,),
        sample_count=sample_count,
        file_count=file_count,
    )


def custom_workload_warning(spec: WorkloadSpec) -> str | None:
    if spec.kind != "single_file" or spec.preset is not None:
        return None
    canonical = CANONICAL_WORKLOAD_PRESETS[CANONICAL_SINGLE_FILE_PRESET]
    assert spec.target_bytes is not None and canonical.target_bytes is not None
    if abs(spec.target_bytes - canonical.target_bytes) > canonical.target_bytes // 10:
        return None
    return (
        f"custom single-file workload is {spec.target_bytes:,} bytes and will not use the "
        f"frozen comparison corpus; use --preset {CANONICAL_SINGLE_FILE_PRESET} "
        f"for its {canonical.target_bytes:,}-byte, seeds 20-39 workload"
    )


def workload_run_id(spec: WorkloadSpec, target: str) -> str:
    if spec.kind == "single_file":
        assert spec.target_bytes is not None
        identity = spec.preset or (
            f"single-file-custom-{spec.target_bytes}-seed-{spec.seeds[0]}"
        )
        return f"{identity}-{target}"
    assert spec.file_count is not None
    return (
        f"typical-project-{spec.file_count}-files-seed-{spec.seeds[0]}-{target}"
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)

    run = subparsers.add_parser("run-lanius", help="run a retained Lanius benchmark")
    workload = run.add_mutually_exclusive_group(required=True)
    workload.add_argument(
        "--preset",
        choices=tuple(CANONICAL_WORKLOAD_PRESETS),
        help="immutable workload identity matching retained comparison baselines",
    )
    workload.add_argument("--workload", choices=("single-file", "typical-project"))
    run.add_argument(
        "--custom-size",
        type=int,
        help="exact bytes for a non-comparable custom single-file workload",
    )
    run.add_argument("--files", type=int, help="typical-project source-file count (default: 100)")
    run.add_argument(
        "--seed",
        type=int,
        help=f"custom workload seed (default: {DEFAULT_BENCHMARK_SEED})",
    )
    run.add_argument(
        "--samples",
        type=int,
        help=f"custom workload sample count (default: {DEFAULT_SAMPLE_COUNT})",
    )
    run.add_argument("--target", choices=("x86_64", "wasm"), default="x86_64")
    run.add_argument("--modes", default=",".join(LANIUS_MODES))
    run.add_argument("--output", type=Path)
    run.add_argument("--skip-profile", action="store_true")
    run.add_argument("--startup-timeout", type=float, default=900.0)
    run.add_argument("--job-timeout", type=float, default=900.0)

    validate = subparsers.add_parser("validate", help="validate canonical result JSON")
    validate.add_argument("paths", nargs="+", type=Path)

    nsight = subparsers.add_parser(
        "attach-nsight", help="attach an Nsight Graphics export to a canonical measurement"
    )
    nsight.add_argument("result", type=Path)
    nsight.add_argument("--measurement", required=True, help="canonical measurement id")
    nsight.add_argument("--export-dir", required=True, type=Path)

    importer = subparsers.add_parser(
        "import-stress", help="normalize retained compiler-stress samples into the canonical schema"
    )
    importer.add_argument("directories", nargs="+", type=Path)
    importer.add_argument("--source-corpus", type=Path, required=True)
    importer.add_argument("--output", type=Path, required=True)

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
    if args.action == "attach-nsight":
        attach_nsight(args)
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


def attach_nsight(args: argparse.Namespace) -> None:
    result_path = resolve(args.result)
    document = json.loads(result_path.read_text())
    validate_document(document)
    measurement = next(
        (item for item in document["measurements"] if item.get("id") == args.measurement),
        None,
    )
    if measurement is None:
        raise ValueError(f"result has no measurement {args.measurement!r}")
    profile = measurement.get("profile")
    if not isinstance(profile, dict):
        raise ValueError(
            f"measurement {args.measurement!r} has no captured host profile to augment"
        )
    profile["nsight"] = build_nsight_profile(resolve(args.export_dir))
    write_document(result_path, document)
    catalog_results(DEFAULT_RESULT_ROOT)
    print(result_path)


def run_lanius(args: argparse.Namespace) -> int:
    spec = resolve_workload_spec(args)
    warning = custom_workload_warning(spec)
    if warning:
        print(f"lanius_perf: warning: {warning}", file=sys.stderr, flush=True)
    modes = tuple(part.strip() for part in args.modes.split(",") if part.strip())
    unknown = set(modes) - set(LANIUS_MODES)
    if not modes or unknown:
        raise ValueError(f"--modes must be a subset of {','.join(LANIUS_MODES)}; unknown={sorted(unknown)}")
    laniusc = ROOT / "target" / "release" / "laniusc"
    if not laniusc.is_file():
        raise ValueError(f"release compiler is missing: {laniusc}; build it before benchmarking")

    run_id, workload, cases, primer_case, generation_commands = prepare_workload(
        spec, args.target
    )
    sample_cases = cases if spec.preset else [cases[0]] * spec.sample_count
    representative_case = sorted(
        cases, key=lambda case: (case.facts["sloc"], case.seed)
    )[len(cases) // 2]
    facts = representative_case.facts
    workload["generation_commands"] = [
        command_record(command, ROOT) for command in generation_commands
    ]
    output = resolve(args.output) if args.output else DEFAULT_RESULT_ROOT / f"{run_id}.json"
    document = new_document(ROOT, run_id, workload)
    version = command_output([str(laniusc), "--version"], ROOT)
    artifact_dir = ROOT / "target" / "lanius-perf-artifacts" / run_id
    artifact_dir.mkdir(parents=True, exist_ok=True)

    for mode in modes:
        print(f"lanius_perf: {run_id} {mode} ({len(sample_cases)} samples)", flush=True)
        measurement = measure_mode(
            mode,
            laniusc,
            version,
            sample_cases,
            cases,
            primer_case,
            args.target,
            artifact_dir,
            facts,
            args.startup_timeout,
            args.job_timeout,
        )
        if not args.skip_profile and mode in {
            "daemon_cold_workspace",
            "daemon_warm_workspace",
        }:
            profile_case = representative_case
            measurement["profile"] = profile_daemon_job(
                mode,
                laniusc,
                cases,
                primer_case,
                profile_case,
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


def prepare_workload(spec: WorkloadSpec, target: str):
    if spec.kind == "single_file":
        assert spec.target_bytes is not None and spec.profile is not None
        run_id = workload_run_id(spec, target)
        root = ROOT / "target" / "lanius-perf-workloads" / run_id
        generation_commands = []
        cases = []
        all_seeds = [*spec.seeds]
        if spec.primer_seed is not None:
            all_seeds.append(spec.primer_seed)
        for seed in all_seeds:
            seed_root = root / f"seed-{seed}"
            command = [
                sys.executable,
                "tools/generate_compiler_stress.py",
                "--out",
                str(seed_root),
                "--layout",
                "comparative-single-file",
                "--sizes",
                str(spec.target_bytes),
                "--seed",
                str(seed),
                "--profile",
                spec.profile,
            ]
            checked(command, ROOT)
            generation_commands.append(command)
            input_path = seed_root / str(spec.target_bytes) / "scaling.lani"
            cases.append(
                WorkloadCase(seed, input_path, None, source_facts([input_path], ROOT))
            )
        primer_case = None
        if spec.primer_seed is not None:
            primer_case = cases.pop()
        workload = {
            "id": run_id,
            "kind": "single_file",
            "classification": "synthetic compiler stress with a realistic function-size distribution",
            "generator": "tools/generate_compiler_stress.py",
            "preset": spec.preset,
            "profile": spec.profile,
            "measured_seeds": list(spec.seeds),
            "primer_seed": spec.primer_seed,
            "target_source_bytes": spec.target_bytes,
            "comparison_group": single_file_comparison_group(
                spec.target_bytes, spec.profile, spec.seeds
            ),
        }
        return run_id, workload, cases, primer_case, generation_commands

    assert spec.file_count is not None
    seed = spec.seeds[0]
    run_id = workload_run_id(spec, target)
    root = ROOT / "target" / "lanius-perf-workloads" / run_id
    generate_typical_project(root, spec.file_count, seed)
    command = [
        sys.executable,
        "tools/generate_typical_project.py",
        "--out",
        str(root),
        "--files",
        str(spec.file_count),
        "--seed",
        str(seed),
    ]
    input_path = root / "lanius" / "main.lani"
    source_root = root / "lanius" / "src"
    sources = [input_path, *source_root.rglob("*.lani")]
    case = WorkloadCase(seed, input_path, source_root, source_facts(sources, ROOT))
    workload = {
        "id": run_id,
        "kind": "typical_project",
        "classification": "corpus-calibrated typical project",
        "generator": "tools/generate_typical_project.py",
        "seed": seed,
        "requested_source_files": spec.file_count,
        "comparison_group": typical_project_comparison_group(spec.file_count, seed),
    }
    return run_id, workload, [case], None, [command]


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
        raise ValueError("imported compiler-stress inputs have no samples")
    corpus_config = corpus / "config.json"
    corpus_settings = json.loads(corpus_config.read_text()) if corpus_config.is_file() else {}
    target_bytes = int(corpus_settings.get("size", all_samples[0]["source_bytes"]))
    profile = str(corpus_settings.get("workload_profile", "unknown-profile"))
    seeds = tuple(int(seed) for seed in corpus_settings.get("seeds", []))
    if not seeds:
        seeds = tuple(sorted({int(sample["seed"]) for sample in all_samples}))
    run_id = f"imported-single-file-{target_bytes}-comparison"
    result = new_document(
        ROOT,
        run_id,
        {
            "id": run_id,
            "kind": "single_file",
            "classification": "imported controlled cross-language compiler stress",
            "generator": "tools/generate_compiler_stress.py",
            "imported": True,
            "baseline_only": True,
            "comparison_group": single_file_comparison_group(
                target_bytes, profile, seeds
            ),
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
    for (language, lane), imported_samples in sorted(grouped.items()):
        seed = imported_samples[0].get("seed")
        source = next(
            iter((corpus / "sources" / f"seed-{seed}").rglob(f"*.{extension[language]}")),
            None,
        )
        if source is None:
            raise ValueError(f"source corpus has no {language} source for seed {seed}")
        facts = source_facts([source], ROOT)
        rows = []
        for index, sample in enumerate(imported_samples):
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
        if not isinstance(template, list) or not template:
            raise ValueError(f"imported samples have no command template for {language}/{lane}")
        configuration = (
            "preallocated"
            if language == "lanius" and lane == "hot_daemon_variable_project"
            else lane
        )
        result["measurements"].append(
            {
                "id": f"{language}-{configuration}",
                "compiler": {"name": language, "version": "unavailable (imported measurement)"},
                "target": "x86_64" if language != "pareas" else "riscv32",
                "configuration": configuration,
                "configuration_display": configuration,
                "source": facts,
                "commands": {"command": command_record(template, ROOT)},
                "measurement_semantics": {
                    "imported": True,
                    "source_artifact": str(directory.relative_to(ROOT)),
                    "note": "raw timing samples are exact; old runner retained a command template rather than a materialized command per sample",
                },
                "samples": rows,
                "summary": summarize(rows, facts),
                "validation": {"artifacts_validated": True},
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
    sample_cases: list[WorkloadCase],
    capacity_cases: list[WorkloadCase],
    primer_case: WorkloadCase | None,
    target: str,
    artifact_dir: Path,
    facts: dict,
    startup_timeout: float,
    job_timeout: float,
) -> dict:
    daemon_argv = daemon_command(laniusc, target)
    raw_samples: list[dict] = []
    ready_samples = []
    sample_commands = []
    suffix = "wasm" if target == "wasm" else "bin"
    last_output = artifact_dir / f"{mode}-0.{suffix}"

    if mode == "process_cold":
        for index, case in enumerate(sample_cases):
            output = artifact_dir / f"{mode}-{index}.{suffix}"
            direct = direct_command(
                laniusc, case.input_path, case.source_root, target, output
            )
            started = time.perf_counter_ns()
            checked(direct, ROOT)
            wall_ms = (time.perf_counter_ns() - started) / 1_000_000.0
            raw_samples.append(
                {
                    "index": index,
                    "wall_ms": wall_ms,
                    "compiler_ms": None,
                    **sample_case_fields(case),
                }
            )
            sample_commands.append(command_record(direct, ROOT))
            last_output = output
        commands = {"sample_compile_commands": sample_commands}
        semantics = {
            "process": "new compiler process for every measured sample",
            "daemon_started_before_timer": False,
            "gpu_workspace_preallocated": False,
            "compiled_unit_results_reused": False,
            "driver_shader_cache": "ambient machine state",
        }
    elif mode == "daemon_cold_workspace":
        sample_requests = []
        for index, case in enumerate(sample_cases):
            output = artifact_dir / f"{mode}-{index}.{suffix}"
            daemon = Daemon(daemon_argv, ROOT, {}, startup_timeout, artifact_dir / f"{mode}-{index}.stderr")
            ready_samples.append(daemon.ready)
            request = compile_request(
                f"measure-{index}", case.input_path, case.source_root, target, output
            )
            try:
                wall_ms, response = daemon.request(request, job_timeout)
                raw_samples.append(
                    sample_from_response(index, wall_ms, response, case)
                )
            finally:
                daemon.shutdown(job_timeout)
            sample_requests.append(request)
            last_output = output
        commands = {
            "daemon_start": command_record(daemon_argv, ROOT),
            "sample_compile_requests": sample_requests,
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
        primer_counts = {}
        try:
            for case in [*capacity_cases, *([primer_case] if primer_case else [])]:
                primer_output = artifact_dir / f"{mode}-primer-{case.seed}.{suffix}"
                primer_counts[str(case.seed)] = prime_workspace_until_stable(
                    daemon,
                    case.input_path,
                    case.source_root,
                    target,
                    primer_output,
                    job_timeout,
                    f"workspace-primer-{case.seed}",
                )
            sample_requests = []
            for index, case in enumerate(sample_cases):
                output = artifact_dir / f"{mode}-{index}.{suffix}"
                _, cleared = daemon.request(
                    {
                        "id": f"clear-{index}",
                        "command": "clear-project-compiled-unit-cache",
                    },
                    job_timeout,
                )
                if cleared.get("event") != "project-compiled-unit-cache-cleared":
                    raise RuntimeError(f"cache clear failed: {cleared}")
                request = compile_request(
                    f"measure-{index}", case.input_path, case.source_root, target, output
                )
                wall_ms, response = daemon.request(request, job_timeout)
                cache = response.get("compiled_unit_cache", {})
                if (
                    cache.get("hits_during_job", 0) > 0
                    and cache.get("misses_during_job", 0) == 0
                ):
                    raise RuntimeError(f"warm project build reused every compiled unit: {response}")
                created = response.get("resources_created_during_job", {})
                if any(created.get(kind, 0) for kind in ("buffers", "bind_groups", "compute_pipelines")):
                    raise RuntimeError(
                        "warm workspace sample created GPU job resources after capacity "
                        f"priming {primer_counts}: {response}"
                    )
                raw_samples.append(
                    sample_from_response(index, wall_ms, response, case)
                )
                sample_requests.append(request)
                last_output = output
        finally:
            daemon.shutdown(job_timeout)
        commands = {
            "daemon_start": command_record(daemon_argv, ROOT),
            "capacity_primer_counts_by_seed": primer_counts,
            "before_each_sample": {"command": "clear-project-compiled-unit-cache"},
            "sample_compile_requests": sample_requests,
        }
        reused_standard_library = any(
            sample.get("compiled_unit_cache", {}).get("hits_during_job", 0) > 0
            for sample in raw_samples
        )
        semantics = {
            "process": "one daemon for primer and every measured sample",
            "daemon_started_before_timer": True,
            "gpu_workspace_preallocated": True,
            "compiled_unit_results_reused": reused_standard_library,
            "project_compiled_unit_results_reused": False,
            "standard_library_compiled_units_reused": reused_standard_library,
            "source_manifest_metadata_may_be_resident": True,
            "driver_shader_cache": "ambient machine state",
        }

    semantics["sample_programs"] = (
        "one distinct generated program per sample"
        if len({case.input_path for case in sample_cases}) > 1
        else "one generated program compiled repeatedly"
    )

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
        "validation": {
            "compile_exit_status": 0,
            "artifact_bytes": last_output.stat().st_size,
        },
    }


def sample_case_fields(case: WorkloadCase) -> dict:
    return {
        "seed": case.seed,
        "source_bytes": case.facts["bytes"],
        "source_sloc": case.facts["sloc"],
    }


def sample_from_response(
    index: int, wall_ms: float, response: dict, case: WorkloadCase
) -> dict:
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
        "recorded_compute_dispatches": response.get("recorded_compute_dispatches_during_job"),
        "compiled_unit_cache": response.get("compiled_unit_cache"),
        **sample_case_fields(case),
    }


def profile_daemon_job(
    mode: str,
    laniusc: Path,
    capacity_cases: list[WorkloadCase],
    primer_case: WorkloadCase | None,
    profile_case: WorkloadCase,
    target: str,
    artifact_dir: Path,
    startup_timeout: float,
    job_timeout: float,
) -> dict:
    if mode not in {"daemon_cold_workspace", "daemon_warm_workspace"}:
        raise ValueError(f"daemon profiling does not support mode {mode!r}")
    output = artifact_dir / f"profile-{mode}.{'wasm' if target == 'wasm' else 'bin'}"
    trace_path = artifact_dir / f"profile-{mode}-trace.json"
    env = os.environ.copy()
    env.update(
        {
            "LANIUS_PERFETTO_TRACE": str(trace_path),
            "LANIUS_GPU_COMPUTE_PASS_BREAKDOWN": "1",
            "LANIUS_GPU_BUFFER_BREAKDOWN": "1",
            "LANIUS_GPU_MEMORY_TIMELINE": "1",
            "LANIUS_COMPILER_GRAPH_BREAKDOWN": "1",
        }
    )
    daemon = Daemon(
        daemon_command(laniusc, target),
        ROOT,
        env,
        startup_timeout,
        artifact_dir / f"profile-{mode}.stderr",
    )
    try:
        if mode == "daemon_warm_workspace":
            for case in [*capacity_cases, *([primer_case] if primer_case else [])]:
                prime_workspace_until_stable(
                    daemon,
                    case.input_path,
                    case.source_root,
                    target,
                    output,
                    job_timeout,
                    f"profile-primer-{case.seed}",
                )
        clear_command = (
            "clear-project-compiled-unit-cache"
            if mode == "daemon_warm_workspace"
            else "clear-compiled-unit-cache"
        )
        daemon.request({"id": "profile-clear", "command": clear_command}, job_timeout)
        wall_ms, response = daemon.request(
            compile_request(
                "profile",
                profile_case.input_path,
                profile_case.source_root,
                target,
                output,
            ),
            job_timeout,
        )
    finally:
        daemon.shutdown(job_timeout)
    trace = json.loads(trace_path.read_text())
    timeline = profile_timeline(trace, "daemon.job.profile")
    compiler_graphs = response.pop("compiler_graphs", [])
    compute_submissions = response.pop("recorded_compute_submission_schedule", [])
    response.pop("recorded_compute_pass_breakdown", None)
    graph = execution_graph(compiler_graphs, compute_submissions)
    require_complete_execution_graph(graph)
    memory_timeline = profile_gpu_memory_timeline(
        response, graph, compute_submissions, timeline
    )
    tracked_gpu_buffers = response.get("tracked_gpu_buffers")
    if isinstance(tracked_gpu_buffers, dict):
        tracked_gpu_buffers.pop("residency_timeline", None)
    return {
        "excluded_from_timing_statistics": True,
        "reason": "named pass accounting and tracing add measurement overhead",
        "wall_ms": wall_ms,
        "response": response,
        "sample": sample_case_fields(profile_case),
        "timeline": timeline,
        "gpu_memory_timeline": memory_timeline,
        "execution_graph": graph,
        "trace_path": str(trace_path.relative_to(ROOT)),
    }


def profile_gpu_memory_timeline(
    response: dict,
    graph: dict,
    compute_submissions: list[dict],
    timeline: list[dict],
) -> dict:
    """Align physical residency and graph-managed live ranges to the job clock."""
    tracked = response.get("tracked_gpu_buffers", {})
    residency = tracked.get("residency_timeline", {}) if isinstance(tracked, dict) else {}
    load_ms = float(response.get("load_ms", 0.0) or 0.0)
    physical_points = []
    for point in residency.get("points", []):
        if not isinstance(point, dict):
            continue
        physical_points.append(
            {
                **point,
                "start_ms": (
                    0.0
                    if point.get("event") == "baseline"
                    else load_ms + float(point.get("elapsed_ms", 0.0) or 0.0)
                ),
            }
        )

    nodes_by_submission: dict[int, list[dict]] = {}
    for node in graph.get("nodes", []):
        if node.get("kind") != "declared_operation":
            continue
        for submission in node.get("submissions", []):
            nodes_by_submission.setdefault(int(submission), []).append(node)

    gpu_events = [
        event for event in timeline
        if event.get("execution_domain") == "gpu_execution"
    ]
    queue_events = [
        event for event in timeline
        if event.get("execution_domain") == "queue_submission"
    ]
    queue_cursor = 0
    working_set_intervals = []
    matched_submissions = 0
    for fallback_index, submission in enumerate(compute_submissions):
        if not isinstance(submission, dict):
            continue
        submission_index = int(submission.get("index", fallback_index))
        submission_label = str(submission.get("label", f"submit {submission_index}"))
        queue_index = next(
            (
                index for index in range(queue_cursor, len(queue_events))
                if queue_events[index].get("name") == submission_label
            ),
            None,
        )
        matched_events = []
        if queue_index is not None:
            matched_submissions += 1
            queue_cursor = queue_index + 1
            window_start = float(queue_events[queue_index]["start_ms"])
            window_end = (
                float(queue_events[queue_index + 1]["start_ms"])
                if queue_index + 1 < len(queue_events)
                else float("inf")
            )
            matched_events = [
                event for event in gpu_events
                if window_start <= float(event["start_ms"]) < window_end
            ]
        if not matched_events:
            pass_names = {
                name for name in submission.get("passes", []) if isinstance(name, str)
            }
            matched_events = [event for event in gpu_events if event.get("name") in pass_names]
        graph_nodes = nodes_by_submission.get(submission_index, [])
        working_set_bytes = max(
            (
                int(node.get("graph_managed_working_set_bytes", 0) or 0)
                for node in graph_nodes
            ),
            default=0,
        )
        if not matched_events or working_set_bytes <= 0:
            continue
        start_ms = min(float(event["start_ms"]) for event in matched_events)
        end_ms = max(
            float(event["start_ms"]) + float(event["duration_ms"])
            for event in matched_events
        )
        working_set_intervals.append(
            {
                "submission": submission_index,
                "label": submission_label,
                "start_ms": start_ms,
                "duration_ms": max(0.0, end_ms - start_ms),
                "bytes": working_set_bytes,
                "operation_count": len(graph_nodes),
                "phases": sorted(
                    {
                        str(node.get("phase"))
                        for node in graph_nodes
                        if node.get("phase")
                    }
                ),
            }
        )

    return {
        "physical_residency": {
            "semantics": residency.get(
                "semantics",
                "exact tracked physical LaniusBuffer residency after each allocation or final release",
            ),
            "points": physical_points,
        },
        "graph_managed_working_set": {
            "semantics": (
                "maximum deduplicated byte ranges live in the compiler graph during each "
                "GPU submission, aligned by its queue-submit marker; immutable inputs and "
                "externally owned resources are excluded"
            ),
            "intervals": working_set_intervals,
            "matched_submissions": matched_submissions,
            "recorded_submissions": len(compute_submissions),
        },
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
        row = {
            "name": event.get("name", "<unnamed>"),
            "category": event.get("cat", ""),
            "lane": lane_by_tid.get(event.get("tid"), str(event.get("tid"))),
            "start_ms": (event_start - start) / 1000.0,
            "duration_ms": event_duration / 1000.0,
        }
        annotate_timeline_event(row)
        rows.append(row)
    rows.sort(key=lambda row: (row["start_ms"], row["lane"], row["name"]))
    return rows


def execution_graph(
    compiler_graphs: list[dict],
    compute_submissions: list[dict],
) -> dict:
    executed: dict[str, int] = {}
    for submission in compute_submissions:
        if not isinstance(submission, dict):
            continue
        for operation in submission.get("operations", []):
            if isinstance(operation, str):
                executed[operation] = executed.get(operation, 0) + 1
    definitions = []
    definitions_by_name: dict[str, list[dict]] = {}
    for graph in compiler_graphs:
        label = graph["label"]
        for node in graph.get("nodes", []):
            if executed.get(node["name"], 0) == 0:
                continue
            definition = {"graph": label, **node}
            definitions.append(definition)
            definitions_by_name.setdefault(node["name"], []).append(definition)

    raw_submissions = []
    occurrence_counts: dict[tuple[str, int, int], int] = {}
    first_positions: dict[tuple[str, int, int], int] = {}
    for submission in compute_submissions:
        if not isinstance(submission, dict) or not isinstance(submission.get("passes"), list):
            continue
        submit_index = len(raw_submissions)
        pass_names = [name for name in submission["passes"] if isinstance(name, str)]
        operation_names = [
            name for name in submission.get("operations", []) if isinstance(name, str)
        ]
        raw_submissions.append(
            {
                "index": submit_index,
                "label": str(submission.get("label", f"submit {submit_index}")),
                "passes": pass_names,
                "operations": operation_names,
            }
        )
        for position, operation_name in enumerate(operation_names):
            for definition in definitions_by_name.get(operation_name, []):
                key = (definition["graph"], definition["id"], submit_index)
                occurrence_counts[key] = occurrence_counts.get(key, 0) + 1
                first_positions.setdefault(key, position)

    nodes = []
    node_ids: dict[tuple[str, int, int | None], str] = {}
    node_ids_by_submission_and_name: dict[tuple[int, str], list[str]] = {}
    for definition in definitions:
        scheduled = 0
        for submission in raw_submissions:
            submit_index = submission["index"]
            key = (definition["graph"], definition["id"], submit_index)
            execution_count = occurrence_counts.get(key, 0)
            if execution_count == 0:
                continue
            scheduled += execution_count
            node_id = f"{definition['graph']}:{definition['id']}@{submit_index}"
            node_ids[(definition["graph"], definition["id"], submit_index)] = node_id
            node_ids_by_submission_and_name.setdefault(
                (submit_index, definition["name"]), []
            ).append(node_id)
            nodes.append(
                {
                    "id": node_id,
                    "kind": "declared_operation",
                    "graph": definition["graph"],
                    "name": definition["name"],
                    "phase": definition["phase"],
                    "dispatch_domain": definition["dispatch_domain"],
                    "graph_managed_working_set_bytes": definition.get(
                        "graph_managed_working_set_bytes"
                    ),
                    "declaration_index": definition["id"],
                    "execution_count": execution_count,
                    "submissions": [submit_index],
                }
            )
        if scheduled != executed.get(definition["name"], 0):
            raise ValueError(
                f"compiler operation {definition['name']!r} has executions outside a submission"
            )

    edges = []
    for graph in compiler_graphs:
        label = graph["label"]
        for edge in graph.get("edges", []):
            for submission_index in range(len(raw_submissions)):
                source = node_ids.get((label, edge["source"], submission_index))
                target = node_ids.get((label, edge["target"], submission_index))
                if source is None or target is None:
                    continue
                edges.append(
                    {
                        "source": source,
                        "target": target,
                        "kind": "resource_dependency",
                        "dependencies": edge.get("dependencies", []),
                    }
                )
    node_by_id = {node["id"]: node for node in nodes}
    normalized_submissions = []

    def add_schedule_endpoint(
        submit_index: int,
        role: str,
        pass_name: str,
        submission_label: str,
    ) -> str:
        node_id = f"submission:{submit_index}:{role}"
        nodes.append(
            {
                "id": node_id,
                "kind": "empty_submission" if role == "empty" else "recorded_pass_endpoint",
                "graph": "recorded_submission_schedule",
                "name": pass_name,
                "phase": "submission_schedule",
                "dispatch_domain": (
                    "command_submission" if role == "empty" else "recorded_compute_pass"
                ),
                "declaration_index": submit_index * 2 + (1 if role == "last" else 0),
                "execution_count": 1,
                "submissions": [submit_index],
                "submission_label": submission_label,
            }
        )
        node_by_id[node_id] = nodes[-1]
        return node_id

    for submission in raw_submissions:
        submit_index = submission["index"]
        submission_label = submission["label"]
        operation_names = submission["operations"]
        matched_operations = sum(
            1 for operation_name in operation_names
            if node_ids_by_submission_and_name.get((submit_index, operation_name))
        )
        if not operation_names:
            first_node = last_node = add_schedule_endpoint(
                submit_index,
                "empty",
                submission_label,
                submission_label,
            )
        else:
            first_matches = node_ids_by_submission_and_name.get(
                (submit_index, operation_names[0]), []
            )
            last_matches = node_ids_by_submission_and_name.get(
                (submit_index, operation_names[-1]), []
            )
            if first_matches:
                first_node = first_matches[0]
            else:
                role = "endpoint" if len(operation_names) == 1 or operation_names[0] == operation_names[-1] else "first"
                first_node = add_schedule_endpoint(
                    submit_index, role, operation_names[0], submission_label
                )
            if last_matches:
                last_node = last_matches[-1]
            elif len(operation_names) == 1 or operation_names[0] == operation_names[-1]:
                last_node = first_node
            else:
                last_node = add_schedule_endpoint(
                    submit_index, "last", operation_names[-1], submission_label
                )
        normalized_submissions.append(
            {
                "index": submit_index,
                "label": submission_label,
                "recorded_compute_passes": len(submission["passes"]),
                "recorded_operations": len(operation_names),
                "matched_operations": matched_operations,
                "first_node": first_node,
                "last_node": last_node,
            }
        )

    def add_order_edge(source: str, target: str, kind: str, submit_index: int) -> None:
        if source == target or any(
            edge["source"] == source and edge["target"] == target and edge["kind"] == kind
            for edge in edges
        ):
            return
        edges.append(
            {
                "source": source,
                "target": target,
                "kind": kind,
                "dependencies": [],
                "submission_index": submit_index,
            }
        )

    for submission in normalized_submissions:
        submit_index = submission["index"]
        declared = [
            node for node in nodes
            if node["kind"] == "declared_operation" and node["submissions"] == [submit_index]
        ]
        declared_ids = {node["id"] for node in declared}
        resource_edges = [
            edge for edge in edges
            if edge["kind"] == "resource_dependency"
            and edge["source"] in declared_ids
            and edge["target"] in declared_ids
        ]
        graph_order = sorted(
            {node["graph"] for node in declared},
            key=lambda graph_label: min(
                first_positions[(node["graph"], node["declaration_index"], submit_index)]
                for node in declared if node["graph"] == graph_label
            ),
        )
        stage_boundary_ids = set()
        for boundary_index, (previous_graph, following_graph) in enumerate(
            zip(graph_order, graph_order[1:])
        ):
            previous_ids = {node["id"] for node in declared if node["graph"] == previous_graph}
            following_ids = {node["id"] for node in declared if node["graph"] == following_graph}
            previous_sinks = previous_ids - {
                edge["source"] for edge in resource_edges if edge["source"] in previous_ids
            }
            following_roots = following_ids - {
                edge["target"] for edge in resource_edges if edge["target"] in following_ids
            }
            boundary_id = (
                f"stage_boundary:{submit_index}:{boundary_index}:"
                f"{previous_graph}->{following_graph}"
            )
            nodes.append(
                {
                    "id": boundary_id,
                    "kind": "stage_boundary",
                    "graph": "compiler_stage_order",
                    "name": f"{previous_graph} → {following_graph}",
                    "phase": "stage_boundary",
                    "dispatch_domain": "ordering_constraint",
                    "declaration_index": boundary_index,
                    "execution_count": 0,
                    "submissions": [submit_index],
                    "submission_label": submission["label"],
                    "from_graph": previous_graph,
                    "to_graph": following_graph,
                }
            )
            node_by_id[boundary_id] = nodes[-1]
            stage_boundary_ids.add(boundary_id)
            for source in sorted(previous_sinks):
                add_order_edge(source, boundary_id, "stage_order", submit_index)
            for target in sorted(following_roots):
                add_order_edge(boundary_id, target, "stage_order", submit_index)

        submission_graph_ids = declared_ids | stage_boundary_ids
        ordered_edges = [
            edge for edge in edges
            if edge["source"] in submission_graph_ids
            and edge["target"] in submission_graph_ids
        ]
        roots = submission_graph_ids - {edge["target"] for edge in ordered_edges}
        sinks = submission_graph_ids - {edge["source"] for edge in ordered_edges}
        first_node = submission["first_node"]
        last_node = submission["last_node"]
        if declared:
            for target in sorted(roots):
                add_order_edge(first_node, target, "submit_span", submit_index)
            for source in sorted(sinks):
                add_order_edge(source, last_node, "submit_span", submit_index)
        else:
            add_order_edge(first_node, last_node, "submit_span", submit_index)

    submit_edges: dict[tuple[str, str], list[dict]] = {}
    for previous, following in zip(normalized_submissions, normalized_submissions[1:]):
        source = previous["last_node"]
        target = following["first_node"]
        submit_edges.setdefault((source, target), []).append(
            {
                "from_index": previous["index"],
                "from_label": previous["label"],
                "to_index": following["index"],
                "to_label": following["label"],
            }
        )
    edges.extend(
        {
            "source": source,
            "target": target,
            "kind": "submit_order",
            "dependencies": [],
            "submission_boundaries": boundaries,
        }
        for (source, target), boundaries in submit_edges.items()
    )
    declared_names = {
        node["name"] for graph in compiler_graphs for node in graph.get("nodes", [])
    }
    executed_names = set(executed)
    return {
        "nodes": nodes,
        "edges": edges,
        "submissions": normalized_submissions,
        "coverage": {
            "declared_operations": sum(len(graph.get("nodes", [])) for graph in compiler_graphs),
            "executed_operation_labels": len(executed_names),
            "matched_operation_labels": len(declared_names & executed_names),
            "unregistered_operation_labels": len(executed_names - declared_names),
            "unregistered_operations": sorted(executed_names - declared_names),
            "declared_but_unexecuted_operations": sorted(declared_names - executed_names),
            "recorded_operations": sum(executed.values()),
            "matched_recorded_operations": sum(
                count for name, count in executed.items() if name in declared_names
            ),
            "recorded_compute_passes": sum(
                len(submission["passes"]) for submission in raw_submissions
            ),
            "submissions_without_operations": sum(
                not submission["operations"] for submission in raw_submissions
            ),
        },
        "semantics": (
            "one node per executed compiler operation per GPU submission, plus scheduling-only "
            "nodes for unregistered operation endpoints and explicit compiler-stage boundary junctions; "
            "resource hazards, submission spans, and adjacent submission boundaries form one "
            "topologically sorted DAG; physical WGPU compute-pass counts remain separate because "
            "one pass may batch multiple compiler operations"
        ),
    }


def require_complete_execution_graph(graph: dict) -> None:
    """Reject a production profile whose recorded work escapes the graph."""
    coverage = graph.get("coverage", {})
    recorded = coverage.get("recorded_operations")
    matched = coverage.get("matched_recorded_operations")
    unknown = coverage.get("unregistered_operations", [])
    empty_submissions = coverage.get("submissions_without_operations")
    issues = []
    if not isinstance(recorded, int) or not isinstance(matched, int):
        issues.append("operation coverage counters are missing")
    elif matched != recorded:
        issues.append(f"only {matched} of {recorded} recorded operations are graph-declared")
    if unknown:
        issues.append("unregistered operations: " + ", ".join(map(str, unknown)))
    if not isinstance(empty_submissions, int):
        issues.append("submission coverage counter is missing")
    elif empty_submissions:
        issues.append(f"{empty_submissions} GPU submissions contain no declared operations")
    if issues:
        raise RuntimeError("incomplete compiler-graph profile: " + "; ".join(issues))


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


def result_reference(relative_path: str, contents: bytes) -> str:
    digest = hashlib.sha256()
    digest.update(relative_path.encode("utf-8"))
    digest.update(b"\0")
    digest.update(contents)
    return digest.hexdigest()[:8]


def catalog_results(result_root: Path) -> Path:
    result_root.mkdir(parents=True, exist_ok=True)
    documents = []
    invalid = []
    for path in sorted(result_root.rglob("*.json")):
        if path.name == "catalog.json":
            continue
        try:
            relative_path = str(path.relative_to(ROOT))
            contents = path.read_bytes()
            document = json.loads(contents)
            validate_document(document)
            annotate_document_timeline(document)
            documents.append({
                "result_id": result_reference(relative_path, contents),
                "path": relative_path,
                "document": document,
            })
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
