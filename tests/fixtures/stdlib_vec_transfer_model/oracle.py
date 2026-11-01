"""Independent ordered-list/owner model and strict raw-binary transcript reader.

Allocator addresses and unpromised capacity rounding are observed, not guessed.
Host-only synthetic transcripts use two legal capacity policies to check that
the verifier accepts either and rejects deliberate ownership/state corruption.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x7EC7A0261114
MAGIC = 0x7665637472616E73
END = 0x656E647472616E73
MAX = (1 << 31) - 1
MASK = (1 << 64) - 1
NAMES = ('push', 'reserve', 'take', 'append', 'split', 'extract', 'pop', 'clear', 'destroy', 'reverse', 'shrink')


@dataclass(frozen=True)
class Case:
    shape: int
    actions: tuple


def semantic(values, action, limit=MAX):
    """List operations define transfers; no loops over native storage slots."""
    op, src, dst, a, b = action
    before = [list(x) for x in values]; after = [list(x) for x in values]
    source = before[src]; count = len(source); code = answer = flags = 0; retired = []
    if op == 0:
        after[src].append(a); answer = count + 1
    elif op == 1:
        code = 2 if a < 0 else 3 if a > limit - count else 0
        answer = None if not code else 0; flags = 1 if code else 0
    elif op == 2:
        assert src != dst and not before[dst]
        after[dst], after[src] = source, []; answer = count
    elif op == 3:
        assert src != dst
        if count > limit - len(before[dst]): code = 3; flags = 3
        else:
            after[dst] = before[dst] + source; after[src] = []; answer = len(after[dst])
            if count == 0: flags = 3
    elif op in (4, 5):
        assert src != dst and not before[dst]
        end = count if op == 4 else b
        if not 0 <= a <= end <= count: code = 1; flags = 3
        else:
            after[dst] = source[a:end]; after[src] = source[:a] + source[end:]
            answer = end - a
            if not answer: flags = 1
    elif op in (6, 7, 8):
        n = min(count, 1) if op == 6 else count
        retired = list(reversed(source[count - n:])) if n else []
        after[src] = source[:count - n]; answer = n
    elif op == 9:
        after[src] = list(reversed(source)); answer = count
    elif op == 10:
        answer = None
    else: raise AssertionError(action)
    return after, code, answer, retired, flags


class Builder:
    def __init__(self, seed):
        self.actions = []; self.values = [[] for _ in range(4)]; self.reset = [True] * 4
        self.next_id = 1; self.rng = random.Random(seed)
    def add(self, op, src=0, dst=0, a=0, b=0):
        if op in (2, 4, 5): assert self.reset[dst]
        action = (op, src, dst, a, b)
        before = self.values
        self.values, code, _, _, _ = semantic(self.values, action)
        if not code:
            if op == 0 or (op == 1 and a > 0): self.reset[src] = False
            if op == 2: self.reset[dst], self.reset[src] = self.reset[src], True
            if op == 3 and before[src]: self.reset[dst] = False
            if op in (4, 5): self.reset[dst] = not self.values[dst]
            if op == 8: self.reset[src] = True
            if op == 10 and not self.values[src]: self.reset[src] = True
        self.actions.append(action)
        assert sum(map(len, self.values)) <= 48
    def push(self, src):
        self.add(0, src, a=self.next_id); self.next_id += 1
    def destroy(self, src): self.add(8, src)


def schedule(profile):
    b = Builder(SEED + profile)
    reserve = (0, 1, 2, 3, 4, 7, 8, 9, 15, 16, 17, 31)[profile]
    b.add(1, 0, a=reserve)
    for _ in range(3 + profile % 6): b.push(0)
    b.add(1, 1, a=(profile * 7) % 18)
    for _ in range(profile % 4): b.push(1)
    b.add(2, 0, 2); b.push(0); b.add(3, 2, 1)
    b.add(3, 2, 1)  # Allocated-empty donor is an exact no-op for both owners.
    b.add(2, 2, 3); b.destroy(3)  # Transfer and retire reserved-empty storage.
    b.add(4, 1, 2, len(b.values[1]) // 2)
    b.add(5, 1, 3, 0, min(1, len(b.values[1])))
    b.add(3, 3, 0); b.destroy(3)
    b.add(5, 2, 3, len(b.values[2]), len(b.values[2])); b.destroy(3)
    b.add(4, 2, 3, -1); b.add(5, 2, 3, 2, 1)
    b.add(3, 2, 1); b.destroy(2)
    b.add(5, 1, 2, 0, len(b.values[1])); b.push(1)
    b.add(3, 1, 0); b.add(3, 0, 2); b.add(2, 2, 3); b.push(2)
    b.destroy(1); b.add(4, 3, 1, len(b.values[3])); b.add(3, 1, 3)
    b.add(5, 3, 1, 0, len(b.values[3]) + 1)
    b.add(9, 3); b.add(3, 2, 3); b.destroy(2)
    b.add(1, 3, a=0); b.add(1, 3, a=-1); b.add(1, 3, a=MAX)
    while len(b.actions) < 64:
        live = [i for i, x in enumerate(b.values) if x]
        empty = [i for i, x in enumerate(b.values) if not x]
        src = b.rng.choice(live or list(range(4)))
        choice = b.rng.randrange(10)
        if choice < 2 or not live:
            b.push(b.rng.randrange(4)); continue
        if choice == 2:
            b.add(7 if profile % 3 == 0 else 6, src); continue
        if choice == 3:
            b.add(9, src); continue
        if choice == 4:
            b.add(10, src); continue
        if choice == 5 or not empty:
            dst = b.rng.choice([i for i in range(4) if i != src]); b.add(3, src, dst); continue
        dst = b.rng.choice([i for i in empty if i != src])
        if not b.reset[dst]:
            b.destroy(dst); continue
        if choice == 6: b.add(2, src, dst)
        elif choice == 7:
            at = b.rng.choice((0, len(b.values[src]), len(b.values[src]) // 2, len(b.values[src]) + 1))
            b.add(4, src, dst, at)
        else:
            n = len(b.values[src]); start = b.rng.randrange(n + 1); end = b.rng.randrange(start, n + 1)
            if choice == 9 and b.rng.randrange(2): end = MAX
            b.add(5, src, dst, start, end)
    assert b.next_id <= 200 and len(b.actions) == 64
    return tuple(b.actions)


def corpus():
    scripts = [schedule(i) for i in range(12)]
    return [Case(shape, scripts[i]) for shape in range(4) for i in range(12)] + [Case(4, scripts[i]) for i in range(8)]


def item_words(shape, identity):
    if shape == 0: return [identity]
    if shape == 1: return [identity * 1000003 - 100000000]
    if shape == 2:
        mark = 0 if identity % 3 == 0 else 2 if identity % 2 == 0 else 1
        branch = [0, (1 << 32) + identity] if identity % 2 == 0 else [1, -identity]
        return [identity, MASK - identity * 4294967297, mark, identity, -identity,
                identity * 1000003 - 100000000, *branch]
    if shape == 4: return [0]
    raise AssertionError(shape)


class Reader:
    def __init__(self, data): self.data = data; self.at = 0; self.marks = {}; self.context = None
    def word(self, label='word'):
        assert self.at + 8 <= len(self.data), ('truncated', self.context, self.at)
        self.marks.setdefault(label, self.at)
        value = struct.unpack_from('<Q', self.data, self.at)[0]; self.at += 8; return value
    def expect(self, value, label):
        actual = self.word(label); assert actual == value & MASK, (self.context, label, actual, value)
    def end(self): assert self.at == len(self.data), ('trailing', self.at, len(self.data))


def read_item(r, shape, identity, inner, label='item'):
    if shape != 3:
        for value in item_words(shape, identity): r.expect(value, label)
        return
    r.expect(identity, 'owned identity'); n = identity % 7 + 1; r.expect(n, 'owned length')
    cap, pointer = r.word('owned capacity'), r.word('owned pointer')
    assert n <= cap <= MAX and pointer > 0
    if identity in inner: assert inner[identity] == (cap, pointer), ('nested owner changed', identity)
    else: inner[identity] = cap, pointer
    for i in range(n): r.expect((identity * 17 + i * 31) & 255, 'owned bytes')


def snapshot(r, shape, size, values, inner, counts):
    metadata = []; r.snapshot_offsets = []
    stride = size if shape < 2 else -size
    for slot, items in enumerate(values):
        r.snapshot_offsets.append((r.at + 8, r.at + 16))
        r.expect(len(items), 'vector length')
        capacity, pointer = r.word('vector capacity'), r.word('vector pointer')
        r.expect(stride, 'vector stride'); r.expect(not items, 'empty flag')
        assert len(items) <= capacity <= (MAX // size if size else MAX)
        if not size: assert pointer == 0 and capacity in (0, MAX)
        else: assert (capacity == 0) == (pointer == 0)
        for identity in items: read_item(r, shape, identity, inner)
        metadata.append((capacity, pointer)); counts['snapshot_entries'] += len(items)
    intervals = [(p, p + c * size) for c, p in metadata if size and c]
    if shape == 3:
        for identity in (x for v in values for x in v):
            cap, pointer = inner[identity]; intervals.append((pointer, pointer + cap))
    ordered = sorted(intervals)
    assert all(a[1] <= b[0] for a, b in zip(ordered, ordered[1:])), ('overlapping live owners', r.context)
    return metadata


def preserved_view(r, shape, size, items, inner):
    r.expect(0, 'saved view start'); r.expect(len(items), 'saved view length')
    r.expect(size if shape < 2 else -size, 'saved view stride')
    for identity in items: read_item(r, shape, identity, inner, 'saved view item')


def check_capacity(before, after, old, new, action, code, size, answer, counts):
    op, src, dst, a, b = action
    if code:
        assert after == before, ('capacity changed on error', action)
        return
    touched = {src, dst} if op in (2, 3, 4, 5) else {src}
    for slot in set(range(4)) - touched: assert after[slot] == before[slot]
    cap, pointer = before[src]; n = len(new[src])
    if op == 2:
        assert after[src] == (0, 0) and after[dst] == before[src]
    elif op == 3:
        assert after[src] == before[src]
        needed = len(new[dst]); c, p = before[dst]; nc, np = after[dst]
        if not old[src] or needed <= c: assert (nc, np) == (c, p); counts['spare_append'] += bool(old[src])
        else:
            assert nc >= needed and nc >= c
            if size: assert np != p
            counts['grown_append'] += 1
    elif op in (4, 5):
        assert after[src] == before[src]
        assert before[dst] == (0, 0), ('result destination not reset', action)
        if not new[dst]: assert after[dst] == (0, 0)
        else: assert after[dst][0] >= len(new[dst])
    elif op in (6, 7, 9): assert after[src] == before[src]
    elif op == 8: assert after[src] == (0, 0)
    elif op in (0, 1):
        needed = n if op == 0 else len(old[src]) + a
        nc, np = after[src]
        if needed <= cap: assert (nc, np) == (cap, pointer)
        else:
            assert nc >= needed and nc >= cap
            if size: assert np != pointer
        if op == 1: assert answer == nc
    elif op == 10:
        if not size: assert after[src] == before[src]
        else:
            assert after[src][0] == n
            if n == cap: assert after[src] == before[src]
        assert answer == after[src][0]


def verify(data, cases):
    r = Reader(data); counts = Counter(); r.expect(MAGIC, 'magic'); r.expect(len(cases), 'case count')
    for number, case in enumerate(cases):
        r.context = (number, 'initial'); r.expect(number, 'case ordinal'); r.expect(case.shape, 'shape'); r.expect(len(case.actions), 'action count')
        size = r.word('element size')
        if case.shape in (0, 1, 4): assert size == (1, 4, 0)[(0, 1, 4).index(case.shape)]
        else: assert size >= 8 and size % 8 == 0
        values = [[] for _ in range(4)]; inner = {}; created = []; retired = []
        metadata = snapshot(r, case.shape, size, values, inner, counts); assert metadata == [(0, 0)] * 4
        for step, action in enumerate(case.actions):
            r.context = (number, step, NAMES[action[0]], action)
            op, src, dst, a, b = action; old = [list(x) for x in values]
            values, code, answer, removed, flags = semantic(values, action, MAX // size if size else MAX)
            if op == 0: assert a not in created; created.append(a); counts['created'] += 1; counts['nested_owners'] += case.shape == 3
            r.expect(step, 'step ordinal'); r.expect(op, 'operation'); r.expect(code, 'status')
            actual_answer = r.word('answer')
            if answer is not None: assert actual_answer == answer
            r.expect(len(removed), 'retired count')
            for identity in removed: read_item(r, case.shape, identity, inner, 'retired item')
            retired += removed; r.expect(flags, 'view flags')
            if flags & 1: preserved_view(r, case.shape, size, old[src], inner)
            if flags & 2: preserved_view(r, case.shape, size, old[dst], inner)
            following = snapshot(r, case.shape, size, values, inner, counts)
            if case.shape != 4:
                if op == 2 and old[src]: r.marks.setdefault('transferred capacity', r.snapshot_offsets[dst][0])
                if op == 3 and old[src]: r.marks.setdefault('retained donor capacity', r.snapshot_offsets[src][0])
                if code: r.marks.setdefault('error preserved capacity', r.snapshot_offsets[src][0])
                if op in (4, 5) and not code and values[dst]:
                    if 'extracted pointer' not in r.marks:
                        r.marks['extracted pointer'] = r.snapshot_offsets[dst][1]
                        r.marks['extraction source pointer'] = r.snapshot_offsets[src][1]
            check_capacity(metadata, following, old, values, action, code, size, actual_answer, counts)
            metadata = following
            assert Counter(x for v in values for x in v) + Counter(retired) == Counter(created)
            assert len(set(created)) == len(created)
            counts['actions'] += 1; counts[NAMES[op]] += 1; counts['errors'] += bool(code)
            counts['bounds_errors'] += code == 1; counts['capacity_errors'] += code in (2, 3)
            if op in (2, 3, 4, 5) and not code:
                moved = len(old[src]) if op in (2, 3) else answer
                counts['moved_items'] += moved
                counts['nonempty_transfers'] += moved > 0
                counts['empty_transfers'] += moved == 0
            counts['saved_views'] += bool(flags & 1) + bool(flags & 2)
        for slot in range(4):
            r.context = (number, 'final cleanup', slot)
            removed = list(reversed(values[slot])); r.expect(len(removed), 'final retired count')
            for identity in removed: read_item(r, case.shape, identity, inner, 'final retired item')
            retired += removed; values[slot] = []
        assert Counter(retired) == Counter(created) and len(retired) == len(set(retired))
        r.context = (number, 'final reset'); final = snapshot(r, case.shape, size, values, inner, counts)
        assert final == [(0, 0)] * 4
    r.expect(END, 'end marker'); r.end()
    assert counts['grown_append'] > 0 and counts['spare_append'] > 0
    assert counts['nonempty_transfers'] > 500 and counts['empty_transfers'] > 100
    assert counts['bounds_errors'] > 100 and counts['nested_owners'] > 100
    return counts, r.marks


class Writer:
    def __init__(self): self.data = bytearray()
    def word(self, value): self.data += struct.pack('<Q', value & MASK)
    def item(self, shape, identity, inner):
        if shape != 3:
            for word in item_words(shape, identity): self.word(word)
        else:
            n = identity % 7 + 1; c, p = inner[identity]
            for word in (identity, n, c, p): self.word(word)
            for i in range(n): self.word((identity * 17 + i * 31) & 255)
    def view(self, shape, size, items, inner):
        for word in (0, len(items), size if shape < 2 else -size): self.word(word)
        for identity in items: self.item(shape, identity, inner)
    def snapshot(self, shape, size, values, metadata, inner):
        for items, (capacity, pointer) in zip(values, metadata):
            for word in (len(items), capacity, pointer, size if shape < 2 else -size, not items): self.word(word)
            for identity in items: self.item(shape, identity, inner)


def simulated(cases, policy, mutant=None):
    """Host verifier controls only. This never supplies native expectations."""
    w = Writer(); w.word(MAGIC); w.word(len(cases)); address = 0x100000; mutated = False
    def allocate(capacity, size):
        nonlocal address
        if not size or not capacity: return 0
        answer = address; address += ((capacity * size + 4095) // 4096 + 1) * 4096; return answer
    def capacity(needed, size):
        if not needed: return 0
        if not size: return MAX
        return needed if policy == 0 else 1 << needed.bit_length()
    for number, case in enumerate(cases):
        size = (1, 4, 72, 32, 0)[case.shape]
        for word in (number, case.shape, len(case.actions), size): w.word(word)
        values = [[] for _ in range(4)]; metadata = [(0, 0)] * 4; inner = {}
        w.snapshot(case.shape, size, values, metadata, inner)
        for step, action in enumerate(case.actions):
            op, src, dst, a, b = action; old = [list(x) for x in values]; before = list(metadata)
            values, code, answer, removed, flags = semantic(values, action, MAX // size if size else MAX)
            if op == 0 and case.shape == 3:
                n = a % 7 + 1; inner[a] = n, allocate(n, 1)
            if not code:
                cap, pointer = before[src]
                if op == 2: metadata[dst], metadata[src] = before[src], (0, 0)
                elif op == 3:
                    if len(values[dst]) > before[dst][0]:
                        nc = capacity(len(values[dst]), size); metadata[dst] = nc, allocate(nc, size)
                elif op in (4, 5):
                    nc = capacity(len(values[dst]), size); metadata[dst] = nc, allocate(nc, size)
                elif op == 8: metadata[src] = (0, 0)
                elif op in (0, 1):
                    needed = len(values[src]) if op == 0 else len(old[src]) + a
                    if needed > cap:
                        nc = capacity(needed, size); metadata[src] = nc, allocate(nc, size)
                elif op == 10 and size:
                    nc = len(values[src])
                    if nc != cap: metadata[src] = nc, allocate(nc, size)
                if answer is None: answer = metadata[src][0]
            if not mutated:
                target = None
                if mutant == 'take order' and op == 2 and len(values[dst]) > 1: target = dst
                if mutant == 'append order' and op == 3 and len(old[src]) > 1:
                    values[dst] = old[dst] + list(reversed(old[src])); mutated = True
                if mutant == 'extracted order' and op in (4, 5) and not code and len(values[dst]) > 1: target = dst
                if mutant == 'retained suffix order' and op == 5 and not code and len(values[src]) > 1: target = src
                if target is not None: values[target].reverse(); mutated = True
            for word in (step, op, code, answer, len(removed)): w.word(word)
            for identity in removed: w.item(case.shape, identity, inner)
            w.word(flags)
            if flags & 1: w.view(case.shape, size, old[src], inner)
            if flags & 2: w.view(case.shape, size, old[dst], inner)
            w.snapshot(case.shape, size, values, metadata, inner)
        for items in values:
            w.word(len(items))
            for identity in reversed(items): w.item(case.shape, identity, inner)
        w.snapshot(case.shape, size, [[] for _ in range(4)], [(0, 0)] * 4, inner)
    w.word(END)
    if mutant is not None: assert mutated, ('unreached mutant', mutant)
    return bytes(w.data)


def packet(cases):
    data = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for c in cases:
        data += struct.pack('<2Q', c.shape, len(c.actions))
        for action in c.actions: data += struct.pack('<5Q', *(x & MASK for x in action))
    return bytes(data)


def summary(cases, counts):
    keys = ('actions', 'created', 'nested_owners', 'moved_items', 'nonempty_transfers', 'empty_transfers',
            'bounds_errors', 'capacity_errors', 'saved_views', 'snapshot_entries')
    return 'vec-transfer-model cases=%d ' % len(cases) + ' '.join('%s=%d' % (key, counts[key]) for key in keys) + ' shapes=5 seed=0x%x\n' % SEED


def reject(data, cases, label):
    try: verify(data, cases)
    except (AssertionError, struct.error, IndexError, KeyError): return
    raise AssertionError('accepted corruption: ' + label)


def controls(cases):
    first = simulated(cases, 0); counts, marks = verify(first, cases)
    second_counts, _ = verify(simulated(cases, 1), cases)
    assert summary(cases, counts) == summary(cases, second_counts)
    selected = ('vector length', 'vector capacity', 'vector pointer', 'vector stride', 'empty flag', 'item',
                'owned identity', 'owned capacity', 'owned pointer', 'owned bytes', 'status', 'answer',
                'retired count', 'saved view length', 'saved view item', 'view flags', 'end marker')
    for label in selected:
        bad = bytearray(first); bad[marks[label]] ^= 1; reject(bytes(bad), cases, label)
    for label in ('transferred capacity', 'retained donor capacity', 'error preserved capacity'):
        bad = bytearray(first); at = marks[label]; old = struct.unpack_from('<Q', bad, at)[0]
        struct.pack_into('<Q', bad, at, old + 8); reject(bytes(bad), cases, label)
    bad = bytearray(first)
    pointer = struct.unpack_from('<Q', first, marks['extraction source pointer'])[0]
    struct.pack_into('<Q', bad, marks['extracted pointer'], pointer)
    reject(bytes(bad), cases, 'shared extracted backing')
    reject(first[:-1], cases, 'truncation'); reject(first + b'\0', cases, 'trailing bytes')
    for name in ('take order', 'append order', 'extracted order', 'retained suffix order'):
        reject(simulated(cases, 0, name), cases, name)
    print(summary(cases, counts), end='')
    print('cpu-controls=27 rejected=27 capacity-policies=2 bytes=%d' % len(first))


def main():
    cases = corpus(); assert len(cases) == 56
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(cases); return
    assert len(sys.argv) == 2
    run = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases), stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, timeout=75, check=False)
    assert run.returncode == 0, ('native status', run.returncode, run.stderr[:2048])
    assert not run.stderr, ('native stderr', run.stderr[:2048])
    counts, _ = verify(run.stdout, cases)
    print(summary(cases, counts), end='')


if __name__ == '__main__': main()
