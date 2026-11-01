"""ext::http_body oracle: frames generated bodies through body_driver at
several piece sizes and compares the content, the consumed count and the
verdict with Python's reading of RFC 9112 framing."""
import random, subprocess, sys

def run(exe, kind, piece, data):
    p = subprocess.run([exe, kind, str(piece)], input=data, capture_output=True, timeout=30)
    if p.returncode != 0:
        raise AssertionError(("exit", kind, piece, p.returncode, p.stderr[-200:]))
    return p.stdout, p.stderr.decode().strip().splitlines()[-1]

def chunked(rng, sizes, ext=False, trailers=()):
    out, content = bytearray(), bytearray()
    for n in sizes:
        piece = bytes(rng.randrange(256) for _ in range(n))
        size = b"%x" % n if rng.random() < 0.5 else b"%X" % n
        if ext:
            size += b" ;name=value;flag"
        out += size + b"\r\n" + piece + b"\r\n"; content += piece
    out += b"0\r\n" + b"".join(t + b"\r\n" for t in trailers) + b"\r\n"
    return bytes(out), bytes(content)

def main():
    exe = sys.argv[1]; rng = random.Random(7); cases = 0
    pieces = [1, 2, 3, 7, 64, 4096]
    valid = []
    for k in range(6):
        sizes = [rng.choice([1, 2, 15, 16, 255, 4096, 10000]) for _ in range(rng.randrange(0, 6))]
        valid.append(chunked(rng, sizes, ext=k % 2 == 1, trailers=[b"x-sum: 1", b"y: two"] if k % 3 == 2 else []))
    for wire, content in valid:
        tail = b"GET /next HTTP/1.1\r\n\r\n"
        for piece in pieces:
            got, verdict = run(exe, "chunked", piece, wire + tail)
            want = "done consumed=%d content=%d" % (len(wire), len(content))
            # A piece may already hold bytes after the body; consumed stops at the end.
            if got != content or verdict != want:
                raise AssertionError(("chunked", piece, verdict, want, len(got), len(content)))
            cases += 1
    bad = {
        b"5\nhello\r\n0\r\n\r\n": "error malformed",
        b"5\r\nhello\n0\r\n\r\n": "error malformed",
        b"5\r\nhelloX\r\n0\r\n\r\n": "error malformed",
        b"g\r\n": "error malformed",
        b"\r\n": "error malformed",
        b";ext\r\n": "error malformed",
        b"5 \x01\r\n": "error malformed",
        b"0\r\nbad\x00field\r\n\r\n": "error malformed",
        b"0\r\nx: y\nz\r\n\r\n": "error malformed",
        b"1" * 70 + b"\r\n": "error limit",
        b"5;" + b"e" * 80 + b"\r\n": "error limit",
        b"fffffffffffff\r\n": "error limit",
        b"0\r\n" + b"x: " + b"y" * 300 + b"\r\n\r\n": "error limit",
    }
    for wire, want in bad.items():
        for piece in pieces:
            got, verdict = run(exe, "chunked", piece, wire)
            if verdict != want:
                raise AssertionError(("bad chunked", wire[:30], piece, verdict, want))
            cases += 1
    for wire in [b"5\r\nhel", b"5\r\nhello\r\n", b"5\r\nhello\r\n0\r\n"]:
        for piece in pieces:
            got, verdict = run(exe, "chunked", piece, wire)
            if not verdict.startswith("open "):
                raise AssertionError(("truncated chunked", wire, piece, verdict))
            cases += 1
    body = bytes(rng.randrange(256) for _ in range(20000))
    for piece in pieces:
        got, verdict = run(exe, "fixed:20000", piece, body + b"extra")
        if got != body or verdict != "done consumed=20000 content=20000":
            raise AssertionError(("fixed", piece, verdict))
        got, verdict = run(exe, "fixed:20000", piece, body[:12345])
        if got != body[:12345] or verdict != "open consumed=12345 content=12345":
            raise AssertionError(("fixed short", piece, verdict))
        got, verdict = run(exe, "close", piece, body)
        if got != body or verdict != "done consumed=20000 content=20000":
            raise AssertionError(("close", piece, verdict))
        cases += 3
    got, verdict = run(exe, "fixed:0", 7, b"next")
    if got != b"" or verdict != "done consumed=0 content=0":
        raise AssertionError(("fixed 0", verdict))
    cases += 1
    print("http-body cases=%d" % cases)

main()
