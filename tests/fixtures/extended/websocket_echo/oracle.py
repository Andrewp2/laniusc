"""Independent loopback clients for the one-message WebSocket echo example.

This is a finite functional oracle. Python h11 parses HTTP, a separate frame
parser checks server wire bytes, and Python ssl/OpenSSL supplies TLS. There is
no production implementation, allocation ledger or resource verifier here.
"""
from __future__ import annotations

import base64
from contextlib import contextmanager
from io import BytesIO
import importlib.util
import os
from pathlib import Path
import re
import selectors
import signal
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import _sha1

import h11

HERE = Path(__file__).resolve().parent
GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
CLOSE = struct.pack("!H", 1000)
BINARY = bytes(range(256)) + b"\x00\xff\r\n"
ORIGIN = "https://fixture.test"
HELP = (b"Usage: websocket-echo ENDPOINT [--tls-cert FILE --tls-key FILE] [--origin ORIGIN]\n"
        b"Listen once on a numeric endpoint (port 0 allowed); print the bound endpoint.\n"
        b"Echo one message at /echo, then mirror Close. Optional Origin must match exactly.\n"
        b"Limits: 65536 message bytes, 64 fragments, 256 frames, 5-second service deadline.\n")
ERRORS = {status: b"websocket-echo: operation failed\n" for status in (2, 3, 4, 5)}


def load(name, path):
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


CERTS = load("websocket_echo_certificates", HERE.parent / "openssl_tls/certificates.py")


def frame(opcode, payload=b"", *, fin=True, rsv=0, masked=True):
    first = (0x80 if fin else 0) | rsv | opcode
    length = len(payload)
    bit = 0x80 if masked else 0
    if length < 126:
        head = bytes((first, bit | length))
    elif length < 65536:
        head = bytes((first, bit | 126)) + struct.pack("!H", length)
    else:
        head = bytes((first, bit | 127)) + struct.pack("!Q", length)
    if not masked:
        return head + payload
    key = os.urandom(4)
    return head + key + bytes(value ^ key[index % 4] for index, value in enumerate(payload))


class Wire:
    def __init__(self, read, write):
        self.read, self.write = read, write
        self.pending = bytearray()

    def take(self, count):
        assert 0 <= count <= 131072
        while len(self.pending) < count:
            data = self.read(min(16384, count - len(self.pending)))
            if not data:
                raise EOFError(f"server EOF: need={count} buffered={len(self.pending)}")
            self.pending.extend(data)
        result = bytes(self.pending[:count])
        del self.pending[:count]
        return result

    def response(self, status=101, key=None):
        head = bytearray()
        while not head.endswith(b"\r\n\r\n"):
            assert len(head) < 16384
            head.extend(self.take(1))
        parser = h11.Connection(h11.CLIENT)
        parser.send(h11.Request(method=b"GET", target=b"/echo", headers=[
            (b"Host", b"fixture.test"), (b"Connection", b"Upgrade"),
            (b"Upgrade", b"websocket"),
        ]))
        parser.send(h11.EndOfMessage())
        parser.receive_data(bytes(head))
        response = parser.next_event()
        assert isinstance(response, (h11.Response, h11.InformationalResponse)), response
        assert (response.status_code, response.http_version) == (status, b"1.1"), response
        fields = list(response.headers)
        values = lambda name: [value for field, value in fields if field == name]
        if status == 101:
            assert values(b"upgrade") == [b"websocket"], fields
            assert [value.lower() for value in values(b"connection")] == [b"upgrade"], fields
            expected = base64.b64encode(_sha1.sha1(key + GUID).digest())
            assert values(b"sec-websocket-accept") == [expected], fields
            assert not values(b"sec-websocket-protocol") and not values(b"sec-websocket-extensions"), fields
            assert not values(b"content-length") and not values(b"transfer-encoding"), fields
        else:
            assert [value.lower() for value in values(b"connection")] == [b"close"], fields
            assert values(b"content-length") == [b"0"], fields
            if status == 400:
                assert values(b"sec-websocket-version") == [b"13"], fields
            assert not values(b"sec-websocket-accept"), fields
        return response

    def server_frame(self):
        first, second = self.take(2)
        assert not first & 0x70, "server must not set RSV bits"
        assert not second & 0x80, "server frames must not be masked"
        opcode, fin = first & 15, bool(first & 0x80)
        assert opcode in (0, 1, 2, 8, 9, 10), opcode
        length = second & 127
        if length == 126:
            length = struct.unpack("!H", self.take(2))[0]
            assert length >= 126
        elif length == 127:
            length = struct.unpack("!Q", self.take(8))[0]
            assert length >= 65536
        assert length <= 65536
        if opcode >= 8:
            assert fin and length <= 125
        return opcode, self.take(length), fin


def request(*, target=b"/echo", method=b"GET", key=None, version=b"13", extra=b"", upgrade=True):
    key = base64.b64encode(os.urandom(16)) if key is None else key
    raw = method + b" " + target + b" HTTP/1.1\r\nHost: fixture.test\r\n"
    if upgrade:
        raw += b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
    raw += b"Sec-WebSocket-Key: " + key + b"\r\nSec-WebSocket-Version: " + version + b"\r\n"
    return raw + extra + b"\r\n", key


def endpoint(value):
    if value.startswith("["):
        host, port = value[1:].split("]:")
        assert socket.inet_pton(socket.AF_INET6, host)
    else:
        host, port = value.rsplit(":", 1)
        assert socket.inet_pton(socket.AF_INET, host)
    port = int(port)
    assert 1 <= port <= 65535
    return host, port


def ready(process):
    deadline = time.monotonic() + 5
    line = bytearray()
    with selectors.DefaultSelector() as selector:
        selector.register(process.stdout, selectors.EVENT_READ)
        while not line.endswith(b"\n"):
            left = deadline - time.monotonic()
            assert left > 0, "server did not publish readiness"
            assert selector.select(left), "server readiness timeout"
            byte = os.read(process.stdout.fileno(), 1)
            assert byte, ("server exited before readiness", process.poll())
            line.extend(byte)
            assert len(line) <= 96
    text = line[:-1].decode("ascii")
    endpoint(text)
    return bytes(line), text


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"websocket-echo-{mode}-"))
        self.count = 0
        self.deadline = time.monotonic() + 75

    def checked(self, name, result, expected, stdout):
        assert result.returncode == expected, (name, result.returncode, result.stdout, result.stderr)
        assert result.stdout == stdout, (name, result.stdout, stdout)
        assert result.stderr == (b"" if expected == 0 else ERRORS[expected]), (name, result.stderr)
        prefix = self.directory / name
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".receipt").write_text(repr((result.args, result.returncode)) + "\n")
        self.count += 1

    @contextmanager
    def server(self, name, *, arguments=(), status=0, address="127.0.0.1:0"):
        assert time.monotonic() < self.deadline, "group deadline exhausted"
        command = [self.executable, address, *map(str, arguments)]
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        announcement = b""
        try:
            announcement, bound = ready(process)
            assert bound.endswith(":0") is False, bound
            yield bound
            stdout, stderr = process.communicate(timeout=9)
            result = subprocess.CompletedProcess(command, process.returncode,
                                                 announcement + stdout, stderr)
            self.checked(name, result, status, announcement)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=2)

    def preflight(self, name, arguments, *, status=2, expected=b"", no_network=True, closed_reader=False):
        assert time.monotonic() < self.deadline, "group deadline exhausted"
        command = [self.executable, *map(str, arguments)]
        trace = self.directory / f"{name}.trace"
        if no_network:
            command = ["strace", "-qq", "-f", "-o", str(trace), "-e", "trace=network", *command]
        if closed_reader:
            read_fd, write_fd = os.pipe()
            os.close(read_fd)
            try:
                result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=write_fd,
                                        stderr=subprocess.PIPE, timeout=9, check=False)
            finally:
                os.close(write_fd)
            result.stdout = b""
        else:
            result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True,
                                    timeout=9, check=False)
        self.checked(name, result, status, expected)
        if no_network:
            events = trace.read_text()
            assert not re.search(r"\b(?:socket|socketpair|connect|accept|accept4|bind|listen|sendto|recvfrom|sendmsg|recvmsg)\(", events), events


def connected(bound):
    connection = socket.create_connection(endpoint(bound), timeout=3)
    connection.settimeout(4)
    return connection


def handshake(wire, **options):
    head, key = request(**options)
    wire.write(head)
    wire.response(key=key)


def normal(wire, *, payload=BINARY, opcode=2, fragments=1, ping=False, origin=False, extra_message=False):
    handshake(wire, extra=b"Origin: " + ORIGIN.encode() + b"\r\n" if origin else b"")
    wire.write(frame(10, b"unsolicited pong"))
    if fragments == 1:
        wire.write(frame(opcode, payload))
    else:
        for index in range(fragments):
            start = len(payload) * index // fragments
            end = len(payload) * (index + 1) // fragments
            wire.write(frame(opcode if index == 0 else 0, payload[start:end], fin=index == fragments - 1))
            if index == 0 and ping:
                wire.write(frame(9, b"\x00ping\xff"))
                assert wire.server_frame() == (10, b"\x00ping\xff", True)
    assert wire.server_frame() == (opcode, payload, True)
    # Control traffic remains legal while the server waits for Close.
    wire.write(frame(9, b"after echo"))
    assert wire.server_frame() == (10, b"after echo", True)
    close = CLOSE + b"done"
    if extra_message:
        wire.write(frame(2, b"second message is not echoed") + frame(8, close))
    else:
        wire.write(frame(8, close))
    assert wire.server_frame() == (8, close, True)


def plain(r):
    values = [
        ("binary", {}), ("empty-binary", {"payload": b""}),
        ("empty-text", {"payload": b"", "opcode": 1}),
        ("text-fragment-ping", {"payload": "€𐍈".encode(), "opcode": 1, "fragments": 3, "ping": True}),
        ("binary-fragment-ping", {"fragments": 3, "ping": True}),
        ("length-126", {"payload": b"x" * 126}),
        ("maximum-65536", {"payload": bytes(range(256)) * 256}),
        ("maximum-fragments-64", {"payload": bytes(range(64)), "fragments": 64}),
        ("origin", {"origin": True}), ("ipv6", {}),
        ("first-message-only", {"extra_message": True}),
    ]
    for name, options in values:
        arguments = ("--origin", ORIGIN) if options.get("origin") else ()
        with r.server(name, arguments=arguments, address="[::1]:0" if name == "ipv6" else "127.0.0.1:0") as bound:
            with connected(bound) as connection:
                normal(Wire(connection.recv, connection.sendall), **options)


def handshake_rejection(r):
    values = [
        ("wrong-key", {"key": b"invalid"}, 400, False),
        ("wrong-version", {"version": b"12"}, 400, False),
        ("wrong-method", {"method": b"POST"}, 400, False),
        ("wrong-route", {"target": b"/elsewhere"}, 404, False),
        ("query-route", {"target": b"/echo?x=1"}, 404, False),
        ("origin-missing", {}, 403, True),
        ("origin-different", {"extra": b"Origin: https://wrong.test\r\n"}, 403, True),
        ("origin-duplicate", {"extra": b"Origin: " + ORIGIN.encode() + b"\r\nOrigin: " + ORIGIN.encode() + b"\r\n"}, 400, True),
        ("duplicate-key", {"extra": b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"}, 400, False),
        ("missing-upgrade", {"upgrade": False}, 400, False),
        ("early-captured-frame", {}, 400, False),
        ("truncated-head", {}, 400, False),
    ]
    for name, options, status, origin in values:
        with r.server(name, arguments=("--origin", ORIGIN) if origin else (), status=3) as bound:
            with connected(bound) as connection:
                wire = Wire(connection.recv, connection.sendall)
                head, _ = request(**options)
                if name == "early-captured-frame":
                    head += frame(2, b"too early")
                if name == "truncated-head":
                    head = head[:-2]
                wire.write(head)
                if name == "truncated-head":
                    connection.shutdown(socket.SHUT_WR)
                wire.response(status=status)
                assert connection.recv(1) == b"", name


def rejection(r):
    values = ["unmasked", "rsv", "invalid-utf8", "truncated-data", "unclean-before-data",
              "unclean-after-echo", "early-close", "abnormal-close",
              "oversized-frame", "fragments-65"]
    for name in values:
        with r.server(name, status=3) as bound:
            with connected(bound) as connection:
                wire = Wire(connection.recv, connection.sendall)
                handshake(wire)
                if name == "unmasked":
                    wire.write(frame(2, BINARY, masked=False))
                elif name == "rsv":
                    wire.write(frame(2, BINARY, rsv=0x40))
                elif name == "invalid-utf8":
                    wire.write(frame(1, b"\xff"))
                elif name == "truncated-data":
                    wire.write(frame(2, BINARY)[:-3])
                elif name in ("unclean-after-echo", "abnormal-close"):
                    wire.write(frame(2, BINARY))
                    assert wire.server_frame() == (2, BINARY, True)
                    if name == "abnormal-close":
                        close = struct.pack("!H", 1001)
                        wire.write(frame(8, close))
                        assert wire.server_frame() == (8, close, True)
                elif name == "early-close":
                    wire.write(frame(8, CLOSE))
                    assert wire.server_frame() == (8, CLOSE, True)
                elif name == "oversized-frame":
                    wire.write(b"\x82\xff" + struct.pack("!Q", 65537))
                elif name == "fragments-65":
                    wire.write(b"".join(frame(2 if i == 0 else 0, b"", fin=False) for i in range(65)))
                connection.shutdown(socket.SHUT_WR)
                # Optional protocol Close/control frames are allowed; no
                # failed or second application message may be published.
                for _ in range(4):
                    try:
                        opcode, payload, fin = wire.server_frame()
                    except (EOFError, ConnectionResetError):
                        break
                    assert opcode in (8, 9, 10), (name, opcode, payload)
                else:
                    raise AssertionError((name, "too many failure control frames"))


def cli(r):
    base = ["127.0.0.1:0"]
    values = [
        ("missing-endpoint", []), ("extra-operand", base + ["extra"]),
        ("unknown-option", base + ["--wat"]),
        ("hostname-endpoint", ["fixture.test:0"]), ("bad-port", ["127.0.0.1:65536"]),
        ("cert-without-key", base + ["--tls-cert", "unused.pem"]),
        ("key-without-cert", base + ["--tls-key", "unused.key"]),
        ("empty-cert", base + ["--tls-cert", "", "--tls-key", "unused.key"]),
        ("empty-origin", base + ["--origin", ""]),
        ("injected-origin", base + ["--origin", "https://x\r\nInjected: yes"]),
        ("duplicate-origin", base + ["--origin", ORIGIN, "--origin", ORIGIN]),
        ("duplicate-cert", base + ["--tls-cert", "a", "--tls-cert", "b", "--tls-key", "c"]),
    ]
    for name, arguments in values:
        r.preflight(name, arguments)
    r.preflight("help", ["--help"], status=0, expected=HELP)
    r.preflight("short-help", ["-h"], status=0, expected=HELP)


def client_context(directory, version, authority="root"):
    context = ssl.create_default_context(cafile=str(directory / f"{authority}.pem"))
    context.minimum_version = context.maximum_version = version
    return context


def tls(r):
    directory = r.directory / "certificates"
    CERTS.generate(directory)
    credentials = ["--tls-cert", directory / "valid.pem", "--tls-key", directory / "valid.key"]
    for name, version in (("tls12", ssl.TLSVersion.TLSv1_2), ("tls13", ssl.TLSVersion.TLSv1_3)):
        with r.server(name, arguments=credentials) as bound:
            raw = connected(bound)
            with client_context(directory, version).wrap_socket(raw, server_hostname="localhost") as connection:
                assert connection.version() == ("TLSv1.2" if name == "tls12" else "TLSv1.3")
                normal(Wire(connection.recv, connection.sendall), fragments=3, ping=True)
                # unwrap sends and verifies close_notify in both directions.
                plain_socket = connection.unwrap()
                plain_socket.close()
    with r.server("bad-trust", arguments=credentials, status=3) as bound:
        raw = connected(bound)
        try:
            client_context(directory, ssl.TLSVersion.TLSv1_3, "untrusted").wrap_socket(raw, server_hostname="localhost")
        except ssl.SSLCertVerificationError:
            pass
        else:
            raise AssertionError("untrusted server certificate accepted")
        finally:
            raw.close()
    with r.server("local-close-notify", arguments=credentials) as bound:
        raw = connected(bound)
        connection = client_context(directory, ssl.TLSVersion.TLSv1_3).wrap_socket(
            raw, server_hostname="localhost", suppress_ragged_eofs=False)
        with connection:
            normal(Wire(connection.recv, connection.sendall))
            # Existing TLS shutdown sends the local authenticated alert; it
            # does not wait for a peer alert. Strict EOF distinguishes that
            # close_notify from an unauthenticated bare transport EOF.
            assert connection.recv(1) == b""


def credentials(r):
    directory = r.directory / "certificates"
    CERTS.generate(directory)
    for name, cert, key in (
        ("missing-cert", directory / "missing.pem", directory / "valid.key"),
        ("missing-key", directory / "valid.pem", directory / "missing.key"),
        ("mismatched-key", directory / "valid.pem", directory / "untrusted.key"),
    ):
        r.preflight(name, ["127.0.0.1:0", "--tls-cert", cert, "--tls-key", key], status=3)


def io(r):
    r.preflight("closed-readiness-stdout", ["127.0.0.1:0"], status=5,
                no_network=False, closed_reader=True)


def deadline(r):
    started = time.monotonic()
    with r.server("accept-deadline", status=3):
        pass
    assert 4.5 <= time.monotonic() - started < 9


def integration(r, client):
    with r.server("lanius-client") as bound:
        result = subprocess.run([str(Path(client).resolve()), bound, "fixture.test", "/echo"],
                                input=BINARY, capture_output=True, timeout=9, check=False)
        assert result.returncode == 0 and result.stdout == BINARY and not result.stderr, result


def controls():
    assert len(HELP) == 324
    for payload in (b"", b"x", b"x" * 125, b"x" * 126, bytes(range(256)) * 256):
        wire = Wire(BytesIO(frame(2, payload, masked=False)).read, lambda data: None)
        assert wire.server_frame() == (2, payload, True)
    try:
        Wire(BytesIO(frame(2, b"x", masked=True)).read, lambda data: None).server_frame()
    except AssertionError:
        pass
    else:
        raise AssertionError("masked-server control failed")
    sample = b"dGhlIHNhbXBsZSBub25jZQ=="
    response = (b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                b"Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n\r\n")
    Wire(BytesIO(response).read, lambda data: None).response(key=sample)
    for value in ("127.0.0.1:1234", "[::1]:1234"):
        endpoint(value)
    print("websocket-echo CPU controls=9")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable, *extra = sys.argv[1:]
        assert (len(extra) == 1) if mode == "integration" else not extra
        def expired(signum, stack):
            raise TimeoutError("WebSocket echo oracle group exceeded 77 seconds")
        signal.signal(signal.SIGALRM, expired)
        signal.setitimer(signal.ITIMER_REAL, 77)
        runner = Runner(executable, mode)
        if mode == "integration":
            integration(runner, extra[0])
        else:
            {"plain": plain, "handshake": handshake_rejection, "rejection": rejection,
             "cli": cli, "tls": tls, "credentials": credentials, "deadline": deadline, "io": io}[mode](runner)
        print(f"websocket-echo-{mode} cases={runner.count} evidence={runner.directory}")
