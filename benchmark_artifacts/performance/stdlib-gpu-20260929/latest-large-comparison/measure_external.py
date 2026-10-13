"""Bounded, resumable debug lanes using the existing compiler stress helpers.

Run from the worktree root: timeout 110s python3 PATH SIZE START STOP
The matching lanius_perf custom workload must already have been generated.
Each size uses seeds 20-22 and three fresh process invocations per compiler.
"""

import argparse
import json
import random
import statistics
import subprocess
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "tools"))
from run_compiler_stress_matrix import (
    compile_process,
    compiler_commands,
    materialize,
    sha256_bytes,
    sha256_file,
    validate_executable,
)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("size", type=int)
parser.add_argument("start", type=int)
parser.add_argument("stop", type=int)
parser.add_argument("--output-root", type=Path)
args = parser.parse_args()
size, start, stop = args.size, args.start, args.stop
root = args.output_root or repo / f"target/stdlib-perf/scaling/external-{size}"
root.mkdir(parents=True, exist_ok=True)
bins = root / "bin"
bins.mkdir(exist_ok=True)
corpus_root = repo / f"target/lanius-perf-workloads/single-file-custom-{size}-seed-20-x86_64"
templates = compiler_commands(repo)
(root / "commands.json").write_text(json.dumps(templates, indent=2) + "\n")
tasks = [(language, seed) for seed in range(20, 23) for language in ("c", "cpp", "rust", "zig", "tcc")]
random.Random(0x1A9105).shuffle(tasks)
sample_file = root / "samples.json"
rows = json.loads(sample_file.read_text())["samples"] if sample_file.exists() else []
version_file = root / "versions.json"
versions = json.loads(version_file.read_text()) if version_file.exists() else {}
for index in range(start, min(stop, len(tasks))):
    language, seed = tasks[index]
    if any(row["order"] == index for row in rows):
        continue
    lane = "default" if language == "tcc" else "o0"
    template = templates[lane][language]
    if language not in versions:
        flag = "version" if language == "zig" else "--version"
        version = subprocess.run([template[0], flag], capture_output=True, text=True, timeout=5)
        versions[language] = (version.stdout + version.stderr).strip()
        version_file.write_text(json.dumps(versions, indent=2) + "\n")
    suffix = {"c": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "tcc": "c"}[language]
    corpus = corpus_root / f"seed-{seed}"
    manifest = json.loads((corpus / "manifest.json").read_text())["source_sets"][0]
    source = corpus / str(size) / f"scaling.{suffix}"
    output = bins / f"{language}-{seed}"
    command = materialize(template, source, output)
    sample = compile_process(command, repo)
    stdout = validate_executable(output, manifest["expected_stdout"])
    rows.append({"order": index, "language": language, "lane": lane,
                 "seed": seed, "source_bytes": source.stat().st_size,
                 "source_sha256": sha256_file(source), "output_sha256": sha256_file(output),
                 "stdout_sha256": sha256_bytes(stdout.encode()), "exit_status": 0,
                 "command": command, **sample})
    sample_file.write_text(json.dumps({"samples": sorted(rows, key=lambda row: row["order"])}, indent=2) + "\n")
    print(f"{size} bytes, {index + 1}/15 {language}/{seed}: {sample['wall_ms']:.3f} ms, output verified", flush=True)
for language in ("c", "cpp", "rust", "zig", "tcc"):
    values = [row["wall_ms"] for row in rows if row["language"] == language]
    if values:
        print(f"{language}: {len(values)} samples, median {statistics.median(values):.3f} ms", flush=True)
