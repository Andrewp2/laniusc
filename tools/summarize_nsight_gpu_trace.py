#!/usr/bin/env python3
"""Summarize tables exported by an Nsight Graphics GPU Trace."""

import csv
import json
import pathlib
import statistics
import sys


REGIME_METRICS = {
    "sm_throughput_pct": "GPUTrace.sm__throughput.avg.pct_of_peak_sustained_elapsed",
    "alu_throughput_pct": (
        "sm__inst_executed_pipe_alu_realtime.avg.pct_of_peak_sustained_elapsed"
    ),
    "fma_throughput_pct": (
        "SM_C.TriageSCG.smsp__inst_executed_pipe_fma.avg."
        "pct_of_peak_sustained_elapsed"
    ),
    "dram_throughput_pct": (
        "FBSP.TriageSCG.dramc__throughput.avg.pct_of_peak_sustained_elapsed"
    ),
    "dram_read_throughput_pct": (
        "FBSP.TriageSCG.dramc__read_throughput.avg.pct_of_peak_sustained_elapsed"
    ),
    "dram_write_throughput_pct": (
        "FBSP.TriageSCG.dramc__write_throughput.avg.pct_of_peak_sustained_elapsed"
    ),
    "l1_hit_rate_pct": "SM_B.TriageSCG.l1tex__t_sector_hit_rate.pct",
    "l2_hit_rate_pct": "LTS.TriageSCG.lts__average_t_sector_hit_rate_realtime.pct",
    "compute_warps_active_pct": (
        "tpc__warps_active_shader_cs_realtime.avg.pct_of_peak_sustained_elapsed"
    ),
    "average_compute_warp_latency": (
        "GPUTrace.PCSampler.tpc__average_warp_latency_shader_cs.ratio"
    ),
    "long_scoreboard_l1tex_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_long_scoreboard_pipe_l1tex."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "wait_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_wait."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "barrier_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_barrier."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "lg_throttle_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_lg_throttle."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "not_selected_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_not_selected."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "math_pipe_throttle_stall_pct": (
        "GPUTrace.PCSampler.tpc__warps_issue_stalled_math_pipe_throttle."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "register_allocation_stall_pct": (
        "tpc__warp_launch_cycles_stalled_shader_cs_reason_register_allocation."
        "avg.pct_of_peak_sustained_elapsed"
    ),
    "instructions_executed": "smsp__inst_executed.sum",
    "compute_warps_launched": "tpc__warps_launched_shader_cs.sum",
}

SUMMED_REGIME_METRICS = {"instructions_executed", "compute_warps_launched"}


def read_events(path: pathlib.Path) -> list[tuple[str, float]]:
    if not path.exists():
        return []
    rows = []
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        reader = csv.reader(stream, delimiter="\t")
        next(reader, None)
        for row in reader:
            if not row or not row[0].strip():
                continue
            values = []
            for value in row[1:]:
                try:
                    values.append(float(value))
                except ValueError:
                    pass
            if values:
                rows.append((row[0].strip(), max(values)))
    return rows


def summarize_passes(events: list[tuple[str, float]]) -> list[dict[str, object]]:
    grouped: dict[str, list[float]] = {}
    for name, milliseconds in events:
        grouped.setdefault(name, []).append(milliseconds)
    rows = []
    for name, values in grouped.items():
        rows.append(
            {
                "pass_name": name,
                "count": len(values),
                "total_time_ms": sum(values),
                "mean_time_ms": statistics.mean(values),
                "min_time_ms": min(values),
                "max_time_ms": max(values),
                "stddev_time_ms": statistics.pstdev(values) if len(values) > 1 else 0.0,
            }
        )
    return sorted(rows, key=lambda row: float(row["total_time_ms"]), reverse=True)


def compiler_phase(pass_name: str) -> str:
    if pass_name.startswith(("lexer.", "dfa_", "pair_")):
        return "lexer"
    if pass_name.startswith("type_check"):
        return "typecheck"
    if pass_name.startswith("codegen.x86"):
        return "x86_codegen"
    if pass_name.startswith("codegen.wasm"):
        return "wasm_codegen"
    if pass_name.startswith(("parser.", "hir_", "brackets_", "tree_", "pack_")):
        return "parser_hir"
    return "other"


def summarize_phases(events: list[tuple[str, float]]) -> list[dict[str, object]]:
    totals: dict[str, list[float]] = {}
    for name, milliseconds in events:
        phase = compiler_phase(name)
        row = totals.setdefault(phase, [0.0, 0.0])
        row[0] += 1
        row[1] += milliseconds
    total_ms = sum(row[1] for row in totals.values())
    return sorted(
        (
            {
                "phase": phase,
                "event_count": int(values[0]),
                "total_time_ms": values[1],
                "percent_of_labeled_time": 100.0 * values[1] / total_ms if total_ms else 0.0,
            }
            for phase, values in totals.items()
        ),
        key=lambda row: float(row["total_time_ms"]),
        reverse=True,
    )


def read_frame_metrics(path: pathlib.Path) -> dict[str, float]:
    metrics = {}
    if not path.exists():
        return metrics
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        for row in csv.reader(stream, delimiter="\t"):
            if len(row) < 2:
                continue
            try:
                metrics[row[0]] = float(row[1])
            except ValueError:
                pass
    return metrics


def read_regimes(path: pathlib.Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8", errors="replace", newline="") as stream:
        return list(csv.DictReader(stream, delimiter="\t"))


def correlate_regimes(
    events: list[tuple[str, float]], regimes: list[dict[str, str]]
) -> list[dict[str, object]]:
    if not regimes:
        return []
    if len(events) != len(regimes):
        raise ValueError(
            "D3DPERF_EVENTS.xls and GPUTRACE_REGIMES.xls have different row counts "
            f"({len(events)} != {len(regimes)})"
        )

    occurrences: dict[str, int] = {}
    rows = []
    for event_index, ((name, milliseconds), regime) in enumerate(zip(events, regimes)):
        regime_name = regime.get("flattened_event_name", "").strip()
        if regime_name != name:
            raise ValueError(
                "event/regime row mismatch at index "
                f"{event_index}: {name!r} != {regime_name!r}"
            )
        occurrence = occurrences.get(name, 0)
        occurrences[name] = occurrence + 1
        row: dict[str, object] = {
            "event_index": event_index,
            "pass_name": name,
            "occurrence": occurrence,
            "time_ms": milliseconds,
        }
        for alias, metric_name in REGIME_METRICS.items():
            try:
                row[alias] = float(regime[metric_name])
            except (KeyError, ValueError):
                row[alias] = None
        rows.append(row)
    return rows


def summarize_pass_metrics(events: list[dict[str, object]]) -> list[dict[str, object]]:
    grouped: dict[str, list[dict[str, object]]] = {}
    for event in events:
        grouped.setdefault(str(event["pass_name"]), []).append(event)

    rows = []
    for pass_name, pass_events in grouped.items():
        total_time_ms = sum(float(event["time_ms"]) for event in pass_events)
        row: dict[str, object] = {
            "pass_name": pass_name,
            "count": len(pass_events),
            "total_time_ms": total_time_ms,
        }
        for alias in REGIME_METRICS:
            values = [
                (float(event["time_ms"]), float(event[alias]))
                for event in pass_events
                if event[alias] is not None
            ]
            if not values:
                row[alias] = None
            elif alias in SUMMED_REGIME_METRICS:
                row[alias] = sum(value for _, value in values)
            else:
                weight = sum(milliseconds for milliseconds, _ in values)
                row[alias] = (
                    sum(milliseconds * value for milliseconds, value in values) / weight
                    if weight
                    else statistics.mean(value for _, value in values)
                )
        rows.append(row)
    return sorted(rows, key=lambda row: float(row["total_time_ms"]), reverse=True)


def write_csv(path: pathlib.Path, rows: list[dict[str, object]]) -> None:
    fieldnames = list(rows[0]) if rows else ["pass_name", "count", "total_time_ms"]
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: summarize_nsight_gpu_trace.py EXPORT_DIR", file=sys.stderr)
        return 2
    export_dir = pathlib.Path(sys.argv[1])
    events = read_events(export_dir / "D3DPERF_EVENTS.xls")
    passes = summarize_passes(events)
    phases = summarize_phases(events)
    metrics = read_frame_metrics(export_dir / "GPUTRACE_FRAME.xls")
    event_metrics = correlate_regimes(
        events, read_regimes(export_dir / "GPUTRACE_REGIMES.xls")
    )
    pass_metrics = summarize_pass_metrics(event_metrics)
    outputs = {
        export_dir / "PASS_SUMMARY.csv": passes,
        export_dir / "PASS_SUMMARY.json": passes,
        export_dir / "PHASE_SUMMARY.json": phases,
        export_dir / "FRAME_METRICS.json": metrics,
        export_dir / "EVENT_METRICS.csv": event_metrics,
        export_dir / "EVENT_METRICS.json": event_metrics,
        export_dir / "PASS_METRICS.csv": pass_metrics,
        export_dir / "PASS_METRICS.json": pass_metrics,
    }
    write_csv(export_dir / "PASS_SUMMARY.csv", passes)
    write_csv(export_dir / "EVENT_METRICS.csv", event_metrics)
    write_csv(export_dir / "PASS_METRICS.csv", pass_metrics)
    for path, value in outputs.items():
        if path.suffix == ".json":
            path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    for path in outputs:
        print(path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
