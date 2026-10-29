"""Independent host-stable key ordering, full values and admission expectations.

No merge passes, workspace operations or production sorting engine are modeled.
Python and binary transport are test infrastructure only.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x57AB1E0261104
MASK, SIGN = (1 << 64) - 1, 1 << 63
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
MIN_I64, MAX_I64 = -(1 << 63), (1 << 63) - 1
POOL = 72


@dataclass(frozen=True)
class Case:
    family: int
    layout: int
    data: tuple
    start: int
    length: int
    capacity_overflow: bool
    actions: tuple
    identity: int


def row(key, secondary, identity):
    flag = 0 if identity % 3 == 0 else (2 if identity % 2 == 0 else 1)
    event = (0, identity * 19 + 7, 0) if identity % 3 == 0 else (1, identity * 23 + 3, (1 << 62) + identity * 29)
    return (key & MASK, secondary & MASK, identity, MASK - identity * 17,
            identity * 97 + 3, SIGN + identity * 131, flag) + event


def initial(case):
    values = ([(160 + index,) for index in range(POOL)] if case.family == 0 else
              [row(10000 + index, -10000 - index, 4000000000 + index) for index in range(POOL)])
    for index, (key, secondary) in enumerate(case.data):
        values[4 + index] = (key,) if case.family == 0 else row(key, secondary, case.identity * 128 + index + 1)
    return values


def signed(value): return value - (1 << 64) if value & SIGN else value


def rank(item, family, operation, mode):
    primary = item[0] if family == 0 else signed(item[0])
    if operation == 0: return primary
    if mode == 2: return primary & 3
    return signed(item[1]) if family == 1 and mode in (3, 4) else primary


def expected(case, values, action, item_size):
    length = MAX_I32 // item_size + 1 if case.capacity_overflow else case.length
    if min(case.start, length) < 0 or case.start + length > MAX_I32: return 1, 1, 0, values, length
    if length <= 1: return 0, 0, length, values, length
    if item_size and length * item_size > MAX_I32: return 1, 4, 0, values, length
    assert case.start + length <= POOL, (case, length, 'unbacked accepted model request')
    operation, mode = action
    chosen = values[case.start:case.start + length]
    ordered = sorted(chosen, key=lambda item: rank(item, case.family, operation, mode),
                     reverse=bool(operation and mode in (1, 4)))
    changed = values[:case.start] + ordered + values[case.start + length:]
    assert Counter(changed) == Counter(values)
    return 0, 0, length, changed, length


def cases():
    result, seen = [], set()
    def append(family, keys=(), start=4, length=None, overflow=False, actions=((0, 0),), secondary=None):
        keys = tuple(keys)
        if secondary is None: secondary = tuple((index * 7) % 5 - 2 for index in range(len(keys)))
        if family == 0: secondary = (0,) * len(keys)
        data = tuple(zip(keys, secondary))
        if length is None: length = len(keys)
        for layout in range(2):
            shape = (family, layout, data, start, length, bool(overflow), tuple(actions))
            if shape not in seen:
                seen.add(shape)
                result.append(Case(*shape, len(result) + 1))

    profiles = (((0, 0),), ((1, 0),), ((1, 1),), ((1, 2),), ((1, 3), (1, 0), (1, 4), (1, 2)))
    for size in range(6):
        for keys in itertools.product((-1, 0, 1), repeat=size):
            for actions in profiles: append(1, keys, actions=actions)
    for size in range(5):
        for keys in itertools.product((0, 1, 2), repeat=size):
            for actions in profiles[:4]: append(0, keys, actions=actions)

    # Interior views select arbitrary portions without relying on sort internals.
    for family, keys in ((0, (7, 3, 5, 3, 0, 7)), (1, (2, -1, 3, -1, 0, 2))):
        for start in range(2, 12):
            for length in range(min(8, POOL - start) + 1):
                append(family, keys, start, length, actions=((1, 2), (0, 0)))
        for start, length in ((MIN_I32, 0), (-1, 0), (0, -1), (0, MIN_I32),
                              (MAX_I32, 1), (MAX_I32 - 1, 2), (MAX_I32, 0),
                              (MAX_I32 - 1, 1), (0, 0), (0, 1)):
            append(family, keys, start, length, actions=((0, 0), (1, 1)))
    for start in (0, 1, MAX_I32):
        append(1, (1, 0), start, 0, overflow=True, actions=((0, 0), (1, 0)))
    append(1, (1, 0), 0, MAX_I32, actions=((0, 0), (1, 0)))

    lengths = (6, 7, 8, 9, 15, 16, 17, 23, 31, 32, 33, 47, 63, 64, 65)
    for size in lengths:
        patterns = (tuple(range(size)), tuple(reversed(range(size))), (3,) * size,
                    tuple(index % 5 for index in range(size)), tuple(min(index, size - index - 1) for index in range(size)),
                    tuple((index * 37) % 11 for index in range(size)))
        for family, keys in itertools.product(range(2), patterns):
            append(family, keys, actions=((1, 2), (1, 1), (0, 0)))
            if family: append(family, keys, actions=profiles[-1])
    for keys in ((MIN_I64, MAX_I64, 0, MIN_I64, MAX_I64, -1, 0),
                 (MAX_I64, MAX_I64 - 1, MIN_I64 + 1, MIN_I64), (1 << 32, 0, -(1 << 32), 1 << 32)):
        for actions in profiles: append(1, keys, actions=actions)
    rng = random.Random(SEED)
    for index in range(180):
        family = index % 2
        size = rng.randrange(66)
        keys = tuple(rng.randrange(256) if family == 0 else rng.choice((rng.randrange(-10, 11), MIN_I64, MAX_I64)) for _ in range(size))
        secondary = tuple(rng.randrange(-8, 9) for _ in range(size))
        start_offset = rng.randrange(size + 1)
        length = rng.randrange(size - start_offset + 1)
        actions = profiles[rng.randrange(4 + family)]
        append(family, keys, 4 + start_offset, length, actions=actions, secondary=secondary)
    return result


def packet(corpus):
    result = bytearray()
    for case in corpus:
        assert len(case.data) <= 65 and 1 <= len(case.actions) <= 4
        assert MIN_I32 <= case.start <= MAX_I32 and MIN_I32 <= case.length <= MAX_I32
        assert case.family or all(0 <= key <= 255 for key, _ in case.data)
        header = (case.family, case.layout, len(case.data), case.start, case.length,
                  case.capacity_overflow, len(case.actions), case.identity)
        words = header + tuple(word for item in case.data for word in item) + tuple(word for action in case.actions for word in action)
        result += struct.pack('<' + 'Q' * len(words), *(word & MASK for word in words))
    return result


def verify(actual, corpus):
    offset, sizes = 0, {}
    for case_index, case in enumerate(corpus):
        values = initial(case)
        width = 1 if case.family == 0 else 10
        previous_calls = 11 + case.identity % 7
        for action_index, action in enumerate(case.actions):
            count = 7 + POOL * width
            assert offset + count * 8 <= len(actual), (SEED, case_index, case, 'truncated')
            words = struct.unpack_from('<' + 'Q' * count, actual, offset)
            tag, code, result, before, after, size, raw_stride = words[:7]
            stride = signed(raw_stride)
            if case.family == 0:
                assert size == 1 and (stride < 0 if case.layout == 0 else stride == 1), (case, 'byte layout', size, stride)
            else:
                assert 0 < size <= 8192 // POOL and size % 8 == 0 and stride < 0, (case, 'record layout', size, stride)
            assert sizes.setdefault(case.family, size) == size, (case, 'inconsistent type size')
            wanted_tag, wanted_code, wanted_result, changed, length = expected(case, values, action, size)
            assert (tag, code, result) == (wanted_tag, wanted_code, wanted_result), (f'seed={SEED:#x}', case_index, action_index, case, 'result', words[:7])
            assert before == previous_calls and after >= before, (case, 'callback counter', before, after, previous_calls)
            if tag or length < 2 or (case.family == 0 and action[0] == 0):
                assert after == before, (case, 'unexpected comparison', action, before, after)
            else:
                ceiling = length * (length - 1).bit_length()
                if case.family == 1 and action[0] == 0: ceiling *= 2
                assert 0 < after - before <= ceiling, (case, 'comparison ceiling', action, after - before, ceiling)
            observed = [tuple(words[7 + index * width:7 + (index + 1) * width]) for index in range(POOL)]
            assert observed == changed, (f'seed={SEED:#x}', case_index, action_index, case, observed, changed)
            values, previous_calls = changed, after
            offset += count * 8
    assert offset == len(actual), (offset, len(actual), 'extra output')


def encoded(corpus, item_size=96):
    # Synthetic records exercise the serialized-output verifier only. They do
    # not simulate a native allocation or assert an actual comparison count.
    output = bytearray()
    for case in corpus:
        values = initial(case)
        size = 1 if case.family == 0 else item_size
        calls = 11 + case.identity % 7
        for action in case.actions:
            tag, code, result, values, length = expected(case, values, action, size)
            before = calls
            if not tag and length >= 2 and (case.family or action[0]): calls += 1
            stride = (1 if case.layout else -8) if case.family == 0 else -size
            words = (tag, code, result, before, calls, size, stride) + tuple(word for item in values for word in item)
            output += struct.pack('<' + 'Q' * len(words), *(word & MASK for word in words))
    return output


def controls():
    def sample(**changes):
        fields = dict(family=1, layout=0, data=((2, 0), (1, 2), (2, 1), (1, 0)), start=4, length=4,
                      capacity_overflow=False, actions=((1, 0),), identity=1)
        fields.update(changes)
        return Case(**fields)
    case = sample()
    _, _, _, ordered, _ = expected(case, initial(case), case.actions[0], 96)
    assert [item[2] for item in ordered[4:8]] == [130, 132, 129, 131]
    equal = sample(data=((3, 9), (3, 8), (3, 7), (3, 6)))
    assert expected(equal, initial(equal), equal.actions[0], 96)[3] == initial(equal)
    grouped = sample(data=((2, 0), (6, 1), (-2, 2), (1, 3)), actions=((1, 2),))
    assert [item[2] for item in expected(grouped, initial(grouped), grouped.actions[0], 96)[3][4:8]] == [132, 129, 130, 131]
    multi = sample(data=((2, 0), (1, 2), (2, 1), (1, 0)), actions=((1, 3), (1, 0)))
    values = initial(multi)
    for action in multi.actions: values = expected(multi, values, action, 96)[3]
    assert [item[2] for item in values[4:8]] == [132, 130, 129, 131]
    assert expected(sample(start=MAX_I32, length=0), initial(case), (0, 0), 96)[:3] == (0, 0, 0)
    assert expected(sample(start=MAX_I32 - 1, length=1), initial(case), (0, 0), 96)[:3] == (0, 0, 1)
    assert expected(sample(start=MAX_I32, length=1), initial(case), (0, 0), 96)[:3] == (1, 1, 0)
    cap = sample(capacity_overflow=True, start=0)
    assert expected(cap, initial(cap), (0, 0), 96)[:3] == (1, 4, 0)
    assert expected(sample(capacity_overflow=True, start=MAX_I32), initial(case), (0, 0), 96)[:3] == (1, 1, 0)
    mutations = []
    original = encoded([case])
    for word, replacement in ((0, 1), (2, 3), (4, 11 + case.identity % 7), (5, 0), (6, 0), (7, 0)):
        bad = bytearray(original)
        assert struct.unpack_from('<Q', bad, word * 8)[0] != replacement
        struct.pack_into('<Q', bad, word * 8, replacement)
        mutations.append(bad)
    # Swap whole equivalent rows: still sorted and a permutation, but unstable.
    unstable = bytearray(original)
    a, b, size = (7 + 4 * 10) * 8, (7 + 5 * 10) * 8, 80
    unstable[a:a + size], unstable[b:b + size] = unstable[b:b + size], unstable[a:a + size]
    mutations.append(unstable)
    corrupted_payload = bytearray(original)
    struct.pack_into('<Q', corrupted_payload, (7 + 4 * 10 + 3) * 8, 0)
    mutations.append(corrupted_payload)
    for index, bad in enumerate(mutations):
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(('accepted verifier corruption', index))
    corpus = cases()
    assert len({(case.family, case.layout, case.data, case.start, case.length, case.capacity_overflow, case.actions) for case in corpus}) == len(corpus)
    assert packet(corpus)
    verify(encoded(corpus[::59]), corpus[::59])
    actions = sum(len(case.actions) for case in corpus)
    print(f'stable-sort CPU cases={len(corpus)} actions={actions} families=2 layouts=2 seed={SEED:#x} verifier-corruptions=8')
    print(f'stable-sort families={dict(sorted(Counter(case.family for case in corpus).items()))} length-selectors={dict(sorted(Counter(int(case.capacity_overflow) for case in corpus).items()))}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
        return
    assert len(sys.argv) == 2, 'usage: oracle.py <model-executable> | controls'
    corpus = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(corpus), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, corpus)
    print(f'stable-sort cases={len(corpus)} actions={sum(len(case.actions) for case in corpus)} families=2 layouts=2 seed={SEED:#x}')


if __name__ == '__main__':
    main()
