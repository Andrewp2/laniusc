"""Finite independent OpenSSL server oracle; no TLS/crypto implementation."""

from pathlib import Path
import socket
import ssl
import struct
import subprocess
import sys
import re
import tempfile

sys.dont_write_bytecode = True
from client import Client, binary, context
from certificates import PASSPHRASE


EXECUTABLE = None
CERTIFICATES = None
CASES = 0


def invoke(*, mode=1, count=1025, layout=0, certificate="valid.pem", key="valid.key",
           password="-", identity="localhost", trust="root", version=None,
           fault=0, fragment=0, expect_client_failure=False, trace=None, fail_at=None):
    global CASES
    parent, inherited = socket.socketpair()
    inherited.setblocking(False)
    if mode == 2:
        inherited.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
        parent.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    chain = CERTIFICATES / certificate if certificate else ""
    private = CERTIFICATES / key if key else ""
    command = [str(EXECUTABLE), str(inherited.fileno()), str(chain), str(private),
               password, str(mode), str(count), str(layout), str(fault)]
    if trace is not None:
        prefix = ["strace", "-qq", "-o", str(trace), "-e", "trace=mmap,munmap,write"]
        if fail_at is not None:
            prefix += ["-e", f"inject=mmap:error=ENOMEM:when={fail_at}"]
        command = prefix + command
    process = subprocess.Popen(command, pass_fds=(inherited.fileno(),),
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    inherited.close()
    client_error = None
    version_name = None
    signals = []
    try:
        if mode not in (0, 6, 7, 8):
            client = Client(parent, context(CERTIFICATES, identity, trust, version), identity, fragment)
            try:
                client.handshake()
                version_name = client.tls.version()
                assert client.tls.getpeercert(), "verified server certificate missing"
                assert version_name in ("TLSv1.2", "TLSv1.3")
                if mode == 4:
                    client.cut_record(binary(count), 7)
                elif mode == 3:
                    client.write(binary(count), chunk=293)
                    client.abrupt_eof()
                elif mode == 5:
                    client.write(binary(count), chunk=293)
                    client.shutdown()
                elif mode == 2:
                    signals.append(process.stderr.readline(16))
                    assert signals == [b"W\n"], signals
                    assert client.read_exact(count) == bytes(byte ^ 90 for byte in binary(count))
                    signals.append(process.stderr.readline(16))
                    assert signals == [b"W\n", b"R\n"], signals
                    client.write(binary(count), chunk=293)
                    assert client.read() == b""
                    client.shutdown()
                elif mode == 9:
                    assert client.read() == b""
                    client.shutdown()
                else:
                    client.write(binary(count), chunk=293)
                    assert client.read_exact(count) == bytes(byte ^ 90 for byte in binary(count))
                    assert client.read() == b""
                    client.shutdown()
            except (ssl.SSLError, OSError, EOFError) as error:
                client_error = error
                if not expect_client_failure:
                    raise
        # Keep stdin open with no bytes until exit. An accidental password
        # read therefore blocks and fails this deadline instead of receiving EOF.
        status = process.wait(timeout=7)
        output = process.stdout.read(4096)
        errors = process.stderr.read(4096)
        assert status == 0 and len(output) == 120 and errors == (b"A\nB\n" if mode == 0 else b""), (command, status, output, errors)
        if expect_client_failure:
            assert client_error is not None, (command, "negative peer unexpectedly succeeded")
        observed = struct.unpack("<15Q", output)
        CASES += 1
        return observed, client_error, version_name
    finally:
        parent.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=1)
        process.stdin.close()
        process.stdout.close()
        process.stderr.close()


def successful(observed, count):
    assert observed[:6] == (0, 0, 0, 0, 0, 0), observed
    assert observed[8:10] == (count, count) and observed[11] == 5, observed
    assert observed[12] > 0, "native TLS operations must execute"


def matrix():
    for count, layout in ((0, 0), (1, 1), (255, 2), (1024, 0), (1025, 1), (16385, 2)):
        observed, _, _ = invoke(count=count, layout=layout, fragment=7 if count == 255 else 0)
        successful(observed, count)
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        observed, _, negotiated = invoke(count=769, version=version, layout=2)
        successful(observed, 769)
        assert negotiated == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
    for identity, certificate, key in (("127.0.0.1", "valid.pem", "valid.key"),
                                        ("fixture.test", "chain-full.pem", "chain.key")):
        observed, _, _ = invoke(identity=identity, certificate=certificate, key=key)
        successful(observed, 1025)
    print(f"openssl-tls-server verified DNS/IP, root-only chain, TLS1.2/1.3, binary layouts and retained context cases={CASES}")


def credentials():
    observed, _, _ = invoke(mode=8)
    assert observed == (0,) * 15, observed
    for key, password in (("valid.key", "-"), ("encrypted.key", PASSPHRASE)):
        observed, _, _ = invoke(mode=6, key=key, password=password)
        assert observed == (0,) * 15, observed
    observed, _, _ = invoke(key="encrypted.key", password=PASSPHRASE, count=1025, layout=1)
    successful(observed, 1025)
    for options, phases in (
        ({"certificate": "missing.pem"}, (11,)),
        ({"certificate": "malformed.pem"}, (11,)),
        ({"certificate": "."}, (11,)),
        ({"key": "missing.key"}, (12,)),
        ({"key": "malformed.pem"}, (12,)),
        ({"key": "root.key"}, (12, 14)),
        ({"key": "encrypted.key", "password": "wrong password"}, (12,)),
        ({"key": "encrypted.key", "password": "-"}, (12,)),
    ):
        observed, _, _ = invoke(mode=6, **options)
        assert observed[0:2] == (6, 10) and observed[2] in phases and observed[4] != 0, (options, observed)
        assert observed[6:] == (0,) * 9, observed
    for options, phase in (({"certificate": ""}, 11), ({"key": ""}, 12)):
        observed, _, _ = invoke(mode=6, **options)
        assert observed[:6] == (6, 1, phase, 0, 0, 0) and observed[6:] == (0,) * 9, observed
    print(f"openssl-tls-server credential validation, encrypted key, mismatch and no-stdin-prompt cases={CASES}")


def verification_and_endings():
    for options, verify_code in (({"identity": "wrong.invalid"}, 62),
                                 ({"identity": "127.0.0.2"}, 64),
                                 ({"trust": "untrusted"}, 20)):
        observed, error, _ = invoke(expect_client_failure=True, **options)
        assert isinstance(error, ssl.SSLCertVerificationError) and error.verify_code == verify_code, (error, options)
        assert observed[0] == 1 and observed[1] == 10 and observed[2] == 7 and observed[11] == 6, observed
        assert observed[8:11] == (0, 0, 0), observed
    observed, _, _ = invoke(version=ssl.TLSVersion.TLSv1_1, expect_client_failure=True)
    assert observed[0:3] == (1, 10, 7) and observed[11] == 6, observed
    for mode, count, expected in ((3, 1, 1), (3, 1025, 1025), (4, 1025, 0)):
        observed, _, _ = invoke(mode=mode, count=count, fragment=7)
        assert observed[0:3] == (2, 14, 8) and observed[11] == 6, observed
        assert observed[8] == 0 and observed[9] == expected and observed[10] == 0, observed
    observed, _, _ = invoke(mode=9, count=0)
    successful(observed, 0)
    observed, _, _ = invoke(mode=5, count=1025, layout=2)
    assert observed[:6] == (0,) * 6 and observed[8:12] == (0, 1025, 1, 5), observed
    print(f"openssl-tls-server peer verification, protocol floor, close-notify and native record truncation cases={CASES}")


def retries():
    observed, _, _ = invoke(mode=2, count=524288, layout=1)
    successful(observed, 524288)
    assert observed[7] > 0 and observed[13] > 0 and observed[14] > 0, observed
    print(f"openssl-tls-server stable pending writes, changed read destinations and bounded polling cases={CASES}")


def faults():
    for fault, outcome, phase in ((1, 6, 1), (2, 6, 1), (3, 6, 3), (4, 6, 11),
                                  (5, 6, 12), (6, 6, 14), (7, 7, 4), (8, 7, 6), (9, 1, 7)):
        observed, _, _ = invoke(mode=7, fault=fault)
        assert observed[0:3] == (outcome, 10, phase) and observed[4] != 0, (fault, observed)
        assert observed[8:11] == (0, 0, 0), observed
    for fault, outcome, phase in ((10, 2, 8), (11, 4, 9), (12, 5, 10)):
        observed, _, _ = invoke(fault=fault, count=1, expect_client_failure=True)
        assert observed[0:3] == (outcome, 10, phase) and observed[4] != 0 and observed[11] == 6, (fault, observed)
    print(f"openssl-tls-server exact native acquisition/configuration/I/O fault cleanup cases={CASES}")


def allocation_events(trace, sizes):
    active = False
    ordinal = 0
    attempts = []
    live = {}
    failures = 0
    for line in trace.splitlines():
        if line.startswith('write(2, "A\\n", 2)'):
            assert not active
            active = True
        elif line.startswith('write(2, "B\\n", 2)'):
            assert active and not live, ("staged allocation survived owner cleanup", live, trace)
            active = False
        if line.startswith("mmap("):
            ordinal += 1
            size = int(line.split(",", 2)[1].strip())
            if active and size in sizes:
                address = line.rsplit(" = ", 1)[1].split()[0]
                attempts.append((ordinal, size))
                if address.startswith("0x"):
                    assert address not in live
                    live[address] = size
                else:
                    assert address == "-1" and "ENOMEM" in line, line
                    failures += 1
        elif line.startswith("munmap("):
            found = re.fullmatch(r"munmap\((0x[0-9a-f]+), (\d+)\)\s+=\s+0", line)
            if found and found[1] in live:
                assert live.pop(found[1]) == int(found[2]), line
    assert not active and not live, trace
    return attempts, failures


def allocations():
    sizes = [len(str(CERTIFICATES / "valid.pem").encode()) + 1,
             len(str(CERTIFICATES / "valid.key").encode()) + 1, 1, 1024, 1024, 16]
    with tempfile.TemporaryDirectory(prefix="tls-server-allocation-") as directory:
        path = Path(directory) / "baseline.trace"
        observed, _, _ = invoke(mode=0, trace=path)
        assert observed[:11] == (0,) * 11 and observed[11] == 1, observed
        baseline, failures = allocation_events(path.read_text(), sizes)
        assert failures == 0 and [size for _, size in baseline] == sizes, (baseline, sizes, path.read_text())
        for index, (ordinal, _) in enumerate(baseline):
            path = Path(directory) / f"failure-{index}.trace"
            observed, _, _ = invoke(mode=0, trace=path, fail_at=ordinal)
            expected = (6, 9, (11, 12, 13)[index]) if index < 3 else (7, 9, 4)
            assert observed[:3] == expected and observed[3:11] == (0,) * 8, (index, observed)
            attempts, failures = allocation_events(path.read_text(), sizes)
            assert failures == 1 and len(attempts) == index + 1, (index, attempts, path.read_text())
            assert [size for _, size in attempts] == sizes[:index + 1]
            assert path.read_text().count("INJECTED") == 1
    print(f"openssl-tls-server all six reached credential/session allocation failures and exact mapping cleanup cases={CASES}")


if __name__ == "__main__":
    group, executable, certificates = sys.argv[1:]
    EXECUTABLE = Path(executable).resolve()
    CERTIFICATES = Path(certificates).resolve()
    {"matrix": matrix, "credentials": credentials, "endings": verification_and_endings,
     "retries": retries, "faults": faults, "allocations": allocations}[group]()
