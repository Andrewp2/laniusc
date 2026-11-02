#!/usr/bin/env python3
"""Loopback oracle for sample_programs/library/ws_cat.lani (ext::websocket_client).

usage: oracle.py GROUP EXE      GROUP: ws, wss, deflate or all

The servers are a minimal RFC 6455 echo server on asyncio (the host has no
`websockets` package): plain on 127.0.0.1:0, and TLS with test certificates
generated per run by ../openssl_tls/certificates.py with the openssl CLI.
permessage-deflate (RFC 7692) is Python's zlib: raw DEFLATE, sync flush,
with or without context takeover on each side and with limited windows.
Each case runs one client script and checks its exact output and exit code,
plus what the server observed: every client frame masked, fresh mask keys,
minimal length encodings, fragment and opcode sequence, RSV1 use, compressed
sizes, close codes and handshake fields.
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
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "openssl_tls"))
from certificates import generate  # noqa: E402

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
TAIL = b"\x00\x00\xff\xff"
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


class Deflate:
    """The server's permessage-deflate state. Without context takeover a side
    starts each message from an empty window: the server compresses with a
    fresh compressobj, and inflates the client's messages with a fresh
    decompressobj, so a client that kept its context fails to inflate."""

    def __init__(self, snct, cnct, server_bits, client_bits=15):
        self.snct, self.cnct, self.bits, self.client_bits = snct, cnct, server_bits, client_bits
        self.c = self.d = None

    def compress(self, data):
        if self.c is None or self.snct:
            self.c = zlib.compressobj(6, zlib.DEFLATED, -self.bits)
        out = self.c.compress(data) + self.c.flush(zlib.Z_SYNC_FLUSH)
        expect(out.endswith(TAIL), "sync flush tail")
        return out[:-4]

    def inflate(self, data):
        if self.d is None or self.cnct:
            # The client's window: a match farther back fails to inflate.
            self.d = zlib.decompressobj(-self.client_bits)
        return self.d.decompress(data + TAIL)


class Peer:
    """One server-side connection."""

    def __init__(self, reader, writer, record, z=None):
        self.reader, self.writer, self.record, self.z = reader, writer, record, z

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
        f = {"fin": bool(b0 & 0x80), "rsv": b0 & 0x70, "opcode": b0 & 0x0F, "masked": masked, "key": key, "data": data, "tag": b1 & 0x7F}
        self.record["frames"].append(f)
        return f

    async def send(self, raw):
        self.writer.write(raw)
        await self.writer.drain()

    async def message(self):
        """Next data message, answering pings and recording pongs; None at
        Close. Compressed messages (RSV1) are inflated and recorded."""
        parts, opcode, rsv = [], None, 0
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
                opcode, rsv = f["opcode"], f["rsv"]
            parts.append(f["data"])
            if f["fin"]:
                data = b"".join(parts)
                wire = len(data)
                if rsv & 0x40:
                    expect(self.z is not None, "RSV1 without permessage-deflate")
                    try:
                        data = self.z.inflate(data)
                    except zlib.error as e:
                        raise Failure("server could not inflate: %s" % e)
                self.record["messages"].append({"opcode": opcode, "compressed": bool(rsv & 0x40), "wire": wire, "size": len(data)})
                return opcode, data

    async def send_message(self, opcode, data, fragments=1):
        """One data message, compressed when permessage-deflate is on."""
        rsv = 0
        if self.z is not None:
            data, rsv = self.z.compress(data), 0x40
            self.record["sent"].append(len(data))
        if fragments == 1:
            return await self.send(frame(opcode, data, rsv=rsv))
        step = len(data) // fragments + 1
        pieces = [data[i:i + step] for i in range(0, len(data), step)] or [b""]
        raw = b"".join(frame(opcode if i == 0 else 0, p, fin=i == len(pieces) - 1, rsv=rsv if i == 0 else 0) for i, p in enumerate(pieces))
        await self.send(raw)

    async def close_reply(self):
        code = self.record["close"][:2]
        await self.send(frame(8, code))


# Each of these sends one frame sequence the client must reject, then reads
# the client's Close.
BAD = {
    "/ping-frag": frame(9, b"x", fin=False),
    "/ping-long": frame(9, b"x" * 126),
    "/pong-frag": frame(10, b"", fin=False),
    "/cont-first": frame(0, b"x"),
    "/interleave": frame(1, b"a", fin=False) + frame(1, b"b"),
    "/opcode3": frame(3, b""),
    "/opcode11": frame(11, b""),
    "/close-1005": frame(8, struct.pack(">H", 1005)),
    "/close-999": frame(8, struct.pack(">H", 999)),
    "/close-short": frame(8, b"\x03"),
    "/close-utf8": frame(8, struct.pack(">H", 1000) + b"\xff"),
    "/utf8-fast": frame(1, b"ok\xff", fin=False),
    "/utf8-cont": frame(1, b"\xce", fin=False) + frame(0, b"x"),
    "/nonminimal": bytes([0x81, 126, 0, 5]) + b"hello",
    "/zcorrupt": frame(2, b"\xff\xff\xff\xff", rsv=0x40),
    "/zrsv-ping": frame(9, b"x", rsv=0x40),
}


async def behave(peer, path):
    if path in BAD:
        await peer.send(BAD[path])
        await peer.message()
        return
    z = peer.z
    if path == "/zbomb":
        await peer.send(frame(2, z.compress(b"\0" * 2000000), rsv=0x40))
        await peer.message()
        return
    if path == "/zbad-utf8":
        await peer.send(frame(1, z.compress(b"ok\xff"), rsv=0x40))
        await peer.message()
        return
    if path == "/zrsv-cont":
        c = z.compress(b"split message")
        await peer.send(frame(1, c[:3], fin=False, rsv=0x40) + frame(0, c[3:], rsv=0x40))
        await peer.message()
        return
    if path == "/close-3000":
        await peer.send(frame(8, struct.pack(">H", 3000) + "fin \u00e9".encode()))
        await peer.message()
        return
    if path == "/utf8-split":
        b = "\u03ba\u1f79\u03c3\u03bc\u03b5".encode()
        await peer.send(frame(1, b[:3], fin=False) + frame(9, b"p") + frame(0, b[3:4], fin=False) + frame(0, b[4:]))
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
    # Echo every data message with its opcode (in three fragments on /zfrag).
    while True:
        got = await peer.message()
        if got is None:
            await peer.close_reply()
            return
        await peer.send_message(got[0], got[1], 3 if path == "/zfrag" else 1)


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
        record = {"frames": [], "pongs": [], "close": None, "headers": {}, "path": None, "messages": [], "sent": [], "z": None, "extension": None, "done": threading.Event()}
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
            path, _, q = target.partition("?")
            query = dict((item.split("=", 1) + ["1"])[:2] for item in q.split("&") if item)
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
            # permessage-deflate: accept the client's first offer. Query
            # flags add server_no_context_takeover (s), client_no_context_
            # takeover (c), window bits (sb, cb) or break the response.
            offers = [e.strip() for v in headers.get("sec-websocket-extensions", []) for e in v.split(",")]
            pmd = next(([p.strip() for p in o.split(";")][1:] for o in offers if o.split(";")[0].strip() == "permessage-deflate"), None)
            record["offer"], z = pmd, None
            if pmd is not None and "decline" not in query:
                snct = "server_no_context_takeover" in pmd or "s" in query
                cnct = "client_no_context_takeover" in pmd or "c" in query
                sb = int(query.get("sb", "15"))
                params = ["permessage-deflate"]
                if snct and "drop-snct" not in query:
                    params.append("server_no_context_takeover")
                if cnct:
                    params.append("client_no_context_takeover")
                if "sb" in query:
                    params.append("server_max_window_bits=%d" % sb)
                if "cb" in query:
                    params.append("client_max_window_bits=%s" % query["cb"])
                if "badparam" in query:
                    params.append("foo")
                record["extension"] = "; ".join(params)
                extra += "Sec-WebSocket-Extensions: %s\r\n" % record["extension"]
                z = record["z"] = Deflate(snct, cnct, sb, int(query.get("cb", "15")))
            if "unoffered" in query:
                extra += "Sec-WebSocket-Extensions: permessage-deflate\r\n"
            response = ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                        "Sec-WebSocket-Accept: %s\r\n%s\r\n" % (accept, extra)).encode()
            if path == "/early":
                response += frame(1, b"early")  # first frame in the same write as the head
            writer.write(response)
            await writer.drain()
            if path in ("/bad-accept", "/bad-protocol") or "unoffered" in query or "badparam" in query or "drop-snct" in query:
                await asyncio.sleep(0.5)
                return
            await behave(Peer(reader, writer, record, z), path)
        except (asyncio.IncompleteReadError, ConnectionError, ssl.SSLError, OSError):
            pass
        except Failure as e:
            record["error"] = str(e)
        finally:
            try:
                writer.close()
            except Exception:
                pass
            record["done"].set()

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
    # The server may still be reading the client's last frames.
    expect(record["done"].wait(10), "server connection did not finish")
    frames = record["frames"]
    FRAMES["count"] += len(frames)
    expect(all(f["masked"] for f in frames), "unmasked client frame")
    # RSV1 only on the first frame of a data message, and only with deflate.
    expect(all(f["rsv"] == 0 or (f["rsv"] == 0x40 and record["z"] is not None and f["opcode"] in (1, 2)) for f in frames), "client set RSV bits")
    # Lengths use the minimal encoding (RFC 6455 5.2).
    for f in frames:
        n = len(f["data"])
        expect(f["tag"] == (n if n < 126 else 126 if n < 65536 else 127), ("length encoding", n, f["tag"]))
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

    # RFC 6455 section 5.2 lengths: 7-bit up to 125, 16-bit up to 65535, then
    # 64-bit, both ways (check_frames checks the client's encodings).
    @case
    def length_boundaries():
        sizes = [0, 1, 125, 126, 127, 65535, 65536, 65537]
        lines, recs = run("/echo", "".join("gen binary %d\nrecv\n" % n for n in sizes) + "close 1000\n")
        expect(lines == [opened] + [line("binary", gen(False, n)) for n in sizes] + ["closed 1000"], lines)
        tags = [f["tag"] for f in recs[0]["frames"]][:len(sizes)]
        expect(tags == [0, 1, 125, 126, 126, 126, 127, 127], tags)

    # Control frames: no fragmentation, at most 125 bytes (5.5); reserved
    # opcodes (5.2); continuation rules (5.4); close payloads (5.5.1, 7.4);
    # UTF-8 checked as fragments arrive (8.1). Each fails with the right code.
    for path, name, code in [
        ("/ping-frag", "wire-protocol", 1002), ("/pong-frag", "wire-protocol", 1002), ("/ping-long", "wire-protocol", 1002),
        ("/cont-first", "wire-protocol", 1002), ("/interleave", "wire-protocol", 1002),
        ("/opcode3", "wire-protocol", 1002), ("/opcode11", "wire-protocol", 1002), ("/nonminimal", "wire-protocol", 1002),
        ("/close-1005", "wire-close", 1002), ("/close-999", "wire-close", 1002), ("/close-short", "wire-close", 1002),
        ("/close-utf8", "wire-utf8", 1007), ("/utf8-fast", "wire-utf8", 1007), ("/utf8-cont", "wire-utf8", 1007),
    ]:
        def failing(path=path, name=name, code=code):
            lines, recs = run(path, "recv\n", code=1)
            expect(lines == [opened, "error " + name], (path, lines))
            expect(recs[0]["close"] == struct.pack(">H", code), (path, recs[0]["close"]))
        failing.__name__ = "rejects" + path.replace("/", "_").replace("-", "_")
        case(failing)

    @case
    def utf8_split_across_fragments():
        lines, _ = run("/utf8-split", "recv\nrecv\nclose 1000\n")
        text = "\u03ba\u1f79\u03c3\u03bc\u03b5".encode()
        expect(lines == [opened, line("ping", b"p"), line("text", text), "closed 1000"], lines)

    @case
    def server_close_3000_with_reason():
        lines, recs = run("/close-3000", "recv\n")
        expect(lines == [opened, "close 3000 fin\\x20\\xc3\\xa9"], lines)
        expect(recs[0]["close"] == struct.pack(">H", 3000), recs[0]["close"])

    @case
    def client_close_code_and_reason():
        lines, recs = run("/echo", "close 4000 going \\xc3\\xa9\n")
        expect(lines == [opened, "closed 4000"], lines)
        expect(recs[0]["close"] == struct.pack(">H", 4000) + "going \u00e9".encode(), recs[0]["close"])

    # Codes an endpoint must not send (1005, 1006, 1015, below 1000), a
    # reason past 123 bytes or not UTF-8, and a Ping over 125 bytes are
    # refused before anything is sent.
    for script, what in [("close 1005\n", "1005"), ("close 1006\n", "1006"), ("close 1015\n", "1015"), ("close 999\n", "999"),
                         ("close 1000 %s\n" % ("r" * 124), "long reason"), ("close 1000 \\xff\n", "reason utf8"),
                         ("ping %s\n" % ("p" * 126), "long ping"), ("send text \\xc3\n", "text utf8")]:
        def refused(script=script, what=what):
            lines, recs = run("/echo", script + "close 1000\n", code=1)
            expect(lines == [opened, "error invalid-request"], (what, lines))
            expect(recs[0]["frames"] == [], (what, recs[0]["frames"]))
        refused.__name__ = "refuses_" + what.replace(" ", "_")
        case(refused)

    return out


def deflate_cases(server, extra):
    """permessage-deflate against zlib; plain transport only."""
    base = server.base
    opened = "open secure=0 protocol=- deflate=1"
    out = []

    def case(fn):
        out.append(fn)
        return fn

    def run(path, script, args=("--deflate",), code=0):
        before = len(server.records)
        rc, lines, err = client(list(args) + [base + path], script)
        expect(rc == code, (rc, lines, err))
        recs = server.records[before:]
        for r in recs:
            check_frames(r)
        return lines, (recs[0] if recs else None)

    # gen binary 256 has no repeat inside one message, so a repeat is small
    # only when it refers back into the previous message.
    repeat = "gen binary 256\nrecv\ngen binary 256\nrecv\n"
    twice = [line("binary", gen(False, 256))] * 2

    def wires(r):
        return [m["wire"] for m in r["messages"]]

    @case
    def negotiated_and_compressed():
        lines, r = run("/echo", "send text hello hello hello\nrecv\nsend binary \\x00\nrecv\nclose 1000\n")
        expect(lines == [opened, line("text", b"hello hello hello"), line("binary", b"\x00"), "closed 1000"], lines)
        expect(r["offer"] == ["client_max_window_bits"] and r["extension"] == "permessage-deflate", (r["offer"], r["extension"]))
        expect([m["compressed"] for m in r["messages"]] == [True, True], r["messages"])
        expect([f["rsv"] for f in r["frames"]] == [0x40, 0x40, 0], r["frames"])

    @case
    def context_takeover_both_ways():
        lines, r = run("/echo", repeat + "close 1000\n")
        expect(lines == [opened] + twice + ["closed 1000"], lines)
        w = wires(r)
        expect(w[1] * 4 < w[0] and r["sent"][1] * 4 < r["sent"][0], ("history not used", w, r["sent"]))

    @case
    def client_no_context_takeover():
        # The server inflates each message from an empty window.
        lines, r = run("/echo?c=1", repeat + "close 1000\n")
        expect(lines == [opened] + twice + ["closed 1000"], lines)
        expect(r["extension"] == "permessage-deflate; client_no_context_takeover", r["extension"])
        w = wires(r)
        expect(w[0] == w[1] and r["sent"][1] * 4 < r["sent"][0], (w, r["sent"]))

    @case
    def server_no_context_takeover():
        lines, r = run("/echo?s=1", repeat + "close 1000\n")
        expect(lines == [opened] + twice + ["closed 1000"], lines)
        w = wires(r)
        expect(w[1] * 4 < w[0] and r["sent"][0] == r["sent"][1], (w, r["sent"]))

    @case
    def offer_without_context_takeover():
        lines, r = run("/echo", repeat + "close 1000\n", args=["--deflate-no-context"])
        expect(lines == [opened] + twice + ["closed 1000"], lines)
        expect(r["offer"] == ["client_no_context_takeover", "server_no_context_takeover", "client_max_window_bits"], r["offer"])
        w = wires(r)
        expect(w[0] == w[1] and r["sent"][0] == r["sent"][1], (w, r["sent"]))

    @case
    def no_context_offer_answered_without_server_reset():
        lines, _ = run("/echo?drop-snct", "", args=["--deflate-no-context"], code=1)
        expect(lines == ["error handshake"], lines)

    # The server limits client_max_window_bits: the client still compresses,
    # and the server inflates with that window, so a farther match fails.
    # 200 bytes back is in every window; 1500 bytes back only from 11 bits.
    noise = [os.urandom(200), os.urandom(1500)]
    escaped = ["".join("\\x%02x" % b for b in n) for n in noise]
    window_script = "".join("send binary %s\nrecv\nsend binary %s\nrecv\n" % (e, e) for e in escaped) + "close 1000\n"
    for cb in (8, 10, 12):
        def client_window(cb=cb):
            lines, r = run("/echo?cb=%d" % cb, window_script)
            expect(lines == [opened] + [line("binary", n) for n in noise for _ in (0, 1)] + ["closed 1000"], (cb, lines))
            w = wires(r)
            expect(all(m["compressed"] for m in r["messages"]) and w[1] < 30 and (w[3] < 60) == (cb >= 11), (cb, w))
        client_window.__name__ = "client_window_bits_%d" % cb
        case(client_window)

    @case
    def server_window_limited():
        lines, r = run("/echo?sb=10", "gen text 5000\nrecv\n" + repeat + "close 1000\n")
        expect(lines == [opened, line("text", gen(True, 5000))] + twice + ["closed 1000"], lines)

    @case
    def large_messages_and_window_slides():
        # 1.3 MB through one context, sync-flushed at offsets that do not
        # line up with the encoder's 32 KiB chunks.
        sizes = [("binary", 1 << 20), ("text", 70000), ("binary", 100001), ("text", 3), ("binary", 0), ("text", 50000), ("binary", 256), ("binary", 256)]
        script = "".join("gen %s %d\nrecv\n" % (k, n) for k, n in sizes) + "close 1000\n"
        lines, r = run("/echo", script)
        expect(lines == [opened] + [line(k, gen(k == "text", n)) for k, n in sizes] + ["closed 1000"], lines)
        w = wires(r)
        expect(w[0] < (1 << 20) // 20 and w[4] == 1 and w[7] * 4 < w[6], w)

    @case
    def compressed_fragments_received():
        lines, r = run("/zfrag", "gen text 3000\nrecv\nsend text abc\nrecv\nclose 1000\n")
        expect(lines == [opened, line("text", gen(True, 3000)), line("text", b"abc"), "closed 1000"], lines)

    @case
    def fragments_sent_compressed():
        # One message compressed across its fragments, RSV1 on the first;
        # Pings may go between them; a code point may span two fragments.
        long = gen(True, 3000).decode()
        lines, r = run("/echo", "frag text 4 abcdefghij\nrecv\nfrag text 5 %s\nrecv\nfragping 3 abc-def-ghi\nrecv\nrecv\nrecv\nfrag text 2 \\xce\\xba\nrecv\nclose 1000\n" % long)
        expect(lines == [opened, line("text", b"abcdefghij"), line("text", long.encode()), line("pong", b"between"), line("pong", b"between"),
                         line("text", b"abc-def-ghi"), line("text", "\u03ba".encode()), "closed 1000"], lines)
        frames = [(f["opcode"], f["rsv"]) for f in r["frames"]]
        expect(frames[:4] == [(1, 0x40), (0, 0), (0, 0), (0, 0)] and frames[4] == (1, 0x40), frames)
        expect([m["compressed"] for m in r["messages"]] == [True] * 4, r["messages"])
        expect(r["messages"][1]["wire"] < 200, r["messages"][1])

    @case
    def fragmented_invalid_text_stops_the_message():
        lines, r = run("/echo", "frag text 2 a\\xff\nrecv\n", code=1)
        expect(lines == [opened, "error invalid-request"], lines)
        expect([(f["opcode"], f["fin"]) for f in r["frames"]] == [(1, False)], r["frames"])

    @case
    def control_frames_unchanged():
        lines, r = run("/ping", "recv\nrecv\nping abc\nrecv\nclose 1000\n")
        expect(lines == [opened, line("ping", b"hb"), line("text", b"pong:hb"), line("pong", b"abc"), "closed 1000"], lines)

    @case
    def declined_offer():
        lines, r = run("/echo?decline", "send text plain\nrecv\nclose 1000\n")
        expect(lines == ["open secure=0 protocol=-", line("text", b"plain"), "closed 1000"], lines)
        expect(r["messages"][0]["compressed"] is False, r["messages"])

    @case
    def unoffered_extension_refused():
        lines, _ = run("/echo?unoffered", "", args=(), code=1)
        expect(lines == ["error handshake"], lines)

    @case
    def unknown_parameter_refused():
        lines, _ = run("/echo?badparam", "", code=1)
        expect(lines == ["error handshake"], lines)

    for path, args, name, code in [
        ("/zbomb", ["--max-message", "100000"], "wire-limit", 1009),
        ("/zcorrupt", [], "inflate", 1007),
        ("/zbad-utf8", [], "wire-utf8", 1007),
        ("/zrsv-cont", [], "wire-protocol", 1002),
        ("/zrsv-ping", [], "wire-protocol", 1002),
    ]:
        def failing(path=path, args=args, name=name, code=code):
            lines, r = run(path, "recv\n", args=["--deflate"] + args, code=1)
            expect(lines == [opened, "error " + name], (path, lines))
            expect(r["close"] == struct.pack(">H", code), (path, r["close"]))
        failing.__name__ = "rejects" + path.replace("/", "_").replace("-", "_")
        case(failing)

    @case
    def invalid_text_refused_before_compression():
        lines, r = run("/echo", "send text \\xff\nclose 1000\n", code=1)
        expect(lines == [opened, "error invalid-request"] and r["frames"] == [], (lines, r["frames"]))

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
    if len(sys.argv) != 3 or sys.argv[1] not in ("ws", "wss", "deflate", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    work = tempfile.mkdtemp(prefix="ws-client-")
    try:
        for group in (["ws", "wss", "deflate"] if sys.argv[1] == "all" else [sys.argv[1]]):
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
            if group == "deflate":
                todo = deflate_cases(server, extra)
            else:
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
