"""Independent finite BufRead provider/state reference, only for tests.

Provider transitions and helper observations are separate. Byte prefixes come
from materialized input, not the Lanius scan implementation. No host I/O model
or production implementation is supplied by Python.
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

SEED = 0xDE11A0261031
MASK = (1 << 64) - 1
MAX_I32 = (1 << 31) - 1
MIN_I32 = -(1 << 31)


@dataclass(frozen=True)
class Case:
    operation: int
    layout: int
    delimiter: int
    source: bytes
    offset: int
    bound: int
    budget: int
    second_budget: int
    second_offset: int
    second_bound: int
    fills: tuple
    consumes: tuple
    identity: int


ERRORS = {1: (7, 0), 2: (8, 0), 3: (10, -123), 4: (1, 0),
          10: (9, 0), 11: (5, 0), 12: (6, 0), 13: (2, 0),
          14: (3, 0), 15: (4, 0), 16: (10, MAX_I32)}


class Provider:
    def __init__(self, case):
        self.case = case
        self.cursor = self.fetched = self.fill_calls = self.consume_calls = 0
        self.trace = []

    def fill(self):
        event = self.case.fills[self.fill_calls] if self.fill_calls < len(self.case.fills) else 4
        self.fill_calls += 1
        self.trace.append((0, event, self.cursor, self.fetched, 0))
        if event in (-1, -2, -3): return ERRORS[-event], None
        if event <= -8:
            code = {-8: 16, -9: 4}.get(event, -event)
            return ERRORS[code], None
        malformed = {-4: (-1, 1), -5: (2, -1),
                     -6: (MAX_I32, 1), -7: (-1, 0)}
        if event in malformed: return None, malformed[event]
        # Filling can acquire a chunk but cannot acknowledge its consumption.
        if self.cursor == self.fetched:
            available = self.case.source[self.fetched:]
            self.fetched += len(available[:event])
        return None, (2 + self.cursor, self.fetched - self.cursor)

    def unread(self):
        return self.case.source[self.cursor:self.fetched]

    def consume(self, requested):
        assert 0 < requested <= len(self.unread())
        event = self.case.consumes[self.consume_calls] if self.consume_calls < len(self.case.consumes) else 0
        self.consume_calls += 1
        self.trace.append((1, event, self.cursor, self.fetched, requested))
        if event == 0:
            self.cursor += requested
            return None, requested
        malformed = {5: requested - 1, 6: requested + 1, 7: -1,
                     8: MAX_I32, 9: MIN_I32}
        if event in malformed: return None, malformed[event]
        return ERRORS[event], None


def signed_i32(value):
    value &= (1 << 32) - 1
    return value - (1 << 32) if value >= (1 << 31) else value


def helper(case, provider, destination, offset, bound, budget):
    copied = bytearray()
    acknowledged = bytearray()
    admitted = signed_i32(bound) if case.operation == 0 else bound & MASK

    def failed(error):
        code, host = error
        return [1, code, host, 0, 0, len(copied), len(acknowledged)]

    def succeeded(ending):
        return [0, 0, 0, len(acknowledged), ending, 0, 0]

    if budget < 0 or (case.operation == 0 and
                      (offset < 0 or admitted < 0 or offset + admitted > MAX_I32)):
        return failed((1, 0))
    if admitted == 0: return succeeded(3)
    calls_before = len(provider.trace)
    while len(acknowledged) < admitted:
        available_calls = budget - (len(provider.trace) - calls_before)
        if not available_calls: return failed((6, 0))
        error, metadata = provider.fill()
        if error:
            if error[0] == 7: continue
            return failed(error)
        start, length = metadata
        if min(start, length) < 0 or start + length > MAX_I32:
            return failed((4, 0))
        if length == 0: return succeeded(2)
        if len(provider.trace) - calls_before == budget: return failed((6, 0))
        prefix = provider.unread()[:admitted - len(acknowledged)]
        assert prefix
        position = prefix.find(bytes((case.delimiter,)))
        selected = prefix if position < 0 else prefix[:position + 1]
        if case.operation == 0:
            at = offset + len(copied)
            assert at >= 0 and at + len(selected) <= len(destination)
            destination[at:at + len(selected)] = selected
            copied.extend(selected)
        error, accepted = provider.consume(len(selected))
        if error: return failed(error)
        if accepted != len(selected): return failed((4, 0))
        acknowledged.extend(selected)
        if position >= 0: return succeeded(1)
    return succeeded(3)


def reference(case):
    provider = Provider(case)
    destination = bytearray(range(192, 224))
    source_backing = bytearray(range(128, 160))
    source_backing[2:2 + len(case.source)] = case.source
    output = []
    for offset, bound, budget in ((case.offset, case.bound, case.budget),
                                  (case.second_offset, case.second_bound, case.second_budget)):
        observation = helper(case, provider, destination, offset, bound, budget)
        output += observation + [provider.cursor, provider.fetched, provider.fill_calls,
                                 provider.consume_calls, len(provider.trace)]
        output += list(destination) + list(source_backing)
        output += [word for call in provider.trace for word in call]
    return [word & MASK for word in output]


def cases():
    result = []

    def append(source, delimiter, bound, budget, fills=(), consumes=(), offset=3,
               second_bound=7, second_budget=8, second_offset=17):
        for operation in range(2):
            for layout in range(4):
                result.append(Case(operation, layout, delimiter, bytes(source), offset,
                                   bound & MASK, budget, second_budget, second_offset,
                                   second_bound & MASK, tuple(fills), tuple(consumes), len(result) + 1))

    # Cross short fill histories with successful, failed and malformed consumes.
    alphabet = (1, 3, 0, -1, -2, -4, -7)
    fills = [script for size in range(3) for script in itertools.product(alphabet, repeat=size)]
    assert len(fills) == 57
    consume_scripts = ((), (0,), (1,), (2,), (5,), (0, 3), (0, 0, 6))
    for index, fill_script in enumerate(fills):
        source = bytes((0, 255, 65, 10, 66, 0, 255, 10))[:index % 9]
        delimiter = (0, 255, 10, 77)[index % 4]
        for consume_script in consume_scripts:
            for budget in (0, 1, 2, 7):
                append(source, delimiter, index % 10, budget, fill_script, consume_script)

    # Reach every provider error and malformed count, including after progress.
    for fill_event in range(-15, 1):
        append(b"ab\x00cd\xffef", 255, 8, 8, (2, fill_event, 8), (0,))
        append(b"ab\x00cd\xffef", 255, 8, 1, (fill_event, 8), ())
    for consume_event in range(17):
        append(b"ab\x00cd\xffef", 255, 8, 8, (2, 8), (0, consume_event, 0))
        append(b"ab\x00cd\xffef", 255, 8, 8, (8,), (consume_event, 0))

    # Fixed-cap delimiter placement and transient EOF followed by live data.
    for size in range(17):
        for at in (-1, 0, size - 1, size):
            source = bytearray((index * 29 + 17) & 255 for index in range(size))
            if 0 <= at < size: source[at] = 255
            append(source, 255, size, 8, (16,))
            append(source, 255, max(0, size - 1), 8, (1, 3, 16))
    for delimiter in (0, 10, 128, 255):
        append(bytes((delimiter, 7, delimiter)), delimiter, 3, 1, (0, 3))
        append(bytes((7, delimiter, 9)), delimiter, 2, 1, (3,))

    shapes = ((-1, 0), (-1, 2), (0, -1), (0, MIN_I32), (MAX_I32, 0),
              (MAX_I32, 1), (MAX_I32 - 1, 2), (3, 0), (3, 1), (3, 16))
    for offset, bound in shapes:
        for budget in (-1, 0, 1, 8):
            append(b"abc\x00def", 0, bound, budget, (16,), (), offset=offset)
    for bound in (1 << 32, (1 << 63) - 1, 1 << 63, MASK):
        append(b"ab\x00c", 0, bound, 8, (1, 3))

    rng = random.Random(SEED)
    for _ in range(400):
        source = bytes(rng.choice((0, 1, 10, 65, 128, 255)) for _ in range(rng.randrange(17)))
        append(source, rng.choice((0, 1, 10, 65, 128, 255, 77)), rng.randrange(17),
               rng.randrange(-1, 9), tuple(rng.randrange(-15, 17) for _ in range(rng.randrange(9))),
               tuple(rng.randrange(17) for _ in range(rng.randrange(9))),
               offset=rng.randrange(4), second_bound=rng.randrange(16),
               second_budget=rng.randrange(-1, 9), second_offset=1)
    assert len(result) == 18000
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert len(case.source) <= 16 and len(case.fills) <= 8 and len(case.consumes) <= 8
        assert -1 <= case.budget <= 8 and -1 <= case.second_budget <= 8
        assert all(-15 <= value <= 16 for value in case.fills)
        assert all(0 <= value <= 16 for value in case.consumes)
        header = [case.operation, case.layout, case.delimiter, len(case.source), case.offset,
                  case.bound, case.budget, case.second_budget, case.second_offset,
                  case.second_bound, len(case.fills), len(case.consumes), case.identity]
        words = header + list(case.source) + [0] * (16 - len(case.source))
        words += list(case.fills) + [0] * (8 - len(case.fills))
        words += list(case.consumes) + [0] * (8 - len(case.consumes))
        assert len(words) == 45
        data += struct.pack("<45Q", *(word & MASK for word in words))
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
        got = struct.unpack_from("<" + "Q" * len(expected), actual, offset)
        assert list(got) == expected, (f"seed={SEED:#x}", index, case, got, expected)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::43]), values[::43])
    def sample(**changes):
        fields = dict(operation=0, layout=0, delimiter=0, source=b"ab\x00cd", offset=3,
                      bound=5, budget=8, second_budget=8, second_offset=17,
                      second_bound=7, fills=(2, 8), consumes=(), identity=1)
        fields.update(changes)
        return Case(**fields)
    good = sample()
    assert reference(good)[:12] == [0, 0, 0, 3, 1, 0, 0, 3, 5, 2, 2, 4]
    assert reference(good)[12:44] == list(range(192, 195)) + [97, 98, 0] + list(range(198, 224))
    read_ahead = sample(budget=1, fills=(5,))
    assert reference(read_ahead)[:12] == [1, 6, 0, 0, 0, 0, 0, 0, 5, 1, 0, 1]
    interrupted = sample(consumes=(1, 0), fills=(5,))
    assert reference(interrupted)[:12] == [1, 7, 0, 0, 0, 3, 0, 0, 5, 1, 1, 2]
    malformed = sample(budget=1, fills=(-7, 5))
    assert reference(malformed)[:12] == [1, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1]
    eof = sample(fills=(0, 5), budget=1)
    words = reference(eof)
    assert words[:12] == [0, 0, 0, 0, 2, 0, 0, 0, 0, 1, 0, 1]
    assert words[81:93] == [0, 0, 0, 3, 1, 0, 0, 3, 5, 2, 1, 3]
    final_delimiter = sample(bound=3, fills=(5,))
    assert reference(final_delimiter)[:7] == [0, 0, 0, 3, 1, 0, 0]
    no_probe = sample(bound=2, fills=(5,))
    assert reference(no_probe)[:12] == [0, 0, 0, 2, 3, 0, 0, 2, 5, 1, 1, 2]
    invalid = sample(offset=-1, bound=0, budget=0)
    assert reference(invalid)[:12] == [1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    zero = sample(bound=0, budget=0)
    assert reference(zero)[:12] == [0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0]
    mutations = ((good, 3, 2), (good, 12, 0), (good, 80, 1),
                 (read_ahead, 8, 0), (interrupted, 6, 3),
                 (malformed, 1, 6), (final_delimiter, 4, 3))
    for case, index, replacement in mutations:
        corrupted = encode([case])
        assert struct.unpack_from("<Q", corrupted, index * 8)[0] != replacement
        struct.pack_into("<Q", corrupted, index * 8, replacement)
        try: verify(corrupted, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted deliberate corruption", case, index))
    outcomes, call_counts = Counter(), Counter()
    copied_unacknowledged = read_ahead_count = resumed_after_eof = 0
    for case in values:
        words = reference(case)
        first_calls = words[11]
        second = 76 + 5 * first_calls
        for at in (0, second):
            outcomes[(words[at], words[at + 1], words[at + 4])] += 1
            call_counts[words[at + 11]] += 1
            copied_unacknowledged += words[at + 5] > words[at + 6]
        read_ahead_count += words[0] == 1 and words[1] == 6 and words[8] > words[7]
        resumed_after_eof += words[4] == 2 and words[second + 3] > 0
    assert copied_unacknowledged and read_ahead_count and resumed_after_eof
    assert all(outcomes[(0, 0, ending)] for ending in (1, 2, 3))
    assert all(any(tag == 1 and error == code and count for (tag, error, _), count in outcomes.items())
               for code in range(1, 11))
    print(f"delimited-io CPU cases={len(values)} helpers=2 layouts=4 invocations=2 seed={SEED:#x} corruption-controls=7")
    print(f"delimited-io copied-unacknowledged={copied_unacknowledged} read-ahead-budget={read_ahead_count} resumed-after-eof={resumed_after_eof}")
    print(f"delimited-io outcomes={dict(sorted(outcomes.items()))} calls={dict(sorted(call_counts.items()))}")


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
    print(f"delimited-io cases={len(values)} helpers=2 layouts=4 invocations=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
