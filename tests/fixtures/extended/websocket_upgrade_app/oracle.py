"""Functional offline-upgrade oracle. No source-resource tracing is claimed.

The executable performs the handshake in Lanius and OpenSSL. This test checks
its wire output with Python's HTTP parser and established hash/Base64 modules.
Random nonce inputs and every result are retained for reproduction.
"""

import base64
import hashlib
import http.client
import io
import os
from pathlib import Path
import secrets
import subprocess
import sys
import tempfile

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
SAMPLE = b"dGhlIHNhbXBsZSBub25jZQ=="
HELP = (
    b"Usage: websocket-upgrade [--protocol TOKEN] [--help]\n"
    b"Read one HTTP upgrade request from stdin through EOF; write its HTTP 101 response.\n"
    b"The selected protocol must be offered exactly; no option declines all protocols.\n"
    b"Limits: 16384 input/head bytes, 4096 line bytes, 64 headers, 32 offered protocols.\n"
)
DIAGNOSTICS = {
    2: b"websocket-upgrade: invalid arguments or handshake\n",
    3: b"websocket-upgrade: input or OpenSSL operation failed\n",
    4: b"websocket-upgrade: allocation failed\n",
    5: b"websocket-upgrade: output failed\n",
}


def request(key=SAMPLE, extra=b""):
    return (
        b"GET /chat?room=1 HTTP/1.1\r\nHost: example.test\r\n"
        b"Upgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: "
        + key + b"\r\nSec-WebSocket-Version: 13\r\n" + extra + b"\r\n"
    )


def padded_request(size):
    """Reach the total-input boundary while staying within each line limit."""
    wire = request()[:-2]
    remaining = size - len(wire) - 2
    assert remaining >= 9
    while remaining:
        count = min(4098, remaining)  # 4096 content bytes plus CRLF.
        if 0 < remaining - count < 9:
            count -= 9 - (remaining - count)
        assert 9 <= count <= 4098
        wire += b"X-Pad: " + b"a" * (count - 9) + b"\r\n"
        remaining -= count
    wire += b"\r\n"
    assert len(wire) == size
    return wire


class SocketBytes:
    def __init__(self, wire):
        self.stream = io.BytesIO(wire)

    def makefile(self, *args, **kwargs):
        return self.stream


def check_response(wire, key, protocol=None):
    # A body, extra frame or second response would violate this tool's output.
    assert wire.endswith(b"\r\n\r\n") and wire.count(b"\r\n\r\n") == 1, wire
    assert b"\n" not in wire.replace(b"\r\n", b""), wire
    parsed = http.client.HTTPResponse(SocketBytes(wire))
    parsed.begin()
    assert (parsed.version, parsed.status) == (11, 101), wire
    fields = parsed.headers
    expected = {"upgrade", "connection", "sec-websocket-accept"}
    if protocol is not None:
        expected.add("sec-websocket-protocol")
    assert {name.lower() for name in fields.keys()} == expected, wire
    for name in expected:
        assert len(fields.get_all(name)) == 1, (name, wire)
    assert fields["Upgrade"].lower() == "websocket", wire
    assert fields["Connection"].lower() == "upgrade", wire
    accept = base64.b64encode(hashlib.sha1(key + GUID, usedforsecurity=False).digest())
    assert fields["Sec-WebSocket-Accept"].encode("ascii") == accept, wire
    if protocol is not None:
        assert fields["Sec-WebSocket-Protocol"].encode("ascii") == protocol, wire
    assert parsed.read() == b"", wire


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"websocket-upgrade-{mode}-"))
        self.count = 0
        self.names = set()

    def run(self, name, data, arguments=(), status=0, protocol=None, key=SAMPLE,
            help_output=False, closed_output=False, closed_error=False,
            directory_input=False):
        assert name not in self.names, name
        self.names.add(name)
        self.count += 1
        stem = self.directory / f"{self.count:02d}-{name}"
        Path(str(stem) + ".input").write_bytes(data)
        # repr preserves arbitrary argv bytes; this is diagnostic text only.
        command = [self.executable, *arguments]
        Path(str(stem) + ".command").write_text(repr(command) + "\n")
        reader = writer = input_file = None
        error_reader = error_writer = None
        try:
            kwargs = dict(stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          cwd=self.directory, timeout=4)
            if closed_output:
                reader, writer = os.pipe()
                os.close(reader)
                reader = None
                kwargs["stdout"] = writer
            if closed_error:
                error_reader, error_writer = os.pipe()
                os.close(error_reader)
                error_reader = None
                kwargs["stderr"] = error_writer
            if directory_input:
                input_file = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
                kwargs["stdin"] = input_file
            else:
                kwargs["input"] = data
            result = subprocess.run(command, **kwargs)
        finally:
            for descriptor in (reader, writer, input_file, error_reader, error_writer):
                if descriptor is not None:
                    os.close(descriptor)
        Path(str(stem) + ".stdout").write_bytes(result.stdout or b"")
        Path(str(stem) + ".stderr").write_bytes(result.stderr or b"")
        Path(str(stem) + ".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status, (name, status, result, stem)
        if closed_error:
            assert result.stderr is None
        else:
            assert result.stderr == (b"" if status == 0 else DIAGNOSTICS[status]), (name, result, stem)
        if closed_output:
            assert result.stdout is None
        elif status:
            assert result.stdout == b"", (name, result, stem)
        elif help_output:
            assert result.stdout == HELP, (name, result, stem)
        else:
            check_response(result.stdout, key, protocol)

    def finish(self, mode):
        (self.directory / "cases.txt").write_text("\n".join(sorted(self.names)) + "\n")
        print(f"websocket-upgrade-{mode} cases={self.count} evidence={self.directory}")


def functional(runner):
    runner.run("rfc-sample", request())
    for index in range(8):
        key = base64.b64encode(secrets.token_bytes(16))
        runner.run(f"fresh-key-{index}", request(key), key=key)
    runner.run("header-case-and-ows", request().replace(
        b"Upgrade: websocket", b"uPgRaDe: \tWebSocket \t").replace(
        b"Connection: Upgrade", b"connection: keep-alive, upGRADE"))
    offers = request(extra=b"Sec-WebSocket-Protocol: Chat, chat\r\n")
    runner.run("protocol-upper", offers, ["--protocol", "Chat"], protocol=b"Chat")
    runner.run("protocol-lower", offers, ["--protocol=chat"], protocol=b"chat")
    runner.run("protocol-declined", offers)
    runner.run("protocol-split-fields", request(extra=(
        b"Sec-WebSocket-Protocol: first\r\nSec-WebSocket-Protocol: second\r\n")),
        ["--protocol", "second"], protocol=b"second")
    token = b"!#$%&'*+-.^_`|~"
    runner.run("token-punctuation", request(extra=b"Sec-WebSocket-Protocol: " + token + b"\r\n"),
               ["--protocol", token.decode("ascii")], protocol=token)
    token = b"p" * 256
    runner.run("protocol-256", request(extra=b"Sec-WebSocket-Protocol: " + token + b"\r\n"),
               ["--protocol", token.decode("ascii")], protocol=token)
    runner.run("extensions-declined", request(extra=(
        b"Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits\r\n")))
    runner.run("empty-body-declaration", request(extra=b"Content-Length: 0\r\n"))
    # Host, Upgrade, Connection, Key and Version are the five mandatory fields.
    runner.run("headers-64", request(extra=b"X: a\r\n" * 59))
    runner.run("line-4096", request(extra=b"X: " + b"a" * 4093 + b"\r\n"))
    runner.run("input-16384", padded_request(16384))
    runner.run("protocol-count-32", request(extra=(
        b"Sec-WebSocket-Protocol: " + b", ".join(f"p{i}".encode() for i in range(32)) + b"\r\n")))


def rejection(runner):
    normal = request()
    cases = {
        "empty": b"", "one-byte": b"G", "incomplete": normal[:-1],
        "bare-lf": normal.replace(b"\r\n", b"\n"),
        "wrong-method": normal.replace(b"GET ", b"POST ", 1),
        "wrong-version": normal.replace(b"HTTP/1.1", b"HTTP/1.0"),
        "missing-host": normal.replace(b"Host: example.test\r\n", b""),
        "duplicate-host": request(extra=b"Host: another.test\r\n"),
        "missing-upgrade": normal.replace(b"Upgrade: websocket\r\n", b""),
        "wrong-connection": normal.replace(b"Connection: Upgrade", b"Connection: close"),
        "missing-key": normal.replace(b"Sec-WebSocket-Key: " + SAMPLE + b"\r\n", b""),
        "bad-key-character": request(SAMPLE.replace(b"d", b"_", 1)),
        "bad-key-padding": request(SAMPLE[:-3] + b"R=="),
        "duplicate-key": request(extra=b"Sec-WebSocket-Key: " + SAMPLE + b"\r\n"),
        "wrong-websocket-version": normal.replace(b"Version: 13", b"Version: 12"),
        "unexpected-accept": request(extra=b"Sec-WebSocket-Accept: surprise\r\n"),
        "nonempty-body": request(extra=b"Content-Length: 1\r\n"),
        "transfer-encoding": request(extra=b"Transfer-Encoding: chunked\r\n"),
        "duplicate-protocol": request(extra=b"Sec-WebSocket-Protocol: chat, chat\r\n"),
        "empty-protocol": request(extra=b"Sec-WebSocket-Protocol:\r\n"),
        "bad-extension": request(extra=b"Sec-WebSocket-Extensions: x; p=\"bad value\"\r\n"),
        "trailing-byte": normal + b"x",
        "trailing-frame": normal + b"\x81\x80\x01\x02\x03\x04",
        "second-request": normal + normal,
        "input-16385": padded_request(16385),
        "line-4097": request(extra=b"X: " + b"a" * 4094 + b"\r\n"),
        "headers-65": request(extra=b"X: a\r\n" * 60),
        "protocol-count-33": request(extra=(
            b"Sec-WebSocket-Protocol: " + b", ".join(f"p{i}".encode() for i in range(33)) + b"\r\n")),
    }
    for name, data in cases.items():
        runner.run(name, data, status=2)
    runner.run("unoffered-protocol", normal, ["--protocol", "chat"], status=2)
    runner.run("protocol-case-mismatch", request(extra=b"Sec-WebSocket-Protocol: chat\r\n"),
               ["--protocol", "Chat"], status=2)


def cli(runner):
    runner.run("long-help", b"malformed", ["--help"], help_output=True)
    runner.run("short-help", b"", ["-h"], help_output=True)
    runner.run("help-with-protocol", b"", ["--protocol", "chat", "--help"], help_output=True)
    runner.run("terminator", request(), ["--"])
    for name, arguments in {
        "operand": ["request.http"], "unknown": ["--unknown"],
        "missing-value": ["--protocol"], "empty-value": ["--protocol="],
        "duplicate": ["--protocol", "chat", "--protocol", "chat"],
        "help-with-value": ["--help=yes"], "help-invalid-tail": ["--help", "operand"],
        "protocol-257": ["--protocol", "p" * 257],
        "count-cap": ["-h"] * 9, "argument-bytes-cap": ["p" * 8193],
        "non-token": ["--protocol", "chat room"],
    }.items():
        runner.run(name, request(), arguments, status=2)


def io_failures(runner):
    runner.run("response-closed-reader", request(), status=5, closed_output=True)
    runner.run("help-closed-reader", b"", ["--help"], status=5, help_output=True, closed_output=True)
    runner.run("stdin-directory", b"", status=3, directory_input=True)
    runner.run("primary-preserved-closed-stderr", b"malformed", status=2, closed_error=True)


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("functional", "rejection", "cli", "io"):
        raise SystemExit("usage: oracle.py {functional|rejection|cli|io} EXECUTABLE")
    mode, executable = sys.argv[1:]
    runner = Runner(executable, mode)
    {"functional": functional, "rejection": rejection, "cli": cli, "io": io_failures}[mode](runner)
    runner.finish(mode)


if __name__ == "__main__":
    main()
