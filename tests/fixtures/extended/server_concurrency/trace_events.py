"""Read-only syscall witnesses for accepted socket identities and causal progress."""
from dataclasses import dataclass
from pathlib import Path
import re
import time


LINE = re.compile(r"^\[([0-9a-fA-F]+)\]\s+([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$")


@dataclass
class Accepted:
    ordinal: int
    fd: int
    generation: int
    port: int
    opened: int
    closed: object = None


class Trace:
    def __init__(self, path, process):
        self.path, self.process = Path(path), process
        self.offset, self.partial = 0, b""
        self.events, self.accepted = [], []
        self.sockets, self.files, self.active, self.generations = {}, {}, {}, {}
        self.listener = None
        self.peak_active, self.peak_sockets = 0, 0

    def refresh(self):
        if not self.path.exists():
            return
        with self.path.open("rb") as source:
            source.seek(self.offset)
            block = source.read()
            self.offset += len(block)
        lines = (self.partial + block).split(b"\n")
        self.partial = lines.pop()
        for raw in lines:
            line = raw.decode("ascii")
            if not line or line.startswith(("+++", "---")):
                continue
            match = LINE.fullmatch(line)
            assert match, ("unsupported trace syntax", line)
            address, name, arguments, result = match.groups()
            event = {"ip": int(address, 16), "name": name, "args": arguments,
                     "result": result, "line": line, "index": len(self.events)}
            self.events.append(event)
            value = result.split()[0]
            if name == "socket" and value.isdecimal():
                fd = int(value)
                assert fd not in self.sockets and fd not in self.files, (line, self.sockets)
                self.sockets[fd] = "socket"
            elif name in ("open", "openat") and value.isdecimal():
                fd = int(value)
                assert fd not in self.sockets and fd not in self.files, line
                self.files[fd] = arguments
            elif name == "listen" and value == "0":
                fd = int(arguments.split(",", 1)[0])
                assert fd in self.sockets and self.listener is None, line
                self.listener = fd
                self.sockets[fd] = "listener"
            elif name == "accept4" and value.isdecimal():
                listener = int(arguments.split(",", 1)[0])
                assert listener == self.listener, line
                port = re.search(r"sin6?_port=htons\(([0-9]+)\)", arguments)
                assert port, ("accepted peer address not decoded", line)
                fd = int(value)
                assert fd not in self.sockets and fd not in self.files and fd not in self.active, line
                generation = self.generations.get(fd, 0) + 1
                self.generations[fd] = generation
                record = Accepted(len(self.accepted), fd, generation,
                                  int(port[1]), event["index"])
                self.accepted.append(record)
                self.active[fd] = record
                self.sockets[fd] = "accepted"
            elif name == "close":
                fd = int(arguments)
                if fd in self.sockets:
                    assert value == "0", ("socket close did not succeed", line)
                    del self.sockets[fd]
                    if fd in self.active:
                        record = self.active.pop(fd)
                        assert record.closed is None, ("repeated accepted close", record)
                        record.closed = event["index"]
                elif fd in self.files:
                    assert value == "0", ("native file close failed", line)
                    del self.files[fd]
                else:
                    assert fd in (0, 1, 2), ("unowned descriptor close", line)
            self.peak_active = max(self.peak_active, len(self.active))
            self.peak_sockets = max(self.peak_sockets, len(self.sockets))
            assert self.peak_active <= 2 and self.peak_sockets <= 3, (
                "concurrency cap exceeded (listener is separate)", line,
                self.peak_active, self.peak_sockets)

    def wait(self, predicate, description, timeout=6):
        until = time.monotonic() + timeout
        while True:
            self.refresh()
            result = predicate()
            if result:
                return result
            assert self.process.poll() is None, (
                description, "service exited", self.process.returncode, self.path)
            assert time.monotonic() < until, (description, "deadline", self.path)
            time.sleep(.005)

    def connection(self, source_port):
        return self.wait(lambda: next((item for item in self.accepted
                                      if item.port == source_port), None),
                         f"accept client port {source_port}")

    def assert_open(self, record):
        self.refresh()
        assert record.closed is None and self.active.get(record.fd) is record, (
            "held descriptor retired/reused before dependency release", record)

    def closed(self, record):
        return self.wait(lambda: record.closed is not None,
                         f"close fd {record.fd} generation {record.generation}")

    def received(self, record, count):
        def observed():
            total = 0
            for event in self.events[record.opened:]:
                if record.closed is not None and event["index"] >= record.closed:
                    break
                if event["name"] not in ("recvfrom", "read"):
                    continue
                if event["args"].split(",", 1)[0] == str(record.fd):
                    value = event["result"].split()[0]
                    if value.isdecimal():
                        total += int(value)
            return total >= count
        return self.wait(observed, f"consume partial request on fd {record.fd}")

    def writer_blocked(self, record, after):
        """Require substantial confirmed output followed by EAGAIN, not a ratio."""
        def witness():
            written = 0
            for event in self.events[after:]:
                if record.closed is not None and event["index"] >= record.closed:
                    break
                if event["index"] < record.opened or event["name"] not in ("sendto", "write"):
                    continue
                if event["args"].split(",", 1)[0] != str(record.fd):
                    continue
                value = event["result"].split()[0]
                if value.isdecimal():
                    written += int(value)
                elif written >= 262144 and event["result"].startswith("-1 EAGAIN "):
                    return event
            return None
        return self.wait(witness, "real held response writer EAGAIN", timeout=8)

    def finish(self, count):
        self.refresh()
        assert not self.partial, ("incomplete final trace", self.partial)
        assert len(self.accepted) == count and self.peak_active == 2, self.accepted
        assert self.peak_sockets == 3 and not self.sockets and not self.files and not self.active, (
            self.sockets, self.files, self.active, self.peak_sockets)
        assert all(item.closed is not None for item in self.accepted), self.accepted
        assert any(event["name"] == "poll" for event in self.events), "no shared poll observed"
        return {"accepted": count, "peak_active": self.peak_active,
                "peak_sockets": self.peak_sockets}
