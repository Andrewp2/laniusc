"""URL reference identity/SNI and no post-selection replay, real native TLS."""
import importlib.util
import io
import http.client
from pathlib import Path
import socket
import ssl
import sys
import tempfile

from connected import connection_chain, probe
from oracle import BODY

TLS = Path(__file__).resolve().parent.parent / "openssl_tls"
sys.path.insert(0, str(TLS))
from certificates import generate
from peer import Server, context, handshake


def read_request(connection, authority, target):
    pending = bytearray()
    while b"\r\n\r\n" not in pending:
        part = connection.read(4096)
        assert part and len(pending) + len(part) <= 32768
        pending.extend(part)
    head, body = bytes(pending).split(b"\r\n\r\n", 1)
    first, fields = head.split(b"\r\n", 1)
    assert first == b"POST " + target + b" HTTP/1.1", first
    headers = http.client.parse_headers(io.BytesIO(fields + b"\r\n\r\n"))
    assert headers.get_all("Host") == [authority] and headers.get_all("Content-Length") == ["4"], headers
    assert headers.get_all("Connection") == ["close"], headers
    while len(body) < 4:
        part = connection.read(4 - len(body))
        assert part
        body += part
    assert body == BODY, body
    return head + b"\r\n\r\n" + body


def case(executable, observer, certificates, directory, version, kind):
    dns = kind != "ip"
    identity = "127.0.0.1" if not dns else "url.example.test" if kind == "identity" else "fixture.test"
    mode = 1 if kind == "identity" else 2 if kind == "truncated" else 0
    received, alerts = [], []
    target = b"/tls/../%2F?q=one??"

    def handler(connection, server):
        try:
            handshake(connection, server)
        except ssl.SSLError as error:
            assert mode == 1, error
            alerts.append(error)
            return
        assert mode != 1, "mismatching identity unexpectedly authenticated"
        authority = f"{identity}:{server.listener.getsockname()[1]}"
        received.append(read_request(connection, authority, target))
        length = 5 if mode == 2 else 4
        connection.write(f"HTTP/1.1 200 OK\r\nContent-Length: {length}\r\n\r\n".encode() + BODY)
        connection.shutdown()  # authenticated close_notify is always explicit

    native = directory / "resolver.log"
    directory.mkdir()
    with Server(context(certificates, version=version), handler, expect_failure=mode != 0) as server:
        port = server.listener.getsockname()[1]
        url = f"https://{identity}:{port}".encode() + target + b"#omitted"
        env = {"LD_PRELOAD": str(observer), "LANIUS_URL_RESOLVE_SCRIPT": "ordered", "LANIUS_RESOLVE_TRACE": str(native)} if dns else {}

        def inspect(tag, words, prefix, profile):
            if tag == 1:
                assert words[2:6] == ((1, 1, 4, 2) if dns else (0, 0, 1, 1)), words
                assert words[12] > 0 and words[15] == mode, words
                if mode == 1:
                    assert words[9] == 0 and words[13:15] == (0, 0) and not received, (words, received)
                else:
                    assert len(received) == 1 and words[8] == words[9] == len(received[0]), (words, received)
                    assert words[13:15] == ((200, 4) if mode == 0 else (0, 0)), words
                if dns:
                    assert native.read_text().splitlines() == [f"G 1024 0 1 6 0 0 {len(identity)} {len(str(port))} 1", f"U {identity} ordered4 loopback", "F"]

        frames, active = probe(executable, [url, certificates / "root.pem", "1" if dns else "0", str(mode)], directory / "probe", inspect, environment=env)
        server.thread.join(timeout=1)
        assert not server.thread.is_alive() and not server.errors, server.errors
        assert server.names == [identity if dns else None], server.names
        assert server.authenticated == (mode != 1), (kind, server.authenticated, alerts)
        if mode == 1:
            assert alerts and not received
        else:
            assert server.version == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
        connection_chain(active, 2 if dns else 1)
        # No third returned endpoint is opened after TLS or HTTP failure.
        server.listener.settimeout(0.1)
        try:
            extra, _ = server.listener.accept()
        except socket.timeout:
            pass
        else:
            extra.close()
            raise AssertionError("URL TLS reopened/replayed after selected TCP")
    return frames


if __name__ == "__main__":
    executable, observer = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    directory = Path(tempfile.mkdtemp(prefix="lanius-url-tls-"))
    certificates = directory / "certificates"
    generate(certificates)
    count = 0
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for kind in ("ip", "dns", "identity", "truncated"):
            case(executable, observer, certificates, directory / str(count), version, kind)
            count += 1
    print(f"url-client-tls cases={count} versions=2 evidence={directory}")
