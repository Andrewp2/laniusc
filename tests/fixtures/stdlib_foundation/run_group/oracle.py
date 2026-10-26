#!/usr/bin/env python3
"""Independent ownership, signal-order and exact resource oracle for run-group."""
import ctypes
import errno
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

CLI, PEER, MODE = sys.argv[1:4]
TRACE = "mmap,munmap,openat,pipe2,fcntl,close,fork,setpgid,getpgid,read,write,wait4,waitid,kill,poll,clock_gettime,rt_sigaction"
CASES = 0


def calls(trace, name):
    return [line for line in trace.splitlines() if line.startswith(name + "(")]


def injected(trace, name, result, ordinal=1, persistent=False):
    actual = calls(trace, name)
    marked = [line for line in trace.splitlines() if "INJECTED" in line]
    expected = actual[ordinal - 1:] if persistent else actual[ordinal - 1:ordinal]
    assert expected and marked == expected, (name, ordinal, persistent, trace)
    for line in marked:
        assert line.rsplit(" = ", 1)[1].split()[:len(result)] == result, line


def ledger(trace, retained=()):
    mappings, descriptors, children = {}, set(), set()
    requests, after_fork = [], False
    for line in trace.splitlines():
        match = re.match(r"mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+|-1)(?: |$)", line)
        if match:
            assert not after_fork, ("post-spawn app allocation", line)
            length, address = int(match[1]), match[2]
            requests.append(length)
            if address != "-1":
                assert address not in mappings, line
                mappings[address] = length
        match = re.match(r"munmap\((0x[0-9a-f]+), (\d+)\) += 0", line)
        if match:
            assert mappings.pop(match[1], None) == int(match[2]), line
        match = re.match(r"(?:openat\(.*|fcntl\(\d+, F_DUPFD_CLOEXEC, \d+)\) += (\d+)(?: |$)", line)
        if match:
            descriptor = int(match[1])
            assert descriptor not in descriptors, line
            descriptors.add(descriptor)
        match = re.match(r"pipe2\(\[(\d+), (\d+)\], O_CLOEXEC\) += 0", line)
        if match:
            for descriptor in map(int, match.groups()):
                assert descriptor not in descriptors, line
                descriptors.add(descriptor)
        match = re.match(r"close\((\d+)\) += 0", line)
        if match:
            descriptor = int(match[1])
            assert descriptor in descriptors, ("unowned/double close", line, trace)
            descriptors.remove(descriptor)
        match = re.match(r"fork\(\) += (\d+)", line)
        if match:
            after_fork = True
            children.add(int(match[1]))
        match = re.match(r"wait4\((\d+),.*\) += (\d+)(?: |$)", line)
        if match and int(match[2]) > 0:
            assert match[1] == match[2] and int(match[2]) in children, line
            children.remove(int(match[2]))
    assert not mappings and not descriptors and children == set(retained), (mappings, descriptors, children, trace)
    return requests


def fields(result):
    records = [line for line in result.stderr.splitlines() if line.startswith(b"run-group: ")]
    assert len(records) == 1, result
    return dict(part.decode().split("=", 1) for part in records[0].split()[1:] if b"=" in part)


def run(arguments, expected=0, environment=None):
    global CASES
    result = subprocess.run([CLI, *arguments], input=b"unused stdin", capture_output=True, timeout=8, env=environment, start_new_session=True)
    assert result.returncode == expected, (arguments, result)
    CASES += 1
    return result


def traced(arguments, expected, injection=None, retained=False, closed_stderr=False, gate=None):
    global CASES
    with tempfile.TemporaryDirectory(prefix="run-group-trace-") as temporary:
        path = Path(temporary) / "trace"
        stdout_path, stderr_path = Path(temporary) / "stdout", Path(temporary) / "stderr"
        command = ["strace", "-qq", "-e", "signal=none", "-o", str(path), "-e", "trace=" + TRACE]
        if injection:
            command += ["-e", "inject=" + injection]
        command += [CLI, *arguments]
        descriptor = None
        # Regular files deliberately do not await EOF from live descendants.
        # The oracle must first regain control to adopt and clean them up.
        stdout_file, stderr_file = stdout_path.open("wb"), stderr_path.open("wb")
        output = {"stdout": stdout_file, "stderr": stderr_file}
        if closed_stderr:
            reader, descriptor = os.pipe()
            os.close(reader)
            output["stderr"] = descriptor
        try:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, start_new_session=True, **output)
            try:
                if gate is not None:
                    end = time.monotonic() + 2
                    while True:
                        seen = path.read_text() if path.exists() else ""
                        if calls(seen, "wait4"):
                            assert not calls(seen, "kill"), seen
                            gate.write_bytes(b"R")
                            break
                        assert process.poll() is None and time.monotonic() < end, seen
                        time.sleep(0.001)
                code = process.wait(timeout=8)
            except BaseException:
                process.kill()
                process.wait(timeout=1)
                raise
        finally:
            stdout_file.close()
            stderr_file.close()
            if descriptor is not None:
                os.close(descriptor)
        result = subprocess.CompletedProcess(command, code, stdout_path.read_bytes(), None if closed_stderr else stderr_path.read_bytes())
        trace = path.read_text()
        assert result.returncode == expected, (arguments, injection, result, trace)
        child = int(re.search(r"fork\(\) += (\d+)", trace)[1]) if calls(trace, "fork") else None
        keep = (child,) if retained else ()
        requests = ledger(trace, keep)
        CASES += 1
        return result, trace, requests, child


def cleanup_owned():
    # Only this single-threaded oracle's actual unreaped children can be
    # signaled. Descendants become its children through Linux subreaping.
    end = time.monotonic() + 3
    while time.monotonic() < end:
        children = Path(f"/proc/self/task/{os.getpid()}/children").read_text().split()
        if not children:
            return
        for value in children:
            child = int(value)
            try:
                observed, _ = os.waitpid(child, os.WNOHANG)
                if observed == 0:
                    os.kill(child, signal.SIGKILL)
            except ChildProcessError:
                pass
            except ProcessLookupError:
                pass
        time.sleep(0.005)
    raise AssertionError("independent oracle cleanup incomplete")


def adopted_status(pid, expected_signal=None, expected_code=None, alive=False):
    end = time.monotonic() + 2
    while True:
        observed = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        if alive:
            assert observed is None, observed
            os.kill(pid, signal.SIGKILL)
            return adopted_status(pid, expected_signal=signal.SIGKILL)
        if observed is not None:
            child, status = os.waitpid(pid, 0)
            assert child == pid
            if expected_signal is not None:
                allowed = expected_signal if isinstance(expected_signal, tuple) else (expected_signal,)
                assert os.WIFSIGNALED(status) and os.WTERMSIG(status) in allowed, status
            if expected_code is not None:
                assert os.WIFEXITED(status) and os.WEXITSTATUS(status) == expected_code, status
            return
        assert time.monotonic() < end, pid
        time.sleep(0.005)


def escalation(trace, pid):
    events = calls(trace, "kill")
    assert len(events) == 4, trace
    targets = [(int(re.match(r"kill\((-?\d+),", line)[1]), re.search(r", (SIG[A-Z0-9]+)\)", line)[1]) for line in events]
    assert targets == [(-pid, "SIGTERM"), (pid, "SIGTERM"), (-pid, "SIGKILL"), (pid, "SIGKILL")], trace
    start = trace.index(events[0])
    finish = trace.index(events[-1]) + len(events[-1])
    assert "wait4(" not in trace[start:finish] and "waitid(" not in trace[start:finish], trace
    terminal = next(line for line in calls(trace, "wait4") if re.search(r"\) += " + str(pid) + r"(?: |$)", line))
    assert trace.index(terminal) > finish, trace


def normal_cases():
    for code in (0, 7, 124, 125, 255):
        result = run(["--status", "--", sys.executable, PEER, "identity", "unused", str(code)], code)
        pid, pgid, parent = map(int, result.stdout.split(b","))
        report = fields(result)
        assert pid == pgid and pgid != os.getpgrp() and parent > 1
        assert report["pid"] == str(pid) and report["group-confirmed"] == "true" and report["reaped"] == "true"
        assert report["term-scope"] == "0" and report["group-kill-attempted"] == "false" and report["exit"] == str(code)
    environment = dict(os.environ, RUN_GROUP_TEST="inherited")
    result = run(["--", sys.executable, PEER, "arguments", "unused", "", "--timeout-ms", "λ", "\udcff"], environment=environment)
    assert result.stdout == b"\x00--timeout-ms\x00\xce\xbb\x00\xff" and result.stderr == b"inherited"
    result = run(["--", "/bin/sh", "-c", "kill -TERM $$"], 143)
    assert result.stdout == result.stderr == b""
    assert run(["--", "true"]).stdout == b""
    assert run(["--help"]).stdout.startswith(b"Usage: run-group ")
    for arguments in ([], ["--bad"], ["--help", "/bin/true"], ["--timeout-ms", "-1", "/bin/true"], ["--timeout-ms", "+1", "/bin/true"], ["--timeout-ms", "86400001", "/bin/true"], ["--grace-ms", "60001", "/bin/true"], ["--reap-ms", "60001", "/bin/true"], ["--max-operations", "10000001", "/bin/true"], ["--status", "--status", "/bin/true"], ["--timeout-ms", "1", "--timeout-ms", "2", "/bin/true"]):
        result, trace, _, _ = traced(arguments, 125)
        assert not calls(trace, "fork") and result.stdout == b""
    result, trace, _, _ = traced(["--", "/no/such/run-group-program"], 127)
    assert fields(result)["reaped"] == "true" and not calls(trace, "kill")


def group_cases():
    with tempfile.TemporaryDirectory(prefix="run-group-family-") as temporary:
        for mode in ("cooperate", "stubborn", "leader-exits", "moved-leader", "escape", "normal-orphan"):
            path = Path(temporary) / mode
            gate = Path(temporary) / (mode + "-go") if mode == "moved-leader" else None
            expected = 7 if mode == "normal-orphan" else 124
            arguments = ["--status", "--timeout-ms", "500", "--grace-ms", "40", "--reap-ms", "500", "--", sys.executable, PEER, mode, str(path)]
            if gate is not None:
                arguments.append(str(gate))
            result, trace, _, leader = traced(arguments, expected, gate=gate)
            rows = [line.split(",") for line in path.read_text().splitlines()]
            members = [row for row in rows if row[0] == "member" and row[4] == "ready"]
            leaders = [row for row in rows if row[0] == "leader" and row[4] == "ready"]
            assert len(members) == len(leaders) == 1, rows
            member = int(members[0][1])
            assert int(leaders[0][1]) == leader
            report = fields(result)
            assert report["reaped"] == "true" and b"cleanup-incomplete" not in result.stderr
            if mode == "normal-orphan":
                assert not calls(trace, "kill") and report["exit"] == "7"
                adopted_status(member, alive=True)
            else:
                escalation(trace, leader)
                assert report["reason"] == "6" and report["group-confirmed"] == "true"
                if mode == "cooperate":
                    assert any(row[0] == "member" and row[4] == "term" for row in rows)
                    adopted_status(member, expected_code=0)
                elif mode == "escape":
                    assert int(members[0][2]) == member != leader
                    adopted_status(member, alive=True)
                else:
                    adopted_status(member, expected_signal=signal.SIGKILL)
                if mode == "leader-exits":
                    assert report["exit"] == "23" and any(row[0] == "leader" and row[4] == "term" for row in rows)
                if mode == "moved-leader":
                    assert int(leaders[0][2]) != leader and int(members[0][2]) == leader


def fault_cases():
    base = ["--status", "--timeout-ms", "30", "--grace-ms", "0", "--reap-ms", "100", "--", "/bin/sleep", "10"]
    for injection, name, native_errno, expected, reason in (
        ("clock_gettime:error=EIO:when=1", "clock_gettime", "EIO", 125, "2"),
        ("clock_gettime:error=EIO:when=2", "clock_gettime", "EIO", 125, "2"),
        ("poll:error=EINTR:when=1", "poll", "EINTR", 124, "6"),
        ("poll:error=EINTR:when=1+", "poll", "EINTR", 124, "6"),
        ("poll:error=EIO:when=1", "poll", "EIO", 125, "5"),
        ("wait4:error=EIO:when=1", "wait4", "EIO", 125, "4"),
        ("read:error=EIO:when=1", "read", "EIO", 125, "7"),
        ("kill:error=EPERM:when=1", "kill", "EPERM", 124, "6"),
        ("kill:error=EPERM:when=4", "kill", "EPERM", 124, "6"),
    ):
        result, trace, _, child = traced(base, expected, injection)
        ordinal = 2 if injection.startswith("clock_gettime:") and "when=2" in injection else 4 if "when=4" in injection else 1
        injected(trace, name, ["-1", native_errno], ordinal, persistent=injection.endswith("when=1+"))
        report = fields(result)
        assert report["reason"] == reason
        if child is not None:
            assert report["reaped"] == "true"
        if name == "kill":
            assert report["cleanup-errno"] == str(errno.EPERM)
            escalation(trace, child)
        if name == "read":
            assert report["startup"] == "2" and report["group-confirmed"] == "true"
            escalation(trace, child)
    result, trace, _, _ = traced(["--status", "--", "/bin/true"], 0, "wait4:error=EINTR:when=1")
    injected(trace, "wait4", ["-1", "EINTR"])
    assert fields(result)["reaped"] == "true" and not calls(trace, "kill")
    result, trace, _, child = traced(["--status", "--max-operations", "0", "--grace-ms", "0", "--reap-ms", "100", "--", "/bin/sleep", "10"], 125)
    assert fields(result)["reason"] == "3"
    escalation(trace, child)
    traced(["--status", "--", "/bin/true"], 125, closed_stderr=True)


def ownership_cases():
    base = ["--status", "--timeout-ms", "0", "--grace-ms", "0", "--reap-ms", "10", "--", "/bin/sleep", "10"]
    for injection, name, native_result in (("wait4:retval=0:when=1+", "wait4", ["0"]), ("wait4:error=EINTR:when=1+", "wait4", ["-1", "EINTR"]), ("kill:error=EPERM:when=1+", "kill", ["-1", "EPERM"])):
        result, trace, _, child = traced(base, 124, injection, retained=True)
        injected(trace, name, native_result, persistent=True)
        assert f"cleanup-incomplete pid={child}".encode() in result.stderr
        assert fields(result)["reaped"] == "false"
        adopted_status(child, alive=name == "kill", expected_signal=(signal.SIGTERM, signal.SIGKILL) if name != "kill" else None)
    result, trace, _, child = traced(["--status", "--grace-ms", "0", "--reap-ms", "10", "--", "/bin/sleep", "10"], 125, "wait4:error=ECHILD:when=1", retained=True)
    injected(trace, "wait4", ["-1", "ECHILD"])
    report = fields(result)
    assert report["ownership-lost"] == "true" and report["reaped"] == "false" and not calls(trace, "kill")
    adopted_status(child, alive=True)


def allocation_cases():
    arguments = ["--", "/bin/true"]
    _, _, baseline, _ = traced(arguments, 0)
    assert baseline
    for point in range(1, len(baseline) + 1):
        result, trace, requests, child = traced(arguments, 125, f"mmap:error=ENOMEM:when={point}")
        injected(trace, "mmap", ["-1", "ENOMEM"], point)
        assert child is None and requests == baseline[:point], trace
        assert fields(result)["reaped"] == "false"
    print(f"run-group: all {len(baseline)} pre-spawn allocation failures; no monitor allocation")


def main():
    libc = ctypes.CDLL(None, use_errno=True)
    assert libc.prctl(36, 1, 0, 0, 0) == 0
    try:
        {"normal": normal_cases, "groups": group_cases, "faults": fault_cases, "ownership": ownership_cases, "allocations": allocation_cases}[MODE]()
        cleanup_owned()
    finally:
        cleanup_owned()
        assert libc.prctl(36, 0, 0, 0, 0) == 0
    print(f"run-group {MODE}: {CASES} native cases; exact owner ledgers and bounded independent descendant cleanup")


if __name__ == "__main__":
    main()
