"""Canonical data model for reproducible Lanius compiler measurements."""

from __future__ import annotations

import datetime as dt
import json
import math
import os
import platform
import shlex
import statistics
import subprocess
from pathlib import Path
from typing import Iterable


SCHEMA = "lanius.performance-run.v1"
SLOC_POLICY = "nonblank physical lines excluding comment-only lines"
SOURCE_SUFFIXES = {".lani", ".c", ".h", ".cc", ".cpp", ".hpp", ".rs", ".zig", ".par"}


def command_record(argv: Iterable[str], cwd: Path, env: dict[str, str] | None = None) -> dict:
    argv = [str(part) for part in argv]
    selected_env = {
        key: value
        for key, value in sorted((env or {}).items())
        if os.environ.get(key) != value
    }
    return {
        "argv": argv,
        "cwd": str(cwd.resolve()),
        "environment_overrides": selected_env,
        "display": shlex.join(argv),
    }


def source_facts(paths: Iterable[Path], root: Path | None = None) -> dict:
    paths = sorted(path.resolve() for path in paths if path.suffix in SOURCE_SUFFIXES)
    if not paths:
        raise ValueError("source set is empty")
    root = (root or Path.cwd()).resolve()
    records = []
    total_bytes = 0
    total_lines = 0
    total_sloc = 0
    for path in paths:
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        lines = text.splitlines()
        sloc = count_sloc(lines)
        total_bytes += len(raw)
        total_lines += len(lines)
        total_sloc += sloc
        try:
            label = str(path.relative_to(root))
        except ValueError:
            label = str(path)
        records.append({"path": label, "bytes": len(raw), "lines": len(lines), "sloc": sloc})
    return {
        "files": len(records),
        "bytes": total_bytes,
        "kilobytes": total_bytes / 1_000.0,
        "megabytes": total_bytes / 1_000_000.0,
        "physical_lines": total_lines,
        "sloc": total_sloc,
        "sloc_policy": SLOC_POLICY,
        "largest_file_bytes": max(record["bytes"] for record in records),
        "file_records": records,
    }


def count_sloc(lines: Iterable[str]) -> int:
    in_block_comment = False
    count = 0
    for raw in lines:
        line = raw.strip()
        if not line:
            continue
        while line:
            if in_block_comment:
                end = line.find("*/")
                if end < 0:
                    line = ""
                    break
                in_block_comment = False
                line = line[end + 2 :].lstrip()
                continue
            if line.startswith("//"):
                line = ""
                break
            if line.startswith("/*"):
                in_block_comment = True
                line = line[2:].lstrip()
                continue
            count += 1
            break
    return count


def summarize(samples: list[dict], source: dict) -> dict:
    wall = [number(sample, "wall_ms") for sample in samples]
    compiler = [float(sample["compiler_ms"]) for sample in samples if sample.get("compiler_ms") is not None]
    summary = {
        "wall_ms": distribution(wall),
        "compiler_ms": distribution(compiler) if compiler else None,
        "median_bytes_per_second": statistics.median(
            float(sample.get("source_bytes", source["bytes"])) * 1000.0 / number(sample, "wall_ms")
            for sample in samples
        ),
        "median_sloc_per_second": statistics.median(
            float(sample.get("source_sloc", source["sloc"])) * 1000.0 / number(sample, "wall_ms")
            for sample in samples
        ),
    }
    return summary


def distribution(values: list[float]) -> dict:
    if not values or any(not math.isfinite(value) or value < 0 for value in values):
        raise ValueError("timing samples must be finite nonnegative numbers")
    ordered = sorted(values)
    median = statistics.median(ordered)
    return {
        "samples": len(ordered),
        "median": median,
        "mean": statistics.fmean(ordered),
        "mad": statistics.median(abs(value - median) for value in ordered),
        "minimum": ordered[0],
        "maximum": ordered[-1],
        "p95": percentile(ordered, 0.95),
        "histogram": histogram(ordered),
    }


def percentile(ordered: list[float], quantile: float) -> float:
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * quantile
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def histogram(values: list[float]) -> dict:
    low, high = values[0], values[-1]
    if low == high:
        return {"unit": "ms", "edges": [low, high], "counts": [len(values)]}
    bin_count = max(1, min(20, math.ceil(math.sqrt(len(values)))))
    width = (high - low) / bin_count
    counts = [0] * bin_count
    for value in values:
        index = min(bin_count - 1, int((value - low) / width))
        counts[index] += 1
    return {
        "unit": "ms",
        "edges": [low + width * index for index in range(bin_count + 1)],
        "counts": counts,
    }


def new_document(repo: Path, run_id: str, workload: dict, machine: dict | None = None) -> dict:
    return {
        "schema": SCHEMA,
        "run": {
            "id": run_id,
            "recorded_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "git_commit": command_output(["git", "rev-parse", "HEAD"], repo),
            "git_dirty": bool(command_output(["git", "status", "--porcelain"], repo)),
        },
        "machine": machine or machine_info(),
        "workload": workload,
        "measurements": [],
    }


def machine_info() -> dict:
    gpu = command_output(
        [
            "nvidia-smi",
            "--query-gpu=name,driver_version,memory.total",
            "--format=csv,noheader,nounits",
        ],
        Path.cwd(),
    )
    return {
        "platform": platform.platform(),
        "cpu": platform.processor(),
        "logical_cpus": os.cpu_count(),
        "gpu": gpu or None,
    }


def command_output(argv: list[str], cwd: Path) -> str:
    try:
        completed = subprocess.run(
            argv,
            cwd=cwd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return completed.stdout.strip()


def validate_document(document: dict) -> None:
    if document.get("schema") != SCHEMA:
        raise ValueError(f"expected schema {SCHEMA!r}")
    if not isinstance(document.get("measurements"), list) or not document["measurements"]:
        raise ValueError("performance result must contain at least one measurement")
    workload = document.get("workload")
    if not isinstance(workload, dict) or workload.get("kind") not in {
        "single_file",
        "typical_project",
    }:
        raise ValueError("workload.kind must be single_file or typical_project")
    ids = set()
    for measurement in document["measurements"]:
        measurement_id = measurement.get("id")
        if not isinstance(measurement_id, str) or not measurement_id or measurement_id in ids:
            raise ValueError("measurement ids must be unique nonempty strings")
        ids.add(measurement_id)
        source = measurement.get("source")
        if not isinstance(source, dict) or min(
            int(source.get("files", 0)), int(source.get("bytes", 0)), int(source.get("sloc", 0))
        ) <= 0:
            raise ValueError(f"measurement {measurement_id} has invalid source facts")
        samples = measurement.get("samples")
        if not isinstance(samples, list) or not samples:
            raise ValueError(f"measurement {measurement_id} has no raw samples")
        expected = summarize(samples, source)
        summary = measurement.get("summary")
        if not isinstance(summary, dict):
            raise ValueError(f"measurement {measurement_id} has no summary")
        if not math.isclose(
            summary["wall_ms"]["median"], expected["wall_ms"]["median"], rel_tol=1e-12
        ):
            raise ValueError(f"measurement {measurement_id} summary does not match samples")


def write_document(path: Path, document: dict) -> None:
    validate_document(document)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")


def number(document: dict, key: str) -> float:
    value = document.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"sample {key} must be numeric")
    return float(value)
