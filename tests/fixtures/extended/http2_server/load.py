"""Load test for the event server (h2c_events.lani): CLIENTS concurrent
h2c clients (libnghttp2 sessions through ctypes), each with REQUESTS
multiplexed requests, then CLIENTS concurrent HTTP/1.1 keep-alive clients
with REQUESTS sequential requests each. Every response body is checked.

usage: load.py SERVER [CLIENTS] [REQUESTS]
"""
import os
import resource
import select
import socket
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import nghttp2_client as ng  # noqa: E402


def connect_all(port, n):
    out = []
    for _ in range(n):
        s = socket.create_connection(("127.0.0.1", port), timeout=5)
        s.setblocking(False)
        out.append(s)
    return out


def send_some(s, buf):
    try:
        n = s.send(buf)
    except BlockingIOError:
        return buf
    return buf[n:]


def h2_load(port, clients, requests, limit=60.0):
    socks = connect_all(port, clients)
    sessions, pending, ids = [], [], []
    for s in socks:
        c = ng.Client()
        ids.append([c.request(b"GET", b"/load/%d" % i, [(b"x-tag", b"c%d" % len(sessions))]) for i in range(requests)])
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
            data = s.recv(262144)
            if not data:
                raise AssertionError("h2 client %d: server closed early" % k)
            sessions[k].receive(data)
            if all(sessions[k].streams[i].closed for i in ids[k]):
                done[k] = True
    seconds = time.time() - start
    for k, c in enumerate(sessions):
        for n, i in enumerate(ids[k]):
            st = c.streams[i]
            if st.status != 200 or bytes(st.body) != b"GET /load/%d c%d " % (n, k):
                raise AssertionError(("h2 response", k, n, st.status, bytes(st.body)[:60]))
        c.close()
    for s in socks:
        s.close()
    return seconds


def h1_load(port, clients, requests, limit=60.0):
    socks = connect_all(port, clients)
    sent = [0] * clients
    got = [0] * clients
    inbox = [b""] * clients
    outbox = [b""] * clients
    by_fd = {s.fileno(): k for k, s in enumerate(socks)}

    def request(k):
        outbox[k] += b"GET /load/%d HTTP/1.1\r\nHost: x\r\n\r\n" % sent[k]
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
            data = s.recv(65536)
            if not data:
                raise AssertionError("h1 client %d: server closed early" % k)
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
                if not head.startswith(b"http/1.1 200") or body != b"h1 /load/%d" % got[k]:
                    raise AssertionError(("h1 response", k, got[k], head[:40], body))
                got[k] += 1
                if sent[k] < requests:
                    request(k)
    seconds = time.time() - start
    for s in socks:
        s.close()
    return seconds


def main():
    exe = sys.argv[1]
    clients = int(sys.argv[2]) if len(sys.argv) > 2 else 100
    requests = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    server = subprocess.Popen([exe, "2000"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        port = int(server.stdout.readline().decode().rsplit(":", 1)[1])
        cpu = lambda: (lambda u: u.ru_utime + u.ru_stime)(resource.getrusage(resource.RUSAGE_SELF))
        mark = cpu(); h2 = h2_load(port, clients, requests); h2_client = cpu() - mark
        mark = cpu(); h1 = h1_load(port, clients, requests); h1_client = cpu() - mark
        stats = server.stdout.readline().decode().strip()
        code = server.wait(timeout=30)
    finally:
        if server.poll() is None:
            server.kill()
            server.wait()
    child = resource.getrusage(resource.RUSAGE_CHILDREN)
    total = clients * requests
    want = "connections=%d h2=%d requests=%d" % (2 * clients, clients, 2 * total)
    if code != 0 or not stats.startswith(want) or not stats.endswith("errors=0"):
        raise AssertionError(("server counters", code, stats, want))
    peak = int(stats.split("peak=")[1].split()[0])
    if peak < clients:
        raise AssertionError(("peak below client count", stats))
    print("load clients=%d requests=%d h2c=%.3fs (%.0f req/s, client cpu %.2fs) http1=%.3fs (%.0f req/s, client cpu %.2fs) server cpu %.2fs peak=%d"
          % (clients, requests, h2, total / h2, h2_client, h1, total / h1, h1_client, child.ru_utime + child.ru_stime, peak))
    print("load-check clients=%d requests=%d %s" % (clients, requests, want + " errors=0"))


if __name__ == "__main__":
    main()
