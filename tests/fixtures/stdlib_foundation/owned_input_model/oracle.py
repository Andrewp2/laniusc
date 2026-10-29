"""Independent bounded reader effects and strict UTF-8 ownership observations.

No allocator/growth implementation is modeled. Python is test infrastructure.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import itertools
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0x0A11C0261103
MASK = (1 << 64) - 1
MIN_I32, MAX_I32 = -(1 << 31), (1 << 31) - 1
IO_ERRORS = {-1: (7, 0), -2: (8, 0), -3: (10, -123), -8: (1, 0),
             -9: (2, 0), -10: (3, 0), -11: (4, 0), -12: (5, 0),
             -13: (6, 0), -14: (9, 0), -15: (10, MAX_I32),
             -16: (10, MIN_I32), -17: (10, 0)}


@dataclass(frozen=True)
class Case:
    text: bool
    layout: int
    maximum: int
    quota: int
    recovery_maximum: int
    recovery_quota: int
    script: tuple
    data: bytes


class Provider:
    def __init__(self, case):
        self.case = case
        self.cursor = self.index = 0
        self.trace = []

    def read(self, requested):
        assert 1 <= requested <= 1024
        event = 1024
        if self.index < len(self.case.script):
            event = self.case.script[self.index]
            self.index += 1
        self.trace.append((requested, event, self.cursor))
        if event in (-4, -5, -6, -7): return (4, 0), b""
        if event < 0: return IO_ERRORS[event], b""
        # Only bytes that actually exist and fit the admitted request can move.
        chunk = self.case.data[self.cursor:self.cursor + min(event, requested)]
        self.cursor += len(chunk)
        return None, chunk


def collect(provider, maximum, quota, text):
    prefix = bytearray()
    before = len(provider.trace)
    cause = detail = payload = 0
    extra = None
    if maximum < 0:
        cause = 1
    else:
        while True:
            if len(provider.trace) - before == quota:
                cause = 2
                break
            probe = len(prefix) == maximum
            request = 1 if probe else min(1024, maximum - len(prefix))
            error, chunk = provider.read(request)
            if error:
                if error[0] == 7: continue
                cause, (detail, payload) = 4, error
                break
            if not chunk:
                if text:
                    try: bytes(prefix).decode("utf-8", errors="strict")
                    except UnicodeDecodeError as error:
                        cause, detail, payload = 6, 1, error.start
                break
            if probe:
                assert len(chunk) == 1
                extra, cause = chunk[0], 3
                break
            prefix.extend(chunk)
    observed = len(provider.trace) - before
    header = [int(bool(cause)), cause, detail, payload, len(prefix), observed if cause else 0,
              int(extra is not None), 0 if extra is None else extra, observed,
              len(provider.trace), provider.cursor, provider.index]
    return header + list(prefix) + [word for call in provider.trace for word in call]


def observations(case):
    provider = Provider(case)
    first = collect(provider, case.maximum, case.quota, case.text)
    second = collect(provider, case.recovery_maximum, case.recovery_quota, False)
    return first, second


def reference(case):
    return [word & MASK for observation in observations(case) for word in observation]


def cases():
    result, seen = [], set()
    def append(data, maximum, quota, script=(), text=None,
               recovery_maximum=16, recovery_quota=8):
        for mode in (False, True) if text is None else (text,):
            for layout in range(2):
                case = Case(mode, layout, maximum, quota, recovery_maximum,
                            recovery_quota, tuple(script), bytes(data))
                if case not in seen:
                    seen.add(case)
                    result.append(case)

    specimens = (b"", b"abc", b"a\x00\r\nZ", b"\xffX", b"A\xc2\xa2B",
                 b"\xe2\x82\xac", b"\xf0\x9f\x98\x80", b"ok\xed\xa0\x80tail")
    alphabet = (1, 2, 0, -1, -2, -3, -4, -5)
    scripts = [script for size in range(4) for script in itertools.product(alphabet, repeat=size)]
    assert len(scripts) == 585
    for index, script in enumerate(scripts):
        data = specimens[index % len(specimens)]
        for quota in (0, 1, 2, 4):
            append(data, index % 9, quota, script)

    for event in range(-17, 0):
        for prefix in ((), (2,)):
            for quota in (0, 1, 2, 3, MASK):
                append(b"ab\xff\x00XYZ", 8, quota, prefix + (event, 1024))

    for data in (b"", b"abc\x00def", b"\xff", b"\xffX"):
        for maximum in (MIN_I32, -1, 0, 1, 7, 8, 9, MAX_I32):
            for quota in (0, 1, 2, 3, MASK): append(data, maximum, quota)

    # Every single byte: strict text expectations are independent of the codec.
    for byte in range(256):
        for maximum in (1, 2): append(bytes((byte,)), maximum, MASK, (1, 1), text=True)
        append(bytes((byte,)), 2, MASK, (1, 1), text=False)

    # All second-byte possibilities around UTF-8's constrained lead classes.
    for lead, suffix in ((0xC2, b""), (0xDF, b""), (0xE0, b"\x80"),
                         (0xED, b"\x80"), (0xF0, b"\x80\x80"), (0xF4, b"\x80\x80")):
        for second in range(256):
            data = b"ok\x00" + bytes((lead, second)) + suffix + b"tail"
            append(data, len(data), MASK, (1,) * min(16, len(data) + 1), text=True)

    valid = ("\x00", "\x7f", "\u0080", "\u07ff", "\u0800", "\ud7ff", "\ue000", "\uffff",
             "\U00010000", "\U0010ffff", "A¢€😀\r\n\x00B")
    malformed = (b"\xc0\xaf", b"\xc1\xbf", b"\x80", b"\xbf", b"\xed\xa0\x80",
                 b"\xe0\x80\x80", b"\xf0\x80\x80\x80", b"\xf4\x90\x80\x80", b"\xf5\x80\x80\x80",
                 b"\xc2", b"\xe2\x82", b"\xf0\x9f\x98", b"\xc2A", b"\xe2A\xac", b"\xe2\x82A", b"\xf0\x9fA\x80")
    for data in tuple(text.encode("utf-8") for text in valid) + tuple(b"ok\x00" + wire + b"tail" for wire in malformed):
        for cut in range(1, len(data) + 1):
            for maximum in (len(data), len(data) + 1): append(data, maximum, MASK, (cut,), text=True)
        append(data, len(data) + 1, MASK, (1,) * min(16, len(data)), text=True)

    # Exact scratch/request boundaries and caps with real bytes around them.
    for length in (1023, 1024, 1025, 2047, 2048, 2049, 2052):
        for data in (b"a" * length, bytes(index % 256 for index in range(length))):
            for maximum in (length - 1, length, length + 1):
                for quota in (1, 2, 3, 4, MASK):
                    append(data, maximum, quota, (1024, 1024),
                           recovery_maximum=2052, recovery_quota=MASK)

    rng = random.Random(SEED)
    for _ in range(300):
        data = bytes(rng.choice((0, 10, 13, 65, 128, 194, 224, 240, 255)) for _ in range(rng.randrange(25)))
        maximum = rng.choice((-1, 0, 1, len(data), len(data) + 1, rng.randrange(25)))
        quota = rng.choice((0, 1, 2, 3, 4, 8, MASK))
        script = tuple(rng.choice(tuple(range(-17, 1)) + (1, 2, 4, 1024)) for _ in range(rng.randrange(17)))
        append(data, maximum, quota, script, text=bool(rng.randrange(2)),
               recovery_maximum=rng.randrange(25), recovery_quota=rng.choice((0, 1, 2, 4, 8, MASK)))
    assert len(result) == 17542
    return result


def packet(values):
    data = bytearray()
    for case in values:
        assert case.layout in (0, 1) and len(case.script) <= 16 and len(case.data) <= 2052
        assert MIN_I32 <= case.maximum <= MAX_I32 and MIN_I32 <= case.recovery_maximum <= MAX_I32
        assert 0 <= case.quota <= MASK and 0 <= case.recovery_quota <= MASK
        assert all(-17 <= event <= 1024 for event in case.script)
        fields = (int(case.text), case.layout, case.maximum, case.quota,
                  case.recovery_maximum, case.recovery_quota, len(case.script), len(case.data))
        fields += case.script + tuple(case.data)
        data += struct.pack("<" + "Q" * len(fields), *(word & MASK for word in fields))
    return data


def encode(values):
    data = bytearray()
    for case in values:
        words = reference(case)
        data += struct.pack("<" + "Q" * len(words), *words)
    return data


def verify(actual, values):
    offset = 0
    for index, case in enumerate(values):
        expected = reference(case)
        size = len(expected) * 8
        assert offset + size <= len(actual), (f"seed={SEED:#x}", index, case, "truncated")
        observed = struct.unpack_from("<" + "Q" * len(expected), actual, offset)
        assert list(observed) == expected, (f"seed={SEED:#x}", index, case, observed, expected)
        offset += size
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    assert packet(values)
    verify(encode(values[::41]), values[::41])
    def sample(**changes):
        fields = dict(text=False, layout=0, maximum=3, quota=2, recovery_maximum=16,
                      recovery_quota=8, script=(), data=b"abcd")
        fields.update(changes)
        return Case(**fields)
    over = sample()
    first, second = observations(over)
    assert first[:12] == [1, 3, 0, 0, 3, 2, 1, 100, 2, 2, 4, 0]
    assert first[12:15] == [97, 98, 99]
    assert first[15:] == [3, 1024, 0, 1, 1024, 3]
    assert second[:12] == [0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 4, 0]
    recovered = sample(maximum=1, data=b"abcdef")
    first, second = observations(recovered)
    assert bytes(first[12:13] + [first[7]] + second[12:12 + second[4]]) == b"abcdef"
    quota = sample(quota=1)
    assert observations(quota)[0][:12] == [1, 2, 0, 0, 3, 1, 0, 0, 1, 1, 3, 0]
    actual_eof = sample(data=b"abc")
    assert observations(actual_eof)[0][:12] == [0, 0, 0, 0, 3, 0, 0, 0, 2, 2, 3, 0]
    zero = sample(maximum=0, quota=0, data=b"")
    assert observations(zero)[0][:12] == [1, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    interrupted = sample(quota=1, script=(-1,))
    assert observations(interrupted)[0][:12] == [1, 2, 0, 0, 0, 1, 0, 0, 1, 1, 0, 1]
    bad_count = sample(quota=1, script=(-5,))
    assert observations(bad_count)[0][:12] == [1, 4, 4, 0, 0, 1, 0, 0, 1, 1, 0, 1]
    text = sample(text=True, maximum=9, quota=MASK, script=(1, 1, 1, 1), data=b"a\xffZ")
    assert observations(text)[0][:12] == [1, 6, 1, 1, 3, 4, 0, 0, 4, 4, 3, 4]
    assert observations(text)[0][12:15] == [97, 255, 90]
    precedence = sample(text=True, maximum=1, data=b"\xffX")
    assert observations(precedence)[0][:12] == [1, 3, 0, 0, 1, 2, 1, 88, 2, 2, 2, 0]
    transient = sample(script=(0, 1024), maximum=4, data=b"ab")
    assert observations(transient)[0][4] == 0 and observations(transient)[1][12:14] == [97, 98]
    split = sample(text=True, maximum=4, quota=MASK, script=(1, 1, 1, 1), data="😀".encode())
    assert observations(split)[0][:12] == [0, 0, 0, 0, 4, 0, 0, 0, 5, 5, 4, 4]
    corruptions = ((over, 7, 0), (over, 10, 3), (over, 15, 1024),
                   (quota, 0, 0), (interrupted, 5, 0), (text, 3, 2),
                   (text, 14, 0), (precedence, 1, 6))
    for case, word, replacement in corruptions:
        bad = encode([case])
        assert struct.unpack_from("<Q", bad, word * 8)[0] != replacement
        struct.pack_into("<Q", bad, word * 8, replacement)
        try: verify(bad, [case])
        except AssertionError: pass
        else: raise AssertionError(("accepted corruption", case, word))
    outcomes, modes, requests = Counter(), Counter(), Counter()
    full_text_failures = probe_failures = 0
    for case in values:
        modes[case.text] += 1
        for words in observations(case):
            outcomes[(words[0], words[1], words[2])] += 1
            full_text_failures += words[1] == 6
            probe_failures += words[6] == 1
            trace = 12 + words[4]
            for index in range(words[9]): requests[words[trace + index * 3]] += 1
    assert requests[1024] and requests[1] and all(modes.values())
    assert all(any(kind == error and count for (_, kind, _), count in outcomes.items()) for error in (0, 1, 2, 3, 4, 6))
    print(f"owned-input CPU cases={len(values)} modes=2 layouts=2 invocations=2 seed={SEED:#x} corruption-controls=8")
    print(f"owned-input modes={dict(sorted(modes.items()))} outcomes={dict(sorted(outcomes.items()))} text-failures={full_text_failures} retained-probes={probe_failures}")


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
    print(f"owned-input cases={len(values)} modes=2 layouts=2 invocations=2 seed={SEED:#x}")


if __name__ == "__main__":
    main()
