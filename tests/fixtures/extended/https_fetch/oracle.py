"""Independent HTTPS peers: Python/OpenSSL TLS and stdlib HTTP header parsing."""
import http.client
import io
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import tempfile
import threading

TLS_FIXTURES = Path(__file__).resolve().parents[1] / "openssl_tls"
sys.path.insert(0, str(TLS_FIXTURES))
from certificates import generate
from peer import Server, binary, context, handshake

MODE, EXE = sys.argv[1:3]
CASES = 0
PAYLOAD = binary(1025) + b"\0\xff\n"


def run(arguments, expected=0, output=None):
    global CASES
    result = subprocess.run([EXE, *map(str, arguments)], stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE if output is None else output,
                            stderr=subprocess.PIPE, timeout=8)
    CASES += 1
    assert result.returncode == expected, (arguments, expected, result)
    if expected == 0:
        assert not result.stderr, result
    else:
        assert not result.stdout, result
        assert result.stderr.startswith(b"https-fetch: ") and result.stderr.endswith(b"\n"), result
        assert b"\0" not in result.stderr, result
    return result


def request(connection, server, identity="localhost", target="/bytes?q=x"):
    data = bytearray()
    while b"\r\n\r\n" not in data:
        part = connection.read(1024)
        assert part and len(data) + len(part) <= 16384
        data.extend(part)
    head, body = bytes(data).split(b"\r\n\r\n", 1)
    first, fields = head.split(b"\r\n", 1)
    assert first == b"GET " + target.encode() + b" HTTP/1.1", first
    headers = http.client.parse_headers(io.BytesIO(fields + b"\r\n\r\n"))
    port = server.listener.getsockname()[1]
    authority = f"[{identity}]" if ":" in identity else identity
    if port != 443:
        authority += f":{port}"
    assert headers.get_all("Host") == [authority], headers
    assert headers.get_all("Connection") == ["close"]
    assert headers.get_all("Content-Length") in (None, ["0"])
    assert not body


def fixed(body=PAYLOAD, status=200):
    return f"HTTP/1.1 {status} Result\r\nContent-Length: {len(body)}\r\n\r\n".encode() + body


def chunked(body=PAYLOAD):
    pieces = [b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n"]
    for offset in range(0, len(body), 17):
        part = body[offset:offset + 17]
        pieces += [f"{len(part):x};tag=yes\r\n".encode(), part, b"\r\n"]
    return b"".join(pieces) + b"0\r\nX-Final: valid\r\n\r\n"


def case(directory, wire, *, expected=0, body=PAYLOAD, identity="localhost",
         certificate="valid", trust="root", fragment=0, abrupt=False,
         options=(), ipv6=False, version=None, stall=None, output=None):
    observed = []

    def handler(connection, server):
        if stall == "handshake":
            server.stop.wait(0.5)
            return
        handshake(connection, server)
        request(connection, server, identity)
        observed.append(True)
        if stall == "response":
            server.stop.wait(0.5)
            return
        connection.write(wire, chunk=1031)
        if abrupt:
            connection.abrupt_eof()
        else:
            connection.shutdown()

    with Server(context(directory, certificate, version), handler, fragment=fragment,
                expect_failure=expected != 0, ipv6=ipv6) as server:
        result = run([server.address, identity, directory / f"{trust}.pem", "/bytes?q=x",
                      "--timeout", "2000", *options], expected, output)
        if expected == 0:
            assert result.stdout == body, result
            assert observed and server.authenticated
            assert server.names == [None if ":" in identity or identity == "127.0.0.1" else identity], server.names
        return result, observed


def matrix(directory):
    for length in [0, 1, 1023, 1024, 1025, 65537]:
        body = binary(length)
        case(directory, fixed(body), body=body)
    case(directory, fixed(), fragment=7)
    case(directory, chunked())
    case(directory, b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n" + PAYLOAD)
    case(directory, b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </x>\r\n\r\n" + fixed())
    case(directory, fixed(status=404))
    case(directory, fixed(), identity="127.0.0.1")
    case(directory, fixed(), identity="fixture.test", certificate="chain-full")
    case(directory, fixed(), version=ssl.TLSVersion.TLSv1_2)
    case(directory, fixed(), version=ssl.TLSVersion.TLSv1_3)
    case(directory, fixed(), abrupt=True)
    case(directory, chunked(), abrupt=True)
    case(directory, fixed(), identity="::1", ipv6=True)


def failures(directory):
    for parameters in [
        {"identity": "wrong.test"}, {"identity": "127.0.0.2"},
        {"trust": "untrusted"}, {"certificate": "expired"},
        {"certificate": "wrong-purpose"}, {"certificate": "chain"},
    ]:
        result, observed = case(directory, fixed(), expected=3, **parameters)
        assert b"certificate" in result.stderr, result
        assert not observed, "HTTP request preceded certificate verification"
    malformed = [
        b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nContent-Length: 3\r\n\r\nabc",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n0\r\n\r\n",
        b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nx",
        b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nq\r\ninvalid\r\n",
        b"HTTP/1.1 101 Switching Protocols\r\nConnection: upgrade\r\nUpgrade: x\r\n\r\n",
        fixed(b"abc") + b"unsolicited",
    ]
    for wire in malformed:
        case(directory, wire, expected=3)
    result, _ = case(directory, b"HTTP/1.1 200 OK\r\n\r\n" + PAYLOAD,
                     expected=3, abrupt=True)
    assert b"truncated TLS" in result.stderr
    # A cut encrypted record is generated by OpenSSL; no custom TLS exists here.
    def truncated(connection, server):
        handshake(connection, server)
        request(connection, server)
        connection.cut_record(fixed(), 11)
    with Server(context(directory), truncated, expect_failure=True) as server:
        result = run([server.address, "localhost", directory / "root.pem", "/bytes?q=x"], 3)
        assert b"truncated TLS" in result.stderr, result


def limits(directory):
    ca = directory / "root.pem"
    for arguments in [[], ["--unknown"], ["-h", "--unknown"], ["--help=yes"],
                      ["127.0.0.1:1", "localhost", ca],
                      ["bad-address", "localhost", ca, "/"],
                      ["127.0.0.1:1", "localhost", ca, "absolute"],
                      ["127.0.0.1:1", "localhost", ca, "/", "--timeout=-1"],
                      ["127.0.0.1:1", "localhost", ca, "/", "--max-body=16777217"],
                      ["127.0.0.1:1", "localhost", ca, "/", "--max-io=2147483648"]]:
        run(arguments, 2)
    assert run(["--help"]).stdout.startswith(b"Usage: https-fetch ADDRESS PEER CA_FILE TARGET")
    for option in ["--max-response", "--max-body", "--max-output"]:
        value = len(fixed()) if option == "--max-response" else len(PAYLOAD)
        case(directory, fixed(), options=[option, str(value)])
        case(directory, fixed(), options=[option, str(value - 1)], expected=2)
    for option in ["--max-io", "--max-tls", "--max-work"]:
        case(directory, fixed(), options=[option, "0"], expected=2)
    case(directory, fixed(), options=["--max-tls", "1"], expected=2)
    case(directory, fixed(), options=["--max-stdout-calls", "0"], expected=5)
    case(directory, fixed(), options=["--timeout", "50"], expected=3, stall="handshake")
    case(directory, fixed(), options=["--timeout", "50"], expected=3, stall="response")
    with open("/dev/full", "wb") as full:
        case(directory, fixed(), expected=5, output=full)
    # A listening port that has just been closed gives deterministic refusal.
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    address = f"127.0.0.1:{listener.getsockname()[1]}"
    listener.close()
    run([address, "localhost", ca, "/"], 3)


def empty_and_large(directory):
    # Zero is an actual finite allowance, not an alias for the default.
    for options in (("--max-body", "0"), ("--max-output", "0"),
                    ("--max-stdout-calls", "0"),
                    ("--max-body", "0", "--max-output", "0", "--max-stdout-calls", "0")):
        case(directory, fixed(b""), body=b"", options=options)
    # The assertion compares every byte received through the real executable.
    # Generous explicit limits separate this scale check from exact-cap tests.
    body = binary(1_048_576)
    case(directory, fixed(body), body=body, options=(
        "--timeout", "5000", "--max-response", "4194304", "--max-body", "2097152",
        "--max-output", "2097152", "--max-io", "131072",
        "--max-tls", "65536", "--max-work", "268435456"))


def stream(directory):
    global CASES
    expected = b"ab\0\xff\n\0x"
    for mode in [0, 1, 2, 3]:
        seen = threading.Event()
        def handler(connection, server, mode=mode):
            handshake(connection, server)
            if mode == 3:
                server.stop.wait(0.6)
                return
            assert connection.read_exact(7) == expected
            seen.set()
            if mode == 0:
                connection.write(b"ACK")
                connection.shutdown()
            elif mode == 2:
                server.stop.wait(0.6)
        with Server(context(directory), handler, expect_failure=mode != 0,
                    receive_buffer=512 if mode == 3 else None) as server:
            result = subprocess.run([EXE, server.address, str(directory / "root.pem"), str(mode)],
                                    capture_output=True, timeout=8)
            CASES += 1
            assert result.returncode == 0 and not result.stdout and not result.stderr, (mode, result)
            if mode != 3:
                assert seen.wait(1), "server did not receive the accepted queue"


with tempfile.TemporaryDirectory(prefix="laniusc_https_fetch_") as name:
    directory = Path(name)
    generate(directory)
    {"matrix": matrix, "failures": failures, "limits": limits,
     "empty-and-large": empty_and_large, "stream": stream}[MODE](directory)
print(f"https-fetch-{MODE} cases={CASES}")
