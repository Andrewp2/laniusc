"""Eight native OpenSSL peer cases for actual Exchange teardown composition."""
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
from oracle import CLIENT
from teardown_ledger import analyze, controls

REQUEST = b"POST /finish HTTP/1.1\r\nHost: localhost\r\nContent-Length: 258\r\n\r\n"
BODY = bytes((0, 255, 17, 34, 51, 68, 85, 102, 119))
TAIL = bytes((index * 31 + 7) & 255 for index in range(258))
MODES = ("missing-alert", "cut-record", "drain-overflow", "authenticated-empty")


def response(client):
    wire = bytearray()
    while b"\r\n\r\n" not in wire:
        part = client.read(1024)
        assert part and len(wire) + len(part) <= 1024, ("missing response head", wire)
        wire.extend(part)
    head_end = wire.index(b"\r\n\r\n") + 4
    assert len(wire) <= head_end + len(BODY), wire
    wire.extend(client.read_exact(head_end + len(BODY) - len(wire)))
    class CapturedSocket:
        def makefile(self, *_args, **_kwargs):
            return io.BytesIO(wire)
    parsed = http.client.HTTPResponse(CapturedSocket())
    parsed.begin()
    assert parsed.status == 413 and parsed.reason == "Limit" and parsed.version == 11
    assert parsed.getheader("Content-Length") == str(len(BODY)) and parsed.getheader("Connection") == "close"
    assert parsed.read() == BODY and parsed.isclosed(), wire
    return bytes(wire)


def invoke(executable, certificates, trace, mode, version):
    command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
               "-e", "trace=mmap,munmap,open,openat,close,socket,bind,listen,accept,accept4,connect,getsockopt,getsockname,getpeername,fcntl,sendto,recvfrom,poll,shutdown,clock_gettime,read,write",
               str(executable), str(certificates / "valid.pem"), str(certificates / "valid.key"), str(mode)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    transport, thread = None, None
    peer_ready = threading.Event()
    errors, wires, peer_receipts = [], [], []
    until = time.monotonic() + 7
    try:
        def read(count):
            result = bytearray()
            while len(result) < count:
                remaining = until - time.monotonic()
                assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], ("teardown report deadline", mode, trace)
                part = os.read(process.stdout.fileno(), count - len(result))
                assert part, ("teardown report EOF", process.poll(), bytes(result), process.stderr.read(), trace)
                result.extend(part)
            return result
        magic, port = struct.unpack("<2Q", read(16))
        assert magic == 1213421622 and 0 < port < 65536, (magic, port)
        transport = socket.create_connection(("127.0.0.1", port), timeout=3)
        process.stdin.write(b"+")

        def peer():
            try:
                client = CLIENT.Client(transport, CLIENT.context(certificates, version=version))
                client.handshake()
                assert client.tls.getpeercert() and client.tls.version() == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
                if mode == 3:
                    client.shutdown()
                    peer_receipts.append("empty-authenticated-alert")
                else:
                    client.write(REQUEST)
                    wires.append(response(client))
                    # Authenticate the server's local notification without
                    # invoking unwrap or creating a client close_notify.
                    assert client.read() == b""
                    if mode == 1:
                        client.cut_record(TAIL[:257], 7)
                        peer_receipts.append("native-record-cut-to-seven-transport-SHUT_WR")
                    elif mode == 2:
                        client.write(TAIL)
                        peer_receipts.append("native-plaintext-258-after-alert")
                    else:
                        assert not client.outgoing.pending
                        peer_receipts.append("server-alert-authenticated-client-alert-withheld")
            except BaseException as error:
                errors.append(error)
            finally:
                peer_ready.set()

        thread = threading.Thread(target=peer, name=f"https-teardown-{MODES[mode]}", daemon=True)
        thread.start()
        phase, phase_mode = struct.unpack("<2Q", read(16))
        assert (phase, phase_mode) == (1213421625, mode), (phase, phase_mode)
        assert peer_ready.wait(max(.1, until - time.monotonic())) and not errors, (errors, mode, trace)
        process.stdin.write(b"G")
        report = struct.unpack("<32Q", read(256))
        thread.join(max(.1, until - time.monotonic()))
        assert not thread.is_alive() and not errors and len(peer_receipts) == 1, (errors, peer_receipts, report)
        assert report[:3] == (1213421626, mode, 771 if version == ssl.TLSVersion.TLSv1_2 else 772), report
        assert 1 < report[3] < 20000 and report[6] == (0 if mode == 3 else 1) and report[7] == 0 and report[8] == int(mode == 3), report
        assert report[14:18] == (1, int(mode == 3), 1, 0) and report[18] == report[19] > 0 and report[22] == 1, report
        assert report[25] == 1 and report[27:30] == (0, 0, 0) and report[30] == int(mode == 0), report
        if mode == 3:
            assert not wires and report[9:14] == (0, 0, 0, 0, 0) and report[20:22] == (0, 0) and report[24] == report[26] == report[31] == 0, report
        else:
            assert len(wires) == 1 and report[11] == report[12] == report[31] == len(wires[0]), (report, wires)
            assert report[9] == len(REQUEST) + (258 if mode == 2 else 0) and report[10] == (258 if mode == 2 else 0) and report[13] == 0, report
            assert report[20] == mode + 1 and report[21] == (167772454 if mode == 1 else 0) and report[24] == len(REQUEST) and report[26] != 0, report
        # The source-created accepted fd cannot be retained by the tracer.
        # Physical TCP EOF and /proc both precede the child's final ACK/exit.
        transport.settimeout(max(.1, until - time.monotonic()))
        assert transport.recv(1) == b"", ("unexpected unauthenticated application output", report)
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1 and set(os.listdir(f"/proc/{children[0]}/fd")) == {"0", "1", "2"}, children
        process.stdin.write(b"!")
        process.stdin.close()
        process.stdin = None
        extra, stderr = process.communicate(timeout=max(.1, until - time.monotonic()))
        assert process.returncode == 0 and not extra, (process.returncode, extra, stderr, report, trace)
        ledger = analyze(executable, trace, report[23])
        assert (ledger["steps"], ledger["waits"], ledger["polls"]) == report[3:6], (ledger, report)
        print(f"https-server-exchange teardown {version.name} {MODES[mode]} report={report} peer={peer_receipts[0]}")
    finally:
        if transport is not None:
            transport.close()
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=2)
        if thread is not None:
            thread.join(1)
        if process.stdin is not None:
            process.stdin.close()
        process.stdout.close()
        process.stderr.close()


def main(executable, certificates):
    assert controls() == 31
    directory = Path(tempfile.mkdtemp(prefix="https_teardown_"))
    try:
        for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
            for mode in range(4):
                invoke(executable, certificates, directory / f"{version.name}-{mode}.trace", mode, version)
        print("https-server-exchange-teardown cases=8 absolute-timeout=2 cut-native-record=2 drain-overflow=2 authenticated-empty=2 teardown-ledger-controls=31")
    except BaseException:
        print(f"teardown diagnostics retained at {directory}", file=sys.stderr)
        raise
    else:
        for path in directory.iterdir():
            path.unlink()
        directory.rmdir()


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
