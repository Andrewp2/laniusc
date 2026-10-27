"""Real HTTPS service oracle: verified Python/OpenSSL clients and stdlib HTTP."""
import http.client
from email.utils import parsedate_to_datetime
import importlib.util
import io
from pathlib import Path
import select
import socket
import ssl
import subprocess
import sys
import tempfile
import time

FIXTURES = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "https_server_certificates", FIXTURES / "openssl_tls_server" / "certificates.py"
)
CERTIFICATES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CERTIFICATES)
sys.path.insert(0, str(FIXTURES / "openssl_tls_server"))
from client import Client, context

MODE, EXE = sys.argv[1:3]
CASES = 0


def payload(count):
    return (bytes(range(256)) * ((count + 255) // 256))[:count]


def request(method="GET", target="/health", body=b"", *, version="1.1", fields=()):
    headers = [("Host", "localhost")] if version == "1.1" else []
    headers += list(fields)
    if not any(name.lower() in ("content-length", "transfer-encoding") for name, _ in headers):
        headers.append(("Content-Length", str(len(body))))
    return (f"{method} {target} HTTP/{version}\r\n" +
            "".join(f"{name}: {value}\r\n" for name, value in headers) + "\r\n").encode() + body


def chunked(body, *, step=17, trailers=b"X-Final: valid\r\n"):
    result = []
    for offset in range(0, len(body), step):
        part = body[offset:offset + step]
        result += [f"{len(part):x};tag=yes\r\n".encode(), part, b"\r\n"]
    return b"".join(result) + b"0\r\n" + trailers + b"\r\n"


class RecordingResponse(http.client.HTTPResponse):
    def __init__(self, *args, **kwargs):
        self.statuses = []
        super().__init__(*args, **kwargs)

    def _read_status(self):
        result = super()._read_status()
        self.statuses.append(result[1])
        return result


class Service:
    def __init__(self, directory, *, options=(), certificate="valid", key=None,
                 ipv6=False, probe=None):
        self.directory = Path(directory)
        self.address = "[::1]:0" if ipv6 else "127.0.0.1:0"
        certificate_path = self.directory / f"{certificate}.pem"
        key_path = self.directory / f"{key or certificate}.key"
        if certificate == "chain-full" and key is None:
            key_path = self.directory / "chain.key"
        arguments = [EXE, self.address, certificate_path, key_path, *options, "--report"]
        if probe is not None:
            arguments = [EXE, certificate_path, key_path, str(probe)]
        self.process = subprocess.Popen(list(map(str, arguments)), stdin=subprocess.DEVNULL,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.start = time.monotonic()
        self.startup = b""

    def __enter__(self):
        ready, _, _ = select.select([self.process.stdout], [], [], 4)
        assert ready, "service did not publish its endpoint"
        self.startup = self.process.stdout.readline(97)
        assert self.startup.endswith(b"\n") and len(self.startup) <= 96, self.failed_start()
        value = self.startup.strip().decode("ascii")
        if value.startswith("["):
            host, port = value[1:].split("]:")
        else:
            host, port = value.split(":")
        self.endpoint = (host, int(port))
        assert self.endpoint[1] != 0
        return self

    def failed_start(self):
        self.process.kill()
        return self.startup, self.process.communicate(timeout=2)

    def finish(self, expected=0, *, diagnostic=None, reports=1, codes=None):
        global CASES
        output, errors = self.process.communicate(timeout=8)
        CASES += 1
        assert self.process.returncode == expected, (expected, self.process.returncode, output, errors)
        assert not output, output
        lines = errors.splitlines()
        records = [dict(item.split("=") for item in line.decode().split())
                   for line in lines if line.startswith(b"received=")]
        assert len(records) == reports, (reports, errors)
        diagnostics = [line for line in lines if not line.startswith(b"received=")]
        if expected == 0:
            assert not diagnostics, errors
        else:
            assert len(diagnostics) == 1 and diagnostics[0].startswith(b"https-serve: "), errors
            if diagnostic:
                assert diagnostic in diagnostics[0], (diagnostic, errors)
        expected_codes = [expected] * reports if codes is None else list(codes)
        assert len(expected_codes) == reports
        required = {"received", "sent", "response", "interim", "drain", "tail", "io",
                    "cleanup", "cleanup-errors", "work", "scan", "id", "rejected",
                    "shutdown", "eof", "closed", "code", "tls", "failed"}
        for index, (record, code) in enumerate(zip(records, expected_codes)):
            assert set(record) == required, record
            for name in record:
                record[name] = int(record[name])
                assert record[name] >= 0, record
            assert record["id"] == index, records
            assert record["code"] == code and record["failed"] == int(code != 0), record
            assert record["sent"] <= record["response"] and record["interim"] in (0, 25), record
            assert record["closed"] == record["cleanup"] == 1, record
            assert record["cleanup-errors"] == 0, record
            if code == 0:
                assert record["sent"] == record["response"], record
                assert record["shutdown"] == record["eof"] == 1, record
                assert record["rejected"] == 0, record
                assert record["io"] > 0 and record["work"] > 0 and record["tls"] > 0, record
        return records

    def __exit__(self, *_):
        if self.process.poll() is None:
            self.process.kill()
            self.process.communicate(timeout=2)


def connect(service, *, identity="localhost", trust="root", version=None):
    raw = socket.create_connection(service.endpoint, timeout=3)
    try:
        return context(service.directory, identity, trust, version).wrap_socket(
            raw, server_hostname=identity, suppress_ragged_eofs=False
        )
    except BaseException:
        raw.close()
        raise


def response(connection, *, method="GET", status=200, body=b"ok\n", statuses=None, allow=None, http_version=11):
    result = RecordingResponse(connection, method=method)
    result.begin()
    assert result.status == status, (result.status, result.getheaders())
    assert result.version == http_version
    dates = result.headers.get_all("Date")
    assert len(dates or []) == 1 and len(dates[0]) == 29 and dates[0].endswith(" GMT"), dates
    assert parsedate_to_datetime(dates[0]).utcoffset().total_seconds() == 0, dates
    assert result.headers.get_all("Connection") == ["close"]
    assert result.headers.get_all("Transfer-Encoding") is None
    if method != "HEAD":
        assert result.headers.get_all("Content-Length") == [str(len(body))]
    if allow is not None:
        assert result.headers.get_all("Allow") == [allow]
    assert result.read() == body
    if statuses is not None:
        assert result.statuses == statuses, result.statuses
    # suppress_ragged_eofs=False makes this specifically an authenticated
    # close_notify, rather than a tolerated abrupt transport EOF.
    assert connection.recv(1) == b""
    result.close()
    # Complete both authenticated directions, then require real transport EOF.
    # A raw TCP close cannot stand in for the peer's native close_notify.
    transport = connection.unwrap()
    try:
        assert transport.recv(1) == b""
    finally:
        transport.close()


def case(directory, wire=None, *, options=(), method="GET", expected_body=b"ok\n",
         status=200, allow=None, identity="localhost", trust="root", version=None,
         certificate="valid", ipv6=False, fragment=0, statuses=(200,), http_version=11):
    with Service(directory, options=options, certificate=certificate, ipv6=ipv6) as service:
        with connect(service, identity=identity, trust=trust, version=version) as connection:
            data = request() if wire is None else wire
            if fragment:
                for start in range(0, len(data), fragment):
                    connection.sendall(data[start:start + fragment])
            else:
                connection.sendall(data)
            response(connection, method=method, body=expected_body, status=status,
                     allow=allow, statuses=list(statuses), http_version=http_version)
        records = service.finish()
        assert records[0]["received"] == len(data), records
        return records[0]



def retained_tail(directory):
    first, following = request(), request(target="/must-not-be-processed")
    with Service(directory) as service:
        with connect(service) as connection:
            connection.sendall(first + following)
            wire = bytearray()
            while True:
                block = connection.recv(4096)
                if not block:
                    break  # suppress_ragged_eofs=False requires native notification.
                wire.extend(block)
                assert len(wire) <= 16384, wire
            transport = connection.unwrap()
            try:
                assert transport.recv(1) == b""
            finally:
                transport.close()
        # Parse frozen bytes so an HTTP reader cannot prefetch and discard a
        # forbidden second response before the socket-EOF assertion sees it.
        class Retained(io.BytesIO):
            def close(self):
                pass  # inspected below, then explicitly released by the base class
        source = Retained(bytes(wire))
        class FrozenSocket:
            def makefile(self, _mode):
                return source
        message = RecordingResponse(FrozenSocket())
        message.begin()
        assert message.statuses == [200] and message.version == 11, wire
        assert message.headers.get_all("Connection") == ["close"]
        assert message.headers.get_all("Content-Length") == ["3"]
        assert message.read() == b"ok\n" and source.tell() == len(wire), wire
        message.close()
        io.BytesIO.close(source)
        record = service.finish()[0]
        assert record["received"] == len(first) + len(following), record
        assert record["tail"] + record["drain"] == len(following), record


def no_response(connection):
    observed = bytearray()
    try:
        while True:
            block = connection.recv(4096)
            if not block:
                break
            observed.extend(block)
            assert len(observed) < 16384
    except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
        pass
    assert not observed, observed


def bad_http(directory, wire, *, options=(), expected=3, diagnostic=b"HTTP request"):
    with Service(directory, options=options) as service:
        with connect(service) as connection:
            try:
                connection.sendall(wire)
            except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
                pass
            no_response(connection)
        return service.finish(expected, diagnostic=diagnostic)



def allowance_rejection(directory, options, counter, allowance, *, construction=False):
    # These are specifically finite-allowance controls, not a fallback for
    # malformed requests or trust failures. Every attempted peer is accepted.
    with Service(directory, options=options) as service:
        connection = None
        try:
            connection = connect(service)
        except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
            pass  # the selected cap can end the owner before handshake completes
        else:
            try:
                connection.sendall(request())
            except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
                pass
            no_response(connection)
        finally:
            if connection is not None:
                connection.close()
        record = service.finish(2, diagnostic=b"limit", reports=1)[0]
        assert record[counter] == allowance, record
        assert record["sent"] == record["response"] == record["received"] == 0, record
        if construction:
            # HTTP-work reservation fails before attaching or driving TLS.
            assert record["tls"] == record["io"] == record["work"] == 0, record


def matrix(directory):
    case(directory)
    case(directory, request("HEAD"), method="HEAD", expected_body=b"")
    case(directory, request(target="/health?format=raw"))
    for body in (b"", b"a\0b\xff\n", payload(1025), payload(65537), payload(262145)):
        case(directory, request("POST", "/echo", body), method="POST", expected_body=body)
    body = payload(1031)
    wire = request("POST", "/echo", chunked(body), fields=(("Transfer-Encoding", "chunked"),))
    case(directory, wire, method="POST", expected_body=body, fragment=13)
    case(directory, request("POST", "/echo", chunked(b""), fields=(("Transfer-Encoding", "chunked"),)), method="POST", expected_body=b"")
    case(directory, request(version="1.0"), http_version=10)
    case(directory, request("POST", "/echo", b"old", version="1.0", fields=(("Expect", "unsupported"),)), method="POST", status=417, expected_body=b"", statuses=(417,), http_version=10)
    case(directory, request("POST", "/echo", b"recognized\0expect", version="1.0", fields=(("Expect", "100-continue"),)), method="POST", expected_body=b"recognized\0expect", statuses=(200,), http_version=10)
    case(directory, request(target="/missing"), status=404, expected_body=b"", statuses=(404,))
    case(directory, request("POST", "/health", b"ignored"), method="POST", status=405, expected_body=b"", allow="GET, HEAD", statuses=(405,))
    case(directory, request(target="/echo"), status=405, expected_body=b"", allow="POST", statuses=(405,))
    case(directory, request(target="https://localhost/health"), status=421, expected_body=b"", statuses=(421,))
    for expectation in ("100-continue", "100-CoNtInUe"):
        body = b"after\0continue"
        wire = request("POST", "/echo", body, fields=(("Expect", expectation),))
        head = wire[:-len(body)]
        with Service(directory) as service:
            with connect(service) as connection:
                connection.sendall(head)
                interim = bytearray()
                while not interim.endswith(b"\r\n\r\n"):
                    interim.extend(connection.recv(1))
                    assert len(interim) <= 1024
                assert bytes(interim) == b"HTTP/1.1 100 Continue\r\n\r\n", interim
                connection.sendall(body)
                response(connection, method="POST", body=body, statuses=[200])
            service.finish()
    body = b"already\0buffered"
    case(directory, request("POST", "/echo", body, fields=(("Expect", "100-continue"),)), method="POST", expected_body=body, statuses=(100, 200))
    # Retained following bytes are bounded discard, never a second response.
    retained_tail(directory)
    for fields in ((("Expect", "unsupported"),), (("Expect", "100-continue"), ("Expect", "100-continue"))):
        wire = request("POST", "/echo", b"", fields=(*fields, ("Content-Length", "99")))
        case(directory, wire, method="POST", status=417, expected_body=b"", statuses=(417,))
    case(directory, identity="fixture.test")
    case(directory, identity="127.0.0.1")
    case(directory, certificate="chain-full")
    case(directory, version=ssl.TLSVersion.TLSv1_2)
    case(directory, version=ssl.TLSVersion.TLSv1_3)
    case(directory, ipv6=True, identity="::1")
    with Service(directory, options=("--requests", "3")) as service:
        for index in range(3):
            body = payload(17 + index)
            with connect(service) as connection:
                connection.sendall(request("POST", "/echo", body))
                response(connection, method="POST", body=body)
        service.finish(reports=3)


def failures(directory):
    global CASES
    for certificate, key in (("missing", "valid"), ("valid", "missing"),
                             ("malformed", "valid"), ("valid", "malformed"),
                             ("valid", "chain"), ("valid", "encrypted")):
        result = subprocess.run([EXE, "127.0.0.1:0", str(directory / f"{certificate}.pem"),
                                 str(directory / f"{key}.key")], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        CASES += 1
        assert result.returncode == 3 and not result.stdout, result
        assert result.stderr == b"https-serve: TLS operation failed\n", result
    for options in ({"identity": "wrong.invalid"}, {"identity": "127.0.0.2"},
                    {"trust": "untrusted"}, {"certificate": "expired"},
                    {"certificate": "chain"}, {"certificate": "wrong-purpose"}):
        certificate = options.pop("certificate", "valid")
        with Service(directory, certificate=certificate) as service:
            try:
                connection = connect(service, **options)
            except ssl.SSLCertVerificationError:
                pass
            else:
                connection.close()
                raise AssertionError("verification unexpectedly succeeded")
            service.finish(3, diagnostic=b"TLS", reports=1)
    invalid = [
        b"GET /health HTTP/1.1\r\n\r\n",
        b"GET /health HTTP/1.1\r\nHost: localhost\r\nHost: duplicate\r\n\r\n",
        request("POST", "/echo", fields=(("Content-Length", "0"), ("Transfer-Encoding", "chunked"))),
        request("POST", "/echo", fields=(("Content-Length", "0"), ("Content-Length", "0"))),
        request("POST", "/echo", b"Z\r\n", fields=(("Transfer-Encoding", "chunked"),)),
        request("POST", "/echo", b"0\r\nContent-Length: 0\r\n\r\n", fields=(("Transfer-Encoding", "chunked"),)),
        request(target="/bad%2Z"),
        b"GET /health HTTP/1.1\r\nHost: localhost\r\n folded: bad\r\n\r\n",
    ]
    for wire in invalid:
        bad_http(directory, wire)
    # A clean TLS EOF still does not complete an unfinished fixed HTTP body.
    with Service(directory) as service:
        raw = socket.create_connection(service.endpoint, timeout=3)
        try:
            client = Client(raw, context(directory), "localhost")
            client.handshake()
            client.write(request("POST", "/echo", b"short", fields=(("Content-Length", "99"),)))
            try:
                client.shutdown()
            except (ssl.SSLError, EOFError, ConnectionResetError):
                pass
        finally:
            raw.close()
        service.finish(3, diagnostic=b"HTTP request")
    for cut in (False, True):
        with Service(directory) as service:
            raw = socket.create_connection(service.endpoint, timeout=3)
            try:
                client = Client(raw, context(directory), "localhost")
                client.handshake()
                if cut:
                    client.cut_record(request(), 7)
                else:
                    client.write(b"GET /health HTTP/1.1\r\n")
                    client.abrupt_eof()
                service.finish(3, diagnostic=b"truncated TLS")
            finally:
                raw.close()


def limits(directory):
    global CASES
    for wire, option, exact in (
        (request(), "--max-request", len(request())),
        (request(), "--max-head", len(request())),
        (request(), "--max-headers", 2),
        (request("POST", "/echo", b"12345"), "--max-body", 5),
        (request("POST", "/echo", chunked(b"1234", step=2), fields=(("Transfer-Encoding", "chunked"),)), "--max-chunks", 2),
    ):
        method = "POST" if wire.startswith(b"POST") else "GET"
        body = b"12345" if option == "--max-body" else b"1234" if option == "--max-chunks" else b"ok\n"
        case(directory, wire, options=(option, str(exact)), method=method, expected_body=body)
        bad_http(directory, wire, options=(option, str(exact - 1)), expected=2, diagnostic=b"limit")
    baseline = case(directory)
    for option, exact in (("--max-response", baseline["response"]), ("--max-work", baseline["work"])):
        case(directory, options=(option, str(exact)))
        bad_http(directory, request(), options=(option, str(exact - 1)), expected=2, diagnostic=b"limit")
    for option in ("--max-request", "--max-body", "--max-response", "--max-work", "--max-head", "--max-headers", "--max-chunks"):
        wire = request("POST", "/echo", b"x") if option == "--max-body" else request("POST", "/echo", chunked(b"x"), fields=(("Transfer-Encoding", "chunked"),)) if option == "--max-chunks" else request()
        if option == "--max-work":
            allowance_rejection(directory, (option, "0"), "work", 0, construction=True)
        else:
            bad_http(directory, wire, options=(option, "0"), expected=2, diagnostic=b"limit")
    # Listener waiting has a fixed service deadline. Accepted owners have
    # their own accepted-at deadline, capped by that same service deadline.
    for phase in ("accept", "handshake", "request"):
        options = ("--timeout", "1000", "--service-timeout", "150") if phase == "accept" else ("--timeout", "150", "--service-timeout", "1000")
        with Service(directory, options=options) as service:
            raw = None
            if phase == "handshake":
                raw = socket.create_connection(service.endpoint, timeout=2)
            elif phase == "request":
                raw = connect(service)
                raw.sendall(b"GET /health HTTP/1.1\r\n")
            try:
                service.finish(3, diagnostic=b"timeout", reports=int(phase != "accept"))
                assert time.monotonic() - service.start < 2
            finally:
                if raw is not None:
                    raw.close()
    # Configuration/expired-service rejection precedes any kernel acceptance.
    for options, status in ((("--timeout", "0"), 3), (("--max-io", "0"), 2), (("--max-tls", "0"), 2)):
        with Service(directory, options=options) as service:
            service.finish(status, reports=0)
    # I/O is a per-accepted-owner bound, so an idle-listener wait cannot spend
    # it. Bind each tiny cap to a real accepted connection and exact counter.
    for flag, allowance, counter in (("--max-io", 1, "io"), ("--max-io", 4, "io"), ("--max-tls", 1, "tls")):
        allowance_rejection(directory, (flag, str(allowance)), counter, allowance)
    invalid = [("--requests", "0"), ("--requests", "65"), ("--concurrency", "0"), ("--concurrency", "17"),
               ("--service-timeout", "-1"), ("--service-timeout", "3840001"), ("--timeout", "60001"),
               ("--max-body", "16777217"), ("--max-head", "65537"), ("--max-headers", "1025"),
               ("--max-chunks", "65537"), ("--max-io", "-1"), ("--max-work", "2147483648"),
               ("--unknown",), ("--max-tls",), ("--max-io", "+1")]
    for options in invalid:
        result = subprocess.run([EXE, "127.0.0.1:0", str(directory / "valid.pem"),
                                 str(directory / "valid.key"), *options], stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
        CASES += 1
        assert result.returncode == 2 and not result.stdout, result
        assert result.stderr == b"https-serve: invalid arguments\n", result
    result = subprocess.run([EXE, "--help"], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
    CASES += 1
    assert result.returncode == 0 and not result.stderr and result.stdout.startswith(b"Usage: https-serve "), result
    # Startup output uses bounded short-write/error handling and does not
    # leave the listening owner behind when a caller supplies a bad sink.
    with open("/dev/full", "wb") as full:
        result = subprocess.run([EXE, "127.0.0.1:0", str(directory / "valid.pem"),
                                 str(directory / "valid.key")], stdin=subprocess.DEVNULL,
                                stdout=full, stderr=subprocess.PIPE, timeout=3)
        CASES += 1
        assert result.returncode == 5 and b"output I/O" in result.stderr, result


def stream(directory):
    global CASES
    for mode in (4, 5, 6, 7):
        result = subprocess.run([EXE, str(directory / "valid.pem"), str(directory / "valid.key"), str(mode)],
                                stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4)
        CASES += 1
        assert result.returncode == 0 and not result.stdout and not result.stderr, (mode, result)
    for mode in (1, 2, 3):
        with Service(directory, probe=mode) as service:
            raw = socket.create_connection(service.endpoint, timeout=3)
            try:
                assert raw.recv(1) == b""
            finally:
                raw.close()
            output, errors = service.process.communicate(timeout=4)
            CASES += 1
            assert service.process.returncode == 0 and not output and not errors, (mode, output, errors)
    with Service(directory, probe=0) as service:
        with connect(service) as connection:
            data = bytearray()
            while len(data) < 7:
                data.extend(connection.recv(7 - len(data)))
            assert bytes(data) == b"ab\0\xff\n\0x", data
            connection.sendall(b"ACK")
            assert connection.recv(1) == b""
        output, errors = service.process.communicate(timeout=4)
        CASES += 1
        assert service.process.returncode == 0 and not output and not errors, (output, errors)
    with Service(directory, probe=8) as service:
        raw = socket.create_connection(service.endpoint, timeout=3)
        raw.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
        connection = context(directory).wrap_socket(raw, server_hostname="localhost", suppress_ragged_eofs=False)
        try:
            output, errors = service.process.communicate(timeout=4)
            CASES += 1
            assert service.process.returncode == 0 and not output and not errors, (output, errors)
        finally:
            connection.close()


with tempfile.TemporaryDirectory(prefix="lanius_https_service_") as temporary:
    directory = Path(temporary)
    CERTIFICATES.generate(directory)
    (directory / "malformed.key").write_bytes(b"not a private key\n")
    {"matrix": matrix, "failures": failures, "limits": limits, "stream": stream}[MODE](directory)
print(f"https-serve-{MODE} cases={CASES}")
