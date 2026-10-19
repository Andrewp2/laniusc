#!/usr/bin/env python3
"""GPU operation time of every daemon job in a perfetto trace, split by pass family.

usage: trace_job_split.py TRACE [TOP]

Prints each daemon.job.<id> span's wall time, its GPU operation sum and dispatch count, then
the TOP families by GPU time in the jobs after the first, one column per job. A family is the
first two dot parts of the operation name for lexer/parser/type_check/lir/artifact operations,
hir_* for HIR passes, parser.tree for tree/bracket/pack scans, else the first dot part.

The trace comes from a daemon run with per-operation GPU spans, for example
  python3 tools/workload_bench.py --laniusc PIN --out OUT --repeat 2 \\
    --env LANIUS_GPU_COMPUTE_PASS_BREAKDOWN=1 --env LANIUS_COMPILER_GRAPH_BREAKDOWN=1 \\
    --env LANIUS_PERFETTO_TRACE=OUT/trace.json W30K
Per-operation stamps split compute passes and inflate GPU time, so use these numbers to rank
and compare passes, not as compile times; untimed clears and resets are charged to the next
timed operation. tools/trace_gpu_idle.py splits the same jobs' GPU-idle time by host span.
"""
import collections, json, sys

t = json.load(open(sys.argv[1]))
ev = t["traceEvents"] if isinstance(t, dict) else t
xs = [e for e in ev if e.get("ph") == "X"]
jobs = sorted((e for e in xs if e["name"].startswith("daemon.job.")), key=lambda e: e["ts"])
top = int(sys.argv[2]) if len(sys.argv) > 2 else 25


def family(n):
    parts = n.split(".")
    if parts[0] in ("type_check", "lir", "artifact", "parser", "lexer") and len(parts) > 1:
        return ".".join(parts[:2])
    if n.startswith("hir_"):
        return "hir_*"
    if n.startswith(("tree_prefix", "brackets", "pack_")):
        return "parser.tree"
    return parts[0]


cols = []
for j in jobs:
    a, b = j["ts"], j["ts"] + j["dur"]
    inside = [e for e in xs if a <= e["ts"] < b and e is not j]
    g = collections.Counter()
    n = collections.Counter()
    for e in inside:
        if e.get("cat") == "gpu":
            g[family(e["name"])] += e["dur"] / 1000
            n[family(e["name"])] += 1
    cols.append((j["name"].removeprefix("daemon.job."), j["dur"] / 1000, g, n))
print("jobs:", " ".join(f"{c[0]}={c[1]:.1f}ms" for c in cols))
fams = collections.Counter()
for c in cols[1:]:
    fams.update(c[2])
head = f"{'family':28s}" + "".join(f"{c[0]:>14s}" for c in cols)
print(head)
print(f"{'GPU op sum':28s}" + "".join(f"{sum(c[2].values()):14.2f}" for c in cols))
print(f"{'dispatch count':28s}" + "".join(f"{sum(c[3].values()):14d}" for c in cols))
for f, _ in fams.most_common(top):
    print(f"{f[:28]:28s}" + "".join(f"{c[2].get(f, 0):9.2f} x{c[3].get(f, 0):<4d}" for c in cols))
