#!/usr/bin/env python3
"""Loopback oracle for sample_programs/library/http_curl.lani (ext::http_agent).

usage: oracle.py GROUP EXE

GROUP: pool, redirect, upload, broken, or all.

Origins are http.server ThreadingHTTPServer instances on 127.0.0.1:0 (two of
them, for cross-origin redirects); broken servers are scripted raw sockets.
Every case checks the client's exit code, output and its own "pool ..." and
"response ..." statistics lines against the oracle, and the server-observed
connection and request counts. Prints one line per group:
http-agent-GROUP cases=N connections=C requests=R
"""
import hashlib
import http.server
import os
import random
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse

EXE = None
LOCK = threading.Lock()
TOTAL = {"connections": 0, "requests": 0}


class Failure(Exception):
    pass


def expect(cond, what):
    if not cond:
        raise Failure(what)


def pattern(n, seed=7):
    return bytes(((i * 73 + seed) % 256) for i in range(n))


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def setup(self):
        super().setup()
        with LOCK:
            self.server.connections += 1
        self.drop_next = False

    def read_body(self):
        te = self.headers.get("Transfer-Encoding")
        chunks = []
        if te is not None:
            expect(te.lower() == "chunked", "request transfer-encoding " + te)
            data = b""
            while True:
                line = self.rfile.readline(1024).strip()
                size = int(line.split(b";")[0], 16)
                if size == 0:
                    while self.rfile.readline(1024) not in (b"\r\n", b"\n", b""):
                        pass
                    break
                chunk = self.rfile.read(size)
                chunks.append(size)
                data += chunk
                expect(self.rfile.read(2) == b"\r\n", "chunk CRLF")
            return data, chunks
        length = self.headers.get("Content-Length")
        if length is not None:
            return self.rfile.read(int(length)), chunks
        return b"", chunks

    def reply(self, status, body=b"", headers=(), head=False):
        self.send_response(status)
        for k, v in headers:
            self.send_header(k, v)
        if not any(k.lower() == "transfer-encoding" for k, _ in headers):
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if not head and self.command != "HEAD":
            self.wfile.write(body)

    def handle_any(self):
        with LOCK:
            self.server.requests += 1
            self.server.log.append((self.command, self.path, dict(self.headers.items())))
        if self.drop_next:
            # Read the request, then hang up without a response.
            self.read_body()
            self.close_connection = True
            return
        url = urllib.parse.urlsplit(self.path)
        path, query = url.path, urllib.parse.parse_qs(url.query)
        if path == "/early":
            self.send_response(413)
            self.send_header("Content-Length", "9")
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(b"too much\n")
            self.wfile.flush()
            self.connection.shutdown(socket.SHUT_WR)
            drained = 0
            self.connection.settimeout(0.5)
            try:
                while True:
                    got = self.connection.recv(65536)
                    if not got:
                        break
                    drained += len(got)
            except OSError:
                pass
            self.server.drained = drained
            self.close_connection = True
            return
        body, chunks = self.read_body()
        if path == "/hello":
            return self.reply(200, b"hello\n")
        if path == "/dir/hello":
            return self.reply(200, b"dir hello\n")
        if path.startswith("/bytes/"):
            return self.reply(200, pattern(int(path[7:])))
        if path.startswith("/chunked/"):
            n = int(path[9:])
            data = pattern(n, 11)
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.end_headers()
            for i in range(0, n, 1000):
                piece = data[i:i + 1000]
                self.wfile.write(b"%x\r\n%s\r\n" % (len(piece), piece))
            self.wfile.write(b"0\r\nX-Trailer: yes\r\n\r\n")
            return
        if path == "/echo":
            h = self.headers
            lines = [
                "method=" + self.command, "len=%d" % len(body), "sha=" + hashlib.sha256(body).hexdigest()[:16],
                "te=%s" % h.get("Transfer-Encoding"), "cl=%s" % h.get("Content-Length"),
                "ctype=%s" % h.get("Content-Type"), "auth=%s" % h.get("Authorization"), "cookie=%s" % h.get("Cookie"),
                "xtest=%s" % h.get("X-Test"), "conn=%s" % h.get("Connection"), "chunks=%d" % len(chunks),
                "maxchunk=%d" % (max(chunks) if chunks else 0), "host=%s" % h.get("Host"),
            ]
            return self.reply(200, ("\n".join(lines) + "\n").encode())
        if path == "/redirect":
            code = int(query["code"][0])
            return self.reply(code, b"redirect\n", [("Location", query["to"][0])])
        if path.startswith("/chain/"):
            n = int(path[7:])
            if n == 0:
                return self.reply(200, b"end\n")
            return self.reply(302, b"hop\n", [("Location", "/chain/%d" % (n - 1))])
        if path == "/loop":
            return self.reply(302, b"loop\n", [("Location", "/loop")])
        if path.startswith("/dir/sub/rel"):
            if url.query:
                return self.reply(200, ("rel query " + url.query + "\n").encode())
            where = {"1": "../hello", "2": "./../../hello", "3": "?x=1",
                     "4": "//localhost:%d/hello" % self.server.server_address[1], "5": "/hello#frag"}[path[12:]]
            return self.reply(302, b"rel\n", [("Location", where)])
        if path == "/nolocation":
            return self.reply(302, b"no location\n")
        if path == "/tohttps":
            return self.reply(302, b"https\n", [("Location", "https://127.0.0.1/")])
        if path == "/badloc":
            return self.reply(302, b"bad\n", [("Location", "http://[::1/x")])
        if path == "/close":
            self.close_connection = True
            return self.reply(200, b"closing\n", [("Connection", "close")])
        if path.startswith("/ka/"):
            return self.reply(200, b"ka\n", [("Keep-Alive", "timeout=" + path[4:])])
        if path == "/http10":
            self.wfile.write(b"HTTP/1.0 200 OK\r\nContent-Length: 4\r\n\r\nv10\n")
            self.close_connection = True
            return
        if path == "/http10ka":
            self.wfile.write(b"HTTP/1.0 200 OK\r\nConnection: keep-alive\r\nContent-Length: 4\r\n\r\nka!\n")
            return
        if path == "/extra":
            self.wfile.write(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nok\nJUNK")
            return
        if path == "/dropnext":
            self.drop_next = True
            return self.reply(200, b"armed\n")
        if path == "/idle-close":
            self.close_connection = True
            return self.reply(200, b"bye\n")
        if path == "/info":
            self.wfile.write(b"HTTP/1.1 100 Continue\r\n\r\nHTTP/1.1 103 Early Hints\r\nLink: </s.css>\r\n\r\n")
            return self.reply(200, b"after info\n")
        if path == "/nocontent":
            self.send_response(204)
            self.end_headers()
            return
        return self.reply(404, b"missing\n")

    do_GET = do_POST = do_PUT = do_HEAD = do_PATCH = do_DELETE = do_OPTIONS = handle_any


class Origin(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        self.connections = 0
        self.requests = 0
        self.log = []
        self.drained = None
        threading.Thread(target=self.serve_forever, daemon=True).start()

    @property
    def base(self):
        return "http://127.0.0.1:%d" % self.server_address[1]

    def reset(self):
        with LOCK:
            TOTAL["connections"] += self.connections
            TOTAL["requests"] += self.requests
            self.connections = 0
            self.requests = 0
            self.log = []
            self.drained = None


class Raw:
    """One scripted raw-socket server per case."""

    def __init__(self, behavior):
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(8)
        self.behavior = behavior
        self.connections = 0
        threading.Thread(target=self.loop, daemon=True).start()

    @property
    def base(self):
        return "http://127.0.0.1:%d" % self.sock.getsockname()[1]

    def loop(self):
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            self.connections += 1
            threading.Thread(target=self.run, args=(conn,), daemon=True).start()

    def run(self, conn):
        try:
            data = b""
            while b"\r\n\r\n" not in data:
                got = conn.recv(65536)
                if not got:
                    return
                data += got
            self.behavior(conn)
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    def close(self):
        with LOCK:
            TOTAL["connections"] += self.connections
        self.sock.close()


def client(args, stdin=b"", timeout=30):
    started = time.monotonic()
    r = subprocess.run([EXE] + args, input=stdin, capture_output=True, timeout=timeout)
    elapsed = time.monotonic() - started
    pool, responses = {}, []
    for line in r.stderr.decode(errors="replace").splitlines():
        if line.startswith("pool "):
            pool = dict(kv.split("=", 1) for kv in line[5:].split())
            pool = {k: int(v) for k, v in pool.items()}
        elif line.startswith("response "):
            fields = dict(kv.split("=", 1) for kv in line[9:].split(" url=")[0].split())
            fields["url"] = line.split(" url=", 1)[1]
            responses.append(fields)
    return r.returncode, r.stdout, r.stderr.decode(errors="replace"), pool, responses, elapsed


def fields(body):
    return dict(line.split("=", 1) for line in body.decode().splitlines() if "=" in line)


def pool_has(pool, **want):
    for k, v in want.items():
        expect(pool.get(k) == v, "pool %s=%s, want %s (%s)" % (k, pool.get(k), v, pool))


# ---------------------------------------------------------------- groups

def group_pool(a, b):
    cases = []

    def case(fn):
        cases.append(fn)
        return fn

    @case
    def reuse_three():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/hello", a.base + "/hello", a.base + "/hello"])
        expect(rc == 0 and out == b"hello\n" * 3, (rc, out, err))
        pool_has(pool, connections=1, reused=2, requests=3, idle=1)
        expect([r["reused"] for r in rs] == ["0", "1", "1"], rs)
        expect(a.connections == 1 and a.requests == 3, (a.connections, a.requests))

    @case
    def per_host_keys():
        # 127.0.0.1 and localhost are different pool keys for the same server.
        port = a.server_address[1]
        local = "http://localhost:%d" % port
        rc, out, err, pool, _, _ = client(["--stats", a.base + "/hello", local + "/hello", a.base + "/hello", local + "/hello"])
        expect(rc == 0 and out == b"hello\n" * 4, (rc, err))
        pool_has(pool, connections=2, reused=2, idle=2)
        expect(a.connections == 2, a.connections)

    @case
    def total_limit_evicts_oldest():
        rc, out, err, pool, _, _ = client(["--stats", "--max-idle", "1", a.base + "/hello", b.base + "/hello", a.base + "/hello"])
        expect(rc == 0, err)
        pool_has(pool, connections=3, reused=0, evicted=2, idle=1)
        expect(a.connections == 2 and b.connections == 1, (a.connections, b.connections))

    @case
    def per_host_limit_with_preconnect():
        rc, out, err, pool, _, _ = client(["--stats", "--preconnect", "3", "--max-idle-per-host", "2", a.base + "/hello", a.base + "/hello"])
        expect(rc == 0 and out == b"hello\n" * 2, err)
        pool_has(pool, connections=3, reused=2, evicted=1, idle=2)
        expect(a.connections == 3 and a.requests == 2, (a.connections, a.requests))

    @case
    def max_uses():
        rc, out, err, pool, _, _ = client(["--stats", "--max-uses", "2"] + [a.base + "/hello"] * 3)
        expect(rc == 0, err)
        pool_has(pool, connections=2, reused=1)
        expect(a.connections == 2, a.connections)

    @case
    def idle_timeout_expires():
        rc, out, err, pool, _, _ = client(["--stats", "--idle-timeout", "150", "--pause", "400", a.base + "/hello", a.base + "/hello"])
        expect(rc == 0, err)
        pool_has(pool, connections=2, reused=0, expired=1)

    @case
    def server_keep_alive_hint():
        rc, out, err, pool, _, _ = client(["--stats", "--pause", "800", a.base + "/ka/1", a.base + "/hello"])
        expect(rc == 0 and out == b"ka\nhello\n", err)
        pool_has(pool, connections=2, expired=1)

    @case
    def connection_close_not_pooled():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/close", a.base + "/hello"])
        expect(rc == 0 and out == b"closing\nhello\n", err)
        pool_has(pool, connections=2, reused=0)
        expect(rs[0]["kept"] == "0" and rs[1]["kept"] == "1", rs)

    @case
    def http10_closes():
        rc, out, err, pool, _, _ = client(["--stats", a.base + "/http10", a.base + "/hello"])
        expect(rc == 0 and out == b"v10\nhello\n", err)
        pool_has(pool, connections=2)

    @case
    def http10_keep_alive():
        rc, out, err, pool, _, _ = client(["--stats", a.base + "/http10ka", a.base + "/hello"])
        expect(rc == 0 and out == b"ka!\nhello\n", err)
        pool_has(pool, connections=1, reused=1)

    @case
    def trailing_bytes_not_pooled():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/extra", a.base + "/hello"])
        expect(rc == 0 and out == b"ok\nhello\n", err)
        pool_has(pool, connections=2)
        expect(rs[0]["kept"] == "0", rs)

    @case
    def stale_probe():
        rc, out, err, pool, _, _ = client(["--stats", "--pause", "300", a.base + "/idle-close", a.base + "/hello"])
        expect(rc == 0 and out == b"bye\nhello\n", err)
        pool_has(pool, connections=2, stale=1, retries=0, reused=0)

    @case
    def stale_retry_get():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/dropnext", a.base + "/hello"])
        expect(rc == 0 and out == b"armed\nhello\n", err)
        pool_has(pool, connections=2, reused=1, retries=1, requests=3)
        expect(a.requests == 3, a.requests)

    @case
    def no_retry_for_post():
        rc, out, err, pool, _, _ = client(["--stats", "-d", "x", a.base + "/dropnext", a.base + "/echo"])
        expect(rc == 52 and out == b"armed\n" and "empty reply" in err, (rc, out, err))
        pool_has(pool, connections=1, retries=0, requests=2)

    @case
    def no_retry_option():
        rc, out, err, pool, _, _ = client(["--stats", "--no-retry", a.base + "/dropnext", a.base + "/hello"])
        expect(rc == 52, (rc, err))
        pool_has(pool, retries=0)

    @case
    def pool_disabled_sends_close():
        rc, out, err, pool, _, _ = client(["--stats", "--max-idle", "0"] + [a.base + "/echo"] * 3)
        expect(rc == 0 and out.count(b"conn=close") == 3, (rc, out))
        pool_has(pool, connections=3, reused=0, idle=0)

    @case
    def chunked_response_then_reuse():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/chunked/5500", a.base + "/bytes/70000"])
        expect(rc == 0 and out == pattern(5500, 11) + pattern(70000), (rc, len(out), err))
        pool_has(pool, connections=1, reused=1)

    @case
    def head_and_204_reuse():
        rc, out, err, pool, _, _ = client(["--stats", "-I", a.base + "/bytes/1000", a.base + "/nocontent", a.base + "/hello"])
        expect(rc == 0 and out.startswith(b"HTTP/1.1 200") and b"Content-Length: 1000" in out and b"HTTP/1.1 204" in out, (rc, out, err))
        pool_has(pool, connections=1, reused=2)

    return cases


def group_redirect(a, b):
    cases = []

    def case(fn):
        cases.append(fn)
        return fn

    def redirect(code, to):
        return a.base + "/redirect?" + urllib.parse.urlencode({"code": code, "to": to})

    @case
    def chain_follows_on_one_connection():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", a.base + "/chain/3"])
        expect(rc == 0 and out == b"end\n", (rc, err))
        pool_has(pool, connections=1, reused=3, redirects=3, requests=4)
        expect(rs[0]["redirects"] == "3" and rs[0]["url"] == a.base + "/chain/0", rs)

    @case
    def not_followed_without_L():
        rc, out, err, pool, rs, _ = client(["--stats", a.base + "/chain/3"])
        expect(rc == 0 and out == b"hop\n" and rs[0]["status"] == "302", (rc, out, rs))
        pool_has(pool, redirects=0)

    @case
    def hop_limit_exceeded():
        rc, out, err, pool, _, _ = client(["--stats", "-L", "--max-redirs", "2", a.base + "/chain/3"])
        expect(rc == 47 and "too many redirects" in err, (rc, err))
        expect(a.requests == 3, a.requests)

    @case
    def hop_limit_exact():
        rc, out, err, pool, _, _ = client(["--stats", "-L", "--max-redirs", "3", a.base + "/chain/3"])
        expect(rc == 0 and out == b"end\n", (rc, err))

    @case
    def loop_stops_at_default_limit():
        rc, out, err, pool, _, _ = client(["--stats", "-L", a.base + "/loop"])
        expect(rc == 47, (rc, err))
        expect(a.requests == 11 and a.connections == 1, (a.requests, a.connections))

    # (method, code, body) -> (method seen, body length seen)
    table = [
        ("POST", 301, "GET", 0), ("POST", 302, "GET", 0), ("POST", 303, "GET", 0), ("POST", 307, "POST", 5), ("POST", 308, "POST", 5),
        ("PUT", 301, "PUT", 5), ("PUT", 302, "PUT", 5), ("PUT", 303, "GET", 0), ("PUT", 307, "PUT", 5),
        ("DELETE", 303, "GET", 0), ("GET", 303, "GET", 0),
    ]
    for method, code, seen, length in table:
        def method_rule(method=method, code=code, seen=seen, length=length):
            rc, out, err, pool, rs, _ = client(["--stats", "-L", "-X", method, "-d", "hello", "-H", "Content-Type: text/plain", redirect(code, "/echo")])
            expect(rc == 0, (rc, err))
            f = fields(out)
            expect(f["method"] == seen and f["len"] == str(length), (method, code, f))
            expect(f["ctype"] == ("text/plain" if length else "None"), f)
            expect(f["cl"] == ("5" if length else "None"), f)
            expect(a.connections == 1, a.connections)
        method_rule.__name__ = "method_%s_%d" % (method, code)
        cases.append(method_rule)

    @case
    def head_stays_head_on_303():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", "-I", redirect(303, "/hello")])
        expect(rc == 0 and out.startswith(b"HTTP/1.1 200") and b"Content-Length: 6" in out and not out.endswith(b"hello\n"), (rc, out))
        expect([m for m, _, _ in a.log] == ["HEAD", "HEAD"], a.log)

    relative = [("1", "/dir/hello", b"dir hello\n"), ("2", "/hello", b"hello\n"), ("3", "/dir/sub/rel3?x=1", b"rel query x=1\n"), ("5", "/hello", b"hello\n")]
    for n, path, body in relative:
        def relative_location(n=n, path=path, body=body):
            rc, out, err, pool, rs, _ = client(["--stats", "-L", a.base + "/dir/sub/rel" + n])
            expect(rc == 0 and out == body, (rc, out, err))
            expect(a.log[-1][1] == path and rs[0]["url"] == a.base + path, (a.log, rs))
        relative_location.__name__ = "relative_" + n
        cases.append(relative_location)

    @case
    def network_path_reference_is_new_host():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", a.base + "/dir/sub/rel4"])
        expect(rc == 0 and out == b"hello\n", (rc, err))
        pool_has(pool, connections=2, reused=0)
        expect(rs[0]["url"] == "http://localhost:%d/hello" % a.server_address[1], rs)

    @case
    def cross_origin_drops_credentials():
        rc, out, err, pool, _, _ = client(["-L", "-H", "Authorization: Bearer t", "-H", "Cookie: a=1", "-H", "X-Test: 1", redirect(302, b.base + "/echo")])
        f = fields(out)
        expect(rc == 0 and f["auth"] == "None" and f["cookie"] == "None" and f["xtest"] == "1", (rc, f))
        expect(f["host"] == "127.0.0.1:%d" % b.server_address[1], f)

    @case
    def same_origin_keeps_credentials():
        rc, out, err, pool, _, _ = client(["-L", "-H", "Authorization: Bearer t", "-H", "Cookie: a=1", redirect(307, "/echo")])
        f = fields(out)
        expect(rc == 0 and f["auth"] == "Bearer t" and f["cookie"] == "a=1", (rc, f))

    @case
    def missing_location_is_final():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", a.base + "/nolocation"])
        expect(rc == 0 and out == b"no location\n" and rs[0]["status"] == "302", (rc, out))

    @case
    def https_location_refused():
        rc, out, err, *_ = client(["-L", a.base + "/tohttps"])
        expect(rc == 1 and "unsupported scheme" in err, (rc, err))

    @case
    def malformed_location():
        rc, out, err, *_ = client(["-L", a.base + "/badloc"])
        expect(rc == 3 and "bad redirect location" in err, (rc, err))

    @case
    def streamed_body_cannot_follow_307():
        rc, out, err, *_ = client(["-L", "-T", "-", redirect(307, "/echo")], stdin=pattern(5000))
        expect(rc == 65, (rc, err))

    @case
    def streamed_body_303_becomes_get():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", "-T", "-", redirect(303, "/echo")], stdin=pattern(5000))
        f = fields(out)
        expect(rc == 0 and f["method"] == "GET" and f["len"] == "0" and f["te"] == "None", (rc, f))
        expect(a.log[0][0] == "PUT" and a.log[0][2].get("Transfer-Encoding") == "chunked", a.log[0])

    return cases


def group_upload(a, b):
    cases = []

    def case(fn):
        cases.append(fn)
        return fn

    def check_echo(out, data, method, chunked):
        f = fields(out)
        expect(f["method"] == method and f["len"] == str(len(data)) and f["sha"] == hashlib.sha256(data).hexdigest()[:16], f)
        if chunked:
            expect(f["te"] == "chunked" and f["cl"] == "None", f)
            expect(f["chunks"] == str(-(-len(data) // 16384)) and int(f["maxchunk"]) <= 16384, f)
        else:
            expect(f["te"] == "None" and f["cl"] == str(len(data)), f)
        return f

    @case
    def stdin_chunked():
        data = random.Random(1).randbytes(100000)
        rc, out, err, *_ = client(["-T", "-", a.base + "/echo"], stdin=data)
        expect(rc == 0, (rc, err))
        check_echo(out, data, "PUT", True)

    @case
    def file_chunked_twice_on_one_connection():
        data = random.Random(2).randbytes(300001)
        with tempfile.NamedTemporaryFile(dir=WORK, delete=False) as f:
            f.write(data)
        try:
            rc, out, err, pool, _, _ = client(["--stats", "-T", f.name, a.base + "/echo", a.base + "/echo"])
        finally:
            os.unlink(f.name)
        expect(rc == 0, (rc, err))
        halves = out.split(b"host=")
        check_echo(halves[0], data, "PUT", True)
        pool_has(pool, connections=1, reused=1)

    @case
    def empty_stream():
        rc, out, err, *_ = client(["-T", "-", a.base + "/echo"], stdin=b"")
        f = fields(out)
        expect(rc == 0 and f["te"] == "chunked" and f["len"] == "0" and f["chunks"] == "0", (rc, f))

    @case
    def fixed_body():
        rc, out, err, *_ = client(["-d", "abc", a.base + "/echo"])
        expect(rc == 0, err)
        check_echo(out, b"abc", "POST", False)

    @case
    def patch_stream():
        data = pattern(16384 * 2)
        rc, out, err, *_ = client(["-X", "PATCH", "-T", "-", a.base + "/echo"], stdin=data)
        expect(rc == 0, err)
        check_echo(out, data, "PATCH", True)

    @case
    def get_without_body_has_no_length():
        rc, out, err, *_ = client([a.base + "/echo"])
        f = fields(out)
        expect(rc == 0 and f["cl"] == "None" and f["te"] == "None" and f["method"] == "GET", f)

    @case
    def early_response_stops_upload():
        size = 32 * 1024 * 1024
        rc, out, err, pool, rs, elapsed = client(["--stats", "-T", "-", a.base + "/early"], stdin=b"\0" * size)
        expect(rc == 0 and out == b"too much\n" and rs[0]["status"] == "413" and rs[0]["kept"] == "0", (rc, out, err))
        pool_has(pool, early=1, idle=0)
        expect(a.drained is not None and a.drained < size // 2, a.drained)

    @case
    def early_response_with_fail():
        rc, out, err, *_ = client(["-f", "-T", "-", a.base + "/early"], stdin=b"\0" * (4 * 1024 * 1024))
        expect(rc == 22 and out == b"", (rc, err))

    @case
    def reserved_header_rejected():
        rc, out, err, *_ = client(["-H", "Content-Length: 3", a.base + "/echo"])
        expect(rc == 2 and "invalid header" in err and a.requests == 0, (rc, err))

    @case
    def header_injection_rejected():
        rc, out, err, *_ = client(["-H", "X-Test: a\rb", a.base + "/echo"])
        expect(rc == 2 and a.requests == 0, (rc, err))

    return cases


def group_broken(a, b):
    cases = []

    def case(fn):
        cases.append(fn)
        return fn

    def raw(behavior, args, want_rc, want_out=None, text=None, connections=1, slow=None):
        server = Raw(behavior)
        try:
            rc, out, err, pool, rs, elapsed = client(args + [server.base + "/x"])
            expect(rc == want_rc, (rc, want_rc, err))
            if want_out is not None:
                expect(out == want_out, out)
            if text is not None:
                expect(text in err, err)
            expect(server.connections == connections, server.connections)
            if slow is not None:
                expect(elapsed < slow, elapsed)
            return pool
        finally:
            server.close()

    def send(data, then=None):
        def behavior(conn):
            conn.sendall(data)
            if then:
                then(conn)
        return behavior

    def stall(conn):
        time.sleep(3)

    @case
    def empty_reply():
        raw(lambda c: None, [], 52, text="empty reply")

    @case
    def truncated_body():
        raw(send(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789"), [], 18, text="truncated")

    @case
    def truncated_head():
        raw(send(b"HTTP/1.1 200 OK\r\nContent-Le"), [], 18)

    @case
    def garbage_status_line():
        raw(send(b"HELLO WORLD\r\n\r\n"), [], 8, text="malformed")

    @case
    def bad_chunk_size():
        raw(send(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nabc\r\n0\r\n\r\n"), [], 8)

    @case
    def length_and_chunked():
        raw(send(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n"), [], 8)

    @case
    def duplicate_lengths_disagree():
        raw(send(b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Length: 4\r\n\r\nabcd"), [], 8)

    @case
    def stalled_head_times_out():
        raw(stall, ["--max-time", "300"], 28, text="timed out", slow=2.0)

    @case
    def stalled_body_times_out():
        raw(send(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789", stall), ["--max-time", "300"], 28, slow=2.0)

    def drip(conn):
        for c in b"HTTP/1.1 200 OK\r\nContent-Length: 4\r\n\r\ndrip":
            conn.sendall(bytes([c]))
            time.sleep(0.02)

    @case
    def slow_drip_within_deadline():
        raw(drip, ["--max-time", "5000"], 0, want_out=b"drip")

    @case
    def slow_drip_past_absolute_deadline():
        raw(drip, ["--max-time", "300"], 28, slow=2.0)

    @case
    def upgrade_refused():
        raw(send(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n"), [], 8, text="unexpected upgrade")

    @case
    def oversized_header():
        raw(send(b"HTTP/1.1 200 OK\r\nX-Big: " + b"a" * 70000 + b"\r\n\r\n"), [], 63, text="too large")

    @case
    def too_many_informational():
        raw(send(b"HTTP/1.1 100 Continue\r\n\r\n" * 9 + b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok"), [], 63)

    @case
    def informational_then_final():
        rc, out, err, *_ = client([a.base + "/info"])
        expect(rc == 0 and out == b"after info\n", (rc, out, err))

    @case
    def close_delimited_body():
        raw(send(b"HTTP/1.1 200 OK\r\n\r\nuntil close"), ["--stats"], 0, want_out=b"until close")

    @case
    def head_ignores_length():
        def keep_open(conn):
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n")
            time.sleep(2)
        raw(keep_open, ["-I"], 0, want_out=b"HTTP/1.1 200 OK\r\nContent-Length: 1000\r\n\r\n", slow=1.5)

    @case
    def connection_refused():
        s = socket.socket()
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
        s.close()
        rc, out, err, *_ = client(["http://127.0.0.1:%d/" % port])
        expect(rc == 7 and "connect failed" in err, (rc, err))

    @case
    def bad_url():
        rc, out, err, *_ = client(["http://[::1/"])
        expect(rc == 3, (rc, err))

    @case
    def https_url_refused():
        rc, out, err, *_ = client(["https://127.0.0.1:1/"])
        expect(rc == 1, (rc, err))

    @case
    def reset_mid_body():
        def rst(conn):
            conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123")
            conn.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, b"\x01\x00\x00\x00\x00\x00\x00\x00")
        raw(rst, [], 56, text="connection error")

    return cases


GROUPS = {"pool": group_pool, "redirect": group_redirect, "upload": group_upload, "broken": group_broken}


def run_group(name):
    a, b = Origin(), Origin()
    TOTAL["connections"] = TOTAL["requests"] = 0
    count = 0
    try:
        for fn in GROUPS[name](a, b):
            a.reset()
            b.reset()
            try:
                fn()
            except Failure as e:
                print("FAIL %s/%s: %s" % (name, fn.__name__, e), file=sys.stderr)
                sys.exit(1)
            except subprocess.TimeoutExpired:
                print("FAIL %s/%s: client timed out" % (name, fn.__name__), file=sys.stderr)
                sys.exit(1)
            count += 1
        a.reset()
        b.reset()
    finally:
        a.shutdown()
        b.shutdown()
    print("http-agent-%s cases=%d connections=%d requests=%d" % (name, count, TOTAL["connections"], TOTAL["requests"]))


def main():
    global EXE, WORK
    if len(sys.argv) != 3 or (sys.argv[1] not in GROUPS and sys.argv[1] != "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    WORK = tempfile.mkdtemp(prefix="http-agent-")
    try:
        for name in (list(GROUPS) if sys.argv[1] == "all" else [sys.argv[1]]):
            run_group(name)
    finally:
        os.rmdir(WORK)
    return 0


WORK = None
if __name__ == "__main__":
    sys.exit(main())
