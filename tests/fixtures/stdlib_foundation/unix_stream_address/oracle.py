"""Independent raw-address peers for the real Lanius UnixStream boundary.

Python sockets provide the other endpoint and host-only queue controls. Names
are raw bytes, not UTF-8 strings or @ shorthand. Readiness uses completed
bind/listen or an explicit pipe byte; no sleep proves readiness.
"""
from __future__ import annotations

from collections import Counter
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import select
import socket
import stat
import struct
import subprocess
import sys
import tempfile

REQUEST = bytes((index * 37 + 11) & 255 for index in range(16))
RESPONSE = bytes(value ^ 90 for value in REQUEST[::-1])
SUCCESS = (0, 0, 0, 1)
INVALID = (1, 1, 0, 1)
BLOCKED = (1, 8, 0, 1)
IN_USE = (1, 10, errno.EADDRINUSE, 1)


@contextmanager
def at_directory(directory):
    saved = os.open(".", os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.chdir(directory)
        yield
    finally:
        os.fchdir(saved)
        os.close(saved)


def address(namespace, name): return name if namespace == 0 else b"\0" + name


def host_bind(stream, namespace, name, directory):
    with at_directory(directory): stream.bind(address(namespace, name))


def host_connect(stream, namespace, name, directory):
    with at_directory(directory): stream.connect(address(namespace, name))


def physical(directory, name):
    return name if name.startswith(b"/") else os.path.join(os.fsencode(directory), name)


def unlink_path(namespace, name, directory):
    if namespace == 0 and name:
        try: os.unlink(physical(directory, name))
        except FileNotFoundError: pass


def frame(mode, namespace, layout, name, mutation=0):
    assert mode in range(4) and namespace in (0, 1) and layout in (0, 1)
    assert len(name) <= 108 and mutation in range(4)
    assert mutation == 0 or (namespace == 0 and name)
    assert namespace == 1 or b"\0" not in name
    return struct.pack("<8Q", mode, namespace, layout, len(name), mutation, 0, 0, 0) + name


def receive_eof(stream):
    chunks = bytearray()
    while True:
        part = stream.recv(17 - len(chunks))
        if not part: return bytes(chunks)
        chunks += part
        assert len(chunks) <= 16, ("extra peer bytes", chunks)


class Child:
    def __init__(self, executable, directory, payload, label):
        self.label = label
        self.process = subprocess.Popen([str(executable)], cwd=directory, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.process.stdin.write(payload)
        self.process.stdin.close()
        self.process.stdin = None

    def ready(self):
        readable, _, _ = select.select([self.process.stdout], [], [], 6)
        assert readable, (self.label, "readiness timeout")
        assert os.read(self.process.stdout.fileno(), 1) == b"R", (self.label, "missing bind/listen readiness")

    def finish(self, expected):
        output, errors = self.process.communicate(timeout=9)
        assert self.process.returncode == 0, (self.label, self.process.returncode, output, errors)
        assert not errors and len(output) == 32, (self.label, output, errors)
        observed = struct.unpack("<4Q", output)
        assert observed == expected, (self.label, observed, expected)

    def close(self):
        if self.process.poll() is None: self.process.kill()
        self.process.communicate(timeout=2)


class Runner:
    def __init__(self, executable, directory):
        self.executable, self.directory = executable, directory
        self.counts = Counter()

    def child(self, mode, namespace, layout, name, label, mutation=0):
        return Child(self.executable, self.directory, frame(mode, namespace, layout, name, mutation), label)

    def probe(self, mode, namespace, layout, name, expected, label, mutation=0):
        child = self.child(mode, namespace, layout, name, label, mutation)
        try: child.finish(expected)
        finally: child.close()
        self.counts["probes"] += 1

    def peer(self, namespace, layout, name, role, label):
        guards = []
        listener = None
        child = None
        try:
            if namespace == 1 and b"\0" in name:
                for other in set((name.split(b"\0", 1)[0], name.rstrip(b"\0"))):
                    if other == name: continue
                    guard = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    guards.append(guard)
                    host_bind(guard, 1, other, self.directory)
                    guard.listen(1)
            if role == 0:
                child = self.child(0, namespace, layout, name, label)
                child.ready()
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as peer:
                    peer.settimeout(4)
                    host_connect(peer, namespace, name, self.directory)
                    peer.sendall(REQUEST)
                    peer.shutdown(socket.SHUT_WR)
                    assert receive_eof(peer) == RESPONSE, (label, "server response")
                child.finish(SUCCESS)
            else:
                listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                host_bind(listener, namespace, name, self.directory)
                listener.listen(1)
                listener.settimeout(4)
                child = self.child(1, namespace, layout, name, label)
                connection, _ = listener.accept()
                with connection:
                    connection.settimeout(4)
                    assert receive_eof(connection) == REQUEST, (label, "client request")
                    connection.sendall(RESPONSE)
                    connection.shutdown(socket.SHUT_WR)
                child.finish(SUCCESS)
            if namespace == 0:
                path = physical(self.directory, name)
                assert stat.S_ISSOCK(os.lstat(path).st_mode), (label, "pathname did not persist")
            self.counts["peers"] += 1
        finally:
            if child is not None: child.close()
            if listener is not None: listener.close()
            for guard in guards: guard.close()
            unlink_path(namespace, name, self.directory)


def peers(runner):
    token = Path(runner.directory).name.encode()
    names = [(0, "path-min", b"s"), (0, "path-normal", b"ordinary.sock"),
             (0, "path-max", b"p" * 107), (0, "path-non-utf8", b"raw-\xff\x80.sock"),
             (0, "path-at-literal", b"@literal.sock"),
             (1, "abstract-empty", b""), (1, "abstract-min", b"\xff"),
             (1, "abstract-normal", b"normal-" + token),
             (1, "abstract-max", (b"max-" + token).ljust(107, b"M")),
             (1, "abstract-embedded-nul", b"embedded-" + token + b"\0tail"),
             (1, "abstract-trailing-nul", b"trailing-" + token + b"\0"),
             (1, "abstract-multiple-nul", b"multiple-" + token + b"\0tail\0\0"),
             (1, "abstract-at-literal", b"@literal-" + token)]
    for namespace, name_label, name in names:
        assert len(name) <= 107
        for role in range(2):
            for layout in range(2):
                runner.peer(namespace, layout, name, role, (name_label, role, layout, name))
    assert runner.counts["peers"] == 52


def empty_queue(listener, label):
    listener.setblocking(False)
    try:
        connection, _ = listener.accept()
    except BlockingIOError as failure:
        assert failure.errno in (errno.EAGAIN, errno.EWOULDBLOCK)
    else:
        connection.close()
        raise AssertionError((label, "invalid connect reached listener"))


def boundaries(runner):
    token = Path(runner.directory).name.encode()
    for namespace, name in ((0, b""), (0, b"q" * 108), (1, b"q" * 108)):
        for mode in (2, 3):
            for layout in range(2):
                before = set(os.listdir(os.fsencode(runner.directory)))
                runner.probe(mode, namespace, layout, name, INVALID, ("invalid-length", mode, namespace, layout, len(name)))
                assert set(os.listdir(os.fsencode(runner.directory))) == before

    for mode in (2, 3):
        for layout in range(2):
            for mutation in (1, 2, 3):
                name = f"mutation-{mode}-{layout}-{mutation}.sock".encode()
                label = ("mutated-path", mode, layout, mutation)
                listener = None
                try:
                    if mode == 3:
                        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                        host_bind(listener, 0, name, runner.directory)
                        listener.listen(1)
                    before = set(os.listdir(os.fsencode(runner.directory)))
                    runner.probe(mode, 0, layout, name, INVALID, label, mutation)
                    assert set(os.listdir(os.fsencode(runner.directory))) == before
                    if listener is not None: empty_queue(listener, label)
                finally:
                    if listener is not None: listener.close()
                    unlink_path(0, name, runner.directory)

    for layout in range(2):
        name = f"regular-existing-{layout}".encode()
        path = physical(runner.directory, name)
        with open(path, "wb") as file: file.write(b"existing file stays")
        try:
            runner.probe(2, 0, layout, name, IN_USE, ("existing-regular", layout))
            assert stat.S_ISREG(os.lstat(path).st_mode)
            with open(path, "rb") as file: assert file.read() == b"existing file stays"
        finally: os.unlink(path)

    for namespace in (0, 1):
        for layout in range(2):
            name = f"existing-listener-{namespace}-{layout}".encode() + (b"-" + token if namespace else b".sock")
            listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                host_bind(listener, namespace, name, runner.directory)
                listener.listen(1)
                listener.settimeout(4)
                runner.probe(2, namespace, layout, name, IN_USE, ("existing-listener", namespace, layout))
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control:
                    control.settimeout(4)
                    host_connect(control, namespace, name, runner.directory)
                    accepted, _ = listener.accept()
                    accepted.close()
            finally:
                listener.close()
                unlink_path(namespace, name, runner.directory)

    for layout in range(2):
        name = f"persist-{layout}.sock".encode()
        try:
            runner.probe(2, 0, layout, name, SUCCESS, ("path-persistence", layout))
            assert stat.S_ISSOCK(os.lstat(physical(runner.directory, name)).st_mode)
            runner.probe(2, 0, layout, name, IN_USE, ("path-rebind-refused", layout))
        finally: unlink_path(0, name, runner.directory)
        abstract = b"reusable-" + token + bytes((48 + layout,))
        runner.probe(2, 1, layout, abstract, SUCCESS, ("abstract-reuse", layout))
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as control:
            host_bind(control, 1, abstract, runner.directory)


def failed_connect_state(candidate):
    error = candidate.getsockopt(socket.SOL_SOCKET, socket.SO_ERROR)
    assert error == 0, ("failed AF_UNIX SO_ERROR", error)
    try:
        candidate.getpeername()
    except OSError as failure:
        assert failure.errno == errno.ENOTCONN, failure
    else:
        raise AssertionError("EAGAIN candidate unexpectedly has a peer")
    poll = select.poll()
    poll.register(candidate, select.POLLOUT)
    writable = any(flags & select.POLLOUT for _, flags in poll.poll(0))
    return writable


def backlog(runner):
    token = Path(runner.directory).name.encode()
    for namespace in (0, 1):
        name = b"backlog-" + token + bytes((48 + namespace,))
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        queued = []
        try:
            host_bind(listener, namespace, name, runner.directory)
            listener.listen(0)
            full = False
            for attempt in range(16):
                candidate = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                retained = False
                try:
                    candidate.setblocking(False)
                    with at_directory(runner.directory): status = candidate.connect_ex(address(namespace, name))
                    if status == 0:
                        queued.append(candidate)
                        retained = True
                        continue
                    assert status == errno.EAGAIN, ("full queue status", status)
                    runner.counts["backlog_writable_controls"] += failed_connect_state(candidate)
                finally:
                    if not retained: candidate.close()
                full = True
                break
            assert full and queued, "bounded host attempts did not establish a full queue"
            # No accept or close of queued peers occurs before this library call.
            runner.probe(3, namespace, namespace, name, BLOCKED, ("full-backlog", namespace, len(queued)))
            listener.setblocking(False)
            accepted_count = 0
            while True:
                try: accepted, _ = listener.accept()
                except BlockingIOError: break
                accepted.close()
                accepted_count += 1
                assert accepted_count <= 16
            assert accepted_count == len(queued), ("unexpected acknowledged connection", accepted_count, len(queued))
            runner.counts["backlog"] += 1
        finally:
            for candidate in queued: candidate.close()
            listener.close()
            unlink_path(namespace, name, runner.directory)


def controls():
    # Pure framing/vector controls. The dedicated host-only backlog control was
    # run before source freeze; actual runtime backlog cases repeat that setup.
    assert len(frame(0, 1, 0, b"")) == 64
    assert len(frame(0, 1, 1, b"x" * 107)) == 171
    assert frame(0, 1, 0, b"a\0b\0")[64:] == b"a\0b\0"
    assert REQUEST != RESPONSE and len(REQUEST) == len(RESPONSE) == 16
    assert struct.unpack("<8Q", frame(2, 0, 1, b"name", 3)[:64]) == (2, 0, 1, 4, 3, 0, 0, 0)
    print("unix-stream-address CPU framing=5 peers=52 report-probes=36 backlog-probes=2 total=90")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <named-executable> | controls"
    executable = Path(sys.argv[1]).resolve()
    with tempfile.TemporaryDirectory(prefix="lanius-unix-address-") as directory:
        runner = Runner(executable, directory)
        peers(runner)
        boundaries(runner)
        before = runner.counts["probes"]
        assert before == 36, runner.counts
        backlog(runner)
        assert runner.counts["probes"] == 38 and runner.counts["backlog"] == 2, runner.counts
        assert not os.listdir(directory), ("explicit pathname cleanup", os.listdir(directory))
        print(f"unix-stream-address cases={runner.counts['peers'] + runner.counts['probes']} "
              f"peers=52 boundaries=36 backlog=2 layouts=2 writable-unconnected-host-controls="
              f"{runner.counts['backlog_writable_controls']}")


if __name__ == "__main__":
    main()
