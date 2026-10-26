"""Bounded HTTPS peers, reusing the existing native OpenSSL MemoryBIO driver."""
import dataclasses
import http.client
import importlib.util
import io
from pathlib import Path
import socket
import ssl
import threading

import h11

FIXTURES = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("https_batch_native_peer", FIXTURES / "openssl_tls" / "peer.py")
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)
BINARY = NATIVE.binary(1025) + b"\x00\xff\r\n"


def fixed(body=BINARY, status=200):
    return ("HTTP/1.1 %d Result\r\nContent-Length: %d\r\nX-Binary: " % (status, len(body))).encode() + b"\x80\xff\r\n\r\n" + body


def chunked(body=BINARY):
    pieces = [b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"]
    for at in range(0, len(body), 29):
        part = body[at:at + 29]
        pieces += [("%x;tag=ok\r\n" % len(part)).encode(), part, b"\r\n"]
    return b"".join(pieces) + b"0\r\nX-Trailer: yes\r\n\r\n"


def decoded(wire, method="POST"):
    class Sock:
        def makefile(self, *args):
            return io.BytesIO(wire)
    response = http.client.HTTPResponse(Sock(), method=method)
    response.begin()
    return response.status, response.read()


@dataclasses.dataclass
class Peer:
    wire: bytes = b""
    certificate: str = "valid"
    family: int = 4
    version: object = None
    require_client: bool = False
    fragment: int = 0
    ending: str = "framed"  # framed, clean, abrupt, cut
    stall: str = ""  # handshake or response
    identity: str = "fixture.test"
    body: bytes = b""
    request_bytes: int = 4
    request_mode: int = 0
    method: str = "POST"
    early: bool = False


class Pool:
    """Only causal barriers and peer operations; no production state machine."""
    def __init__(self, directory, peers, concurrency=2, schedule="ordinary", expected_failure=False):
        self.directory = Path(directory)
        self.peers = peers
        self.concurrency = concurrency
        self.schedule = schedule
        self.expected_failure = expected_failure
        self.condition = threading.Condition()
        self.stop = threading.Event()
        self.events = []
        self.accepted, self.requests, self.ended = set(), set(), set()
        self.transports = []
        self.servers = []
        self.request_bodies = {}
        self.client_certificates = {}

    def record(self, event, index):
        with self.condition:
            self.events.append((event, index))
            if event == "accepted":
                self.accepted.add(index)
            elif event == "request":
                self.requests.add(index)
            elif event == "ended":
                self.ended.add(index)
            self.condition.notify_all()

    def wait(self, predicate):
        with self.condition:
            while not predicate() and not self.stop.is_set():
                self.condition.wait(.025)
            return not self.stop.is_set()

    def wave(self, index):
        first = index // self.concurrency * self.concurrency
        return set(range(first, min(first + self.concurrency, len(self.peers))))

    def before_handshake(self, index):
        if self.schedule == "waves":
            return self.wait(lambda: self.wave(index) <= self.accepted)
        if self.schedule == "fair" and index < self.concurrency:
            return self.wait(lambda: set(range(min(self.concurrency, len(self.peers)))) <= self.accepted)
        return True

    def before_response(self, index):
        if self.schedule == "waves":
            members = self.wave(index)
            return self.wait(lambda: members <= self.requests and all(other in self.ended for other in members if other > index))
        if self.schedule == "fair":
            if index == 0:
                return self.wait(lambda: set(range(1, len(self.peers))) <= self.ended)
            return self.wait(lambda: {0, 1} <= self.requests)
        return True

    def request(self, connection, index, early=False):
        parser = h11.Connection(h11.SERVER)
        head, body = None, bytearray()
        while True:
            event = parser.next_event()
            if event is h11.NEED_DATA:
                if early and head is not None:
                    return head, bytes(body)
                data = connection.read(1024)
                if not data:
                    raise EOFError("TLS peer closed before complete request")
                parser.receive_data(data)
            elif isinstance(event, h11.Request):
                head = event
                expected = self.peers[index]
                assert head.method == expected.method.encode() and head.target == ("/j%02d" % index).encode(), head
                fields = list(head.headers)
                assert [v for k, v in fields if k == b"host"] == [b"batch.example"], fields
                assert [v for k, v in fields if k == b"connection"] == [b"close"], fields
                assert [v for k, v in fields if k == b"content-length"] == [str(len(expected.body)).encode()], fields
            elif isinstance(event, h11.Data):
                body.extend(event.data)
                assert len(body) <= len(self.peers[index].body), len(body)
                assert self.peers[index].body[:len(body)] == body
            elif isinstance(event, h11.EndOfMessage):
                assert head is not None and bytes(body) == self.peers[index].body, (head, body)
                return head, bytes(body)

    def handle(self, connection, server, index):
        spec = self.peers[index]
        with self.condition:
            self.transports.append(connection.transport)
        self.record("accepted", index)
        if not self.before_handshake(index):
            return
        if spec.stall == "handshake":
            self.stop.wait(6)
            return
        self.record("handshake-output", index)
        NATIVE.handshake(connection, server)
        self.record("verified", index)
        if spec.require_client:
            certificate = connection.tls.getpeercert()
            assert certificate, "required client certificate missing"
            self.client_certificates[index] = certificate
        _, prefix = self.request(connection, index, early=spec.early)
        self.record("request", index)
        if not self.before_response(index):
            return
        if spec.stall == "response":
            self.stop.wait(6)
            return
        self.record("response", index)
        if spec.early:
            # TLS1.3 peer withholds final body until authenticated local close.
            head, body = spec.wire.split(b"\r\n\r\n", 1)
            connection.write(head + b"\r\n\r\n")
            if server.version == "TLSv1.3":
                uploaded = bytearray(prefix)
                while True:
                    part = connection.read(16384)
                    if not part:
                        break
                    uploaded.extend(part)
                    assert len(uploaded) < len(spec.body), len(uploaded)
                    assert spec.body[:len(uploaded)] == uploaded
                self.request_bodies[index] = bytes(uploaded)
                self.record("client-notify", index)
                connection.write(body)
            else:
                # TLS1.2 has no pre-body half-close promise. Do not require one.
                connection.write(body)
        elif spec.ending == "cut":
            connection.cut_record(spec.wire, 11)
            return
        else:
            # A whole application message in one native TLS record exercises
            # buffered plaintext when the client's io_bytes is much smaller.
            connection.write(spec.wire, chunk=16384)
        if spec.ending == "abrupt":
            connection.abrupt_eof()
            return
        if spec.ending == "clean" or spec.early:
            connection.shutdown()
        else:
            # Framed HTTP must finish without requiring peer EOF. SSL_read can
            # observe the client's notify or raise on its deliberate abort.
            try:
                assert connection.read(1) == b""
            except (ssl.SSLError, OSError, EOFError):
                pass
        self.record("ended", index)

    def __enter__(self):
        for index, spec in enumerate(self.peers):
            context = NATIVE.context(self.directory, spec.certificate, spec.version)
            if spec.require_client:
                context.verify_mode = ssl.CERT_REQUIRED
                context.load_verify_locations(cafile=self.directory / "root.pem")
            handler = lambda connection, server, index=index: self.handle(connection, server, index)
            server = NATIVE.Server(context, handler, fragment=spec.fragment,
                                   expect_failure=self.expected_failure, ipv6=spec.family == 6)
            self.servers.append(server)
            server.__enter__()
        return self

    def __exit__(self, kind, value, traceback):
        self.stop.set()
        with self.condition:
            self.condition.notify_all()
            transports = list(self.transports)
        for server in self.servers:
            server.stop.set()
        for transport in transports:
            try:
                transport.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
        for server in self.servers:
            server.__exit__(kind, value, traceback)
