"""Three native crypto faults at the public client's opening boundary.

Fault injection reuses the upgrade fixture's interposer. Recovery removes its
fault environment variable in the same process, so its positive call forwards
to actual OpenSSL. The peer's accept value comes from CPython's separate _sha1.
"""
import _sha1
import base64
import importlib.util
import os
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile
import threading

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
FAULTS = {"provider": (1, (128 << 23) | 0x123), "size": (2, 19), "wide-size": (2, 0x100000014)}


def resources():
    source = Path(__file__).with_name("crypto_resources.py")
    spec = importlib.util.spec_from_file_location("websocket_crypto_resources", source)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def no_request(connection):
    # EOF is required: mere silence could be a hung or still-owned socket.
    actual = connection.recv(1)
    assert actual == b"", ("crypto failure published HTTP bytes", actual)


def recover(connection):
    request = bytearray()
    while not request.endswith(b"\r\n\r\n"):
        block = connection.recv(4096)
        assert block, ("recovery closed before upgrade", bytes(request))
        request.extend(block)
        assert len(request) <= 8192, "unbounded recovery request"
    lines = bytes(request).split(b"\r\n")
    assert lines[0] == b"GET /crypto HTTP/1.1", lines[0]
    headers = {}
    for line in lines[1:-2]:
        key, value = line.split(b":", 1)
        key = key.lower()
        assert key not in headers, ("duplicate request header", key)
        headers[key] = value.strip()
    key = headers[b"sec-websocket-key"]
    assert len(base64.b64decode(key, validate=True)) == 16, key
    accept = base64.b64encode(_sha1.sha1(key + GUID).digest())
    connection.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n"
                       b"Connection: Upgrade\r\nSec-WebSocket-Accept: " + accept + b"\r\n\r\n")
    assert connection.recv(1) == b"", "recovered client did not destroy its connection"


def invoke(group, executable, shim, fault, trace=None):
    environment = dict(os.environ, LD_PRELOAD=str(shim), LANIUS_WEBSOCKET_FAULT=fault)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(2)
        listener.settimeout(5)
        url = f"ws://127.0.0.1:{listener.getsockname()[1]}/crypto"
        observed, failures = [], []

        def peer():
            try:
                for action in ([no_request, recover] if group == "typed" else [no_request]):
                    connection, _ = listener.accept()
                    with connection:
                        connection.settimeout(4)
                        action(connection)
                        observed.append(action.__name__)
            except BaseException as error:
                failures.append(error)

        worker = threading.Thread(target=peer, daemon=True)
        worker.start()
        command = [str(executable), url]
        if group == "typed":
            command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i",
                       "-e", "signal=none", "-e", "trace=mmap,munmap,write", "-o", str(trace), *command]
        result = subprocess.run(command, input=b"", capture_output=True, env=environment, timeout=7)
        worker.join(timeout=5)
        assert not worker.is_alive(), "loopback peer did not finish"
        assert not failures, (fault, failures, result)
        assert observed == (["no_request", "recover"] if group == "typed" else ["no_request"]), observed
        if group == "typed":
            assert result.returncode == 0 and result.stderr == b"A\nB\n", (fault, result)
            assert len(result.stdout) == 16, (fault, result)
            assert struct.unpack("<QQ", result.stdout) == FAULTS[fault], (fault, result.stdout)
        else:
            assert result.returncode == 1 and not result.stderr, (fault, result)
            assert result.stdout == b"error crypto\n", (fault, result.stdout)


def controls():
    # A published request byte must fail, while explicit EOF is accepted.
    for payload in (b"", b"G"):
        reader, writer = socket.socketpair()
        with reader, writer:
            if payload:
                writer.sendall(payload)
            writer.shutdown(socket.SHUT_WR)
            try:
                no_request(reader)
            except AssertionError:
                assert payload
            else:
                assert not payload
    assert resources().controls() == 12


def main():
    if sys.argv[1:] == ["controls"]:
        controls()
        print("websocket-client-crypto host-controls=14")
        return
    assert len(sys.argv) == 4 and sys.argv[1] in ("typed", "sample"), sys.argv
    group, executable, shim = sys.argv[1], Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve()
    controls()
    ledger = resources() if group == "typed" else None
    with tempfile.TemporaryDirectory(prefix="lanius-websocket-crypto-") as directory:
        for fault in FAULTS:
            trace = Path(directory) / fault
            invoke(group, executable, shim, fault, trace)
            if ledger:
                allocations = ledger.analyze(executable, trace.read_text())
                assert any(row["active"] for row in allocations), "failed connect did not stage owners"
    if group == "typed":
        print("websocket-client-crypto typed=3 zero-request=3 recovered=3 owners=balanced")
    else:
        print("websocket-client-crypto sample=3 zero-request=3 diagnostic=crypto")


if __name__ == "__main__":
    main()
