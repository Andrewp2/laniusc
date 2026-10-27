"""Three exact HTTPS cleanup contracts, with real peers and reached close faults."""
import http.client
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
from cleanup_ledger import analyze, controls
from oracle import CLIENT

REQUEST = b"POST /close HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n"


def invoke(executable, certificates, trace, version, *, normal=False, target=None):
    parent = None
    command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
               "-e", "trace=mmap,munmap,open,openat,close,socket,bind,listen,accept,accept4,connect,getsockopt,getsockname,getpeername,fcntl,sendto,recvfrom,poll,shutdown,clock_gettime,read,write"]
    if target is not None:
        command += ["-e", f"inject=close:error=EIO:when={target['ordinal']}"]
    command += [str(executable), str(certificates / "valid.pem"), str(certificates / "valid.key")]
    if normal:
        command += [str(int(target is not None))]
    else:
        command += [str(certificates / "root.pem"), "0", str(int(target is not None))]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    errors, peer_errors, wire = [], [], bytearray()
    until = time.monotonic() + 8

    def peer():
        try:
            client = CLIENT.Client(parent, CLIENT.context(certificates, version=version))
            client.handshake()
            assert client.tls.getpeercert()
            client.write(REQUEST)
            try:
                while True:
                    part = client.read()
                    if not part:
                        break
                    wire.extend(part)
                if not normal:
                    raise AssertionError("abort after fatal preparation invented clean TLS EOF")
                class CapturedSocket:
                    def makefile(self, *_args, **_kwargs):
                        return io.BytesIO(wire)
                response = http.client.HTTPResponse(CapturedSocket())
                response.begin()
                assert response.status == 200 and response.getheader("Connection") == "close" and response.getheader("Content-Length") == "0"
                assert response.read() == b"" and response.isclosed()
                client.shutdown()
            except ssl.SSLError as error:
                if normal:
                    raise
                peer_errors.append(error)
        except BaseException as error:
            errors.append(error)

    thread = None
    try:
        def read(count):
            result = bytearray()
            while len(result) < count:
                remaining = until - time.monotonic()
                assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "cleanup report deadline"
                part = os.read(process.stdout.fileno(), count - len(result))
                assert part, ("cleanup report EOF", process.poll(), bytes(result), process.stderr.read())
                result.extend(part)
            return result
        magic, port = struct.unpack("<2Q", read(16))
        assert magic == 1213421622 and 0 < port < 65536, (magic, port)
        # This peer socket is opened after the tracer/tracee were spawned, so
        # neither process can inherit a copy that masks abortive TCP EOF.
        parent = socket.create_connection(("127.0.0.1", port), timeout=4)
        process.stdin.write(b"+")
        thread = threading.Thread(target=peer, name="https-preparation-cleanup-peer", daemon=True)
        thread.start()
        report = struct.unpack("<16Q", read(128))
        thread.join(max(.1, until - time.monotonic()))
        assert not thread.is_alive() and not errors, (errors, report)
        assert report[0] == 1213421621 and report[1] == (771 if version == ssl.TLSVersion.TLSv1_2 else 772), report
        assert report[4] == 1 and report[5] == int(target is not None) and report[6] == len(REQUEST), report
        assert report[9] == 0 and report[10] == int(target is not None) and report[11] == int(normal), report
        if normal:
            assert report[7] == report[12] == len(wire) > 0 and not peer_errors, (report, wire, peer_errors)
        else:
            assert report[7] == 0 and not wire and peer_errors and report[8] != 0, (report, wire, peer_errors)
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1 and set(os.listdir(f"/proc/{children[0]}/fd")) == {"0", "1", "2"}, children
        process.stdin.write(b"!")
        process.stdin.close()
        process.stdin = None
        extra, stderr = process.communicate(timeout=max(.1, until - time.monotonic()))
        assert process.returncode == 0 and not extra, (process.returncode, extra, stderr, report)
        ledger = analyze(executable, trace, report[15], None if target is None else target["ordinal"])
        assert ledger["steps"] == report[2], (ledger, report)
        if target is not None:
            reached = ledger["close"]
            assert reached["ip"] == target["ip"] and reached["frames"] == target["frames"], ("close target drift", reached, target)
            assert reached["frames"] == (("S",) if normal else ("A",)), reached
        return ledger
    finally:
        if parent is not None:
            parent.close()
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=2)
        if thread is not None:
            thread.join(1)
        if process.stdin is not None:
            process.stdin.close()
        process.stdout.close()
        process.stderr.close()


def main(executable, certificates, name):
    assert controls() == 7
    count = 0
    with tempfile.TemporaryDirectory(prefix="https_cleanup_faults_") as directory:
        for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
            normal = name == "normal-close"
            trace = Path(directory) / f"{version.name}.trace"
            baseline = invoke(executable, certificates, trace, version, normal=normal)
            count += 1
            target = baseline["close"]
            assert target["frames"] == (("S",) if normal else ("A",)), target
            invoke(executable, certificates, trace, version, normal=normal, target=target)
            count += 1
    print(f"https-server-exchange-{name} cases={count} reached-close-EIO=2 cleanup-ledger-controls=7")


if __name__ == "__main__":
    executable, certificates, name = sys.argv[1:]
    assert name in ("preparation-abort", "normal-close")
    main(Path(executable).resolve(), Path(certificates).resolve(), name)
