"""ext::http_proxy_tls oracle: the TLS proxy fixture (tls_main) in front of
Python upstreams, driven by Python's ssl module (OpenSSL) with HTTP/1.1
sockets and libnghttp2 sessions over ALPN h2. A throwaway self-signed
certificate is made with the openssl command. Usage: tls_oracle.py
TLS_PROXY_EXE. Prints one summary line."""
import os, socket, ssl, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from proxy_oracle import H1, H2, check, h2_echo, pattern, sha, start_proxy, start_upstream, stop_proxy


def certificate(directory):
    cert, key = os.path.join(directory, "cert.pem"), os.path.join(directory, "key.pem")
    subprocess.run(["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
                    "-keyout", key, "-out", cert, "-days", "2", "-subj", "/CN=localhost",
                    "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)
    return cert, key


def wrapper(cert, protocols):
    context = ssl.create_default_context(cafile=cert)
    if protocols:
        context.set_alpn_protocols(protocols)
    # A missing close_notify must show as an error, not a clean EOF.
    return lambda s: context.wrap_socket(s, server_hostname="localhost", suppress_ragged_eofs=False)


def main():
    exe = sys.argv[1]
    up_a, port_a = start_upstream("A")
    up_b, port_b = start_upstream("B")
    work = tempfile.TemporaryDirectory()
    try:
        cert, key = certificate(work.name)
        proxy, port = start_proxy(exe, port_a, port_b, extra=[cert, key])
    except Exception:
        up_a.kill(); up_b.kill(); work.cleanup()
        raise
    h1, h2, either, none = wrapper(cert, ["http/1.1"]), wrapper(cert, ["h2"]), wrapper(cert, ["h2", "http/1.1"]), wrapper(cert, None)
    cases = 0
    try:
        # ALPN http/1.1: the request is rewritten with X-Forwarded-Proto https.
        c = H1(port, wrap=h1)
        check(c.s.selected_alpn_protocol() == "http/1.1" and c.s.version() in ("TLSv1.2", "TLSv1.3"), ("alpn h1", c.s.selected_alpn_protocol()))
        c.send(b"GET /echo/tls HTTP/1.1\r\nHost: test\r\nConnection: keep-alive, X-Secret\r\nX-Secret: 1\r\n\r\n")
        r = c.response(); e = r.echo(); h = dict(e["h"])
        check(r.status == 200 and e["request"] == "GET /echo/tls HTTP/1.1" and h.get("x-forwarded-proto") == "https" and h.get("x-forwarded-for") == "127.0.0.1" and h.get("via") == "1.1 lanius" and "x-secret" not in h, ("h1 rewrite", r.status, e))
        check(r.header(b"via") == b"1.1 lanius" and r.header(b"x-up-secret") is None, ("h1 response fields", r.headers))
        cases += 1
        # Keep-alive on one TLS connection: uploads and downloads that span
        # many records, fixed and chunked.
        body = pattern(1000000)
        c.send(b"POST /upload HTTP/1.1\r\nHost: t\r\nContent-Length: %d\r\n\r\n" % len(body) + body)
        e = c.response().echo(); check(e["body-sha"] == sha(body), ("h1 tls upload", e)); cases += 1
        wire = b"".join(b"%x\r\n" % len(body[i:min(i + 9000, 300000)]) + body[i:min(i + 9000, 300000)] + b"\r\n" for i in range(0, 300000, 9000)) + b"0\r\n\r\n"
        c.send(b"POST /echo HTTP/1.1\r\nHost: t\r\nTransfer-Encoding: chunked\r\n\r\n" + wire)
        e = c.response().echo(); check(e["body-sha"] == sha(body[:300000]) and e["body-len"] == "300000", ("h1 tls chunked upload", e)); cases += 1
        c.send(b"GET /fixed/3000000 HTTP/1.1\r\nHost: t\r\n\r\n")
        r = c.response(); check(r.status == 200 and sha(r.body) == sha(pattern(3000000)), "h1 tls download"); cases += 1
        c.send(b"GET /chunked/200000 HTTP/1.1\r\nHost: t\r\n\r\nGET /b/x HTTP/1.1\r\nHost: t\r\n\r\n")
        r1 = c.response(); r2 = c.response()
        check(r1.body == pattern(200000) and r1.trailers == [b"X-T: 1"] and r2.echo()["upstream"] == "B", ("h1 tls chunked, pipelined", r1.trailers)); cases += 1
        # Connection: close ends with close_notify before the FIN.
        c.send(b"GET /echo/last HTTP/1.1\r\nHost: t\r\nConnection: close\r\n\r\n")
        r = c.response(); check(r.status == 200 and r.header(b"connection") == b"close", "h1 tls close")
        check(c.s.recv(100) == b"", "close_notify"); c.close(); cases += 1
        # A close-delimited upstream response reaches the client whole.
        c = H1(port, wrap=h1); c.send(b"GET /close/50000 HTTP/1.0\r\nHost: t\r\n\r\n")
        r = c.response(); check(r.body == pattern(50000), ("h1 tls close-delimited", len(r.body))); c.close(); cases += 1
        # No ALPN offered: HTTP/1.1.
        c = H1(port, wrap=none)
        check(c.s.selected_alpn_protocol() is None, "no alpn")
        c.send(b"GET /echo HTTP/1.1\r\nHost: t\r\n\r\n"); check(c.response().status == 200, "no alpn request"); c.close(); cases += 1
        # ALPN h2 (offered alone, or before http/1.1): HTTP/2 over TLS.
        for wrap in (h2, either):
            c = H2(port, wrap=wrap)
            check(c.s.selected_alpn_protocol() == "h2", ("alpn h2", c.s.selected_alpn_protocol()))
            sids = [c.request(b"GET", b"/echo/%d" % i, [(b"x-tag", b"t%d" % i)]) for i in range(10)]
            for i, st in enumerate(c.wait(*sids)):
                e = h2_echo(st); h = dict(e["h"])
                check(st.status == 200 and h["x-tag"] == "t%d" % i and h["via"] == "2 lanius" and h["x-forwarded-proto"] == "https", ("h2 tls", i, e))
            cases += 1
        s1 = c.request(b"POST", b"/upload", [(b"content-length", b"1000000")], body)
        s2 = c.request(b"GET", b"/fixed/3000000"); s3 = c.request(b"GET", b"/b/q")
        r1, r2, r3 = c.wait(s1, s2, s3)
        check(h2_echo(r1)["body-sha"] == sha(body) and sha(bytes(r2.body)) == sha(pattern(3000000)) and h2_echo(r3)["upstream"] == "B", "h2 tls bodies"); cases += 1
        sid = c.streaming(b"POST", b"/stream")
        for k in range(3):
            piece = bytes([97 + k]) * (20000 + k); want = len(c.c.streams[sid].body) + len(piece)
            c.feed(sid, piece); c.pump(lambda: len(c.c.streams[sid].body) >= want)
        c.feed(sid, b"", end=True); st = c.wait(sid)[0]
        check(st.status == 200 and bytes(st.body[-20002:]) == b"c" * 20002, "h2 tls streaming"); cases += 1
        c.close()
        # Plain HTTP to the TLS port fails the handshake and is dropped.
        c = H1(port); c.send(b"GET / HTTP/1.1\r\nHost: t\r\n\r\n")
        check(c.closed(), "plain to tls"); c.close(); cases += 1
    finally:
        stats = stop_proxy(proxy)
        up_a.kill(); up_b.kill(); work.cleanup()
    check(stats["tls_handshakes"] == 5 and stats["tls_h2"] == 2 and stats["tls_failures"] == 1 and stats["h2"] == 2, ("stats", stats))
    print("http-proxy-tls cases=%d handshakes=%d h2=%d requests=%d failures=%d" % (cases, stats["tls_handshakes"], stats["tls_h2"], stats["requests"], stats["tls_failures"]))

main()
