#!/usr/bin/env python3
"""HPACK oracle for tests/fixtures/extended/hpack/driver.lani (ext::hpack).

usage: oracle.py rfc|nghttp2|malformed|all DRIVER

rfc        RFC 7541 Appendix C: C.1 integers, C.2 field representations,
           C.3-C.6 request and response sequences decoded with their table
           states, and re-encoded byte for byte (C.3/C.5 raw, C.4/C.6 Huffman).
nghttp2    Differential runs against libnghttp2's HPACK deflater and inflater
           (the library curl uses), loaded with ctypes: seeded header-list
           sequences in both directions with table resizes, never-indexed
           fields and every Huffman symbol, comparing fields, flags and
           dynamic table sizes block by block.
malformed  Invalid blocks the decoder must reject, each also rejected by
           nghttp2 where the rule is shared; the Limit outcome keeps table state.
Prints: hpack-GROUP cases=N blocks=B
"""
import ctypes
import os
import random
import subprocess
import sys

EXE = None


class Failure(Exception):
    pass


def expect(ok, what):
    if not ok:
        raise Failure(repr(what)[:2000])


def hx(b):
    return b.hex() if b else "-"


def run(commands):
    r = subprocess.run([EXE], input=("\n".join(commands) + "\n").encode(), capture_output=True, timeout=120)
    expect(r.returncode == 0, ("driver exit", r.returncode, r.stderr[-400:]))
    return r.stdout.decode().splitlines()


def parse(lines):
    """Group driver output into per-command results."""
    out, cur = [], None
    for line in lines:
        if line.startswith("h "):
            _, n, v, never = line.split(" ")
            cur["fields"].append((b"" if n == "-" else bytes.fromhex(n), b"" if v == "-" else bytes.fromhex(v), never == "1"))
            continue
        cur = {"line": line, "fields": []}
        out.append(cur)
    return out


def table_of(line):
    w = line.split(" ")
    return {w[i]: int(w[i + 1]) for i in range(len(w)) if w[i] in ("size", "capacity", "entries")}


def H(s):
    return s.encode()


BLOCKS = {"count": 0}

# ---------------------------------------------------------------- rfc group
C3 = [("828684410f7777772e6578616d706c652e636f6d",
       [(":method", "GET"), (":scheme", "http"), (":path", "/"), (":authority", "www.example.com")], 57, 1),
      ("828684be58086e6f2d6361636865",
       [(":method", "GET"), (":scheme", "http"), (":path", "/"), (":authority", "www.example.com"), ("cache-control", "no-cache")], 110, 2),
      ("828785bf400a637573746f6d2d6b65790c637573746f6d2d76616c7565",
       [(":method", "GET"), (":scheme", "https"), (":path", "/index.html"), (":authority", "www.example.com"), ("custom-key", "custom-value")], 164, 3)]
C4 = ["828684418cf1e3c2e5f23a6ba0ab90f4ff", "828684be5886a8eb10649cbf",
      "828785bf408825a849e95ba97d7f8925a849e95bb8e8b4bf"]
R1 = [(":status", "302"), ("cache-control", "private"), ("date", "Mon, 21 Oct 2013 20:13:21 GMT"), ("location", "https://www.example.com")]
R2 = [(":status", "307"), ("cache-control", "private"), ("date", "Mon, 21 Oct 2013 20:13:21 GMT"), ("location", "https://www.example.com")]
R3 = [(":status", "200"), ("cache-control", "private"), ("date", "Mon, 21 Oct 2013 20:13:22 GMT"), ("location", "https://www.example.com"),
      ("content-encoding", "gzip"), ("set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1")]
C5 = [("4803333032580770726976617465611d4d6f6e2c203231204f637420323031332032303a31333a323120474d546e1768747470733a2f2f7777772e6578616d706c652e636f6d", R1, 222, 4),
      ("4803333037c1c0bf", R2, 222, 4),
      ("88c1611d4d6f6e2c203231204f637420323031332032303a31333a323220474d54c05a04677a69707738666f6f3d4153444a4b48514b425a584f5157454f50495541585157454f49553b206d61782d6167653d333630303b2076657273696f6e3d31", R3, 215, 3)]
C6 = ["488264025885aec3771a4b6196d07abe941054d444a8200595040b8166e082a62d1bff6e919d29ad171863c78f0b97c8e9ae82ae43d3",
      "4883640effc1c0bf",
      "88c16196d07abe941054d444a8200595040b8166e084a62d1bffc05a839bd9ab77ad94e7821dd7f2e6c7b335dfdfcd5b3960d5af27087f3672c1ab270fb5291f9587316065c003ed4ee5b1063d5007"]


def decode_sequence(table, blocks):
    cmds = ["dec %d 65536 1024 65536" % table]
    if table != 4096:
        cmds.append("max %d" % table)
    cmds += ["d " + b for b in blocks]
    res = parse(run(cmds))[1 + (table != 4096):]
    BLOCKS["count"] += len(blocks)
    return res


def check_decoded(res, expected):
    for r, (_, fields, size, entries) in zip(res, expected):
        expect(r["line"].startswith("ok %d " % len(fields)), r["line"])
        t = table_of(r["line"])
        expect(t["size"] == size and t["entries"] == entries, (r["line"], size, entries))
        expect([(n, v) for n, v, _ in r["fields"]] == [(H(n), H(v)) for n, v in fields], r["fields"])


def encode_fields(own, huff, sequence, auto):
    """Re-encode each field list; auto uses encode(), else encode_field(inc)."""
    cmds = ["enc %d" % own, "huff " + huff]
    for fields in sequence:
        for n, v in fields:
            cmds.append(("a %s %s 0" if auto else "f %s %s inc") % (hx(H(n)), hx(H(v))))
        cmds.append("e")
    res = [r["line"] for r in parse(run(cmds)) if r["line"].startswith("b ")]
    BLOCKS["count"] += len(sequence)
    return [r.split(" ")[1] for r in res], [table_of(r) for r in res]


def rfc_cases():
    out = []

    def case(fn):
        out.append(fn)
        return fn

    @case
    def c1_integers():
        lines = run(["int 5 10", "int 5 1337", "int 8 42", "dint 5 0a", "dint 5 1f9a0a", "dint 8 2a"])
        expect(lines == ["b 0a", "b 1f9a0a", "b 2a", "v 10 1", "v 1337 3", "v 42 1"], lines)

    @case
    def c2_field_representations():
        seq = [("400a637573746f6d2d6b65790d637573746f6d2d686561646572", ("custom-key", "custom-header", False), 55, 1),
               ("040c2f73616d706c652f70617468", (":path", "/sample/path", False), 0, 0),
               ("100870617373776f726406736563726574", ("password", "secret", True), 0, 0),
               ("82", (":method", "GET", False), 0, 0)]
        for block, (n, v, never), size, entries in seq:
            r = decode_sequence(4096, [block])[0]
            t = table_of(r["line"])
            expect(t["size"] == size and t["entries"] == entries and r["fields"] == [(H(n), H(v), never)], (block, r))
        # Re-encode with the matching representation of each example.
        lines = run(["enc 4096", "huff never", "f %s %s inc" % (hx(b"custom-key"), hx(b"custom-header")), "e",
                     "enc 4096", "huff never", "f %s %s without" % (hx(b":path"), hx(b"/sample/path")), "e",
                     "enc 4096", "huff never", "f %s %s never" % (hx(b"password"), hx(b"secret")), "e",
                     "enc 4096", "f %s %s inc" % (hx(b":method"), hx(b"GET")), "e"])
        blocks = [l.split(" ")[1] for l in lines if l.startswith("b ")]
        expect(blocks == [s[0] for s in seq], blocks)

    @case
    def c3_requests_without_huffman():
        check_decoded(decode_sequence(4096, [b for b, _, _, _ in C3]), C3)
        for auto in (False, True):
            blocks, tables = encode_fields(4096, "never", [f for _, f, _, _ in C3], auto)
            expect(blocks == [b for b, _, _, _ in C3], blocks)
            expect([t["size"] for t in tables] == [57, 110, 164], tables)

    @case
    def c4_requests_with_huffman():
        expected = [(b, f, s, e) for b, (_, f, s, e) in zip(C4, C3)]
        check_decoded(decode_sequence(4096, C4), expected)
        for huff in ("always", "shortest"):
            blocks, _ = encode_fields(4096, huff, [f for _, f, _, _ in C3], True)
            expect(blocks == C4, (huff, blocks))

    @case
    def c5_responses_without_huffman():
        check_decoded(decode_sequence(256, [b for b, _, _, _ in C5]), C5)
        blocks, tables = encode_fields(256, "never", [f for _, f, _, _ in C5], False)
        expect(blocks == [b for b, _, _, _ in C5], blocks)
        expect([(t["size"], t["entries"]) for t in tables] == [(222, 4), (222, 4), (215, 3)], tables)

    @case
    def c6_responses_with_huffman():
        expected = [(b, f, s, e) for b, (_, f, s, e) in zip(C6, C5)]
        check_decoded(decode_sequence(256, C6), expected)
        # The example codes every string; "307" is no shorter coded, so the
        # Shortest mode sends it raw there.
        blocks, _ = encode_fields(256, "always", [f for _, f, _, _ in C5], False)
        expect(blocks == C6, blocks)
        blocks, _ = encode_fields(256, "shortest", [f for _, f, _, _ in C5], False)
        expect(blocks == [C6[0], "4803333037c1c0bf", C6[2]], blocks)

    @case
    def c4_huffman_strings():
        lines = run(["hufe " + hx(b"www.example.com"), "hufd f1e3c2e5f23a6ba0ab90f4ff",
                     "hufe " + hx(b"no-cache"), "hufd a8eb10649cbf", "hufe -", "hufd -"])
        expect(lines == ["b f1e3c2e5f23a6ba0ab90f4ff", "b " + hx(b"www.example.com"), "b a8eb10649cbf", "b " + hx(b"no-cache"), "b -", "b -"], lines)

    @case
    def size_update_at_block_start():
        # An encoder capped below 4096 announces its size in the first block;
        # a lowered peer maximum announces the smallest size, then the final.
        lines = run(["enc 256", "a %s %s 0" % (hx(b":method"), hx(b"GET")), "e",
                     "enc 4096", "peer 100", "peer 4096", "a %s %s 0" % (hx(b":method"), hx(b"GET")), "e"])
        blocks = [l.split(" ")[1] for l in lines if l.startswith("b ")]
        expect(blocks == ["3fe10182", "3f45" + "3fe11f" + "82"], blocks)
        r = decode_sequence(4096, ["3fe10182", "3f453fe11f82"])
        expect(table_of(r[0]["line"])["capacity"] == 256 and table_of(r[1]["line"])["capacity"] == 4096, r)

    return out


# ---------------------------------------------------------------- nghttp2
class NV(ctypes.Structure):
    _fields_ = [("name", ctypes.c_void_p), ("value", ctypes.c_void_p), ("namelen", ctypes.c_size_t),
                ("valuelen", ctypes.c_size_t), ("flags", ctypes.c_uint8)]


NO_INDEX = 1


class Nghttp2:
    def __init__(self):
        self.lib = lib = ctypes.CDLL("libnghttp2.so.14")
        lib.nghttp2_hd_inflate_new.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
        lib.nghttp2_hd_deflate_new.argtypes = [ctypes.POINTER(ctypes.c_void_p), ctypes.c_size_t]
        lib.nghttp2_hd_inflate_hd2.argtypes = [ctypes.c_void_p, ctypes.POINTER(NV), ctypes.POINTER(ctypes.c_int), ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
        lib.nghttp2_hd_inflate_hd2.restype = ctypes.c_ssize_t
        lib.nghttp2_hd_inflate_end_headers.argtypes = [ctypes.c_void_p]
        lib.nghttp2_hd_deflate_hd.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.POINTER(NV), ctypes.c_size_t]
        lib.nghttp2_hd_deflate_hd.restype = ctypes.c_ssize_t
        lib.nghttp2_hd_deflate_bound.argtypes = [ctypes.c_void_p, ctypes.POINTER(NV), ctypes.c_size_t]
        lib.nghttp2_hd_deflate_bound.restype = ctypes.c_size_t
        for f in ("nghttp2_hd_inflate_change_table_size", "nghttp2_hd_deflate_change_table_size"):
            getattr(lib, f).argtypes = [ctypes.c_void_p, ctypes.c_size_t]
        for f in ("nghttp2_hd_inflate_get_dynamic_table_size", "nghttp2_hd_deflate_get_dynamic_table_size"):
            getattr(lib, f).argtypes = [ctypes.c_void_p]
            getattr(lib, f).restype = ctypes.c_size_t
        for f in ("nghttp2_hd_inflate_del", "nghttp2_hd_deflate_del"):
            getattr(lib, f).argtypes = [ctypes.c_void_p]

    def inflater(self):
        p = ctypes.c_void_p()
        expect(self.lib.nghttp2_hd_inflate_new(ctypes.byref(p)) == 0, "inflate_new")
        return p

    def deflater(self, size=4096):
        p = ctypes.c_void_p()
        expect(self.lib.nghttp2_hd_deflate_new(ctypes.byref(p), size) == 0, "deflate_new")
        return p

    def inflate(self, inf, block):
        """Fields of one block, or None when nghttp2 rejects it."""
        buf = ctypes.create_string_buffer(block, len(block) or 1)
        base, off, fields = ctypes.addressof(buf), 0, []
        while True:
            nv, flags = NV(), ctypes.c_int(0)
            rv = self.lib.nghttp2_hd_inflate_hd2(inf, ctypes.byref(nv), ctypes.byref(flags), base + off, len(block) - off, 1)
            if rv < 0:
                return None
            off += rv
            if flags.value & 2:
                fields.append((ctypes.string_at(nv.name, nv.namelen), ctypes.string_at(nv.value, nv.valuelen), bool(nv.flags & NO_INDEX)))
            if flags.value & 1:
                self.lib.nghttp2_hd_inflate_end_headers(inf)
                return fields
            if rv == 0 and not flags.value & 2 and off >= len(block):
                return None

    def deflate(self, dfl, fields):
        keep = [(ctypes.create_string_buffer(n, len(n) or 1), ctypes.create_string_buffer(v, len(v) or 1)) for n, v, _ in fields]
        arr = (NV * max(1, len(fields)))()
        for i, ((n, v, never), (nb, vb)) in enumerate(zip(fields, keep)):
            arr[i] = NV(ctypes.addressof(nb), ctypes.addressof(vb), len(n), len(v), NO_INDEX if never else 0)
        bound = self.lib.nghttp2_hd_deflate_bound(dfl, arr, len(fields))
        out = ctypes.create_string_buffer(bound + 16)
        rv = self.lib.nghttp2_hd_deflate_hd(dfl, out, bound + 16, arr, len(fields))
        expect(rv >= 0, ("deflate", rv))
        return out.raw[:rv]


NAMES = [b":method", b":path", b":authority", b":scheme", b":status", b"accept", b"accept-encoding", b"user-agent",
         b"content-type", b"content-length", b"cache-control", b"date", b"etag", b"server", b"set-cookie", b"cookie",
         b"authorization", b"x-request-id", b"x-trace", b"via", b"location"]


def random_fields(rng, pool):
    fields = []
    for _ in range(rng.randint(1, 14)):
        r = rng.random()
        if r < 0.55 and pool:
            n, v = rng.choice(pool)
        else:
            n = rng.choice(NAMES) if r < 0.85 else bytes(rng.choice(b"abcdefghijklmnopqrstuvwxyz-0123456789") for _ in range(rng.randint(1, 24)))
            kind = rng.random()
            if kind < 0.6:
                v = bytes(rng.choice(b"abcdefghijklmnopqrstuvwxyz0123456789/=;.-_ ") for _ in range(rng.randint(0, 40)))
            elif kind < 0.8:
                v = bytes(rng.randrange(256) for _ in range(rng.randint(0, 30)))
            elif kind < 0.9:
                v = bytes(rng.choice(b"abcdefgh") for _ in range(rng.randint(200, 5000)))  # larger than the table
            else:
                v = b""
            pool.append((n, v))
        fields.append((n, v, rng.random() < 0.08))
    return fields


def encoded_never(n, v, never):
    return never or n in (b"authorization", b"proxy-authorization") or (n == b"cookie" and len(v) < 20)


def nghttp2_cases():
    ng = Nghttp2()
    out = []

    def case(fn):
        out.append(fn)
        return fn

    @case
    def lanius_encoder_to_nghttp2_inflater():
        rng = random.Random(7541)
        for seq in range(40):
            inf, pool, cmds, lists, resizes = ng.inflater(), [], ["enc 4096", "huff " + ("shortest", "always", "never")[seq % 3]], [], {}
            for blk in range(25):
                if rng.random() < 0.12:
                    size = rng.choice([0, 64, 256, 1000, 4096])
                    cmds.append("peer %d" % size)
                    resizes[blk] = size
                fields = random_fields(rng, pool)
                lists.append(fields)
                cmds += ["a %s %s %d" % (hx(n), hx(v), never) for n, v, never in fields] + ["e"]
            blocks = [r["line"] for r in parse(run(cmds)) if r["line"].startswith("b ")]
            expect(len(blocks) == len(lists), len(blocks))
            for blk, (line, fields) in enumerate(zip(blocks, lists)):
                if blk in resizes:
                    expect(ng.lib.nghttp2_hd_inflate_change_table_size(inf, resizes[blk]) == 0, "change")
                w = line.split(" ")
                got = ng.inflate(inf, b"" if w[1] == "-" else bytes.fromhex(w[1]))
                want = [(n, v, encoded_never(n, v, never)) for n, v, never in fields]
                expect(got == want, (seq, blk, got, want))
                expect(ng.lib.nghttp2_hd_inflate_get_dynamic_table_size(inf) == table_of(line)["size"], (seq, blk, line))
                BLOCKS["count"] += 1
            ng.lib.nghttp2_hd_inflate_del(inf)

    @case
    def nghttp2_deflater_to_lanius_decoder():
        rng = random.Random(9113)
        for seq in range(40):
            dfl, pool, cmds, lists, sizes = ng.deflater(4096), [], ["dec 4096 1048576 4096 65536"], [], []
            for blk in range(25):
                if rng.random() < 0.12:
                    ng.lib.nghttp2_hd_deflate_change_table_size(dfl, rng.choice([0, 64, 256, 1000, 4096]))
                fields = random_fields(rng, pool)
                lists.append(fields)
                cmds.append("d " + hx(ng.deflate(dfl, fields)))
                sizes.append(ng.lib.nghttp2_hd_deflate_get_dynamic_table_size(dfl))
            res = parse(run(cmds))[1:]
            for blk, (r, fields, size) in enumerate(zip(res, lists, sizes)):
                expect(r["line"].startswith("ok %d " % len(fields)), (seq, blk, r["line"]))
                want = [(n, v, encoded_never(n, v, never)) for n, v, never in fields]
                expect(r["fields"] == want, (seq, blk, r["fields"], want))
                expect(table_of(r["line"])["size"] == size, (seq, blk, r["line"], size))
                BLOCKS["count"] += 1
            ng.lib.nghttp2_hd_deflate_del(dfl)

    @case
    def every_huffman_symbol_both_ways():
        # 40 short-code bytes make Huffman shorter, so nghttp2 codes each symbol.
        dfl, inf = ng.deflater(0), ng.inflater()
        values = [b"a" * 40 + bytes([s]) + b"e" * 9 for s in range(256)]
        cmds = ["dec 4096 1048576 4096 65536"] + ["d " + hx(ng.deflate(dfl, [(b"x-sym", v, False)])) for v in values]
        res = parse(run(cmds))[1:]
        expect(all(r["fields"] == [(b"x-sym", v, False)] for r, v in zip(res, values)), [r["line"] for r in res][:5])
        # Every byte string Huffman-coded by the Lanius encoder decodes in nghttp2.
        cmds = ["enc 0", "huff always"] + sum([["a %s %s 0" % (hx(b"x-all"), hx(bytes([s, 255 - s, (s * 7) & 255]) * 3)), "e"] for s in range(256)], [])
        blocks = [r["line"].split(" ")[1] for r in parse(run(cmds)) if r["line"].startswith("b ")]
        for s, b in zip(range(256), blocks):
            got = ng.inflate(inf, bytes.fromhex(b))
            expect(got == [(b"x-all", bytes([s, 255 - s, (s * 7) & 255]) * 3, False)], (s, b, got))
        BLOCKS["count"] += 512

    return out


# ---------------------------------------------------------------- malformed
BAD = [
    ("index_zero", "80", "index", True),
    ("index_past_table", "be", "index", True),
    ("truncated_integer", "ff", "truncated", True),
    ("integer_overflow", "ffffffffff0f", "integer", True),
    ("string_past_block", "000a6162", "truncated", True),
    ("huffman_eos", "0084ffffffff0161", "huffman", True),
    ("huffman_long_padding", "00821fff0161", "huffman", True),
    ("huffman_zero_padding", "0081180161", "huffman", True),
    ("size_update_above_maximum", "3fe21f", "table-size", True),
    ("size_update_after_field", "8220", "size-update", True),
    ("literal_name_index_past_table", "7f0001", "index", True),
    ("missing_value", "0003616263", "truncated", True),
]


def malformed_cases():
    ng = Nghttp2()
    out = []

    def case(fn):
        out.append(fn)
        return fn

    for name, block, error, shared in BAD:
        def make(block=block, error=error, shared=shared):
            def fn():
                res = parse(run(["dec 4096 65536 1024 65536", "d " + block, "d 82"]))
                expect(res[1]["line"] == "err " + error and res[1]["fields"] == [], (block, res[1]))
                expect(res[2]["line"] == "err failed", res[2])  # a compression error is final
                if shared:
                    expect(ng.inflate(ng.inflater(), bytes.fromhex(block)) is None, ("nghttp2 accepted", block))
                BLOCKS["count"] += 2
            fn.__name__ = name
            return fn
        out.append(make())

    @case
    def string_above_limit_is_final():
        res = parse(run(["dec 4096 65536 1024 8", "d 400a637573746f6d2d6b65790d637573746f6d2d686561646572", "d 82"]))
        expect(res[1]["line"] == "err too-long" and res[2]["line"] == "err failed", res)

    @case
    def list_limit_keeps_table_in_step():
        # Two indexed literals (55 + 64 bytes) exceed a 100-byte list: Limit,
        # the first field kept, both entries added; later references resolve.
        b1 = "400a637573746f6d2d6b65790d637573746f6d2d686561646572" + "40" + "0b" + b"x-second-ky".hex() + "15" + b"a-much-longer-value-1".hex()
        res = parse(run(["dec 4096 100 1024 65536", "d " + b1, "d bf", "d be"]))
        expect(res[1]["line"].startswith("err limit") or res[1]["line"] == "err limit", res[1])
        expect(res[1]["fields"] == [(b"custom-key", b"custom-header", False)], res[1])
        expect(res[2]["fields"] == [(b"custom-key", b"custom-header", False)], res[2])
        expect(res[3]["fields"] == [(b"x-second-ky", b"a-much-longer-value-1", False)], res[3])

    @case
    def field_count_limit():
        res = parse(run(["dec 4096 65536 2 65536", "d 828684", "d 82"]))
        expect(res[1]["line"] == "err limit" and len(res[1]["fields"]) == 2 and res[2]["line"].startswith("ok 1 "), res)

    @case
    def oversized_entry_empties_table():
        # A 4097-byte entry cannot fit: the table empties (RFC 7541 4.4).
        big = "40" + "01" + "61" + "7f" + "e11e" + "62" * 4064
        res = parse(run(["dec 4096 1048576 1024 65536", "d 400a637573746f6d2d6b65790d637573746f6d2d686561646572", "d " + big, "d be"]))
        expect(table_of(res[1]["line"])["entries"] == 1, res[1])
        expect(table_of(res[2]["line"])["entries"] == 0 and table_of(res[2]["line"])["size"] == 0, res[2])
        expect(res[3]["line"] == "err index", res[3])

    @case
    def mutated_blocks_agree_with_nghttp2():
        # Single-byte mutations of valid blocks: whenever both decoders accept,
        # they produce the same fields.
        rng, dfl = random.Random(1), ng.deflater(4096)
        pool, base = [], []
        for _ in range(30):
            base.append(ng.deflate(ng.deflater(4096), random_fields(rng, pool)))
        both = 0
        cmds, blocks = [], []
        for _ in range(600):
            b = bytearray(rng.choice(base))
            if b:
                b[rng.randrange(len(b))] = rng.randrange(256)
            blocks.append(bytes(b))
            cmds += ["dec 4096 1048576 4096 65536", "d " + hx(bytes(b))]
        res = parse(run(cmds))[1::2]
        for b, r in zip(blocks, res):
            theirs = ng.inflate(ng.inflater(), b)
            if theirs is not None and r["line"].startswith("ok"):
                expect([f[:2] for f in r["fields"]] == [f[:2] for f in theirs], (b.hex(), r, theirs))
                both += 1
        expect(both > 100, both)
        BLOCKS["count"] += 600

    return out


def main():
    global EXE
    if len(sys.argv) != 3 or sys.argv[1] not in ("rfc", "nghttp2", "malformed", "all"):
        print(__doc__, file=sys.stderr)
        return 2
    EXE = os.path.abspath(sys.argv[2])
    groups = {"rfc": rfc_cases, "nghttp2": nghttp2_cases, "malformed": malformed_cases}
    for group in (list(groups) if sys.argv[1] == "all" else [sys.argv[1]]):
        BLOCKS["count"] = 0
        todo = groups[group]()
        for fn in todo:
            try:
                fn()
            except Failure as e:
                print("FAIL %s/%s: %s" % (group, fn.__name__, e), file=sys.stderr)
                return 1
        print("hpack-%s cases=%d blocks=%d" % (group, len(todo), BLOCKS["count"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
