"""Small loopback contracts for Hub's external-crypto failure boundary.

The existing interposer injects only failures. Recovery and the uninjected
control both use the real EVP provider; peer.py independently checks the accept.
"""
from contextlib import contextmanager
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import time

from peer import Peer


FAULTS = {
    # ERR_raise(ERR_LIB_USER, 0x123) from the OpenSSL 3 test interposer.
    "provider": (1, 0x40000123),
    "size": (2, 19),
    "wide-size": (2, 0x100000014),
}
KEY = b"dGhlIHNhbXBsZSBub25jZQ=="


def startup(process):
    deadline = time.monotonic() + 4
    line = b""
    while b"\n" not in line:
        remaining = deadline - time.monotonic()
        assert remaining > 0, "service startup deadline"
        ready, _, _ = select.select([process.stdout], [], [], remaining)
        assert ready, "service startup deadline"
        chunk = os.read(process.stdout.fileno(), 256)
        assert chunk, ("service exited before startup", process.poll())
        line += chunk
        assert len(line) <= 256, ("unexpected startup", line)
    assert line.startswith(b"127.0.0.1:") and line.count(b"\n") == 1, line
    return int(line.strip().rsplit(b":", 1)[1])


@contextmanager
def server(executable, shim, fault, sample=False):
    environment = os.environ.copy()
    environment.pop("LD_PRELOAD", None)
    environment.pop("LANIUS_WEBSOCKET_FAULT", None)
    if fault:
        environment["LD_PRELOAD"] = str(shim.resolve())
        environment["LANIUS_WEBSOCKET_FAULT"] = fault
    command = [str(executable.resolve())]
    if sample:
        command += ["127.0.0.1:0", "--sessions", "1", "--connections", "1"]
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
    try:
        yield process, startup(process)
    finally:
        if process.poll() is None:
            process.kill()
        process.communicate(timeout=3)


def upgrade_request(path):
    return (b"GET " + path + b" HTTP/1.1\r\nHost: localhost\r\n"
            b"Upgrade: websocket\r\nConnection: Upgrade\r\n"
            b"Sec-WebSocket-Key: " + KEY + b"\r\nSec-WebSocket-Version: 13\r\n"
            b"Sec-WebSocket-Extensions: permessage-deflate\r\n\r\n")


def rejected(peer, path, expected):
    status, headers, body = peer.http(upgrade_request(path))
    assert status == 500, (path, status, headers, body)
    assert body == expected, (path, body, expected)
    assert b"sec-websocket-accept" not in headers and b"upgrade" not in headers, headers
    assert b"sec-websocket-extensions" not in headers, headers
    assert b"close" not in headers.get(b"connection", []), headers
    assert peer.buf == b"", ("unexpected output after rejection", peer.buf)


def ordinary_http(peer, path, expected):
    status, _, body = peer.http(b"GET " + path + b" HTTP/1.1\r\nHost: localhost\r\n\r\n")
    assert status == 200 and body.startswith(expected), (status, body)


def hub_cases(executable, shim):
    for fault in [None, *FAULTS]:
        with server(executable, shim, fault) as (process, port):
            peer = Peer(port, timeout=3)
            try:
                if fault:
                    expected = struct.pack("<QQ", *FAULTS[fault])
                    for _ in range(2):
                        rejected(peer, b"/fail", expected)
                    # Both the same HTTP socket and the single Hub slot survive.
                    ordinary_http(peer, b"/http", b"http retained\n")
                assert peer.handshake(b"/recover") == 101, (fault, peer.status)
                assert peer.message() == (1, 0, b"native accept works")
                peer.send(8, struct.pack(">H", 1000))
                peer.expect_close([1000])
                out, err = process.communicate(timeout=3)
                assert process.returncode == 0 and not err and out == b"crypto-probe ok\n", (fault, process.returncode, out, err)
            finally:
                peer.close()
    print("ws-service-crypto-hub cases=4 failures=6 exact-causes=yes http-owned=yes recovered=yes")


def sample_cases(executable, shim):
    for fault in FAULTS:
        with server(executable, shim, fault, sample=True) as (process, port):
            peer = Peer(port, timeout=3)
            try:
                for path in [b"/ws", b"/chat"]:
                    rejected(peer, path, b"websocket accept unavailable\n")
                    ordinary_http(peer, b"/", b"websocket echo")
                # The existing malformed-request status still applies under faults.
                status, _, _ = peer.http(b"GET /ws HTTP/1.1\r\nHost: localhost\r\n\r\n")
                assert status == 400, (fault, status)
                assert process.poll() is None, (fault, "sample exited")
                process.kill()
                _, err = process.communicate(timeout=3)
                assert not err, (fault, err)
            finally:
                peer.close()
    print("ws-service-crypto-sample cases=3 failures=6 status=500 http-reused=yes")


def main():
    assert len(sys.argv) == 4, "usage: crypto_oracle.py {hub|sample} EXECUTABLE SHIM"
    mode, executable, shim = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    assert mode in ("hub", "sample"), mode
    (hub_cases if mode == "hub" else sample_cases)(executable, shim)


if __name__ == "__main__":
    main()
