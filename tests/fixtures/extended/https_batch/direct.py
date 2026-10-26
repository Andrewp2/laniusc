"""Direct Exchange markers prove resumability; test poll runs outside step."""
import os
from pathlib import Path
import re
import select
import struct
import subprocess
import time

from controlled import ControlledPool
from peers import BINARY, Peer, decoded, fixed
from resources import analyze, injected_at


def intervals(path):
    active, steps, waits = None, 0, 0
    tcp_leaves = 0
    for line in Path(path).read_text().splitlines():
        marker = re.search(r'write\(2, "([SsWwAa])", 1\)\s+=\s+1$', line)
        if marker:
            value = marker[1]
            if value.isupper():
                assert active is None, line
                active, tcp_leaves = value, 0
            else:
                assert active == value.upper(), line
                if active == "S":
                    assert tcp_leaves <= 1, line
                    steps += 1
                elif active == "W":
                    assert tcp_leaves == 0, line
                    waits += 1
                active = None
        elif active in ("S", "W"):
            assert not re.search(r"\bpoll\(", line), ("hidden poll inside API call", line)
            tcp_leaves += int(bool(re.search(r"\b(?:connect|getsockopt|getpeername)\(", line)))
    assert active is None and steps > 0 and waits > 0, (active, steps, waits)
    return steps


def run(executable, directory, trace, *, fault=0, abort=False, close_fault=None):
    peer = Peer(wire=fixed(), request_bytes=4, ending="clean", stall="response" if abort else "")
    peer.body = b"\x00\xff\x00\x0a"
    if fault == 1:
        prelude = b"HTTP/1.1 103 Hints\r\nLink: </r>\r\n\r\n"
        peer.preludes = (prelude, prelude)
    with ControlledPool(directory, [peer], 1, expected_failure=abort) as pool:
        port = pool.servers[0].listener.getsockname()[1]
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
                   "-e", "trace=mmap,munmap,openat,open,close,socket,connect,getsockopt,getpeername,sendto,recvfrom,poll,shutdown,clock_gettime,read,write"]
        if close_fault is not None:
            command += ["-e", "inject=close:error=EIO:when=%d" % close_fault]
        command += [executable, str(Path(directory) / "root.pem")]
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, bufsize=0)
        until = time.monotonic() + 7
        try:
            process.stdin.write(struct.pack("<16i", port, fault, int(abort), int(close_fault is not None), 17, *([0] * 11)))
            process.stdin.flush()
            def read(count):
                data = bytearray()
                while len(data) < count:
                    remaining = until - time.monotonic()
                    assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "direct HTTPS deadline"
                    part = os.read(process.stdout.fileno(), count - len(data))
                    assert part, ("direct fixture EOF", process.poll(), bytes(data), process.stderr.read())
                    data.extend(part)
                return bytes(data)
            words = struct.unpack("<16i", read(64))
            assert words[0] == 1213415986 and words[1] in (771, 772), words
            wire, body = read(words[9]), read(words[10])
            child = Path("/proc/%d/task/%d/children" % (process.pid, process.pid)).read_text().split()
            assert len(child) == 1 and set(os.listdir("/proc/%s/fd" % child[0])) == {"0", "1", "2"}, child
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            out, errors = process.communicate(timeout=max(.1, until - time.monotonic()))
            assert process.returncode == 0 and not out and re.fullmatch(b"(?:Ss|Ww|Aa)+", errors), (process.returncode, out, errors)
            assert intervals(trace) == words[2], words
            ledger = analyze(trace, executable, epochs=False, injected_close=close_fault)
            assert ledger["max_sockets"] == 1, ledger
            if abort:
                assert words[7] == 1 and words[8] == int(close_fault is not None) and not wire and not body, words
            else:
                assert not words[7] and wire == peer.wire and body == BINARY and decoded(wire)[1] == body, (words, wire, body)
                if fault:
                    assert words[4] == 1, words
                if fault == 1:
                    assert words[5] > 0, words
            if close_fault is not None:
                injected_at(ledger, "close", close_fault, "EIO")
            return ledger
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=2)


def cases(executable, directory, trace):
    count = 0
    for fault in (0, 1, 2, 9):
        run(executable, directory, trace, fault=fault)
        count += 1
    baseline = run(executable, directory, trace, abort=True)
    count += 1
    lines = Path(trace).read_text().splitlines()
    marker = next(index for index, line in enumerate(lines) if re.search(r'write\(2, "A", 1\)\s+=\s+1$', line))
    target = next(event for event in baseline["attempts"]["close"] if event["line_number"] > marker)
    faulted = run(executable, directory, trace, abort=True, close_fault=target["ordinal"])
    event = injected_at(faulted, "close", target["ordinal"], "EIO")
    assert event["ip"] == target["ip"] and event["args"] == target["args"], (event, target)
    return count + 1
