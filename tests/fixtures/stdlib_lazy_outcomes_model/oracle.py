"""Declarative branch-selection reference for composed lazy value operations.

The table is an algebra over tagged values and callback effects, not a copy of
the Lanius branch implementation. Every payload, event and preserved operand is
part of a complete deterministic binary transcript. Python is test-only.
"""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x1A2F0261119
MASK = (1 << 64) - 1
MAGIC = 0x6C617A796D6F646C
END = 0x656E646C617A796D
EVENT = 0xE001
AFTER = 0xA001
PRODUCER_BASE = 0xF0E1D2C3B4A59687
WIDE_MASK = 0x91A2B3C4D5E6F708
BRANCH_MASK = 0xFEDCBA9876543210

# Handler: callback kind, selected identity slot, projection. Negative kinds
# are constants/projections without invocation. Kinds 0..5 are mapper,
# predicate, optional mapper, result mapper, producer, optional producer.
PRESERVE = (-1, 0, 'receiver')
PAYLOAD = (-1, 0, 'payload')
NONE = (-1, 0, 'none')
EAGER = (-1, 0, 'eager')
FALSE = (-1, 0, 'false')
TRUE = (-1, 0, 'true')
OK = (-1, 0, 'ok_payload')
TABLE = (
    ('option', 'option', {'S': (0, 1, 'some'), 'N': NONE}),
    ('option', 'plain', {'S': (0, 1, 'identity'), 'N': EAGER}),
    ('option', 'plain', {'S': (0, 1, 'identity'), 'N': (4, 2, 'identity')}),
    ('option', 'option', {'S': (2, 1, 'identity'), 'N': NONE}),
    ('option', 'option', {'S': PRESERVE, 'N': (5, 2, 'identity')}),
    ('option', 'plain', {'S': PAYLOAD, 'N': (4, 2, 'identity')}),
    ('option', 'result', {'S': OK, 'N': (4, 2, 'err')}),
    ('option', 'option', {'S': (1, 1, 'filter'), 'N': NONE}),
    ('option', 'flag', {'S': (1, 1, 'identity'), 'N': FALSE}),
    ('option', 'flag', {'S': (1, 1, 'identity'), 'N': TRUE}),
    ('result', 'result', {'O': (0, 1, 'ok'), 'E': PRESERVE}),
    ('result', 'result', {'O': PRESERVE, 'E': (0, 1, 'err')}),
    ('result', 'plain', {'O': (0, 1, 'identity'), 'E': EAGER}),
    ('result', 'plain', {'O': (0, 1, 'identity'), 'E': (0, 2, 'identity')}),
    ('result', 'result', {'O': (3, 1, 'identity'), 'E': PRESERVE}),
    ('result', 'result', {'O': PRESERVE, 'E': (3, 2, 'identity')}),
    ('result', 'plain', {'O': PAYLOAD, 'E': (0, 2, 'identity')}),
    ('result', 'flag', {'O': (1, 1, 'identity'), 'E': FALSE}),
    ('result', 'flag', {'O': FALSE, 'E': (1, 1, 'identity')}),
)
NAMES = ('option.map', 'option.map_or', 'option.map_or_else', 'option.and_then', 'option.or_else',
         'option.unwrap_or_else', 'option.ok_or_else', 'option.filter', 'option.is_some_and', 'option.is_none_or',
         'result.map', 'result.map_err', 'result.map_or', 'result.map_or_else', 'result.and_then',
         'result.or_else', 'result.unwrap_or_else', 'result.is_ok_and', 'result.is_err_and')


@dataclass(frozen=True)
class Case:
    shape: int
    mode: int
    token: int
    actions: tuple


class State:
    def __init__(self, mode, token): self.calls = 0; self.seed(mode, token)
    def seed(self, mode, token):
        self.option = ('S', token) if mode & 1 else ('N', None)
        self.result = ('O' if mode & 2 else 'E', token ^ MASK)
        self.plain = token ^ 0x1111111111111111; self.flag = bool(mode & 1)
    def values(self): return self.option, self.result, self.plain, self.flag
    def step(self, action, counts, coverage, mutant=None):
        op, route, mode, salt = action; events = []
        original = self.values()
        if mutant == 'reset counter': self.calls = 0

        def callback(kind, identity, operand):
            self.calls += 1
            if mutant == 'wrong callback input' and operand is not None: operand ^= 1
            base = PRODUCER_BASE if operand is None else operand
            token = base ^ salt ^ (self.calls << 32) ^ (identity << 8)
            selected = mode == 1 or (mode >= 2 and ((token ^ self.calls) & 1) != 0)
            if kind in (0, 4): answer = token
            elif kind == 1:
                answer = mode == 1 or (mode == 2 and ((base ^ salt ^ self.calls) & 1) != 0) or (mode == 3 and base % 5 == self.calls % 5)
            elif kind in (2, 5): answer = ('S', token) if selected else ('N', None)
            else: answer = ('O', token) if selected else ('E', token ^ (1 << 63))
            if mutant == 'lose callback failure' and kind in (2, 3, 5):
                answer = ('O' if kind == 3 else 'S', token)
            events.append((kind, identity, self.calls, mode, salt, operand, answer))
            return answer

        if op < 19:
            source, target, choices = TABLE[op]; receiver = getattr(self, source)
            coverage.add((op, route, receiver[0]))
            kind, slot, projection = choices[receiver[0]]
            value = None
            if kind >= 0:
                operand = receiver[1] if kind < 4 else None
                value = callback(kind, op * 2 + slot, operand)
                if mutant == 'duplicate callback': value = callback(kind, op * 2 + slot, operand)
            elif mutant == 'eager skipped callback':
                callback(0, op * 2 + 1, receiver[1] if receiver[1] is not None else salt)
            projections = {
                'receiver': lambda: receiver, 'payload': lambda: receiver[1], 'none': lambda: ('N', None),
                'eager': lambda: salt ^ 0xAAAAAAAAAAAAAAAA, 'false': lambda: False, 'true': lambda: True,
                'ok_payload': lambda: ('O', receiver[1]), 'some': lambda: ('S', value),
                'ok': lambda: ('O', value), 'err': lambda: ('E', value), 'identity': lambda: value,
                'filter': lambda: receiver if bool(value) != (mutant == 'inverted filter') else ('N', None),
            }
            setattr(self, target, projections[projection]())
            counts['api_calls'] += 1; counts['method' if route else 'free'] += 1
            counts['selected'] += kind >= 0; counts['skipped'] += kind < 0
        elif op == 19:
            selected = mode == 1 or (mode >= 2 and self.flag)
            self.option = ('S', self.plain) if selected else ('N', None)
        elif op == 20:
            selected = mode == 1 or (mode >= 2 and self.flag)
            self.result = ('O' if selected else 'E', self.plain)
        elif op == 21: self.seed(mode, salt)
        elif op == 22: self.option = ('S', self.result[1]) if self.result[0] == 'O' else ('N', None)
        else: raise AssertionError(action)
        counts['actions'] += 1; counts['callbacks'] += len(events)
        for kind, _, _, _, _, _, answer in events:
            counts['producer_calls'] += kind >= 4
            counts['callback_absence'] += kind in (2, 5) and answer[0] == 'N'
            counts['callback_errors'] += kind == 3 and answer[0] == 'E'
        return original, events


def corpus():
    cases = []
    edges = (0, MASK, 1 << 63, (1 << 63) - 1, 0x0102030405060708, 0xFEDCBA9876543210, 1, 2)
    for shape in range(2):
        for profile, token in enumerate(edges):
            rng = random.Random(SEED + profile); actions = []
            def add(op, mode=0, salt=None):
                route = (profile // 4 + len(actions)) & 1
                actions.append((op, route, mode, rng.getrandbits(64) if salt is None else salt))
            # Each public branch appears in both call forms across profiles.
            for op in range(19):
                add(21, profile % 4, edges[(profile + op) % len(edges)])
                actions.append((op, (profile // 4 + op) & 1, (profile + op) % 4, rng.getrandbits(64)))
            # Outcomes feed following operations without resets: callback None
            # and Err must skip transforms, then chosen fallbacks recover.
            chain = ((21, 3), (3, 0), (0, 1), (7, 1), (4, 0), (4, 1), (6, 0),
                     (14, 0), (10, 1), (11, 2), (15, 0), (10, 1), (15, 1),
                     (10, 2), (13, 3), (17, 1), (19, 2), (7, 0), (8, 1),
                     (2, 2), (20, 2), (16, 3), (19, 1), (22, 0))
            for op, mode in chain: add(op, mode)
            while len(actions) < 96:
                add(rng.randrange(23), rng.randrange(4))
            cases.append(Case(shape, profile % 4, token, tuple(actions)))
    return cases


def payload_words(shape, token):
    if shape == 0: return (token,)
    n = token % 2000001 - 1000000
    half = n // 2 if n >= 0 else -((-n) // 2)
    mark = 0 if token % 3 == 0 else 2 if token & 1 == 0 else 1
    branch = (0, token ^ BRANCH_MASK) if token & 2 == 0 else (1, n)
    return (token, token ^ WIDE_MASK, mark, n, -n, half, *branch)


class Writer:
    def __init__(self): self.data = bytearray(); self.marks = {}; self.context = {}
    def word(self, value, label='word'):
        self.marks.setdefault(label, len(self.data)); self.data += struct.pack('<Q', value & MASK)
    def payload(self, shape, token, label='payload'):
        for word in payload_words(shape, token): self.word(word, label)
    def option(self, shape, value, label='option'):
        self.word(value[0] == 'S', label)
        if value[0] == 'S': self.payload(shape, value[1], label + ' payload')
    def result(self, shape, value, label='result'):
        self.word(value[0] == 'E', label); self.payload(shape, value[1], label + ' payload')
    def values(self, shape, values, prefix):
        option, result, plain, flag = values
        self.option(shape, option, prefix + ' option'); self.result(shape, result, prefix + ' result')
        self.payload(shape, plain, prefix + ' plain'); self.word(flag, prefix + ' flag')
    def event(self, shape, event):
        kind, identity, tick, mode, salt, operand, answer = event
        self.word(EVENT, 'event marker'); self.word(kind, 'callback kind'); self.word(identity, 'callback identity')
        self.word(tick, 'callback ordinal'); self.word(mode, 'callback mode'); self.word(salt, 'callback salt')
        self.word(operand is not None, 'callback input present')
        if operand is not None: self.payload(shape, operand, 'callback input')
        if kind in (0, 4): self.payload(shape, answer, 'callback output')
        elif kind == 1: self.word(answer, 'predicate result')
        elif kind in (2, 5): self.option(shape, answer, 'callback option')
        else: self.result(shape, answer, 'callback result')


def transcript(cases, mutant=None):
    w = Writer(); counts = Counter(); coverage = set(); w.word(MAGIC, 'magic'); w.word(len(cases), 'case count')
    for number, case in enumerate(cases):
        for value in (number, case.shape, case.mode, case.token, len(case.actions)): w.word(value)
        state = State(case.mode, case.token); w.values(case.shape, state.values(), 'initial')
        for step, action in enumerate(case.actions):
            w.context[len(w.data)] = (number, step, NAMES[action[0]] if action[0] < 19 else 'harness', action)
            w.word(step, 'step'); w.word(action[0], 'operation'); w.word(action[1], 'route')
            original, events = state.step(action, counts, coverage, mutant)
            for event in events: w.event(case.shape, event)
            w.word(AFTER, 'after marker'); w.word(state.calls, 'total callbacks')
            w.values(case.shape, original, 'preserved'); w.values(case.shape, state.values(), 'after')
        w.word(state.calls, 'final callbacks'); w.values(case.shape, state.values(), 'final')
    w.word(END, 'end marker')
    if mutant is None:
        required = {(op, route, tag) for op, (source, _, _) in enumerate(TABLE) for route in (0, 1)
                    for tag in ('S', 'N') if source == 'option'}
        required |= {(op, route, tag) for op, (source, _, _) in enumerate(TABLE) for route in (0, 1)
                     for tag in ('O', 'E') if source == 'result'}
        assert coverage == required and len(coverage) == 76
        assert counts['callback_absence'] and counts['callback_errors'] and counts['producer_calls']
    return bytes(w.data), counts, w.marks, w.context


def packet(cases):
    data = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for case in cases:
        data += struct.pack('<4Q', case.shape, case.mode, case.token, len(case.actions))
        for action in case.actions: data += struct.pack('<4Q', *action)
    return bytes(data)


def verify(actual, expected, contexts):
    if actual == expected: return
    at = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
    origin = max((offset for offset in contexts if offset <= at), default=None)
    raise AssertionError(('binary mismatch', 'offset', at, 'context', contexts.get(origin),
                          'actual length', len(actual), 'expected length', len(expected),
                          actual[at:at + 16].hex(), expected[at:at + 16].hex()))


def summary(cases, counts):
    keys = ('actions', 'api_calls', 'free', 'method', 'selected', 'skipped', 'callbacks',
            'producer_calls', 'callback_absence', 'callback_errors')
    return ('lazy-outcomes-model cases=%d ' % len(cases) + ' '.join('%s=%d' % (k, counts[k]) for k in keys)
            + ' apis=19 branch_routes=76 shapes=2 seed=0x%x\n' % SEED)


def controls(cases):
    expected, counts, marks, contexts = transcript(cases); verify(expected, expected, contexts)
    def reject(data, label):
        try: verify(data, expected, contexts)
        except AssertionError: return
        raise AssertionError('accepted corruption: ' + label)
    labels = ('callback identity', 'callback ordinal', 'callback input', 'callback output', 'predicate result',
              'callback option', 'callback result', 'preserved option', 'preserved result payload',
              'after option payload', 'after result', 'after plain', 'after flag', 'final callbacks')
    for label in labels:
        bad = bytearray(expected); bad[marks[label]] ^= 1; reject(bytes(bad), label)
    for mutant in ('eager skipped callback', 'duplicate callback', 'wrong callback input',
                   'lose callback failure', 'inverted filter', 'reset counter'):
        reject(transcript(cases, mutant)[0], mutant)
    reject(expected[:-1], 'truncation'); reject(expected + b'\0', 'trailing bytes')
    print(summary(cases, counts), end='')
    print('cpu-controls=22 rejected=22 bytes=%d' % len(expected))


def main():
    cases = corpus(); assert len(cases) == 16
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(cases); return
    assert len(sys.argv) == 2
    expected, counts, _, contexts = transcript(cases)
    child = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=75, check=False)
    assert child.returncode == 0, ('native exit', child.returncode, child.stderr[:2048])
    assert not child.stderr, ('native stderr', child.stderr[:2048])
    verify(child.stdout, expected, contexts); print(summary(cases, counts), end='')


if __name__ == '__main__': main()
