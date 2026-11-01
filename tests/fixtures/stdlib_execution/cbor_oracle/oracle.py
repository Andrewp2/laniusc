"""Oracle for ext::cbor_stream and sample_programs/cbor_to_json.lani.

The reference is an independent Python CBOR implementation in this file: a
decoder that mirrors the documented error order and offsets, a preserving
encoder, a core deterministic encoder (RFC 8949 section 4.2.1, floats narrowed
with struct round trips) and the RFC 8949 section 6.1 JSON mapping used by the
sample. The RFC 8949 Appendix A table below is typed in by hand.

usage: oracle.py GROUP BATCH [CBOR_TO_JSON]
GROUP: appendix, generated, mutations, limits, sequences, json
BATCH is the compiled tests/fixtures/stdlib_execution/cbor_oracle/cbor_batch.lani.
"""
import base64
import json
import math
import random
import struct
import subprocess
import sys

sys.setrecursionlimit(20000)


class Undefined:
    def __eq__(self, other):
        return isinstance(other, Undefined)

    def __repr__(self):
        return 'undefined'


UNDEF = Undefined()


class Simple:
    def __init__(self, value):
        self.value = value

    def __eq__(self, other):
        return isinstance(other, Simple) and other.value == self.value

    def __repr__(self):
        return 'simple(%d)' % self.value


class Tag:
    def __init__(self, number, content):
        self.number, self.content = number, content

    def __repr__(self):
        return '%d(%r)' % (self.number, self.content)


class Map:
    def __init__(self, pairs):
        self.pairs = list(pairs)

    def __repr__(self):
        return '{%s}' % ', '.join('%r: %r' % p for p in self.pairs)


INF, NAN = float('inf'), float('nan')

# RFC 8949 Appendix A, Table 6: (expected value, encoding). Typed by hand.
APPENDIX_A = [
    (0, '00'), (1, '01'), (10, '0a'), (23, '17'), (24, '1818'), (25, '1819'),
    (100, '1864'), (1000, '1903e8'), (1000000, '1a000f4240'),
    (1000000000000, '1b000000e8d4a51000'),
    (18446744073709551615, '1bffffffffffffffff'),
    (Tag(2, bytes.fromhex('010000000000000000')), 'c249010000000000000000'),
    (-18446744073709551616, '3bffffffffffffffff'),
    (Tag(3, bytes.fromhex('010000000000000000')), 'c349010000000000000000'),
    (-1, '20'), (-10, '29'), (-100, '3863'), (-1000, '3903e7'),
    (0.0, 'f90000'), (-0.0, 'f98000'), (1.0, 'f93c00'), (1.1, 'fb3ff199999999999a'),
    (1.5, 'f93e00'), (65504.0, 'f97bff'), (100000.0, 'fa47c35000'),
    (3.4028234663852886e+38, 'fa7f7fffff'), (1.0e+300, 'fb7e37e43c8800759c'),
    (5.960464477539063e-8, 'f90001'), (0.00006103515625, 'f90400'),
    (-4.0, 'f9c400'), (-4.1, 'fbc010666666666666'),
    (INF, 'f97c00'), (NAN, 'f97e00'), (-INF, 'f9fc00'),
    (INF, 'fa7f800000'), (NAN, 'fa7fc00000'), (-INF, 'faff800000'),
    (INF, 'fb7ff0000000000000'), (NAN, 'fb7ff8000000000000'), (-INF, 'fbfff0000000000000'),
    (False, 'f4'), (True, 'f5'), (None, 'f6'), (UNDEF, 'f7'),
    (Simple(16), 'f0'), (Simple(255), 'f8ff'),
    (Tag(0, '2013-03-21T20:04:00Z'), 'c074323031332d30332d32315432303a30343a30305a'),
    (Tag(1, 1363896240), 'c11a514b67b0'),
    (Tag(1, 1363896240.5), 'c1fb41d452d9ec200000'),
    (Tag(23, bytes.fromhex('01020304')), 'd74401020304'),
    (Tag(24, bytes.fromhex('6449455446')), 'd818456449455446'),
    (Tag(32, 'http://www.example.com'), 'd82076687474703a2f2f7777772e6578616d706c652e636f6d'),
    (b'', '40'), (bytes.fromhex('01020304'), '4401020304'),
    ('', '60'), ('a', '6161'), ('IETF', '6449455446'), ('"\\', '62225c'),
    ('ü', '62c3bc'), ('水', '63e6b0b4'), ('\U00010151', '64f0908591'),
    ([], '80'), ([1, 2, 3], '83010203'), ([1, [2, 3], [4, 5]], '8301820203820405'),
    (list(range(1, 26)), '98190102030405060708090a0b0c0d0e0f101112131415161718181819'),
    (Map([]), 'a0'), (Map([(1, 2), (3, 4)]), 'a201020304'),
    (Map([('a', 1), ('b', [2, 3])]), 'a26161016162820203'),
    (['a', Map([('b', 'c')])], '826161a161626163'),
    (Map([('a', 'A'), ('b', 'B'), ('c', 'C'), ('d', 'D'), ('e', 'E')]), 'a56161614161626142616361436164614461656145'),
    (bytes.fromhex('0102030405'), '5f42010243030405ff'),
    ('streaming', '7f657374726561646d696e67ff'),
    ([], '9fff'),
    ([1, [2, 3], [4, 5]], '9f018202039f0405ffff'),
    ([1, [2, 3], [4, 5]], '9f01820203820405ff'),
    ([1, [2, 3], [4, 5]], '83018202039f0405ff'),
    ([1, [2, 3], [4, 5]], '83019f0203ff820405'),
    (list(range(1, 26)), '9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff'),
    (Map([('a', 1), ('b', [2, 3])]), 'bf61610161629f0203ffff'),
    (['a', Map([('b', 'c')])], '826161bf61626163ff'),
    (Map([('Fun', True), ('Amt', -2)]), 'bf6346756ef563416d7421ff'),
]


# ---------------------------------------------------------------- floats
def half_value(bits):
    return struct.unpack('>e', bits.to_bytes(2, 'big'))[0]


def single_value(bits):
    return struct.unpack('>f', bits.to_bytes(4, 'big'))[0]


def double_value(bits):
    return struct.unpack('>d', bits.to_bytes(8, 'big'))[0]


def float_value(width, bits):
    return {2: half_value, 4: single_value, 8: double_value}[width](bits)


def nan_narrow(bits, width):
    """NaN/infinity bits narrowed one step with the payload kept, or None."""
    if width == 8:
        sign, frac = bits >> 63, bits & ((1 << 52) - 1)
        if frac & ((1 << 29) - 1):
            return None
        return (sign << 31) | (0xff << 23) | (frac >> 29)
    sign, frac = bits >> 31, bits & ((1 << 23) - 1)
    if frac & ((1 << 13) - 1):
        return None
    return (sign << 15) | (0x1f << 10) | (frac >> 13)


def special(width, bits):
    exp_bits = {2: 5, 4: 8, 8: 11}[width]
    frac_bits = {2: 10, 4: 23, 8: 52}[width]
    return (bits >> frac_bits) & ((1 << exp_bits) - 1) == (1 << exp_bits) - 1


def narrower(width, bits):
    """(width, bits) of the next narrower exact float, or None."""
    if width == 2:
        return None
    if special(width, bits):
        b = nan_narrow(bits, width)
        return None if b is None else (width // 2, b)
    x = float_value(width, bits)
    code = '>e' if width == 4 else '>f'
    try:
        packed = struct.pack(code, x)
    except (OverflowError, struct.error):
        return None
    if struct.unpack(code, packed)[0] != x:
        return None
    return (width // 2, int.from_bytes(packed, 'big'))


def shortest(width, bits):
    while True:
        step = narrower(width, bits)
        if step is None:
            return width, bits
        width, bits = step


def widen_bits(width, bits, wide):
    if wide == 8:
        return widen_to_double(width, bits)
    if special(2, bits):
        return (bits >> 15) << 31 | 0xff << 23 | (bits & 0x3ff) << 13
    return struct.unpack('>I', struct.pack('>f', half_value(bits)))[0]


def widen_to_double(width, bits):
    if width == 8:
        return bits
    if special(width, bits):
        frac_bits = {2: 10, 4: 23}[width]
        sign = bits >> (frac_bits + {2: 5, 4: 8}[width])
        frac = bits & ((1 << frac_bits) - 1)
        return (sign << 63) | (0x7ff << 52) | (frac << (52 - frac_bits))
    return struct.unpack('>Q', struct.pack('>d', float_value(width, bits)))[0]


# ---------------------------------------------------------------- model
# ('u', n) ('n', n) ('b', bytes, chunks|None) ('t', str, chunks|None)
# ('a', items, indefinite) ('m', pairs, indefinite) ('tag', n, item)
# ('s', value) ('f', width, bits)
def value(m):
    k = m[0]
    if k == 'u':
        return m[1]
    if k == 'n':
        return -1 - m[1]
    if k in ('b', 't'):
        return m[1]
    if k == 'a':
        return [value(x) for x in m[1]]
    if k == 'm':
        return Map((value(a), value(b)) for a, b in m[1])
    if k == 'tag':
        return Tag(m[1], value(m[2]))
    if k == 's':
        return {20: False, 21: True, 22: None, 23: UNDEF}.get(m[1], Simple(m[1]))
    return float_value(m[1], m[2])


def same(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, float):
        if math.isnan(a):
            return math.isnan(b)
        return a == b and math.copysign(1, a) == math.copysign(1, b)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, Map):
        return len(a.pairs) == len(b.pairs) and all(same(x[0], y[0]) and same(x[1], y[1]) for x, y in zip(a.pairs, b.pairs))
    if isinstance(a, Tag):
        return a.number == b.number and same(a.content, b.content)
    return a == b


def head(major, arg, width=None):
    if width is None:
        width = 0 if arg < 24 else 1 if arg < 256 else 2 if arg < 65536 else 4 if arg < 2 ** 32 else 8
    if width == 0:
        return bytes([major << 5 | arg])
    return bytes([major << 5 | {1: 24, 2: 25, 4: 26, 8: 27}[width]]) + arg.to_bytes(width, 'big')


def encode(m, widen=None):
    """Preserving encoder. widen(arg) may return a longer head width."""
    def h(major, arg):
        w = widen(arg) if widen else None
        return head(major, arg, w)
    k = m[0]
    if k == 'u':
        return h(0, m[1])
    if k == 'n':
        return h(1, m[1])
    if k in ('b', 't'):
        major = 2 if k == 'b' else 3
        if m[2] is None:
            data = m[1] if k == 'b' else m[1].encode()
            return h(major, len(data)) + data
        out = bytes([major << 5 | 31])
        for c in m[2]:
            data = c if k == 'b' else c.encode()
            out += h(major, len(data)) + data
        return out + b'\xff'
    if k == 'a':
        body = b''.join(encode(x, widen) for x in m[1])
        return (b'\x9f' + body + b'\xff') if m[2] else h(4, len(m[1])) + body
    if k == 'm':
        body = b''.join(encode(a, widen) + encode(b, widen) for a, b in m[1])
        return (b'\xbf' + body + b'\xff') if m[2] else h(5, len(m[1])) + body
    if k == 'tag':
        return h(6, m[1]) + encode(m[2], widen)
    if k == 's':
        return bytes([0xe0 | m[1]]) if m[1] < 24 else bytes([0xf8, m[1]])
    return bytes([{2: 0xf9, 4: 0xfa, 8: 0xfb}[m[1]]]) + m[2].to_bytes(m[1], 'big')


class Duplicate(Exception):
    pass


def canonical(m):
    k = m[0]
    if k in ('u', 'n', 's'):
        return encode(m)
    if k in ('b', 't'):
        data = m[1] if k == 'b' else m[1].encode()
        return head(2 if k == 'b' else 3, len(data)) + data
    if k == 'a':
        return head(4, len(m[1])) + b''.join(canonical(x) for x in m[1])
    if k == 'm':
        pairs = sorted((canonical(a), canonical(b)) for a, b in m[1])
        for i in range(1, len(pairs)):
            if pairs[i - 1][0] == pairs[i][0]:
                raise Duplicate()
        return head(5, len(pairs)) + b''.join(a + b for a, b in pairs)
    if k == 'tag':
        return head(6, m[1]) + canonical(m[2])
    w, b = shortest(m[1], m[2])
    return encode(('f', w, b))


class CErr(Exception):
    def __init__(self, kind, offset):
        super().__init__(kind, offset)
        self.kind, self.offset = kind, offset


BREAK = object()


def preferred(additional, arg):
    return {24: arg >= 24, 25: arg > 255, 26: arg > 65535, 27: arg > 0xffffffff}.get(additional, True)


class Decoder:
    # canon: a map whose canonical keys repeat fails when it closes, as the
    # deterministic Writer does. json_keys: a key that is not text or an
    # integer (looking through tags) fails at its head, as cbor_to_json does.
    def __init__(self, data, det=False, max_depth=128, max_items=1000000, max_string=16777216, canon=False, json_keys=False):
        self.data, self.det, self.canon, self.json_keys = data, det, canon, json_keys
        self.max_depth, self.max_items, self.max_string = max_depth, max_items, max_string
        self.pos, self.items = 0, 0
        self.offsets = {}

    def closed(self, node):
        if self.canon:
            try:
                canonical(node)
            except Duplicate:
                raise CErr('werror DuplicateKey', None)

    def one(self):
        m = self.item(None, 0)
        if self.pos != len(self.data):
            raise CErr('TrailingData', self.pos)
        return m

    def sequence(self):
        roots = 0
        while self.pos < len(self.data):
            self.item(None, 0)
            roots += 1
        return roots

    def item(self, parent, depth, odd=False, chunk=None, key=False):
        d, at = self.data, self.pos
        if at >= len(d):
            raise CErr('UnexpectedEnd', at)
        major, additional = d[at] >> 5, d[at] & 31
        if 28 <= additional <= 30:
            raise CErr('InvalidHead', at)
        width = {24: 1, 25: 2, 26: 4, 27: 8}.get(additional, 0)
        if at + 1 + width > len(d):
            raise CErr('UnexpectedEnd', at)
        arg = int.from_bytes(d[at + 1:at + 1 + width], 'big') if width else additional
        if additional == 31:
            if major in (0, 1, 6):
                raise CErr('InvalidHead', at)
            if major == 7:
                if parent is None:
                    raise CErr('UnexpectedBreak', at)
                if parent == 'imap' and odd:
                    raise CErr('OddMap', at)
                if parent in ('arr', 'map', 'tag'):
                    raise CErr('UnexpectedBreak', at)
                self.pos += 1
                return BREAK
            if self.det:
                raise CErr('Indefinite', at)
            if parent in ('ib', 'it'):
                raise CErr('ChunkType', at)
            if self.items >= self.max_items:
                raise CErr('ItemLimit', at)
            if depth >= self.max_depth:
                raise CErr('DepthLimit', at)
            self.items += 1
            self.pos += 1
            if key and self.json_keys and major != 3:
                raise CErr('UnsupportedKey', at)
            if major in (2, 3):
                state, chunks = [0], []
                while True:
                    c = self.item('ib' if major == 2 else 'it', depth + 1, chunk=state)
                    if c is BREAK:
                        break
                    chunks.append(c[1])
                joined = b''.join(chunks) if major == 2 else ''.join(chunks)
                node = ('b' if major == 2 else 't', joined, chunks)
            elif major == 4:
                items = []
                while True:
                    x = self.item('iarr', depth + 1)
                    if x is BREAK:
                        break
                    items.append(x)
                node = ('a', items, True)
            else:
                pairs = []
                while True:
                    k = self.item('imap', depth + 1, odd=False, key=True)
                    if k is BREAK:
                        break
                    v = self.item('imap', depth + 1, odd=True)
                    pairs.append((k, v))
                node = ('m', pairs, True)
                self.closed(node)
            self.offsets[id(node)] = at
            return node
        if self.det and major != 7 and not preferred(additional, arg):
            raise CErr('NotPreferred', at)
        if major == 7 and additional == 24 and arg < 32:
            raise CErr('InvalidSimple', at)
        if self.det and major == 7 and additional in (26, 27):
            if narrower(4 if additional == 26 else 8, arg) is not None:
                raise CErr('FloatNotShortest', at)
        if (parent == 'ib' and major != 2) or (parent == 'it' and major != 3):
            raise CErr('ChunkType', at)
        if major in (2, 3):
            if arg > self.max_string:
                raise CErr('StringLimit', at)
            if chunk is not None and arg > self.max_string - chunk[0]:
                raise CErr('StringLimit', at)
            if at + 1 + width + arg > len(d):
                raise CErr('UnexpectedEnd', at)
        if self.items >= self.max_items:
            raise CErr('ItemLimit', at)
        start = at + 1 + width
        payload = d[start:start + arg] if major in (2, 3) else b''
        text = None
        if major == 3:
            try:
                text = payload.decode('utf-8', 'strict')
            except UnicodeDecodeError:
                raise CErr('InvalidUtf8', at)
        if major in (4, 5, 6) and depth >= self.max_depth:
            raise CErr('DepthLimit', at)
        self.items += 1
        if key and self.json_keys and major not in (0, 1, 3, 6):
            raise CErr('UnsupportedKey', at)
        self.pos = start + len(payload)
        if chunk is not None:
            chunk[0] += arg
        if major == 0:
            node = ('u', arg)
        elif major == 1:
            node = ('n', arg)
        elif major == 2:
            node = ('b', bytes(payload), None)
        elif major == 3:
            node = ('t', text, None)
        elif major == 4:
            node = ('a', [self.item('arr', depth + 1) for _ in range(arg)], False)
        elif major == 5:
            pairs, previous = [], None
            for _ in range(arg):
                kstart = self.pos
                k = self.item('map', depth + 1, key=True)
                raw = self.data[kstart:self.pos]
                if self.det and previous is not None:
                    if raw == previous:
                        raise CErr('DuplicateKey', kstart)
                    if raw < previous:
                        raise CErr('UnsortedKeys', kstart)
                previous = raw
                pairs.append((k, self.item('map', depth + 1, odd=True)))
            node = ('m', pairs, False)
            self.closed(node)
        elif major == 6:
            node = ('tag', arg, self.item('tag', depth + 1, key=key))
        elif additional < 25:
            node = ('s', arg)
        else:
            node = ('f', {25: 2, 26: 4, 27: 8}[additional], arg)
        self.offsets[id(node)] = at
        return node


def python_outcome(data, det=False, **limits):
    try:
        return 'ok', Decoder(data, det, **limits).one()
    except CErr as e:
        if e.offset is None:
            return e.kind, None
        return 'error %s %d' % (e.kind, e.offset), None


# ---------------------------------------------------------------- JSON mapping
class Unsupported(Exception):
    def __init__(self, offset):
        super().__init__(offset)
        self.offset = offset


def to_json(m, offsets):
    """Expected JSON value; numbers as ('int', n) or ('float', x)."""
    k = m[0]
    if k == 'u':
        return ('int', m[1])
    if k == 'n':
        return ('int', -1 - m[1])
    if k == 'b':
        return base64.urlsafe_b64encode(m[1]).decode().rstrip('=')
    if k == 't':
        return m[1]
    if k == 'a':
        return [to_json(x, offsets) for x in m[1]]
    if k == 'm':
        pairs = []
        for a, b in m[1]:
            key = a
            while key[0] == 'tag':
                key = key[2]
            if key[0] == 't':
                name = key[1]
            elif key[0] in ('u', 'n'):
                name = str(value(key))
            else:
                raise Unsupported(offsets[id(key)])
            pairs.append((name, to_json(b, offsets)))
        return ('obj', pairs)
    if k == 'tag':
        return to_json(m[2], offsets)
    if k == 's':
        return {20: False, 21: True}.get(m[1])
    x = float_value(m[1], m[2])
    return None if math.isinf(x) or math.isnan(x) else ('float', x)


def digits_of(spelling):
    mantissa = spelling.lower().lstrip('-').split('e')[0].replace('.', '')
    return mantissa.lstrip('0').rstrip('0') or '0'


def json_same(expected, got):
    if isinstance(expected, tuple) and expected[0] == 'int':
        return isinstance(got, Num) and '.' not in got.s and 'e' not in got.s.lower() and int(got.s) == expected[1]
    if isinstance(expected, tuple) and expected[0] == 'float':
        if not isinstance(got, Num):
            return False
        x = float(got.s)
        return x == expected[1] and math.copysign(1, x) == math.copysign(1, expected[1]) and digits_of(got.s) == digits_of(repr(expected[1]))
    if isinstance(expected, tuple) and expected[0] == 'obj':
        return isinstance(got, Obj) and len(got.pairs) == len(expected[1]) and all(
            a[0] == b[0] and json_same(a[1], b[1]) for a, b in zip(expected[1], got.pairs))
    if isinstance(expected, list):
        return isinstance(got, list) and len(got) == len(expected) and all(json_same(a, b) for a, b in zip(expected, got))
    return type(expected) is type(got) and expected == got


class Num:
    def __init__(self, s):
        self.s = s


class Obj:
    def __init__(self, pairs):
        self.pairs = pairs


def parse_json(text):
    return json.loads(text, parse_int=Num, parse_float=Num, object_pairs_hook=Obj)


# ---------------------------------------------------------------- generation
ALPHABET = ['a', 'b', 'z', ' ', '"', '\\', '\x00', '\n', '\x7f', 'é', 'ü', '水', '€', '\U00010151', '\U0001f600']


def rand_text(rng, n):
    return ''.join(rng.choice(ALPHABET) for _ in range(n))


def rand_arg(rng):
    r = rng.random()
    if r < 0.4:
        return rng.randrange(24)
    if r < 0.6:
        return rng.randrange(24, 256)
    if r < 0.75:
        return rng.randrange(256, 65536)
    if r < 0.88:
        return rng.randrange(65536, 2 ** 32)
    return rng.choice([2 ** 32, 2 ** 64 - 1, rng.randrange(2 ** 32, 2 ** 64)])


def rand_float(rng):
    r = rng.random()
    if r < 0.2:
        return ('f', 2, rng.randrange(65536))
    if r < 0.35:
        return ('f', 4, rng.randrange(2 ** 32))
    if r < 0.5:
        return ('f', 8, rng.randrange(2 ** 64))
    if r < 0.8:  # narrowable values stored wide
        w = rng.choice([2, 4])
        b = rng.randrange(2 ** (8 * w))
        wide = rng.choice([4, 8]) if w == 2 else 8
        return ('f', wide, widen_bits(w, b, wide))
    special_bits = [0x7ff8000000000000, 0xfff8000000000001, 0x7ff0000000000001, 0x7ff4000000000000,
                    0x7ff0000020000000, 0x7ff0040000000000, 0x0000000000000001, 0x8000000000000000,
                    0x3ff0000000000000, 0x47efffffe0000000, 0x47efffffffffffff, 0x3e70000000000000,
                    0x3e6ffffffffffffe, 0x36a0000000000000, 0x380fffffc0000000, 0x40effc0000000000]
    return ('f', 8, rng.choice(special_bits))


def split(rng, seq):
    cuts = sorted(rng.sample(range(len(seq) + 1), min(len(seq) + 1, rng.randrange(0, 4))))
    pieces, last = [], 0
    for c in cuts + [len(seq)]:
        pieces.append(seq[last:c])
        last = c
    return [p for p in pieces if p or rng.random() < 0.3]


def gen(rng, depth=0, keys_plain=False, max_depth=6):
    r = rng.random()
    if depth >= max_depth:
        r = r * 0.6
    if r < 0.12:
        return ('u', rand_arg(rng))
    if r < 0.2:
        return ('n', rand_arg(rng))
    if r < 0.28:
        data = bytes(rng.randrange(256) for _ in range(rng.choice([0, 1, 2, 3, 5, 24, 30, 300])))
        return ('b', data, split(rng, data) if rng.random() < 0.2 else None)
    if r < 0.4:
        s = rand_text(rng, rng.choice([0, 1, 2, 4, 9, 30]))
        return ('t', s, split(rng, s) if rng.random() < 0.2 else None)
    if r < 0.48:
        return ('s', rng.choice([20, 21, 22, 23, 0, 7, 19, 32, 100, 255]))
    if r < 0.6:
        return rand_float(rng)
    if r < 0.75:
        return ('a', [gen(rng, depth + 1, keys_plain, max_depth) for _ in range(rng.choice([0, 1, 2, 3, 5, 25]))], rng.random() < 0.2)
    if r < 0.92:
        n = rng.choice([0, 1, 2, 3, 6])
        pairs = []
        for _ in range(n):
            if keys_plain:
                key = rng.choice([('t', rand_text(rng, rng.randrange(4)), None), ('u', rand_arg(rng)), ('n', rng.randrange(30))])
            else:
                key = gen(rng, depth + 1, keys_plain, max_depth) if rng.random() < 0.3 else rng.choice(
                    [('t', rand_text(rng, rng.randrange(3)), None), ('u', rng.randrange(30)), ('n', rng.randrange(5)), ('f', 2, 0x3c00), ('f', 8, 0x3ff0000000000000)])
            pairs.append((key, gen(rng, depth + 1, keys_plain, max_depth)))
        if pairs and rng.random() < 0.1:
            pairs.append((pairs[0][0], ('u', 0)))
        return ('m', pairs, rng.random() < 0.2)
    return ('tag', rng.choice([0, 1, 2, 23, 24, 32, 55799, rand_arg(rng)]), gen(rng, depth + 1, keys_plain, max_depth))


def widener(rng, rate):
    def w(arg):
        if rng.random() >= rate:
            return None
        need = 0 if arg < 24 else 1 if arg < 256 else 2 if arg < 65536 else 4 if arg < 2 ** 32 else 8
        options = [x for x in (1, 2, 4, 8) if x > need]
        return rng.choice(options) if options else None
    return w


# ---------------------------------------------------------------- driving
def batch(exe, mode, lines, chunk=4096, depth=128, items=1000000, strings=16777216):
    data = ''.join(x.hex() + '\n' for x in lines).encode()
    proc = subprocess.run([exe, mode, str(chunk), str(depth), str(items), str(strings)], input=data, capture_output=True, timeout=240)
    if proc.returncode != 0:
        raise SystemExit('batch %s exited %d: %r' % (mode, proc.returncode, proc.stderr[:200]))
    out = proc.stdout.decode().split('\n')
    assert out[-1] == '' and len(out) == len(lines) + 1, (len(out), len(lines))
    return out[:-1]


def expect_copy(data, **limits):
    status, m = python_outcome(data, **limits)
    return encode(m).hex() if status == 'ok' else status


def expect_canon(data):
    status, m = python_outcome(data, canon=True)
    return canonical(m).hex() if status == 'ok' else status


def expect_check(data):
    status, m = python_outcome(data, det=True)
    if status == 'ok':
        # Self-consistency: deterministic input is its own canonical form.
        assert canonical(m) == data, data.hex()
        return 'ok'
    return status


def strip_writer_offset(line):
    return ' '.join(line.split(' ')[:2]) if line.startswith('werror ') else line


CHUNKS = (1, 3, 7, 4096)


def compare(exe, lines, report):
    """Runs copy, canon and check at every chunk size; returns per-mode counts."""
    expected = {
        'copy': [expect_copy(x) for x in lines],
        'canon': [expect_canon(x) for x in lines],
        'check': [expect_check(x) for x in lines],
    }
    agree = {}
    for mode in ('copy', 'canon', 'check'):
        good = 0
        for chunk in CHUNKS:
            got = batch(exe, mode, lines, chunk)
            for data, want, have in zip(lines, expected[mode], got):
                if strip_writer_offset(have) == want:
                    good += 1
                elif len(report) < 10:
                    report.append((mode, chunk, data.hex()[:120], want[:80], have[:80]))
        agree[mode] = good
    return expected, agree


def group_appendix(exe, json_exe):
    report, python_ok = [], 0
    lines = [bytes.fromhex(h) for _, h in APPENDIX_A]
    for expected_value, h in APPENDIX_A:
        status, m = python_outcome(bytes.fromhex(h))
        if status == 'ok' and same(value(m), expected_value) and encode(m).hex() == h:
            python_ok += 1
        else:
            report.append(('python', h, status, repr(expected_value)))
    expected, agree = compare(exe, lines, report)
    deterministic = sum(1 for e in expected['check'] if e == 'ok')
    json_ok = run_json(json_exe, lines, report)[0] if json_exe else 0
    n = len(lines)
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    print('cbor-appendix cases=%d python=%d copy=%d/%d canon=%d/%d check=%d/%d deterministic=%d json=%d' % (
        n, python_ok, agree['copy'], n * len(CHUNKS), agree['canon'], n * len(CHUNKS), agree['check'], n * len(CHUNKS), deterministic, json_ok))


def group_generated(exe, count=1500):
    rng = random.Random(8949)
    report, models, lines = [], [], []
    for i in range(count):
        m = gen(rng)
        models.append(m)
        lines.append(encode(m, widener(rng, 0.15) if i % 3 == 0 else None))
    expected, agree = compare(exe, lines, report)
    # Independent round trips: Python decodes the Lanius output.
    copies = batch(exe, 'copy', lines, 5)
    canons = batch(exe, 'canon', lines, 5)
    round_trip = 0
    for m, c, k in zip(models, copies, canons):
        ok = same(value(python_outcome(bytes.fromhex(c))[1]), value(m))
        if k.startswith('werror DuplicateKey'):
            ok = ok and expect_canon(encode(m)).startswith('werror DuplicateKey')
        else:
            status, back = python_outcome(bytes.fromhex(k), det=True)
            ok = ok and status == 'ok' and canonical(back) == bytes.fromhex(k)
        round_trip += ok
    duplicates = sum(1 for e in expected['canon'] if e.startswith('werror'))
    deterministic = sum(1 for e in expected['check'] if e == 'ok')
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    n = count * len(CHUNKS)
    print('cbor-generated cases=%d copy=%d/%d canon=%d/%d check=%d/%d roundtrip=%d duplicates=%d deterministic=%d' % (
        count, agree['copy'], n, agree['canon'], n, agree['check'], n, round_trip, duplicates, deterministic))


def mutate(rng, data):
    data = bytearray(data)
    for _ in range(rng.choice([1, 1, 2, 3])):
        r = rng.random()
        if r < 0.3 and data:
            data[rng.randrange(len(data))] = rng.randrange(256)
        elif r < 0.5 and data:
            i = rng.randrange(len(data))
            data[i] ^= 1 << rng.randrange(8)
        elif r < 0.7:
            del data[rng.randrange(len(data) + 1):]
        elif r < 0.85:
            data.insert(rng.randrange(len(data) + 1), rng.choice([0xff, 0x1f, 0x5f, 0x7f, 0x9f, 0xbf, 0xf8, 0x1c, rng.randrange(256)]))
        elif data:
            del data[rng.randrange(len(data))]
    return bytes(data)


def group_mutations(exe, count=3000):
    rng = random.Random(7049)
    report, lines = [], []
    seeds = [encode(gen(rng, max_depth=4)) for _ in range(400)] + [bytes.fromhex(h) for _, h in APPENDIX_A]
    while len(lines) < count:
        lines.append(mutate(rng, rng.choice(seeds)))
    expected, agree = compare(exe, lines, report)
    rejected = sum(1 for e in expected['copy'] if e.startswith('error'))
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    n = count * len(CHUNKS)
    print('cbor-mutations cases=%d copy=%d/%d canon=%d/%d check=%d/%d rejected=%d' % (
        count, agree['copy'], n, agree['canon'], n, agree['check'], n, rejected))


def group_limits(exe, count=1200):
    rng = random.Random(4242)
    report, good, rejected, cases = [], 0, 0, 0
    settings = [(0, 1000000, 16777216), (1, 1000000, 16777216), (3, 1000000, 16777216), (128, 1, 16777216),
                (128, 5, 16777216), (128, 30, 16777216), (128, 1000000, 0), (128, 1000000, 3), (2, 10, 4)]
    for depth, items, strings in settings:
        lines = [encode(gen(rng, max_depth=5)) for _ in range(count // len(settings))]
        want = [expect_copy(x, max_depth=depth, max_items=items, max_string=strings) for x in lines]
        for chunk in (1, 4096):
            got = batch(exe, 'copy', lines, chunk, depth, items, strings)
            for data, w, g in zip(lines, want, got):
                cases += 1
                if w == g:
                    good += 1
                elif len(report) < 10:
                    report.append((depth, items, strings, chunk, data.hex()[:100], w[:60], g[:60]))
        rejected += sum(1 for w in want if w.startswith('error'))
    # Deep nesting at the default depth limit.
    deep = [b'\x81' * n + b'\x00' for n in (127, 128, 129, 300)] + [b'\x9f' * 128 + b'\xff' * 128, b'\xc1' * 129 + b'\x00']
    want = [expect_copy(x) for x in deep]
    got = batch(exe, 'copy', deep, 4096)
    cases += len(deep)
    good += sum(1 for w, g in zip(want, got) if w == g)
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    print('cbor-limits cases=%d agree=%d rejected=%d' % (cases, good, rejected))


def group_sequences(exe, count=600):
    rng = random.Random(8742)
    lines = []
    for _ in range(count):
        parts = [encode(gen(rng, max_depth=3)) for _ in range(rng.randrange(0, 5))]
        data = b''.join(parts)
        if rng.random() < 0.25:
            data = mutate(rng, data)
        lines.append(data)
    good, report = 0, []
    want = []
    for x in lines:
        try:
            want.append('roots %d' % Decoder(x).sequence())
        except CErr as e:
            want.append('error %s %d' % (e.kind, e.offset))
    for chunk in (1, 4096):
        got = batch(exe, 'seq', lines, chunk)
        for data, w, g in zip(lines, want, got):
            if w == g:
                good += 1
            elif len(report) < 10:
                report.append((chunk, data.hex()[:100], w, g))
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    print('cbor-sequences cases=%d agree=%d rejected=%d' % (count * 2, good, sum(1 for w in want if w.startswith('error'))))


def python_offsets(data):
    d = Decoder(data)
    m = d.one()
    return d.offsets, m


def run_json(json_exe, lines, report):
    """Runs the sample once per input; returns (agree, converted, unsupported, invalid)."""
    good, kinds = 0, {'converted': 0, 'unsupported': 0, 'invalid': 0}
    for data in lines:
        status, _ = python_outcome(data, json_keys=True)
        proc = subprocess.run([json_exe], input=data, capture_output=True, timeout=20)
        if status != 'ok':
            kind = 'unsupported' if 'UnsupportedKey' in status else 'invalid'
            ok = proc.returncode == 2 and proc.stdout == b'' and proc.stderr.decode() == 'cbor-to-json: %s at %s\n' % tuple(status.split(' ')[1:])
        else:
            offsets, m = python_offsets(data)
            want = to_json(m, offsets)  # Unsupported here would be an oracle bug.
            kind = 'converted'
            ok = proc.returncode == 0 and proc.stderr == b'' and proc.stdout.endswith(b'\n') and json_same(want, parse_json(proc.stdout.decode()))
        kinds[kind] += 1
        good += ok
        if not ok and len(report) < 10:
            report.append(('json', data.hex()[:100], status, proc.returncode, proc.stdout[:100], proc.stderr[:100]))
    return good, kinds


def group_json(exe, json_exe, count=400):
    rng = random.Random(6100)
    lines = [encode(gen(rng, keys_plain=(i % 4 != 0), max_depth=4)) for i in range(count)]
    lines += [mutate(rng, x) for x in lines[:100]]
    report = []
    good, kinds = run_json(json_exe, lines, report)
    # --seq: one JSON line per root; --deterministic: reject other encodings.
    flagged = 0
    for i in range(100):
        roots = [gen(rng, keys_plain=True, max_depth=3) for _ in range(rng.randrange(0, 4))]
        data = b''.join(encode(m) if i % 2 else canonical_or_plain(m) for m in roots)
        want_lines = []
        try:
            for m in roots:
                offsets, node = python_offsets(encode(m) if i % 2 else canonical_or_plain(m))
                want_lines.append(to_json(node, offsets))
        except Unsupported:
            continue
        proc = subprocess.run([json_exe, '--seq'], input=data, capture_output=True, timeout=20)
        got = proc.stdout.decode().split('\n')
        ok = proc.returncode == 0 and got[-1] == '' and len(got) == len(want_lines) + 1 and all(
            json_same(w, parse_json(g)) for w, g in zip(want_lines, got))
        if not want_lines:
            ok = proc.returncode == 0 and proc.stdout == b''
        flagged += 1
        good += ok
        if not ok and len(report) < 10:
            report.append(('seq', data.hex()[:100], proc.returncode, proc.stdout[:100], proc.stderr[:100]))
    for i in range(100):
        m = gen(rng, keys_plain=True, max_depth=3)
        data = encode(m) if i % 2 else canonical_or_plain(m)
        status, _ = python_outcome(data, det=True, json_keys=True)
        proc = subprocess.run([json_exe, '--deterministic'], input=data, capture_output=True, timeout=20)
        if status == 'ok':
            offsets, node = python_offsets(data)
            ok = proc.returncode == 0 and json_same(to_json(node, offsets), parse_json(proc.stdout.decode()))
        else:
            ok = proc.returncode == 2 and proc.stderr.decode() == 'cbor-to-json: %s at %s\n' % tuple(status.split(' ')[1:])
        flagged += 1
        good += ok
        if not ok and len(report) < 10:
            report.append(('det', data.hex()[:100], status, proc.returncode, proc.stdout[:100], proc.stderr[:100]))
    for r in report:
        print('MISMATCH', r, file=sys.stderr)
    print('cbor-json cases=%d agree=%d converted=%d unsupported=%d invalid=%d flagged=%d' % (
        len(lines) + flagged, good, kinds['converted'], kinds['unsupported'], kinds['invalid'], flagged))


def canonical_or_plain(m):
    try:
        return canonical(m)
    except Duplicate:
        return encode(m)


def main():
    group, exe = sys.argv[1], sys.argv[2]
    json_exe = sys.argv[3] if len(sys.argv) > 3 else None
    if group == 'appendix':
        group_appendix(exe, json_exe)
    elif group == 'generated':
        group_generated(exe)
    elif group == 'mutations':
        group_mutations(exe)
    elif group == 'limits':
        group_limits(exe)
    elif group == 'sequences':
        group_sequences(exe)
    elif group == 'json':
        group_json(exe, json_exe)
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
