"""Independent strict profile grammar plus host canonical Base64 wire anchor."""
from __future__ import annotations

import base64
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xBA5E640261102
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
POOL, WORDS = 80, 170
STANDARD = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
URL = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"


@dataclass(frozen=True)
class Case:
    operation: int
    profile: int
    layout: int
    alias: bool
    input_start: int
    input_length: int
    output_start: int
    capacity: int
    argument: int
    payload_start: int
    payload: bytes


class InvalidWire(Exception):
    def __init__(self, code, payload=0): self.code, self.payload = code, payload


def padded(profile): return profile in (0, 2)


def canonical(data, profile):
    result = base64.b64encode(data, altchars=b"-_" if profile >= 2 else None)
    return result if padded(profile) else result.rstrip(b"=")


def encoded_count(length, profile):
    if length < 0: raise InvalidWire(1)
    count = 4 * ((length + 2) // 3) if padded(profile) else (8 * length + 5) // 6
    if count > MAX_I32: raise InvalidWire(2)
    return count


def strict_decode(wire, profile):
    size = len(wire)
    if (size % 4 != 0 if padded(profile) else size % 4 == 1): raise InvalidWire(3)
    alphabet = frozenset(URL if profile >= 2 else STANDARD)

    def symbol(index):
        if wire[index] == 61: raise InvalidWire(5, index)
        if wire[index] not in alphabet: raise InvalidWire(4, index)

    # A grammar walk establishes which symbols may be padding. Host decoding
    # does not decide profile admission or the first indexed error.
    for begin in range(0, size, 4):
        end = min(begin + 4, size)
        if padded(profile) and end == size:
            symbol(begin)
            symbol(begin + 1)
            if wire[begin + 2] == 61:
                if wire[begin + 3] != 61: raise InvalidWire(5, begin + 2)
            else:
                symbol(begin + 2)
                if wire[begin + 3] != 61: symbol(begin + 3)
        else:
            for index in range(begin, end): symbol(index)
    admitted = wire + b"=" * ((-size) % 4) if not padded(profile) else wire
    decoded = base64.b64decode(admitted, altchars=b"-_" if profile >= 2 else None, validate=True)
    if canonical(decoded, profile) != wire:
        if padded(profile):
            assert wire.endswith(b"=")
            index = size - 3 if wire.endswith(b"==") else size - 2
        else:
            assert size % 4 in (2, 3)
            index = size - 1
        raise InvalidWire(6, index)
    return decoded


def bounds(start, length):
    return start >= 0 and length >= 0 and start + length <= MAX_I32


def initial(case):
    source = bytearray(range(64, 144))
    source[case.payload_start:case.payload_start + len(case.payload)] = case.payload
    target = source if case.alias else bytearray(range(160, 240))
    return source, target


def reference(case):
    source, target = initial(case)
    try:
        if case.operation == 0:
            count = encoded_count(case.argument, case.profile)
        else:
            if not bounds(case.input_start, case.input_length): raise InvalidWire(1)
            if case.operation in (2, 3) and not bounds(case.output_start, case.capacity): raise InvalidWire(1)
            if case.operation == 2:
                count = encoded_count(case.input_length, case.profile)
                if count > case.capacity: raise InvalidWire(7, count)
                wire = bytes(source[case.input_start:case.input_start + case.input_length])
                converted = canonical(wire, case.profile)
                assert len(converted) == count
            else:
                wire = bytes(source[case.input_start:case.input_start + case.input_length])
                converted = strict_decode(wire, case.profile)
                count = len(converted)
                if case.operation == 3 and count > case.capacity: raise InvalidWire(7, count)
            if case.operation in (2, 3) and count:
                assert case.output_start + count <= POOL
                target[case.output_start:case.output_start + count] = converted
        result = [0, 0, 0, count]
    except InvalidWire as error:
        result = [1, error.code, error.payload, 0]
    source_stride = 1 if case.layout & 1 else MASK
    target_stride = source_stride if case.alias else (1 if case.layout & 2 else MASK)
    return [case.operation, case.profile, case.layout, int(case.alias)] + result + [source_stride, target_stride] + list(source) + list(target)


def cases():
    result, seen = [], set()
    def append(operation, profile, layout, payload, capacity=0, input_start=4,
               output_start=7, alias=False, input_length=None, argument=0, payload_start=None):
        case = Case(operation, profile, layout, alias, input_start,
                    len(payload) if input_length is None else input_length,
                    output_start, capacity, argument,
                    input_start if payload_start is None else payload_start, bytes(payload))
        if case not in seen:
            seen.add(case)
            result.append(case)

    rng = random.Random(SEED)
    binaries = {b"", b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar", b"\xfb\xff\xef"}
    for length in range(49):
        binaries.update((bytes(range(length)), bytes(length), b"\xff" * length,
                         bytes(rng.randrange(256) for _ in range(length))))
    for profile in range(4):
        for data in sorted(binaries, key=lambda value: (len(value), value)):
            wire = canonical(data, profile)
            for layout in range(4):
                istart = (2, 4, 7, 3)[layout]
                ostart = (5, 1, 3, 7)[(layout + profile) % 4]
                for capacity in sorted({0, max(0, len(wire) - 1), len(wire), len(wire) + 1}):
                    append(2, profile, layout, data, capacity, istart, ostart)
                append(1, profile, layout, wire, input_start=istart, output_start=ostart)
                for capacity in sorted({0, max(0, len(data) - 1), len(data), len(data) + 1}):
                    append(3, profile, layout, wire, capacity, istart, ostart)

    # Exhaust every possible byte substitution in tails, complete groups and
    # alphabet-sensitive anchors. Every mutation checks decode_into with cap0.
    for profile in range(4):
        for raw in (b"f", b"fo", b"foo", b"\xfb\xff"):
            wire = canonical(raw, profile)
            for position in range(len(wire)):
                for byte in range(256):
                    mutated = wire[:position] + bytes((byte,)) + wire[position + 1:]
                    layout = (position + byte) % 4
                    append(3, profile, layout, mutated, 0, input_start=3, output_start=5)
                    if byte % 8 == 0 or byte in (0, 9, 10, 13, 32, 43, 45, 47, 61, 95, 127, 255):
                        append(1, profile, (layout + 1) % 4, mutated, input_start=7)
            for position in range(len(wire) + 1):
                for byte in (0, 9, 10, 13, 32, 43, 45, 47, 61, 95, 128, 255):
                    changed = wire[:position] + bytes((byte,)) + wire[position:]
                    append(3, profile, position % 4, changed, 0, input_start=4)
                changed = wire[:position] + wire[position + 1:]
                append(1, profile, position % 4, changed, input_start=2)

    precedence = (b"!!!!", b"Z", b"Zh==", b"Zh=!", b"Zg=A", b"Zg=\xff",
                  b"Zm9=", b"Zm!=", b"=AAA", b"A=AA", b"AA=A", b"AA=!",
                  b"Zg==AAAA", b"AAAAZg==", b"AAAAZh==", b"AAAAZm9=",
                  b"Zh", b"Zm9", b"Zg=", b"Zg==", b"-w==", b"/w==")
    for profile in range(4):
        for index, wire in enumerate(precedence):
            for operation in (1, 3):
                for capacity in (0, 16):
                    append(operation, profile, index % 4, wire, capacity, 2, 5)

    # Same-first-address aliases, both actual byte stride directions. Thorough
    # physical/other-overlap testing belongs to the independent boundary gate.
    for profile in range(4):
        for length in range(49):
            data = bytes(range(length))
            wire = canonical(data, profile)
            for layout in (0, 3):
                for capacity in sorted({max(0, len(wire) - 1), len(wire)}):
                    append(2, profile, layout, data, capacity, 4, 4, True)
                for capacity in sorted({max(0, len(data) - 1), len(data)}):
                    append(3, profile, layout, wire, capacity, 4, 4, True)
                for malformed in (b"Zh==", b"Zg=!", b"AAAAZh==", b"Zm9", b"Zg=", b"!!!!"):
                    append(3, profile, layout, malformed, 16, 4, 4, True)

    metadata = ((-1, 0, 4, 0), (MIN_I32, 1, 4, 0), (4, -1, 4, 0),
                (MAX_I32, 1, 4, 0), (MAX_I32 - 1, 2, 4, 0), (1, MAX_I32, 4, 0),
                (4, 4, -1, 0), (4, 4, 4, -1), (4, 4, MAX_I32, 1),
                (4, 4, MAX_I32 - 1, 2), (4, 0, MAX_I32, 0),
                (MAX_I32, 0, 4, 0), (4, 0, 4, 0))
    for profile in range(4):
        for operation in range(4):
            for layout in range(4):
                for istart, ilen, ostart, capacity in metadata:
                    append(operation, profile, layout, b"!!!!", capacity, istart, ostart,
                           input_length=ilen, payload_start=4, argument=1)
        length_values = {MIN_I32, -1, 0, 1, 2, 3, 4, 47, 48, 49,
                         (1 << 30) - 1, 1 << 30, MAX_I32}
        for threshold in (1610612733, 1610612735):
            length_values.update(threshold + delta for delta in (-2, -1, 0, 1, 2))
        for length in sorted(length_values):
            append(0, profile, 0, b"", input_start=4, argument=length)
    assert len(result) == 48995
    return result


def packet(values):
    data = bytearray()
    for index, case in enumerate(values):
        assert case.operation in range(4) and case.profile in range(4) and case.layout in range(4)
        assert len(case.payload) <= 68 and 0 <= case.payload_start <= POOL - len(case.payload)
        assert all(MIN_I32 <= value <= MAX_I32 for value in
                   (case.input_start, case.input_length, case.output_start, case.capacity, case.argument))
        if case.operation != 0 and bounds(case.input_start, case.input_length) and case.input_length:
            assert case.input_start + case.input_length <= POOL
        if case.operation in (2, 3) and bounds(case.output_start, case.capacity) and case.capacity:
            assert case.output_start + case.capacity <= POOL
        if case.alias:
            assert case.layout in (0, 3) and case.input_start == case.output_start
        fields = (case.operation, case.profile, case.layout, int(case.alias), case.input_start,
                  case.input_length, case.output_start, case.capacity, case.argument,
                  case.payload_start, len(case.payload), index) + tuple(case.payload)
        data += struct.pack("<" + "Q" * len(fields), *(word & MASK for word in fields))
    return data


def encode(values):
    data = bytearray()
    for case in values:
        data += struct.pack("<170Q", *reference(case))
    return data


def verify(actual, values):
    assert len(actual) == len(values) * WORDS * 8, (len(actual), len(values) * WORDS * 8)
    for index, case in enumerate(values):
        expected = reference(case)
        observed = list(struct.unpack_from("<170Q", actual, index * WORDS * 8))
        for word, packed in ((8, bool(case.layout & 1)),
                             (9, bool(case.layout & (1 if case.alias else 2)))):
            stride = observed[word] - (1 << 64) if observed[word] >= (1 << 63) else observed[word]
            assert stride == 1 if packed else stride < 0, (f"seed={SEED:#x}", index, case, "stride", word, stride)
            expected[word] = observed[word]
        if case.alias: assert observed[8] == observed[9], (index, case, "same-base stride")
        assert observed == expected, (f"seed={SEED:#x}", index, case, observed, expected)


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::41]), values[::41])
    anchors = ((b"", b""), (b"f", b"Zg=="), (b"fo", b"Zm8="), (b"foo", b"Zm9v"),
               (b"foob", b"Zm9vYg=="), (b"fooba", b"Zm9vYmE="), (b"foobar", b"Zm9vYmFy"))
    assert all(canonical(raw, 0) == wire and strict_decode(wire, 0) == raw for raw, wire in anchors)
    assert canonical(b"\xfb\xff", 0) == b"+/8=" and canonical(b"\xfb\xff", 3) == b"-_8"
    for profile in range(4):
        assert encoded_count(1610612733, profile) == 2147483644
        if padded(profile):
            try: encoded_count(1610612734, profile)
            except InvalidWire as error: assert error.code == 2
            else: raise AssertionError("missing padded overflow")
        else: assert encoded_count(1610612735, profile) == MAX_I32
    def sample(**changes):
        fields = dict(operation=3, profile=0, layout=0, alias=False, input_start=4,
                      input_length=4, output_start=7, capacity=1, argument=0,
                      payload_start=4, payload=b"Zg==")
        fields.update(changes)
        return Case(**fields)
    good = sample()
    assert reference(good)[4:8] == [0, 0, 0, 1]
    assert reference(good)[90 + 7] == 102
    short = sample(capacity=0)
    assert reference(short)[4:8] == [1, 7, 1, 0]
    bad_tail = sample(payload=b"Zh==", capacity=0)
    assert reference(bad_tail)[4:8] == [1, 6, 1, 0]
    shape = sample(payload=b"Zh=!", capacity=0)
    assert reference(shape)[4:8] == [1, 5, 2, 0]
    late = sample(payload=b"AAAAZh==", input_length=8, capacity=0)
    assert reference(late)[4:8] == [1, 6, 5, 0]
    invalid_output = sample(payload=b"!", input_length=1, output_start=-1, capacity=0)
    assert reference(invalid_output)[4:8] == [1, 1, 0, 0]
    alias = sample(alias=True, output_start=4)
    assert reference(alias)[14] == 102 and reference(alias)[94] == 102
    encoder = sample(operation=2, payload=b"f", input_length=1, capacity=4)
    assert reference(encoder)[97:101] == list(b"Zg==")
    alias_encode = sample(operation=2, alias=True, output_start=4, payload=b"f", input_length=1, capacity=4)
    assert reference(alias_encode)[14:18] == list(b"Zg==")
    corruptions = ((good, 7, 2), (good, 97, 0), (short, 6, 0),
                   (short, 90, 0), (bad_tail, 5, 7), (shape, 5, 4),
                   (late, 6, 1), (alias_encode, 14, 0))
    for case, word, replacement in corruptions:
        bad = encode([case])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted deliberate corruption", case, word))
    operations, profiles, outcomes = Counter(), Counter(), Counter()
    aliases = 0
    for case in values:
        words = reference(case)
        operations[case.operation] += 1
        profiles[case.profile] += 1
        outcomes[(words[4], words[5])] += 1
        aliases += case.alias
    assert all(outcomes[(1, error)] for error in range(1, 8))
    print(f"checked-base64 CPU cases={len(values)} profiles=4 apis=4 layouts=4 seed={SEED:#x} corruption-controls=8 aliases={aliases}")
    print(f"checked-base64 operations={dict(sorted(operations.items()))} profiles={dict(sorted(profiles.items()))} outcomes={dict(sorted(outcomes.items()))}")


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
    print(f"checked-base64 cases={len(values)} profiles=4 apis=4 layouts=4 seed={SEED:#x}")


if __name__ == "__main__":
    main()
