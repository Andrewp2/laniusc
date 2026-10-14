#!/usr/bin/env python3
"""Compile generics probes through one resident laniusc daemon and run the ELFs.

usage: tools/generics_matrix.py [--laniusc PATH] [--stdlib DIR] [--probes DIR]
                                [--memory-max SIZE] [PATTERN]

Each probe's expected exit code is 42 unless its first line is `// expect: N`.
The daemon runs under a systemd memory cap so a runaway driver shader compile
kills only the daemon, not the desktop session.
"""
import argparse
import json
import queue
import threading
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent

parser = argparse.ArgumentParser()
parser.add_argument("--laniusc", default=str(ROOT / "target/debug/laniusc"))
parser.add_argument("--stdlib", default=str(ROOT / "stdlib"))
parser.add_argument("--probes", default=str(ROOT / "tests/fixtures/generics_matrix"))
parser.add_argument("--out", default=str(ROOT / "target/generics_matrix"))
parser.add_argument("--memory-max", default="6G")
parser.add_argument("--timeout", type=float, default=120.0, help="seconds per compile")
parser.add_argument("--hang-seconds", type=float, default=100.0,
                    help="restart the daemon after a failed compile that took this long (GPU hang)")
parser.add_argument("pattern", nargs="?", default="")
args = parser.parse_args()

probes = sorted(p for p in pathlib.Path(args.probes).glob("*.lani") if args.pattern in p.name)
out_dir = pathlib.Path(args.out)
out_dir.mkdir(parents=True, exist_ok=True)

command = [args.laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", args.stdlib]
if shutil.which("systemd-run"):
    command = ["systemd-run", "--user", "--scope", "-q", "-p", f"MemoryMax={args.memory_max}",
               "-p", "MemorySwapMax=0"] + command
stderr_path = out_dir / "daemon.stderr"


class Daemon:
    """One resident compiler; restarted after a job exceeds the timeout."""

    def __init__(self):
        self.process = subprocess.Popen(command, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=open(stderr_path, "a"), text=True, bufsize=1)
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def request(self, obj, timeout):
        self.process.stdin.write(json.dumps(obj) + "\n")
        self.process.stdin.flush()
        deadline = time.time() + timeout
        while True:
            try:
                line = self.lines.get(timeout=max(0.0, deadline - time.time()))
            except queue.Empty:
                raise TimeoutError
            if line is None:
                raise RuntimeError(f"daemon exited; see {stderr_path}")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == obj["id"]:
                return msg

    def kill(self):
        self.process.kill()
        self.process.wait()


def diagnostic(msg):
    text = json.dumps(msg)
    match = re.search(r'"message":\s*"((?:[^"\\]|\\.)*)"', text)
    return (match.group(1) if match else text)[:400]


results = []
daemon = Daemon()
for probe in probes:
    expect_match = re.match(r"//\s*expect:\s*(-?\d+)", probe.read_text())
    expect = int(expect_match.group(1)) if expect_match else 42
    elf = out_dir / (probe.stem + ".elf")
    elf.unlink(missing_ok=True)
    started = time.time()
    try:
        msg = daemon.request({"id": probe.stem, "command": "compile", "emit": "x86_64",
                              "input": str(probe.resolve()), "output": str(elf.resolve()),
                              "stdlib_root": str(pathlib.Path(args.stdlib).resolve())}, args.timeout)
    except (TimeoutError, RuntimeError) as err:
        daemon.kill()
        daemon = Daemon()
        results.append((probe.stem, "COMPILE-TIMEOUT" if isinstance(err, TimeoutError) else "DAEMON-EXIT",
                        time.time() - started, ""))
    else:
        elapsed = time.time() - started
        if not elf.exists():
            results.append((probe.stem, "COMPILE-FAIL", elapsed, diagnostic(msg)))
            # A failure after a readback timeout means the GPU hung; the next
            # job would only queue behind it, so start a fresh daemon.
            if elapsed > args.hang_seconds:
                daemon.kill()
                daemon = Daemon()
        else:
            elf.chmod(0o755)
            try:
                code = subprocess.run([str(elf)], capture_output=True, timeout=10).returncode
                status = "PASS" if code == expect else f"WRONG(exit {code}, want {expect})"
            except subprocess.TimeoutExpired:
                status = "RUN-TIMEOUT"
            results.append((probe.stem, status, elapsed, ""))
    name, status, elapsed, detail = results[-1]
    print(f"{status:28} {elapsed:7.1f}s  {name}", flush=True)
    if detail:
        print(f"    {detail}", flush=True)

try:
    daemon.request({"id": "shutdown", "command": "shutdown"}, 30)
except (TimeoutError, RuntimeError):
    daemon.kill()
passed = sum(1 for result in results if result[1] == "PASS")
print(f"\n{passed}/{len(results)} passed")
sys.exit(0 if passed == len(results) else 1)
