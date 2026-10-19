#!/usr/bin/env python3
"""Compile generated workloads in one warm daemon: identical reps, then one-function edits.

usage: workload_bench.py --laniusc BIN --out DIR [--repeat N] [--mode both|identical|edit]
                         [--stdlib-root DIR] [--env K=V ...] [--daemon-arg ARG ...] WORKLOAD_DIR...

Each WORKLOAD_DIR holds manifest.json and sources (tools/generate_generic_workload.py,
tools/generate_stdlib_workload.py, tools/generate_project_workload.py). The workload is copied
to OUT/ws/<name> so every job of a workload reads the same paths.

Per workload the daemon compiles:
  rep 0          the original sources (first compile of this workload in the daemon);
  identical 1..N the original sources again, byte for byte;
  edit 1..N      the original sources with one app function body changed.

Edit k picks the k-th module entry that main calls (`part = CALLEE(seed); print(part);`),
spread over main with a stride. Odd edits insert tokens: every `return EXPR;` in that
function's body becomes `return ((EXPR) + k) & 4095;`. Even edits delete tokens: the whole
body becomes `return V;`, V being the entry's printed value plus k (masked), when main calls
the entry once (otherwise the edit inserts). Each edit starts from the original sources, so
consecutive edit jobs differ in two function bodies (the previous edit is undone) and the
token count goes up and down from job to job. The printed line for that entry becomes
(old + k) & 4095 and the final total line is recomputed from the parts, so the expected
stdout stays exact. The edit needs main's `print(part)` / `total = (total + part) &
4095` shape, which all three generators write; other workloads (or `"run": false` ones) report
edit mode as unsupported.

The summary reports the first edit on its own as well as the edit median: the first edit after
a load is a user's common case, and it pays for whatever the identical reps left warm.

Daemon stderr goes to OUT/daemon.stderr; one line per job on stdout, then a summary per
workload, and every job as JSON in OUT/jobs.jsonl.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import pathlib
import re
import select
import shutil
import signal
import statistics
import subprocess
import sys
import time

MASK = 4095
CALL_RE = re.compile(r"^\s*part = ([A-Za-z_][A-Za-z0-9_:]*)\((.*)\);\s*$")
RETURN_RE = re.compile(r"^(\s*)return (.*);(\s*)$")


def fn_body_span(text: str, name: str):
    """(start, end) offsets of the body braces of `fn name(`, or None."""
    m = re.search(r"(?m)^\s*(?:pub\s+)?fn\s+" + re.escape(name) + r"\s*[<(]", text)
    if not m:
        return None
    open_at = text.find("{", m.end())
    if open_at < 0:
        return None
    depth = 0
    for i in range(open_at, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return open_at, i + 1
    return None


class EditPlan:
    """Where main's entries live and how stdout depends on them."""

    def __init__(self, workdir: pathlib.Path, manifest: dict):
        self.workdir = workdir
        self.manifest = manifest
        self.reason = None
        self.files: dict[pathlib.Path, str] = {}
        if manifest.get("run") is False or manifest.get("expected_stdout") is None:
            self.reason = "workload is not run (no expected stdout)"
            return
        entry = workdir / manifest["entry"]
        root = workdir / manifest["source_root"] if manifest.get("source_root") else None
        self.entry = entry
        self.root = root
        main_text = entry.read_text()
        span = fn_body_span(main_text, "main")
        if span is None:
            self.reason = "no fn main"
            return
        self.callees = []
        for line in main_text[span[0]:span[1]].split("\n"):
            m = CALL_RE.match(line)
            if m:
                self.callees.append(m.group(1))
        self.lines = [int(v) for v in manifest["expected_stdout"].split("\n") if v != ""]
        if not self.callees or len(self.lines) != len(self.callees) + 1:
            self.reason = f"main shape: {len(self.callees)} entry calls, {len(self.lines)} stdout lines"
            return
        if sum(self.lines[:-1]) & MASK != self.lines[-1]:
            self.reason = "last stdout line is not the masked sum of the parts"
            return

    def locate(self, callee: str):
        """(file, fn name) of a callee spelled as in main."""
        parts = callee.split("::")
        name = parts[-1]
        if len(parts) == 1:
            return self.entry, name
        module = "::".join(parts[:-1])
        candidates = []
        if self.root is not None:
            candidates.append(self.root / pathlib.Path(*parts[:-1]).with_suffix(".lani"))
            candidates += sorted(self.root.rglob("*.lani"))
        for path in candidates:
            if path.is_file() and re.search(r"(?m)^module\s+" + re.escape(module) + r"\s*;", path.read_text()):
                return path, name
        return None, name

    def edit(self, k: int):
        """Apply edit k (1-based) to the pristine sources; returns (files written, expected, label)."""
        n = len(self.callees)
        stride = 7 if n % 7 else 5
        index = ((k - 1) * stride + n // 2) % n
        callee = self.callees[index]
        path, name = self.locate(callee)
        if path is None:
            raise RuntimeError(f"cannot find the module of {callee}")
        text = self.pristine(path)
        span = fn_body_span(text, name)
        if span is None:
            raise RuntimeError(f"cannot find fn {name} in {path}")
        delta = k % MASK or 1
        parts = list(self.lines[:-1])
        if k % 2 == 0 and self.callees.count(callee) == 1:
            value = (parts[index] + delta) & MASK
            path.write_text(text[:span[0]] + f"{{\n    return {value};\n}}" + text[span[1]:])
            parts[index] = value
            label = f"{callee}={value}"
        else:
            body = text[span[0]:span[1]].split("\n")
            changed = 0
            for i, line in enumerate(body):
                m = RETURN_RE.match(line)
                if m:
                    body[i] = f"{m.group(1)}return (({m.group(2)}) + {delta}) & {MASK};{m.group(3)}"
                    changed += 1
            if not changed:
                raise RuntimeError(f"fn {name} has no single-line return to edit")
            path.write_text(text[:span[0]] + "\n".join(body) + text[span[1]:])
            for j, c in enumerate(self.callees):
                if c == callee:
                    parts[j] = (parts[j] + delta) & MASK
            label = f"{callee}+{delta}"
        expected = "".join(f"{v}\n" for v in parts + [sum(parts) & MASK])
        return [path], expected, label

    def pristine(self, path: pathlib.Path) -> str:
        if path not in self.files:
            self.files[path] = path.read_text()
        return self.files[path]

    def restore(self):
        for path, text in self.files.items():
            path.write_text(text)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--laniusc", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--repeat", type=int, default=3, help="warm reps per mode (after rep 0)")
    ap.add_argument("--mode", choices=["both", "identical", "edit"], default="both")
    ap.add_argument("--timeout", type=float, default=300.0)
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--daemon-arg", action="append", default=[])
    ap.add_argument("--stdlib-root", default=str(pathlib.Path(__file__).resolve().parents[1] / "stdlib"))
    ap.add_argument("workloads", nargs="+")
    a = ap.parse_args()

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    env.setdefault("LANIUS_READBACK_TIMEOUT_MS", "60000")
    for kv in a.env:
        k, v = kv.split("=", 1)
        env[k] = v
    argv = [a.laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", a.stdlib_root,
            "--idle-buffer-timeout-ms", "0"] + a.daemon_arg
    err = (out / "daemon.stderr").open("wb")
    libc = ctypes.CDLL("libc.so.6", use_errno=True)
    t0 = time.time()
    # PR_SET_PDEATHSIG: the daemon dies with this script, even when a timeout kills the script.
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

    try:
        ready = read(600)
    except BaseException:
        proc.kill()
        proc.wait()
        err.close()
        raise
    print(f"ready after {time.time() - t0:.1f}s: {ready.get('event')}", flush=True)
    jobs = (out / "jobs.jsonl").open("w")
    summaries = []
    jid = 0

    def run_job(w, m, workdir, label, expected):
        nonlocal jid
        jid += 1
        exe = out / f"{w.name}-{jid}.bin"
        req = {"id": f"j{jid}", "command": "compile", "emit": "x86_64", "input": str(workdir / m["entry"]),
               "output": str(exe)}
        if m.get("source_root"):
            req["source_root"] = str(workdir / m["source_root"])
        s = time.perf_counter()
        proc.stdin.write(json.dumps(req) + "\n")
        proc.stdin.flush()
        resp = read(a.timeout)
        ms = (time.perf_counter() - s) * 1000
        ok = bool(resp.get("ok"))
        if not ok:
            verdict = json.dumps(resp)[:600]
        elif expected is None:
            verdict = f"built {exe.stat().st_size if exe.exists() else 0} bytes (not run)"
        else:
            try:
                r = subprocess.run([str(exe)], capture_output=True, text=True, timeout=30)
                good = r.stdout == expected and r.returncode == m.get("expected_exit_code", 0)
                verdict = "output-ok" if good else f"OUTPUT-MISMATCH rc={r.returncode} got={r.stdout[:80]!r}"
                ok = ok and good
            except Exception as e:  # noqa: BLE001
                verdict = f"RUN-ERROR {e}"
                ok = False
        # The output's digest, so two runs can be compared byte for byte.
        digest = hashlib.sha256(exe.read_bytes()).hexdigest()[:16] if exe.exists() else None
        try:
            exe.unlink()
        except FileNotFoundError:
            pass
        print(f"{w.name} {label} {'ok' if resp.get('ok') else 'FAIL'} {ms:.1f}ms {verdict}", flush=True)
        jobs.write(json.dumps({"workload": w.name, "job": label, "ms": round(ms, 3), "ok": ok,
                               "verdict": verdict, "sha256": digest, "response": resp}) + "\n")
        jobs.flush()
        return ms, ok

    try:
        for wpath in a.workloads:
            w = pathlib.Path(wpath).resolve()
            m = json.loads((w / "manifest.json").read_text())
            workdir = out / "ws" / w.name
            if pathlib.Path(m["entry"]).is_absolute():
                workdir = pathlib.Path("/")  # sources outside the workload dir: compile in place
                m = dict(m, entry=m["entry"].lstrip("/"),
                         source_root=m["source_root"].lstrip("/") if m.get("source_root") else None)
            else:
                if workdir.exists():
                    shutil.rmtree(workdir)
                shutil.copytree(w, workdir)
            expected = m.get("expected_stdout") if m.get("run") is not False else None
            run_job(w, m, workdir, "rep0", expected)
            ident, edits, failures = [], [], 0
            if a.mode in ("both", "identical"):
                for k in range(1, a.repeat + 1):
                    ms, ok = run_job(w, m, workdir, f"identical{k}", expected)
                    ident.append(ms)
                    failures += not ok
            edit_note = ""
            if a.mode in ("both", "edit"):
                plan = EditPlan(workdir, m) if workdir != pathlib.Path("/") else None
                if plan is None or plan.reason:
                    edit_note = f"edit mode unsupported: {plan.reason if plan else 'sources outside the workload'}"
                    print(f"{w.name} {edit_note}", flush=True)
                else:
                    try:
                        for k in range(1, a.repeat + 1):
                            plan.restore()
                            _, exp, label = plan.edit(k)
                            ms, ok = run_job(w, m, workdir, f"edit{k}[{label}]", exp)
                            edits.append(ms)
                            failures += not ok
                    finally:
                        plan.restore()
            med = lambda xs: f"{statistics.median(xs):.1f}" if xs else "-"
            line = (f"SUMMARY {w.name}: identical median {med(ident)} ms {['%.1f' % x for x in ident]}, "
                    f"first edit {edits[0] if edits else float('nan'):.1f} ms, "
                    f"edit median {med(edits)} ms {['%.1f' % x for x in edits]}, failures={failures}"
                    + (f" ({edit_note})" if edit_note else ""))
            summaries.append(line)
    finally:
        try:
            proc.stdin.write(json.dumps({"id": "shutdown", "command": "shutdown"}) + "\n")
            proc.stdin.flush()
            proc.wait(timeout=30)
        except Exception:  # noqa: BLE001
            proc.kill()
            proc.wait()
        err.close()
        jobs.close()
    for line in summaries:
        print(line, flush=True)


if __name__ == "__main__":
    sys.exit(main())
