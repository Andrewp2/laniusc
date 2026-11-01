"""Finite dictionary reference for scoped map updates; no bucket/tree model."""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass, replace
from pathlib import Path
import copy
import random
import struct
import subprocess
import sys

SEED = 0x6A90261111
MASK = (1 << 64) - 1
MAGIC = 0x6D61707570646174
END = 0x656E646D61707570
DOMAIN = 31

@dataclass(frozen=True)
class Case:
    family: int
    shape: int
    hashing: int
    actions: tuple

def corpus():
    rng = random.Random(SEED)
    schedules = []
    # Ordered, reverse and alternating insertions force distinct AVL histories;
    # the same histories exercise full-hash collisions and tombstone reuse.
    orders = [list(range(31)), list(reversed(range(31))),
              [15, 7, 23, 3, 11, 19, 27, 1, 5, 9, 13, 17, 21, 25, 29,
               0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30]]
    for order in orders:
        ops = [(2, 15), (1, 15), (4, 15)]
        ops += [(0, k) for k in order]
        ops += [(2, k) for k in order]
        ops += [(1, k) for k in (15, 7, 23, 0, 30, 3, 11, 19, 27)]
        ops += [(2, k) for k in range(31)]
        ops += [(0, k) for k in (15, 7, 23, 0, 30, 3, 11, 19, 27)]
        ops += [(2, k) for k in reversed(range(31))]
        ops += [(3, 0), (2, 0), (0, 0), (2, 0), (1, 0), (2, 0), (3, 0)]
        schedules.append(ops)
    # Empty, one-entry, replacement, return-Err and Some(None) witnesses.
    schedules.append([(2, 4), (0, 4)] + [(2, 4)] * 8 + [(0, 4), (2, 4),
                     (1, 4), (2, 4), (0, 4), (2, 4), (3, 4), (2, 4), (3, 4)])
    for size in (1, 2, 5, 17, 31):
        ops = [(0, k) for k in range(size)]
        for i in range(80):
            op = rng.choices((0, 1, 2, 3, 4), (20, 16, 54, 3, 7))[0]
            key = rng.randrange(min(31, size + 3))
            ops.append((op, key))
        ops += [(2, k) for k in range(size)]
        schedules.append(ops)
    result = []
    for ordinal, ops in enumerate(schedules):
        actions = []
        for tick, (op, key) in enumerate(ops):
            # Each query has a new representative; updates must retain the
            # original insertion stamp, while replacement insertion changes it.
            stamp = (0xF123456700000000 | (ordinal << 24) | tick)
            token = rng.getrandbits(64)
            if tick % 11 == 0:
                token = (0, MASK, 1 << 32, 1 << 63)[(tick // 11) % 4]
            actions.append((op, key, stamp, token, tick % 4))
        assert len(actions) <= 192
        for family in (0, 1):
            for shape in (0, 1):
                # Hash modes are distinct probing histories; repeating them on
                # TreeMap would add no semantic state space.
                for hashing in ((0, 1, 2) if family == 0 else (0,)):
                    result.append(Case(family, shape, hashing, tuple(actions)))
    return result

def value(shape, token):
    if shape == 0:
        return token
    n = token % 2000001 - 1000000
    mark = None if token % 3 == 0 else bool(token & 1)
    return (token ^ 0x91A2B3C4D5E6F708, mark, (n, -n, n // 2 if n >= 0 else -((-n) // 2)))

def transformation(shape, old, token, mode, tick):
    if shape == 0:
        new = old ^ token ^ (tick << 32)
        answer = None if mode % 3 == 0 else old ^ token ^ (tick << 17)
        return new, answer
    number, mark, words = old
    if mode == 0:
        new_mark = None if mark is None else not mark
    elif mode == 1:
        new_mark = None
    else:
        new_mark = bool((token ^ tick) & 1)
    new = (number ^ token ^ (tick << 32), new_mark,
           (words[1], words[2], token % 2000001 - 1000000))
    # Err is an ordinary result value; the new V remains installed.
    answer = (0, old, tick) if mode % 2 == 0 else (1, new, token)
    return new, answer

def reference(case, counts=None):
    contents = {}
    calls = 0
    trace = []
    for op, key, stamp, token, mode in case.actions:
        event = None
        previous = contents.get(key)
        if op == 0:
            result = previous
            contents[key] = (key, stamp, case.hashing, value(case.shape, token))
        elif op == 1:
            result = contents.pop(key, None)
        elif op == 2:
            if previous is None:
                result = None
                if counts is not None: counts['missing'] += 1
            else:
                calls += 1
                new, answer = transformation(case.shape, previous[3], token, mode, calls)
                event = (calls, mode, token, previous[3], new, answer)
                contents[key] = (*previous[:3], new)
                result = (answer,)
                if counts is not None:
                    counts['callbacks'] += 1
                    counts['result_errors' if case.shape and mode % 2 else 'other_results'] += 1
                    if case.shape == 0 and answer is None: counts['some_none'] += 1
        else:
            assert op in (3, 4)
            result = None
            if op == 3: contents.clear()
        # Semantic contents are a dictionary, independent of either storage
        # structure. Returned entries retain their complete representative.
        snapshot = tuple(contents[k] for k in sorted(contents))
        trace.append((op, event, result, calls, contents.get(key), snapshot))
        if counts is not None:
            counts['actions'] += 1
            counts['snapshot_entries'] += len(contents)
            counts['inserts' if op == 0 else 'removes' if op == 1 else 'updates' if op == 2 else 'clears' if op == 3 else 'observes'] += 1
    return tuple(trace)

def packet(cases):
    out = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for ordinal, case in enumerate(cases):
        out += struct.pack('<5Q', ordinal, case.family, case.shape, case.hashing, len(case.actions))
        for action in case.actions: out += struct.pack('<5Q', *action)
    return out

class Writer:
    def __init__(self): self.data = bytearray()
    def byte(self, x): self.data.append(x)
    def word(self, x): self.data += struct.pack('<Q', x & MASK)
    def val(self, shape, x):
        if shape == 0: self.word(x); return
        number, mark, words = x
        self.word(number); self.byte(0 if mark is None else 2 if mark else 1)
        for word in words: self.word(word)
    def answer(self, shape, x):
        if shape == 0:
            self.byte(x is not None)
            if x is not None: self.word(x)
        else:
            tag, payload, extra = x
            self.byte(tag); self.val(1, payload); self.word(extra)
    def entry(self, shape, x):
        self.byte(x is not None)
        if x is not None:
            for word in x[:3]: self.word(word)
            self.val(shape, x[3])

def encode(cases, traces):
    w = Writer(); w.word(MAGIC); w.word(len(cases))
    for ordinal, (case, trace) in enumerate(zip(cases, traces)):
        w.word(ordinal)
        for op, event, result, calls, query, snapshot in trace:
            w.byte(0xDA); w.byte(op)
            if event is not None:
                tick, mode, token, old, new, answer = event
                w.byte(0xCA); w.word(tick); w.word(mode); w.word(token)
                w.val(case.shape, old); w.val(case.shape, new); w.answer(case.shape, answer)
            w.byte(0xDB)
            if op in (0, 1): w.entry(case.shape, result)
            elif op == 2:
                w.byte(result is not None)
                if result is not None: w.answer(case.shape, result[0])
            w.word(calls); w.entry(case.shape, query)
            w.word(len(snapshot)); w.byte(not snapshot)
            for entry in snapshot: w.entry(case.shape, entry)
            w.entry(case.shape, None); w.byte(1)
    w.word(END)
    return bytes(w.data)

class Reader:
    def __init__(self, data): self.data = data; self.at = 0
    def take(self, n):
        assert 0 <= n <= len(self.data) - self.at, ('truncated', self.at, n)
        got = self.data[self.at:self.at+n]; self.at += n; return got
    def byte(self): return self.take(1)[0]
    def tag(self):
        value = self.byte(); assert value in (0, 1), ('tag', value); return value
    def word(self): return struct.unpack('<Q', self.take(8))[0]
    def val(self, shape):
        if shape == 0: return self.word()
        number = self.word(); mark = self.byte(); assert mark <= 2
        words = tuple(self.word() for _ in range(3))
        words = tuple(x if x < (1 << 63) else x - (1 << 64) for x in words)
        assert all(-(1 << 31) <= x < (1 << 31) for x in words)
        return number, (None if mark == 0 else mark == 2), words
    def answer(self, shape):
        if shape == 0: return self.word() if self.tag() else None
        tag = self.tag(); return tag, self.val(1), self.word()
    def entry(self, shape):
        if not self.tag(): return None
        return self.word(), self.word(), self.word(), self.val(shape)

def verify(cases, data):
    r = Reader(data)
    assert r.word() == MAGIC and r.word() == len(cases)
    for ordinal, case in enumerate(cases):
        assert r.word() == ordinal
        expected = reference(case)
        for index, wanted in enumerate(expected):
            op, event, result, calls, query, snapshot = wanted
            assert r.byte() == 0xDA and r.byte() == op, (ordinal, index, 'operation')
            tag = r.byte(); actual_event = None
            if tag == 0xCA:
                actual_event = (r.word(), r.word(), r.word(), r.val(case.shape), r.val(case.shape), r.answer(case.shape))
                tag = r.byte()
            assert tag == 0xDB and actual_event == event, (ordinal, index, 'callback', actual_event, event)
            actual_result = None
            if op in (0, 1): actual_result = r.entry(case.shape)
            elif op == 2 and r.tag(): actual_result = (r.answer(case.shape),)
            assert actual_result == result, (ordinal, index, 'result')
            assert r.word() == calls, (ordinal, index, 'count')
            assert r.entry(case.shape) == query, (ordinal, index, 'immediate query')
            assert r.word() == len(snapshot) and r.tag() == (not snapshot), (ordinal, index, 'length')
            actual = []
            while True:
                entry = r.entry(case.shape)
                if entry is None: break
                actual.append(entry); assert len(actual) <= DOMAIN
            assert r.tag() == 1, (ordinal, index, 'fused cursor')
            if case.family == 0:
                assert len({entry[0] for entry in actual}) == len(actual), (ordinal, index, 'duplicate key')
                actual.sort(key=lambda entry: entry[0])
            assert tuple(actual) == snapshot, (ordinal, index, 'complete contents')
    assert r.word() == END and r.at == len(data), ('trailing output', r.at, len(data))

def summary(cases):
    counts = Counter()
    for case in cases: reference(case, counts)
    return ('map-updates cases=%d actions=%d callbacks=%d missing=%d result_errors=%d some_none=%d snapshot_entries=%d families=2 shapes=2 hash_modes=3 seed=0x%x\n' %
            (len(cases), counts['actions'], counts['callbacks'], counts['missing'], counts['result_errors'], counts['some_none'], counts['snapshot_entries'], SEED))

def controls(cases):
    traces = [reference(case) for case in cases]
    pristine = encode(cases, traces); verify(cases, pristine)
    controls = []
    def changed(name, predicate, mutate):
        candidate = copy.deepcopy(traces)
        for ci, trace in enumerate(candidate):
            for ai, item in enumerate(trace):
                if predicate(cases[ci], item):
                    items = list(trace); items[ai] = mutate(item, cases[ci]); candidate[ci] = tuple(items)
                    controls.append((name, encode(cases, candidate))); return
        raise AssertionError('unreached control: ' + name)
    def replace_field(item, index, value):
        parts = list(item); parts[index] = value; return tuple(parts)
    changed('omitted callback', lambda c, t: t[1] is not None, lambda t,c: replace_field(t, 1, None))
    changed('extra missing callback', lambda c,t: t[0] == 2 and t[1] is None,
            lambda t,c: replace_field(t, 1, (1,0,0,value(c.shape,0),value(c.shape,0),None if c.shape == 0 else (0,value(1,0),1))))
    changed('callback ordinal', lambda c,t: t[1] is not None,
            lambda t,c: replace_field(t, 1, (t[1][0]+1, *t[1][1:])))
    changed('callback input', lambda c,t: t[1] is not None and c.shape == 0,
            lambda t,c: replace_field(t, 1, (*t[1][:3], t[1][3]^1, *t[1][4:])))
    changed('callback new value', lambda c,t: t[1] is not None and c.shape == 1,
            lambda t,c: replace_field(t, 1, (*t[1][:4], value(1,17), t[1][5])))
    changed('wrong nested optional', lambda c,t: c.shape == 0 and t[2] == (None,),
            lambda t,c: replace_field(t, 2, (0,)))
    changed('Err rollback', lambda c,t: c.shape == 1 and t[1] is not None and t[1][5][0] == 1,
            lambda t,c: replace_field(t, 4, (*t[4][:3], t[1][3])))
    changed('query representative replaced', lambda c,t: t[0] == 2 and t[4] is not None,
            lambda t,c: replace_field(t, 4, (t[4][0],t[4][1]^1,*t[4][2:])))
    changed('returned old representative', lambda c,t: t[0] in (0,1) and t[2] is not None,
            lambda t,c: replace_field(t, 2, (t[2][0],t[2][1]^1,*t[2][2:])))
    changed('callback count', lambda c,t: True, lambda t,c: replace_field(t, 3, t[3]+1))
    changed('lost unrelated entry', lambda c,t: len(t[5]) >= 2,
            lambda t,c: replace_field(t, 5, t[5][:-1]))
    changed('duplicate iterator entry', lambda c,t: c.family == 0 and len(t[5]) >= 2,
            lambda t,c: replace_field(t, 5, (t[5][0],t[5][0],*t[5][2:])))
    changed('tree iterator order', lambda c,t: c.family == 1 and len(t[5]) >= 2,
            lambda t,c: replace_field(t, 5, tuple(reversed(t[5]))))
    changed('wrong array lane', lambda c,t: c.shape == 1 and t[4] is not None,
            lambda t,c: replace_field(t, 4, (*t[4][:3], (t[4][3][0],t[4][3][1],(*t[4][3][2][:2],t[4][3][2][2]+1)))))
    controls += [('truncated', pristine[:-1]), ('trailing byte', pristine+b'\0'), ('wrong magic', b'\0'+pristine[1:])]
    for name, candidate in controls:
        try: verify(cases, candidate)
        except (AssertionError, ValueError, IndexError, struct.error): pass
        else: raise AssertionError('accepted deliberate corruption: ' + name)
    print(summary(cases), end='')
    print('cpu-controls=%d rejected=%d bytes=%d' % (len(controls), len(controls), len(pristine)))

def main():
    cases = corpus()
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(cases); return
    assert len(sys.argv) == 2, 'oracle.py controls | EXECUTABLE'
    executable = Path(sys.argv[1]).resolve()
    result = subprocess.run([str(executable)], input=packet(cases), stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=75, check=False)
    assert result.returncode == 0, ('native status', result.returncode, result.stderr[:2048])
    assert not result.stderr, ('native stderr', result.stderr[:2048])
    verify(cases, result.stdout)
    print(summary(cases), end='')

if __name__ == '__main__': main()
