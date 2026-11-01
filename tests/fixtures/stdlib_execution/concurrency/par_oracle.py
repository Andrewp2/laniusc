#!/usr/bin/env python3
"""Model oracle for std::par (par_sort.lani runner).

Usage: par_oracle.py RUNNER SEED CASES
Each case picks a shape (random, all equal, sorted, reversed, few distinct,
organ pipe, sawtooth, extremes), a size and a worker count, runs every mode
of the runner and compares with Python: sorted() for the sorts, a stable
sort by key for the stable variants (indices must match exactly), the map
function per element, the wrapping sum plus ordered hash for reduce, and
running prefixes for scan (a wrapping u64 sum and the non-commutative
composition of affine maps mod 1e9+7).
Prints "cases N mismatches M" and exits 1 on any mismatch.
"""
import random
import struct
import subprocess
import sys

MASK = (1 << 64) - 1
P = 1000000007
B = 131
SHAPES = ["random", "equal", "sorted", "reversed", "few", "organ", "saw", "extremes", "dups"]


def keys_for(rng, shape, n):
    if shape == "random":
        return [rng.randrange(-(1 << 63), 1 << 63) for _ in range(n)]
    if shape == "equal":
        v = rng.randrange(-1000, 1000)
        return [v] * n
    if shape == "sorted":
        return sorted(rng.randrange(-10**6, 10**6) for _ in range(n))
    if shape == "reversed":
        return sorted((rng.randrange(-10**6, 10**6) for _ in range(n)), reverse=True)
    if shape == "few":
        return [rng.randrange(4) for _ in range(n)]
    if shape == "organ":
        return [min(i, n - i) for i in range(n)]
    if shape == "saw":
        period = rng.randrange(1, 50)
        return [i % period for i in range(n)]
    if shape == "extremes":
        return [rng.choice([-(1 << 63), (1 << 63) - 1, 0, -1, 1]) for _ in range(n)]
    return [rng.randrange(n // 8 + 1) for _ in range(n)]


def to_signed(v):
    return v - (1 << 64) if v >= 1 << 63 else v


def run(runner, mode, workers, keys):
    data = struct.pack("<III", mode, workers, len(keys)) + struct.pack("<%dq" % len(keys), *keys)
    done = subprocess.run([runner], input=data, capture_output=True, timeout=120)
    if done.returncode != 0:
        return None, done.returncode
    return done.stdout, 0


def expect(mode, keys):
    n = len(keys)
    if mode in (0, 2, 6, 10):
        return struct.pack("<%dq" % n, *sorted(keys))
    if mode in (1, 3, 11):
        order = sorted(range(n), key=lambda i: keys[i])
        return struct.pack("<%dq" % n, *[keys[i] for i in order]) + struct.pack("<%dI" % n, *order)
    if mode == 4:
        return struct.pack("<%dq" % n, *[(k >> 1) ^ 21845 for k in keys])
    if mode in (7, 9):
        out, acc = [], 0
        for k in keys:
            acc = (acc + (k & MASK)) & MASK
            out.append(acc)
        return struct.pack("<%dQ" % n, *out)
    if mode == 8:
        out, a, b = [], 1, 0
        for k in keys:
            u = k & MASK
            ka, kb = u % P, (u >> 20) % P
            a, b = ka * a % P, (ka * b + kb) % P
            out += [a, b]
        return struct.pack("<%dQ" % (2 * n), *out)
    total, h, scale = 0, 0, 1
    for k in keys:
        u = k & MASK
        total = (total + u) & MASK
        h = (h * B + u % P) % P
        scale = scale * B % P
    return struct.pack("<QQQ", total, h, scale)


def main():
    runner, seed, cases = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    rng = random.Random(seed)
    checked = mismatches = 0
    for case in range(cases):
        shape = SHAPES[case % len(SHAPES)]
        n = rng.choice([0, 1, 2, 3, 7, 64, 255, 1000, 4097, rng.randrange(2, 70000), rng.randrange(65536, 300000)])
        workers = rng.choice([1, 2, 3, 4, 7, 8, 13])
        keys = keys_for(rng, shape, n)
        for mode in range(12):
            got, code = run(runner, mode, workers, keys)
            checked += 1
            if code != 0 or got != expect(mode, keys):
                mismatches += 1
                print("MISMATCH seed %d case %d shape %s n %d workers %d mode %d exit %d" % (seed, case, shape, n, workers, mode, code))
    print("cases %d mismatches %d" % (checked, mismatches))
    sys.exit(1 if mismatches else 0)


if __name__ == "__main__":
    main()
