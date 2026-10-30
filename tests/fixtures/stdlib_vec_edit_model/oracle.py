"""Independent ordered-authority model; Python never implements a library API.

Retention is a selection over original identities. Adjacent deduplication walks
representative groups rather than mutable slots. The native transcript must
also expose the precise interleaving of decisions and destruction, so equal
final lists alone do not suffice. Synthetic transcripts test this verifier only.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x7ECED170261118
MAGIC = 0x7665636564697473
END = 0x656E646564697473
MASK = (1 << 64) - 1
MAX = (1 << 31) - 1
NAMES = ('push', 'retain', 'dedup_by', 'dedup', 'truncate', 'clear')
# core::mem's native record contract counts eight-byte words, including i32
# record fields. Small: id/key/reference. Owned: id/key/wide, Option<bool>'s
# tag+payload, three array words, three Vec descriptor words, reference.
PROFILE_SIZES = (8 * (1 + 1 + 1), 8 * (3 + 2 + 3 + 3 + 1))


@dataclass(frozen=True)
class Item:
    identity: int
    key: int


@dataclass(frozen=True)
class Case:
    shape: int
    reserve: int
    actions: tuple


class State:
    def __init__(self):
        self.items = []; self.calls = self.destroyed = self.salt = 0
        self.created = []; self.retired = []

    def step(self, action, mutant=None):
        op, a, b = action
        before = tuple(self.items); self.salt = b; events = []

        def retire(item):
            events.append((4, self.calls, self.destroyed, item.identity, item.key, 0, 0, 0))
            self.destroyed += 1; self.retired.append(item.identity)

        def decide(kind, left, right=None):
            self.calls += 1
            rkey = 0 if right is None else right.key
            if kind == 1:
                answers = (True, False, (left.key + b) % 2 == 0,
                           (left.key + self.calls + self.destroyed + b) % 3 != 0)
                answer = answers[a]
            elif kind == 3:
                answer = left.key == rkey
            else:
                answers = (left.key == rkey, abs(left.key - rkey) <= 1,
                           (left.key + 3 * rkey + self.calls + self.destroyed + b) % 4 <= 1,
                           left.key <= rkey)
                answer = answers[a]
            events.append((kind, self.calls, self.destroyed, left.identity, left.key,
                           0 if right is None else right.identity, rkey, int(answer)))
            return answer

        code = answer = 0
        if op == 0:
            assert b > 0 and b not in self.created
            self.created.append(b); self.items.append(Item(b, a)); answer = len(self.items)
        elif op == 1:
            selected = []
            for item in before:
                if decide(1, item): selected.append(item)
                else: retire(item)
            self.items = selected; answer = len(before) - len(selected)
        elif op in (2, 3):
            # Each retained representative starts a group. The next false
            # decision starts the next group; every candidate is tested once.
            remaining = before; representatives = []
            while remaining:
                representative = remaining[0]; representatives.append(representative)
                suffix = remaining[1:]; boundary = len(suffix)
                previous = representative
                for index, current in enumerate(suffix):
                    left = previous if mutant == 'previous original' else representative
                    equal = decide(3 if op == 3 else 2, left, current)
                    previous = current
                    if not equal:
                        boundary = index; break
                    retire(current)
                remaining = suffix[boundary:]
            self.items = representatives; answer = len(before) - len(representatives)
        elif op == 4:
            if a < 0: code = 1
            else:
                self.items = list(before[:a])
                for item in reversed(before[a:]): retire(item)
                answer = len(self.items)
        elif op == 5:
            self.items = []
            for item in reversed(before): retire(item)
        else: raise AssertionError(action)
        assert Counter(x.identity for x in self.items) + Counter(self.retired) == Counter(self.created)
        assert len(self.retired) == len(set(self.retired))
        return code, answer, events


def schedule(profile):
    rng = random.Random(SEED + profile); state = State(); actions = []; identity = 0
    def add(op, a=0, b=0):
        action = (op, a, b); state.step(action); actions.append(action)
        assert len(state.items) <= 24
    def push(key):
        nonlocal identity
        identity += 1; add(0, key, identity)
    add(1, profile % 4, profile); add(2, profile % 4, profile); add(3); add(4, -1); add(5)
    for key in (0, 1, 2): push(key)
    add(2, 1)  # [0,1,2] must retain [0,2], not just [0].
    add(1, 0); add(4, MAX); add(4, -1); add(5)
    for key in (2, 2, 2, 3, 3, 2, 2): push(key)
    add(3); add(4, 2); add(5)
    for key in (5, 5, 5): push(key)
    add(2, 3); push(7); add(1, 3, profile); add(5)
    for key in (3, 1, 4, 1, 5, 9): push(key)
    add(1, 2, profile % 2); add(2, 2, profile)
    while len(actions) < 80:
        pick = rng.randrange(12)
        if len(state.items) < 2 or (pick < 5 and len(state.items) < 24):
            push(rng.randrange(10))
        elif pick < 7: add(1, rng.randrange(4), rng.randrange(11))
        elif pick < 9: add(2, rng.randrange(4), rng.randrange(11))
        elif pick == 9: add(3)
        elif pick == 10: add(4, rng.choice((-1, 0, 1, len(state.items), len(state.items) + 1, MAX)))
        else: add(5)
    return tuple(actions)


def corpus():
    scripts = [schedule(i) for i in range(12)]
    return [Case(shape, (0, 1, 5, 31)[i % 4], script)
            for shape in range(2) for i, script in enumerate(scripts)]


def payload(item):
    identity, key = item.identity, item.key
    tag = 0 if identity % 3 == 0 else 2 if identity % 2 == 0 else 1
    return [MASK - identity * 4294967297, tag, identity, -key, identity * 1000003 - 100000000]


def inner_bytes(item):
    return [(item.identity * 17 + item.key * 19 + i * 31) & 255 for i in range(item.identity % 7 + 1)]


class Reader:
    def __init__(self, data): self.data = data; self.at = 0; self.marks = {}; self.context = None
    def word(self, label):
        assert self.at + 8 <= len(self.data), ('truncated', self.context, self.at)
        self.marks.setdefault(label, self.at)
        value = struct.unpack_from('<Q', self.data, self.at)[0]; self.at += 8; return value
    def expect(self, value, label):
        got = self.word(label)
        assert got == value & MASK, (self.context, label, got, value)


def snapshot(reader, case, state, size, inner, counts):
    r = reader
    r.expect(state.calls, 'callback counter'); r.expect(state.destroyed, 'destruction counter')
    r.expect(state.salt, 'context salt'); r.expect(len(state.items), 'vector length')
    cap, address = r.word('vector capacity'), r.word('vector address')
    assert len(state.items) <= cap <= MAX // size
    assert (cap == 0) == (address == 0)
    r.expect(-size, 'vector stride'); r.expect(0, 'view start')
    r.expect(len(state.items), 'view length'); r.expect(not state.items, 'empty flag')
    ranges = [(address, address + cap * size)] if cap else []
    for item in state.items:
        r.expect(item.identity, 'survivor identity'); r.expect(item.key, 'survivor key')
        if case.shape:
            for word in payload(item): r.expect(word, 'compound payload')
            expected = inner_bytes(item)
            r.expect(len(expected), 'nested length')
            c, p = r.word('nested capacity'), r.word('nested address')
            assert len(expected) <= c <= MAX and p > 0
            if item.identity in inner: assert inner[item.identity] == (c, p), ('nested authority changed', item)
            else: inner[item.identity] = c, p
            for byte in expected: r.expect(byte, 'nested byte')
            ranges.append((p, p + c))
        counts['snapshot_items'] += 1
    ranges.sort()
    assert all(left[1] <= right[0] for left, right in zip(ranges, ranges[1:])), ('live allocations overlap', r.context)
    return cap, address


def read_events(r, expected, counts):
    r.expect(len(expected), 'event count')
    for event in expected:
        kind = event[0]
        labels = ('event kind', 'event call ordinal', 'event destroyed before',
                  'event left identity', 'event left key', 'event right identity', 'event right key', 'event result')
        for word, label in zip(event, labels): r.expect(word, label)
        counts['events'] += 1
        counts[('unused', 'predicates', 'comparisons', 'natural_comparisons', 'destroyed')[kind]] += 1


def verify(data, cases):
    r = Reader(data); counts = Counter(); r.expect(MAGIC, 'magic'); r.expect(len(cases), 'case count')
    for index, case in enumerate(cases):
        r.context = (index, 'initial')
        for value, label in ((index, 'case index'), (case.shape, 'shape'), (case.reserve, 'reserve'),
                             (len(case.actions), 'action count')): r.expect(value, label)
        size = r.word('element size'); assert size == PROFILE_SIZES[case.shape]
        state = State(); inner = {}; metadata = snapshot(r, case, state, size, inner, counts)
        assert metadata[0] >= case.reserve
        if case.reserve == 0: assert metadata == (0, 0)
        for step, action in enumerate(case.actions):
            r.context = (index, step, NAMES[action[0]], action)
            old = tuple(state.items); previous = metadata
            code, answer, events = state.step(action)
            for value, label in ((step, 'step'), (action[0], 'operation'), (code, 'status'), (answer, 'answer')):
                r.expect(value, label)
            read_events(r, events, counts)
            metadata = snapshot(r, case, state, size, inner, counts)
            if action[0] != 0 or len(state.items) <= previous[0]:
                assert metadata == previous, ('backing/capacity changed during edit', r.context, previous, metadata)
            else: assert metadata[0] >= len(state.items) and metadata[0] >= previous[0]
            counts['actions'] += 1; counts[NAMES[action[0]]] += 1
            counts['bounds'] += code == 1
            counts['empty_edits'] += action[0] != 0 and not old
            counts['singleton_edits'] += action[0] != 0 and len(old) == 1
            counts['refills'] += action[0] == 0 and not old and previous[0] > 0
        r.context = (index, 'final retirement')
        previous = metadata
        _, _, events = state.step((5, 0, 0))
        r.expect(99, 'cleanup marker'); read_events(r, events, counts)
        metadata = snapshot(r, case, state, size, inner, counts); assert metadata == previous
        r.context = (index, 'backing release')
        assert snapshot(r, case, state, size, inner, counts) == (0, 0)
        assert Counter(state.retired) == Counter(state.created)
        counts['created'] += len(state.created)
        counts['nested_owners'] += case.shape * len(state.created)
    r.expect(END, 'end marker'); assert r.at == len(data), ('trailing bytes', r.at, len(data))
    assert counts['created'] == counts['destroyed']
    assert min(counts[name] for name in ('predicates', 'comparisons', 'natural_comparisons', 'bounds',
                                       'empty_edits', 'singleton_edits', 'refills')) > 0
    return counts, r.marks


class Writer:
    def __init__(self): self.data = bytearray()
    def word(self, value): self.data += struct.pack('<Q', value & MASK)
    def words(self, values):
        for value in values: self.word(value)
    def snapshot(self, case, state, size, cap, address, inner):
        self.words((state.calls, state.destroyed, state.salt, len(state.items), cap, address,
                    -size, 0, len(state.items), not state.items))
        for item in state.items:
            self.words((item.identity, item.key))
            if case.shape:
                values = inner_bytes(item); c, p = inner[item.identity]
                self.words(payload(item)); self.words((len(values), c, p)); self.words(values)


def simulated(cases, policy=0, mutant=None):
    """Verifier controls only; native observations always come from model.lani."""
    w = Writer(); w.words((MAGIC, len(cases))); address = 0x100000; reached = False
    def allocate(count, size):
        nonlocal address
        if not count: return 0
        pointer = address; address += ((count * size + 4095) // 4096 + 1) * 4096; return pointer
    def capacity(needed): return needed if policy == 0 else (1 << needed.bit_length())
    for index, case in enumerate(cases):
        size = PROFILE_SIZES[case.shape]; cap = capacity(case.reserve) if case.reserve else 0
        pointer = allocate(cap, size); state = State(); inner = {}
        w.words((index, case.shape, case.reserve, len(case.actions), size))
        w.snapshot(case, state, size, cap, pointer, inner)
        for step, action in enumerate(case.actions):
            code, answer, events = state.step(action, mutant)
            if action[0] == 0:
                if len(state.items) > cap: cap = capacity(len(state.items)); pointer = allocate(cap, size)
                if case.shape:
                    value = state.items[-1]; count = len(inner_bytes(value)); c = capacity(count)
                    inner[value.identity] = c, allocate(c, 1)
            if mutant == 'previous original' and action[0] == 2 and action[1] == 1: reached = True
            if not reached and mutant == 'deferred destruction' and any(e[0] == 4 for e in events) and any(e[0] != 4 for e in events):
                events = [e for e in events if e[0] != 4] + [e for e in events if e[0] == 4]; reached = True
            if not reached and mutant == 'forward tail cleanup' and action[0] in (4, 5) and len(events) > 1:
                events.reverse(); reached = True
            if not reached and mutant == 'reversed survivors' and action[0] != 0 and len(state.items) > 1:
                state.items.reverse(); reached = True
            if not reached and mutant == 'edit grows backing' and action[0] != 0 and cap:
                cap += 1; pointer = allocate(cap, size); reached = True
            w.words((step, action[0], code, answer, len(events)))
            for event in events: w.words(event)
            w.snapshot(case, state, size, cap, pointer, inner)
        _, _, events = state.step((5, 0, 0)); w.words((99, len(events)))
        for event in events: w.words(event)
        w.snapshot(case, state, size, cap, pointer, inner)
        w.snapshot(case, state, size, 0, 0, inner)
    w.word(END)
    if mutant: assert reached, ('unreached mutation', mutant)
    return bytes(w.data)


def packet(cases):
    result = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for case in cases:
        result += struct.pack('<3Q', case.shape, case.reserve, len(case.actions))
        for action in case.actions: result += struct.pack('<3Q', *(word & MASK for word in action))
    return bytes(result)


def summary(cases, counts):
    keys = ('actions', 'created', 'nested_owners', 'predicates', 'comparisons', 'natural_comparisons',
            'destroyed', 'events', 'bounds', 'empty_edits', 'singleton_edits', 'refills', 'snapshot_items')
    return ('vec-edit-model cases=%d ' % len(cases) + ' '.join('%s=%d' % (k, counts[k]) for k in keys)
            + ' shapes=2 seed=0x%x\n' % SEED)


def reject(data, cases, label):
    try: verify(data, cases)
    except (AssertionError, struct.error, KeyError, IndexError): return
    raise AssertionError('accepted corruption: ' + label)


def controls(cases):
    data = simulated(cases); counts, marks = verify(data, cases)
    other, _ = verify(simulated(cases, 1), cases)
    assert summary(cases, counts) == summary(cases, other)
    labels = ('survivor identity', 'survivor key', 'compound payload', 'nested byte', 'nested address',
              'vector stride', 'view length', 'status', 'answer', 'event count', 'event kind',
              'event call ordinal', 'event destroyed before', 'event left identity', 'event right identity',
              'event result', 'callback counter', 'destruction counter')
    for label in labels:
        bad = bytearray(data); bad[marks[label]] ^= 1; reject(bytes(bad), cases, label)
    for label in ('previous original', 'deferred destruction', 'forward tail cleanup',
                  'reversed survivors', 'edit grows backing'):
        reject(simulated(cases, mutant=label), cases, label)
    reject(data[:-1], cases, 'truncation'); reject(data + b'\0', cases, 'extra bytes')
    print(summary(cases, counts), end='')
    print('cpu-controls=25 rejected=25 capacity-policies=2 bytes=%d' % len(data))


def main():
    cases = corpus(); assert len(cases) == 24
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(cases); return
    assert len(sys.argv) == 2
    result = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75, check=False)
    assert result.returncode == 0, ('native status', result.returncode, result.stderr[:2048])
    assert not result.stderr, ('native stderr', result.stderr[:2048])
    counts, _ = verify(result.stdout, cases); print(summary(cases, counts), end='')


if __name__ == '__main__': main()
