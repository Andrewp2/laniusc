#!/usr/bin/env python3
"""GPU busy, GPU idle and unspanned host time of one daemon job in a Lanius Perfetto trace.

usage: tools/job_timeline.py TRACE JOB [MIN_MS]

TRACE is a LANIUS_PERFETTO_TRACE file and JOB the id of its `daemon.job.JOB` span. Prints:
- wall, GPU busy (the union of cat=gpu spans) and GPU idle;
- GPU idle under host.submit spans, and under host.readback spans (map waits) not also under a
  submit, with their ratio to GPU busy: how much of the idle time submit and map latency explain;
- every interval of at least MIN_MS (default 0.5) under no host span (the host.* lanes other than
  host.daemon, and the specialization lane), with the spans just before and after it and how much
  of it the GPU was busy.

CPU only.
"""
from __future__ import annotations

import bisect
import json
import pathlib
import sys


def load(path: str):
    trace = json.loads(pathlib.Path(path).read_text())
    events = trace["traceEvents"] if isinstance(trace, dict) else trace
    lanes = {e["tid"]: e.get("args", {}).get("name", "") for e in events
             if e.get("ph") == "M" and e.get("name") == "thread_name"}
    return lanes, [e for e in events if e.get("ph") == "X"]


def union(items) -> list[list[float]]:
    out: list[list[float]] = []
    for s, e in sorted(items):
        if out and s <= out[-1][1]:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out


def overlap(intervals, s: float, e: float) -> float:
    starts = [x[0] for x in intervals]
    i = max(0, bisect.bisect_right(starts, s) - 1)
    total = 0.0
    while i < len(intervals) and intervals[i][0] < e:
        total += max(0.0, min(e, intervals[i][1]) - max(s, intervals[i][0]))
        i += 1
    return total


def is_host(lane: str) -> bool:
    return (lane.startswith("host.") and lane != "host.daemon") or lane == "specialization"


def analyze(lanes: dict, spans: list, job_name: str, min_ms: float = 0.5) -> dict:
    """Times in microseconds (trace units)."""
    job = next(e for e in spans if e["name"] == f"daemon.job.{job_name}")
    a, b = job["ts"], job["ts"] + job["dur"]

    def clip(e):
        return max(a, e["ts"]), min(b, e["ts"] + e["dur"])

    def lane_union(pred):
        return union(clip(e) for e in spans if pred(lanes.get(e["tid"], "")) and e is not job
                     and e["ts"] < b and e["ts"] + e["dur"] > a)

    gpu = union(clip(e) for e in spans if e.get("cat") == "gpu" and e["ts"] < b and e["ts"] + e["dur"] > a)
    busy = sum(e - s for s, e in gpu)
    idle = [[s, e] for s, e in zip([a] + [x[1] for x in gpu], [x[0] for x in gpu] + [b]) if e > s]
    submit = lane_union(lambda lane: lane == "host.submit")
    readback = lane_union(lambda lane: lane == "host.readback")
    host_any = lane_union(is_host)
    both = union([max(s1, s2), min(e1, e2)] for s1, e1 in submit for s2, e2 in readback if min(e1, e2) > max(s1, s2))
    idle_submit = sum(overlap(submit, s, e) for s, e in idle)
    idle_readback = sum(overlap(readback, s, e) - overlap(both, s, e) for s, e in idle)
    named = sorted((e for e in spans if is_host(lanes.get(e["tid"], "")) and a <= e["ts"] < b), key=lambda e: e["ts"])
    holes = []
    for s, e in zip([a] + [x[1] for x in host_any], [x[0] for x in host_any] + [b]):
        if e - s < min_ms * 1000:
            continue
        before = [x for x in named if x["ts"] + x["dur"] <= s + 1]
        after = [x for x in named if x["ts"] >= e - 1]
        holes.append({"start": s - a, "dur": e - s, "gpu_busy": overlap(gpu, s, e),
                      "after": before[-1]["name"] if before else "(job start)",
                      "before": after[0]["name"] if after else "(job end)"})
    return {"wall": b - a, "busy": busy, "submit": sum(e - s for s, e in submit), "idle_submit": idle_submit,
            "readback": sum(e - s for s, e in readback), "idle_readback": idle_readback, "holes": holes}


def report(name: str, r: dict, min_ms: float) -> list[str]:
    ms = 1000.0
    busy = r["busy"] or 1.0
    lines = [f"job {name}: wall {r['wall'] / ms:.1f} ms, GPU busy {r['busy'] / ms:.1f} ms, "
             f"GPU idle {(r['wall'] - r['busy']) / ms:.1f} ms",
             f"  submit spans {r['submit'] / ms:.1f} ms (GPU idle under them {r['idle_submit'] / ms:.1f} ms); "
             f"readback/map-wait spans {r['readback'] / ms:.1f} ms (GPU idle under them {r['idle_readback'] / ms:.1f} ms)",
             f"  (submit + map-wait GPU idle) / GPU busy = {(r['idle_submit'] + r['idle_readback']) / busy:.2f}; "
             f"all GPU idle / GPU busy = {(r['wall'] - r['busy']) / busy:.2f}",
             f"  intervals under no host span >= {min_ms} ms: {len(r['holes'])}, "
             f"{sum(h['dur'] for h in r['holes']) / ms:.1f} ms"]
    for h in r["holes"]:
        lines.append(f"   {h['start'] / ms:7.1f} +{h['dur'] / ms:6.2f} ms (GPU busy {h['gpu_busy'] / ms:5.2f})  "
                     f"after {h['after'][:55]}  before {h['before'][:55]}")
    return lines


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    min_ms = float(argv[2]) if len(argv) > 2 else 0.5
    lanes, spans = load(argv[0])
    print("\n".join(report(argv[1], analyze(lanes, spans, argv[1], min_ms), min_ms)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
