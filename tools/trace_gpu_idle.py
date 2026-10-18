#!/usr/bin/env python3
"""GPU busy and idle time of one daemon job in a perfetto trace, idle time split by host span.

usage: trace_gpu_idle.py TRACE JOB [MIN_GAP_MS] [TOP]

JOB is the daemon job id (the <id> of daemon.job.<id>, e.g. j3). GPU busy time is the union of
the job's GPU operation spans (cat "gpu"). Each idle gap of at least MIN_GAP_MS (default 0.3) is
charged to the innermost host span (cat "host") covering the gap's midpoint, or to "(no host
span)"; gaps at the job's start and end are marked. The TOP span names by idle time are printed.
A span that holds GPU-idle time is host work the GPU waits for: recording, packing, waiting on
nothing, or work outside any span.

Record the trace as tools/trace_job_split.py describes (per-operation GPU spans), and read the
busy time as an upper bound: the per-operation stamps inflate GPU time.
"""
import collections, json, sys

t = json.load(open(sys.argv[1]))
ev = t["traceEvents"] if isinstance(t, dict) else t
xs = [e for e in ev if e.get("ph") == "X"]
job = next(e for e in xs if e["name"] == f"daemon.job.{sys.argv[2]}")
min_gap = float(sys.argv[3]) * 1000 if len(sys.argv) > 3 else 300.0
top = int(sys.argv[4]) if len(sys.argv) > 4 else 30
a, b = job["ts"], job["ts"] + job["dur"]
gpu = sorted(((e["ts"], e["ts"] + e["dur"]) for e in xs if e.get("cat") == "gpu" and a <= e["ts"] < b))
host = [e for e in xs if e.get("cat") == "host" and a <= e["ts"] < b and e is not job]
busy, gaps, cur_s, cur_e = 0.0, [], None, None
for s, e in gpu:
    if cur_e is None:
        gaps.append((a, s))
        cur_s, cur_e = s, e
    elif s > cur_e:
        busy += cur_e - cur_s
        gaps.append((cur_e, s))
        cur_s, cur_e = s, e
    else:
        cur_e = max(cur_e, e)
if cur_e is not None:
    busy += cur_e - cur_s
    gaps.append((cur_e, b))
by = collections.Counter()
cnt = collections.Counter()
small = 0.0
for s, e in gaps:
    d = e - s
    if d < min_gap:
        small += d
        continue
    mid = (s + e) / 2
    cover = [h for h in host if h["ts"] <= mid < h["ts"] + h["dur"]]
    name = min(cover, key=lambda h: h["dur"])["name"] if cover else "(no host span)"
    if s == a:
        name = "(job start) " + name
    if e == b:
        name = "(job end) " + name
    by[name] += d / 1000
    cnt[name] += 1
print(f"job {sys.argv[2]}: wall {job['dur'] / 1000:.2f} ms, GPU busy {busy / 1000:.2f} ms, "
      f"idle {(job['dur'] - busy) / 1000:.2f} ms ({small / 1000:.2f} ms in gaps < {min_gap / 1000:.2f} ms)")
for n, v in by.most_common(top):
    print(f"  {n[:80]:80s} {v:8.2f} ms x{cnt[n]}")
