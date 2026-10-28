"""Finite sequence/state model for eight iterator fold APIs.

The oracle keeps materialized deques, explicit callback traces and observable
poll counters. It does not invoke a Lanius or native library implementation.
All arithmetic is bounded integer arithmetic and order-sensitive.
"""
from __future__ import annotations
from collections import deque
from dataclasses import dataclass
import random
from pathlib import Path
import struct
import subprocess
import sys

SEED = 0xF01D20261029
MASK = (1 << 64) - 1
BOUND = 17 * 17**8 + 18 * (17**8 - 1) // 16
assert BOUND < 2**37 < 2**63


@dataclass(frozen=True)
class Case:
    kind: int
    length: int
    front: int
    back: int
    mode: int
    target: int
    initial: int
    commands: tuple


class State:
    def __init__(self):
        self.front_polls = self.back_polls = self.front_ok = self.back_ok = 0
        self.callbacks = self.maps = self.queries = 0
        self.trace = []


class Source:
    def __init__(self, length, state):
        self.values = deque(range(1, length + 1))
        self.state = state

    def pull(self, back=False):
        state = self.state
        state.trace.append((2 if back else 1, 0, 0))
        if back: state.back_polls += 1
        else: state.front_polls += 1
        if not self.values: return None
        if back:
            state.back_ok += 1
            return self.values.pop()
        state.front_ok += 1
        return self.values.popleft()


class Map:
    def __init__(self, source, state, transform=False):
        self.source, self.state, self.transform, self.done = source, state, transform, False

    def pull(self, back=False):
        if self.done: return None
        value = self.source.pull(back)
        if value is None:
            self.done = True
            return None
        mapped = value * 2 + 1 if self.transform else value
        self.state.maps += 1
        self.state.trace.append((4 if self.transform else 3, value, mapped))
        return mapped


class Reverse:
    def __init__(self, source): self.source, self.done = source, False
    def pull(self, back=False):
        if self.done: return None
        value = self.source.pull(not back)
        if value is None: self.done = True
        return value


def apply(state, value, accumulator, fallible, mode, target):
    state.trace.append((6 if fallible else 5, accumulator, value))
    state.callbacks += 1
    fail = fallible and ((mode == 1 and value == target) or
                         (mode == 2 and state.callbacks == target) or
                         (mode == 3 and value != target))
    if fail:
        return None, (value, accumulator, MASK - value * 131 - state.callbacks, state.callbacks)
    answer = accumulator * 17 + value + 1
    assert 0 <= answer <= BOUND, (answer, BOUND)
    return answer, None


def expected(case):
    state = State()
    base = Source(case.length, state)
    for _ in range(case.front): assert base.pull() is not None
    for _ in range(case.back): assert base.pull(True) is not None
    source = base
    if case.kind in (1, 2, 3): source = Map(base, state, transform=case.kind == 3)
    if case.kind == 2: source = Reverse(source)
    carry = case.initial
    output = []
    for op, quota, seed in case.commands:
        seed = carry if seed == MASK else seed
        assert 0 <= seed <= BOUND
        tag, accumulator, folded, exhausted = 0, 0, MASK, False
        error = (0, 0, 0, 0)
        if op in (8, 9):
            item = source.pull(op == 9)
            tag = 6 if item is None else 7
            accumulator = 0 if item is None else item
        else:
            back = op in (2, 3, 6, 7)
            fallible = op in (1, 3, 5, 7)
            bounded = op >= 4
            if op in (0, 1):
                current = source.pull()
                if current is None:
                    tag = 0
                else:
                    while True:
                        item = source.pull()
                        if item is None:
                            tag, accumulator, carry = 1, current, current
                            break
                        current, failure = apply(state, item, current, fallible, case.mode, case.target)
                        if failure is not None:
                            tag, error, carry = 4, failure, failure[1]
                            break
            else:
                current, successful = seed, 0
                while not bounded or successful < quota:
                    item = source.pull(back)
                    if item is None:
                        exhausted = bounded
                        break
                    current, failure = apply(state, item, current, fallible, case.mode, case.target)
                    if failure is not None:
                        tag, error, carry = (5 if bounded else 4), failure, failure[1]
                        break
                    successful += 1
                if tag not in (4, 5):
                    tag = 3 if bounded else 2
                    accumulator = current
                    carry = current
                if bounded: folded = successful
        output.extend((op, tag, accumulator, folded, int(exhausted), *error,
                       state.front_ok, state.back_ok, state.front_polls, state.back_polls,
                       state.callbacks, state.maps, state.queries))
    assert len(state.trace) < 128
    output.append(len(state.trace))
    output.extend(word & MASK for event in state.trace for word in event)
    return output


def cases():
    output = []
    policies = ((0, 0), (1, 1), (1, 3), (2, 1), (2, 2), (3, 2))
    for kind in range(4):
        for length in range(4):
            for front in range(length + 1):
                for back in range(length - front + 1):
                    remaining = length - front - back
                    for op in range(8):
                        quotas = sorted({0, 1, remaining, remaining + 1, MASK}) if op >= 4 else (0,)
                        for quota in quotas:
                            for mode, target in policies:
                                # Resume from the opposite end after any error,
                                # then fold the remaining middle with the carry.
                                commands = ((op, quota, 2), (8 if op in (2, 3, 6, 7) else 9, 0, 0),
                                            (4 if op in (2, 3, 6, 7) else 6, MASK, MASK))
                                output.append(Case(kind, length, front, back, mode, target, 2, commands))
    for kind in range(4):
        for length in range(9):
            for mode, target in ((0, 0), (2, 2)):
                commands = ((5, 1, 0), (7, 1, MASK), (5, 0, MASK),
                            (7, 2, MASK), (1, 0, MASK), (2, 0, MASK))
                output.append(Case(kind, length, 0, 0, mode, target, 0, commands))
    rng = random.Random(SEED)
    for _ in range(1600):
        kind, length = rng.randrange(4), rng.randrange(9)
        front = rng.randrange(length + 1)
        back = rng.randrange(length - front + 1)
        mode, target = rng.randrange(4), rng.randrange(1, 19)
        commands = []
        for index in range(6):
            op = rng.randrange(4, 10) if index < 3 else rng.randrange(10)
            quota = rng.choice((0, 1, 2, length, length + 1, MASK))
            seed = MASK if rng.randrange(4) else rng.randrange(4)
            commands.append((op, quota, seed))
        output.append(Case(kind, length, front, back, mode, target, rng.randrange(4), tuple(commands)))
    return output


def packet(values):
    output = bytearray()
    for case in values:
        output += struct.pack("<8Q", case.kind, case.length, case.front, case.back,
                              case.mode, case.target, case.initial, len(case.commands))
        for command in case.commands: output += struct.pack("<3Q", *command)
    return output


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = expected(case)
        length = len(want) * 8
        assert offset + length <= len(actual), (index, case, "truncated output")
        got = struct.unpack_from("<" + "Q" * len(want), actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += length
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    sample = values[::83]
    actual = b"".join(struct.pack("<" + "Q" * len(words), *words) for words in map(expected, sample))
    verify(actual, sample)
    selected = Case(0, 2, 0, 0, 2, 1, 3, ((5, 1, 3), (8, 0, 0), (6, MASK, MASK)))
    words = expected(selected)
    assert words[:16] == [5, 5, 0, 0, 0, 1, 3, MASK - 132, 1, 1, 0, 1, 0, 1, 0, 0]
    bad = words.copy(); bad[7] ^= 1
    try:
        verify(struct.pack("<" + "Q" * len(bad), *bad), [selected])
    except AssertionError:
        pass
    else:
        raise AssertionError("model accepted changed callback error identity")
    maximum = 0
    distribution = [0] * 10
    for case in values:
        words = expected(case)
        for op, quota, seed in case.commands: distribution[op] += 1
        for index in range(len(case.commands)): maximum = max(maximum, words[index * 16 + 2], words[index * 16 + 6])
    print(f"iterator-folds CPU cases={len(values)} bound={BOUND} observed_accumulator_max={maximum} error-identity-corruption=rejected")
    print(f"iterator-folds command-distribution={distribution}")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values)
    print(f"iterator-folds cases={len(values)} commands={sum(len(case.commands) for case in values)} sources=4 seed={SEED:#x}")


if __name__ == "__main__":
    main()
