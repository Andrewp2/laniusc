"""Independent finite provider schedules for bounded positional I/O.

Confirmed byte chunks, explicit attempted calls and declarative outcome classes
form the reference. No host files or production Python implementation are used.
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

SEED = 0xA71020261030
MASK = (1 << 64) - 1
MAX_POSITION = (1 << 63) - 1
MAX_I32 = (1 << 31) - 1
MIN_I32 = -(1 << 31)


@dataclass(frozen=True)
class Case:
    operation: int
    layout: int
    offset: int
    count: int
    position: int
    budget: int
    script: tuple
    identity: int


def byte_at(position):
    mixed = (position ^ (position >> 32) ^ (position >> 55)) & 255
    return (mixed * 37 + 23) & 255


def outcome(event, remaining):
    if event >= 0: return 0, event, 0
    if event in (-4, -5, -6, -16, -17):
        amount = {-4: -1, -5: remaining + 1, -6: remaining,
                  -16: MIN_I32, -17: MAX_I32}[event]
        return 0, amount, 0
    # (public Error discriminant in the test protocol, preserved Host payload)
    error, host = {-1: (7, 0), -2: (8, 0), -3: (10, 5), -7: (1, 0),
                   -8: (10, MAX_I32), -9: (10, -123), -10: (9, 0),
                   -11: (5, 0), -12: (6, 0), -13: (2, 0), -14: (3, 0),
                   -15: (4, 0), -18: (10, 0)}[event]
    return error, None, host


def reference(case):
    valid_range = case.offset >= 0 and case.count >= 0 and case.offset + case.count <= MAX_I32
    valid_position = case.count >= 0 and case.position + case.count <= MAX_POSITION
    buffer = [160 + index for index in range(32)]
    if case.operation == 1:
        buffer = [(case.identity * 13 + index * 17) & 255 for index in range(32)]
    confirmed = bytearray()
    calls = []
    error, host = 0, 0
    if not valid_range or not valid_position or case.budget < 0:
        error = 1
    elif case.count:
        error = 6
        for attempt in range(case.budget):
            done = len(confirmed)
            remaining = case.count - done
            event = case.script[attempt] if attempt < len(case.script) else 0
            at, position = case.offset + done, case.position + done
            calls.append((at, remaining, position, event))
            cause, amount, detail = outcome(event, remaining)
            if cause:
                if cause == 7: continue
                error, host = cause, detail
                break
            if not 0 <= amount <= remaining:
                error = 4
                break
            if not amount:
                error = 2 if case.operation == 0 else 3
                break
            if case.operation == 0:
                chunk = bytes(byte_at(position + index) for index in range(amount))
                buffer[at:at + amount] = chunk
            else:
                chunk = bytes(buffer[at:at + amount])
                assert len(chunk) == amount
            confirmed.extend(chunk)
            if len(confirmed) == case.count:
                error = 0
                break
    sink = list(confirmed) if case.operation else []
    header = [case.operation, case.layout, int(bool(error)), error, host,
              len(confirmed), len(calls), len(sink), int(valid_range), int(valid_position)]
    words = header + buffer + sink + [word for call in calls for word in call]
    return [word & MASK for word in words]


def cases():
    result = []

    def append(offset, count, position, budget, script):
        for operation in range(2):
            for layout in range(2):
                result.append(Case(operation, layout, offset, count, position,
                                   budget, tuple(script), len(result) + 1))

    alphabet = (-6, 1, 0, -1, -2, -3, -4, -5)
    scripts = [script for length in range(4) for script in itertools.product(alphabet, repeat=length)]
    assert len(scripts) == 585
    for index, script in enumerate(scripts):
        count = 1 + index % 6
        offset = 2 + index % 5
        position = (0, (1 << 32) + 7, MAX_POSITION - count, MAX_POSITION - 32)[index % 4]
        for budget in (0, 1, 4): append(offset, count, position, budget, script)

    shapes = ((-1, 0), (-1, 1), (0, -1), (0, MIN_I32), (MAX_I32, 0),
              (MAX_I32, 1), (MAX_I32 - 1, 2), (0, 0), (3, 0), (2, 1),
              (5, 6), (15, 12))
    positions = (0, 1, (1 << 32) + 7, MAX_POSITION, MAX_POSITION - 1,
                 MAX_POSITION - 12, MAX_POSITION + 1, MASK)
    for offset, count in shapes:
        for position in positions:
            for budget in (-1, 0, 1, 3): append(offset, count, position, budget, (1, -1, -6))

    # Exercise the full eight-attempt domain, including quota exhaustion after
    # progress, completion on the last attempt and a late non-retryable result.
    for budget in range(9): append(3, budget + 1, MAX_POSITION - 16, budget, (1,) * 8)
    for count, script in ((8, (1,) * 8), (3, (-1,) * 8),
                          (12, (1,) * 7 + (-2,)), (5, (1, -1) * 4),
                          (12, (1,) * 7 + (-5,))):
        append(3, count, MAX_POSITION - count, 8, script)

    rng = random.Random(SEED)
    events = tuple(range(-18, 0)) + (0, 1, 2, 5, 12)
    for _ in range(600):
        count = rng.randrange(13)
        offset = rng.randrange(33 - count)
        position = rng.choice((rng.randrange(1 << 48), MAX_POSITION - count,
                               MAX_POSITION - count + 1, MASK))
        budget = rng.randrange(-1, 9)
        script = tuple(rng.choice(events) for _ in range(rng.randrange(9)))
        append(offset, count, position, budget, script)
    assert len(result) == 11012
    return result


def packet(values):
    result = bytearray()
    for case in values:
        assert case.operation in (0, 1) and case.layout in (0, 1)
        assert MIN_I32 <= case.offset <= MAX_I32 and MIN_I32 <= case.count <= MAX_I32
        assert 0 <= case.position <= MASK and -1 <= case.budget <= 8 and len(case.script) <= 8
        assert all(-18 <= event <= 12 for event in case.script)
        # Every logically valid nonempty array interval is physically backed.
        valid = case.offset >= 0 and case.count >= 0 and case.offset + case.count <= MAX_I32
        if valid and case.count: assert case.offset + case.count <= 32
        header = (case.operation, case.layout, case.offset, case.count, case.position,
                  case.budget, len(case.script), case.identity)
        result += struct.pack("<8Q", *(word & MASK for word in header))
        result += struct.pack("<" + "Q" * len(case.script), *(word & MASK for word in case.script))
    return result


def encode(values):
    result = bytearray()
    for case in values:
        words = reference(case)
        result += struct.pack("<" + "Q" * len(words), *words)
    return result


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = reference(case)
        size = len(want) * 8
        assert offset + size <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        got = struct.unpack_from("<" + "Q" * len(want), actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::31]), values[::31])
    position = (1 << 32) + 11
    read = Case(0, 0, 3, 5, position, 4, (2, -1, 3, -3), 1)
    expected = reference(read)
    assert expected[:10] == [0, 0, 0, 0, 0, 5, 3, 0, 1, 1]
    assert expected[10:42] == [160, 161, 162] + [byte_at(position + i) for i in range(5)] + list(range(168, 192))
    assert expected[42:] == [3, 5, position, 2, 5, 3, position + 2, MASK, 5, 3, position + 2, 3]
    write = Case(1, 1, 4, 5, position, 4, (2, -4, -6), 2)
    rejected = reference(write)
    assert rejected[:10] == [1, 1, 1, 4, 0, 2, 2, 2, 1, 1]
    assert rejected[42:44] == [(2 * 13 + index * 17) & 255 for index in (4, 5)]
    interrupted = reference(Case(0, 0, 3, 5, position, 1, (-1, -6), 3))
    assert interrupted[:10] == [0, 0, 1, 6, 0, 0, 1, 0, 1, 1]
    bad_position = reference(Case(0, 0, 3, 1, MAX_POSITION, 8, (-6,), 4))
    assert bad_position[:10] == [0, 0, 1, 1, 0, 0, 0, 0, 1, 0]
    host = Case(1, 0, 2, 3, position, 2, (1, -9), 5)
    assert reference(host)[:10] == [1, 0, 1, 10, (-123) & MASK, 1, 2, 1, 1, 1]
    mutations = ((read, 5, 4), (read, 10, 0), (read, 44, 11),
                 (write, 42, 0), (host, 4, 123))
    for case, word, replacement in mutations:
        wrong = encode([case])
        struct.pack_into("<Q", wrong, word * 8, replacement)
        try:
            verify(wrong, [case])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted deliberate corruption", case, word))
    outcomes, calls, consumed = Counter(), Counter(), Counter()
    partial_failures = 0
    for case in values:
        words = reference(case)
        outcomes[words[3]] += 1
        calls[words[6]] += 1
        partial_failures += words[2] == 1 and words[5] > 0
        trace = 42 + words[7]
        for index in range(words[6]): consumed[words[trace + index * 4 + 3]] += 1
    assert all(outcomes[code] for code in (0, 1, 2, 3, 4, 5, 6, 8, 9, 10))
    assert consumed[MASK] and partial_failures and calls[8]
    print(f"positional-io CPU cases={len(values)} seed={SEED:#x} "
          f"partial-failures={partial_failures} corruption-controls=5")
    print(f"positional-io outcomes={dict(sorted(outcomes.items()))} calls={dict(sorted(calls.items()))}")


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
    print(f"positional-io cases={len(values)} operations=2 layouts=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
