"""Independent arbitrary-integer Seek and materialized byte-state reference."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x5EECA0261031
MASK = (1 << 64) - 1
MIN_I64, MAX_I64 = -(1 << 63), (1 << 63) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1


@dataclass(frozen=True)
class Case:
    family: int
    layout: int
    base: int
    cursor: int
    actions: tuple
    identity: int


def signed(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value >= (1 << (width - 1)) else value


def answer(value=None, error=0, host=0):
    return [1, error, host, 0] if error else [0, 0, 0, value]


def arithmetic(base, offset):
    total = base + offset
    return answer(total) if 0 <= total <= MASK else answer(error=1)


def provider_reference(case):
    output, trace = [], []
    position = case.base
    for helper, error, reported, effect in case.actions:
        # Provider effects and acknowledgements are deliberately independent.
        trace.append((1 if helper == 0 else 0, 0))
        position = effect
        if error:
            result = answer(error=error, host=signed(reported, 32) if error == 10 else 0)
        elif helper == 1 and reported != 0:
            result = answer(error=4)
        else:
            result = answer(reported)
        output += result + [position, len(trace)]
        output += [word for call in trace for word in call]
    return output


def slice_reference(case):
    length, cursor = signed(case.base, 32), signed(case.cursor, 32)
    pattern = bytearray((case.identity * 13 + index * 17) & 255 for index in range(32))
    data = pattern if case.family == 2 else bytearray(range(160, 192))
    auxiliary = bytearray(range(192, 224)) if case.family == 2 else pattern
    output = []
    for action, a, b, _ in case.actions:
        if action == 6:
            length, cursor = signed(a, 32), signed(b, 32)
            result = [2, 0, 0, 0]
        elif action == 5:
            assert 0 <= cursor <= length <= 16, (case, "transfer precondition")
            count, offset = signed(a, 32), signed(b, 32)
            if min(offset, count) < 0 or offset + count > MAX_I32:
                result = answer(error=1)
            else:
                amount = min(count, length - cursor)
                assert amount == 0 or offset + amount <= 32
                if case.family == 2:
                    auxiliary[offset:offset + amount] = data[cursor:cursor + amount]
                else:
                    data[cursor:cursor + amount] = auxiliary[offset:offset + amount]
                cursor += amount
                result = answer(amount)
        else:
            origin = action if action < 3 else (1 if action == 3 else 0)
            argument = a if action < 3 else 0
            target = ((argument & MASK) if origin == 0 else
                      (cursor if origin == 1 else length) + signed(argument, 64))
            if not (0 <= cursor <= length and 0 <= target <= length):
                result = answer(error=1)
            else:
                cursor = target
                result = answer(target)
        remaining = length - cursor if 0 <= cursor <= length else 0
        output += result + [cursor, length, cursor, remaining] + list(data) + list(auxiliary)
    return output


def reference(case):
    output = [case.family, case.layout, case.identity]
    if case.family == 0:
        output += arithmetic(case.base, signed(case.cursor, 64)) + [case.base, case.cursor]
    elif case.family == 1:
        output += provider_reference(case)
    else:
        output += slice_reference(case)
    return [word & MASK for word in output]


def cases():
    result = []
    def append(family, layout, base, cursor, actions=()):
        result.append(Case(family, layout, base, cursor, tuple(actions), len(result) + 1))

    bases = {0, 1, 2, 3, 127, 128, 255, 256, MASK, MASK - 1, MASK - 2}
    offsets = {MIN_I64, MIN_I64 + 1, MAX_I64 - 1, MAX_I64, -2, -1, 0, 1, 2}
    for power in (15, 16, 31, 32, 53, 62, 63):
        bases.update((1 << power) + adjustment for adjustment in (-1, 0, 1))
        if power < 63:
            offsets.update(sign * ((1 << power) + adjustment)
                           for sign in (-1, 1) for adjustment in (-1, 0, 1))
    pairs = {(base, offset) for base in bases for offset in offsets}
    for bit in range(64):
        for base in ((1 << bit) - 1, 1 << bit, MASK - (1 << bit)):
            for offset in (MIN_I64, MAX_I64, -1, 0, 1): pairs.add((base, offset))
            for edge in (-base, MASK - base):
                pairs.update((base, edge + adjustment) for adjustment in (-1, 0, 1)
                             if MIN_I64 <= edge + adjustment <= MAX_I64)
    rng = random.Random(SEED)
    for _ in range(3000):
        base = rng.getrandbits(64)
        offset = signed(rng.getrandbits(64), 64)
        pairs.add((base, offset))
        for edge in (-base, MASK - base):
            if MIN_I64 <= edge <= MAX_I64:
                pairs.add((base, edge))
    for base, offset in sorted(pairs): append(0, 0, base, offset)

    payloads = (0, 1, MAX_I32, MAX_I32 + 1, (1 << 32) - 1, 1 << 63, MASK)
    for error in range(11):
        for index, payload in enumerate(payloads):
            actions = tuple((step % 2, error, payload, (payloads[(index + step) % 7]))
                            for step in range(6)) + ((0, 0, MASK, 1), (1, 0, 0, 0))
            append(1, 0, payloads[(index + 1) % 7], 0, actions)
    for _ in range(120):
        actions = tuple((rng.randrange(2), rng.randrange(11), rng.getrandbits(64),
                         rng.getrandbits(64)) for _ in range(8))
        append(1, 0, rng.getrandbits(64), 0, actions)

    def memory(length, cursor, actions):
        for family in (2, 3):
            for layout in range(4): append(family, layout, length, cursor, actions)

    for length in range(9):
        for cursor in range(length + 1):
            for origin in range(3):
                for argument in (-1, 0, 1, length + 1, MIN_I64, MAX_I64):
                    actions = ((origin, argument, 0, 0), (3, 0, 0, 0),
                               (5, 3, 2, 0), (1, -1, 0, 0), (2, 0, 0, 0),
                               (5, 2, 3, 0), (0, 0, 0, 0), (4, 0, 0, 0))
                    memory(length, cursor, actions)

    forged = ((-1, 0), (MIN_I32, MIN_I32), (0, -1), (5, -1), (5, 6),
              (16, MAX_I32), (MAX_I32, 0), (MAX_I32, MAX_I32),
              (MIN_I32, MAX_I32), (MAX_I32, MIN_I32))
    for length, cursor in forged:
        memory(length, cursor, ((0, 0, 0, 0), (1, 0, 0, 0), (2, 0, 0, 0),
                                (3, 0, 0, 0), (4, 0, 0, 0), (6, 5, 2, 0),
                                (5, 4, 3, 0), (2, -1, 0, 0)))

    for count, offset in ((-1, 0), (MIN_I32, 0), (0, -1), (0, MAX_I32),
                          (1, MAX_I32), (2, MAX_I32 - 1), (0, 3), (1, 3), (8, 3)):
        memory(12, 3, ((5, count, offset, 0), (3, 0, 0, 0), (1, -3, 0, 0),
                       (5, 3, 4, 0), (2, -12, 0, 0), (5, 2, 1, 0),
                       (0, MASK, 0, 0), (4, 0, 0, 0)))

    for _ in range(250):
        length = rng.randrange(17)
        cursor = rng.randrange(length + 1)
        actions = []
        for _ in range(8):
            action = rng.randrange(6)
            if action == 0: a, b = rng.choice((0, length, length + 1, rng.getrandbits(64))), 0
            elif action < 3: a, b = rng.choice((MIN_I64, MAX_I64, -1, 0, 1, rng.randrange(-20, 21))), 0
            elif action == 5: a, b = rng.choice((-1, 0, 1, 3, 8)), rng.choice((-1, 0, 2, MAX_I32))
            else: a, b = 0, 0
            actions.append((action, a, b, 0))
        memory(length, cursor, actions)
    assert len(result) == 17620
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.family in range(4) and case.layout in range(4) and len(case.actions) <= 8
        if case.family == 0:
            assert 0 <= case.base <= MASK and MIN_I64 <= case.cursor <= MAX_I64
        words = [case.family, case.layout, case.base, case.cursor, len(case.actions),
                 case.identity, 0, 0]
        words += [word for action in case.actions for word in action]
        words += [0] * (40 - len(words))
        assert len(words) == 40
        data += struct.pack("<40Q", *(word & MASK for word in words))
    return data


def encode(values):
    data = bytearray()
    for case in values:
        words = reference(case)
        data += struct.pack("<" + "Q" * len(words), *words)
    return data


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        expected = reference(case)
        size = len(expected) * 8
        assert offset + size <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        observed = struct.unpack_from("<" + "Q" * len(expected), actual, offset)
        assert list(observed) == expected, (f"seed={SEED:#x}", index, case, observed, expected)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::29]), values[::29])
    assert arithmetic(1 << 63, MIN_I64) == [0, 0, 0, 0]
    assert arithmetic((1 << 63) - 1, MIN_I64) == [1, 1, 0, 0]
    assert arithmetic(MASK, 1) == [1, 1, 0, 0]
    assert arithmetic(MASK, -1) == [0, 0, 0, MASK - 1]
    assert arithmetic(1 << 63, MAX_I64) == [0, 0, 0, MASK]
    arithmetic_case = Case(0, 0, 1 << 63, MIN_I64, (), 1)
    effects = Case(1, 0, 7, 0, ((0, 7, 0, MASK), (1, 0, 1, 10),
                               (0, 0, MASK, 20), (1, 0, 0, 0)), 2)
    words = reference(effects)
    assert words[3:11] == [1, 7, 0, 0, MASK, 1, 1, 0]
    assert words[11:21] == [1, 4, 0, 0, 10, 2, 1, 0, 0, 0]
    assert words[21:33] == [0, 0, 0, MASK, 20, 3, 1, 0, 0, 0, 1, 0]
    host = Case(1, 0, 0, 0, ((1, 10, 1 << 31, MASK),), 3)
    assert reference(host)[3:9] == [1, 10, MIN_I32 & MASK, 0, MASK, 1]
    reader = Case(2, 0, 5, 1, ((0, MASK, 0, 0), (1, 1, 0, 0),
                              (5, 2, 3, 0), (2, -1, 0, 0)), 4)
    words = reference(reader)
    assert words[3:11] == [1, 1, 0, 0, 1, 5, 1, 4]
    assert words[75:83] == [0, 0, 0, 2, 2, 5, 2, 3]
    assert words[147:155] == [0, 0, 0, 2, 4, 5, 4, 1]
    assert words[187:192] == [192, 193, 194, 86, 103]
    forged = Case(3, 3, -1, 0, ((4, 0, 0, 0), (6, 4, 2, 0),
                               (5, 1, 3, 0), (3, 0, 0, 0)), 5)
    assert reference(forged)[3:11] == [1, 1, 0, 0, 0, MASK, 0, 0]
    mutations = ((arithmetic_case, 6, 1), (effects, 8, 2),
                 (effects, 7, 0), (host, 5, 1 << 31),
                 (reader, 7, 0), (reader, 11, 0), (forged, 155 + 2, 0))
    for case, index, replacement in mutations:
        corrupted = encode([case])
        assert struct.unpack_from("<Q", corrupted, index * 8)[0] != replacement
        struct.pack_into("<Q", corrupted, index * 8, replacement)
        try: verify(corrupted, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted deliberate corruption", case, index))
    families = Counter(case.family for case in values)
    action_counts = Counter(case.family for case in values for _ in case.actions)
    arithmetic_outcomes = Counter(reference(case)[3] for case in values if case.family == 0)
    for case in values:
        reference(case)
    print(f"seek-model CPU cases={len(values)} families=4 layouts=4 seed={SEED:#x} corruption-controls=7")
    print(f"seek-model families={dict(sorted(families.items()))} actions={dict(sorted(action_counts.items()))} arithmetic-tags={dict(sorted(arithmetic_outcomes.items()))}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f"seek-model cases={len(values)} families=4 layouts=4 seed={SEED:#x}")


if __name__ == "__main__":
    main()
