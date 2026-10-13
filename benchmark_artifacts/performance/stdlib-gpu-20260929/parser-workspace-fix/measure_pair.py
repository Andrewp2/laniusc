"""Interleave full recompiles using two primed lanius_perf daemons.

Run from the worktree root: timeout 110s python3 PATH SIZE LABEL [--reverse]
Optional --previous-shaders and --fixed-shaders select preserved snapshots.
Both processes use the same compiler binary; the shader version is selected at startup.
"""

import argparse
import json
import random
import signal
import statistics
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "tools"))
from lanius_perf import (
    Daemon, WorkloadSpec, compile_request, daemon_command,
    prepare_workload, prime_workspace_until_stable, sample_from_response,
)
from perf_model import command_output, command_record, new_document, summarize, write_document
from run_compiler_stress_matrix import sha256_file, validate_executable


def interrupted(signum, frame):
    raise TimeoutError(f"benchmark interrupted by signal {signum}")


signal.signal(signal.SIGTERM, interrupted)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("size", type=int)
parser.add_argument("label")
parser.add_argument("--reverse", action="store_true")
parser.add_argument("--previous-shaders", default="pre-parser-shaders")
parser.add_argument("--fixed-shaders", default="parser-workspace-validated-shaders")
args = parser.parse_args()
size, label, reverse = args.size, args.label, args.reverse
spec = WorkloadSpec(kind="single_file", seeds=(20, 21, 22), sample_count=15,
                    target_bytes=size, profile="mixed-function-sizes", primer_seed=19)
_, workload, cases, primer, generation_commands = prepare_workload(spec, "x86_64")
workload["generation_commands"] = [command_record(command, repo) for command in generation_commands]
workload["sample_policy"] = "three distinct seeds, five recompiles per seed; alternating shader order per pair"
root = repo / f"target/stdlib-perf/scaling/{label}-{size}-paired"
root.mkdir(parents=True, exist_ok=True)
shader_root = repo / "target/stdlib-perf/build/laniusc-shader-artifacts/release/shaders"
snapshots = repo / "target/stdlib-perf/results"
compiler = repo / "target/release/laniusc"
argv = daemon_command(compiler, "x86_64")
states, validations, paired_ratios = {}, [], []
sample_cases = cases * 5
random.Random(0x1A9105).shuffle(sample_cases)


def select_shaders(name):
    assert shader_root.is_symlink(), shader_root
    snapshot = snapshots / name
    assert snapshot.is_dir(), snapshot
    shader_root.unlink()
    shader_root.symlink_to(snapshot)


try:
    versions = [("previous", args.previous_shaders), ("fixed", args.fixed_shaders)]
    if reverse:
        versions.reverse()
    for name, snapshot in versions:
        select_shaders(snapshot)
        version = command_output([str(compiler), "--version"], repo)
        daemon = Daemon(argv, repo, {}, 30, root / f"{name}.stderr")
        state = {"daemon": daemon, "version": version, "samples": [], "requests": [], "primers": {}}
        states[name] = state
        for case in [*cases, primer]:
            state["primers"][str(case.seed)] = prime_workspace_until_stable(
                daemon, case.input_path, case.source_root, "x86_64",
                root / f"{name}-primer-{case.seed}.bin", 30, f"primer-{case.seed}")
        print(f"{name}: primed all source shapes; {version.split('shader-artifact-digest:')[1].splitlines()[0].strip()}", flush=True)

    for index, case in enumerate(sample_cases):
        order = ("previous", "fixed") if index % 2 == 0 else ("fixed", "previous")
        if reverse:
            order = tuple(reversed(order))
        pair_hashes, pair_wall = {}, {}
        for order_index, name in enumerate(order):
            state = states[name]
            _, cleared = state["daemon"].request(
                {"id": f"clear-{index}", "command": "clear-project-compiled-unit-cache"}, 30)
            assert cleared.get("event") == "project-compiled-unit-cache-cleared", cleared
            output = root / f"{name}-{index}.bin"
            request = compile_request(f"measure-{index}", case.input_path, case.source_root, "x86_64", output)
            wall_ms, response = state["daemon"].request(request, 30)
            assert response.get("ok") is True, response
            assert response.get("compiled_unit_cache", {}).get("hits_during_job", 0) == 0, response
            assert not any(response.get("resources_created_during_job", {}).get(kind, 0)
                           for kind in ("buffers", "bind_groups", "compute_pipelines")), response
            sample = sample_from_response(index, wall_ms, response, case)
            sample["paired_order_index"] = order_index
            state["samples"].append(sample)
            state["requests"].append(request)
            manifest = json.loads((case.input_path.parents[1] / "manifest.json").read_text())["source_sets"][0]
            output.chmod(0o755)
            stdout = validate_executable(output, manifest["expected_stdout"])
            digest = sha256_file(output)
            validations.append({"pair_index": index, "order_index": order_index, "revision": name,
                                "seed": case.seed, "stdout": stdout, "exit_status": 0,
                                "source_sha256": sha256_file(case.input_path), "output_sha256": digest})
            pair_hashes[name], pair_wall[name] = digest, wall_ms
        assert pair_hashes["previous"] == pair_hashes["fixed"], pair_hashes
        paired_ratios.append(pair_wall["fixed"] / pair_wall["previous"])
        print(f"pair {index:02d} seed {case.seed}: previous {pair_wall['previous']:.3f} ms, fixed {pair_wall['fixed']:.3f} ms", flush=True)

    for name, state in states.items():
        measurement = {
            "id": "lanius-x86_64-daemon_warm_workspace", "compiler": {"name": "lanius", "version": state["version"]},
            "target": "x86_64", "configuration": "daemon_warm_workspace", "source": cases[1].facts,
            "commands": {"daemon_start": command_record(argv, repo), "capacity_primer_counts_by_seed": state["primers"],
                         "before_each_sample": {"command": "clear-project-compiled-unit-cache"},
                         "sample_compile_requests": state["requests"]},
            "measurement_semantics": {
                "process": "two separately primed daemons; alternate shader order within each paired source compile",
                "daemon_started_before_timer": True, "gpu_workspace_preallocated": True,
                "compiled_unit_results_reused": False, "project_compiled_unit_results_reused": False,
                "source_manifest_metadata_may_be_resident": True, "driver_shader_cache": "ambient machine state",
                "sample_programs": workload["sample_policy"], "simultaneously_resident_daemons": 2,
                "daemon_start_order": [name for name, _ in versions],
            },
            "samples": state["samples"], "summary": summarize(state["samples"], cases[1].facts),
            "daemon_ready_samples": [state["daemon"].ready],
            "validation": {"compile_exit_status": 0, "artifacts_validated": True,
                           "artifact_bytes": Path(state["requests"][-1]["output"]).stat().st_size},
        }
        document = new_document(repo, f"stdlib-shader-paired-{label}-{name}-{size}", workload)
        document["measurements"].append(measurement)
        write_document(root / f"{name}.json", document)
        print(f"{name} median: {measurement['summary']['wall_ms']['median']:.3f} ms", flush=True)
    (root / "validation.txt").write_text(json.dumps(validations, indent=2) + "\n")
    (root / "paired-ratios.txt").write_text(json.dumps(paired_ratios, indent=2) + "\n")
    print(f"Median paired change: {(statistics.median(paired_ratios) - 1) * 100:.2f}%; all 30 executables passed", flush=True)
finally:
    try:
        for state in states.values():
            try:
                state["daemon"].shutdown(10)
            except Exception as error:
                print(f"daemon cleanup failed: {error}", file=sys.stderr)
    finally:
        select_shaders("current-shaders")
