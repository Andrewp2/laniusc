"""CPU mutation controls for the independent trace guards; no native child."""
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace

from support import MAGIC, START, Session, audit_epochs, audit_resources, events, parse_response, request


def marker(tag, io=0):
    row = [0] * 32
    row[0], row[1], row[19] = MAGIC, tag, io
    raw = "".join("\\x%02x" % byte for byte in struct.pack("<32i", *row))
    return '[0000000000401000] write(1, "' + raw + '", 128) = 128'


def epoch(tag, body, charged=0):
    return "\n".join([marker(tag), *body, marker(START[tag], charged)]) + "\n"


def rejected(action):
    try:
        action()
    except AssertionError:
        return
    raise AssertionError("trace mutation was not rejected")


def collector_controls():
    class Peer:
        def __init__(self, value):
            self.value = value

        def recv(self, _count):
            if isinstance(self.value, BaseException):
                raise self.value
            return self.value

    def fixture(status=2, fd=-1, closed=8, cleanup=1, result=None):
        row = [0] * 32
        row[2], row[3], row[24], row[22] = status, fd, closed, cleanup
        return SimpleNamespace(conn=Peer(ConnectionResetError(104, "test reset") if result is None else result),
                               eof=False, reset=False, last=row,
                               evidence=SimpleNamespace(peer_actions=[], peer_wire=bytearray()))

    count = 0
    for status in (2, 3):
        value = fixture(status=status)
        Session.collect(value, allow_reset=True)
        assert value.reset and not value.eof and value.evidence.peer_actions == [("server-reset", 104, 0)]
        count += 1
    value = fixture()
    rejected(lambda: Session.collect(value))
    assert value.reset and not value.eof and value.evidence.peer_actions == [("server-reset", 104, 0)]
    count += 1
    for options in ({"status": 0}, {"status": 1}, {"fd": 4}, {"closed": 0}, {"cleanup": 0}):
        value = fixture(**options)
        rejected(lambda: Session.collect(value, allow_reset=True))
        count += 1
    value = fixture()
    Session.collect(value, allow_reset=True)
    rejected(lambda: Session.collect(value))
    count += 1
    value = fixture(status=1, result=b"")
    Session.collect(value)
    assert value.eof and not value.reset and value.evidence.peer_actions == [("server-eof", 0)]
    count += 1
    value = fixture(status=0, fd=4, closed=0, cleanup=0, result=BlockingIOError())
    Session.collect(value)
    assert not value.eof and not value.reset and not value.evidence.peer_actions
    return count + 1


def run():
    count = 0
    leaf = '[0000000000402000] recvfrom(4, "\\x61", 1, 0, NULL, NULL) = 1'
    poll = '[0000000000403000] poll([{fd=4, events=POLLIN}], 1, 10) = 1 ([{fd=4, revents=POLLIN}])'
    allocation = '[0000000000404000] mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x41000000'
    clock = '[0000000000405000] clock_gettime(CLOCK_MONOTONIC, {tv_sec=1, tv_nsec=0}) = 0'
    socket = '[0000000000406000] socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 3'
    for text in (epoch(1, [leaf], 1), epoch(1, []), epoch(3, [], 1), epoch(21, [poll]), epoch(9, [])):
        audit_epochs(text)
        count += 1
    for tag, body, charged in (
        (1, [leaf, leaf], 2), (1, [poll], 0), (3, [poll], 1), (5, [poll], 0),
        (3, [leaf], 1), (9, [allocation], 0), (9, [clock], 0),
        (1, [leaf.replace(", 1, 0,", ", 1025, 0,")], 1),
        (1, [leaf], 0), (21, [poll], 1), (1, [socket], 0),
    ):
        rejected(lambda: audit_epochs(epoch(tag, body, charged)))
        count += 1
    rejected(lambda: events("futex(0x1, FUTEX_WAKE, 1) = 0\n"))
    count += 1
    text = "\n".join([
        socket,
        '[0000000000406000] accept4(3, NULL, NULL, SOCK_NONBLOCK) = 4',
        allocation,
        '[0000000000404000] munmap(0x41000000, 8) = 0',
        '[0000000000406000] close(4) = 0',
        '[0000000000406000] close(3) = 0',
    ]) + "\n"
    with tempfile.TemporaryDirectory() as directory:
        assert audit_resources(text, directory)[0] == 1
        count += 1
        for invalid in (
            text.replace("munmap(0x41000000, 8)", "munmap(0x41000000, 7)"),
            text.replace('[0000000000406000] close(4) = 0\n', ""),
            text.replace("close(4) = 0", "close(4) = -1 EIO (INJECTED)"),
        ):
            rejected(lambda: audit_resources(invalid, directory))
            count += 1
    assert b"Transfer-Encoding: chunked" in request(b"POST", b"/echo", b"\0\xff", chunked=True)
    parse_response(b"HTTP/1.1 200 OK\r\nDate: Thu, 01 Jan 1970 00:00:00 GMT\r\nConnection: close\r\nContent-Length: 2\r\n\r\n\0\xff", b"POST", 200, b"\0\xff")
    count += 1
    return count + collector_controls()


if __name__ == "__main__":
    print("direct-server CPU guard controls=%d; no native child" % run())
