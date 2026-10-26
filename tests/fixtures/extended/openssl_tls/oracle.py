"""Loopback-only independent native TLS wrapper oracle (test infrastructure)."""

from pathlib import Path
import socket
import ssl
import struct
import subprocess
import sys
import threading

from peer import Server, binary, context, handshake


EXECUTABLE = None
CERTIFICATES = None
CASES = 0


def handshake_only(connection, server):
    handshake(connection, server)
    assert connection.read() == b"", "client must send close_notify"
    connection.shutdown()


def exchange(count, ending="clean", backpressure=False):
    def handler(connection, server):
        handshake(connection, server)
        if backpressure:
            assert server.release.wait(4), "client never reached native WANT_WRITE"
        request = connection.read_exact(count)
        assert request == binary(count), (len(request), count)
        if backpressure:
            assert server.response_release.wait(4), "client never reached native read retry"
        response = bytes(byte ^ 90 for byte in request)
        if ending == "truncated":
            connection.cut_record(response[:16384], 7)
        else:
            connection.write(response, chunk=293)
            if ending == "abrupt":
                connection.abrupt_eof()
            else:
                connection.shutdown()
    return handler


def invoke(server, *, identity="localhost", ip=False, mode=0, count=0,
           layout=0, maximum=100000, trust="root"):
    command = [
        str(EXECUTABLE), server.address, str(CERTIFICATES / f"{trust}.pem"),
        identity, str(int(ip)), str(mode), str(count), str(layout), str(maximum),
    ]
    if mode == 4:
        # The server deliberately withholds reads until the native client has
        # observed WANT_WRITE and rejected unrelated pending operations.
        process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        signals = []
        def release():
            signal = process.stderr.readline(16)
            signals.append(signal)
            if signal == b"W\n":
                server.release.set()
                signal = process.stderr.readline(16)
                signals.append(signal)
                if signal == b"R\n":
                    server.response_release.set()
        observer = threading.Thread(target=release, daemon=True)
        observer.start()
        try:
            status = process.wait(timeout=7)
        except BaseException:
            process.kill()
            process.wait(timeout=1)
            raise
        finally:
            observer.join(1)
        assert not observer.is_alive(), "WANT_WRITE notification observer did not stop"
        output = process.stdout.read(4096)
        errors = process.stderr.read(4096)
        assert signals == [b"W\n", b"R\n"], (signals, status, output, errors)
    else:
        result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=7)
        status, output, errors = result.returncode, result.stdout, result.stderr
    assert status == 0 and not errors and len(output) == 120, (command, status, output, errors)
    return struct.unpack("<15Q", output)


def case(*, certificate="valid", identity="localhost", ip=False, mode=0,
         count=0, layout=0, maximum=100000, trust="root", version=None,
         no_certificate=False, ending="clean", fragment=0, failure=False,
         ipv6=False, handler=None):
    global CASES
    configuration = context(CERTIFICATES, certificate, version, no_certificate)
    if handler is None:
        handler = handshake_only if mode in (0, 8) else exchange(count, ending, mode == 4)
    with Server(configuration, handler, fragment=fragment, expect_failure=failure,
                receive_buffer=32768 if mode == 4 else None, ipv6=ipv6) as server:
        observed = invoke(server, identity=identity, ip=ip, mode=mode, count=count,
                          layout=layout, maximum=maximum, trust=trust)
        assert server.connected, "client did not connect to the explicit loopback endpoint"
    CASES += 1
    return observed, server


def successful(observed, count=0):
    assert observed[0:5] == (0, 0, 0, 0, 0), observed
    assert observed[7:9] == (count, count), observed
    assert observed[10] == 1 and observed[11] == 5, observed  # complete shutdown and Closed
    assert observed[5] > 0, "nonblocking client must expose WANT_READ, including dirty-queue retries"


def matrix():
    for index, count in enumerate((0, 1, 255, 1024, 1025, 16384, 16385, 65536)):
        observed, server = case(mode=1, count=count, layout=index % 3, fragment=1 if count == 255 else 0)
        successful(observed, count)
        assert server.names == ["localhost"], server.names
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        observed, server = case(mode=1, count=1025, layout=1, version=version)
        successful(observed, 1025)
        assert server.version == ("TLSv1.2" if version == ssl.TLSVersion.TLSv1_2 else "TLSv1.3")
    for identity, ip, certificate in (
        ("fixture.test", False, "chain-full"),
        ("127.0.0.1", True, "valid"),
        ("::1", True, "chain-full"),
    ):
        observed, server = case(mode=1, count=769, layout=2, identity=identity, ip=ip,
                                certificate=certificate, ipv6=identity == "::1")
        successful(observed, 769)
        assert server.names == [None if ip else identity], server.names
    observed, _ = case(mode=6, count=4097, layout=1)
    successful(observed, 4097)  # context owner destroyed before handshake; SSL retained its native reference
    observed, _ = case(mode=8)
    successful(observed)
    print(f"openssl-tls verified matrix cases={CASES}")


def verification():
    for options, verification_code in (
        ({"trust": "untrusted"}, 20),
        ({"identity": "wrong.invalid"}, 62),
        ({"identity": "127.0.0.2", "ip": True}, 64),
        ({"certificate": "expired"}, 10),
        ({"certificate": "chain"}, 20),
        ({"certificate": "wrong-purpose"}, 26),
        ({"certificate": "cn-only"}, 62),
    ):
        observed, _ = case(failure=True, **options)
        assert observed[0] == 1 and observed[1] == 11 and observed[2] == verification_code, (options, observed)
        assert observed[4] != 0 and observed[7:11] == (0, 0, 0, 0) and observed[11] == 6, (options, observed)
    for options in ({"version": ssl.TLSVersion.TLSv1_1}, {"no_certificate": True}):
        observed, _ = case(failure=True, **options)
        assert observed[0] == 1 and observed[1] in (10, 12) and observed[11] == 6, (options, observed)
        assert observed[7:11] == (0, 0, 0, 0), observed
    print(f"openssl-tls mandatory identity/trust/protocol rejection cases={CASES}")


def endings():
    for ending, mode in (("clean", 1), ("abrupt", 2), ("truncated", 3)):
        for count in (1, 1025):
            observed, _ = case(mode=mode, count=count, layout=1, ending=ending, fragment=7)
            if ending == "clean":
                successful(observed, count)
            else:
                assert observed[0] == 2 and observed[1] == 14 and observed[11] == 6, (ending, observed)
                assert observed[8] == (0 if ending == "truncated" else count), observed
                assert observed[9:11] == (0, 0), "fatal EOF must not call shutdown"
    observed, _ = case(mode=0)
    successful(observed)
    assert observed[9] == 1, "initial shutdown must expose successfully sent/incomplete state"
    print(f"openssl-tls authenticated close, abrupt EOF and truncated native record cases={CASES}")


def retries():
    observed, _ = case(mode=4, count=524288, layout=1)
    successful(observed, 524288)
    assert observed[6] > 0 and observed[13] > 0, observed
    assert observed[14] > 0, "read retry must retain requested size and permit destination changes"

    def stalled(_connection, server):
        assert server.stop.wait(5), "bounded client did not stop its stalled handshake"
    observed, _ = case(mode=5, maximum=1, handler=stalled)
    assert observed[0] == 3 and observed[5] == 1 and observed[12] == 1, observed
    assert observed[7:11] == (0, 0, 0, 0), observed

    def closed(connection, server):
        handshake(connection, server)
        connection.abrupt_eof()
    observed, _ = case(mode=7, count=65536, layout=1, handler=closed, failure=True)
    assert observed[0] in (2, 4) and observed[1] in (10, 14) and observed[11] == 6, observed
    assert observed[9:11] == (0, 0), observed
    print(f"openssl-tls stable write retry, bounded poll, dirty queue and native ownership cases={CASES}")


if __name__ == "__main__":
    group, executable, certificates = sys.argv[1:]
    EXECUTABLE = Path(executable).resolve()
    CERTIFICATES = Path(certificates).resolve()
    {"matrix": matrix, "verification": verification, "endings": endings, "retries": retries}[group]()
