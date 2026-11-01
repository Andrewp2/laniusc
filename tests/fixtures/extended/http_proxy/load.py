"""Load test for the reverse proxy (proxy_main.lani, "load" profile) in
front of one asyncio upstream (upstream.py): CLIENTS concurrent h2c
clients (libnghttp2 sessions through ctypes) with REQUESTS multiplexed
requests each, then CLIENTS concurrent HTTP/1.1 keep-alive clients with
REQUESTS sequential requests each, and the same HTTP/1.1 phase straight
to the upstream for comparison. Every body is checked. With --tls, PROXY
is tls_main.lani and both proxy phases run over TLS (ALPN h2, then
http/1.1) with a throwaway certificate; there is no direct phase.

usage: load.py PROXY [CLIENTS] [REQUESTS] [--tls]
"""
import os
import select
import socket
import ssl
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "http2_server"))
import nghttp2_client as ng  # noqa: E402
sys.path.insert(0, HERE)
from tls_oracle_common import certificate, wrapper  # noqa: E402

WOULD_BLOCK = (BlockingIOError, ssl.SSLWantReadError, ssl.SSLWantWriteError)


def connect_all(port, n, wrap=None):
    out = []
    for _ in range(n):
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        if wrap:
            s = wrap(s)
        s.setblocking(False)
        out.append(s)
    return out


def send_some(s, buf):
    try:
        n = s.send(buf)
    except WOULD_BLOCK:
        return buf
    return buf[n:]


def receive(s):
    """What is readable now; b"" at EOF. A TLS socket may hold decrypted
    bytes select cannot see, so read until it would block."""
    data = b""
    while True:
        try:
            piece = s.recv(262144)
        except WOULD_BLOCK:
            return data if data else None
        if not piece:
            return data
        data += piece
        if not isinstance(s, ssl.SSLSocket):
            return data


def h2_load(port, clients, requests, limit=60.0, wrap=None):
    socks = connect_all(port, clients, wrap)
    sessions, pending, ids = [], [], []
    for k, s in enumerate(socks):
        c = ng.Client()
        ids.append([c.request(b"GET", b"/load/%d" % i, [(b"x-tag", b"c%d" % k)]) for i in range(requests)])
        sessions.append(c)
        pending.append(b"")
    start = time.time()
    done = [False] * clients
    by_fd = {s.fileno(): k for k, s in enumerate(socks)}
    while not all(done):
        if time.time() - start > limit:
            raise AssertionError("h2 load timed out: %d of %d clients done" % (sum(done), clients))
        writers = []
        for k, c in enumerate(sessions):
            if done[k]:
                continue
            pending[k] += c.output()
            if pending[k]:
                pending[k] = send_some(socks[k], pending[k])
            if pending[k]:
                writers.append(socks[k])
        readers = [socks[k] for k in range(clients) if not done[k]]
        r, w, _ = select.select(readers, writers, [], 0.5)
        for s in r:
            k = by_fd[s.fileno()]
            data = receive(s)
            if data is None:
                continue
            if not data:
                raise AssertionError("h2 client %d: proxy closed early" % k)
            sessions[k].receive(data)
            if all(sessions[k].streams[i].closed for i in ids[k]):
                done[k] = True
    seconds = time.time() - start
    for k, c in enumerate(sessions):
        for n, i in enumerate(ids[k]):
            st = c.streams[i]
            if st.status != 200 or bytes(st.body) != b"/load/%d c%d 2 lanius" % (n, k):
                raise AssertionError(("h2 response", k, n, st.status, bytes(st.body)[:60]))
        c.close()
    for s in socks:
        s.close()
    return seconds


def h1_load(port, clients, requests, via, limit=60.0, wrap=None):
    socks = connect_all(port, clients, wrap)
    sent, got = [0] * clients, [0] * clients
    inbox, outbox = [b""] * clients, [b""] * clients
    by_fd = {s.fileno(): k for k, s in enumerate(socks)}

    def request(k):
        outbox[k] += b"GET /load/%d HTTP/1.1\r\nHost: x\r\nX-Tag: h%d\r\n\r\n" % (sent[k], k)
        sent[k] += 1
    for k in range(clients):
        request(k)
    start = time.time()
    while min(got) < requests:
        if time.time() - start > limit:
            raise AssertionError("h1 load timed out")
        writers = []
        for k in range(clients):
            if outbox[k]:
                outbox[k] = send_some(socks[k], outbox[k])
            if outbox[k]:
                writers.append(socks[k])
        readers = [socks[k] for k in range(clients) if got[k] < requests]
        r, w, _ = select.select(readers, writers, [], 0.5)
        for s in r:
            k = by_fd[s.fileno()]
            data = receive(s)
            if data is None:
                continue
            if not data:
                raise AssertionError("h1 client %d: closed early" % k)
            inbox[k] += data
            while True:
                head_end = inbox[k].find(b"\r\n\r\n")
                if head_end < 0:
                    break
                head = inbox[k][:head_end].lower()
                length = int(head.split(b"content-length:")[1].split(b"\r\n")[0])
                if len(inbox[k]) < head_end + 4 + length:
                    break
                body = inbox[k][head_end + 4:head_end + 4 + length]
                inbox[k] = inbox[k][head_end + 4 + length:]
                if not head.startswith(b"http/1.1 200") or body != b"/load/%d h%d %s" % (got[k], k, via):
                    raise AssertionError(("h1 response", k, got[k], head[:40], body))
                got[k] += 1
                if sent[k] < requests:
                    request(k)
    seconds = time.time() - start
    for s in socks:
        s.close()
    return seconds


def cpu(pid):
    fields = open("/proc/%d/stat" % pid).read().rsplit(")", 1)[1].split()
    return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")


def peak_rss_kib(pid):
    for line in open("/proc/%d/status" % pid):
        if line.startswith("VmHWM:"):
            return int(line.split()[1])
    return 0


def main():
    args = [a for a in sys.argv[1:] if a != "--tls"]
    tls = "--tls" in sys.argv
    exe = args[0]
    clients = int(args[1]) if len(args) > 1 else 100
    requests = int(args[2]) if len(args) > 2 else 20
    work = tempfile.TemporaryDirectory()
    extra, h2_wrap, h1_wrap = [], None, None
    if tls:
        cert, key = certificate(work.name)
        extra, h2_wrap, h1_wrap = [cert, key], wrapper(cert, ["h2"]), wrapper(cert, ["http/1.1"])
    upstream = subprocess.Popen([sys.executable, "-I", os.path.join(HERE, "upstream.py"), "A"], stdout=subprocess.PIPE)
    up_port = int(upstream.stdout.readline())
    proxy = subprocess.Popen([exe, "1000", str(up_port), str(up_port), "load"] + extra, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    direct = None
    try:
        port = int(proxy.stdout.readline().decode().rsplit(":", 1)[1])
        mark = cpu(proxy.pid); h2 = h2_load(port, clients, requests, wrap=h2_wrap); h2_cpu = cpu(proxy.pid) - mark
        mark = cpu(proxy.pid); h1 = h1_load(port, clients, requests, b"1.1 lanius", wrap=h1_wrap); h1_cpu = cpu(proxy.pid) - mark
        rss = peak_rss_kib(proxy.pid)
        if not tls:
            direct = h1_load(up_port, clients, requests, b"-")
        out, err = proxy.communicate(timeout=60)
    finally:
        if proxy.poll() is None:
            proxy.kill()
        upstream.kill(); work.cleanup()
    if proxy.returncode != 0 or err:
        raise AssertionError(("proxy exit", proxy.returncode, err[-300:]))
    stats = dict(kv.split("=") for kv in out.decode().strip().splitlines()[-1].split())
    total = clients * requests
    if tls:
        print("load-tls clients=%d requests=%d h2=%.3fs (%.0f req/s, proxy cpu %.2fs) http1=%.3fs (%.0f req/s, proxy cpu %.2fs) connects=%s peak_rss=%d KiB"
              % (clients, requests, h2, total / h2, h2_cpu, h1, total / h1, h1_cpu, stats["connects"], rss))
    else:
        print("load clients=%d requests=%d h2c=%.3fs (%.0f req/s, proxy cpu %.2fs) http1=%.3fs (%.0f req/s, proxy cpu %.2fs) direct http1=%.3fs (%.0f req/s) connects=%s peak_rss=%d KiB"
              % (clients, requests, h2, total / h2, h2_cpu, h1, total / h1, h1_cpu, direct, total / direct, stats["connects"], rss))
    want = {"clients": 2 * clients, "h2": clients, "requests": 2 * total, "h2_requests": total, "responses": 2 * total, "bad_gateway": 0, "gateway_timeout": 0, "aborted": 0}
    if tls:
        want.update({"tls_handshakes": 2 * clients, "tls_h2": clients, "tls_failures": 0})
    for k, v in want.items():
        if int(stats[k]) != v:
            raise AssertionError(("stats", k, stats))
    print("load-check%s clients=%d requests=%d proxied=%d h2_requests=%d errors=0" % ("-tls" if tls else "", clients, requests, 2 * total, total))


main()
