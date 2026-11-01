"""Oracle for ext::msgpack and sample_programs/msgpack_json.lani.

Two independent references: the installed `msgpack` 1.0 package (acceptance,
values, packb bytes, Unpacker streaming) and a Python MessagePack model in
this file (shortest encoder, a decoder that mirrors the documented error
order and offsets, canonical rules). The format table below is typed in by
hand from the MessagePack specification.

usage: oracle.py GROUP BATCH MSGPACK_JSON
GROUP: spec, generated, mutations, limits, sequences, json
"""
import base64
import json
import math
import random
import struct
import subprocess
import sys

import msgpack


def Ext(code, data):
    """Ext values as msgpack-python's ext_hook reports them (any code, incl. reserved negatives)."""
    return ('ext', code, data)

sys.setrecursionlimit(20000)

# (encoding, expected msgpack-python value), one row per format family.
SPEC = [
    ('00', 0), ('7f', 127), ('e0', -32), ('ff', -1),
    ('cc80', 128), ('ccff', 255), ('cd0100', 256), ('cdffff', 65535), ('ce00010000', 65536),
    ('ceffffffff', 4294967295), ('cf0000000100000000', 4294967296), ('cfffffffffffffffff', 18446744073709551615),
    ('d0df', -33), ('d080', -128), ('d1ff7f', -129), ('d18000', -32768), ('d2ffff7fff', -32769),
    ('d280000000', -2147483648), ('d3ffffffff7fffffff', -2147483649), ('d38000000000000000', -9223372036854775808),
    ('c0', None), ('c2', False), ('c3', True),
    ('ca3fc00000', 1.5), ('cb3ff8000000000000', 1.5), ('ca7f800000', math.inf), ('cbfff0000000000000', -math.inf),
    ('cb8000000000000000', -0.0), ('cb0000000000000001', 5e-324),
    ('a0', ''), ('a161', 'a'), ('a3e6b0b4', '水'), ('a4f0908591', '\U00010151'),
    ('bf' + '61' * 31, 'a' * 31), ('d920' + '61' * 32, 'a' * 32), ('da0100' + '61' * 256, 'a' * 256),
    ('c400', b''), ('c403010203', b'\x01\x02\x03'), ('c50100' + '00' * 256, b'\x00' * 256),
    ('90', []), ('9101', [1]), ('9f' + '00' * 15, [0] * 15), ('dc0010' + '00' * 16, [0] * 16),
    ('80', []), ('81a161c0', [('a', None)]), ('820102a162c2', [(1, 2), ('b', False)]),
    ('8f' + ''.join('%02x00' % i for i in range(15)), [(i, 0) for i in range(15)]),
    ('de0010' + ''.join('%02x00' % i for i in range(16)), [(i, 0) for i in range(16)]),
    ('819101c0', [([1], None)]),
    ('d40501', Ext(5, b'\x01')), ('d5050102', Ext(5, b'\x01\x02')),
    ('d605' + '00' * 4, Ext(5, b'\x00' * 4)), ('d705' + '00' * 8, Ext(5, b'\x00' * 8)),
    ('d805' + '00' * 16, Ext(5, b'\x00' * 16)), ('c70005', Ext(5, b'')),
    ('c70305616263', Ext(5, b'abc')), ('c8010080' + '00' * 256, Ext(-128, b'\x00' * 256)),
    ('d6ff00000001', msgpack.Timestamp(1, 0)), ('d7ff0000001400000001', msgpack.Timestamp(1, 5)),
    ('c70cff000000000000000400000000', msgpack.Timestamp(2 ** 34, 0)),
    ('c70cff3b9ac9fffffffffffffffffb', msgpack.Timestamp(-5, 999999999)),
]
# Invalid encodings with their expected error at the head offset.
SPEC_ERRORS = [
    ('c1', 'InvalidByte 0'), ('', 'UnexpectedEnd 0'), ('cc', 'UnexpectedEnd 0'), ('a2', 'UnexpectedEnd 0'),
    ('92c0', 'UnexpectedEnd 2'), ('0000', 'TrailingData 1'), ('a1ff', 'InvalidUtf8 0'), ('a2eda080', 'InvalidUtf8 0'),
    ('d6ff000000', 'UnexpectedEnd 0'), ('d4ff00', 'InvalidTimestamp 0'), ('c703ff000000', 'InvalidTimestamp 0'),
    ('d7ff' + 'ffffffff00000000', 'InvalidTimestamp 0'), ('c70cff3b9aca00' + '00' * 8, 'InvalidTimestamp 0'),
    ('9191c1', 'InvalidByte 2'), ('81a1', 'UnexpectedEnd 1'),
]


# ---------------------------------------------------------------- model
# ('nil',) ('bool', b) ('u', n) ('i', n) ('f32', bits) ('f64', bits) ('str', s)
# ('bin', b) ('ext', type, data) ('arr', items) ('map', pairs)
def be(value, width):
    return (value % (1 << (8 * width))).to_bytes(width, 'big')


def enc_int(n):
    if n >= 0:
        if n < 128:
            return bytes([n])
        for code, w in ((0xcc, 1), (0xcd, 2), (0xce, 4), (0xcf, 8)):
            if n < 1 << (8 * w):
                return bytes([code]) + be(n, w)
    if n >= -32:
        return bytes([n + 256])
    for code, w in ((0xd0, 1), (0xd1, 2), (0xd2, 4), (0xd3, 8)):
        if n >= -(1 << (8 * w - 1)):
            return bytes([code]) + be(n, w)
    raise ValueError(n)


def enc_len(kind, n):
    if kind == 'str' and n < 32:
        return bytes([0xa0 + n])
    if kind in ('arr', 'map') and n < 16:
        return bytes([(0x90 if kind == 'arr' else 0x80) + n])
    codes = {'str': (0xd9, 0xda, 0xdb), 'bin': (0xc4, 0xc5, 0xc6), 'arr': (None, 0xdc, 0xdd), 'map': (None, 0xde, 0xdf)}[kind]
    if n < 256 and codes[0]:
        return bytes([codes[0], n])
    if n < 65536:
        return bytes([codes[1]]) + be(n, 2)
    return bytes([codes[2]]) + be(n, 4)


def enc_ext(t, data):
    fixed = {1: 0xd4, 2: 0xd5, 4: 0xd6, 8: 0xd7, 16: 0xd8}
    if len(data) in fixed:
        return bytes([fixed[len(data)], t % 256]) + data
    if len(data) < 256:
        return bytes([0xc7, len(data), t % 256]) + data
    if len(data) < 65536:
        return b'\xc8' + be(len(data), 2) + bytes([t % 256]) + data
    return b'\xc9' + be(len(data), 4) + bytes([t % 256]) + data


def encode(m, widen=None):
    """Shortest encoding; widen(kind) may pick a longer legal header."""
    k = m[0]
    if widen:
        alt = widen(m)
        if alt is not None:
            return alt
    if k == 'nil':
        return b'\xc0'
    if k == 'bool':
        return b'\xc3' if m[1] else b'\xc2'
    if k in ('u', 'i'):
        return enc_int(m[1])
    if k == 'f32':
        return b'\xca' + be(m[1], 4)
    if k == 'f64':
        return b'\xcb' + be(m[1], 8)
    if k == 'str':
        data = m[1].encode()
        return enc_len('str', len(data)) + data
    if k == 'bin':
        return enc_len('bin', len(m[1])) + m[1]
    if k == 'ext':
        return enc_ext(m[1], m[2])
    if k == 'arr':
        return enc_len('arr', len(m[1])) + b''.join(encode(x, widen) for x in m[1])
    return enc_len('map', len(m[1])) + b''.join(encode(a, widen) + encode(b, widen) for a, b in m[1])


def widen_header(rng, m):
    """A non-canonical but valid encoding of m's own header, or None."""
    k = m[0]
    if k in ('u', 'i'):
        n = m[1]
        options = []
        for code, w, signed in ((0xcc, 1, 0), (0xcd, 2, 0), (0xce, 4, 0), (0xcf, 8, 0), (0xd0, 1, 1), (0xd1, 2, 1), (0xd2, 4, 1), (0xd3, 8, 1)):
            lo, hi = (-(1 << (8 * w - 1)), (1 << (8 * w - 1)) - 1) if signed else (0, (1 << (8 * w)) - 1)
            if lo <= n <= hi:
                options.append(bytes([code]) + be(n, w))
        options = [o for o in options if o != enc_int(n)]
        return rng.choice(options) if options else None
    if k == 'str':
        data = m[1].encode()
        options = [code + data for code in (b'\xd9' + be(len(data), 1) if len(data) < 256 else None, b'\xda' + be(len(data), 2) if len(data) < 65536 else None, b'\xdb' + be(len(data), 4)) if code]
        options = [o for o in options if o != encode(m)]
        return rng.choice(options) if options else None
    if k == 'bin':
        options = [c + m[1] for c in (b'\xc5' + be(len(m[1]), 2), b'\xc6' + be(len(m[1]), 4))]
        return rng.choice(options)
    if k == 'ext':
        t = bytes([m[1] % 256])
        return rng.choice([b'\xc7' + be(len(m[2]), 1) + t + m[2] if len(m[2]) < 256 else b'\xc9' + be(len(m[2]), 4) + t + m[2],
                           b'\xc8' + be(len(m[2]), 2) + t + m[2]])
    return None


class CErr(Exception):
    def __init__(self, kind, offset):
        super().__init__(kind, offset)
        self.kind, self.offset = kind, offset


def utf8(data):
    try:
        return data.decode('utf-8', 'strict')
    except UnicodeDecodeError:
        return None


def timestamp_ok(data):
    if len(data) == 4:
        return True
    if len(data) == 8:
        return int.from_bytes(data, 'big') >> 34 <= 999999999
    if len(data) == 12:
        return int.from_bytes(data[:4], 'big') <= 999999999
    return False


EXTRA = {}
for b in range(256):
    EXTRA[b] = 0
for b, n in ((0xc4, 1), (0xcc, 1), (0xd0, 1), (0xd9, 1), (0xc5, 2), (0xcd, 2), (0xd1, 2), (0xda, 2), (0xdc, 2), (0xde, 2),
             (0xc6, 4), (0xca, 4), (0xce, 4), (0xd2, 4), (0xdb, 4), (0xdd, 4), (0xdf, 4), (0xcb, 8), (0xcf, 8), (0xd3, 8),
             (0xc7, 2), (0xc8, 3), (0xc9, 5), (0xd4, 1), (0xd5, 1), (0xd6, 1), (0xd7, 1), (0xd8, 1)):
    EXTRA[b] = n


class Decoder:
    """json: ext values and non-str/int keys fail at their head, as the sample does."""
    def __init__(self, data, canonical=False, max_depth=128, max_items=1000000, max_string=16777216, json_mode=False):
        self.data, self.canonical = data, canonical
        self.max_depth, self.max_items, self.max_string = max_depth, max_items, max_string
        self.json_mode = json_mode
        self.pos = self.items = 0

    def one(self):
        m = self.item(0)
        if self.pos != len(self.data):
            raise CErr('TrailingData', self.pos)
        return m

    def sequence(self):
        roots = []
        while self.pos < len(self.data):
            roots.append(self.item(0))
        return roots

    def item(self, depth, key=False):
        d, at = self.data, self.pos
        if at >= len(d):
            raise CErr('UnexpectedEnd', at)
        b = d[at]
        if b == 0xc1:
            raise CErr('InvalidByte', at)
        extra = EXTRA[b]
        if at + 1 + extra > len(d):
            raise CErr('UnexpectedEnd', at)
        h = d[at + 1:at + 1 + extra]
        canonical, cls, length, node = True, 'scalar', 0, None
        if 0x80 <= b <= 0x8f:
            cls, length = 'map', b - 0x80
        elif 0x90 <= b <= 0x9f:
            cls, length = 'arr', b - 0x90
        elif 0xa0 <= b <= 0xbf:
            cls, length = 'str', b - 0xa0
        elif b in (0xd9, 0xda, 0xdb):
            cls, length = 'str', int.from_bytes(h, 'big')
            canonical = {0xd9: length >= 32, 0xda: length > 255, 0xdb: length > 65535}[b]
        elif b in (0xc4, 0xc5, 0xc6):
            cls, length = 'bin', int.from_bytes(h, 'big')
            canonical = {0xc4: True, 0xc5: length > 255, 0xc6: length > 65535}[b]
        elif b in (0xdc, 0xdd):
            cls, length = 'arr', int.from_bytes(h, 'big')
            canonical = length >= 16 if b == 0xdc else length > 65535
        elif b in (0xde, 0xdf):
            cls, length = 'map', int.from_bytes(h, 'big')
            canonical = length >= 16 if b == 0xde else length > 65535
        elif 0xd4 <= b <= 0xd8:
            cls, length, etype = 'ext', 1 << (b - 0xd4), h[0]
        elif b in (0xc7, 0xc8, 0xc9):
            cls, length, etype = 'ext', int.from_bytes(h[:-1], 'big'), h[-1]
            canonical = {0xc7: length not in (1, 2, 4, 8, 16), 0xc8: length > 255, 0xc9: length > 65535}[b]
        elif b <= 0x7f:
            node = ('u', b)
        elif b >= 0xe0:
            node = ('i', b - 256)
        elif b == 0xc0:
            node = ('nil',)
        elif b in (0xc2, 0xc3):
            node = ('bool', b == 0xc3)
        elif b == 0xca:
            node = ('f32', int.from_bytes(h, 'big'))
        elif b == 0xcb:
            node = ('f64', int.from_bytes(h, 'big'))
        elif 0xcc <= b <= 0xcf:
            v = int.from_bytes(h, 'big')
            canonical = v >= {0xcc: 128, 0xcd: 256, 0xce: 65536, 0xcf: 1 << 32}[b]
            node = ('u', v)
        elif 0xd0 <= b <= 0xd3:
            v = int.from_bytes(h, 'big', signed=True)
            canonical = v < {0xd0: -32, 0xd1: -128, 0xd2: -32768, 0xd3: -(1 << 31)}[b]
            node = ('i', v)
        if self.canonical and not canonical:
            raise CErr('NotCanonical', at)
        start = at + 1 + extra
        if cls in ('str', 'bin', 'ext'):
            if length > self.max_string:
                raise CErr('StringLimit', at)
            if start + length > len(d):
                raise CErr('UnexpectedEnd', at)
        if self.items >= self.max_items:
            raise CErr('ItemLimit', at)
        payload = d[start:start + length] if cls in ('str', 'bin', 'ext') else b''
        if cls == 'str' and utf8(payload) is None:
            raise CErr('InvalidUtf8', at)
        if cls == 'ext' and etype == 255 and not timestamp_ok(payload):
            raise CErr('InvalidTimestamp', at)
        if cls in ('arr', 'map') and depth >= self.max_depth:
            raise CErr('DepthLimit', at)
        self.items += 1
        if self.json_mode:
            if cls == 'ext':
                raise CErr('UnsupportedExt', at)
            if key and not (cls == 'str' or (node is not None and node[0] in ('u', 'i'))):
                raise CErr('UnsupportedKey', at)
        self.pos = start + len(payload)
        if cls == 'str':
            return ('str', payload.decode())
        if cls == 'bin':
            return ('bin', bytes(payload))
        if cls == 'ext':
            return ('ext', etype - 256 if etype >= 128 else etype, bytes(payload))
        if cls == 'arr':
            return ('arr', [self.item(depth + 1) for _ in range(length)])
        if cls == 'map':
            pairs = []
            for _ in range(length):
                k = self.item(depth + 1, key=True)
                pairs.append((k, self.item(depth + 1)))
            return ('map', pairs)
        return node


def outcome(data, **options):
    try:
        return 'ok', Decoder(data, **options).one()
    except CErr as e:
        return 'error %s %d' % (e.kind, e.offset), None


def reference(data):
    """msgpack-python acceptance and value."""
    try:
        return True, msgpack.unpackb(data, raw=False, strict_map_key=False, object_pairs_hook=list, timestamp=0, ext_hook=Ext)
    except Exception:
        return False, None


def py_value(m, pack=False):
    """The msgpack-python value of a model node (pack: ExtType for packb)."""
    k = m[0]
    if k == 'nil':
        return None
    if k in ('bool', 'u', 'i', 'str', 'bin'):
        return m[1]
    if k == 'f32':
        return struct.unpack('>f', be(m[1], 4))[0]
    if k == 'f64':
        return struct.unpack('>d', be(m[1], 8))[0]
    if k == 'ext':
        if m[1] == -1 and timestamp_ok(m[2]):
            return msgpack.Timestamp.from_bytes(m[2])
        return msgpack.ExtType(m[1], m[2]) if pack else Ext(m[1], m[2])
    if k == 'arr':
        return [py_value(x, pack) for x in m[1]]
    return [(py_value(a, pack), py_value(b, pack)) for a, b in m[1]]


def same(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, float):
        if math.isnan(a):
            return math.isnan(b)
        return a == b and math.copysign(1, a) == math.copysign(1, b)
    if isinstance(a, (list, tuple)):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    return a == b


# ---------------------------------------------------------------- generation
ALPHABET = ['a', 'z', ' ', '"', '\\', '\x00', '\n', 'é', '水', '€', '\U00010151', '\U0001f600']


def rand_int(rng):
    r = rng.random()
    if r < 0.5:
        return rng.choice([rng.randrange(-40, 140), rng.randrange(-200, 300)])
    return rng.choice([rng.randrange(-2 ** 15, 2 ** 16), rng.randrange(-2 ** 31, 2 ** 32), rng.randrange(-2 ** 63, 2 ** 64),
                       2 ** 64 - 1, -2 ** 63, 2 ** 32, -2 ** 31 - 1, 65535, -32769])


def gen(rng, depth=0, max_depth=5, plain_keys=False):
    r = rng.random()
    if depth >= max_depth:
        r *= 0.55
    if r < 0.2:
        n = rand_int(rng)
        return ('u', n) if n >= 0 else ('i', n)
    if r < 0.25:
        return rng.choice([('nil',), ('bool', True), ('bool', False)])
    if r < 0.33:
        if rng.random() < 0.5:
            return ('f32', rng.choice([rng.randrange(2 ** 32), 0x7fc00000, 0x7f800001, 0x80000000, 0x00000001]))
        return ('f64', rng.choice([rng.randrange(2 ** 64), 0x7ff8000000000000, 0x8000000000000000,
                                   struct.unpack('>Q', struct.pack('>d', rng.uniform(-1e6, 1e6)))[0]]))
    if r < 0.45:
        return ('str', ''.join(rng.choice(ALPHABET) for _ in range(rng.choice([0, 1, 5, 31, 32, 40, 300]))))
    if r < 0.5:
        return ('bin', bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 3, 255, 256, 300]))))
    if r < 0.57:
        if rng.random() < 0.4:
            seconds = rng.choice([0, 1, 2 ** 32 - 1, 2 ** 32, 2 ** 34 - 1, 2 ** 34, -1, -2 ** 63, 2 ** 63 - 1])
            nanos = rng.choice([0, 0, 1, 999999999])
            return ('ext', -1, msgpack.Timestamp(seconds, nanos).to_bytes())
        return ('ext', rng.choice([c for c in range(-128, 128) if c != -1]) if rng.random() < 0.7 else rng.randrange(0, 128),
                bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 2, 3, 4, 8, 16, 17, 300]))))
    if r < 0.75:
        sizes = [0, 1, 2, 3, 15, 16, 20] if depth < 2 else [0, 1, 2, 3]
        return ('arr', [gen(rng, depth + 1, max_depth, plain_keys) for _ in range(rng.choice(sizes))])
    pairs = []
    for _ in range(rng.choice([0, 1, 2, 4, 15, 16] if depth < 2 else [0, 1, 2])):
        if plain_keys:
            key = rng.choice([('str', ''.join(rng.choice(ALPHABET) for _ in range(rng.randrange(4)))), ('u', rng.randrange(300)), ('i', rng.randrange(-300, 0))])
        else:
            key = gen(rng, depth + 1, max_depth) if rng.random() < 0.3 else ('str', rng.choice(['a', 'b', 'k']))
        pairs.append((key, gen(rng, depth + 1, max_depth, plain_keys)))
    return ('map', pairs)


def widener(rng, rate):
    def w(m):
        if rng.random() >= rate:
            return None
        k = m[0]
        if k in ('arr', 'map') and len(m[1]) < 65536:
            code = (b'\xdc' if k == 'arr' else b'\xde') + be(len(m[1]), 2)
            body = b''.join(encode(x, w) for x in m[1]) if k == 'arr' else b''.join(encode(a, w) + encode(b, w) for a, b in m[1])
            return code + body
        return widen_header(rng, m)
    return w


def mutate(rng, data):
    data = bytearray(data)
    for _ in range(rng.choice([1, 1, 2, 3])):
        r = rng.random()
        if r < 0.3 and data:
            data[rng.randrange(len(data))] = rng.randrange(256)
        elif r < 0.5 and data:
            data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
        elif r < 0.7:
            del data[rng.randrange(len(data) + 1):]
        elif r < 0.85:
            data.insert(rng.randrange(len(data) + 1), rng.choice([0xc1, 0xa1, 0x91, 0x81, 0xd6, 0xc7, 0xdc, 0xff, rng.randrange(256)]))
        elif data:
            del data[rng.randrange(len(data))]
    return bytes(data)


# ---------------------------------------------------------------- driving
def batch(exe, mode, lines, chunk=4096, depth=128, items=1000000, strings=16777216):
    data = ''.join(x.hex() + '\n' for x in lines).encode()
    proc = subprocess.run([exe, mode, str(chunk), str(depth), str(items), str(strings)], input=data, capture_output=True, timeout=240)
    if proc.returncode != 0:
        raise SystemExit('batch %s exited %d: %r' % (mode, proc.returncode, proc.stderr[:200]))
    out = proc.stdout.decode().split('\n')
    assert out[-1] == '' and len(out) == len(lines) + 1, (len(out), len(lines))
    return out[:-1]


CHUNKS = (1, 3, 7, 4096)


def expect_copy(data, **limits):
    status, m = outcome(data, **limits)
    return encode(m).hex() if status == 'ok' else status


def expect_check(data):
    status, m = outcome(data, canonical=True)
    if status == 'ok':
        assert encode(m) == data, data.hex()  # canonical input is its own shortest form
    return status


def compare(exe, lines, report):
    expected = {'copy': [expect_copy(x) for x in lines], 'check': [expect_check(x) for x in lines]}
    agree = {}
    for mode in ('copy', 'check'):
        good = 0
        for chunk in CHUNKS:
            for data, want, have in zip(lines, expected[mode], batch(exe, mode, lines, chunk)):
                if want == have:
                    good += 1
                elif len(report) < 10:
                    report.append((mode, chunk, data.hex()[:120], want[:80], have[:80]))
        agree[mode] = good
    # msgpack-python: same acceptance, and the Lanius output has the input's value.
    python = 0
    for data, copy in zip(lines, expected['copy']):
        ok, value = reference(data)
        if ok != (not copy.startswith('error')):
            if len(report) < 10:
                report.append(('msgpack-python acceptance', data.hex()[:120], copy[:60]))
            continue
        if ok:
            again_ok, again = reference(bytes.fromhex(copy))
            if not (again_ok and same(again, value)):
                if len(report) < 10:
                    report.append(('msgpack-python value', data.hex()[:120]))
                continue
        python += 1
    return expected, agree, python


def finish(name, fields, report):
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    print(name + ' ' + ' '.join('%s=%s' % kv for kv in fields))


def group_spec(exe, json_exe):
    report = []
    typed = 0
    for h, want in SPEC:
        ok, value = reference(bytes.fromhex(h))
        status, m = outcome(bytes.fromhex(h))
        if ok and same(value, want) and status == 'ok' and same(py_value(m), want):
            typed += 1
        else:
            report.append(('typed', h[:40], repr(value)[:40], status))
    errors = 0
    for h, want in SPEC_ERRORS:
        status, _ = outcome(bytes.fromhex(h))
        ok, _ = reference(bytes.fromhex(h))
        if status == 'error ' + want and not ok:
            errors += 1
        else:
            report.append(('typed error', h, want, status, ok))
    lines = [bytes.fromhex(h) for h, _ in SPEC] + [bytes.fromhex(h) for h, _ in SPEC_ERRORS]
    expected, agree, python = compare(exe, lines, report)
    n = len(lines) * len(CHUNKS)
    finish('msgpack-spec', [('cases', len(lines)), ('typed', '%d/%d' % (typed + errors, len(lines))), ('copy', '%d/%d' % (agree['copy'], n)),
                            ('check', '%d/%d' % (agree['check'], n)), ('msgpack_python', '%d/%d' % (python, len(lines)))], report)


def group_generated(exe, json_exe, count=1500):
    rng = random.Random(2013)
    report, lines, packb, packable = [], [], 0, 0
    for i in range(count):
        m = gen(rng)
        data = encode(m, widener(rng, 0.2) if i % 3 == 0 else None)
        lines.append(data)
        # The shortest encoder agrees with msgpack.packb wherever packb applies.
        value = py_value(m, pack=True) if not has_f32_or_pairs(m) else None
        try:
            packed = msgpack.packb(value, use_bin_type=True, strict_types=False) if not has_f32_or_pairs(m) else None
        except Exception:
            packed = None
        packable += packed is not None
        if packed is not None and packed == encode(m):
            packb += 1
        elif packed is not None and len(report) < 10:
            report.append(('packb', encode(m).hex()[:80], packed.hex()[:80]))
    expected, agree, python = compare(exe, lines, report)
    canonical = sum(1 for e in expected['check'] if e == 'ok')
    n = count * len(CHUNKS)
    finish('msgpack-generated', [('cases', count), ('copy', '%d/%d' % (agree['copy'], n)), ('check', '%d/%d' % (agree['check'], n)),
                                 ('msgpack_python', '%d/%d' % (python, count)), ('packb', '%d/%d' % (packb, packable)), ('canonical', canonical)], report)


def has_f32_or_pairs(m):
    """Values packb cannot express: float32, ordered pairs, reserved ext codes."""
    if m[0] in ('f32', 'map') or (m[0] == 'ext' and m[1] < -1):
        return True
    if m[0] == 'arr':
        return any(has_f32_or_pairs(x) for x in m[1])
    return False


def group_mutations(exe, json_exe, count=3000):
    rng = random.Random(1024)
    seeds = [encode(gen(rng, max_depth=4)) for _ in range(400)] + [bytes.fromhex(h) for h, _ in SPEC]
    lines = [mutate(rng, rng.choice(seeds)) for _ in range(count)]
    report = []
    expected, agree, python = compare(exe, lines, report)
    rejected = sum(1 for e in expected['copy'] if e.startswith('error'))
    n = count * len(CHUNKS)
    finish('msgpack-mutations', [('cases', count), ('copy', '%d/%d' % (agree['copy'], n)), ('check', '%d/%d' % (agree['check'], n)),
                                 ('msgpack_python', '%d/%d' % (python, count)), ('rejected', rejected)], report)


def group_limits(exe, json_exe, count=1200):
    rng = random.Random(77)
    settings = [(0, 1000000, 16777216), (1, 1000000, 16777216), (3, 1000000, 16777216), (128, 1, 16777216),
                (128, 7, 16777216), (128, 40, 16777216), (128, 1000000, 0), (128, 1000000, 4), (2, 12, 8)]
    report, good, cases, rejected = [], 0, 0, 0
    for depth, items, strings in settings:
        lines = [encode(gen(rng, max_depth=4)) for _ in range(count // len(settings))]
        want = [expect_copy(x, max_depth=depth, max_items=items, max_string=strings) for x in lines]
        rejected += sum(1 for w in want if w.startswith('error'))
        for chunk in (1, 4096):
            for data, w, g in zip(lines, want, batch(exe, 'copy', lines, chunk, depth, items, strings)):
                cases += 1
                good += w == g
                if w != g and len(report) < 10:
                    report.append((depth, items, strings, chunk, data.hex()[:80], w[:60], g[:60]))
    deep = [b'\x91' * n + b'\x00' for n in (127, 128, 129, 1000)]
    want = [expect_copy(x) for x in deep]
    cases += len(deep)
    good += sum(1 for w, g in zip(want, batch(exe, 'copy', deep)) if w == g)
    finish('msgpack-limits', [('cases', cases), ('agree', good), ('rejected', rejected)], report)


def group_sequences(exe, json_exe, count=600):
    rng = random.Random(4096)
    lines = []
    for _ in range(count):
        data = b''.join(encode(gen(rng, max_depth=3)) for _ in range(rng.randrange(0, 5)))
        lines.append(mutate(rng, data) if rng.random() < 0.25 else data)
    want, unpacker = [], 0
    for x in lines:
        try:
            roots = Decoder(x).sequence()
            want.append('roots %d' % len(roots))
        except CErr as e:
            want.append('error %s %d' % (e.kind, e.offset))
        # msgpack.Unpacker fed one byte at a time agrees on the stream.
        u = msgpack.Unpacker(raw=False, strict_map_key=False, object_pairs_hook=list, timestamp=0, ext_hook=Ext)
        got, failed, complete = 0, False, 0
        try:
            for i in range(len(x)):
                u.feed(x[i:i + 1])
                for _ in u:
                    got += 1
                    complete = u.tell()
        except Exception:
            failed = True
        trailing = complete != len(x) if not failed else False
        unpacker += (('error' in want[-1]) == (failed or trailing)) and (failed or trailing or want[-1] == 'roots %d' % got)
    report, good = [], 0
    for chunk in (1, 4096):
        for data, w, g in zip(lines, want, batch(exe, 'seq', lines, chunk)):
            good += w == g
            if w != g and len(report) < 10:
                report.append((chunk, data.hex()[:80], w, g))
    finish('msgpack-sequences', [('cases', count * 2), ('agree', good), ('unpacker', '%d/%d' % (unpacker, count)),
                                 ('rejected', sum(1 for w in want if w.startswith('error')))], report)


# ---------------------------------------------------------------- JSON
class Num:
    def __init__(self, s):
        self.s = s


class Obj:
    def __init__(self, pairs):
        self.pairs = pairs


def digits_of(spelling):
    mantissa = spelling.lower().lstrip('-').split('e')[0].replace('.', '')
    return mantissa.lstrip('0').rstrip('0') or '0'


def json_of(m):
    k = m[0]
    if k == 'nil':
        return None
    if k == 'bool':
        return m[1]
    if k in ('u', 'i'):
        return ('int', m[1])
    if k in ('f32', 'f64'):
        x = py_value(m)
        return None if math.isinf(x) or math.isnan(x) else ('float', x)
    if k == 'str':
        return m[1]
    if k == 'bin':
        return base64.urlsafe_b64encode(m[1]).decode().rstrip('=')
    if k == 'arr':
        return [json_of(x) for x in m[1]]
    return ('obj', [(a[1] if a[0] == 'str' else str(a[1]), json_of(b)) for a, b in m[1]])


def json_same(want, got):
    if isinstance(want, tuple) and want[0] == 'int':
        return isinstance(got, Num) and got.s.lstrip('-').isdigit() and int(got.s) == want[1]
    if isinstance(want, tuple) and want[0] == 'float':
        if not isinstance(got, Num):
            return False
        x = float(got.s)
        return x == want[1] and math.copysign(1, x) == math.copysign(1, want[1]) and digits_of(got.s) == digits_of(repr(want[1]))
    if isinstance(want, tuple) and want[0] == 'obj':
        return isinstance(got, Obj) and len(got.pairs) == len(want[1]) and all(a[0] == b[0] and json_same(a[1], b[1]) for a, b in zip(want[1], got.pairs))
    if isinstance(want, list):
        return isinstance(got, list) and len(got) == len(want) and all(json_same(a, b) for a, b in zip(want, got))
    return type(want) is type(got) and want == got


def parse_json_lines(text):
    return [json.loads(line, parse_int=Num, parse_float=Num, object_pairs_hook=Obj) for line in text.split('\n')[:-1]]


def to_json_case(json_exe, data):
    try:
        roots = Decoder(data, max_depth=512, max_items=1 << 64, json_mode=True).sequence()
        status = 'ok'
    except CErr as e:
        status = 'msgpack-json: %s at %d\n' % (e.kind, e.offset)
    proc = subprocess.run([json_exe], input=data, capture_output=True, timeout=20)
    if status != 'ok':
        return proc.returncode == 2 and proc.stderr.decode() == status, 'error'
    if not roots:
        return proc.returncode == 0 and proc.stdout == b'', 'empty'
    if proc.returncode != 0 or proc.stderr:
        return False, 'converted'
    got = parse_json_lines(proc.stdout.decode())
    return len(got) == len(roots) and all(json_same(json_of(m), g) for m, g in zip(roots, got)), 'converted'


def json_text(rng, depth=0):
    r = rng.random()
    if depth > 3:
        r *= 0.5
    if r < 0.15:
        return json.dumps(''.join(rng.choice(ALPHABET) for _ in range(rng.randrange(6))), ensure_ascii=rng.random() < 0.5)
    if r < 0.4:
        return rng.choice(['0', '-0', '1', '-1', '127', '128', '-33', '65536', '18446744073709551615', '18446744073709551616',
                           '-9223372036854775808', '-9223372036854775809', '1.5', '-0.0', '1e400', '-1e-400', '2.5e-324',
                           '0.1', '123456789012345678901234567890', '1E+2', str(rng.randrange(-2 ** 70, 2 ** 70)),
                           repr(rng.uniform(-1e9, 1e9))])
    if r < 0.5:
        return rng.choice(['true', 'false', 'null'])
    if r < 0.75:
        return '[' + ','.join(json_text(rng, depth + 1) for _ in range(rng.choice([0, 1, 3, 16, 20]))) + ']'
    keys = [json.dumps(rng.choice(['a', 'b', 'ké', ''])) for _ in range(rng.choice([0, 1, 2, 16, 17]))]
    return '{' + ','.join('%s:%s' % (k, json_text(rng, depth + 1)) for k in keys) + '}'


def json_model(value):
    """Expected MessagePack model of a JSON value parsed with Num/Obj."""
    if value is None:
        return ('nil',)
    if isinstance(value, bool):
        return ('bool', value)
    if isinstance(value, Num):
        s = value.s
        if s.lstrip('-').isdigit():
            n = int(s)
            if -2 ** 63 <= n < 2 ** 64:
                return ('u', n) if n >= 0 else ('i', n)
        return ('f64', struct.unpack('>Q', struct.pack('>d', float(s)))[0])
    if isinstance(value, str):
        return ('str', value)
    if isinstance(value, list):
        return ('arr', [json_model(x) for x in value])
    return ('map', [(('str', k), json_model(v)) for k, v in value.pairs])


def group_json(exe, json_exe, count=500):
    rng = random.Random(8259)
    report, good, kinds = [], 0, {}
    cases = []
    for i in range(count):
        roots = [gen(rng, max_depth=3, plain_keys=(i % 5 != 0)) for _ in range(1 if i % 4 else rng.randrange(0, 4))]
        data = b''.join(encode(m) for m in roots)
        cases.append(mutate(rng, data) if i % 10 == 9 else data)
    for data in cases:
        ok, kind = to_json_case(json_exe, data)
        kinds[kind] = kinds.get(kind, 0) + 1
        good += ok
        if not ok and len(report) < 10:
            report.append(('to-json', data.hex()[:100]))
    # --from-json against Python json and the shortest encoder.
    back, back_good = 0, 0
    for i in range(400):
        text = json_text(rng)
        if i % 8 == 7:
            text = text[:rng.randrange(len(text) + 1)] + rng.choice(['', ',', ']', '}', '"', 'x'])
        try:
            value = json.loads(text, parse_int=Num, parse_float=Num, object_pairs_hook=Obj, parse_constant=reject)
            want = encode(json_model(value))
        except ValueError:
            want = None
        proc = subprocess.run([json_exe, '--from-json'], input=text.encode(), capture_output=True, timeout=20)
        ok = (proc.returncode == 0 and proc.stdout == want) if want is not None else (proc.returncode == 2 and proc.stderr.startswith(b'msgpack-json: json '))
        if ok and want is not None:
            # msgpack-python reads the bytes back to the JSON value.
            ok = same(reference(proc.stdout)[1], py_value(json_model(value)))
        back += 1
        back_good += ok
        if not ok and len(report) < 10:
            report.append(('from-json', text[:100], proc.returncode, proc.stdout[:60], proc.stderr[:80]))
    finish('msgpack-json', [('cases', len(cases) + back), ('agree', good + back_good), ('converted', kinds.get('converted', 0)),
                            ('empty', kinds.get('empty', 0)), ('rejected', kinds.get('error', 0)), ('from_json', '%d/%d' % (back_good, back))], report)


def reject(name):
    raise ValueError(name)


def main():
    group, exe, json_exe = sys.argv[1], sys.argv[2], sys.argv[3]
    groups = {'spec': group_spec, 'generated': group_generated, 'mutations': group_mutations,
              'limits': group_limits, 'sequences': group_sequences, 'json': group_json}
    if group not in groups:
        raise SystemExit(__doc__)
    groups[group](exe, json_exe)


if __name__ == '__main__':
    main()
