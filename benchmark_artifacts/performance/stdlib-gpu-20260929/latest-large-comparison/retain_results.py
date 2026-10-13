"""Retain the fresh 5 MB comparison in the existing performance result format."""

import hashlib
import json
import shutil
import statistics
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "tools"))
from perf_model import command_record, new_document, source_facts, summarize, write_document

retained = Path(__file__).resolve().parent
results = repo / "target/stdlib-perf/scaling"
gpu_documents, validations = [], []
for revision in ("latest-large-before", "latest-large-after"):
    name = f"{revision}-5000000"
    document = json.loads((results / f"{name}.json").read_text())
    rows = json.loads((results / f"{name}.validation.json").read_text())
    assert len(rows) == 15 and all(row["exit_status"] == 0 for row in rows)
    assert "efa9a254987c7afa" in document["measurements"][0]["compiler"]["version"]
    gpu_documents.append(document)
    validations.extend(rows)
    for suffix, destination in (("json", "json"), ("validation.json", "validation.txt"), ("log", "log")):
        shutil.copy2(results / f"{name}.{suffix}", retained / f"{name}.{destination}")
external = results / "latest-large-external-5000000"
raw = json.loads((external / "samples.json").read_text())["samples"]
assert len(raw) == 15 and all(row["exit_status"] == 0 for row in raw)
versions = json.loads((external / "versions.json").read_text())
document = new_document(repo, "stdlib-latest-large-external-5000000", gpu_documents[0]["workload"])
timings = []
gpu_median = statistics.median(sample["wall_ms"] for d in gpu_documents
                               for sample in d["measurements"][0]["samples"])
timings.append(f"lanius\t30\t{gpu_median:.6f}\t1.000000")
for language in ("c", "cpp", "rust", "zig", "tcc"):
    selected = [row for row in raw if row["language"] == language]
    assert len(selected) == 3 and {row["seed"] for row in selected} == {20, 21, 22}
    suffix = {"c": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "tcc": "c"}[language]
    source = repo / f"target/lanius-perf-workloads/single-file-custom-5000000-seed-20-x86_64/seed-21/5000000/scaling.{suffix}"
    facts = source_facts([source], repo)
    samples = [{"index": index, "seed": row["seed"], "wall_ms": row["wall_ms"],
                "compiler_ms": row["compiler_ms"], "source_bytes": row["source_bytes"],
                "source_sha256": row["source_sha256"], "output_sha256": row["output_sha256"]}
               for index, row in enumerate(selected)]
    summary = summarize(samples, facts)
    document["measurements"].append({
        "id": f"{language}-debug", "compiler": {"name": language, "version": versions[language]},
        "target": "x86_64", "configuration": selected[0]["lane"], "source": facts,
        "commands": {"sample_compile_commands": [command_record(row["command"], repo) for row in selected]},
        "measurement_semantics": {"process": "fresh compiler process per distinct seed",
                                  "debug_info": "disabled",
                                  "compiler_caches": "ambient machine state; CPU cache misses not instrumented"},
        "samples": samples, "summary": summary,
        "validation": {"artifacts_validated": True, "compile_exit_status": 0},
    })
    median = summary["wall_ms"]["median"]
    timings.append(f"{language}\t3\t{median:.6f}\t{median / gpu_median:.6f}")
write_document(retained / "external-5000000.json", document)
for name in ("samples", "commands", "versions"):
    shutil.copy2(external / f"{name}.json", retained / f"external-{name}.txt")
for part in (1, 2, 3):
    shutil.copy2(results / f"latest-large-external-5000000-part{part}.log", retained / f"external-part{part}.log")
selection = dict(line.split("=", 1) for line in (retained / "selection.txt").read_text().splitlines())
shaders = Path(selection["shaders"])
actual_hashes = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}\t{p.relative_to(shaders)}\n'
                        for p in sorted(shaders.rglob('*')) if p.is_file())
assert actual_hashes == (retained / "shader-sha256.tsv").read_text()
assert hashlib.sha256(Path(selection["compiler"]).read_bytes()).hexdigest() == selection["compiler_sha256"]
gpu_source_hashes = {row["seed"]: row["source_sha256"] for row in validations}
for seed in (20, 21, 22):
    matching = [row for row in validations if row["seed"] == seed]
    assert len({row["source_sha256"] for row in matching}) == 1
    assert len({row["output_sha256"] for row in matching}) == 1
    manifest = repo / f"target/lanius-perf-workloads/single-file-custom-5000000-seed-20-x86_64/seed-{seed}/manifest.json"
    shutil.copy2(manifest, retained / f"manifest-{seed}.txt")
(retained / "summary.tsv").write_text("compiler\tsamples\tmedian_wall_ms\tother_time_over_lanius\n" + "\n".join(timings) + "\n")
print("\n".join(timings))
print("All 45 measured executables passed; compiler and shader snapshots are unchanged.")
