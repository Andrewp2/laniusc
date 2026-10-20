#!/usr/bin/env python3
"""Replay lanius_perf's daemon_warm_workspace priming and print each job's GPU resource creations.

usage: tools/prime_probe.py --laniusc BIN --out DIR [--env K=V]... [--stdlib-root DIR] SEED_ROOT

GPU work: run it inside a GPU hold (target/claude-work/bin/heavy --quiet).

SEED_ROOT holds seed-N/1000000/scaling.lani, as written by tools/lanius_perf.py for the
single-file-1mb preset (target/lanius-perf-workloads/single-file-1mb-x86_64). The order follows
lanius_perf: seeds 20..39 then 19, each primed until a job creates no buffer, bind group or
pipeline (at most 6 jobs), then seeds 20, 21 and 22 measured once each. Each job clears the
compiled-unit cache first. Each job prints its compile time and created buffers and bind groups,
grouped by the first three parts of their labels, which shows which owner keeps allocating after
priming. The daemon runs with LANIUS_GPU_RESOURCE_CREATION_BREAKDOWN=1 so the responses carry labels.
Responses go to DIR/jobs.jsonl and the daemon's stderr to DIR/daemon.stderr.
"""
from __future__ import annotations

import argparse
import collections
import ctypes
import json
import os
import pathlib
import select
import signal
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
PR_SET_PDEATHSIG = 1


def label_prefix(label: str, parts: int = 3) -> str:
    return ".".join(label.split(".")[:parts])


def group_creations(response: dict) -> tuple[collections.Counter, collections.Counter]:
    """(buffers, bind groups) created by a job, counted by label prefix."""
    breakdown = response.get("resource_creation_breakdown") or {}
    groups = []
    for kind in ("buffers", "bind_groups"):
        counter: collections.Counter = collections.Counter()
        for row in breakdown.get(kind, []):
            counter[label_prefix(row["label"])] += row["created"]
        groups.append(counter)
    return groups[0], groups[1]


def created_anything(response: dict) -> bool:
    created = response.get("resources_created_during_job", {})
    return any(created.get(k, 0) for k in ("buffers", "bind_groups", "compute_pipelines"))


def schedule() -> list[tuple[int, str, int]]:
    """(seed, tag, maximum jobs): the priming then the measured jobs."""
    return [(seed, "prime", 6) for seed in [*range(20, 40), 19]] + [(seed, "measure", 1) for seed in (20, 21, 22)]


class Daemon:
    def __init__(self, laniusc: str, stdlib_root: str, env: dict, out: pathlib.Path):
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        argv = [laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", stdlib_root,
                "--idle-buffer-timeout-ms", "0"]
        self.err = (out / "daemon.stderr").open("wb")
        self.proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.err, text=True,
                                     bufsize=1, env=env,
                                     preexec_fn=lambda: libc.prctl(PR_SET_PDEATHSIG, signal.SIGKILL))

    def read(self, timeout: float = 120):
        r, _, _ = select.select([self.proc.stdout], [], [], timeout)
        if not r:
            raise TimeoutError("daemon response timeout")
        line = self.proc.stdout.readline()
        if not line:
            raise RuntimeError(f"daemon exited {self.proc.poll()}")
        return json.loads(line)

    def request(self, req: dict) -> dict:
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        return self.read()

    def close(self):
        self.proc.stdin.close()
        try:
            self.proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.kill(self.proc.pid, signal.SIGKILL)
            self.proc.wait()
        self.err.close()


def main(argv) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--laniusc", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--stdlib-root", default=str(REPO / "stdlib"))
    ap.add_argument("root")
    a = ap.parse_args(argv)
    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LANIUS_GPU_RESOURCE_CREATION_BREAKDOWN="1",
               LANIUS_GPU_RESOURCE_CREATION_BREAKDOWN_LIMIT="5000")
    for kv in a.env:
        k, v = kv.split("=", 1)
        env[k] = v
    daemon = Daemon(a.laniusc, a.stdlib_root, env, out)
    n = 0
    try:
        daemon.read()
        with (out / "jobs.jsonl").open("w") as log:
            for seed, tag, limit in schedule():
                for k in range(1, limit + 1):
                    n += 1
                    daemon.request({"id": f"clear{n}", "command": "clear-compiled-unit-cache"})
                    src = pathlib.Path(a.root) / f"seed-{seed}" / "1000000" / "scaling.lani"
                    r = daemon.request({"id": f"j{n}", "command": "compile", "emit": "x86_64", "input": str(src),
                                        "output": str(out / "probe.bin")})
                    created = r.get("resources_created_during_job", {})
                    bufs, bgs = group_creations(r)
                    print(f"j{n} seed {seed} {tag}{k}: ok={r.get('ok')} {r.get('compile_ms', 0):.1f} ms "
                          f"buffers={created.get('buffers')} bind_groups={created.get('bind_groups')} "
                          f"{r.get('workspace_request_kind')}", flush=True)
                    if bufs:
                        print("   buffers: " + ", ".join(f"{p} x{c}" for p, c in bufs.most_common(12)), flush=True)
                    if bgs:
                        print("   bind groups: " + ", ".join(f"{p} x{c}" for p, c in bgs.most_common(12)), flush=True)
                    log.write(json.dumps({"seed": seed, "tag": f"{tag}{k}", "response": r}) + "\n")
                    if not created_anything(r):
                        break
    finally:
        daemon.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
