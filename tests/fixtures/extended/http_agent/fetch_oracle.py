#!/usr/bin/env python3
"""Loopback oracle for sample_programs/library/agent_fetch.lani, the
streaming fetch sample over ext::http_agent (Agent fetch_to).

usage: fetch_oracle.py http CLIENT
       fetch_oracle.py h2 CLIENT
       fetch_oracle.py proxy CLIENT PROXY TLS_PROXY

http   Python's http.server (ThreadingHTTPServer, SimpleHTTPRequestHandler
       over a temporary directory, HTTP/1.1 keep-alive) plus a few scripted
       paths: files of 3 MB and 20 MiB streamed to -o FILE (the larger is
       past the agent's 16 MiB buffered-body limit; peak RSS is checked),
       keep-alive across URLs, chunked responses with trailers, directory
       redirects with and without -L, -f, HEAD with -D, a chunked upload,
       --max-time mid-body, a refused connect, a closed stdout pipe, and
       std::cli errors and --help.
h2     libnghttp2's server session over TLS with ALPN h2 (../http2/
       h2server.py): bodies of 5 MB and 17 MiB through stream flow control,
       three URLs as streams of one connection, a redirect, RST_STREAM and a
       closed stdout pipe.
proxy  the ext::http_proxy fixture (../http_proxy/proxy_main.lani) and its
       TLS front end (tls_main.lani, ALPN h2 and http/1.1) in front of the
       proxy oracle's upstream: fixed, chunked and close-delimited bodies,
       keep-alive through the proxy, HTTP/2 to the TLS proxy.
Prints: agent-fetch-GROUP cases=N
"""
import hashlib
import http.server
import os
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "http2"))
sys.path.insert(0, str(HERE.parent / "openssl_tls"))
sys.path.insert(0, str(HERE.parent / "http_proxy"))
import h2server  # noqa: E402
from certificates import generate  # noqa: E402
from h2server import gen  # noqa: E402

EXE = None
CERTS = None


class Failure(Exception):
    pass


def expect(ok, what):
    if not ok:
        raise Failure(what)


def stats(err):
    pool, responses = {}, []
    for line in err.splitlines():
        if line.startswith("pool "):
            pool = {k: int(v) for k, v in (kv.split("=", 1) for kv in line[5:].split())}
        elif line.startswith("response "):
            fields = dict(kv.split("=", 1) for kv in line[9:].split(" url=")[0].split())
            fields["url"] = line.split(" url=", 1)[1]
            responses.append(fields)
    return pool, responses


def client(args, stdin=b"", timeout=60, cacert=False):
    """Run the client; returns rc, stdout, stderr, pool, responses, seconds."""
    extra = ["--cacert", str(CERTS / "root.pem")] if cacert else []
    started = time.monotonic()
    p = subprocess.Popen([EXE] + extra + args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate(stdin, timeout=timeout)
    elapsed = time.monotonic() - started
    err = err.decode(errors="replace")
    pool, responses = stats(err)
    return p.returncode, out, err, pool, responses, elapsed


def peak_rss(args, cacert=False):
    """rc and peak RSS (KiB) of one run whose stdout is discarded. GNU time
    reports it: a child forked from this Python process would carry
    Python's own peak into its ru_maxrss across exec."""
    extra = ["--cacert", str(CERTS / "root.pem")] if cacert else []
    with tempfile.NamedTemporaryFile() as report:
        p = subprocess.run(["/usr/bin/time", "-f", "%M", "-o", report.name, EXE] + extra + args, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=60)
        rss = int(Path(report.name).read_text().split()[-1])
    return p.returncode, rss, p.stderr.decode(errors="replace")


def closed_pipe(args, cacert=False):
    """Read a little of stdout, then close it: the client must fail with 23."""
    extra = ["--cacert", str(CERTS / "root.pem")] if cacert else []
    p = subprocess.Popen([EXE] + extra + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    first = p.stdout.read(4096)
    p.stdout.close()
    err = p.stderr.read().decode(errors="replace")
    rc = p.wait(timeout=60)
    return rc, first, err


def blob(n, seed=7):
    out = bytearray()
    block = hashlib.sha256(b"%d" % seed).digest()
    while len(out) < n:
        block = hashlib.sha256(block).digest()
        out += block * 32
    return bytes(out[:n])


def run_cases(cases):
    for fn in cases:
        try:
            fn()
        except Failure as e:
            raise Failure("%s: %s" % (fn.__name__, e))
    return len(cases)


# ------------------------------------------------------------ http.server
class Files(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def setup(self):
        super().setup()
        with self.server.lock:
            self.server.connections += 1

    def do_GET(self):
        with self.server.lock:
            self.server.requests += 1
        if self.path.startswith("/gen/"):
            # Chunked, in uneven pieces, with a trailer.
            data = blob(int(self.path[5:]), 3)
            self.send_response(200)
            self.send_header("Transfer-Encoding", "chunked")
            self.send_header("Trailer", "X-Sum")
            self.end_headers()
            at, step = 0, 1
            while at < len(data):
                piece = data[at:at + step]
                self.wfile.write(b"%x;ext=1\r\n" % len(piece) + piece + b"\r\n")
                at += len(piece)
                step = step * 3 + 7 if step < 60000 else 1
            self.wfile.write(b"0\r\nX-Sum: " + hashlib.sha256(data).hexdigest().encode() + b"\r\n\r\n")
            return
        if self.path == "/slow":
            self.send_response(200)
            self.send_header("Content-Length", "100000")
            self.end_headers()
            self.wfile.write(b"s" * 1000)
            self.wfile.flush()
            time.sleep(3)
            return
        super().do_GET()

    def do_HEAD(self):
        with self.server.lock:
            self.server.requests += 1
        super().do_HEAD()

    def do_PUT(self):
        with self.server.lock:
            self.server.requests += 1
        body = bytearray()
        if self.headers.get("Transfer-Encoding", "").lower() == "chunked":
            while True:
                size = int(self.rfile.readline().split(b";")[0], 16)
                if size == 0:
                    while self.rfile.readline() not in (b"\r\n", b""):
                        pass
                    break
                body += self.rfile.read(size)
                self.rfile.readline()
        else:
            body += self.rfile.read(int(self.headers.get("Content-Length", "0")))
        reply = b"%s %d %s\n" % (self.command.encode(), len(body), hashlib.sha256(body).hexdigest().encode())
        self.send_response(201)
        self.send_header("Content-Length", str(len(reply)))
        self.end_headers()
        self.wfile.write(reply)

    do_POST = do_PUT


class FileServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, root):
        super().__init__(("127.0.0.1", 0), lambda *a: Files(*a, directory=root))
        self.lock, self.connections, self.requests = threading.Lock(), 0, 0
        self.base = "http://127.0.0.1:%d" % self.server_address[1]
        threading.Thread(target=self.serve_forever, daemon=True).start()

    def handle_error(self, request, client_address):
        pass

    def counts(self):
        time.sleep(0.05)
        with self.lock:
            c, r = self.connections, self.requests
            self.connections = self.requests = 0
        return c, r


def group_http(work):
    root = Path(work) / "www"
    (root / "dir").mkdir(parents=True)
    files = {"a.txt": b"alpha\n", "b.txt": b"bravo\n", "c.txt": b"charlie\n", "big.bin": blob(3000000), "huge.bin": blob(20 * 1048576, 5)}
    for name, data in files.items():
        (root / name).write_bytes(data)
    (root / "dir" / "inner.txt").write_bytes(b"inner\n")
    s = FileServer(str(root))
    out = Path(work) / "out.bin"
    cases = []
    case = cases.append

    def big_file_to_output():
        rc, stdout, err, pool, rs, _ = client(["--stats", "-o", str(out), s.base + "/big.bin"])
        expect(rc == 0 and stdout == b"" and out.read_bytes() == files["big.bin"], (rc, err))
        expect(rs[0]["status"] == "200" and rs[0]["version"] == "11" and rs[0]["streamed"] == "3000000", rs)
        expect(s.counts() == (1, 1), "one connection, one request")
    case(big_file_to_output)

    def keep_alive_across_urls():
        rc, stdout, err, pool, rs, _ = client(["--stats", s.base + "/a.txt", s.base + "/b.txt", s.base + "/c.txt"])
        expect(rc == 0 and stdout == b"alpha\nbravo\ncharlie\n", (rc, stdout, err))
        expect(pool["connections"] == 1 and pool["reused"] == 2 and pool["requests"] == 3 and pool["idle"] == 1, pool)
        expect([r["reused"] for r in rs] == ["0", "1", "1"] and all(r["kept"] == "1" for r in rs), rs)
        expect(s.counts() == (1, 3), "server saw one connection")
    case(keep_alive_across_urls)

    def past_the_buffered_body_limit():
        rc, rss, err = peak_rss(["-o", str(out), s.base + "/huge.bin"])
        expect(rc == 0 and out.stat().st_size == len(files["huge.bin"]), (rc, err))
        expect(hashlib.sha256(out.read_bytes()).digest() == hashlib.sha256(files["huge.bin"]).digest(), "20 MiB body")
        expect(rss < 16384, ("peak RSS KiB", rss))
        s.counts()
    case(past_the_buffered_body_limit)

    def chunked_with_trailer():
        rc, stdout, err, pool, rs, _ = client(["--stats", s.base + "/gen/5000000", s.base + "/a.txt"])
        expect(rc == 0 and stdout == blob(5000000, 3) + b"alpha\n", (rc, len(stdout), err))
        expect(rs[0]["streamed"] == "5000000" and pool["connections"] == 1 and pool["reused"] == 1, (rs, pool))
        s.counts()
    case(chunked_with_trailer)

    def directory_redirect():
        rc, stdout, err, pool, rs, _ = client(["--stats", s.base + "/dir"])
        expect(rc == 0 and rs[0]["status"] == "301" and rs[0]["redirects"] == "0", (rc, rs, err))
        rc, stdout, err, pool, rs, _ = client(["--stats", "-L", s.base + "/dir"])
        expect(rc == 0 and b"inner.txt" in stdout and rs[0]["status"] == "200" and rs[0]["redirects"] == "1", (rc, rs, err))
        expect(rs[0]["url"] == s.base + "/dir/" and rs[0]["streamed"] == str(len(stdout)), rs)
        expect(pool["connections"] == 1 and pool["requests"] == 2, pool)
        rc, stdout, err, pool, rs, _ = client(["-L", "--max-redirs", "0", s.base + "/dir"])
        expect(rc == 47 and "too many redirects" in err, (rc, err))
        s.counts()
    case(directory_redirect)

    def fail_keeps_body():
        rc, stdout, err, pool, rs, _ = client(["-f", s.base + "/missing", s.base + "/a.txt"])
        expect(rc == 22 and b"404" in stdout and b"alpha" not in stdout and "HTTP error" in err, (rc, stdout[:80], err))
        s.counts()
    case(fail_keeps_body)

    def head_and_dump_header():
        rc, stdout, err, pool, rs, _ = client(["--stats", "-I", "-D", "-", s.base + "/big.bin"])
        expect(rc == 0 and stdout == b"" and rs[0]["streamed"] == "0", (rc, stdout[:40], err))
        expect(err.startswith("HTTP/1.0 200 OK\r\n") or err.startswith("HTTP/1.1 200 OK\r\n"), err[:60])
        expect("Content-Length: 3000000\r\n" in err, err[:300])
        dump = Path(work) / "head.txt"
        rc, stdout, err, pool, rs, _ = client(["-D", str(dump), s.base + "/a.txt"])
        expect(rc == 0 and stdout == b"alpha\n" and dump.read_bytes().startswith(b"HTTP/1.") and dump.read_bytes().endswith(b"\r\n\r\n"), (rc, err))
        s.counts()
    case(head_and_dump_header)

    def chunked_upload_and_fixed_post():
        body = blob(1000000, 9)
        rc, stdout, err, pool, rs, _ = client(["-T", "-", s.base + "/up"], stdin=body)
        expect(rc == 0 and stdout == b"PUT %d %s\n" % (len(body), hashlib.sha256(body).hexdigest().encode()), (rc, stdout, err))
        rc, stdout, err, pool, rs, _ = client(["-d", "x=1", s.base + "/form"])
        expect(rc == 0 and stdout == b"POST 3 %s\n" % hashlib.sha256(b"x=1").hexdigest().encode(), (rc, stdout, err))
        s.counts()
    case(chunked_upload_and_fixed_post)

    def deadline_mid_body():
        rc, stdout, err, pool, rs, elapsed = client(["--max-time", "800", s.base + "/slow"])
        expect(rc == 28 and stdout == b"s" * 1000 and elapsed < 2.5, (rc, len(stdout), elapsed, err))
        s.counts()
    case(deadline_mid_body)

    def refused_connect():
        spare = socket.socket(); spare.bind(("127.0.0.1", 0)); port = spare.getsockname()[1]; spare.close()
        rc, stdout, err, pool, rs, _ = client(["--connect-timeout", "500", "http://127.0.0.1:%d/" % port])
        expect(rc == 7 and "connect failed" in err, (rc, err))
    case(refused_connect)

    def closed_stdout():
        rc, first, err = closed_pipe([s.base + "/huge.bin"])
        expect(rc == 23 and first == files["huge.bin"][:len(first)] and "write error" in err, (rc, len(first), err))
        s.counts()
    case(closed_stdout)

    def command_line():
        rc, stdout, err, pool, rs, _ = client(["--help"])
        expect(rc == 0 and b"agent-fetch" in stdout and b"--max-time" in stdout and b"URL" in stdout, (rc, stdout[:200]))
        rc, stdout, err, pool, rs, _ = client([])
        expect(rc == 2 and err, (rc, err))
        rc, stdout, err, pool, rs, _ = client(["--bogus", s.base + "/a.txt"])
        expect(rc == 2 and "bogus" in err, (rc, err))
        rc, stdout, err, pool, rs, _ = client(["--max-time", "soon", s.base + "/a.txt"])
        expect(rc == 2 and "max-time" in err, (rc, err))
        rc, stdout, err, pool, rs, _ = client(["-H", "nocolon", s.base + "/a.txt"])
        expect(rc == 2 and "header" in err, (rc, err))
        rc, stdout, err, pool, rs, _ = client(["-H", "Host: x", s.base + "/a.txt"])
        expect(rc == 2 and "invalid header" in err, (rc, err))
        attached = Path(work) / "attached.txt"
        rc, stdout, err, pool, rs, _ = client(["--max-time=5000", "-o" + str(attached), s.base + "/a.txt"])
        expect(rc == 0 and stdout == b"" and attached.read_bytes() == b"alpha\n", (rc, err))
        s.counts()
    case(command_line)

    n = run_cases(cases)
    s.shutdown()
    return n


# ------------------------------------------------------------ nghttp2
def h2_context():
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(CERTS / "valid.pem"), str(CERTS / "valid.key"))
    context.set_alpn_protocols(["h2"])
    return context


def group_h2(work):
    s = h2server.Server(context=h2_context())
    base = "https://127.0.0.1:%d" % s.port
    out = Path(work) / "h2.bin"
    cases = []
    case = cases.append

    def settle():
        s.settle(2)
        conns = list(s.conns)
        del s.conns[:]
        return conns

    def flow_controlled_body():
        rc, stdout, err, pool, rs, _ = client(["--stats", "-o", str(out), base + "/size/5000000"], cacert=True)
        expect(rc == 0 and out.read_bytes() == gen(5000000), (rc, err))
        expect(rs[0]["version"] == "20" and rs[0]["streamed"] == "5000000" and pool["http2"] == 1, (rs, pool))
        expect(len(settle()) == 1, "one connection")
    case(flow_controlled_body)

    def streams_of_one_connection():
        rc, stdout, err, pool, rs, _ = client(["--stats", base + "/hello", base + "/size/70000", base + "/hello"], cacert=True)
        expect(rc == 0 and stdout == b"hello world\n" + gen(70000) + b"hello world\n", (rc, err))
        expect(pool["connections"] == 1 and pool["reused"] == 2 and pool["sessions"] == 1, pool)
        conns = settle()
        expect(len(conns) == 1 and len(conns[0].requests) == 3, "three streams")
    case(streams_of_one_connection)

    def past_the_buffered_body_limit():
        rc, rss, err = peak_rss(["-o", str(out), base + "/size/%d" % (17 * 1048576)], cacert=True)
        expect(rc == 0 and out.stat().st_size == 17 * 1048576, (rc, err))
        expect(hashlib.sha256(out.read_bytes()).digest() == hashlib.sha256(gen(17 * 1048576)).digest(), "17 MiB body")
        expect(rss < 20480, ("peak RSS KiB", rss))
        settle()
    case(past_the_buffered_body_limit)

    def redirect_on_the_connection():
        rc, stdout, err, pool, rs, _ = client(["--stats", "-L", base + "/redirect"], cacert=True)
        expect(rc == 0 and stdout == b"hello world\n" and rs[0]["redirects"] == "1" and rs[0]["streamed"] == "12", (rc, rs, err))
        expect(pool["connections"] == 1 and pool["requests"] == 2, pool)
        rc, stdout, err, pool, rs, _ = client(["--stats", base + "/redirect"], cacert=True)
        expect(rc == 0 and stdout == b"" and rs[0]["status"] == "302" and rs[0]["streamed"] == "0", (rc, rs, err))
        settle()
    case(redirect_on_the_connection)

    def reset_stream():
        rc, stdout, err, pool, rs, _ = client([base + "/rst/2"], cacert=True)
        expect(rc == 16 and "HTTP/2 error" in err, (rc, err))
        settle()
    case(reset_stream)

    def closed_stdout():
        rc, first, err = closed_pipe([base + "/size/%d" % (8 * 1048576)], cacert=True)
        expect(rc == 23 and first == gen(8 * 1048576)[:len(first)] and "write error" in err, (rc, len(first), err))
        conns = settle()
        # The server is blocked sending DATA the client stopped reading, so
        # it ends with a reset connection rather than reading RST_STREAM.
        expect(len(conns) == 1, "one connection")
    case(closed_stdout)

    n = run_cases(cases)
    s.stop()
    return n


# ------------------------------------------------------------ ext::http_proxy
def group_proxy(work, proxy_exe, tls_exe):
    from proxy_oracle import pattern, start_proxy, start_upstream, stop_proxy
    up_a, port_a = start_upstream("A")
    up_b, port_b = start_upstream("B")
    procs = [up_a, up_b]
    cases = []
    case = cases.append
    try:
        plain, plain_port = start_proxy(proxy_exe, port_a, port_b)
        procs.append(plain)
        secure, secure_port = start_proxy(tls_exe, port_a, port_b, extra=[str(CERTS / "valid.pem"), str(CERTS / "valid.key")])
        procs.append(secure)
        base = "http://127.0.0.1:%d" % plain_port
        tls = "https://127.0.0.1:%d" % secure_port

        def bodies_through_the_proxy():
            rc, stdout, err, pool, rs, _ = client(["--stats", base + "/fixed/3000000", base + "/chunked/200000", base + "/fixed/10"])
            expect(rc == 0 and stdout == pattern(3000000) + pattern(200000) + pattern(10), (rc, len(stdout), err))
            expect([r["streamed"] for r in rs] == ["3000000", "200000", "10"] and pool["connections"] == 1 and pool["reused"] == 2, (rs, pool))
        case(bodies_through_the_proxy)

        def close_delimited():
            rc, stdout, err, pool, rs, _ = client(["--stats", base + "/close/50000", base + "/fixed/5"])
            expect(rc == 0 and stdout == pattern(50000) + pattern(5), (rc, len(stdout), err))
            expect(rs[0]["kept"] == "0" and pool["connections"] == 2, (rs, pool))
        case(close_delimited)

        def http2_to_the_tls_proxy():
            rc, stdout, err, pool, rs, _ = client(["--stats", tls + "/fixed/3000000", tls + "/chunked/200000"], cacert=True)
            expect(rc == 0 and stdout == pattern(3000000) + pattern(200000), (rc, len(stdout), err))
            expect([r["version"] for r in rs] == ["20", "20"] and pool["http2"] == 1 and pool["connections"] == 1, (rs, pool))
        case(http2_to_the_tls_proxy)

        def http11_to_the_tls_proxy():
            rc, stdout, err, pool, rs, _ = client(["--stats", "--no-http2", tls + "/fixed/1000000", tls + "/fixed/7"], cacert=True)
            expect(rc == 0 and stdout == pattern(1000000) + pattern(7), (rc, len(stdout), err))
            expect([r["version"] for r in rs] == ["11", "11"] and pool["http2"] == 0 and pool["connections"] == 1, (rs, pool))
        case(http11_to_the_tls_proxy)

        n = run_cases(cases)
        stop_proxy(plain); stop_proxy(secure)
        return n
    finally:
        for p in procs:
            if p.poll() is None:
                p.kill()
                p.wait()


def main():
    global EXE, CERTS
    group, EXE = sys.argv[1], sys.argv[2]
    with tempfile.TemporaryDirectory() as work:
        CERTS = Path(work) / "certs"
        generate(CERTS)
        if group == "http":
            n = group_http(work)
        elif group == "h2":
            n = group_h2(work)
        elif group == "proxy":
            n = group_proxy(work, sys.argv[3], sys.argv[4])
        else:
            raise SystemExit("unknown group " + group)
    print("agent-fetch-%s cases=%d" % (group, n))


if __name__ == "__main__":
    main()
