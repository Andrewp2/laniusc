"""An HTTP/1.1 upstream for the proxy oracle and load test (asyncio).

Usage: upstream.py NAME. Prints its port, then serves until killed. The
request path picks the behaviour:

  /echo...      200 listing the request line, every header and the body's
                length and SHA-256; X-Conn and X-Seq name the connection
                and the request's position on it; hop-by-hop response
                fields (Connection: x-up-secret, X-Up-Secret, Keep-Alive)
                test that the proxy drops them
  /upload       like /echo, reading the body as it streams
  /fixed/N      N pattern bytes with Content-Length
  /chunked/N    N pattern bytes chunked (1000-byte chunks), trailer X-T
  /close/N      N pattern bytes delimited by closing (HTTP/1.0 style)
  /load/...     "TARGET X-TAG VIA", the load test's short answer
  /head-only    Content-Length: 1234 and no body (for HEAD)
  /304          304 Not Modified with an ETag
  /100          an interim 100 Continue, then 200
  /slow-head    the response head after 1.5 s
  /stall        a head promising 100000 bytes, 1000 of them, then silence
  /drop         close without answering
  /flaky        answer the first request on a connection; close on later ones
  /stream       a chunked response that echoes each request body piece as
                soon as it arrives (the request body must be chunked or
                have a length)
"""
import asyncio, hashlib, itertools, sys

NAME = sys.argv[1].encode() if len(sys.argv) > 1 else b"A"
CONN = itertools.count(1)


def pattern(n):
    block = bytes(range(97, 123)) * 40
    out = bytearray()
    while len(out) < n:
        out += block
    return bytes(out[:n])


class BadRequest(Exception):
    pass


async def body_pieces(reader, headers):
    """Yield the request body as it arrives."""
    length = headers.get(b"content-length")
    if headers.get(b"transfer-encoding", b"").lower() == b"chunked":
        while True:
            line = await reader.readuntil(b"\r\n")
            size = int(line.split(b";")[0].strip(), 16)
            if size == 0:
                while (await reader.readuntil(b"\r\n")) != b"\r\n":
                    pass
                return
            left = size
            while left:
                piece = await reader.read(min(left, 65536))
                if not piece:
                    raise BadRequest()
                left -= len(piece)
                yield piece
            if await reader.readexactly(2) != b"\r\n":
                raise BadRequest()
    elif length is not None:
        left = int(length)
        while left:
            piece = await reader.read(min(left, 65536))
            if not piece:
                raise BadRequest()
            left -= len(piece)
            yield piece


def response(status, reason, fields, body=b""):
    head = b"HTTP/1.1 %d %s\r\n" % (status, reason)
    for k, v in fields:
        head += k + b": " + v + b"\r\n"
    return head + b"\r\n" + body


async def handle(reader, writer):
    conn = next(CONN)
    seq = 0
    try:
        while True:
            try:
                raw = await reader.readuntil(b"\r\n\r\n")
            except (asyncio.IncompleteReadError, ConnectionError):
                return
            seq += 1
            lines = raw[:-4].split(b"\r\n")
            method, target, version = lines[0].split(b" ")
            fields = []
            for line in lines[1:]:
                k, v = line.split(b":", 1)
                fields.append((k.strip().lower(), v.strip()))
            headers = {}
            for k, v in fields:
                headers.setdefault(k, v)
            path = target.split(b"?")[0]
            ident = [(b"X-Conn", b"%s-%d" % (NAME, conn)), (b"X-Seq", b"%d" % seq)]
            if path == b"/drop" or (path == b"/flaky" and seq > 1):
                return
            if path == b"/stream":
                writer.write(response(200, b"OK", ident + [(b"Transfer-Encoding", b"chunked")]))
                await writer.drain()
                async for piece in body_pieces(reader, headers):
                    writer.write(b"%x\r\n" % len(piece) + piece + b"\r\n")
                    await writer.drain()
                writer.write(b"0\r\n\r\n")
                await writer.drain()
                continue
            digest, size = hashlib.sha256(), 0
            async for piece in body_pieces(reader, headers):
                digest.update(piece)
                size += len(piece)
            if path == b"/slow-head":
                await asyncio.sleep(1.5)
            if path == b"/stall":
                writer.write(response(200, b"OK", ident + [(b"Content-Length", b"100000")]) + pattern(1000))
                await writer.drain()
                await asyncio.sleep(3)
                return
            if path.startswith(b"/fixed/"):
                n = int(path[7:])
                writer.write(response(200, b"OK", ident + [(b"Content-Length", b"%d" % n)]))
                data = pattern(n)
                for at in range(0, n, 1 << 20):
                    writer.write(data[at:at + (1 << 20)])
                    await writer.drain()
                continue
            if path.startswith(b"/chunked/"):
                n = int(path[9:])
                writer.write(response(200, b"OK", ident + [(b"Transfer-Encoding", b"chunked"), (b"Trailer", b"X-T")]))
                data = pattern(n)
                for at in range(0, n, 1000):
                    piece = data[at:at + 1000]
                    writer.write(b"%x\r\n" % len(piece) + piece + b"\r\n")
                writer.write(b"0\r\nX-T: 1\r\n\r\n")
                await writer.drain()
                continue
            if path.startswith(b"/close/"):
                n = int(path[7:])
                writer.write(b"HTTP/1.1 200 OK\r\nConnection: close\r\nX-Conn: %s-%d\r\n\r\n" % (NAME, conn) + pattern(n))
                await writer.drain()
                return
            if path.startswith(b"/load/"):
                body = target + b" " + headers.get(b"x-tag", b"-") + b" " + headers.get(b"via", b"-")
                writer.write(response(200, b"OK", [(b"Content-Length", b"%d" % len(body))], body))
                await writer.drain()
                continue
            if path == b"/head-only":
                writer.write(response(200, b"OK", ident + [(b"Content-Length", b"1234")]))
                await writer.drain()
                continue
            if path == b"/304":
                writer.write(response(304, b"Not Modified", ident + [(b"ETag", b'"v1"')]))
                await writer.drain()
                continue
            if path == b"/100":
                writer.write(b"HTTP/1.1 100 Continue\r\n\r\n")
            text = bytearray(b"upstream=%s\nrequest=%s %s %s\n" % (NAME, method, target, version))
            for k, v in fields:
                text += b"h:" + k + b"=" + v + b"\n"
            text += b"body-len=%d\nbody-sha=%s\n" % (size, digest.hexdigest().encode())
            extra = [(b"Connection", b"x-up-secret"), (b"X-Up-Secret", b"1"), (b"Keep-Alive", b"timeout=5")]
            body = b"" if method == b"HEAD" else bytes(text)
            writer.write(response(200, b"OK", ident + extra + [(b"Content-Type", b"text/plain"), (b"Content-Length", b"%d" % len(text))], body))
            await writer.drain()
    except (BadRequest, ConnectionError, asyncio.IncompleteReadError, ValueError):
        return
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", 0, backlog=1024, limit=1 << 20)
    print(server.sockets[0].getsockname()[1], flush=True)
    async with server:
        await server.serve_forever()

asyncio.run(main())
