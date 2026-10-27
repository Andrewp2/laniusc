"""Pre-HTTP constructor/quota cases; source ENOMEM is a separate finite group."""
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from constructor_ledger import analyze, controls


def invoke(executable, certificates, trace, mode, target=None):
    command = ["strace", "--kill-on-exit", "-qq", "-i", "-s", "96", "-o", str(trace),
               "-e", "trace=mmap,munmap,open,openat,close,socket,bind,listen,accept,accept4,connect,getsockopt,getsockname,getpeername,fcntl,sendto,recvfrom,poll,shutdown,clock_gettime,read,write"]
    if target is not None:
        command += ["-e", f"inject=mmap:error=ENOMEM:when={target['ordinal']}"]
    command += [str(executable), str(certificates / "valid.pem"), str(certificates / "valid.key"), str(mode), str(int(target is not None))]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    peer = None
    until = time.monotonic() + 6
    try:
        def read(count):
            result = bytearray()
            while len(result) < count:
                remaining = until - time.monotonic()
                assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], ("constructor report deadline", mode, trace)
                part = os.read(process.stdout.fileno(), count - len(result))
                assert part, ("constructor report EOF", process.poll(), bytes(result), process.stderr.read(), trace)
                result.extend(part)
            return result
        magic, port = struct.unpack("<2Q", read(16))
        assert magic == 1213421622 and 0 < port < 65536, (magic, port)
        # No connection exists when strace starts: EOF cannot be masked by an
        # inherited tracer fd. Deliberately send no ClientHello or HTTP bytes.
        peer = socket.create_connection(("127.0.0.1", port), timeout=3)
        process.stdin.write(b"+")
        report = struct.unpack("<16Q", read(128))
        calls = int(mode in (2, 4))
        io_calls = 0 if mode == 0 else 2 if mode in (2, 4) else 1
        steps = 3 if mode == 2 else 2 if mode in (3, 4) else 1 if mode == 5 and target is None else 0
        waits = 2 if mode == 4 else int(mode in (2, 3) or (mode == 5 and target is None))
        assert report == (1213421623, mode, int(target is not None), int(mode != 5 or target is not None), calls, io_calls, steps, waits, 1, 0, 0, 0, 0, 0, 0, report[15]), report
        peer.settimeout(max(.1, until - time.monotonic()))
        assert peer.recv(1) == b"", ("unexpected server bytes before handshake admission", report)
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1 and set(os.listdir(f"/proc/{children[0]}/fd")) == {"0", "1", "2"}, children
        process.stdin.write(b"!")
        process.stdin.close()
        process.stdin = None
        extra, stderr = process.communicate(timeout=max(.1, until - time.monotonic()))
        assert process.returncode == 0 and not extra, (process.returncode, extra, stderr, report, trace)
        ledger = analyze(executable, trace, report[15], None if target is None else target["ordinal"])
        assert ledger["steps"] == steps and ledger["waits"] == waits, (ledger, report)
        expected_close = "B" if mode <= 1 or target is not None else "A" if mode == 5 else "W" if mode == 4 else "S"
        assert ledger["close"]["frames"] == (expected_close,), ledger["close"]
        if target is not None:
            reached = ledger["injected"][0]
            assert (reached["ip"], reached["length"], reached["frames"]) == (target["ip"], target["length"], ("B",)), ("constructor target drift", reached, target)
        return ledger
    finally:
        if peer is not None:
            peer.close()
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=2)
        if process.stdin is not None:
            process.stdin.close()
        process.stdout.close()
        process.stderr.close()


def main(executable, certificates, group):
    assert controls() == 17
    directory = Path(tempfile.mkdtemp(prefix="https_constructor_"))
    try:
        if group == "constructor-quotas":
            for mode in range(6):
                invoke(executable, certificates, directory / f"mode-{mode}.trace", mode)
            print("https-server-exchange-constructor-quotas cases=6 real-handshake-WANT_READ=2 constructor-ledger-controls=17")
        else:
            raise AssertionError(("unknown constructor group", group))
    except BaseException:
        print(f"constructor diagnostics retained at {directory}", file=sys.stderr)
        raise
    else:
        for path in directory.iterdir():
            path.unlink()
        directory.rmdir()


if __name__ == "__main__":
    executable, certificates, group = sys.argv[1:]
    assert group == "constructor-quotas"
    main(Path(executable).resolve(), Path(certificates).resolve(), group)
