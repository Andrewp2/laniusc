"""Reuse lanius_perf's generator, workspace priming, and timed compile path.

Run from the worktree root: timeout 110s python3 PATH SIZE REVISION
The caller selects the compiled shader directory before starting this process.
"""

import argparse
import json
import random
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "tools"))
from lanius_perf import WorkloadSpec, measure_mode, prepare_workload
from perf_model import command_output, command_record, new_document, write_document
from run_compiler_stress_matrix import sha256_file, validate_executable

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("size", type=int)
parser.add_argument("revision")
parser.add_argument("--compiler", type=Path, default=repo / "target/release/laniusc")
args = parser.parse_args()
size, revision = args.size, args.revision
spec = WorkloadSpec(kind="single_file", seeds=(20, 21, 22), sample_count=15,
                    target_bytes=size, profile="mixed-function-sizes", primer_seed=19)
run_id, workload, cases, primer, generation_commands = prepare_workload(spec, "x86_64")
workload["generation_commands"] = [command_record(command, repo) for command in generation_commands]
workload["sample_policy"] = "three distinct seeds, five full recompiles per seed in deterministic randomized order"
artifact_dir = repo / f"target/stdlib-perf/scaling/{revision}-{size}-artifacts"
artifact_dir.mkdir(parents=True, exist_ok=True)
compiler = args.compiler.resolve()
version = command_output([str(compiler), "--version"], repo)
sample_cases = cases * 5
random.Random(0x1A9105).shuffle(sample_cases)
measurement = measure_mode("daemon_warm_workspace", compiler, version, sample_cases, cases,
                           primer, "x86_64", artifact_dir, cases[1].facts, 45, 30)
measurement["measurement_semantics"]["sample_programs"] = workload["sample_policy"]
validations = []
for sample, request in zip(measurement["samples"], measurement["commands"]["sample_compile_requests"], strict=True):
    source = Path(request["input"])
    manifest = json.loads((source.parents[1] / "manifest.json").read_text())["source_sets"][0]
    output = Path(request["output"])
    output.chmod(0o755)
    stdout = validate_executable(output, manifest["expected_stdout"])
    validations.append({"seed": sample["seed"], "stdout": stdout, "exit_status": 0,
                        "source_sha256": sha256_file(source), "output_sha256": sha256_file(output)})
measurement["validation"]["artifacts_validated"] = True
document = new_document(repo, f"stdlib-size-sweep-{revision}-{size}", workload)
document["measurements"].append(measurement)
output = repo / f"target/stdlib-perf/scaling/{revision}-{size}.json"
write_document(output, document)
output.with_suffix(".validation.json").write_text(json.dumps(validations, indent=2) + "\n")
print(f"{revision} {size} bytes: wall median {measurement['summary']['wall_ms']['median']:.3f} ms, 15 executable checks passed", flush=True)
print(next(line for line in version.splitlines() if line.startswith("shader-artifact-digest:")))
