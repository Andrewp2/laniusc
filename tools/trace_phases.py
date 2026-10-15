#!/usr/bin/env python3
"""Split one daemon job of a Lanius Perfetto trace into compile phases.

usage: tools/trace_phases.py TRACE [--job NAME] [--stderr FILE] [--primer NAME] [--top N]

TRACE is a LANIUS_PERFETTO_TRACE file. The job is the `daemon.job.NAME` span
(default: the last job). The job splits into:

  original compile  job start to the end of the first source-pack compile
                    (its compile.source-pack.finish.wasm_object stamp)
  replays           each later source-pack compile, one per monomorphization
                    replay run (from its record.parser_capacity_retry stamp to
                    its finish.wasm_object stamp)
  gaps              the time between replays and after the last one: generic
                    call discovery, program evidence, link

Each part's wall time is attributed to the innermost host span open at each
moment, with priority readback wait > submit > compiler stamp > lexer stamp.
Time under no host span is host work nobody instrumented, or the host idling on
the GPU; the GPU-busy column (the union of gpu.frontend pass spans) tells which.
Readbacks are grouped by phase: call inference, canonical rounds and so on.

--stderr reads the daemon's stderr and, with LANIUS_TRACE_CALL_INFERENCE=1, lists
the changed count of each call-inference round of the original compile. The
rounds of earlier jobs in the same stderr are skipped by counting their
`type_check.call_inference` readbacks, one per round.

CPU only. The analysis needs the host.* lanes (always traced) and, for GPU
busy time, the gpu.frontend lane.
"""

from __future__ import annotations

import argparse
import bisect
import collections
import json
import pathlib
import re
import sys

HOST_PRIORITY = {"host.readback": 0, "host.submit": 1, "host.compiler": 2, "host.lexer": 3}
NO_SPAN = "no host span"
FIRST_STAMP = "compile.source-pack.record.parser_capacity_retry"
LAST_STAMP = "compile.source-pack.finish.wasm_object"
ROUND = re.compile(r"\[typecheck\.call_inference\] round=(\d+) changed=(\d+)")


def load_trace(path: str):
    """(lane name by tid, complete spans) of a Chrome-JSON Perfetto trace."""
    trace = json.loads(pathlib.Path(path).read_text())
    events = trace["traceEvents"] if isinstance(trace, dict) else trace
    lanes = {e["tid"]: e.get("args", {}).get("name", str(e["tid"]))
             for e in events if e.get("ph") == "M" and e.get("name") == "thread_name"}
    return lanes, [e for e in events if e.get("ph") == "X"]


def readback_phase(name: str) -> str:
    if name == "type_check.call_inference":
        return "call inference"
    if "canonical" in name:
        return "canonical rounds"
    if name.startswith("generic call"):
        return "generic call discovery"
    if name.startswith("program "):
        return "program evidence"
    if name.startswith(("codegen", "x86", "lowering", "wasm")):
        return "codegen"
    if name.startswith(("parser", "lex")):
        return "parser"
    if name.startswith("semantic-interface"):
        return "semantic interface"
    if name.startswith("type_check"):
        return "type check (other)"
    return name


def gpu_group(name: str) -> str:
    parts = name.split(".")
    if parts[0] == "type_check" and len(parts) > 1:
        return "type_check." + parts[1]
    if parts[0].startswith(("hir", "tree", "brackets", "ll1", "parser")):
        return "parser/HIR"
    return parts[0]


class Job:
    def __init__(self, lanes: dict, spans: list, name: str | None):
        jobs = [e for e in spans if e["name"].startswith("daemon.job.")]
        if not jobs:
            raise SystemExit("no daemon.job.* span in the trace")
        by_name = {e["name"][len("daemon.job."):]: e for e in jobs}
        if name is None:
            job = max(jobs, key=lambda e: e["ts"])
        elif name in by_name:
            job = by_name[name]
        else:
            raise SystemExit(f"no daemon.job.{name} span; jobs: {', '.join(sorted(by_name))}")
        self.name = job["name"][len("daemon.job."):]
        self.start, self.end = job["ts"], job["ts"] + job["dur"]
        self.lanes = lanes
        inside = [e for e in spans if self.start <= e["ts"] <= self.end]
        self.host = sorted((e for e in inside if lanes.get(e["tid"]) in HOST_PRIORITY), key=lambda e: e["ts"])
        self.readbacks = [e for e in self.host if lanes[e["tid"]] == "host.readback"]
        self.gpu = sorted((e for e in inside if lanes.get(e["tid"]) == "gpu.frontend"), key=lambda e: e["ts"])
        self.gpu_starts = [e["ts"] for e in self.gpu]
        self.busy = merged(self.gpu)
        self.blocks = self._blocks()

    def _blocks(self) -> list[tuple[float, float]]:
        blocks, block_start = [], self.start
        for e in self.host:
            if self.lanes[e["tid"]] != "host.compiler":
                continue
            if e["name"] == FIRST_STAMP and block_start is None:
                block_start = e["ts"]
            elif e["name"] == LAST_STAMP and block_start is not None:
                blocks.append((block_start, e["ts"] + e["dur"]))
                block_start = None
        return blocks or [(self.start, self.end)]

    def gaps(self) -> list[tuple[float, float]]:
        edges = [t for block in self.blocks for t in block] + [self.end]
        return [(edges[i], edges[i + 1]) for i in range(1, len(edges) - 1, 2)]

    def partition(self, windows) -> dict[str, float]:
        """ms per innermost host span label over the windows (start, end), in us."""
        totals: dict[str, float] = collections.defaultdict(float)
        for start, end in windows:
            active = [e for e in self.host if e["ts"] < end and e["ts"] + e["dur"] > start]
            boundaries = sorted([(max(start, e["ts"]), 1, i) for i, e in enumerate(active)]
                                + [(min(end, e["ts"] + e["dur"]), 0, i) for i, e in enumerate(active)])
            open_spans: set[int] = set()
            cursor = start
            for point, opening, index in boundaries + [(end, 0, -1)]:
                if point > cursor:
                    totals[self._label(active, open_spans)] += (point - cursor) / 1000.0
                    cursor = point
                if index >= 0:
                    (open_spans.add if opening else open_spans.discard)(index)
        return totals

    def _label(self, active, open_spans) -> str:
        if not open_spans:
            return NO_SPAN
        best = active[min(open_spans, key=lambda i: (HOST_PRIORITY[self.lanes[active[i]["tid"]]], -active[i]["ts"]))]
        lane = self.lanes[best["tid"]]
        if lane == "host.readback":
            return "wait: " + readback_phase(best["name"])
        if lane == "host.submit":
            return "submit"
        return best["name"].replace("compile.source-pack.", "")

    def readback_rows(self, windows) -> dict[str, list[float]]:
        """phase -> [count, wait ms, GPU-busy ms during the waits]."""
        rows: dict[str, list[float]] = collections.defaultdict(lambda: [0, 0.0, 0.0])
        for start, end in windows:
            for e in self.readbacks:
                if start <= e["ts"] < end:
                    row = rows[readback_phase(e["name"])]
                    row[0] += 1
                    row[1] += e["dur"] / 1000.0
                    row[2] += busy_ms(self.busy, e["ts"], e["ts"] + e["dur"])
        return rows

    def gpu_rows(self, windows) -> dict[str, list[float]]:
        rows: dict[str, list[float]] = collections.defaultdict(lambda: [0, 0.0])
        for start, end in windows:
            for e in self.gpu[bisect.bisect_left(self.gpu_starts, start):bisect.bisect_left(self.gpu_starts, end)]:
                row = rows[gpu_group(e["name"])]
                row[0] += 1
                row[1] += e["dur"] / 1000.0
        return rows

    def gpu_busy(self, windows) -> float:
        return sum(busy_ms(self.busy, start, end) for start, end in windows)


def merged(gpu_spans) -> tuple[list[float], list[float]]:
    """The union of the spans as sorted disjoint intervals (starts, ends)."""
    starts: list[float] = []
    ends: list[float] = []
    for e in gpu_spans:
        a, b = e["ts"], e["ts"] + e["dur"]
        if ends and a <= ends[-1]:
            ends[-1] = max(ends[-1], b)
        else:
            starts.append(a)
            ends.append(b)
    return starts, ends


def busy_ms(intervals, left: float, right: float) -> float:
    starts, ends = intervals
    index = max(0, bisect.bisect_right(starts, left) - 1)
    total = 0.0
    while index < len(starts) and starts[index] < right:
        total += max(0.0, min(right, ends[index]) - max(left, starts[index]))
        index += 1
    return total / 1000.0


def inference_rounds(stderr: str, job: Job, spans: list) -> list[int]:
    """Changed counts of the original compile's call-inference rounds."""
    earlier = sum(1 for e in spans if job.lanes.get(e["tid"]) == "host.readback"
                  and e["name"] == "type_check.call_inference" and e["ts"] < job.start)
    mine = sum(1 for e in job.readbacks if e["name"] == "type_check.call_inference" and e["ts"] < job.blocks[0][1])
    changed = [int(m.group(2)) for m in map(ROUND.search, pathlib.Path(stderr).read_text(errors="replace").splitlines())
               if m]
    return changed[earlier:earlier + mine]


def wall(windows) -> float:
    return sum(end - start for start, end in windows) / 1000.0


def report(job: Job, rounds: list[int] | None, top: int) -> list[str]:
    original = [job.blocks[0]]
    replays = job.blocks[1:]
    gaps = job.gaps()
    lines = [f"job `{job.name}`: {wall([(job.start, job.end)]):.1f} ms; original compile {wall(original):.1f} ms, "
             f"{len(replays)} replays {wall(replays):.1f} ms, gaps {wall(gaps):.1f} ms"]
    parts = [("original compile", original, 1), (f"replays (per replay of {len(replays)})", replays, len(replays)),
             ("gaps: discovery, evidence, link (total)", gaps, 1)]
    for title, windows, per in parts:
        if not windows or wall(windows) == 0:
            continue
        lines.append("")
        lines.append(f"## {title}: {wall(windows) / per:.1f} ms wall, GPU busy {job.gpu_busy(windows) / per:.1f} ms")
        lines.append("time by innermost host span:")
        for label, ms in sorted(job.partition(windows).items(), key=lambda item: -item[1])[:top]:
            if ms / per >= 0.05:
                lines.append(f"  {ms / per:9.1f} ms  {label}")
        rows = job.readback_rows(windows)
        if rows:
            lines.append("readbacks (count x mean wait = total; GPU busy during the waits):")
            for label, (count, ms, busy) in sorted(rows.items(), key=lambda item: -item[1][1])[:top]:
                lines.append(f"  {count / per:7.1f} x {ms / count:6.2f} = {ms / per:8.1f} ms  (GPU busy {busy / per:7.1f})  {label}")
        gpu = job.gpu_rows(windows)
        if gpu:
            lines.append(f"GPU passes: {sum(c for c, _ in gpu.values()) / per:.0f}, "
                         f"{sum(ms for _, ms in gpu.values()) / per:.1f} ms; top groups:")
            for label, (count, ms) in sorted(gpu.items(), key=lambda item: -item[1][1])[:top]:
                lines.append(f"  {count / per:7.0f} passes {ms / per:8.1f} ms  {label}")
        if title == "original compile" and rounds:
            lines.append(f"call-inference rounds: {len(rounds)}, changed per round: {', '.join(map(str, rounds))}")
    return lines


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("trace")
    parser.add_argument("--job", help="daemon job id (default: the last job in the trace)")
    parser.add_argument("--stderr", help="the daemon's stderr, for LANIUS_TRACE_CALL_INFERENCE rounds")
    parser.add_argument("--top", type=int, default=15)
    args = parser.parse_args()
    lanes, spans = load_trace(args.trace)
    job = Job(lanes, spans, args.job)
    rounds = inference_rounds(args.stderr, job, spans) if args.stderr else None
    print("\n".join(report(job, rounds, args.top)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
