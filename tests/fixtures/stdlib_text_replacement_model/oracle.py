"""Unicode-library literal reference; test-only strict binary protocol.

re.finditer(re.escape(...)) establishes the complete immutable match list.
str.replace independently establishes replacement bytes. Neither reference
copies the Lanius byte scanner, cursor transitions, or measure/fill passes.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, replace
from itertools import product
from pathlib import Path
import random
import re
import struct
import subprocess
import sys

SEED = 0x7E871A0261116
MAX = (1 << 64) - 1
MAGIC = 0x746578747265706C
SIZES = (2056, 264, 136)
REPLACEMENTS = ('', 'X', '\0', 'é', '界😀', r'\1$&', 'aé', '\n')


@dataclass(frozen=True)
class Case:
    source: str
    needle: str
    replacement: str
    layout: int
    origins: tuple[int, int, int]
    aliases: tuple[int, int]
    actions: tuple[int, ...]
    operations: tuple[tuple[int, int, int], ...]


def matches(source, needle):
    prefixes = [0]
    for scalar in source:
        prefixes.append(prefixes[-1] + len(scalar.encode('utf-8')))
    return tuple((prefixes[match.start()], match.group().encode('utf-8'))
                 for match in re.finditer(re.escape(needle), source))


def replaced(source, needle, replacement, count):
    # Python's C count is signed; scalar_count+1 bounds every literal match
    # sequence, so clamp before asking Python to represent an arbitrary u64.
    return source.replace(needle, replacement, min(count, len(source) + 1)).encode('utf-8')


def operations(source, needle, replacement, ordinal):
    count = len(matches(source, needle))
    limits = tuple(dict.fromkeys((0, 1, max(0, count - 1), count, count + 1,
                                 (1 << 32), (1 << 63), MAX)))
    result = []
    for index, maximum in enumerate(limits):
        value = replaced(source, needle, replacement, maximum)
        result.append((0, maximum, len(value) + (7 if (index + ordinal) % 3 == 0 else 0)))
    complete = replaced(source, needle, replacement, MAX)
    result += [(1, MAX, len(complete)), (0, MAX, -1 if ordinal % 2 else -(1 << 31)),
               (0, MAX, max(0, len(complete) - 1))]
    assert len(result) <= 16
    return tuple(result)


def corpus():
    rng = random.Random(SEED)
    triples = []
    for length in range(4):
        for letters in product(('a', 'b', 'é'), repeat=length):
            source = ''.join(letters)
            for needle in ('', 'a', 'b', 'é', 'aa', 'ab', 'éa'):
                triples.append((source, needle, REPLACEMENTS[(len(triples) // 7) % 8], (-1, -1)))
    assert len(triples) == 280
    edges = [
        ('aaaaa', 'aa', 'X'), ('aaaaa', 'aaa', 'aa'), ('abababa', 'aba', 'ababa'),
        ('banana', 'ana', '!'), ('ééé', 'éé', '界'), ('😀😀😀', '😀😀', 'é'),
        ('Aé界😀', '', '|'), ('', 'a', '\0'), ('a', '', ''), ('é', '', '😀'),
        ('😀', '😀', ''), ('prefix-middle-suffix', 'middle', ''), ('x' * 257, 'x', ''),
        ('ab', 'a', 'aa'), ('a' * 20, 'a', 'a' * 8),
        ('a$b\\c', '$', r'\1$&'), ('a.b*a.b*', 'a.b*', '$0\\'),
        ('[a](a)?a+', '(a)?', '\\g<0>'), ('\0a\0b\0', '\0', '😀\0'),
        ('\r\n\r\n', '\r\n', '\0'), ('e\u0301é', 'é', 'e\u0301'),
        ('e\u0301é', 'e\u0301', 'é'), ('e\u0301', '', '_'),
        ('👩\u200d💻', '', '.'), ('A\ufe0fB', '\ufe0f', ''),
        ('\ufeffx\ufeff', '\ufeff', '界'), ('\uffff\U0010ffff\uffff', '\uffff', 'x'),
        ('\x7f\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000\U0010ffff', '', 'é'),
        ('no matches here', 'longer missing pattern', 'q'), ('é界😀', 'é界😀', ''),
        ('aaXaa', 'aa', 'aa'), ('abcabc', 'abc', 'abcabc'),
    ]
    triples += [(s, n, r, (-1, -1)) for s, n, r in edges]
    # Read-only overlaps: needle/replacement are actual source subviews.
    aliases = [
        ('aaaaa', 'aa', 'aaa', (0, 1)), ('ééé', 'é', 'éé', (2, 0)),
        ('abcabc', 'abc', 'bc', (3, 1)), ('😀x😀', '😀', 'x', (0, 4)),
        ('Aé界😀', '', 'é界', (1, 1)), ('abc', 'abc', 'abc', (0, 0)),
        ('aaaa', 'a', '', (2, 4)), ('', '', '', (0, 0)),
    ]
    triples += aliases
    assert len(triples) == 320
    pool = ('a', 'b', 'é', '界', '😀', '\0', '\n', '\u0301', '\ufeff', '\U0010ffff')
    for ordinal in range(64):
        length = (0, 1, 2, 7, 31, 63, 127, 257)[ordinal % 8]
        source = ''.join(rng.choice(pool) for _ in range(length))
        if ordinal % 4 == 0:
            needle = ''
        elif ordinal % 4 == 1:
            start = rng.randrange(len(source) + 1)
            needle = source[start:start + 1 + ordinal % 5]
        elif ordinal % 4 == 2:
            needle = ''.join(rng.choice(pool) for _ in range(1 + ordinal % 7))
        else:
            source = ('aé' * (1 + length // 2))[:length]
            needle = 'aéa'
        triples.append((source, needle, REPLACEMENTS[ordinal % 8], (-1, -1)))
    assert len(triples) == 384
    values = []
    for ordinal, (source, needle, replacement, alias) in enumerate(triples):
        actions = (0, 2, 1, 0, 3, 1, 4, 5, 0, 1, 2, 0, 1, 3, 0)
        actions += tuple(rng.choice((0, 0, 1, 1, 2, 3, 4, 5)) for _ in range(9))
        values.append(Case(source, needle, replacement, ordinal % 8,
                           (3 + 2 * (ordinal % 3), 3 + 2 * ((ordinal + 1) % 3),
                            3 + 2 * ((ordinal + 2) % 3)), alias, actions,
                           operations(source, needle, replacement, ordinal)))
    # The eight representative semantics each run on all eight actual layouts,
    # while the larger finite corpus rotates layout instead of multiplying it.
    for original in (0, 8, 279, 280, 286, 298, 302, 311):
        base = values[original]
        values += [replace(base, layout=layout) for layout in range(8) if layout != base.layout]
    assert len(values) == 440
    for case in values:
        data = [value.encode('utf-8') for value in (case.source, case.needle, case.replacement)]
        assert all(len(item) <= bound for item, bound in zip(data, (2048, 256, 128)))
        for index, alias in enumerate(case.aliases, 1):
            if alias >= 0:
                assert data[0][alias:alias + len(data[index])] == data[index]
                data[0][:alias].decode('utf-8')
        assert max(len(replaced(case.source, case.needle, case.replacement, count))
                   for _, count, _ in case.operations) <= 16384
    return values


def words(*values):
    return struct.pack('<' + 'Q' * len(values), *(value & MAX for value in values))


def packet(cases):
    result = bytearray()
    for case in cases:
        data = tuple(value.encode('utf-8') for value in (case.source, case.needle, case.replacement))
        result += words(case.layout, *(len(item) for item in data), *case.origins, *case.aliases,
                        len(case.actions), len(case.operations))
        result += b''.join(data) + bytes(case.actions)
        result += b''.join(words(*operation) for operation in case.operations)
    return bytes(result)


def metadata(case):
    data = tuple(value.encode('utf-8') for value in (case.source, case.needle, case.replacement))
    strides = [1 if case.layout & (1 << index) else -8 for index in range(3)]
    origins = list(case.origins)
    for index, alias in enumerate(case.aliases, 1):
        if alias >= 0:
            origins[index] = case.origins[0] + alias
            strides[index] = strides[0]
    return b''.join(words(origin, len(item), stride) for origin, item, stride in zip(origins, data, strides))


def backing(case):
    data = tuple(value.encode('utf-8') for value in (case.source, case.needle, case.replacement))
    result = []
    for size, (base, step), origin, value in zip(SIZES, ((211, 17), (101, 13), (53, 19)), case.origins, data):
        region = bytearray((base + index * step) & 255 for index in range(size))
        region[origin:origin + len(value)] = value
        result.append(region)
    return b''.join(result)


POISON = b''.join(bytes((base + index * step) & 255 for index in range(size))
                  for size, (base, step) in zip(SIZES, ((41, 23), (61, 29), (71, 31))))


def string_record(value):
    return words(len(value), len(value.decode('utf-8')), 1) + value


def reference(case, counts=None):
    if counts is None:
        counts = Counter()
    result = bytearray(words(MAGIC, case.layout, len(case.operations)))
    descriptor = metadata(case)
    original = backing(case)
    result += descriptor
    sequence = matches(case.source, case.needle)
    positions = [0, 0]

    def emit_item(opcode, value):
        counts['pulls'] += 1
        if value is None:
            result.extend((opcode, 0))
            return
        counts['items'] += 1
        index, data = value
        result.extend((opcode, 1))
        result.extend(words(index, case.origins[0] + index, len(data), 1 if case.layout & 1 else -8))
        result.extend((original[0], original[2055]))
        result.extend(data)

    def pull(which):
        if positions[which] == len(sequence):
            emit_item(which, None)
            return False
        emit_item(which, sequence[positions[which]])
        positions[which] += 1
        return True

    for action in case.actions:
        if action < 2:
            pull(action)
        else:
            if action == 2:
                positions[1] = positions[0]
            elif action == 3:
                positions[0] = positions[1]
            else:
                positions[action - 4] = 0
            counts['copies'] += 1
            result.extend((action, 2))
    for cursor in range(2):
        while pull(cursor):
            pass
    result.extend((2, 2))
    counts['copies'] += 1
    positions[1] = positions[0]
    for probe in range(6):
        assert not pull(probe % 2)
    for value in sequence[:3]:
        emit_item(6, value)
    emit_item(6, None)
    emit_item(6, None)
    emit_item(7, sequence[3] if len(sequence) > 3 else None)
    result += descriptor + original

    for index, (mode, count, limit) in enumerate(case.operations):
        counts['operations'] += 1
        counts['replace_calls' if mode else 'replacen_calls'] += 1
        value = replaced(case.source, case.needle, case.replacement, MAX if mode else count)
        error = 1 if limit < 0 else 2 if len(value) > limit else 0
        result += words(index) + descriptor + descriptor + words(error)
        if error:
            counts['bounds' if error == 1 else 'output_limit'] += 1
            result += original
        else:
            counts['successes'] += 1
            counts['result_bytes'] += len(value)
            counts['empty_results'] += not value
            counts['zero_count'] += mode == 0 and count == 0
            counts['max_count'] += mode == 0 and count == MAX
            result += string_record(value) + original
            result += string_record(value) + string_record(value + b'!') + words(0, 0) + POISON
    result += words(99)
    return bytes(result)


def verify(actual, cases):
    at, counts = 0, Counter()
    for index, case in enumerate(cases):
        expected = reference(case, counts)
        observed = actual[at:at + len(expected)]
        if observed != expected:
            mismatch = next((offset for offset, pair in enumerate(zip(observed, expected)) if pair[0] != pair[1]), min(len(observed), len(expected)))
            raise AssertionError(f'case={index} layout={case.layout} source={case.source!r} needle={case.needle!r} '
                                 f'replacement={case.replacement!r} offset={mismatch} '
                                 f'observed={observed[mismatch:mismatch+8]!r} expected={expected[mismatch:mismatch+8]!r}')
        at += len(expected)
    assert at == len(actual), ('extra bytes', at, len(actual))
    return counts


def summary(cases, counts):
    return (f'text-replacement-model cases={len(cases)} pulls={counts["pulls"]} items={counts["items"]} '
            f'copies={counts["copies"]} operations={counts["operations"]} successes={counts["successes"]} '
            f'bounds={counts["bounds"]} output_limit={counts["output_limit"]} '
            f'result_bytes={counts["result_bytes"]} layouts=8 seed=0x{SEED:x}\n')


def controls():
    cases = corpus()
    assert packet(cases)
    assert matches('Aé界😀', '') == ((0, b''), (1, b''), (3, b''), (6, b''), (10, b''))
    assert matches('', '') == ((0, b''),)
    assert matches('aaaaa', 'aa') == ((0, b'aa'), (2, b'aa'))
    assert matches('ababa', 'aba') == ((0, b'aba'),)
    assert matches('e\u0301é', 'é') == ((3, 'é'.encode()),)
    assert replaced('ab', 'a', 'aa', MAX) == b'aab'
    assert replaced('é', '', r'\1$&', MAX) == r'\1$&'.encode() + 'é'.encode() + r'\1$&'.encode()
    wanted = b''.join(reference(case) for case in cases)
    counts = verify(wanted, cases)
    # A compact Unicode/empty-pattern case makes byte-vs-scalar and Some(empty)
    # errors visible; complete results and preservation are separately mutated.
    base = next(case for case in cases if case.source == 'Aé界😀' and not case.needle)
    output = reference(base)
    mutations = []
    def changed(label, position):
        assert 0 <= position < len(output)
        bad = bytearray(output)
        bad[position] ^= 1
        mutations.append((label, bytes(bad)))
    # First item starts after three case words and nine descriptor words.
    start = 12 * 8
    for label, offset in [('tag', 1), ('offset', 2), ('source-start', 10), ('length', 18),
                          ('stride', 26), ('source-guard', 34)]:
        changed(label, start + offset)
    changed('case-layout', 8)
    changed('source-metadata', 24)
    original = backing(base)
    changed('input-preservation', output.index(original) + base.origins[0])
    changed('result-bytes', output.index(string_record(base.source.encode())) + 24)
    changed('post-source-poison', output.index(POISON) + 17)
    changed('destroyed-owner', output.index(POISON) - 16)
    # Change coherent semantic expectations as well as individual frame bytes.
    for label, altered in [
        ('replacement-text', replace(base, replacement='x')),
        ('empty-byte-boundary', replace(base, source='Aabc😀')),
        ('different-needle', replace(base, needle='é')),
        ('u64-count', replace(base, operations=tuple((mode, 0, limit) for mode, _, limit in base.operations))),
        ('output-limit', replace(base, operations=tuple((mode, count, 0) for mode, count, _ in base.operations))),
    ]:
        mutations.append((label, reference(altered)))
    mutations += [('truncated', output[:-1]), ('extra', output + b'\0')]
    # Coherent output-only faults preserve case metadata and every input cell.
    # They therefore cannot be rejected merely because the selected case changed.
    semantic_mutations = []
    for label, source, needle, replacement, correct, wrong in [
        ('overlapping-replacement', 'aaaaa', 'aa', 'X', b'XXa', b'XXXa'),
        ('searching-inserted-bytes', 'ab', 'a', 'aa', b'aab', b'aaab'),
    ]:
        selected = next(case for case in cases if (case.source, case.needle, case.replacement) == (source, needle, replacement))
        original_output = reference(selected)
        corrupted = original_output.replace(string_record(correct), string_record(wrong))
        corrupted = corrupted.replace(string_record(correct + b'!'), string_record(wrong + b'!'))
        assert corrupted != original_output
        semantic_mutations.append((label, corrupted, selected))
    # Move an otherwise valid empty source subview inside the two-byte é.
    needle_record = bytes((1, 1)) + words(1, base.origins[0] + 1, 0, 1 if base.layout & 1 else -8)
    assert needle_record in output
    corrupted = output.replace(needle_record, bytes((1, 1)) + words(2, base.origins[0] + 2, 0, 1 if base.layout & 1 else -8), 1)
    semantic_mutations.append(('byte-instead-of-scalar-boundary', corrupted, base))
    for label, bad, selected in [(label, bad, base) for label, bad in mutations] + semantic_mutations:
        try:
            verify(bad, [selected])
        except AssertionError:
            pass
        else:
            raise AssertionError(f'accepted verifier corruption: {label}')
    print(summary(cases, counts), end='')
    print(f'cpu-controls rejected={len(mutations) + len(semantic_mutations)} transcript_bytes={len(wanted)} '
          f'empty_results={counts["empty_results"]} zero_count_successes={counts["zero_count"]} '
          f'max_count_successes={counts["max_count"]} replace_calls={counts["replace_calls"]} '
          f'replacen_calls={counts["replacen_calls"]}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
        return
    assert len(sys.argv) == 2, 'oracle.py EXECUTABLE | controls'
    cases = corpus()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(cases),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75, check=False)
    assert process.returncode == 0 and not process.stderr, (process.returncode, process.stderr[:2000])
    print(summary(cases, verify(process.stdout, cases)), end='')


if __name__ == '__main__':
    main()
