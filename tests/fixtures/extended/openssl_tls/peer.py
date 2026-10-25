"""Bounded loopback TLS peer using Python's native OpenSSL MemoryBIO.

Only transport fragmentation/truncation is controlled here. OpenSSL creates,
authenticates and encrypts every TLS record. This module also serves the HTTPS
application's independent HTTP oracle.
"""

from pathlib import Path
import socket
import ssl
import threading
import time
import warnings


MAX_PLAINTEXT = 16 * 1024 * 1024


def context(directory, certificate="valid", version=None, no_certificate=False):
    directory = Path(directory)
    result = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    result.minimum_version = ssl.TLSVersion.TLSv1_2
    result.num_tickets = 0
    if no_certificate:
        result.maximum_version = ssl.TLSVersion.TLSv1_2
        result.set_ciphers("aNULL:@SECLEVEL=0")
    else:
        key_name = "chain" if certificate == "chain-full" else certificate
        result.load_cert_chain(directory / f"{certificate}.pem", directory / f"{key_name}.key")
    if version is not None:
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", DeprecationWarning)
            result.minimum_version = version
            result.maximum_version = version
        if version < ssl.TLSVersion.TLSv1_2:
            result.set_ciphers("ALL:@SECLEVEL=0")
    return result


class Connection:
    """Single server connection with a whole-operation deadline and step cap."""

    def __init__(self, transport, tls_context, fragment=0, seconds=5):
        self.transport = transport
        self.incoming = ssl.MemoryBIO()
        self.outgoing = ssl.MemoryBIO()
        self.tls = tls_context.wrap_bio(self.incoming, self.outgoing, server_side=True)
        self.fragment = fragment
        self.deadline = time.monotonic() + seconds
        self.steps = 0

    def _tick(self):
        self.steps += 1
        remaining = self.deadline - time.monotonic()
        if remaining <= 0 or self.steps > 200_000:
            raise TimeoutError("TLS fixture operation bound exceeded")
        self.transport.settimeout(remaining)

    def send_wire(self, wire):
        size = self.fragment or len(wire) or 1
        for at in range(0, len(wire), size):
            self._tick()
            self.transport.sendall(wire[at:at + size])

    def flush(self):
        while self.outgoing.pending:
            self.send_wire(self.outgoing.read())

    def receive(self):
        self._tick()
        data = self.transport.recv(16384)
        if data:
            self.incoming.write(data)
        else:
            self.incoming.write_eof()

    def operation(self, action):
        while True:
            self._tick()
            try:
                result = action()
                self.flush()
                return result
            except ssl.SSLWantReadError:
                self.flush()
                self.receive()
            except ssl.SSLWantWriteError:
                self.flush()
            except ssl.SSLError:
                # OpenSSL queues fatal protocol alerts in the output BIO too.
                # Deliver that native alert before closing the transport.
                self.flush()
                raise

    def handshake(self):
        self.operation(self.tls.do_handshake)

    def read(self, count=16384):
        assert 0 < count <= MAX_PLAINTEXT
        return self.operation(lambda: self.tls.read(count))

    def read_exact(self, count):
        assert 0 <= count <= MAX_PLAINTEXT
        result = bytearray()
        while len(result) < count:
            data = self.read(min(count - len(result), 16384))
            if not data:
                raise EOFError(f"TLS peer closed after {len(result)} of {count} bytes")
            result.extend(data)
        return bytes(result)

    def write(self, data, chunk=16384):
        assert len(data) <= MAX_PLAINTEXT and 0 < chunk <= 16384
        for at in range(0, len(data), chunk):
            block = data[at:at + chunk]
            written = self.operation(lambda: self.tls.write(block))
            assert written == len(block), (written, len(block))

    def cut_record(self, data, retained):
        """Send a strict prefix of a newly generated encrypted application record."""
        assert data and len(data) <= 16384 and not self.outgoing.pending
        assert self.tls.write(data) == len(data)
        wire = self.outgoing.read()
        assert 0 < retained < len(wire), (retained, len(wire))
        self.send_wire(wire[:retained])
        self.transport.shutdown(socket.SHUT_WR)

    def abrupt_eof(self):
        assert not self.outgoing.pending
        self.transport.shutdown(socket.SHUT_WR)

    def shutdown(self):
        self.operation(self.tls.unwrap)


class Server:
    """An ephemeral loopback listener whose test handler runs in one thread."""

    def __init__(self, tls_context, handler, *, fragment=0, expect_failure=False,
                 receive_buffer=None, ipv6=False):
        self.context = tls_context
        self.handler = handler
        self.fragment = fragment
        self.expect_failure = expect_failure
        self.receive_buffer = receive_buffer
        self.listener = socket.socket(socket.AF_INET6 if ipv6 else socket.AF_INET, socket.SOCK_STREAM)
        self.listener.bind(("::1" if ipv6 else "127.0.0.1", 0))
        self.listener.listen(1)
        self.listener.settimeout(0.1)
        self.stop = threading.Event()
        self.release = threading.Event()
        self.response_release = threading.Event()
        self.errors = []
        self.names = []
        self.connected = False
        self.authenticated = False
        self.version = None
        self.context.set_servername_callback(lambda _ssl, name, _context: self.names.append(name))
        self.thread = threading.Thread(target=self._serve, name="openssl-tls-test-peer", daemon=True)

    @property
    def address(self):
        host, port, *_ = self.listener.getsockname()
        return f"[{host}]:{port}" if ":" in host else f"{host}:{port}"

    def _serve(self):
        transport = None
        try:
            while not self.stop.is_set():
                try:
                    transport, _ = self.listener.accept()
                    break
                except TimeoutError:
                    pass
            if transport is None:
                return
            self.connected = True
            if self.receive_buffer is not None:
                transport.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, self.receive_buffer)
            connection = Connection(transport, self.context, self.fragment)
            self.handler(connection, self)
        except (ssl.SSLError, OSError, EOFError) as error:
            if not self.expect_failure and not self.stop.is_set():
                self.errors.append(error)
        except BaseException as error:
            self.errors.append(error)
        finally:
            if transport is not None:
                transport.close()

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, kind, value, traceback):
        self.stop.set()
        self.release.set()
        self.response_release.set()
        self.thread.join(6)
        self.listener.close()
        assert not self.thread.is_alive(), "loopback TLS peer did not stop"
        if kind is None:
            assert not self.errors, self.errors


def handshake(connection, server):
    connection.handshake()
    server.authenticated = True
    server.version = connection.tls.version()


def binary(count):
    assert 0 <= count <= MAX_PLAINTEXT
    return bytes(((index * 73 + 11) ^ (index // 251)) & 255 for index in range(count))


def self_check(directory):
    """CPU-only checks establish peer behavior before any Lanius claim."""
    payload = binary(1025)

    def client(server, identity="localhost", trust="root", close=True):
        configuration = ssl.create_default_context(cafile=Path(directory) / f"{trust}.pem")
        configuration.minimum_version = ssl.TLSVersion.TLSv1_2
        raw = socket.create_connection(server.listener.getsockname()[:2], timeout=3)
        return configuration.wrap_socket(raw, server_hostname=identity, suppress_ragged_eofs=False)

    for mode in ("clean", "abrupt", "truncated"):
        def handler(connection, server, mode=mode):
            handshake(connection, server)
            assert connection.read_exact(len(payload)) == payload
            if mode == "truncated":
                connection.cut_record(payload, 7)
            else:
                connection.write(payload)
                if mode == "clean":
                    connection.shutdown()
                else:
                    connection.abrupt_eof()

        with Server(context(directory), handler, fragment=7) as server:
            connection = client(server)
            connection.sendall(payload)
            received = bytearray()
            try:
                while data := connection.recv(4096):
                    received.extend(data)
                assert mode == "clean", mode
                connection.unwrap().close()
            except ssl.SSLEOFError:
                assert mode != "clean", mode
            finally:
                connection.close()
            assert bytes(received) == (b"" if mode == "truncated" else payload), mode
        assert server.names == ["localhost"]
    print("openssl-tls peer: binary clean-close, abrupt EOF and cut native TLS record passed")

    # Prove the legacy-version negative fixture can actually negotiate TLS1.1
    # when its client allows that version; a modern-client rejection alone
    # would not establish the production wrapper's TLS1.2 floor.
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        legacy = ssl.create_default_context(cafile=Path(directory) / "root.pem")
        legacy.minimum_version = ssl.TLSVersion.TLSv1_1
        legacy.maximum_version = ssl.TLSVersion.TLSv1_1
        legacy.set_ciphers("ALL:@SECLEVEL=0")

        def legacy_handler(connection, server):
            handshake(connection, server)
            assert connection.read_exact(1) == b"L"
            connection.write(b"1")
            connection.shutdown()

        with Server(context(directory, version=ssl.TLSVersion.TLSv1_1), legacy_handler) as server:
            raw = socket.create_connection(server.listener.getsockname()[:2], timeout=3)
            connection = legacy.wrap_socket(raw, server_hostname="localhost", suppress_ragged_eofs=False)
            assert connection.version() == "TLSv1.1"
            connection.sendall(b"L")
            assert connection.recv(1) == b"1" and connection.recv(1) == b""
            connection.unwrap().close()
        assert server.version == "TLSv1.1" and server.names == ["localhost"]
    print("openssl-tls peer: TLS1.1 fixture negotiates with explicit native security-level-0 client")


if __name__ == "__main__":
    import sys
    self_check(sys.argv[1])
