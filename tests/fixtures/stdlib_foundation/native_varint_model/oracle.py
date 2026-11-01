"""Independent native varint wire oracle. Python is test infrastructure only."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xA71A0261102
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
WORDS = 44


@dataclass(frozen=True)
class Case:
    operation: int
    family: int
    layout: int
    start: int
    length: int
    offset: int
    value: int
    wire: bytes


def signed(value, width):
    value &= (1 << width) - 1
    return value - (1 << width) if value >= (1 << (width - 1)) else value


def zigzag(value):
    return 2 * value if value >= 0 else -2 * value - 1


def unzigzag(value):
    return value // 2 if value % 2 == 0 else -(value // 2) - 1


def encoded(value):
    digits = []
    while True:
        quotient, remainder = divmod(value, 128)
        digits.append(remainder + (128 if quotient else 0))
        if not quotient: return bytes(digits)
        value = quotient


def width_of(case):
    return 32 if case.family in (0, 2) else 64


def unsigned_value(case):
    width = width_of(case)
    raw = case.value & ((1 << width) - 1)
    return zigzag(signed(raw, width)) if case.family >= 2 else raw


def logical_bounds(case):
    return (min(case.start, case.length, case.offset) >= 0
            and case.start + case.length <= MAX_I32 and case.offset <= case.length)


def initial(case):
    backing = bytearray(range(160, 192))
    backing[4:4 + len(case.wire)] = case.wire
    return backing


def read_reference(case, backing):
    limit = 5 if width_of(case) == 32 else 10
    begin = case.start + case.offset
    available = backing[begin:case.start + case.length]
    window = available[:limit]
    terminator = next((index for index, byte in enumerate(window) if byte < 128), None)
    if terminator is None:
        return [1, 4 if len(window) == limit else 3, 0, 0, 0]
    prefix = window[:terminator + 1]
    value = sum((byte % 128) * (128 ** index) for index, byte in enumerate(prefix))
    if value >= 1 << width_of(case): return [1, 4, 0, 0, 0]
    # Canonicality follows independent re-encoding, not a copied final-zero guard.
    if len(prefix) != len(encoded(value)): return [1, 5, 0, 0, 0]
    if case.family >= 2: value = unzigzag(value)
    return [0, 0, 0, value & MASK, case.offset + len(prefix)]


def reference(case):
    backing = initial(case)
    if not logical_bounds(case): result = [1, 1, 0, 0, 0]
    elif case.operation == 0:
        result = read_reference(case, backing)
    else:
        wire = encoded(unsigned_value(case))
        if len(wire) > case.length - case.offset:
            result = [1, 2, len(wire), 0, 0]
        else:
            at = case.start + case.offset
            assert at + len(wire) <= len(backing)
            backing[at:at + len(wire)] = wire
            result = [0, 0, 0, 0, case.offset + len(wire)]
    width = width_of(case)
    bits = case.value & ((1 << width) - 1)
    length = max(1, (unsigned_value(case).bit_length() + 6) // 7)
    scalar = [length, zigzag(signed(bits, width)), unzigzag(bits) & MASK]
    stride = MASK if case.layout == 0 else 1
    return [case.operation, case.family, case.layout] + result + scalar + [stride] + list(backing)


def cases():
    result, seen = [], set()
    profiles = ((0, 4), (2, 2), (4, 0), (1, 3))

    def append(operation, family, layout, start, length, offset, value, wire):
        case = Case(operation, family, layout, start, length, offset, value & MASK, bytes(wire))
        if case not in seen:
            seen.add(case)
            result.append(case)

    def wire_case(family, wire, count=None, profile=0, value=0, both=True):
        start, offset = profiles[profile % len(profiles)]
        count = len(wire) if count is None else count
        for layout in range(2) if both else (profile % 2,):
            append(0, family, layout, start, offset + count, offset, value, wire)

    # Exhaustive one-byte inputs for every type and both strides.
    for family in range(4):
        wire_case(family, b"", profile=family, value=MASK)
        for byte in range(256):
            wire_case(family, bytes((byte,)), profile=byte + family,
                      value=((byte + 1) * 0x9E3779B97F4A7C15) & MASK)

    # Every two-byte prefix whose first byte requests continuation, exactly once.
    # Assign types/layouts/offset profiles across the exhaustive wire domain.
    for first in range(128, 256):
        for second in range(256):
            family = (first + second) % 4
            profile = (first // 4 + second) % 4
            wire_case(family, bytes((first, second)), profile=profile,
                      value=((first << 56) ^ (second * 0x0101010101010101)) & MASK, both=False)

    # Every possible fifth/tenth byte after both zero and maximal payloads,
    # with and without a physically present following terminator.
    for family in range(4):
        limit = 5 if family in (0, 2) else 10
        for prefix_byte in (128, 255):
            for last in range(256):
                for tail in (b"", b"\x00\x7f"):
                    wire = bytes((prefix_byte,)) * (limit - 1) + bytes((last,)) + tail
                    wire_case(family, wire, profile=last + family,
                              value=((last << 48) ^ (prefix_byte << 32) ^ MASK) & MASK)

    known = (b"\x00", b"\x01", b"\x7f", b"\x80\x01", b"\xac\x02",
             b"\xff\xff\xff\xff\x0f", b"\xff" * 9 + b"\x01",
             b"\x80\x00", b"\x81\x00", b"\x80" * 10)
    for family in range(4):
        for index, wire in enumerate(known):
            wire_case(family, wire, profile=index, value=0xFEDCBA9876543210)

    rng = random.Random(SEED)
    for family in range(4):
        width = 32 if family in (0, 2) else 64
        maximum = (1 << width) - 1
        values = {0, 1, 2, 3, maximum, maximum - 1, 1 << (width - 1), (1 << (width - 1)) - 1}
        for bit in range(width):
            values.update(value for value in ((1 << bit) - 1, 1 << bit, (1 << bit) + 1) if value <= maximum)
        values.update(rng.getrandbits(width) for _ in range(128))
        for ordinal, value in enumerate(sorted(values)):
            specimen = Case(1, family, 0, 0, 0, 0, value, b"")
            wire = encoded(unsigned_value(specimen))
            # Writers check every insufficient capacity, exact capacity and spare.
            for capacity in range(len(wire) + 2):
                profile = (ordinal + capacity) % 4
                start, offset = profiles[profile]
                append(1, family, profile % 2, start, offset + capacity, offset,
                       value, b"\x55\xaa" * 6)
            # Readers see a genuine canonical wire, every truncation and tails.
            for available in range(len(wire) + 3):
                wire_case(family, wire + b"\x00\xff", count=available,
                          profile=ordinal + available, value=value ^ 0xDEADBEEF01234567,
                          both=False)

    invalid = ((-1, 0, 0), (MIN_I32, 1, 0), (2, -1, 0), (2, MIN_I32, 0),
               (MAX_I32, 1, 0), (MAX_I32 - 1, 2, 0), (1, MAX_I32, 0),
               (2, 3, -1), (2, 3, MIN_I32), (2, 3, 4), (2, 3, MAX_I32),
               (MAX_I32, 0, 0), (2, 0, 0))
    for family in range(4):
        for operation in range(2):
            for layout in range(2):
                for start, length, offset in invalid:
                    append(operation, family, layout, start, length, offset, MASK, b"\x80\x00")
    assert len(result) == 61144
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.operation in (0, 1) and case.family in range(4) and case.layout in (0, 1)
        assert len(case.wire) <= 12 and 0 <= case.value <= MASK
        assert all(MIN_I32 <= value <= MAX_I32 for value in (case.start, case.length, case.offset))
        if logical_bounds(case) and case.offset < case.length:
            assert case.start + case.length <= 32
        fields = (case.operation, case.family, case.layout, case.start, case.length,
                  case.offset, case.value, len(case.wire)) + tuple(case.wire)
        data += struct.pack("<" + "Q" * len(fields), *(word & MASK for word in fields))
    return data


def encode(values):
    data = bytearray()
    for case in values:
        data += struct.pack("<44Q", *reference(case))
    return data


def verify(actual, values):
    assert len(actual) == len(values) * WORDS * 8, (len(actual), len(values) * WORDS * 8)
    for index, case in enumerate(values):
        expected = reference(case)
        observed = list(struct.unpack_from("<44Q", actual, index * WORDS * 8))
        stride = signed(observed[11], 64)
        assert stride == 1 if case.layout else stride < 0, (f"seed={SEED:#x}", index, case, "stride", stride)
        expected[11] = observed[11]
        assert observed == expected, (f"seed={SEED:#x}", index, case, observed, expected)


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::37]), values[::37])
    assert encoded(0) == b"\x00" and encoded(300) == b"\xac\x02"
    assert encoded((1 << 64) - 1) == b"\xff" * 9 + b"\x01"
    assert [zigzag(value) for value in (-2, -1, 0, 1, 2)] == [3, 1, 0, 2, 4]
    assert zigzag(-(1 << 63)) == MASK and unzigzag(MASK) == -(1 << 63)
    def sample(**changes):
        fields = dict(operation=0, family=1, layout=0, start=2, length=4,
                      offset=2, value=MASK, wire=b"\xac\x02")
        fields.update(changes)
        return Case(**fields)
    read = sample()
    assert reference(read)[3:11] == [0, 0, 0, 300, 4, 10, 1, (-(1 << 63)) & MASK]
    short = sample(operation=1, length=3)
    assert reference(short)[3:8] == [1, 2, 10, 0, 0]
    assert reference(short)[12:] == list(initial(short))
    write = sample(operation=1, family=3, value=MASK, length=3)
    assert reference(write)[3:11] == [0, 0, 0, 0, 3, 1, 1, (-(1 << 63)) & MASK]
    assert reference(write)[16:18] == [1, 2]
    truncated = sample(length=3)
    assert reference(truncated)[3:8] == [1, 3, 0, 0, 0]
    overflow = sample(family=0, start=4, offset=0, length=5, wire=b"\x80" * 5)
    assert reference(overflow)[3:8] == [1, 4, 0, 0, 0]
    noncanonical = sample(family=0, start=4, offset=0, length=5, wire=b"\x80" * 4 + b"\x00")
    assert reference(noncanonical)[3:8] == [1, 5, 0, 0, 0]
    last_overflow = sample(family=0, start=4, offset=0, length=5, wire=b"\x80" * 4 + b"\x10")
    assert reference(last_overflow)[3:8] == [1, 4, 0, 0, 0]
    bounds = sample(operation=1, start=-1, length=0)
    assert reference(bounds)[3:8] == [1, 1, 0, 0, 0]
    signed_min = sample(operation=1, family=2, value=1 << 31, length=7)
    assert reference(signed_min)[16:21] == [255, 255, 255, 255, 15]
    mutations = ((read, 6, 301), (read, 7, 6), (short, 5, 1), (short, 16, 0),
                 (overflow, 4, 5), (bounds, 4, 2), (signed_min, 9, 0), (write, 12, 0))
    for case, word, replacement in mutations:
        bad = encode([case])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted deliberate corruption", case, word))
    outcomes, types, operations = Counter(), Counter(), Counter()
    for case in values:
        words = reference(case)
        outcomes[(words[3], words[4])] += 1
        types[case.family] += 1
        operations[case.operation] += 1
    assert all(outcomes[(1, error)] for error in range(1, 6))
    print(f"native-varint CPU cases={len(values)} widths=4 layouts=2 seed={SEED:#x} corruption-controls=8")
    print(f"native-varint families={dict(sorted(types.items()))} operations={dict(sorted(operations.items()))} outcomes={dict(sorted(outcomes.items()))}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    verify(process.stdout, values)
    print(f"native-varint cases={len(values)} widths=4 layouts=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
