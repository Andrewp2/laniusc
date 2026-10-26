"""Native TLS server closure experiment. Python/OpenSSL creates every record."""
import http.client
import importlib.util
import io
from pathlib import Path
import select
import socket
import ssl
import struct
import subprocess
import sys

sys.dont_write_bytecode = True
BASE = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("server_shutdown_client", BASE / "openssl_tls_server" / "client.py")
CLIENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CLIENT)
EXE = None
CERTS = None
CASES = 0
HEAD = b"HTTP/1.1 413 Content Too Large\r\nContent-Length: 65536\r\nConnection: close\r\n\r\n"
FIELDS = ("mode", "version", "sent", "drained", "local_notify", "peer_eof", "outcome",
          "stage", "cause", "phase", "ssl_error", "native_code", "system", "checks",
          "write_wants", "steps", "quiesced", "stable_write_retries", "context_owners",
          "session_owners", "invalid_frees", "fd_checked", "shutdown_calls",
          "stable_read_retries", "real_write_wants")
MODES = ("alert-before-queued-tail", "alert-before-late-tail", "drain-before-alert",
         "alert-before-missing-peer-alert", "drain-before-missing-peer-alert", "alert-before-abrupt-eof")


def marker(process, expected):
    ready, _, _ = select.select([process.stderr], [], [], 4)
    assert ready, ("missing product phase", expected, process.poll())
    actual = process.stderr.readline(16)
    assert actual == expected, ("wrong product phase", expected, actual, process.poll())


def parse_response(wire):
    class CapturedSocket:
        def makefile(self, *_args, **_kwargs):
            return io.BytesIO(wire)
    response = http.client.HTTPResponse(CapturedSocket())
    response.begin()
    assert response.status == 413 and response.version == 11
    assert response.getheader("Content-Length") == "65536"
    assert response.getheader("Connection") == "close"
    body = response.read()
    assert len(body) == 65536 and body == bytes((i * 73 + 11) & 255 for i in range(65536))
    assert response.isclosed() and len(wire) == len(HEAD) + len(body)


def native_reason(error, expected):
    return isinstance(error, ssl.SSLError) and error.library == "SSL" and error.reason == expected


def validate(report, peer, mode):
    assert report["mode"] == mode and report["version"] == peer["version"], (report, peer)
    assert report["sent"] == len(HEAD) + 65536 and peer["response_bytes"] == report["sent"], (report, peer)
    assert report["write_wants"] > 0 and report["real_write_wants"] > 0 and report["stable_write_retries"] > 0, report
    assert report["checks"] > 1 and 0 < report["steps"] < 20000, report
    assert [report[key] for key in ("context_owners", "session_owners", "invalid_frees", "fd_checked")] == [0, 0, 0, 1], report
    if mode in (0, 1):
        assert peer["server_alert_authenticated"], (report, peer)
        assert report["local_notify"] == 1 and report["quiesced"] == 1, report
        if report["outcome"] == 0:
            assert report["peer_eof"] == 1 and report["stage"] == 5, report
            assert report["cause"] == report["native_code"] == report["system"] == 0, report
            if peer["tail_confirmed"] == 257:
                assert report["drained"] == 257, (report, peer)
            else:
                # A native client restriction is reported distinctly from a
                # write timeout or transport failure, and no sent bytes claimed.
                assert peer["tail_confirmed"] == 0 and report["drained"] == 0, (report, peer)
                assert native_reason(peer["tail_error"], "PROTOCOL_IS_SHUTDOWN"), (report, peer)
        else:
            # The one admitted protocol restriction has an exact native SSL
            # reason, operation and terminal state. An arbitrary error/timeout
            # cannot turn this observational experiment into a passing case.
            code = report["native_code"]
            assert report["outcome"] == 1 and report["stage"] == 4 and report["cause"] == 10, (report, peer)
            assert report["phase"] == 8 and report["ssl_error"] == 1, report
            assert not code & 0x80000000 and (code >> 23) & 255 == 20 and code & 0x7fffff == 291, report
            assert report["peer_eof"] == 0 and peer["tail_confirmed"] == 257, (report, peer)
    elif mode == 2:
        assert report["outcome"] == 0 and report["stage"] == 5 and report["drained"] == 257, report
        assert report["local_notify"] == report["peer_eof"] == 1 and report["quiesced"] == 0, report
        assert peer["tail_confirmed"] == 257 and peer["shutdown_complete"], (report, peer)
    elif mode in (3, 4):
        assert report["outcome"] == 2 and report["stage"] == 4 and report["peer_eof"] == 0, report
        assert report["cause"] == report["native_code"] == report["system"] == 0, report
        assert report["local_notify"] == (1 if mode == 3 else 0), report
        assert report["drained"] == (0 if mode == 3 else 257), report
    else:
        assert report["outcome"] == 1 and report["stage"] == 4 and report["cause"] == 14, report
        assert report["phase"] == 8 and report["peer_eof"] == 0 and report["local_notify"] == 1, report
        assert report["drained"] == 0 and peer["abrupt_eof"], (report, peer)


def invoke(mode, version):
    global CASES
    parent, inherited = socket.socketpair()
    inherited.setblocking(False)
    inherited.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
    parent.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4096)
    assert inherited.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF) <= 16384
    assert parent.getsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF) <= 16384
    command = [str(EXE), str(inherited.fileno()), str(CERTS / "valid.pem"),
               str(CERTS / "valid.key"), str(mode)]
    process = subprocess.Popen(command, pass_fds=(inherited.fileno(),), stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    inherited.close()
    peer = {"version": 772 if version == ssl.TLSVersion.TLSv1_3 else 771,
            "response_bytes": 0, "server_alert_authenticated": False,
            "tail_confirmed": 0, "tail_error": None, "shutdown_complete": False,
            "shutdown_error": None, "abrupt_eof": False}
    try:
        client = CLIENT.Client(parent, CLIENT.context(CERTS, version=version))
        client.handshake()
        assert client.tls.getpeercert() and client.tls.version() == ("TLSv1.3" if peer["version"] == 772 else "TLSv1.2")
        client.write(b"Q")
        # Do not read even one response byte until genuine native backpressure.
        marker(process, b"W\n")
        wire = client.read_exact(len(HEAD) + 65536)
        parse_response(wire)
        peer["response_bytes"] = len(wire)
        marker(process, b"F\n")
        process.stdin.write(b"G")
        process.stdin.flush()
        tail = bytes((i * 31 + 7) & 255 for i in range(257))
        if mode in (2, 4):
            client.write(tail)
            peer["tail_confirmed"] = len(tail)
            if mode == 2:
                client.shutdown()
                peer["shutdown_complete"] = True
                peer["server_alert_authenticated"] = True
                marker(process, b"N\n")
        else:
            marker(process, b"N\n")
            if mode == 5:
                client.abrupt_eof()
                peer["abrupt_eof"] = True
            elif mode in (0, 1):
                if mode == 1:
                    assert client.read() == b""
                    peer["server_alert_authenticated"] = True
                try:
                    client.write(tail)
                    peer["tail_confirmed"] = len(tail)
                except ssl.SSLError as error:
                    peer["tail_error"] = error
                if mode == 0:
                    assert client.read() == b""
                    peer["server_alert_authenticated"] = True
                try:
                    client.shutdown()
                    peer["shutdown_complete"] = True
                except (ssl.SSLError, OSError) as error:
                    peer["shutdown_error"] = error
            # Mode3 deliberately keeps the peer transport live without reading
            # the server alert or invoking a native operation that could reply.
        process.stdin.close()
        process.stdin = None
        out, err = process.communicate(timeout=6)
        assert process.returncode == 0 and len(out) == 256 and err == b"", (command, process.returncode, out, err, peer)
        values = struct.unpack("<32Q", out)
        report = dict(zip(FIELDS, values))
        readable_peer = {key: repr(value) if isinstance(value, BaseException) else value for key, value in peer.items()}
        print(f"server-shutdown {version.name} {MODES[mode]} report={report} peer={readable_peer}", flush=True)
        validate(report, peer, mode)
        CASES += 1
    finally:
        parent.close()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=1)
        if process.stdin is not None:
            process.stdin.close()
        process.stdout.close()
        process.stderr.close()


def group(modes):
    for version in (ssl.TLSVersion.TLSv1_2, ssl.TLSVersion.TLSv1_3):
        for mode in modes:
            invoke(mode, version)


if __name__ == "__main__":
    name, executable, certificates = sys.argv[1:]
    EXE, CERTS = Path(executable).resolve(), Path(certificates).resolve()
    group({"alert": (0, 1), "drain": (2,), "deadline": (3, 4), "truncation": (5,)}[name])
    print(f"openssl-tls-server-shutdown {name} cases={CASES}")
