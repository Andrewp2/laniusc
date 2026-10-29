"""Independent open-description compatibility/lifetime model for real locks.

The executable performs real Lanius opens, duplicates and nonblocking locks.
This reference uses explicit description identities and a compatibility table.
No host flock implementation is called by the Python oracle.
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
import tempfile

SEED = 0xF10C20261030
MASK = (1 << 64) - 1
WORDS = 66
PAYLOAD = bytes((index * 17 + 3) & 255 for index in range(32))


@dataclass(frozen=True)
class Program:
    identity: int
    actions: tuple


def opened(slot, flags=0, position=3): return (0, slot, flags, position)
def duplicate(source, target, close_on_exec=1): return (1, source, target, close_on_exec)
def closed(slot): return (2, slot, 0, 0)
def shared(slot): return (3, slot, 0, 0)
def exclusive(slot): return (4, slot, 0, 0)
def unlocked(slot): return (5, slot, 0, 0)
def seek(slot, position): return (6, slot, 0, position)


def cleanup():
    # The fresh independent acquisition observes release after every last close.
    return tuple(closed(slot) for slot in range(4)) + (opened(0, 0, 0), exclusive(0), unlocked(0), closed(0))


class Model:
    def __init__(self):
        self.handles = [None] * 4
        self.close_on_exec = [None] * 4
        self.descriptions = {}
        self.next_description = 0

    def members(self, description):
        return [slot for slot, value in enumerate(self.handles) if value == description]

    def apply(self, action):
        operation, slot, other, argument = action
        description = self.handles[slot]
        result = [0, 0, 0, 0]
        normalized = 0
        if operation == 0:
            assert description is None
            description = self.next_description
            self.next_description += 1
            self.handles[slot] = description
            self.close_on_exec[slot] = True
            self.descriptions[description] = {
                "lock": None, "position": argument,
                "status": (1024 if other & 1 else 0) | (2048 if other & 2 else 0)}
        elif operation == 1:
            assert self.handles[other] is None
            if description is None:
                result = [1, 10, 9, 0]
            else:
                self.handles[other] = description
                self.close_on_exec[other] = bool(argument)
        elif operation == 2:
            if description is not None:
                self.handles[slot] = None
                self.close_on_exec[slot] = None
                if not self.members(description): del self.descriptions[description]
        elif description is None:
            result = [1, 10, 9, 0]
        elif operation in (3, 4):
            requested = "shared" if operation == 3 else "exclusive"
            others = [record["lock"] for identity, record in self.descriptions.items()
                      if identity != description]
            allowed = (all(mode != "exclusive" for mode in others) if requested == "shared"
                       else all(mode is None for mode in others))
            if allowed:
                self.descriptions[description]["lock"] = requested
            else:
                result = [1, 8, 0, 0]
                normalized = 1
                # This is an observed explicit unlock in the test adapter.
                # It does not assume atomic failed-conversion retention.
                self.descriptions[description]["lock"] = None
        elif operation == 5:
            self.descriptions[description]["lock"] = None
        else:
            assert operation == 6
            self.descriptions[description]["position"] = argument
            result[3] = argument
        prefix = list(action) + result + [normalized, 0, 0, 0, 0, len(PAYLOAD)] + list(PAYLOAD)
        for index, identity in enumerate(self.handles):
            if identity is None:
                prefix.extend((0, MASK, MASK, MASK, MASK))
            else:
                record = self.descriptions[identity]
                # Raw descriptor numbers are opaque; only liveness/uniqueness
                # are contractual, not host allocation order or reuse.
                prefix.extend((1, None, record["position"], record["status"], int(self.close_on_exec[index])))
        assert len(prefix) == WORDS
        return prefix


def programs():
    result = []

    def append(actions):
        result.append(Program(len(result) + 1, tuple(actions) + cleanup()))

    prefix = (opened(0, 0, 3), opened(1, 3, 11))
    alphabet = (shared(0), exclusive(0), unlocked(0), shared(1), exclusive(1), unlocked(1))
    for length in range(4):
        for actions in itertools.product(alphabet, repeat=length): append(prefix + actions)

    alias_prefix = prefix + (duplicate(0, 2, 0), shared(0))
    alias_alphabet = (shared(0), exclusive(0), shared(1), exclusive(1),
                      shared(2), exclusive(2), unlocked(2), closed(0), closed(2))
    for length in range(4):
        for actions in itertools.product(alias_alphabet, repeat=length): append(alias_prefix + actions)

    # Longer named sequences directly exercise lifetime and conversion claims.
    append(prefix + (shared(0), shared(0), shared(1), exclusive(0), exclusive(1),
                     unlocked(1), exclusive(0)))
    append(prefix + (duplicate(0, 2), exclusive(0), closed(0), exclusive(1),
                     closed(2), exclusive(1)))
    append(prefix + (duplicate(0, 2), shared(0), unlocked(2), exclusive(1),
                     shared(2), unlocked(1), exclusive(2)))
    append(prefix + (exclusive(0), closed(0), opened(0, 1, 17), exclusive(1),
                     shared(0), unlocked(1), shared(0)))
    append(prefix + (shared(0), shared(0), unlocked(0), exclusive(1)))
    append(prefix + (exclusive(0), shared(0), shared(1), unlocked(1), exclusive(0)))
    append((opened(0, 3, 7), duplicate(0, 2, 0), seek(2, 29), exclusive(0),
            closed(0), seek(2, 17), unlocked(2), closed(2), opened(0, 0, 3)))
    append((shared(0), exclusive(1), unlocked(2), closed(3), duplicate(0, 3),
            seek(1, 7), opened(0, 2, 5), duplicate(0, 3, 0), shared(3)))

    rng = random.Random(SEED)
    for _ in range(200):
        actions = [opened(0, 0, 3), opened(1, 3, 11), opened(2, 2, 19)]
        live = [True, True, True, False]
        for _ in range(32):
            operation = rng.choice((3, 3, 4, 4, 5, 5, 2, 0, 1, 1, 6))
            slot = rng.randrange(4)
            if operation in (0, 1):
                free = [index for index in range(4) if not live[index]]
                if not free:
                    actions.append(closed(slot))
                    live[slot] = False
                    continue
                target = rng.choice(free)
                if operation == 0:
                    actions.append(opened(target, rng.randrange(4), rng.randrange(32)))
                    live[target] = True
                else:
                    actions.append(duplicate(slot, target, rng.randrange(2)))
                    live[target] = live[slot]
            elif operation == 2:
                actions.append(closed(slot))
                live[slot] = False
            elif operation == 6:
                actions.append(seek(slot, rng.randrange(32)))
            else:
                actions.append((operation, slot, 0, 0))
        append(actions)
    assert len(result) == 1287
    return result


def packet(values):
    result = bytearray()
    for program in values:
        assert len(program.actions) <= 64
        result += struct.pack("<2Q", program.identity, len(program.actions))
        for action in program.actions:
            operation, slot, other, argument = action
            assert 0 <= operation <= 6 and 0 <= slot < 4 and 0 <= other < 4 and 0 <= argument <= 31
            result += struct.pack("<4Q", *action)
    return result


def verify(actual, values):
    offset = 0
    for program_index, program in enumerate(values):
        state = Model()
        for step, action in enumerate(program.actions):
            label = (f"seed={SEED:#x}", program_index, program, step, action)
            wanted = state.apply(action)
            assert offset + WORDS * 8 <= len(actual), (label, "truncated output")
            got = struct.unpack_from("<" + "Q" * WORDS, actual, offset)
            live_descriptors = []
            for index, value in enumerate(wanted):
                if value is None:
                    assert got[index] <= (1 << 31) - 1, (label, "live borrowed descriptor", got[index])
                    live_descriptors.append(got[index])
                else:
                    assert got[index] == value, (label, index, got[index], value, got, wanted)
            assert len(set(live_descriptors)) == len(live_descriptors), (label, "duplicate descriptor ownership")
            offset += WORDS * 8
        assert state.handles == [None] * 4 and not state.descriptions
    assert offset == len(actual), (offset, len(actual), "extra output")


def encoded(values):
    """CPU self-control only, with arbitrary distinct live descriptor numbers."""
    result = bytearray()
    for program in values:
        state = Model()
        for action in program.actions:
            words = state.apply(action)
            words = [(100 + ((index - 47) // 5)) if word is None else word
                     for index, word in enumerate(words)]
            result += struct.pack("<" + "Q" * WORDS, *words)
    return result


def statistics(values):
    counts = Counter()
    operations = Counter()
    for program in values:
        state = Model()
        used = set()
        for action in program.actions:
            operation, slot, other, _ = action
            operations[operation] += 1
            identity = state.handles[slot]
            record = state.descriptions.get(identity)
            old_lock = record["lock"] if record else None
            members = len(state.members(identity)) if identity is not None else 0
            words = state.apply(action)
            counts["steps"] += 1
            counts["would_block"] += words[5] == 8
            counts["closed_owner_error"] += words[5:7] == [10, 9]
            if operation in (3, 4) and record:
                wanted = "shared" if operation == 3 else "exclusive"
                counts["repeated_acquisition"] += old_lock == wanted and words[4] == 0
                counts["failed_conversion"] += old_lock is not None and old_lock != wanted and words[5] == 8
            counts["last_close_locked"] += operation == 2 and members == 1 and old_lock is not None
            counts["close_duplicate_locked"] += operation == 2 and members > 1 and old_lock is not None
            counts["unlock_through_alias"] += operation == 5 and members > 1 and old_lock is not None
            counts["seek_through_alias"] += operation == 6 and members > 1 and words[4] == 0
            if operation == 0:
                counts["reopen"] += slot in used
                used.add(slot)
            shared_holders = sum(value["lock"] == "shared" for value in state.descriptions.values())
            counts["shared_coexistence_states"] += shared_holders > 1
        assert not state.descriptions
    return counts, operations


def controls():
    values = programs()
    assert packet(values)
    verify(encoded(values[::19]), values[::19])
    state = Model()
    for action in (opened(0), opened(1), duplicate(0, 2), exclusive(0), closed(0)):
        state.apply(action)
    assert state.apply(exclusive(1))[4:13] == [1, 8, 0, 0, 1, 0, 0, 0, 0]
    state.apply(closed(2))
    assert state.apply(exclusive(1))[4:8] == [0, 0, 0, 0]
    state = Model()
    for action in (opened(0), opened(1), shared(0), shared(1)): state.apply(action)
    assert state.apply(exclusive(0))[4:13] == [1, 8, 0, 0, 1, 0, 0, 0, 0]
    assert state.descriptions[state.handles[0]]["lock"] is None
    assert state.apply(exclusive(1))[4:8] == [0, 0, 0, 0]
    state = Model()
    for action in (opened(0), opened(1), shared(0), shared(0), unlocked(0)): state.apply(action)
    assert state.apply(exclusive(1))[4:8] == [0, 0, 0, 0]
    control = Program(1, (opened(0, 3, 7), opened(1), duplicate(0, 2, 0), seek(2, 29),
                          exclusive(0), closed(0), exclusive(1), closed(2), exclusive(1)) + cleanup())
    good = encoded([control])
    verify(good, [control])
    mutations = ((6, 5, 0), (3, 48, 7), (3, 60, 1),
                 (3, 57, 100), (3, 14, 0), (5, 46, 1))
    for step, word, replacement in mutations:
        wrong = bytearray(good)
        struct.pack_into("<Q", wrong, (step * WORDS + word) * 8, replacement)
        try:
            verify(wrong, [control])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted deliberate corruption", step, word))
    counts, operations = statistics(values)
    assert all(counts[name] for name in ("would_block", "closed_owner_error", "repeated_acquisition",
        "failed_conversion", "last_close_locked", "close_duplicate_locked", "unlock_through_alias",
        "seek_through_alias", "reopen", "shared_coexistence_states"))
    print(f"file-locks CPU programs={len(values)} steps={counts['steps']} handles=4 "
          f"seed={SEED:#x} corruption-controls=6")
    print(f"file-locks coverage={dict(sorted(counts.items()))} operations={dict(sorted(operations.items()))}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = programs()
    with tempfile.TemporaryDirectory(prefix="lanius-lock-model-") as directory:
        path = Path(directory) / "shared-file"
        path.write_bytes(PAYLOAD)
        output = subprocess.run([str(Path(sys.argv[1]).resolve()), str(path)], input=packet(values),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70)
        assert output.returncode == 0, (output.returncode, output.stderr, len(output.stdout))
        assert not output.stderr, output.stderr
        verify(output.stdout, values)
        assert path.read_bytes() == PAYLOAD, "complete file bytes unchanged"
    steps = sum(len(program.actions) for program in values)
    print(f"file-locks programs={len(values)} steps={steps} handles=4 seed={SEED:#x}")


if __name__ == "__main__":
    main()
