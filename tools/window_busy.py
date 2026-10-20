#!/usr/bin/env python3
"""GPU busy, readback wait and submit time inside windows of one daemon job in a Lanius Perfetto trace.

usage: tools/window_busy.py TRACE JOB NAME:START:END ...

START and END are ms from the start of the `daemon.job.JOB` span; find them with
tools/trace_phases.py or by reading the host.compiler and specialization lanes. For each window:
wall, GPU busy (the union of cat=gpu spans), readback wait (the union of host.readback spans, with
the number of readbacks that start in the window) and submit time. CPU only.
"""
from __future__ import annotations

import sys

from job_timeline import load, overlap, union


def windows(lanes: dict, spans: list, job_name: str, specs: list[str]) -> list[dict]:
    job = next(e for e in spans if e["name"] == f"daemon.job.{job_name}")
    gpu = union((e["ts"], e["ts"] + e["dur"]) for e in spans if e.get("cat") == "gpu")
    readbacks = [e for e in spans if lanes.get(e["tid"]) == "host.readback"]
    readback = union((e["ts"], e["ts"] + e["dur"]) for e in readbacks)
    submit = union((e["ts"], e["ts"] + e["dur"]) for e in spans if lanes.get(e["tid"]) == "host.submit")
    rows = []
    for spec in specs:
        name, start, end = spec.rsplit(":", 2)
        s = job["ts"] + float(start) * 1000
        e = job["ts"] + float(end) * 1000
        rows.append({"name": name, "wall": (e - s) / 1000, "gpu_busy": overlap(gpu, s, e) / 1000,
                     "readback": overlap(readback, s, e) / 1000,
                     "readbacks": sum(1 for r in readbacks if s <= r["ts"] < e),
                     "submit": overlap(submit, s, e) / 1000})
    return rows


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    lanes, spans = load(argv[0])
    for r in windows(lanes, spans, argv[1], argv[2:]):
        print(f"{r['name']:28s} wall {r['wall']:6.1f}  GPU busy {r['gpu_busy']:6.1f}  "
              f"readback wait {r['readback']:6.1f} ({r['readbacks']})  submit {r['submit']:5.1f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
