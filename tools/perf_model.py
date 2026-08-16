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
COMPACT_RECORD_ARRAYS = {
    "edges",
    "events",
    "file_records",
    "nodes",
    "passes",
    "phases",
    "stages",
    "submissions",
}


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
    legacy_keys = _keys_with_prefix(document, "legacy_")
    if legacy_keys:
        raise ValueError(f"canonical result contains obsolete metadata key {legacy_keys[0]!r}")
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
        profile = measurement.get("profile")
        if isinstance(profile, dict):
            validate_profile_storage(measurement_id, profile)
            if profile.get("execution_graph") is not None:
                validate_execution_graph(measurement_id, profile["execution_graph"])
            if profile.get("nsight") is not None:
                validate_nsight_profile(measurement_id, profile["nsight"])


def _keys_with_prefix(value: object, prefix: str) -> list[str]:
    matches = []
    if isinstance(value, dict):
        for key, child in value.items():
            if isinstance(key, str) and key.startswith(prefix):
                matches.append(key)
            matches.extend(_keys_with_prefix(child, prefix))
    elif isinstance(value, list):
        for child in value:
            matches.extend(_keys_with_prefix(child, prefix))
    return matches


def validate_profile_storage(measurement_id: str, profile: dict) -> None:
    response = profile.get("response")
    if isinstance(response, dict) and "recorded_compute_pass_breakdown" in response:
        raise ValueError(
            f"measurement {measurement_id} duplicates raw pass breakdown after graph normalization"
        )


def validate_execution_graph(measurement_id: str, graph: object) -> None:
    if not isinstance(graph, dict):
        raise ValueError(f"measurement {measurement_id} has an invalid execution graph")
    nodes = graph.get("nodes")
    edges = graph.get("edges")
    submissions = graph.get("submissions")
    coverage = graph.get("coverage")
    if (
        not isinstance(nodes, list)
        or not isinstance(edges, list)
        or not isinstance(submissions, list)
        or not isinstance(coverage, dict)
    ):
        raise ValueError(f"measurement {measurement_id} has an invalid execution graph")
    coverage_fields = (
        "declared_operations",
        "executed_labels",
        "matched_labels",
        "unregistered_executed_labels",
        "recorded_passes",
        "matched_recorded_passes",
    )
    if any(
        not isinstance(coverage.get(field), int) or coverage[field] < 0
        for field in coverage_fields
    ):
        raise ValueError(f"measurement {measurement_id} has invalid execution graph coverage")
    if coverage["matched_labels"] > len(nodes):
        raise ValueError(f"measurement {measurement_id} has inconsistent execution graph coverage")
    by_id = {node.get("id"): node for node in nodes if isinstance(node, dict)}
    if len(by_id) != len(nodes) or None in by_id:
        raise ValueError(f"measurement {measurement_id} has duplicate execution graph nodes")
    for node in nodes:
        node_kind = node.get("kind")
        if (
            node_kind
            not in {
                "declared_operation",
                "recorded_pass_endpoint",
                "empty_submission",
                "stage_boundary",
            }
            or not isinstance(node.get("graph"), str)
            or not isinstance(node.get("name"), str)
            or not isinstance(node.get("phase"), str)
            or not isinstance(node.get("dispatch_domain"), str)
            or not isinstance(node.get("declaration_index"), int)
            or not isinstance(node.get("execution_count"), int)
            or (node_kind == "stage_boundary" and node["execution_count"] != 0)
            or (node_kind != "stage_boundary" and node["execution_count"] <= 0)
            or not isinstance(node.get("submissions"), list)
            or any(not isinstance(index, int) or index < 0 for index in node["submissions"])
            or (
                node_kind == "stage_boundary"
                and (
                    not isinstance(node.get("from_graph"), str)
                    or not isinstance(node.get("to_graph"), str)
                    or len(node["submissions"]) != 1
                )
            )
        ):
            raise ValueError(f"measurement {measurement_id} has an invalid execution graph node")
    for expected_index, submission in enumerate(submissions):
        if (
            not isinstance(submission, dict)
            or submission.get("index") != expected_index
            or not isinstance(submission.get("label"), str)
            or not isinstance(submission.get("recorded_passes"), int)
            or not isinstance(submission.get("matched_passes"), int)
            or (
                submission.get("first_node") is not None
                and submission.get("first_node") not in by_id
            )
            or (
                submission.get("last_node") is not None
                and submission.get("last_node") not in by_id
            )
        ):
            raise ValueError(f"measurement {measurement_id} has an invalid compute submission")
    outgoing = {node_id: [] for node_id in by_id}
    indegree = {node_id: 0 for node_id in by_id}
    for edge in edges:
        if not isinstance(edge, dict) or edge.get("source") not in by_id or edge.get("target") not in by_id:
            raise ValueError(f"measurement {measurement_id} has an invalid execution graph edge")
        dependencies = edge.get("dependencies")
        if edge.get("kind") == "resource_dependency":
            if not isinstance(dependencies, list) or not dependencies or any(
                not isinstance(dependency, dict)
                or not isinstance(dependency.get("resource"), str)
                or dependency.get("hazard")
                not in {"read_after_write", "write_after_read", "write_after_write"}
                for dependency in dependencies
            ):
                raise ValueError(f"measurement {measurement_id} has an invalid graph dependency")
        elif edge.get("kind") == "submit_order":
            boundaries = edge.get("submission_boundaries")
            if dependencies != [] or not isinstance(boundaries, list) or not boundaries or any(
                not isinstance(boundary, dict)
                or boundary.get("to_index") != boundary.get("from_index", -2) + 1
                or not isinstance(boundary.get("from_label"), str)
                or not isinstance(boundary.get("to_label"), str)
                for boundary in boundaries
            ):
                raise ValueError(f"measurement {measurement_id} has an invalid submit edge")
        elif edge.get("kind") in {"stage_order", "submit_span"}:
            if (
                dependencies != []
                or not isinstance(edge.get("submission_index"), int)
                or edge["submission_index"] < 0
            ):
                raise ValueError(f"measurement {measurement_id} has an invalid execution-order edge")
        else:
            raise ValueError(f"measurement {measurement_id} has an unknown graph edge kind")
        outgoing[edge["source"]].append(edge["target"])
        indegree[edge["target"]] += 1
    ready = [node_id for node_id, count in indegree.items() if count == 0]
    visited = 0
    while ready:
        source = ready.pop()
        visited += 1
        for target in outgoing[source]:
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
    if visited != len(nodes):
        raise ValueError(f"measurement {measurement_id} execution graph contains a cycle")


def validate_nsight_profile(measurement_id: str, profile: object) -> None:
    if not isinstance(profile, dict) or profile.get("schema") != "lanius.nsight-gpu-profile.v1":
        raise ValueError(f"measurement {measurement_id} has an invalid Nsight profile schema")
    events = profile.get("events")
    passes = profile.get("passes")
    if not isinstance(events, list) or not events or not isinstance(passes, list) or not passes:
        raise ValueError(f"measurement {measurement_id} has an empty Nsight profile")
    if profile.get("event_count") != len(events) or profile.get("unique_pass_count") != len(passes):
        raise ValueError(f"measurement {measurement_id} has inconsistent Nsight counts")
    elapsed = 0.0
    for index, event in enumerate(events):
        if not isinstance(event, dict) or event.get("event_index") != index:
            raise ValueError(f"measurement {measurement_id} has unordered Nsight events")
        start = number(event, "gpu_start_ms")
        duration = number(event, "time_ms")
        if not math.isclose(start, elapsed, rel_tol=1e-12, abs_tol=1e-12):
            raise ValueError(f"measurement {measurement_id} has a discontinuous Nsight time axis")
        elapsed += duration
    if not math.isclose(
        number(profile, "labeled_gpu_time_ms"), elapsed, rel_tol=1e-12, abs_tol=1e-12
    ):
        raise ValueError(f"measurement {measurement_id} has inconsistent Nsight GPU time")


def write_document(path: Path, document: dict) -> None:
    validate_document(document)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(serialize_document(document))


def serialize_document(document: dict) -> str:
    """Keep canonical results reviewable without expanding every telemetry record."""
    return _render_json(document, 0, ()) + "\n"


def _render_json(value: object, level: int, path: tuple[str | int, ...]) -> str:
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for key in sorted(value):
            encoded_key = json.dumps(key, ensure_ascii=False)
            encoded_value = _render_json(value[key], level + 1, path + (key,))
            rows.append(f"{'  ' * (level + 1)}{encoded_key}: {encoded_value}")
        return "{\n" + ",\n".join(rows) + f"\n{'  ' * level}}}"
    if isinstance(value, list):
        if not value:
            return "[]"
        if path and path[-1] in COMPACT_RECORD_ARRAYS:
            rows = [
                f"{'  ' * (level + 1)}"
                + json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                for item in value
            ]
        else:
            rows = [
                f"{'  ' * (level + 1)}{_render_json(item, level + 1, path + (index,))}"
                for index, item in enumerate(value)
            ]
        return "[\n" + ",\n".join(rows) + f"\n{'  ' * level}]"
    return json.dumps(value, ensure_ascii=False, sort_keys=True)


def number(document: dict, key: str) -> float:
    value = document.get(key)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"sample {key} must be numeric")
    return float(value)
