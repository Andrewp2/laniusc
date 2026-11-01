"""Independent tagged-value tables for eager Option/Result compositions.

Payloads remain integer bit patterns. Python does not construct floating
values, call the product library or infer output tags from numeric payloads.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x0A7C20261031
MASK = (1 << 64) - 1
OBSERVATION_WORDS = 13
WORDS = 4 * OBSERVATION_WORDS


@dataclass(frozen=True)
class Case:
    operation: int
    method: int
    variant: int
    a: int
    b: int
    c: int
    d: int
    identity: int


def some(value): return ("some", value)
def ok(value): return ("ok", value)
def err(value): return ("err", value)


def item(first, second):
    flag = 0 if first & 3 == 0 else (2 if first & 1 == 0 else 1)
    return (first, first, second, second, flag)


def fault(first, second):
    code = first & ((1 << 32) - 1)
    if code & (1 << 31): code -= 1 << 32
    return (code & MASK, second)


def other_fault(first, second): return (first, second, first & 1)


def observation(shape=0, value=None):
    words = [shape] + [0] * 12

    def payload(held): words[3:8] = held
    def failure(held): words[8:10] = held
    def replacement(held): words[10:13] = held

    if shape in (1, 8):
        if value is not None:
            words[1] = 1
            if shape == 1: payload(value[1])
            else: words[4] = value[1]
    elif shape in (2, 3, 9):
        if value[0] == "ok":
            if shape == 9: words[4] = value[1]
            else: payload(value[1])
        else:
            words[1] = 1
            (replacement if shape == 3 else failure)(value[1])
    elif shape in (4, 6):
        words[2] = 2
        if value is not None:
            words[1] = 1
            inner = value[1]
            words[2] = 0
            if shape == 4:
                if inner[0] == "ok": payload(inner[1])
                else: words[2] = 1; failure(inner[1])
            elif inner is not None:
                words[2] = 1
                payload(inner[1])
    elif shape in (5, 7):
        words[2] = 2
        if value[0] == "err":
            words[1] = 1
            failure(value[1])
        else:
            inner = value[1]
            words[2] = 0
            if shape == 5:
                if inner is not None: words[2] = 1; payload(inner[1])
            elif inner[0] == "ok": payload(inner[1])
            else: words[2] = 1; failure(inner[1])
    else:
        assert shape == 0
    return words


def to_result(value):
    if value is None: return ok(None)
    return ok(some(value[1][1])) if value[1][0] == "ok" else err(value[1][1])


def to_option(value):
    if value[0] == "err": return some(err(value[1]))
    return None if value[1] is None else some(ok(value[1][1]))


def reference(case):
    op, variant = case.operation, case.variant
    first, second = item(case.a, case.b), item(case.c, case.d)
    first_error, second_error = fault(case.a, case.b), fault(case.c, case.d)
    new_error = other_fault(case.c, case.d)
    right, middle = observation(), observation()
    if op == 0:
        left = some(case.a) if variant & 1 else None
        next_value = some(second) if variant & 2 else None
        result = next_value if left is not None else None
        observed, before, right = observation(1, result), observation(8, left), observation(1, next_value)
    elif op == 1:
        left = ok(case.a) if variant & 1 else err(first_error)
        next_value = ok(second) if variant & 2 else err(second_error)
        result = next_value if left[0] == "ok" else err(first_error)
        observed, before, right = observation(2, result), observation(9, left), observation(2, next_value)
    elif op == 2:
        left = ok(first) if variant & 1 else err(first_error)
        next_value = ok(second) if variant & 2 else err(new_error)
        result = ok(first) if left[0] == "ok" else next_value
        observed, before, right = observation(3, result), observation(2, left), observation(3, next_value)
    elif op == 3:
        source = (ok(ok(first)), ok(err(first_error)), err(second_error))[variant]
        result = source[1] if source[0] == "ok" else err(source[1])
        observed, before = observation(2, result), observation(7, source)
    elif op == 4:
        source = (None, some(None), some(some(first)))[variant]
        result = None if source is None else source[1]
        observed, before = observation(1, result), observation(6, source)
    elif op in (5, 7):
        source = (None, some(ok(first)), some(err(first_error)))[variant]
        result = to_result(source)
        observed, before = observation(5, result), observation(4, source)
        if op == 7:
            middle = observed
            restored = to_option(result)
            assert restored == source
            observed = observation(4, restored)
    else:
        assert op in (6, 8)
        source = (ok(None), ok(some(first)), err(first_error))[variant]
        result = to_option(source)
        observed, before = observation(4, result), observation(5, source)
        if op == 8:
            middle = observed
            restored = to_result(result)
            assert restored == source
            observed = observation(5, restored)
    return observed + before + right + middle


def cases():
    result = []
    words = (0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF, 0x100000000,
             0x7FFFFFFFFFFFFFFF, 0x8000000000000000, MASK,
             0x0123456789ABCDEF, 0xFEDCBA9876543210,
             0x0010000000000000, 0x000FFFFFFFFFFFFF,
             0x3FF0000000000000, 0xBFF0000000000000,
             0x7FF0000000000000, 0xFFF0000000000000,
             0x7FF0000000000001, 0xFFF0000000000001,
             0x7FF8000000000123, 0xFFF8000000000456)
    payloads = [(0, 0, 0, 0), (MASK, MASK, MASK, MASK)]
    payloads += [(word, words[(index + 1) % len(words)],
                  MASK ^ words[(index + 7) % len(words)], words[(index + 11) % len(words)])
                 for index, word in enumerate(words)]
    assert len(payloads) == 23
    for values in payloads:
        for operation in range(9):
            for method in range(2):
                for variant in range(4 if operation <= 2 else 3):
                    result.append(Case(operation, method, variant, *values, len(result) + 1))
    rng = random.Random(SEED)
    for index in range(800):
        operation, method = rng.randrange(9), rng.randrange(2)
        variant = rng.randrange(4 if operation <= 2 else 3)
        a, b, c, d = (rng.getrandbits(64) for _ in range(4))
        if index % 4 == 0:
            b, d = (0x7FF0000000000000 | (rng.getrandbits(52) or 1) | (rng.randrange(2) << 63)
                    for _ in range(2))
        result.append(Case(operation, method, variant, a, b, c, d, len(result) + 1))
    assert len(result) == 2180
    return result


def packet(values):
    result = bytearray()
    for case in values:
        assert 0 <= case.operation <= 8 and case.method in (0, 1)
        assert 0 <= case.variant < (4 if case.operation <= 2 else 3)
        assert all(0 <= value <= MASK for value in (case.a, case.b, case.c, case.d))
        result += struct.pack("<8Q", case.operation, case.method, case.variant,
                              case.a, case.b, case.c, case.d, case.identity)
    return result


def encode(values):
    return b"".join(struct.pack("<52Q", *reference(case)) for case in values)


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = reference(case)
        assert offset + WORDS * 8 <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        got = struct.unpack_from("<52Q", actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += WORDS * 8
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values), values)
    select = Case(0, 1, 3, 1, MASK, 0xFEDCBA9876543210, 0x7FF0000000000001, 1)
    wanted = reference(select)
    assert wanted[:3] == [1, 1, 0]
    assert wanted[3:8] == [0xFEDCBA9876543210, 0xFEDCBA9876543210,
                           0x7FF0000000000001, 0x7FF0000000000001, 0]
    failed = Case(1, 0, 0, 0x80000000, MASK, 4, 7, 2)
    assert reference(failed)[:3] == [2, 1, 0]
    assert reference(failed)[8:10] == [0xFFFFFFFF80000000, MASK]
    changed_error = Case(2, 0, 0, 0x80000000, MASK, 0xFEDCBA9876543210, 0x123456789ABCDEF0, 3)
    assert reference(changed_error)[8:13] == [0, 0, 0xFEDCBA9876543210, 0x123456789ABCDEF0, 0]
    inverse = Case(7, 1, 2, 0, 0, MASK, MASK, 4)
    assert reference(inverse)[:3] == [4, 1, 1]
    assert reference(inverse)[39:42] == [5, 1, 2]
    mutations = ((select, 1, 0), (select, 4, 0x76543210),
                 (select, 6, 0x7FF8000000000001), (select, 14, 0),
                 (failed, 8, 0x80000000), (changed_error, 10, 0), (inverse, 41, 0))
    for case, word, replacement in mutations:
        wrong = bytearray(encode([case]))
        struct.pack_into("<Q", wrong, word * 8, replacement)
        try:
            verify(wrong, [case])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted deliberate corruption", case, word))
    operations, flavors, variants, shapes, flags = Counter(), Counter(), Counter(), Counter(), Counter()
    for case in values:
        words = reference(case)
        operations[case.operation] += 1
        flavors[case.method] += 1
        variants[(case.operation, case.method, case.variant)] += 1
        shapes[tuple(words[:3])] += 1
        for offset in range(0, WORDS, OBSERVATION_WORDS): flags[words[offset + 7]] += 1
    assert len(variants) == 60 and all(variants.values())
    assert all(flags[value] for value in (0, 1, 2))
    print(f"outcome-composition CPU cases={len(values)} operations=9 flavors=2 "
          f"variant-selectors={len(variants)} seed={SEED:#x} corruption-controls=7")
    print(f"outcome-composition operations={dict(sorted(operations.items()))} "
          f"flavors={dict(sorted(flavors.items()))} primary-shapes={dict(sorted(shapes.items()))}")


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
    print(f"outcome-composition cases={len(values)} operations=9 flavors=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
