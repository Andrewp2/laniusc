"""Arbitrary-precision reference independent of the Lanius implementation.

The transport retains all 64 bits; arithmetic is interpreted at each native width.
"""
import math
import random
import struct
import subprocess
import sys
import time

MASK = (1 << 64) - 1
LIMITS = [
    (-(1 << (n - 1)), (1 << (n - 1)) - 1, n, True)
    if signed else (0, (1 << n) - 1, n, False)
    for n, signed in [(8, 1), (8, 0), (16, 1), (16, 0), (32, 1), (32, 0),
                      (64, 1), (64, 0), (64, 1), (64, 0)]
]


def cast(a, width, signed):
    a &= (1 << width) - 1
    return a - (1 << width) if signed and a & (1 << (width - 1)) else a


def bound(a, low, high):
    return a if low <= a <= high else None


def reference(kind, op, raw_a, raw_b, n):
    low, high, width, signed = LIMITS[kind]
    mask = (1 << width) - 1
    a = cast(raw_a, width, signed)
    b = cast(raw_b, width, signed)
    word = raw_a & mask
    clamp = lambda x: max(low, min(high, x))
    wrap = lambda x: cast(x, width, signed)
    if 52 <= op < 112:
        offset = op - 52
        to = offset < 30
        other = (offset % 30) // 3
        mode = offset % 3
        ol, oh, ow, os = LIMITS[other]
        number = a if to else cast(raw_a, ow, os)
        lo, hi, w, s = (ol, oh, ow, os) if to else (low, high, width, signed)
        return (bound(number, lo, hi) if mode == 0 else
                max(lo, min(hi, number)) if mode == 1 else cast(number, w, s))
    if op < 9:
        value = [a + b, a - b, a * b][op % 3]
        return wrap(value) if op < 3 else bound(value, low, high) if op < 6 else clamp(value)
    if op in (9, 10, 11, 12, 48, 49, 50):
        if not b:
            return None
        if signed and a == low and b == -1:
            return low if op == 48 else 0 if op == 49 else high if op == 50 else None
        q = abs(a) // abs(b) * (-1 if (a < 0) != (b < 0) else 1)
        r = a - q * b
        if op in (11, 12) and r < 0:
            q += -1 if b > 0 else 1
            r = a - q * b
        return r if op in (10, 12, 49) else q
    if op == 13:
        return bound(-a, low, high)
    if op == 14:
        return wrap(-a)
    if op == 15:
        return clamp(-a)
    if op in (16, 17, 18):
        if op == 17:
            return wrap(pow(a, n, 1 << width))
        if abs(a) > 1 and n >= width:
            return None if op == 16 else low if a < 0 and n % 2 else high
        value = pow(a, n)
        return bound(value, low, high) if op == 16 else clamp(value)
    if op in (19, 20, 21, 22):
        if op < 21 and n >= width:
            return None
        n %= width
        return wrap(a << n) if op in (19, 21) else a >> n
    if op in (23, 24):
        n %= width
        if op == 24:
            n = -n % width
        return wrap((word << n) | (word >> ((width - n) % width)))
    if op == 25:
        return wrap(int(f'{word:0{width}b}'[::-1], 2))
    if op == 26:
        return wrap(int.from_bytes(word.to_bytes(width // 8, 'little'), 'big'))
    if op == 27:
        return word.bit_count()
    if op == 28:
        return width - word.bit_count()
    if op in (29, 31):
        return width - (word if op == 29 else word ^ mask).bit_length()
    if op in (30, 32):
        x = word if op == 30 else word ^ mask
        return (x & -x).bit_length() - 1 if x else width
    if op == 33:
        return bound(1 if a <= 1 else 1 << (a - 1).bit_length(), low, high)
    if op == 34:
        return bound(abs(a), low, high)
    if op == 35:
        return wrap(abs(a))
    if op == 36:
        return clamp(abs(a))
    if op == 37:
        return (a > 0) - (a < 0)
    if op == 38:
        return abs(a)
    if op == 39:
        return abs(a - b)
    if op == 40:
        return min(a, b)
    if op == 41:
        return max(a, b)
    if op == 42:
        return int(a % 2 == 0)
    if op == 43:
        return int(b != 0 and a % b == 0)
    if op == 44:
        return bound(a, -(1 << 31), (1 << 31) - 1)
    if op == 45:
        return bound(a, 0, (1 << 32) - 1)
    if op == 46:
        return bound(cast(raw_a, 64, True), low, high)
    if op == 47:
        return bound(raw_a, low, high)
    if op == 51:
        return int(a > 0 and a & (a - 1) == 0)
    if op == 112:
        return math.gcd(a, b)
    if op == 113:
        return bound(math.lcm(a, b), low, high)
    if op == 114:
        return bound((a + b - 1) // b * b, low, high) if b else None
    if op == 115:
        return a // b * b if b else None
    if op == 116:
        return int(b != 0 and a % b == 0)
    if op == 117:
        return min(abs(a - b), high)
    if op in (118, 119):
        high_bound = cast(n, width, signed)
        return (3 if op == 119 else None) if b > high_bound else max(b, min(high_bound, a))
    raise ValueError(op)


def main():
    rng = random.Random(0x83202026)
    edges = {0, 1, 2, 3, MASK, MASK - 1, MASK - 2, 1 << 63, (1 << 63) - 1}
    for width in (8, 16, 32):
        for boundary in (1 << (width - 1), 1 << width):
            edges.update(boundary + delta for delta in (-2, -1, 0, 1, 2))
        third = ((1 << (width - 1)) - 1) // 3
        for value in (third, third + 1):
            edges.update((value, -value & MASK))
    edges = sorted(edges)
    shifts = [0, 1, 2, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, (1 << 32) - 1]
    cases = []

    def push(k, op, a, b, n):
        if k % 2 and op in (15, 34, 35, 36, 37, 38, 117):
            return
        if k % 2 == 0 and op in (114, 115, 116):
            return
        if op in (48, 49, 50) and cast(b, LIMITS[k][2], LIMITS[k][3]) == 0:
            return
        cases.append((k, op, a, b, n))

    for k in range(6):
        for op in range(120):
            for i in range(80):
                push(k, op, edges[i] if i < len(edges) else rng.getrandbits(64),
                     edges[(i * 11 + 7) % len(edges)] if i < len(edges) else rng.getrandbits(64),
                     shifts[i % len(shifts)])
        for op in (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 39, 43, 48, 49, 50, 112, 113, 114, 115, 116, 117):
            for a in edges:
                for b in edges:
                    push(k, op, a, b, 3)
    # Python uses an independent seeded sample; exhaustive byte pairs are checked
    # against Rust primitives by the companion test, avoiding duplicate work.
    data = struct.pack('<I', len(cases)) + b''.join(struct.pack('<BB2xQQI', *c) for c in cases)
    started = time.perf_counter()
    result = subprocess.run([sys.argv[1]], input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=10)
    elapsed = time.perf_counter() - started
    assert result.returncode == 0, (result.returncode, result.stderr)
    assert not result.stderr, result.stderr
    assert len(result.stdout) == 12 * len(cases), (len(result.stdout), len(cases))
    for i, (case, actual) in enumerate(zip(cases, struct.iter_unpack('<IQ', result.stdout))):
        expected = reference(*case)
        wanted = (int(expected is not None), 0 if expected is None else expected & MASK)
        if actual != wanted:
            raise AssertionError((i, case, actual, wanted))
    print(f'{len(cases):,} arithmetic/bit/conversion/gcd/alignment cases match Python arbitrary-precision reference, '
          f'seed=0x83202026; native process {elapsed:.6f}s')


if __name__ == '__main__':
    main()
