"""Inject only a reached, marked Server poll; audit its live accepted owner."""
import os
from pathlib import Path
import re
import select
import struct
import subprocess
import sys
import tempfile
import time


MAGIC = 0x53504654


def marker(line):
    found = re.fullmatch(r'write\(2, "((?:\\x[0-9a-f]{2})*)", 20\)\s+= 20', line)
    if not found:
        return None
    raw = bytes.fromhex(found[1].replace("\\x", ""))
    assert len(raw) == 20, line
    value = struct.unpack("<5i", raw)
    assert value[0] == MAGIC, value
    return value[1:]


def audit(text, mode, complete, target_ordinal=None):
    maps, fds = {}, {}
    events, marks, polls = [], {}, []
    accepts = allocations = generation = 0
    for line in text.splitlines():
        if " = " not in line:
            assert not complete and line.startswith("read(0, "), line
            continue
        name = line.split("(", 1)[0]
        result = line.rsplit(" = ", 1)[1].split()[0]
        event = {"line": line, "name": name, "result": result}
        events.append(event)
        stamp = marker(line)
        if stamp is not None:
            phase, profile, fd, physical = stamp
            assert profile == mode and phase not in marks, stamp
            if phase in (10, 11, 20, 30, 31, 40, 41):
                assert fd in fds and fds[fd][0] == "accepted", (stamp, fds)
            marks[phase] = (len(events)-1, fd, physical)
        if name == "mmap" and result.startswith("0x"):
            assert "MAP_32BIT" in line and result not in maps, line
            maps[result] = int(line.split(",")[1])
            allocations += 1
        elif name == "munmap":
            address, size = line[7:].split(")", 1)[0].split(",")
            assert result == "0" and maps.pop(address, None) == int(size), line
        elif name in ("socket", "accept4") and re.fullmatch(r"\d+", result):
            fd = int(result)
            assert fd not in fds, line
            generation += 1
            fds[fd] = ("accepted" if name == "accept4" else "socket", generation)
            accepts += name == "accept4"
        elif name == "close":
            fd = int(line[6:].split(")", 1)[0])
            assert result == "0" and fd in fds, line
            del fds[fd]
        elif name == "poll":
            polls.append(len(events)-1)
        else:
            assert name in ("recvfrom", "sendto", "read", "write"), line
    assert not maps and not fds and accepts == 1 and allocations > 0, (maps, fds, accepts, allocations)
    assert set(marks) == ({10, 11, 20, 21, 30, 31, 40, 41} if mode == 1 else {10, 11, 20, 21}), marks
    fd = marks[20][1]
    assert all(value[1] == fd for value in marks.values()), marks

    def interval(start, end):
        return events[marks[start][0]+1:marks[end][0]]

    def one_poll(start, end):
        found = [event for event in interval(start, end) if event["name"] == "poll"]
        assert len(found) == 1, found
        event = found[0]
        left = event["line"].rsplit(" = ", 1)[0]
        assert [int(value) for value in re.findall(r"fd=(-?\d+)", left)] == [-1, fd], event
        assert "events=POLLIN" in left, event
        timeout = re.search(r",\s*2,\s*(\d+)\)$", left)
        assert timeout and int(timeout[1]) > 0, event
        return event

    warm = one_poll(10, 11)
    assert warm["result"] == "1" and "INJECTED" not in warm["line"] and marks[10][2] == 0 and marks[11][2] == 1, warm
    between = interval(11, 20)
    received = [event for event in between if event["name"] == "recvfrom" and event["line"].startswith(f"recvfrom({fd}, ")]
    assert any(event["result"] == "1" and '"\\x47"' in event["line"] for event in received), received
    assert received[-1]["result"] == "-1" and "EAGAIN" in received[-1]["line"], received
    target = one_poll(20, 21)
    index = next(index for index in range(marks[20][0]+1, marks[21][0]) if events[index]["name"] == "poll")
    ordinal = polls.index(index)+1
    assert target_ordinal is None or ordinal == target_ordinal, (ordinal, target_ordinal)
    assert marks[20][2] == 1 and marks[21][2] == 2, marks
    injected = [event for event in events if "INJECTED" in event["line"]]
    if mode == 0:
        assert target["result"] == "1" and not injected, target
    else:
        error = "EINTR" if mode == 1 else "EIO"
        assert injected == [target] and target["result"] == "-1" and error in target["line"], (target, injected)
    if mode == 1:
        assert not any(event["name"] in ("recvfrom", "close") for event in interval(20, 21)), target
        assert not any(event["name"] in ("poll", "recvfrom", "close") for event in interval(30, 31)), interval(30, 31)
        recovered = one_poll(40, 41)
        assert recovered["result"] == "1" and "INJECTED" not in recovered["line"] and marks[40][2] == 2 and marks[41][2] == 3, recovered
        tail = events[marks[41][0]+1:]
    else:
        tail = events[marks[21][0]+1:]
    if mode != 2:
        assert any(event["name"] == "recvfrom" and event["line"].startswith(f"recvfrom({fd}, ") and event["result"] == "0" for event in tail), tail
    else:
        closed = [event for event in interval(20, 21) if event["name"] == "close" and int(event["line"][6:].split(")", 1)[0]) == fd]
        assert len(closed) == 1 and closed[0]["result"] == "0", interval(20, 21)
        assert not any(event["name"] == "poll" for event in tail), tail
    return ordinal


def invoke(executable, mode, target_ordinal=None):
    directory = Path(tempfile.mkdtemp(prefix=f"server-poll-fault-{mode}-"))
    trace = directory / "trace.txt"
    command = ["strace", "--kill-on-exit", "-qq", "-xx", "-s", "256", "-o", str(trace), "-e", "trace=mmap,munmap,socket,accept4,close,recvfrom,sendto,poll,read,write"]
    if mode:
        command += ["-e", f"inject=poll:error={'EINTR' if mode == 1 else 'EIO'}:when={target_ordinal}"]
    command += [str(executable), str(mode)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    captured = bytearray()
    try:
        deadline = time.monotonic()+12
        while len(captured) < 16:
            remaining = deadline-time.monotonic()
            assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "marked native poll control stalled"
            chunk = os.read(process.stdout.fileno(), 16-len(captured))
            assert chunk, "native control exited before owner checkpoint"
            captured.extend(chunk)
        assert struct.unpack("<4i", captured) == (MAGIC, mode, 3 if mode == 1 else 2, 1), captured
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1 and set(os.listdir(f"/proc/{int(children[0])}/fd")) == {"0", "1", "2"}, children
        until = time.monotonic()+2
        while True:
            text = trace.read_text()
            if re.search(r"write\(1, .*16\)\s+= 16", text):
                break
            assert time.monotonic() < until, text
            time.sleep(0.005)
        ordinal = audit(text, mode, False, target_ordinal)
        process.stdin.write(b"\x01")
        process.stdin.flush()
        output, error = process.communicate(timeout=5)
        assert process.returncode == 0 and not output and len(error) == (160 if mode == 1 else 80), (process.returncode, output, error)
        audit(trace.read_text(), mode, True, ordinal)
        return ordinal
    except BaseException:
        (directory / "stdout.bin").write_bytes(captured)
        if process.poll() is None:
            process.kill()
        output, error = process.communicate(timeout=3)
        (directory / "tail.bin").write_bytes(output)
        (directory / "stderr.bin").write_bytes(error)
        print(f"marked Server poll evidence: {directory}", file=sys.stderr)
        raise


def run(executable):
    ordinal = invoke(executable, 0)
    invoke(executable, 1, ordinal)
    invoke(executable, 2, ordinal)
    print("server-poll-faults cases=2 calibration=1")


if __name__ == "__main__":
    run(Path(sys.argv[1]).resolve())
