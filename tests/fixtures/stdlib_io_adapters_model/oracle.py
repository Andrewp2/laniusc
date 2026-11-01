"""Finite stream-event model for borrowed reader composition.

The reference interprets a tree of quota and selection states over scripted
byte providers. Event histories and conservation/monotonicity checks supplement
the exact state/output comparison. No production library implementation is used.
"""
from __future__ import annotations
from dataclasses import dataclass
from collections import Counter
from pathlib import Path
import random
import struct
import subprocess
import sys

MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
SEED = 0x10ADA0261106

@dataclass(frozen=True)
class Action:
    op: int
    offset: int = 3
    count: int = 4
    quota: int = 0
    first: int = 16
    second: int = 16

@dataclass(frozen=True)
class Case:
    kind: int
    layout: int
    first_length: int
    second_length: int
    quotas: tuple
    actions: tuple

@dataclass(frozen=True)
class Reply:
    error: int = 0
    host: int = 0
    number: int = 0
    start: int = 0
    length: int = 0
    stride: int = 0
    data: tuple = ()


def error(code, host=0): return Reply(error=code, host=host)
def integer(value): return Reply(number=value)
def valid(start, count): return start >= 0 and count >= 0 and start + count <= MAX_I32

def source_data(identity, length):
    base = 128 if identity == 0 else 160
    values = [base + index for index in range(32)]
    values[2:2 + length] = [((index * (37 if identity == 0 else 53)) + (13 if identity == 0 else 201)) & 255 for index in range(length)]
    return values


class Model:
    def __init__(self, case):
        self.case = case
        self.strides = [1 if case.layout & (1 << bit) else -8 for bit in range(3)]
        self.destination = list(range(192, 224))
        self.providers = [dict(data=source_data(identity, length), length=length, cursor=0, fetched=0,
                               calls=[0, 0, 0]) for identity, length in enumerate((case.first_length, case.second_length))]
        # First two entries are leaves. The remaining nodes encode a graph of
        # adapter state, including unused adapters whose construction is inert.
        self.nodes = [dict(type='provider', identity=0), dict(type='provider', identity=1),
                      dict(type='quota', children=(0,), limit=case.quotas[0], fault=False),
                      dict(type='quota', children=(1,), limit=case.quotas[1], fault=False),
                      dict(type='select', children=(0, 1), done=False, fault=False),
                      dict(type='quota', children=(4,), limit=case.quotas[2], fault=False),
                      dict(type='select', children=(2, 3), done=False, fault=False)]
        self.root = (2, 4, 5, 6)[case.kind]
        self.events = []
        self.accepted = []

    def provider(self, identity, action):
        source = self.providers[identity]
        event = (action.first, action.second)[identity]
        offset, count = (action.offset, action.count) if action.op == 0 else (0, action.count if action.op == 2 else 0)
        self.events.append((identity, action.op, event, offset, count, source['cursor'], source['fetched']))
        source['calls'][action.op] += 1
        if -12 <= event <= -1:
            code = -event
            if code <= 9: return error(code)
            return error(10, (-123 - identity, MIN_I32, MAX_I32)[code - 10])
        if action.op == 1:
            start, length = 2 + source['cursor'], source['fetched'] - source['cursor']
            if event <= -101:
                start, length = { -101: (-1, 1), -102: (2, -1), -103: (MAX_I32, 1),
                                  -104: (-1, 0), -105: (MAX_I32, 0)}[event]
            else:
                assert event >= 0
                if source['cursor'] == source['fetched']:
                    source['fetched'] += min(event, source['length'] - source['fetched'])
                length = source['fetched'] - source['cursor']
            data = tuple(source['data'][start:start + length]) if valid(start, length) and length else ()
            return Reply(start=start, length=length, stride=self.strides[identity], data=data)
        if event <= -101:
            choices = (-1, count + 1, MIN_I32, MAX_I32) if action.op == 0 else (-1, count + 1, count - 1, MIN_I32)
            return integer(choices[-event - 101])
        if action.op == 2:
            if not 0 <= count <= source['fetched'] - source['cursor']: return error(1)
            source['cursor'] += count
            return integer(count)
        assert action.op == 0 and event >= 0 and valid(offset, count) and offset + count <= 32
        amount = min(event, count, source['length'] - source['cursor'])
        self.destination[offset:offset + amount] = source['data'][2 + source['cursor']:2 + source['cursor'] + amount]
        source['cursor'] += amount
        source['fetched'] = max(source['fetched'], source['cursor'])
        return integer(amount)

    def invoke(self, ordinal, action):
        node = self.nodes[ordinal]
        if node['type'] == 'provider': return self.provider(node['identity'], action)
        if node['fault']: return error(4)
        # Request admission is independent of the provider event schedule.
        if action.op == 0 and not valid(action.offset, action.count): return error(1)
        if action.op == 2 and action.count < 0: return error(1)
        if action.op in (0, 2) and action.count == 0: return integer(0)
        if node['type'] == 'quota':
            if action.op == 2 and action.count > node['limit']: return error(1)
            if action.op in (0, 1) and node['limit'] == 0:
                return Reply(stride=1) if action.op == 1 else integer(0)
            admitted = min(action.count, node['limit']) if action.op == 0 else action.count
            child = node['children'][0]
        else:
            admitted = action.count
            child = node['children'][int(node['done'])]
        request = Action(action.op, action.offset, admitted, action.quota, action.first, action.second)
        reply = self.invoke(child, request)
        if reply.error: return reply
        conforms = valid(reply.start, reply.length) if action.op == 1 else (
            0 <= reply.number <= admitted if action.op == 0 else reply.number == admitted)
        if not conforms:
            node['fault'] = True
            return error(4)
        empty = reply.length == 0 if action.op == 1 else reply.number == 0
        if node['type'] == 'select' and not node['done'] and action.op != 2 and empty:
            node['done'] = True
            # Selection is committed before the second response, including Err.
            return self.invoke(ordinal, action)
        if node['type'] == 'quota':
            if action.op == 1:
                length = min(reply.length, node['limit'])
                return Reply(start=reply.start, length=length, stride=reply.stride, data=reply.data[:length])
            node['limit'] -= reply.number
            self.accepted.append((ordinal, reply.number))
        return reply

    def states(self):
        nodes = self.nodes
        return [nodes[2]['limit'], int(nodes[2]['fault']), nodes[3]['limit'], int(nodes[3]['fault']),
                int(nodes[4]['done']), int(nodes[4]['fault']), nodes[5]['limit'], int(nodes[5]['fault']),
                int(nodes[6]['done']), int(nodes[6]['fault'])]

    def step(self, action):
        before = [dict(node) for node in self.nodes]
        events_before = len(self.events)
        self.accepted = []
        if action.op == 3:
            ordinal = (2, 3, 5)[action.offset]
            if self.nodes[ordinal]['fault']: reply = error(4)
            else:
                self.nodes[ordinal]['limit'] = action.quota
                reply = integer(action.quota)
        else: reply = self.invoke(self.root, action)
        events = self.events[events_before:]
        # Sequence properties are checked separately from output serialization.
        assert len(events) <= 2
        if action.op == 3 or (action.op in (0, 2) and action.count == 0): assert not events
        for ordinal in range(2, 7):
            node, previous = self.nodes[ordinal], before[ordinal]
            assert not previous['fault'] or node['fault'], 'fault recovered'
            if node['type'] == 'select':
                assert not previous['done'] or node['done'], 'handoff reversed'
            elif not (action.op == 3 and ordinal == (2, 3, 5)[action.offset] and not previous['fault']):
                committed = sum(amount for owner, amount in self.accepted if owner == ordinal)
                assert previous['limit'] - node['limit'] == committed, 'unconfirmed quota progress'
        for identity, provider in enumerate(self.providers):
            assert 0 <= provider['cursor'] <= provider['fetched'] <= provider['length']
            assert provider['data'] == source_data(identity, provider['length']), 'source changed'
        if action.op != 3 and before[self.root]['fault']: assert not events
        if action.op == 0 and not reply.error:
            assert 0 <= reply.number <= action.count
        words = [int(reply.error != 0), reply.error, reply.host, reply.number,
                 reply.start, reply.length, reply.stride, len(reply.data)] + list(reply.data)
        words += self.states()
        for provider in self.providers:
            words += [provider['cursor'], provider['fetched']] + provider['calls']
        words += self.destination + self.providers[0]['data'] + self.providers[1]['data']
        words += [len(events)] + [word for event in events for word in event]
        return words


def reference(case):
    model = Model(case)
    words = list(model.strides)
    for action in case.actions: words += model.step(action)
    return [word & MASK for word in words]


def cases():
    result, seen = [], set()
    def append(kind, actions, lengths=(12, 9), quotas=(7, 5, 11), layouts=range(8)):
        assert len(actions) <= 32
        for layout in layouts:
            case = Case(kind, layout, *lengths, tuple(quotas), tuple(actions))
            if case not in seen:
                seen.add(case)
                result.append(case)
    def setter(kind, quota, target=None):
        return Action(3, (2 if kind == 2 else 0) if target is None else target, quota=quota)
    mixed = [Action(0, count=0), Action(2, count=0), Action(1, first=3, second=4),
             Action(2, count=1), Action(0, count=2, first=1, second=1), Action(1),
             Action(2, count=8), Action(0, count=4, first=0, second=2), Action(1),
             Action(2, count=2), Action(0, count=6), Action(1)]
    quotas = ((0, 0, 0), (1, 2, 3), (7, 5, 11), (16, 16, 32),
              (MAX_I32 + 1, (1 << 32) + 1, 1 << 63), (MASK, MASK - 1, MASK))
    for kind in range(4):
        for limits in quotas:
            append(kind, mixed + [setter(kind, MASK), Action(1), Action(0, count=9)], quotas=limits)
        for lengths in ((0, 0), (0, 9), (12, 0), (1, 1), (16, 16)):
            append(kind, [Action(1), Action(2, count=1), Action(0, count=3), Action(1),
                          setter(kind, 0), Action(1), setter(kind, MASK), Action(0, count=16)], lengths=lengths)
        # Transient first EOF, second error, permanent mixed-protocol handoff,
        # then observational second EOF and recovery.
        append(kind, [Action(0, first=0, second=-7), Action(1, first=16, second=0),
                      Action(1, first=16, second=3), Action(2, count=2),
                      Action(0, first=16, second=0), Action(0, first=16, second=4)], quotas=(MASK, MASK, MASK))
        for op in (0, 1, 2):
            for event in tuple(range(-12, 0)) + (-101, -102, -103, -104):
                for selected in (0, 1):
                    setup = [Action(1, first=4, second=4)] if op == 2 else []
                    if selected:
                        setup = [Action(0, count=1, first=0, second=0)] + setup
                    trigger = Action(op, count=2, first=event if selected == 0 else 16,
                                     second=event if selected == 1 else 16)
                    script = setup + [trigger, Action(0, -1, 0), Action(0, MAX_I32, 0), Action(2, count=0),
                                      setter(kind, 8), Action(1), Action(2, count=1), Action(0, count=2)]
                    append(kind, script, quotas=(MASK, MASK, MASK), layouts=((op + selected) % 8, (op + selected + 4) % 8))
        append(kind, [Action(1, first=-105, second=-105), Action(1, first=2, second=2), Action(2, count=1)])
        for offset, count in ((-1, 0), (0, -1), (MIN_I32, 1), (MAX_I32, 1), (MAX_I32 - 1, 2), (MAX_I32, 0)):
            append(kind, [Action(0, offset, count), Action(1), Action(2, count=MIN_I32),
                          Action(2, count=MAX_I32), Action(0, count=1)])
        # A legitimate reopened inner quota never reverses an outer chain's EOF.
        if kind == 3:
            append(kind, [Action(0, count=2), setter(kind, 10), Action(1), Action(2, count=1),
                          setter(kind, MASK, 1), Action(0, count=3)], quotas=(0, 2, MASK))
    rng = random.Random(SEED)
    counts = (-1, 0, 1, 2, 3, 8, 16, MAX_I32)
    events = (0, 1, 2, 5, 16, -1, -4, -7, -8, -10, -101, -102, -103, -104)
    for index in range(192):
        kind = index % 4
        actions = []
        for _ in range(12):
            op = rng.randrange(4)
            if op == 3:
                actions.append(setter(kind, rng.choice((0, 1, 2, 7, MAX_I32, 1 << 32, 1 << 63, MASK)),
                                      rng.choice((0, 1)) if kind == 3 else None))
            else:
                count = rng.choice(counts)
                offset = rng.choice((-1, 3, MAX_I32))
                # Valid nonempty destinations always have actual backing.
                if op == 0 and count > 0 and valid(offset, count) and offset + count > 32:
                    offset = 3 if count <= 16 else MAX_I32
                actions.append(Action(op, offset, count, first=rng.choice(events), second=rng.choice(events)))
        append(kind, actions, lengths=(rng.randrange(17), rng.randrange(17)),
               quotas=tuple(rng.choice((0, 1, 7, 16, MASK)) for _ in range(3)), layouts=(index % 8,))
    return result


def packet(values):
    result = bytearray()
    for case in values:
        words = [case.kind, case.layout, case.first_length, case.second_length, *case.quotas, len(case.actions)]
        for action in case.actions:
            assert action.op in range(4) and MIN_I32 <= action.offset <= MAX_I32 and MIN_I32 <= action.count <= MAX_I32
            assert 0 <= action.quota <= MASK
            words += [action.op, action.offset, action.count, action.quota, action.first, action.second]
        result += struct.pack('<' + 'Q' * len(words), *(word & MASK for word in words))
    return result


def encode(values):
    result = bytearray()
    for case in values:
        words = reference(case)
        result += struct.pack('<' + 'Q' * len(words), *words)
    return result


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        expected = reference(case)
        size = 8 * len(expected)
        assert offset + size <= len(actual), (f'seed={SEED:#x}', index, case, 'truncated')
        observed = struct.unpack_from('<' + 'Q' * len(expected), actual, offset)
        if observed != tuple(expected):
            word = next(at for at, pair in enumerate(zip(observed, expected)) if pair[0] != pair[1])
            raise AssertionError((f'seed={SEED:#x}', index, case, 'word', word, 'observed', observed[word], 'expected', expected[word]))
        offset += size
    assert offset == len(actual), (offset, len(actual), 'extra output')


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values), values)
    # Literal sequence laws independently check the state evaluator.
    take = Model(Case(0, 7, 5, 4, (2, 0, 0), ()))
    take.step(Action(0, count=4))
    assert take.destination[3:5] == [13, 50] and take.nodes[2]['limit'] == 0
    assert take.providers[0]['cursor'] == 2 and take.events == [(0, 0, 16, 3, 2, 0, 0)]
    before = len(take.events)
    assert take.step(Action(1))[:8] == [0, 0, 0, 0, 0, 0, 1, 0]
    assert len(take.events) == before
    take.step(Action(3, 0, quota=MASK)); take.step(Action(0, count=1, first=0))
    assert take.nodes[2]['limit'] == MASK
    take.step(Action(0, count=1))
    assert take.destination[3] == 87 and take.nodes[2]['limit'] == MASK - 1
    chain = Model(Case(1, 7, 5, 4, (MASK, MASK, MASK), ()))
    chain.step(Action(0, count=2, first=0, second=-4))
    assert chain.nodes[4]['done'] and not chain.nodes[4]['fault']
    chain.step(Action(1, first=-101, second=2))
    assert [event[0] for event in chain.events] == [0, 1, 1]
    nested = Model(Case(2, 7, 5, 4, (MASK, MASK, MASK), ()))
    nested.step(Action(0, count=2, first=-102))
    assert nested.nodes[4]['fault'] and not nested.nodes[5]['fault'] and nested.nodes[5]['limit'] == MASK
    nested.step(Action(3, 2, quota=3))
    assert nested.nodes[5]['limit'] == 3
    calls = len(nested.events); nested.step(Action(1)); assert len(nested.events) == calls
    reopened = Model(Case(3, 7, 5, 4, (0, 2, MASK), ()))
    reopened.step(Action(0, count=1)); reopened.step(Action(3, 0, quota=10)); reopened.step(Action(0, count=1))
    assert reopened.nodes[6]['done'] and reopened.providers[0]['cursor'] == 0 and reopened.providers[1]['cursor'] == 2
    # Honest read-only composition: emitted chunks reconstruct the quota prefix.
    for kind in range(4):
        sample = Model(Case(kind, 7, 9, 6, (5, 3, 11), ()))
        chunks = []
        for _ in range(20):
            observed = sample.step(Action(0, count=2, first=16, second=16))
            assert observed[0] == 0
            chunks += sample.destination[3:3 + observed[3]]
        a, b = source_data(0, 9)[2:11], source_data(1, 6)[2:8]
        expected = (a[:5], a + b, (a + b)[:11], a[:5] + b[:3])[kind]
        assert chunks == expected
    sample = Case(2, 7, 9, 6, (5, 3, 11), (Action(0, count=2), Action(1)))
    words = reference(sample)
    # Header; result; quota; provider state; destination; source guard; event.
    mutations = ((0, 8), (3 + 3, 1), (3 + 8 + 6, 11), (3 + 8 + 10, 0),
                 (3 + 8 + 20 + 3, 0), (3 + 8 + 20 + 32, 0),
                 (3 + 8 + 20 + 96 + 1 + 3, 0))
    for word, replacement in mutations:
        assert words[word] != replacement
        bad = encode([sample]); struct.pack_into('<Q', bad, word * 8, replacement)
        try: verify(bad, [sample])
        except AssertionError: pass
        else: raise AssertionError(('accepted corruption', word))
    for bad in (encode([sample])[:-1], encode([sample]) + b'\0'):
        try: verify(bad, [sample])
        except AssertionError: pass
        else: raise AssertionError('accepted framing corruption')
    counts = Counter(case.kind for case in values)
    print(f'io-adapters CPU cases={len(values)} actions={sum(len(case.actions) for case in values)} compositions=4 layouts=8 seed={SEED:#x} corruption-controls=9')
    print(f'io-adapters compositions={dict(sorted(counts.items()))}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls(); return
    assert len(sys.argv) == 2, 'usage: oracle.py <model-executable> | controls'
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f'io-adapters cases={len(values)} actions={sum(len(case.actions) for case in values)} compositions=4 layouts=8 seed={SEED:#x}')


if __name__ == '__main__': main()
