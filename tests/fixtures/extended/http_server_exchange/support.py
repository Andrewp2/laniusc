"""Independent direct-server test support; never a production HTTP implementation.

The canonical older test's request encoder, h11 response oracle and resource
ledger are reused verbatim. Only named definitions are loaded because that
script has an unconditional CLI entry; importing it would execute a test run.
"""
import ast
import collections
import email.utils
import os
from pathlib import Path
import re
import select
import shutil
import socket
import struct
import subprocess
import tempfile
import time

import h11

MAGIC = 0x48535831
WORDS = 32
RECORD_BYTES = WORDS * 4
TRACE = "socket,accept4,connect,fcntl,close,mmap,munmap,recvfrom,sendto,poll,shutdown,clock_gettime,rt_sigaction,read,write,bind,listen,getsockname,getpeername,setsockopt,getsockopt"
ACTIVE = {"recvfrom", "sendto", "shutdown"}
EVENT = re.compile(r"^(?:\[([0-9a-fA-Fx]+)\]\s+)?([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$")
START = {1: 2, 3: 4, 5: 6, 7: 8, 9: 10, 11: 12, 21: 22}


def independent_helpers():
    path = Path(__file__).resolve().parents[1] / "http_server_oracle.py"
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    names = {"request", "parse", "resources"}
    definitions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name in names]
    assert {node.name for node in definitions} == names
    namespace = {"h11": h11, "email": email, "collections": collections, "re": re}
    exec(compile(ast.Module(body=definitions, type_ignores=[]), str(path), "exec"), namespace)
    return {name: namespace[name] for name in names}


INDEPENDENT = independent_helpers()
request = INDEPENDENT["request"]
parse_response = INDEPENDENT["parse"]


def exact(stream, count, captured, timeout=4):
    data = bytearray()
    deadline = time.monotonic() + timeout
    while len(data) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], ("public call stalled", count, bytes(data))
        part = os.read(stream.fileno(), count - len(data))
        assert part, ("premature native EOF", count, bytes(data))
        captured.extend(part)
        data.extend(part)
    return bytes(data)


def events(text):
    parsed = []
    for line in text.splitlines():
        if not line:
            continue
        match = EVENT.fullmatch(line)
        assert match, ("unparsed native event", line)
        ip, name, args, result = match.groups()
        assert name in TRACE.split(","), line
        parsed.append({"ip": int(ip, 16) if ip is not None else None,
                       "name": name, "args": args, "result": result,
                       "line": line, "plain": line[match.start(2):]})
    return parsed


def record_marker(event):
    if event["name"] != "write":
        return None
    match = re.fullmatch(r'1, "((?:\\x[0-9a-f]{2})+)", ' + str(RECORD_BYTES), event["args"])
    if not match:
        return None
    payload = bytes.fromhex(match[1].replace("\\x", ""))
    if len(payload) != RECORD_BYTES:
        return None
    words = struct.unpack("<32i", payload)
    if words[0] != MAGIC:
        return None
    assert event["result"].split()[0] == str(RECORD_BYTES), event
    return words


def audit_epochs(text):
    """Check public-call boundaries, never private protocol phase numbers."""
    current = None
    epochs = []
    for event in events(text):
        words = record_marker(event)
        if words is None:
            if current is not None:
                current[2].append(event)
            continue
        tag = words[1]
        if tag in START:
            assert current is None, (current, words)
            current = [tag, words, []]
        elif tag in START.values():
            assert current is not None and START[current[0]] == tag, (current, words)
            epochs.append((*current, words))
            current = None
        else:
            assert current is None, (current, words)
    assert current is None and epochs, (current, text)
    for tag, before, body, after in epochs:
        leaves = [event for event in body if event["name"] in ACTIVE]
        polls = [event for event in body if event["name"] == "poll"]
        if tag == 21:
            assert not leaves and len(polls) <= 1, (tag, body)
        else:
            assert not polls, ("internal poll", tag, body)
            assert len(leaves) <= (1 if tag == 1 else 0), ("multiple active leaves", tag, body)
        if tag == 9:
            assert not any(event["name"] in ("mmap", "munmap", "close", "clock_gettime") for event in body), body
        if tag != 7:
            assert not any(event["name"] in ("socket", "accept4", "connect", "fcntl", "getsockopt", "setsockopt", "getpeername", "getsockname", "bind", "listen") for event in body), body
        if tag == 1:
            assert after[19] - before[19] == len(leaves), ("step I/O accounting", before, after, leaves)
        if tag == 3:
            assert after[19] - before[19] in (0, 1), ("poll participation accounting", before, after)
        if tag == 21:
            assert after[19] == before[19], ("external poll changed owner counter", before, after)
        for event in leaves:
            if event["name"] in ("recvfrom", "sendto"):
                length = re.match(r'\d+, (?:"(?:\\x[0-9a-f]{2})*"|0x[0-9a-f]+), (\d+),', event["args"])
                assert length and 0 < int(length.group(1)) <= 1024, event
        # Confirmed byte/call/work counters may grow but never rewind. Cleanup
        # and decision events preserve views until explicit destruction.
        assert all(after[index] >= before[index] for index in (11, 15, 17, 18, 19, 20, 21, 22, 23)), (before, after)
    return epochs


def audit_resources(text, directory):
    parsed = events(text)
    # This campaign does not pretend injected close failure closes a real fd.
    # All checked owners must actually be released before the final ACK.
    for event in parsed:
        if event["name"] == "close":
            assert event["result"].split()[0] == "0", event
    normalized = Path(directory) / "resources.normalized.trace"
    normalized.write_text("\n".join(event["plain"] for event in parsed) + "\n", encoding="utf-8")
    return INDEPENDENT["resources"](normalized)


def injected(text, syscall, ordinal, error):
    selected = [event for event in events(text) if event["name"] == syscall]
    marked = [index + 1 for index, event in enumerate(selected) if "INJECTED" in event["result"]]
    assert marked == [ordinal], (syscall, ordinal, selected)
    assert selected[ordinal - 1]["result"].split()[:2] == ["-1", error], selected


class Evidence:
    """Retain a failed run's complete trace and native/protocol evidence."""
    def __init__(self, label):
        self.directory = Path(tempfile.mkdtemp(prefix="http-server-exchange-" + label + "-"))
        self.process = None
        self.received = bytearray()
        self.stdout = b""
        self.stderr = b""
        self.drained = False
        self.records = []
        self.peer_wire = bytearray()
        self.peer_actions = []

    def finish_process(self):
        self.stdout, self.stderr = self.process.communicate(timeout=3)
        self.drained = True
        assert self.process.returncode == 0 and not self.stdout and not self.stderr, (self.process.returncode, self.stdout, self.stderr)

    def close(self, error=None):
        if error is None and self.process is not None and not self.drained:
            error = AssertionError("case ended without completing its native checkpoint")
        status_before = self.process.poll() if self.process is not None else None
        intervention = "none"
        if self.process is not None and not self.drained:
            if status_before is None:
                try:
                    self.process.wait(timeout=.2)
                except subprocess.TimeoutExpired:
                    intervention = "killed live strace after diagnostic wait"
                    self.process.kill()
            self.stdout, self.stderr = self.process.communicate(timeout=3)
            self.drained = True
        if error is None:
            shutil.rmtree(self.directory)
            return
        (self.directory / "native.stdout").write_bytes(bytes(self.received) + self.stdout)
        (self.directory / "native.stderr").write_bytes(self.stderr)
        (self.directory / "peer.response").write_bytes(self.peer_wire)
        detail = {"error": repr(error), "status_before_drain": status_before,
                  "status_after_drain": self.process.returncode if self.process is not None else None,
                  "intervention": intervention, "records": self.records,
                  "peer_actions": self.peer_actions, "native_stderr": self.stderr}
        (self.directory / "diagnostic.txt").write_text(repr(detail) + "\n", encoding="utf-8")
        raise AssertionError(("direct server failure evidence retained", str(self.directory), detail)) from error


class Session:
    """Caller-controlled probe; construction never starts a test at import."""
    def __init__(self, executable, label="case", mode=0, timeout=5000,
                 quota=100000, work=100000000, raw_cap=65536, body_cap=4194304,
                 drain_cap=4194304, response_cap=4194304, fault=None):
        self.evidence = Evidence(label)
        self.trace = self.evidence.directory / "syscalls.log"
        self.conn = None
        self.eof = False
        self.reset = False
        self.last = None
        self.payloads = []
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-o", str(self.trace),
                   "-e", "signal=none", "-e", "trace=" + TRACE]
        for expression in ([] if fault is None else ([fault] if isinstance(fault, str) else fault)):
            command += ["-e", "inject=" + expression]
        command += [str(executable), str(mode), str(timeout), str(quota), str(work),
                    str(raw_cap), str(body_cap), str(drain_cap), str(response_cap)]
        (self.evidence.directory / "command.txt").write_text(repr(command) + "\n", encoding="utf-8")
        try:
            self.evidence.process = subprocess.Popen(command, stdin=subprocess.PIPE,
                                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
            self.last = self.record()
            assert self.last[1] == 0, self.last
            if mode == 0:
                assert 0 < self.last[29] <= 65535, self.last
                self.conn = socket.create_connection(("127.0.0.1", self.last[29]), timeout=2)
                self.conn.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
                self.conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
                self.conn.setblocking(False)
                self.command(27)
        except BaseException as error:
            self.close(error)

    def record(self):
        words = struct.unpack("<32i", exact(self.evidence.process.stdout, RECORD_BYTES, self.evidence.received))
        assert words[0] == MAGIC, words
        self.evidence.records.append(words)
        assert 0 <= words[30] <= 4194304, words
        if words[30]:
            self.payloads.append((words, exact(self.evidence.process.stdout, words[30], self.evidence.received)))
        return words

    def command(self, action, a=0, b=0, c=0, payload=b""):
        packet = struct.pack("<8i", action, a, b, c, len(payload), 0, 0, 0) + payload
        with open(self.evidence.directory / "commands.bin", "ab") as output:
            output.write(packet)
        self.evidence.process.stdin.write(packet)
        self.evidence.process.stdin.flush()
        first = self.record()
        expected = 1 if action < 16 else {16: 3, 22: 11, 23: 9, 27: 7}.get(action, 5)
        assert first[1] == expected, (action, first)
        self.last = self.record()
        assert self.last[1] == START[expected], (action, self.last)
        if action == 16 and self.last[31] == 1:
            first = self.record()
            assert first[1] == 21, first
            self.last = self.record()
            assert self.last[1] == 22, self.last
        return self.last

    def collect(self, *, allow_reset=False):
        if allow_reset:
            assert self.last[2] in (2, 3) and self.last[3] == -1 and self.last[24] & 8 and self.last[22] == 1, ("reset allowance requires explicit fatal/aborted cleanup", self.last)
        if self.conn is None or self.eof:
            return
        assert not self.reset or allow_reset, "peer reset cannot satisfy a clean EOF requirement"
        if self.reset:
            return
        while True:
            try:
                data = self.conn.recv(65536)
            except BlockingIOError:
                return
            except ConnectionResetError as error:
                self.reset = True
                self.evidence.peer_actions.append(("server-reset", error.errno, len(self.evidence.peer_wire)))
                assert allow_reset, ("unexpected peer reset", self.last)
                return
            if not data:
                self.eof = True
                self.evidence.peer_actions.append(("server-eof", len(self.evidence.peer_wire)))
                return
            self.evidence.peer_wire.extend(data)

    def send_some(self, data):
        assert self.conn is not None
        try:
            count = self.conn.send(data)
        except BlockingIOError:
            return 0
        assert count > 0
        self.evidence.peer_actions.append(("send", bytes(data[:count])))
        return count

    def send(self, data):
        remaining = memoryview(data)
        deadline = time.monotonic() + 3
        while remaining:
            count = self.send_some(remaining)
            remaining = remaining[count:]
            if not count:
                left = deadline - time.monotonic()
                assert left > 0 and select.select([], [self.conn], [], left)[1], "peer send deadline"

    def half_close(self):
        self.conn.shutdown(socket.SHUT_WR)
        self.evidence.peer_actions.append(("client-half-close",))

    def step(self, ready=0):
        return self.command(ready)

    def progress(self, collect=True):
        if collect:
            self.collect()
        if self.last[4] & 4:
            return self.step()
        if self.last[4] & 3:
            waited = self.command(16)
            if waited[7]:
                return waited
            if waited[1] == 22:
                return self.step(waited[31])
            return self.last
        return self.last

    def until(self, predicate, collect=True, steps=20000):
        for _ in range(steps):
            if predicate(self.last):
                return self.last
            before = len(self.evidence.records)
            self.progress(collect)
            assert len(self.evidence.records) > before, ("unresolved application decision", self.last)
        raise AssertionError(("step bound", self.last))

    def finish(self, *, allow_reset=False):
        if allow_reset:
            assert self.last[2] in (2, 3) and self.last[3] == -1 and self.last[24] & 8 and self.last[22] == 1, ("reset allowance requires explicit fatal/aborted cleanup", self.last)
        self.command(22)
        packet = struct.pack("<8i", 26, 0, 0, 0, 0, 0, 0, 0)
        self.evidence.process.stdin.write(packet)
        self.evidence.process.stdin.flush()
        checkpoint = self.record()
        assert checkpoint[1] == 20, checkpoint
        with open("/proc/%d/task/%d/children" % (self.evidence.process.pid, self.evidence.process.pid), encoding="utf-8") as source:
            children = source.read().split()
        assert len(children) == 1, children
        child = int(children[0])
        assert set(os.listdir("/proc/%d/fd" % child)) == {"0", "1", "2"}, ("descriptors survived destruction", child)
        # Stop the checked prefix at the completed checkpoint write. The later
        # ACK read may not have returned and cannot be treated as a full event.
        # Receiving bytes from write(1) can precede strace's publication of the
        # syscall's return value. Await that same completed marker, keeping the
        # child blocked on its ACK. This waits for observer output, never an
        # inferred EOF or replacement for a required protocol dependency.
        trace_deadline = time.monotonic() + 2
        while True:
            raw = self.trace.read_text(encoding="utf-8")
            complete_lines = []
            found = False
            for line in raw.splitlines():
                complete_lines.append(line)
                match = EVENT.fullmatch(line)
                if match:
                    event = {"name": match.group(2), "args": match.group(3), "result": match.group(4)}
                    marker = record_marker(event)
                    if marker is not None and marker[1] == 20:
                        found = True
                        break
            if found:
                break
            assert time.monotonic() < trace_deadline, ("missing completed trace checkpoint", raw)
            time.sleep(.001)
        prefix = "\n".join(complete_lines) + "\n"
        before = audit_resources(prefix, self.evidence.directory)
        self.evidence.process.stdin.write(b"!")
        self.evidence.process.stdin.close()
        self.evidence.process.stdin = None
        self.evidence.finish_process()
        self.collect(allow_reset=allow_reset)
        text = self.trace.read_text(encoding="utf-8")
        after = audit_resources(text, self.evidence.directory)
        assert before[0] == after[0], (before, after)
        epochs = audit_epochs(text)
        return text, epochs

    def close(self, error=None):
        if self.conn is not None:
            self.conn.close()
            self.conn = None
        self.evidence.close(error)
