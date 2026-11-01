"""ext::http_rewrite oracle: fixed inputs and the exact heads a reverse
proxy must produce (RFC 9110 7.6, RFC 9113 8.2.3 and 8.3)."""
import subprocess, sys

def run(exe, args, data):
    p = subprocess.run([exe] + args, input=data, capture_output=True, timeout=30)
    if p.returncode != 0 or p.stderr:
        raise AssertionError(("exit", args, p.returncode, p.stderr))
    return p.stdout

CASES = [
    (["request"],
     b"POST /a?b HTTP/1.1\r\nHost: up\r\nConnection: keep-alive, X-Secret\r\nX-Secret: 1\r\nKeep-Alive: 5\r\n"
     b"X-Forwarded-For: 10.0.0.1\r\nVia: 1.0 edge\r\nTransfer-Encoding: chunked\r\nTE: trailers\r\n"
     b"Expect: 100-continue\r\nAccept: */*\r\n\r\n",
     b"POST /a?b HTTP/1.1\r\nHost: up\r\nAccept: */*\r\nTransfer-Encoding: chunked\r\n"
     b"X-Forwarded-For: 10.0.0.1, 192.0.2.7\r\nX-Forwarded-Proto: http\r\nVia: 1.0 edge, 1.1 lanius\r\n\r\n"),
    (["request"],
     b"PUT /x HTTP/1.0\r\nHost: up\r\nContent-Length: 5\r\nX-Forwarded-For: a\r\nX-Forwarded-For: b\r\nX-Forwarded-Proto: https\r\nUpgrade: h2c\r\nProxy-Connection: keep-alive\r\n\r\n",
     b"PUT /x HTTP/1.1\r\nHost: up\r\nX-Forwarded-Proto: https\r\nContent-Length: 5\r\nX-Forwarded-For: a, b, 192.0.2.7\r\nVia: 1.0 lanius\r\n\r\n"),
    (["request"], b"GET / HTTP/1.1\r\n\r\n", b"error\n"),
    (["response-keep"],
     b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 12\r\nConnection: close\r\nVia: 1.1 origin\r\nSet-Cookie: a=1\r\n\r\n",
     b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nSet-Cookie: a=1\r\nContent-Length: 12\r\nVia: 1.1 origin, 1.1 lanius\r\nConnection: keep-alive\r\n\r\n"),
    (["response-close"],
     b"HTTP/1.0 404 Missing\r\nKeep-Alive: timeout=5\r\n\r\n",
     b"HTTP/1.1 404 Missing\r\nVia: 1.0 lanius\r\nConnection: close\r\n\r\n"),
    (["response-keep"],
     b"HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\nContent-Length: 99\r\n\r\n",
     b"HTTP/1.1 304 Not Modified\r\nETag: \"v1\"\r\nContent-Length: 99\r\nVia: 1.1 lanius\r\nConnection: keep-alive\r\n\r\n"),
    (["h2-response"],
     b"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\nVia: 1.1 origin\r\nX-Hop: y\r\nConnection: x-hop\r\n\r\n",
     b"content-type: text/plain\nvia: 1.1 origin, 1.1 lanius\n"),
    (["h2-response"],
     b"HTTP/1.1 201 Created\r\nLocation: /n\r\nContent-Length: 3\r\nKeep-Alive: 1\r\n\r\n",
     b"location: /n\ncontent-length: 3\nvia: 1.1 lanius\n"),
    (["h2-request", "-1"],
     b":method: POST\n:scheme: http\n:authority: example.test:8080\n:path: /up?x=1\ncookie: a=1\nuser-agent: t\ncookie: b=2\nte: trailers\nx-forwarded-for: 10.1.1.1\n\n",
     b"POST /up?x=1 HTTP/1.1\r\nuser-agent: t\r\nHost: example.test:8080\r\nCookie: a=1; b=2\r\nTransfer-Encoding: chunked\r\n"
     b"X-Forwarded-For: 10.1.1.1, 192.0.2.7\r\nX-Forwarded-Proto: http\r\nVia: 2 lanius\r\n\r\n"),
    (["h2-request", "7"],
     b":method: PUT\n:scheme: http\n:authority: a\n:path: /p\nhost: b\ncontent-length: 7\nvia: 1.1 far\n\n",
     b"PUT /p HTTP/1.1\r\nhost: b\r\nContent-Length: 7\r\nX-Forwarded-For: 192.0.2.7\r\nX-Forwarded-Proto: http\r\nVia: 1.1 far, 2 lanius\r\n\r\n"),
    (["h2-request", "-2"],
     b":method: GET\n:scheme: http\n:authority: a\n:path: /\n\n",
     b"GET / HTTP/1.1\r\nHost: a\r\nX-Forwarded-For: 192.0.2.7\r\nX-Forwarded-Proto: http\r\nVia: 2 lanius\r\n\r\n"),
    # Two Connection fields, then three (the token set's scan fallback).
    (["request"],
     b"GET /c HTTP/1.1\r\nHost: up\r\nconnection: X-A\r\nX-A: 1\r\nX: 2\r\nX-B: 3\r\nCONNECTION: , x-b ,x-c\r\nX-C: 4\r\nX-D: 5\r\nX-Forwarded-For:\r\n\r\n",
     b"GET /c HTTP/1.1\r\nHost: up\r\nX: 2\r\nX-D: 5\r\nX-Forwarded-For: 192.0.2.7\r\nX-Forwarded-Proto: http\r\nVia: 1.1 lanius\r\n\r\n"),
    (["response-keep"],
     b"HTTP/1.1 200 OK\r\nConnection: x-a\r\nConnection: x-b\r\nX-A: 1\r\nX-B: 2\r\nX-C: 3\r\nconnection: X-C\r\nX-AB: 4\r\nContent-Length: 0\r\n\r\n",
     b"HTTP/1.1 200 OK\r\nX-AB: 4\r\nContent-Length: 0\r\nVia: 1.1 lanius\r\nConnection: keep-alive\r\n\r\n"),
]

def main():
    exe = sys.argv[1]
    for args, data, want in CASES:
        got = run(exe, args, data)
        if got != want:
            raise AssertionError((args, data[:40], got, want))
    print("http-rewrite cases=%d" % len(CASES))

main()
