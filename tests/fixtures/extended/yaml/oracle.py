"""Oracle: ext::yaml against PyYAML 6.0.1 (yaml.safe_load_all), compared as JSON.

usage: python3 -I oracle.py BATCH_EXE [--seed N] [--docs N]

BATCH_EXE is tests/fixtures/extended/yaml/batch.lani compiled. Groups:

- agree: hand-written documents (YAML 1.2 spec chapter 2 examples typed from
  memory, and one or more cases per feature) where YAML 1.1 and 1.2 read the
  same. ext::yaml must equal PyYAML.
- differ: documents where YAML 1.2 (ext::yaml) and YAML 1.1 (PyYAML) differ,
  or where ext::yaml's policy differs. Each has the expected ext::yaml result
  written by hand; PyYAML's result is printed for the record.
- errors: each ext::yaml error kind, with its expected kind; PyYAML must
  also reject the document unless the case says otherwise.
- generated: random documents (block and flow collections, every scalar
  style, chomping, anchors and aliases, comments, several documents) built
  from a known value. That value, PyYAML and ext::yaml must all agree.

PyYAML raising ValueError on a recursive or out-of-range value (when it is
turned into JSON) counts as a rejection.

Values are compared as JSON: ints exactly, floats as binary doubles, strings
exactly (PyYAML strings pass through JSON so surrogate pairs combine).
Prints `group agree/total` lines and exits 1 on any disagreement.
"""

import decimal
import json
import math
import random
import subprocess
import sys

import yaml


def lanius_value(text):
    return json.loads(text, parse_float=decimal.Decimal, parse_int=int)


def py_value(value):
    """PyYAML's result as JSON values (dates and other objects fail)."""
    return json.loads(json.dumps(value, ensure_ascii=True, allow_nan=True), parse_float=float)


def same(a, b):
    """a from ext::yaml (Decimal floats), b from Python (float or int)."""
    if isinstance(a, bool) or a is None or isinstance(b, bool) or b is None:
        return type(a) is type(b) and a == b
    if isinstance(a, (int, decimal.Decimal)) and isinstance(b, (int, float, decimal.Decimal)):
        if not (isinstance(a, int) and isinstance(b, int)):
            return float(a) == float(b) or (math.isnan(float(b)) and math.isnan(float(a)))
        return a == b
    if isinstance(a, str) or isinstance(b, str):
        return a == b
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return list(a) == list(b) and all(same(a[k], b[k]) for k in a)
    return False


def pyyaml(text, single=False):
    try:
        if single:
            return 'ok', py_value(yaml.safe_load(text))
        return 'ok', py_value(list(yaml.safe_load_all(text)))
    except Exception as error:  # yaml.YAMLError, or a value JSON cannot hold
        return 'err', type(error).__name__


# Hand-written cases -----------------------------------------------------------

AGREE = [
    # YAML 1.2 spec chapter 2 (examples 2.1-2.10, 2.12-2.18, 2.21, 2.23, 2.27 shapes).
    '- Mark McGwire\n- Sammy Sosa\n- Ken Griffey\n',
    'hr:  65    # Home runs\navg: 0.278 # Batting average\nrbi: 147   # Runs Batted In\n',
    'american:\n  - Boston Red Sox\n  - Detroit Tigers\nnational:\n  - New York Mets\n  - Chicago Cubs\n',
    '-\n  name: Mark McGwire\n  hr:   65\n  avg:  0.278\n-\n  name: Sammy Sosa\n  hr:   63\n  avg:  0.288\n',
    '- [name        , hr, avg  ]\n- [Mark McGwire, 65, 0.278]\n- [Sammy Sosa  , 63, 0.288]\n',
    'Mark McGwire: {hr: 65, avg: 0.278}\nSammy Sosa: {\n    hr: 63,\n    avg: 0.288\n  }\n',
    '# Ranking of 1998 home runs\n---\n- Mark McGwire\n- Sammy Sosa\n- Ken Griffey\n\n# Team ranking\n---\n- Chicago Cubs\n- St Louis Cardinals\n',
    '---\ntime: 20h03\nplayer: Sammy Sosa\naction: strike (miss)\n...\n---\ntime: 20h04\nplayer: Sammy Sosa\naction: grand slam\n...\n',
    '---\nhr: # 1998 hr ranking\n  - Mark McGwire\n  - Sammy Sosa\nrbi:\n  # 1998 rbi ranking\n  - Sammy Sosa\n  - Ken Griffey\n',
    '---\nhr:\n  - Mark McGwire\n  # Following node labeled SS\n  - &SS Sammy Sosa\nrbi:\n  - *SS # Subsequent occurrence\n  - Ken Griffey\n',
    '---\n# Products purchased\n- item    : Super Hoop\n  quantity: 1\n- item    : Basketball\n  quantity: 4\n- item    : Big Shoes\n  quantity: 1\n',
    '# ASCII Art\n--- |\n  \\//||\\/||\n  // ||  ||__\n',
    '>\n  Mark McGwire\'s\n  year was crippled\n  by a knee injury.\n',
    '>\n Sammy Sosa completed another\n fine season with great stats.\n\n   63 Home Runs\n   0.288 Batting Average\n\n What a year!\n',
    'name: Mark McGwire\naccomplishment: >\n  Mark set a major league\n  home run record in 1998.\nstats: |\n  65 Home Runs\n  0.278 Batting Average\n',
    'unicode: "Sosa did fine.\\u263A"\ncontrol: "\\b1998\\t1999\\t2000\\n"\nhex esc: "\\x0d\\x0a is \\r\\n"\n\nsingle: \'"Howdy!" he cried.\'\nquoted: \' # Not a \'\'comment\'\'.\'\ntie-fighter: \'|\\-*-/|\'\n',
    'plain:\n  This unquoted scalar\n  spans many lines.\n\nquoted: "So does this\n  quoted scalar.\\n"\n',
    'canonical: 12345\ndecimal: +12345\nhexadecimal: 0xC\n',
    'canonical: 1.23015e+3\nexponential: 12.3015e+02\nfixed: 1230.15\n',
    'null:\nbooleans: [ true, false ]\nstring: \'012345\'\n',
    '---\nnot-date: !!str 2002-04-28\n',
    # Block collections and indentation.
    'a:\n  b:\n    c: 1\n  d: 2\ne: 3\n',
    'a:\n- 1\n- 2\nb: x\n',
    '- - a\n  - b\n- - c\n',
    '- a: 1\n  b:\n  - x\n  - y\n- c\n',
    'a:\n    deep: 1\nb:  [1, 2]\n',
    '-\n-\n- x\n',
    'a:\nb: 1\n',
    '- \n  a: 1\n',
    '? a\n: 1\n? b\n',
    '? a\n:\n  - 1\n',
    # Flow collections.
    '[a, [b, c], {d: e}, [], {}]',
    '{a: 1, b: [2, 3], c: {d: 4}}',
    '[a, b, ]',
    '{a, b: 2}',
    '[a: 1, b: 2]',
    '[? a : 1]',
    '{"a": 1, \'b\': 2}',
    '[ "quoted, comma", \'single\' ]',
    '{a: [1,\n  2],\n b: 3}',
    '[a:b, c]',
    'k: [ x , y ]   # trailing comment',
    # Scalars.
    'a: plain text with  spaces\nb: x#y\nc: a:b\nd: -x\ne: ?y\n',
    'a: "esc \\" \\\\ \\/ \\t \\n \\0 \\e \\a"\n',
    "a: 'it''s'\nb: ''\nc: \"\"\n",
    'a: "multi\n  line\n\n  para"\n',
    "a: 'multi\n  line\n\n  para'\n",
    'a: "line \\\n  joined"\n',
    'a: |\n  keep\n  lines\n\nb: x\n',
    'a: |-\n  strip\n\n\nb: x\n',
    'a: |+\n  keep\n\n\nb: x\n',
    'a: >\n  folded\n  lines\n\n  next\n',
    'a: >-\n  folded\n   more\n  back\n',
    'a: >+\n  x\n\n',
    'a: |2\n    two extra\n  base\n',
    'a: |\n\n  leading blank\n',
    'a: | # comment\n  text\n',
    '- |\n  in seq\n- >\n  folded\n  seq\n',
    'a: |\n  x\nb: |\n  y\n',
    '--- |\n  doc\n',
    '"\\u00e9\\U0001F600\\x41"',
    '"\\ud83d\\ude00"',
    'é: ü\n日本: 語',
    # Core schema values both versions agree on.
    '[null, Null, NULL, ~, true, True, TRUE, false, False, FALSE]',
    '[0, 12, -7, +3, 0x1F, 0xff, 1.5, -0.25, 2.5e+3, 1.0, .5, 0.0]',
    '[1.e+2, 123456789012345678901234567890]',
    '[ "true", \'1\', "null" ]',
    'a: !!str 12\nc: !<tag:yaml.org,2002:str> true\n',
    # Anchors and aliases.
    'a: &x {b: 1}\nc: *x\nd: *x\n',
    '- &a [1, 2]\n- *a\n- &b x\n- *b\n',
    'base: &base\n  x: 1\nother: *base\n',
    '- &a\n  k: v\n- *a\n',
    '[&a x, *a]',
    '&doc {a: 1}',
    # Documents and comments.
    '--- 1\n--- 2\n--- 3\n',
    '--- a\n...\n--- b\n...\n',
    '# only a comment\n',
    '',
    '---\n',
    '--- # comment\n- a\n',
    '%YAML 1.2\n---\na: 1\n',
    '%YAML 1.1\n--- x\n',
    '%FOO bar baz\n--- 1\n',
    'a: 1 # c1\n# c2\nb: 2 # c3\n',
    '\ufeffa: 1\n',
    'a: 1\r\nb:\r\n  - x\r\n',
    '{a: 1}\n--- [2]\n',
]

# (document, expected ext::yaml output, note): 1.1 versus 1.2 and policy.
DIFFER = [
    ('[yes, no, on, off, y, n, Yes, NO]', 'ok [["yes","no","on","off","y","n","Yes","NO"]]', '1.1 booleans are strings in 1.2'),
    ('a: 010', 'ok [{"a":10}]', '1.1 octal 010 is decimal 10 in 1.2'),
    ('a: 0o17', 'ok [{"a":15}]', '0o17 is octal in 1.2, a string in 1.1'),
    ('a: 0b101', 'ok [{"a":"0b101"}]', 'binary integers are 1.1 only'),
    ('a: 1e3', 'ok [{"a":1e3}]', '1.2 floats need no dot or exponent sign'),
    ('a: 1.5e3', 'ok [{"a":1.5e3}]', 'PyYAML requires an exponent sign'),
    ('a: -.5', 'ok [{"a":-0.5}]', 'PyYAML reads a signed .5 as a string'),
    ('a: 1_000', 'ok [{"a":"1_000"}]', 'digit separators are 1.1 only'),
    ('a: 1:20', 'ok [{"a":"1:20"}]', 'sexagesimal numbers are 1.1 only'),
    ('time: 20:03:20', 'ok [{"time":"20:03:20"}]', 'spec example 2.8; PyYAML reads 72200'),
    ('[+.5e+1]', 'ok [[5]]', 'PyYAML requires a digit before the dot of a signed float'),
    ('! 12', 'ok ["12"]', 'the non-specific tag ! makes a scalar a string in 1.2'),
    ('a: 0x_1F', 'ok [{"a":"0x_1F"}]', 'digit separators are 1.1 only'),
    ('a: 2001-12-14', 'ok [{"a":"2001-12-14"}]', 'timestamps are 1.1 only (PyYAML builds a date)'),
    ('a: =', 'ok [{"a":"="}]', 'the 1.1 value key = is a string'),
    ('base: &b {x: 1}\nm:\n  <<: *b\n  y: 2', 'ok [{"base":{"x":1},"m":{"<<":{"x":1},"y":2}}]', 'merge keys are 1.1 only'),
    ('a:\tb', 'ok [{"a":"b"}]', 'tabs may separate tokens within a line in 1.2'),
    ('a: 1\t# c', 'ok [{"a":1}]', 'tabs before a comment'),
    ('a: x\ty', 'ok [{"a":"x\\ty"}]', 'tabs inside plain scalars'),
    ('- a\n  \n  \t\n  b\n', 'ok [["a\\n\\nb"]]', 'a tab after the indentation of an empty line'),
    ('[a?b]', 'ok [["a?b"]]', '1.2 allows ? inside flow plain scalars'),
    ('&a.b x', 'ok ["x"]', '1.2 anchor names allow any non-indicator character'),
    ('- &a x\n- &a y\n- *a', 'ok [["x","y","y"]]', '1.2 lets an anchor be redefined'),
    ('a\n...\nb', 'ok ["a","b"]', '1.2 allows a bare document after ...'),
    ('a: 1\na: 2', 'err DuplicateKey 1 0', 'duplicate keys are errors in 1.2; PyYAML keeps the last'),
    ('1.50: a', 'ok [{"1.50":"a"}]', 'number keys keep their spelling'),
    ('!!int 3', 'err Unsupported 0 0', 'only !!str and ! tags are supported'),
    ('a: .inf', 'err NonFinite 0 3', 'JSON has no infinity'),
    ('[.nan]', 'err NonFinite 0 1', 'JSON has no NaN'),
    ('&a [*a]', 'err RecursiveAlias 0 4', 'PyYAML builds a recursive list'),
    ('"\\ud800"', 'err InvalidEscape 0 1', 'a lone surrogate escape'),
    ('a: \x85b', 'ok [{"a":"\x85b"}]', 'NEL is not a line break in 1.2'),
]

# (document, expected kind, PyYAML also rejects, mode, nodes, aliases, depth)
LAUGHS = 'a: &a [x, x, x, x, x, x, x, x, x, x]\n' + ''.join(
    '%s: &%s [%s]\n' % (chr(98 + i), chr(98 + i), ', '.join(['*' + chr(97 + i)] * 10)) for i in range(6))
ERRORS = [
    ('[a, b', 'Syntax', True), ('{a: 1', 'Syntax', True), ('"open', 'Syntax', True), ("'open", 'Syntax', True),
    ('a:\n  b: 1\n c: 2', 'Syntax', True), ('a: b: c', 'Syntax', True), ('- a\nb: c', 'Syntax', True),
    ('a: 1\n- b', 'Syntax', True), ('[a] b', 'Syntax', True), ('{a: 1} }', 'Syntax', True), (']', 'Syntax', True),
    ('a:\n\tb: 1', 'Syntax', True), ('- a\n\t- b', 'Syntax', True), ('key: "a\n---\nb"', 'Syntax', True),
    ('a: |0\n  x', 'Syntax', True), ('a: |x\n  y', 'Syntax', True), ('@a', 'Syntax', True), ('`a', 'Syntax', True),
    ('a: &\n', 'Syntax', True), ('*', 'Syntax', True), ('---\na\nb: c', 'Syntax', True), ('%YAML 1\n--- a', 'Syntax', True),
    ('[a, b]\n- c', 'Syntax', True), ('- a\n\t\n  b', 'Syntax', True), ('a: 1\nb', 'Syntax', True), ('{: 1}', 'Syntax', True),
    ('a: "\\q"', 'InvalidEscape', True), ('a: "\\xZZ"', 'InvalidEscape', True), ('a: "\\u12"', 'InvalidEscape', True),
    ('a: "\\ud83d\\u0041"', 'InvalidEscape', False), ('"\\U00110000"', 'InvalidEscape', True),
    ('a: \x01', 'InvalidCharacter', True), ('a: \x7f', 'InvalidCharacter', True), ('a: \u0080', 'InvalidCharacter', True),
    ('a: \ufffe', 'InvalidCharacter', True),
    ('%TAG ! tag:example.com,2000:\n--- a', 'Unsupported', False), ('!foo x', 'Unsupported', True),
    ('!!map {}', 'Unsupported', False), ('%YAML 2.0\n--- a', 'Unsupported', True),
    ('*x', 'UnknownAlias', True), ('a: &x 1\n---\nb: *x', 'UnknownAlias', True), ('[*a, &a 1]', 'UnknownAlias', True),
    ('- &a\n  - *a', 'RecursiveAlias', True), ('{a: &m {b: *m}}', 'RecursiveAlias', True),
    ('? [a]\n: b', 'NonScalarKey', True), ('{[a]: b}', 'NonScalarKey', True), ('? - a\n: b', 'NonScalarKey', True),
    ('? {a: 1}\n: b', 'NonScalarKey', True), ('[[a]: b]', 'NonScalarKey', True),
    ('{a: 1, a: 2}', 'DuplicateKey', False), ('a: 1\n"a": 2', 'DuplicateKey', False), ('[a: 1]\n', None, False),
    ('x: !!str [a]', 'InvalidTag', True), ('!!str {a: 1}', 'InvalidTag', True),
    ('-.inf', 'NonFinite', False), ('.NaN', 'NonFinite', False),
]
LIMITED = [
    # (mode, nodes, aliases, depth, document, expected kind)
    ('A', 0, 0, 0, LAUGHS, 'AliasLimit'),
    ('A', 0, 100, 0, 'a: &a [1, 2, 3]\nb: [*a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a]', 'AliasLimit'),
    ('A', 0, 104, 0, 'a: &a [1, 2, 3]\nb: [*a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a, *a]', None),
    ('A', 0, 0, 0, '[' * 300 + ']' * 300, 'DepthLimit'),
    ('A', 0, 0, 2, '[[[1]]]', 'DepthLimit'),
    ('A', 0, 0, 3, '[[[1]]]', None),
    ('A', 0, 0, 2, 'a:\n  b:\n    c: 1', 'DepthLimit'),
    ('A', 5, 0, 0, '[1, 2, 3, 4]', 'NodeLimit'),
    ('A', 6, 0, 0, '[1, 2, 3, 4]', None),
    ('S', 0, 0, 0, '--- 1\n--- 2', 'MultipleDocuments'),
    ('S', 0, 0, 0, '', None),
    ('S', 0, 0, 0, 'a: 1', None),
]


# Generated documents ----------------------------------------------------------

WORDS = ['alpha', 'beta', 'gamma', 'x', 'Hello world', 'a-b', 'a.b', 'path/to', 'é', '日本語', 'with:colon', 'hash#in',
         'two  spaces', 'tail-', 'CamelCase', 'snake_case', 'q?mark', 'v1.2.3']
FLOW_WORDS = ['alpha', 'beta', 'x', 'Hello world', 'a-b', 'a.b', 'é', 'snake_case', 'v1.2.3', 'hash#in', 'with:colon']
KEYS = ['name', 'id', 'value', 'items', 'k', 'long key', 'é', 'a.b', 'x-y']
NUMBERS = [('0', 0), ('7', 7), ('-12', -12), ('+3', 3), ('1234567890123', 1234567890123), ('0x1F', 31),
           ('1.5', 1.5), ('-0.25', -0.25), ('2.5e+3', 2500.0), ('1.0', 1.0), ('.5', 0.5), ('0.0', 0.0)]
SPECIALS = ['tab\there', 'quote"in', "apos'in", 'back\\slash', 'new\nline', 'bell\x07', 'emoji 😀', '', ' lead', 'trail ',
            'true', 'null', '123', '- dash', '#hash', 'a: b', '[x]', '{y}', 'yes', '010', '1e3']


class Gen:
    def __init__(self, rng):
        self.rng = rng
        self.anchors = []
        self.count = 0

    def value(self, depth):
        r = self.rng.random()
        if depth <= 0 or r < 0.45:
            return self.scalar()
        if r < 0.72:
            return [self.value(depth - 1) for _ in range(self.rng.randrange(0, 4))]
        keys = self.rng.sample(KEYS, self.rng.randrange(0, 4))
        return {k: self.value(depth - 1) for k in keys}

    def scalar(self):
        r = self.rng.random()
        if r < 0.08:
            return None
        if r < 0.16:
            return self.rng.random() < 0.5
        if r < 0.36:
            return ('num', self.rng.choice(NUMBERS))
        if r < 0.75:
            return self.rng.choice(WORDS)
        if r < 0.9:
            return self.rng.choice(SPECIALS)
        lines = [self.rng.choice(['line one', 'two', 'with # hash', 'quote " and \'', 'é']) for _ in range(self.rng.randrange(1, 4))]
        return ('block', lines)


def intended(value):
    if isinstance(value, tuple):
        return value[1][1] if value[0] == 'num' else value
    if isinstance(value, list):
        return [intended(v) for v in value]
    if isinstance(value, dict):
        return {k: intended(v) for k, v in value.items()}
    return value


def double_quote(text):
    out = ['"']
    for ch in text:
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ch == '\n':
            out.append('\\n')
        elif ch == '\t':
            out.append('\\t')
        elif ord(ch) < 32:
            out.append('\\x%02x' % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


class Emitter:
    def __init__(self, rng):
        self.rng = rng
        self.anchors = []   # (name, value) of complete anchored nodes
        self.next = 0

    def string(self, text, flow):
        words = FLOW_WORDS if flow else WORDS
        r = self.rng.random()
        if text in words and r < 0.6:
            return text
        if "\n" not in text and all(ord(c) >= 32 for c in text) and r < 0.8:
            return "'" + text.replace("'", "''") + "'"
        return double_quote(text)

    def scalar(self, value, flow):
        """(text, value) for a scalar."""
        if value is None:
            return self.rng.choice(['null', '~', 'Null']), None
        if value is True or value is False:
            return self.rng.choice(['true', 'True'] if value else ['false', 'False']), value
        if isinstance(value, tuple) and value[0] == 'num':
            return value[1][0], value[1][1]
        if isinstance(value, tuple):
            text = ' '.join(value[1])
            return self.string(text, flow), text
        return self.string(value, flow), value

    def anchor(self):
        if self.rng.random() < 0.12:
            self.next += 1
            return 'a%d' % self.next
        return None

    def alias(self):
        if self.anchors and self.rng.random() < 0.1:
            name, value = self.rng.choice(self.anchors)
            return '*' + name, value
        return None

    def flow(self, value):
        """(text, intended) in flow context."""
        hit = self.alias()
        if hit:
            return hit
        name = self.anchor()
        prefix = '&%s ' % name if name else ''
        if isinstance(value, list):
            parts = [self.flow(v) for v in value]
            text, result = '[' + ', '.join(p[0] for p in parts) + ']', [p[1] for p in parts]
        elif isinstance(value, dict):
            parts = [(k, self.flow(v)) for k, v in value.items()]
            text = '{' + ', '.join('%s: %s' % (self.string(k, True), p[0]) for k, p in parts) + '}'
            result = {k: p[1] for k, p in parts}
        else:
            text, result = self.scalar(value, True)
        if name:
            self.anchors.append((name, result))
        return prefix + text, result

    def block_scalar(self, lines, indent):
        style = self.rng.choice(['|', '|-', '|+', '>', '>-'])
        pad = ' ' * indent
        body = ''.join(pad + line + '\n' for line in lines)
        if style[0] == '|':
            text = '\n'.join(lines)
        else:
            text = ' '.join(lines)
        if style.endswith('-'):
            result = text
        elif style.endswith('+'):
            extra = self.rng.randrange(0, 3)
            body += '\n' * extra
            result = text + '\n' + '\n' * extra
        else:
            result = text + '\n'
        return style + '\n' + body, result

    def block(self, value, indent, after):
        """Text for value after `key:` or `- ` (after says which), ending with a newline."""
        hit = self.alias()
        if hit:
            return ' ' + hit[0] + self.comment() + '\n', hit[1]
        step = self.rng.choice([1, 2, 2, 4])
        if isinstance(value, tuple) and value[0] == 'block':
            text, result = self.block_scalar(value[1], indent + step)
            return ' ' + text, result
        if isinstance(value, (list, dict)) and value and self.rng.random() < 0.8:
            name = self.anchor()
            head = (' &' + name if name else '') + '\n'
            child = indent + step
            if isinstance(value, list) and after == 'key' and self.rng.random() < 0.4:
                child = indent  # an indentless sequence
            if isinstance(value, list):
                body, result = self.sequence(value, child)
            else:
                body, result = self.mapping(value, child)
            if name:
                self.anchors.append((name, result))
            return head + body, result
        text, result = self.flow(value)
        return ' ' + text + self.comment() + '\n', result

    def comment(self):
        return ' # note' if self.rng.random() < 0.1 else ''

    def sequence(self, items, indent):
        out, result = [], []
        for item in items:
            pad = ' ' * indent
            if isinstance(item, dict) and item and self.rng.random() < 0.5:
                # compact mapping: "- k: v" with the rest aligned after "- "
                body, value = self.mapping(item, indent + 2)
                out.append(pad + '- ' + body[indent + 2:])
                result.append(value)
                continue
            text, value = self.block(item, indent, 'item')
            out.append(pad + '-' + text)
            result.append(value)
            if self.rng.random() < 0.05:
                out.append(pad + '# between items\n')
        return ''.join(out), result

    def mapping(self, items, indent):
        out, result = [], {}
        for key, item in items.items():
            text, value = self.block(item, indent, 'key')
            out.append(' ' * indent + self.string(key, False) + ':' + text)
            result[key] = value
        return ''.join(out), result

    def document(self, value):
        """(text, intended, whether the text may follow '--- ' on its line)."""
        self.anchors = []
        if isinstance(value, (list, dict)) and value and self.rng.random() < 0.8:
            if isinstance(value, list):
                return self.sequence(value, 0) + (False,)
            return self.mapping(value, 0) + (False,)
        if isinstance(value, tuple) and value[0] == 'block':
            return self.block_scalar(value[1], 1) + (True,)
        text, result = self.flow(value)
        return text + '\n', result, True


def generated(rng, count):
    cases = []
    for _ in range(count):
        gen, emitter = Gen(rng), Emitter(rng)
        documents = [gen.value(3) for _ in range(rng.choice([1, 1, 1, 2, 3]))]
        parts, results = [], []
        for index, value in enumerate(documents):
            body, result, inline = emitter.document(value)
            explicit = index > 0 or rng.random() < 0.3
            if explicit:
                if inline and (body.startswith(('|', '>')) or rng.random() < 0.5):
                    parts.append('--- ' + body)
                else:
                    parts.append('---\n' + body)
            else:
                parts.append(body)
            if rng.random() < 0.15:
                parts.append('...\n')
            if rng.random() < 0.1:
                parts.append('# between documents\n')
            results.append(result)
        cases.append((''.join(parts), results))
    return cases


# Running ----------------------------------------------------------------------

def run(exe, records):
    data = b''.join(('%s %d %d %d %d\n' % (mode, nodes, aliases, depth, len(text.encode('utf-8')))).encode() + text.encode('utf-8')
                    for mode, nodes, aliases, depth, text in records)
    result = subprocess.run([exe], input=data, capture_output=True, timeout=240)
    if result.returncode != 0:
        raise SystemExit('batch exited %d %r' % (result.returncode, result.stderr[:300]))
    return result.stdout.decode('utf-8').split('\n')


def main():
    args = sys.argv[1:]
    seed, count = 1212, 3000
    if '--seed' in args:
        seed = int(args[args.index('--seed') + 1])
    if '--docs' in args:
        count = int(args[args.index('--docs') + 1])
    exe = args[0]
    rng = random.Random(seed)
    gen_cases = generated(rng, count)
    records = [('A', 0, 0, 0, t) for t in AGREE] + [('A', 0, 0, 0, t) for t, _, _ in DIFFER]
    records += [('A', 0, 0, 0, t) for t, _, _ in ERRORS] + [(m, n, a, d, t) for m, n, a, d, t, _ in LIMITED]
    records += [('A', 0, 0, 0, t) for t, _ in gen_cases]
    lines = run(exe, records)
    at, failed = 0, 0

    def report(group, ok, total):
        print('%s %d/%d' % (group, ok, total))

    def show(*parts):
        if failed <= 12:
            print('DIFF', *parts)

    ok = 0
    for text in AGREE:
        got, (status, value) = lines[at], pyyaml(text)
        at += 1
        good = status == 'ok' and got.startswith('ok ') and same(lanius_value(got[3:]), value)
        ok += good
        if not good:
            failed += 1
            show('agree', repr(text), '\n  lanius', got, '\n  pyyaml', status, value)
    report('agree', ok, len(AGREE))

    ok = 0
    for text, expected, note in DIFFER:
        got = lines[at]
        at += 1
        status, value = pyyaml(text)
        if expected.startswith('ok '):
            good = got.startswith('ok ') and same(lanius_value(got[3:]), lanius_value(expected[3:]))
            if status == 'ok' and same(lanius_value(expected[3:]), value):
                good = False  # not actually a difference
                show('differ (PyYAML agrees)', repr(text))
        else:
            good = got == expected
        ok += good
        if not good:
            failed += 1
            show('differ', repr(text), note, '\n  lanius', got, '\n  expected', expected, '\n  pyyaml', status, value)
    report('differ', ok, len(DIFFER))

    ok = 0
    for text, kind, py_rejects in ERRORS:
        got = lines[at]
        at += 1
        status, value = pyyaml(text)
        if kind is None:
            good = got.startswith('ok ')
        else:
            good = got.startswith('err %s ' % kind) and (status == 'err') == py_rejects
        ok += good
        if not good:
            failed += 1
            show('errors', repr(text), kind, '\n  lanius', got, '\n  pyyaml', status, value)
    report('errors', ok, len(ERRORS))

    ok = 0
    for mode, nodes, aliases, depth, text, kind in LIMITED:
        got = lines[at]
        at += 1
        good = got.startswith('err %s ' % kind) if kind else got.startswith('ok ')
        ok += good
        if not good:
            failed += 1
            show('limits', repr(text)[:80], kind, '\n  lanius', got[:200])
    report('limits', ok, len(LIMITED))

    ok, model_failures = 0, 0
    for text, results in gen_cases:
        got = lines[at]
        at += 1
        status, value = pyyaml(text)
        expected = py_value(results)
        model = status == 'ok' and same_py(value, expected)
        good = got.startswith('ok ') and same(lanius_value(got[3:]), expected) and model
        if not model:
            model_failures += 1
        ok += good
        if not good:
            failed += 1
            show('generated', repr(text), '\n  lanius', got[:300], '\n  pyyaml', status, str(value)[:300], '\n  intended', str(expected)[:300])
    report('generated', ok, len(gen_cases))
    print('generated documents PyYAML disagreed with the intended value:', model_failures)
    print('disagreements', failed)
    return 1 if failed else 0


def same_py(a, b):
    if isinstance(a, bool) or isinstance(b, bool) or a is None or b is None:
        return type(a) is type(b) and a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return float(a) == float(b)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same_py(x, y) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return list(a) == list(b) and all(same_py(a[k], b[k]) for k in a)
    return a == b


if __name__ == '__main__':
    sys.exit(main())
