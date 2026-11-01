"""ext::http_service_tls oracle: the TLS event server fixture (tls_events)
driven by Python's ssl module (OpenSSL) with libnghttp2 sessions over ALPN
h2 and raw HTTP/1.1 sockets. A throwaway self-signed certificate is made
with the openssl command. Usage: tls_oracle.py TLS_EVENTS_EXE. Prints one
summary line."""
import os, ssl, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "http_proxy"))
from proxy_oracle import H1, H2, check
from tls_oracle_common import certificate, wrapper


def pattern(n):
    return bytes(97 + i % 26 for i in range(n))


def main():
    exe = sys.argv[1]
    work = tempfile.TemporaryDirectory()
    cert, key = certificate(work.name)
    server = subprocess.Popen([exe, "1500", cert, key], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    cases = 0
    try:
        port = int(server.stdout.readline().decode().rsplit(":", 1)[1])
        h1, h2, none = wrapper(cert, ["http/1.1"]), wrapper(cert, ["h2", "http/1.1"]), wrapper(cert, None)
        # ALPN h2: multiplexed streams, a request body and a large response.
        c = H2(port, wrap=h2)
        check(c.s.selected_alpn_protocol() == "h2", ("alpn", c.s.selected_alpn_protocol()))
        sids = [c.request(b"GET", b"/echo/%d" % i, [(b"x-tag", b"t%d" % i)]) for i in range(30)]
        for i, st in enumerate(c.wait(*sids)):
            check(st.status == 200 and bytes(st.body) == b"GET /echo/%d t%d " % (i, i), ("h2 echo", i, st.status, bytes(st.body)[:80]))
        cases += 1
        body = pattern(150000)
        st = c.wait(c.request(b"POST", b"/up", [(b"content-length", b"150000")], body))[0]
        check(bytes(st.body) == b"POST /up  " + body, "h2 tls upload"); cases += 1
        s1, s2 = c.request(b"GET", b"/big/2000000"), c.request(b"GET", b"/big/70000")
        r1, r2 = c.wait(s1, s2)
        check(bytes(r1.body) == pattern(2000000) and bytes(r2.body) == pattern(70000), "h2 tls big"); cases += 1
        c.close()
        # ALPN http/1.1 with keep-alive, then Connection: close with close_notify.
        c = H1(port, wrap=h1)
        check(c.s.selected_alpn_protocol() == "http/1.1", "alpn h1")
        for i in range(3):
            c.send(b"GET /k%d HTTP/1.1\r\nHost: t\r\n\r\n" % i)
            r = c.response(); check(r.status == 200 and r.body == b"h1 /k%d" % i, ("h1 keep-alive", r.status, r.body))
        c.send(b"GET /a HTTP/1.1\r\nHost: t\r\n\r\nGET /b HTTP/1.1\r\nHost: t\r\n\r\n")
        check(c.response().body == b"h1 /a" and c.response().body == b"h1 /b", "h1 pipelined")
        c.send(b"GET /last HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        r = c.response(); check(r.body == b"h1 /last" and c.s.recv(10) == b"", "h1 close_notify"); c.close()
        cases += 3
        # No ALPN: HTTP/1.1.
        c = H1(port, wrap=none); c.send(b"GET /n HTTP/1.1\r\nHost: t\r\n\r\n")
        check(c.s.selected_alpn_protocol() is None and c.response().body == b"h1 /n", "no alpn"); c.close(); cases += 1
        # Plain HTTP to the TLS port fails the handshake and is dropped.
        c = H1(port); c.send(b"GET / HTTP/1.1\r\nHost: t\r\n\r\n")
        check(c.closed(), "plain to tls"); c.close(); cases += 1
        out, err = server.communicate(timeout=60)
    finally:
        if server.poll() is None:
            server.kill()
        work.cleanup()
    check(server.returncode == 0 and not err, ("exit", server.returncode, err[-300:]))
    stats = {k: int(v) for k, v in (kv.split("=") for kv in out.decode().strip().splitlines()[-1].split())}
    check(stats["tls_handshakes"] == 3 and stats["tls_h2"] == 1 and stats["tls_failures"] == 1 and stats["h2"] == 1, ("stats", stats))
    print("http-service-tls cases=%d handshakes=%d h2=%d requests=%d" % (cases, stats["tls_handshakes"], stats["tls_h2"], stats["requests"]))

main()
