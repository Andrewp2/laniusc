"""ext::ws_deflate against Python's zlib (RFC 7692 7.2): compress and
inflate interop with and without context takeover, sync-flushed and BFINAL
peer messages, corrupt and oversized input, offer negotiation and response
parsing. Usage: deflate_oracle.py DRIVER. Prints one summary line."""
import os
import random
import struct
import subprocess
import sys
import zlib

EXE = sys.argv[1]
TAIL = b"\x00\x00\xff\xff"


def records(items):
    return b"".join(struct.pack(">I", len(x)) + x for x in items)


def unrecords(data):
    out, at = [], 0
    while at < len(data):
        n = struct.unpack(">I", data[at:at + 4])[0]
        out.append(data[at + 4:at + 4 + n])
        at += 4 + n
    return out


def run(args, data):
    p = subprocess.run([EXE] + args, input=data, capture_output=True, timeout=60)
    if p.returncode != 0 or p.stderr:
        raise AssertionError(("exit", args, p.returncode, p.stderr[:200]))
    return p.stdout


def check(ok, what):
    if not ok:
        raise AssertionError(what)


def corpus():
    rnd = random.Random(5)
    text = b"The quick brown fox jumps over the lazy dog. " * 300
    return [b"", b"a", b"Hello", text, os.urandom(70000), bytes(rnd.randrange(4) for _ in range(100000)), text[:40000] + os.urandom(3000) + text[:40000], "é中\U0001f600".encode() * 500]


def main():
    cases = 0
    msgs = corpus()
    # Our compressed messages inflate with zlib after appending the tail.
    # Without context takeover each is independent (a fresh decompressobj
    # per message).
    out = unrecords(run(["c", "s", "reset"], records(msgs + msgs)))
    for m, c in zip(msgs + msgs, out):
        d = zlib.decompressobj(-15)
        check(d.decompress(c + TAIL) == m, ("compress", len(m)))
    check(len(out[3]) < len(msgs[3]) // 10, ("ratio", len(out[3])))
    check(out[:len(msgs)] == out[len(msgs):], "reset: equal messages compress equally")
    cases += 1
    # With context takeover one decompressobj inflates the whole sequence,
    # and a repeated message refers back into the previous one. Sizes past
    # the 64 KiB window exercise the encoder's window slide after a flush.
    rnd = random.Random(7)
    seq = [os.urandom(1000), None, os.urandom(20000), None, b"x", None, os.urandom(70001), None, b"", None,
           bytes(rnd.randrange(16) for _ in range(150000)), None, "é中\U0001f600".encode() * 9000, None]
    seq = [seq[i - 1] if m is None else m for i, m in enumerate(seq)]
    for role in ("s", "c"):
        out = unrecords(run(["c", role], records(seq)))
        d = zlib.decompressobj(-15)
        for i, (m, c) in enumerate(zip(seq, out)):
            check(d.decompress(c + TAIL) == m, ("takeover", role, i, len(m)))
        check(len(out[1]) < 40 and len(out[3]) < len(seq[3]) // 50, ("history used", role, [len(c) for c in out]))
    cases += 1
    # A limited window (max_window_bits 8..15): a zlib inflater with that
    # window accepts everything, so no match reaches farther back.
    near = [os.urandom(200), None, os.urandom(1500), None, bytes(rnd.randrange(8) for _ in range(40000)), None]
    near = [near[i - 1] if m is None else m for i, m in enumerate(near)]
    for bits in (8, 9, 10, 12, 15):
        for role in ("s", "c"):
            out = unrecords(run(["c", role, "takeover", str(bits)], records(near)))
            d = zlib.decompressobj(-bits)
            for i, (m, c) in enumerate(zip(near, out)):
                check(d.decompress(c + TAIL) == m, ("window", bits, role, i))
            # 200 bytes back is inside every window; 1500 only from 11 bits.
            check(len(out[1]) < 30 and (len(out[3]) < 60) == (bits >= 11), ("window reach", bits, role, [len(c) for c in out]))
    cases += 1
    # zlib with context takeover and sync flush: one compressor across
    # messages, references into earlier messages.
    z = zlib.compressobj(6, zlib.DEFLATED, -15)
    sent = []
    for m in msgs + msgs:
        c = z.compress(m) + z.flush(zlib.Z_SYNC_FLUSH)
        check(c.endswith(TAIL), "sync tail")
        sent.append(c[:-4])
    back = unrecords(run(["d", "s"], records(sent)))
    check(back == msgs + msgs, ("context takeover", [len(b) for b in back]))
    cases += 1
    # No context takeover: a fresh compressor per message, with reset flag.
    sent = []
    for m in msgs:
        z = zlib.compressobj(9, zlib.DEFLATED, -9)
        sent.append((z.compress(m) + z.flush(zlib.Z_SYNC_FLUSH))[:-4])
    check(unrecords(run(["d", "s", "reset"], records(sent))) == msgs, "no context takeover, 9-bit window")
    cases += 1
    # BFINAL peer messages (Z_FINISH): each a complete stream.
    sent = []
    for m in msgs:
        z = zlib.compressobj(1, zlib.DEFLATED, -15)
        sent.append(z.compress(m) + z.flush(zlib.Z_FINISH))
    check(unrecords(run(["d", "c"], records(sent))) == msgs, "BFINAL messages")
    cases += 1
    # Corrupt and oversized: an error, then the codec still serves a fresh
    # stream message (BFINAL).
    z = zlib.compressobj(6, zlib.DEFLATED, -15)
    big = z.compress(b"x" * 2000000) + z.flush(zlib.Z_FINISH)
    z = zlib.compressobj(6, zlib.DEFLATED, -15)
    ok = z.compress(b"after") + z.flush(zlib.Z_FINISH)
    got = unrecords(run(["d", "s", "reset"], records([b"\xff\xff\xff", ok, big, ok])))
    check(got == [b"error", b"after", b"error", b"after"], ("errors", got))
    cases += 1
    # Server negotiation.
    def offer(*values):
        head = b"GET / HTTP/1.1\r\nHost: x\r\n" + b"".join(b"Sec-WebSocket-Extensions: " + v + b"\r\n" for v in values) + b"\r\n"
        return run(["n"], head).strip()
    # The server keeps context takeover unless asked, and honors the
    # client's server_max_window_bits.
    check(offer(b"permessage-deflate") == b"permessage-deflate", "plain offer")
    check(offer(b"permessage-deflate; client_max_window_bits; client_no_context_takeover") == b"permessage-deflate; client_no_context_takeover", "client params")
    check(offer(b"permessage-deflate; server_max_window_bits=10, permessage-deflate") == b"permessage-deflate; server_max_window_bits=10", "window bits")
    check(offer(b"permessage-deflate; server_max_window_bits=8; server_no_context_takeover") == b"permessage-deflate; server_no_context_takeover; server_max_window_bits=8", "8 bits, reset")
    check(offer(b"x-other, permessage-deflate; server_no_context_takeover") == b"permessage-deflate; server_no_context_takeover", "after unknown extension")
    check(offer(b"permessage-deflate; server_max_window_bits=\"15\"") == b"permessage-deflate", "quoted bits")
    check(offer(b"permessage-deflate; bogus, permessage-deflate; client_no_context_takeover") == b"permessage-deflate; client_no_context_takeover", "fallback offer")
    for bad in [b"permessage-deflate; bogus", b"permessage-deflate; server_no_context_takeover; server_no_context_takeover", b"permessage-deflate; client_max_window_bits=7",
                b"permessage-deflate; server_max_window_bits", b"permessage-deflate; server_no_context_takeover=1", b"permessage-deflate; server_max_window_bits=16"]:
        check(offer(bad) == b"-", ("bad offer", bad))
    check(offer() == b"-", "no offer")
    cases += 1
    # Client: the server's response value.
    values = [b"permessage-deflate", b"permessage-deflate; server_no_context_takeover; client_no_context_takeover",
              b"permessage-deflate; client_max_window_bits=10; server_max_window_bits=12", b"permessage-deflate; client_max_window_bits",
              b"permessage-deflate, permessage-deflate", b"x-other", b"permessage-deflate; foo=1"]
    want = [b"0 0 15 15", b"1 1 15 15", b"0 0 12 10", b"error", b"error", b"error", b"error"]
    got = unrecords(run(["a"], records(values)))
    check(got == want, ("accepted", got))
    cases += 1
    print("ws-deflate cases=%d" % cases)


main()
