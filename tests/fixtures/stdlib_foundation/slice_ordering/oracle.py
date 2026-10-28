"""Independent finite models for checked comparator-driven slice algorithms.

Python sorting, bisect and filtering supply the reference. Actual permitted
unstable tie layouts are adopted only after permutation and ordering checks.
This file and its binary transport are test infrastructure, not product code.
"""
from __future__ import annotations

import bisect
from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x510CE0261029
MASK = (1 << 64) - 1
POOL = 20
ROW_WORDS = 6
ACTION_WORDS = 3 + POOL * ROW_WORDS


@dataclass(frozen=True)
class Case:
    layout: int
    identity: int
    keys: tuple
    start: int
    length: int
    actions: tuple


def row(key, identity):
    flag = 0 if identity % 3 == 0 else (2 if identity % 2 == 0 else 1)
    return (key & MASK, identity, MASK - identity * 17,
            identity * 97 + 3, (1 << 32) + identity * 131, flag)


def signed(value):
    return value if value < 1 << 63 else value - (1 << 64)


def initial(case):
    result = [row(700 + index, 100000 + index) for index in range(POOL)]
    for index, key in enumerate(case.keys):
        result[index + 2] = row(key, case.identity * 16 + index + 1)
    return result


def rank(value, mode, parameter):
    if mode == 0: return value
    if mode == 1: return -value
    if mode == 2: return abs(value)
    if mode == 3: return -abs(value)
    if mode == 4: return abs(value) // parameter
    assert mode == 5
    return abs(value - parameter)


def ranks(rows, mode, parameter):
    return [rank(signed(item[0]), mode, parameter) for item in rows]


def schedule(mode, parameter, alternate_parameter, first, second):
    other = (mode + 1) % 6
    a = lambda operation: (operation, first, mode, parameter)
    b = lambda operation: (operation, second, other, alternate_parameter)
    return (a(1), a(6), a(1), a(0), a(1), a(2), a(3), a(4), a(5),
            b(0), b(1), b(2), b(3), b(4), b(5), b(6))


def policy_parameter(mode, number):
    if mode == 4: return number % 4 + 1
    if mode == 5: return number % 9 - 4
    return 0


def cases():
    result = []
    datasets = 0

    def append(keys, start, length, mode, first, second):
        nonlocal datasets
        parameter = policy_parameter(mode, datasets)
        other_parameter = policy_parameter((mode + 1) % 6, datasets + 3)
        actions = schedule(mode, parameter, other_parameter, first, second)
        for layout in range(2):
            result.append(Case(layout, len(result) + 1, tuple(keys), start, length, actions))
        datasets += 1

    # Every length <= 4 over a three-value alphabet, under every policy.
    for length in range(5):
        for keys in itertools.product((-1, 0, 1), repeat=length):
            for mode in range(6):
                first = (keys[datasets % length] if length and datasets % 2 == 0
                         else (-2, -1, 0, 1, 2)[datasets % 5])
                second = (-4, 0, 4)[datasets % 3]
                append(keys, 0, length, mode, first, second)

    # Explicit interior subviews of every supported backing length.
    for length in range(13):
        keys = tuple((index * 5) % 9 - 4 for index in range(length))
        start = 1 if length else 0
        selected = max(0, length - 2)
        for mode in range(6): append(keys, start, selected, mode, 0, 20)

    rng = random.Random(SEED)
    for _ in range(600):
        length = rng.randrange(13)
        keys = tuple(rng.randrange(-12, 13) for _ in range(length))
        start = rng.randrange(length + 1)
        selected = rng.randrange(length - start + 1)
        mode = rng.randrange(6)
        first = (keys[start + rng.randrange(selected)] if selected and rng.randrange(2)
                 else rng.randrange(-20, 21))
        second = rng.randrange(-20, 21)
        append(keys, start, selected, mode, first, second)
    assert datasets == 1404 and len(result) == 2808
    return result


def packet(values):
    result = bytearray()
    for case in values:
        assert 0 <= case.start <= len(case.keys) <= 12
        assert 0 <= case.length <= len(case.keys) - case.start
        assert len(case.actions) <= 16
        assert all(-12 <= key <= 12 for key in case.keys)
        result += struct.pack("<8Q", case.layout, len(case.keys), case.start,
                              case.length, len(case.actions), case.identity, 0, 0)
        result += struct.pack("<" + "Q" * len(case.keys), *(key & MASK for key in case.keys))
        for action in case.actions:
            operation, needle, mode, parameter = action
            assert 0 <= operation <= 6 and -20 <= needle <= 20 and 0 <= mode <= 5
            assert 1 <= parameter <= 4 if mode == 4 else -4 <= parameter <= 4
            result += struct.pack("<4Q", *(word & MASK for word in action))
    return result


def check_action(case, action, before, words, label):
    operation, needle, mode, parameter = action
    got_operation, raw_result, calls = words[:3]
    result = signed(raw_result)
    after = [tuple(words[index:index + ROW_WORDS])
             for index in range(3, ACTION_WORDS, ROW_WORDS)]
    low, high = case.start + 2, case.start + 2 + case.length
    old, changed = before[low:high], after[low:high]
    assert got_operation == operation, (label, "operation", got_operation, operation)
    assert after[:low] == before[:low] and after[high:] == before[high:], (label, "outside selected view")
    assert Counter(changed) == Counter(old), (label, "whole-record permutation", old, changed)
    projected = ranks(old, mode, parameter)
    target = rank(needle, mode, parameter)
    if not case.length or (case.length == 1 and operation == 0):
        assert calls == 0, (label, "empty/singleton callback", calls)
    if operation == 0:
        assert result == case.length, (label, "sort result", result, case.length)
        assert ranks(changed, mode, parameter) == sorted(projected), (label, "sort order", changed)
    elif operation == 6:
        less = [item for item in old if rank(signed(item[0]), mode, parameter) < target]
        rest = [item for item in old if rank(signed(item[0]), mode, parameter) >= target]
        assert result == len(less), (label, "partition boundary", result, len(less))
        assert Counter(changed[:result]) == Counter(less), (label, "partition Less side")
        assert Counter(changed[result:]) == Counter(rest), (label, "partition other side")
    else:
        assert after == before, (label, "read-only API changed storage")
        if operation == 1:
            want = int(projected == sorted(projected))
        else:
            assert projected == sorted(projected), (label, "oracle query precondition")
            left, right = bisect.bisect_left(projected, target), bisect.bisect_right(projected, target)
            equal = [index for index, value in enumerate(projected) if value == target]
            assert equal == list(range(left, right))
            want = {2: left, 3: right, 4: equal[0] if equal else -1,
                    5: equal[-1] if equal else -1}[operation]
        assert result == want, (label, "query result", result, want, projected, target)
    return after


def verify(actual, values):
    offset = 0
    record_size = ACTION_WORDS * 8
    for case_index, case in enumerate(values):
        state = initial(case)
        for action_index, action in enumerate(case.actions):
            label = (f"seed={SEED:#x}", case_index, action_index, case, action)
            assert offset + record_size <= len(actual), (label, "truncated output")
            words = struct.unpack_from("<" + "Q" * ACTION_WORDS, actual, offset)
            state = check_action(case, action, state, words, label)
            offset += record_size
    assert offset == len(actual), (offset, len(actual), "extra output")


def synthesized(values, reverse_ties=False):
    """Oracle self-control only: choose an arbitrary legal unstable layout."""
    result = bytearray()
    for case in values:
        state = initial(case)
        low, high = case.start + 2, case.start + 2 + case.length
        for operation, needle, mode, parameter in case.actions:
            selected = state[low:high]
            key = lambda item: rank(signed(item[0]), mode, parameter)
            projected = [key(item) for item in selected]
            target = rank(needle, mode, parameter)
            if operation == 0:
                arranged = sorted(selected, key=key)
                if reverse_ties:
                    arranged = [item for _, group in itertools.groupby(arranged, key=key)
                                for item in reversed(list(group))]
                state[low:high] = arranged
                answer = len(selected)
            elif operation == 6:
                left = [item for item in selected if key(item) < target]
                right = [item for item in selected if key(item) >= target]
                state[low:high] = list(reversed(left)) + list(reversed(right))
                answer = len(left)
            elif operation == 1:
                answer = int(projected == sorted(projected))
            else:
                left, right = bisect.bisect_left(projected, target), bisect.bisect_right(projected, target)
                answer = {2: left, 3: right, 4: left if left < right else -1,
                          5: right - 1 if left < right else -1}[operation]
            words = [operation, answer & MASK, 0]
            words.extend(word for item in state for word in item)
            result += struct.pack("<" + "Q" * ACTION_WORDS, *words)
    return result


def statistics(values):
    operations, policies = Counter(), Counter()
    queries = Counter()
    for case in values:
        for operation, needle, mode, parameter in case.actions:
            operations[operation] += 1
            policies[mode] += 1
            if operation == 4:
                selected = case.keys[case.start:case.start + case.length]
                projected = sorted(rank(item, mode, parameter) for item in selected)
                target = rank(needle, mode, parameter)
                equal = projected.count(target)
                queries["duplicate" if equal > 1 else "single" if equal else "missing"] += 1
                if not projected: queries["empty"] += 1
                elif target < projected[0]: queries["before"] += 1
                elif target > projected[-1]: queries["after"] += 1
    return operations, policies, queries


def controls():
    values = cases()
    assert packet(values)
    # Two legal choices of unstable tie order must both be accepted.
    samples = values[::23]
    verify(synthesized(samples), samples)
    verify(synthesized(samples, reverse_ties=True), samples)
    control = Case(0, 1, (2, 1, 2, 1), 0, 4, schedule(0, 0, 0, 1, 2))
    good = synthesized([control], reverse_ties=True)
    assert good != synthesized([control])
    verify(good, [control])
    mutations = []
    # An unselected guard, one payload word, a partition boundary, and an
    # arbitrary duplicate hit must never pass as valid alternative layouts.
    mutations.append((3 + 1, 100001))
    mutations.append((3 + (2 * ROW_WORDS) + 3, 0))
    mutations.append((ACTION_WORDS + 1, 1))
    mutations.append((7 * ACTION_WORDS + 1, 1))
    for word, replacement in mutations:
        corrupted = bytearray(good)
        struct.pack_into("<Q", corrupted, word * 8, replacement)
        try:
            verify(corrupted, [control])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted intentional corruption", word))
    operations, policies, queries = statistics(values)
    assert sum(operations.values()) == 44928
    assert all(policies[policy] for policy in range(6))
    assert all(queries[name] for name in ("duplicate", "single", "missing", "empty", "before", "after"))
    print(f"slice-ordering CPU cases={len(values)} actions={sum(operations.values())} "
          f"seed={SEED:#x} legal-tie-layouts=2 corruption-controls=4")
    print(f"slice-ordering operations={dict(sorted(operations.items()))} "
          f"policies={dict(sorted(policies.items()))} queries={dict(sorted(queries.items()))}")


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
    print(f"slice-ordering cases={len(values)} actions={sum(len(case.actions) for case in values)} "
          f"layouts=2 policies=6 seed={SEED:#x}")


if __name__ == "__main__":
    main()
