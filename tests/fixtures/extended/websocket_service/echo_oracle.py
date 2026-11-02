"""ws_echo_server against a hand-written RFC 6455 peer (peer.py): handshake,
echo sizes, ping/pong, fragmentation, an Autobahn-style list of framing
errors (reserved bits and opcodes, unmasked frames, bad continuations,
control frame rules), UTF-8, close codes, limits, permessage-deflate,
broadcast, many sessions, and leftover bytes after the upgrade.
Usage: echo_oracle.py SERVER. Prints one summary line."""
import os
import struct
import subprocess
import sys
import threading
import time
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from peer import Closed, Peer  # noqa: E402

EXE = sys.argv[1]
TAIL = b"\x00\x00\xff\xff"


def start(*args):
    p = subprocess.Popen([EXE, "127.0.0.1:0"] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    line = p.stdout.readline().decode().strip()
    if not line:
        raise AssertionError(("no startup line", p.stderr.read()[:300]))
    return p, int(line.rsplit(":", 1)[1])


def stop(p):
    alive = p.poll() is None
    p.kill()
    p.wait()
    return alive


def check(ok, what):
    if not ok:
        raise AssertionError(what)


def opened(port, path=b"/ws", extensions=None):
    peer = Peer(port)
    check(peer.handshake(path, extensions) == 101, ("upgrade", path, peer.status))
    return peer


def echo(peer, opcode, payload):
    peer.send(opcode, payload)
    op, rsv, got = peer.message()
    check(op == opcode and got == payload and rsv == 0, ("echo", opcode, len(payload), op, len(got)))


def expect_fail(port, frames, codes=(1002,), what=""):
    peer = opened(port)
    for f in frames:
        peer.raw(f(peer) if callable(f) else f)
    try:
        code, _ = peer.expect_close(codes)
    except Closed:
        raise AssertionError(("closed without Close frame", what))
    return code


def http_cases(port):
    p = Peer(port)
    status, _, body = p.http(b"GET / HTTP/1.1\r\nHost: x\r\n\r\n")
    check(status == 200 and body.startswith(b"websocket echo"), ("banner", status))
    status, _, _ = p.http(b"GET /ws HTTP/1.1\r\nHost: x\r\n\r\n")
    check(status == 400, ("plain GET /ws", status))
    p.close()
    p = Peer(port)
    check(p.http(b"GET /nope HTTP/1.1\r\nHost: x\r\n\r\n")[0] == 404, "404")
    p.close()
    bad = [b"Sec-WebSocket-Version: 8", b"Sec-WebSocket-Key: short"]
    for extra in bad:
        p = Peer(port)
        req = b"GET /ws HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" + extra + b"\r\n"
        if b"Key" not in extra:
            req += b"Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
        if b"Version" not in extra:
            req += b"Sec-WebSocket-Version: 13\r\n"
        check(p.http(req + b"\r\n")[0] == 400, ("bad handshake", extra))
        p.close()
    # The HTTP server still works after upgrades on the same listener.
    peer = opened(port)
    check(b"sec-websocket-extensions" not in peer.headers, "no extension without offer")
    echo(peer, 1, b"after http")
    peer.send(8, struct.pack(">H", 1000))
    peer.expect_close([1000])
    return 1


def echo_cases(port):
    peer = opened(port)
    for n in [0, 1, 125, 126, 127, 65535, 65536, 200000]:
        echo(peer, 1, b"x" * n)
        echo(peer, 2, os.urandom(n))
    echo(peer, 1, "é中\U0001f600".encode() * 100)
    # Ping (0 and 125 bytes) gets a matching pong; an unsolicited pong is ignored.
    for n in [0, 125]:
        body = os.urandom(n)
        peer.send(9, body)
        fin, rsv, op, got = peer.recv()
        check(op == 10 and got == body and fin, ("pong", n, op))
    peer.send(10, b"unsolicited")
    echo(peer, 1, b"after pong")
    # Fragmented text with a ping between fragments: the pong comes first.
    peer.send(1, b"frag", fin=False)
    peer.send(0, b"men", fin=False)
    peer.send(9, b"mid")
    peer.send(0, b"ted", fin=True)
    fin, rsv, op, got = peer.recv()
    check(op == 10 and got == b"mid", ("interleaved pong", op, got))
    op, rsv, got = peer.message()
    check(op == 1 and got == b"fragmented", ("reassembled", got))
    # A UTF-8 code point split across fragments is valid.
    s = "\U0001f600".encode()
    peer.send(1, s[:1], fin=False)
    peer.send(0, s[1:3], fin=False)
    peer.send(0, s[3:], fin=True)
    check(peer.message() == (1, 0, s), "split code point")
    # Fragmented binary with empty fragments.
    peer.send(2, b"", fin=False)
    peer.send(0, b"ab", fin=False)
    peer.send(0, b"", fin=True)
    check(peer.message() == (2, 0, b"ab"), "empty fragments")
    # Many frames in one write.
    peer.raw(b"".join(peer.frame(1, b"m%d" % i) for i in range(100)))
    for i in range(100):
        check(peer.message() == (1, 0, b"m%d" % i), ("batched", i))
    peer.send(8, struct.pack(">H", 1000) + b"done")
    code, _ = peer.expect_close([1000])
    return 6


def framing_cases(port):
    cases = 0
    for rsv in [1, 2, 4, 3, 7]:
        expect_fail(port, [lambda p, r=rsv: p.frame(1, b"hi", rsv=r)], what=("rsv", rsv))
        cases += 1
    for op in [3, 4, 5, 6, 7, 11, 12, 13, 14, 15]:
        expect_fail(port, [lambda p, o=op: p.frame(o, b"")], what=("opcode", op))
        cases += 1
    expect_fail(port, [lambda p: p.frame(1, b"unmasked", mask=False)], what="unmasked")
    expect_fail(port, [lambda p: p.frame(0, b"cont", fin=True)], what="continuation first")
    expect_fail(port, [lambda p: p.frame(1, b"a", fin=False), lambda p: p.frame(1, b"b")], what="new message mid-fragment")
    expect_fail(port, [lambda p: p.frame(9, b"", fin=False)], what="fragmented ping")
    expect_fail(port, [lambda p: p.frame(9, b"x" * 126)], what="ping too long")
    expect_fail(port, [lambda p: p.frame(8, b"\x03")], what="one-byte close")
    # A non-minimal or oversized 64-bit length is a protocol error.
    expect_fail(port, [b"\x81\xff" + struct.pack(">Q", 1 << 63) + b"\x00\x00\x00\x00"], codes=(1002, 1009), what="length high bit")
    cases += 7
    # A message larger than --max-message fails with 1009.
    expect_fail(port, [lambda p: p.frame(2, b"z" * 524288, fin=False), lambda p: p.frame(0, b"z" * 524288, fin=False), lambda p: p.frame(0, b"z" * 524288)], codes=(1009,), what="too big")
    cases += 1
    return cases


def utf8_cases(port):
    bad = [b"\xff", b"\xc0\xaf", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"ok\xe2\x82", b"\xce\x41"]
    for b in bad:
        expect_fail(port, [lambda p, b=b: p.frame(1, b)], codes=(1007,), what=("utf8", b))
    # Invalid in a later fragment, and a truncated sequence at the end.
    expect_fail(port, [lambda p: p.frame(1, b"good", fin=False), lambda p: p.frame(0, b"\xf8")], codes=(1007,), what="fragment utf8")
    expect_fail(port, [lambda p: p.frame(1, b"\xe2\x82", fin=False), lambda p: p.frame(0, b"", fin=True)], codes=(1007,), what="truncated utf8")
    # Binary is not checked.
    peer = opened(port)
    echo(peer, 2, b"\xff\xfe")
    peer.send(8, struct.pack(">H", 1000))
    peer.expect_close([1000])
    return len(bad) + 3


def close_cases(port):
    cases = 0
    for code in [1000, 1001, 1002, 1003, 1007, 1008, 1009, 1010, 1011, 1012, 1013, 1014, 3000, 3999, 4000, 4999]:
        peer = opened(port)
        peer.send(8, struct.pack(">H", code) + b"reason")
        got, _ = peer.expect_close([code])
        cases += 1
    for code in [0, 999, 1004, 1005, 1006, 1015, 1016, 1100, 2000, 2999, 5000, 65535]:
        expect_fail(port, [lambda p, c=code: p.frame(8, struct.pack(">H", c))], what=("close code", code))
        cases += 1
    expect_fail(port, [lambda p: p.frame(8, struct.pack(">H", 1000) + b"\xff")], codes=(1007,), what="close reason utf8")
    # An empty Close is answered with an empty Close.
    peer = opened(port)
    peer.send(8, b"")
    fin, rsv, op, payload = peer.recv()
    check(op == 8 and payload == b"", ("empty close", op, payload))
    peer.expect_eof()
    # Server-initiated close: "close" -> 1000 bye, then EOF after our answer.
    peer = opened(port)
    peer.send(1, b"close")
    code, reason = peer.expect_close([1000])
    check(reason == b"bye", ("reason", reason))
    # Data after the client's Close is ignored; the echo of Close still comes.
    peer = opened(port)
    peer.raw(peer.frame(8, struct.pack(">H", 1000)) + peer.frame(1, b"late"))
    fin, rsv, op, payload = peer.recv()
    check(op == 8, ("close first", op))
    peer.expect_eof()
    # Abrupt drop mid-frame: the server keeps serving.
    peer = opened(port)
    peer.raw(peer.frame(1, b"abcdef")[:5])
    peer.close()
    return cases + 4


def deflate_cases(port):
    cases = 0
    # The server keeps context takeover unless the offer asks otherwise
    # (one decompressobj for every reply; the repeated message must refer
    # back), or resets per message (a fresh decompressobj each time).
    random = os.urandom(3000)
    texts = [b"hello " * 50, b"", b"x", "é中\U0001f600".encode() * 300, b"hello " * 50, random, random, b"A" * 300000]
    for offer, reset, bits in [(b"permessage-deflate; client_max_window_bits", False, 15),
                               (b"permessage-deflate; server_no_context_takeover", True, 15),
                               (b"permessage-deflate; server_max_window_bits=9", False, 9)]:
        peer = opened(port, extensions=offer)
        ext = peer.headers.get(b"sec-websocket-extensions")
        want = b"permessage-deflate" + (b"; server_no_context_takeover" if reset else b"") + (b"; server_max_window_bits=9" if bits == 9 else b"")
        check(ext == [want], ("negotiated", offer, ext))
        z = zlib.compressobj(6, zlib.DEFLATED, -15)
        d = zlib.decompressobj(-bits)
        sizes = []
        for i, m in enumerate(texts):
            op = 1 if i not in (5, 6) else 2
            c = z.compress(m) + z.flush(zlib.Z_SYNC_FLUSH)
            peer.send(op, c[:-4], rsv=4)
            gop, rsv, got = peer.message()
            sizes.append(len(got))
            if rsv == 4:
                if reset:
                    d = zlib.decompressobj(-bits)
                got = d.decompress(got + TAIL)
            check(gop == op and got == m, ("deflate echo", offer, i, gop, rsv, len(got)))
            check(rsv == 4 or len(m) < 64, ("compressed reply", i, rsv))
        # The second 3000 random bytes: tiny only with history in reach.
        check((sizes[6] < 100) == (not reset and bits == 15), ("takeover", offer, sizes))
        peer.close()
        cases += 1
    # A compressed message split into fragments, RSV1 on the first only.
    peer = opened(port, extensions=b"permessage-deflate")
    c = zlib.compressobj(6, zlib.DEFLATED, -15)
    body = c.compress(b"fragmented compressed " * 100) + c.flush(zlib.Z_FINISH)
    peer.send(1, body[:10], fin=False, rsv=4)
    peer.send(0, body[10:20], fin=False)
    peer.send(0, body[20:], fin=True)
    gop, rsv, got = peer.message()
    if rsv == 4:
        got = zlib.decompressobj(-15).decompress(got + TAIL)
    check(got == b"fragmented compressed " * 100, "compressed fragments")
    # Uncompressed messages still work on a deflate session.
    echo(peer, 1, b"plain")
    peer.send(8, struct.pack(">H", 1000))
    peer.expect_close([1000])
    cases += 1
    # Errors: RSV1 on a continuation or a control frame; invalid UTF-8 after
    # inflation; corrupt DEFLATE data; an inflated size over the limit.
    def deflated(m):
        z = zlib.compressobj(6, zlib.DEFLATED, -15)
        return (z.compress(m) + z.flush(zlib.Z_SYNC_FLUSH))[:-4]
    for frames, codes, what in [
            ([lambda p: p.frame(1, deflated(b"ab"), fin=False, rsv=4), lambda p: p.frame(0, b"", rsv=4)], (1002,), "rsv1 continuation"),
            ([lambda p: p.frame(9, b"", rsv=4)], (1002,), "rsv1 ping"),
            ([lambda p: p.frame(1, deflated(b"\xff\xfe"), rsv=4)], (1007,), "inflated utf8"),
            ([lambda p: p.frame(2, b"\xff\xff\xff\xff", rsv=4)], (1007,), "corrupt"),
            ([lambda p: p.frame(2, deflated(b"\x00" * 3000000), rsv=4)], (1009,), "inflated too big")]:
        peer = opened(port, extensions=b"permessage-deflate")
        for f in frames:
            peer.raw(f(peer))
        peer.expect_close(codes)
        cases += 1
    # RSV1 without negotiation is still a protocol error.
    expect_fail(port, [lambda p: p.frame(1, deflated(b"hi"), rsv=4)], what="rsv1 not negotiated")
    return cases + 1


def broadcast_cases(port):
    a = opened(port, b"/chat")
    b = opened(port, b"/chat")
    e = opened(port, b"/ws")
    a.send(1, b"hello all")
    check(a.message() == (1, 0, b"hello all"), "chat self")
    check(b.message() == (1, 0, b"hello all"), "chat other")
    e.send(1, b"solo")
    check(e.message() == (1, 0, b"solo"), "echo beside chat")
    b.send(8, struct.pack(">H", 1001))
    b.expect_close([1001])
    a.send(2, b"\x01\x02")
    check(a.message() == (2, 0, b"\x01\x02"), "chat after leave")
    for p in [a, e]:
        p.send(8, struct.pack(">H", 1000))
        p.expect_close([1000])
    return 1


def many_cases(port):
    errors = []

    def client(k):
        try:
            peer = opened(port)
            for i in range(20):
                echo(peer, 1, b"client %d message %d " % (k, i) * (i + 1))
            peer.send(8, struct.pack(">H", 1000))
            peer.expect_close([1000])
        except Exception as ex:  # noqa: BLE001
            errors.append((k, repr(ex)))
    threads = [threading.Thread(target=client, args=(k,)) for k in range(40)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(60)
    check(not errors, ("concurrent", errors[:3]))
    # Frames sent together with the handshake (leftover bytes at detach).
    peer = Peer(port)
    first = peer.frame(1, b"early") + peer.frame(9, b"p")
    check(peer.handshake(b"/ws", first=first) == 101, "early upgrade")
    check(peer.message() == (1, 0, b"early"), "leftover frame")
    peer.send(8, struct.pack(">H", 1000))
    peer.expect_close([1000])
    return 2


def limits_cases():
    cases = 0
    p, port = start("--sessions", "2", "--idle-timeout", "400")
    try:
        a, b = opened(port), opened(port)
        c = Peer(port)
        check(c.handshake() == 503, ("full", c.status))
        c.close()
        cases += 1
        # Idle sessions get a 1001 close.
        t0 = time.time()
        a.expect_close([1001])
        b.expect_close([1001])
        check(time.time() - t0 < 5, "idle close timing")
        cases += 1
        d = opened(port)
        echo(d, 1, b"slot reused")
        d.send(8, struct.pack(">H", 1000))
        d.expect_close([1000])
        cases += 1
    finally:
        check(stop(p), "limits server alive")
    p, port = start("--no-deflate")
    try:
        peer = opened(port, extensions=b"permessage-deflate")
        check(b"sec-websocket-extensions" not in peer.headers, "no-deflate declines")
        echo(peer, 1, b"plain")
        peer.send(8, struct.pack(">H", 1000))
        peer.expect_close([1000])
        cases += 1
    finally:
        check(stop(p), "no-deflate server alive")
    return cases


def main():
    total = 0
    p, port = start("--max-message", "1048576")
    try:
        for f in [http_cases, echo_cases, framing_cases, utf8_cases, close_cases, deflate_cases, broadcast_cases, many_cases]:
            total += f(port)
        echo(opened(port), 1, b"still alive")
    finally:
        alive = stop(p)
    check(alive, ("server exited", p.stderr.read()[:300]))
    total += limits_cases()
    # --deflate-no-context: the server resets even when not asked.
    p, port = start("--deflate-no-context")
    try:
        peer = opened(port, extensions=b"permessage-deflate")
        ext = peer.headers.get(b"sec-websocket-extensions")
        check(ext == [b"permessage-deflate; server_no_context_takeover"], ("no-context server", ext))
        for m in [b"repeat " * 40, b"repeat " * 40]:
            z = zlib.compressobj(6, zlib.DEFLATED, -15)
            peer.send(1, (z.compress(m) + z.flush(zlib.Z_SYNC_FLUSH))[:-4], rsv=4)
            gop, rsv, got = peer.message()
            check(rsv == 4 and zlib.decompressobj(-15).decompress(got + TAIL) == m, ("no-context reply", rsv))
        peer.close()
        total += 1
    finally:
        alive = stop(p)
    check(alive, ("no-context server exited", p.stderr.read()[:300]))
    print("ws-service cases=%d" % total)


main()
