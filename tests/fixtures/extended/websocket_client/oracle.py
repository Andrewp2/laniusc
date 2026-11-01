#!/usr/bin/env python3
"""Loopback oracle for sample_programs/library/ws_cat.lani (ext::websocket_client).

usage: oracle.py GROUP EXE      GROUP: ws, wss or all

The servers are a minimal RFC 6455 implementation on asyncio (the host has no
`websockets` package): plain on 127.0.0.1:0, and TLS with test certificates
generated per run by ../openssl_tls/certificates.py with the openssl CLI.
Each case runs one client script and checks its exact output and exit code,
plus what the server observed: every client frame masked, fresh mask keys,
fragment and opcode sequence, close codes and handshake fields.
Prints: websocket-client-GROUP cases=N frames=F
"""
import asyncio
import base64
import hashlib
import os
import shutil
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "openssl_tls"))
from certificates import generate  # noqa: E402

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
EXE = None
CERTS = None
FRAMES = {"count": 0}


class Failure(Exception):
    pass


def expect(cond, what):
    if not cond:
        raise Failure(what)


def fnv(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xFFFFFFFF
    return "%08x" % h


def esc(data):
    return "".join(chr(b) if 32 < b < 127 and b != 92 else "\\x%02x" % b for b in data)


def line(kind, data):
    out = "%s %d %s" % (kind, len(data), fnv(data))
    return out + (" " + esc(data) if len(data) <= 200 else "")


def gen(text, n):
    return bytes((97 + i % 26) if text else ((i * 73 + 7) % 256) for i in range(n))


def frame(opcode, payload, fin=True, mask=None, rsv=0):
    head = bytes([(0x80 if fin else 0) | rsv | opcode])
    n = len(payload)
    bit = 0x80 if mask is not None else 0
    if n < 126:
        head += bytes([bit | n])
    elif n < 65536:
        head += bytes([bit | 126]) + struct.pack(">H", n)
    else:
        head += bytes([bit | 127]) + struct.pack(">Q", n)
    if mask is not None:
        head += mask
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return head + payload


class Peer:
    """One server-side connection."""

    def __init__(self, reader, writer, record):
        self.reader, self.writer, self.record = reader, writer, record

    async def read_frame(self):
        b0, b1 = await self.reader.readexactly(2)
        n = b1 & 0x7F
        if n == 126:
            n = struct.unpack(">H", await self.reader.readexactly(2))[0]
        elif n == 127:
            n = struct.unpack(">Q", await self.reader.readexactly(8))[0]
        masked = bool(b1 & 0x80)
        key = await self.reader.readexactly(4) if masked else b"\0\0\0\0"
        data = await self.reader.readexactly(n)
        data = bytes(b ^ key[i % 4] for i, b in enumerate(data))
        f = {"fin": bool(b0 & 0x80), "rsv": b0 & 0x70, "opcode": b0 & 0x0F, "masked": masked, "key": key, "data": data}
        self.record["frames"].append(f)
        return f

    async def send(self, raw):
        self.writer.write(raw)
        await self.writer.drain()

    async def message(self):
        """Next data message, answering pings and recording pongs; None at Close."""
        parts, opcode = [], None
        while True:
            f = await self.read_frame()
            if f["opcode"] == 9:
                await self.send(frame(10, f["data"]))
                continue
            if f["opcode"] == 10:
                self.record["pongs"].append(f["data"])
                continue
            if f["opcode"] == 8:
                self.record["close"] = f["data"]
                return None
            if opcode is None:
                opcode = f["opcode"]
            parts.append(f["data"])
            if f["fin"]:
                return opcode, b"".join(parts)

    async def close_reply(self):
        code = self.record["close"][:2]
        await self.send(frame(8, code))


async def behave(peer, path):
    if path == "/fragments":
        await peer.send(frame(1, b"hel", fin=False) + frame(9, b"mid") + frame(0, b"lo ", fin=False) + frame(0, b"world"))
        f = await peer.read_frame()  # the client's Pong for "mid"
        expect(f["opcode"] == 10 and f["data"] == b"mid", f)
        await peer.send(frame(1, b"got-pong"))
    if path == "/ping":
        await peer.send(frame(9, b"hb"))
        f = await peer.read_frame()
        await peer.send(frame(1, b"pong:" + f["data"]))
    if path == "/server-close":
        await peer.send(frame(8, struct.pack(">H", 1001) + b"bye"))
        await peer.message()
        return
    if path == "/bad-mask":
        await peer.send(frame(1, b"masked", mask=b"abcd"))
        await peer.message()
        return
    if path == "/bad-utf8":
        await peer.send(frame(1, b"\xff\xfe"))
        await peer.message()
        return
    if path == "/rsv":
        await peer.send(frame(1, b"x", rsv=0x40))
        await peer.message()
        return
    if path == "/drop":
        return
    if path == "/push":
        await peer.send(frame(1, b"y" * 5000))
        await peer.message()
        return
    # Echo every data message unfragmented with its opcode.
    while True:
        got = await peer.message()
        if got is None:
            await peer.close_reply()
            return
        await peer.send(frame(got[0], got[1]))


class Server:
    def __init__(self, context=None):
        self.records = []
        self.loop = asyncio.new_event_loop()
        self.ready = threading.Event()
        self.context = context
        threading.Thread(target=self.run, daemon=True).start()
        self.ready.wait()

    def run(self):
        asyncio.set_event_loop(self.loop)
        self.server = self.loop.run_until_complete(asyncio.start_server(self.handle, "127.0.0.1", 0, ssl=self.context))
        self.port = self.server.sockets[0].getsockname()[1]
        self.ready.set()
        self.loop.run_forever()

    @property
    def base(self):
        return ("wss" if self.context else "ws") + "://127.0.0.1:%d" % self.port

    async def handle(self, reader, writer):
        record = {"frames": [], "pongs": [], "close": None, "headers": {}, "path": None}
        self.records.append(record)
        try:
            head = await reader.readuntil(b"\r\n\r\n")
            lines = head.decode("latin-1").split("\r\n")
            method, target, version = lines[0].split(" ")
            headers = {}
            for h in lines[1:]:
                if h:
                    k, v = h.split(":", 1)
                    headers.setdefault(k.strip().lower(), []).append(v.strip())
            record["headers"], record["path"] = headers, target
            path = target.split("?")[0]
            if path == "/reject":
                writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                await writer.drain()
                return
            key = headers["sec-websocket-key"][0]
            expect(len(base64.b64decode(key)) == 16 and headers["sec-websocket-version"] == ["13"], headers)
            accept = base64.b64encode(hashlib.sha1(key.encode() + GUID).digest()).decode()
            if path == "/bad-accept":
                accept = base64.b64encode(b"x" * 20).decode()
            extra = ""
            offered = [p.strip() for v in headers.get("sec-websocket-protocol", []) for p in v.split(",")]
            if path == "/protocol" and "chat" in offered:
                extra = "Sec-WebSocket-Protocol: chat\r\n"
            if path == "/bad-protocol":
                extra = "Sec-WebSocket-Protocol: nope\r\n"
            response = ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Accept: %s\r\n%s\r\n" % (accept, extra)).encode()
            if path == "/early":
                response += frame(1, b"early")  # first frame in the same write as the head
            writer.write(response)
            await writer.drain()
            if path in ("/bad-accept", "/bad-protocol"):
                await asyncio.sleep(0.5)
                return
            await behave(Peer(reader, writer, record), path)
        except (asyncio.IncompleteReadError, ConnectionError, ssl.SSLError, OSError):
            pass
        except Failure as e:
            record["error"] = str(e)
        finally:
            try:
                writer.close()
            except Exception:
                pass

    async def shutdown(self):
        self.server.close()
        tasks = [t for t in asyncio.all_tasks() if t is not asyncio.current_task()]
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)

    def stop(self):
        asyncio.run_coroutine_threadsafe(self.shutdown(), self.loop).result(10)
        self.loop.call_soon_threadsafe(self.loop.stop)


def client(args, script, timeout=30):
    r = subprocess.run([EXE] + args, input=script.encode(), capture_output=True, timeout=timeout)
    return r.returncode, r.stdout.decode(errors="replace").splitlines(), r.stderr.decode(errors="replace")


def check_frames(record):
    frames = record["frames"]
    FRAMES["count"] += len(frames)
    expect(all(f["masked"] for f in frames), "unmasked client frame")
    expect(all(f["rsv"] == 0 for f in frames), "client set RSV bits")
    keys = [f["key"] for f in frames]
    if len(keys) >= 4:
        expect(len(set(keys)) >= len(keys) - 1, "mask keys repeat: %s" % keys)
    expect("error" not in record, record.get("error"))


def cases(server, extra):
    base = server.base
    secure = "1" if server.context else "0"
    opened = "open secure=%s protocol=-" % secure
    out = []

    def case(fn):
        out.append(fn)
        return fn

    def run(path, script, args=(), code=0):
        before = len(server.records)
        rc, lines, err = client(list(extra) + list(args) + [base + path], script)
        expect(rc == code, (rc, lines, err))
        recs = server.records[before:]
        for r in recs:
            check_frames(r)
        return lines, recs

    @case
    def echo_text_binary_and_close():
        lines, recs = run("/echo", "send text hello world\nrecv\nsend binary \\x00\\xff\\x80abc\nrecv\nclose 1000 done\n")
        expect(lines == [opened, line("text", b"hello world"), line("binary", b"\x00\xff\x80abc"), "closed 1000"], lines)
        r = recs[0]
        expect([f["opcode"] for f in r["frames"]] == [1, 2, 8] and r["close"] == struct.pack(">H", 1000) + b"done", r["frames"])
        expect(r["headers"]["host"] == ["127.0.0.1:%d" % server.port] and r["headers"]["upgrade"] == ["websocket"], r["headers"])

    @case
    def large_messages():
        big = gen(False, 1 << 20)
        lines, recs = run("/echo", "gen binary %d\nrecv\ngen text 70000\nrecv\nsend text \nrecv\nclose 1000\n" % len(big))
        expect(lines == [opened, line("binary", big), line("text", gen(True, 70000)), line("text", b""), "closed 1000"], lines)
        lengths = [len(f["data"]) for f in recs[0]["frames"]]
        expect(lengths[:3] == [1 << 20, 70000, 0], lengths)

    @case
    def fragmented_send():
        lines, recs = run("/echo", "frag text 4 abcdefghij\nrecv\nfrag binary 3 \\x01\\x02\\x03\\x04\\x05\nrecv\nclose 1000\n")
        expect(lines == [opened, line("text", b"abcdefghij"), line("binary", b"\x01\x02\x03\x04\x05"), "closed 1000"], lines)
        seq = [(f["opcode"], f["fin"]) for f in recs[0]["frames"]]
        expect(seq == [(1, False), (0, False), (0, False), (0, True), (2, False), (0, False), (0, True), (8, True)], seq)

    @case
    def ping_between_fragments():
        lines, recs = run("/echo", "fragping 3 one-two-three\nrecv\nrecv\nrecv\nclose 1000\n")
        expect(lines == [opened, line("pong", b"between"), line("pong", b"between"), line("text", b"one-two-three"), "closed 1000"], lines)
        seq = [f["opcode"] for f in recs[0]["frames"]]
        expect(seq == [1, 9, 0, 9, 0, 8], seq)

    @case
    def receive_fragments_with_interleaved_ping():
        lines, recs = run("/fragments", "recv\nrecv\nrecv\nclose 1000\n")
        expect(lines == [opened, line("ping", b"mid"), line("text", b"hello world"), line("text", b"got-pong"), "closed 1000"], lines)

    @case
    def server_ping_answered():
        lines, recs = run("/ping", "recv\nrecv\nclose 1000\n")
        expect(lines == [opened, line("ping", b"hb"), line("text", b"pong:hb"), "closed 1000"], lines)
        expect(recs[0]["frames"][0]["opcode"] == 10 and recs[0]["frames"][0]["data"] == b"hb", recs[0]["frames"])

    @case
    def client_ping_gets_pong():
        lines, _ = run("/echo", "ping \\x01x\nrecv\nclose 1000\n")
        expect(lines == [opened, line("pong", b"\x01x"), "closed 1000"], lines)

    @case
    def server_initiated_close():
        lines, recs = run("/server-close", "recv\nsend text late\n", code=1)
        expect(lines == [opened, "close 1001 bye", "error closed"], lines)
        expect(recs[0]["close"] == struct.pack(">H", 1001), recs[0]["close"])

    @case
    def close_without_code():
        lines, recs = run("/echo", "close\n")
        expect(lines == [opened, "closed -1"], lines)
        expect(recs[0]["close"] == b"", recs[0]["close"])

    @case
    def frames_with_the_101():
        lines, _ = run("/early", "recv\nclose 1000\n")
        expect(lines == [opened, line("text", b"early"), "closed 1000"], lines)

    @case
    def subprotocol():
        lines, recs = run("/protocol", "close 1000\n", args=["--protocol", "superchat, chat"])
        expect(lines == ["open secure=%s protocol=chat" % secure, "closed 1000"], lines)
        expect(recs[0]["headers"]["sec-websocket-protocol"] == ["superchat, chat"], recs[0]["headers"])

    @case
    def extra_headers():
        lines, recs = run("/echo", "close 1000\n", args=["-H", "Origin: http://example.test", "-H", "Authorization: Bearer t"])
        h = recs[0]["headers"]
        expect(h["origin"] == ["http://example.test"] and h["authorization"] == ["Bearer t"], h)

    @case
    def timeout_keeps_connection():
        lines, _ = run("/echo", "recv 200\nsend text after\nrecv\nclose 1000\n")
        expect(lines == [opened, "timeout", line("text", b"after"), "closed 1000"], lines)

    @case
    def unmasked_server_frame_fails():
        lines, recs = run("/bad-mask", "recv\n", code=1)
        expect(lines == [opened, "error wire-protocol"], lines)
        expect(recs[0]["close"] == struct.pack(">H", 1002), recs[0]["close"])

    @case
    def invalid_utf8_fails_1007():
        lines, recs = run("/bad-utf8", "recv\n", code=1)
        expect(lines == [opened, "error wire-utf8"], lines)
        expect(recs[0]["close"] == struct.pack(">H", 1007), recs[0]["close"])

    @case
    def reserved_bits_fail():
        lines, recs = run("/rsv", "recv\n", code=1)
        expect(lines == [opened, "error wire-protocol"] and recs[0]["close"] == struct.pack(">H", 1002), (lines, recs[0]["close"]))

    @case
    def too_large_fails_1009():
        lines, recs = run("/push", "recv\n", args=["--max-message", "1000"], code=1)
        expect(lines == [opened, "error wire-limit"] and recs[0]["close"] == struct.pack(">H", 1009), (lines, recs[0]["close"]))

    @case
    def too_large_to_send():
        lines, recs = run("/echo", "gen text 2000\n", args=["--max-message", "1000"], code=1)
        expect(lines == [opened, "error invalid-request"], lines)

    @case
    def eof_without_close():
        lines, _ = run("/drop", "recv\n", code=1)
        expect(lines == [opened, "error eof"], lines)

    @case
    def rejected_upgrade():
        lines, _ = run("/reject", "", code=1)
        expect(lines == ["error rejected 403"], lines)

    @case
    def wrong_accept():
        lines, _ = run("/bad-accept", "", code=1)
        expect(lines == ["error handshake"], lines)

    @case
    def unoffered_protocol():
        lines, _ = run("/bad-protocol", "", code=1)
        expect(lines == ["error handshake"], lines)

    @case
    def fragment_in_url():
        rc, lines, _ = client(list(extra) + [base + "/echo#x"], "")
        expect(rc == 1 and lines == ["error bad-url"], (rc, lines))

    @case
    def http_scheme_refused():
        rc, lines, _ = client(list(extra) + ["http://127.0.0.1:%d/" % server.port], "")
        expect(rc == 1 and lines == ["error unsupported-scheme"], (rc, lines))

    return out


def tls_cases(server, extra):
    out = []

    def case(fn):
        out.append(fn)
        return fn

    @case
    def untrusted_certificate():
        rc, lines, _ = client([server.base + "/echo"], "")
        expect(rc == 1 and lines == ["error certificate"], (rc, lines))

    @case
    def localhost_dns_identity():
        rc, lines, _ = client(list(extra) + ["wss://localhost:%d/echo" % server.port], "send text sni\nrecv\nclose 1000\n")
        expect(rc == 0 and lines == ["open secure=1 protocol=-", line("text", b"sni"), "closed 1000"], (rc, lines))

    return out


def main():
    global EXE, CERTS
    if len(sys.argv) != 3 or sys.argv[1] not in ("ws", "wss", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    work = tempfile.mkdtemp(prefix="ws-client-")
    try:
        for group in (["ws", "wss"] if sys.argv[1] == "all" else [sys.argv[1]]):
            FRAMES["count"] = 0
            extra, context = [], None
            if group == "wss":
                CERTS = Path(work) / "certs"
                if not CERTS.exists():
                    generate(CERTS)
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(str(CERTS / "valid.pem"), str(CERTS / "valid.key"))
                extra = ["--cacert", str(CERTS / "root.pem")]
            server = Server(context)
            todo = cases(server, extra) + (tls_cases(server, extra) if context else [])
            try:
                for fn in todo:
                    try:
                        fn()
                    except Failure as e:
                        print("FAIL %s/%s: %s" % (group, fn.__name__, e), file=sys.stderr)
                        return 1
                    except subprocess.TimeoutExpired:
                        print("FAIL %s/%s: client timed out" % (group, fn.__name__), file=sys.stderr)
                        return 1
            finally:
                server.stop()
            print("websocket-client-%s cases=%d frames=%d" % (group, len(todo), FRAMES["count"]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
