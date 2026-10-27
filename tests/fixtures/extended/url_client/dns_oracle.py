"""One ordered synthetic NSS list with real refused/live loopback endpoints."""
import os
import re
from pathlib import Path
import socket
import sys
import tempfile
import threading

from connected import connection_chain, probe
from oracle import BODY, TRUSTED, request


def run(executable, observer, directory):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(2)
    listener.settimeout(6)
    port = listener.getsockname()[1]
    authority = f"url.example.test:{port}".encode()
    target = b"/dns/../%2F?unchanged=yes"
    received, failures = [], []

    def peer():
        try:
            with listener.accept()[0] as connection:
                received.append(request(connection, authority, target))
                connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\n" + BODY)
                connection.shutdown(socket.SHUT_WR)
                assert connection.recv(1) == b""
            listener.settimeout(0.1)
            try:
                duplicate, _ = listener.accept()
            except socket.timeout:
                pass
            else:
                duplicate.close()
                raise AssertionError("replayed request after selection")
        except BaseException as error:
            failures.append(error)

    worker = threading.Thread(target=peer, daemon=True)
    worker.start()
    native = directory / "resolver.log"

    def inspect(tag, words, prefix, profile):
        if tag == 1:
            assert words[2:6] == (1, 1, 4, 2) and words[15] == 1, words
            assert len(received) == 1 and words[8] == words[9] == len(received[0]), (words, received)
            assert words[13:15] == (200, 4), words
            assert native.read_text().splitlines() == [f"G 1024 0 1 6 0 0 16 {len(str(port))} 1", "U url.example.test ordered4 loopback", "F"]

    try:
        frames, active = probe(executable, [b"http://" + authority + target + b"#omitted", "1"], directory / "probe", inspect,
                               environment={"LD_PRELOAD": str(observer), "LANIUS_URL_RESOLVE_SCRIPT": "ordered", "LANIUS_RESOLVE_TRACE": str(native)})
        worker.join(timeout=1)
        assert not worker.is_alive() and not failures, failures
        connection_chain(active, 2, plaintext=received[0])
        connects = [item for item in active if item["name"] == "connect"]
        addresses = []
        for item in connects:
            match = re.search(r'inet_addr\(("[^"\n]*")\)', item["args"])
            assert match and f"sin_port=htons({port})" in item["args"], item
            encoded = match[1]
            addresses.append(TRUSTED.quoted(encoded) if "\\x" in encoded else encoded[1:-1].encode("ascii"))
        assert addresses == [b"127.0.0.2", b"127.0.0.1"], addresses
        return frames
    finally:
        listener.close()
        worker.join(timeout=1)


if __name__ == "__main__":
    executable, observer = map(lambda value: Path(value).resolve(), sys.argv[1:3])
    directory = Path(tempfile.mkdtemp(prefix="lanius-url-dns-"))
    run(executable, observer, directory)
    print(f"url-client-dns cases=1 addresses=4 selected=1 attempts=2 evidence={directory}")
