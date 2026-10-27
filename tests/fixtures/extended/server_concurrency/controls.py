"""CPU-only mutation controls for causal witnesses; no program/network runs."""
from pathlib import Path
import tempfile
from unittest.mock import patch

from trace_events import Trace
from oracle import Journal, REPORT_FIELDS, Response, parse_reports, request, successful_report


class Terminal:
    returncode = 0

    def poll(self):
        return 0


def syscall(value):
    return "[0000000000401000] " + value + "\n"


def accepted(fd, port):
    return syscall(f'accept4(3, {{sa_family=AF_INET, sin_port=htons({port}), '
                   f'sin_addr=inet_addr("127.0.0.1")}}, [128 => 16], '
                   f'SOCK_CLOEXEC|SOCK_NONBLOCK) = {fd}')


def prefix():
    return [syscall('openat(AT_FDCWD, "certificate.pem", O_RDONLY) = 6'),
            syscall('socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 3'),
            syscall('listen(3, 16) = 0'), accepted(4, 10001), accepted(5, 10002)]


def denied(action):
    try:
        action()
    except AssertionError:
        return
    raise AssertionError("mutation was incorrectly accepted")


def trace(directory, lines):
    path = directory / "trace.log"
    path.write_text("".join(lines))
    result = Trace(path, Terminal())
    result.refresh()
    return result


class Memory:
    def __init__(self, parts):
        self.parts = list(parts)
        self.timeouts = []

    def settimeout(self, seconds):
        assert 0 < seconds <= 6
        self.timeouts.append(seconds)

    def recv(self, amount):
        assert amount > 0
        return self.parts.pop(0) if self.parts else b""


def response(body=b"\0\xffbody", *, connection=b"close", extra=b""):
    return (b"HTTP/1.1 200 OK\r\nDate: Sun, 06 Nov 1994 08:49:37 GMT\r\n"
            b"Connection: " + connection + b"\r\nContent-Length: " +
            str(len(body)).encode() + b"\r\n\r\n" + body + extra)


def parser(wire, expected=b"\0\xffbody"):
    _, reader, _ = request(expected)
    return Response(Memory([wire]), reader, expected)


def report(tls=False, **changes):
    values = dict.fromkeys(REPORT_FIELDS, 0)
    values.update(received=91, sent=143, response=143, io=12, cleanup=1,
                  work=1024, scan=91, shutdown=1, eof=1, closed=1)
    if tls:
        values["tls"] = 9
    values["failed"] = 0
    values.update(changes)
    return b" ".join(f"{key}={value}".encode() for key, value in values.items()) + b"\n"


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix="server-concurrency-controls-") as name:
        directory = Path(name)
        lines = prefix() + [syscall('close(5) = 0'), accepted(5, 10003)]
        lines += [syscall('sendto(4, "data", 1024, MSG_NOSIGNAL, NULL, 0) = 1024')] * 256
        lines += [syscall('sendto(4, "data", 1024, MSG_NOSIGNAL, NULL, 0) = -1 EAGAIN (Resource temporarily unavailable)'),
                  syscall('poll([{fd=4, events=POLLOUT}], 1, 1000) = 1 ([{fd=4, revents=POLLOUT}])'),
                  syscall('close(5) = 0'), syscall('close(4) = 0'),
                  syscall('close(3) = 0'), syscall('close(6) = 0')]
        good = trace(directory, lines)
        assert good.finish(3) == {"accepted": 3, "peak_active": 2, "peak_sockets": 3}
        assert [item.generation for item in good.accepted] == [1, 1, 2]
        assert good.accepted[1].fd == good.accepted[2].fd
        assert good.writer_blocked(good.accepted[0], 0)["name"] == "sendto"
        count += 1

        denied(lambda: good.assert_open(good.accepted[1]))
        count += 1
        denied(lambda: trace(directory, prefix() + [accepted(7, 10004)]))
        count += 1
        denied(lambda: trace(directory, lines + [syscall('close(4) = 0')]))
        count += 1
        denied(lambda: trace(directory, prefix() + [syscall('close(4) = -1 EIO (Input/output error)')]))
        count += 1
        denied(lambda: good.connection(10099))
        count += 1

        wrong_direction = [line.replace('sendto(4,', 'recvfrom(4,') for line in lines]
        denied(lambda: trace(directory, wrong_direction).writer_blocked(good.accepted[0], 0))
        count += 1
        interrupted = [line.replace('-1 EAGAIN ', '-1 EINTR ') for line in lines]
        denied(lambda: trace(directory, interrupted).writer_blocked(good.accepted[0], 0))
        count += 1
        too_little = lines[:8] + lines[-6:]
        denied(lambda: trace(directory, too_little).writer_blocked(good.accepted[0], 0))
        count += 1

        # A later owner of the same integer fd cannot satisfy the old owner.
        reused = prefix() + [syscall('close(4) = 0'), accepted(4, 10004)]
        reused += [syscall('write(4, "data", 1024) = 1024')] * 256
        reused += [syscall('write(4, "data", 1024) = -1 EAGAIN (Resource temporarily unavailable)')]
        later = trace(directory, reused)
        denied(lambda: later.writer_blocked(later.accepted[0], 0))
        count += 1

        parser(response()).advance()
        fragmented = response()
        _, reader, _ = request(b"\0\xffbody")
        Response(Memory([fragmented[:17], fragmented[17:]]), reader, b"\0\xffbody").advance()
        count += 2
        denied(lambda: parser(response(b"wrong!", connection=b"close")).advance())
        count += 1
        denied(lambda: parser(response(connection=b"keep-alive")).advance())
        count += 1
        denied(lambda: parser(response(extra=b"surplus")).advance())
        count += 1

        # Responsive receives cannot keep resetting the response deadline.
        now = [0]
        class Trickle(Memory):
            def recv(self, amount):
                now[0] += 4
                return super().recv(amount)
        payload = b"abcdefgh"
        wire = response(payload)
        cut = wire.index(b"\r\n\r\n") + 4
        slow = Trickle([wire[:cut], *[bytes([byte]) for byte in payload]])
        _, reader, _ = request(payload)
        with patch("oracle.time.monotonic", side_effect=lambda: now[0]):
            denied(lambda: Response(slow, reader, payload).advance())
        assert len(slow.parts) > 0 and slow.timeouts[-1] < 6
        count += 1

        # Flushed evidence survives an exception before ordinary cleanup.
        journal_path = directory / "oracle-events.log"
        journal = Journal(journal_path)
        journal.note("held-peer", port=10001, fd=4, generation=1)
        assert "held-peer port=10001 fd=4 generation=1" in journal_path.read_text()
        journal.close()
        count += 1

        for tls in (False, True):
            parsed = parse_reports(report(tls), tls)
            assert len(parsed) == 1
            successful_report(parsed[0], 0, 91, 143, tls)
            count += 1
            for key, value in (("shutdown", 0), ("eof", 0), ("closed", 0),
                               ("code", 3), ("failed", 1), ("id", 1),
                               ("received", 90), ("sent", 142), ("cleanup", 0)):
                denied(lambda k=key, v=value: successful_report(
                    parse_reports(report(tls, **{k: v}), tls)[0], 0, 91, 143, tls))
                count += 1
            denied(lambda: parse_reports(report(tls).replace(b" closed=1", b""), tls))
            count += 1
            denied(lambda: parse_reports(report(tls).replace(b" failed=0", b" accepted=143 failed=0"), tls))
            count += 1
            denied(lambda: parse_reports(report(tls).replace(b" id=0", b" id=0 id=0"), tls))
            count += 1
        denied(lambda: parse_reports(report(True), False))
        count += 1
        denied(lambda: parse_reports(report(False), True))
        count += 1
        denied(lambda: parse_reports(report(False).rstrip(b"\n"), False))
        count += 1
    print(f"server-concurrency infrastructure controls={count} native-cases=0")


if __name__ == "__main__":
    main()
