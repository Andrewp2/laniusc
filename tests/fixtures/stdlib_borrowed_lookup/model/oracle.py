"""Dictionary reference and contract-only search-path checks; no hash/AVL engine."""
from __future__ import annotations
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import math
import random
import struct
import subprocess
import sys

SEED = 0xB0770261120
MAGIC = 0x626F72726F776564
END = 0x656E64626F72726F
MASK = (1 << 64) - 1
QUERY_XOR = 0x55AA11EE22DD33CC
NAMES = ('insert', 'contains_by', 'get_by', 'entry_or_replace', 'remove_by', 'update_value_by', 'clear')


@dataclass(frozen=True)
class Case:
    family: int  # hash map, tree map, hash set, tree set
    hashing: int
    actions: tuple


def is_map(case): return case.family < 2
def is_hash(case): return case.family % 2 == 0
def query_operation(case, op): return op in ((1, 2, 3, 4, 5) if is_map(case) else (1, 2, 4))
def hashed(identity, mode): return 65535 if mode == 0 else ((identity % 3) * 2654435761) & 0xFFFFFFFF
def query(case, action):
    _, key, stamp, _, _ = action
    bias = stamp % 9 - 4
    return key + bias, bias, stamp ^ QUERY_XOR, case.hashing


def payload(token):
    n = token % 2000001 - 1000000
    return token ^ 0x91A2B3C4D5E6F708, 0 if token % 3 == 0 else 2 if token & 1 else 1, (n, -n, n // 2 if n >= 0 else -((-n) // 2))


def change(old, token, mode, ordinal):
    number, mark, words = old
    new_mark = (0 if not mark else 3 - mark) if mode == 0 else 0 if mode == 1 else 2 if (token ^ ordinal) & 1 else 1
    updated = number ^ token ^ (ordinal << 32), new_mark, (words[1], words[2], token % 2000001 - 1000000)
    # Failure is an R value, and still reinstalls the new V.
    receipt = (0, old, ordinal) if mode % 2 == 0 else (1, updated, token)
    return updated, receipt


def semantic(case, contents, action, updates):
    op, key, stamp, token, mode = action; before = dict(contents)
    previous = before.get(key); result = None; event = None
    supplied = (key, stamp, case.hashing, payload(token) if is_map(case) else None)
    if op == 0:
        if is_map(case): result = previous; contents[key] = supplied
        elif previous is None: contents[key] = supplied
        else: result = supplied
    elif op == 1: result = previous is not None
    elif op == 2: result = None if previous is None else previous[3] if is_map(case) else previous
    elif op == 3:
        result = previous
        if not is_map(case): contents[key] = supplied
    elif op == 4: result = contents.pop(key, None)
    elif op == 5:
        assert is_map(case)
        if previous is not None:
            updates += 1; new, receipt = change(previous[3], token, mode, updates)
            contents[key] = (*previous[:3], new); result = (receipt,)
            event = updates, mode, token, previous[3], new, receipt
    elif op == 6: contents.clear()
    else: raise AssertionError(action)
    return before, result, event, updates


def corpus():
    ascending = list(range(15))
    orders = [ascending, ascending[::-1], [7, 3, 11, 1, 5, 9, 13, 0, 2, 4, 6, 8, 10, 12, 14],
              [0, 14, 1, 13, 2, 12, 3, 11, 4, 10, 5, 9, 6, 8, 7]]
    for i in range(2):
        order = list(ascending); random.Random(SEED + i).shuffle(order); orders.append(order)
    result = []
    for family in range(4):
        for profile, order in enumerate(orders):
            rng = random.Random(SEED + family * 101 + profile); ops = []
            queries = (1, 2, 3, 5, 4) if family < 2 else (1, 2, 4)
            ops += [(op, 7) for op in queries]
            ops += [(0, key) for key in order]
            for op in queries: ops += [(op, 7), (op, 30)]
            ops += [(4, key) for key in (0, 2, 4, 6, 8, 10, 12, 14)]
            ops += [(0, key) for key in (7, 0, 4, 8, 12, 14)]
            ops += [(0, 1), (0 if family < 2 else 3, 1), (6, 0)]
            ops += [(op, 7) for op in queries]
            ops += [(0, key) for key in (3, 1, 4, 2, 5)]
            ops += [(5 if family < 2 else 2, 3), (2, 3)]
            while len(ops) < 96:
                choices = (0, 0, 1, 2, 3, 4, 5, 5, 6) if family < 2 else (0, 0, 1, 2, 3, 4, 4, 6)
                ops.append((rng.choice(choices), rng.randrange(24)))
            actions = []
            for step, (op, key) in enumerate(ops):
                stamp = 0xF123450000000000 | profile << 16 | step
                token = rng.getrandbits(64) if step % 9 else (0, MASK, 1 << 63, (1 << 32) + 1)[step // 9 % 4]
                # Every schedule explicitly reaches an update with ordinary Err.
                mode = 1 if op == 5 and key == 3 else step % 4
                actions.append((op, key, stamp, token, mode))
            for hashing in ((0, 1) if family % 2 == 0 else (0,)):
                result.append(Case(family, hashing, tuple(actions)))
    return result


class Reader:
    def __init__(self, data): self.data = data; self.at = 0; self.marks = {}; self.context = None
    def word(self, label='word'):
        assert self.at + 8 <= len(self.data), ('truncated', self.context)
        self.marks.setdefault(label, self.at)
        value = struct.unpack_from('<Q', self.data, self.at)[0]; self.at += 8; return value
    def expect(self, value, label):
        actual = self.word(label); assert actual == value & MASK, (self.context, label, actual, value)
    def signed(self, label):
        word = self.word(label); return word if word < (1 << 63) else word - (1 << 64)
    def val(self, expected, label='value'):
        number, mark, words = expected; self.expect(number, label + ' wide'); self.expect(mark, label + ' option')
        for word in words: self.expect(word, label + ' array')
    def key(self, expected, label='key'):
        for word in expected[:3]: self.expect(word, label)
    def entry(self, case, expected, label='entry'):
        self.expect(expected is not None, label + ' present')
        if expected is not None:
            self.key(expected, label + ' representative')
            if is_map(case): self.val(expected[3], label + ' value')
    def receipt(self, expected, label='receipt'):
        tag, value, extra = expected; self.expect(tag, label + ' variant'); self.val(value, label + ' value'); self.expect(extra, label + ' extra')


def snapshot(r, case, contents, counts):
    r.expect(len(contents), 'length'); r.expect(not contents, 'empty')
    metadata = (r.word('capacity'), r.word('storage'), r.signed('metadata a'), r.signed('metadata b'), r.signed('metadata c'))
    cap, address, a, b, c = metadata
    assert cap >= len(contents) and (cap == 0) == (address == 0)
    if is_hash(case): assert a == cap * 2 and len(contents) <= b <= a and c == 0
    else:
        assert 0 <= a <= cap and a >= len(contents)
        assert (b == -1) == (not contents) and -1 <= b < cap and -1 <= c < cap
    observed = {}; order = []
    while True:
        present = r.word('iterator present'); assert present in (0, 1), ('invalid presence', r.context, present)
        if not present: break
        r.marks.setdefault('nonempty iterator present', r.at - 8)
        assert len(observed) < len(contents)
        key = r.word('snapshot identity'); assert key in contents and key not in observed
        entry = contents[key]; r.expect(entry[1], 'snapshot representative'); r.expect(entry[2], 'snapshot hash mode')
        if is_map(case): r.val(entry[3], 'snapshot value')
        observed[key] = entry; order.append(key); counts['snapshot_entries'] += 1
    assert observed == contents
    if not is_hash(case): assert order == sorted(contents), ('tree order', r.context, order)
    r.expect(0, 'iterator fused')
    return metadata


def verify(data, cases):
    r = Reader(data); counts = Counter(); coverage = set()
    r.expect(MAGIC, 'magic'); r.expect(len(cases), 'case count')
    for number, case in enumerate(cases):
        r.context = (number, 'initial')
        for word in (number, case.family, case.hashing, len(case.actions)): r.expect(word, 'case header')
        contents = {}; hashes = comparisons = updates = 0
        metadata = snapshot(r, case, contents, counts); assert metadata == ((0, 0, 0, 0, 0) if is_hash(case) else (0, 0, 0, -1, -1))
        for step, action in enumerate(case.actions):
            op, key, stamp, token, mode = action; previous = metadata; old_updates = updates
            r.context = (number, step, NAMES[op], key)
            for word in (step, *action): r.expect(word, 'action header')
            before, result, expected_update, updates = semantic(case, contents, action, updates)
            querying = query_operation(case, op); hit = key in before
            if querying: coverage.add((case.family, op, hit)); counts['queries'] += 1
            query_data = query(case, action); query_hash = hashed(key, case.hashing)
            seen = set(); matched = False; got_hash = False; got_update = False; lower = -1; upper = 32
            while True:
                kind = r.word('event kind')
                if kind == 99: break
                assert querying and not got_update
                if kind == 1:
                    assert is_hash(case) and not got_hash and not seen
                    got_hash = True; hashes += 1; r.expect(hashes, 'hash ordinal')
                    for word in query_data: r.expect(word, 'hashed query')
                    r.expect(query_hash, 'query hash')
                elif kind in (2, 3):
                    assert (kind == 2) == is_hash(case) and not matched
                    if is_hash(case): assert got_hash
                    comparisons += 1; r.expect(comparisons, 'comparison ordinal')
                    stored = r.word('compared identity'); assert stored in before and stored not in seen
                    entry = before[stored]; r.expect(entry[1], 'compared representative'); r.expect(entry[2], 'compared hash mode')
                    for word in query_data: r.expect(word, 'comparison query')
                    if is_hash(case):
                        assert hashed(stored, case.hashing) == query_hash, ('ineligible cached hash', r.context)
                        decision = stored == key
                    else:
                        assert lower < stored < upper
                        decision = 0 if stored < key else 2 if stored > key else 1
                        if stored < key: lower = stored
                        if stored > key: upper = stored
                    r.expect(decision, 'comparison decision'); seen.add(stored); matched = stored == key
                elif kind == 4:
                    assert expected_update is not None and matched and not got_update
                    got_update = True
                    ordinal, behavior, salt, old, new, receipt = expected_update
                    r.expect(ordinal, 'update ordinal'); r.expect(behavior, 'update mode'); r.expect(salt, 'update token')
                    r.val(old, 'callback input'); r.val(new, 'callback installed'); r.receipt(receipt, 'callback receipt')
                else: raise AssertionError(('unknown event', r.context, kind))
            assert got_hash == (querying and is_hash(case))
            assert matched == (querying and hit)
            assert got_update == (expected_update is not None)
            assert len(seen) <= len(before)
            if querying and before and (not is_hash(case) or case.hashing == 0): assert seen
            if not is_hash(case): assert len(seen) <= 2 * math.ceil(math.log2(len(before) + 1))
            if op in (0, 3, 4): r.entry(case, result, 'returned')
            elif op == 1: r.expect(result, 'contains result')
            elif op == 2:
                if is_map(case):
                    r.expect(result is not None, 'get present')
                    if result is not None: r.val(result, 'get value')
                else: r.entry(case, result, 'returned')
            elif op == 5:
                r.expect(result is not None, 'update present')
                if result is not None: r.receipt(result[0], 'returned receipt')
            else: r.expect(0, 'clear result')
            r.expect(hashes, 'total hashes'); r.expect(comparisons, 'total comparisons'); r.expect(updates, 'total updates')
            metadata = snapshot(r, case, contents, counts)
            if querying:
                if op != 4 or not hit: assert metadata == previous, ('query changed structural metadata', r.context)
                else: assert metadata[:2] == previous[:2], ('remove changed allocation', r.context)
            if op == 6: assert metadata[:2] == previous[:2], ('clear changed allocation', r.context)
            counts['actions'] += 1; counts['query_hashes'] += querying and is_hash(case)
            counts['query_hits'] += querying and hit; counts['query_misses'] += querying and not hit
            counts['updates'] += updates - old_updates
            counts['missing_updates'] += op == 5 and expected_update is None
            counts['error_receipts'] += expected_update is not None and expected_update[-1][0] == 1
            counts['removals'] += op == 4 and hit
        r.expect(100, 'final marker'); snapshot(r, case, contents, counts)
    r.expect(END, 'end marker'); assert r.at == len(data), ('trailing bytes', r.at, len(data))
    required = {(family, op, hit) for family in range(4) for op in ((1, 2, 3, 4, 5) if family < 2 else (1, 2, 4)) for hit in (False, True)}
    assert coverage == required and len(coverage) == 32
    assert counts['missing_updates'] and counts['error_receipts'] and counts['removals']
    return counts, r.marks


class Writer:
    def __init__(self): self.data = bytearray()
    def word(self, value): self.data += struct.pack('<Q', value & MASK)
    def words(self, values):
        for value in values: self.word(value)
    def val(self, value): self.words(value[:2]); self.words(value[2])
    def entry(self, case, value):
        self.word(value is not None)
        if value is not None:
            self.words(value[:3])
            if is_map(case): self.val(value[3])
    def receipt(self, value): self.word(value[0]); self.val(value[1]); self.word(value[2])
    def snapshot(self, case, contents, metadata, policy):
        self.words((len(contents), not contents, *metadata))
        keys = sorted(contents, reverse=bool(policy and is_hash(case)))
        for key in keys: self.entry(case, contents[key])
        self.words((0, 0))


def simulated(cases, policy=0, mutant=None):
    """Verifier controls accept two search policies; neither predicts native paths."""
    w = Writer(); w.words((MAGIC, len(cases))); reached = False
    for number, case in enumerate(cases):
        w.words((number, case.family, case.hashing, len(case.actions)))
        contents = {}; hashes = comparisons = updates = 0
        metadata = (0, 0, 0, 0, 0) if is_hash(case) else (0, 0, 0, -1, -1)
        w.snapshot(case, contents, metadata, policy)
        for step, action in enumerate(case.actions):
            op, key, stamp, token, mode = action; w.words((step, *action))
            before, result, update, updates = semantic(case, contents, action, updates)
            querying = query_operation(case, op); query_data = query(case, action)
            if querying:
                if is_hash(case):
                    hashes += 1; w.words((1, hashes, *query_data, hashed(key, case.hashing)))
                    candidates = sorted((k for k in before if hashed(k, case.hashing) == hashed(key, case.hashing)), reverse=bool(policy))
                else:
                    candidates = []; remaining = sorted(before)
                    while remaining:
                        middle = (len(remaining) - policy) // 2; current = remaining[middle]; candidates.append(current)
                        if current == key: break
                        remaining = remaining[middle + 1:] if current < key else remaining[:middle]
                for stored in candidates:
                    comparisons += 1; entry = before[stored]
                    decision = int(stored == key) if is_hash(case) else 0 if stored < key else 2 if stored > key else 1
                    w.words((2 if is_hash(case) else 3, comparisons, *entry[:3], *query_data, decision))
                    if stored == key: break
                if update:
                    ordinal, behavior, salt, old, new, receipt = update
                    w.words((4, ordinal, behavior, salt)); w.val(old); w.val(new); w.receipt(receipt)
                    if mutant == 'lost failed update' and receipt[0] == 1 and not reached:
                        contents[key] = before[key]; reached = True
            if not reached and mutant == 'query representative' and querying and key in contents:
                value = contents[key]; contents[key] = (value[0], query_data[2], *value[2:]); reached = True
            if not reached and mutant == 'remove kept entry' and op == 4 and key in before:
                contents[key] = before[key]; reached = True
            if not reached and mutant == 'set duplicate replaced representative' and op == 0 and not is_map(case) and key in before:
                contents[key] = (key, stamp, case.hashing, None); reached = True
            cap, address, a, b, c = metadata
            if op in (0, 3) and not querying:
                if not cap: cap = 64; address = 0x100000 + number * 0x10000
                if is_hash(case): a = cap * 2; b = max(b, len(contents))
                else: a = max(a, len(contents)); b = 0 if contents else -1
            if op == 4 and key in before:
                if is_hash(case): b = b if contents else 0
                else: b = 0 if contents else -1; c = 0
            if op == 6:
                if is_hash(case): b = 0
                else: a = 0; b = c = -1
            metadata = cap, address, a, b, c
            w.word(99)
            if op in (0, 3, 4): w.entry(case, result)
            elif op == 1: w.word(result)
            elif op == 2:
                if is_map(case):
                    w.word(result is not None)
                    if result is not None: w.val(result)
                else: w.entry(case, result)
            elif op == 5:
                w.word(result is not None)
                if result is not None: w.receipt(result[0])
            else: w.word(0)
            w.words((hashes, comparisons, updates)); w.snapshot(case, contents, metadata, policy)
        w.word(100); w.snapshot(case, contents, metadata, policy)
    w.word(END)
    if mutant: assert reached, ('unreached mutant', mutant)
    return bytes(w.data)


def packet(cases):
    data = bytearray(struct.pack('<2Q', MAGIC, len(cases)))
    for case in cases:
        data += struct.pack('<3Q', case.family, case.hashing, len(case.actions))
        for action in case.actions: data += struct.pack('<5Q', *action)
    return bytes(data)


def summary(cases, counts):
    keys = ('actions', 'queries', 'query_hashes', 'query_hits', 'query_misses', 'updates',
            'missing_updates', 'error_receipts', 'removals', 'snapshot_entries')
    return ('borrowed-lookup-model cases=%d ' % len(cases) + ' '.join('%s=%d' % (k, counts[k]) for k in keys)
            + ' families=4 apis=16 hit_miss_routes=32 hash_modes=2 seed=0x%x\n' % SEED)


def controls(cases):
    first = simulated(cases); counts, marks = verify(first, cases)
    other, _ = verify(simulated(cases, 1), cases); assert summary(cases, counts) == summary(cases, other)
    def reject(data, label):
        try: verify(data, cases)
        except (AssertionError, struct.error, KeyError, IndexError): return
        raise AssertionError('accepted corruption: ' + label)
    labels = ('hash ordinal', 'hashed query', 'query hash', 'compared representative', 'comparison query',
              'comparison decision', 'update ordinal', 'callback input wide', 'callback installed array',
              'callback receipt variant', 'returned representative', 'get value option', 'update present',
              'snapshot representative', 'snapshot value wide', 'total updates')
    for label in labels:
        bad = bytearray(first); bad[marks[label]] ^= 1; reject(bytes(bad), label)
    bad = bytearray(first); struct.pack_into('<Q', bad, marks['nonempty iterator present'], 2)
    reject(bytes(bad), 'non-Boolean iterator presence')
    for label in ('lost failed update', 'query representative', 'remove kept entry', 'set duplicate replaced representative'):
        reject(simulated(cases, mutant=label), label)
    reject(first[:-1], 'truncation'); reject(first + b'\0', 'trailing bytes')
    print(summary(cases, counts), end=''); print('cpu-controls=23 rejected=23 search-policies=2 bytes=%d' % len(first))


def main():
    cases = corpus(); assert len(cases) == 36
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(cases); return
    assert len(sys.argv) == 2
    child = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=75, check=False)
    assert child.returncode == 0, ('native status', child.returncode, child.stderr[:2048])
    assert not child.stderr, ('native stderr', child.stderr[:2048])
    counts, _ = verify(child.stdout, cases); print(summary(cases, counts), end='')


if __name__ == '__main__': main()
