#!/usr/bin/env python3
"""Loopback oracle for ext::http_agent over HTTP/2 (sample_programs/library/http_curl.lani).

usage: agent_oracle.py h2|all CLIENT

h2  http_curl against libnghttp2's server session over TLS with ALPN h2
    (h2server.Server), with test certificates generated per run by
    ../openssl_tls/certificates.py: ALPN selection, one connection reused
    for sequential requests, --parallel multiplexing (concurrency observed
    by the server, the server's MAX_CONCURRENT_STREAMS honoured), fixed and
    streamed uploads under flow control, response fields, CONTINUATION,
    trailers, 1xx, HEAD, redirects on the same connection, RST_STREAM and
    GOAWAY, server PING, certificate verification, and fallback to HTTP/1.1
    for a TLS origin that does not select h2.
Prints: http2-agent-GROUP cases=N connections=C requests=R
"""
import http.server
import os
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import time
import zlib
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "openssl_tls"))
import h2server  # noqa: E402
from certificates import generate  # noqa: E402
from h2server import gen  # noqa: E402

EXE = None
CERTS = None
TOTAL = {"connections": 0, "requests": 0}


class Failure(Exception):
    pass


def expect(ok, what):
    if not ok:
        raise Failure(what)


def client(args, stdin=b"", timeout=30):
    started = time.monotonic()
    r = subprocess.run([EXE, "--cacert", str(CERTS / "root.pem")] + args, input=stdin, capture_output=True, timeout=timeout)
    elapsed = time.monotonic() - started
    pool, responses = {}, []
    for line in r.stderr.decode(errors="replace").splitlines():
        if line.startswith("pool "):
            pool = {k: int(v) for k, v in (kv.split("=", 1) for kv in line[5:].split())}
        elif line.startswith("response "):
            fields = dict(kv.split("=", 1) for kv in line[9:].split(" url=")[0].split())
            fields["url"] = line.split(" url=", 1)[1]
            responses.append(fields)
    return r.returncode, r.stdout, r.stderr.decode(errors="replace"), pool, responses, elapsed


def pool_has(pool, **want):
    for k, v in want.items():
        expect(pool.get(k) == v, "pool %s=%s, want %s (%s)" % (k, pool.get(k), v, pool))


def h2_context():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(CERTS / "valid.pem"), str(CERTS / "valid.key"))
    context.set_alpn_protocols(["h2"])
    return context


class Origin:
    """An nghttp2 server over TLS; counts its connections and requests."""

    def __init__(self, settings=((3, 100),)):
        self.server = h2server.Server(context=h2_context(), settings=settings)
        self.base = "https://127.0.0.1:%d" % self.server.port

    def conns(self):
        self.server.settle(2)
        return list(self.server.conns)

    def reset(self):
        self.server.settle(2)
        TOTAL["connections"] += len(self.server.conns)
        TOTAL["requests"] += sum(len(c.requests) for c in self.server.conns)
        del self.server.conns[:]


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.server.alpn.append(self.connection.selected_alpn_protocol())
        body = b"one point one\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class Http11(http.server.ThreadingHTTPServer):
    """A TLS origin that only selects http/1.1."""
    daemon_threads = True

    def __init__(self):
        super().__init__(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(CERTS / "valid.pem"), str(CERTS / "valid.key"))
        context.set_alpn_protocols(["http/1.1"])
        self.socket = context.wrap_socket(self.socket, server_side=True)
        self.alpn = []
        self.base = "https://127.0.0.1:%d" % self.server_address[1]
        threading.Thread(target=self.serve_forever, daemon=True).start()

    def handle_error(self, request, client_address):
        pass


def group_h2():
    cases = []
    s = Origin()
    narrow = Origin(settings=((3, 2),))
    old = Http11()

    def case(fn):
        cases.append(fn)
        return fn

    @case
    def alpn_selects_h2():
        rc, out, err, pool, rs, _ = client(["--stats", s.base + "/hello"])
        expect(rc == 0 and out == b"hello world\n", (rc, out, err))
        expect(rs[0]["version"] == "20" and rs[0]["status"] == "200", rs)
        pool_has(pool, connections=1, http2=1, requests=1, sessions=1, idle=0)
        conns = s.conns()
        expect(len(conns) == 1 and conns[0].requests[0]["path"] == b"/hello", conns)
        h = dict(conns[0].requests[0]["headers"])
        expect(h[b":scheme"] == b"https" and h[b":authority"] == ("127.0.0.1:%d" % s.server.port).encode(), h)
        # The client closed with GOAWAY(NO_ERROR) and pushes stay disabled.
        expect(conns[0].client_goaway == 0 and conns[0].client_settings.get(2) == 0, (conns[0].client_goaway, conns[0].client_settings))

    @case
    def sequential_requests_share_one_connection():
        rc, out, err, pool, rs, _ = client(["--stats", s.base + "/hello", s.base + "/size/300000", s.base + "/hello"])
        expect(rc == 0 and out == b"hello world\n" + gen(300000) + b"hello world\n", (rc, len(out), err))
        expect([r["reused"] for r in rs] == ["0", "1", "1"], rs)
        pool_has(pool, connections=1, http2=1, requests=3, reused=2)
        conns = s.conns()
        expect(len(conns) == 1 and [r["stream"] for r in conns[0].requests] == [1, 3, 5], [c.requests for c in conns])

    @case
    def parallel_streams_run_concurrently():
        urls = [s.base + "/delay/400" for _ in range(8)]
        rc, out, err, pool, rs, elapsed = client(["--stats", "--parallel"] + urls)
        expect(rc == 0 and out == b"/delay/400" * 8, (rc, out, err))
        expect(elapsed < 2.5, "8 x 400 ms took %.2f s" % elapsed)
        pool_has(pool, connections=1, http2=1, requests=8, reused=7)
        conns = s.conns()
        expect(len(conns) == 1 and conns[0].max_open == 8, [(len(conns), c.max_open) for c in conns])

    @case
    def parallel_honours_max_concurrent_streams():
        urls = [narrow.base + "/delay/200" for _ in range(6)] + [narrow.base + "/size/70000"]
        rc, out, err, pool, rs, _ = client(["--stats", "--parallel"] + urls)
        expect(rc == 0 and out == b"/delay/200" * 6 + gen(70000), (rc, len(out), err))
        conns = narrow.conns()
        expect(len(conns) == 1 and conns[0].max_open == 2 and len(conns[0].requests) == 7, [(c.max_open, len(c.requests)) for c in conns])

    @case
    def parallel_mixes_origins_in_order():
        rc, out, err, pool, rs, _ = client(["--stats", "--parallel", s.base + "/hello", old.base + "/x", s.base + "/size/5", old.base + "/y"])
        expect(rc == 0 and out == b"hello world\none point one\n" + gen(5) + b"one point one\n", (rc, out, err))
        expect([r["version"] for r in rs] == ["20", "11", "20", "11"], rs)
        pool_has(pool, connections=2, http2=1)

    @case
    def fixed_upload():
        rc, out, err, _, _, _ = client(["-i", "-d", "abc", s.base + "/echo"])
        expect(rc == 0 and out.endswith(b"\r\nabc") and b"x-request-length: 3\r\n" in out, (rc, out, err))
        req = s.conns()[0].requests[0]
        expect(req["method"] == b"POST" and dict(req["headers"]).get(b"content-length") == b"3" and req["body"] == b"abc", req)

    @case
    def streamed_upload_under_flow_control():
        data = gen(400000)
        rc, out, err, _, _, _ = client(["-T", "-", s.base + "/echo"], stdin=data)
        expect(rc == 0 and out == data, (rc, len(out), err))
        req = s.conns()[0].requests[0]
        expect(req["method"] == b"PUT" and b"content-length" not in dict(req["headers"]), req["headers"])

    @case
    def empty_streamed_upload():
        rc, out, err, _, _, _ = client(["-T", "-", s.base + "/echo"], stdin=b"")
        expect(rc == 0 and out == b"", (rc, out, err))

    @case
    def method_and_custom_fields():
        rc, out, err, _, _, _ = client(["-X", "DELETE", "-H", "X-Trace: Abc", "-H", "Authorization: Bearer t", s.base + "/method"])
        expect(rc == 0 and out == b"DELETE 0", (rc, out, err))
        h = s.conns()[0].requests[0]["headers"]
        expect((b"x-trace", b"Abc") in h and (b"authorization", b"Bearer t") in h, h)

    @case
    def response_fields_and_continuation():
        rc, out, err, _, _, _ = client(["-i", s.base + "/headers/60/400"])
        head, body = out.split(b"\r\n\r\n", 1) if b"\r\n\r\n" in out else (out, b"")
        expect(rc == 0 and out.endswith(b"ok"), (rc, out[-40:], err))
        lines = out[:-2].split(b"\r\n")
        expect(lines[0].startswith(b"x-h-0: 0-") and any(l.startswith(b"x-h-59: 59-") for l in lines), lines[:3])

    @case
    def trailers_early_hints_and_head():
        rc, out, err, _, rs, _ = client(["--stats", s.base + "/trailers", s.base + "/early-hints"])
        expect(rc == 0 and out == b"abcfinal", (rc, out, err))
        expect([r["status"] for r in rs] == ["200", "200"], rs)
        rc, out, err, _, rs, _ = client(["-I", "--stats", s.base + "/head"])
        expect(rc == 0 and out == b"content-length: 1234\r\n" and rs[0]["bytes"] == "0", (rc, out, err))

    @case
    def redirect_on_the_same_connection():
        rc, out, err, pool, rs, _ = client(["--stats", "-L", s.base + "/redirect"])
        expect(rc == 0 and out == b"hello world\n", (rc, out, err))
        expect(rs[0]["redirects"] == "1" and rs[0]["url"] == s.base + "/hello", rs)
        pool_has(pool, connections=1, http2=1, requests=2, reused=1, redirects=1)

    @case
    def status_and_fail():
        rc, out, err, _, _, _ = client(["-f", s.base + "/status/404"])
        expect(rc == 22, (rc, out, err))

    @case
    def reset_stream_is_an_http2_error():
        rc, out, err, pool, _, _ = client(["--stats", s.base + "/rst/2", s.base + "/hello"])
        expect(rc == 16 and "HTTP/2 error" in err, (rc, out, err))

    @case
    def refused_stream_is_retried_once():
        rc, out, err, pool, _, _ = client(["--stats", s.base + "/rst/7"])
        expect(rc == 16, (rc, out, err))
        pool_has(pool, retries=1, requests=2)

    @case
    def goaway_moves_to_a_new_connection():
        rc, out, err, pool, rs, _ = client(["--stats", s.base + "/goaway", s.base + "/hello"])
        expect(rc == 0 and out == b"byehello world\n", (rc, out, err))
        expect([r["reused"] for r in rs] == ["0", "0"] and rs[0]["kept"] == "0", rs)
        pool_has(pool, connections=2, http2=2)

    @case
    def server_ping_is_answered():
        rc, out, err, _, _, _ = client(["-i", s.base + "/ping"])
        expect(rc == 0 and b"x-ping-acks: 1\r\n" in out and out.endswith(b"pinged"), (rc, out, err))

    @case
    def idle_connection_expires():
        rc, out, err, pool, rs, _ = client(["--stats", "--idle-timeout", "100", "--pause", "300", s.base + "/hello", s.base + "/hello"])
        expect(rc == 0 and out == b"hello world\n" * 2, (rc, out, err))
        pool_has(pool, connections=2, http2=2, expired=1)

    @case
    def max_uses_closes_after_the_limit():
        rc, out, err, pool, _, _ = client(["--stats", "--max-uses", "2"] + [s.base + "/hello"] * 3)
        expect(rc == 0, (rc, err))
        pool_has(pool, connections=2, http2=2, requests=3)

    @case
    def http11_flag_and_fallback():
        del old.alpn[:]
        rc, out, err, pool, rs, _ = client(["--stats", old.base + "/a", old.base + "/b"])
        expect(rc == 0 and out == b"one point one\n" * 2 and [r["version"] for r in rs] == ["11", "11"], (rc, out, err, rs))
        pool_has(pool, connections=1, http2=0, reused=1)
        rc, out, err, pool, rs, _ = client(["--stats", "--http1.1", old.base + "/c"])
        expect(rc == 0 and rs[0]["version"] == "11", (rc, err, rs))
        # Offered h2 and http/1.1 the first time; without ALPN the second.
        expect(old.alpn == ["http/1.1", "http/1.1", None], old.alpn)

    @case
    def certificate_still_verified():
        r = subprocess.run([EXE, s.base + "/hello"], capture_output=True, timeout=30)
        expect(r.returncode == 60, (r.returncode, r.stderr))

    count = 0
    try:
        for fn in cases:
            try:
                fn()
            except Failure as e:
                print("FAIL h2/%s: %s" % (fn.__name__, e), file=sys.stderr)
                sys.exit(1)
            except subprocess.TimeoutExpired:
                print("FAIL h2/%s: client timed out" % fn.__name__, file=sys.stderr)
                sys.exit(1)
            count += 1
            s.reset()
            narrow.reset()
    finally:
        s.server.stop()
        narrow.server.stop()
        old.shutdown()
    return count


GROUPS = {"h2": group_h2}


def main():
    global EXE, CERTS
    if len(sys.argv) != 3 or (sys.argv[1] not in GROUPS and sys.argv[1] != "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    work = tempfile.mkdtemp(prefix="http2-agent-")
    CERTS = Path(work) / "certs"
    try:
        generate(CERTS)
        for name in (list(GROUPS) if sys.argv[1] == "all" else [sys.argv[1]]):
            TOTAL["connections"] = TOTAL["requests"] = 0
            count = GROUPS[name]()
            print("http2-agent-%s cases=%d connections=%d requests=%d" % (name, count, TOTAL["connections"], TOTAL["requests"]))
    finally:
        shutil.rmtree(work, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
