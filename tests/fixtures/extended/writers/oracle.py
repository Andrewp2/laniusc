"""Round-trip oracle for ext::yaml_writer and ext::toml_writer.

usage: python3 -I oracle.py BATCH_EXE [--seed N] [--trees N]

BATCH_EXE is tests/fixtures/extended/writers/batch.lani compiled. Each tree
is written as JSON (with chosen number spellings), parsed by ext::json_tree
and written by the Lanius writer. Then:

- YAML: PyYAML 6.0.1 yaml.safe_load of the output must equal the tree, and
  ext::yaml must read the output back to the same tree (numbers compared as
  exact decimals, so 1e3 and 1.0e+3 agree).
- TOML: Python tomllib.loads of the output must equal the tree. Floats are
  read with parse_float=str, so their spelling must be exactly the tree's;
  integers compare exactly. Table member order is not kept (TOML puts
  key/value pairs before sub-tables), so objects compare as mappings.
- Errors: the TOML writer must reject non-object roots (NotTable), null
  (NullValue) and integers outside i64 (IntegerRange).

Prints `group agree/total` lines and exits 1 on any disagreement.
"""

import decimal
import json
import random
import subprocess
import sys
import tomllib

import yaml


class Num:
    def __init__(self, spelling):
        self.spelling = spelling


def to_json(value):
    if isinstance(value, Num):
        return value.spelling
    if isinstance(value, dict):
        return '{' + ','.join(json.dumps(k, ensure_ascii=False) + ':' + to_json(v) for k, v in value.items()) + '}'
    if isinstance(value, list):
        return '[' + ','.join(to_json(v) for v in value) + ']'
    return json.dumps(value, ensure_ascii=False)


def is_float(spelling):
    return any(c in spelling for c in '.eE')


def same_py(expected, got):
    """expected: a tree with Num; got: PyYAML or tomllib output (floats as float or ('f', text))."""
    if isinstance(expected, Num):
        if is_float(expected.spelling):
            if isinstance(got, tuple):
                return got == ('f', expected.spelling)
            return isinstance(got, float) and got == float(expected.spelling)
        return type(got) is int and got == int(expected.spelling)
    if isinstance(expected, bool) or expected is None:
        return type(got) is type(expected) and got == expected
    if isinstance(expected, str):
        return isinstance(got, str) and got == expected
    if isinstance(expected, list):
        return isinstance(got, list) and len(got) == len(expected) and all(same_py(a, b) for a, b in zip(expected, got))
    if isinstance(expected, dict):
        return isinstance(got, dict) and set(got) == set(expected) and all(same_py(expected[k], got[k]) for k in expected)
    return False


def same_lanius(expected, got, ordered=True):
    """got: ext::yaml's JSON read with Decimal floats."""
    if isinstance(expected, Num):
        if is_float(expected.spelling):
            return isinstance(got, decimal.Decimal) and got == decimal.Decimal(expected.spelling)
        return type(got) is int and got == int(expected.spelling)
    if isinstance(expected, bool) or expected is None:
        return type(got) is type(expected) and got == expected
    if isinstance(expected, str):
        return isinstance(got, str) and got == expected
    if isinstance(expected, list):
        return isinstance(got, list) and len(got) == len(expected) and all(same_lanius(a, b) for a, b in zip(expected, got))
    if isinstance(expected, dict):
        return isinstance(got, dict) and list(got) == list(expected) and all(same_lanius(expected[k], got[k]) for k in expected)
    return False


# Values -----------------------------------------------------------------------

TRICKY = [
    '', ' ', 'plain', 'Hello world', 'two  spaces', ' lead', 'trail ', 'yes', 'No', 'ON', 'off', 'y', 'N', 'true', 'False',
    'null', 'Null', '~', '=', '<<', '0', '-1', '+1', '.5', '1e3', '1.5e3', '0x1F', '0o17', '010', '1_000', '1:20',
    '2001-12-14', '.inf', '-.Inf', '.NaN', '---', '...', '--- x', '- x', '-x', '? x', '?x', ': x', ':x', 'x:', 'a: b',
    'a:b', '#x', 'a #b', 'a#b', '&a', '*a', '!t', '!!str', '%x', '@x', '`x', '|', '>', '[x]', '{x}', 'x,y', 'x]', "'q'",
    '"q"', 'a"b', "a'b", 'back\\slash', 'tab\there', 'new\nline', 'cr\rhere', 'nul\x00', 'bell\x07', 'esc\x1b', 'del\x7f',
    'nel\x85x', 'c1\x9f', 'nbsp\xa0', 'ls x', 'ps x', 'bom﻿x', 'nonchar￾', 'é', 'éa', '日本語', 'emoji 😀',
    '😀', 'ß:', '/path/to', '_under', 'a-b', 'x.y.z', 'CamelCase', 'ends with colon:', 'mid: colon', 'a ', 'A' * 300,
    'k' * 1100, 'line one\nline two', 'line\n', 'keep\n\n', 'keep\n\n\n', '\nlead', ' indented\nx', 'a\n  more\nb',
    'a\n\nb', 'a\n \nb', 'a\n   ', 'tab\n\tline', 'a\r\nb', 'x\n---\ny', 'x\n...\n', 'é\n日本\n', 'nel\n\x85', '#c\n#d',
]
WORDS = ['alpha', 'beta', 'x', 'name', 'value', 'id', 'Hello', 'path/to', 'é', 'a-b', 'snake_case', 'v1.2.3']
INTS = ['0', '-0', '7', '-12', '1234567890123', '9223372036854775807', '-9223372036854775808', '123456789012345678901234567890']
FLOATS = ['1.5', '-0.25', '0.0', '-0.0', '1e3', '1E3', '1e+3', '1E-7', '2.5e10', '6.02214076e23', '1.0', '100.000',
          '0.1', '3.141592653589793238', '1e400', '-1e-400', '5e-324', '1.7976931348623157e308']


def string(rng):
    r = rng.random()
    if r < 0.5:
        return rng.choice(TRICKY)
    if r < 0.8:
        return rng.choice(WORDS)
    pieces = [rng.choice(TRICKY + WORDS) for _ in range(rng.randrange(1, 4))]
    return rng.choice([' ', '', '\n', ': ', '#']).join(pieces)


def key(rng):
    r = rng.random()
    if r < 0.6:
        return rng.choice(WORDS)
    return string(rng)


def scalar(rng, toml=False):
    r = rng.random()
    if r < 0.1 and not toml:
        return None
    if r < 0.2:
        return rng.random() < 0.5
    if r < 0.4:
        choices = INTS[:-1] if toml else INTS
        return Num(rng.choice(choices))
    if r < 0.55:
        return Num(rng.choice(FLOATS))
    return string(rng)


def tree(rng, depth, toml=False):
    r = rng.random()
    if depth <= 0 or r < 0.35:
        return scalar(rng, toml)
    if r < 0.6:
        n = rng.randrange(0, 5)
        if toml and rng.random() < 0.3:
            return [mapping(rng, depth - 1, toml) for _ in range(n)]  # an array of tables
        return [tree(rng, depth - 1, toml) for _ in range(n)]
    return mapping(rng, depth - 1, toml)


def mapping(rng, depth, toml=False):
    out = {}
    for _ in range(rng.randrange(0, 5)):
        out[key(rng)] = tree(rng, depth, toml)
    return out


# Running ----------------------------------------------------------------------

def run(exe, records):
    data = b''.join(('%s %d\n' % (mode, len(text.encode('utf-8')))).encode() + text.encode('utf-8') for mode, text in records)
    result = subprocess.run([exe], input=data, capture_output=True, timeout=240)
    if result.returncode != 0:
        raise SystemExit('batch exited %d %r' % (result.returncode, result.stderr[:300]))
    out, at, results = result.stdout, 0, []
    for mode, _ in records:
        end = out.index(b'\n', at)
        head = out[at:end].decode()
        at = end + 1
        if not head.startswith('ok '):
            results.append((head, None, None))
            continue
        size = int(head[3:])
        doc = out[at:at + size].decode('utf-8')
        at += size + 1
        back = None
        if mode == 'Y':
            end = out.index(b'\n', at)
            back = out[at:end].decode('utf-8')
            at = end + 1
        results.append(('ok', doc, back))
    return results


def check_yaml(value, doc, back):
    try:
        loaded = yaml.safe_load(doc)
    except yaml.YAMLError as error:
        return 'PyYAML: %s' % type(error).__name__
    if not same_py(value, loaded):
        return 'PyYAML read %r' % (loaded,)
    if not back.startswith('ok '):
        return 'ext::yaml: ' + back
    got = json.loads(back[3:], parse_float=decimal.Decimal)
    if not same_lanius(value, got):
        return 'ext::yaml read ' + back[:300]
    return None


def check_toml(value, doc):
    try:
        loaded = tomllib.loads(doc, parse_float=lambda s: ('f', s))
    except tomllib.TOMLDecodeError as error:
        return 'tomllib: %s' % error
    if not same_py(value, loaded):
        return 'tomllib read %r' % (loaded,)
    return None


def numbers(value):
    """Hand-written cases use Python ints; the oracle compares Num spellings."""
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, int):
        return Num(str(value))
    if isinstance(value, list):
        return [numbers(v) for v in value]
    if isinstance(value, dict):
        return {k: numbers(v) for k, v in value.items()}
    return value


YAML_CASES = [
    {}, [], 'x', '', None, True, Num('1e3'), Num('-0'), {'a': {}}, {'a': []}, [[], {}], [[[1]]], [{'a': 1, 'b': [2]}],
    {'k' * 1100: 1, 'b': {'k' * 300: [1]}}, ['keep\n\n'], {'a': 'keep\n\n', 'b': 1}, 'line\n', {'': ''},
    {'null': 1, 'true': 2, '1': 3, '-': 4, '? x': 5, '': 6}, [{'a': [{'b': 'x\ny'}]}],
]
TOML_CASES = [
    {}, {'a': {}}, {'a': []}, {'a': [{}]}, {'a': [{}, {}]}, {'a': [1, {}]}, {'a': [[{'b': 1}]]}, {'': 1, 'a b': {'': 2}},
    {'a.b': {'c.d': [{'e': {'f': 1}}]}}, {'x': {'y': {'z': {}}}}, {'n': Num('9223372036854775807'), 'm': Num('-9223372036854775808')},
    {'f': [Num('1e3'), Num('-0.0'), Num('1E-7')]}, {'s': 'tab\tquote"back\\nl\ncr\rnul\x00del\x7fnel\x85ls 😀'},
    {'a': [{'b': [{'c': 1}], 'd': 2}], 'e': 3},
]
TOML_ERRORS = [
    ('[]', 'NotTable'), ('1', 'NotTable'), ('"x"', 'NotTable'), ('null', 'NotTable'), ('{"a":null}', 'NullValue'),
    ('{"a":[1,null]}', 'NullValue'), ('{"a":{"b":{"c":null}}}', 'NullValue'), ('{"a":[{"b":null}]}', 'NullValue'),
    ('{"a":9223372036854775808}', 'IntegerRange'), ('{"a":-9223372036854775809}', 'IntegerRange'),
    ('{"a":[123456789012345678901234567890]}', 'IntegerRange'),
]


def main():
    args = sys.argv[1:]
    seed, count = 7, 3000
    if '--seed' in args:
        seed = int(args[args.index('--seed') + 1])
    if '--trees' in args:
        count = int(args[args.index('--trees') + 1])
    exe = args[0]
    rng = random.Random(seed)
    yaml_trees = [numbers(v) for v in YAML_CASES] + [tree(rng, 4) for _ in range(count)] + [string(rng) for _ in range(count // 10)]
    toml_trees = [numbers(v) for v in TOML_CASES] + [mapping(rng, 4, toml=True) for _ in range(count)]
    records = [('Y', to_json(v)) for v in yaml_trees] + [('T', to_json(v)) for v in toml_trees] + [('T', t) for t, _ in TOML_ERRORS]
    results = run(exe, records)
    failed = 0

    def show(*parts):
        if failed <= 10:
            print('DIFF', *parts)

    ok = 0
    plain = quoted = literal = 0
    for value, (status, doc, back) in zip(yaml_trees, results):
        problem = 'writer: ' + status if status != 'ok' else check_yaml(value, doc, back)
        if problem is None:
            ok += 1
        else:
            failed += 1
            show('yaml', repr(to_json(value))[:300], '\n  ', problem, '\n  output', repr(doc)[:400])
        if doc:
            for line in doc.split('\n'):
                body = line.lstrip(' -')
                if ': ' in body:
                    body = body.split(': ', 1)[1]
                quoted += body.startswith('"')
                literal += body.startswith('|')
    print('yaml %d/%d' % (ok, len(yaml_trees)))
    print('yaml scalars: %d double-quoted, %d literal blocks' % (quoted, literal))

    ok = 0
    toml_results = results[len(yaml_trees):len(yaml_trees) + len(toml_trees)]
    for value, (status, doc, back) in zip(toml_trees, toml_results):
        problem = 'writer: ' + status if status != 'ok' else check_toml(value, doc)
        if problem is None:
            ok += 1
        else:
            failed += 1
            show('toml', repr(to_json(value))[:300], '\n  ', problem, '\n  output', repr(doc)[:400])
    print('toml %d/%d' % (ok, len(toml_trees)))

    ok = 0
    for (text, kind), (status, doc, back) in zip(TOML_ERRORS, results[len(yaml_trees) + len(toml_trees):]):
        good = status.startswith('err %s ' % kind)
        ok += good
        if not good:
            failed += 1
            show('toml error', text, kind, status)
    print('toml errors %d/%d' % (ok, len(TOML_ERRORS)))
    print('disagreements', failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
