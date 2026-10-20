#!/usr/bin/env python3
"""Daemon startup: spawn to `ready`, then the first jobs, over several fresh daemons.

usage: tools/startup_bench.py --laniusc BIN --out DIR [--runs N] [--concurrent K] [--env K=V]...
                              [--job WORKLOAD_DIR]... [--ready-timeout S] [--job-timeout S]
                              [--stdlib-root DIR]

GPU work: run it inside a GPU hold (target/claude-work/bin/heavy --quiet).

Sequential mode (default): N daemons one after another. For each: the wall time from spawn to the
`ready` line (saved as DIR/runK.ready.json), then each --job workload (a directory with a
manifest.json: entry, optional source_root, expected_stdout, expected_exit_code) compiled once in
order, each executable run and checked against the manifest, then stdin is closed and the daemon
waited on (killed by PID after 30 s). Ends with a SUMMARY line: ready median and max, first-job median.

--concurrent K: spawn K daemons at once and report which became ready within --ready-timeout and
when; no jobs. A daemon still not ready at 4 s, at 10 s and at the timeout gets its threads dumped
(name, state, wchan, CPU ticks from /proc). Every daemon is killed by PID at the end.

--env K=V sets a daemon environment variable; `{tag}` in V becomes the run tag (run1, conc0 ...),
for example --env LANIUS_PERFETTO_TRACE=DIR/{tag}.json. Each daemon's stderr is DIR/TAG.stderr.
"""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import pathlib
import select
import signal
import statistics
import subprocess
import sys
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
PR_SET_PDEATHSIG = 1


def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--laniusc", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--concurrent", type=int, default=0)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--job", action="append", default=[])
    ap.add_argument("--ready-timeout", type=float, default=120.0)
    ap.add_argument("--job-timeout", type=float, default=100.0)
    ap.add_argument("--stdlib-root", default=str(REPO / "stdlib"))
    return ap.parse_args(argv)


def daemon_env(base: dict, pairs: list[str], tag: str) -> dict:
    env = dict(base)
    for kv in pairs:
        k, v = kv.split("=", 1)
        env[k] = v.replace("{tag}", tag)
    return env


def thread_states(pid: int) -> dict:
    """(thread name, state, wchan) -> [CPU ticks of each such thread], from /proc."""
    states: dict = {}
    for t in sorted(pathlib.Path(f"/proc/{pid}/task").iterdir()):
        try:
            name = (t / "comm").read_text().strip()
            wchan = (t / "wchan").read_text().strip()
            fields = (t / "stat").read_text().rsplit(")", 1)[1].split()
            state, cpu = fields[0], int(fields[11]) + int(fields[12])
        except OSError:
            continue
        states.setdefault((name, state, wchan), []).append(cpu)
    return states


def summary(readies: list[float], firsts: list[float]) -> str:
    line = (f"SUMMARY ready median {statistics.median(readies):.0f} ms max {max(readies):.0f} ms "
            f"{['%.0f' % x for x in readies]}")
    if firsts:
        line += f"; first job median {statistics.median(firsts):.1f} ms {['%.1f' % x for x in firsts]}"
    return line


class Bench:
    def __init__(self, a):
        self.a = a
        self.out = pathlib.Path(a.out)
        self.out.mkdir(parents=True, exist_ok=True)
        self.libc = ctypes.CDLL("libc.so.6", use_errno=True)

    def spawn(self, tag):
        a = self.a
        argv = [a.laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", a.stdlib_root,
                "--idle-buffer-timeout-ms", "0"]
        err = (self.out / f"{tag}.stderr").open("wb")
        t0 = time.perf_counter()
        proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True,
                                bufsize=1, env=daemon_env(os.environ, a.env, tag),
                                preexec_fn=lambda: self.libc.prctl(PR_SET_PDEATHSIG, signal.SIGKILL))
        return proc, t0, err

    @staticmethod
    def read(proc, timeout):
        r, _, _ = select.select([proc.stdout], [], [], timeout)
        if not r:
            raise TimeoutError("daemon response timeout")
        line = proc.stdout.readline()
        if not line:
            raise RuntimeError(f"daemon exited {proc.poll()}")
        return json.loads(line)

    @staticmethod
    def stop(proc):
        try:
            proc.stdin.close()
        except OSError:
            pass
        try:
            proc.wait(timeout=30)
        except subprocess.TimeoutExpired:
            os.kill(proc.pid, signal.SIGKILL)
            proc.wait()

    def compile_job(self, proc, tag, k, wl):
        w = pathlib.Path(wl).resolve()
        m = json.loads((w / "manifest.json").read_text())
        exe = self.out / f"{tag}-job{k}.bin"
        req = {"id": f"{tag}.j{k}", "command": "compile", "emit": "x86_64", "input": str(w / m["entry"]),
               "output": str(exe)}
        if m.get("source_root"):
            req["source_root"] = str(w / m["source_root"])
        s = time.perf_counter()
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()
        resp = self.read(proc, self.a.job_timeout)
        ms = (time.perf_counter() - s) * 1000
        verdict = "FAIL " + json.dumps(resp)[:300]
        if resp.get("ok"):
            r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
            good = r.stdout == m.get("expected_stdout") and r.returncode == m.get("expected_exit_code", 0)
            verdict = "output-ok" if good else f"OUTPUT-MISMATCH rc={r.returncode}"
        if exe.exists():
            exe.unlink()
        return ms, resp.get("compile_ms"), verdict, resp

    @staticmethod
    def dump_threads(i, proc, label):
        print(f"   daemon {i} pid {proc.pid} {label}:", flush=True)
        for (name, state, wchan), cpus in sorted(thread_states(proc.pid).items()):
            print(f"     threads {name!r} x{len(cpus)} state {state} wchan {wchan} cpu_ticks {sum(cpus)}", flush=True)

    def concurrent(self):
        a = self.a
        procs = [self.spawn(f"conc{i}") for i in range(a.concurrent)]
        pending = {p[0].stdout.fileno(): (i, p) for i, p in enumerate(procs)}
        start = time.perf_counter()
        deadline = start + a.ready_timeout
        probes = [4.0, 10.0]
        try:
            while pending and time.perf_counter() < deadline:
                r, _, _ = select.select([p[0].stdout for _, p in pending.values()], [], [], 0.5)
                for f in r:
                    i, (proc, t0, _) = pending.pop(f.fileno())
                    line = proc.stdout.readline()
                    ev = json.loads(line).get("event") if line else f"exited {proc.poll()}"
                    print(f"daemon {i} pid {proc.pid}: {ev} after {time.perf_counter() - t0:.2f} s", flush=True)
                if probes and time.perf_counter() - start >= probes[0]:
                    at = probes.pop(0)
                    for i, (proc, _, _) in pending.values():
                        if proc.poll() is None:
                            self.dump_threads(i, proc, f"not ready at {at:.0f} s")
            for i, (proc, _, _) in pending.values():
                print(f"daemon {i} pid {proc.pid}: NOT READY after {a.ready_timeout:.0f} s "
                      f"(alive={proc.poll() is None})", flush=True)
                if proc.poll() is None:
                    self.dump_threads(i, proc, "at the timeout")
        finally:
            for proc, _, err in procs:
                if proc.poll() is None:
                    os.kill(proc.pid, signal.SIGKILL)
                proc.wait()
                err.close()

    def sequential(self):
        a = self.a
        readies, firsts = [], []
        for run in range(1, a.runs + 1):
            tag = f"run{run}"
            proc, t0, err = self.spawn(tag)
            try:
                ready = self.read(proc, a.ready_timeout)
                ready_s = time.perf_counter() - t0
                (self.out / f"{tag}.ready.json").write_text(json.dumps(ready, indent=1))
                dc = ready.get("driver_shader_cache") or {}
                print(f"{tag}: ready {ready_s * 1000:.0f} ms (startup_ms {ready.get('startup_ms', 0):.0f}, "
                      f"pipelines {ready.get('compute_pipelines_created')}, pipeline_create_ms "
                      f"{dc.get('pipeline_create_ms', 0):.0f}, cache {dc.get('result')}, "
                      f"rss {ready.get('resident_set_bytes', 0) / 2**20:.0f} MiB)", flush=True)
                readies.append(ready_s * 1000)
                for k, wl in enumerate(a.job, 1):
                    ms, cms, verdict, resp = self.compile_job(proc, tag, k, wl)
                    with (self.out / f"{tag}.jobs.jsonl").open("a") as f:
                        f.write(json.dumps({"job": k, "workload": wl, "ms": ms, "response": resp}) + "\n")
                    print(f"  job{k} {pathlib.Path(wl).name}: {ms:.1f} ms (compile_ms {cms}) {verdict}", flush=True)
                    if k == 1:
                        firsts.append(ms)
            finally:
                self.stop(proc)
                err.close()
        if readies:
            print(summary(readies, firsts), flush=True)


def main(argv) -> int:
    a = parse_args(argv)
    bench = Bench(a)
    if a.concurrent:
        bench.concurrent()
    else:
        bench.sequential()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
