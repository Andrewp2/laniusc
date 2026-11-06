"""Independent scalar-regex reference for literal Text partitions.

The library scans byte slices. This reference uses Python's Unicode regular
expression engine; rightmost matching runs on reversed scalar strings, then
maps spans through a UTF-8 prefix table. It never reverses leftmost matches.
Transport is one binary batch, with source and separator bytes kept separate.
"""
import itertools
import random
import re
import struct
import subprocess
import sys


U64 = (1 << 64) - 1
SEED = 0x7E871A0261117
LIMITS = (0, 1, 2, 3, 4, 1 << 32, 1 << 63, U64)
ACTIONS = (0, 2, 0, 1, 3, 0, 4, 1, 5, 1, 0)


def word(value):
    return struct.pack("<Q", value & U64)


def prefix(source):
    result = [0]
    for scalar in source:
        result.append(result[-1] + len(scalar.encode("utf-8")))
    return result


def matches(source, needle, reverse=False):
    if reverse:
        return [(len(source) - match.end(), len(source) - match.start())
                for match in re.finditer(re.escape(needle[::-1]), source[::-1])]
    return [match.span() for match in re.finditer(re.escape(needle), source)]


def partitions(source, needle, limit=None, reverse=False):
    if limit == 0:
        return []
    if limit == 1:
        return [(0, len(source))]
    maxsplit = 0 if limit is None else min(limit - 1, len(source) + 1)
    text, delimiter = (source[::-1], needle[::-1]) if reverse else (source, needle)
    pieces = re.split(re.escape(delimiter), text, maxsplit=maxsplit)
    spans, at = [], len(source) if reverse else 0
    for piece in pieces:
        if reverse:
            spans.append((at - len(piece), at))
            at -= len(piece) + len(needle)
        else:
            spans.append((at, at + len(piece)))
            at += len(piece) + len(needle)
    assert all(0 <= low <= high <= len(source) for low, high in spans)
    return spans


def case(source, needle, index, limit):
    alias = U64
    # Read-only source aliases use a byte offset, not a scalar offset.
    if index % 5 == 0 and needle in source:
        alias = len(source[:source.index(needle)].encode("utf-8"))
    return dict(source=source, needle=needle, layout=index % 4,
                origin=1 + index % 5, needle_origin=2 + index % 3,
                limit=limit, alias=alias)


def cases():
    witnesses = [
        ("", ""), ("", "x"), ("a", ""), ("a", "a"), ("ababa", "aba"),
        ("aaaaa", "aa"), ("banana", "ana"), ("éaéaé", "éaé"),
        ("::a::::b::", "::"), ("Aé界😀", ""), ("\0a\0\0b\0", "\0"),
        ("e\u0301é e\u0301é", "é"), ("a\r\nb\nc\r\n", "\r\n"),
        ("\ufeff\uffff\U0010ffff\u0080\u07ff\u0800\U00010000", ""),
        ("👩\u200d💻👩\u200d💻", "\u200d"),
        ("abababababababababababababababababac", "ababababac"),
        ("abababababababababababababababababab", "ababababac"),
        ("xxxxxxxxxxxxxx", "xxxxxxxxxxxxxxxx"),
    ]
    result = []
    for source, needle in witnesses:
        for limit in LIMITS:
            for _ in range(4):
                result.append(case(source, needle, len(result), limit))
    for size in range(5):
        for letters in itertools.product("aé", repeat=size):
            source = "".join(letters)
            for needle in ("", "a", "é", "aa", "aé", "éa", "éé"):
                result.append(case(source, needle, len(result), LIMITS[len(result) % len(LIMITS)]))
    rng = random.Random(SEED)
    alphabet = ("a", "b", "é", "界", "😀", "\0", "\u0301", "\u200d")
    for _ in range(80):
        source = "".join(rng.choice(alphabet) for _ in range(rng.randrange(35)))
        if rng.randrange(2) and source:
            low = rng.randrange(len(source) + 1)
            needle = source[low:low + rng.randrange(5)]
        else:
            needle = "".join(rng.choice(alphabet) for _ in range(rng.randrange(5)))
        result.append(case(source, needle, len(result), rng.choice(LIMITS)))
    return result


def request(record):
    source, needle = record["source"].encode(), record["needle"].encode()
    header = (len(source), len(needle), record["layout"], record["origin"],
              record["needle_origin"], record["limit"], record["alias"])
    assert len(source) + record["origin"] < 256 and len(needle) + record["needle_origin"] < 128
    return struct.pack("<7Q", *header) + source + needle


def expected(record, stats=None):
    source, needle = record["source"], record["needle"]
    raw, needle_raw = source.encode(), needle.encode()
    offsets = prefix(source)
    origin, needle_origin = record["origin"], record["needle_origin"]
    stride = 1 if record["layout"] & 1 else -8
    needle_stride = 1 if record["layout"] & 2 else -8
    if record["alias"] != U64:
        needle_origin, needle_stride = origin + record["alias"], stride
    source_descriptor = word(origin) + word(len(raw)) + word(stride)
    needle_descriptor = word(needle_origin) + word(len(needle_raw)) + word(needle_stride)
    output = bytearray(source_descriptor + needle_descriptor)

    def view(span):
        low, high = map(offsets.__getitem__, span)
        return word(origin + low) + word(high - low) + word(stride) + raw[low:high]

    def item(span):
        if stats is not None:
            stats["pulls"] += 1
            stats["items"] += span is not None
        return b"\0" if span is None else b"\1" + view(span)

    left, right = matches(source, needle), matches(source, needle, True)
    for selected in (left, right):
        if selected:
            low, high = selected[0]
            output += b"\1" + view((0, low)) + view((high, len(source)))
        else:
            output += b"\0"
    output += word(offsets[left[0][0]] if left else -1)
    output += word(offsets[right[0][0]] if right else -1)
    for span in right:
        output += b"\1" + word(offsets[span[0]]) + view(span)
    output += b"\0\0"
    if stats is not None:
        stats["matches"] += len(right)

    def exercise(spans):
        positions = [0, 0]
        def pull(cursor):
            at = positions[cursor]
            positions[cursor] = min(at + 1, len(spans))
            return item(spans[at] if at < len(spans) else None)
        for action in ACTIONS:
            output.append(action)
            if action < 2:
                output.extend(pull(action))
            else:
                if action == 2:
                    positions[1] = positions[0]
                elif action == 3:
                    positions[0] = positions[1]
                elif action == 4:
                    positions[0] = 0
                elif action == 5:
                    positions[1] = 0
                output.append(2)
                if stats is not None:
                    stats["copies"] += 1
        for cursor in (0, 1):
            while True:
                output.append(cursor)
                value = pull(cursor)
                output.extend(value)
                if value == b"\0":
                    break
        for cursor in (0, 1, 0, 1):
            output.append(cursor)
            output.extend(pull(cursor))

    for reverse, limit in ((False, None), (True, None), (False, record["limit"]), (True, record["limit"])):
        exercise(partitions(source, needle, limit, reverse))
    output += source_descriptor + needle_descriptor
    backing = bytearray(b"\xff" * 256)
    backing[origin:origin + len(raw)] = raw
    separate = bytearray(b"\xff" * 128)
    separate[record["needle_origin"]:record["needle_origin"] + len(needle_raw)] = needle_raw
    output += backing + separate
    return bytes(output)


def compare(actual, desired, records, lengths):
    if actual == desired:
        return
    position = next((i for i, (a, b) in enumerate(zip(actual, desired)) if a != b), min(len(actual), len(desired)))
    start = 0
    for index, length in enumerate(lengths):
        if position < start + length:
            raise AssertionError(("text partition mismatch", index, records[index],
                                  "case byte", position - start, "actual length", len(actual), "expected length", len(desired),
                                  actual[max(0, position - 16):position + 24].hex(), desired[max(0, position - 16):position + 24].hex()))
        start += length
    raise AssertionError(("extra/truncated partition output", len(actual), len(desired)))


def controls():
    assert matches("ababa", "aba") == [(0, 3)]
    assert matches("ababa", "aba", True) == [(2, 5)]
    assert matches("aaaaa", "aa", True) == [(3, 5), (1, 3)]
    assert partitions("ababa", "aba", reverse=True) == [(5, 5), (0, 2)]
    assert partitions("::a::::b::", "::", 2, True) == [(10, 10), (0, 8)]
    assert partitions("Aé界😀", "", reverse=True) == [(4, 4), (3, 4), (2, 3), (1, 2), (0, 1), (0, 0)]
    assert [prefix("Aé界😀")[low] for low, _ in matches("Aé界😀", "", True)] == [10, 6, 3, 1, 0]
    assert partitions("", "") == [(0, 0), (0, 0)]
    assert partitions("", "", 1) == [(0, 0)] and partitions("x", "", 0) == []
    assert partitions("a::b::c", "::", 2) == [(0, 1), (3, 7)]
    assert partitions("a::b::c", "::", 2, True) == [(6, 7), (0, 4)]
    assert partitions("a::b::c", "::", U64) == partitions("a::b::c", "::")
    record = case("Aé界😀", "", 1, 3)
    desired = expected(record)
    other_origin = dict(record, origin=record["origin"] + 1)
    other_stride = dict(record, layout=record["layout"] ^ 1)
    mutants = [desired[:-1], desired + b"\0", bytes([desired[0] ^ 1]) + desired[1:],
               expected(other_origin), expected(other_stride)]
    for altered in mutants:
        try:
            compare(altered, desired, [record], [len(desired)])
        except AssertionError:
            continue
        raise AssertionError("comparison accepted a changed view or output")
    return 12 + len(mutants)


def main():
    control_count = controls()
    records = cases()
    stats = dict(pulls=0, items=0, copies=0, matches=0)
    chunks = [expected(record, stats) for record in records]
    summary = (f"text-partition-model cases={len(records)} pulls={stats['pulls']} items={stats['items']} "
               f"copies={stats['copies']} matches={stats['matches']} layouts=4 seed={SEED:#x}")
    if sys.argv[1:] == ["controls"]:
        print(f"text-partition-model-controls={control_count}")
        print(summary)
        return
    assert len(sys.argv) == 2, sys.argv
    completed = subprocess.run([sys.argv[1]], input=b"".join(map(request, records)), capture_output=True, timeout=30)
    assert completed.returncode == 0 and completed.stderr == b"", (completed.returncode, completed.stderr)
    compare(completed.stdout, b"".join(chunks), records, list(map(len, chunks)))
    print(summary)


if __name__ == "__main__":
    main()
