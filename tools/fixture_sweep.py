#!/usr/bin/env python3
"""Compile and run every stdlib/generics fixture through one warm daemon.

usage:
  tools/fixture_sweep.py run [--laniusc PATH] [--shard I/N] [--resume] [--suite NAME]...
                             [--pattern TEXT]... [--out DIR] [--timeout S] [--memory-max SIZE]
  tools/fixture_sweep.py report [--out DIR] [--write FILE.md]
  tools/fixture_sweep.py diff --base OLD_DIR [--out DIR] [--write FILE.md]
  tools/fixture_sweep.py stdlib [--laniusc PATH] [--each] [--out DIR]
  tools/fixture_sweep.py list [--suite NAME]... [--pattern TEXT]...

`run` compiles each fixture with the resident daemon (like tools/generics_matrix.py),
runs the ELF, and compares the result with the fixture's expectation. Every
compiled ELF also goes through tools/x86_jump_check.py: a jmp/jcc that leaves its
function fails a fixture that otherwise passed (FAIL-JUMP). Suites:
stdlib_foundation (tests/fixtures/stdlib_foundation, expectations parsed from the
Rust tests by tools/fixture_expectations.py), generics_matrix and generics_backlog
(exit 42). In every suite the fixture's leading comment lines can set the
expectation and the stdlib root (`// expect: N`, `// expect: signal N`,
`// expect: LNCdddd`, `// expect: reject`, `// stdlib-root: DIR`; see
tools/fixture_expectations.py). Results go to DIR/results-shard-I-of-N.json;
`report` merges every shard file in DIR and prints pass/fail counts grouped by
status and diagnostic code, with the largest failure groups and an example
location for each.

A fixture that no Rust test compiles and that has no `// expect:` line is
judged against a guess (run with the repo stdlib, exit 0; a `reject*` name must
fail to compile). Its failures are marked with a dagger everywhere (FAIL-EXIT†,
the fail† column, "wrong exit status †" in a diff), so they never read as plain
failures: the fixture needs a real expectation before anyone debugs it.

A fixture listed in tests/fixtures/known_gaps.txt expects a feature that is
not there yet. While it fails the way its entry records, it is KNOWN-GAP and
is reported with its owner apart from the failures; once it passes it is
GAP-CLOSED, so the entry can be removed. A different failure stays a failure.

`stdlib` runs `laniusc check` on an entry that imports every stdlib module; with
--each it also compiles one entry per module through the daemon, so every
failing module is listed (a single check stops at the first error).

Every mode touches the GPU: run it through
target/claude-work/bin/heavy, and split `run` with --shard so that each
hold stays under ten minutes (about 1.5 s per fixture on a warm daemon).
"""

from __future__ import annotations

import argparse
import atexit
import collections
import hashlib
import json
import os
import pathlib
import queue
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

ROOT = pathlib.Path(__file__).resolve().parent.parent
STDLIB = ROOT / "stdlib"
DEFAULT_OUT = ROOT / "target" / "fixture_sweep"
SUITES = ("stdlib_foundation", "generics_matrix", "generics_backlog")
# Harness needs (tools/fixture_expectations.py) that leave the plain compile and
# run meaningful: the recorded exit status and stdout are the plain run's.
RUNNABLE_NEEDS = {"multiple-expectations", "fault-injection", "source-pack"}
# Needs without which the fixture is not the program its test compiles.
SKIPPED_NEEDS = {"source-concat", "generated-stdlib"}
OK_STATUSES = ("PASS", "COMPILED-ONLY", "SKIPPED", "GAP-CLOSED")
# Not passing, but recorded in KNOWN_GAPS: reported apart from the failures.
GAP_STATUSES = ("KNOWN-GAP",)
KNOWN_GAPS = "tests/fixtures/known_gaps.txt"


# ---------------------------------------------------------------------------
# Daemon


class Daemon:
    """One resident compiler under a memory-capped scope of its own."""

    started = 0
    live: list["Daemon"] = []

    def __init__(self, laniusc: str, memory_max: str, readback_timeout_ms: str, stderr_path: pathlib.Path):
        env = dict(os.environ, LANIUS_READBACK_TIMEOUT_MS=readback_timeout_ms)
        argv = [laniusc, "daemon", "--stdio", "--backend", "x86_64", "--stdlib-root", str(STDLIB)]
        self.unit = None
        if shutil.which("systemd-run"):
            Daemon.started += 1
            self.unit = f"lanius-sweep-{os.getpid()}-{Daemon.started}.scope"
            argv = ["systemd-run", "--user", "--scope", "-q", f"--unit={self.unit}",
                    "-p", f"MemoryMax={memory_max}", "-p", "MemorySwapMax=0"] + argv
        self.stderr_path = stderr_path
        self.process = subprocess.Popen(argv, cwd=ROOT, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=open(stderr_path, "a"), text=True, bufsize=1)
        Daemon.live.append(self)
        self.lines: queue.Queue = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        self.ready = self._next(None, 900)

    def _read(self):
        for line in self.process.stdout:
            self.lines.put(line)
        self.lines.put(None)

    def _next(self, request_id, timeout):
        deadline = time.time() + timeout
        while True:
            try:
                line = self.lines.get(timeout=max(0.0, deadline - time.time()))
            except queue.Empty:
                raise TimeoutError
            if line is None:
                raise RuntimeError(f"daemon exited; see {self.stderr_path}")
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if request_id is None or msg.get("id") == request_id:
                return msg

    def request(self, obj: dict, timeout: float) -> dict:
        self.process.stdin.write(json.dumps(obj) + "\n")
        self.process.stdin.flush()
        return self._next(obj["id"], timeout)

    def kill(self):
        if self.process.poll() is None:
            try:
                self.request({"id": "shutdown", "command": "shutdown"}, 20)
                self.process.wait(timeout=20)
            except (TimeoutError, RuntimeError, subprocess.TimeoutExpired, BrokenPipeError):
                pass
        self.process.kill()
        self.process.wait()
        if self.unit:
            subprocess.run(["systemctl", "--user", "stop", self.unit], stderr=subprocess.DEVNULL)
        if self in Daemon.live:
            Daemon.live.remove(self)


def kill_live_daemons(*_):
    for daemon in list(Daemon.live):
        daemon.kill()


atexit.register(kill_live_daemons)
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
signal.signal(signal.SIGHUP, lambda *_: sys.exit(129))


# ---------------------------------------------------------------------------
# Cases


def suite_of(path: pathlib.Path) -> str:
    for suite in SUITES:
        if f"/{suite}/" in str(path):
            return suite
    return "other"


def relative(path: pathlib.Path) -> str:
    try:
        return str(path.resolve().relative_to(ROOT))
    except ValueError:
        return str(path)


def guessed(result: dict) -> bool:
    """A failure judged against a guess: no Rust test compiles the fixture and it has no `// expect:` line."""
    source = result.get("expected", {}).get("source", "")
    return (result["status"] not in OK_STATUSES + GAP_STATUSES and source.startswith("default")
            and not source.startswith("default:generics"))  # generics probes exit 42 by convention


def dagger(result: dict) -> str:
    return "†" if guessed(result) else ""


def load_known_gaps(root: pathlib.Path) -> dict[str, dict]:
    """KNOWN_GAPS lines: fixture path, the failure it shows today, owner, reason.

    The failure is an error code (LNC0006), a status (FAIL-EXIT), or `any`.
    """
    path = root / KNOWN_GAPS
    gaps = {}
    if not path.exists():
        return gaps
    for number, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split(None, 3)
        if len(fields) < 4:
            raise SystemExit(f"{KNOWN_GAPS}:{number}: want `fixture failure owner reason`, got {line!r}")
        fixture, failure, owner, reason = fields
        if not (root / fixture).exists():
            raise SystemExit(f"{KNOWN_GAPS}:{number}: no fixture {fixture}")
        gaps[fixture] = {"failure": failure, "owner": owner, "reason": reason}
    return gaps


def apply_known_gap(record: dict, gaps: dict[str, dict]):
    """Mark a listed fixture KNOWN-GAP while it fails as recorded, GAP-CLOSED once it passes."""
    gap = gaps.get(record["name"])
    if gap is None:
        return
    record["known_gap"] = gap
    failure = gap["failure"]
    if record["status"] in OK_STATUSES:
        record.update(status="GAP-CLOSED", detail=f"passes now; remove it from {KNOWN_GAPS}")
    elif failure == "any" or failure in (record["status"], record.get("code")):
        record["gap_status"] = record["status"]
        record["status"] = "KNOWN-GAP"


def load_cases(suites: list[str], patterns: list[str]) -> list:
    from fixture_expectations import load_expectations

    cases = [
        expectation
        for expectation in load_expectations(ROOT)
        if expectation.kind != "module"
        and suite_of(expectation.path) in suites
        and (not patterns or any(pattern in relative(expectation.path) for pattern in patterns))
    ]
    return sorted(cases, key=lambda expectation: relative(expectation.path))


def describe_expectation(expectation) -> dict:
    return {
        "kind": expectation.kind,
        "exit_code": expectation.exit_code,
        "signal": expectation.signal,
        "stdout": None if expectation.stdout is None else expectation.stdout.decode("utf-8", "replace")[:300],
        "error_code": expectation.error_code,
        "stdlib_root": relative(expectation.stdlib_root) if expectation.stdlib_root else None,
        "harness": list(expectation.harness),
        "source": expectation.source,
    }


def diagnostic_fields(response: dict) -> dict:
    diagnostic = response.get("diagnostic") or {}
    label = diagnostic.get("primary_label") or {}
    location = None
    if label.get("path"):
        location = f"{relative(pathlib.Path(label['path']))}:{label.get('line')}:{label.get('column')}"
    message = diagnostic.get("message") or response.get("protocol_error") or response.get("error") or ""
    return {
        "code": diagnostic.get("code"),
        "title": diagnostic.get("title"),
        "message": str(message)[:500],
        "location": location,
        "source_line": (label.get("source_line") or "").strip()[:200] or None,
    }


STAGE_DETAIL_RE = re.compile(
    r"internal compiler phase error.*|GPU [\w -]*rejection.*|GPU type-check detail.*|.*readback did not complete.*")


def stage_detail(stderr_path: pathlib.Path, offset: int) -> str | None:
    """The first internal error line the daemon wrote after `offset`, if any."""
    try:
        with open(stderr_path, "rb") as stream:
            stream.seek(offset)
            text = stream.read(1 << 20).decode("utf-8", "replace")
    except OSError:
        return None
    for line in text.splitlines():
        match = STAGE_DETAIL_RE.search(line)
        if match:
            return match.group(0).strip()[:300]
    return None


def stderr_size(path: pathlib.Path) -> int:
    try:
        return path.stat().st_size
    except OSError:
        return 0


def run_elf(elf: pathlib.Path) -> dict:
    elf.chmod(0o755)
    # Each program runs in its own empty directory, as the fs tests do: a fixture that creates
    # files must neither litter the checkout nor see what an earlier sweep left behind.
    with tempfile.TemporaryDirectory(prefix="fixture-sweep-run-") as directory:
        try:
            completed = subprocess.run([str(elf.resolve())], capture_output=True, timeout=10,
                                       stdin=subprocess.DEVNULL, cwd=directory)
        except subprocess.TimeoutExpired:
            return {"timeout": True}
    code = completed.returncode
    return {
        "exit_code": code if code >= 0 else None,
        "signal": -code if code < 0 else None,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def judge_run(expectation, run: dict) -> tuple[str, str]:
    if run.get("timeout"):
        return "FAIL-RUN-TIMEOUT", "program ran longer than 10 s"
    if expectation.signal is not None:
        if run["signal"] != expectation.signal:
            return "FAIL-EXIT", f"got exit {run['exit_code']} signal {run['signal']}, want signal {expectation.signal}"
    elif expectation.exit_code is not None and run["exit_code"] != expectation.exit_code:
        signal_text = f" signal {run['signal']}" if run["signal"] else ""
        return "FAIL-EXIT", f"got exit {run['exit_code']}{signal_text}, want exit {expectation.exit_code}"
    if expectation.stdout is not None and run["stdout"] != expectation.stdout:
        return "FAIL-STDOUT", (
            f"stdout {run['stdout'][:120]!r} != expected {expectation.stdout[:120]!r}"
        )
    return "PASS", ""


def check_jumps(elf: pathlib.Path, record: dict):
    """Run tools/x86_jump_check.py on a compiled fixture. A jmp/jcc into another
    function is a miscompile even when the run passed, so it fails the fixture."""
    from x86_jump_check import describe, jumps_leaving_function

    if shutil.which("objdump") is None:
        record["jump_check"] = "skipped: no objdump"
        return
    try:
        jumps = jumps_leaving_function(str(elf))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        jumps = [{"error": str(error)[:200]}]
    if not jumps:
        return
    record["bad_jumps"] = len(jumps)
    record["bad_jump_examples"] = [jump.get("error") or describe(jump) for jump in jumps[:5]]
    if record["status"] in OK_STATUSES:
        record.update(status="FAIL-JUMP", detail=f"{len(jumps)} bad jumps; first: {record['bad_jump_examples'][0]}")


def sweep(args) -> int:
    suites = args.suite or list(SUITES)
    cases = load_cases(suites, args.pattern)
    gaps = load_known_gaps(ROOT)
    index, count = parse_shard(args.shard)
    cases = [case for position, case in enumerate(cases) if position % count == index - 1]
    out = pathlib.Path(args.out)
    elf_dir = out / "elf"
    elf_dir.mkdir(parents=True, exist_ok=True)
    result_path = out / f"results-shard-{index}-of-{count}.json"
    stderr_path = out / f"daemon-shard-{index}-of-{count}.stderr"
    results = []
    previous_wall = 0.0
    previous = {}
    if args.resume and result_path.exists():
        previous = json.loads(result_path.read_text())
        results = previous["results"]
        previous_wall = previous.get("wall_s", 0.0)
    done = {result["name"] for result in results}
    todo = [(number, case) for number, case in enumerate(cases) if relative(case.path) not in done]
    print(f"fixture_sweep: {len(cases)} fixtures in shard {index}/{count}"
          + (f", {len(todo)} not yet run" if args.resume else ""), flush=True)

    started_all = time.time()
    version = laniusc_version(args.laniusc)
    # Shader digests seen when a daemon started (it loads every kernel then) and at the end.
    digests_seen = list(previous.get("shader_digests_seen", []))

    def start_daemon() -> Daemon:
        digests_seen.append(shader_digest(args.laniusc))
        return Daemon(args.laniusc, args.memory_max, args.readback_timeout_ms, stderr_path)

    def write(complete: bool):
        document = {
            "schema": "lanius.fixture-sweep.v1",
            "laniusc": args.laniusc,
            "laniusc_version": version,
            "source_root": str(ROOT),
            "shard": f"{index}/{count}",
            "suites": suites,
            "pattern": args.pattern,
            "cases_in_shard": len(cases),
            "complete": complete,
            "wall_s": round(previous_wall + time.time() - started_all, 1),
            "daemon_ready": daemon.ready,
            "shader_digests_seen": sorted(set(filter(None, digests_seen))),
            "results": results,
        }
        temporary = result_path.with_suffix(".tmp")
        temporary.write_text(json.dumps(document, indent=1) + "\n")
        temporary.replace(result_path)

    if not todo:
        print("fixture_sweep: nothing left to run in this shard")
        return 0
    daemon = start_daemon()
    print(f"fixture_sweep: daemon ready in {time.time() - started_all:.1f} s: "
          f"{json.dumps(daemon.ready)[:300]}", flush=True)
    for position, (number, expectation) in enumerate(todo):
        name = relative(expectation.path)
        elf = elf_path(elf_dir, name)
        elf.unlink(missing_ok=True)
        stdlib_root = expectation.stdlib_root or STDLIB
        started = time.time()
        record = {"name": name, "suite": suite_of(expectation.path), "expected": describe_expectation(expectation)}
        skip = sorted(SKIPPED_NEEDS & set(expectation.harness))
        if skip:
            record.update(status="SKIPPED", detail="needs " + ",".join(skip), elapsed_s=0.0)
            results.append(record)
            print(f"{'SKIPPED':22} {0.0:6.1f}s  {name}", flush=True)
            write(complete=len(results) == len(cases))
            continue
        stderr_offset = stderr_size(stderr_path)
        try:
            response = daemon.request({
                "id": f"fixture-{number}", "command": "compile", "emit": "x86_64",
                "input": str(expectation.path), "output": str(elf), "stdlib_root": str(stdlib_root),
            }, args.timeout)
        except (TimeoutError, RuntimeError) as error:
            daemon.kill()
            daemon = start_daemon()
            status = "FAIL-COMPILE-TIMEOUT" if isinstance(error, TimeoutError) else "FAIL-DAEMON-EXIT"
            record.update(status=status, detail=str(error)[:300])
        else:
            elapsed = time.time() - started
            compiled = response.get("ok") is True and elf.exists()
            if not compiled:
                fields = diagnostic_fields(response)
                record.update(fields)
                detail = stage_detail(stderr_path, stderr_offset)
                if detail:
                    record["stage_detail"] = detail
                if expectation.kind == "compile_error":
                    if expectation.error_code and fields["code"] != expectation.error_code:
                        record.update(status="FAIL-WRONG-CODE",
                                      detail=f"got {fields['code']}, want {expectation.error_code}")
                    else:
                        record.update(status="PASS", detail="rejected as expected")
                else:
                    record.update(status="FAIL-COMPILE", detail=fields["message"])
                # A failure after a readback timeout means the GPU hung; the
                # next job would only queue behind it, so start a fresh daemon.
                if elapsed > args.hang_seconds:
                    record["hang_suspected"] = True
                    daemon.kill()
                    daemon = start_daemon()
            elif expectation.kind == "compile_error":
                record.update(status="FAIL-ACCEPTED", detail=f"compiled; want {expectation.error_code or 'an error'}")
            elif expectation.kind == "check_only":
                record.update(status="PASS", detail="compiled (check-only fixture)")
            elif set(expectation.harness) - RUNNABLE_NEEDS:
                record.update(status="COMPILED-ONLY", detail="needs " + ",".join(expectation.harness))
            else:
                run = run_elf(elf)
                status, detail = judge_run(expectation, run)
                record.update(status=status, detail=detail)
                if not run.get("timeout"):
                    record["actual"] = {
                        "exit_code": run["exit_code"], "signal": run["signal"],
                        "stdout": run["stdout"].decode("utf-8", "replace")[:300],
                        "stderr": run["stderr"].decode("utf-8", "replace")[:300],
                    }
            record["compile_s"] = round(elapsed, 3)
            if compiled:
                check_jumps(elf, record)
        apply_known_gap(record, gaps)
        record["elapsed_s"] = round(time.time() - started, 3)
        results.append(record)
        line = f"{record['status'] + dagger(record):22} {record['elapsed_s']:6.1f}s  {name}"
        if record["status"] in GAP_STATUSES:
            gap = record["known_gap"]
            line += f"\n    {record['gap_status']} {record.get('code') or ''}: {gap['reason'][:160]} (owner {gap['owner']})"
        elif record["status"] not in OK_STATUSES or record["status"] == "GAP-CLOSED":
            line += f"\n    {record.get('code') or ''} {record.get('location') or ''} {record.get('detail', '')[:200]}"
            if record.get("bad_jumps") and record["status"] != "FAIL-JUMP":
                line += f"\n    {record['bad_jumps']} bad jumps; first: {record['bad_jump_examples'][0]}"
        print(line, flush=True)
        # Written after every fixture, so a hold that is cut short keeps its
        # results and `--resume` continues where it stopped.
        write(complete=len(results) == len(cases))
        if args.budget_seconds and time.time() - started_all > args.budget_seconds:
            print(f"fixture_sweep: stopping after {args.budget_seconds} s budget; "
                  f"{len(todo) - position - 1} fixtures not run (continue with --resume)", flush=True)
            break
    daemon.kill()
    digests_seen.append(shader_digest(args.laniusc))
    write(complete=len(results) == len(cases))
    passed = sum(1 for result in results if result["status"] in OK_STATUSES)
    known = sum(1 for result in results if result["status"] in GAP_STATUSES)
    guesses = sum(1 for result in results if guessed(result))
    print(f"\nfixture_sweep: {passed}/{len(results)} passed or compiled"
          + (f", {known} known gaps" if known else "")
          + (f", {guesses} of the failures against a guessed expectation (†)" if guesses else "")
          + f"; wrote {relative(result_path)}")
    return 0 if passed + known == len(results) else 1


def parse_shard(text: str) -> tuple[int, int]:
    match = re.fullmatch(r"(\d+)/(\d+)", text)
    if not match or not 1 <= int(match.group(1)) <= int(match.group(2)):
        raise SystemExit(f"--shard must be I/N with 1 <= I <= N, got {text!r}")
    return int(match.group(1)), int(match.group(2))


def laniusc_version(laniusc: str) -> dict:
    """The binary's own hash plus the shader digest it reports.

    The compiler loads its kernels at run time from the build's shared artifact
    directory, so a copied binary can run newer kernels than it was built with:
    the shader digest is re-read when a daemon starts and at the end of a shard.
    """
    try:
        text = subprocess.run([laniusc, "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return {}
    fields = dict(line.split(": ", 1) for line in text.splitlines() if ": " in line)
    version = {key: fields.get(key) for key in ("shader-artifact-digest", "shader-artifact-count", "build-profile")}
    try:
        version["binary-sha256"] = hashlib.sha256(pathlib.Path(laniusc).read_bytes()).hexdigest()[:16]
    except OSError:
        pass
    return version


def shader_digest(laniusc: str) -> str | None:
    try:
        text = subprocess.run([laniusc, "--version"], capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"^shader-artifact-digest: (\S+)", text, re.M)
    return match.group(1) if match else None


# ---------------------------------------------------------------------------
# Report


SCALAR = r"(?:u8|u16|u32|u64|i8|i16|i32|i64|usize|isize|char|f32|f64|bool)"
# `x as u32` casts, and `let a: u32 = b;` where b has another scalar type: the
# stdlib leans on both, and one missing feature should not hide other bugs.
AS_CAST_RE = re.compile(rf"\bas\s+{SCALAR}\b")
IMPLICIT_SCALAR_RE = re.compile(rf"^let\s+\w+\s*:\s*{SCALAR}\s*=\s*[\w.]+\s*;$")


def scalar_conversion(result: dict) -> str | None:
    """Name the scalar conversion on the failing line, so `as` casts group apart."""
    line = result.get("source_line") or ""
    if AS_CAST_RE.search(line):
        return "scalar conversion: `as` cast"
    if result.get("code") == "LNC0006" and IMPLICIT_SCALAR_RE.match(line):
        return "scalar conversion: implicit (let with scalar annotation)"
    return None


def failure_group(result: dict) -> str:
    status = result["status"]
    if status == "FAIL-COMPILE":
        conversion = scalar_conversion(result)
        if conversion:
            return f"compile error {result.get('code') or '(no code)'}, {conversion}"
        if "readback did not complete" in (result.get("stage_detail") or ""):
            return f"compile error {result.get('code') or '(no code)'}, GPU hang (readback timeout)"
        return f"compile error {result.get('code') or '(no code)'}"
    if status == "FAIL-WRONG-CODE":
        return f"wrong diagnostic {result.get('code') or '(no code)'}"
    return {
        "FAIL-COMPILE-TIMEOUT": "compile timeout (GPU hang)",
        "FAIL-DAEMON-EXIT": "daemon exited",
        "FAIL-ACCEPTED": "invalid program accepted",
        "FAIL-EXIT": "wrong exit status",
        "FAIL-STDOUT": "wrong stdout",
        "FAIL-RUN-TIMEOUT": "program timeout",
        "FAIL-JUMP": "jump leaves its function (run passed)",
    }.get(status, status)


def normalized_message(message: str) -> str:
    message = re.sub(r"`[^`]*`", "`_`", message or "")
    message = re.sub(r"\b\d+\b", "N", message)
    return message[:160]


def load_results(out: pathlib.Path) -> tuple[dict[str, dict], list]:
    shards = sorted(out.glob("results-shard-*.json"))
    if not shards:
        raise SystemExit(f"no shard results in {out}")
    results: dict[str, dict] = {}
    documents = []
    for path in shards:
        document = json.loads(path.read_text())
        documents.append((path, document))
        for result in document["results"]:
            results[result["name"]] = result
    return results, documents


def report(args) -> int:
    out = pathlib.Path(args.out)
    results, documents = load_results(out)
    lines = render_report(results, documents)
    lines += render_jump_check(results, out / "elf")
    stdlib_summary = out / "stdlib" / "stdlib_check.json"
    if stdlib_summary.exists():
        lines += render_stdlib_check(json.loads(stdlib_summary.read_text()))
    text = "\n".join(lines) + "\n"
    print(text)
    if args.write:
        pathlib.Path(args.write).write_text(text)
        print(f"wrote {args.write}")
    return 0


def render_report(results: dict[str, dict], documents) -> list[str]:
    by_suite = collections.defaultdict(collections.Counter)
    for result in results.values():
        by_suite[result["suite"]][result["status"]] += 1
        by_suite[result["suite"]]["guessed"] += guessed(result)
    failures = [result for result in results.values() if result["status"] not in OK_STATUSES + GAP_STATUSES]
    groups = collections.defaultdict(list)
    for result in failures:
        groups[failure_group(result)].append(result)
    lines = ["# Fixture sweep", ""]
    first = documents[0][1]
    versions = {json.dumps(document.get("laniusc_version", {}), sort_keys=True) for _, document in documents}
    lines.append(f"Compiler: `{first['laniusc']}` {json.dumps(first.get('laniusc_version', {}))}"
                 + ("" if len(versions) == 1 else f" (WARNING: shards ran {len(versions)} different builds)"))
    lines.append("")
    lines.append("Each fixture is compiled by one resident daemon (`laniusc daemon --stdio`), run, and "
                 "judged against the outcome its Rust tests assert (tools/fixture_expectations.py). "
                 "Reproduce with `tools/fixture_sweep.py run --laniusc BIN --shard I/N --resume` per "
                 "shard, `tools/fixture_sweep.py stdlib --each`, then `tools/fixture_sweep.py report`.")
    lines.append("")
    def kernel_mix(document) -> str:
        # Kernels load from disk at daemon start, so a rebuild during a shard mixes builds.
        seen = set(document.get("shader_digests_seen", []))
        seen.add(document.get("laniusc_version", {}).get("shader-artifact-digest"))
        seen.discard(None)
        return f", MIXED kernels {', '.join(sorted(seen))}" if len(seen) > 1 else ""

    shard_times = ", ".join(
        f"{document['shard']} ({document['wall_s']} s"
        + ("" if document.get("complete", True) else
           f", INCOMPLETE: {document['cases_in_shard'] - len(document['results'])} not run")
        + kernel_mix(document)
        + ")"
        for _, document in documents)
    lines.append(f"Shards: {shard_times}")
    lines.append("")
    lines.append("| suite | fixtures | pass | compiled only | skipped | known gap | fail | fail† |")
    lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for suite, counts in sorted(by_suite.items()):
        total = sum(counts.values()) - counts["guessed"]
        failed = total - sum(counts[status] for status in OK_STATUSES + GAP_STATUSES) - counts["guessed"]
        lines.append(f"| {suite} | {total} | {counts['PASS'] + counts['GAP-CLOSED']} | {counts['COMPILED-ONLY']} | "
                     f"{counts['SKIPPED']} | {counts['KNOWN-GAP']} | {failed} | {counts['guessed']} |")
    lines.append("")
    if any(counts["guessed"] for counts in by_suite.values()):
        lines.append("fail†: the fixture failed an expectation that is a guess (no Rust test compiles it and it "
                     "has no `// expect:` line), so the guess may be what is wrong. Give it a real expectation "
                     "before routing it to a compiler owner.")
        lines.append("")
    gaps = sorted((result for result in results.values() if result["status"] in GAP_STATUSES),
                  key=lambda result: (result["known_gap"]["owner"], result["name"]))
    if gaps:
        lines.append(f"## Known gaps ({len(gaps)})")
        lines.append("")
        lines.append(f"Listed in `{KNOWN_GAPS}`; not counted as failures while they fail as recorded.")
        lines.append("")
        lines.append("| fixture | owner | today | reason |")
        lines.append("| --- | --- | --- | --- |")
        for result in gaps:
            gap = result["known_gap"]
            today = f"{result['gap_status']} {result.get('code') or ''}".strip()
            lines.append(f"| `{result['name']}` | {gap['owner']} | {today} | {gap['reason']} |")
        lines.append("")
    closed = sorted(result["name"] for result in results.values() if result["status"] == "GAP-CLOSED")
    if closed:
        lines.append(f"Known gaps that pass now; remove them from `{KNOWN_GAPS}`: "
                     + ", ".join(f"`{name}`" for name in closed) + ".")
        lines.append("")
    lines.append("## Failures by group")
    lines.append("")
    lines.append("| group | count | of which † | example | location |")
    lines.append("| --- | ---: | ---: | --- | --- |")
    for group, members in sorted(groups.items(), key=lambda item: -len(item[1])):
        example = members[0]
        lines.append(f"| {group} | {len(members)} | {sum(map(guessed, members))} | "
                     f"`{example['name']}`{dagger(example)} | {example.get('location') or ''} |")
    lines.append("")
    # Generics matrix fixtures all exit 42 by convention; other unreferenced fixtures are a guess.
    guesses = sorted(result["name"] for result in failures if guessed(result))
    if guesses:
        lines.append(f"{len(guesses)} of the {len(failures)} failures (†) are fixtures that no Rust test "
                     "compiles and that have no `// expect:` line, so their expected outcome is a guess: a "
                     "`reject*` name must fail to compile, anything else must run with the repo stdlib and "
                     "exit 0. Some need a setup the guess does not know, such as their own `// stdlib-root:`: "
                     + ", ".join(name.rsplit("/", 1)[-1] for name in guesses) + ".")
        lines.append("")
    for group, members in sorted(groups.items(), key=lambda item: -len(item[1])):
        lines.append(f"### {group} ({len(members)})")
        lines.append("")
        messages = collections.defaultdict(list)
        for member in members:
            if member["status"] == "FAIL-EXIT":
                key = member.get("detail") or ""  # keep the exit codes: 101 is a trap, 1 an error
            elif member["status"] == "FAIL-STDOUT":
                key = "stdout differs"
            elif (member.get("location") or "").startswith("stdlib/"):
                # Many fixtures fail on the same stdlib line; list it once.
                key = f"at {member['location']}: {normalized_message(member.get('message') or '')}"
            elif member.get("stage_detail"):
                key = normalized_message(member["stage_detail"])
            else:
                key = normalized_message(member.get("message") or member.get("detail") or "")
            messages[key].append(member)
        for message, same in sorted(messages.items(), key=lambda item: -len(item[1])):
            example = same[0]
            lines.append(f"- {len(same)} x {message or '(no message)'}")
            lines.append(f"  - e.g. `{example['name']}`{dagger(example)} {example.get('location') or ''}"
                         + (f": `{example['source_line']}`" if example.get("source_line") else "")
                         + (f" ({example.get('detail', '')[:160]})" if example.get('detail') and example['status'] != 'FAIL-COMPILE' else ""))
            others = ", ".join(member["name"].rsplit("/", 1)[-1] + dagger(member) for member in same[1:8])
            if others:
                lines.append(f"  - also: {others}{' ...' if len(same) > 8 else ''}")
        lines.append("")
    return lines


def elf_path(elf_dir: pathlib.Path, name: str) -> pathlib.Path:
    return elf_dir / (re.sub(r"[^\w.-]", "_", name) + ".elf")


def render_jump_check(results: dict[str, dict], elf_dir: pathlib.Path) -> list[str]:
    """Static check of every kept ELF (tools/x86_jump_check.py): jumps into other functions or back to their own entry."""
    from x86_jump_check import describe, jumps_leaving_function

    if shutil.which("objdump") is None:
        return []
    flagged = []
    checked = 0
    for name, result in sorted(results.items()):
        elf = elf_path(elf_dir, name)
        if not elf.exists():
            continue
        checked += 1
        jumps = jumps_leaving_function(str(elf))
        if jumps:
            flagged.append((name, result, jumps))
    if not checked:
        return []
    lines = ["## Jumps that leave their function or return to its entry", ""]
    lines.append(f"tools/x86_jump_check.py over the {checked} compiled programs kept in `{relative(elf_dir)}`: "
                 f"{len(flagged)} contain a jmp/jcc into another function or to its own function's entry, "
                 "a miscompile whether or not the run passed.")
    if flagged:
        lines.append("")
        lines.append("| fixture | status | jumps | first |")
        lines.append("| --- | --- | ---: | --- |")
        for name, result, jumps in sorted(flagged, key=lambda item: (item[1]["status"] == "PASS", item[0])):
            lines.append(f"| `{name}` | {result['status']} | {len(jumps)} | {describe(jumps[0])} |")
    lines.append("")
    return lines


def outcome(result: dict | None) -> str:
    if result is None:
        return "absent"
    if result["status"] in GAP_STATUSES:
        return "known gap"
    if result["status"] in OK_STATUSES:
        return "ok"
    return failure_group(result) + (" †" if guessed(result) else "")


def diff(args) -> int:
    base_dir, new_dir = pathlib.Path(args.base), pathlib.Path(args.out)
    base, base_documents = load_results(base_dir)
    new, new_documents = load_results(new_dir)
    lines = render_diff(base, new, base_documents, new_documents)
    summaries = []
    for directory in (base_dir, new_dir):
        path = directory / "stdlib" / "stdlib_check.json"
        summaries.append(json.loads(path.read_text()) if path.exists() else None)
    lines += render_stdlib_diff(*summaries)
    text = "\n".join(lines) + "\n"
    print(text)
    if args.write:
        pathlib.Path(args.write).write_text(text)
        print(f"wrote {args.write}")
    return 0


def render_diff(base: dict[str, dict], new: dict[str, dict], base_documents, new_documents) -> list[str]:
    def build(documents) -> str:
        version = documents[0][1].get("laniusc_version", {})
        return f"`{version.get('shader-artifact-digest', '?')}`"

    lines = ["# Fixture sweep diff", ""]
    lines.append(f"Base {build(base_documents)} ({len(base)} fixtures), new {build(new_documents)} "
                 f"({len(new)} fixtures).")
    lines.append("")
    names = sorted(set(base) | set(new))
    changes = collections.defaultdict(list)  # (base outcome, new outcome) -> names
    for name in names:
        before, after = outcome(base.get(name)), outcome(new.get(name))
        if before != after:
            changes[(before, after)].append(name)
    def count(test) -> int:
        return sum(len(members) for (before, after), members in changes.items() if test(before, after))

    fixed = count(lambda before, after: before not in ("ok", "absent") and after == "ok")
    broken = count(lambda before, after: before == "ok" and after not in ("ok", "absent"))
    moved = count(lambda before, after: "ok" not in (before, after) and "absent" not in (before, after))
    added, removed = count(lambda before, _: before == "absent"), count(lambda _, after: after == "absent")
    passing = [sum(1 for result in results.values() if result["status"] in OK_STATUSES)
               for results in (base, new)]
    lines.append(f"Passing (pass, compiled only or skipped): {passing[0]} -> {passing[1]}. "
                 f"Newly passing {fixed}, newly failing {broken}, failing differently {moved}"
                 + (f", fixtures added {added}" if added else "")
                 + (f", fixtures removed {removed}" if removed else "") + ".")
    lines.append("")
    group_counts = [collections.Counter(outcome(result) for result in results.values()) for results in (base, new)]
    lines.append("| group | base | new | change |")
    lines.append("| --- | ---: | ---: | ---: |")
    for group in sorted(set(group_counts[0]) | set(group_counts[1]),
                        key=lambda group: (group != "ok", -max(group_counts[0][group], group_counts[1][group]))):
        before, after = group_counts[0][group], group_counts[1][group]
        lines.append(f"| {group} | {before} | {after} | {after - before:+d} |")
    lines.append("")
    lines.append("## Changed fixtures")
    lines.append("")
    for (before, after), members in sorted(changes.items(), key=lambda item: (item[0][1] != "ok", -len(item[1]))):
        lines.append(f"### {before} -> {after} ({len(members)})")
        lines.append("")
        for name in members[:40]:
            result = new.get(name) or {}
            detail = result.get("location") or result.get("detail") or ""
            message = result.get("message") or ""
            lines.append(f"- `{name}`" + (f" {detail}" if detail and after != "ok" else "")
                         + (f": {message[:120]}" if message and after != "ok" else ""))
        if len(members) > 40:
            lines.append(f"- ... and {len(members) - 40} more")
        lines.append("")
    return lines


def render_stdlib_diff(base: dict | None, new: dict | None) -> list[str]:
    if not base or not new or base.get("modules_checked") is None or new.get("modules_checked") is None:
        return []
    ok = [{record["module"] for record in summary["modules_checked"] if record["ok"]} for summary in (base, new)]
    lines = ["## Stdlib per-module check", ""]
    lines.append(f"Modules that compile on their own: {len(ok[0])}/{len(base['modules_checked'])} -> "
                 f"{len(ok[1])}/{len(new['modules_checked'])}; `laniusc check` over all modules: "
                 f"{base['check_status']} -> {new['check_status']}.")
    for title, modules in (("Newly compiling", ok[1] - ok[0]), ("No longer compiling", ok[0] - ok[1])):
        if modules:
            lines.append(f"{title}: " + ", ".join(f"`{module}`" for module in sorted(modules)) + ".")
    lines.append("")
    return lines


def render_stdlib_check(summary: dict) -> list[str]:
    lines = ["## Stdlib check", ""]
    lines.append(f"`laniusc check` on one entry importing all {summary['modules']} stdlib modules: "
                 f"**{summary['check_status']}**.")
    if summary.get("legacy_files"):
        lines.append(f"Files without a module header (not imported): {', '.join(summary['legacy_files'])}.")
    first = summary.get("check_output", "").strip()
    if first and summary["check_status"] != "PASS":
        try:
            diagnostic = json.loads(first.splitlines()[0])
            label = diagnostic.get("primary_label") or diagnostic.get("diagnostic", {}).get("primary_label") or {}
            code = diagnostic.get("code") or diagnostic.get("diagnostic", {}).get("code")
            lines.append(f"First error: {code} at {relative(pathlib.Path(label.get('path', '?')))}:"
                         f"{label.get('line')}:{label.get('column')}: `{(label.get('source_line') or '').strip()}`")
        except (json.JSONDecodeError, AttributeError, IndexError):
            lines.append("First error:")
            lines.append("```")
            lines.append(first[:1200])
            lines.append("```")
    checked = summary.get("modules_checked")
    if checked is not None:
        failed = [record for record in checked if not record["ok"]]
        lines.append("")
        lines.append(f"Compiling one importing entry per module: {len(checked) - len(failed)}/{len(checked)} "
                     f"modules compile (of {summary['modules']}).")
        groups = collections.defaultdict(list)
        for record in failed:
            conversion = scalar_conversion(record)
            key = (f"{record.get('code')}" + (f", {conversion}" if conversion else ""), record.get("location") or "")
            groups[key].append(record)
        if failed:
            lines.append("")
            lines.append("| error | location | modules | example module | source |")
            lines.append("| --- | --- | ---: | --- | --- |")
            for (error, location), members in sorted(groups.items(), key=lambda item: -len(item[1])):
                example = members[0]
                lines.append(f"| {error} | {location} | {len(members)} | `{example['module']}` | "
                             f"`{(example.get('source_line') or '').replace('|', '/')}` |")
            lines.append("")
            lines.append("Failing modules: " + ", ".join(
                f"`{record['module']}` ({record.get('code')} {record.get('location') or ''})" for record in failed))
    lines.append("")
    return lines


# ---------------------------------------------------------------------------
# Stdlib check


def stdlib_modules() -> list[tuple[str, pathlib.Path]]:
    modules = []
    for path in sorted(STDLIB.rglob("*.lani")):
        match = re.search(r"^\s*module\s+([\w:]+)\s*;", path.read_text(), re.M)
        if match:
            modules.append((match.group(1), path))
    return modules


def stdlib_check(args) -> int:
    out = pathlib.Path(args.out) / "stdlib"
    out.mkdir(parents=True, exist_ok=True)
    modules = stdlib_modules()
    legacy = [relative(path) for path in sorted(STDLIB.rglob("*.lani"))
              if path not in {module_path for _, module_path in modules}]
    entry = out / "stdlib_all.lani"
    entry.write_text("".join(f"import {name};\n" for name, _ in modules)
                     + "\nfn main() -> i32 {\n    return 0;\n}\n")
    print(f"fixture_sweep: laniusc check over {len(modules)} stdlib modules "
          f"(not modules, skipped: {', '.join(legacy) or 'none'})", flush=True)
    command = [args.laniusc, "check", "--diagnostic-format", "json", "--stdlib-root", str(STDLIB), str(entry)]
    started = time.time()
    try:
        completed = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=args.timeout,
                                   env=dict(os.environ, LANIUS_READBACK_TIMEOUT_MS=args.readback_timeout_ms))
        status = "PASS" if completed.returncode == 0 else f"FAIL (exit {completed.returncode})"
        output = (completed.stdout + completed.stderr).strip()
    except subprocess.TimeoutExpired:
        status, output = "FAIL (timeout)", ""
    print(f"laniusc check: {status} in {time.time() - started:.1f} s")
    if output:
        print(output[:3000])
    summary = {"modules": len(modules), "legacy_files": legacy, "check_status": status, "check_output": output[:20000]}
    if args.each:
        summary["modules_checked"] = check_each_module(args, modules, out)
    (out / "stdlib_check.json").write_text(json.dumps(summary, indent=1) + "\n")
    print(f"wrote {relative(out / 'stdlib_check.json')}")
    return 0 if status == "PASS" else 1


def check_each_module(args, modules, out: pathlib.Path) -> list[dict]:
    started_all = time.time()
    daemon = Daemon(args.laniusc, args.memory_max, args.readback_timeout_ms, out / "daemon.stderr")
    results = []
    for number, (name, path) in enumerate(modules):
        if args.budget_seconds and time.time() - started_all > args.budget_seconds:
            print(f"fixture_sweep: stopping after {args.budget_seconds} s budget; "
                  f"{len(modules) - number} modules not checked", flush=True)
            break
        entry = out / f"import_{name.replace('::', '_')}.lani"
        entry.write_text(f"import {name};\n\nfn main() -> i32 {{\n    return 0;\n}}\n")
        elf = out / f"import_{name.replace('::', '_')}.elf"
        started = time.time()
        stderr_offset = stderr_size(out / "daemon.stderr")
        try:
            response = daemon.request({"id": f"module-{number}", "command": "compile", "emit": "x86_64",
                                       "input": str(entry), "output": str(elf), "stdlib_root": str(STDLIB)},
                                      args.timeout)
            record = {"module": name, "path": relative(path), "ok": response.get("ok") is True}
            if not record["ok"]:
                record.update(diagnostic_fields(response))
                detail = stage_detail(out / "daemon.stderr", stderr_offset)
                if detail:
                    record["stage_detail"] = detail
        except (TimeoutError, RuntimeError) as error:
            daemon.kill()
            daemon = Daemon(args.laniusc, args.memory_max, args.readback_timeout_ms, out / "daemon.stderr")
            record = {"module": name, "path": relative(path), "ok": False, "message": f"{type(error).__name__}"}
        record["elapsed_s"] = round(time.time() - started, 2)
        results.append(record)
        mark = "ok  " if record["ok"] else "FAIL"
        print(f"{mark} {record['elapsed_s']:6.1f}s {name}"
              + ("" if record["ok"] else f"\n    {record.get('code')} {record.get('location')} {record.get('message', '')[:200]}"),
              flush=True)
    daemon.kill()
    failed = [record for record in results if not record["ok"]]
    print(f"\n{len(results) - len(failed)}/{len(results)} stdlib modules compile on their own")
    return results


# ---------------------------------------------------------------------------


def main() -> int:
    global ROOT, STDLIB
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = parser.add_subparsers(dest="action", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--laniusc", default=str(ROOT / "target/release/laniusc"))
    common.add_argument("--out", default=str(DEFAULT_OUT))
    common.add_argument("--memory-max", default="8G")
    common.add_argument("--timeout", type=float, default=120.0, help="seconds per compile")
    common.add_argument("--readback-timeout-ms", default="20000",
                        help="GPU readback timeout for the daemon, so a hang fails fast")
    run = sub.add_parser("run", parents=[common], help="compile and run fixtures")
    run.add_argument("--shard", default="1/1", help="run every Nth fixture starting at I (I/N)")
    run.add_argument("--suite", action="append", choices=SUITES)
    run.add_argument("--pattern", action="append", default=[],
                     help="only fixtures whose path contains this (repeatable: any of them)")
    run.add_argument("--hang-seconds", type=float, default=15.0,
                     help="restart the daemon after a failed compile that took this long")
    run.add_argument("--budget-seconds", type=float, default=540.0,
                     help="stop the shard after this long (keeps a GPU hold under 10 minutes); 0 = no limit")
    run.add_argument("--resume", action="store_true",
                     help="keep this shard's earlier results and run only the fixtures it has not reached")
    rep = sub.add_parser("report", help="merge shard results and summarize")
    rep.add_argument("--out", default=str(DEFAULT_OUT))
    rep.add_argument("--write", help="also write the summary to this markdown file")
    dif = sub.add_parser("diff", help="compare this sweep with an earlier one, fixture by fixture")
    dif.add_argument("--base", required=True, help="the earlier sweep's --out directory")
    dif.add_argument("--out", default=str(DEFAULT_OUT), help="the newer sweep's --out directory")
    dif.add_argument("--write", help="also write the diff to this markdown file")
    std = sub.add_parser("stdlib", parents=[common], help="laniusc check over the whole stdlib")
    std.add_argument("--each", action="store_true", help="also compile one importing entry per module")
    std.add_argument("--budget-seconds", type=float, default=480.0,
                     help="stop --each after this long (keeps a GPU hold under 10 minutes); 0 = no limit")
    lst = sub.add_parser("list", help="print the fixtures and expectations without running anything")
    lst.add_argument("--suite", action="append", choices=SUITES)
    lst.add_argument("--pattern", action="append", default=[])
    for subparser in (run, std, lst):
        subparser.add_argument(
            "--source-root",
            help="take tests/ and stdlib/ from this tree instead of this checkout, so a pinned compiler "
                 "is swept with its own commit's fixtures and stdlib (e.g. a `git archive` export)")
    args = parser.parse_args()
    if getattr(args, "source_root", None):
        ROOT = pathlib.Path(args.source_root).resolve()
        STDLIB = ROOT / "stdlib"
        if not (ROOT / "tests").is_dir() or not STDLIB.is_dir():
            parser.error(f"--source-root {ROOT} needs tests/ and stdlib/")
    if args.action == "run":
        return sweep(args)
    if args.action == "report":
        return report(args)
    if args.action == "diff":
        return diff(args)
    if args.action == "stdlib":
        return stdlib_check(args)
    cases = load_cases(args.suite or list(SUITES), args.pattern)
    for case in cases:
        print(f"{relative(case.path)}: {json.dumps(describe_expectation(case))}")
    print(f"{len(cases)} fixtures; by kind: {dict(collections.Counter(case.kind for case in cases))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
