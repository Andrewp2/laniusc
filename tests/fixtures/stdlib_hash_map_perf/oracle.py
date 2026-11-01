"""Check model.lani's operation histories against a Python dict.

usage: python3 -I oracle.py MODEL_EXECUTABLE
The dict is the reference: it knows nothing of groups, tags or tombstones.
Iteration is compared as an order-free digest plus the entry count; entries
an IntoIter consumes are checked one by one against the reference.
"""
import struct, subprocess, sys

M = (1 << 64) - 1
SPREAD = 11400714819323198485


class Stream:
    def __init__(self, data):
        assert len(data) % 8 == 0, f'partial word: {len(data)} bytes'
        self.words = struct.unpack(f'<{len(data) // 8}Q', data)
        self.at = 0

    def expect(self, value, label):
        assert self.at < len(self.words), f'output ended before {label} (word {self.at})'
        got = self.words[self.at]
        assert got == value & M, f'word {self.at} {label}: got {got}, expected {value & M}'
        self.at += 1

    def take(self, label):
        assert self.at < len(self.words), f'output ended before {label}'
        self.at += 1
        return self.words[self.at - 1]


def digest(table):
    return sum(((k * SPREAD) & M) ^ v for k, v in table.items()) & M


def run(s, wide, seed, ops, keys, insert, remove):
    state = seed
    def draw():
        nonlocal state
        state = (state * 6364136223846793005 + 1442695040888963407) & M
        return state >> 33
    table, stats = {}, [0, 0, 0]
    for i in range(ops):
        r = draw(); op = r % 100
        base = (r >> 8) % keys
        key = (base * SPREAD + 1) & M if wide else base
        value = draw()
        ins, rem = insert, remove
        if i < ops // 3: ins, rem = 80, 5
        elif i < 2 * (ops // 3): ins, rem = 10, 80
        if op < ins:
            s.expect(table[key] + 1 if key in table else 0, f'insert #{i}'); table[key] = value; stats[0] += 1
        elif op < ins + rem:
            s.expect(table.pop(key) + 1 if key in table else 0, f'remove #{i}'); stats[1] += 1
        else:
            s.expect(table[key] + 1 if key in table else 0, f'get #{i}')
            s.expect(1 if key in table else 0, f'get_entry #{i}'); stats[2] += 1
        if i % 997 == 0: s.expect(len(table), f'len #{i}'); s.expect(digest(table), f'digest #{i}')
        if i % 4999 == 4998: s.expect(digest(table), f'shrink digest #{i}')
        if i % 7919 == 7918: s.expect(digest(table), f'clone digest #{i}')
        if i % 6007 == 6006:
            taken = 0
            while taken < 64 and table:
                k = s.take(f'taken key #{i}')
                assert k in table, f'IntoIter yielded absent key {k} at op {i}'
                s.expect(table.pop(k), f'taken value #{i}'); taken += 1
            s.expect(M, f'take end #{i}'); s.expect(len(table), f'remaining #{i}')
        if i % 25013 == 25012: table.clear(); s.expect(0, f'clear #{i}')
    s.expect(len(table), 'final len'); s.expect(digest(table), 'final digest')
    return stats


def main():
    out = subprocess.run([sys.argv[1]], capture_output=True, timeout=120)
    assert out.returncode == 0 and not out.stderr, (out.returncode, out.stderr[:200])
    s = Stream(out.stdout)
    totals = [0, 0, 0]
    for profile in [(True, 1, 60000, 3000, 35, 45), (True, 2, 90000, 60000, 40, 40),
                    (False, 3, 9000, 300, 35, 45), (False, 4, 30000, 2000, 35, 45),
                    (False, 5, 30000, 20000, 30, 50)]:
        totals = [a + b for a, b in zip(totals, run(s, *profile))]
    assert s.at == len(s.words), f'{len(s.words) - s.at} extra words'
    print(f'PASS hash-map model profiles=5 words={len(s.words)} inserts={totals[0]} removes={totals[1]} lookups={totals[2]}')


main()
