#!/usr/bin/env python3
"""Independent Linux process identities, signal delivery and owner ledgers.

Python is test infrastructure only. Production forks/execs/groups remain Lanius.
All runs use a private session; orphan helpers are adopted and actually reaped.
"""
import ctypes
import errno
import os
from pathlib import Path
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import time

PROBE, FAILURE, CONFIRM, PEER, GROUP = sys.argv[1:]
TRACE = "mmap,munmap,fcntl,open,openat,close,pipe2,fork,wait4,waitid,read,write,close_range,dup3,execve,kill,rt_sigaction,chdir,setpgid,getpgid,poll"
MAGIC = 0x47525031
CASES = 0
libc = ctypes.CDLL(None, use_errno=True)
assert libc.prctl(36, 1, 0, 0, 0) == 0, ctypes.get_errno()  # PR_SET_CHILD_SUBREAPER


def records(text):
    pending, result = {}, []
    for line in text.splitlines():
        match = re.match(r"^(\d+) +(.*)$", line)
        if not match:
            continue
        pid, body = int(match[1]), match[2]
        if body.endswith("<unfinished ...>"):
            assert pid not in pending, line
            pending[pid] = body[:-len("<unfinished ...>")].rstrip()
        elif body.startswith("<... ") and " resumed>" in body:
            assert pid in pending, line
            result.append((pid, pending.pop(pid) + body.split(" resumed>", 1)[1]))
        else:
            result.append((pid, body))
    assert all(any(p == pid and "killed by" in s for p, s in result) for pid in pending), pending
    return result


def audit(text, auto_reaped=False):
    events = records(text)
    assert events, text
    parent = events[0][0]
    mappings, fds, children = {}, set(), set()
    forked = set()
    allocations = []
    for pid, body in events:
        if pid != parent:
            continue
        match = re.match(r"mmap\(NULL, (\d+),.*\) += (0x[0-9a-f]+|-1)(?: |$)", body)
        if match:
            size, address = int(match[1]), match[2]
            allocations.append(size)
            if address != "-1":
                assert address not in mappings, body
                mappings[address] = size
            else:
                assert "ENOMEM" in body and "INJECTED" in body, body
        match = re.match(r"munmap\((0x[0-9a-f]+), (\d+)\) += 0", body)
        if match:
            assert mappings.pop(match[1], None) == int(match[2]), body
        match = re.match(r"(?:open(?:at)?\(.*|fcntl\(\d+, F_DUPFD_CLOEXEC, \d+\)) += (\d+)(?: |$)", body)
        if match:
            fd = int(match[1]); assert fd not in fds, body; fds.add(fd)
        match = re.match(r"pipe2\(\[(\d+), (\d+)\], O_CLOEXEC\) += 0", body)
        if match:
            for fd in map(int, match.groups()):
                assert fd not in fds, body
                fds.add(fd)
        match = re.match(r"close\((\d+)\) += 0", body)
        if match:
            fd = int(match[1]); assert fd in fds or fd <= 2, body; fds.discard(fd)
        match = re.match(r"fork\(\) += (\d+)", body)
        if match:
            child = int(match[1]); assert child not in children; children.add(child); forked.add(child)
        match = re.match(r"wait4\(.*\) += (\d+)(?: |$)", body)
        if match and int(match[1]) > 0:
            child = int(match[1]); assert child in children, body; children.remove(child)
        if auto_reaped and body.startswith("wait4(") and "= -1 ECHILD" in body:
            children.clear()
    assert not mappings and not fds and not children, (mappings, fds, children, text)
    for child in forked:
        for pid, body in events:
            if pid != child:
                continue
            if body.startswith("execve("):
                break
            assert not body.startswith(("mmap(", "munmap(")), (child, body)
    return parent, events, allocations


def fault(text, syscall, error, follow, ordinal=1):
    events = records(text)
    parent = events[0][0]
    marked = [(pid, body) for pid, body in events if "INJECTED" in body and body.startswith(syscall + "(")]
    assert marked, (syscall, error, text)
    if not follow:
        assert all(pid == parent for pid, _ in marked), marked
    for pid, body in marked:
        assert body.startswith(syscall + "("), (pid, body)
        result = body.rsplit(" = ", 1)[1].split()
        assert result[:2] == ["-1", error], (pid, body)
        calls = [s for p, s in events if p == pid and s.startswith(syscall + "(")]
        assert body == calls[ordinal - 1], (pid, body, calls)
    return marked


def preexec_signal_fault(events, parent, syscall, delivered, ordinal):
    # -qq and signal=none suppress death/signal display lines. Signal-only
    # injection also has no errno/retval INJECTED marker. Bind its evidence to
    # the real forked child, selected syscall entry and actual parent wait.
    forked = [int(match[1]) for pid, body in events if pid == parent
              if (match := re.match(r"fork\(\) += (\d+)(?: |$)", body))]
    assert len(forked) == 1, forked
    child = forked[0]
    calls = [(index, body) for index, (pid, body) in enumerate(events)
             if body.startswith(syscall + "(")]
    assert len(calls) == ordinal and all(events[index][0] == child for index, _ in calls), calls
    entered, body = calls[ordinal - 1]
    assert body.rsplit(" = ", 1)[1].strip() == "?", body
    assert not any(pid == child and body.startswith("execve(") for pid, body in events), events
    assert not any(body.startswith("kill(") for _pid, body in events), events
    reaped = [(index, body) for index, (pid, body) in enumerate(events) if pid == parent
              and re.match(r"wait4\(" + str(child) + r", \[\{WIFSIGNALED\(s\) && WTERMSIG\(s\) == "
                           + re.escape(delivered) + r"\}\], 0, NULL\) += " + str(child) + r"(?: |$)", body)]
    assert len(reaped) == 1 and entered < reaped[0][0], (child, calls, reaped)


def exact_read(fd, count, timeout=7):
    result = b""
    end = time.monotonic() + timeout
    while len(result) < count:
        left = end - time.monotonic()
        assert left > 0 and select.select([fd], [], [], left)[0], (len(result), count)
        part = os.read(fd, count - len(result))
        assert part, (len(result), count)
        result += part
    return result


def owned_grandchild(pid):
    """Establish our unreaped-child relationship before obtaining signal authority."""
    end = time.monotonic() + 5
    while True:
        try:
            status = os.waitid(os.P_PID, pid, os.WEXITED | os.WNOHANG | os.WNOWAIT)
        except ChildProcessError:
            assert time.monotonic() < end, "grandchild was not adopted by the test subreaper"
            time.sleep(0.005)
            continue
        # SIGCHLD is not ignored here and no other code reaps this child. The
        # relationship now pins its PID, even if it exits before pidfd_open.
        assert status is None, "grandchild must be live after leader authority is revoked"
        return os.pidfd_open(pid)


def reap_adopted():
    """Reap only our children after the owned tracer has killed its tracees."""
    end = time.monotonic() + 5
    while True:
        try:
            pid, _status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if pid == 0:
            assert time.monotonic() < end, "tracee remained live after tracer cleanup"
            time.sleep(0.005)


def identity_case(mode, injection=None):
    global CASES
    with tempfile.TemporaryDirectory(prefix="command-group-") as directory:
        trace = Path(directory) / "trace"
        command = ["strace", "--kill-on-exit", "-f", "-qq", "-s", "4096", "-e", "signal=none", "-e", "trace=" + TRACE, "-o", str(trace)]
        if injection:
            command += ["-e", "inject=" + injection]
        command += [PROBE, PEER, str(mode)]
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        grand_fd = None
        grand = None
        try:
            data = exact_read(process.stdout.fileno(), 44)
            magic, actual_mode, parent, pgid, sid, peer_magic, leader, leader_group, leader_sid, grand, grand_group = struct.unpack("<11i", data)
            assert (magic, actual_mode, peer_magic) == (MAGIC, mode, MAGIC)
            assert parent > 1 and leader > 1 and grand > 1 and len({parent, leader, grand}) == 3
            assert pgid == sid == process.pid and leader_sid == sid
            assert leader_group == grand_group == (pgid if mode == 0 else leader)
            if mode in (5, 6):
                assert exact_read(process.stdout.fileno(), 1) == b"R"
                grand_fd = owned_grandchild(grand)
                poller = select.poll(); poller.register(grand_fd, select.POLLIN)
                assert not poller.poll(0), "grandchild must still be live after leader reap"
                signal.pidfd_send_signal(grand_fd, signal.SIGKILL)
            output, errors = process.communicate(timeout=10)
            assert process.returncode == 0 and not output and not errors, (mode, process.returncode, output, errors, trace.read_text())
            parent_pid, events, _ = audit(trace.read_text(), auto_reaped=mode == 6)
            if injection:
                syscall, rest = injection.split(":error=", 1)
                marked = fault(trace.read_text(), syscall, rest.split(":", 1)[0], True)
                assert len(marked) == 1 and marked[0][0] == parent
            assert parent_pid == parent
            parent_events = [body for pid, body in events if pid == parent]
            negative = [int(re.match(r"kill\((-?\d+),", body)[1]) for body in parent_events if body.startswith("kill(") and int(re.match(r"kill\((-?\d+),", body)[1]) < 0]
            assert all(target == -leader for target in negative), (mode, negative)
            assert not any(body.startswith(("kill(0,", "kill(-1,")) for body in parent_events)
            reaped = next((index for index, body in enumerate(parent_events) if body.startswith("wait4(") and re.search(r"= " + str(leader) + r"(?: |$)", body)), None)
            if reaped is not None:
                assert not any(body.startswith(f"kill(-{leader},") for body in parent_events[reaped + 1:])
            if mode in (4, 7):
                observed = [index for index, body in enumerate(parent_events) if body.startswith("waitid(") and "WNOWAIT" in body and "si_pid=" + str(leader) in body]
                assert observed and reaped is not None and observed[0] < reaped, (mode, parent_events)
                assert any(body.startswith(f"kill(-{leader}, SIGKILL)") for body in parent_events[observed[0]:reaped])
            if mode in (0, 1, 8, 11):
                try:
                    os.waitpid(grand, os.WNOHANG)
                except ChildProcessError:
                    pass
                else:
                    raise AssertionError("peer did not reap its own grandchild")
            else:
                adopted, status = os.waitpid(grand, 0)
                assert adopted == grand and os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGKILL, (mode, status)
            CASES += 1
        finally:
            if grand_fd is not None:
                try:
                    signal.pidfd_send_signal(grand_fd, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                os.close(grand_fd)
            if process.poll() is None:
                # Popen still owns this unreaped child. EXITKILL then reaches
                # every followed tracee, including groups outside its PGID.
                process.kill()
            process.communicate(timeout=5)
            reap_adopted()


def startup_case(injection=None, expected=43, follow=True, executable=FAILURE):
    global CASES
    with tempfile.TemporaryDirectory(prefix="command-group-fault-") as directory:
        trace = Path(directory) / "trace"
        command = ["strace", "-qq", "-xx", "-s", "4096", "-e", "signal=none", "-e", "trace=" + TRACE, "-o", str(trace)]
        if follow:
            command.append("-f")
        expressions = [] if injection is None else ([injection] if isinstance(injection, str) else injection)
        for expression in expressions:
            command += ["-e", "inject=" + expression]
        result = subprocess.run([*command, executable], capture_output=True, timeout=8, start_new_session=True)
        text = trace.read_text()
        if not follow:
            text = "\n".join("0 " + line for line in text.splitlines())
        assert result.returncode == expected and not result.stdout and not result.stderr, (injection, result, text)
        parent, events, allocations = audit(text)
        for expression in expressions:
            if ":error=" in expression:
                syscall, rest = expression.split(":error=", 1)
                ordinal = int(expression.rsplit(":when=", 1)[1])
                fault(text, syscall, rest.split(":", 1)[0], follow, ordinal)
            if ":retval=" in expression:
                syscall, rest = expression.split(":retval=", 1)
                expected_value = rest.split(":", 1)[0]
                marked = [(pid, body) for pid, body in events if "INJECTED" in body and body.startswith(syscall + "(")]
                assert marked and all(body.rsplit(" = ", 1)[1].split()[0] == expected_value for _, body in marked), marked
                if not follow:
                    assert len(marked) == 1 and marked[0][0] == parent
            if ":signal=" in expression:
                syscall, rest = expression.split(":signal=", 1)
                assert follow
                preexec_signal_fault(events, parent, syscall, rest.split(":", 1)[0],
                                     int(expression.rsplit(":when=", 1)[1]))
        if follow and any(expression.startswith("setpgid:error=") for expression in expressions):
            packets = []
            for pid, body in events:
                match = re.match(r'write\(\d+, "((?:\\x[0-9a-f]{2})+)", 16\) += 16', body)
                if pid != parent and match:
                    packet = struct.unpack("<4i", bytes.fromhex(match[1].replace("\\x", "")))
                    if packet[0] == 1279479108:
                        packets.append(packet)
            expected_errno = errno.EPERM if "EPERM" in expressions[0] else errno.EINTR
            assert len(packets) == 1 and packets[0][1:3] == (6, expected_errno), (packets, text)
            assert packets[0][3] == packets[0][0] ^ packets[0][1] ^ packets[0][2]
        CASES += 1
        return allocations, events


if GROUP == "membership":
    for value in (0, 1):
        identity_case(value)
elif GROUP == "signals":
    for value in (2, 3):
        identity_case(value)
    identity_case(10, "kill:error=EPERM:when=1")
    identity_case(11, "kill:error=EPERM:when=1")
elif GROUP == "authority":
    for value in (4, 5, 6):
        identity_case(value)
    identity_case(4, "waitid:error=EINTR:when=1")
elif GROUP == "capture":
    for value in (7, 8):
        identity_case(value)
elif GROUP == "faults":
    baseline, _ = startup_case()
    for point in range(1, len(baseline) + 1):
        actual, _ = startup_case(f"mmap:error=ENOMEM:when={point}", 41, False)
        assert actual == baseline[:point]
    for expression, status, follow in [
        ("pipe2:error=EMFILE:when=1", 41, False),
        ("fork:error=EAGAIN:when=1", 41, False),
        ("setpgid:error=EPERM:when=1", 42, True),
        ("setpgid:error=EINTR:when=1", 42, True),
        ("setpgid:error=EPERM:when=1", 43, False),
        ("read:error=EIO:when=1", 44, False),
        ("read:error=EINTR:when=1", 43, False),
        ("write:error=EINTR:when=1", 43, True),
        ("write:retval=8:when=1", 44, True),
        ("close_range:signal=SIGKILL:when=1", 45, True),
        ("wait4:error=EIO:when=1", 44, False),
    ]:
        startup_case(expression, status, follow)
    startup_case(None, 40, False, CONFIRM)
    startup_case("setpgid:error=EPERM:when=1", 44, False, CONFIRM)
    startup_case(["setpgid:error=EACCES:when=1", "getpgid:error=EIO:when=1"], 44, False, CONFIRM)
    startup_case(["setpgid:error=EACCES:when=1", "getpgid:retval=0:when=1"], 44, False, CONFIRM)
else:
    raise AssertionError(GROUP)
print(f"command group {GROUP}: {CASES} finite native cases; identities, authority and owner ledgers checked")
