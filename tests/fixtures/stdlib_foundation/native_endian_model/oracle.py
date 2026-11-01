"""Independent integer-bit/byte model for all 24 native endian additions.

No Python floating-point values are constructed. IEEE signaling/quiet payloads
remain integer words through generation, expected serialization and comparison.
Read bytes and unrelated write values exercise each direction separately.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xE0D1A0261030
MASK = (1 << 64) - 1
MAX_I32 = (1 << 31) - 1
MIN_I32 = -(1 << 31)
WIDTHS = (8, 2, 4, 8, 4, 8)
NAMES = ("u64", "i16", "i32", "i64", "f32", "f64")
WORDS = 69


@dataclass(frozen=True)
class Case:
    kind: int
    order: int
    layout: int
    length: int
    offset: int
    reading: int
    writing: int
    fallback: int
    identity: int


def integer_patterns(bits):
    mask, sign = (1 << bits) - 1, 1 << (bits - 1)
    values = [0, 1, 2, 127, 128, 255, 256, sign - 1, sign, sign + 1,
              mask - 1, mask, int.from_bytes(b"\x55" * (bits // 8), "big"),
              int.from_bytes(b"\xaa" * (bits // 8), "big"),
              0x0123456789ABCDEF & mask, 0xFEDCBA9876543210 & mask]
    values += [1 << bit for bit in range(bits)]
    values += [mask ^ (1 << bit) for bit in range(bits)]
    return tuple(dict.fromkeys(value & mask for value in values))


def float_patterns(bits):
    fraction = 23 if bits == 32 else 52
    exponent_bits = bits - fraction - 1
    exponent = ((1 << exponent_bits) - 1) << fraction
    quiet = 1 << (fraction - 1)
    one = ((1 << (exponent_bits - 1)) - 1) << fraction
    magnitudes = (0, 1, 2, (1 << fraction) - 1, 1 << fraction,
                  (1 << fraction) + 1, one - 1, one, one + 1,
                  exponent - 2, exponent - 1, exponent,
                  exponent | 1, exponent | 2, exponent | (quiet - 1),
                  exponent | quiet, exponent | quiet | 1, exponent | quiet | 2,
                  exponent | ((1 << fraction) - 1), exponent | 0x12345,
                  exponent | quiet | 0x12345)
    return tuple(dict.fromkeys(value | sign for value in magnitudes for sign in (0, 1 << (bits - 1))))


def invalid_shapes(width):
    return ((-1, 0), (MIN_I32, 0), (0, 0), (width - 1, 0),
            (32, -1), (32, MIN_I32), (32, 33 - width),
            (MAX_I32, MAX_I32 - width + 1), (MAX_I32, MAX_I32), (width, 1))


def admitted(case):
    width = WIDTHS[case.kind]
    return case.length >= width and case.offset >= 0 and case.offset <= case.length - width


def reading_bytes(case):
    result = bytearray((case.identity * 7 + index * 29 + 193) & 255 for index in range(32))
    width = WIDTHS[case.kind]
    # Invalid cases still carry a distinct field in backed, safe storage; no
    # physically invalid index is used while creating their input bytes.
    at = case.offset if admitted(case) else 4
    result[at:at + width] = case.reading.to_bytes(width, "big" if case.order == 0 else "little")
    return result


def reference(case):
    width = WIDTHS[case.kind]
    byte_order = "big" if case.order == 0 else "little"
    source = reading_bytes(case)
    destination = bytearray((case.identity * 19 + index * 23 + 11) & 255 for index in range(32))
    valid = admitted(case)
    if valid:
        observed = int.from_bytes(source[case.offset:case.offset + width], byte_order)
        assert observed == case.reading
        destination[case.offset:case.offset + width] = case.writing.to_bytes(width, byte_order)
    else:
        observed = case.fallback
    return [case.kind, case.order, case.layout, observed, int(valid), *source, *destination]


def cases():
    result = []
    rng = random.Random(SEED)

    def append(kind, length, offset, reading, writing, fallback):
        for order in range(2):
            for layout in range(2):
                result.append(Case(kind, order, layout, length, offset,
                                   reading, writing, fallback, len(result) + 1))

    for kind, width in enumerate(WIDTHS):
        bits = width * 8
        mask, sign = (1 << bits) - 1, 1 << (bits - 1)
        patterns = float_patterns(bits) if kind >= 4 else integer_patterns(bits)
        for index, value in enumerate(patterns):
            for length, offset in ((width, 0), (32, 3), (width + 5, 5), (32, 32 - width)):
                append(kind, length, offset, value, patterns[(index + 1) % len(patterns)],
                       patterns[(index - 1) % len(patterns)])
        fallbacks = (patterns if kind >= 4 else
                     tuple(dict.fromkeys((0, 1, sign - 1, sign, sign + 1, mask - 1, mask,
                                          int.from_bytes(b"\xaa" * width, "big")))))
        for index, fallback in enumerate(fallbacks):
            for length, offset in invalid_shapes(width):
                append(kind, length, offset, patterns[(index * 3) % len(patterns)],
                       patterns[(index * 5 + 1) % len(patterns)], fallback)
        for index in range(160):
            reading, writing, fallback = (rng.getrandbits(bits) for _ in range(3))
            if kind >= 4 and index % 4 == 0:
                fraction = 23 if bits == 32 else 52
                exponent = ((1 << (bits - fraction - 1)) - 1) << fraction
                reading, writing, fallback = (exponent | (rng.getrandbits(fraction) or 1) |
                    (rng.randrange(2) << (bits - 1)) for _ in range(3))
            if index % 5 == 0:
                length, offset = rng.choice(invalid_shapes(width))
            else:
                length = rng.randrange(width, 33)
                offset = rng.randrange(length - width + 1)
            append(kind, length, offset, reading, writing, fallback)
    return result


def packet(values):
    result = bytearray()
    for case in values:
        width = WIDTHS[case.kind]
        assert 0 <= case.kind < 6 and case.order in (0, 1) and case.layout in (0, 1)
        assert MIN_I32 <= case.length <= MAX_I32 and MIN_I32 <= case.offset <= MAX_I32
        assert all(0 <= value < 1 << (width * 8) for value in (case.reading, case.writing, case.fallback))
        if admitted(case): assert case.offset + width <= 32
        header = (case.kind, case.order, case.layout, case.length, case.offset,
                  case.writing, case.fallback, case.identity)
        result += struct.pack("<8Q", *(word & MASK for word in header))
        result += reading_bytes(case)
    return result


def encode(values):
    result = bytearray()
    for case in values: result += struct.pack("<69Q", *reference(case))
    return result


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        want = reference(case)
        assert offset + WORDS * 8 <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        got = struct.unpack_from("<69Q", actual, offset)
        assert list(got) == want, (f"seed={SEED:#x}", index, case, got, want)
        offset += WORDS * 8
    assert offset == len(actual), (offset, len(actual), "extra output")


def float_category(value, bits):
    fraction = 23 if bits == 32 else 52
    exponent_mask = (1 << (bits - fraction - 1)) - 1
    exponent = (value >> fraction) & exponent_mask
    payload = value & ((1 << fraction) - 1)
    if not exponent: category = "zero" if not payload else "subnormal"
    elif exponent != exponent_mask: category = "normal"
    elif not payload: category = "infinity"
    else: category = "quiet_nan" if payload & (1 << (fraction - 1)) else "signaling_nan"
    return ("negative_" if value >> (bits - 1) else "positive_") + category


def statistics(values):
    shapes, types, directions = Counter(), Counter(), Counter()
    floats = {name: Counter() for name in ("read", "write", "invalid_fallback")}
    for case in values:
        valid = admitted(case)
        shapes["valid" if valid else "invalid"] += 1
        types[NAMES[case.kind]] += 1
        for direction in ("read", "write"): directions[(case.kind, case.order, direction)] += 1
        if case.kind >= 4:
            bits = WIDTHS[case.kind] * 8
            if valid:
                floats["read"][float_category(case.reading, bits)] += 1
                floats["write"][float_category(case.writing, bits)] += 1
            else:
                floats["invalid_fallback"][float_category(case.fallback, bits)] += 1
    return shapes, types, directions, floats


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::41]), values[::41])
    vector = Case(0, 0, 0, 32, 3, 0xFEDCBA9876543210, 0x0123456789ABCDEF, MASK, 1)
    want = reference(vector)
    assert want[3:5] == [0xFEDCBA9876543210, 1]
    assert want[40:48] == [1, 35, 69, 103, 137, 171, 205, 239]
    signed = reference(Case(1, 1, 1, 5, 3, 0x8000, 0xFFFF, 0x7FFF, 2))
    assert signed[3:5] == [0x8000, 1] and signed[40:42] == [255, 255]
    invalid = Case(4, 0, 1, 3, 0, 0x7FC12345, 0xFFC12345, 0x7F800001, 3)
    assert reference(invalid)[3:5] == [0x7F800001, 0]
    double = reference(Case(5, 0, 0, 8, 0, 0xFFF0000000000001, 0xFFF8000000012345, 0, 4))
    assert double[3] == 0xFFF0000000000001
    assert double[37:45] == [255, 248, 0, 0, 0, 1, 35, 69]
    mutations = ((vector, 3, 0x76543210), (vector, 40, 239),
                 (vector, 37, 0), (vector, 8, 0), (vector, 4, 0),
                 (invalid, 3, 0x7FC00001))
    for case, word, replacement in mutations:
        wrong = encode([case])
        struct.pack_into("<Q", wrong, word * 8, replacement)
        try:
            verify(wrong, [case])
        except AssertionError:
            pass
        else:
            raise AssertionError(("accepted deliberate corruption", case, word))
    shapes, types, directions, floats = statistics(values)
    assert len(directions) == 24
    categories = {sign + category for sign in ("positive_", "negative_")
                  for category in ("zero", "subnormal", "normal", "infinity", "quiet_nan", "signaling_nan")}
    assert all(set(counts) == categories for counts in floats.values())
    for kind in (4, 5):
        by_width = statistics([case for case in values if case.kind == kind])[3]
        assert all(set(counts) == categories for counts in by_width.values())
    print(f"native-endian CPU cases={len(values)} functions={len(directions)} "
          f"seed={SEED:#x} corruption-controls=6")
    print(f"native-endian shapes={dict(shapes)} types={dict(types)}")
    print(f"native-endian float-categories={{{', '.join(f'{name!r}: {dict(sorted(counts.items()))!r}' for name, counts in floats.items())}}}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "usage: oracle.py <model-executable> | controls"
    values = cases()
    output = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70)
    assert output.returncode == 0, (output.returncode, output.stderr, len(output.stdout))
    assert not output.stderr, output.stderr
    verify(output.stdout, values)
    print(f"native-endian cases={len(values)} functions=24 layouts=2 orders=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
