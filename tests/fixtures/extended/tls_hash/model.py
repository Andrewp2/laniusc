#!/usr/bin/env python3
"""Test-only hashlib and declarative suite oracle; binary IPC, no production backend.

Published anchors: NIST CAVP SHA256/SHA384 ShortMsg Len=0 and NIST worked
SHA256.pdf / SHA384.pdf one-block 'abc' examples. No source algorithm is copied.
"""
import hashlib
import itertools
import random
import struct
import sys

WORD = (1 << 64) - 1
MAX_BYTES = (1 << 61) - 1
IDS = [0x1301, 0x1302, 0x1303]
PUBLISHED = [
    ["e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
     "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"],
    ["38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b",
     "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7"],
]


def digest(algorithm, message):
    return hashlib.new(['sha256', 'sha384'][algorithm], message).digest().ljust(48, b'\0')


def words(data):
    assert len(data) % 8 == 0
    return list(struct.unpack('<'+'Q'*(len(data)//8), data))


def result(op, algorithm, mode, a, b, c, split, parameter):
    length = [32, 48][algorithm]
    if op == 0:
        prefix = digest(algorithm, a[:split])
        changed = bytearray(prefix)
        changed[0] ^= 128
        changed[47] ^= 1
        return [0, algorithm, length, len(a)+len(c), split+len(b)]+words(
            digest(algorithm, a)+prefix+bytes(changed)+digest(algorithm, a)
            +digest(algorithm, a)+digest(algorithm, a[:split]+b)
            +digest(algorithm, a+c))
    if op in (1, 7):
        if mode in (1, 2, 3):
            return [1, 0]
        value = b'' if mode == 4 else a
        if op == 1 and len(value) != length:
            return [2, 0]
        if op == 7:
            return [0, length]+words(digest(algorithm, value))
        owned = value.ljust(48, b'\0')
        changed = bytearray(owned)
        changed[0] ^= 128
        changed[47] ^= 1
        return [0, length]+words(owned+bytes(changed)+owned)
    if op == 2:
        initial = [len(b), MAX_BYTES, MAX_BYTES+1, MAX_BYTES-1, MAX_BYTES-3, WORD][parameter]
        value = b'' if mode == 4 else a
        status = 1 if mode in (1, 2, 3) else 3 if initial > MAX_BYTES or len(value) > MAX_BYTES-initial else 0
        accepted = 0 if status else len(value)
        raw = initial+accepted
        second = 3 if parameter == 3 and mode == 0 and len(a) == 1 else 0
        after = b+(value if not status else b'')
        return [status, accepted, raw, second, len(after)+len(c), algorithm, length]+words(
            digest(algorithm, b)+digest(algorithm, after)+digest(algorithm, after+c))
    if op == 3:
        if parameter not in IDS:
            return [2, 0, 0, 0, 0, 0]
        kind = int(parameter == 0x1302)
        return [0, parameter, kind, [32, 48][kind], 16 if parameter == 0x1301 else 32, int(parameter != 0x1303)]
    if op == 4:
        if mode in (1, 2, 3):
            return [1]
        value = [] if mode == 4 else list(a)
        if not 1 <= len(value) <= 3 or len(set(value)) != len(value):
            return [3]
        owned = [IDS[x] for x in value]+[0x1303]*(3-len(value))
        changed = list(owned)
        changed[0] = 0x1302 if owned[0] == 0x1301 else 0x1301
        if len(value) < 3:
            changed[len(value)] = 0x1301
        return [0, len(value), *owned, len(value), *changed]
    if op == 5:
        active_length = parameter if parameter < 1 << 31 else parameter-(1 << 64)
        active = a[:max(0, active_length)]
        valid = 1 <= active_length <= 3 and len(set(active)) == active_length
        return [0 if valid else 3, active_length if valid else 0, parameter, *[IDS[x] for x in a]]
    if op == 6:
        return [0, 3, 0x1303, 0x1301, 0x1302]
    raise AssertionError(op)


CASES = []


def add(op, algorithm=0, mode=0, a=b'', b=b'', c=b'', split=0, chunk=17, parameter=0):
    parameter &= WORD
    expected = result(op, algorithm, mode, a, b, c, split, parameter)
    for layout in (0, 1):
        header = struct.pack('<10Q', op, layout, algorithm, mode, len(a), len(b), len(c), split, chunk, parameter & WORD)
        CASES.append((header+a+b+c, expected))


def hashes():
    rng = random.Random(0x544c5348415348)
    lengths = [1, 2, 3, 54, 55, 56, 63, 64, 65, 110, 111, 112, 127, 128, 129, 255, 256, 257, 511, 1024, 2048]
    for algorithm in (0, 1):
        for index, message in enumerate([b'', b'abc']):
            assert digest(algorithm, message).hex() == PUBLISHED[algorithm][index].ljust(96, '0')
        messages = [b'', b'abc']+[bytes((i*73+n*19+7) % 256 for i in range(n)) for n in lengths]
        for message in messages:
            for index, (split, chunk) in enumerate([(0, 1), (len(message)//2, 7), (len(message), 129)]):
                branch = bytes((i*3+index) % 256 for i in range([0, 17, 130][index]))
                suffix = bytes((255-i) % 256 for i in range([1, 63, 129][index]))
                add(0, algorithm, a=message, b=branch, c=suffix, split=split, chunk=chunk)
        for _ in range(20):
            message = rng.randbytes(rng.randrange(513))
            add(0, algorithm, a=message, b=rng.randbytes(rng.randrange(130)), c=rng.randbytes(rng.randrange(130)), split=rng.randrange(len(message)+1), chunk=rng.choice([1, 3, 16, 55, 64, 111, 128]))


def limits():
    for algorithm in (0, 1):
        for n in [0, 1, 31, 32, 33, 47, 48, 49, 64]:
            for mode in range(5):
                add(1, algorithm, mode, bytes((i*31+5) % 256 for i in range(n)), b=b'later algorithm stack use')
        for n in [0, 1, 55, 112]:
            for mode in range(5):
                add(7, algorithm, mode, bytes((i*13+2) % 256 for i in range(n)))
        for seed_length in [0, 55, 112, 129]:
            seed = bytes((i*19+seed_length) % 256 for i in range(seed_length))
            for n in [0, 1, 2, 3, 4]:
                for seam in range(6):
                    add(2, algorithm, a=bytes(range(n)), b=seed, c=bytes(range(130)), parameter=seam)
        for mode in [1, 2, 3, 4]:
            for seam in [0, 1, 2, 3, 5]:
                add(2, algorithm, mode, b'\xff', b=bytes(range(129)), c=bytes(range(130)), parameter=seam)


def suites():
    for value in [0x1301, 0x1302, 0x1303, 0, 0x1300, 0x1304, 0xffff]:
        add(3, parameter=value)
    for n in range(1, 4):
        for policy in itertools.permutations(range(3), n):
            add(4, a=bytes(policy))
    for n in (2, 3):
        for policy in itertools.product(range(3), repeat=n):
            if len(set(policy)) != n:
                add(4, a=bytes(policy))
    for data in [b'', bytes([0, 0, 0, 0]), bytes([0, 1, 2, 0]), bytes([2, 1, 0, 2])]:
        add(4, a=data)
        for mode in range(1, 5):
            add(4, mode=mode, a=data)
    for data in itertools.product(range(3), repeat=3):
        for length in [-1, 0, 1, 2, 3, 4]:
            add(5, a=bytes(data), parameter=length)
    add(6)


def main():
    {'hashes': hashes, 'limits': limits, 'suites': suites}[sys.argv[1]]()
    output = sys.stdout.buffer
    output.write(struct.pack('<Q', len(CASES)))
    for wire, expected in CASES:
        output.write(struct.pack('<Q', len(wire))+wire+struct.pack('<Q', len(expected)))
        output.write(struct.pack('<'+'Q'*len(expected), *expected))


if __name__ == '__main__':
    main()
