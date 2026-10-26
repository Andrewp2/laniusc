#!/usr/bin/env python3
"""Concurrent binary peers and independent capture resource/fault models."""
import ctypes
import os
from pathlib import Path
import random
import re
import signal
import subprocess
import sys
import tempfile
import time

CLI, FAULT = (str(Path(p).resolve()) for p in sys.argv[1:3])
CASES = 0
TRACE = "mmap,munmap,pipe2,close,fcntl,fork,waitid,wait4,poll,read,write,clock_gettime,rt_sigaction,kill"


def run(arguments, data=b"", expected=0, out=None, err=None):
    global CASES
    result = subprocess.run([CLI, *arguments], input=data, capture_output=True, timeout=8)
    assert result.returncode == expected, (arguments, result)
    if out is not None:
        assert result.stdout == out, (arguments, result)
    if err is not None:
        assert result.stderr == err, (arguments, result)
    CASES += 1
    return result


def ledger(trace, close_model=False, allowed_unreaped=()):
    mappings, descriptors, children = {}, set(), set()
    calls = []
    for body in trace.splitlines():
        match = re.match(r"([a-z_0-9]+)\(", body)
        if match:
            calls.append((match[1], body))
        match = re.match(r"mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)", body)
        if match:
            address, length = int(match[2], 16), int(match[1])
            assert address not in mappings, body
            mappings[address] = length
        match = re.match(r"munmap\((0x[0-9a-f]+), (\d+)\) += 0", body)
        if match:
            assert mappings.pop(int(match[1], 16), None) == int(match[2]), body
        match = re.match(r"pipe2\(\[(\d+), (\d+)\], O_CLOEXEC\) += 0", body)
        if match:
            for descriptor in map(int, match.groups()):
                assert descriptor not in descriptors, body
                descriptors.add(descriptor)
        match = re.match(r"close\((\d+)\) += (.*)", body)
        if match and (match[2] == "0" or (close_model and match[2].startswith("-1 EIO") and "INJECTED" in body)):
            # Fake EIO skips the kernel; model Linux's ownership-ending close
            # contract for that reporting branch and separately forbid retry.
            descriptors.discard(int(match[1]))
        match = re.match(r"fork\(\) += (\d+)", body)
        if match:
            children.add(int(match[1]))
        match = re.match(r"wait4\(.*\) += (\d+)(?: |$)", body)
        if match and int(match[1]) > 0:
            assert int(match[1]) in children, body
            children.remove(int(match[1]))
    assert not mappings and not descriptors and children == set(allowed_unreaped), (mappings, descriptors, children, trace)
    return calls


def reached_injections(trace, injections):
    for injection in injections:
        syscall, *settings = injection.split(":")
        options = dict(item.split("=", 1) for item in settings)
        start = re.fullmatch(r"(\d+)(\+)?", options["when"])
        assert start, injection
        first, repeated = int(start[1]), bool(start[2])
        calls = [line for line in trace.splitlines() if line.startswith(syscall + "(")]
        expected = set(range(first, len(calls) + 1)) if repeated else {first}
        actual = {i for i, line in enumerate(calls, 1) if "INJECTED" in line}
        assert expected and actual == expected, (injection, trace)
        for ordinal in actual:
            result = calls[ordinal - 1].rsplit(" = ", 1)[1].split()
            if "error" in options:
                assert result[:2] == ["-1", options["error"]], (injection, trace)
            else:
                assert result[0] == options["retval"], (injection, trace)


def traced(executable, arguments=(), inject=(), expected=0, data=b"", out=b"", closed=None, close_model=False, allow_incomplete=False):
    global CASES
    if isinstance(inject, str):
        inject = [inject]
    with tempfile.TemporaryDirectory(prefix="capture-trace-") as directory:
        path = Path(directory) / "trace"
        command = ["strace", "-qq", "-o", str(path), "-e", "trace=" + TRACE]
        for item in inject:
            command += ["-e", "inject=" + item]
        descriptors = None
        kwargs = {"stdout": subprocess.PIPE, "stderr": subprocess.PIPE}
        if closed:
            reader, writer = os.pipe()
            os.close(reader)
            kwargs[closed] = writer
            descriptors = writer
        result = subprocess.run([*command, executable, *arguments], input=data, timeout=8, **kwargs)
        if descriptors is not None:
            os.close(descriptors)
        trace = path.read_text()
        assert result.returncode == expected, (inject, result, trace)
        if closed != "stdout":
            assert result.stdout == out, (inject, result, trace)
        reached_injections(trace, inject)
        incomplete = ()
        if allow_incomplete:
            found = re.search(rb"cleanup-incomplete pid=(\d+)", result.stderr)
            assert found, (result, trace)
            incomplete = (int(found[1]),)
        calls = ledger(trace, close_model, incomplete)
        CASES += 1
        return result, trace, calls, incomplete


# Each peer fills both outputs before it reads stdin. Sequential communication
# deadlocks here; binary reference results are computed independently in Python.
peer = """import os,sys
n=int(sys.argv[1]);seed=int(sys.argv[2])
a=bytes((i*17+seed)%256 for i in range(n))
b=bytes((i*29+seed+3)%256 for i in range(n))
def put(fd,data):
 while data:
  count=os.write(fd,data);data=data[count:]
for i in range(0,n,3071):
 put(1,a[i:i+3071]);put(2,b[i:i+3071])
d=sys.stdin.buffer.read();put(1,d[::-1]);put(2,len(d).to_bytes(8,'little'))
"""
rng = random.Random(0xC4A7)
for n in (0, 1, 1023, 1024, 1025, 65537, 262147, 1048577):
    seed = rng.randrange(256)
    data = rng.randbytes(n + 19)
    a = bytes((i * 17 + seed) % 256 for i in range(n))
    b = bytes((i * 29 + seed + 3) % 256 for i in range(n))
    run(["--", sys.executable, "-c", peer, str(n), str(seed)], data, out=a + data[::-1], err=b + len(data).to_bytes(8, "little"))

for n in (0, 1, 1023, 1024, 1025):
    code = f"import os;os.write(1,b'x'*{n});os.write(2,b'y'*{n})"
    run(["--max-stdout-bytes", str(n), "--max-stderr-bytes", str(n), "--", sys.executable, "-c", code], out=b"x" * n, err=b"y" * n)
for option, channel, reason in (("--max-stdout-bytes", 1, 3), ("--max-stderr-bytes", 2, 4)):
    result = run([option, "3", "--", sys.executable, "-c", f"import os;os.write({channel},b'abcZ')"], expected=125, out=b"")
    assert f"reason={reason}".encode() in result.stderr and (b"stdout-read=4" if channel == 1 else b"stderr-read=4") in result.stderr
run(["--", "/bin/sh", "-c", "exit 23"], expected=23, out=b"", err=b"")
run(["--", "/bin/sh", "-c", "exit 125"], expected=125, out=b"", err=b"")
run(["--", "/bin/sh", "-c", "kill -TERM $$"], expected=143, out=b"", err=b"")
result = run(["--timeout-ms", "20", "--", "/bin/sleep", "1"], expected=124, out=b"")
assert b"reason=6" in result.stderr and b"cleanup-incomplete" not in result.stderr
result = run(["--max-operations", "0", "--", "/bin/cat"], b"abc", expected=125, out=b"")
assert b"reason=5" in result.stderr
run(["--", "/no/such/command"], expected=127, out=b"")
run(["--max-input-bytes", "2", "--", "/bin/cat"], b"abc", expected=125, out=b"")
for args in ([], ["--help", "/bin/true"], ["--timeout-ms", "-1", "/bin/true"], ["--max-operations", "1000000001", "/bin/true"], ["--bad"], ["--timeout-ms", "1", "--timeout-ms", "2", "/bin/true"]):
    run(args, expected=125, out=b"")
run(["--help"], err=b"")

_, baseline, calls, _ = traced(FAULT)
assert sum(name == "mmap" for name, _ in calls) == 7, baseline  # 3 spawn + 4 capture allocations
first_flags = next(i for i, (name, body) in enumerate(calls) if name == "fcntl" and "F_SETFL" in body)
assert not any(name == "mmap" for name, _ in calls[first_flags:]), baseline
for number in range(4, 8):
    traced(FAULT, inject=f"mmap:error=ENOMEM:when={number}", expected=82)
for number in range(1, 10):
    traced(FAULT, inject=f"fcntl:error=EIO:when={number}", expected=84)
for inject, expected in [
    ("rt_sigaction:error=EPERM:when=2", 81),
    ("clock_gettime:error=EIO:when=2", 83),
    ("clock_gettime:error=EIO:when=3", 83),
    ("clock_gettime:error=EIO:when=4", 84),
    ("poll:error=EINTR:when=1", 0),
    ("poll:error=EIO:when=1", 85),
    ("poll:retval=4:when=1", 85),
    ("write:error=EINTR:when=1", 0),
    ("write:error=EAGAIN:when=1", 0),
    ("write:error=EIO:when=1", 86),
    ("write:retval=0:when=1", 86),
    ("read:error=EINTR:when=2", 0),
    ("read:error=EAGAIN:when=2", 0),
    ("read:error=EIO:when=2", 87),
    ("read:retval=1025:when=2", 87),
    ("waitid:error=EINTR:when=1", 0),
    ("waitid:error=EIO:when=1", 89),
    ("wait4:error=EINTR:when=1", 0),
    ("wait4:error=EIO:when=1", 89),
]:
    traced(FAULT, inject=inject, expected=expected)
close_ordinal = sum(name == "close" for name, _ in calls[:first_flags]) + 1
_, _, failed_closes, _ = traced(FAULT, inject=f"close:error=EIO:when={close_ordinal}", expected=86, close_model=True)
failed_fd = next(int(re.match(r"close\((\d+)\)", body)[1]) for name, body in failed_closes if name == "close" and "INJECTED" in body)
assert sum(body.startswith(f"close({failed_fd})") for _, body in failed_closes) == 1

# Full CLI allocations and actual broken output pipes retain cleanup evidence.
_, _, cli_calls, _ = traced(CLI, ["--", "/bin/true"])
for number in range(1, sum(name == "mmap" for name, _ in cli_calls) + 1):
    traced(CLI, ["--", "/bin/true"], inject=f"mmap:error=ENOMEM:when={number}", expected=125)
traced(CLI, ["--", "/bin/true"], inject="rt_sigaction:error=EPERM:when=1", expected=125)
traced(CLI, ["--", "/bin/cat"], inject="read:error=EIO:when=1", expected=125)
publication, _, _, _ = traced(CLI, ["--", "/bin/echo", "data"], inject="write:error=EIO:when=1", expected=125)
assert b"reason=11 errno=5" in publication.stderr and b"stdout-read=5" in publication.stderr
_, _, aborted_calls, _ = traced(CLI, ["--", "/bin/sleep", "1"], inject="poll:error=EIO:when=1", expected=125)
poll_index = next(i for i, (name, _) in enumerate(aborted_calls) if name == "poll")
close_number = sum(name == "close" for name, _ in aborted_calls[:poll_index]) + 1
failure, _, cleanup_calls, _ = traced(CLI, ["--", "/bin/sleep", "1"], inject=["poll:error=EIO:when=1", f"close:error=EIO:when={close_number}"], expected=125, close_model=True)
assert b"reason=12 errno=5" in failure.stderr and b"cleanup-errno=5" in failure.stderr
failed_fd = next(int(re.match(r"close\((\d+)\)", body)[1]) for name, body in cleanup_calls if name == "close" and "INJECTED" in body)
assert sum(body.startswith(f"close({failed_fd})") for _, body in cleanup_calls) == 1
traced(CLI, ["--help"], closed="stdout", expected=125)
publication, _, _, _ = traced(CLI, ["--", "/bin/echo", "data"], closed="stdout", expected=125)
assert b"reason=11 errno=32" in publication.stderr and b"stdout-read=5" in publication.stderr
traced(CLI, ["--bad"], closed="stderr", expected=125)

# Deliberately prevent successful final reaping. WNOWAIT may still observe a
# terminal status without consuming the child. The CLI must disclose
# retained ownership, not claim reap. This harness adopts/reaps that exact
# killed descendant after the CLI exits; no unrelated PID is signaled.
libc = ctypes.CDLL(None, use_errno=True)
assert libc.prctl(36, 1, 0, 0, 0) == 0
try:
    for args, injection, expected, reason in [
        (["--timeout-ms", "0"], "wait4:retval=0:when=1+", 124, 6),
        (["--timeout-ms", "30"], "wait4:error=EINTR:when=1+", 124, 6),
        (["--timeout-ms", "1000", "--max-operations", "50"], "wait4:error=EINTR:when=1+", 125, 5),
    ]:
        result, trace, _, retained = traced(CLI, [*args, "--cleanup-ms", "10", "--", "/bin/sleep", "2"], inject=injection, expected=expected, allow_incomplete=True)
        assert f"reason={reason}".encode() in result.stderr
        pid = retained[0]
        assert re.search(rf"kill\({pid}, SIGKILL\) += 0", trace), trace
        if "EINTR" in injection:
            assert 2 <= trace.count("wait4(") < 100, trace
        limit = time.monotonic() + 2
        while True:
            waited, status = os.waitpid(pid, os.WNOHANG)
            if waited:
                assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGKILL
                break
            assert time.monotonic() < limit
            time.sleep(0.005)
finally:
    assert libc.prctl(36, 0, 0, 0, 0) == 0

print(f"capture oracle: {CASES} native cases; concurrent binary peers, 4 capture allocation faults, parent FD/mapping/reaping ledgers balanced; incomplete-reap model disclosed and harness-reaped")
