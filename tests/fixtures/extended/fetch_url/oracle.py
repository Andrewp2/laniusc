"""Functional URL fetch oracle; independent HTTP/OpenSSL peers, test only.

This first increment claims no source allocation/fd cleanup ledger. Full traces
are used narrowly for preflight network absence and an actual closed-reader
EPIPE, not as an allocation-ownership verifier.
"""
import importlib.util
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time

import h11

HERE = Path(__file__).resolve().parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

HTTP = load("fetch_url_shared_plain_peers", HERE.parent / "fetch_many/peers.py")
TLS = load("fetch_url_shared_openssl_peer", HERE.parent / "openssl_tls/peer.py")
CERTS = load("fetch_url_shared_certificates", HERE.parent / "openssl_tls/certificates.py")
BINARY = bytes(range(256)) * 4 + b"\x00\xff\r\n"
HELP = (b"Usage: fetch URL [OPTIONS]\n"
        b"Options: --method METHOD --header NAME:VALUE --body FILE --ca-file FILE\n"
        b"         --client-cert CHAIN --client-key KEY --timeout MS --connect-timeout MS\n"
        b"         --max-output N --max-request N --max-response N --max-body N\n"
        b"         --max-work N --max-io N --max-tls N --max-socket-calls N\n"
        b"         --max-attempts N --max-results N --max-stdout-calls N --max-body-calls N\n"
        b"         --help, -h\n")
REASONS = {
    "arguments": b"fetch: invalid arguments\n", "url": b"fetch: invalid URL\n",
    "request": b"fetch: invalid request\n", "configuration": b"fetch: invalid configuration\n",
    "limit": b"fetch: limit exceeded\n", "timeout": b"fetch: timeout\n",
    "input": b"fetch: body file I/O failed\n", "output": b"fetch: output I/O or call limit failed\n",
    "verify": b"fetch: certificate verification failed\n", "tls": b"fetch: TLS operation failed\n",
    "response": b"fetch: invalid or incomplete HTTP response\n",
}
NETWORK = re.compile(r"\b(?:socket|socketpair|connect|sendto|sendmsg|recvfrom|recvmsg)\(")

def request(read):
    """h11 validates independent wire framing; no production request parser."""
    parser = h11.Connection(h11.SERVER)
    head, body, total = None, bytearray(), 0
    for _ in range(4096):
        event = parser.next_event()
        if event is h11.NEED_DATA:
            data = read(1024)
            if not data:
                raise EOFError("fetch closed before complete request")
            total += len(data)
            assert total <= 131072, total
            parser.receive_data(data)
        elif isinstance(event, h11.Request):
            head = event
        elif isinstance(event, h11.Data):
            body.extend(event.data)
        elif isinstance(event, h11.EndOfMessage):
            assert head is not None
            return head, bytes(body)
        else:
            raise AssertionError(event)
    raise AssertionError("fixture request bound")

def verify(head, body, *, method, target, authority, upload, headers):
    assert (head.method, head.target, head.http_version) == (method, target, b"1.1"), head
    fields = list(head.headers)
    assert [v for k, v in fields if k == b"host"] == [authority], fields
    assert [v for k, v in fields if k == b"connection"] == [b"close"], fields
    assert [v for k, v in fields if k == b"content-length"] == [str(len(upload)).encode()], fields
    assert body == upload, (len(body), len(upload), body[:64])
    for key, values in headers.items():
        assert [v for k, v in fields if k == key] == values, (key, fields)

class Plain(HTTP.Server):
    """Reuse the existing listener/thread/release lifecycle; admit POST bodies."""
    def __init__(self, wire, check, *, failure=False, delayed=False):
        super().__init__({}, allow_abort=failure)
        self.wire, self.check, self.delayed = wire, check, delayed
        self.progress = []

    def handle(self, connection):
        try:
            connection.settimeout(2)
            head, body = request(connection.recv)
            self.check(head, body)
            with self.condition:
                self.records.append((head, body))
            if self.delayed:
                if self.stop.wait(.22):
                    return
                connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\na")
                self.progress.append("first")
                if self.stop.wait(.30):
                    return
                connection.sendall(b"b")
                self.progress.append("second")
            else:
                connection.sendall(self.wire)
        except (OSError, EOFError, h11.RemoteProtocolError) as error:
            if not self.allow_abort and not self.stop.is_set():
                self.errors.append(error)
        except BaseException as error:
            self.errors.append(error)
        finally:
            with self.condition:
                self.connections.discard(connection)
            connection.close()

class Runner:
    def __init__(self, executable, mode):
        self.exe = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"fetch-url-{mode}-"))
        self.count, self.names = 0, set()

    def run(self, name, arguments, *, status=0, stdout=b"", reason=None,
            trace=False, no_network=False, output=None, data=None, environment=None):
        assert name not in self.names, name
        self.names.add(name)
        self.count += 1
        stem = self.directory / f"{self.count:02d}-{name}"
        command = [self.exe, *map(os.fspath, arguments)]
        if trace:
            command = ["strace", "-qq", "-f", "-s", "512", "-e", "trace=all", "-o", str(stem)+".trace", "--", *command]
        (Path(str(stem)+".command")).write_text(repr(command)+"\n")
        kwargs = dict(stdout=subprocess.PIPE if output is None else output,
                      stderr=subprocess.PIPE, cwd=self.directory, timeout=6,
                      env=environment)
        if data is None:
            kwargs["stdin"] = subprocess.DEVNULL
        else:
            kwargs["input"] = data
        started = time.monotonic()
        result = subprocess.run(command, **kwargs)
        elapsed = time.monotonic()-started
        Path(str(stem)+".stdout").write_bytes(result.stdout or b"")
        Path(str(stem)+".stderr").write_bytes(result.stderr)
        assert result.returncode == status, (name, status, result, stem)
        if output is None:
            assert result.stdout == stdout, (name, len(result.stdout), stdout[:64], result, stem)
        expected_error = b"" if reason is None else REASONS[reason]
        assert result.stderr == expected_error, (name, expected_error, result, stem)
        text = Path(str(stem)+".trace").read_text() if trace else ""
        if no_network:
            assert trace and not NETWORK.search(text), (name, text)
        return result, elapsed, text

    def plain(self, name, *, wire=None, expected=BINARY, status=0, reason=None,
              args=(), method=b"GET", upload=b"", headers=None, suffix="/bytes?q=x",
              target=None, zero_port=False, delayed=False, output=None, trace=False, data=None, before=()):
        check = lambda head, body: verify(head, body, method=method,
            target=target if target is not None else suffix.split("#", 1)[0].encode() or b"/",
            authority=authority.encode(), upload=upload, headers=headers or {})
        with Plain(HTTP.fixed(BINARY) if wire is None else wire, check,
                   failure=status != 0, delayed=delayed) as peer:
            port = peer.socket.getsockname()[1]
            authority = f"127.0.0.1:{'0' if zero_port else ''}{port}"
            url = f"http://{authority}{suffix}"
            result, elapsed, text = self.run(name, [*before, url, "--timeout", "2000", *args],
                status=status, stdout=expected, reason=reason, output=output, trace=trace, data=data)
            if status == 0 or delayed or status == 5:
                assert len(peer.records) == 1, (name, peer.records)
            if delayed:
                assert peer.progress == ["first"], (name, peer.progress, elapsed)
            return result, elapsed, text


def plain(runner):
    r = runner
    r.plain("target-authority-fragment", suffix="/a//./b%2Fc?q=%00&x=#ignored", zero_port=True)
    r.plain("default-path", suffix="#discarded", target=b"/")
    r.plain("empty-query", suffix="?#discarded", target=b"/?")
    for status in (404, 500):
        r.plain(f"status-{status}", wire=HTTP.fixed(BINARY, status))
    r.plain("chunked-binary", wire=HTTP.chunked(BINARY))
    r.plain("close-delimited", wire=b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n"+BINARY)
    r.plain("no-content", wire=b"HTTP/1.1 204 Empty\r\nConnection: close\r\n\r\n", expected=b"")
    r.plain("head", wire=b"HTTP/1.1 200 OK\r\nContent-Length: 999\r\nConnection: close\r\n\r\n", method=b"HEAD", args=["--method", "HEAD"], expected=b"")
    body = r.directory / "payload.bin"
    body.write_bytes(BINARY)
    r.plain("post-file-and-headers", method=b"POST", upload=BINARY,
        args=["--method=POST", "--body", body, "--header", "X-Value:first", "--header", "X-Value:second", "--header", "X-Empty:"],
        headers={b"x-value": [b"first", b"second"], b"x-empty": [b""]})
    (r.directory / "-").write_bytes(b"file-not-stdin\x00\xff")
    r.plain("dash-is-file", upload=b"file-not-stdin\x00\xff", args=["--body", "-"], data=b"unused stdin")
    empty = r.directory / "empty.bin"
    empty.write_bytes(b"")
    r.plain("empty-upload", method=b"POST", args=["--method", "POST", "--body", empty])
    r.plain("last-scalar-wins", before=["--method", "POST"], args=["--method", "GET"])
    for cap, status in ((3, 0), (2, 3)):
        r.plain(f"output-{cap}", wire=HTTP.fixed(b"abc"), args=["--max-output", str(cap)], expected=b"abc" if status == 0 else b"", status=status, reason=None if status == 0 else "limit")
    r.plain("decoded-body-limit", wire=HTTP.fixed(b"abc"), args=["--max-body", "2"], expected=b"", status=3, reason="limit")
    wire = HTTP.fixed(b"abc")
    for cap, status in ((len(wire), 0), (len(wire)-1, 3)):
        r.plain(f"response-{cap}", wire=wire, args=["--max-response", str(cap)], expected=b"abc" if status == 0 else b"", status=status, reason=None if status == 0 else "limit")
    r.plain("stdout-no-calls", args=["--max-stdout-calls", "0"], expected=b"", status=5, reason="output")
    r.plain("empty-zero-output-calls", wire=HTTP.fixed(b""), args=["--max-output", "0", "--max-stdout-calls", "0"], expected=b"")
    r.plain("stdout-confirmed-prefix", args=["--max-stdout-calls", "1"], expected=BINARY[:1024], status=5, reason="output")
    r.plain("original-deadline", args=["--timeout", "400"], expected=b"", status=3, reason="timeout", delayed=True)
    read_end, write_end = os.pipe()
    os.close(read_end)
    try:
        _, _, text = r.plain("closed-reader", status=5, reason="output", output=write_end, trace=True)
        assert re.search(r"write\(1,.*= -1 EPIPE", text), text
        assert "SIG_IGN" in text, text
    finally:
        os.close(write_end)
    body.write_bytes(b"abc")
    r.plain("body-file-exact-eof", args=["--body", body, "--max-body", "3"], upload=b"abc", wire=HTTP.fixed(b"abc"), expected=b"abc")


def preflight(r):
    bad = [
        ("no-url", [], "arguments"), ("unknown", ["--help", "--unknown"], "arguments"),
        ("missing-option-value", ["--method"], "arguments"), ("extra-url", ["http://127.0.0.1:9/", "extra"], "arguments"),
        ("bad-port", ["http://127.0.0.1:0/"], "url"), ("legacy-numeric", ["http://127.1/"], "url"),
        ("userinfo", ["http://user@127.0.0.1:9/"], "url"), ("bad-scheme", ["ftp://127.0.0.1:9/"], "url"),
        ("bad-header", ["http://127.0.0.1:9/", "--header", "no-colon"], "arguments"),
    ]
    url = "http://127.0.0.1:9/"
    for name, options, reason in [
        ("bad-method", ["--method", "BAD METHOD"], "request"),
        ("connect-method", ["--method", "CONNECT"], "request"),
        ("host-override", ["--header", "Host:other"], "request"),
        ("header-injection", ["--header", "X:a\r\nInjected:b"], "request"),
        ("tls-ca-on-http", ["--ca-file", "does-not-exist", "--body", "tls-rejected-body"], "arguments"),
        ("tls-calls-on-http", ["--max-tls", "1"], "arguments"),
        ("unpaired-credentials", ["--client-cert", "does-not-exist"], "arguments"),
        ("zero-connect-timeout", ["--connect-timeout", "0"], "configuration"),
        ("too-many-results", ["--max-results", "4097"], "configuration"),
        ("zero-attempts", ["--max-attempts", "0"], "configuration"),
        ("zero-http-io", ["--max-io", "0"], "configuration"),
        ("bad-number", ["--max-output", "-1"], "arguments"),
        ("overflow-number", ["--max-work", "18446744073709551616"], "arguments"),
    ]:
        bad.append((name, [url, *options], reason))
    for name, arguments, reason in bad:
        _, _, text = r.run(name, arguments, status=2, reason=reason, trace=True, no_network=True)
        if name == "tls-ca-on-http":
            assert not re.search(r"(?:open|openat)\([^\n]*(?:does-not-exist|tls-rejected-body)", text), text
    for name, options, reason in [
        ("zero-timeout", ["--timeout", "0"], "timeout"),
        ("zero-socket-calls", ["--max-socket-calls", "0"], "limit"),
        ("request-cap", ["--max-request", "0"], "limit"),
        ("work-cap", ["--max-work", "0"], "limit"),
        ("missing-body", ["--body", "does-not-exist"], "input"),
        ("body-call-admission", ["--body", "does-not-exist", "--max-body-calls", "3"], "limit"),
    ]:
        r.run(name, [url, *options], status=3, reason=reason, trace=True, no_network=True)
    body = r.directory / "too-large.bin"
    body.write_bytes(b"abc")
    r.run("body-byte-cap", [url, "--body", body, "--max-body", "2"], status=3, reason="limit", trace=True, no_network=True)
    for name, options in (("help", ["--help"]), ("short-help", ["-h"]),
                          ("help-does-not-open-files", [url, "--help", "--body", "help-body-missing", "--ca-file", "help-ca-missing"])):
        _, _, text = r.run(name, options, stdout=HELP, trace=True, no_network=True)
        assert not re.search(r"(?:open|openat)\([^\n]*(?:help-body-missing|help-ca-missing)", text), text
    r.run("help-output-budget", ["--help", "--max-stdout-calls", "0"], status=5, reason="output")


def tls(r):
    directory = r.directory / "certificates"
    CERTS.generate(directory)
    for name, identity, options, status, reason in [
        ("dns-ca", "localhost", (), 0, None),
        ("ip-san", "127.0.0.1", (), 0, None),
        ("untrusted-ca", "localhost", ("--ca-file", directory / "untrusted.pem"), 3, "verify"),
        ("default-ca-rejects-private", "localhost", (), 3, "verify"),
    ]:
        seen = []
        def handler(connection, server):
            TLS.handshake(connection, server)
            head, body = request(connection.read)
            authority = f"{identity}:{server.listener.getsockname()[1]}".encode()
            verify(head, body, method=b"GET", target=b"/tls?q=%2F", authority=authority, upload=b"", headers={})
            seen.append(True)
            connection.write(HTTP.fixed(BINARY))
            connection.shutdown()
        with TLS.Server(TLS.context(directory), handler, expect_failure=status != 0) as peer:
            port = peer.listener.getsockname()[1]
            arguments = [f"https://{identity}:{port}/tls?q=%2F#discarded", "--timeout", "2000"]
            if name != "default-ca-rejects-private":
                arguments += ["--ca-file", directory / "root.pem"]
            arguments += list(options)
            environment = None
            if name == "default-ca-rejects-private":
                environment = dict(os.environ, SSL_CERT_FILE=str(directory / "untrusted.pem"), SSL_CERT_DIR=str(directory / "empty-trust"))
                (directory / "empty-trust").mkdir()
            r.run(name, arguments, status=status, reason=reason, stdout=BINARY if status == 0 else b"", environment=environment)
            if status == 0:
                assert seen and peer.authenticated and peer.names == ["localhost" if identity == "localhost" else None], (name, seen, peer.names)


def controls():
    assert len(HELP) == 417
    assert NETWORK.search('123 connect(4, ...) = 0')
    assert not NETWORK.search('123 write(2, "connection failed", 17) = 17')
    wire = iter([b"POST /x?q=%2F HTTP/1.1\r\nHost: Example:0080\r\nConnection: close\r\nContent-Length: 4\r\nX-A: one\r\nX-A: two\r\n\r\n\x00\xff\r\n"])
    head, body = request(lambda count: next(wire, b""))
    verify(head, body, method=b"POST", target=b"/x?q=%2F", authority=b"Example:0080", upload=b"\x00\xff\r\n", headers={b"x-a": [b"one", b"two"]})
    for change in (dict(target=b"/wrong"), dict(authority=b"other"), dict(upload=b"xxxx"), dict(headers={b"x-a": [b"two", b"one"]})):
        expected = dict(method=b"POST", target=b"/x?q=%2F", authority=b"Example:0080", upload=b"\x00\xff\r\n", headers={b"x-a": [b"one", b"two"]})
        expected.update(change)
        try:
            verify(head, body, **expected)
        except AssertionError:
            pass
        else:
            raise AssertionError(("mutation accepted", change))
    print("fetch-url CPU controls=7")

if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"plain": plain, "preflight": preflight, "tls": tls}[mode](runner)
        print(f"fetch-url-{mode} cases={runner.count} evidence={runner.directory}")
