"""ext::http_proxy oracle: Python upstreams (upstream.py) behind the
proxy fixture, driven by raw HTTP/1.1 sockets and libnghttp2 h2c
sessions. Usage: proxy_oracle.py GROUP PROXY_EXE with GROUP h1, h2 or
errors. Prints one summary line."""
import hashlib, os, socket, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "http2_server"))


def start_upstream(name):
    p = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "upstream.py"), name], stdout=subprocess.PIPE)
    return p, int(p.stdout.readline())


def start_proxy(exe, a, b, quiet=1500, profile="test"):
    p = subprocess.Popen([exe, str(quiet), str(a), str(b), profile], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    line = p.stdout.readline().decode()
    return p, int(line.rsplit(":", 1)[1])


def stop_proxy(p):
    out, err = p.communicate(timeout=60)
    if p.returncode != 0 or err:
        raise AssertionError(("proxy exit", p.returncode, err[-300:]))
    stats = dict(kv.split("=") for kv in out.decode().strip().splitlines()[-1].split())
    return {k: int(v) for k, v in stats.items()}


def pattern(n):
    block = bytes(range(97, 123)) * 40
    out = bytearray()
    while len(out) < n:
        out += block
    return bytes(out[:n])


def sha(data):
    return hashlib.sha256(data).hexdigest()


class Response:
    def __init__(self, status, reason, headers, body, trailers=()):
        self.status, self.reason, self.headers, self.body, self.trailers = status, reason, headers, body, list(trailers)

    def header(self, name):
        for k, v in self.headers:
            if k == name:
                return v
        return None

    def echo(self):
        """The upstream's /echo report as {key: value}; h: entries list."""
        info = {"h": []}
        for line in self.body.decode().splitlines():
            k, v = line.split("=", 1)
            if k.startswith("h:"):
                info["h"].append((k[2:], v))
            else:
                info[k] = v
        return info


class H1:
    def __init__(self, port, timeout=10):
        self.s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
        self.buf = b""

    def send(self, data):
        self.s.sendall(data)

    def fill(self):
        data = self.s.recv(1 << 20)
        if not data:
            raise EOFError()
        self.buf += data

    def take(self, n):
        while len(self.buf) < n:
            self.fill()
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def line(self):
        while b"\r\n" not in self.buf:
            self.fill()
        out, self.buf = self.buf.split(b"\r\n", 1)
        return out

    def response(self, method=b"GET", interim=False):
        while b"\r\n\r\n" not in self.buf:
            self.fill()
        head, self.buf = self.buf.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
        version, status, reason = (lines[0].split(b" ", 2) + [b""])[:3]
        headers = []
        for line in lines[1:]:
            k, v = line.split(b":", 1)
            headers.append((k.strip().lower(), v.strip()))
        status = int(status)
        r = Response(status, reason, headers, b"")
        if status < 200:
            return r if interim else self.response(method)
        te = r.header(b"transfer-encoding")
        if method == b"HEAD" or status in (204, 304):
            return r
        if te is not None:
            body = bytearray()
            while True:
                size = int(self.line().split(b";")[0], 16)
                if size == 0:
                    while True:
                        t = self.line()
                        if not t:
                            break
                        r.trailers.append(t)
                    break
                body += self.take(size)
                if self.take(2) != b"\r\n":
                    raise AssertionError("bad chunk end")
            r.body = bytes(body)
            return r
        length = r.header(b"content-length")
        if length is not None:
            r.body = self.take(int(length))
            return r
        try:
            while True:
                self.fill()
        except EOFError:
            pass
        r.body, self.buf = self.buf, b""
        return r

    def closed(self, wait=5):
        """True when the proxy closes the connection (EOF or reset)."""
        self.s.settimeout(wait)
        try:
            while True:
                if not self.s.recv(65536):
                    return True
        except (ConnectionResetError, BrokenPipeError):
            return True
        except socket.timeout:
            return False

    def close(self):
        self.s.close()


def get(port, target, extra=b"", method=b"GET", body=None):
    c = H1(port)
    data = b"%s %s HTTP/1.1\r\nHost: test\r\n%s" % (method, target, extra)
    if body is not None:
        data += b"Content-Length: %d\r\n" % len(body)
    c.send(data + b"\r\n" + (body or b""))
    r = c.response(method)
    c.close()
    return r


def check(cond, what):
    if not cond:
        raise AssertionError(what)


def h1_group(exe):
    up_a, port_a = start_upstream("A")
    up_b, port_b = start_upstream("B")
    proxy, port = start_proxy(exe, port_a, port_b)
    cases = 0
    try:
        # Hop-by-hop request fields are dropped; X-Forwarded-For, -Proto and Via added.
        r = get(port, b"/echo/one", b"Connection: keep-alive, X-Secret\r\nX-Secret: 1\r\nKeep-Alive: 5\r\nTE: trailers\r\nProxy-Connection: x\r\nUpgrade: h2c\r\nUser-Agent: oracle\r\n")
        e = r.echo(); names = [k for k, v in e["h"]]
        check(r.status == 200 and e["upstream"] == "A" and e["request"] == "GET /echo/one HTTP/1.1", ("echo", r.status, e))
        for gone in ("connection", "x-secret", "keep-alive", "te", "proxy-connection", "upgrade"):
            check(gone not in names, ("forwarded hop-by-hop", gone, e["h"]))
        h = dict(e["h"])
        check(h.get("x-forwarded-for") == "127.0.0.1" and h.get("x-forwarded-proto") == "http" and h.get("via") == "1.1 lanius" and h.get("user-agent") == "oracle" and h.get("host") == "test", ("rewritten", h))
        check(r.header(b"via") == b"1.1 lanius" and r.header(b"x-up-secret") is None and r.header(b"keep-alive") is None and r.header(b"connection") == b"keep-alive", ("response fields", r.headers))
        cases += 1
        # Existing X-Forwarded-For and Via are extended.
        e = get(port, b"/echo", b"X-Forwarded-For: 10.0.0.1\r\nVia: 1.0 edge\r\nX-Forwarded-Proto: https\r\n").echo(); h = dict(e["h"])
        check(h["x-forwarded-for"] == "10.0.0.1, 127.0.0.1" and h["via"] == "1.0 edge, 1.1 lanius" and h["x-forwarded-proto"] == "https", ("appended", h))
        cases += 1
        # Routing by prefix.
        check(get(port, b"/b/x").echo()["upstream"] == "B", "route /b/"); cases += 1
        check(get(port, b"/bx").echo()["upstream"] == "A", "route /bx"); cases += 1
        # Fixed and chunked request bodies.
        body = pattern(100000)
        e = get(port, b"/echo", method=b"POST", body=body).echo()
        check(e["body-len"] == "100000" and e["body-sha"] == sha(body) and dict(e["h"]).get("content-length") == "100000", ("fixed upload", e))
        cases += 1
        c = H1(port)
        wire = b"".join(b"%x\r\n" % len(body[i:i + 7000]) + body[i:i + 7000] + b"\r\n" for i in range(0, len(body), 7000)) + b"0\r\nX-Sum: 9\r\n\r\n"
        c.send(b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n" + wire)
        e = c.response().echo(); c.close()
        check(e["body-sha"] == sha(body) and dict(e["h"]).get("transfer-encoding") == "chunked", ("chunked upload", e)); cases += 1
        # Keep-alive and pipelining on one client connection.
        c = H1(port)
        c.send(b"GET /echo/p1 HTTP/1.1\r\nHost: t\r\n\r\nGET /echo/p2 HTTP/1.1\r\nHost: t\r\n\r\n")
        r1, r2 = c.response(), c.response()
        check(r1.echo()["request"].split()[1] == "/echo/p1" and r2.echo()["request"].split()[1] == "/echo/p2", "pipelined order")
        c.send(b"GET /echo/p3 HTTP/1.1\r\nHost: t\r\n\r\n"); r3 = c.response(); c.close()
        check(r3.status == 200, "third on keep-alive"); cases += 1
        # The upstream connection is pooled across clients.
        first = get(port, b"/echo/pool1").header(b"x-conn"); second = get(port, b"/echo/pool2").header(b"x-conn")
        check(first == second, ("pooled", first, second)); cases += 1
        # Response framings.
        r = get(port, b"/chunked/50000")
        check(r.body == pattern(50000) and r.header(b"transfer-encoding") == b"chunked" and r.trailers == [b"X-T: 1"], ("chunked response", len(r.body), r.trailers)); cases += 1
        c = H1(port); c.send(b"GET /close/30000 HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response(); c.close()
        check(r.body == pattern(30000) and r.header(b"connection") == b"close", ("close-delimited", len(r.body), r.headers)); cases += 1
        c = H1(port); c.send(b"HEAD /head-only HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response(b"HEAD")
        check(r.header(b"content-length") == b"1234" and r.body == b"", "HEAD")
        c.send(b"GET /304 HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response()
        check(r.status == 304 and r.header(b"etag") == b'"v1"', "304")
        c.send(b"GET /100 HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response(interim=True); c.close()
        check(r.status == 200, ("upstream interim not forwarded", r.status)); cases += 3
        # Expect: 100-continue is answered by the proxy.
        c = H1(port); c.send(b"POST /echo HTTP/1.1\r\nHost: t\r\nContent-Length: 5\r\nExpect: 100-continue\r\n\r\n")
        r = c.response(interim=True); check(r.status == 100, ("100 continue", r.status))
        c.send(b"hello"); e = c.response().echo(); c.close()
        check(e["body-len"] == "5" and "expect" not in dict(e["h"]), ("after 100", e)); cases += 1
        # HTTP/1.0 client: no keep-alive unless asked.
        c = H1(port); c.send(b"GET /echo HTTP/1.0\r\n\r\n"); r = c.response()
        check(r.header(b"connection") == b"close" and r.echo()["h"][-1] == ("via", "1.0 lanius") and c.closed(), ("1.0", r.headers)); c.close(); cases += 1
        # Large bodies stream through the 16 KiB buffers both ways.
        big = pattern(20000000)
        c = H1(port); c.send(b"GET /fixed/20000000 HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response(); c.close()
        check(len(r.body) == len(big) and sha(r.body) == sha(big), "big download"); cases += 1
        e = get(port, b"/upload", method=b"POST", body=big).echo()
        check(e["body-len"] == str(len(big)) and e["body-sha"] == sha(big), "big upload"); cases += 1
        # Streaming both ways: each request piece is echoed before the next is sent.
        c = H1(port); c.send(b"POST /stream HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n")
        while b"\r\n\r\n" not in c.buf:
            c.fill()
        c.buf = c.buf.split(b"\r\n\r\n", 1)[1]
        for k in range(5):
            piece = bytes([65 + k]) * (3000 + k)
            c.send(b"%x\r\n" % len(piece) + piece + b"\r\n")
            got = bytearray()
            while len(got) < len(piece):
                size = int(c.line(), 16); got += c.take(size); c.take(2)
            check(bytes(got) == piece, ("stream echo", k))
        c.send(b"0\r\n\r\n"); check(int(c.line(), 16) == 0, "stream end"); c.line(); c.close(); cases += 1
        # A pooled connection that the upstream drops is retried once on a
        # fresh one: /flaky closes every request after a connection's first.
        r = get(port, b"/flaky"); check(r.status == 200 and r.header(b"x-seq") == b"1", ("flaky first", r.status, r.headers))
        r = get(port, b"/flaky"); check(r.status == 200 and r.header(b"x-seq") == b"1", ("flaky retried", r.status, r.headers)); cases += 1
    finally:
        stats = stop_proxy(proxy)
        up_a.kill(); up_b.kill()
    check(stats["retries"] == 2 and stats["bad_gateway"] == 0 and stats["aborted"] == 0 and stats["reused"] > 5, ("stats", stats))
    print("http-proxy-h1 cases=%d requests=%d connects=%d reused=%d retries=%d" % (cases, stats["requests"], stats["connects"], stats["reused"], stats["retries"]))


def unused_port():
    s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
    return port


def errors_group(exe):
    up_a, port_a = start_upstream("A")
    proxy, port = start_proxy(exe, port_a, port_a)
    cases = 0
    try:
        # An upstream that closes without answering: 502, and the client
        # connection stays usable.
        c = H1(port); c.send(b"GET /drop HTTP/1.1\r\nHost: t\r\n\r\n"); r = c.response()
        check(r.status == 502 and r.header(b"connection") == b"keep-alive", ("drop", r.status, r.headers))
        c.send(b"GET /echo HTTP/1.1\r\nHost: t\r\n\r\n"); check(c.response().status == 200, "after 502"); c.close(); cases += 1
        # No response head within response_timeout_ms (800 ms): 504.
        started = time.monotonic(); r = get(port, b"/slow-head"); took = time.monotonic() - started
        check(r.status == 504 and 0.6 < took < 1.4, ("slow head", r.status, took)); cases += 1
        # A body that stops: the client connection closes after io_timeout_ms.
        c = H1(port); c.send(b"GET /stall HTTP/1.1\r\nHost: t\r\n\r\n")
        while b"\r\n\r\n" not in c.buf:
            c.fill()
        started = time.monotonic(); check(c.closed(5), "stall closed"); took = time.monotonic() - started
        check(len(c.buf.split(b"\r\n\r\n", 1)[1]) <= 1000 and took < 2.5, ("stall", took)); c.close(); cases += 1
        # Malformed, oversized and unsupported heads; a slow head.
        for wire, want in [(b"GET / HTTP/1.1\r\nHost: a\r\nBad Header\r\n\r\n", (400,)),
                           (b"GET / HTTP/1.1\r\nHost: a\r\nX-Big: " + b"x" * 20000 + b"\r\n\r\n", (431,)),
                           (b"GET / HTTP/1.1\r\nHost: a\r\nTransfer-Encoding: gzip\r\n\r\n", (501,)),
                           (b"GET / HTTP/1.1\r\nHost: a\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n", (400,)),
                           (b"GET / HTTP/1.1\r\nHost: a\r\n", (408,))]:
            c = H1(port); c.send(wire); r = c.response()
            check(r.status in want and r.header(b"connection") == b"close" and c.closed(), ("bad head", wire[:40], r.status)); c.close(); cases += 1
        # A malformed chunked request body ends both connections.
        c = H1(port); c.send(b"POST /upload HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\nzz\r\n")
        check(c.closed(), "bad chunk closes"); c.close(); cases += 1
        # A client that disconnects mid-upload leaves the proxy serving.
        c = H1(port); c.send(b"POST /upload HTTP/1.1\r\nHost: t\r\nContent-Length: 1000000\r\n\r\n" + b"x" * 5000); time.sleep(0.2); c.close()
        check(get(port, b"/echo").status == 200, "after abandoned upload"); cases += 1
        # An idle client is closed after idle_timeout_ms (1500 ms).
        c = H1(port); started = time.monotonic(); check(c.closed(4), "idle closed"); took = time.monotonic() - started
        check(1.2 < took < 2.5, ("idle", took)); c.close(); cases += 1
    finally:
        stats = stop_proxy(proxy)
    # A refused upstream connection: 502.
    dead, dead_port = start_proxy(exe, unused_port(), port_a)
    try:
        r = get(dead_port, b"/echo"); check(r.status == 502, ("refused", r.status)); cases += 1
    finally:
        dead_stats = stop_proxy(dead); up_a.kill()
    check(stats["bad_gateway"] == 1 and stats["gateway_timeout"] == 1 and stats["rejected"] == 5 and stats["aborted"] >= 2 and dead_stats["bad_gateway"] == 1, ("stats", stats, dead_stats))
    print("http-proxy-errors cases=%d bad_gateway=%d gateway_timeout=%d rejected=%d" % (cases, stats["bad_gateway"] + dead_stats["bad_gateway"], stats["gateway_timeout"], stats["rejected"]))


class H2:
    """A libnghttp2 client session over TCP (prior-knowledge h2c)."""

    def __init__(self, port):
        import ctypes
        import nghttp2_client as ng
        self.ng, self.ctypes = ng, ctypes
        self.s = socket.create_connection(("127.0.0.1", port), timeout=10)
        self.c = ng.Client()
        self.pending = {}

    def request(self, method, path, headers=(), body=None):
        return self.c.request(method, path, list(headers), body)

    def streaming(self, method, path, headers=()):
        """A request whose body is fed later with feed(); deferred until then."""
        ng, ctypes = self.ng, self.ctypes
        state = {"data": bytearray(), "end": False}

        def read(session, stream_id, buf, length, flags, source, user):
            if not state["data"] and not state["end"]:
                return -508  # NGHTTP2_ERR_DEFERRED
            n = min(length, len(state["data"]))
            ctypes.memmove(buf, bytes(state["data"][:n]), n)
            del state["data"][:n]
            if state["end"] and not state["data"]:
                flags[0] |= ng.DATA_FLAG_EOF
            return n
        cb = ng.READ_CB(read)
        provider = ng.DataProvider(ng.DataSource(0), cb)
        self.c._keep += [cb, provider]
        fields = [(b":method", method), (b":scheme", b"http"), (b":authority", b"localhost"), (b":path", path)] + list(headers)
        keep = [ctypes.create_string_buffer(x, len(x)) for f in fields for x in f]
        self.c._keep.append(keep)
        nva = (ng.Nv * len(fields))()
        for i in range(len(fields)):
            nva[i] = ng.Nv(ctypes.cast(keep[2 * i], ctypes.c_void_p), ctypes.cast(keep[2 * i + 1], ctypes.c_void_p), len(fields[i][0]), len(fields[i][1]), 0)
        sid = ng.lib.nghttp2_submit_request(self.c.session, None, nva, len(fields), ctypes.byref(provider), None)
        self.c.streams[sid] = ng.Stream()
        self.pending[sid] = state
        return sid

    def feed(self, sid, data, end=False):
        state = self.pending[sid]
        state["data"] += data; state["end"] = end
        self.ng.lib.nghttp2_session_resume_data(self.c.session, sid)

    def pump(self, until, limit=20):
        deadline = time.monotonic() + limit
        while True:
            out = self.c.output()
            if out:
                self.s.sendall(out)
            if until():
                return
            if time.monotonic() > deadline:
                raise AssertionError("h2 pump timed out")
            self.s.settimeout(0.05)
            try:
                data = self.s.recv(1 << 20)
            except socket.timeout:
                continue
            if not data:
                raise EOFError()
            self.c.receive(data)

    def wait(self, *sids):
        self.pump(lambda: all(self.c.streams[s].closed for s in sids))
        return [self.c.streams[s] for s in sids]

    def close(self):
        self.c.goaway_submit(0)
        try:
            self.s.sendall(self.c.output())
        except OSError:
            pass
        self.s.close(); self.c.close()


def h2_echo(stream):
    return Response(stream.status, b"", stream.headers, bytes(stream.body)).echo()


def h2_group(exe):
    up_a, port_a = start_upstream("A")
    up_b, port_b = start_upstream("B")
    proxy, port = start_proxy(exe, port_a, port_b)
    cases = 0
    try:
        c = H2(port)
        # 20 multiplexed requests on one connection.
        sids = [c.request(b"GET", b"/echo/%d" % i, [(b"x-tag", b"t%d" % i)]) for i in range(20)]
        for i, st in enumerate(c.wait(*sids)):
            e = h2_echo(st); h = dict(e["h"])
            check(st.status == 200 and st.error == 0 and e["request"] == "GET /echo/%d HTTP/1.1" % i and h["x-tag"] == "t%d" % i, ("multiplexed", i, st.status, e))
            check(h["via"] == "2 lanius" and h["host"] == "localhost" and h["x-forwarded-for"] == "127.0.0.1", ("h2 rewrite", h))
            names = [k for k, v in st.headers]
            check(b"connection" not in names and b"keep-alive" not in names and b"x-up-secret" not in names and (b"via", b"1.1 lanius") in st.headers, ("h2 response fields", st.headers))
        cases += 1
        # Request bodies: with a length, and without one (chunked upstream).
        body = pattern(200000)
        s1 = c.request(b"POST", b"/echo", [(b"content-length", b"200000")], body)
        s2 = c.request(b"POST", b"/upload", [], pattern(300000))
        r1, r2 = c.wait(s1, s2); e1, e2 = h2_echo(r1), h2_echo(r2)
        check(e1["body-sha"] == sha(body) and dict(e1["h"]).get("content-length") == "200000", ("h2 fixed upload", e1))
        check(e2["body-sha"] == sha(pattern(300000)) and dict(e2["h"]).get("transfer-encoding") == "chunked", ("h2 chunked upload", e2)); cases += 2
        # Split cookies are joined; /b/ is routed to B.
        s1 = c.request(b"GET", b"/echo", [(b"cookie", b"a=1"), (b"cookie", b"b=2")]); s2 = c.request(b"GET", b"/b/z")
        r1, r2 = c.wait(s1, s2)
        check(dict(h2_echo(r1)["h"]).get("cookie") == "a=1; b=2" and h2_echo(r2)["upstream"] == "B", "cookies, route"); cases += 2
        # Chunked, close-delimited, HEAD and large responses.
        s1 = c.request(b"GET", b"/chunked/100000"); s2 = c.request(b"GET", b"/close/20000"); s3 = c.request(b"HEAD", b"/head-only"); s4 = c.request(b"GET", b"/fixed/5000000")
        r1, r2, r3, r4 = c.wait(s1, s2, s3, s4)
        check(bytes(r1.body) == pattern(100000) and b"transfer-encoding" not in [k for k, v in r1.headers], "h2 chunked response")
        check(bytes(r2.body) == pattern(20000) and r2.error == 0, "h2 close-delimited")
        check(r3.status == 200 and dict(r3.headers).get(b"content-length") == b"1234" and not r3.body, ("h2 HEAD", r3.headers))
        check(sha(bytes(r4.body)) == sha(pattern(5000000)), "h2 big download"); cases += 4
        big = pattern(5000000)
        r = c.wait(c.request(b"POST", b"/upload", [(b"content-length", b"5000000")], big))[0]
        check(h2_echo(r)["body-sha"] == sha(big), "h2 big upload"); cases += 1
        # One stream fails upstream while its neighbour completes.
        s1 = c.request(b"GET", b"/drop"); s2 = c.request(b"GET", b"/echo/ok"); s3 = c.request(b"GET", b"/slow-head")
        r1, r2, r3 = c.wait(s1, s2, s3)
        check(r1.status == 502 and r2.status == 200 and r3.status == 504, ("h2 errors", r1.status, r2.status, r3.status)); cases += 2
        # Streaming both ways over HTTP/2.
        sid = c.streaming(b"POST", b"/stream")
        for k in range(5):
            piece = bytes([97 + k]) * (5000 + k); want = len(c.c.streams[sid].body) + len(piece)
            c.feed(sid, piece, end=False)
            c.pump(lambda: len(c.c.streams[sid].body) >= want)
            check(bytes(c.c.streams[sid].body[-len(piece):]) == piece, ("h2 stream echo", k))
        c.feed(sid, b"", end=True); st = c.wait(sid)[0]
        check(st.status == 200 and st.error == 0, "h2 stream end"); cases += 1
        c.close()
    finally:
        stats = stop_proxy(proxy)
        up_a.kill(); up_b.kill()
    check(stats["h2"] == 1 and stats["h2_requests"] == 33 and stats["bad_gateway"] == 1 and stats["gateway_timeout"] == 1, ("stats", stats))
    print("http-proxy-h2 cases=%d requests=%d connects=%d reused=%d" % (cases, stats["h2_requests"], stats["connects"], stats["reused"]))


def main():
    group, exe = sys.argv[1], sys.argv[2]
    {"h1": h1_group, "errors": errors_group, "h2": h2_group}[group](exe)

main()
