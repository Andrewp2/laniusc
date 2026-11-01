"""Independent ordered TOML values, canonical bytes and offset-only Read model."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import datetime
import math
from pathlib import Path
import random
import re
import struct
import subprocess
import sys
import tomllib

SEED = 0x70A10261117
MASK = (1 << 64) - 1
I32_MAX = (1 << 31) - 1


@dataclass(frozen=True)
class Node:
    kind: int
    value: object = None
    children: tuple = ()
    token: str = ''


@dataclass(frozen=True)
class Case:
    tree: Node
    limit: int
    work: int
    layout: int
    actions: tuple
    literal_tabs: bool = False


def text(value): return Node(2, value)
def integer(value, token=''): return Node(3, value, token=token or str(value))
def floating(token, canonical): return Node(4, canonical, token=token)
def boolean(value): return Node(5, value)
def array(*values): return Node(1, children=tuple(('', value) for value in values))
def table(*members): return Node(0, children=tuple(members))
def temporal(kind, token): return Node(kind, token, token=token)


def quote(value):
    # Declarative substitution over a complete UTF-8 value, not serializer state.
    substitutions = {byte: ('\\u%04x' % byte).encode() for byte in (*range(32), 127)}
    substitutions.update({34: b'\\"', 92: b'\\\\'})
    return b'"' + b''.join(substitutions.get(byte, bytes((byte,)))
                           for byte in value.encode()) + b'"'


TEMPORAL = re.compile(
    r'(?:(?P<date>\d{4}-\d{2}-\d{2})(?P<join>[Tt ])?)?'
    r'(?:(?P<hm>\d{2}:\d{2})(?::(?P<seconds>\d{2}))?'
    r'(?:\.(?P<fraction>\d+))?(?P<zone>[Zz]|[+-]\d{2}:\d{2})?)?')


def temporal_parts(node):
    matched = TEMPORAL.fullmatch(node.token)
    assert matched, node
    return matched.groupdict(default='')


def canonical_temporal(node):
    fields = temporal_parts(node)
    result = fields['date']
    if fields['hm']:
        result += ('T' if fields['date'] else '') + fields['hm'] + ':' + (fields['seconds'] or '00')
        fraction = fields['fraction'].rstrip('0')
        result += '.' + fraction if fraction else ''
    zone = fields['zone']
    result += 'Z' if zone in ('Z', 'z', '+00:00') else zone
    return result.encode()


def wire(node, root=False):
    if root:
        assert node.kind == 0
        return b''.join(quote(key) + b'=' + wire(child) + b'\n' for key, child in node.children)
    if node.kind == 0:
        return b'{' + b','.join(quote(key) + b'=' + wire(child) for key, child in node.children) + b'}'
    if node.kind == 1: return b'[' + b','.join(wire(child) for _, child in node.children) + b']'
    if node.kind == 2: return quote(node.value)
    if node.kind == 3: return str(node.value).encode()
    if node.kind == 4: return node.value.encode()
    if node.kind == 5: return b'true' if node.value else b'false'
    return canonical_temporal(node)


def all_nodes(node):
    return [node] + [item for _, child in node.children for item in all_nodes(child)]


def work(tree):
    nodes = all_nodes(tree)
    fractions = [temporal_parts(node)['fraction'] for node in nodes if node.kind >= 6]
    return len(wire(tree, True)) + len(nodes) - 1 + sum(
        len(value) + len(value) - len(value.rstrip('0')) for value in fractions)


def source_value(node):
    if node.kind == 0:
        return b'{ ' + b', '.join(quote(key) + b' = ' + source_value(child)
                                  for key, child in node.children) + b' }'
    if node.kind == 1: return b'[ ' + b', '.join(source_value(child) for _, child in node.children) + b' ]'
    if node.kind == 2:
        # Input uses uppercase hex digits; expected output uses lowercase digits.
        return re.sub(rb'\\u([0-9a-f]{4})', lambda match: b'\\u' + match[1].upper(), quote(node.value))
    if node.kind in (3, 4) or node.kind >= 6: return node.token.encode()
    return b'true' if node.value else b'false'


def source(case):
    if case.literal_tabs:
        first_key, first = case.tree.children[0]
        assert first_key == 's' and first.kind == 2 and set(first.value) == {'\t'}
        return b"s='" + first.value.encode() + b"'\n" + b''.join(
            quote(key) + b' = ' + source_value(child) + b'\n' for key, child in case.tree.children[1:])
    return b''.join(quote(key) + b' = ' + source_value(child) + b'\n'
                    for key, child in case.tree.children)


def u64(value): return struct.pack('<Q', value & MASK)
def sized(value): return u64(len(value)) + value


def snapshot(tree):
    def visit(node):
        result = bytearray(u64(node.kind))
        if node.kind <= 1:
            result += u64(len(node.children))
            for key, child in node.children:
                if node.kind == 0: result += sized(key.encode())
                result += visit(child)
        elif node.kind == 2: result += sized(node.value.encode())
        elif node.kind == 3: result += u64(node.value) + sized(str(node.value).encode())
        elif node.kind == 4:
            number = float(node.value)
            is_nan = math.isnan(number)
            negative = math.copysign(1, number) < 0
            result += u64(is_nan) + u64(negative) + (u64(0) if is_nan else struct.pack('<d', number))
            result += sized(node.value.encode())
        elif node.kind == 5: result += u64(node.value)
        else:
            result += sized(node.token.encode())
            result += sized(temporal_parts(node)['fraction'].encode())
        return result
    return u64(len(all_nodes(tree))) + visit(tree)


def schedules(rng, cut):
    actions = [(0, 3, cut), (2, 0, 0), (0, 5, 1), (1, 7, 2), (0, I32_MAX, 0),
               (1, -1, 0), (0, I32_MAX, 1), (1, 0, -1), (3, 0, 0), (4, 0, 0), (5, 0, 0)]
    for _ in range(13):
        actions.append((rng.choice((0, 0, 1, 1, 2, 3, 4, 5)), rng.randrange(8),
                        rng.choice((0, 1, 2, 3, 5, 7, 13, 31))))
    return tuple(actions)


def cases():
    rng = random.Random(SEED)
    leaves = [text(''), text('"\\é界😀'), text(''.join(map(chr, range(32))) + '\x7f'),
              text('\u0080\u07ff\u0800\ud7ff\ue000\uffff\U00010000\U0010ffff'),
              integer(0, '+0'), integer(-9223372036854775808), integer(9223372036854775807),
              integer(65535, '0xFF_FF'), integer(83, '0o123'), integer(5, '0b101'),
              boolean(False), boolean(True), array(), table()]
    leaves += [text(chr(value)) for value in range(32)]
    leaves += [floating(token, canonical) for token, canonical in (
        ('+0.0', '0.0'), ('-0e0', '-0.0'), ('1.500', '1.5'), ('1e2', '100.0'),
        ('+inf', 'inf'), ('-inf', '-inf'), ('nan', 'nan'), ('-nan', '-nan'))]
    temporal_values = [
        temporal(8, '2024-02-29'), temporal(9, '07:32'), temporal(9, '07:32:00.0000'),
        temporal(9, '23:59:59.000000000001230000'),
        temporal(7, '1979-05-27t07:32'), temporal(7, '1979-05-27 07:32:01.120000'),
        temporal(6, '1979-05-27t07:32z'), temporal(6, '1979-05-27 07:32:00+00:00'),
        temporal(6, '1979-05-27T07:32:00-00:00'),
        temporal(6, '2000-01-01T00:00:00.123456789012345678900+05:45'),
        temporal(6, '2000-01-01T00:00:00.000000000000000000001-07:30'),
        temporal(9, '12:34:56.' + '1234567890' * 12 + '9' + '0' * 136),
    ]
    leaves += temporal_values
    profiles = [table()] + [table(('v', leaf)) for leaf in leaves]
    profiles += [table(('z', integer(1)), ('a', array(table(('x', text('\0'))), array())),
                       ('', table()), ('\0"\\é', text('\x7f\n'))),
                 table(('v', array(*temporal_values))),
                 table(('v', text('x' * 1017))), table(('v', text('x' * 1018))),
                 table(('v', text('x' * 1019)))]
    nested = text('\0é😀')
    for index in range(20): nested = array(nested) if index % 2 else table(('', nested))
    profiles.append(table(('deep', nested)))
    alphabet = ('a', '\0', '\t', '\n', '\x7f', '"', '\\', 'é', '界', '😀')
    def generate(depth):
        if depth and rng.randrange(3) == 0:
            children = [generate(depth - 1) for _ in range(rng.randrange(4))]
            return array(*children) if rng.randrange(2) else table(*[(f'k{index}', value) for index, value in enumerate(children)])
        return text(''.join(rng.choice(alphabet) for _ in range(rng.randrange(12))))
    profiles += [table(('first', generate(4)), ('last', generate(3))) for _ in range(24)]
    result = []
    for index, tree in enumerate(profiles):
        data = wire(tree, True)
        assert len(data) <= 2048 and len(all_nodes(tree)) <= 128
        actions = schedules(rng, min(len(data), index % 32))
        for layout in (0, 1): result.append(Case(tree, len(data), MASK, layout, actions))
        if data and index % 7 == 0: result.append(Case(tree, len(data) - 1, MASK, index % 2, actions))
    # Every possible first cut through these small complete wires. Later pulls
    # and copies cross the resulting escape, UTF-8 and structure continuations.
    for tree in (table(('s', text('\0é😀'))), table(('a', array(table(), array(), boolean(True)))),
                 table(('t', temporal(9, '07:32:01.1200')))):
        data = wire(tree, True)
        assert len(data) <= 61
        for cut in range(len(data) + 1):
            result.append(Case(tree, len(data), MASK, cut % 2, schedules(rng, cut)))
    # The compact literal-TAB source parses below W; no private options writes.
    witness = table(('s', text('\t' * 16)))
    assert len(wire(witness, True)) == 103 and work(witness) == 104
    for budget in (103, 104, 207, 208, MASK):
        for layout in (0, 1):
            result.append(Case(witness, 103, budget, layout, schedules(rng, 8), True))
    # Literal TAB expansion leaves the public parser ample budget below this
    # serializer boundary. Fraction scan/trim and container visits all count.
    witness = table(('s', text('\t' * 64)),
                    ('t', temporal(9, '12:34:56.' + '1234567890' * 12 + '9' + '0' * 136)),
                    ('n', array(table(('a', integer(5))), array())))
    charge = work(witness)
    for budget in (charge - 1, charge, 2 * charge - 1, 2 * charge):
        for layout in (0, 1):
            result.append(Case(witness, len(wire(witness, True)), budget, layout, schedules(rng, 11), True))
    return result


def packet(values):
    result = bytearray()
    for case in values:
        body = source(case)
        assert len(body) <= 8192 and len(case.actions) <= 32
        result += struct.pack('<5Q', len(body), case.limit, case.work, case.layout, len(case.actions)) + body
        for action in case.actions: result += struct.pack('<Iii', *action)
    return result


def header(code, amount=0): return struct.pack('<3Q', code, amount, MASK if code else 0)


def reference(case, counts=None, mutant=''):
    expected = wire(case.tree, True)
    if mutant == 'short_control': expected = expected.replace(b'\\u0009', b'\\t')
    if mutant == 'uppercase_hex': expected = expected.replace(b'\\u007f', b'\\u007F')
    if mutant == 'lost_fraction': expected = expected.replace(b'.1234567890123456789', b'.123456789')
    if mutant == 'negative_zone': expected = expected.replace(b'-00:00', b'Z')
    if mutant == 'minus_zero': expected = expected.replace(b'-0.0', b'0.0')
    charged = work(case.tree)
    if mutant == 'free_trim':
        charged -= sum(len(temporal_parts(node)['fraction']) - len(temporal_parts(node)['fraction'].rstrip('0'))
                       for node in all_nodes(case.tree) if node.kind >= 6)
    measured_code = 1 if len(expected) > case.limit else (2 if charged > case.work else 0)
    prepared_code = measured_code or (2 if 2 * charged > case.work else 0)
    if mutant == 'free_replay': prepared_code = measured_code
    if counts is not None:
        counts['measured'] += measured_code == 0
        counts['admitted'] += prepared_code == 0
        counts['output_limit'] += prepared_code == 1
        counts['work_limit'] += prepared_code == 2
        counts['wire_bytes'] += len(expected) if prepared_code == 0 else 0
    state = snapshot(case.tree)
    output = bytearray(state)
    output += header(measured_code, len(expected) if not measured_code else 0)
    output += header(prepared_code, len(expected) if not prepared_code else 0)
    output += header(prepared_code, len(expected) if not prepared_code else 0)
    if not prepared_code: output += expected
    if not prepared_code:
        output += u64(1 if case.layout else -8)
        positions = [0, 0]
        ordinal = 0
        def execute(op, offset=0, count=0):
            nonlocal ordinal
            destination = bytearray((157 + index * 13 + ordinal * 7) & 255 for index in range(64))
            output.append(op)
            if op >= 2:
                if op == 2: positions[1] = positions[0]
                if op == 3: positions[0] = positions[1]
                if op == 4: positions[0] = 0
                if op == 5: positions[1] = 0
                if mutant == 'copy_reset' and op == 2: positions[1] = 0
                output.append(2); output.extend(u64(0)); amount = 0
                if counts is not None: counts['copies'] += 1
            else:
                if counts is not None: counts['reads'] += 1
                invalid = offset < 0 or count < 0 or offset > I32_MAX - count
                if mutant == 'zero_before_bounds' and count == 0: invalid = False
                if invalid:
                    output.append(1); output.extend(u64(1)); amount = -1
                    if counts is not None: counts['invalid'] += 1
                else:
                    amount = min(count, len(expected) - positions[op])
                    if amount: destination[offset:offset + amount] = expected[positions[op]:positions[op] + amount]
                    positions[op] += amount
                    output.append(0); output.extend(u64(amount))
                    if counts is not None:
                        counts['zero_requests'] += count == 0
                        counts['eof'] += count > 0 and amount == 0
            output.extend(u64(len(expected) - positions[0]) + u64(len(expected) - positions[1]))
            output.extend(destination); ordinal += 1
            return amount
        for action in case.actions: execute(*action)
        for cursor in range(2):
            turn = 0
            while execute(cursor, 3, (1, 7, 13, 31)[turn % 4]) > 0:
                turn += 1
                assert turn <= 4096
            execute(cursor, I32_MAX, 0); execute(cursor, -1, 0); execute(cursor, 2, 3)
        execute(2); execute(1, 0, 1)
    output += state
    output += header(prepared_code, len(expected) if not prepared_code else 0)
    if not prepared_code: output += expected
    return output


def verify(actual, values):
    position = 0
    counts = Counter()
    for index, case in enumerate(values):
        expected = reference(case, counts)
        observed = actual[position:position + len(expected)]
        if observed != expected:
            first = next((at for at, pair in enumerate(zip(observed, expected)) if pair[0] != pair[1]), len(observed))
            raise AssertionError((f'seed={SEED:#x}', 'case', index, 'source', source(case),
                                  'limit/work/layout', (case.limit, case.work, case.layout),
                                  'actions', case.actions, 'byte', first,
                                  'actual', observed[first:first + 16], 'expected', expected[first:first + 16]))
        position += len(expected)
    assert position == len(actual), ('extra output', position, len(actual))
    return counts


def summary(values, counts, suffix=''):
    fields = ('measured', 'admitted', 'output_limit', 'work_limit', 'reads', 'copies',
              'invalid', 'zero_requests', 'eof', 'wire_bytes')
    return f'toml-streaming{suffix} cases={len(values)} layouts=2 ' + ' '.join(
        f'{key}={counts[key]}' for key in fields) + f' seed={SEED:#x}'


def typed_reference(node, observed):
    """Check the canonical output with Python's independent TOML 1.0 decoder.

    Our canonical bytes use explicit seconds and no TOML 1.1-only syntax.
    datetime truncates fractions and merges Z/+00:00/-00:00, so these checks
    supplement, and cannot replace, the exact byte/fraction reference above.
    """
    if node.kind == 0:
        assert type(observed) is dict and list(observed) == [key for key, _ in node.children]
        for key, child in node.children: typed_reference(child, observed[key])
    elif node.kind == 1:
        assert type(observed) is list and len(observed) == len(node.children)
        for (_, child), actual in zip(node.children, observed): typed_reference(child, actual)
    elif node.kind in (2, 3, 5):
        assert type(observed) is {2: str, 3: int, 5: bool}[node.kind] and observed == node.value
    elif node.kind == 4:
        expected = float(node.value)
        assert type(observed) is float
        assert math.isnan(observed) if math.isnan(expected) else observed == expected
        assert math.copysign(1, observed) == math.copysign(1, expected)
    else:
        fields = temporal_parts(node)
        assert type(observed) is {6: datetime.datetime, 7: datetime.datetime,
                                 8: datetime.date, 9: datetime.time}[node.kind]
        if fields['date']:
            assert (observed.year, observed.month, observed.day) == tuple(map(int, fields['date'].split('-')))
        if fields['hm']:
            assert (observed.hour, observed.minute, observed.second, observed.microsecond) == (
                *map(int, fields['hm'].split(':')), int(fields['seconds'] or 0),
                int((fields['fraction'][:6] + '000000')[:6]))
        if node.kind == 6:
            zone = fields['zone']
            minutes = 0 if zone.lower() == 'z' else (int(zone[1:3]) * 60 + int(zone[4:6])) * (-1 if zone[0] == '-' else 1)
            assert observed.utcoffset() == datetime.timedelta(minutes=minutes)


def controls():
    assert quote('\0\t\x1f\x7f"\\é') == b'"\\u0000\\u0009\\u001f\\u007f\\"\\\\\xc3\xa9"'
    assert wire(table(('x', array(integer(1), table(('z', boolean(True)))))), True) == b'"x"=[1,{"z"=true}]\n'
    assert canonical_temporal(temporal(6, '1979-05-27t07:32+00:00')) == b'1979-05-27T07:32:00Z'
    assert canonical_temporal(temporal(6, '1979-05-27t07:32:00.12000-00:00')) == b'1979-05-27T07:32:00.12-00:00'
    values = cases()
    assert packet(values)
    for case in values:
        # An additional independent TOML decoder checks type preservation, with
        # temporal precision handled above rather than truncated by datetime.
        decoded = tomllib.loads(wire(case.tree, True).decode())
        typed_reference(case.tree, decoded)
    transcript = b''.join(reference(case) for case in values)
    counts = verify(transcript, values)
    base = next(case for case in values if case.tree == table(('v', text('"\\é界😀'))))
    valid = reference(base)
    mutations = (0, 8, len(snapshot(base.tree)), len(snapshot(base.tree)) + 8,
                 len(snapshot(base.tree)) + 24, len(snapshot(base.tree)) + 72,
                 len(snapshot(base.tree)) + 72 + len(wire(base.tree, True)) + 8 + 10,
                 len(valid) - 1)
    rejected = 0
    for offset in mutations:
        changed = bytearray(valid); changed[offset] ^= 1
        try: verify(changed, [base])
        except AssertionError: rejected += 1
        else: raise AssertionError(('accepted mutation', offset))
    for changed in (valid[:-1], valid + b'\0'):
        try: verify(changed, [base])
        except AssertionError: rejected += 1
        else: raise AssertionError('accepted frame mutation')
    mutants = ('short_control', 'uppercase_hex', 'lost_fraction', 'negative_zone', 'minus_zero',
               'free_trim', 'free_replay', 'copy_reset', 'zero_before_bounds')
    for mutant in mutants:
        witnesses = [case for case in values if reference(case, mutant=mutant) != reference(case)]
        assert witnesses, ('vacuous mutant', mutant)
        try: verify(reference(witnesses[0], mutant=mutant), witnesses[:1])
        except AssertionError: rejected += 1
        else: raise AssertionError(('accepted semantic mutant', mutant))
    assert rejected == 19
    print(summary(values, counts, ' CPU') + f' controls={rejected} transcript_bytes={len(transcript)}')


def main():
    if len(sys.argv) == 2 and sys.argv[1] == 'controls': controls(); return
    assert len(sys.argv) == 2, 'usage: oracle.py <executable> | controls'
    values = cases()
    process = subprocess.run([str(Path(sys.argv[1]).resolve())], input=packet(values),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=75)
    assert process.returncode == 0, (process.returncode, process.stderr, len(process.stdout))
    assert not process.stderr, process.stderr
    print(summary(values, verify(process.stdout, values)))


if __name__ == '__main__': main()
