#!/usr/bin/env python3
"""Independent native peers plus per-process resource/fault ledgers."""
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile


RUNNER, PROBE, SIGNAL_PEER = map(lambda s: str(Path(s).resolve()), sys.argv[1:4])
TRACE = "mmap,munmap,fcntl,open,openat,close,pipe2,fork,wait4,read,write,close_range,dup3,execve,kill,rt_sigaction,chdir"
CASES = 0


def run(args, expected=0, out=None, err=None, **kwargs):
    global CASES
    result = subprocess.run([RUNNER, *args], capture_output=True, timeout=8, **kwargs)
    assert result.returncode == expected, (args, result)
    if out is not None:
        assert result.stdout == out, (args, result)
    if err is not None:
        assert result.stderr == err, (args, result)
    CASES += 1
    return result


def records(trace):
    """Rejoin strace's interleaved unfinished calls before interpreting them."""
    pending = {}
    result = []
    for line in trace.splitlines():
        match = re.match(r"^(\d+) +(.*)$", line)
        if not match:
            continue
        pid, body = int(match[1]), match[2]
        if body.endswith("<unfinished ...>"):
            assert pid not in pending, line
            pending[pid] = body[: -len("<unfinished ...>")].rstrip()
        elif body.startswith("<... ") and " resumed>" in body:
            assert pid in pending, line
            body = pending.pop(pid) + body.split(" resumed>", 1)[1]
            result.append((pid, body))
        else:
            result.append((pid, body))
    # A killed tracee can leave its last syscall unfinished.
    assert all(any(p == pid and "killed by" in s for p, s in result) for pid in pending), pending
    return result


def ledger(trace, close_error_model=False):
    events = records(trace)
    root = events[0][0]
    mappings, descriptors, children = {}, set(), set()
    for pid, body in events:
        if pid != root:
            continue
        match = re.match(r"mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+)", body)
        if match:
            address, size = int(match[2], 16), int(match[1])
            assert address not in mappings, body
            mappings[address] = size
        match = re.match(r"munmap\((0x[0-9a-f]+), (\d+)\) += 0", body)
        if match:
            address, size = int(match[1], 16), int(match[2])
            assert mappings.pop(address, None) == size, body
        match = re.match(r"(?:open(?:at)?\(.*|fcntl\(\d+, F_DUPFD_CLOEXEC, \d+\)) += (\d+)(?: |$)", body)
        if match:
            descriptor = int(match[1])
            assert descriptor not in descriptors, body
            descriptors.add(descriptor)
        match = re.match(r"pipe2\(\[(\d+), (\d+)\], O_CLOEXEC\) += 0", body)
        if match:
            for descriptor in map(int, match.groups()):
                assert descriptor not in descriptors, body
                descriptors.add(descriptor)
        match = re.match(r"close\((\d+)\) += 0", body)
        if match:
            descriptors.discard(int(match[1]))
        if close_error_model:
            # Injection skips the kernel close. Model Linux's documented EIO
            # release contract for this reporting-only regression, while still
            # requiring exactly one attempt and all other resources balanced.
            match = re.match(r"close\((\d+)\) += -1 EIO .*INJECTED", body)
            if match:
                descriptors.discard(int(match[1]))
        match = re.match(r"fork\(\) += (\d+)", body)
        if match:
            children.add(int(match[1]))
        match = re.match(r"wait4\(.*\) += (\d+)(?: |$)", body)
        if match and int(match[1]) > 0:
            assert int(match[1]) in children, body
            children.remove(int(match[1]))
    assert not mappings and not descriptors and not children, (mappings, descriptors, children, trace)
    # This implementation's child performs no allocation before attempting exec.
    child_ids = {p for p, s in events if s.startswith("execve(") and p != root}
    for pid in child_ids:
        before_exec = []
        for p, s in events:
            if p == pid:
                if s.startswith("execve("):
                    break
                before_exec.append(s)
        assert not any(s.startswith(("mmap(", "munmap(")) for s in before_exec), before_exec
    return [(p, s) for p, s in events if p == root]


def traced(executable, args=(), inject=None, expected=0, follow=True, close_error_model=False, **kwargs):
    global CASES
    with tempfile.TemporaryDirectory(prefix="lanius-command-trace-") as directory:
        path = Path(directory) / "trace"
        command = ["strace", "-qq", "-s", "4096", "-o", str(path), "-e", "trace=" + TRACE]
        if follow:
            command.append("-f")
        if inject:
            for item in ([inject] if isinstance(inject, str) else inject):
                command += ["-e", "inject=" + item]
        result = subprocess.run([*command, executable, *args], capture_output=True, timeout=8, **kwargs)
        trace = path.read_text()
        if not follow:
            trace = "\n".join("0 " + line for line in trace.splitlines())
        assert result.returncode == expected, (inject, result, trace)
        assert result.stdout == b"", (inject, result, trace)
        if inject:
            assert "INJECTED" in trace or (isinstance(inject, str) and ":signal=SIGKILL:" in inject and "killed by SIGKILL" in trace), (inject, trace)
        events = ledger(trace, close_error_model)
        CASES += 1
        return result, trace, events


with tempfile.TemporaryDirectory(prefix="lanius-command-peer-") as directory:
    root = Path(directory)
    source, output, errors = (root / name for name in ("source", "output", "errors"))
    source.write_bytes(b"pear\napple\nbanana\napple\n")
    run(["--", "/usr/bin/sort", "-u"], input=source.read_bytes(), out=b"apple\nbanana\npear\n", err=b"")
    run(["--stdin", str(source), "--stdout", str(output), "--stderr", str(errors), "--", "/usr/bin/sort", "-r"], out=b"", err=b"")
    assert output.read_bytes() == b"pear\nbanana\napple\napple\n" and errors.read_bytes() == b""
    run(["--append", "--stdout", str(output), "--", "/bin/echo", "more"], out=b"", err=b"")
    assert output.read_bytes().endswith(b"apple\nmore\n")
    run(["--clear-env", "--env", "PATH=/bin:/usr/bin", "--env", "MODE=first", "--env", "MODE=last", "--cwd", directory, "--", "sh", "-c", 'printf "%s|%s" "$MODE" "$PWD"'], out=("last|" + directory).encode(), err=b"")
    run(["--env", "COMMAND_OVERRIDE=replaced", "--", "/bin/sh", "-c", 'test "$COMMAND_OVERRIDE" = replaced'], env={**os.environ, "COMMAND_OVERRIDE": "original"}, out=b"", err=b"")
    # Bytes survive argument capture, explicit environment, and execve unchanged.
    code = b"import os,sys;sys.stdout.buffer.write(os.fsencode(sys.argv[1])+b'|'+os.environb[b'RAW'])"
    run([b"--clear-env", b"--env", b"RAW=\xff\x80", b"--", os.fsencode(sys.executable), b"-c", code, b"\xfe\x81"], out=b"\xfe\x81|\xff\x80", err=b"")
    code = "import os,sys;sys.stdout.buffer.write(b'|'.join(os.fsencode(a) for a in sys.argv[1:]))"
    run(["--", sys.executable, "-c", code, "", "--status", "a b", "quote'\"", "\n"], out=b"|--status|a b|quote'\"|\n", err=b"")
    run(["--status", "--", "/bin/sh", "-c", "exit 23"], expected=23, out=b"", err=b"run-command: startup=unconfirmed exit=23\n")
    run(["--", "/bin/sh", "-c", "exit 125"], expected=125, out=b"", err=b"")
    run(["--", "/bin/sh", "-c", "exit 127"], expected=127, out=b"", err=b"")
    run(["--status", "--", "/bin/sh", "-c", "kill -TERM $$"], expected=143, out=b"", err=b"run-command: startup=unconfirmed signal=15\n")
    # This native peer does not silently change the SIGPIPE disposition at startup.
    run(["--", SIGNAL_PEER], expected=141, out=b"", err=b"")
    run(["--sigpipe", "inherit", "--", SIGNAL_PEER], expected=42, out=b"", err=b"")
    executable = root / "local-command"
    executable.write_bytes(b"#!/bin/sh\nprintf local")
    executable.chmod(0o700)
    for path in ("", ":", "/missing:", ":/missing"):
        run(["--clear-env", "--env", "PATH=" + path, "--cwd", directory, "--", "local-command"], out=b"local", err=b"")
    denied = root / "denied"
    denied.write_text("not executable")
    denied.chmod(0o600)
    result = run(["--clear-env", "--env", "PATH=" + directory + ":/missing", "--", "denied"], expected=126, out=b"")
    assert b"reported-child-failure stage=8 errno=13" in result.stderr
    denied.chmod(0o700)
    result = run(["--", str(denied)], expected=126, out=b"")
    assert b"reported-child-failure stage=8 errno=8" in result.stderr  # no shell fallback
    result = run(["--cwd", str(root / "missing"), "--", "/bin/true"], expected=126, out=b"")
    assert b"reported-child-failure stage=7 errno=2" in result.stderr
    result = run(["--", "/no/such/command"], expected=127, out=b"")
    assert b"reported-child-failure stage=8 errno=2" in result.stderr
    result = run(["--clear-env", "--", "true"], expected=125, out=b"")
    assert b"runner-failure stage=1 errno=0" in result.stderr
    for args in ([], ["--env", "BAD"], ["--env", "=x", "/bin/true"], ["--cwd"], ["--help", "/bin/true"], ["--unknown", "/bin/true"], ["--clear-env", "--clear-env", "/bin/true"]):
        run(args, expected=125, out=b"")
    run(["--help"], out=b"Usage: run-command [--clear-env] [--env KEY=VALUE] [--cwd DIR] [--stdin FILE] [--stdout FILE] [--stderr FILE] [--append] [--sigpipe default|inherit] [--status] -- PROGRAM [ARG...]\n", err=b"")
    # Large real workload verifies streaming rather than argument introspection.
    payload = bytes(range(256)) * 8192
    run(["--", "/bin/cat"], input=payload, out=payload, err=b"")

# Startup uncertainty is observed independently of all diagnostics/writes by
# dedicated distinct probe exit codes. Signals only target our own children.
_, baseline, events = traced(PROBE, expected=42)
assert sum(s.startswith("mmap(") for _, s in events) == 3
for number in range(1, 4):
    traced(PROBE, inject=f"mmap:error=ENOMEM:when={number}", expected=46)
    traced(PROBE, inject=f"openat:error=EMFILE:when={number}", expected=46)
for inject, expected in [
    ("pipe2:error=EMFILE:when=1", 46),
    ("fork:error=EAGAIN:when=1", 46),
    ("close_range:error=ENOSYS:when=1", 42),
    ("dup3:error=EBADF:when=1", 42),
    ("rt_sigaction:error=EIO:when=1", 42),
    ("write:error=EINTR:when=1", 42),
    ("read:error=EINTR:when=1", 42),
    ("wait4:error=EINTR:when=1", 42),
    ("write:error=EIO:when=1", 43),
    ("write:retval=1:when=1", 44),
    ("write:poke_enter=@arg2=444d434c0400000002000000434d434c:when=1", 44),
    ("close_range:signal=SIGKILL:when=1", 45),
    ("read:error=EIO:when=1", 44),
    ("read:retval=1:when=1", 44),
    ("wait4:error=EIO:when=1", 44),
]:
    traced(PROBE, inject=inject, expected=expected)

# Parent-only injection makes every live allocation in the real runner fail
# independently without faulting libc/Python/the selected executable.
clean_environment = {"PATH": "/bin:/usr/bin", "COMMAND_TEST": "raw"}
_, _, events = traced(RUNNER, ["--", "/bin/true"], follow=False, env=clean_environment)
allocation_count = sum(s.startswith("mmap(") for _, s in events)
for number in range(1, allocation_count + 1):
    traced(RUNNER, ["--", "/bin/true"], inject=f"mmap:error=ENOMEM:when={number}", expected=125, follow=False, env=clean_environment)
for number in range(1, 4):
    traced(RUNNER, ["--", "/bin/true"], inject=f"fcntl:error=EMFILE:when={number}", expected=125, follow=False, env=clean_environment)
traced(RUNNER, ["--", "/bin/true"], inject="rt_sigaction:error=EPERM:when=1", expected=125, follow=False, env=clean_environment)
traced(RUNNER, ["--", "/bin/true"], inject="wait4:error=EIO:when=1", expected=125, follow=False, env=clean_environment)
traced(RUNNER, ["--", "/bin/true"], inject=["wait4:error=EIO:when=1", "kill:error=EPERM:when=1"], expected=125, follow=False, env=clean_environment)

with tempfile.TemporaryDirectory(prefix="lanius-command-close-") as directory:
    source = str(Path(directory) / "input")
    redirected = str(Path(directory) / "output")
    errors = str(Path(directory) / "errors")
    Path(source).write_bytes(b"input")
    args = ["--stdin", source, "--stdout", redirected, "--stderr", errors, "--", "/bin/true"]
    _, _, events = traced(RUNNER, args, follow=False, env=clean_environment)
    owners = [int(re.search(r" = (\d+)$", body)[1]) for _, body in events if body.startswith("open(")]
    assert len(owners) == 3
    opened = owners[0]
    closes = [body for _, body in events if body.startswith("close(")]
    ordinal = next(i + 1 for i, body in enumerate(closes) if body.startswith(f"close({opened})"))
    result, _, events = traced(RUNNER, args, inject=f"close:error=EIO:when={ordinal}", expected=125, follow=False, close_error_model=True, env=clean_environment)
    assert b"runner-failure stage=13 errno=5" in result.stderr
    for descriptor in owners:
        assert sum(body.startswith(f"close({descriptor})") for _, body in events) == 1
    for number in range(1, 4):
        traced(RUNNER, args, inject=f"open:error=EACCES:when={number}", expected=125, follow=False, env=clean_environment)

# Actual closed pipes, including diagnostic failure after a child was reaped.
for args, channel in [(["--help"], "stdout"), (["--status", "--", "/bin/true"], "stderr"), (["--bad"], "stderr")]:
    reader, writer = os.pipe()
    os.close(reader)
    kwargs = {"stdout": subprocess.PIPE, "stderr": subprocess.PIPE, channel: writer}
    result = subprocess.run([RUNNER, *args], timeout=8, **kwargs)
    os.close(writer)
    assert result.returncode == 125, (args, result)
    CASES += 1

print(f"command oracle: {CASES} native cases, {allocation_count} runner allocation fault points; parent FD/mapping/reaping ledgers balanced")
