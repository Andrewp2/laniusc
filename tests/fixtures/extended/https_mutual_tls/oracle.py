"""Actual HTTPS apps with native OpenSSL peers and runtime-only mTLS credentials."""
import http.client
import importlib.util
import io
from pathlib import Path
import select
import socket
import ssl
import subprocess
import sys

sys.dont_write_bytecode = True
FIXTURES = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("https_mutual_certificates", FIXTURES / "openssl_mutual_tls" / "certificates.py")
CERTIFICATES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CERTIFICATES)
sys.path.insert(0, str(FIXTURES / "openssl_tls"))
from peer import Server, context as native_server_context
import tempfile

MODE, FETCH, SERVE, PREPARED = sys.argv[1:5]
CASES = 0
PAYLOAD = bytes(range(256)) * 65 + b"\0\xff\n"
VERSIONS = (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3)


def key_name(certificate):
    return {"client-chain-full": "client-chain", "chain-full": "chain"}.get(certificate, certificate)


def client_context(directory, certificate="client", *, identity="localhost", version=None):
    result = ssl.create_default_context(cafile=directory / "root.pem")
    result.minimum_version = ssl.TLSVersion.TLSv1_2
    if version is not None:
        result.minimum_version = result.maximum_version = version
    if certificate is not None:
        result.load_cert_chain(directory / f"{certificate}.pem", directory / f"{key_name(certificate)}.key")
    assert result.check_hostname and result.verify_mode == ssl.CERT_REQUIRED
    return result


def server_context(directory, *, required=True, certificate="valid", version=None):
    result = native_server_context(directory, certificate=certificate, version=version)
    if required:
        result.verify_mode = ssl.CERT_REQUIRED
        result.load_verify_locations(cafile=directory / "root.pem")
    return result


def inspect_fetch(result, expected, body=None):
    assert result.returncode == expected, (expected, result)
    if expected:
        assert not result.stdout and result.stderr.startswith(b"https-fetch: "), result
        assert result.stderr.endswith(b"\n") and b"\0" not in result.stderr, result
        assert b"Enter PEM" not in result.stderr and b"pass phrase" not in result.stderr, result
    else:
        assert result.stdout == body and not result.stderr, (body, result)


def run_fetch(directory, endpoint, *, certificate="client", key=None, peer="localhost",
              trust="root", options=(), expected=0, body=b"ok\n"):
    global CASES
    arguments = [FETCH, endpoint, peer, directory / f"{trust}.pem", "/health"]
    if certificate is not None:
        arguments += ["--client-cert", directory / f"{certificate}.pem", "--client-key", directory / f"{key or key_name(certificate)}.key"]
    result = subprocess.run(list(map(str, [*arguments, *options])), stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8)
    CASES += 1
    inspect_fetch(result, expected, body)
    return result


def read_request(connection, server):
    data = bytearray()
    while b"\r\n\r\n" not in data:
        part = connection.read(1024)
        assert part and len(data) + len(part) <= 16384
        data.extend(part)
    head, body = bytes(data).split(b"\r\n\r\n", 1)
    line, fields = head.split(b"\r\n", 1)
    assert line == b"GET /health HTTP/1.1" and not body, data
    parsed = http.client.parse_headers(io.BytesIO(fields + b"\r\n\r\n"))
    assert parsed.get_all("Connection") == ["close"]
    assert len(parsed.get_all("Host")) == 1
    server.http_requests.append(bytes(data))


def fetch_case(directory, *, certificate="client", server_certificate="valid", required=True,
               version=None, peer="localhost", trust="root", options=(), expected=0,
               body=PAYLOAD, ipv6=False):
    observed = []
    def handler(connection, server):
        connection.handshake()
        server.authenticated = True
        peer_certificate = connection.tls.getpeercert()
        if required:
            assert peer_certificate
            observed.append(dict(item for rdn in peer_certificate["subject"] for item in rdn)["commonName"])
        read_request(connection, server)
        connection.write(f"HTTP/1.1 200 OK\r\nContent-Length: {len(body)}\r\n\r\n".encode() + body)
        connection.shutdown()
    with Server(server_context(directory, required=required, certificate=server_certificate, version=version), handler,
                expect_failure=expected != 0, ipv6=ipv6) as server:
        server.http_requests = []
        result = run_fetch(directory, server.address, certificate=certificate, peer=peer, trust=trust,
                           options=options, expected=expected, body=body)
    if expected == 0:
        assert len(server.http_requests) == 1
        if required:
            assert observed == [key_name(certificate)], observed
        assert server.names == [None if peer in ("127.0.0.1", "::1") else peer], server.names
    elif expected == 3:
        assert not server.http_requests
    return result


class Service:
    def __init__(self, directory, *, required=True, client_trust="root", options=(), ipv6=False):
        self.directory = directory
        arguments = [SERVE, "[::1]:0" if ipv6 else "127.0.0.1:0", directory / "valid.pem", directory / "valid.key", "--report", *options]
        if required:
            arguments += ["--require-client-ca", directory / f"{client_trust}.pem"]
        self.process = subprocess.Popen(list(map(str, arguments)), stdin=subprocess.DEVNULL,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def __enter__(self):
        ready, _, _ = select.select([self.process.stdout], [], [], 4)
        assert ready, "HTTPS service did not publish a bound endpoint"
        line = self.process.stdout.readline(97)
        assert line.endswith(b"\n") and len(line) <= 96, (line, self.process.communicate(timeout=2))
        value = line.strip().decode()
        if value.startswith("["):
            host, port = value[1:].split("]:")
        else:
            host, port = value.split(":")
        self.endpoint = (host, int(port))
        self.address = value
        return self

    def finish(self, expected=0, *, reports=1):
        global CASES
        output, errors = self.process.communicate(timeout=8)
        CASES += 1
        assert self.process.returncode == expected and not output, (expected, self.process.returncode, output, errors)
        lines = errors.splitlines()
        records = [line for line in lines if line.startswith(b"received=")]
        diagnostics = [line for line in lines if not line.startswith(b"received=")]
        assert len(records) == reports, errors
        if expected:
            assert len(diagnostics) == 1 and diagnostics[0].startswith(b"https-serve: "), errors
        else:
            assert not diagnostics, errors
        for line in records:
            values = {name: int(value) for name, value in (item.split("=") for item in line.decode().split())}
            assert values["sent"] <= values["accepted"] <= values["response"], values
            assert values["failed"] == int(expected != 0), values
        return errors

    def __exit__(self, *_):
        if self.process.poll() is None:
            self.process.kill()
            self.process.communicate(timeout=2)


def connect(service, certificate="client", *, identity="localhost", version=None):
    raw = socket.create_connection(service.endpoint, timeout=3)
    try:
        return client_context(service.directory, certificate, identity=identity, version=version).wrap_socket(
            raw, server_hostname=identity, suppress_ragged_eofs=False)
    except BaseException:
        raw.close()
        raise


def response(connection, *, method="POST", body=PAYLOAD):
    message = http.client.HTTPResponse(connection, method=method)
    message.begin()
    assert message.status == 200 and message.headers.get_all("Connection") == ["close"]
    assert message.headers.get_all("Content-Length") == [str(len(body))]
    assert message.read() == body
    assert connection.recv(1) == b""
    message.close()


def serve_case(directory, *, certificate="client", required=True, version=None, identity="localhost",
               client_trust="root", expected=0, options=(), ipv6=False):
    with Service(directory, required=required, client_trust=client_trust, options=options, ipv6=ipv6) as service:
        connection = None
        observed = bytearray()
        try:
            connection = connect(service, certificate, identity=identity, version=version)
            request = f"POST /echo HTTP/1.1\r\nHost: localhost\r\nContent-Length: {len(PAYLOAD)}\r\n\r\n".encode() + PAYLOAD
            connection.sendall(request)
            if expected == 0:
                response(connection)
            else:
                # TLS 1.3 may complete locally before the server's client-cert
                # rejection arrives. A response read must observe that alert.
                while True:
                    part = connection.recv(4096)
                    if not part:
                        break
                    observed.extend(part)
                    assert len(observed) <= 16384
        except (ssl.SSLError, ConnectionResetError, BrokenPipeError):
            if expected == 0:
                raise
        finally:
            if connection is not None:
                connection.close()
        assert not observed, observed
        return service.finish(expected, reports=1 if expected == 0 else 0)


def matrix(directory):
    for version in VERSIONS:
        for certificate in ("client", "client-alt", "client-no-eku", "client-chain-full"):
            fetch_case(directory, certificate=certificate, version=version)
            serve_case(directory, certificate=certificate, version=version)
    for peer in ("fixture.test", "127.0.0.1", "::1"):
        fetch_case(directory, peer=peer, ipv6=peer == "::1")
    serve_case(directory, identity="::1", ipv6=True)
    serve_case(directory, certificate="client-untrusted", client_trust="untrusted")
    fetch_case(directory, certificate=None, required=False)
    serve_case(directory, certificate=None, required=False)
    for certificate in ("client", "client-alt", "client-no-eku", "client-chain-full"):
        with Service(directory) as service:
            run_fetch(directory, service.address, certificate=certificate)
            service.finish()
    with Service(directory, options=("--requests", "3")) as service:
        for certificate in ("client", "client-alt", "client-chain-full"):
            run_fetch(directory, service.address, certificate=certificate)
        service.finish(reports=3)


def failures(directory):
    for version in VERSIONS:
        for certificate in (None, "client-expired", "client-wrong-purpose", "client-untrusted", "client-chain"):
            result = fetch_case(directory, certificate=certificate, version=version, expected=3)
            assert not result.stdout
            serve_case(directory, certificate=certificate, version=version, expected=3)
    for arguments in ({"peer": "wrong.invalid"}, {"peer": "127.0.0.2"}, {"trust": "untrusted"},
                      {"server_certificate": "expired"}, {"server_certificate": "wrong-purpose"}, {"server_certificate": "chain"}):
        fetch_case(directory, expected=3, **arguments)
    for certificate, peer, client_trust in ((None, "localhost", "root"), ("client-untrusted", "localhost", "root"),
                                            ("client", "localhost", "untrusted"), ("client", "wrong.invalid", "root")):
        with Service(directory, client_trust=client_trust) as service:
            run_fetch(directory, service.address, certificate=certificate, peer=peer, expected=3)
            service.finish(3, reports=0)


def direct(executable, arguments, expected):
    global CASES
    result = subprocess.run(list(map(str, [executable, *arguments])), stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=4)
    CASES += 1
    assert result.returncode == expected and not result.stdout, (expected, result)
    assert result.stderr.startswith(b"https-") and result.stderr.endswith(b"\n"), result
    assert b"Enter PEM" not in result.stderr and b"pass phrase" not in result.stderr, result
    return result


def limits(directory):
    base = ["127.0.0.1:1", "localhost", directory / "root.pem", "/health"]
    for options in (("--client-cert", directory / "client.pem"), ("--client-key", directory / "client.key"),
                    ("--client-cert", "", "--client-key", ""),
                    ("--client-cert", directory / "client.pem", "--client-key", ""),
                    ("--client-cert", "", "--client-key", directory / "client.key"),
                    ("--client-cert",), ("--client-key",)):
        direct(FETCH, [*base, *options], 2)
    for certificate, key in (("missing", "client"), ("client", "missing"), ("malformed", "client"),
                             ("client", "malformed"), ("client", "client-alt"), ("client", "client-encrypted")):
        run_fetch(directory, "127.0.0.1:1", certificate=certificate, key=key, expected=3)
    for value, expected in (("", 2), (directory / "missing.pem", 3), (directory / "malformed.pem", 3)):
        direct(SERVE, ["127.0.0.1:0", directory / "valid.pem", directory / "valid.key", "--require-client-ca", value], expected)
    direct(SERVE, ["127.0.0.1:0", directory / "valid.pem", directory / "valid.key", "--require-client-ca"], 2)
    for option, expected in (("--max-io", 2), ("--max-tls", 2), ("--timeout", 3), ("--max-work", 2)):
        run_fetch(directory, "127.0.0.1:1", options=(option, "0"), expected=expected)
    for option in ("--max-body", "--max-output"):
        fetch_case(directory, options=(option, len(PAYLOAD)))
        fetch_case(directory, options=(option, len(PAYLOAD) - 1), expected=2)
    for options in (("--max-io", "4"), ("--max-tls", "1")):
        fetch_case(directory, options=options, expected=2)
    for options in (("--max-tls", "0"), ("--max-tls", "1")):
        serve_case(directory, options=options, expected=2)
    for phase in ("accept", "handshake", "request"):
        with Service(directory, options=("--timeout", "150")) as service:
            connection = None
            if phase == "handshake":
                connection = socket.create_connection(service.endpoint, timeout=3)
            if phase == "request":
                connection = connect(service)
                connection.sendall(b"GET /health HTTP/1.1\r\n")
            try:
                errors = service.finish(3, reports=int(phase == "request"))
                assert b"timeout" in errors
            finally:
                if connection is not None:
                    connection.close()


def run_prepared(directory, endpoint, mode):
    global CASES
    result = subprocess.run([PREPARED, endpoint, str(directory / "root.pem"), str(directory / "client.pem"),
                             str(directory / "client.key"), str(mode)], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5)
    CASES += 1
    assert result.returncode == 0 and not result.stdout and not result.stderr, (mode, result)


def prepared(directory):
    for mode in (2, 3, 4, 7):
        run_prepared(directory, "127.0.0.1:1", mode)
    def handler(connection, server):
        connection.handshake()
        assert connection.tls.getpeercert()
        assert connection.read_exact(7) == b"ab\0\xff\n\0x"
        connection.write(b"ACK")
        connection.shutdown()
    with Server(server_context(directory), handler) as server:
        run_prepared(directory, server.address, 0)
    with Server(server_context(directory), handler, expect_failure=True) as server:
        run_prepared(directory, server.address, 1)
    def stall(_connection, server):
        server.stop.wait(1)
    with Server(server_context(directory), stall, expect_failure=True) as server:
        run_prepared(directory, server.address, 5)
    with socket.socket() as reserved:
        reserved.bind(("127.0.0.1", 0))
        run_prepared(directory, f"127.0.0.1:{reserved.getsockname()[1]}", 6)


with tempfile.TemporaryDirectory(prefix="lanius_https_mutual_") as temporary:
    directory = Path(temporary)
    CERTIFICATES.generate(directory)
    (directory / "malformed.key").write_bytes(b"not a private key\n")
    {"matrix": matrix, "failures": failures, "limits": limits, "prepared": prepared}[MODE](directory)
print(f"https-mutual-{MODE} cases={CASES}")
