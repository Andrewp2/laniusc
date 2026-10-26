"""Real plain abort cleanup; a skipped injected close stays live until repair."""
import collections
import os
from pathlib import Path
import re
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

from support import ACTIVE, EVENT, Evidence, INDEPENDENT, TRACE, events, exact

MAGIC = 1213421622
REQUEST = b"POST /close HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n"


def marker(event):
    if event["name"] != "write" or event["result"] != "1":
        return None
    found = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', event["args"])
    if found is None:
        return None
    value = chr(int(found[1], 16))
    assert value in "CcSsWwPpRrAaKkTtXx", event
    return value


def ledger(text, directory, fd, close_fault=None):
    """Track native listener/accepted ownership; failed close never removes it."""
    counts = collections.Counter()
    epochs, current, closes, marked, markers, wire = [], None, [], [], [], bytearray()
    live, listener, accepted, listener_closes = set(), None, None, []
    for event in events(text):
        counts[event["name"]] += 1
        event["ordinal"] = counts[event["name"]]
        token = marker(event)
        if token is not None:
            markers.append(token)
            if token.isupper():
                assert current is None, (current, event)
                current = [token, []]
            else:
                assert current is not None and current[0] == token.upper(), (current, event)
                epochs.append(current)
                current = None
            continue
        frame = None if current is None else current[0]
        event["frame"] = frame
        if current is not None:
            current[1].append(event)
        if event["name"] in ("socket", "accept4", "bind", "listen"):
            assert frame == "C", ("socket admission outside setup", event)
        assert event["name"] != "connect", event
        if event["name"] in ("socket", "accept4"):
            opened = int(event["result"])
            assert opened >= 0 and opened not in live, event
            live.add(opened)
            if event["name"] == "socket":
                assert listener is None, event
                listener = opened
            else:
                assert listener is not None and accepted is None, event
                accepted = opened
                if fd is None:
                    fd = opened
                assert accepted == fd, (fd, event)
        if "INJECTED" in event["result"]:
            marked.append(event)
            assert event["name"] == "close" and event["ordinal"] == close_fault and event["result"].split()[:2] == ["-1", "EIO"], event
        if event["name"] == "poll":
            assert frame == "P", ("hidden poll", event)
        if event["name"] in ACTIVE:
            assert frame == "S" and event["name"] == "recvfrom", ("unexpected active I/O", event)
            part = re.fullmatch(r'(\d+), ("(?:\\x[0-9a-f]{2})*"|0x[0-9a-f]+), (\d+), 0, NULL, NULL', event["args"])
            assert part and int(part[1]) == fd and 0 < int(part[3]) <= 1024, event
            count = int(event["result"].split()[0])
            if count >= 0:
                assert part[2].startswith('"'), event
                captured = bytes.fromhex(part[2][1:-1].replace("\\x", ""))
                assert len(captured) == count, event
                wire.extend(captured)
        if event["name"] == "close":
            closing = int(event["args"])
            assert closing in live, (live, event)
            if frame == "C":
                assert closing == listener and accepted is not None and event["result"] == "0", event
                listener_closes.append(event)
                live.remove(closing)
                continue
            assert frame in ("A", "K") and closing == fd, (live, event)
            closes.append(event)
            if event["result"] == "0":
                live.remove(fd)
            else:
                assert frame == "A" and event in marked, event
    assert current is None and not live and bytes(wire) == REQUEST, (current, live, bytes(wire))
    assert listener is not None and accepted == fd and len(listener_closes) == 1 and counts["socket"] == counts["accept4"] == 1, (listener, accepted, listener_closes, counts)
    by_name = collections.Counter(tag for tag, _ in epochs)
    assert all(by_name[tag] == 1 for tag in "CRATX") and by_name["S"] > 0, by_name
    assert by_name["W"] == by_name["P"] and by_name["K"] == int(close_fault is not None), by_name
    for tag, body in epochs:
        leaves = [event for event in body if event["name"] in ACTIVE]
        polls = [event for event in body if event["name"] == "poll"]
        assert len(leaves) <= (1 if tag == "S" else 0), (tag, body)
        assert len(polls) == int(tag == "P"), (tag, body)
        if tag in "RTX":
            assert not any(event["name"] == "close" for event in body), (tag, body)
        if tag == "T":
            assert not any(event["name"] in ("clock_gettime", "mmap", "munmap", "fcntl") for event in body), body
    assert len(closes) == (1 if close_fault is None else 2) and closes[0]["frame"] == "A", closes
    assert len(marked) == int(close_fault is not None), marked
    if close_fault is not None:
        assert closes[0] == marked[0] and closes[1]["frame"] == "K" and closes[1]["result"] == "0", closes
    # Reuse the existing raw source-mapping ledger unchanged. Native-created
    # descriptors have their separate truthful ledger, including skipped close.
    allocations = Path(directory) / "abort.allocations.trace"
    mapping_lines = [event["plain"] for event in events(text) if event["name"] in ("mmap", "munmap")]
    allocations.write_text("".join(line + "\n" for line in mapping_lines), encoding="utf-8")
    mapping_count, _, _ = INDEPENDENT["resources"](allocations)
    return dict(close=closes[0], steps=by_name["S"], mappings=mapping_count,
                markers="".join(markers).encode())


def completed_checkpoint(trace, packet):
    encoded = "".join("\\x%02x" % byte for byte in packet)
    expected = '1, "' + encoded + '", 128'
    deadline = time.monotonic() + 2
    while True:
        complete = []
        for line in trace.read_text(encoding="utf-8").splitlines():
            complete.append(line)
            parsed = EVENT.fullmatch(line)
            if parsed and parsed[2] == "write" and parsed[3] == expected and parsed[4] == "128":
                return "\n".join(complete) + "\n"
        assert time.monotonic() < deadline, "missing completed report write in trace"
        time.sleep(.001)


def invoke(executable, target=None):
    evidence = Evidence("abort-cleanup-fault" if target is not None else "abort-cleanup-success")
    peer = None
    trace = evidence.directory / "syscalls.log"
    command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-o", str(trace),
               "-e", "signal=none", "-e", "trace=" + TRACE]
    if target is not None:
        command += ["-e", "inject=close:error=EIO:when=%d" % target["ordinal"]]
    command += [str(executable), str(int(target is not None))]
    (evidence.directory / "command.txt").write_text(repr(command) + "\n", encoding="utf-8")
    try:
        evidence.process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        startup = struct.unpack("<2Q", exact(evidence.process.stdout, 16, evidence.received))
        evidence.records.append(startup)
        assert startup[0] == MAGIC and 0 < startup[1] <= 65535, startup
        peer = socket.create_connection(("127.0.0.1", startup[1]), timeout=2)
        peer.sendall(REQUEST)
        evidence.peer_actions.append(("send-full-request", REQUEST))
        evidence.process.stdin.write(b"+")
        evidence.process.stdin.flush()
        packet = exact(evidence.process.stdout, 128, evidence.received, timeout=6)
        report = struct.unpack("<16Q", packet)
        evidence.records.append(report)
        fault = int(target is not None)
        assert report[0] == MAGIC and report[1] == fault and report[3] == len(REQUEST), report
        assert report[7:10] == (1, fault, 0) and report[11:14] == (19, 6, 0), report
        assert report[14:16] == ((6, 10) if fault else (0, 0)), report
        prefix = completed_checkpoint(trace, packet)
        before = ledger(prefix, evidence.directory, None, None if target is None else target["ordinal"])
        children = Path("/proc/%d/task/%d/children" % (evidence.process.pid, evidence.process.pid)).read_text().split()
        assert len(children) == 1, children
        child_fds = {name: os.readlink("/proc/%s/fd/%s" % (children[0], name)) for name in os.listdir("/proc/%s/fd" % children[0])}
        tracer_fds = {name: os.readlink("/proc/%d/fd/%s" % (evidence.process.pid, name)) for name in os.listdir("/proc/%d/fd" % evidence.process.pid)}
        evidence.peer_actions.append(("pre-exit-native-fds", child_fds))
        evidence.peer_actions.append(("pre-exit-tracer-fds", tracer_fds))
        assert set(child_fds) == {"0", "1", "2"}, child_fds
        assert peer.recv(1) == b"", "abort produced unexpected HTTP bytes"
        evidence.peer_actions.append(("server-eof",))
        assert before["steps"] == report[2], (before, report)
        if target is not None:
            assert all(before["close"][key] == target[key] for key in ("ip", "ordinal", "frame")), (target, before["close"])
        evidence.process.stdin.write(b"!")
        evidence.process.stdin.close()
        evidence.process.stdin = None
        evidence.stdout, evidence.stderr = evidence.process.communicate(timeout=3)
        evidence.drained = True
        assert evidence.process.returncode == 0 and not evidence.stdout and evidence.stderr == before["markers"], (evidence.process.returncode, evidence.stdout, evidence.stderr)
        after = ledger(trace.read_text(encoding="utf-8"), evidence.directory, None, None if target is None else target["ordinal"])
        assert after == before, (before, after)
    except BaseException as error:
        evidence.close(error)
    else:
        evidence.close()
        return before["close"]
    finally:
        if peer is not None:
            peer.close()


def controls():
    def event(value):
        return "[0000000000401000] " + value + "\n"
    def marked(value):
        return event('write(2, "\\x%02x", 1) = 1' % ord(value))
    wire = "".join("\\x%02x" % byte for byte in REQUEST)
    start = event("mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x41000000") + marked("C") + event("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 6") + event("accept4(6, NULL, NULL, SOCK_NONBLOCK) = 7") + event("close(6) = 0") + marked("c") + marked("S") + event('recvfrom(7, "' + wire + '", 1024, 0, NULL, NULL) = %d' % len(REQUEST)) + marked("s") + marked("R") + marked("r") + marked("A")
    good = event("close(7) = 0")
    failure = event("close(7) = -1 EIO (Input/output error) (INJECTED)")
    tail = marked("T") + marked("t") + marked("X") + event("munmap(0x41000000, 8) = 0") + marked("x")
    baseline = start + good + marked("a") + tail
    fault = start + failure + marked("a") + marked("K") + good + marked("k") + tail
    with tempfile.TemporaryDirectory(prefix="http_abort_ledger_controls_") as directory:
        assert ledger(baseline, directory, 7)["steps"] == 1
        assert ledger(fault, directory, 7, 2)["close"]["frame"] == "A"
        mutants = [
            fault.replace(marked("K") + good + marked("k"), ""),
            fault.replace("EIO", "EBADF"),
            fault.replace(" (INJECTED)", ""),
            fault.replace("close(7) = -1", "close(8) = -1"),
            fault + good,
            fault.replace(marked("t"), good + marked("t")),
            fault.replace(marked("r"), event("poll([], 0, 25) = 0 (Timeout)") + marked("r")),
        ]
        for text in mutants:
            try:
                ledger(text, directory, 7, 2)
            except AssertionError:
                continue
            raise AssertionError("abort cleanup ledger accepted an ownership mutation")
    return 2 + len(mutants)


def main(executable):
    assert controls() == 9
    target = invoke(executable)
    invoke(executable, target)
    print("http-server-exchange-abort-cleanup cases=2 reached-close-EIO=1 before-exit-cleanup=1 cleanup-ledger-controls=9")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
