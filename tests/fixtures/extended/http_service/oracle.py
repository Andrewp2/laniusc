#!/usr/bin/env python3
"""Loopback oracle for sample_programs/library/http_static.lani.

usage: oracle.py GROUP EXE   (GROUP: functional, malformed, slowloris, all)

Each group starts its own server on 127.0.0.1:0 over a fresh document root,
runs Python http.client/urllib/raw-socket cases, waits for the server to exit
after its accept timeout and checks the server's exact summary counters
against the oracle's own tally. Prints one line per group:
http-service-GROUP cases=N connections=C requests=R rejected=J timeouts=T
"""
import http.client
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request

TALLY = {"connections": 0, "requests": 0, "rejected": 0, "timeouts": 0}


class Counted(http.client.HTTPConnection):
    def connect(self):
        TALLY["connections"] += 1
        super().connect()


def check(cond, what):
    if not cond:
        raise AssertionError(what)


def make_root(base):
    root = os.path.join(base, "root")
    os.makedirs(os.path.join(root, "sub", "deeper"))
    os.makedirs(os.path.join(root, "we ird"))
    files = {
        "a.txt": b"hello world\n",
        "empty.txt": b"",
        "index.json": b'{"k": 1}\n',
        "a&b<c>.txt": b"escaped\n",
        "big.bin": bytes((i * 7919 + (i >> 8)) & 255 for i in range(300001)),
        "sub/i.html": b"<b>x</b>\n",
        "sub/deeper/z.css": b"p{}\n",
        "we ird/caf\u00e9.txt": b"unicode\n",
    }
    for name, data in files.items():
        with open(os.path.join(root, name), "wb") as f:
            f.write(data)
    return root, files


class Server:
    def __init__(self, exe, root, extra):
        args = [exe, root, "127.0.0.1:0", "--accept-timeout", "1500"] + extra
        self.proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        line = self.proc.stdout.readline().decode()
        m = re.match(r"127\.0\.0\.1:(\d+)\n", line)
        check(m, "startup line %r" % line)
        self.port = int(m.group(1))

    def finish(self):
        out, err = self.proc.communicate(timeout=60)
        check(self.proc.returncode == 0, "server exit %r %r" % (self.proc.returncode, err))
        check(err == b"", "stderr %r" % err)
        fields = dict(kv.split("=") for kv in out.decode().split())
        return {k: int(v) for k, v in fields.items()}


def http_conn(port):
    return Counted("127.0.0.1", port, timeout=10)


def get(conn, method, path, headers=None, body=None, chunked=False):
    TALLY["requests"] += 1
    conn.request(method, path, body=body, headers=headers or {}, encode_chunked=chunked)
    r = conn.getresponse()
    data = r.read()
    if os.environ.get("ORACLE_DEBUG") and r.getheader("Connection") != "keep-alive":
        print("closed after", method, path, r.status, file=sys.stderr)
    return r, data


def raw(port, data, pause=None, read_timeout=5.0, shut=False):
    """Send bytes (a list means separate writes), return (bytes until EOF, seconds)."""
    TALLY["connections"] += 1
    s = socket.create_connection(("127.0.0.1", port), timeout=read_timeout)
    start = time.monotonic()
    parts = data if isinstance(data, list) else [data]
    try:
        for p in parts:
            s.sendall(p)
            if pause:
                time.sleep(pause)
    except (BrokenPipeError, ConnectionResetError):
        pass
    if shut:
        s.shutdown(socket.SHUT_WR)
    got = b""
    try:
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            got += chunk
    except ConnectionResetError:
        pass
    s.close()
    return got, time.monotonic() - start


def trickle(port, data, pause, budget=6.0):
    """Send one byte per pause until the server answers or closes."""
    TALLY["connections"] += 1
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.settimeout(pause)
    start = time.monotonic()
    got = b""
    i = 0
    while time.monotonic() - start < budget:
        if i < len(data) and not got:
            try:
                s.sendall(data[i:i + 1])
            except (BrokenPipeError, ConnectionResetError):
                break
            i += 1
        try:
            c = s.recv(4096)
            if not c:
                break
            got += c
        except socket.timeout:
            pass
        except ConnectionResetError:
            break
    s.close()
    return got, time.monotonic() - start


def statuses(blob):
    return [int(m.group(1)) for m in re.finditer(rb"HTTP/1\.1 (\d{3}) ", blob)]


def functional(exe, base):
    root, files = make_root(base)
    srv = Server(exe, root, [])
    port = srv.port
    cases = 0
    conn = http_conn(port)
    # Plain files through one keep-alive connection.
    for name in ["a.txt", "empty.txt", "index.json", "big.bin", "sub/i.html", "sub/deeper/z.css"]:
        r, data = get(conn, "GET", "/" + name.replace(" ", "%20"))
        check(r.status == 200 and data == files[name], name)
        check(r.getheader("Content-Length") == str(len(files[name])), name)
        check(r.getheader("Accept-Ranges") == "bytes", name)
        cases += 1
    types = {"a.txt": "text/plain; charset=utf-8", "index.json": "application/json", "big.bin": "application/octet-stream", "sub/i.html": "text/html; charset=utf-8", "sub/deeper/z.css": "text/css"}
    for name, ctype in types.items():
        r, data = get(conn, "HEAD", "/" + name)
        check(r.status == 200 and data == b"" and r.getheader("Content-Type") == ctype and r.getheader("Content-Length") == str(len(files[name])), "HEAD " + name)
        cases += 1
    sock0 = conn.sock
    # Percent-encoded names and the escaped name.
    r, data = get(conn, "GET", "/we%20ird/caf%C3%A9.txt")
    check(r.status == 200 and data == b"unicode\n", "percent")
    cases += 1
    r, data = get(conn, "GET", "/a%26b%3Cc%3E.txt")
    check(r.status == 200 and data == b"escaped\n", "escaped name")
    cases += 1
    # Directory listings compare against the filesystem.
    for url, rel in [("/", ""), ("/sub/", "sub"), ("/sub/deeper/", "sub/deeper"), ("/we%20ird/", "we ird")]:
        r, data = get(conn, "GET", url)
        check(r.status == 200 and r.getheader("Content-Type") == "text/html; charset=utf-8", url)
        text = data.decode()
        hrefs = sorted(re.findall(r'<li><a href="([^"]*)">', text))
        want = []
        for e in os.listdir(os.path.join(root, rel)):
            q = urllib.request.quote(e, safe="-._~")
            want.append(q + "/" if os.path.isdir(os.path.join(root, rel, e)) else q)
        check(hrefs == sorted(want), "listing %s %r %r" % (url, hrefs, want))
        if rel == "":
            check("a&amp;b&lt;c&gt;.txt</a>" in text, "html escape")
        cases += 1
    # Every listed href resolves.
    r, data = get(conn, "GET", "/")
    for href in re.findall(r'<li><a href="([^"]*)">', data.decode()):
        r2, d2 = get(conn, "GET", "/" + href)
        check(r2.status == 200, "href " + href)
        cases += 1
    # Redirect without and with query.
    r, data = get(conn, "GET", "/sub")
    check(r.status == 301 and r.getheader("Location") == "/sub/" and data == b"", "redirect")
    r, data = get(conn, "GET", "/sub?x=1")
    check(r.status == 301 and r.getheader("Location") == "/sub/?x=1", "redirect query")
    cases += 2
    # Missing, traversal and method errors.
    for path, code in [("/nope", 404), ("/sub/nope.txt", 404), ("/../etc/passwd", 400), ("/%2e%2e/x", 400), ("/sub/../a.txt", 400), ("/a%2Fb", 400), ("/a%00b", 400), ("/a.txt/", 404)]:
        r, data = get(conn, "GET", path)
        check(r.status == code, "%s -> %d" % (path, r.status))
        cases += 1
    r, data = get(conn, "DELETE", "/healthz")
    check(r.status == 405 and r.getheader("Allow") == "GET, HEAD, POST", "405")
    r, data = get(conn, "GET", "/healthz")
    check(r.status == 200 and data == b"ok\n", "health")
    r, data = get(conn, "POST", "/a.txt", body=b"x")
    check(r.status == 405, "POST static")
    cases += 3
    # Ranges against Python slicing.
    big = files["big.bin"]
    size = len(big)
    for spec, first, last in [("0-0", 0, 0), ("5-", 5, size - 1), ("-5", size - 5, size - 1), ("0-999999999", 0, size - 1), ("100-200", 100, 200), ("-999999999", 0, size - 1), ("%d-%d" % (size - 1, size - 1), size - 1, size - 1), ("65535-65536", 65535, 65536)]:
        r, data = get(conn, "GET", "/big.bin", {"Range": "bytes=" + spec})
        check(r.status == 206 and data == big[first:last + 1], "range " + spec)
        check(r.getheader("Content-Range") == "bytes %d-%d/%d" % (first, last, size), "content-range " + spec)
        cases += 1
    for spec in ["bytes=%d-" % size, "bytes=-0", "bytes=999999999-"]:
        r, data = get(conn, "GET", "/big.bin", {"Range": spec})
        check(r.status == 416 and r.getheader("Content-Range") == "bytes */%d" % size and data == b"", "416 " + spec)
        cases += 1
    for spec in ["bytes=0-1,3-4", "bytes=x-y", "items=0-1", "bytes=5-2", "bytes=-", "bytes 0-1"]:
        r, data = get(conn, "GET", "/big.bin", {"Range": spec})
        check(r.status == 200 and data == big, "ignored " + spec)
        cases += 1
    r, data = get(conn, "HEAD", "/big.bin", {"Range": "bytes=10-19"})
    check(r.status == 206 and data == b"" and r.getheader("Content-Length") == "10", "HEAD range")
    r, data = get(conn, "GET", "/empty.txt", {"Range": "bytes=0-"})
    check(r.status == 416, "empty range")
    cases += 2
    # Echo: fixed, empty, binary 1 MiB-limit and chunked bodies.
    for body in [b"abc", b"", bytes(range(256)) * 64, os.urandom(1048576)]:
        r, data = get(conn, "POST", "/echo", body=body)
        check(r.status == 200 and data == body, "echo %d" % len(body))
        cases += 1
    pieces = [b"chunk-one ", b"", b"x" * 70000, b"tail"]
    r, data = get(conn, "POST", "/echo", body=iter([p for p in pieces if p]), chunked=True)
    check(r.status == 200 and data == b"".join(pieces), "chunked echo")
    cases += 1
    check(conn.sock is sock0, "keep-alive connection reused")
    cases += 1
    conn.close()
    # urllib follows the redirect over two connections.
    TALLY["connections"] += 2
    TALLY["requests"] += 2
    with urllib.request.urlopen("http://127.0.0.1:%d/sub" % port, timeout=10) as u:
        check(u.status == 200 and u.geturl().endswith("/sub/") and b"i.html" in u.read(), "urllib redirect")
    cases += 1
    # Pipelined requests on one connection, then Connection: close.
    pipe = b"".join(b"GET /%s HTTP/1.1\r\nHost: x\r\n\r\n" % n for n in [b"a.txt", b"healthz", b"nope"])
    pipe += b"GET /a.txt HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\nGET /a.txt HTTP/1.1\r\nHost: x\r\n\r\n"
    TALLY["requests"] += 4
    got, _ = raw(port, pipe)
    check(statuses(got) == [200, 200, 404, 200] and got.count(b"hello world\n") == 2 and got.count(b"Connection: close") == 1, "pipeline %r" % got[-200:])
    cases += 1
    # Pipelined bytes arriving one at a time.
    TALLY["requests"] += 2
    got, _ = raw(port, [bytes([c]) for c in b"GET /a.txt HTTP/1.1\r\nHost: x\r\n\r\nGET /healthz HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"])
    check(statuses(got) == [200, 200], "fragmented pipeline")
    cases += 1
    # Absolute-form targets route by their path.
    TALLY["requests"] += 2
    got, _ = raw(port, b"GET http://x/a.txt HTTP/1.1\r\nHost: x\r\n\r\nGET http://x HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    check(statuses(got) == [200, 200] and b"hello world\n" in got and b"Index of /" in got, "absolute-form")
    cases += 1
    # HTTP/1.0 closes unless asked; keep-alive is honored.
    TALLY["requests"] += 1
    got, _ = raw(port, b"GET /a.txt HTTP/1.0\r\n\r\nGET /a.txt HTTP/1.0\r\n\r\n")
    check(statuses(got) == [200] and b"Connection: close" in got, "1.0 close")
    TALLY["requests"] += 2
    got, _ = raw(port, b"GET /a.txt HTTP/1.0\r\nConnection: keep-alive\r\n\r\nGET /a.txt HTTP/1.0\r\n\r\n")
    check(statuses(got) == [200, 200] and got.count(b"Connection: keep-alive") == 1, "1.0 keep-alive")
    cases += 2
    # Expect: 100-continue sends the interim response before the body.
    TALLY["connections"] += 1
    TALLY["requests"] += 1
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    s.sendall(b"POST /echo HTTP/1.1\r\nHost: x\r\nExpect: 100-continue\r\nContent-Length: 5\r\nConnection: close\r\n\r\n")
    interim = s.recv(100)
    check(interim == b"HTTP/1.1 100 Continue\r\n\r\n", "100 %r" % interim)
    s.sendall(b"hello")
    rest = b""
    while True:
        c = s.recv(4096)
        if not c:
            break
        rest += c
    s.close()
    check(statuses(rest) == [200] and rest.endswith(b"hello"), "expect body")
    cases += 1
    stats = srv.finish()
    return cases, stats


MALFORMED = [
    (b"HELLO\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n", 400),
    (b"GET / HTTP/1.1\nHost: x\n\n", 400),
    (b"GET  / HTTP/1.1\r\nHost: x\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\nHost : x\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\nHost: x\r\n folded\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\nHost: x\r\nX: a\x00b\r\n\r\n", 400),
    (b"GET / HTTP/1.1\r\nHost: x\r\nX: a\x7fb\r\n\r\n", 400),
    (b"GET /a b HTTP/1.1\r\nHost: x\r\n\r\n", 400),
    (b"GET / HTTP/1.1 \r\nHost: x\r\n\r\n", 400),
    (b"GET / HTTP/1.2\r\nHost: x\r\n\r\n", 501),
    (b"GET / HTTP/2.0\r\nHost: x\r\n\r\n", 501),
    (b"GET / HTP/1.1\r\nHost: x\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3\r\nContent-Length: 3\r\n\r\nabc", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 3, 3\r\n\r\nabc", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: -1\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: abc\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n", 501),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.0\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nzz\r\nabc\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabcX\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n3;=x\r\nabc\r\n0\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n0\r\nContent-Length: 5\r\n\r\n", 400),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000\r\n\r\n", 413),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n100000\r\n" + b"y" * 1048576 + b"\r\n1\r\nz\r\n0\r\n\r\n", 413),
    (b"POST /echo HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFFFFFF\r\n", 413),
    (b"GET /" + b"a" * 9000 + b" HTTP/1.1\r\nHost: x\r\n\r\n", 431),
    (b"GET / HTTP/1.1\r\nHost: x\r\nX: " + b"v" * 9000 + b"\r\n\r\n", 431),
    (b"GET / HTTP/1.1\r\nHost: x\r\n" + b"".join(b"X%d: v\r\n" % i for i in range(70)) + b"\r\n", 431),
    (b"GET / HTTP/1.1\r\nHost: x\r\n" + b"X: " + b"v" * 4000 + b"\r\nY: " + b"v" * 4000 + b"\r\nZ: " + b"v" * 400 + b"\r\n\r\n", 431),
    (b"\r\n\r\n", 400),
    (b"GET /a%zz HTTP/1.1\r\nHost: x\r\n\r\n", 400),
]


def malformed(exe, base):
    root, files = make_root(base)
    srv = Server(exe, root, [])
    port = srv.port
    cases = 0
    for data, code in MALFORMED:
        got, _ = raw(port, data)
        TALLY["rejected"] += 1
        st = statuses(got)
        check(st == [code], "%r -> %r" % (data[:60], st))
        check(b"Connection: close" in got, "close %r" % data[:40])
        cases += 1
    # A valid request before a malformed one is answered first; nothing after.
    TALLY["requests"] += 1
    TALLY["rejected"] += 1
    got, _ = raw(port, b"GET /a.txt HTTP/1.1\r\nHost: x\r\n\r\nBROKEN\r\n\r\nGET /a.txt HTTP/1.1\r\nHost: x\r\n\r\n")
    check(statuses(got) == [200, 400], "good then bad %r" % statuses(got))
    cases += 1
    # Truncated head and truncated body, both half-closed by the peer.
    for data in [b"GET / HTTP/1.1\r\nHost: x\r\n", b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 10\r\n\r\nabc"]:
        TALLY["rejected"] += 1
        got, _ = raw(port, data, shut=True)
        check(statuses(got) == [400], "truncated %r" % got)
        cases += 1
    # Abrupt resets and empty connections count no request and no rejection.
    for _ in range(3):
        raw(port, b"", shut=True)
        cases += 1
    # The server still serves correctly afterwards.
    conn = http_conn(port)
    r, data = get(conn, "GET", "/big.bin")
    check(r.status == 200 and data == files["big.bin"], "after malformed")
    conn.close()
    cases += 1
    stats = srv.finish()
    return cases, stats


def slowloris(exe, base):
    root, files = make_root(base)
    srv = Server(exe, root, ["--head-timeout", "800", "--idle-timeout", "1200", "--body-timeout", "1000"])
    port = srv.port
    cases = 0

    def healthy():
        conn = http_conn(port)
        r, data = get(conn, "GET", "/healthz")
        check(r.status == 200 and data == b"ok\n", "healthy")
        conn.close()

    # 1. Head trickled one byte per 50 ms never completes: 408 at the absolute deadline.
    TALLY["rejected"] += 1
    TALLY["timeouts"] += 1
    data = b"GET / HTTP/1.1\r\nHost: x\r\n" + b"X-Pad: y\r\n" * 10
    got, secs = trickle(port, data, 0.05)
    check(statuses(got) == [408] and b"Connection: close" in got, "trickle %r" % got)
    check(0.7 <= secs < 2.0, "trickle bounded %f" % secs)
    healthy()
    cases += 2
    # 2. Endless header lines: still the same absolute head deadline.
    TALLY["connections"] += 1
    TALLY["rejected"] += 1
    TALLY["timeouts"] += 1
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    start = time.monotonic()
    s.sendall(b"GET / HTTP/1.1\r\nHost: x\r\n")
    got = b""
    s.settimeout(0.1)
    while time.monotonic() - start < 4:
        try:
            s.sendall(b"X: y\r\n")
        except (BrokenPipeError, ConnectionResetError):
            break
        try:
            c = s.recv(4096)
            if not c:
                break
            got += c
        except socket.timeout:
            pass
        except ConnectionResetError:
            break
    secs = time.monotonic() - start
    s.close()
    check(statuses(got) == [408] and 0.7 <= secs < 2.5, "endless headers %r %f" % (statuses(got), secs))
    healthy()
    cases += 2
    # 3. Idle connection with no bytes: closed silently after the idle timeout.
    got, secs = raw(port, b"")
    check(got == b"" and 1.0 <= secs < 2.5, "idle %r %f" % (got, secs))
    healthy()
    cases += 2
    # 4. Slow body: 408 after the body deadline.
    TALLY["rejected"] += 1
    TALLY["timeouts"] += 1
    got, secs = raw(port, b"POST /echo HTTP/1.1\r\nHost: x\r\nContent-Length: 100\r\n\r\n0123456789")
    check(statuses(got) == [408] and 0.9 <= secs < 2.5, "slow body %r %f" % (statuses(got), secs))
    healthy()
    cases += 2
    # 5. Partial head then silence.
    TALLY["rejected"] += 1
    TALLY["timeouts"] += 1
    got, secs = raw(port, b"GET /a.txt HTTP/1.1\r\nHo")
    check(statuses(got) == [408] and 0.7 <= secs < 2.0, "partial head %f" % secs)
    cases += 1
    # 6. Keep-alive connection idles out after one response.
    TALLY["connections"] += 1
    TALLY["requests"] += 1
    s = socket.create_connection(("127.0.0.1", port), timeout=5)
    start = time.monotonic()
    s.sendall(b"GET /a.txt HTTP/1.1\r\nHost: x\r\n\r\n")
    got = b""
    while True:
        c = s.recv(4096)
        if not c:
            break
        got += c
    secs = time.monotonic() - start
    s.close()
    check(statuses(got) == [200] and got.endswith(b"hello world\n") and 1.0 <= secs < 2.5, "keep-alive idle %f" % secs)
    cases += 1
    # 7. A slow but complete request inside the head deadline is served.
    TALLY["requests"] += 1
    got, secs = raw(port, [b"GET /a.txt HTTP/1.1\r\n", b"Host: x\r\n", b"Connection: close\r\n", b"\r\n"], pause=0.1)
    check(statuses(got) == [200], "slow but in time")
    cases += 1
    # 8. A slowloris holds the sequential server; a queued client waits for it.
    TALLY["rejected"] += 1
    TALLY["timeouts"] += 1
    TALLY["connections"] += 2
    TALLY["requests"] += 1
    hold = socket.create_connection(("127.0.0.1", port), timeout=5)
    hold.sendall(b"GET / HTTP/1.1\r\n")
    time.sleep(0.05)
    start = time.monotonic()
    q = socket.create_connection(("127.0.0.1", port), timeout=5)
    q.sendall(b"GET /a.txt HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
    got = b""
    while True:
        c = q.recv(4096)
        if not c:
            break
        got += c
    waited = time.monotonic() - start
    q.close()
    held = b""
    while True:
        c = hold.recv(4096)
        if not c:
            break
        held += c
    hold.close()
    check(statuses(held) == [408] and statuses(got) == [200] and 0.5 <= waited < 2.0, "queued %f" % waited)
    cases += 1
    stats = srv.finish()
    return cases, stats


def main():
    group, exe = sys.argv[1], sys.argv[2]
    groups = ["functional", "malformed", "slowloris"] if group == "all" else [group]
    for g in groups:
        for k in TALLY:
            TALLY[k] = 0
        with tempfile.TemporaryDirectory(prefix="lanius-http-service-") as base:
            cases, stats = {"functional": functional, "malformed": malformed, "slowloris": slowloris}[g](exe, base)
        for k in TALLY:
            check(stats[k] == TALLY[k], "%s %s server=%d oracle=%d %r" % (g, k, stats[k], TALLY[k], stats))
        check(stats["errors"] == 0, "server errors %r" % stats)
        print("http-service-%s cases=%d connections=%d requests=%d rejected=%d timeouts=%d" % (g, cases, stats["connections"], stats["requests"], stats["rejected"], stats["timeouts"]))
        sys.stdout.flush()


if __name__ == "__main__":
    main()
