"""Model oracle: ext::json_pointer and ext::json_patch against a Python model.

usage: python3 -I oracle.py BATCH_EXE [--seed N] [--cases N]

BATCH_EXE is tests/fixtures/extended/json_patch/batch.lani compiled. The
model below implements RFC 6901 pointers, RFC 6902 patches and RFC 7386 merge
patches with the library's error kinds and check order (documented in
docs/extended-json-patch.md). It is checked against the RFC examples first,
then every case (RFC examples, one or more cases per error kind, generated
documents and patches) runs through BATCH_EXE and the outputs are compared
bytewise. Prints one `group agree/total` line per group and exits 1 on any
disagreement.
"""

import copy
import decimal
import json
import random
import re
import subprocess
import sys


class Num:
    """A JSON number that keeps its spelling."""

    def __init__(self, spelling):
        self.spelling = spelling

    def __repr__(self):
        return self.spelling


class Failure(Exception):
    def __init__(self, kind, operation=-1, offset=None):
        super().__init__(kind)
        self.kind, self.operation, self.offset = kind, operation, offset


def _pairs(pairs):
    seen = {}
    for key, value in pairs:
        if key in seen:
            raise Failure("DuplicateKey")
        seen[key] = value
    return seen


def _constant(name):
    raise ValueError(name)


def parse(text):
    try:
        return json.loads(text, parse_int=Num, parse_float=Num, parse_constant=_constant, object_pairs_hook=_pairs)
    except Failure:
        raise
    except ValueError:
        raise Failure("Parse")


def _escape(text):
    out = ['"']
    for ch in text:
        if ch == '"':
            out.append('\\"')
        elif ch == '\\':
            out.append('\\\\')
        elif ord(ch) < 0x20:
            out.append('\\u%04x' % ord(ch))
        else:
            out.append(ch)
    out.append('"')
    return ''.join(out)


def encode(value):
    """The library writer's compact form."""
    if value is None:
        return 'null'
    if value is True:
        return 'true'
    if value is False:
        return 'false'
    if isinstance(value, Num):
        return value.spelling
    if isinstance(value, str):
        return _escape(value)
    if isinstance(value, list):
        return '[' + ','.join(encode(item) for item in value) + ']'
    return '{' + ','.join(_escape(key) + ':' + encode(item) for key, item in value.items()) + '}'


def equal(a, b):
    if a is None or isinstance(a, bool):
        return a is b
    if isinstance(a, Num):
        return isinstance(b, Num) and decimal.Decimal(a.spelling) == decimal.Decimal(b.spelling)
    if isinstance(a, str):
        return isinstance(b, str) and a == b
    if isinstance(a, list):
        return isinstance(b, list) and len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return isinstance(b, dict) and len(a) == len(b) and all(k in b and equal(v, b[k]) for k, v in a.items())


def nodes(value):
    if isinstance(value, list):
        return 1 + sum(nodes(item) for item in value)
    if isinstance(value, dict):
        return 1 + sum(nodes(item) for item in value.values())
    return 1


# RFC 6901 -------------------------------------------------------------------

def parse_pointer(text):
    if text == '':
        return []
    if text[0] != '/':
        raise Failure("InvalidPointer", -1, 0)
    raw = text.encode('utf-8')
    tokens, current, index = [], bytearray(), 1
    while True:
        if index == len(raw) or raw[index] == 0x2f:
            tokens.append(current.decode('utf-8'))
            if index == len(raw):
                return tokens
            current, index = bytearray(), index + 1
            continue
        byte = raw[index]
        if byte == 0x7e:
            following = raw[index + 1] if index + 1 < len(raw) else None
            if following == 0x30:
                byte = 0x7e
            elif following == 0x31:
                byte = 0x2f
            else:
                raise Failure("InvalidPointer", -1, index)
            index += 1
        current.append(byte)
        index += 1


INDEX = re.compile(r'0|[1-9][0-9]*')


def array_index(token):
    """The index, -2 for "-", -1 when not an index."""
    if token == '-':
        return -2
    if INDEX.fullmatch(token) is None:
        return -1
    return int(token)


def resolve(document, tokens):
    node = document
    for token in tokens:
        if isinstance(node, dict):
            if token not in node:
                raise Failure("NotFound")
            node = node[token]
        elif isinstance(node, list):
            position = array_index(token)
            if position == -1:
                raise Failure("InvalidIndex")
            if position < 0 or position >= len(node):
                raise Failure("OutOfRange")
            node = node[position]
        else:
            raise Failure("NotFound")
    return node


# RFC 6902 -------------------------------------------------------------------

OPERATIONS = ('add', 'remove', 'replace', 'move', 'copy', 'test')


class State:
    def __init__(self, document, max_nodes):
        self.root = document
        self.max_nodes = max_nodes
        self.count = 0

    def charge(self, value):
        self.count += nodes(value)
        if self.count > self.max_nodes:
            raise Failure("NodeLimit")

    def add(self, tokens, value):
        if not tokens:
            self.root = value
            return
        parent = resolve(self.root, tokens[:-1])
        token = tokens[-1]
        if isinstance(parent, dict):
            parent[token] = value
        elif isinstance(parent, list):
            position = array_index(token)
            if position == -1:
                raise Failure("InvalidIndex")
            if position == -2 or position == len(parent):
                parent.append(value)
            elif position > len(parent):
                raise Failure("OutOfRange")
            else:
                parent.insert(position, value)
        else:
            raise Failure("NotFound")

    def detach(self, tokens):
        parent = resolve(self.root, tokens[:-1])
        if isinstance(parent, dict):
            del parent[tokens[-1]]
        else:
            del parent[array_index(tokens[-1])]

    def put(self, tokens, value):
        if not tokens:
            self.root = value
            return
        parent = resolve(self.root, tokens[:-1])
        if isinstance(parent, dict):
            parent[tokens[-1]] = value
        else:
            parent[array_index(tokens[-1])] = value


def pointer_member(op, name):
    if name not in op or not isinstance(op[name], str):
        raise Failure("InvalidPatch")
    return parse_pointer(op[name])


def apply_one(state, op):
    if not isinstance(op, dict):
        raise Failure("InvalidPatch")
    if 'op' not in op or not isinstance(op['op'], str):
        raise Failure("InvalidPatch")
    name = op['op']
    if name not in OPERATIONS:
        raise Failure("UnknownOperation")
    path = pointer_member(op, 'path')
    if name in ('add', 'replace', 'test') and 'value' not in op:
        raise Failure("InvalidPatch")
    if name in ('move', 'copy'):
        source = pointer_member(op, 'from')
        value = resolve(state.root, source)
        if name == 'move':
            if source == path:
                return
            if len(source) < len(path) and path[:len(source)] == source:
                raise Failure("MoveIntoChild")
            state.detach(source)
            state.add(path, value)
            return
        value = copy.deepcopy(value)
        state.charge(value)
        state.add(path, value)
        return
    if name == 'add':
        value = copy.deepcopy(op['value'])
        state.charge(value)
        state.add(path, value)
        return
    if name == 'remove' and not path:
        raise Failure("RemoveRoot")
    target = resolve(state.root, path)
    if name == 'remove':
        state.detach(path)
    elif name == 'test':
        if not equal(target, op['value']):
            raise Failure("TestFailed")
    else:
        value = copy.deepcopy(op['value'])
        state.charge(value)
        state.put(path, value)


def apply_patch(document, patch, max_nodes=1 << 24):
    if not isinstance(patch, list):
        raise Failure("InvalidPatch")
    state = State(copy.deepcopy(document), max_nodes)
    state.charge(state.root)
    for index, op in enumerate(patch):
        try:
            apply_one(state, op)
        except Failure as failure:
            failure.operation = index
            raise
    return state.root


# RFC 7386 -------------------------------------------------------------------

def merge_node(state, target, patch):
    if not isinstance(patch, dict):
        value = copy.deepcopy(patch)
        state.charge(value)
        return value
    if not isinstance(target, dict):
        target = {}
        state.charge(None)
    for key, value in patch.items():
        if value is None:
            target.pop(key, None)
        else:
            target[key] = merge_node(state, target.get(key), value)
    return target


def merge_patch(document, patch, max_nodes=1 << 24):
    state = State(copy.deepcopy(document), max_nodes)
    state.charge(state.root)
    return merge_node(state, state.root, patch)


# Cases ----------------------------------------------------------------------

def outcome(mode, nodes_limit, doc_text, arg_text):
    """The expected batch output line."""
    try:
        document = parse(doc_text)
        argument = parse(arg_text)
        limit = nodes_limit if nodes_limit > 0 else 1 << 24
        if mode == 'G':
            if not isinstance(argument, str):
                raise Failure("InvalidPatch")
            value = resolve(document, parse_pointer(argument))
        elif mode == 'M':
            value = merge_patch(document, argument, limit)
        else:
            value = apply_patch(document, argument, limit)
        return 'ok ' + encode(value)
    except Failure as failure:
        line = 'err %s %d' % (failure.kind, failure.operation)
        if failure.kind == 'InvalidPointer':
            line += ' %d' % failure.offset
        return line


def dump(value):
    return encode(value)


# RFC 6902 Appendix A, as (document, patch, expected result or error kind).
RFC6902 = [
    ('{"foo":"bar"}', '[{"op":"add","path":"/baz","value":"qux"}]', '{"foo":"bar","baz":"qux"}'),
    ('{"foo":["bar","baz"]}', '[{"op":"add","path":"/foo/1","value":"qux"}]', '{"foo":["bar","qux","baz"]}'),
    ('{"baz":"qux","foo":"bar"}', '[{"op":"remove","path":"/baz"}]', '{"foo":"bar"}'),
    ('{"foo":["bar","qux","baz"]}', '[{"op":"remove","path":"/foo/1"}]', '{"foo":["bar","baz"]}'),
    ('{"baz":"qux","foo":"bar"}', '[{"op":"replace","path":"/baz","value":"boo"}]', '{"baz":"boo","foo":"bar"}'),
    ('{"foo":{"bar":"baz","waldo":"fred"},"qux":{"corge":"grault"}}',
     '[{"op":"move","from":"/foo/waldo","path":"/qux/thud"}]',
     '{"foo":{"bar":"baz"},"qux":{"corge":"grault","thud":"fred"}}'),
    ('{"foo":["all","grass","cows","eat"]}', '[{"op":"move","from":"/foo/1","path":"/foo/3"}]',
     '{"foo":["all","cows","eat","grass"]}'),
    ('{"baz":"qux","foo":["a",2,"c"]}',
     '[{"op":"test","path":"/baz","value":"qux"},{"op":"test","path":"/foo/1","value":2}]',
     '{"baz":"qux","foo":["a",2,"c"]}'),
    ('{"baz":"qux"}', '[{"op":"test","path":"/baz","value":"bar"}]', 'err TestFailed 0'),
    ('{"foo":"bar"}', '[{"op":"add","path":"/child","value":{"grandchild":{}}}]',
     '{"foo":"bar","child":{"grandchild":{}}}'),
    ('{"foo":"bar"}', '[{"op":"add","path":"/baz","value":"qux","xyz":123}]', '{"foo":"bar","baz":"qux"}'),
    ('{"foo":"bar"}', '[{"op":"add","path":"/baz/bat","value":"qux"}]', 'err NotFound 0'),
    ('{"foo":"bar"}', '[{"op":"add","path":"/baz","value":"qux","op":"remove"}]', 'err DuplicateKey -1'),
    ('{"/":9,"~1":10}', '[{"op":"test","path":"/~01","value":10}]', '{"/":9,"~1":10}'),
    ('{"/":9,"~1":10}', '[{"op":"test","path":"/~01","value":"10"}]', 'err TestFailed 0'),
    ('{"foo":["bar"]}', '[{"op":"add","path":"/foo/-","value":["abc","def"]}]', '{"foo":["bar",["abc","def"]]}'),
]

# RFC 6901 section 5.
RFC6901_DOC = ('{"foo":["bar","baz"],"":0,"a/b":1,"c%d":2,"e^f":3,"g|h":4,"i\\\\j":5,'
               '"k\\"l":6," ":7,"m~n":8}')
RFC6901 = [
    ('', '{"foo":["bar","baz"],"":0,"a/b":1,"c%d":2,"e^f":3,"g|h":4,"i\\\\j":5,"k\\"l":6," ":7,"m~n":8}'),
    ('/foo', '["bar","baz"]'), ('/foo/0', '"bar"'), ('/', '0'), ('/a~1b', '1'), ('/c%d', '2'),
    ('/e^f', '3'), ('/g|h', '4'), ('/i\\j', '5'), ('/k"l', '6'), ('/ ', '7'), ('/m~0n', '8'),
]

# RFC 7386 Appendix A and the section 3 example.
RFC7386 = [
    ('{"a":"b"}', '{"a":"c"}', '{"a":"c"}'),
    ('{"a":"b"}', '{"b":"c"}', '{"a":"b","b":"c"}'),
    ('{"a":"b"}', '{"a":null}', '{}'),
    ('{"a":"b","b":"c"}', '{"a":null}', '{"b":"c"}'),
    ('{"a":["b"]}', '{"a":"c"}', '{"a":"c"}'),
    ('{"a":"c"}', '{"a":["b"]}', '{"a":["b"]}'),
    ('{"a":{"b":"c"}}', '{"a":{"b":"d","c":null}}', '{"a":{"b":"d"}}'),
    ('{"a":[{"b":"c"}]}', '{"a":[1]}', '{"a":[1]}'),
    ('["a","b"]', '["c","d"]', '["c","d"]'),
    ('{"a":"b"}', '["c"]', '["c"]'),
    ('{"a":"foo"}', 'null', 'null'),
    ('{"a":"foo"}', '"bar"', '"bar"'),
    ('{"e":null}', '{"a":1}', '{"e":null,"a":1}'),
    ('[1,2]', '{"a":"b","c":null}', '{"a":"b"}'),
    ('{}', '{"a":{"bb":{"ccc":null}}}', '{"a":{"bb":{}}}'),
    ('{"title":"Goodbye!","author":{"givenName":"John","familyName":"Doe"},"tags":["example","sample"],'
     '"content":"This will be unchanged"}',
     '{"title":"Hello!","phoneNumber":"+01-234-567-8901","author":{"familyName":null},"tags":["example"]}',
     '{"title":"Hello!","author":{"givenName":"John"},"tags":["example"],"content":"This will be unchanged",'
     '"phoneNumber":"+01-234-567-8901"}'),
]

# One or more cases per error kind (and the checks around each), as
# (mode, max_nodes, document, argument).
ERRORS = [
    ('P', 0, '{"a":1,}', '[]'), ('P', 0, '', '[]'), ('P', 0, '[1 2]', '[]'), ('P', 0, '{}', '[{"op":}]'),
    ('P', 0, '{}', '[] []'), ('M', 0, 'nul', '{}'), ('G', 0, '[1]', '"/0'),
    ('P', 0, '{"a":1,"a":2}', '[]'), ('P', 0, '{"a":{"b":1,"b":1}}', '[]'), ('M', 0, '{}', '{"x":1,"x":null}'),
    ('P', 0, '{' + ','.join('"k%d":%d' % (i, i) for i in range(12)) + ',"k5":0}', '[]'),
    ('P', 0, '{' + ','.join('"k%d":%d' % (i, i) for i in range(7)) + ',"k6":0}', '[]'),
    ('P', 0, '{' + ','.join('"k%d":%d' % (i, i) for i in range(8)) + ',"k8":0}', '[]'),
    ('P', 0, '{}', '{"op":"add"}'), ('P', 0, '{}', '"add"'), ('P', 0, '{}', 'null'),
    ('P', 0, '{}', '[1]'), ('P', 0, '{}', '[[]]'), ('P', 0, '{}', '[{}]'),
    ('P', 0, '{}', '[{"path":"/a","value":1}]'), ('P', 0, '{}', '[{"op":1,"path":"/a"}]'),
    ('P', 0, '{}', '[{"op":"ADD","path":"/a","value":1}]'), ('P', 0, '{}', '[{"op":"","path":""}]'),
    ('P', 0, '{}', '[{"op":"addx","value":1}]'), ('P', 0, '{}', '[{"op":"add","value":1}]'),
    ('P', 0, '{}', '[{"op":"add","path":7,"value":1}]'), ('P', 0, '{}', '[{"op":"add","path":"a","value":1}]'),
    ('P', 0, '{}', '[{"op":"add","path":"/a~","value":1}]'), ('P', 0, '{}', '[{"op":"add","path":"/a~2","value":1}]'),
    ('P', 0, '{}', '[{"op":"test","path":"/~x"}]'), ('P', 0, '{}', '[{"op":"add","path":"/a"}]'),
    ('P', 0, '{}', '[{"op":"replace","path":"/a"}]'), ('P', 0, '{}', '[{"op":"test","path":""}]'),
    ('P', 0, '{"a":1}', '[{"op":"move","path":"/b"}]'), ('P', 0, '{"a":1}', '[{"op":"copy","path":"/b","from":null}]'),
    ('P', 0, '{"a":1}', '[{"op":"move","path":"/b","from":"a"}]'), ('P', 0, '{"a":1}', '[{"op":"copy","path":"/b","from":"/~"}]'),
    ('P', 0, '{"a":1}', '[{"op":"move","path":"","from":"/b"}]'), ('P', 0, '{"a":1}', '[{"op":"remove","path":"/b"}]'),
    ('P', 0, '{"a":1}', '[{"op":"replace","path":"/b","value":2}]'), ('P', 0, '{"a":1}', '[{"op":"test","path":"/a/b","value":1}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/01","value":2}]'), ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/x","value":2}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/+1","value":2}]'), ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/","value":2}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"remove","path":"/a/-1"}]'), ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/2","value":2}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"add","path":"/a/99999999999999999999","value":2}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"remove","path":"/a/1"}]'), ('P', 0, '{"a":[1]}', '[{"op":"remove","path":"/a/-"}]'),
    ('P', 0, '{"a":[1]}', '[{"op":"test","path":"/a/-","value":1}]'), ('P', 0, '{"a":[[1]]}', '[{"op":"add","path":"/a/-/0","value":1}]'),
    ('P', 0, '{"a":1}', '[{"op":"test","path":"/a","value":"1"}]'), ('P', 0, '{"a":1}', '[{"op":"test","path":"/a","value":true}]'),
    ('P', 0, '{"a":[1,{"b":null}]}', '[{"op":"test","path":"/a","value":[1,{"b":false}]}]'),
    ('P', 0, '{"a":{"b":1}}', '[{"op":"move","from":"/a","path":"/a/b"}]'),
    ('P', 0, '{"a":{"b":1}}', '[{"op":"move","from":"","path":"/a"}]'),
    ('P', 0, '{"a":{"b":1}}', '[{"op":"move","from":"/a","path":"/a"}]'),
    ('P', 0, '{"a":{"b":1}}', '[{"op":"move","from":"/a","path":"/ab"}]'),
    ('P', 0, '{"a":{"b":1}}', '[{"op":"move","from":"/a/b","path":""}]'),
    ('P', 0, '{"a":1}', '[{"op":"remove","path":""}]'), ('P', 0, '{"a":1}', '[{"op":"add","path":"","value":[2]}]'),
    ('P', 0, '{"a":1}', '[{"op":"replace","path":"","value":3}]'), ('P', 0, '{"a":1}', '[{"op":"copy","from":"","path":"/b"}]'),
    ('P', 0, '{"a":1}', '[{"op":"add","path":"/b","value":2},{"op":"test","path":"/b","value":3}]'),
    ('P', 0, '{"a":1}', '[{"op":"add","path":"/b","value":2},{"op":"remove","path":""}]'),
    ('P', 0, '{"a":1}', '[{"op":"add","path":"/b","value":2},{"op":"bogus"}]'),
    ('P', 0, '7', '[{"op":"add","path":"/x","value":1}]'), ('P', 0, '"s"', '[{"op":"test","path":"/0","value":1}]'),
    ('P', 0, '{"a":[1,2,3]}', '[]'), ('P', 0, '[]', '[{"op":"add","path":"/0","value":1},{"op":"add","path":"/0","value":0}]'),
    ('P', 3, '{"a":1}', '[{"op":"add","path":"/b","value":2}]'),
    ('P', 3, '{"a":1}', '[{"op":"add","path":"/b","value":2},{"op":"add","path":"/c","value":3}]'),
    ('P', 2, '{"a":1,"b":2}', '[]'), ('P', 4, '{"a":[1]}', '[{"op":"copy","from":"/a","path":"/b"}]'),
    ('P', 4, '{"a":[1]}', '[{"op":"move","from":"/a","path":"/b"},{"op":"move","from":"/b","path":"/c"}]'),
    ('P', 3, '{"a":1}', '[{"op":"add","path":"/x/y","value":[1,2]}]'),
    ('P', 3, '{"a":1}', '[{"op":"replace","path":"/x","value":[1,2]}]'),
    ('P', 3, '{"a":1}', '[{"op":"replace","path":"/a","value":[1,2]}]'),
    ('M', 3, '{"a":1}', '{"b":{"c":1}}'), ('M', 4, '{"a":1}', '{"b":{"c":1}}'), ('M', 2, '[1,2]', '{}'),
    ('M', 1, '1', '{"a":null}'), ('M', 2, '1', '{"a":null}'),
    ('G', 0, '{"a":1}', '1'), ('G', 0, '{"a":1}', '"a"'), ('G', 0, '{"a":1}', '"/b"'), ('G', 0, '[1]', '"/1"'),
    ('G', 0, '[1]', '"/-"'), ('G', 0, '[1]', '"/00"'), ('G', 0, '{"a":1}', '"/a/0"'), ('G', 0, '{"a":1}', '"/a~3"'),
    ('G', 0, '{"\\u00e9":[true]}', '"/\\u00e9/0"'), ('G', 0, '{"\\ud83d\\ude00":1}', '"/\\ud83d\\ude00"'),
    ('G', 0, '{"a\\u0000b":1}', '"/a\\u0000b"'), ('G', 0, '{"":{"":2}}', '"//"'),
    ('P', 0, '{"n":1.0}', '[{"op":"test","path":"/n","value":1}]'),
    ('P', 0, '{"n":-0}', '[{"op":"test","path":"/n","value":0e5}]'),
    ('P', 0, '{"n":12.50E-1}', '[{"op":"test","path":"/n","value":1.25}]'),
    ('P', 0, '{"n":100}', '[{"op":"test","path":"/n","value":1e2}]'),
    ('P', 0, '{"n":100}', '[{"op":"test","path":"/n","value":1e3}]'),
    ('P', 0, '{"n":0.001}', '[{"op":"test","path":"/n","value":1E-3}]'),
    ('P', 0, '{"n":-5}', '[{"op":"test","path":"/n","value":5}]'),
    ('P', 0, '{"a":{"x":1,"y":2}}', '[{"op":"test","path":"/a","value":{"y":2,"x":1}}]'),
    ('P', 0, '{"a":{"x":1,"y":2}}', '[{"op":"test","path":"/a","value":{"y":2}}]'),
    ('P', 0, '{"a":[1,2]}', '[{"op":"test","path":"/a","value":[2,1]}]'),
]

KEYS = ['a', 'b', 'c', 'foo', '', '~', '/', 'a/b', 'm~n', '~1', '~0', '0', '1', '-', 'é', '🙂', 'x y', 'q"', 'b\\s', 't\n']
NUMBERS = ['0', '-0', '1', '2', '10', '-7', '1.5', '1.50', '15e-1', '0.0', '1e2', '100', '1E+2', '-0.0e0', '3.25', '123456789012345678901']
STRINGS = ['', 'x', 'bar', 'é', '🙂', 'a\u0001b', 'q"', 'back\\', 'tab\t', '/~', '0']


def gen_value(rng, depth):
    roll = rng.random()
    if depth <= 0 or roll < 0.45:
        pick = rng.randrange(5)
        if pick == 0:
            return None
        if pick == 1:
            return rng.random() < 0.5
        if pick == 2:
            return Num(rng.choice(NUMBERS))
        return rng.choice(STRINGS)
    if roll < 0.7:
        return [gen_value(rng, depth - 1) for _ in range(rng.randrange(4))]
    out = {}
    # Some objects cross the library's 8-member index threshold.
    width = rng.randrange(6, 14) if rng.random() < 0.2 else rng.randrange(4)
    for _ in range(width):
        out[rng.choice(KEYS)] = gen_value(rng, depth - 1)
    return out


def gen_document(rng):
    """Mostly arrays and objects; a few scalars."""
    while True:
        value = gen_value(rng, 4)
        if isinstance(value, (list, dict)) or rng.random() < 0.1:
            return value


def escape_token(token):
    return token.replace('~', '~0').replace('/', '~1')


def paths(value, prefix=()):
    yield list(prefix)
    if isinstance(value, list):
        for index, item in enumerate(value):
            yield from paths(item, prefix + (str(index),))
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from paths(item, prefix + (key,))


def pointer_text(tokens):
    return ''.join('/' + escape_token(token) for token in tokens)


def gen_pointer(rng, document, purpose):
    """Mostly existing paths, sometimes a new member or index, sometimes broken."""
    existing = list(paths(document))
    tokens = list(rng.choice(existing))
    roll = rng.random()
    if roll < 0.5:
        pass
    elif roll < 0.75:
        tokens.append(rng.choice(KEYS + ['-', '0', '1', '2', '3', '00', '5']))
    elif roll < 0.85 and tokens:
        tokens[-1] = rng.choice(KEYS + ['-', '9', '01'])
    elif roll < 0.9:
        tokens = tokens[:-1]
    else:
        text = pointer_text(tokens)
        return rng.choice([text + '~', text + '~2', 'a' + text, text + '/~x'])
    return pointer_text(tokens)


def gen_patch(rng, document):
    ops, shadow = [], copy.deepcopy(document)
    for _ in range(rng.randrange(1, 6)):
        name = rng.choice(OPERATIONS + OPERATIONS + ('bogus',))
        op = {'op': name, 'path': gen_pointer(rng, shadow, name)}
        if name in ('add', 'replace', 'test'):
            if name == 'test' and rng.random() < 0.6:
                try:
                    found = resolve(shadow, parse_pointer(op['path']))
                    op['value'] = copy.deepcopy(found)
                    if rng.random() < 0.3:
                        op['value'] = gen_value(rng, 1)
                except Failure:
                    op['value'] = gen_value(rng, 2)
            else:
                op['value'] = gen_value(rng, 2)
        if name in ('move', 'copy'):
            op['from'] = gen_pointer(rng, shadow, name)
        roll = rng.random()
        if roll < 0.03:
            del op['path']
        elif roll < 0.05 and 'value' in op:
            del op['value']
        elif roll < 0.06:
            op['op'] = Num('3')
        elif roll < 0.07:
            op['extra'] = [Num('1')]
        if rng.random() < 0.3:
            items = list(op.items())
            rng.shuffle(items)
            op = dict(items)
        ops.append(op)
        try:
            shadow = apply_patch(shadow, [op])
        except Failure:
            pass
    return ops


def gen_merge(rng, document, depth=3):
    if rng.random() < 0.2 or depth == 0:
        return gen_value(rng, 2)
    out = {}
    keys = list(document.keys()) if isinstance(document, dict) else []
    for _ in range(rng.randrange(12) if rng.random() < 0.2 else rng.randrange(5)):
        key = rng.choice(keys) if keys and rng.random() < 0.6 else rng.choice(KEYS)
        roll = rng.random()
        if roll < 0.3:
            out[key] = None
        elif roll < 0.6:
            out[key] = gen_merge(rng, document.get(key) if isinstance(document, dict) else None, depth - 1)
        else:
            out[key] = gen_value(rng, 2)
    return out


def json_text(value, rng):
    """Library-compact text, or Python's spelling with whitespace and \\u escapes."""
    if rng is None or rng.random() < 0.6:
        return encode(value)
    return py_text(value, rng.random() < 0.5)


def py_text(value, ascii_only):
    if isinstance(value, Num):
        return value.spelling
    if isinstance(value, list):
        return '[ ' + ' , '.join(py_text(item, ascii_only) for item in value) + ' ]'
    if isinstance(value, dict):
        return '{ ' + ', '.join(json.dumps(k, ensure_ascii=ascii_only) + ' : ' + py_text(v, ascii_only) for k, v in value.items()) + ' }'
    return json.dumps(value, ensure_ascii=ascii_only)


def check_model():
    problems = 0
    for doc, patch, expected in RFC6902:
        got = outcome('P', 0, doc, patch)
        want = expected if expected.startswith('err') else 'ok ' + encode(parse(expected))
        if got != want:
            print('model rfc6902', doc, patch, got, want)
            problems += 1
    for pointer, expected in RFC6901:
        got = outcome('G', 0, RFC6901_DOC, json.dumps(pointer))
        if got != 'ok ' + encode(parse(expected)):
            print('model rfc6901', pointer, got)
            problems += 1
    for doc, patch, expected in RFC7386:
        if outcome('M', 0, doc, patch) != 'ok ' + encode(parse(expected)):
            print('model rfc7386', doc, patch)
            problems += 1
    return problems


def main():
    args = sys.argv[1:]
    seed, count = 6902, 3000
    if '--seed' in args:
        seed = int(args[args.index('--seed') + 1])
    if '--cases' in args:
        count = int(args[args.index('--cases') + 1])
    exe = args[0]
    if check_model():
        print('model disagrees with the RFC examples')
        return 1
    groups = []
    groups.append(('rfc6902', [('P', 0, d, p) for d, p, _ in RFC6902]))
    groups.append(('rfc6901', [('G', 0, RFC6901_DOC, json.dumps(p)) for p, _ in RFC6901]))
    groups.append(('rfc7386', [('M', 0, d, p) for d, p, _ in RFC7386]))
    groups.append(('errors', ERRORS))
    rng = random.Random(seed)
    patches, merges, pointers = [], [], []
    for _ in range(count):
        document = gen_document(rng)
        patches.append(('P', 0, json_text(document, rng), json_text(gen_patch(rng, document), rng)))
    for _ in range(count // 2):
        document = gen_document(rng)
        merges.append(('M', 0, json_text(document, rng), json_text(gen_merge(rng, document), rng)))
    for _ in range(count // 2):
        document = gen_document(rng)
        pointers.append(('G', 0, json_text(document, rng), json.dumps(gen_pointer(rng, document, 'get'))))
    limited = []
    for _ in range(count // 10):
        document = gen_value(rng, 3)
        limit = nodes(document) + rng.randrange(-1, 6)
        if rng.random() < 0.5:
            limited.append(('P', max(limit, 1), encode(document), encode(gen_patch(rng, document))))
        else:
            limited.append(('M', max(limit, 1), encode(document), encode(gen_merge(rng, document))))
    groups += [('patch', patches), ('merge', merges), ('pointer', pointers), ('limits', limited)]
    cases = [case for _, group in groups for case in group]
    for mode, limit, doc, arg in cases:
        assert '\n' not in doc + arg and '\t' not in doc + arg
    stdin = ''.join('%s\t%d\t%s\t%s\n' % case for case in cases).encode('utf-8')
    result = subprocess.run([exe], input=stdin, capture_output=True, timeout=240)
    if result.returncode != 0:
        print('batch exited', result.returncode, result.stderr[:400])
        return 1
    lines = result.stdout.decode('utf-8').split('\n')
    at, failed, kinds = 0, 0, {}
    for name, group in groups:
        agree = 0
        for case in group:
            want = outcome(*case)
            got = lines[at]
            at += 1
            kind = want.split()[1] if want.startswith('err') else 'ok'
            kinds[kind] = kinds.get(kind, 0) + 1
            if got == want:
                agree += 1
            elif failed < 10:
                print('DIFF', name, case, '\n  lanius', got, '\n  model ', want)
            failed += got != want
        print('%s %d/%d' % (name, agree, len(group)))
    print('outcomes', ' '.join('%s=%d' % item for item in sorted(kinds.items())))
    print('disagreements', failed)
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
