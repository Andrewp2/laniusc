"""Sorted-reference selection oracle; no BFPRT/selection algorithm is mirrored."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x5E1EC0261101
MASK = (1 << 64) - 1
MIN_I64, MAX_I64 = -(1 << 63), (1 << 63) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
POOL = 48


@dataclass(frozen=True)
class Case:
    family: int
    layout: int
    keys: tuple
    start: int
    length: int
    nth: int
    mode: int
    identity: int


def signed(value):
    return value - (1 << 64) if value >= (1 << 63) else value


def row(key, identity):
    flag = 0 if identity % 3 == 0 else (2 if identity % 2 == 0 else 1)
    return (key & MASK, identity, MASK - identity * 17,
            identity * 97 + 3, (1 << 32) + identity * 131, flag)


def initial(case):
    if case.family == 0:
        values = [(160 + index,) for index in range(POOL)]
    elif case.family == 1:
        values = [(100000 + index,) for index in range(POOL)]
    else:
        values = [row(100000 + index, 4000000000 + index) for index in range(POOL)]
    for index, key in enumerate(case.keys):
        values[4 + index] = (row(key, case.identity * 64 + index + 1)
                             if case.family == 2 else (key & MASK,))
    return values


def rank(item, case):
    value = item[0] if case.family == 0 else signed(item[0])
    if case.family != 2 or case.mode == 0: return value
    if case.mode == 1: return -value
    return value & 3


def admitted(case):
    return (min(case.start, case.length, case.nth) >= 0
            and case.start + case.length <= MAX_I32 and case.nth < case.length)


def mutated(item, case):
    words = list(item)
    words[2 if case.family == 2 else 0] ^= 128 if case.family == 0 else 1 << 63
    return tuple(words)


def dimensions(case):
    width = 6 if case.family == 2 else 1
    return width, 10 + width * (1 + 2 * POOL)


def check(case, words, label):
    width, _ = dimensions(case)
    family, layout, tag, error, start, length, before_calls, after_calls, raw_stride, returned_stride = words[:10]
    assert (family, layout) == (case.family, case.layout), (label, "family/backing")
    stride = signed(raw_stride)
    if case.family == 0:
        assert stride == 1 if case.layout else stride < 0, (label, "byte stride", stride)
    else:
        assert stride < 0, (label, "native storage stride", stride)
    before = 17 + case.identity % 7 if case.family == 2 else 0
    assert before_calls == before and after_calls >= before_calls, (label, "callback counter")
    item = tuple(words[10:10 + width])
    offset = 10 + width
    selected = [tuple(words[at:at + width]) for at in range(offset, offset + POOL * width, width)]
    alias = [tuple(words[at:at + width]) for at in range(offset + POOL * width, len(words), width)]
    original = initial(case)
    if not admitted(case):
        expected_item = row(0, 0) if case.family == 2 else (0,)
        assert (tag, error, start, length, returned_stride) == (1, 1, 0, 0, 0), (label, "Bounds rejection")
        assert item == expected_item and selected == original and alias == original, (label, "rejection mutation")
        assert after_calls == before_calls, (label, "rejected input compared")
        return
    assert (tag, error, start, length) == (0, 0, case.start + case.nth, 1), (label, "returned metadata")
    assert returned_stride == raw_stride, (label, "returned native stride")
    low, high = case.start, case.start + case.length
    old, changed = original[low:high], selected[low:high]
    assert selected[:low] == original[:low] and selected[high:] == original[high:], (label, "surrounding storage")
    assert Counter(changed) == Counter(old), (label, "whole-value permutation", old, changed)
    pivot = changed[case.nth]
    expected_rank = sorted(rank(value, case) for value in old)[case.nth]
    actual_rank = rank(pivot, case)
    assert actual_rank == expected_rank, (label, "selected rank", actual_rank, expected_rank)
    assert all(rank(value, case) <= actual_rank for value in changed[:case.nth]), (label, "before partition")
    assert all(rank(value, case) >= actual_rank for value in changed[case.nth + 1:]), (label, "after partition")
    assert item == pivot, (label, "returned element differs from stored nth")
    expected_alias = list(selected)
    expected_alias[start] = mutated(item, case)
    assert alias == expected_alias, (label, "mutation through returned alias")
    if case.family == 2:
        if case.length == 1: assert after_calls == before_calls, (label, "singleton compared")
        else: assert after_calls > before_calls, (label, "nontrivial selection never compared")
    else:
        assert after_calls == before_calls, (label, "unexpected custom callback")


def cases():
    result, seen = [], set()
    def append(family, keys, start, length, nth, mode=0):
        keys = tuple(keys)
        for layout in range(2):
            shape = (family, layout, keys, start, length, nth, mode)
            if shape in seen: continue
            seen.add(shape)
            result.append(Case(family, layout, keys, start, length, nth, mode, len(result) + 1))

    # Every rank in every length<=4 sequence over a three-value alphabet.
    for length in range(5):
        for keys in itertools.product((-1, 0, 1), repeat=length):
            for nth in range(length):
                append(1, keys, 4, length, nth)
                for mode in range(3): append(2, keys, 4, length, nth, mode)
                append(0, tuple(key + 1 for key in keys), 4, length, nth)

    # Every permutation of five distinct values, with every rank.
    for keys in itertools.permutations(range(5)):
        for nth in range(5):
            append(1, keys, 4, 5, nth)
            append(2, keys, 4, 5, nth, 0)
            append(0, keys, 4, 5, nth)

    # Deliberate shapes at group/short-group boundaries, and interior views.
    for length in (1, 2, 5, 6, 9, 10, 11, 24, 25, 26, 39, 40):
        ascending = tuple(range(length))
        datasets = (ascending, tuple(reversed(ascending)), (7,) * length,
                    tuple(min(index, length - 1 - index) for index in range(length)),
                    tuple(index % 3 for index in range(length)))
        for keys in datasets:
            for nth in sorted({0, length // 2, length - 1}):
                append(1, keys, 4, length, nth)
                append(0, keys, 4, length, nth)
                for mode in range(3): append(2, keys, 4, length, nth, mode)
            if length >= 3:
                for nth in sorted({0, (length - 2) // 2, length - 3}):
                    append(1, keys, 5, length - 2, nth)
                    for mode in range(3): append(2, keys, 5, length - 2, nth, mode)

    extremes = (MIN_I64, MAX_I64, 0, -1, 1, MIN_I64 + 1, MAX_I64 - 1,
                1 << 32, -(1 << 32), MIN_I64, MAX_I64)
    for nth in range(len(extremes)):
        append(1, extremes, 4, len(extremes), nth)
        for mode in range(3): append(2, extremes, 4, len(extremes), nth, mode)

    invalid = ((-1, 3, 0), (MIN_I32, 1, 0), (4, -1, 0), (4, MIN_I32, 0),
               (MAX_I32, 1, 0), (MAX_I32 - 1, 2, 0), (1, MAX_I32, 0),
               (0, MAX_I32, -1), (4, 0, 0), (MAX_I32, 0, 0),
               (4, 4, -1), (4, 4, MIN_I32), (4, 4, 4), (4, 4, MAX_I32))
    for start, length, nth in invalid:
        for family in range(3):
            for mode in range(3 if family == 2 else 1):
                append(family, (3, 1, 2, 1), start, length, nth, mode)
    for family in range(3):
        for mode in range(3 if family == 2 else 1): append(family, (), 4, 0, 0, mode)

    rng = random.Random(SEED)
    for _ in range(200):
        length = rng.randrange(1, 41)
        keys = tuple(rng.choice((MIN_I64, MAX_I64, -1, 0, 1, rng.randrange(-30, 31))) for _ in range(length))
        offset = rng.randrange(length)
        selected = rng.randrange(1, length - offset + 1)
        nth = rng.randrange(selected)
        append(1, keys, 4 + offset, selected, nth)
        append(2, keys, 4 + offset, selected, nth, rng.randrange(3))
        append(0, tuple(key & 255 for key in keys), 4 + offset, selected, nth)
    assert len(result) == 11976
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert len(case.keys) <= 40 and case.layout in (0, 1) and case.mode in range(3)
        assert all(MIN_I64 <= key <= MAX_I64 for key in case.keys)
        if case.family == 0: assert all(0 <= key <= 255 for key in case.keys)
        if admitted(case): assert 4 <= case.start <= case.start + case.length <= 4 + len(case.keys)
        fields = (case.family, case.layout, len(case.keys), case.start, case.length,
                  case.nth, case.mode, case.identity)
        data += struct.pack("<8Q", *(word & MASK for word in fields))
        data += struct.pack("<" + "Q" * len(case.keys), *(key & MASK for key in case.keys))
    return data


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        _, words = dimensions(case)
        size = words * 8
        label = (f"seed={SEED:#x}", index, case)
        assert offset + size <= len(actual), (label, "truncated")
        check(case, struct.unpack_from("<" + "Q" * words, actual, offset), label)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def synthetic(case, reverse_ties=False, change=None):
    values = initial(case)
    before = 17 + case.identity % 7 if case.family == 2 else 0
    stride = 1 if case.family == 0 and case.layout else -1
    if not admitted(case):
        item = row(0, 0) if case.family == 2 else (0,)
        header = [case.family, case.layout, 1, 1, 0, 0, before, before, stride & MASK, 0]
        alias = list(values)
    else:
        ordered = sorted(values[case.start:case.start + case.length], key=lambda value: rank(value, case))
        if reverse_ties:
            ordered = [value for _, group in itertools.groupby(ordered, key=lambda value: rank(value, case))
                       for value in reversed(list(group))]
        nth = case.nth
        values[case.start:case.start + case.length] = list(reversed(ordered[:nth])) + [ordered[nth]] + list(reversed(ordered[nth + 1:]))
        if change: change(values)
        at = case.start + nth
        item = values[at]
        header = [case.family, case.layout, 0, 0, at, 1, before,
                  before + int(case.family == 2 and case.length > 1), stride & MASK, stride & MASK]
        alias = list(values)
        alias[at] = mutated(item, case)
    words = header + list(item) + [word for value in values + alias for word in value]
    return bytearray(struct.pack("<" + "Q" * len(words), *words))


def controls():
    values = cases()
    assert packet(values)
    for reverse_ties in (False, True):
        samples = values[::31]
        verify(b"".join(synthetic(case, reverse_ties) for case in samples), samples)
    case = Case(2, 0, (0, 1, 2, 3, 4), 4, 5, 2, 0, 1)
    good = synthetic(case)
    verify(good, [case])
    def swapped(a, b):
        def change(values): values[a], values[b] = values[b], values[a]
        return change
    wrong_rank = synthetic(case, change=swapped(6, 4))
    wrong_partition = synthetic(case, change=swapped(4, 8))
    wrong_alias = bytearray(good)
    # Restore the stored pivot marker in the second snapshot: alias went nowhere.
    width, _ = dimensions(case)
    first_marker = 10 + width + 6 * width + 2
    alias_marker = first_marker + POOL * width
    struct.pack_into("<Q", wrong_alias, alias_marker * 8, struct.unpack_from("<Q", good, first_marker * 8)[0])
    corruptions = [wrong_rank, wrong_partition, wrong_alias]
    for word, replacement in ((4, 5), (10 + 1, 123),
                               (10 + width + 2, 0), (10 + width + 4 * width + 3, 0)):
        bad = bytearray(good)
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        corruptions.append(bad)
    for bad in corruptions:
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError("accepted deliberate corruption")
    # Independent integer simulation of the median-only frame depth, not a
    # native i32::MAX allocation or a restatement of the fixed stack size.
    active, depth = MAX_I32, 1
    while active > 5:
        active = (active + 4) // 5
        depth += 1
    assert depth == 14
    counts = Counter((case.family, case.mode) for case in values)
    invalid = sum(not admitted(case) for case in values)
    singleton = sum(admitted(case) and case.length == 1 for case in values)
    print(f"slice-selection CPU cases={len(values)} families=3 forms=2 policies=3 seed={SEED:#x} corruption-controls=7 frame-depth={depth}")
    print(f"slice-selection families-policies={dict(sorted(counts.items()))} rejected={invalid} singletons={singleton}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f"slice-selection cases={len(values)} families=3 forms=2 policies=3 seed={SEED:#x}")


if __name__ == "__main__":
    main()
