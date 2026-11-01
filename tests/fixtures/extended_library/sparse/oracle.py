"""Sparse runtime oracle: dense dictionaries, exact Fractions and ordered IEEE.

No sparse production algorithms are implemented here. Coordinates are materialized
in Python dictionaries, dense products use elementary row/column loops, and the
bounded dyadic corpus is checked again with exact Fraction arithmetic. Non-dyadic,
extreme and subnormal cases follow the specified binary64 product/add order and
compare exact finite bits rather than accepting tiny values by absolute tolerance.
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

SEED = 0xC5A20261028
MAX = (1 << 64) - 1
HUGE = sys.float_info.max
MIN = math.ulp(0.0)
F = Fraction


def bits(value):
    return struct.unpack("<Q", struct.pack("<d", value))[0]


@dataclass(frozen=True)
class Base:
    m: int
    n: int
    p: int
    a: tuple
    b: tuple
    triplets: tuple
    row_factors: tuple
    col_factors: tuple
    x: tuple
    dense_a: tuple
    dense_b: tuple
    factor: float
    dyadic: bool = True
    label: str = ""


def canonical(m, n, items, *, preserve=True):
    entries = sorted((r, c, value) for (r, c), value in dict(items).items()
                     if preserve or value != 0.0)
    offsets = [0]
    for row in range(m):
        offsets.append(offsets[-1] + sum(r == row for r, c, value in entries))
    return tuple(offsets), tuple(c for r, c, value in entries), tuple(value for r, c, value in entries)


def sparse_header(m, n, items, *, preserve=True):
    offsets, columns, values = canonical(m, n, items, preserve=preserve)
    return [0, MAX, MAX, MAX, 0, m, n, len(values), *offsets, *columns, *map(bits, values)]


def dense_header(m, n, values, *, status=0, row=-1, entry=-1, completed=-1):
    return [status, row & MAX, entry & MAX, completed & MAX, 1, m, n, len(values), *map(bits, values)]


def failure(kind, row, entry):
    return [kind, row & MAX, entry & MAX, MAX, 2, 0, 0, 0]


def row_entries(m, n, items):
    offsets, columns, values = canonical(m, n, items)
    output = []
    for row in range(m):
        output.append([(entry, columns[entry], values[entry])
                       for entry in range(offsets[row], offsets[row + 1])])
    return output


def coalesced(base):
    # Validate the whole coordinate list before grouping, as the public
    # preflight promises. Grouping uses original input order for each key.
    grouped = {}
    for ordinal, (row, col, value) in enumerate(base.triplets):
        if not 0 <= row < base.m:
            return failure(3, row, ordinal)
        if not 0 <= col < base.n:
            return failure(8, row, ordinal)
        if not math.isfinite(value):
            return failure(10, row, ordinal)
        grouped.setdefault((row, col), []).append((ordinal, value))
    result = {}
    for (row, col), values in sorted(grouped.items()):
        total = values[0][1]
        for ordinal, value in values[1:]:
            total += value
            if not math.isfinite(total):
                return failure(11, row, ordinal)
        if base.dyadic:
            exact = sum((F(value) for ordinal, value in values), F(0))
            assert F(total) == exact, (base.label, "dyadic coalescing", total, exact)
        result[row, col] = total
    return sparse_header(base.m, base.n, result, preserve=False)


def dot_rows(base, dense, width):
    output = [0.0] * (base.m * width)
    for row, entries in enumerate(row_entries(base.m, base.n, base.a)):
        for col in range(width):
            total = 0.0
            exact = F(0)
            for entry, inner, value in entries:
                product = value * dense[inner * width + col]
                if not math.isfinite(product):
                    return output, (row, entry)
                total += product
                if not math.isfinite(total):
                    return output, (row, entry)
                if base.dyadic:
                    exact += F(value) * F(dense[inner * width + col])
            if base.dyadic:
                assert F(total) == exact, (base.label, "dyadic dot", row, col, total, exact)
            output[row * width + col] = total
    return output, None


def expected(case):
    op, layout, base = case
    a, b = dict(base.a), dict(base.b)
    if op in (0, 2, 4):
        return sparse_header(base.m, base.n, a)
    if op == 1:
        return coalesced(base)
    if op == 3:
        return sparse_header(base.n, base.m, {(c, r): value for (r, c), value in a.items()})
    if op in (5, 6):
        result = {}
        for row in range(base.m):
            for col in range(base.n):
                if (row, col) not in a and (row, col) not in b:
                    continue
                value = a.get((row, col), 0.0) + b.get((row, col), 0.0) if op == 5 else a.get((row, col), 0.0) - b.get((row, col), 0.0)
                if not math.isfinite(value):
                    # Finite operands can overflow only at a matching key;
                    # the API identifies the left operand's global CSR entry.
                    ordinal = sorted(a).index((row, col))
                    return failure(11, row, ordinal)
                if base.dyadic:
                    exact = F(a.get((row, col), 0.0)) + (1 if op == 5 else -1) * F(b.get((row, col), 0.0))
                    assert F(value) == exact
                result[row, col] = value
        return sparse_header(base.m, base.n, result, preserve=False)
    if op in (7, 8, 9):
        result = {}
        for row, entries in enumerate(row_entries(base.m, base.n, base.a)):
            for entry, col, stored in entries:
                factor = base.factor if op == 7 else base.row_factors[row] if op == 8 else base.col_factors[col]
                value = stored * factor
                if not math.isfinite(value):
                    return failure(11, row, entry)
                if base.dyadic:
                    assert F(value) == F(stored) * F(factor)
                result[row, col] = value
        return sparse_header(base.m, base.n, result, preserve=False)
    if op in (10, 14):
        values, error = dot_rows(base, base.x, 1)
        if error:
            row, entry = error
            if op == 10:
                return failure(11, row, entry)
            values[row:] = [12345.0] * (base.m - row)
            return dense_header(base.m, 1, values, status=11, row=row, entry=entry, completed=row)
        return dense_header(base.m, 1, values, completed=base.m if op == 14 else -1)
    if op in (11, 15):
        return dense_header(base.m, base.n, [a.get((r, c), 0.0) for r in range(base.m) for c in range(base.n)])
    if op == 12:
        return sparse_header(base.m, base.n,
                             {(r, c): base.dense_a[r * base.n + c]
                              for r in range(base.m) for c in range(base.n)}, preserve=False)
    if op == 13:
        values, error = dot_rows(base, base.dense_b, base.p)
        if error:
            row, entry = error
            return failure(11, row, entry)
        return dense_header(base.m, base.p, values)
    assert op == 16
    return sparse_header(base.m, base.n, {})


def make_base(m, n, p, a=(), b=(), *, triplets=(), factor=2.0, row_factors=None,
              col_factors=None, x=None, dense_a=None, dense_b=None, dyadic=True, label=""):
    return Base(m, n, p, tuple(sorted(dict(a).items())), tuple(sorted(dict(b).items())), tuple(triplets),
                tuple([1.0] * m if row_factors is None else row_factors),
                tuple([1.0] * n if col_factors is None else col_factors),
                tuple([1.0] * n if x is None else x),
                tuple([0.0] * (m * n) if dense_a is None else dense_a),
                tuple([1.0] * (n * p) if dense_b is None else dense_b), factor, dyadic, label)


def bases():
    output = []
    for m, n, p in ((0, 0, 0), (0, 3, 2), (3, 0, 2), (2, 3, 0), (1, 1, 1), (8, 8, 8)):
        output.append(make_base(m, n, p, label=f"empty-{m}-{n}-{p}"))
    output.append(make_base(3, 4, 2, { (0, 0): -0.0, (0, 3): 2.0, (2, 1): 0.0, (2, 3): -3.0 },
                            { (0, 3): -2.0, (1, 2): 4.0 },
                            triplets=((2, 1, 1.0), (0, 3, 2.0), (2, 1, -1.0), (0, 3, 3.0)),
                            x=(1.0, 2.0, 3.0, 4.0), row_factors=(0.0, -1.0, 2.0),
                            col_factors=(1.0, 0.0, -1.0, .5), label="zeros-cancellation"))
    rng = random.Random(SEED)
    for index in range(80):
        m, n, p = rng.randrange(9), rng.randrange(9), rng.randrange(9)
        def value(): return rng.randrange(-16, 17) / 4
        def matrix():
            return {(r, c): (-0.0 if rng.randrange(10) == 0 else value())
                    for r in range(m) for c in range(n) if rng.randrange(4) == 0}
        triplets = []
        if m and n:
            for _ in range(rng.randrange(min(64, 2 * m * n) + 1)):
                triplets.append((rng.randrange(m), rng.randrange(n), value()))
        output.append(make_base(m, n, p, matrix(), matrix(), triplets=triplets,
                                factor=value(), row_factors=[value() for _ in range(m)],
                                col_factors=[value() for _ in range(n)], x=[value() for _ in range(n)],
                                dense_a=[value() if rng.randrange(3) == 0 else 0.0 for _ in range(m * n)],
                                dense_b=[value() for _ in range(n * p)], label=f"dyadic-{index}"))
    for index in range(20):
        m, n, p = rng.randrange(1, 7), rng.randrange(1, 7), rng.randrange(1, 7)
        a = {(r, c): rng.randrange(-20, 21) / 3 for r in range(m) for c in range(n) if rng.randrange(3) == 0}
        b = {(r, c): rng.randrange(-20, 21) / 7 for r in range(m) for c in range(n) if rng.randrange(3) == 0}
        output.append(make_base(m, n, p, a, b, factor=.1,
                                row_factors=[rng.randrange(-5, 6) / 3 for _ in range(m)],
                                col_factors=[rng.randrange(-5, 6) / 7 for _ in range(n)],
                                x=[rng.randrange(-5, 6) / 7 for _ in range(n)],
                                dense_a=[rng.randrange(-5, 6) / 3 for _ in range(m * n)],
                                dense_b=[rng.randrange(-5, 6) / 7 for _ in range(n * p)],
                                dyadic=False, label=f"sequential-ieee-{index}"))
    return output


def cases():
    output = [(op, layout, base) for base in bases() for layout in range(2) for op in range(17)]
    numeric = [
        make_base(1, 1, 1, {(0, 0): HUGE}, {(0, 0): HUGE}, factor=2., row_factors=(2.,), col_factors=(2.,), x=(2.,), dense_b=(2.,), dyadic=False, label="max-overflow"),
        make_base(1, 1, 1, {(0, 0): -HUGE}, {(0, 0): HUGE}, dyadic=False, label="negative-overflow"),
        make_base(2, 2, 1, {(0, 0): 2., (1, 0): HUGE, (1, 1): HUGE}, x=(1., 1.), dyadic=False, label="completed-prefix"),
        make_base(2, 2, 2, {(0, 0): MIN, (0, 1): -MIN, (1, 1): -0.0}, factor=.5, row_factors=(.5, .5), col_factors=(.5, .5), x=(.5, .5), dense_b=(.5, .5, .5, .5), dyadic=False, label="subnormal-signed-zero"),
        make_base(1, 1, 1, {(0, 0): HUGE}, factor=0., row_factors=(0.,), col_factors=(0.,), x=(0.,), dense_b=(0.,), dyadic=False, label="huge-times-zero"),
        make_base(1, 1, 1, {(0, 0): 1e308}, {(0, 0): -1e308}, factor=1e-308, row_factors=(1e-308,), col_factors=(1e-308,), x=(1e-308,), dense_b=(1e-308,), dyadic=False, label="extreme-finite"),
        make_base(1, 1, 1, {(0, 0): -1e-300}, factor=1e-100, row_factors=(1e-100,), col_factors=(1e-100,), x=(1e-100,), dense_b=(1e-100,), dyadic=False, label="gradual-underflow"),
    ]
    for base in numeric:
        output.extend((op, layout, base) for layout in range(2) for op in range(17))
    coordinates = [
        ((0, 0, 1e16), (0, 0, 1.), (0, 0, -1e16)),
        ((0, 0, 1e16), (0, 0, -1e16), (0, 0, 1.)),
        ((0, 0, HUGE), (0, 1, 1.), (0, 0, HUGE)),
        ((1, 1, HUGE), (0, 0, 2.), (1, 1, HUGE)),
        ((0, 0, -0.0), (0, 1, MIN), (0, 1, -MIN)),
    ]
    for index, triplets in enumerate(coordinates):
        base = make_base(2, 2, 1, triplets=triplets, dyadic=False, label=f"ordered-coordinate-{index}")
        output.extend((1, layout, base) for layout in range(2))
    return output


def packet(values):
    output = bytearray()
    for op, layout, base in values:
        ao, ac, av = canonical(base.m, base.n, base.a)
        bo, bc, bv = canonical(base.m, base.n, base.b)
        output += struct.pack("<8id", op, base.m, base.n, base.p, len(av), len(bv), len(base.triplets), layout, base.factor)
        for offsets, columns, stored in ((ao, ac, av), (bo, bc, bv)):
            output += struct.pack("<" + "i" * len(offsets), *offsets)
            output += struct.pack("<" + "i" * len(columns), *columns)
            output += struct.pack("<" + "d" * len(stored), *stored)
        for row, col, value in base.triplets:
            output += struct.pack("<iid", row, col, value)
        for data in (base.row_factors, base.col_factors, base.x, base.dense_a, base.dense_b):
            output += struct.pack("<" + "d" * len(data), *data)
    return output


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = expected(case)
        count = len(want) * 8
        assert offset + count <= len(actual), (index, case[0], case[2].label, "truncated output")
        got = struct.unpack_from("<" + "Q" * len(want), actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case[0], case[1], case[2].label, got, want)
        offset += count
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    sample = values[::41]
    actual = b"".join(struct.pack("<" + "Q" * len(words), *words) for words in map(expected, sample))
    verify(actual, sample)
    # A tiny output mutation must fail even when it is far below a usual
    # absolute numerical tolerance. No tiny-result tolerance is used here.
    tiny = make_base(1, 1, 1, {(0, 0): MIN}, dyadic=False, label="tiny-control")
    selected = [(11, 0, tiny)]
    words = expected(selected[0]); words[-1] = bits(0.0)
    try:
        verify(struct.pack("<" + "Q" * len(words), *words), selected)
    except AssertionError:
        pass
    else:
        raise AssertionError("oracle accepted lost subnormal output")
    for case in values:
        expected(case)
    print(f"sparse-model CPU controls={len(sample)} all-cases={len(values)} tiny-corruption=rejected")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values)
    print(f"sparse-model cases={len(values)} modes=17 storage_forms=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
