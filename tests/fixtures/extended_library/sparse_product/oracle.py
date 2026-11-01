"""Independent finite sparse products: dense dictionaries/Fraction and IEEE.

The exact dyadic corpus is multiplied as dense coordinate dictionaries with
Fraction. Ordered binary64 boundary cases model the specified increasing-inner
product/add sequence and compare exact bits, including gradual underflow.
"""
from __future__ import annotations
from dataclasses import dataclass, replace
from fractions import Fraction
import math
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xC5A520261028
MASK = (1 << 64) - 1
HUGE = sys.float_info.max
MIN = math.ulp(0.0)
F = Fraction


def bits(value):
    return struct.unpack("<Q", struct.pack("<d", value))[0]


@dataclass(frozen=True)
class Case:
    m: int
    k: int
    n: int
    a: tuple
    b: tuple
    layout: int = 0
    cap: int = 1048576
    dyadic: bool = True
    label: str = ""


def case(m, k, n, a=(), b=(), **keywords):
    return Case(m, k, n, tuple(sorted(dict(a).items())), tuple(sorted(dict(b).items())), **keywords)


def csr(rows, cols, items):
    ordered = sorted(dict(items).items())
    offsets = [0]
    for row in range(rows):
        offsets.append(offsets[-1] + sum(r == row for (r, c), value in ordered))
    return offsets, [c for (r, c), value in ordered], [value for key, value in ordered]


def failure(kind, row=-1, entry=-1):
    return [kind, row & MASK, entry & MASK, 0, 0, 0]


def expected(value):
    a, b = dict(value.a), dict(value.b)
    if len(a) > value.cap or len(b) > value.cap:
        return failure(5)
    left_ordinals = {key: index for index, key in enumerate(sorted(a))}
    result = {}
    total_entries = 0
    for row in range(value.m):
        # A small dense row of partial sums models only the specified IEEE
        # order. It is not a sparse accumulator/marker/sorting implementation.
        partial = [0.0] * value.n
        for inner in range(value.k):
            if (row, inner) not in a:
                continue
            for column in range(value.n):
                if (inner, column) not in b:
                    continue
                product = a[row, inner] * b[inner, column]
                if not math.isfinite(product):
                    return failure(11, row, left_ordinals[row, inner])
                partial[column] += product
                if not math.isfinite(partial[column]):
                    return failure(11, row, left_ordinals[row, inner])
        if value.dyadic:
            for column in range(value.n):
                exact = sum((F(a.get((row, inner), 0.0)) * F(b.get((inner, column), 0.0))
                             for inner in range(value.k)), F(0))
                assert F(partial[column]) == exact, (value.label, row, column, partial[column], exact)
        for column, item in enumerate(partial):
            if item == 0.0:
                continue
            if total_entries == value.cap:
                return failure(5, row, column)
            result[row, column] = item
            total_entries += 1
    offsets, columns, values = csr(value.m, value.n, result)
    return [0, MASK, MASK, value.m, value.n, len(values), *offsets, *columns, *map(bits, values)]


def cases():
    bases = []
    for m in range(5):
        for k in range(5):
            for n in range(5):
                a = {(r, c): ((r + c) % 5 - 2) / 2
                     for r in range(m) for c in range(k) if (r + 2 * c) % 3 == 0}
                b = {(r, c): ((2 * r + c) % 5 - 2) / 2
                     for r in range(k) for c in range(n) if (2 * r + c) % 3 == 0}
                bases.append(case(m, k, n, a, b, label=f"shape-{m}-{k}-{n}"))
    rng = random.Random(SEED)
    for index in range(900):
        m, k, n = rng.randrange(9), rng.randrange(9), rng.randrange(9)
        density = rng.choice((1, 2, 3, 5))
        def matrix(rows, cols):
            return {(r, c): (-0.0 if rng.randrange(13) == 0 else rng.randrange(-8, 9) / 4)
                    for r in range(rows) for c in range(cols) if rng.randrange(density) == 0}
        bases.append(case(m, k, n, matrix(m, k), matrix(k, n), label=f"dyadic-{index}"))
    for index in range(50):
        m, k, n = rng.randrange(1, 9), rng.randrange(1, 9), rng.randrange(1, 9)
        a = {(r, c): rng.randrange(-9, 10) / 3 for r in range(m) for c in range(k) if rng.randrange(3) == 0}
        b = {(r, c): rng.randrange(-9, 10) / 7 for r in range(k) for c in range(n) if rng.randrange(3) == 0}
        bases.append(case(m, k, n, a, b, dyadic=False, label=f"ordered-ieee-{index}"))
    bases += [
        case(2, 2, 6, {(0, 0): 1., (0, 1): 1., (1, 0): 2., (1, 1): -1.},
             {(0, 3): 2., (0, 5): 3., (1, 0): 4., (1, 2): 5.}, label="shared-destinations-sorted-touch"),
        case(3, 3, 3, {(0, 0): -0., (0, 1): 1., (1, 1): 0., (2, 2): -0.},
             {(0, 0): HUGE, (1, 0): 2., (1, 2): -0., (2, 1): HUGE}, dyadic=False, label="stored-zeros-visited"),
        case(1, 3, 1, {(0, 0): 1e16, (0, 1): 1., (0, 2): -1e16},
             {(0, 0): 1., (1, 0): 1., (2, 0): 1.}, dyadic=False, label="increasing-inner-loses-small"),
        case(1, 3, 1, {(0, 0): 1e16, (0, 1): -1e16, (0, 2): 1.},
             {(0, 0): 1., (1, 0): 1., (2, 0): 1.}, dyadic=False, label="increasing-inner-keeps-small"),
        case(1, 3, 1, {(0, 0): HUGE, (0, 1): HUGE, (0, 2): -HUGE},
             {(0, 0): 1., (1, 0): 1., (2, 0): 1.}, dyadic=False, label="overflow-before-cancellation"),
        case(1, 1, 1, {(0, 0): HUGE}, {(0, 0): 2.}, dyadic=False, label="product-overflow"),
        case(2, 2, 2, {(0, 1): 1., (1, 0): HUGE},
             {(0, 0): 1., (0, 1): 2., (1, 0): 1.}, dyadic=False, label="later-output-product-overflow"),
        case(2, 2, 2, {(0, 0): 1., (1, 0): HUGE, (1, 1): HUGE},
             {(0, 0): 1., (1, 0): 1.}, dyadic=False, label="later-row-sum-overflow"),
        case(1, 2, 1, {(0, 0): HUGE, (0, 1): -HUGE}, {(0, 0): 1., (1, 0): 1.}, dyadic=False, label="finite-cancellation"),
        case(1, 2, 1, {(0, 0): 1e308, (0, 1): -1e308}, {(0, 0): 1e-308, (1, 0): 1e-308}, dyadic=False, label="finite-extreme-products"),
        case(1, 1, 1, {(0, 0): MIN}, {(0, 0): 1.}, dyadic=False, label="positive-subnormal"),
        case(1, 1, 1, {(0, 0): -MIN}, {(0, 0): 1.}, dyadic=False, label="negative-subnormal"),
        case(1, 1, 1, {(0, 0): MIN}, {(0, 0): .5}, dyadic=False, label="rounded-positive-zero"),
        case(1, 1, 1, {(0, 0): -MIN}, {(0, 0): .5}, dyadic=False, label="rounded-negative-zero"),
        case(1, 2, 1, {(0, 0): MIN, (0, 1): MIN}, {(0, 0): 1., (1, 0): 1.}, dyadic=False, label="subnormal-sum"),
        case(1, 1, 1, {(0, 0): -1e-300}, {(0, 0): 1e-100}, dyadic=False, label="gradual-underflow"),
        case(2, 1, 2, {(0, 0): 1., (1, 0): 1.}, {(0, 0): 1., (0, 1): 1.}, cap=2, label="actual-output-cap"),
        case(3, 2, 3, {(r, k): 1. for r in range(3) for k in range(2)},
             {(r, c): (1. if r == 0 else -1.) * (c + 1) for r in range(2) for c in range(3)}, cap=6, label="cancellation-fits-cap"),
        case(3, 2, 3, {(r, k): 1. for r in range(3) for k in range(2)},
             {(r, c): float(c + 1) for r in range(2) for c in range(3)}, cap=6, label="fill-in-exceeds-cap"),
        case(2, 3, 4, {(0, 0): 1., (0, 1): 1., (1, 2): 1.}, {(0, 0): 1.}, cap=2, label="left-input-entry-cap"),
        case(2, 3, 4, {(0, 0): 1.}, {(0, 0): 1., (1, 1): 1., (2, 2): 1.}, cap=2, label="right-input-entry-cap"),
        case(3, 0, 8, cap=0, label="wide-empty-zero-cap"),
    ]
    return [replace(value, layout=layout) for value in bases for layout in range(2)]


def packet(values):
    output = bytearray()
    for value in values:
        ao, ac, av = csr(value.m, value.k, value.a)
        bo, bc, bv = csr(value.k, value.n, value.b)
        output += struct.pack("<8i", value.m, value.k, value.n, len(av), len(bv), value.layout, value.cap, 0)
        for offsets, columns, stored in ((ao, ac, av), (bo, bc, bv)):
            output += struct.pack("<" + "i" * len(offsets), *offsets)
            output += struct.pack("<" + "i" * len(columns), *columns)
            output += struct.pack("<" + "d" * len(stored), *stored)
    return output


def verify(actual, values):
    offset = 0
    for index, value in enumerate(values):
        want = expected(value)
        length = len(want) * 8
        assert offset + length <= len(actual), (index, value.label, "truncated output")
        got = struct.unpack_from("<" + "Q" * len(want), actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, value.label, value.layout, got, want)
        offset += length
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    sample = values[::23]
    actual = b"".join(struct.pack("<" + "Q" * len(words), *words) for words in map(expected, sample))
    verify(actual, sample)
    tiny = case(1, 1, 1, {(0, 0): MIN}, {(0, 0): 1.}, dyadic=False, label="lost-subnormal-control")
    words = expected(tiny); words[-1] = bits(0.)
    try:
        verify(struct.pack("<" + "Q" * len(words), *words), [tiny])
    except AssertionError:
        pass
    else:
        raise AssertionError("oracle accepted lost subnormal output")
    for value in values:
        expected(value)
    print(f"sparse-product CPU controls={len(sample)} all-cases={len(values)} tiny-corruption=rejected")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values)
    print(f"sparse-product cases={len(values)} storage_forms=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
