"""Dictionary reference for lazy map insertion, updates, and candidate recovery.

No hash-table or AVL structure is modeled. Each operation checks complete public
contents and exact initializer/updater events. Hash iteration is unordered.
"""
from collections import Counter
from dataclasses import dataclass, replace
import random
import struct
import subprocess
import sys

MAGIC = 5494753468931064141
END = 4994005193759370573
SEED = 0x6A90261106
MASK = (1 << 64) - 1
DOMAIN = 31
INIT_ERROR = 1229801703532086340


@dataclass(frozen=True)
class Case:
    family: int
    hashing: int
    actions: tuple


@dataclass(frozen=True)
class Step:
    op: int
    event: tuple | None
    result: object
    initialized: int
    updated: int
    query: object
    contents: tuple


def corpus():
    cases = []
    for scenario in range(8):
        rng = random.Random(SEED + scenario)
        commands = []

        def add(op, key, init=0, update=0):
            tick = len(commands)
            token = rng.getrandbits(64)
            if tick % 9 == 0:
                token = (0, MASK, 1 << 32, 1 << 63)[(tick // 9) % 4]
            stamp = 0xF123000000000000 | (scenario << 32) | tick
            commands.append((op, key, stamp, token, init, update))

        # Failure must not consume an empty slot; hits ignore even a failing
        # or mismatching initializer, and ordinary insertion replaces stamps.
        add(2, 0, 1)
        add(3, 0, 2)
        add(2, 0, 3)
        add(3, 0)
        add(2, 0, 1, 1)
        add(3, 0, 2, 2)
        add(0, 0)
        add(2, 0, 3, 3)
        order = list(range(1, DOMAIN))
        if scenario % 4 == 1:
            order.reverse()
        elif scenario % 4 == 2:
            rng.shuffle(order)
        elif scenario % 4 == 3:
            order = order[::2] + order[1::2]
        for key in order:
            add(2 + key % 2, key)
        # Filled collision groups, removals, and then reuse/growth.
        for key in order[::2]:
            add(1, key)
        for key in order[::2]:
            add(2 + key % 2, key, 2)
            add(3 - key % 2, key)
        for _ in range(96):
            op = rng.choices((0, 1, 2, 3, 4, 5), (10, 14, 32, 32, 2, 10))[0]
            add(op, rng.randrange(DOMAIN), rng.randrange(4), rng.randrange(4))
        add(4, 0)
        add(3, DOMAIN - 1, 1)
        add(2, DOMAIN - 1, 2)
        add(3, DOMAIN - 1)
        add(2, DOMAIN - 1, 1, 3)
        add(5, DOMAIN - 1)
        assert len(commands) <= 256
        for family, modes in ((0, range(3)), (1, (0,))):
            for hashing in modes:
                cases.append(Case(family, hashing, tuple(commands)))
    return cases


def hash_code(identity, mode):
    source = 65535 if mode == 0 else ((identity % 3) if mode == 1 else identity) * 2654435761
    return source & 0xFFFFFFFF


def initial(token):
    return token, 0, (0 if token % 3 == 0 else 2 if token & 1 else 1)


def transform(old, token, mode, tick):
    number, visits, mark = old
    new_mark = 0
    if mode == 0 and mark:
        new_mark = 3 - mark
    if mode >= 2:
        new_mark = 2 if (token ^ tick) & 1 else 1
    new = number ^ token ^ (tick << 32), visits + 1, new_mark
    report = (0, number ^ tick) if mode % 2 == 0 else (1, token ^ new[1])
    return new, report


def reference(case, counts=None):
    contents = {}
    initialized = updated = 0
    trace = []
    for op, identity, stamp, token, mode, update_mode in case.actions:
        key = identity, stamp, hash_code(identity, case.hashing)
        old = contents.get(identity)
        event = result = None
        if op == 0:
            result = old
            contents[identity] = key + initial(token)
        elif op == 1:
            result = contents.pop(identity, None)
        elif op in (2, 3):
            if old is not None:
                updated += 1
                value, report = transform(old[3:], token, update_mode, updated)
                event = (194, updated, update_mode, token, old[3:], value, report)
                contents[identity] = old[:3] + value
                result = (1, report)
                if counts is not None:
                    counts['updated'] += 1
                    counts['report_errors'] += report[0]
                    counts['ignored_bad_initializer'] += mode != 0
            else:
                initialized += 1
                event = (193, initialized, mode, key, token)
                if mode == 1:
                    result = (2, token ^ INIT_ERROR)
                    if counts is not None:
                        counts['initialize_errors'] += 1
                else:
                    candidate = key
                    if mode == 2:
                        candidate_id = (identity + 1) % DOMAIN
                        candidate = candidate_id, stamp, hash_code(candidate_id, case.hashing)
                    if mode == 3:
                        candidate = identity, stamp, key[2] ^ 0x80000000
                    entry = candidate + initial(token)
                    matches = candidate[0] == identity and (case.family == 1 or candidate[2] == key[2])
                    if matches:
                        contents[identity] = entry
                        result = (0,)
                        if counts is not None:
                            counts['inserted'] += 1
                    else:
                        result = (3, entry)
                        if counts is not None:
                            counts['mismatches'] += 1
            if counts is not None:
                counts['natural' if op == 2 else 'borrowed'] += 1
        elif op == 4:
            contents.clear()
        else:
            assert op == 5
        snapshot = tuple(contents[k] for k in sorted(contents))
        trace.append(Step(op, event, result, initialized, updated, contents.get(identity), snapshot))
        if counts is not None:
            counts['actions'] += 1
            counts['snapshot_entries'] += len(snapshot)
    return trace


def packet(cases):
    out = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for index, case in enumerate(cases):
        out += struct.pack('<4Q', index, case.family, case.hashing, len(case.actions))
        for action in case.actions:
            out += struct.pack('<6Q', *action)
    return out


def flatten(value):
    if isinstance(value, tuple):
        return [word for part in value for word in flatten(part)]
    return [value]


def entry(value):
    return (0,) if value is None else (1, *value)


def encode(cases, traces):
    words = [MAGIC, len(cases)]
    for index, (case, trace) in enumerate(zip(cases, traces)):
        words.append(index)
        for action, step in enumerate(trace):
            words.extend((218, action, step.op))
            if step.event is not None:
                words.extend(flatten(step.event))
            words.append(219)
            if step.op in (0, 1):
                words.extend(entry(step.result))
            elif step.op in (2, 3):
                words.extend(flatten(step.result))
            words.extend((step.initialized, step.updated, *entry(step.query), len(step.contents)))
            for item in step.contents:
                words.extend(entry(item))
            words.extend((0, 1))
    words.append(END)
    return struct.pack('<%dQ' % len(words), *words)


class Reader:
    def __init__(self, data):
        assert len(data) % 8 == 0, 'partial word'
        self.words = struct.unpack('<%dQ' % (len(data) // 8), data)
        self.at = 0

    def take(self, count=1):
        assert count <= len(self.words) - self.at, ('truncated', self.at, count)
        found = self.words[self.at:self.at + count]
        self.at += count
        return found[0] if count == 1 else found

    def entry(self):
        tag = self.take()
        assert tag in (0, 1), ('entry tag', tag)
        return self.take(6) if tag else None


def verify(cases, data):
    r = Reader(data)
    assert r.take(2) == (MAGIC, len(cases))
    for ordinal, case in enumerate(cases):
        assert r.take() == ordinal
        for index, wanted in enumerate(reference(case)):
            context = ordinal, index
            assert r.take(3) == (218, index, wanted.op), (*context, 'action')
            tag = r.take()
            actual_event = None
            if tag == 193:
                actual_event = (tag, r.take(), r.take(), r.take(3), r.take())
                tag = r.take()
            elif tag == 194:
                actual_event = (tag, r.take(), r.take(), r.take(), r.take(3), r.take(3), r.take(2))
                tag = r.take()
            assert actual_event == wanted.event and tag == 219, (*context, 'callback', actual_event, wanted.event)
            actual_result = None
            if wanted.op in (0, 1):
                actual_result = r.entry()
            elif wanted.op in (2, 3):
                result_tag = r.take()
                assert result_tag in (0, 1, 2, 3), (*context, 'unexpected storage/result tag', result_tag)
                if result_tag == 0:
                    actual_result = (0,)
                elif result_tag == 1:
                    actual_result = (1, r.take(2))
                elif result_tag == 2:
                    actual_result = (2, r.take())
                else:
                    actual_result = (3, r.take(6))
            assert actual_result == wanted.result, (*context, 'result', actual_result, wanted.result)
            assert r.take(2) == (wanted.initialized, wanted.updated), (*context, 'callback counts')
            assert r.entry() == wanted.query, (*context, 'query entry')
            assert r.take() == len(wanted.contents), (*context, 'length')
            actual = []
            while True:
                item = r.entry()
                if item is None:
                    break
                actual.append(item)
                assert len(actual) <= DOMAIN, (*context, 'unbounded cursor')
            assert r.take() == 1, (*context, 'fused cursor')
            assert len({item[0] for item in actual}) == len(actual), (*context, 'duplicate key')
            if case.family == 0:
                actual.sort(key=lambda item: item[0])
            assert tuple(actual) == wanted.contents, (*context, 'complete contents')
    assert r.take() == END and r.at == len(r.words), 'trailing output'


def summary(cases):
    counts = Counter()
    for case in cases:
        reference(case, counts)
    return ('lazy-map-model cases=%d actions=%d inserted=%d updated=%d initialize_errors=%d mismatches=%d report_errors=%d ignored_bad_initializer=%d natural=%d borrowed=%d snapshot_entries=%d seed=0x%x\n' %
            (len(cases), counts['actions'], counts['inserted'], counts['updated'], counts['initialize_errors'], counts['mismatches'], counts['report_errors'], counts['ignored_bad_initializer'], counts['natural'], counts['borrowed'], counts['snapshot_entries'], SEED))


def controls(cases):
    traces = [reference(case) for case in cases]
    pristine = encode(cases, traces)
    verify(cases, pristine)
    mutations = []

    def mutate(name, predicate, change):
        for ci, trace in enumerate(traces):
            for ai, step in enumerate(trace):
                if predicate(cases[ci], step):
                    changed = [list(items) for items in traces]
                    changed[ci][ai] = change(step)
                    mutations.append((name, encode(cases, changed)))
                    return
        raise AssertionError('unreached control: ' + name)

    mutate('missing initializer', lambda c, s: s.event is not None and s.event[0] == 193, lambda s: replace(s, event=None))
    mutate('extra initializer on hit', lambda c, s: s.event is not None and s.event[0] == 194, lambda s: replace(s, event=(193, 1, 0, (0, 0, 0), 0)))
    mutate('wrong callback input', lambda c, s: s.event is not None and s.event[0] == 194, lambda s: replace(s, event=(*s.event[:4], (s.event[4][0] ^ 1, *s.event[4][1:]), *s.event[5:])))
    mutate('wrong initializer error', lambda c, s: s.op in (2, 3) and s.result[0] == 2, lambda s: replace(s, result=(2, s.result[1] ^ 1)))
    mutate('lost recovered candidate', lambda c, s: s.op in (2, 3) and s.result[0] == 3, lambda s: replace(s, result=(3, (*s.result[1][:1], s.result[1][1] ^ 1, *s.result[1][2:]))))
    mutate('wrong inserted outcome', lambda c, s: s.op in (2, 3) and s.result == (0,), lambda s: replace(s, result=(1, (0, 0))))
    mutate('replaced stored representative', lambda c, s: s.event is not None and s.event[0] == 194, lambda s: replace(s, query=(s.query[0], s.query[1] ^ 1, *s.query[2:])))
    mutate('rolled back update error', lambda c, s: s.event is not None and s.event[0] == 194 and s.event[-1][0] == 1, lambda s: replace(s, query=s.query[:3] + s.event[4]))
    mutate('wrong callback count', lambda c, s: True, lambda s: replace(s, initialized=s.initialized + 1))
    mutate('lost unrelated entry', lambda c, s: len(s.contents) > 1, lambda s: replace(s, contents=s.contents[:-1]))
    mutate('duplicate hash iteration', lambda c, s: c.family == 0 and len(s.contents) > 1, lambda s: replace(s, contents=(s.contents[0], s.contents[0], *s.contents[2:])))
    mutate('unordered tree iteration', lambda c, s: c.family == 1 and len(s.contents) > 1, lambda s: replace(s, contents=tuple(reversed(s.contents))))
    mutations.extend((('truncated', pristine[:-1]), ('trailing', pristine + bytes(8)), ('wrong magic', bytes(8) + pristine[8:])))
    for name, corrupted in mutations:
        try:
            verify(cases, corrupted)
        except (AssertionError, ValueError, IndexError, struct.error):
            pass
        else:
            raise AssertionError('accepted deliberate corruption: ' + name)
    return len(mutations)


def main():
    cases = corpus()
    if sys.argv[1:] == ['controls']:
        count = controls(cases)
        print(summary(cases), end='')
        print('host-controls=%d rejected=%d' % (count, count))
        return
    assert len(sys.argv) == 2, 'oracle.py controls | EXECUTABLE'
    result = subprocess.run([sys.argv[1]], input=packet(cases), capture_output=True, timeout=75, check=False)
    assert result.returncode == 0, ('native status', result.returncode, result.stderr[:2048])
    assert not result.stderr, ('native stderr', result.stderr[:2048])
    verify(cases, result.stdout)
    print(summary(cases), end='')


if __name__ == '__main__':
    main()
