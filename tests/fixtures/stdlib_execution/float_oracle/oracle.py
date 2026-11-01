"""Python float()/repr() oracle for core::float_decimal (Eisel-Lemire, Grisu3,
exact big-integer fallback) through float_batch.lani.

usage: oracle.py GROUP EXECUTABLE [COUNT]
GROUP: parse64, parse32, format64, format32

parse64 compares bits with float(text). parse32 rounds float(text) to binary32
and resolves the only double-rounding hazard (a double exactly on a binary32
midpoint) with exact rational arithmetic. format64 compares shortest digits
and exponent with repr(x) and requires float(output) to return x. format32
uses an exact rational model of shortest, closest, ties-to-even-coefficient.
"""
import random
import struct
import subprocess
import sys
from fractions import Fraction

MAX64 = (1 << 64) - 1


def d_of(bits):
    return struct.unpack('<d', struct.pack('<Q', bits))[0]


def b_of(x):
    return struct.unpack('<Q', struct.pack('<d', x))[0]


def f32_of(bits):
    return struct.unpack('<f', struct.pack('<I', bits))[0]


def round32(text):
    """Correctly rounded binary32 bits of a decimal string."""
    d = float(text)
    try:
        bits = struct.unpack('<I', struct.pack('<f', d))[0]
    except OverflowError:
        bits = 0x7f800000 | (0x80000000 if d < 0 else 0)
        return bits
    db = b_of(d) & ~(1 << 63)
    exponent = db >> 52
    # Binary32 midpoints: normal f32 needs 24 bits, so bit 28 set and bits 0..27
    # clear in the double mantissa; also subnormal midpoints, checked exactly.
    if d != 0 and abs(d) < 3.5e38:
        exact = Fraction(text)
        low = bits & 0x7fffffff
        cand = [low - 1, low, low + 1] if low > 0 else [low, low + 1]
        best = None
        for c in cand:
            if c < 0 or c > 0x7f800000:
                continue
            v = abs(Fraction(f32_of(c))) if c < 0x7f800000 else Fraction(2) ** 128
            dist = abs(abs(exact) - v)
            key = (dist, c & 1)
            if best is None or key < best[0]:
                best = (key, c)
        sign = 0x80000000 if d < 0 else 0
        return best[1] | sign
    return bits


def run(exe, mode, lines):
    data = ('\n'.join(lines) + '\n').encode()
    proc = subprocess.run([exe, mode], input=data, capture_output=True, timeout=280)
    assert proc.returncode == 0 and not proc.stderr, (proc.returncode, proc.stderr[:200])
    out = proc.stdout.decode().split('\n')
    assert out[-1] == '' and len(out) == len(lines) + 1, (len(out), len(lines))
    return out[:-1]


def digits_of(text):
    """(coefficient, exponent) without trailing zeros, sign ignored."""
    text = text.lstrip('-')
    mantissa, _, exp = text.partition('e')
    exp = int(exp) if exp else 0
    whole, _, frac = mantissa.partition('.')
    coefficient = int((whole + frac).lstrip('0') or '0')
    exp -= len(frac)
    if coefficient == 0:
        return 0, 0
    while coefficient % 10 == 0:
        coefficient //= 10
        exp += 1
    return coefficient, exp


def random_double_bits(rng):
    kind = rng.randrange(8)
    if kind == 0:
        return rng.getrandbits(52)  # subnormal (or zero)
    if kind == 1:
        return (rng.randrange(1, 2047) << 52)  # power of two
    if kind == 2:
        return (rng.randrange(1, 2047) << 52) | ((1 << 52) - 1 - rng.randrange(4))
    if kind == 3:
        return rng.choice([1, 2, 3, (1 << 52) - 1, 1 << 52, (1 << 52) + 1, 0x7fefffffffffffff, 0x7feffffffffffffe,
                           0x44b52d02c7e14af6, 0x44b52d02c7e14af7, 0x3fb999999999999a, 0x3ff0000000000000])
    return rng.getrandbits(63) % 0x7ff0000000000000


def exact_decimal(value):
    """Exact decimal spelling of a dyadic Fraction."""
    numerator, denominator = value.numerator, value.denominator
    scale = 0
    while denominator % 10 == 0:
        denominator //= 10
        scale += 1
    k = 0
    while denominator != 1:
        if denominator % 2 == 0:
            denominator //= 2
            numerator *= 5
        else:
            denominator //= 5
            numerator *= 2
        k += 1
    return '%de-%d' % (numerator, k + scale)


def parse_inputs(rng, count, single):
    lines = []
    fraction_bits, top = (23, 0x7f800000) if single else (52, 0x7ff0000000000000)
    while len(lines) < count:
        # Weights: 40% printed binary values, 30% w*10^q, 1% exact midpoints,
        # 4% long digit strings, 5% fixed extremes, 20% plain decimals.
        kind = rng.randrange(100)
        sign = '-' if rng.random() < 0.2 else ''
        if kind < 40:
            if single:
                b = rng.getrandbits(31) % top
                x = f32_of(b)
                lines.append(sign + ('%.*g' % (rng.choice([6, 8, 9, 12]), x)))
            else:
                x = d_of(random_double_bits(rng))
                lines.append(sign + rng.choice([repr(x), '%.17e' % x, '%.15g' % x, '%.25e' % x]))
        elif kind < 70:
            w = rng.randrange(1, 10 ** rng.randrange(1, 20))
            q = rng.randrange(-60, 50) if single else rng.randrange(-360, 330)
            lines.append('%s%de%d' % (sign, w, q))
        elif kind == 70:
            # Exact midpoint between adjacent binary values, and its neighbours.
            b = rng.getrandbits(31) % (top - 1) if single else random_double_bits(rng) % (top - 1)
            lo = Fraction(f32_of(b)) if single else Fraction(d_of(b))
            hi = Fraction(f32_of(b + 1)) if single else Fraction(d_of(b + 1))
            mid = exact_decimal((lo + hi) / 2)
            m, _, e = mid.partition('e')
            if len(m) > 760:
                continue
            tweak = rng.randrange(3)
            if tweak == 1:
                m = str(int(m) + 1)
            elif tweak == 2:
                m = str(int(m) - 1)
            lines.append(sign + m + 'e' + e)
        elif kind < 75:
            # Many digits: a fallback-path decimal near a random value.
            digits = ''.join(rng.choice('0123456789') for _ in range(rng.randrange(20, 120)))
            lines.append('%s0.%se%d' % (sign, digits, rng.randrange(-45, 39) if single else rng.randrange(-330, 310)))
        elif kind < 80:
            lines.append(sign + rng.choice(['0', '0.0', '1e-400', '1e400', '4.9e-324', '2.4703282292062327e-324',
                                            '2.4703282292062328e-324', '1.7976931348623157e308', '1.7976931348623158e308',
                                            '1.7976931348623159e308', '2.2250738585072011e-308', '2.2250738585072012e-308',
                                            '3.4028235e38', '3.4028236e38', '1.4e-45', '7.0064923e-46', '7.006492321624086e-46',
                                            '1.17549435e-38', '9007199254740993', '1e23', '8.589973e9', '0.1', '123456789012345678901234']))
        else:
            ip = str(rng.randrange(10 ** rng.randrange(0, 12)))
            fp = ''.join(rng.choice('0123456789') for _ in range(rng.randrange(0, 12)))
            lines.append(sign + ip + ('.' + fp if fp else '') + rng.choice(['', 'e%d' % rng.randrange(-30, 30), 'E+5']))
    return lines


def model_shortest32(bits):
    """Shortest closest decimal for binary32 bits (positive finite nonzero)."""
    x = Fraction(f32_of(bits))
    lower = Fraction(f32_of(bits - 1)) if bits > 0 else -x
    upper = Fraction(f32_of(bits + 1)) if bits + 1 < 0x7f800000 else Fraction(2) ** 128
    low_b, high_b = (x + lower) / 2, (x + upper) / 2
    inclusive = bits % 2 == 0
    for p in range(1, 10):
        text = '%.*e' % (p - 1, float(x))
        c, e = digits_of(text)
        mant, _, ex = text.partition('e')
        unit_exp = int(ex) - (p - 1)
        base = int(mant.replace('.', ''))
        found = []
        for cand in (base - 1, base, base + 1):
            if cand <= 0:
                continue
            v = Fraction(cand) * Fraction(10) ** unit_exp
            ok = (low_b < v < high_b) or (inclusive and (v == low_b or v == high_b))
            if ok:
                found.append((abs(v - x), cand % 2, cand))
        if found:
            found.sort()
            cand = found[0][2]
            return digits_of('%de%d' % (cand, unit_exp))
    raise AssertionError(bits)


def main():
    group, exe = sys.argv[1], sys.argv[2]
    count = int(sys.argv[3]) if len(sys.argv) > 3 else {'parse64': 2000000, 'format64': 2000000,
                                                           'parse32': 500000, 'format32': 300000}[group]
    rng = random.Random(1074 + sum(map(ord, group)))
    mismatches = []
    agree = 0
    if group in ('parse64', 'parse32'):
        single = group == 'parse32'
        lines = parse_inputs(rng, count, single)
        got = run(exe, 'p32' if single else 'p64', lines)
        for text, out in zip(lines, got):
            want = '%08x' % round32(text) if single else '%016x' % b_of(float(text))
            if out == want:
                agree += 1
            else:
                mismatches.append((text[:80], want, out))
    elif group == 'format64':
        bits = [random_double_bits(rng) | (rng.getrandbits(1) << 63) for _ in range(count)]
        got = run(exe, 'f64', ['%016x' % b for b in bits])
        for b, out in zip(bits, got):
            x = d_of(b)
            ok = float(out) == x and (b_of(float(out)) == b) and digits_of(out) == digits_of(repr(x))
            if ok:
                agree += 1
            else:
                mismatches.append(('%016x' % b, repr(x), out))
    elif group == 'format32':
        bits = []
        while len(bits) < count:
            kind = rng.randrange(5)
            if kind == 0:
                b = rng.getrandbits(23) or 1
            elif kind == 1:
                b = rng.randrange(1, 255) << 23
            elif kind == 2:
                b = rng.choice([1, 2, 0x7f7fffff, 0x7f7ffffe, 0x00800000, 0x007fffff, 0x3dcccccd, 0x3f800000])
            else:
                b = rng.getrandbits(31) % 0x7f800000 or 1
            bits.append(b)
        got = run(exe, 'f32', ['%08x' % b for b in bits])
        for b, out in zip(bits, got):
            want = model_shortest32(b)
            ok = digits_of(out) == want and round32(out) == b
            if ok:
                agree += 1
            else:
                mismatches.append(('%08x' % b, want, out))
    else:
        raise SystemExit('unknown group ' + group)
    print('float-%s cases=%d agree=%d' % (group, count, agree))
    for m in mismatches[:20]:
        print('MISMATCH', m, file=sys.stderr)
    return 0 if not mismatches else 1


if __name__ == '__main__':
    sys.exit(main())
