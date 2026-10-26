"""Actual HTTPS server Exchange, independently verified native TLS/HTTP peers."""
import contextlib
import http.client
import importlib.util
import io
import os
from pathlib import Path
import select
import socket
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True
from ledger import analyze
BASE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("https_exchange_native_client", BASE / "openssl_tls_server" / "client.py")
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)
BODY = bytes(range(256)) * 13 + b"\x00\xff\r\n"
CONTINUE = b"HTTP/1.1 100 Continue\r\n\r\n"
COUNT = 0


def parse_response(wire, status, body):
    class CapturedSocket:
        def makefile(self, *_args, **_kwargs):
            return io.BytesIO(wire)
    response = http.client.HTTPResponse(CapturedSocket())
    response.begin()
    assert response.status == status and response.version == 11
    assert response.getheader("X-Owned") == "stable" and response.getheader("Connection") == "close"
    assert int(response.getheader("Content-Length")) == len(body)
    assert response.read() == body and response.isclosed()


def request(*, chunked=False, expect=False, early=False):
    body = bytes((i * 31 + 7) & 255 for i in range(257)) if early else BODY
    header = b"POST /echo?q=stable HTTP/1.1\r\nHost: localhost\r\nX-Head: frozen\r\n"
    header += b"Transfer-Encoding: chunked\r\n" if chunked else b"Content-Length: %d\r\n" % len(body)
    if expect:
        header += b"Expect: 100-continue\r\n"
    header += b"\r\n"
    if chunked:
        wire_body = b"".join(b"%x\r\n" % len(block) + block + b"\r\n" for at in range(0, len(body), 251) for block in (body[at:at + 251],)) + b"0\r\nX-Tail: yes\r\n\r\n"
    else:
        wire_body = body
    return header, wire_body, body


def read_report(process, deadline):
    result = bytearray()
    while len(result) < 256:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "HTTPS Exchange report deadline"
        block = os.read(process.stdout.fileno(), 256 - len(result))
        assert block, ("HTTPS Exchange report EOF", process.poll(), bytes(result), process.stderr.read())
        result.extend(block)
    return struct.unpack("<32Q", result)


def invoke(executable, certificates, *, version, required=False, missing=False, chunked=False, expect=False, early=False):
    global COUNT
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.bind(("127.0.0.1", 0))
    listener.listen(1)
    parent = socket.create_connection(listener.getsockname(), timeout=4)
    inherited, remote = listener.accept()
    listener.close()
    inherited.setblocking(False)
    inherited.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
    inherited.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    parent.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    assert inherited.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF) <= 16384
    mode = 2 if missing else 1 if early else 0
    fd = inherited.fileno()
    errors, peer_wire, marker_prefix = [], bytearray(), bytearray()
    peer_error = []
    header, wire_body, body = request(chunked=chunked, expect=expect, early=early)
    with tempfile.TemporaryDirectory(prefix="https_server_exchange_") as directory:
        trace = Path(directory) / "native.trace"
        command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
                   "-e", "trace=mmap,munmap,open,openat,close,socket,connect,getsockopt,getpeername,fcntl,sendto,recvfrom,poll,shutdown,clock_gettime,read,write",
                   str(executable), str(fd), str(remote[1]), str(certificates / "valid.pem"),
                   str(certificates / "valid.key"), str(certificates / "root.pem"), str(mode), str(int(required)), "100000"]
        process = subprocess.Popen(command, pass_fds=(fd,), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        inherited.close()
        until = time.monotonic() + 8

        def peer():
            try:
                configuration = CLIENT.context(certificates, version=version)
                if required and not missing:
                    configuration.load_cert_chain(certificates / "client.pem", certificates / "client.key")
                client = CLIENT.Client(parent, configuration)
                try:
                    client.handshake()
                    assert client.tls.getpeercert() and client.tls.version() == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
                    client.write(header)
                    if expect:
                        assert client.read_exact(len(CONTINUE)) == CONTINUE
                    if not early:
                        client.write(wire_body)
                    else:
                        # Real native backpressure is causally established;
                        # never read even a prefix of the final response first.
                        while True:
                            remaining = until - time.monotonic()
                            assert remaining > 0 and select.select([process.stderr], [], [], remaining)[0], "missing native WANT_WRITE marker"
                            byte = os.read(process.stderr.fileno(), 1)
                            assert byte, ("marker EOF", process.poll())
                            marker_prefix.extend(byte)
                            if byte == b"B":
                                break
                    while True:
                        block = client.read()
                        if not block:
                            break
                        peer_wire.extend(block)
                    if missing:
                        raise AssertionError("required-client TLS unexpectedly admitted HTTP")
                    expected = bytes((i * 73 + 11) & 255 for i in range(65536)) if early else body
                    parse_response(bytes(peer_wire), 413 if early else 200, expected)
                    if early:
                        client.write(wire_body)
                    client.shutdown()
                except (ssl.SSLError, OSError) as error:
                    if not missing:
                        raise
                    peer_error.append(error)
            except BaseException as error:
                errors.append(error)

        thread = threading.Thread(target=peer, name="verified-https-exchange-peer", daemon=True)
        thread.start()
        try:
            report = read_report(process, until)
            thread.join(max(.1, until - time.monotonic()))
            assert not thread.is_alive() and not errors, (errors, report)
            assert report[0] == 1213421620 and report[1] == mode and report[18] == 1, report
            child_ids = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
            assert len(child_ids) == 1 and set(os.listdir(f"/proc/{child_ids[0]}/fd")) == {"0", "1", "2"}, child_ids
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            extra, stderr = process.communicate(timeout=max(.1, until - time.monotonic()))
            assert process.returncode == 0 and not extra, (process.returncode, extra, bytes(marker_prefix) + stderr)
            ledger = analyze(executable, trace, fd)
            assert ledger["steps"] == report[3] and report[14] == report[15], (ledger, report)
            assert report[21:23] == (1, 0), report
            if missing:
                assert peer_error and not peer_wire and report[2] == 0 and report[4:8] == (0, 0, 0, 1), (report, peer_error)
                assert report[9:14] == (0, 0, 0, 0, 0), report
                assert (report[8] >> 23) & 255 == 20 and report[8] & 0x7fffff == 199, report
            else:
                assert report[2] == (771 if version == ssl.TLSVersion.TLSv1_2 else 772), report
                assert report[4] == 1 and report[5] == (0 if early else 1) and report[6:8] == (1, 0), report
                assert report[11] == report[12] == len(peer_wire) and report[24:26] == (1, 1), report
                assert report[13] == (25 if expect else 0), report
                assert report[9] == len(header) + len(wire_body), report
                if early:
                    assert report[10] == 257 and report[16] > 0 and report[17] > 0 and marker_prefix.endswith(b"B"), report
                else:
                    assert report[10] == 0, report
            COUNT += 1
        finally:
            parent.close()
            if process.poll() is None:
                process.kill()
                process.communicate(timeout=2)
            thread.join(1)
            if process.stdin is not None:
                process.stdin.close()
            process.stdout.close()
            process.stderr.close()


def steps(executable, certificates):
    invoke(executable, certificates, version=ssl.TLSVersion.TLSv1_2)
    invoke(executable, certificates, version=ssl.TLSVersion.TLSv1_3, chunked=True)
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        invoke(executable, certificates, version=version, required=True, expect=True)
        invoke(executable, certificates, version=version, required=True, missing=True)


def closure(executable, certificates):
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        invoke(executable, certificates, version=version, early=True)


if __name__ == "__main__":
    executable, certificates, group = sys.argv[1:]
    {"steps": steps, "closure": closure}[group](Path(executable).resolve(), Path(certificates).resolve())
    print(f"https-server-exchange-{group} cases={COUNT} native-step-bound-and-source-fd-owners=checked")
