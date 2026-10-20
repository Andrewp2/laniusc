#!/usr/bin/env python3
"""Compile generics probes through one resident laniusc daemon and run them.

usage: tools/generics_matrix.py [--laniusc PATH] [--stdlib DIR] [--probes DIR]
                                [--memory-max SIZE] [--target x86_64|wasm] [PATTERN]

With `--target wasm` each probe compiles to a Wasm module whose exported
`main` runs under node (host imports are stubs returning 0). The low byte of
its result stands for the exit code, and a trap counts as exit 101 (the x86
panic exit).

A probe is a `.lani` file, or a directory holding a multi-module project: the
entry `main.lani` plus a source root `src/` (`gen::lib` is `src/gen/lib.lani`).
Its expected exit code is 42 unless the first line of the file (of `main.lani`
for a directory) is `// expect: N` (a negative N is the signal that kills
the x86 process, e.g. -4 for an assertion's SIGILL); `// expect: error LNC0021` expects the
compile to fail with that diagnostic code instead. LNC0017 is the x86
backend-boundary code (a rejection in shared lowering, like a type with no
zero value); the Wasm backend reports the same rejection as LNC0036, so with
`--target wasm` an expected LNC0017 matches LNC0036.
The daemon runs under a systemd memory cap so a runaway driver shader compile
kills only the daemon, not the desktop session.
"""
import argparse
import atexit
import json
import os
import queue
import threading
import pathlib
import re
import shutil
import signal
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
parser.add_argument("--hang-seconds", type=float, default=15.0,
                    help="restart the daemon after a failed compile that took this long (GPU hang)")
parser.add_argument("--readback-timeout-ms", default="20000",
                    help="GPU readback timeout for the daemon; warm probes finish in seconds, so a hang fails fast")
parser.add_argument("--skip", action="append", default=[], help="skip probes whose name contains this (repeatable)")
parser.add_argument("--target", choices=["x86_64", "wasm"], default="x86_64")
parser.add_argument("pattern", nargs="?", default="")
args = parser.parse_args()

probes = sorted(p for p in pathlib.Path(args.probes).iterdir()
                if (p.suffix == ".lani" or (p.is_dir() and (p / "main.lani").is_file()))
                and args.pattern in p.name and not any(skip in p.name for skip in args.skip))
out_dir = pathlib.Path(args.out)
out_dir.mkdir(parents=True, exist_ok=True)

command = [args.laniusc, "daemon", "--stdio", "--backend", args.target, "--stdlib-root", args.stdlib]
wasm = args.target == "wasm"
node = shutil.which("node") if wasm else None
if wasm and node is None:
    sys.exit("--target wasm needs node on PATH")
# Instantiate with stub imports and print main's result, or `trap` if it traps.
RUN_WASM = r"""
const fs = require('fs');
const mod = new WebAssembly.Module(fs.readFileSync(process.argv[1]));
const imports = {};
for (const imp of WebAssembly.Module.imports(mod)) {
  imports[imp.module] = imports[imp.module] || {};
  if (imp.kind === 'function') imports[imp.module][imp.name] = () => 0;
  else if (imp.kind === 'memory') imports[imp.module][imp.name] = new WebAssembly.Memory({ initial: 16 });
}
const instance = new WebAssembly.Instance(mod, imports);
let result;
try { result = instance.exports.main(); } catch (error) {
  if (error instanceof WebAssembly.RuntimeError) { console.log('trap ' + error.message); process.exit(0); }
  throw error;
}
console.log('main ' + (result === undefined ? 0 : Number(result)));
"""


def run_artifact(path):
    """The probe's exit code: the ELF's, or the Wasm main's low byte (101 on a trap)."""
    if not wasm:
        return subprocess.run([str(path)], capture_output=True, timeout=10).returncode, ""
    run = subprocess.run([node, "-e", RUN_WASM, str(path)], capture_output=True, text=True, timeout=10)
    words = run.stdout.split()
    if run.returncode != 0 or len(words) < 2:
        return None, (run.stderr.strip().splitlines() or ["node failed"])[-1][:300]
    if words[0] == "trap":
        return 101, ""
    return int(words[1]) & 0xff, ""
use_scope = shutil.which("systemd-run") is not None
stderr_path = out_dir / "daemon.stderr"


class Daemon:
    """One resident compiler; restarted after a job exceeds the timeout."""

    started = 0

    def __init__(self):
        env = dict(os.environ, LANIUS_READBACK_TIMEOUT_MS=args.readback_timeout_ms)
        # Instance-copy replays skip the optimizer's validation-only passes by
        # default; the matrix validates them (set it to 0 to time the default).
        env.setdefault("LANIUS_LIR_VALIDATE_REPLAYS", "1")
        argv = command
        self.unit = None
        if use_scope:
            # A scope of its own, so a runaway driver compile kills only the
            # daemon; kill() stops the scope so no daemon outlives this script.
            Daemon.started += 1
            self.unit = f"lanius-matrix-{os.getpid()}-{Daemon.started}.scope"
            argv = ["systemd-run", "--user", "--scope", "-q", f"--unit={self.unit}",
                    "-p", f"MemoryMax={args.memory_max}", "-p", "MemorySwapMax=0"] + command
        self.process = subprocess.Popen(argv, cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=open(stderr_path, "a"), text=True, bufsize=1)
        live_daemons.append(self)
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
        if self.unit:
            subprocess.run(["systemctl", "--user", "stop", self.unit], stderr=subprocess.DEVNULL)
        if self in live_daemons:
            live_daemons.remove(self)


live_daemons = []


def kill_live_daemons(*_):
    for daemon in list(live_daemons):
        daemon.kill()


atexit.register(kill_live_daemons)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))


def diagnostic(msg):
    text = json.dumps(msg)
    match = re.search(r'"message":\s*"((?:[^"\\]|\\.)*)"', text)
    detail = match.group(1) if match else text
    label = (msg.get("diagnostic") or {}).get("primary_label") or {}
    if isinstance(label, dict) and label.get("message"):
        detail += f" ({label['message']})"
    return detail[:400]


def diagnostic_code(msg):
    code = (msg.get("diagnostic") or {}).get("code")
    return code if isinstance(code, str) else None


results = []
daemon = Daemon()
for probe in probes:
    entry = probe / "main.lani" if probe.is_dir() else probe
    expect_match = re.match(r"//\s*expect:\s*(?:(-?\d+)|error\s+(LNC\d+))", entry.read_text())
    expect = int(expect_match.group(1)) if expect_match and expect_match.group(1) else 42
    expect_error = expect_match.group(2) if expect_match else None
    elf = out_dir / (probe.stem + (".wasm" if wasm else ".elf"))
    elf.unlink(missing_ok=True)
    request = {"id": probe.stem, "command": "compile", "emit": args.target,
               "input": str(entry.resolve()), "output": str(elf.resolve()),
               "stdlib_root": str(pathlib.Path(args.stdlib).resolve())}
    if probe.is_dir():
        request["source_root"] = str((probe / "src").resolve())
    started = time.time()
    try:
        msg = daemon.request(request, args.timeout)
    except (TimeoutError, RuntimeError) as err:
        daemon.kill()
        daemon = Daemon()
        results.append((probe.stem, "COMPILE-TIMEOUT" if isinstance(err, TimeoutError) else "DAEMON-EXIT",
                        time.time() - started, ""))
    else:
        elapsed = time.time() - started
        if expect_error:
            code = None if elf.exists() else diagnostic_code(msg)
            wanted = {expect_error}
            if wasm and expect_error == "LNC0017":
                wanted.add("LNC0036")
            status = "PASS" if code in wanted else f"WRONG({code or 'compiled'}, want {expect_error})"
            results.append((probe.stem, status, elapsed, "" if status == "PASS" else diagnostic(msg)))
        elif not elf.exists():
            results.append((probe.stem, "COMPILE-FAIL", elapsed, diagnostic(msg)))
            # A failure after a readback timeout means the GPU hung; the next
            # job would only queue behind it, so start a fresh daemon.
            if elapsed > args.hang_seconds:
                daemon.kill()
                daemon = Daemon()
        else:
            elf.chmod(0o755)
            detail = ""
            try:
                code, detail = run_artifact(elf)
                if code is None:
                    status = "RUN-FAIL"
                else:
                    status = "PASS" if code == (expect if expect < 0 else expect & 0xff) else f"WRONG(exit {code}, want {expect})"
            except subprocess.TimeoutExpired:
                status = "RUN-TIMEOUT"
            results.append((probe.stem, status, elapsed, detail))
    name, status, elapsed, detail = results[-1]
    print(f"{status:28} {elapsed:7.1f}s  {name}", flush=True)
    if detail:
        print(f"    {detail}", flush=True)

try:
    daemon.request({"id": "shutdown", "command": "shutdown"}, 30)
    daemon.process.wait(timeout=30)
except (TimeoutError, RuntimeError, subprocess.TimeoutExpired):
    pass
daemon.kill()
passed = sum(1 for result in results if result[1] == "PASS")
print(f"\n{passed}/{len(results)} passed")
sys.exit(0 if passed == len(results) else 1)
