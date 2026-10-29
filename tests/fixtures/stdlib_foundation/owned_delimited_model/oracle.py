"""Independent owned record effects and UTF-8 oracle; test infrastructure only.

The provider models acquired versus acknowledged input. Record values use
materialized byte prefixes and host strict UTF-8, without allocator/growth logic.
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

SEED = 0x0D3110261104
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
ERRORS = {1: (7, 0), 2: (8, 0), 3: (10, -123), 4: (1, 0),
          10: (9, 0), 11: (5, 0), 12: (6, 0), 13: (2, 0),
          14: (3, 0), 15: (4, 0), 16: (10, MAX_I32)}


@dataclass(frozen=True)
class Case:
    text: bool
    second_text: bool
    layout: int
    delimiter: int
    data: bytes
    fills: tuple
    consumes: tuple
    maximum: int
    quota: int
    second_maximum: int
    second_quota: int


class Provider:
    def __init__(self, case):
        self.case = case
        self.cursor = self.fetched = self.fill_calls = self.consume_calls = 0
        self.trace = []

    def fill(self):
        event = self.case.fills[self.fill_calls] if self.fill_calls < len(self.case.fills) else 8
        self.fill_calls += 1
        self.trace.append((0, event, self.cursor, self.fetched, 0))
        if event in (-1, -2, -3): return ERRORS[-event], None
        if event <= -8: return ERRORS[{-8: 16, -9: 4}.get(event, -event)], None
        malformed = {-4: (-1, 1), -5: (2, -1), -6: (MAX_I32, 1), -7: (-1, 0)}
        if event in malformed: return None, malformed[event]
        if self.cursor == self.fetched:
            self.fetched += len(self.case.data[self.fetched:self.fetched + event])
        return None, (2 + self.cursor, self.fetched - self.cursor)

    def pending(self):
        return self.case.data[self.cursor:self.fetched]

    def consume(self, count):
        assert 0 < count <= len(self.pending())
        event = self.case.consumes[self.consume_calls] if self.consume_calls < len(self.case.consumes) else 0
        self.consume_calls += 1
        self.trace.append((1, event, self.cursor, self.fetched, count))
        if event == 0:
            self.cursor += count
            return None, count
        malformed = {5: count - 1, 6: count + 1, 7: -1, 8: MAX_I32, 9: MIN_I32}
        if event in malformed: return None, malformed[event]
        return ERRORS[event], None


def record(provider, text, maximum, quota):
    retained = bytearray()
    acknowledged = bytearray()
    before = len(provider.trace)
    ending = cause = detail = payload = 0
    delimiter = b'\n' if text else bytes((provider.case.delimiter,))
    if maximum < 0:
        cause = 1
    else:
        while True:
            if len(provider.trace) - before == quota:
                cause = 2
                break
            error, metadata = provider.fill()
            if error:
                if error[0] == 7: continue
                cause, (detail, payload) = 4, error
                break
            start, length = metadata
            if min(start, length) < 0 or start + length > MAX_I32:
                cause, detail = 4, 4
                break
            if not length:
                ending = 2
                break
            if len(retained) == maximum:
                cause = 3
                break
            if len(provider.trace) - before == quota:
                cause = 2
                break
            allowed = provider.pending()[:maximum - len(retained)]
            head, marker, _ = allowed.partition(delimiter)
            chosen = head + marker
            assert chosen
            retained.extend(chosen)
            error, accepted = provider.consume(len(chosen))
            if error:
                cause, (detail, payload) = 4, error
                break
            if accepted != len(chosen):
                cause, detail = 4, 4
                break
            acknowledged.extend(chosen)
            if marker:
                ending = 1
                break
    if not cause and text:
        try: bytes(retained).decode('utf-8', errors='strict')
        except UnicodeDecodeError as error:
            cause, detail, payload = 6, 1, error.start
    if cause and cause != 6: assert ending == 0
    calls = len(provider.trace) - before
    assert len(provider.trace) <= 64
    stride = -1 if provider.case.layout == 0 else 1  # Native magnitude deliberately unspecified.
    words = [int(bool(cause)), cause, detail, payload, len(retained), calls,
             len(acknowledged), ending, calls, provider.cursor, provider.fetched,
             provider.fill_calls, provider.consume_calls, len(provider.trace), stride]
    backing = bytearray(range(128, 168))
    backing[2:2 + len(provider.case.data)] = provider.case.data
    return words + list(retained) + list(backing) + [word for event in provider.trace for word in event]


def observations(case):
    provider = Provider(case)
    return (record(provider, case.text, case.maximum, case.quota),
            record(provider, case.second_text, case.second_maximum, case.second_quota))


def cases():
    result, seen = [], set()
    def append(data=b'ab\ncd\x00ef', delimiter=10, fills=(), consumes=(), maximum=32, quota=16,
               second_maximum=32, second_quota=16, modes=(0, 1), second_modes=(0,)):
        for text, second_text, layout in itertools.product(modes, second_modes, range(2)):
            case = Case(bool(text), bool(second_text), layout, delimiter, bytes(data), tuple(fills),
                        tuple(consumes), maximum, quota, second_maximum, second_quota)
            if case not in seen:
                seen.add(case)
                result.append(case)

    # Exhaust short acquisition histories against acknowledgement schedules.
    scripts = [script for size in range(3)
               for script in itertools.product((0, 1, 3, -1, -2, -4, -7), repeat=size)]
    assert len(scripts) == 57
    sources = (b'', b'\n', b'ab\ncd', b'\x00\xff\nA', b'\xe2\x82\xac\nZ', b'\xc0\xaf\nX', b'a\r\nB')
    for index, fills in enumerate(scripts):
        for consumes in ((), (0,), (1,), (2,), (5,), (0, 3), (0, 0, 6)):
            for quota in (0, 1, 2, 8):
                append(sources[index % len(sources)], (0, 10, 255, 77)[index % 4], fills, consumes,
                       maximum=index % 10, quota=quota)

    # Provider errors/metadata at entry, after progress, and at the final fill quota.
    for event in range(-15, 1):
        for quota in (1, 2, 3, 8):
            append(b'\xffab\nZ', fills=(event, 8), quota=quota, maximum=5)
            append(b'\xffab\nZ', fills=(1, event, 8), quota=quota, maximum=5)
    for event in range(17):
        append(b'\xffab\nZ', fills=(8,), consumes=(event, 0), maximum=5)
        append(b'\xffab\nZ', fills=(1, 8), consumes=(0, event, 0), maximum=5)

    # Delimiter and cap boundaries; NUL and high-bit delimiters are ordinary bytes.
    for size in range(17):
        for delimiter in (0, 10, 128, 255):
            for at in (-1, 0, size - 1, size):
                data = bytearray((i * 29 + 17) & 255 for i in range(size))
                if 0 <= at < size: data[at] = delimiter
                for maximum in {0, max(0, size - 1), size, size + 1}:
                    append(data, delimiter, fills=(1, 3, 32), maximum=maximum, second_modes=(0, 1))
    for maximum in (MIN_I32, -1, 0, 1, 2, MAX_I32):
        for quota in (0, 1, 2, 3, 16, MASK):
            append(b'\nX', fills=(0, 8), maximum=maximum, quota=quota)
            append(b'\nX', fills=(8,), maximum=maximum, quota=quota)
    for bad in (-4, -5, -6, -7):
        append(b'', fills=(bad, 0), maximum=0, quota=1)
        append(b'A', fills=(bad, 8), maximum=0, quota=1)
    append(b'abc', fills=(3, 0, 3), maximum=0, quota=1)
    append(b'A\nB\nC', fills=(32,), modes=(0, 1), second_modes=(0, 1))

    # Strict text anchors split at every byte boundary, including CR/LF and NUL.
    utf8 = (b'', b'\n', b'\r\n', b'A\x00B\n', b'\xc2\xa2\nZ', b'\xe2\x82\xac\r\nZ',
            b'\xf0\x9f\x98\x80\nZ', b'\x80\nZ', b'\xc0\xaf\nZ', b'\xed\xa0\x80\nZ',
            b'\xf4\x90\x80\x80\nZ', b'\xe2\x82', b'A\xe2\nZ', b'A\xe2\x82\xac')
    for data in utf8:
        for split in range(len(data) + 1):
            for maximum in {0, max(0, len(data) - 1), len(data), len(data) + 1}:
                append(data, fills=(split, 1, 32), maximum=maximum, modes=(1,), second_modes=(0, 1))
            for fills in ((split, -1, 32), (split, -2, 32)):
                append(data, fills=fills, modes=(1,), second_modes=(0, 1))

    rng = random.Random(SEED)
    for _ in range(400):
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(33)))
        fills = tuple(rng.choice((0, 1, 2, 4, 8, 32, -1, -2, -3, -4, -7)) for _ in range(rng.randrange(6)))
        consumes = tuple(rng.choice((0, 0, 0, 1, 2, 3, 5, 6, 7)) for _ in range(rng.randrange(5)))
        append(data, rng.randrange(256), fills, consumes, rng.randrange(34), rng.randrange(17),
               rng.randrange(34), rng.randrange(17), modes=(rng.randrange(2),), second_modes=(rng.randrange(2),))
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert len(case.data) <= 32 and len(case.fills) <= 12 and len(case.consumes) <= 12
        assert all(MIN_I32 <= value <= MAX_I32 for value in (case.maximum, case.second_maximum))
        assert all(0 <= value <= MASK for value in (case.quota, case.second_quota))
        fields = (case.text, case.second_text, case.layout, case.delimiter, len(case.data),
                  len(case.fills), len(case.consumes), case.maximum, case.quota,
                  case.second_maximum, case.second_quota) + tuple(case.data) + case.fills + case.consumes
        data.extend(struct.pack('<' + 'Q' * len(fields), *(word & MASK for word in fields)))
    return data


def encoded(values):
    data = bytearray()
    for case in values:
        for words in observations(case):
            data.extend(struct.pack('<' + 'Q' * len(words), *(word & MASK for word in words)))
    return data


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        for invocation, expected in enumerate(observations(case)):
            size = len(expected) * 8
            assert offset + size <= len(actual), (f'seed={SEED:#x}', index, invocation, case, 'truncated')
            observed = list(struct.unpack_from('<' + 'Q' * len(expected), actual, offset))
            stride = observed[14] if observed[14] < (1 << 63) else observed[14] - (1 << 64)
            assert stride < 0 if case.layout == 0 else stride == 1, (index, case, 'stride', stride)
            expected[14] = stride
            expected = [word & MASK for word in expected]
            assert observed == expected, (f'seed={SEED:#x}', index, invocation, case, observed, expected)
            offset += size
    assert offset == len(actual), (offset, len(actual), 'extra output')


def controls():
    def sample(**changes):
        fields = dict(text=False, second_text=False, layout=0, delimiter=10, data=b'A\nB', fills=(8,),
                      consumes=(), maximum=3, quota=8, second_maximum=32, second_quota=16)
        fields.update(changes)
        return Case(**fields)
    normal = sample()
    first, second = observations(normal)
    assert first[:14] == [0, 0, 0, 0, 2, 2, 2, 1, 2, 2, 3, 1, 1, 2]
    assert second[:14] == [0, 0, 0, 0, 1, 3, 1, 2, 3, 3, 3, 3, 2, 5]
    assert first[15:17] == list(b'A\n') and second[15:16] == list(b'B')
    assert observations(sample(data=b'', maximum=0, quota=1))[0][:8] == [0, 0, 0, 0, 0, 1, 0, 2]
    assert observations(sample(maximum=0, quota=1))[0][:8] == [1, 3, 0, 0, 0, 1, 0, 0]
    assert observations(sample(quota=1))[0][:8] == [1, 2, 0, 0, 0, 1, 0, 0]
    assert observations(sample(fills=(-7,), maximum=0, quota=1))[0][:8] == [1, 4, 4, 0, 0, 1, 0, 0]
    staged = sample(consumes=(1, 0))
    assert observations(staged)[0][:8] == [1, 4, 7, 0, 2, 2, 0, 0]
    assert observations(staged)[1][15:17] == list(b'A\n')
    assert observations(sample(fills=(-1, 8), quota=3))[0][:8] == [0, 0, 0, 0, 2, 3, 2, 1]
    assert observations(sample(data=b'A\n', maximum=2))[0][:8] == [0, 0, 0, 0, 2, 2, 2, 1]
    assert observations(sample(data=b'AB', maximum=2))[0][:8] == [0, 0, 0, 0, 2, 3, 2, 2]
    assert observations(sample(data=b'ABC', maximum=2))[0][:8] == [1, 3, 0, 0, 2, 3, 2, 0]
    invalid = sample(text=True, data=b'A\xff\nB')
    assert observations(invalid)[0][:8] == [1, 6, 1, 1, 3, 2, 3, 1]
    assert observations(replace(invalid, maximum=2))[0][:8] == [1, 3, 0, 0, 2, 3, 2, 0]
    assert observations(replace(invalid, fills=(2, -2), maximum=4))[0][:8] == [1, 4, 8, 0, 2, 3, 2, 0]
    split = sample(text=True, data=b'\xe2\x82\xac\nZ', maximum=5, fills=(1, 1, 8))
    assert observations(split)[0][:8] == [0, 0, 0, 0, 4, 6, 4, 1]
    mutations = ((normal, 0, 5, 1), (normal, 0, 6, 0), (normal, 0, 7, 2),
                 (normal, 0, 15, 0), (normal, 0, 17, 0), (normal, 0, 14, 0),
                 (staged, 0, 2, 8), (invalid, 0, 3, 0))
    for case, invocation, word, replacement in mutations:
        bad = encoded([case])
        byte_offset = sum(len(x) * 8 for x in observations(case)[:invocation]) + word * 8
        assert struct.unpack_from('<Q', bad, byte_offset)[0] != replacement
        struct.pack_into('<Q', bad, byte_offset, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(('accepted verifier corruption', case, word))
    values = cases()
    assert len(values) == len(set(values))
    assert packet(values)
    verify(encoded(values[::73]), values[::73])
    modes, causes, endings = Counter(), Counter(), Counter()
    for case in values:
        for text, words in zip((case.text, case.second_text), observations(case)):
            modes[int(text)] += 1
            causes[words[1]] += 1
            endings[words[7]] += 1
    print(f'owned-delimited CPU cases={len(values)} invocations={len(values) * 2} layouts=2 seed={SEED:#x} verifier-corruptions=8')
    print(f'owned-delimited modes={dict(sorted(modes.items()))} causes={dict(sorted(causes.items()))} endings={dict(sorted(endings.items()))}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
        return
    assert len(sys.argv) == 2, 'usage: oracle.py <model-executable> | controls'
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f'owned-delimited cases={len(values)} invocations={len(values) * 2} layouts=2 seed={SEED:#x}')


if __name__ == '__main__':
    main()
