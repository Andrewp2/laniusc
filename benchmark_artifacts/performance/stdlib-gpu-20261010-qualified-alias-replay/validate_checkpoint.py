"""Validate retained inputs and execute every canonical benchmark output."""
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess
import sys

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
BASE = OUT.parent / "stdlib-gpu-20261010-imported-members"


def read(path):
    return json.loads(path.read_text())


def save(name, value):
    (OUT / name).write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


frozen = read(OUT / "frozen-inputs.json")
for name, expected in frozen["source"].items():
    assert digest(ROOT / name) == expected, name
shader_root = Path(frozen["shader_root"])
current_shaders = {
    str(p.relative_to(shader_root)): digest(p)
    for p in shader_root.rglob("*")
    if p.is_file() and (p.name.endswith(".spv") or p.name.endswith(".reflect.json"))
}
assert current_shaders == frozen["shader_artifacts"]

sys.path.insert(0, str(ROOT / "tools"))
from perf_model import validate_document
report = read(OUT / "canonical-1mb.json")
validate_document(report)
measurement = report["measurements"][0]
samples = measurement["samples"]
requests = measurement["commands"]["sample_compile_requests"]
assert len(samples) == len(requests) == 20
assert [sample["seed"] for sample in samples] == list(range(20, 40))
old_outputs = {row["seed"]: row for row in read(BASE / "canonical-1mb.validation.json")}
outputs = []
for sample, request in zip(samples, requests):
    source, output = Path(request["input"]), Path(request["output"])
    contract = read(source.parent.parent / "manifest.json")["source_sets"][0]
    assert sample["source_bytes"] == source.stat().st_size == 1_000_000
    assert digest(source) == contract["sources"]["lanius"]["sha256"]
    assert digest(source) == old_outputs[sample["seed"]]["source_sha256"]
    assert sample["compiled_unit_cache"]["hits_during_job"] == 0
    assert all(value == 0 for value in sample["resources_created"].values())
    assert output.read_bytes().startswith(b"\x7fELF")
    run = subprocess.run([str(output)], capture_output=True, timeout=5)
    assert run.returncode == 0, (sample["seed"], run.returncode)
    assert run.stdout == contract["expected_stdout"].encode(), sample["seed"]
    assert run.stderr == b"", sample["seed"]
    outputs.append({
        "seed": sample["seed"], "stdout": run.stdout.decode(),
        "source_sha256": digest(source), "output_sha256": digest(output),
        "exit_status": run.returncode,
    })
save("canonical-1mb.validation.json", outputs)

generic = (OUT / "generic-32.log").read_text()
assert "output_verified=true" in generic
assert "rebuild_entry=true warmups=3 iters=10" in generic
generic_median = float(re.search(r"median_ms=([\d.]+)", generic)[1])
before = read(OUT / "binary-identities-before-performance.json")
after = {name: digest(ROOT / name) for name in before}
old_shaders = read(BASE / "frozen-inputs.json")["shader_artifacts"]
shader_changes = [name for name, value in current_shaders.items() if old_shaders.get(name) != value]
version = subprocess.check_output([str(ROOT / "target/release/laniusc"), "--version"], text=True)
assert version == (OUT / "compiler-version.txt").read_text()

metadata = {
    "removed_shader_payloads": sorted(set(old_shaders) - set(current_shaders)),
    "source_count": len(frozen["source"]),
    "shader_payload_count": len(current_shaders),
    "frozen_sources_and_shaders_unchanged": True,
    "measured_binary_identities": after,
    "canonical_cli_rebuild_binary_transitions": {
        name: {"before": before[name], "after": value}
        for name, value in after.items() if before[name] != value
    },
    "shader_metadata": "\n".join(line for line in version.splitlines() if line.startswith("shader-")),
    "changed_spv": sum(name.endswith(".spv") for name in shader_changes),
    "changed_reflection": sum(name.endswith(".reflect.json") for name in shader_changes),
    "canonical_compiler_median_ms": statistics.median(s["compiler_ms"] for s in samples),
    "canonical_wall_median_ms": statistics.median(s["wall_ms"] for s in samples),
    "generic_32_median_ms": generic_median,
    "canonical_elf_count": len(outputs),
    "canonical_source_hashes_match_baseline": True,
    "canonical_seeds": [s["seed"] for s in samples],
    "canonical_source_bytes": 1_000_000,
    "canonical_cache_hits": 0,
    "canonical_resource_creations": 0,
    "recorded_compute_dispatches": sorted({s["recorded_compute_dispatches"] for s in samples}),
    "recorded_compute_passes": sorted({s["recorded_compute_passes"] for s in samples}),
    "tracked_live_bytes": sorted({s["gpu_memory"]["bytes"] for s in samples}),
    "tracked_allocations": sorted({s["gpu_memory"]["allocations"] for s in samples}),
    "excluded_raw_buffers": sorted({s["gpu_memory"]["untracked_allocations"] for s in samples}),
    "canonical_runner_status": "saved_report_then_existing_catalogue_list_get_exception",
    "generic_32_final_elf_verified": True,
    "generic_32_expected_stdout_sha256": digest(OUT / "generic-32.expected.txt"),
    "output_contracts_verified": 21,
}
save("checkpoint-metadata.json", metadata)
print(json.dumps({key: metadata[key] for key in [
    "source_count", "shader_payload_count", "changed_spv", "changed_reflection",
    "canonical_compiler_median_ms", "canonical_wall_median_ms", "generic_32_median_ms",
    "canonical_elf_count", "tracked_live_bytes", "tracked_allocations",
]}, indent=2))
