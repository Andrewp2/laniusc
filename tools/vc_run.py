#!/usr/bin/env python3
"""Run row for verified_compiler: its compiler, built by laniusc, against laniusc.

usage: vc_run.py --laniusc BIN --out DIR [--vc-src verified_compiler/src] [--tests verified_compiler/tests]
                 [--known-gaps verified_compiler/tests/vc_run_known_gaps.txt] [PATTERN]
       vc_run.py --compile-only BIN [--out DIR]

--compile-only BIN only compiles verified_compiler's two entries,
compiler.lani and extractor.lani, with that laniusc (one warm daemon,
--stdlib-root stdlib, source root verified_compiler/src) and exits 1 if
either fails. It needs only a checkout and the binary.

1. laniusc compiles verified_compiler's compiler.lani to OUT/compiler.elf.
2. Each input program (an import-free `.lani` with `fn main` under
   verified_compiler/tests, tests/x86 and tests/fixtures) is compiled twice:
   by OUT/compiler.elf (`compiler.elf input > output`) and by laniusc, the
   oracle. Both outputs run.
3. A case passes when both reject it, or both run it with the same exit status
   and stdout. Any other outcome is a FAIL, unless the case is on the
   known-gap list, where it is KNOWN-GAP. A known gap that passes is FIXED
   (remove it from the list).

The exit status is 1 when a case outside the list fails, or the compiler
itself does not build.

Known gaps (2026-10-19): 76 of 81 pass. vc's three strides for records that
hold a slice (syntax_tree::Tree, aliases::Catalog, body_catalog::FunctionBody)
now come from core::mem::size_of, since slices are three words, and laniusc
now rejects a bool or integer slice_from_raw_parts argument where a length or
ptr belongs, `return;` in an i32 fn, and a non-bool while condition.
backend_descriptor_slice_field allocates 24 bytes for its one-slice record.
The 5 FAILs:
  semantics differ: compiler_uninitialized_self_assignment (laniusc zero-fills
    `let value: i32;`, vc traps on the read)
  vc lags the language: usize_widening_direct_lean (vc still widens i32 to
    usize implicitly)
  vc gaps: match_non_exhaustive_trap (vc lowering rejects, exit 10),
    typed_slice_intrinsic_call (vc rejects, exit 11), compiler_extern_metadata
    (vc's close(1) returns 255, laniusc's returns 0)
"""
import argparse
import ctypes
import json
import os
import pathlib
import re
import select
import signal
import subprocess
import sys
import time

REPO = pathlib.Path(__file__).resolve().parents[1]
ap = argparse.ArgumentParser()
ap.add_argument("--laniusc")
ap.add_argument("--out")
ap.add_argument("--compile-only", metavar="BIN",
                help="only compile compiler.lani and extractor.lani with BIN")
ap.add_argument("--vc-src", default=str(REPO / "verified_compiler" / "src"))
ap.add_argument("--tests", default=str(REPO / "verified_compiler" / "tests"))
ap.add_argument("--stdlib-root", default=str(REPO / "stdlib"))
ap.add_argument("--known-gaps", default=str(REPO / "verified_compiler" / "tests" / "vc_run_known_gaps.txt"))
ap.add_argument("--timeout", type=float, default=300.0, help="seconds per laniusc compile")
ap.add_argument("--run-timeout", type=float, default=20.0, help="seconds per vc compile or program run")
ap.add_argument("pattern", nargs="?", default="")
a = ap.parse_args()
if a.compile_only:
    a.laniusc = a.compile_only
if not a.laniusc:
    ap.error("--laniusc or --compile-only is required")
if not a.out:
    if not a.compile_only:
        ap.error("--out is required")
    import tempfile
    a.out = tempfile.mkdtemp(prefix="vc_compile_")

out = pathlib.Path(a.out)
out.mkdir(parents=True, exist_ok=True)
vc_src = pathlib.Path(a.vc_src)
tests = pathlib.Path(a.tests)
known = set()
if pathlib.Path(a.known_gaps).is_file():
    for line in pathlib.Path(a.known_gaps).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            known.add(line)

imports = re.compile(r"^\s*(?:pub\s+)?import\s", re.M)
mains = re.compile(r"^\s*fn\s+main\s*\(", re.M)
cases = []
for d in (tests, tests / "x86", tests / "fixtures"):
    for f in sorted(d.glob("*.lani")):
        text = f.read_text()
        name = str(f.relative_to(tests))
        if mains.search(text) and not imports.search(text) and a.pattern in name:
            cases.append((name, f))

env = dict(os.environ)
env.setdefault("LANIUS_READBACK_TIMEOUT_MS", "60000")
libc = ctypes.CDLL("libc.so.6", use_errno=True)
err = (out / "daemon.stderr").open("wb")
proc = subprocess.Popen(
    [a.laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", a.stdlib_root,
     "--idle-buffer-timeout-ms", "0"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=err, text=True, bufsize=1, env=env,
    preexec_fn=lambda: libc.prctl(1, signal.SIGKILL))


def read(timeout):
    r, _, _ = select.select([proc.stdout], [], [], timeout)
    if not r:
        raise TimeoutError("daemon response timeout")
    line = proc.stdout.readline()
    if not line:
        raise RuntimeError(f"daemon exited {proc.poll()}")
    return json.loads(line)


jid = 0


def laniusc(source, output, source_root=None):
    """(ok, diagnostic code) of one daemon compile."""
    global jid
    jid += 1
    req = {"id": f"j{jid}", "command": "compile", "emit": "x86_64", "input": str(source), "output": str(output)}
    if source_root:
        req["source_root"] = str(source_root)
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    resp = read(a.timeout)
    if resp.get("ok"):
        return True, None
    text = json.dumps(resp)
    m = re.search(r"LNC\d{4}", text)
    return False, m.group(0) if m else text[:200]


def run(argv, stdout_path=None):
    """(exit status or 'timeout' or -signal, stdout bytes)."""
    try:
        p = subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True, timeout=a.run_timeout)
    except subprocess.TimeoutExpired:
        return "timeout", b""
    if stdout_path:
        stdout_path.write_bytes(p.stdout)
    return p.returncode, p.stdout


def describe(outcome):
    # A laniusc rejection shows its diagnostic code; a vc one its exit status
    # (verified_compiler/src/compiler.lani exit_code: 10 is a lowering failure).
    return f"reject {outcome[1]}" if outcome[0] == "reject" else f"exit {outcome[1]}"


failures = 0
try:
    ready = read(600).get("event")
    if a.compile_only:
        for entry in ("compiler.lani", "extractor.lani"):
            target = out / (entry[:-5] + ".elf")
            s = time.perf_counter()
            ok, code = laniusc(vc_src / entry, target, vc_src)
            ms = (time.perf_counter() - s) * 1000
            print(f"{'ok  ' if ok else 'FAIL'} {entry}: {ms:.0f} ms, "
                  f"{target.stat().st_size if ok else 0} bytes{'' if ok else ', ' + str(code)}", flush=True)
            failures += 0 if ok else 1
        print(f"SUMMARY vc compile: {2 - failures}/2 entries compile ({ready})", flush=True)
        sys.exit(1 if failures else 0)
    compiler = out / "compiler.elf"
    s = time.perf_counter()
    ok, code = laniusc(vc_src / "compiler.lani", compiler, vc_src)
    print(f"ready: {ready}; compiler.lani {'ok' if ok else 'FAIL ' + str(code)} "
          f"{(time.perf_counter() - s) * 1000:.0f} ms, {compiler.stat().st_size if ok else 0} bytes", flush=True)
    if not ok:
        sys.exit(1)
    counts = {}
    for name, source in cases:
        stem = name.replace("/", "__")[:-5]
        ok, code = laniusc(source, out / f"{stem}.oracle.elf")
        if ok:
            rc, stdout = run([str(out / f"{stem}.oracle.elf")])
            oracle = ("run", rc, stdout)
        else:
            oracle = ("reject", code, b"")
        vc_elf = out / f"{stem}.vc.elf"
        rc, _ = run([str(compiler), str(source)], vc_elf)
        if rc == 0 and vc_elf.stat().st_size:
            vc_elf.chmod(0o755)
            rc, stdout = run([str(vc_elf)])
            vc = ("run", rc, stdout)
        else:
            vc = ("reject", rc, b"")
        same = (oracle[0] == vc[0] == "reject") or (oracle[0] == vc[0] == "run" and oracle[1:] == vc[1:])
        status = ("FIXED" if name in known else "PASS") if same else ("KNOWN-GAP" if name in known else "FAIL")
        if status == "FAIL":
            failures += 1
        counts[status] = counts.get(status, 0) + 1
        print(f"{status:<10} {name}: laniusc {describe(oracle)}, vc {describe(vc)}", flush=True)
    print(f"SUMMARY vc run: {len(cases)} cases, " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())), flush=True)
finally:
    try:
        proc.stdin.write(json.dumps({"id": "shutdown", "command": "shutdown"}) + "\n")
        proc.stdin.flush()
        proc.wait(timeout=30)
    except Exception:  # noqa: BLE001
        proc.kill()
        proc.wait()
    err.close()
sys.exit(1 if failures else 0)
