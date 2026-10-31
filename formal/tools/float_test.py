#!/usr/bin/env python3
"""Differential test of the IEEE specification (Lanius/IEEE.lean) against this CPU.

    python3 -I formal/tools/float_test.py WORKDIR [--count N] [--seed S]

Run from the repository root. For binary32 and binary64, the tool generates
operands: every pair of a list of edge patterns (signed zeros, the least and
greatest subnormals, the least normal, one, the greatest finite value,
infinities, quiet and signaling NaNs with payloads, x86's default NaN), pairs
that round at a tie or next to one, operands a few binades apart (so sums
cancel and carry), and random patterns (N of each kind). Each case runs

  natively   as the SSE instruction the x86 model gives the operation's
             meaning (addss/addsd, subss/subsd, mulss/mulsd, divss/divsd,
             cmpss/cmpsd with predicates 0, 1 and 2 for ==, < and <=,
             cvtsi2ss/cvtsi2sd from 32 and 64 bits, cvtss2sd, cvtsd2ss,
             xorps with the sign bit for negation), in a small stub of machine
             code this tool writes into an executable mapping and calls with
             ctypes, with the default MXCSR (round to nearest, exceptions
             masked, no flush to zero);
  in Lean    the compiled `floatTest` (Lanius/Tools/FloatTest.lean), which
             evaluates the specification's definitions.

The results must be equal bit for bit, NaN payloads and signs included.
Decimal literals (significands of 1 to 40 digits, exponents to +-350, and
known hard cases) are compared with the C library's strtof and strtod, which
round correctly; truncation to integers (Rust's saturating `as`) with exact
integer arithmetic in Python. Prints a summary; exits nonzero on any
difference.
"""

import argparse
import ctypes
import mmap
import os
import random
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402

FLOAT_TEST = os.path.join(run_cache.FORMAL, '.lake/build/bin/floatTest')

FORMATS = {32: (8, 23), 64: (11, 52)}

# --------------------------------------------------------------- native


def stub(w, op):
    """Machine code for op on rdi, rsi (patterns), returning rax."""
    p = 0xF3 if w == 32 else 0xF2
    if w == 32:
        load = bytes([0x66, 0x0F, 0x6E, 0xC7, 0x66, 0x0F, 0x6E, 0xCE])  # movd xmm0, edi; movd xmm1, esi
        out = bytes([0x66, 0x0F, 0x7E, 0xC0])                            # movd eax, xmm0
    else:
        load = bytes([0x66, 0x48, 0x0F, 0x6E, 0xC7, 0x66, 0x48, 0x0F, 0x6E, 0xCE])  # movq xmm0, rdi; movq xmm1, rsi
        out = bytes([0x66, 0x48, 0x0F, 0x7E, 0xC0])                                 # movq rax, xmm0
    ret = bytes([0xC3])
    arith = {'add': 0x58, 'mul': 0x59, 'sub': 0x5C, 'div': 0x5E}
    if op in arith:
        return load + bytes([p, 0x0F, arith[op], 0xC1]) + out + ret
    if op in ('eq', 'lt', 'le'):
        imm = {'eq': 0, 'lt': 1, 'le': 2}[op]
        # cmpss/cmpsd xmm0, xmm1, imm; movd eax, xmm0; and eax, 1
        return load + bytes([p, 0x0F, 0xC2, 0xC1, imm, 0x66, 0x0F, 0x7E, 0xC0, 0x83, 0xE0, 0x01]) + ret
    if op == 'neg':
        # xorps xmm0, xmm1 (rsi holds the sign bit)
        return load + bytes([0x0F, 0x57, 0xC1]) + out + ret
    if op == 'cvt':
        # cvtss2sd / cvtsd2ss xmm0, xmm0, then the other format's move out
        other = bytes([0x66, 0x48, 0x0F, 0x7E, 0xC0]) if w == 32 else bytes([0x66, 0x0F, 0x7E, 0xC0])
        return load + bytes([p, 0x0F, 0x5A, 0xC0]) + other + ret
    if op == 'int32':
        return bytes([p, 0x0F, 0x2A, 0xC7]) + out + ret            # cvtsi2s? xmm0, edi
    if op == 'int64':
        return bytes([p, 0x48, 0x0F, 0x2A, 0xC7]) + out + ret      # cvtsi2s? xmm0, rdi
    raise ValueError(op)


class Native:
    def __init__(self):
        self.code = mmap.mmap(-1, 1 << 16, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.code))
        self.fns = {}
        at = 0
        for w in (32, 64):
            for op in ('add', 'sub', 'mul', 'div', 'eq', 'lt', 'le', 'neg', 'cvt', 'int32', 'int64'):
                code = stub(w, op)
                self.code[at:at + len(code)] = code
                self.fns[w, op] = ctypes.CFUNCTYPE(ctypes.c_uint64, ctypes.c_uint64, ctypes.c_uint64)(self.base + at)
                at += (len(code) + 15) & ~15
        libc = ctypes.CDLL(None)
        self.strtod = libc.strtod
        self.strtod.restype = ctypes.c_double
        self.strtod.argtypes = [ctypes.c_char_p, ctypes.c_void_p]
        self.strtof = libc.strtof
        self.strtof.restype = ctypes.c_float
        self.strtof.argtypes = [ctypes.c_char_p, ctypes.c_void_p]

    def run(self, case):
        op, w = case[0], case[1]
        if op in ('add', 'sub', 'mul', 'div', 'eq', 'lt', 'le'):
            return self.fns[w, op](case[2], case[3])
        if op == 'neg':
            return self.fns[w, op](case[2], 1 << (w - 1))
        if op == 'cvt':
            return self.fns[w, op](case[2], 0)
        if op == 'int':
            i = case[2]
            if -(1 << 31) <= i < (1 << 31) and case[3] == 32:
                return self.fns[w, 'int32'](i & 0xFFFFFFFF, 0)
            return self.fns[w, 'int64'](i & (2 ** 64 - 1), 0)
        if op == 'trunc':
            return trunc_reference(w, case[2], case[3], case[4])
        if op == 'dec':
            text = f'{case[2]}e{case[3]}'.encode()
            if w == 32:
                return struct.unpack('<I', struct.pack('<f', self.strtof(text, None)))[0]
            return struct.unpack('<Q', struct.pack('<d', self.strtod(text, None)))[0]
        raise ValueError(op)


def trunc_reference(w, bits, lo, hi):
    """Rust's float-to-integer `as`: NaN is 0, otherwise toward zero, saturated."""
    e, f = FORMATS[w]
    mag = bits & ((1 << (e + f)) - 1)
    if mag > ((1 << e) - 1) << f:
        return 0
    if mag == ((1 << e) - 1) << f:
        return lo if bits >> (e + f) else hi
    field, frac = mag >> f, mag & ((1 << f) - 1)
    q = frac + (1 << f) if field else frac
    u = max(field, 1) - ((1 << (e - 1)) - 1) - f
    m = q << u if u >= 0 else q >> -u
    v = -m if bits >> (e + f) else m
    return max(lo, min(hi, v))


# --------------------------------------------------------------- cases


def pattern(w, sign, field, frac):
    e, f = FORMATS[w]
    return (sign << (e + f)) | (field << f) | frac


def edges(w):
    e, f = FORMATS[w]
    top = (1 << e) - 1
    bias = (1 << (e - 1)) - 1
    out = []
    for sign in (0, 1):
        out += [pattern(w, sign, 0, 0), pattern(w, sign, 0, 1), pattern(w, sign, 0, (1 << f) - 1),
                pattern(w, sign, 1, 0), pattern(w, sign, 1, 1), pattern(w, sign, bias, 0), pattern(w, sign, bias, 1),
                pattern(w, sign, bias - 1, (1 << f) - 1), pattern(w, sign, bias + 1, 0),
                pattern(w, sign, top - 1, (1 << f) - 1), pattern(w, sign, top - 1, 0), pattern(w, sign, top, 0),
                pattern(w, sign, top, 1 << (f - 1)), pattern(w, sign, top, (1 << (f - 1)) | 5),
                pattern(w, sign, top, 1), pattern(w, sign, top, 0x2a), pattern(w, sign, top, (1 << f) - 1),
                pattern(w, sign, bias + f, 0), pattern(w, sign, bias + f + 1, 1), pattern(w, sign, 2, 3)]
    return out


def near(rng, w, a):
    """An operand a few binades from a's, so sums cancel, carry or tie."""
    e, f = FORMATS[w]
    top = (1 << e) - 1
    field = (a >> f) & top
    shift = rng.choice((0, 0, 1, f, f + 1, f + 2, rng.randrange(0, f + 3)))
    nf = max(0, min(top - 1, field - shift if rng.random() < 0.8 else field + shift))
    frac = rng.choice((0, 1, (1 << f) - 1, 1 << (f - 1), rng.randrange(1 << f), a & ((1 << f) - 1)))
    return pattern(w, rng.randrange(2), nf, frac)


def ties(w):
    """x + y and x - y where y is half a unit of x, or just above or below it."""
    e, f = FORMATS[w]
    bias = (1 << (e - 1)) - 1
    out = []
    for frac in (0, 1, 2, 3, (1 << f) - 1, (1 << f) - 2):
        x = pattern(w, 0, bias, frac)
        for yfrac in (0, 1, (1 << f) - 1):
            for d in (f + 1, f, f + 2):
                out.append((x, pattern(w, 0, bias - d, yfrac)))
    return out


HARD_DECIMALS = [
    (1, 23), (9007199254740993, 0), (9007199254740992, 0), (9007199254740994, 0), (2, -1075), (25, -1076),
    (24703282292062327208828439643411068618252990130716238221279284125033775364, -397),
    (24703282292062327208828439643411068618252990130716238221279284125033775363, -397),
    (17976931348623157, 292), (17976931348623158, 292), (17976931348623159, 292), (1797693134862315807, 290),
    (22250738585072011, -324), (22250738585072012, -324), (4940656458412465441765687928682213723651, -363),
    (11920928955078125, -23), (11754943508222875, -54), (34028234663852886, 22), (340282356779733661637539395458142568448, 0),
    (340282356779733661637539395458142568447, 0), (14012984643248170709, -64), (7006492321624085354, -64),
    (7006492321624085355, -64), (16777217, 0), (16777219, 0), (33554435, 0), (1, 0), (5, -1), (1, -1), (3, -1),
    (123456789012345678901234567890, -10), (1, 400), (1, -400), (1, 309), (1, -325), (1, -46), (1, 39),
    (314159265358979323846264338327950288, -35), (693147180559945309417232121458176568, -36),
]


def gen(rng, w, count):
    cases = []
    e, f = FORMATS[w]
    width = 1 + e + f
    ed = edges(w)
    for a in ed:
        for b in ed:
            for op in ('add', 'sub', 'mul', 'div', 'eq', 'lt', 'le'):
                cases.append((op, w, a, b))
        cases.append(('neg', w, a))
        cases.append(('cvt', w, a))
    for x, y in ties(w):
        for op in ('add', 'sub'):
            cases.append((op, w, x, y))
            cases.append((op, w, y, x))
    for _ in range(count):
        a = rng.getrandbits(width)
        b = rng.getrandbits(width) if rng.random() < 0.5 else near(rng, w, a)
        for op in ('add', 'sub', 'mul', 'div', 'eq', 'lt', 'le'):
            cases.append((op, w, a, b))
        cases.append(('neg', w, a))
        cases.append(('cvt', w, a))
    ints = [0, 1, -1, 2 ** 24, 2 ** 24 + 1, 2 ** 24 + 3, -(2 ** 24 + 1), 2 ** 53, 2 ** 53 + 1, 2 ** 53 + 3,
            2 ** 31 - 1, -2 ** 31, 2 ** 63 - 1, -2 ** 63, 2 ** 62 + 2 ** 38 + 1, 2 ** 62 + 2 ** 9]
    for _ in range(count):
        bits = rng.choice((8, 16, 31, 32, 53, 54, 63))
        ints.append(rng.randrange(-(1 << bits), 1 << bits))
    for i in ints:
        cases.append(('int', w, i, 32))
        cases.append(('int', w, i, 64))
    bounds = [(-(2 ** 31), 2 ** 31 - 1), (0, 2 ** 32 - 1), (-(2 ** 63), 2 ** 63 - 1), (0, 2 ** 64 - 1), (-128, 127),
              (0, 255)]
    for a in ed + [rng.getrandbits(width) for _ in range(count)] + \
            [pattern(w, rng.randrange(2), rng.randrange((1 << (e - 1)) - 2, (1 << (e - 1)) + 70), rng.getrandbits(f))
             for _ in range(count)]:
        lo, hi = rng.choice(bounds)
        cases.append(('trunc', w, a, lo, hi))
    decs = list(HARD_DECIMALS)
    for _ in range(count):
        digits = rng.randrange(1, 41)
        m = rng.randrange(10 ** (digits - 1), 10 ** digits)
        ex = rng.randrange(-350, 330) if rng.random() < 0.5 else rng.randrange(-50, 40)
        decs.append((m, ex))
    for m, ex in decs:
        cases.append(('dec', w, m, ex))
    return cases


def lean_line(case):
    op, w = case[0], case[1]
    if op == 'int':
        return f'int {w} {case[2]}'
    return ' '.join([op, str(w)] + [str(x) for x in case[2:]])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=2000)
    parser.add_argument('--seed', default='1')
    args = parser.parse_args()
    os.makedirs(args.workdir, exist_ok=True)
    rng = random.Random(args.seed)
    cases = gen(rng, 32, args.count) + gen(rng, 64, args.count)
    # A 32-bit `int` case runs both the 32- and 64-bit conversions natively; Lean has one meaning.
    native = Native()
    want = [native.run(c) for c in cases]
    lines = '\n'.join(lean_line(c) for c in cases) + '\n'
    run = subprocess.run([FLOAT_TEST], input=lines, capture_output=True, text=True)
    got = run.stdout.split('\n')
    if run.returncode != 0 or len(got) < len(cases):
        print(run.stdout[-2000:], run.stderr[-2000:])
        raise SystemExit('floatTest failed')
    bad = []
    for c, n, l in zip(cases, want, got):
        if str(n) != l.strip():
            bad.append((c, n, l.strip()))
    with open(os.path.join(args.workdir, 'differences.txt'), 'w') as out:
        for c, n, l in bad:
            out.write(f'{lean_line(c)}: cpu {n:#x} lean {int(l):#x}\n' if l.lstrip('-').isdigit() and n >= 0
                      else f'{lean_line(c)}: cpu {n} lean {l}\n')
    for c, n, l in bad[:10]:
        print(f'differ: {lean_line(c)}: cpu {n} lean {l}')
    kinds = {}
    for c in cases:
        kinds[c[0]] = kinds.get(c[0], 0) + 1
    summary = ', '.join(f'{k} {v}' for k, v in sorted(kinds.items()))
    print(f'{len(cases)} cases ({summary}), {len(bad)} differ')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
