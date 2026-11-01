"""Oracle for ext::http2_server: libnghttp2's client session (ctypes) and raw
frames against a server.

usage: oracle.py pipe ENGINE_HARNESS       (stdin/stdout engine harness)
       oracle.py tcp SERVER_BINARY         (h2c service; prints its port)
"""
import os
import select
import socket
import struct
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nghttp2_client as ng  # noqa: E402

PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"


class Pipe:
    def __init__(self, exe):
        self.p = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.eof = False

    def send(self, data):
        if data:
            try:
                self.p.stdin.write(data)
                self.p.stdin.flush()
            except BrokenPipeError:
                pass

    def recv(self, wait):
        if self.eof:
            return b""
        r, _, _ = select.select([self.p.stdout], [], [], wait)
        if not r:
            return None
        data = os.read(self.p.stdout.fileno(), 65536)
        if not data:
            self.eof = True
        return data

    def finish(self):
        try:
            self.p.stdin.close()
        except BrokenPipeError:
            pass
        rest = self.p.stdout.read()
        code = self.p.wait(timeout=10)
        return code, rest


class Tcp:
    def __init__(self, port):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=5)
        self.s.setblocking(False)
        self.eof = False

    def send(self, data):
        if data:
            try:
                self.s.setblocking(True)
                self.s.sendall(data)
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                self.s.setblocking(False)

    def recv(self, wait):
        if self.eof:
            return b""
        r, _, _ = select.select([self.s], [], [], wait)
        if not r:
            return None
        try:
            data = self.s.recv(65536)
        except ConnectionResetError:
            data = b""
        if not data:
            self.eof = True
        return data

    def finish(self):
        self.s.close()
        return None, b""


def exchange(client, t, done, limit=10.0, on_data=None):
    """Run the session until done() or the transport closes."""
    end = time.time() + limit
    while time.time() < end:
        t.send(client.output())
        if done():
            return True
        data = t.recv(0.05)
        if data is None:
            continue
        if data == b"":
            return done()
        client.receive(data)
        if on_data:
            on_data()
    raise AssertionError("exchange timed out")


# ---- raw frames ----
def frame(kind, flags, stream, payload):
    return struct.pack(">I", len(payload))[1:] + bytes([kind, flags]) + struct.pack(">I", stream) + payload


def literal(name, value):
    # Literal header field without indexing, new name, no Huffman (RFC 7541 6.2.2).
    return b"\x00" + bytes([len(name)]) + name + bytes([len(value)]) + value


def block(fields):
    return b"".join(literal(n, v) for n, v in fields)


def get(path=b"/"):
    return [(b":method", b"GET"), (b":scheme", b"http"), (b":authority", b"x"), (b":path", path)]


def frames(data):
    out, at = [], 0
    while at + 9 <= len(data):
        n = int.from_bytes(data[at:at + 3], "big")
        out.append((data[at + 3], data[at + 4], int.from_bytes(data[at + 5:at + 9], "big") & 0x7fffffff, data[at + 9:at + 9 + n]))
        at += 9 + n
    return out


def raw(t, payload, wait=1.0):
    """Send payload after the preface and an empty SETTINGS, collect frames."""
    t.send(PREFACE + frame(4, 0, 0, b"") + payload)
    got, end = b"", time.time() + wait
    while time.time() < end:
        data = t.recv(0.05)
        if data is None:
            continue
        if data == b"":
            break
        got += data
    return frames(got)


def goaway_code(fs):
    for k, f, s, p in fs:
        if k == 7:
            return int.from_bytes(p[4:8], "big")
    return None


def resets(fs):
    return {s: int.from_bytes(p[:4], "big") for k, f, s, p in fs if k == 3}


def responses(fs):
    return [s for k, f, s, p in fs if k == 1]


# ---- cases ----
def check(ok, what):
    if not ok:
        raise AssertionError(what)


def nghttp2_cases(connect, limits):
    """connect() opens a fresh transport; limits: dict(streams, window, body)."""
    count = 0
    # Multiplexed requests beyond the concurrency limit, each with its own tag.
    # Requests go out once the server's SETTINGS (and its limit) arrived.
    t = connect(); c = ng.Client()
    exchange(c, t, lambda: any(k == ng.SETTINGS and f & 1 for k, f, s in c.frames))
    ids = [c.request(b"GET", b"/m/%d" % i, [(b"x-tag", b"t%d" % i)]) for i in range(3 * limits["streams"] // 2)]
    exchange(c, t, lambda: all(c.streams[i].closed for i in ids))
    for n, i in enumerate(ids):
        s = c.streams[i]
        check(s.status == 200 and s.error == 0 and bytes(s.body) == b"GET /m/%d t%d " % (n, n), ("multiplex", n, s.status, bytes(s.body)[:80]))
    check(c.remote_setting(ng.MAX_CONCURRENT_STREAMS) == limits["streams"], "advertised MAX_CONCURRENT_STREAMS")
    check((b"content-type", b"text/plain") in c.streams[ids[0]].headers, "response fields")
    c.close(); t.finish(); count += 1
    # A request body larger than our stream and connection windows.
    t = connect(); c = ng.Client()
    body = bytes((i * 7) % 251 for i in range(limits["body"] * 3 // 4))
    sid = c.request(b"POST", b"/up", [(b"x-tag", b"p")], body)
    exchange(c, t, lambda: c.streams[sid].closed)
    check(c.streams[sid].status == 200 and bytes(c.streams[sid].body) == b"POST /up p " + body, "upload echo")
    c.close(); t.finish(); count += 1
    # Our sending honours a small client window and resumes on WINDOW_UPDATE.
    t = connect(); c = ng.Client(settings=[(ng.INITIAL_WINDOW_SIZE, 1000)], manual_window=True)
    sid = c.request(b"GET", b"/big/100000")
    seen = {"n": 0}

    def consume():
        n = len(c.streams[sid].body)
        if n > seen["n"]:
            c.consume(sid, n - seen["n"]); seen["n"] = n
    exchange(c, t, lambda: c.streams[sid].closed, on_data=consume)
    want = bytes(97 + i % 26 for i in range(100000))
    check(bytes(c.streams[sid].body) == want and c.streams[sid].error == 0, "flow-controlled download")
    check(0 < c.max_data_frame <= 1000, ("data frame within window", c.max_data_frame))
    c.close(); t.finish(); count += 1
    # PING is acknowledged.
    t = connect(); c = ng.Client(); c.ping()
    exchange(c, t, lambda: any(k == ng.PING and f & 1 for k, f, s in c.frames))
    c.close(); t.finish(); count += 1
    # A request body over body_bytes gets 413 without reaching the handler.
    t = connect(); c = ng.Client()
    sid = c.request(b"POST", b"/up", [], bytes(limits["body"] + 1000))
    exchange(c, t, lambda: c.streams[sid].closed)
    check(c.streams[sid].status == 413, ("413", c.streams[sid].status))
    c.close(); t.finish(); count += 1
    # Client GOAWAY: the open stream still completes, then the server ends.
    t = connect(); c = ng.Client()
    sid = c.request(b"GET", b"/last"); c.goaway_submit(0)
    exchange(c, t, lambda: c.streams[sid].closed)
    check(c.streams[sid].status == 200, "response after client GOAWAY")
    code, rest = t.finish()
    check(code in (None, 0), ("server exit after GOAWAY", code))
    c.close(); count += 1
    return count


def raw_cases(connect, limits):
    count = 0

    def expect_goaway(payload, code, what):
        t = connect(); fs = raw(t, payload); t.finish()
        check(goaway_code(fs) == code, (what, goaway_code(fs), [(k, s) for k, f, s, p in fs]))

    def expect_reset(payload, stream, code, what, then=None):
        t = connect(); fs = raw(t, payload + (then or b"")); t.finish()
        check(resets(fs).get(stream) == code, (what, resets(fs)))
        if then:
            check(3 in responses(fs), (what, "connection still serves", responses(fs)))

    t = connect(); t.send(PREFACE[:-4] + b"XXXX" + frame(4, 0, 0, b"")); fs = []
    end = time.time() + 1.0; got = b""
    while time.time() < end:
        d = t.recv(0.05)
        if d is None: continue
        if d == b"": break
        got += d
    t.finish()
    # The engine answers GOAWAY; the service treats it as a malformed
    # HTTP/1.1 head and answers 400.
    if limits.get("http1"):
        check(got.startswith(b"HTTP/1.1 400"), ("bad preface", got[:40]))
    else:
        check(goaway_code(frames(got)) == 1, "bad preface")
    count += 1
    after = frame(1, 5, 3, block(get(b"/after")))
    expect_goaway(frame(0, 0, 0, b"x"), 1, "DATA on stream 0"); count += 1
    expect_goaway(frame(1, 5, 2, block(get())), 1, "HEADERS on an even stream"); count += 1
    expect_goaway(frame(1, 4, 1, bytes(16385)), 6, "frame over MAX_FRAME_SIZE"); count += 1
    expect_goaway(frame(1, 5, 1, b"\x80"), 9, "invalid HPACK index"); count += 1
    expect_goaway(frame(8, 0, 0, b"\0\0\0\0"), 1, "zero WINDOW_UPDATE on the connection"); count += 1
    expect_goaway(frame(1, 0, 1, block(get())) + frame(0, 1, 1, b"x"), 1, "frame inside a header block"); count += 1
    expect_goaway(frame(4, 0, 0, struct.pack(">HI", 4, 1 << 31)), 3, "INITIAL_WINDOW_SIZE over 2^31-1"); count += 1
    expect_goaway(frame(5, 4, 1, b"\0\0\0\2" + block(get())), 1, "PUSH_PROMISE from a client"); count += 1
    post = [(b":method", b"POST"), (b":scheme", b"http"), (b":authority", b"x"), (b":path", b"/up")]
    expect_goaway(frame(8, 0, 0, struct.pack(">I", 0x7fffffff)), 3, "connection send window over 2^31-1"); count += 1
    expect_reset(frame(1, 4, 1, block(get())) + frame(8, 0, 1, struct.pack(">I", 0x7fffffff)), 1, 3, "stream send window over 2^31-1", after); count += 1
    expect_reset(frame(1, 5, 1, block(get()[:3])), 1, 1, "request without :path", after); count += 1
    expect_reset(frame(1, 5, 1, block(get() + [(b"X-Upper", b"v")])), 1, 1, "uppercase field name", after); count += 1
    expect_reset(frame(1, 5, 1, block(get() + [(b"connection", b"close")])), 1, 1, "connection-specific field", after); count += 1
    expect_reset(frame(1, 5, 1, block(get() + [(b":path", b"/")])), 1, 1, "duplicate pseudo-field", after); count += 1
    expect_reset(frame(1, 4, 1, block(post + [(b"content-length", b"5")])) + frame(0, 1, 1, b"abc"), 1, 1, "content-length mismatch", after); count += 1
    # Streams beyond MAX_CONCURRENT_STREAMS are refused, the rest survive.
    n = limits["streams"]
    opened = b"".join(frame(1, 4, 2 * i + 1, block(post)) for i in range(n + 1))
    t = connect(); fs = raw(t, opened); t.finish()
    check(resets(fs).get(2 * n + 1) == 7 and len(resets(fs)) == 1, ("refused stream", resets(fs))); count += 1
    # Unknown frame types are ignored.
    t = connect(); fs = raw(t, frame(0x20, 0, 0, b"zz") + frame(1, 5, 1, block(get(b"/u")))); t.finish()
    check(1 in responses(fs) and goaway_code(fs) is None, "unknown frame type ignored"); count += 1
    return count


def main():
    mode, exe = sys.argv[1], sys.argv[2]
    if mode == "pipe":
        limits = {"streams": 8, "body": 200000, "connection_window": 65535}
        connect = lambda: Pipe(exe)
        a = nghttp2_cases(connect, limits)
        b = raw_cases(connect, limits)
        print("http2-server-engine nghttp2=%d raw=%d" % (a, b))
        return
    if mode == "tcp":
        server = subprocess.Popen([exe], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            port = int(server.stdout.readline().decode().rsplit(":", 1)[1])
            limits = {"streams": 100, "body": 200000, "connection_window": 4194304, "http1": True}
            connect = lambda: Tcp(port)
            a = nghttp2_cases(connect, limits)
            b = raw_cases(connect, limits)
            # The same listener still serves HTTP/1.1.
            s1 = socket.create_connection(("127.0.0.1", port), timeout=5)
            s1.sendall(b"GET /plain HTTP/1.1\r\nHost: x\r\n\r\n")
            reply = b""
            while True:
                d = s1.recv(65536)
                if not d: break
                reply += d
            s1.close()
            check(reply.startswith(b"HTTP/1.1 200") and reply.endswith(b"h1 /plain"), ("HTTP/1.1 fallback", reply[-60:]))
            print("http2-server-h2c nghttp2=%d raw=%d http1=1" % (a, b))
        finally:
            server.kill(); server.wait()
        return
    raise SystemExit("unknown mode")


if __name__ == "__main__":
    main()
