"""Retain canonical timings and exact validation/provenance beside this driver."""

import json
import shutil
import sys
from pathlib import Path

repo = Path.cwd()
sys.path.insert(0, str(repo / "tools"))
from perf_model import command_record, new_document, source_facts, summarize, write_document

retained = Path(__file__).resolve().parent
results = repo / "target/stdlib-perf/scaling"
for size in (1_000_000, 4_000_000, 5_000_000):
    revisions = ("current",) if size == 1_000_000 else ("baseline", "current", "baseline-repeat", "current-repeat")
    for revision in revisions:
        name = f"{revision}-{size}"
        shutil.copy2(results / f"{name}.json", retained / f"{name}.json")
        shutil.copy2(results / f"{name}.validation.json", retained / f"{name}.validation.txt")
        shutil.copy2(results / f"{name}.log", retained / f"{name}.log")
    lanius = json.loads((results / f"current-{size}.json").read_text())
    external = results / f"external-{size}"
    raw = json.loads((external / "samples.json").read_text())["samples"]
    assert len(raw) == 15 and all(row["exit_status"] == 0 for row in raw)
    versions = json.loads((external / "versions.json").read_text())
    document = new_document(repo, f"stdlib-size-sweep-external-{size}", lanius["workload"])
    for language in ("c", "cpp", "rust", "zig", "tcc"):
        selected = [row for row in raw if row["language"] == language]
        assert len(selected) == 3 and {row["seed"] for row in selected} == {20, 21, 22}
        suffix = {"c": "c", "cpp": "cpp", "rust": "rs", "zig": "zig", "tcc": "c"}[language]
        source = repo / f"target/lanius-perf-workloads/single-file-custom-{size}-seed-20-x86_64/seed-21/{size}/scaling.{suffix}"
        facts = source_facts([source], repo)
        samples = [{"index": index, "seed": row["seed"], "wall_ms": row["wall_ms"],
                    "compiler_ms": row["compiler_ms"], "source_bytes": row["source_bytes"],
                    "source_sha256": row["source_sha256"], "output_sha256": row["output_sha256"]}
                   for index, row in enumerate(selected)]
        document["measurements"].append({
            "id": f"{language}-debug", "compiler": {"name": language, "version": versions[language]},
            "target": "x86_64", "configuration": selected[0]["lane"], "source": facts,
            "commands": {"sample_compile_commands": [command_record(row["command"], repo) for row in selected]},
            "measurement_semantics": {"process": "fresh compiler process per distinct seed",
                                      "debug_info": "disabled", "compiled_unit_results_reused": False},
            "samples": samples, "summary": summarize(samples, facts),
            "validation": {"artifacts_validated": True, "compile_exit_status": 0},
        })
    write_document(retained / f"external-{size}.json", document)
    for name in ("samples", "commands", "versions"):
        shutil.copy2(external / f"{name}.json", retained / f"external-{size}-{name}.txt")
    shutil.copy2(results / f"external-{size}.log", retained / f"external-{size}.log")
    for seed in (19, 20, 21, 22):
        manifest = repo / f"target/lanius-perf-workloads/single-file-custom-{size}-seed-20-x86_64/seed-{seed}/manifest.json"
        shutil.copy2(manifest, retained / f"manifest-{size}-{seed}.txt")
shutil.copy2(results / "current-8mb.log", retained / "unsupported-8mb.log")
print("Retained 12 canonical result documents and executable validation records")
