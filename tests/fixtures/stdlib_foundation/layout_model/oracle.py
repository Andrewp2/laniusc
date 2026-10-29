"""Arbitrary-precision arithmetic reference for checked storage layouts.

Rounded multiples, products and sums use unbounded Python integers. Alignment
validity is membership in the explicit 64-bit power set, not a copy of product
bit guards. No pointers, allocations or native record layouts are modeled.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x1A90A0261031
MAX = (1 << 63) - 1
USIZE_MAX = (1 << 64) - 1
POWERS = frozenset(1 << bit for bit in range(64))
WORDS = 10


@dataclass(frozen=True)
class Case:
    operation: int
    a: int
    b: int
    c: int
    d: int
    mutation: int
    identity: int


def rounded(value, alignment): return -(-value // alignment) * alignment


def classification(size, alignment):
    if alignment not in POWERS: return 1
    return 0 if rounded(size, alignment) <= MAX else 2


def reference(case):
    operation, a, b, c, d = case.operation, case.a, case.b, case.c, case.d
    tag, error, size, alignment, extra = 0, 0, 0, 0, 0
    left_error = classification(a, b)
    if operation == 2:
        tag, extra = 2, int(left_error == 0)
    elif operation in (0, 1):
        error = left_error
        if not error: size, alignment = a, b
    elif operation == 3:
        error = left_error
        if not error: extra = rounded(a, b) - a
    elif operation == 4:
        error = left_error
        if not error: size, alignment = rounded(a, b), b
    elif operation == 5:
        error = left_error
        if not error:
            if c not in POWERS: error = 1
            else:
                candidate = max(b, c)
                error = classification(a, candidate)
                if not error: size, alignment = a, candidate
    elif operation == 6:
        error = left_error
        if not error:
            stride = rounded(a, b)
            total = stride * c
            error = classification(total, b)
            if not error: size, alignment, extra = total, b, stride
    else:
        assert operation == 7
        error = left_error or classification(c, d)
        if not error:
            offset = rounded(a, d)
            total, candidate = offset + c, max(b, d)
            error = classification(total, candidate)
            if not error: size, alignment, extra = total, candidate, offset
    if error: tag = 1
    return [operation, tag, error, size, alignment, extra, a, b, c, d]


def cases():
    result, seen = [], set()

    def append(operation, a, b, c=0, d=1):
        key = (operation, a, b, c, d)
        if key in seen: return
        seen.add(key)
        assert all(0 <= value <= USIZE_MAX for value in (a, b, c, d))
        for mutation in range(2): result.append(Case(*key, mutation, len(result) + 1))

    sizes = (0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65,
             255, 256, 257, (1 << 31) - 1, 1 << 31, (1 << 32) - 1, 1 << 32,
             (1 << 32) + 1, MAX - 16, MAX - 8, MAX - 2, MAX - 1, MAX,
             MAX + 1, MAX + 2, MAX + 8, USIZE_MAX - 1, USIZE_MAX)
    alignments = (0, 1, 2, 3, 4, 7, 8, 16, 64, 256, 1 << 31, 1 << 32,
                  1 << 62, 1 << 63, USIZE_MAX - 1, USIZE_MAX)
    for size in sizes:
        for alignment in alignments:
            for operation in range(5): append(operation, size, alignment)

    # Every alignment power, including 2^63, with mathematical rounding edges.
    for alignment in sorted(POWERS):
        last_multiple = (MAX // alignment) * alignment
        for size in (0, 1, alignment - 1, alignment, last_multiple,
                     last_multiple + 1, MAX, MAX + 1, USIZE_MAX):
            for operation in range(5): append(operation, size, alignment)

    layouts = ((0, 1), (1, 1), (2, 2), (3, 4), (5, 4), (7, 8), (8, 8), (9, 8),
               (17, 16), (0, 64), (63, 64), (64, 64), (65, 64),
               (0, 1 << 63), (1, 1 << 63), (0, 1 << 62), (1 << 62, 1 << 62),
               (1 << 32, 8), (MAX, 1), (MAX - 1, 2), (MAX, 2),
               (MAX - 7, 8), (MAX - 6, 8), (MAX + 1, 1), (USIZE_MAX, 1),
               (0, 0), (MAX + 1, 0), (USIZE_MAX, 3), (0, 3), (MAX // 4, 4), (MAX // 8, 8))
    for size, alignment in layouts:
        for requested in alignments: append(5, size, alignment, requested)
        for count in sizes: append(6, size, alignment, count)
        if not classification(size, alignment):
            stride = rounded(size, alignment)
            quotient = MAX // stride if stride else USIZE_MAX
            for count in (0, 1, 2, max(0, quotient - 1), quotient, min(USIZE_MAX, quotient + 1), USIZE_MAX):
                append(6, size, alignment, count)
        for other_size, other_alignment in layouts:
            append(7, size, alignment, other_size, other_alignment)

    # Independent arithmetic record construction: retain unpadded intermediate
    # sizes, then explicitly request padding and arrays of the resulting record.
    record = (0, 1)
    for field in ((1, 1), (3, 4), (8, 8), (0, 64), (2, 2)):
        append(7, *record, *field)
        offset = rounded(record[0], field[1])
        record = (offset + field[0], max(record[1], field[1]))
        append(4, *record)
        append(6, *record, 17)

    rng = random.Random(SEED)
    for index in range(2000):
        operation = rng.randrange(8)
        b = rng.choice(tuple(sorted(POWERS))) if rng.randrange(4) else rng.choice(alignments)
        a = rng.choice(sizes) if rng.randrange(2) else rng.getrandbits(64)
        if index % 3 == 0:
            a, b = rng.randrange(4097), 1 << rng.randrange(13)
        elif b in POWERS and index % 3 == 1:
            last = (MAX // b) * b
            a = min(USIZE_MAX, max(0, last + rng.choice((-1, 0, 1))))
        c, d = rng.getrandbits(64), rng.choice(alignments)
        if operation == 5:
            c = rng.choice(tuple(sorted(POWERS))) if rng.randrange(2) else rng.choice(alignments)
        elif operation == 6:
            c = rng.choice(sizes)
            if not classification(a, b) and rounded(a, b) and index % 2:
                quotient = MAX // rounded(a, b)
                c = min(USIZE_MAX, max(0, quotient + rng.choice((-1, 0, 1))))
        elif operation == 7:
            c = rng.choice(sizes)
            if index % 3 == 0: c, d = rng.randrange(4097), 1 << rng.randrange(13)
        else:
            c, d = 0, 1
        append(operation, a, b, c, d)
    assert len(result) == 18878
    return result


def packet(values):
    result = bytearray()
    for case in values:
        assert case.operation in range(8) and case.mutation in (0, 1)
        assert all(0 <= value <= USIZE_MAX for value in (case.a, case.b, case.c, case.d))
        result += struct.pack("<8Q", case.operation, case.a, case.b, case.c, case.d,
                              case.mutation, case.identity, 0)
    return result


def encode(values): return b"".join(struct.pack("<10Q", *reference(case)) for case in values)


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = reference(case)
        assert offset + WORDS * 8 <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        got = struct.unpack_from("<10Q", actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += WORDS * 8
    assert offset == len(actual), (offset, len(actual), "extra output")


def case(operation, a, b, c=0, d=1): return Case(operation, a, b, c, d, 0, 1)


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values), values)
    constructor = case(0, 7, 8)
    assert reference(constructor)[:6] == [0, 0, 0, 7, 8, 0]
    assert reference(case(4, 7, 8))[:6] == [4, 0, 0, 8, 8, 0]
    assert reference(case(3, MAX, 1))[:6] == [3, 0, 0, 0, 0, 0]
    assert reference(case(3, 0, 1 << 63))[:6] == [3, 0, 0, 0, 0, 0]
    assert reference(case(3, 1, 1 << 63))[:6] == [3, 1, 2, 0, 0, 0]
    array = case(6, 3, 4, 2)
    assert reference(array)[:6] == [6, 0, 0, 8, 4, 4]
    zero = case(6, 0, 1 << 63, USIZE_MAX)
    assert reference(zero)[:6] == [6, 0, 0, 0, 1 << 63, 0]
    assert reference(case(6, 1, 1, MAX))[:6] == [6, 0, 0, MAX, 1, 1]
    assert reference(case(6, 1, 1, MAX + 1))[:6] == [6, 1, 2, 0, 0, 0]
    assert reference(case(6, USIZE_MAX, 0, 0))[:6] == [6, 1, 1, 0, 0, 0]
    extend = case(7, 3, 4, 2, 2)
    assert reference(extend)[:6] == [7, 0, 0, 6, 4, 4]
    assert reference(case(7, 0, 8, MAX, 1))[:6] == [7, 1, 2, 0, 0, 0]
    precedence = case(7, MAX + 1, 1, 0, 0)
    assert reference(precedence)[:6] == [7, 1, 2, 0, 0, 0]
    assert reference(case(5, MAX + 1, 1, 0))[:6] == [5, 1, 2, 0, 0, 0]
    assert reference(case(5, 0, 0, 0))[:6] == [5, 1, 1, 0, 0, 0]
    assert reference(case(3, USIZE_MAX, 3))[:6] == [3, 1, 1, 0, 0, 0]
    assert reference(case(0, 0, 1 << 63))[:6] == [0, 0, 0, 0, 1 << 63, 0]
    invalid_bool = case(2, 0, 0)
    assert reference(invalid_bool)[:6] == [2, 2, 0, 0, 0, 0]
    mutations = ((constructor, 3, 8), (precedence, 2, 1), (array, 5, 3),
                 (zero, 4, 0), (extend, 5, 3), (extend, 6, 0), (invalid_bool, 5, 1))
    for value, word, replacement in mutations:
        wrong = bytearray(encode([value]))
        struct.pack_into("<Q", wrong, word * 8, replacement)
        try:
            verify(wrong, [value])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted deliberate corruption", value, word))
    operations, outcomes, forms = Counter(), Counter(), Counter()
    for value in values:
        words = reference(value)
        operations[value.operation] += 1
        outcomes[(words[1], words[2])] += 1
        forms[value.mutation] += 1
    assert len(operations) == 8 and all(forms[value] for value in (0, 1))
    assert all(outcomes[value] for value in ((0, 0), (1, 1), (1, 2), (2, 0)))
    assert {value.b for value in values if value.b in POWERS} == POWERS
    print(f"layout-model CPU cases={len(values)} functions=8 forms=2 seed={SEED:#x} corruption-controls=7")
    print(f"layout-model operations={dict(sorted(operations.items()))} outcomes={dict(sorted(outcomes.items()))} forms={dict(forms)}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    output = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70)
    assert output.returncode == 0, (output.returncode, output.stderr, len(output.stdout))
    assert not output.stderr, output.stderr
    verify(output.stdout, values)
    print(f"layout-model cases={len(values)} functions=8 forms=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
