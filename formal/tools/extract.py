#!/usr/bin/env python3
"""Shallow extraction of pure Lanius code into ordinary Lean definitions.

    python3 formal/tools/extract.py formal/lani/mini/compiler.lani formal/Lanius/Mini/Compiler.lean
    python3 formal/tools/extract.py --check SOURCE OUTPUT   # fail if OUTPUT is stale
    python3 formal/tools/extract.py --inline MODULE SOURCE OUTPUT

With --inline, OUTPUT is instead each `// extract: inline` function as a
definition `Inline.name` (in a module importing MODULE, the extraction of
SOURCE): the term each call of it was replaced by, for the extraction
certificates (formal/Lanius/Faithful/).

The accepted subset is small enough that each construct has one obvious Lean
meaning, and everything else is rejected:

  types      usize -> Nat, i32 and u32 -> BitVec 32, u64 -> BitVec 64,
             u8 -> UInt8, bool -> Bool,
             the prelude's List<T> -> List T (Nil is [], Cons(x, rest) is
             x :: rest), core::option::Option<T> -> Option T, Box<T> -> T;
             user enums -> inductive, user structs -> structure
  functions  fn and impl methods (self first) -> def, recursion as written;
             generic functions only as the list operations in SPEC_FNS
  bodies     let, if/else, return; match on an enum, an Option, or a List
  arithmetic i32/u32/u64 + - * & | ^ wrap, like BitVec; u32/u64 >> by a constant;
             usize only /, since + - * go through the prelude's panicking
             plus/minus/times, which equal Nat + - * whenever they return;
             comparisons on usize, u32, u64 and u8 (unsigned in Lean too); casts usize -> i32/u64 (BitVec.ofNat), i32 -> u32 (same
             bits), u32 -> u64 (zero-extended), i32/u32/u64 -> u8 (low byte)

The prelude section (between `// extract: prelude begin` and `end`) is not
extracted. Every item in it must be in PRELUDE below with exactly the listed
signature; calls to it become the listed Lean term. A list operation in
SPEC_FNS is extracted as Lists.<name> followed by a theorem, checked by Lean,
that it equals its Lean list function; calls to it from other code are written
as that function. A function marked
`// extract: inline` is not emitted: each call becomes `let` bindings of its
arguments followed by its body (calls to it must not be recursive).
Functions and impl blocks between `// extract: mutual begin` and `end` are one
Lean `mutual` block, for recursion through a type nested in a List. A type
nested in itself that way, and every type containing one, derives only Repr,
since Lean cannot derive DecidableEq for it.

A second program can use the types of the first: items between
`// extract: external begin MODULE from PATH` and `// extract: external end`
are copies of types and list operations of the Lanius file PATH (relative to
the repository root), whose extraction is the Lean module MODULE. Each must be
the item of the same name in PATH, with the same fields, constructors or
signature. They are not emitted, and the output imports MODULE.
"""

import os
import re
import sys

# Prelude functions: Lanius signature -> how a call is written in Lean.
PRELUDE_FNS = {
    'boxed': ('fn boxed<T>(value: T) -> Box<T>', 'arg'),
    'unbox': ('fn unbox<T>(value: Box<T>) -> T', 'arg'),
    'plus': ('fn plus(a: usize, b: usize) -> usize', '+'),
    'times': ('fn times(a: usize, b: usize) -> usize', '*'),
    'minus': ('fn minus(a: usize, b: usize) -> usize', '-'),
    'max_of': ('fn max_of(a: usize, b: usize) -> usize', 'max'),
}
PRELUDE_TYPES = {
    'Box': 'struct Box<T> { storage: ptr }',
    'List': 'enum List<T> { Nil, Cons(T, Box<List<T>>) }',
}

# List operations: Lanius signature, how a call from other code is written in
# Lean, and the theorem (statement, proof) checked after the extracted
# definition. The statement is exactly what that call rewriting assumes.
SPEC_FNS = {
    'empty': ('fn empty<T>() -> List<T>', 'nil',
              '{T : Type} : (Lists.empty : List T) = []', 'rfl'),
    'single': ('fn single<T>(item: T) -> List<T>', 'single',
               '{T : Type} (item : T) : Lists.single item = [item]', 'rfl'),
    'cons': ('fn cons<T>(item: T, rest: List<T>) -> List<T>', '::',
             '{T : Type} (item : T) (rest : List T) : Lists.cons item rest = item :: rest', 'rfl'),
    'concat': ('fn concat<T>(first: List<T>, second: List<T>) -> List<T>', '++',
               '{T : Type} (first second : List T) : Lists.concat first second = first ++ second',
               'by induction first <;> simp_all [Lists.concat]'),
    'length': ('fn length<T>(items: List<T>) -> usize', 'length',
               '{T : Type} (items : List T) : Lists.length items = items.length',
               'by induction items <;> simp_all [Lists.length]'),
    'get': ('fn get<T>(items: List<T>, index: usize) -> Option<T>', 'get',
            '{T : Type} (items : List T) (index : Nat) : Lists.get items index = items[index]?',
            'by induction items generalizing index <;> cases index <;> simp_all [Lists.get]'),
    'get_or': ('fn get_or<T>(items: List<T>, index: usize, fallback: T) -> T', 'getD',
               '{T : Type} (items : List T) (index : Nat) (fallback : T) :\n    '
               'Lists.getOr items index fallback = items.getD index fallback',
               'by induction items generalizing index <;> cases index <;> simp_all [Lists.getOr]'),
}

LEAN_KEYWORDS = set('''at by do else end fun from have if import in instance let match namespace open
show then theorem universe variable where with deriving structure inductive def section'''.split())


class ExtractError(Exception):
    pass


def fail(message, token=None):
    where = f'line {token.line}: ' if token is not None else ''
    raise ExtractError(where + message)


# ---------------------------------------------------------------- lexing

class Token:
    def __init__(self, kind, text, line, comments):
        self.kind, self.text, self.line, self.comments = kind, text, line, comments

    def __repr__(self):
        return f'{self.kind}:{self.text}@{self.line}'


PUNCT = ['::', '->', '==', '!=', '<=', '>=', '&&', '||', '>>', '+=',
         '(', ')', '{', '}', '[', ']', '<', '>', ',', ';', ':', '.', '=', '+', '-', '*', '/', '%', '&', '|', '^', '!']


def lex(text):
    tokens, comments, i, line = [], [], 0, 1
    while i < len(text):
        c = text[i]
        if c == '\n':
            line += 1
            i += 1
            if i < len(text) and text[i] == '\n':
                comments = []
            continue
        if c.isspace():
            i += 1
            continue
        if text.startswith('//', i):
            end = text.find('\n', i)
            end = len(text) if end < 0 else end
            body = text[i + 2:end].strip()
            if body.startswith('extract:'):
                tokens.append(Token('marker', body[len('extract:'):].strip(), line, []))
            else:
                comments.append(body)
            i = end
            continue
        m = re.match(r'[A-Za-z_][A-Za-z0-9_]*', text[i:])
        if m:
            tokens.append(Token('ident', m.group(0), line, comments))
        else:
            m = re.match(r'[0-9]+', text[i:])
            if m:
                tokens.append(Token('int', m.group(0), line, comments))
            else:
                p = next((p for p in PUNCT if text.startswith(p, i)), None)
                if p is None:
                    fail(f'unexpected character {c!r}', Token('', '', line, []))
                m = None
                tokens.append(Token('punct', p, line, comments))
                i += len(p)
                comments = []
                continue
        comments = []
        i += len(m.group(0))
    tokens.append(Token('eof', '', line, []))
    return tokens


# ---------------------------------------------------------------- types

class Ty:
    def __init__(self, name, args=()):
        self.name, self.args = name, tuple(args)

    def __eq__(self, other):
        return isinstance(other, Ty) and (self.name, self.args) == (other.name, other.args)

    def __hash__(self):
        return hash((self.name, self.args))

    def __repr__(self):
        return self.name + (f'<{", ".join(map(repr, self.args))}>' if self.args else '')

    def strip_box(self):
        return self.args[0].strip_box() if self.name == 'Box' else self


USIZE, I32, U32, U64, U8, BOOL = Ty('usize'), Ty('i32'), Ty('u32'), Ty('u64'), Ty('u8'), Ty('bool')
TYPE_PATHS = {'core::option::Option': 'Option'}


def lean_type(t):
    t = t.strip_box()
    simple = {'usize': 'Nat', 'i32': 'BitVec 32', 'u32': 'BitVec 32', 'u64': 'BitVec 64', 'u8': 'UInt8',
              'bool': 'Bool'}
    if t.name in simple:
        return simple[t.name]
    if t.name == 'List':
        return f'List {atom_type(t.args[0])}'
    if t.name == 'Option':
        return f'Option {atom_type(t.args[0])}'
    return t.name


def atom_type(t):
    s = lean_type(t)
    return f'({s})' if ' ' in s else s


# ---------------------------------------------------------------- parsing

class Parser:
    def __init__(self, tokens):
        self.tokens, self.pos = tokens, 0

    def peek(self, offset=0):
        return self.tokens[self.pos + offset]

    def next(self):
        t = self.tokens[self.pos]
        self.pos += 1
        return t

    def at(self, text, offset=0):
        t = self.peek(offset)
        return t.kind in ('punct', 'ident') and t.text == text

    def expect(self, text):
        t = self.next()
        if t.text != text or t.kind not in ('punct', 'ident'):
            fail(f'expected {text!r}, found {t.text!r}', t)
        return t

    def ident(self):
        t = self.next()
        if t.kind != 'ident':
            fail(f'expected a name, found {t.text!r}', t)
        return t.text

    def path(self):
        parts = [self.ident()]
        while self.at('::'):
            self.next()
            parts.append(self.ident())
        return parts

    def type_(self):
        name = '::'.join(self.path())
        name = TYPE_PATHS.get(name, name)
        if '::' in name:
            fail(f'type {name} is not in the extracted subset', self.peek())
        args = []
        if self.at('<'):
            self.next()
            args.append(self.type_())
            while self.at(','):
                self.next()
                args.append(self.type_())
            self.close_angle()
        return Ty(name, args)

    def close_angle(self):
        t = self.peek()
        if t.kind == 'punct' and t.text == '>>':
            t.text = '>'  # the first > closes this list, the second the outer one
            return
        self.expect('>')

    def type_params(self):
        params = []
        if self.at('<'):
            self.next()
            params.append(self.ident())
            while self.at(','):
                self.next()
                params.append(self.ident())
            self.expect('>')
        return params

    # items ------------------------------------------------------------

    def items(self):
        items, prelude, inline, external = [], None, False, None
        while self.peek().kind != 'eof':
            t = self.peek()
            if t.kind == 'marker':
                self.next()
                m = re.fullmatch(r'external begin (\S+) from (\S+)', t.text)
                if m:
                    if prelude is not None or external is not None:
                        fail('an external section cannot nest', t)
                    external = {'module': m.group(1), 'path': m.group(2)}
                    items.append(('external', external))
                elif t.text == 'external end':
                    if external is None:
                        fail('external end without begin', t)
                    external = None
                elif t.text == 'prelude begin':
                    prelude = []
                elif t.text == 'prelude end':
                    items.append(('prelude', prelude))
                    prelude = None
                elif t.text == 'inline':
                    inline = True
                elif t.text in ('mutual begin', 'mutual end'):
                    if prelude is not None:
                        fail('mutual blocks are not allowed in the prelude', t)
                    items.append(('item', {'kind': 'mutual', 'begin': t.text == 'mutual begin', 'doc': []}))
                else:
                    fail(f'unknown marker {t.text!r}', t)
                continue
            if self.at('module') or self.at('import'):
                while not self.at(';'):
                    self.next()
                self.next()
                continue
            comments = t.comments
            if self.at('pub'):
                self.next()
            if self.at('struct'):
                item = self.struct()
            elif self.at('enum'):
                item = self.enum()
            elif self.at('fn'):
                item = self.fn(prelude is not None)
                item['inline'] = inline
                inline = False
            elif self.at('impl'):
                item = self.impl()
            else:
                fail(f'unexpected {t.text!r} at item level', t)
            item['doc'] = comments
            item['external'] = external
            if prelude is not None:
                prelude.append(item)
            else:
                items.append(('item', item))
        if prelude is not None:
            fail('prelude section is not closed')
        if external is not None:
            fail('external section is not closed')
        return items

    def struct(self):
        self.expect('struct')
        name = self.ident()
        tparams = self.type_params()
        self.expect('{')
        fields = []
        while not self.at('}'):
            doc = self.peek().comments
            field = self.ident()
            self.expect(':')
            fields.append((field, self.type_(), doc))
            if self.at(','):
                self.next()
        self.expect('}')
        return {'kind': 'struct', 'name': name, 'tparams': tparams, 'fields': fields}

    def enum(self):
        self.expect('enum')
        name = self.ident()
        tparams = self.type_params()
        self.expect('{')
        ctors = []
        while not self.at('}'):
            doc = self.peek().comments
            ctor = self.ident()
            payload = []
            if self.at('('):
                self.next()
                while not self.at(')'):
                    payload.append(self.type_())
                    if self.at(','):
                        self.next()
                self.expect(')')
            ctors.append((ctor, payload, doc))
            if self.at(','):
                self.next()
        self.expect('}')
        return {'kind': 'enum', 'name': name, 'tparams': tparams, 'ctors': ctors}

    def fn(self, signature_only, self_type=None):
        self.expect('fn')
        name = self.ident()
        tparams = self.type_params()
        self.expect('(')
        params = []
        while not self.at(')'):
            if self.at('self'):
                self.next()
                if self_type is None:
                    fail('self outside an impl', self.peek())
                params.append(('self', self_type))
            else:
                pname = self.ident()
                self.expect(':')
                params.append((pname, self.type_()))
            if self.at(','):
                self.next()
        self.expect(')')
        ret = None
        if self.at('->'):
            self.next()
            ret = self.type_()
        if self.at('where'):
            fail('where clauses are not in the extracted subset', self.peek())
        if signature_only:
            self.skip_block()
            body = None
        else:
            body = self.block()
        return {'kind': 'fn', 'name': name, 'tparams': tparams, 'params': params, 'ret': ret,
                'body': body, 'self_type': self_type, 'inline': False}

    def impl(self):
        self.expect('impl')
        name = self.ident()
        self.expect('{')
        fns = []
        while not self.at('}'):
            doc = self.peek().comments
            if self.at('pub'):
                self.next()
            f = self.fn(False, Ty(name))
            f['doc'] = doc
            fns.append(f)
        self.expect('}')
        return {'kind': 'impl', 'name': name, 'fns': fns}

    def skip_block(self):
        self.expect('{')
        depth = 1
        while depth:
            t = self.next()
            if t.kind == 'eof':
                fail('unterminated block', t)
            if t.kind == 'punct' and t.text == '{':
                depth += 1
            elif t.kind == 'punct' and t.text == '}':
                depth -= 1

    # statements -------------------------------------------------------

    def block(self):
        self.expect('{')
        stmts = []
        while not self.at('}'):
            stmts.append(self.stmt())
        self.expect('}')
        return stmts

    def stmt(self):
        t = self.peek()
        if self.at('let'):
            self.next()
            name = self.ident()
            self.expect(':')
            ty = self.type_()
            self.expect('=')
            value = self.expr()
            self.expect(';')
            return ('let', name, ty, value, t)
        if self.at('if'):
            self.next()
            self.expect('(')
            cond = self.expr()
            self.expect(')')
            then = self.block()
            other = None
            if self.at('else'):
                self.next()
                other = self.block()
            return ('if', cond, then, other, t)
        if self.at('return'):
            self.next()
            value = self.expr()
            self.expect(';')
            return ('return', value, t)
        fail(f'statement {t.text!r} is not in the extracted subset', t)

    # expressions ------------------------------------------------------

    BINARY = [['||'], ['&&'], ['==', '!=', '<', '<=', '>', '>='], ['|'], ['^'], ['&'], ['>>'], ['+', '-'], ['*', '/', '%']]

    def expr(self, level=0):
        if level == len(self.BINARY):
            return self.cast()
        left = self.expr(level + 1)
        while self.peek().kind == 'punct' and self.peek().text in self.BINARY[level]:
            t = self.next()
            right = self.expr(level + 1)
            if level == 2 and self.peek().kind == 'punct' and self.peek().text in self.BINARY[2]:
                fail('chained comparison', t)
            left = ('binary', t.text, left, right, t)
        return left

    def cast(self):
        e = self.unary()
        while self.at('as'):
            t = self.next()
            e = ('cast', e, self.type_(), t)
        return e

    def unary(self):
        if self.at('!'):
            t = self.next()
            return ('not', self.unary(), t)
        return self.postfix()

    def postfix(self):
        e = self.primary()
        while self.at('.'):
            t = self.next()
            name = self.ident()
            if self.at('('):
                e = ('method', e, name, self.args(), t)
            else:
                e = ('field', e, name, t)
        return e

    def args(self):
        self.expect('(')
        args = []
        while not self.at(')'):
            args.append(self.expr())
            if self.at(','):
                self.next()
        self.expect(')')
        return args

    def primary(self):
        t = self.peek()
        if t.kind == 'int':
            self.next()
            return ('int', int(t.text), t)
        if self.at('true') or self.at('false'):
            self.next()
            return ('bool', t.text == 'true', t)
        if self.at('('):
            self.next()
            e = self.expr()
            self.expect(')')
            return e
        if self.at('match'):
            self.next()
            self.expect('(')
            scrutinee = self.expr()
            self.expect(')')
            self.expect('{')
            arms = []
            while not self.at('}'):
                at = self.peek()
                ctor = self.path()
                binders = []
                if self.at('('):
                    self.next()
                    while not self.at(')'):
                        binders.append(self.ident())
                        if self.at(','):
                            self.next()
                    self.expect(')')
                self.expect('->')
                arms.append((ctor, binders, self.expr(), at))
                if self.at(','):
                    self.next()
            self.expect('}')
            return ('match', scrutinee, arms, t)
        if t.kind == 'ident' or self.at('self'):
            path = self.path()
            if self.at('('):
                return ('call', path, self.args(), t)
            if self.at('{') and len(path) == 1 and path[0][:1].isupper():
                self.next()
                fields = []
                while not self.at('}'):
                    fname = self.ident()
                    self.expect(':')
                    fields.append((fname, self.expr()))
                    if self.at(','):
                        self.next()
                self.expect('}')
                return ('struct', path[0], fields, t)
            return ('name', path, t)
        fail(f'expression {t.text!r} is not in the extracted subset', t)


# ---------------------------------------------------------------- Lean terms

# A term is (text, precedence). Multi-line terms (let, if, match) have
# precedence 0 and are parenthesized wherever they are not the whole body.
ATOM, APP = 1024, 1000


def camel(name):
    parts = name.split('_')
    out = parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])
    if out in LEAN_KEYWORDS:
        fail(f'name {name} is a Lean keyword')
    return out


def lower_first(name):
    return name[:1].lower() + name[1:]


def paren(term, need):
    text, prec = term
    return text if prec >= need else f'({indent_tail(text, 1)})'


def indent_tail(text, by):
    return text.replace('\n', '\n' + ' ' * by)


def app(head, args):
    return (' '.join([head] + [paren(a, ATOM) for a in args]), APP) if args else (head, ATOM)


def infix(op, left, right, prec, assoc):
    lneed = prec if assoc == 'left' else prec + 1
    rneed = prec if assoc == 'right' else prec + 1
    return (f'{paren(left, lneed)} {op} {paren(right, rneed)}', prec)


LEAN_INFIX = {  # op: (precedence, associativity)
    '++': (65, 'left'), '::': (67, 'right'), '+': (65, 'left'), '-': (65, 'left'), '*': (70, 'left'),
    '/': (70, 'left'), '%': (70, 'left'), '&&': (35, 'left'), '||': (30, 'left'), '&&&': (58, 'left'),
    '|||': (55, 'left'), '^^^': (58, 'left'), '>>>': (75, 'left'), '<': (50, 'none'), '≤': (50, 'none'),
    '=': (50, 'none'), '≠': (50, 'none'),
}


def lean_infix(op, left, right):
    prec, assoc = LEAN_INFIX[op]
    return infix(op, left, right, prec, assoc)


# ---------------------------------------------------------------- extraction

class Extractor:
    def __init__(self, items):
        self.structs, self.enums, self.fns, self.methods = {}, {}, {}, {}
        self.ctors = {}  # bare constructor name -> [enum names]
        self.prelude_seen = False
        self.order = []
        self.imports = []
        in_mutual = False
        for kind, item in items:
            if kind == 'prelude':
                self.check_prelude(item)
                continue
            if kind == 'external':
                self.imports.append(item)
                continue
            if item.get('external') is not None:
                self.check_external(item)
            if item['kind'] == 'mutual':
                if item['begin'] == in_mutual:
                    fail('mutual blocks must alternate begin and end, and cannot nest')
                in_mutual = item['begin']
                self.order.append(item)
                continue
            if in_mutual and (item['kind'] not in ('fn', 'impl') or item.get('inline')
                              or item.get('name') in SPEC_FNS):
                fail(f'{item.get("name")}: a mutual block holds only extracted functions and impl blocks')
            if item['kind'] in ('struct', 'enum') and item['tparams']:
                fail(f'{item["name"]}: generic types are only allowed in the prelude')
            if item['kind'] == 'struct':
                self.structs[item['name']] = item
            elif item['kind'] == 'enum':
                self.enums[item['name']] = item
                for ctor, _, _ in item['ctors']:
                    self.ctors.setdefault(ctor, []).append(item['name'])
            elif item['kind'] == 'fn':
                if item['name'] in SPEC_FNS:
                    if signature(item) != SPEC_FNS[item['name']][0]:
                        fail(f'{item["name"]}: signature differs from extract.py SPEC_FNS: {signature(item)}')
                    if item['inline']:
                        fail(f'{item["name"]}: list operations cannot be inline')
                elif item['tparams']:
                    fail(f'{item["name"]}: generic functions are only the list operations in SPEC_FNS')
                if item['name'] in PRELUDE_FNS or item['name'] in self.fns:
                    fail(f'{item["name"]} is defined twice')
                self.fns[item['name']] = item
            elif item['kind'] == 'impl':
                for f in item['fns']:
                    key = (item['name'], f['name'])
                    if key in self.methods:
                        fail(f'{item["name"]}::{f["name"]} is defined twice')
                    self.methods[key] = f
            if item.get('external') is None:
                self.order.append(item)
        if in_mutual:
            fail('mutual block is not closed')
        if not self.prelude_seen:
            fail('no prelude section')
        self.no_deq = self.nested_types()
        ctor_names = {lower_first(c) for c in self.ctors}
        clash = sorted(n for n in self.fns if camel(n) in ctor_names)
        if clash:
            fail(f'functions named like a constructor resolve to it inside that enum\'s methods: {clash}')
        missing = sorted(set(SPEC_FNS) - set(self.fns))
        if missing:
            fail(f'list operations missing: {missing}')
        self.current = None

    def nested_types(self):
        """Types Lean cannot derive DecidableEq for: an enum that occurs in
        its own constructors inside a type argument (after Box is dropped),
        and every type that contains such a type."""
        def mentions(t, name):
            t = t.strip_box()
            return t.name == name or any(mentions(a, name) for a in t.args)

        def nested_in(t, name):
            t = t.strip_box()
            return any(mentions(a, name) for a in t.args)

        def field_types(item):
            if item['kind'] == 'struct':
                return [ty for _, ty, _ in item['fields']]
            return [ty for _, payload, _ in item['ctors'] for ty in payload]

        types = dict(self.structs)
        types.update(self.enums)
        bad = {name for name, item in self.enums.items()
               if any(nested_in(ty, name) for ty in field_types(item))}
        changed = True
        while changed:
            changed = False
            for name, item in types.items():
                if name not in bad and any(mentions(ty, other) for ty in field_types(item) for other in bad):
                    bad.add(name)
                    changed = True
        return bad

    def check_prelude(self, prelude):
        self.prelude_seen = True
        fns, types = {}, {}
        for item in prelude:
            if item['kind'] == 'fn':
                fns[item['name']] = signature(item)
            elif item['kind'] == 'struct':
                fields = ', '.join(f'{n}: {t!r}' for n, t, _ in item['fields'])
                types[item['name']] = f'struct {item["name"]}<{", ".join(item["tparams"])}> {{ {fields} }}'
            elif item['kind'] == 'enum':
                ctors = ', '.join(c + (f'({", ".join(map(repr, p))})' if p else '') for c, p, _ in item['ctors'])
                types[item['name']] = f'enum {item["name"]}<{", ".join(item["tparams"])}> {{ {ctors} }}'
            else:
                fail('impl blocks are not allowed in the prelude')
        expected_fns = {name: sig for name, (sig, _) in PRELUDE_FNS.items()}
        if fns != expected_fns:
            diff = sorted(set(fns.items()) ^ set(expected_fns.items()))
            fail(f'prelude functions differ from extract.py PRELUDE_FNS: {diff}')
        if types != PRELUDE_TYPES:
            diff = sorted(set(types.items()) ^ set(PRELUDE_TYPES.items()))
            fail(f'prelude types differ from extract.py PRELUDE_TYPES: {diff}')

    def check_external(self, item):
        """An external item must be the item of the same name in its source."""
        source = item['external']
        if 'items' not in source:
            root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
            try:
                text = open(os.path.join(root, source['path'])).read()
            except OSError as error:
                fail(f'external source {source["path"]}: {error}')
            source['items'] = {i['name']: i for k, i in Parser(lex(text)).items()
                               if k == 'item' and i['kind'] in ('struct', 'enum', 'fn')}
        if item['kind'] == 'fn' and item['name'] not in SPEC_FNS:
            fail(f'{item["name"]}: only types and list operations can be external')
        if item['kind'] == 'impl':
            fail(f'{item["name"]}: impl blocks cannot be external')
        theirs = source['items'].get(item['name'])
        if theirs is None or theirs['kind'] != item['kind'] or self.shape(theirs) != self.shape(item):
            fail(f'{item["name"]} differs from its definition in {source["path"]}')

    @staticmethod
    def shape(item):
        if item['kind'] == 'struct':
            return [(n, repr(t)) for n, t, _ in item['fields']]
        if item['kind'] == 'enum':
            return [(c, [repr(t) for t in p]) for c, p, _ in item['ctors']]
        return signature(item)

    # declarations -----------------------------------------------------

    def run(self, source_name):
        out = [''.join(f'import {source["module"]}\n' for source in self.imports) +
               HEADER.format(source=source_name)]
        for item in self.order:
            if item['kind'] == 'mutual':
                out.append('mutual\n' if item['begin'] else 'end\n')
            elif item['kind'] == 'struct':
                out.append(self.emit_struct(item))
            elif item['kind'] == 'enum':
                out.append(self.emit_enum(item))
            elif item['kind'] == 'fn':
                if item['name'] in SPEC_FNS:
                    out.append(self.emit_fn(item, f'Lists.{camel(item["name"])}'))
                    _, _, statement, proof = SPEC_FNS[item['name']]
                    out.append(f'theorem Lists.{camel(item["name"])}_spec {statement} :=\n  {proof}\n')
                elif not item['inline']:
                    out.append(self.emit_fn(item, camel(item['name'])))
            elif item['kind'] == 'impl':
                for f in item['fns']:
                    if f['inline']:
                        fail('inline methods are not supported')
                    out.append(self.emit_fn(f, f'{item["name"]}.{camel(f["name"])}'))
        out.append('end Lanius.Mini\n')
        return '\n'.join(out)

    def run_inline(self, source_name, module):
        out = [f'import {module}\n' + INLINE_HEADER.format(source=source_name)]
        for item in self.order:
            if item['kind'] == 'fn' and item['name'] not in SPEC_FNS and item['inline']:
                # An inline function's parameters may be Lean keywords: its
                # calls never bind them.
                out.append(self.emit_fn(item, f'Inline.{camel(item["name"])}', keyword_params=True))
        out.append('end Lanius.Mini\n')
        return '\n'.join(out)

    def emit_struct(self, item):
        lines = doc(item['doc'], '') + [f'structure {item["name"]} where']
        for name, ty, field_doc in item['fields']:
            lines += doc(field_doc, '  ') + [f'  {camel(name)} : {lean_type(ty)}']
        lines.append(self.deriving(item))
        return '\n'.join(lines) + '\n'

    def emit_enum(self, item):
        lines = doc(item['doc'], '') + [f'inductive {item["name"]} where']
        for ctor, payload, ctor_doc in item['ctors']:
            sig = ''.join(f'{atom_type(t)} → ' for t in payload)
            lines += doc(ctor_doc, '  ') + [f'  | {lower_first(ctor)} : {sig}{item["name"]}']
        lines.append(self.deriving(item))
        return '\n'.join(lines) + '\n'

    def deriving(self, item):
        return '  deriving Repr' if item['name'] in self.no_deq else '  deriving DecidableEq, Repr'

    def emit_fn(self, f, lean_name, keyword_params=False):
        if f['ret'] is None:
            fail(f'{f["name"]} returns nothing')
        env = {}
        binders = [f'{{{t} : Type}}' for t in f['tparams']]
        self.current = f
        for name, ty in f['params']:
            lname = name + '_' if keyword_params and name in LEAN_KEYWORDS else camel(name)
            env[name] = (lname, ty)
            binders.append(f'({lname} : {lean_type(ty)})')
        body = self.block(f['body'], env, f['ret'])
        self.current = None
        head = ' '.join([f'def {lean_name}'] + binders) + f' : {lean_type(f["ret"])} :='
        return '\n'.join(doc(f['doc'], '')) + ('\n' if f['doc'] else '') + head + '\n  ' + indent_tail(body[0], 2) + '\n'

    # statements -------------------------------------------------------

    def block(self, stmts, env, ret):
        if not stmts:
            fail('a block must end with return')
        s, rest = stmts[0], stmts[1:]
        if s[0] == 'let':
            _, name, ty, value, t = s
            v = self.expr(value, env, ty)
            lname = camel(name)
            inner = dict(env)
            inner[name] = (lname, ty)
            body = self.block(rest, inner, ret)
            return (f'let {lname} : {lean_type(ty)} := {paren(v, 1)}\n{body[0]}', 0)
        if s[0] == 'return':
            if rest:
                fail('unreachable code after return', s[2])
            return self.expr(s[1], env, ret)
        if s[0] == 'if':
            _, cond, then, other, t = s
            c = self.condition(cond, env)
            a = self.block(then, env, ret)
            if other is not None:
                if rest:
                    fail('unreachable code after if/else', t)
                b = self.block(other, env, ret)
            else:
                b = self.block(rest, env, ret)
            return (f'if {c} then\n  {indent_tail(a[0], 2)}\nelse\n  {indent_tail(b[0], 2)}', 0)
        fail('unknown statement')

    def condition(self, cond, env):
        """An if condition: comparisons stay propositions, other bools are tested with = true."""
        if cond[0] == 'binary' and cond[1] in ('<', '<=', '>', '>=', '==', '!='):
            return self.comparison(cond, env)[0]
        return self.expr(cond, env, BOOL)[0]

    # expressions ------------------------------------------------------

    def expr(self, e, env, expected=None):
        term, ty = self.infer(e, env, expected)
        if expected is not None and ty.strip_box() != expected.strip_box():
            fail(f'expected {expected!r}, found {ty!r}', e[-1])
        return term

    def infer(self, e, env, expected):
        kind = e[0]
        if kind == 'int':
            ty = expected if expected is not None else None
            if ty is None:
                fail('integer literal needs a known type', e[-1])
            limits = {'usize': 2 ** 64, 'i32': 2 ** 31, 'u32': 2 ** 32, 'u64': 2 ** 64, 'u8': 2 ** 8}
            if ty.name not in limits or e[1] >= limits[ty.name]:
                fail(f'literal {e[1]} does not fit {ty!r}', e[-1])
            return (str(e[1]), ATOM), ty
        if kind == 'bool':
            return ('true' if e[1] else 'false', ATOM), BOOL
        if kind == 'name':
            path = e[1]
            if len(path) == 1 and path[0] in env:
                lname, ty = env[path[0]]
                return (lname, ATOM), ty
            if len(path) == 1 and path[0] == 'Nil':
                if expected is None or expected.strip_box().name != 'List':
                    fail('Nil needs a known List type', e[-1])
                return ('[]', ATOM), expected.strip_box()
            if len(path) == 1 and path[0] == 'None':
                if expected is None or expected.name != 'Option':
                    fail('None needs a known Option type', e[-1])
                return ('none', ATOM), expected
            enum, ctor = self.ctor(path, e[-1])
            payload = self.ctor_payload(enum, ctor)
            if payload:
                fail(f'{ctor} needs arguments', e[-1])
            return (f'{enum}.{lower_first(ctor)}', ATOM), Ty(enum)
        if kind == 'call':
            return self.call(e, env, expected)
        if kind == 'method':
            _, recv, name, args, t = e
            recv_term, recv_ty = self.infer(recv, env, None)
            recv_ty = recv_ty.strip_box()
            f = self.methods.get((recv_ty.name, name))
            if f is None:
                fail(f'no method {recv_ty!r}.{name}', t)
            arg_terms = self.args(f['params'][1:], args, env, t)
            return app(f'{recv_ty.name}.{camel(name)}', [recv_term] + arg_terms), f['ret']
        if kind == 'field':
            _, recv, name, t = e
            recv_term, recv_ty = self.infer(recv, env, None)
            recv_ty = recv_ty.strip_box()
            s = self.structs.get(recv_ty.name)
            field = next((ft for fn, ft, _ in s['fields'] if fn == name), None) if s else None
            if field is None:
                fail(f'no field {recv_ty!r}.{name}', t)
            return (f'{paren(recv_term, ATOM)}.{camel(name)}', ATOM), field
        if kind == 'struct':
            _, name, fields, t = e
            s = self.structs.get(name)
            if s is None:
                fail(f'unknown struct {name}', t)
            declared = [fn for fn, _, _ in s['fields']]
            if [fn for fn, _ in fields] != declared:
                fail(f'{name} literal must list fields {declared} in order', t)
            parts = []
            for (fname, value), (_, fty, _) in zip(fields, s['fields']):
                parts.append(f'{camel(fname)} := {paren(self.expr(value, env, fty), 1)}')
            return (f'({{ {", ".join(parts)} }} : {name})', ATOM), Ty(name)
        if kind == 'binary':
            return self.binary(e, env, expected)
        if kind == 'not':
            term = self.expr(e[1], env, BOOL)
            return (f'!{paren(term, ATOM)}', APP), BOOL
        if kind == 'cast':
            return self.cast(e, env)
        if kind == 'match':
            return self.match(e, env, expected)
        fail(f'unsupported expression {kind}', e[-1])

    def ctor(self, path, token):
        if len(path) == 2 and path[0] in self.enums:
            enum, ctor = path
            if not any(c == ctor for c, _, _ in self.enums[enum]['ctors']):
                fail(f'{enum} has no constructor {ctor}', token)
            return enum, ctor
        if len(path) == 1:
            owners = self.ctors.get(path[0], [])
            if len(owners) == 1:
                return owners[0], path[0]
            if len(owners) > 1:
                fail(f'constructor {path[0]} is ambiguous; write {owners[0]}::{path[0]}', token)
        fail(f'unknown name {"::".join(path)}', token)

    def ctor_payload(self, enum, ctor):
        return next(p for c, p, _ in self.enums[enum]['ctors'] if c == ctor)

    def args(self, params, args, env, token):
        if len(params) != len(args):
            fail(f'expected {len(params)} arguments, found {len(args)}', token)
        return [self.expr(a, env, ty) for (_, ty), a in zip(params, args)]

    def call(self, e, env, expected):
        _, path, args, t = e
        name = path[0] if len(path) == 1 else None
        if name == 'Some':
            if len(args) != 1:
                fail('Some takes one argument', t)
            inner = expected.args[0] if expected is not None and expected.name == 'Option' else None
            term, ty = self.infer(args[0], env, inner)
            return app('some', [term]), Ty('Option', [ty])
        if name == 'Cons':
            if len(args) != 2:
                fail('Cons takes two arguments', t)
            lst = expected.strip_box() if expected is not None and expected.strip_box().name == 'List' else None
            item, ity = self.infer(args[0], env, lst.args[0] if lst else None)
            lst = lst or Ty('List', [ity])
            rest = self.expr(args[1], env, Ty('Box', [lst]))
            return lean_infix('::', item, rest), lst
        if name in PRELUDE_FNS:
            return self.prelude_call(name, args, env, expected, t)
        if name in SPEC_FNS and self.current is not None and self.current['name'] in SPEC_FNS:
            if name != self.current['name']:
                fail('a list operation may call only itself', t)
            f = self.fns[name]
            return app(f'Lists.{camel(name)}', self.args(f['params'], args, env, t)), f['ret']
        if name in SPEC_FNS:
            return self.spec_call(name, args, env, expected, t)
        if name in self.fns:
            f = self.fns[name]
            if f['inline']:
                return self.inline(f, args, env, t)
            return app(camel(name), self.args(f['params'], args, env, t)), f['ret']
        enum, ctor = self.ctor(path, t)
        payload = self.ctor_payload(enum, ctor)
        terms = self.args([('', p) for p in payload], args, env, t)
        return app(f'{enum}.{lower_first(ctor)}', terms), Ty(enum)

    def prelude_call(self, name, args, env, expected, t):
        return self.rule_call(name, PRELUDE_FNS[name][1], args, env, expected, t)

    def spec_call(self, name, args, env, expected, t):
        return self.rule_call(name, SPEC_FNS[name][1], args, env, expected, t)

    def rule_call(self, name, rule, args, env, expected, t):
        arity = {'arg': 1, 'nil': 0, 'single': 1, '++': 2, '::': 2, 'length': 1, 'get': 2,
                 'getD': 3, '+': 2, '*': 2, '-': 2, 'max': 2}[rule]
        if len(args) != arity:
            fail(f'{name} takes {arity} arguments', t)
        elem = expected.args[0] if expected is not None and expected.name in ('List', 'Box') else None
        if rule == 'arg':
            if name == 'boxed':
                term, ty = self.infer(args[0], env, elem)
                return term, Ty('Box', [ty])
            term, ty = self.infer(args[0], env, Ty('Box', [expected]) if expected is not None else None)
            if ty.name != 'Box':
                fail('unbox needs a Box', t)
            return term, ty.args[0]
        if rule == 'nil':
            if expected is None or expected.name != 'List':
                fail('empty() needs a known List type', t)
            return ('[]', ATOM), expected
        if rule == 'single':
            term, ty = self.infer(args[0], env, elem)
            return (f'[{paren(term, 1)}]', ATOM), Ty('List', [ty])
        if rule == '++':
            left, lty = self.infer(args[0], env, expected)
            right = self.expr(args[1], env, lty)
            if lty.name != 'List':
                fail('concat needs lists', t)
            return lean_infix('++', left, right), lty
        if rule == '::':
            rest, rty = self.infer(args[1], env, expected)
            if rty.name != 'List':
                fail('cons needs a list', t)
            item = self.expr(args[0], env, rty.args[0])
            return lean_infix('::', item, rest), rty
        if rule == 'length':
            term, ty = self.infer(args[0], env, None)
            if ty.name != 'List':
                fail('length needs a list', t)
            return (f'{paren(term, ATOM)}.length', ATOM), USIZE
        if rule == 'get':
            term, ty = self.infer(args[0], env, Ty('List', [expected.args[0]]) if expected is not None else None)
            index = self.expr(args[1], env, USIZE)
            return (f'{paren(term, ATOM)}[{index[0]}]?', ATOM), Ty('Option', [ty.args[0]])
        if rule == 'getD':
            term, ty = self.infer(args[0], env, Ty('List', [expected]) if expected is not None else None)
            index = self.expr(args[1], env, USIZE)
            fallback = self.expr(args[2], env, ty.args[0])
            return (f'{paren(term, ATOM)}.getD {paren(index, ATOM)} {paren(fallback, ATOM)}', APP), ty.args[0]
        a = self.expr(args[0], env, USIZE)
        b = self.expr(args[1], env, USIZE)
        if rule == 'max':
            return app('max', [a, b]), USIZE
        return lean_infix(rule, a, b), USIZE

    def inline(self, f, args, env, t):
        """let-bind the arguments (variables are substituted), then the body."""
        if len(args) != len(f['params']):
            fail(f'{f["name"]} takes {len(f["params"])} arguments', t)
        inner, lets = {}, []
        for (pname, pty), arg in zip(f['params'], args):
            term, ty = self.infer(arg, env, pty)
            if ty.strip_box() != pty.strip_box():
                fail(f'{f["name"]}: argument {pname} has type {ty!r}', t)
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', term[0]) and term[0] not in ('true', 'false', 'none'):
                inner[pname] = (term[0], pty)
            else:
                lname = camel(pname)
                lets.append(f'let {lname} : {lean_type(pty)} := {paren(term, 1)}')
                inner[pname] = (lname, pty)
        # The body sees only its parameters and its own lets, so the one hazard
        # is a let in the body or for an argument shadowing a caller name that
        # a parameter was replaced by.
        let_names = {camel(s[1]) for s in walk_lets(f['body'])} | {line.split()[1] for line in lets}
        clash = let_names & {lname for lname, _ in env.values()}
        if clash:
            fail(f'inlining {f["name"]} would shadow {sorted(clash)}', t)
        body = self.block(f['body'], inner, f['ret'])
        return ('\n'.join(lets + [body[0]]), 0), f['ret']

    def comparison(self, e, env):
        _, op, left, right, t = e
        lt = self.infer_operand(left, env)
        rt = self.infer_operand(right, env)
        ty = lt or rt
        if ty is None:
            fail('comparison of two literals', t)
        a, b = self.expr(left, env, ty), self.expr(right, env, ty)
        # Lean's < and ≤ on Nat, BitVec and UInt8 are unsigned, so signed i32
        # comparisons stay out.
        if ty not in (USIZE, U32, U64, U8):
            fail(f'comparison on {ty!r} is not in the extracted subset', t)
        flipped = {'<': ('<', a, b), '<=': ('≤', a, b), '>': ('<', b, a), '>=': ('≤', b, a),
                   '==': ('=', a, b), '!=': ('≠', a, b)}
        lean_op, x, y = flipped[op]
        return lean_infix(lean_op, x, y)

    def infer_operand(self, e, env):
        if e[0] == 'int':
            return None
        return self.infer(e, env, None)[1].strip_box()

    def binary(self, e, env, expected):
        _, op, left, right, t = e
        if op in ('<', '<=', '>', '>=', '==', '!='):
            return app('decide', [self.comparison(e, env)]), BOOL
        if op in ('&&', '||'):
            a, b = self.expr(left, env, BOOL), self.expr(right, env, BOOL)
            return lean_infix(op, a, b), BOOL
        ty = self.infer_operand(left, env) or self.infer_operand(right, env) or expected
        if ty is None:
            fail('arithmetic on two literals needs a known type', t)
        if op == '>>':
            width = {U32: 32, U64: 64}.get(ty)
            if width is None or right[0] != 'int' or right[1] >= width:
                fail('>> is only extracted for u32 and u64 by a constant below the width', t)
            return lean_infix('>>>', self.expr(left, env, ty), (str(right[1]), ATOM)), ty
        if ty == USIZE:
            if op in ('/', '%'):
                return lean_infix(op, self.expr(left, env, USIZE), self.expr(right, env, USIZE)), USIZE
            fail(f'usize {op} must use the prelude (plus, minus, times)', t)
        if ty in (I32, U32, U64) and op in ('+', '-', '*', '&', '|', '^'):
            lean_op = {'&': '&&&', '|': '|||', '^': '^^^'}.get(op, op)
            return lean_infix(lean_op, self.expr(left, env, ty), self.expr(right, env, ty)), ty
        fail(f'{op} on {ty!r} is not in the extracted subset', t)

    def cast(self, e, env):
        _, inner, target, t = e
        term, source = self.infer(inner, env, None)
        source = source.strip_box()
        if source == USIZE and target == I32:
            return app('BitVec.ofNat', [('32', ATOM), term]), I32
        if source == USIZE and target == U64:
            return app('BitVec.ofNat', [('64', ATOM), term]), U64
        if source == I32 and target == U32:
            return term, U32
        if source == U32 and target == U64:
            return app('BitVec.setWidth', [('64', ATOM), term]), U64
        if source in (I32, U32, U64) and target == U8:
            return app('UInt8.ofNat', [(f'{paren(term, ATOM)}.toNat', ATOM)]), U8
        fail(f'cast {source!r} as {target!r} is not in the extracted subset', t)

    def match(self, e, env, expected):
        _, scrutinee, arms, t = e
        term, ty = self.infer(scrutinee, env, None)
        ty = ty.strip_box()
        if True:
            if ty.name == 'List':
                shapes = {'Nil': 0, 'Cons': 2}
                def pattern(ctor, binders):
                    return '[]' if ctor == 'Nil' else f'{binders[0]} :: {binders[1]}'
                def binder_types(ctor):
                    return [] if ctor == 'Nil' else [ty.args[0], Ty('Box', [ty])]
            elif ty.name == 'Option':
                shapes = {'Some': 1, 'None': 0}
                def pattern(ctor, binders):
                    return 'none' if ctor == 'None' else f'some {binders[0]}'
                def binder_types(ctor):
                    return [ty.args[0]] if ctor == 'Some' else []
            elif ty.name in self.enums:
                enum = self.enums[ty.name]
                shapes = {c: len(p) for c, p, _ in enum['ctors']}
                def pattern(ctor, binders):
                    return ' '.join([f'.{lower_first(ctor)}'] + binders)
                def binder_types(ctor):
                    return self.ctor_payload(ty.name, ctor)
            else:
                fail(f'cannot match on {ty!r}', t)
        seen, lines, result_ty = set(), [], expected
        for index, (path, binders, body, at) in enumerate(arms):
            if len(path) == 2 and path[0] == ty.name:
                path = path[1:]
            ctor = path[-1]
            if len(path) != 1 or ctor not in shapes:
                fail(f'{"::".join(path)} is not a constructor of {ty!r}', at)
            if ctor in seen:
                fail(f'duplicate arm {ctor}', at)
            seen.add(ctor)
            if len(binders) != shapes[ctor]:
                fail(f'{ctor} binds {shapes[ctor]} values', at)
            inner = dict(env)
            lnames = []
            for b, bty in zip(binders, binder_types(ctor)):
                lnames.append(camel(b))
                inner[b] = (camel(b), bty)
            arm_term, arm_ty = self.infer(body, inner, result_ty)
            if result_ty is None:
                result_ty = arm_ty
            elif arm_ty.strip_box() != result_ty.strip_box():
                fail(f'arm {ctor} has type {arm_ty!r}, expected {result_ty!r}', at)
            last = index == len(arms) - 1
            text = arm_term[0] if (arm_term[1] > 0 or last) else paren(arm_term, 1)
            if '\n' in text:
                lines.append(f'| {pattern(ctor, lnames)} =>\n  {indent_tail(text, 2)}')
            else:
                lines.append(f'| {pattern(ctor, lnames)} => {text}')
        if seen != set(shapes):
            fail(f'match is missing {sorted(set(shapes) - seen)}', t)
        return (f'match {paren(term, 1)} with\n' + '\n'.join(lines), 0), result_ty


def walk_lets(stmts):
    for s in stmts or []:
        if s[0] == 'let':
            yield s
        elif s[0] == 'if':
            yield from walk_lets(s[2])
            yield from walk_lets(s[3])


def signature(f):
    tparams = f'<{", ".join(f["tparams"])}>' if f['tparams'] else ''
    params = ', '.join(f'{n}: {t!r}' for n, t in f['params'])
    return f'fn {f["name"]}{tparams}({params}) -> {f["ret"]!r}'


def doc(comments, pad):
    if not comments:
        return []
    text = ' '.join(comments)
    return [f'{pad}/-- {text} -/']


HEADER = '''/-! Generated by formal/tools/extract.py from {source}. Do not edit.

Shallow extraction: each Lanius function is the Lean definition of the same
name (snake_case becomes camelCase, methods become `Type.method`, list
operations become `Lists.name` with a spec theorem). `usize` is `Nat`, `i32` is
`BitVec 32`, `u8` is `UInt8`, `List<T>` is `List T`, `Box<T>` is `T`. The
prelude's `plus`/`minus`/`times` panic instead of wrapping, so they are
`+`/`-`/`*` on `Nat` for every run that returns. -/

set_option linter.unusedVariables false

namespace Lanius.Mini
'''

INLINE_HEADER = '''/-! Generated by formal/tools/extract.py --inline from {source}. Do not edit.

Each function marked `// extract: inline` as the definition `Inline.name`:
what a call of it is replaced by in the extraction. -/

set_option linter.unusedVariables false

namespace Lanius.Mini
'''


def main(argv):
    check = '--check' in argv
    module = None
    if '--inline' in argv:
        at = argv.index('--inline')
        module = argv[at + 1]
        argv = argv[:at] + argv[at + 2:]
    paths = [a for a in argv if a != '--check']
    if len(paths) != 2:
        print(__doc__.split('\n\n')[0], file=sys.stderr)
        return 2
    source, output = paths
    try:
        items = Parser(lex(open(source).read())).items()
        root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        name = os.path.relpath(os.path.abspath(source), root)
        text = Extractor(items).run(name) if module is None else Extractor(items).run_inline(name, module)
    except ExtractError as error:
        print(f'{source}: {error}', file=sys.stderr)
        return 1
    if check:
        current = open(output).read()
        if current != text:
            print(f'{output} is stale; rerun formal/tools/extract.py', file=sys.stderr)
            return 1
        return 0
    with open(output, 'w') as f:
        f.write(text)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
