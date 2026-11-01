"""Exact-size iteration model using materialized finite sequences.

Count expectations drain an isolated copy of the list/deque model. They never
reuse the library's cardinality formulas. The live model records upstream pulls
and mapping calls, so queries cannot hide eager evaluation or caching effects.
"""
from __future__ import annotations

from collections import deque
import copy
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xE5AC72026
MAX = (1 << 64) - 1
RECORD = 80


class Source:
    def __init__(self, values, counts, tracked=False):
        self.values = deque(values)
        self.counts, self.tracked = counts, tracked

    def pull(self, back=False):
        if self.tracked:
            self.counts[1 if back else 0] += 1
        if not self.values:
            return None
        return self.values.pop() if back else self.values.popleft()


class Reverse:
    def __init__(self, source):
        self.source, self.done = source, False

    def pull(self, back=False):
        if self.done:
            return None
        value = self.source.pull(not back)
        if value is None:
            self.done = True
        return value


class Map:
    def __init__(self, source, counts):
        self.source, self.counts, self.done = source, counts, False

    def pull(self, back=False):
        if self.done:
            return None
        value = self.source.pull(back)
        if value is None:
            self.done = True
            return None
        self.counts[2] += 1
        return value * 3 + 7


class Take:
    def __init__(self, source, quota):
        self.source, self.quota, self.done = source, quota, False

    def pull(self, back=False):
        assert not back
        if self.done or self.quota == 0:
            return None
        value = self.source.pull()
        if value is None:
            self.done = True
        else:
            self.quota -= 1
        return value


class Skip:
    def __init__(self, source, prefix):
        self.source, self.prefix, self.done = source, prefix, False

    def pull(self, back=False):
        assert not back
        if self.done:
            return None
        while self.prefix:
            if self.source.pull() is None:
                self.done = True
                return None
            self.prefix -= 1
        value = self.source.pull()
        if value is None:
            self.done = True
        return value


class StepBy:
    def __init__(self, source, step):
        assert step > 0
        self.source, self.step, self.first, self.done = source, step, True, False

    def pull(self, back=False):
        assert not back
        if self.done:
            return None
        if not self.first:
            # A finite source bounds this loop even when step == u64::MAX.
            skipped = 0
            while skipped < self.step - 1:
                if self.source.pull() is None:
                    self.done = True
                    return None
                skipped += 1
        self.first = False
        value = self.source.pull()
        if value is None:
            self.done = True
        return value


class Peekable:
    def __init__(self, source):
        self.source, self.cached, self.done = source, None, False

    def peek(self):
        if self.cached is None and not self.done:
            self.cached = self.source.pull()
            if self.cached is None:
                self.done = True
        return self.cached

    def take_cached(self):
        value, self.cached = self.cached, None
        return value

    def finish(self):
        if self.cached is not None:
            return True
        self.done = True
        return False

    def pull(self, back=False):
        assert not back
        if self.cached is not None:
            return self.take_cached()
        if self.done:
            return None
        value = self.source.pull()
        if value is None:
            self.done = True
        return value


def group_values(mode, length, width):
    values = list(range(length))
    if mode == 4:
        return [tuple(values[i:i + width]) for i in range(0, length, width)]
    return [tuple(values[i:i + width]) for i in range(length - width + 1)]


def allowed(mode):
    if mode in (15, 16):
        return (0, 1, 3, 4, 5)
    if mode in (0, 1, 2, 3, 6, 7, 8, 9, 17):
        return (0, 1, 2)
    return (0, 1)


def build(case):
    mode, length, pre, a, b, c, actions = case
    counts = [0, 0, 0]
    if mode == 0:
        source = Source([], counts)
    elif mode == 1:
        source = Source([41] if length else [], counts)
    elif mode in (2, 17):
        source = Source(range(-2, length - 2), counts)
    elif mode in (4, 5):
        source = Source(group_values(mode, length, a), counts)
    else:
        source = Source(range(length), counts, tracked=mode >= 6)
    for _ in range(pre):
        assert source.pull() is not None
    if mode == 7:
        source = Reverse(source)
    elif mode in (8, 9, 16):
        source = Map(source, counts)
        if mode == 9:
            source = Reverse(source)
        if mode == 16:
            source = Peekable(source)
    elif mode == 10:
        source = Take(source, a)
    elif mode == 11:
        source = Skip(source, a)
    elif mode == 12:
        source = StepBy(source, a)
    elif mode == 13:
        source = StepBy(Take(Skip(source, a), b), c)
    elif mode == 14:
        source = Take(Skip(StepBy(source, c), a), b)
    elif mode == 15:
        source = Peekable(source)
    return source, counts


def materialized_count(source):
    isolated = copy.deepcopy(source)
    values = []
    while True:
        value = isolated.pull()
        if value is None:
            return len(values)
        values.append(value)
        assert len(values) <= 8


def encode(value):
    if value is None:
        return 0, 0, 0
    if isinstance(value, tuple):
        packed = sum((item + 1) << (index * 8) for index, item in enumerate(value))
        return 1, packed, len(value)
    return 1, value & MAX, 1


def expected(case):
    source, counts = build(case)
    output = []
    for action in case[-1]:
        before = materialized_count(source)
        value, error = None, False
        if action == 1:
            value = source.pull()
        elif action == 2:
            value = source.pull(True)
        elif action == 3:
            value = source.peek()
        elif action == 4:
            value = source.take_cached()
        elif action == 5:
            error = source.finish()
        else:
            assert action in (0, 6)
        cached = isinstance(source, Peekable) and source.cached is not None
        after = materialized_count(source)
        output.extend((before, *encode(value), int(error), int(cached), after, *counts))
    return output


def cases():
    output = []
    def add(mode, length, pre, a=0, b=0, c=1, actions=(0, 1, 0)):
        output.append((mode, length, pre, a, b, c, tuple(actions)))
    for mode in (0, 1, 2, 3, 6, 7, 8, 9, 17):
        lengths = (0,) if mode == 0 else range(2) if mode == 1 else range(4)
        for length in lengths:
            for pre in range(length + 1):
                for actions in itertools.product(allowed(mode), repeat=3):
                    add(mode, length, pre, actions=actions)
    for mode in (4, 5):
        for length in range(6):
            for width in range(1, 5):
                total = len(group_values(mode, length, width))
                for pre in sorted({0, total // 2, total}):
                    for actions in itertools.product((0, 1), repeat=3):
                        add(mode, length, pre, a=width, actions=actions)
    for mode in (10, 11, 12):
        for length in range(6):
            for pre in sorted({0, length // 2, length}):
                arguments = (1, 2, 3, 5, MAX) if mode == 12 else (0, 1, 2, 5, MAX)
                for argument in arguments:
                    for actions in itertools.product((0, 1), repeat=3):
                        add(mode, length, pre, a=argument, actions=actions)
    compositions = ((0, 0, 1), (0, MAX, 1), (MAX, MAX, 2), (1, 3, 2),
                    (2, 1, 3), (0, 4, 2), (3, 5, MAX), (5, 0, 2))
    for mode in (13, 14):
        for length in range(6):
            for pre in sorted({0, length // 2, length}):
                for a, b, c in compositions:
                    for actions in itertools.product((0, 1), repeat=3):
                        add(mode, length, pre, a, b, c, actions)
    for mode in (15, 16):
        for length in range(5):
            for pre in range(length + 1):
                for actions in itertools.product(allowed(mode), repeat=3):
                    add(mode, length, pre, actions=actions)
                # Cached finish rejection, explicit recovery, then close.
                add(mode, length, pre, actions=(3, 5, 0, 3, 4, 5, 0, 1, 3))
    rng = random.Random(SEED)
    for _ in range(400):
        mode = rng.randrange(18)
        length = 0 if mode == 0 else rng.randrange(2) if mode == 1 else rng.randrange(9)
        a = rng.choice((1, 2, 3, 5, MAX))
        if mode in (4, 5):
            a = rng.randrange(1, 6)
            total = len(group_values(mode, length, a))
        else:
            total = length
        pre = rng.randrange(total + 1)
        b, c = rng.choice((0, 1, 3, MAX)), rng.choice((1, 2, 3, MAX))
        actions = [rng.choice(allowed(mode) + (6,)) for _ in range(12)]
        add(mode, length, pre, a, b, c, actions)
    return output


def packet(values):
    output = bytearray()
    for mode, length, pre, a, b, c, actions in values:
        schedule = sum(action << (3 * index) for index, action in enumerate(actions))
        output += struct.pack("<8Q", mode, length, pre, a, b, c, len(actions), schedule)
    return output


def verify(actual, values):
    expected_bytes = sum(len(case[-1]) for case in values) * RECORD
    assert len(actual) == expected_bytes, (len(actual), expected_bytes)
    offset = 0
    for index, case in enumerate(values):
        want = expected(case)
        got = struct.unpack_from("<" + "Q" * len(want), actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += len(want) * 8
    assert offset == len(actual)


def controls():
    values = cases()
    sample = values[::97]
    actual = b"".join(struct.pack("<" + "Q" * len(words), *words)
                      for words in map(expected, sample))
    verify(actual, sample)
    broken = bytearray(actual)
    broken[0] ^= 1
    try:
        verify(broken, sample)
    except AssertionError:
        pass
    else:
        raise AssertionError("model failed to reject a changed count")
    # Explicit independent cache/finish observation, including callback count.
    recovery = (16, 2, 0, 0, 0, 1, (3, 5, 0, 4, 5, 1))
    words = expected(recovery)
    assert words[:10] == [2, 1, 7, 1, 0, 1, 2, 1, 0, 1]
    assert words[10:20] == [2, 0, 0, 0, 1, 1, 2, 1, 0, 1]
    assert words[-10:] == [0, 0, 0, 0, 0, 0, 0, 1, 0, 1]
    print(f"exact-size-iterators CPU cases={len(sample)} all-cases={len(values)} count-corruption=rejected cache-recovery=checked")


def main():
    if sys.argv[1:] == ["controls"]:
        controls()
        return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=45, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values)
    print(f"exact-size-iterators cases={len(values)} steps={sum(len(case[-1]) for case in values)} modes=18 seed={SEED:#x}")


if __name__ == "__main__":
    main()
