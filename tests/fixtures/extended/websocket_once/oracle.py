"""Independent finite loopback peers for websocket-once; test code only.

Python parses the actual client frames and OpenSSL supplies all TLS and test
certificate operations. This is a functional oracle, not a leak checker.
"""
import base64
import hashlib
import importlib.util
from io import BytesIO
import os
from pathlib import Path
import re
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time

import h11

HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TLS = load("websocket_once_tls_peer", HERE.parent / "openssl_tls/peer.py")
CERTS = load("websocket_once_certificates", HERE.parent / "openssl_tls/certificates.py")
GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
UPLOAD = b"\x00client\xff\r\n"
BINARY = bytes(range(256)) + b"\x00\xff\r\n"
CLOSE = struct.pack("!H", 1000)
HELP = (b"Usage: websocket-once ENDPOINT AUTHORITY TARGET [--tls-name DNS] [--ca-file FILE]\n"
        b"Read one binary message from stdin through EOF; publish the first peer message\n"
        b"after a normal WebSocket Close exchange and transport cleanup.\n"
        b"Limits: 65536 message bytes, 64 fragments, 256 frames, 5-second network deadline.\n")
ERRORS = {
    2: b"websocket-once: invalid arguments or input\n",
    3: b"websocket-once: transport, trust or protocol failed\n",
    4: b"websocket-once: allocation failed\n",
    5: b"websocket-once: output failed\n",
}


def frame(opcode, payload=b"", *, fin=True, rsv=0, masked=False):
    first = (0x80 if fin else 0) | rsv | opcode
    length = len(payload)
    mask_bit = 0x80 if masked else 0
    if length < 126:
        head = bytes((first, mask_bit | length))
    elif length < 65536:
        head = bytes((first, mask_bit | 126)) + struct.pack("!H", length)
    else:
        head = bytes((first, mask_bit | 127)) + struct.pack("!Q", length)
    if not masked:
        return head + payload
    key = b"test"
    return head + key + bytes(value ^ key[index % 4] for index, value in enumerate(payload))


class Wire:
    def __init__(self, read, write):
        self.read, self.write = read, write
        self.pending = bytearray()
        self.masks = []

    def take(self, count):
        assert 0 <= count <= 131072
        while len(self.pending) < count:
            data = self.read(min(16384, count-len(self.pending)))
            if not data:
                raise EOFError(f"client EOF: need={count} buffered={len(self.pending)}")
            self.pending.extend(data)
        result = bytes(self.pending[:count])
        del self.pending[:count]
        return result

    def request(self, authority=b"Example.test:0080", target=b"/socket?q=%2f"):
        head = bytearray()
        while not head.endswith(b"\r\n\r\n"):
            assert len(head) < 16384
            head.extend(self.take(1))
        parser = h11.Connection(h11.SERVER)
        parser.receive_data(bytes(head))
        request = parser.next_event()
        assert isinstance(request, h11.Request), request
        assert (request.method, request.target, request.http_version) == (b"GET", target, b"1.1")
        fields = list(request.headers)
        def values(name):
            return [value for key, value in fields if key == name]
        assert values(b"host") == [authority], fields
        assert values(b"upgrade") == [b"websocket"], fields
        assert [value.lower() for value in values(b"connection")] == [b"upgrade"], fields
        assert values(b"sec-websocket-version") == [b"13"], fields
        assert not values(b"sec-websocket-protocol") and not values(b"sec-websocket-extensions"), fields
        keys = values(b"sec-websocket-key")
        assert len(keys) == 1 and len(keys[0]) == 24
        nonce = base64.b64decode(keys[0], validate=True)
        assert len(nonce) == 16 and base64.b64encode(nonce) == keys[0]
        assert isinstance(parser.next_event(), h11.EndOfMessage)
        accept = base64.b64encode(hashlib.sha1(keys[0] + GUID).digest())
        return accept, nonce

    def client_frame(self):
        first, second = self.take(2)
        assert first & 0x80 and not first & 0x70, (first, second)
        assert second & 0x80, "client frame must be masked"
        length = second & 127
        if length == 126:
            length = struct.unpack("!H", self.take(2))[0]
            assert length >= 126
        elif length == 127:
            length = struct.unpack("!Q", self.take(8))[0]
            assert length >= 65536
        assert length <= 65536
        mask = self.take(4)
        self.masks.append(mask)
        encoded = self.take(length)
        return first & 15, bytes(value ^ mask[index % 4] for index, value in enumerate(encoded))


def response(accept, extra=b""):
    return (b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
            b"Sec-WebSocket-Accept: " + accept + b"\r\n" + extra + b"\r\n")


class Plain:
    def __init__(self, handler, *, failure=False):
        self.handler, self.failure = handler, failure
        self.listener = socket.socket()
        self.listener.bind(("127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(.1)
        self.stop = threading.Event()
        self.errors, self.records = [], []
        self.thread = threading.Thread(target=self.serve, daemon=True, name="websocket-once-peer")

    @property
    def address(self):
        host, port = self.listener.getsockname()
        return f"{host}:{port}"

    def serve(self):
        connection = None
        try:
            while not self.stop.is_set():
                try:
                    connection, _ = self.listener.accept()
                    break
                except TimeoutError:
                    pass
            if connection is None:
                return
            connection.settimeout(7)
            wire = Wire(connection.recv, connection.sendall)
            self.handler(wire, self)
        except (OSError, EOFError) as error:
            if not self.failure and not self.stop.is_set():
                self.errors.append(error)
        except BaseException as error:
            self.errors.append(error)
        finally:
            if connection is not None:
                connection.close()

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, kind, value, traceback):
        self.stop.set()
        self.thread.join(8)
        self.listener.close()
        assert not self.thread.is_alive(), "plain peer failed to stop"
        if kind is None:
            assert not self.errors, self.errors


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"websocket-once-{mode}-"))
        self.count = 0

    def run(self, name, arguments, *, data=UPLOAD, expected=b"", status=0,
            no_network=False, closed_reader=False, input_directory=False, environment=None):
        prefix = self.directory / name
        command = [self.executable, *map(str, arguments)]
        trace = prefix.with_suffix(".trace")
        if no_network:
            command = ["strace", "-qq", "-f", "-o", str(trace), "-e", "trace=network", *command]
        start = time.monotonic()
        if input_directory:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True,
                                        timeout=12, env=environment, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            read_fd, write_fd = os.pipe()
            os.close(read_fd)
            try:
                result = subprocess.run(command, input=data, stdout=write_fd, stderr=subprocess.PIPE,
                                        timeout=12, env=environment, check=False)
            finally:
                os.close(write_fd)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True,
                                    timeout=12, env=environment, check=False)
        elapsed = time.monotonic()-start
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".receipt").write_text(repr((command, result.returncode, elapsed)) + "\n")
        assert result.returncode == status, (name, result.returncode, result.stdout, result.stderr)
        assert result.stdout == expected, (name, len(result.stdout), len(expected), result.stdout[:200])
        assert result.stderr == (b"" if status == 0 else ERRORS[status]), (name, result.stderr)
        if no_network:
            text = trace.read_text()
            assert not re.search(r"\b(?:socket|socketpair|connect|sendto|sendmsg|recvfrom|recvmsg)\(", text), text
        self.count += 1
        return elapsed


def arguments(peer):
    return [peer.address, "Example.test:0080", "/socket?q=%2f"]


def normal(wire, peer, *, upload=UPLOAD, payload=BINARY, opcode=2,
           fragmented=False, ping=False, after_close_ping=False, extra_message=False, coalesced_close=False):
    accept, nonce = wire.request()
    peer.records.append(nonce)
    initial = b""
    if not fragmented and not ping:
        initial = frame(opcode, payload)
        if extra_message:
            initial += frame(2, b"this second message is not published")
        if coalesced_close:
            initial += frame(8, CLOSE)
    # Upgrade and first frame deliberately share one application write.
    wire.write(response(accept) + initial)
    assert wire.client_frame() == (2, upload)
    if fragmented:
        cut = len(payload)//2
        wire.write(frame(opcode, payload[:cut], fin=False))
        if ping:
            wire.write(frame(9, b"\x00ping\xff"))
            assert wire.client_frame() == (10, b"\x00ping\xff")
        # Split frame headers and payload across tiny transport writes.
        tail = frame(0, payload[cut:])
        for at in range(0, len(tail), 3):
            wire.write(tail[at:at+3])
    elif ping:
        wire.write(frame(9, b"ping"))
        assert wire.client_frame() == (10, b"ping")
        wire.write(frame(opcode, payload))
    assert wire.client_frame() == (8, CLOSE)
    if after_close_ping:
        wire.write(frame(9, b"late"))
        assert wire.client_frame() == (10, b"late")
    if not coalesced_close:
        wire.write(frame(8, CLOSE))
    peer.records.append(tuple(wire.masks))


def plain(r):
    cases = [
        ("coalesced-binary", {}),
        ("empty-data", dict(payload=b"", upload=b"")),
        ("fragmented-text-ping", dict(payload="snowman ☃".encode(), opcode=1, fragmented=True, ping=True)),
        ("ping-after-local-close", dict(after_close_ping=True)),
        ("coalesced-data-close", dict(coalesced_close=True)),
        ("extended-126", dict(payload=b"x"*126)),
        ("maximum-65536", dict(payload=bytes(range(256))*256, upload=bytes(range(256))*256)),
        ("fragmented-binary-ping", dict(fragmented=True, ping=True)),
        ("first-message-only", dict(extra_message=True)),
    ]
    nonces = []
    for name, options in cases:
        def handler(wire, peer, options=options):
            normal(wire, peer, **options)
        with Plain(handler) as peer:
            r.run(name, arguments(peer), data=options.get("upload", UPLOAD), expected=options.get("payload", BINARY))
        assert len(peer.records) == 2, (name, peer.records)
        nonces.append(peer.records[0])
    # Freshness tripwire across independent processes; no deterministic key fixture.
    assert len(set(nonces)) == len(nonces), "reused handshake nonce"


def rejection(r):
    cases = ["bad-accept", "unoffered-protocol", "extension", "truncated-head",
             "masked-server", "rsv", "invalid-utf8", "close-before-data",
             "abnormal-close", "unclean-after-data", "fragmented-eof", "oversized-frame"]
    for name in cases:
        def handler(wire, peer, name=name):
            accept, _ = wire.request()
            if name == "bad-accept":
                wire.write(response(base64.b64encode(b"x"*20)))
                return
            if name == "unoffered-protocol":
                wire.write(response(accept, b"Sec-WebSocket-Protocol: extra\r\n"))
                return
            if name == "extension":
                wire.write(response(accept, b"Sec-WebSocket-Extensions: permessage-deflate\r\n"))
                return
            if name == "truncated-head":
                wire.write(response(accept)[:-3])
                return
            wire.write(response(accept))
            assert wire.client_frame() == (2, UPLOAD)
            if name == "masked-server":
                wire.write(frame(2, BINARY, masked=True))
            elif name == "rsv":
                wire.write(frame(2, BINARY, rsv=0x40))
            elif name == "invalid-utf8":
                wire.write(frame(1, b"\xff"))
            elif name == "close-before-data":
                payload = CLOSE+b"no data"
                wire.write(frame(8, payload))
                assert wire.client_frame() == (8, payload)
            elif name in ("abnormal-close", "unclean-after-data"):
                wire.write(frame(2, BINARY))
                assert wire.client_frame() == (8, CLOSE)
                if name == "abnormal-close":
                    wire.write(frame(8, struct.pack("!H", 1001)))
            elif name == "fragmented-eof":
                wire.write(frame(2, b"unfinished", fin=False))
            elif name == "oversized-frame":
                wire.write(b"\x82\x7f"+struct.pack("!Q", 65537))
        with Plain(handler, failure=True) as peer:
            r.run(name, arguments(peer), status=3)


def cli(r):
    base = ["127.0.0.1:9", "example.test", "/"]
    cases = [
        ("missing-all", []), ("missing-target", base[:2]),
        ("extra-operand", base+["extra"]), ("unknown-option", base+["--wat"]),
        ("ca-without-tls", base+["--ca-file", "unused.pem"]),
        ("duplicate-name", base+["--tls-name", "localhost", "--tls-name", "localhost"]),
        ("duplicate-ca", base+["--tls-name", "localhost", "--ca-file", "a", "--ca-file", "b"]),
        ("hostname-endpoint", ["example.test:80", *base[1:]]),
        ("zero-port", ["127.0.0.1:0", *base[1:]]),
        ("bad-authority", [base[0], "bad\r\nInjected: yes", "/"]),
        ("target-fragment", [*base[:2], "/#fragment"]),
        ("non-origin-target", [*base[:2], "http://example.test/"]),
        ("numeric-tls-name", base+["--tls-name", "127.0.0.1"]),
        ("empty-ca", base+["--tls-name", "localhost", "--ca-file", ""]),
    ]
    for name, values in cases:
        r.run(name, values, data=b"", status=2, no_network=True)
    r.run("input-over-cap", base, data=b"x"*65537, status=2, no_network=True)
    r.run("help", ["--help"], data=b"", expected=HELP, no_network=True)
    r.run("short-help", ["-h"], data=b"", expected=HELP, no_network=True)


def io(r):
    with Plain(lambda wire, peer: normal(wire, peer)) as peer:
        r.run("closed-stdout", arguments(peer), status=5, closed_reader=True)
    assert len(peer.records) == 2
    r.run("stdin-read-error", ["127.0.0.1:9", "example.test", "/"],
          status=2, no_network=True, input_directory=True)
    def stalled(wire, peer):
        accept, _ = wire.request()
        wire.write(response(accept)+frame(2, BINARY))
        assert wire.client_frame() == (2, UPLOAD)
        assert wire.client_frame() == (8, CLOSE)
        peer.stop.wait(7)
    with Plain(stalled, failure=True) as peer:
        elapsed = r.run("deadline-before-close", arguments(peer), status=3)
        assert 4.5 <= elapsed < 10, elapsed


def tls(r):
    directory = r.directory / "certificates"
    CERTS.generate(directory)
    cases = [
        ("tls12-ca", ssl.TLSVersion.TLSv1_2, "localhost", "root", False, 0),
        ("tls13-ca", ssl.TLSVersion.TLSv1_3, "localhost", "root", False, 0),
        ("controlled-default-paths", ssl.TLSVersion.TLSv1_3, "localhost", "root", True, 0),
        ("identity-mismatch", ssl.TLSVersion.TLSv1_3, "wrong.invalid", "root", False, 3),
        ("untrusted-ca", ssl.TLSVersion.TLSv1_3, "localhost", "untrusted", False, 3),
    ]
    for name, version, identity, authority, default, status in cases:
        seen = []
        def handler(connection, server):
            TLS.handshake(connection, server)
            wire = Wire(connection.read, connection.write)
            server.records = []
            normal(wire, server, fragmented=True, ping=True)
            seen.append(True)
            connection.shutdown()
        with TLS.Server(TLS.context(directory, version=version), handler, expect_failure=status != 0) as peer:
            values = arguments(peer)+["--tls-name", identity]
            environment = None
            if default:
                empty = directory / "empty-trust"
                empty.mkdir(exist_ok=True)
                environment = dict(os.environ, SSL_CERT_FILE=str(directory / "root.pem"), SSL_CERT_DIR=str(empty))
            else:
                values += ["--ca-file", directory / f"{authority}.pem"]
            r.run(name, values, status=status, expected=BINARY if status == 0 else b"", environment=environment)
        assert peer.names == [identity], (name, peer.names)
        if status == 0:
            assert seen and peer.authenticated and peer.version == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
        else:
            assert not seen and not peer.authenticated


def controls():
    assert len(HELP) == 306
    assert response(b"A"*28).endswith(b"\r\n\r\n")
    for payload in (b"", b"x", b"x"*125, b"x"*126, bytes(range(256))*256):
        encoded = frame(2, payload, masked=True)
        wire = Wire(BytesIO(encoded).read, lambda data: None)
        assert wire.client_frame() == (2, payload)
    try:
        Wire(BytesIO(frame(2, b"x")).read, lambda data: None).client_frame()
    except AssertionError:
        pass
    else:
        raise AssertionError("unmasked client control failed")
    print("websocket-once CPU controls=8")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"plain": plain, "rejection": rejection, "cli": cli, "io": io, "tls": tls}[mode](runner)
        print(f"websocket-once-{mode} cases={runner.count} evidence={runner.directory}")
