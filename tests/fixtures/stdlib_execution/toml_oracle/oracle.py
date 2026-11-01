"""Python tomllib oracle for ext::toml through sample_programs/library/toml_normalize.lani.

Accepted input: tomllib.loads(program output) must equal tomllib.loads(input),
compared in order with exact types, float sign/NaN and datetime spelling, and
normalizing the output again must reproduce it byte for byte. Rejected input:
the program exits 2 with a `toml-error` diagnostic. tomllib implements TOML
1.0.0; ext::toml implements 1.1.0, so documents using only-1.1 syntax are
counted separately (expected accept by ext::toml, reject by tomllib).

usage: oracle.py GROUP EXECUTABLE   (GROUP: edge, generated, mutations)
"""
import datetime
import math
import random
import re
import subprocess
import sys
import tomllib


def run(exe, data):
    proc = subprocess.run([exe], input=data, capture_output=True, timeout=20)
    return proc.returncode, proc.stdout, proc.stderr


def reference(data):
    try:
        return True, tomllib.loads(data.decode('utf-8'))
    except (tomllib.TOMLDecodeError, UnicodeDecodeError, ValueError):
        return False, None


def same(a, b):
    if type(a) is not type(b):
        return False
    if isinstance(a, dict):
        return list(a) == list(b) and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, float):
        if math.isnan(a):
            return math.isnan(b)
        return a == b and math.copysign(1, a) == math.copysign(1, b)
    if isinstance(a, (datetime.datetime, datetime.time)):
        return a.isoformat() == b.isoformat() and a.utcoffset() == b.utcoffset() if isinstance(a, datetime.datetime) else a.isoformat() == b.isoformat()
    return a == b


def outside_i64(value):
    if isinstance(value, bool):
        return False
    if isinstance(value, int):
        return not -2 ** 63 <= value < 2 ** 63
    if isinstance(value, dict):
        return any(outside_i64(v) for v in value.values())
    if isinstance(value, list):
        return any(outside_i64(v) for v in value)
    return False


TOML11 = re.compile(rb'\\e|\\x[0-9a-fA-F]{2}|(?<![:\d])\d\d:\d\d(?![:\d])|\{[^}\n]*\n|,\s*\}')


class Tally:
    def __init__(self, group):
        self.group, self.cases, self.agree, self.accepted, self.rejected, self.toml11, self.failures = group, 0, 0, 0, 0, 0, []
        self.int_range = 0

    def check(self, exe, name, data, expect=None):
        valid, value = reference(data)
        code, out, err = run(exe, data)
        self.cases += 1
        if expect == '1.1':
            # Valid TOML 1.1, invalid 1.0: tomllib must reject, ext::toml accept.
            self.toml11 += 1
            ok = not valid and code == 0
            if ok:
                second = run(exe, out)
                ok = second[0] == 0 and second[1] == out
        elif valid and code == 2 and b'kind=number out of range ' in err and outside_i64(value):
            # tomllib keeps unbounded Python ints; TOML 1.0 requires an error for
            # integers that cannot be represented losslessly in 64 bits.
            self.int_range += 1
            ok = True
        elif valid:
            self.accepted += 1
            ok = code == 0 and err == b''
            if ok:
                back_ok, back = reference(out)
                ok = back_ok and same(value, back)
            if ok:
                second = run(exe, out)
                ok = second[0] == 0 and second[1] == out
        else:
            self.rejected += 1
            ok = code == 2 and out == b'' and (err.startswith(b'toml-normalize: toml-error stage=parse kind=') or
                                                err.startswith(b'toml-normalize: invalid-utf8 stage=input byte='))
            if not ok and expect is None and code == 0 and TOML11.search(data):
                self.toml11 += 1
                self.rejected -= 1
                ok = True
        if expect is not None and expect not in ('1.1', 'valid', 'invalid'):
            ok = ok and (b'kind=' + expect.encode() + b' ') in err
        if expect == 'valid' and not valid:
            ok = False
        if expect not in (None, 'valid', '1.1', 'number out of range') and valid:
            ok = False
        if ok:
            self.agree += 1
        else:
            self.failures.append((name, data[:160], valid, code, out[:200], err[:200]))

    def finish(self):
        print('toml-%s cases=%d agree=%d accepted=%d rejected=%d toml11_only=%d int64_only=%d' % (
            self.group, self.cases, self.agree, self.accepted, self.rejected, self.toml11, self.int_range))
        for f in self.failures[:20]:
            print('MISMATCH', f, file=sys.stderr)
        return 0 if not self.failures else 1


V, I = 'valid', 'invalid'
EDGE = [
    # dotted keys
    (b'a.b.c = 1\na.b.d = 2\n', V), (b'a . b = 1\n', V), (b'"a.b" = 1\na.b = 2\n', V), (b"site.'google.com' = true\n", V),
    (b'a.b = 1\na.b = 2\n', 'duplicate key'), (b'a = 1\na.b = 2\n', I), (b'a.b = 1\n[a]\nc = 2\n', I),
    (b'[a]\nb.c = 1\n[a.b]\nd = 2\n', I), (b'[a.b]\nc = 1\n[a]\nb.d = 2\n', I), (b'a.b.c = 1\n[a.b]\n', I),
    (b'[x]\ny.z = 1\n[x.w]\n', V), (b'fruit.apple.color = "red"\nfruit.apple.taste.sweet = true\n', V),
    (b'3.14159 = "pi"\n', V), (b'1234 = 1\n-_- = 2\n', V), (b'"" = 1\n', V), (b"'' = 1\n", V), (b'= 1\n', I),
    (b'a."b.c".d = 1\n', V), (b'a.\n', I), (b'.a = 1\n', I), (b'a..b = 1\n', I), (b'"\\u00e9" = 1\n\xc3\xa9x = 2\n', I),
    (b'"\\u0061" = 1\na = 2\n', 'duplicate key'), (b"'a' = 1\n\"a\" = 2\n", 'duplicate key'),
    # inline tables
    (b'p = { x = 1, y = 2 }\n', V), (b'p = {}\n', V), (b'p = { a.b = 1, a.c = 2 }\n', V), (b'p = { x = 1, x = 2 }\n', 'duplicate key'),
    (b'p = { x = 1 }\np.y = 2\n', I), (b'p = { x = 1 }\n[p]\n', I), (b'p = { x = 1 }\n[p.q]\n', I),
    (b'p = { x = { y = 1 } }\n', V), (b'p = { x = [1, { z = 2 }] }\n', V), (b'p = { x = 1, }\n', '1.1'),
    (b'p = {\n x = 1 }\n', '1.1'), (b'p = { x = 1 y = 2 }\n', I), (b'p = { x }\n', I), (b'[t]\np = { a = 1 }\n[t.p.b]\n', I),
    # arrays and arrays of tables
    (b'a = [1, 2, 3]\n', V), (b'a = [1, "x", 2.0, [true], {k = 1}]\n', V), (b'a = [\n 1,\n 2, # c\n]\n', V), (b'a = []\n', V),
    (b'a = [,]\n', I), (b'a = [1,,2]\n', I), (b'a = [1 2]\n', I),
    (b'[[f]]\nn = 1\n[[f]]\nn = 2\n', V), (b'[[f]]\n[f.sub]\nx = 1\n[[f.v]]\ny = 1\n[[f]]\n', V),
    (b'[[f]]\n[[f.v]]\n[f.v.w]\n', V), (b'a = []\n[[a]]\n', I), (b'a = [1]\n[[a]]\n', I), (b'[a]\n[[a]]\n', I),
    (b'[[a]]\n[a]\n', I), (b'a = 1\n[[a]]\n', I), (b'[[a.b]]\n[a]\nc = 1\n', V), (b'[[a]]\nb = 1\n[a.b]\n', I),
    (b'[ [a] ]\n', I), (b'[[a] ]\n', I), (b'[[ a ]]\n', V), (b'[ a . b ]\n', V),
    # table redefinition
    (b'[a]\n[a]\n', 'table redefinition'), (b'[a]\nb = 1\n[a.b]\n', I), (b'[a.b]\n[a]\n', V), (b'[a.b]\n[a]\n[a]\n', I),
    (b'[a]\nb.c = 1\n[a.b.d]\n', V), (b'[a]\nx = 1\n[b]\n[a]\n', I), (b'[]\n', I), (b'[a\n', I), (b'[a]]\n', I),
    (b'[a]\n\n[a.b]\nc = 1\n[a.b]\n', I),
    # date-times
    (b'd = 1979-05-27T07:32:00Z\n', V), (b'd = 1979-05-27T00:32:00-07:00\n', V), (b'd = 1979-05-27T00:32:00.999999-07:00\n', V),
    (b'd = 1979-05-27 07:32:00Z\n', V), (b'd = 1979-05-27t07:32:00z\n', V), (b'd = 1979-05-27T07:32:00\n', V),
    (b'd = 1979-05-27\n', V), (b'd = 07:32:00\n', V), (b'd = 00:32:00.999999\n', V), (b'd = 1979-05-27T07:32:00.123456789Z\n', V),
    (b'd = 2000-02-29\n', V), (b'd = 1900-02-29\n', I), (b'd = 2001-02-29\n', I), (b'd = 1979-13-01\n', I),
    (b'd = 1979-05-32\n', I), (b'd = 1979-05-27T24:00:00\n', I), (b'd = 1979-05-27T07:60:00\n', I),
    (b'd = 1979-5-27\n', I), (b'd = 1979-05-27T07:32:00+25:00\n', I), (b'd = 1979-05-27T07:32\n', '1.1'), (b't = 07:32\n', '1.1'),
    (b'd = 1979-05-27T07:32:00.Z\n', I), (b'd = 1979-05-27T\n', I), (b'd = 0001-01-01T00:00:00Z\n', V),
    (b'd = 9999-12-31T23:59:59.999999+23:59\n', V), (b'd = [1979-05-27, 07:32:00, 1979-05-27T07:32:00Z]\n', V),
    # numbers
    (b'i = +99\nj = -17\nk = 0\nl = 1_000\nm = 5_349_221\n', V), (b'h = 0xDEADBEEF\no = 0o755\nb = 0b1101\n', V),
    (b'i = 9223372036854775807\nj = -9223372036854775808\n', V), (b'i = 9223372036854775808\n', 'number out of range'),
    (b'i = 01\n', I), (b'i = 1__0\n', I), (b'i = _1\n', I), (b'i = 1_\n', I), (b'i = +0x1\n', I), (b'i = 0X1\n', I),
    (b'f = 3.1415\ng = -0.01\nh = 5e+22\ni = 1e06\nj = -2E-2\nk = 6.626e-34\nl = 224_617.445_991\n', V),
    (b'f = -0.0\ng = +0.0\nh = inf\ni = -inf\nj = nan\nk = +nan\nl = -nan\n', V), (b'f = .7\n', I), (b'f = 7.\n', I),
    (b'f = 3.e+20\n', I), (b'f = 1e\n', I), (b'f = 1.5e400\n', V), (b'f = 4.9e-325\n', V), (b'f = Inf\n', I),
    (b'f = 0.1e1_0\n', V), (b'f = 1_000.0_1\n', V), (b'f = 00.1\n', I),
    # strings
    (b's = "tab\\there \\"q\\" \\\\ \\u00e9 \\U0001F600"\n', V), (b"s = 'C:\\\\Users'\n", V), (b's = """\nline1\nline2"""\n', V),
    (b's = """a \\\n   b"""\n', V), (b"s = '''\nraw \\n'''\n", V), (b's = """""quote""""" \n', V), (b's = """"""""\n', V), (b's = """"""""""\n', I),
    (b's = "\\ud800"\n', I), (b's = "\\U00110000"\n', I), (b's = "\\q"\n', I), (b's = "a\x01b"\n', I), (b's = "a\tb"\n', V),
    (b's = "\\e"\n', '1.1'), (b's = "\\x41"\n', '1.1'), (b's = "unterminated\n', I), (b's = "a\nb"\n', I),
    (b's = "\x7f"\n', I), (b"s = 'a\x7f'\n", I), (b's = "\xc3\xa9\xf0\x9f\x98\x80"\n', V), (b's = "\xc3"\n', I),
    (b's = "\xed\xa0\x80"\n', I), (b's = """a\r\nb"""\n', V), (b's = "a"\r\n', V), (b's = "a"\r', I),
    # comments, whitespace, misc
    (b'# comment\na = 1 # trailing\n', V), (b'a = 1 # \x01\n', I), (b'a = 1\n\n\t\n', V), (b'a = true\nb = false\n', V),
    (b'a = True\n', I), (b'a = 1 b = 2\n', I), (b'a = \n', I), (b'a\n', I), (b'', V), (b'\xef\xbb\xbfa = 1\n', I),
    (b'a = 1\x00\n', I), (b'[a]\n# x\n  b = 1\n', V),
]


def gen_key(rng):
    k = rng.randrange(10)
    if k < 6:
        return rng.choice(['a', 'b', 'name', 'x_1', 'k-2', '42', 'Zz'])
    if k < 8:
        return '"' + rng.choice(['sp ace', 'dot.ted', '\\u00e9t\\u00e9', 'q\\"', '']) + '"'
    return "'" + rng.choice(['lit', 'a.b', 'w s']) + "'"


def gen_scalar(rng):
    k = rng.randrange(16)
    if k == 0:
        return str(rng.randrange(-10 ** 18, 10 ** 18))
    if k == 1:
        return rng.choice(['0x' + format(rng.randrange(1 << 62), 'X'), '0o' + format(rng.randrange(1 << 40), 'o'),
                           '0b' + format(rng.randrange(1 << 20), 'b'), '1_000_000', '+7', '-9223372036854775808'])
    if k == 2:
        return rng.choice(['%.17g' % rng.uniform(-1e9, 1e9), '1e%d' % rng.randrange(-300, 300), '-0.0', 'inf', '-inf', 'nan',
                           '6.02214076e23', '%.3f' % rng.random(), '5e-324', '1.7976931348623157e308', '2.5E-3'])
    if k == 3:
        return rng.choice(['true', 'false'])
    if k in (4, 5, 6):
        body = ''.join(rng.choice(['a', ' ', '\\t', '\\n', '\\"', '\\\\', '\\u00e9', '\\U0001F600', '\u4e2d', '#', '=', "'"])
                       for _ in range(rng.randrange(0, 6)))
        return '"' + body + '"'
    if k == 7:
        return "'" + ''.join(rng.choice(['a', ' ', '\\', '"', '\u00e9']) for _ in range(rng.randrange(0, 6))) + "'"
    if k == 8:
        return '"""' + rng.choice(['\nfirst\nsecond', 'a \\\n   b', 'q"q""', '']) + '"""'
    if k == 9:
        return "'''" + rng.choice(['\nraw\\n', 'x', "it's"]) + "'''"
    y, mo, d = rng.randrange(1, 10000), rng.randrange(1, 13), rng.randrange(1, 29)
    h, mi, s = rng.randrange(24), rng.randrange(60), rng.randrange(60)
    frac = rng.choice(['', '.5', '.123456', '.999999', '.000001'])
    date, time = '%04d-%02d-%02d' % (y, mo, d), '%02d:%02d:%02d%s' % (h, mi, s, frac)
    off = rng.choice(['Z', 'z', '+00:00', '-07:30', '+14:00', '-00:00'])
    sep = rng.choice(['T', 't', ' '])
    return rng.choice([date + sep + time + off, date + sep + time, date, time])


def gen_value(rng, depth):
    k = rng.randrange(10 if depth < 3 else 7)
    if k < 7:
        return gen_scalar(rng)
    if k < 9:
        items = [gen_value(rng, depth + 1) for _ in range(rng.randrange(0, 4))]
        sep = rng.choice([', ', ',', ',\n  ', ' , '])
        tail = rng.choice(['', ',']) if items else ''
        return '[' + sep.join(items) + tail + ']'
    keys = unique_keys(rng, rng.randrange(0, 4))
    return '{' + ', '.join('%s = %s' % (key, gen_value(rng, depth + 1)) for key in keys) + '}'


def canonical(key):
    if key.startswith('"'):
        return key[1:-1].replace('\\u00e9', '\u00e9').replace('\\"', '"')
    if key.startswith("'"):
        return key[1:-1]
    return key


def unique_keys(rng, count):
    out, seen = [], set()
    while len(out) < count:
        key = gen_key(rng)
        if canonical(key) not in seen:
            seen.add(canonical(key))
            out.append(key)
    return out


def gen_doc(rng):
    lines = []
    root = unique_keys(rng, rng.randrange(1, 8))
    tables = []
    for key in root:
        style = rng.randrange(6)
        if style < 3:
            lines.append('%s = %s' % (key, gen_value(rng, 0)))
        elif style == 3:
            for sub in unique_keys(rng, rng.randrange(1, 3)):
                lines.append('%s.%s = %s' % (key, sub, gen_scalar(rng)))
        else:
            tables.append((key, style))
    for key, style in tables:
        if style == 4:
            lines.append(rng.choice(['', '# section']))
            lines.append('[%s]' % key)
            subs = unique_keys(rng, rng.randrange(0, 4))
            for sub in subs:
                lines.append('%s = %s' % (sub, gen_value(rng, 1)))
            if rng.random() < 0.5:
                inner = gen_key(rng)
                if canonical(inner) not in {canonical(s) for s in subs}:
                    lines.append('[%s.%s]' % (key, inner))
                    lines.append('z = %s' % gen_scalar(rng))
        else:
            for _ in range(rng.randrange(1, 4)):
                lines.append('[[%s]]' % key)
                for sub in unique_keys(rng, rng.randrange(0, 3)):
                    lines.append('%s = %s' % (sub, gen_value(rng, 1)))
    eol = rng.choice(['\n', '\n', '\r\n'])
    return (eol.join(lines) + eol).encode('utf-8')


def mutate(rng, data):
    data = bytearray(data)
    for _ in range(rng.randrange(1, 3)):
        pos = rng.randrange(len(data) + 1)
        byte = rng.choice(b'[]{}=.,"\'#\\ \n0123456789-+:eTZxuabn_\x00\x7f\xc3\xff')
        op = rng.randrange(3)
        if op == 0:
            data.insert(pos, byte)
        elif pos < len(data):
            if op == 1:
                del data[pos]
            else:
                data[pos] = byte
    return bytes(data)


def main():
    group, exe = sys.argv[1], sys.argv[2]
    tally = Tally(group)
    rng = random.Random(2021 + sum(map(ord, group)))
    if group == 'edge':
        for index, (data, expect) in enumerate(EDGE):
            tally.check(exe, 'edge%d' % index, data, expect)
    elif group == 'generated':
        for index in range(600):
            tally.check(exe, 'gen%d' % index, gen_doc(rng))
    elif group == 'mutations':
        for index in range(1000):
            tally.check(exe, 'mut%d' % index, mutate(rng, gen_doc(rng)))
    else:
        raise SystemExit('unknown group ' + group)
    return tally.finish()


if __name__ == '__main__':
    sys.exit(main())
