"""Independent finite source/budget state reference. No PRNG is implemented."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xB0D6E0261101
MASK = (1 << 64) - 1
MIN_I64, MAX_I64 = -(1 << 63), (1 << 63) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
RECORD_WORDS = 43
ROUTES = ((0,), (0,), (1,), (1, 0), (0, 0))


@dataclass(frozen=True)
class Case:
    layout: int
    limit: int
    script: tuple
    actions: tuple
    identity: int


class SourceError(Exception):
    def __init__(self, code, host=0):
        self.code, self.host = code, host


def signed(value, width=64):
    value &= (1 << width) - 1
    return value - (1 << width) if value >= (1 << (width - 1)) else value


class Source:
    def __init__(self, case):
        self.case = case
        self.remaining = [case.limit, case.limit]
        self.index = self.calls = 0

    def draw(self, adapter):
        for counter in ROUTES[adapter]:
            if not self.remaining[counter]: raise SourceError(8)
            self.remaining[counter] -= 1
        self.calls += 1
        if self.index == len(self.case.script): raise SourceError(6)
        error, word = self.case.script[self.index]
        self.index += 1
        if error: raise SourceError(error, signed(word, 32) if error == 5 else 0)
        return word

    def rank(self, adapter, width):
        if width == 0: raise SourceError(2)
        if width == 1: return 0
        admitted_start = (1 << 64) % width
        while True:
            word = self.draw(adapter)
            if word >= admitted_start: return word % width

    def inclusive(self, adapter, low, high):
        if low > high: raise SourceError(3)
        if low == high: return low
        size = high - low + 1
        offset = self.draw(adapter) if size == (1 << 64) else self.rank(adapter, size)
        return low + offset


def unit_bits(word, precision, exponent_bits):
    """Exact encoding of (top precision bits)/2**precision, no float conversion."""
    integer = word >> (64 - precision)
    if not integer: return 0
    leading = integer.bit_length() - 1
    fraction_bits = precision - 1
    exponent = leading - precision + (1 << (exponent_bits - 1)) - 1
    fraction = (integer - (1 << leading)) << (fraction_bits - leading)
    return (exponent << fraction_bits) | fraction


def valid_span(start, length):
    return start >= 0 and length >= 0 and start + length <= MAX_I32


def operation(source, buffer, action):
    kind, adapter, a, b = action
    completed = 0
    try:
        if kind == 0: value = source.draw(adapter)
        elif kind == 1: value = source.rank(adapter, a & MASK)
        elif kind == 2: value = source.inclusive(adapter, a & MASK, b & MASK)
        elif kind == 3: value = source.inclusive(adapter, signed(a), signed(b)) & MASK
        elif kind == 4: value = source.draw(adapter) >> 63
        elif kind == 5: value = unit_bits(source.draw(adapter), 24, 8)
        elif kind == 6: value = unit_bits(source.draw(adapter), 53, 11)
        elif kind == 7:
            start, length = signed(a, 32), signed(b, 32)
            if not valid_span(start, length): raise SourceError(1)
            while completed < length:
                chunk = source.draw(adapter).to_bytes(8, "little")[:length - completed]
                at = start + completed
                assert at + len(chunk) <= len(buffer)
                buffer[at:at + len(chunk)] = chunk
                completed += len(chunk)
            value = completed
        else:
            start, length = signed(a, 32), signed(b, 32)
            if not valid_span(start, length): raise SourceError(1)
            if kind == 8:
                if length == 0: return [2, 0, 0, 0, 0]
                index = source.rank(adapter, length)
                assert start + index < len(buffer)
                value = buffer[start + index]
            else:
                assert kind == 9
                for last in reversed(range(1, length)):
                    selected = source.rank(adapter, last + 1)
                    assert start + last < len(buffer)
                    buffer[start + last], buffer[start + selected] = buffer[start + selected], buffer[start + last]
                    completed += 1
                value = completed
        return [0, 0, 0, value, 0]
    except SourceError as error:
        return [1, error.code, error.host, 0, completed]


def reference(case):
    source = Source(case)
    buffer = bytearray(range(160, 192))
    words = []
    for action in case.actions:
        result = operation(source, buffer, action)
        words += list(action[:2]) + result + source.remaining + [source.calls, source.index] + list(buffer)
    return [word & MASK for word in words]


def tail(first):
    return (first, (1, 1, 1, 0), (0, 0, 0, 0), (7, 2, 17, 9),
            (9, 3, 3, 5), (8, 4, 3, 4), (2, 1, 7, 7), (3, 0, -1, 1))


def cases():
    result, seen = [], set()
    def append(limit, script, actions):
        script, actions = tuple(script), tuple(actions)
        for layout in range(2):
            shape = (layout, limit, script, actions)
            if shape in seen: continue
            seen.add(shape)
            result.append(Case(layout, limit, script, actions, len(result) + 1))

    bounds = (0, 1, 2, 3, 5, 7, 10, (1 << 31) - 1, 1 << 32, (1 << 32) + 1,
              (1 << 63) - 1, 1 << 63, (1 << 63) + 1, MASK)
    for bound in bounds:
        threshold = (1 << 64) % bound if bound else 0
        endpoints = {0, MASK, threshold, min(MASK, threshold + 1)}
        if threshold: endpoints.add(threshold - 1)
        for word in sorted(endpoints):
            script = ((0, word), (0, 0), (0, MASK), (0, 1), (0, 255), (0, MASK), (0, 4), (0, 5))
            for limit in (0, 1, 2, MASK):
                for adapter in range(5): append(limit, script, tail((1, adapter, bound, 0)))

    unsigned = ((0, 0), (MASK, MASK), (0, MASK), (1, MASK), (0, MAX_I64),
                (1 << 63, MASK), (MASK, 0), (10, 9), (10, 15))
    signed_ranges = ((MIN_I64, MIN_I64), (MAX_I64, MAX_I64), (MIN_I64, MAX_I64),
                     (-1, 1), (MIN_I64, 0), (0, MAX_I64), (1, -1), (-10, -3))
    for kind, ranges in ((2, unsigned), (3, signed_ranges)):
        for low, high in ranges:
            for limit in (0, 1, 2, 8, MASK):
                for adapter in range(5):
                    append(limit, ((0, 0), (0, MASK), (0, 1 << 63), (0, 1), (0, 255)),
                           tail((kind, adapter, low, high)))

    for error in range(1, 9):
        payloads = (0, 1 << 31, MAX_I32, MASK - 122) if error == 5 else (0,)
        for payload in payloads:
            for prefix in ((), ((0, MASK),)):
                for limit in (1, 2, 8, MASK):
                    for adapter in range(5):
                        append(limit, prefix + ((error, payload), (0, MASK), (0, 7)),
                               tail((0, adapter, 0, 0)))

    spans = ((-1, 0), (-1, 2), (0, -1), (0, MIN_I32), (MAX_I32, 0),
             (MAX_I32, 1), (MAX_I32 - 1, 2), (2, 0), (2, 1), (2, 7),
             (2, 8), (2, 9), (2, 16), (2, 17))
    script = ((0, 0x0123456789ABCDEF), (0, 0xFEDCBA9876543210), (5, MASK - 122), (0, MASK))
    for offset, count in spans:
        for limit in (0, 1, 2, 3, MASK):
            for adapter in range(5): append(limit, script, tail((7, adapter, offset, count)))

    views = ((-1, 0), (-1, 1), (2, -1), (2, MIN_I32), (MAX_I32, 1),
             (MAX_I32 - 1, 2), (1, MAX_I32), (MAX_I32, 0), (2, 0),
             (2, 1), (2, 2), (2, 5), (2, 12))
    for kind in (8, 9):
        for start, length in views:
            for limit in (0, 1, 8):
                for adapter in range(5):
                    append(limit, ((0, 0), (0, MASK), (0, 1), (0, 2), (0, 3)),
                           tail((kind, adapter, start, length)))

    float_words = (0, 1, (1 << 11) - 1, 1 << 11, (1 << 40) - 1,
                   1 << 40, (1 << 63) - 1, 1 << 63, MASK)
    for kind in (4, 5, 6):
        for word in float_words:
            for limit in (0, 1, 2, MASK):
                for adapter in range(5): append(limit, ((0, word), (0, MASK)), tail((kind, adapter, 0, 0)))

    rng = random.Random(SEED)
    for _ in range(300):
        limit = rng.choice((0, 1, 2, 3, 4, 8, 16, MASK))
        script = tuple((rng.choice((0, 0, 0, 0, 5, 6, 8)), rng.getrandbits(64))
                       for _ in range(rng.randrange(17)))
        actions = []
        for _ in range(8):
            kind, adapter = rng.randrange(10), rng.randrange(5)
            if kind == 1: a, b = rng.choice(bounds), 0
            elif kind == 2: a, b = rng.choice(unsigned)
            elif kind == 3: a, b = rng.choice(signed_ranges)
            elif kind == 7: a, b = rng.choice(spans)
            elif kind in (8, 9): a, b = rng.choice(views)
            else: a, b = 0, 0
            actions.append((kind, adapter, a, b))
        append(limit, script, actions)
    assert len(result) == 7130
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.layout in (0, 1) and 0 <= case.limit <= MASK
        assert len(case.script) <= 16 and len(case.actions) <= 8
        assert all(0 <= code <= 8 and 0 <= word <= MASK for code, word in case.script)
        assert all(0 <= kind <= 9 and 0 <= adapter <= 4 for kind, adapter, _, _ in case.actions)
        fields = [case.layout, case.limit, len(case.script), len(case.actions), case.identity, 0, 0, 0]
        fields += [word for event in case.script for word in event]
        fields += [word for action in case.actions for word in action]
        data += struct.pack("<" + "Q" * len(fields), *(word & MASK for word in fields))
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
    verify(encode(values[::31]), values[::31])
    def sample(limit, script, actions): return Case(0, limit, tuple(script), tuple(actions), 1)
    rejected = sample(1, ((0, 0),), ((1, 0, 3, 0),))
    assert reference(rejected)[:11] == [1, 0, 1, 8, 0, 0, 0, 0, 1, 1, 1]
    accepted = sample(1, ((0, 1),), ((1, 0, 3, 0),))
    assert reference(accepted)[:11] == [1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1]
    last = sample(2, ((0, 0), (0, 3)), ((1, 0, 3, 0),))
    assert reference(last)[:11] == [1, 0, 0, 0, 0, 0, 0, 0, 2, 2, 2]
    same = sample(1, ((0, 3),), ((0, 4, 0, 0),))
    assert reference(same)[:11] == [0, 4, 1, 8, 0, 0, 0, 0, 1, 0, 0]
    copied = sample(2, ((0, 10), (0, 20), (0, 30)),
                    ((0, 0, 0, 0), (0, 1, 0, 0), (0, 2, 0, 0), (0, 3, 0, 0)))
    words = reference(copied)
    assert words[:11] == [0, 0, 0, 0, 0, 10, 0, 1, 2, 1, 1]
    assert words[43:54] == [0, 1, 0, 0, 0, 20, 0, 0, 2, 2, 2]
    assert words[86:97] == [0, 2, 0, 0, 0, 30, 0, 0, 1, 3, 3]
    assert words[129:140] == [0, 3, 1, 8, 0, 0, 0, 0, 0, 3, 3]
    partial = sample(1, ((0, 0x0123456789ABCDEF),), ((7, 0, 3, 9),))
    assert reference(partial)[:11] == [7, 0, 1, 8, 0, 0, 8, 0, 1, 1, 1]
    assert reference(partial)[11:43] == [160, 161, 162] + list(bytes.fromhex("efcdab8967452301")) + list(range(171, 192))
    host = sample(MASK, ((5, 1 << 31),), ((0, 0, 0, 0),))
    assert reference(host)[:11] == [0, 0, 1, 5, MIN_I32 & MASK, 0, 0, MASK - 1, MASK, 1, 1]
    no_draw = sample(0, (), ((1, 4, 1, 0), (2, 3, MASK, MASK),
                             (8, 0, MAX_I32, 0), (9, 4, 2, 1)))
    assert all(reference(no_draw)[at + 9] == 0 for at in range(0, 4 * RECORD_WORDS, RECORD_WORDS))
    assert unit_bits(0, 24, 8) == 0 and unit_bits(MASK, 24, 8) == 0x3F7FFFFF
    assert unit_bits(1 << 40, 24, 8) == 0x33800000
    assert unit_bits(MASK, 53, 11) == 0x3FEFFFFFFFFFFFFF
    corruptions = ((rejected, 2, 0), (accepted, 5, 0), (same, 9, 1),
                   (copied, 43 + 7, 1), (copied, 86 + 8, 2),
                   (partial, 6, 9), (partial, 11, 0), (host, 4, 1 << 31))
    for case, word, replacement in corruptions:
        bad = encode([case])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted corruption", case, word))
    operations, adapters, outcomes = Counter(), Counter(), Counter()
    for case in values:
        words = reference(case)
        for index, (kind, adapter, _, _) in enumerate(case.actions):
            operations[kind] += 1
            adapters[adapter] += 1
            at = index * RECORD_WORDS
            outcomes[(words[at + 2], words[at + 3])] += 1
    assert all(operations[kind] for kind in range(10)) and all(adapters[index] for index in range(5))
    assert all(outcomes[(1, code)] for code in range(1, 9))
    print(f"random-budget CPU cases={len(values)} actions={sum(operations.values())} layouts=2 adapters=5 seed={SEED:#x} corruption-controls=8")
    print(f"random-budget operations={dict(sorted(operations.items()))} adapters={dict(sorted(adapters.items()))} outcomes={dict(sorted(outcomes.items()))}")


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
    print(f"random-budget cases={len(values)} actions={sum(len(case.actions) for case in values)} layouts=2 adapters=5 seed={SEED:#x}")


if __name__ == "__main__":
    main()
