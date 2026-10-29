"""Materialized sequence decisions and exact effects; test infrastructure only.

Independent sources use whole prefix/adjacency relations before deriving the
finite effect trace. Shared aliases use alternating positions in one sequence.
No production traversal engine is reproduced, and no Python float is created.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, replace
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xC0A0261104
MASK, SIGN = (1 << 64) - 1, 1 << 63
MIN_I64, MAX_I64 = -(1 << 63), (1 << 63) - 1
INFINITY = 0x7FF0000000000000


@dataclass(frozen=True)
class Case:
    operation: int
    layout: int
    policy: int
    strict: bool
    alias: int
    source: int
    left: tuple
    right: tuple
    front_left: int
    back_left: int
    front_right: int
    back_right: int
    take_left: int
    take_right: int


def relation(case, a, b):
    left, left_bits = a
    right, right_bits = b
    if case.policy == 3:
        a_magnitude, b_magnitude = left_bits & (SIGN - 1), right_bits & (SIGN - 1)
        if max(a_magnitude, b_magnitude) > INFINITY: return 3
        if a_magnitude == b_magnitude == 0: return 1
        # Finite IEEE encodings and infinities are monotone within each sign.
        a_rank = (MASK ^ left_bits) if left_bits & SIGN else left_bits | SIGN
        b_rank = (MASK ^ right_bits) if right_bits & SIGN else right_bits | SIGN
        return 0 if a_rank < b_rank else (2 if a_rank > b_rank else 1)
    if case.policy == 2:
        left = (-1 if left < 0 else 1) * (abs(left) // 3)
        right = (-1 if right < 0 else 1) * (abs(right) // 3)
    order = 0 if left < right else (2 if left > right else 1)
    return 2 - order if case.policy == 1 else order


def sequence(case, right=False):
    data = case.right if right else case.left
    front, back = (case.front_right, case.back_right) if right else (case.front_left, case.back_left)
    selected = list(range(front, len(data) - back))
    if case.source == 1: selected.reverse()
    if case.source == 2: selected = selected[:case.take_right if right else case.take_left]
    return selected


def pull(side, present): return [side, int(present), 0, 0, 0, 0, 0, 0]


def callback(case, ai, bi):
    a = case.left[ai]
    b = (case.left if case.alias or case.operation >= 6 else case.right)[bi]
    aid = 101 + ai
    bid = (101 if case.alias or case.operation >= 6 else 201) + bi
    order = relation(case, a, b)
    kind = (7, 3, 0, 4, 9, 5, 10, 6)[case.operation]
    if not kind: return []  # Natural<T>'s internal Ord.lt strategy is not fixed here.
    if case.operation in (0, 1): result = int(order == 1)
    elif case.operation in (6, 7):
        result = int(order == 0 or (order == 1 and not (case.operation == 7 and case.strict)))
    else: result = order
    return [kind, aid, bid, a[0], b[0], a[1], b[1], result]


def item(case, index, right):
    aliased = bool(case.alias)
    data = case.left if aliased or not right else case.right
    key, bits = data[index]
    identity = (101 if aliased or not right else 201) + index
    if right and case.operation % 2:
        extra = [identity * 97 + 3, SIGN + identity * 131]
    else:
        flag = 0 if identity % 3 == 0 else (2 if identity % 2 == 0 else 1)
        extra = [MASK - identity * 17, flag]
    return [1, identity, key, bits] + extra


def reference(case):
    left, right = sequence(case), sequence(case, True)
    events = []
    if case.operation >= 6:
        adjacent = list(zip(left, left[1:]))
        outcomes = [relation(case, case.left[a], case.left[b]) for a, b in adjacent]
        accepted = [order == 0 or (order == 1 and not (case.operation == 7 and case.strict))
                    for order in outcomes]
        bad = next((index for index, value in enumerate(accepted) if not value), None)
        count = len(left) if bad is None else bad + 2
        result = int(bad is None)
        events += pull(1, bool(left))
        for position in range(1, count):
            events += pull(1, True) + callback(case, left[position - 1], left[position])
        if left and bad is None: events += pull(1, False)
        remaining_left, remaining_right = left[count:], right
    else:
        if case.alias:
            common = left
            compared_left, compared_right = common[::2], common[1::2]
        else:
            compared_left, compared_right = left, right
        pairs = list(zip(compared_left, compared_right))
        orders = [relation(case, case.left[a], (case.left if case.alias else case.right)[b]) for a, b in pairs]
        decisive = next((index for index, order in enumerate(orders) if order != 1), None)
        equal_operation = case.operation in (0, 1)
        if decisive is not None:
            rounds = decisive + 1
            result = 0 if equal_operation else orders[decisive]
        else:
            rounds = len(pairs) + 1
            length_order = 0 if len(compared_left) < len(compared_right) else (2 if len(compared_left) > len(compared_right) else 1)
            result = int(length_order == 1) if equal_operation else length_order
        right_side = 1 if case.alias == 2 else 2
        for position in range(rounds):
            events += pull(1, position < len(compared_left)) + pull(right_side, position < len(compared_right))
            if position < len(pairs): events += callback(case, *pairs[position])
        if case.alias:
            consumed = min(rounds * 2, len(common))
            remaining_left, remaining_right = common[consumed:], []
        else:
            remaining_left, remaining_right = left[rounds:], right[rounds:]
    output = [result, len(events) // 8] + events
    for right_side, remaining in ((False, remaining_left), (True, remaining_right)):
        for index in remaining: output += item(case, index, right_side)
        output.append(0)
    lb, rb = list(range(200, 216)), list(range(220, 236))
    lb[2:2 + len(case.left)] = range(len(case.left))
    rb[2:2 + len(case.right)] = range(len(case.right))
    output += [word for pair in zip(lb, rb) for word in pair]
    for index in range(12):
        a = case.left[index] if index < len(case.left) else (-700 - index, 0xFEDCBA9876543210 + index)
        b = case.right[index] if index < len(case.right) else (-900 - index, 0x0123456789ABCDEF + index)
        output += list(a) + list(b)
    assert len(events) // 8 <= 64
    return [word & MASK for word in output]


def values(numbers):
    return tuple((number, (0x7FF8000000000000 ^ ((number & MASK) * 131 + index)) & MASK)
                 for index, number in enumerate(numbers))


def cases():
    result, seen = [], set()
    def append(operation, left=(), right=(), policy=0, strict=False, alias=0, source=0,
               front_left=0, back_left=0, front_right=0, back_right=0, take_left=0, take_right=0,
               raw=False):
        if policy == 3 and operation in (2, 3): return
        if alias == 2 and operation % 2: return
        if not raw: left, right = values(left), values(right)
        if operation >= 6:
            right, alias, front_right, back_right, take_right = (), 0, 0, 0, 0
        if operation != 7: strict = False
        if source != 2: take_left = take_right = 0
        for layout in range(2):
            case = Case(operation, layout, policy, strict, alias, source, tuple(left), tuple(right),
                        front_left, back_left, front_right, back_right, take_left, take_right)
            assert front_left + back_left <= len(left) and front_right + back_right <= len(right)
            if case not in seen:
                seen.add(case)
                result.append(case)

    binary = [seq for size in range(4) for seq in itertools.product((0, 1), repeat=size)]
    for left, right in itertools.product(binary, repeat=2):
        for operation in range(6): append(operation, left, right)
    ternary = [seq for size in range(4) for seq in itertools.product((-1, 0, 1), repeat=size)]
    for index, (left, right) in enumerate(itertools.product(ternary, repeat=2)):
        append(index % 6, left, right)
    for left in ternary:
        for policy in range(3):
            append(6, left, policy=policy)
            for strict in (False, True): append(7, left, policy=policy, strict=strict)

    anchors = ((), (0,), (1,), (1, 1), (0, 1), (1, 0), (-3, -2, -1, 0, 1, 2, 3),
               (0, 0, 1, 1), (1, 1, 0, 0), (MIN_I64, 0, MAX_I64), (2, 2, 2, 2),
               (0, 1, 2, 3, 4), (0, 1, 2, 4, 3))
    for index, left in enumerate(anchors):
        for right in (left, left[:-1], left + (2,), tuple(reversed(left))):
            for operation in range(6):
                for policy in (1, 2): append(operation, left, right, policy=policy)
        for operation in range(6):
            append(operation, left, alias=1)
            append(operation, left, alias=2)
        for source in (1, 2):
            for operation in range(8):
                append(operation, left, tuple(reversed(left)), source=source,
                       take_left=index % (len(left) + 2), take_right=(index + 1) % (len(left) + 2))
    for left in ternary:
        for operation in range(6): append(operation, left, alias=1)
        for operation in (0, 2, 4): append(operation, left, alias=2)
    for source in range(3):
        for operation in range(8):
            for front_left, back_left, front_right, back_right in ((1, 2, 2, 1), (0, 5, 4, 1), (2, 0, 0, 3)):
                append(operation, (9, 1, 2, 2, 3, 8), (7, 2, 2, 3, 4, 6), source=source,
                       front_left=front_left, back_left=back_left, front_right=front_right, back_right=back_right,
                       take_left=3, take_right=4)

    ieee = (0, SIGN, 1, SIGN | 1, 0x0010000000000000, 0x8010000000000000,
            0x3FF0000000000000, 0xBFF0000000000000, INFINITY, SIGN | INFINITY,
            0x7FF8000000000001, 0xFFF8000000000123, 0x7FF0000000000001)
    for a, b in itertools.product(ieee, repeat=2):
        left, right = ((0, a),), ((0, b),)
        for operation in (0, 1, 4, 5): append(operation, left, right, policy=3, raw=True)
        for operation in (6, 7): append(operation, left + right, policy=3, raw=True)
    for bits in ieee:
        for operation in (6, 7): append(operation, ((42, bits),), policy=3, raw=True)
        for operation in (0, 1, 4, 5):
            append(operation, ((0, 0), (42, bits), (99, 0)), ((0, SIGN), (42, bits), (98, 0)), policy=3, raw=True)
    rng = random.Random(SEED)
    for index in range(320):
        length_left, length_right = rng.randrange(13), rng.randrange(13)
        left = tuple(rng.randrange(-8, 9) for _ in range(length_left))
        right = tuple(rng.randrange(-8, 9) for _ in range(length_right))
        operation = index % 8
        source = rng.randrange(3)
        alias = rng.choice((0, 0, 1))
        append(operation, left, right, policy=rng.randrange(3), strict=bool(index % 2), alias=alias, source=source,
               take_left=rng.randrange(15), take_right=rng.randrange(15))
    return result


def packet(corpus):
    result = bytearray()
    for case in corpus:
        assert len(case.left) <= 12 and len(case.right) <= 12
        assert case.policy != 3 or case.operation not in (2, 3)
        header = (case.operation, case.layout, case.policy, case.strict, case.alias, case.source,
                  len(case.left), len(case.right), case.front_left, case.back_left,
                  case.front_right, case.back_right, case.take_left, case.take_right)
        words = header + tuple(word for value in case.left + case.right for word in value)
        result += struct.pack('<' + 'Q' * len(words), *(word & MASK for word in words))
    return result


def encoded(corpus):
    result = bytearray()
    for case in corpus:
        words = reference(case)
        result += struct.pack('<' + 'Q' * len(words), *words)
    return result


def verify(actual, corpus):
    offset = 0
    for index, case in enumerate(corpus):
        expected = reference(case)
        size = len(expected) * 8
        assert offset + size <= len(actual), (f'seed={SEED:#x}', index, case, 'truncated')
        observed = list(struct.unpack_from('<' + 'Q' * len(expected), actual, offset))
        assert observed == expected, (f'seed={SEED:#x}', index, case, observed, expected)
        offset += size
    assert offset == len(actual), (offset, len(actual), 'extra output')


def controls():
    def sample(operation=1, **changes):
        fields = dict(operation=operation, layout=0, policy=0, strict=False, alias=0, source=0,
                      left=values((0, 1, 2)), right=values((0, 9, 2)),
                      front_left=0, back_left=0, front_right=0, back_right=0, take_left=0, take_right=0)
        fields.update(changes)
        return Case(**fields)
    different = sample()
    words = reference(different)
    assert words[:2] == [0, 6]
    assert words[2:10] == pull(1, True) and words[10:18] == pull(2, True)
    assert words[18:26] == [3, 101, 201, 0, 0, values((0,))[0][1], values((0,))[0][1], 1]
    equal = sample(right=values((0, 1, 2)))
    assert reference(equal)[:2] == [1, 11]
    prefix = sample(operation=3, right=values((0,)))
    assert reference(prefix)[:2] == [2, 5]
    reverse_prefix = replace(prefix, policy=1)
    assert reference(reverse_prefix)[0] == 2  # Structural length is not reversed.
    alias = sample(operation=0, left=values((1, 1, 1)), right=(), alias=2)
    assert reference(alias)[:2] == [0, 5]
    assert reference(alias)[2:10] == pull(1, True)
    assert reference(alias)[10:18] == pull(1, True)
    odd = replace(alias, operation=2)
    assert reference(odd)[:2] == [2, 4]
    sorted_case = sample(operation=7, left=values((0, 1, 0)), right=())
    assert reference(sorted_case)[:2] == [0, 5]
    strict = replace(sorted_case, left=values((1, 1, 2)), strict=True)
    assert reference(strict)[:2] == [0, 3]
    empty = replace(sorted_case, left=())
    assert reference(empty)[:2] == [1, 1]
    single_nan = replace(sorted_case, operation=6, policy=3, left=((0, 0x7FF0000000000001),))
    assert reference(single_nan)[:2] == [1, 2]
    unordered = sample(operation=5, policy=3, left=((0, 0x7FF8000000000001),), right=((0, 0),))
    assert reference(unordered)[:2] == [3, 3]
    zero = replace(unordered, left=((0, SIGN),), right=((0, 0),))
    assert reference(zero)[:2] == [1, 5]
    mutated = ((different, 0, 1), (different, 2, 2), (different, 11, 0),
               (different, 19, 999), (different, 50, 0), (different, -1, 0),
               (unordered, 0, 1), (sorted_case, 1, 6))
    for case, word, replacement in mutated:
        bad = encoded([case])
        if word < 0: word += len(bad) // 8
        assert struct.unpack_from('<Q', bad, word * 8)[0] != replacement
        struct.pack_into('<Q', bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(('accepted verifier corruption', case, word))
    corpus = cases()
    assert len(corpus) == len(set(corpus))
    assert packet(corpus)
    verify(encoded(corpus[::67]), corpus[::67])
    counts = Counter(case.operation for case in corpus)
    sources = Counter(case.source for case in corpus)
    aliases = Counter(case.alias for case in corpus)
    results = Counter((case.operation, reference(case)[0]) for case in corpus)
    print(f'iterator-comparison CPU cases={len(corpus)} operations=8 layouts=2 seed={SEED:#x} verifier-corruptions=8')
    print(f'iterator-comparison operations={dict(sorted(counts.items()))} sources={dict(sorted(sources.items()))} aliases={dict(sorted(aliases.items()))}')
    print(f'iterator-comparison results={dict(sorted(results.items()))}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
        return
    assert len(sys.argv) == 2, 'usage: oracle.py <model-executable> | controls'
    corpus = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(corpus),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, corpus)
    print(f'iterator-comparison cases={len(corpus)} operations=8 layouts=2 seed={SEED:#x}')


if __name__ == '__main__':
    main()
