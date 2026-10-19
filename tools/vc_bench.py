#!/usr/bin/env python3
"""Warm compile of verified_compiler's compiler.lani (or --entry) in one daemon.

usage: vc_bench.py --laniusc BIN --out DIR [--src verified_compiler/src] [--entry compiler.lani]
                   [--repeat N] [--stdlib-root stdlib]

The source tree is copied to OUT/ws, so the checkout is never edited.

rep0, then N identical reps, then N edits. Edit k inserts `let p12_edit_k: i32 = k;`
as the first statement of one function body in the entry's import closure (a
different function and file each k, each edit from the pristine sources), so the
edited job changes one function body the way workload_bench's edits do. Outputs
are not run (vc has no expected stdout here); each job must report ok.
"""
import argparse
import ctypes
import json
import os
import pathlib
import re
import select
import shutil
import signal
import statistics
import subprocess
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("--laniusc", required=True)
ap.add_argument("--src", default=str(REPO / "verified_compiler" / "src"))
ap.add_argument("--out", required=True)
ap.add_argument("--entry", default="compiler.lani")
ap.add_argument("--repeat", type=int, default=5)
ap.add_argument("--timeout", type=float, default=300.0)
ap.add_argument("--stdlib-root", default=str(REPO / "stdlib"))
a = ap.parse_args()

out = pathlib.Path(a.out)
out.mkdir(parents=True, exist_ok=True)
ws = out / "ws"
if ws.exists():
    shutil.rmtree(ws)
shutil.copytree(a.src, ws)
entry = ws / a.entry

imp = re.compile(r"^\s*(?:pub\s+)?import\s+([A-Za-z_][\w:]*)", re.M)
seen, todo = [], [entry]
while todo:
    f = todo.pop()
    if f in seen:
        continue
    seen.append(f)
    for m in imp.finditer(f.read_text()):
        parts = m.group(1).split("::")
        for n in range(len(parts), 0, -1):
            cand = ws.joinpath(*parts[:n]).with_suffix(".lani")
            if cand.is_file():
                if cand not in seen:
                    todo.append(cand)
                break
closure = sorted(seen)
# Candidate edit sites: `fn name(...) ... {` lines at column 0 or 4 whose next line is not `}`.
fn_re = re.compile(r"^(    )?(pub )?fn \w+[^\n]*\{\s*$", re.M)
sites = []
for f in closure:
    text = f.read_text()
    for m in fn_re.finditer(text):
        sites.append((f, m.end()))
pristine = {}


def edit(k):
    f, at = sites[(k * 7919) % len(sites)]
    text = pristine.setdefault(f, f.read_text())
    f.write_text(text[:at] + f"\n        let p12_edit_{k}: i32 = {k};" + text[at:])
    return f"{f.relative_to(ws)}@{at}"


def restore():
    for f, text in pristine.items():
        f.write_text(text)


env = dict(os.environ)
env.setdefault("LANIUS_READBACK_TIMEOUT_MS", "60000")
argv = [a.laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", a.stdlib_root,
        "--idle-buffer-timeout-ms", "0"]
err = (out / "daemon.stderr").open("wb")
libc = ctypes.CDLL("libc.so.6", use_errno=True)
proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True,
                        bufsize=1, env=env, preexec_fn=lambda: libc.prctl(1, signal.SIGKILL))


def read(timeout):
    r, _, _ = select.select([proc.stdout], [], [], timeout)
    if not r:
        raise TimeoutError("daemon response timeout")
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError(f"daemon exited {proc.poll()}")
    return json.loads(line)


jobs = (out / "jobs.jsonl").open("w")
jid = 0


def job(label):
    global jid
    jid += 1
    exe = out / f"vc-{jid}.bin"
    req = {"id": f"j{jid}", "command": "compile", "emit": "x86_64", "input": str(entry),
           "output": str(exe), "source_root": str(ws)}
    s = time.perf_counter()
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    resp = read(a.timeout)
    ms = (time.perf_counter() - s) * 1000
    ok = bool(resp.get("ok"))
    size = exe.stat().st_size if exe.exists() else 0
    print(f"vc {label} {'ok' if ok else 'FAIL'} {ms:.1f}ms compile_ms={resp.get('compile_ms')} "
          f"bytes={size} disp={resp.get('recorded_compute_dispatches_during_job')} "
          f"rb={resp.get('readback_round_trips_during_job')} "
          + ("" if ok else json.dumps(resp)[:400]), flush=True)
    jobs.write(json.dumps({"job": label, "ms": ms, "ok": ok, "response": resp}) + "\n")
    jobs.flush()
    return ms, ok


try:
    print(f"ready: {read(600).get('event')}; closure {len(closure)} files, {len(sites)} edit sites", flush=True)
    job("rep0")
    ident = [job(f"identical{k}")[0] for k in range(1, a.repeat + 1)]
    edits = []
    try:
        for k in range(1, a.repeat + 1):
            restore()
            label = edit(k)
            edits.append(job(f"edit{k}[{label}]")[0])
    finally:
        restore()
    med = statistics.median
    print(f"SUMMARY vc: identical median {med(ident):.1f} ms {['%.1f' % x for x in ident]}, "
          f"first edit {edits[0]:.1f} ms, edit median {med(edits):.1f} ms {['%.1f' % x for x in edits]}",
          flush=True)
finally:
    try:
        proc.stdin.write(json.dumps({"id": "shutdown", "command": "shutdown"}) + "\n")
        proc.stdin.flush()
        proc.wait(timeout=30)
    except Exception:  # noqa: BLE001
        proc.kill()
        proc.wait()
    err.close()
