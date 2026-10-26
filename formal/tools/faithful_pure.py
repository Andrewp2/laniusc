#!/usr/bin/env python3
"""The purity certificates of the self program dumped by faithful_dump.py.

    python3 -I formal/tools/faithful_pure.py [--chunk N] [DUMP REP OUTDIR]

DUMP is the Lean file faithful_dump.py wrote (`Lanius.Faithful.Self`, with
DUMP.meta next to it), REP the SelfProg.lean faithful_certs.py wrote (for
the prims). OUTDIR (default: DUMP's directory) gets

  SelfPureBase.lean  the prims, the functions `outside` the pure fragment
                     (the driver `app::main`, and `size_of` and
                     `typed_slice_from_storage`, which only the prims call),
                     the program's declarations `decls`, and two tables
                     checked once: the box structs (`boxElem_self`) and the
                     callees' signatures in blocks (`callTy_self`), so the
                     per-function checks do not walk the function list;
  SelfPure<k>.lean   for N functions each (default 100): `pure<i> :
                     PureFunc prog prims outside src<i> = true` for each pure
                     function (`pureFunc_fast` and `decide +kernel` of
                     `stmtOkC`, Sim/CheckFast.lean), and `part<k>`/`chunk<k>`:
                     `FuncOk` of each of them. The chunks import only
                     SelfPureBase, so they build in parallel;
  SelfDecls.lean     `prog.decls = decls`, computed once (`declareProgram` is
                     slow to reduce);
  SelfPrims.lean     `PrimsOk prog prims`, from SelfDecls;
  SelfPure.lean      `selfPure : PureProg prog SelfRep.prims outside` and
                     `selfPrims : PrimsOk prog SelfRep.prims`.

All proofs are `decide +kernel` or `rfl`. A file is only rewritten when its
text changes. The generator also runs a Python copy of `PureFunc` and stops
with the reason when a function is not pure, checks that nothing reachable
from `compile_source` or `front_end_files` (other than through the prims) is
outside, and computes `declareProgram`'s declarations in its order.
"""

import os
import re
import sys

PRIM_NAMES = ('mini::selfhost::boxed', 'mini::selfhost::unbox')
OUTSIDE_PREFIXES = ('app::', 'core::mem::size_of', 'core::mem::typed_slice_from_storage')
ROOTS = ('mini::selfhost::compile_source', 'mini::selfhost::front_end_files')
NS = 'Lanius.Faithful.SelfPure'
BLOCK = 41  # functions per block of `sigBlocks`: about the square root of their number


# ---------------------------------------------------------------- parsing

TOKEN = re.compile(r'\s*(?:(0x[0-9a-fA-F]+#\d+)|(\d+)|([A-Za-z_.][A-Za-z0-9_.]*)|(:=|[\[\](){},]))')


def tokenize(text):
    pos, out = 0, []
    text = text.rstrip()
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError(f'cannot tokenize at {text[pos:pos + 40]!r}')
        bv, num, name, punct = m.groups()
        if bv is not None:
            out.append(('num', int(bv.split('#')[0], 16)))
        elif num is not None:
            out.append(('num', int(num)))
        elif name is not None:
            out.append(('name', name))
        else:
            out.append(('p', punct))
        pos = m.end()
    return out


class Parser:
    """Lean terms: applications, lists, `{ f := v, ... }` records, numbers."""

    def __init__(self, text):
        self.toks = tokenize(text)
        self.i = 0

    def peek(self):
        return self.toks[self.i] if self.i < len(self.toks) else ('eof', None)

    def take(self, kind, val=None):
        t = self.peek()
        if t[0] != kind or (val is not None and t[1] != val):
            raise ValueError(f'expected {kind} {val}, got {t}')
        self.i += 1
        return t

    def primary(self):
        t = self.peek()
        if t == ('p', '('):
            self.i += 1
            e = self.expr()
            self.take('p', ')')
            return e
        if t == ('p', '['):
            self.i += 1
            items = []
            if self.peek() != ('p', ']'):
                items.append(self.expr())
                while self.peek() == ('p', ','):
                    self.i += 1
                    items.append(self.expr())
            self.take('p', ']')
            return ('list', items)
        if t == ('p', '{'):
            self.i += 1
            fields = {}
            while True:
                name = self.take('name')[1]
                self.take('p', ':=')
                fields[name] = self.expr()
                if self.peek() == ('p', ','):
                    self.i += 1
                    continue
                break
            self.take('p', '}')
            return ('rec', fields)
        if t[0] == 'num':
            self.i += 1
            return ('num', t[1])
        if t[0] == 'name':
            self.i += 1
            return ('name', t[1])
        raise ValueError(f'unexpected {t}')

    def starts_primary(self):
        t = self.peek()
        return t[0] in ('num', 'name') or t in (('p', '('), ('p', '['), ('p', '{'))

    def expr(self):
        head = self.primary()
        args = []
        while self.starts_primary():
            args.append(self.primary())
        if not args:
            return head
        if head[0] != 'name':
            raise ValueError('application of a non-name')
        return ('app', head[1], args)


def ctor(term):
    """The constructor name (without its namespace) and arguments of a term."""
    if term[0] == 'name':
        return term[1].rsplit('.', 1)[-1], []
    if term[0] == 'app':
        return term[1].rsplit('.', 1)[-1], term[2]
    raise ValueError(f'not a constructor term: {term}')


# ---------------------------------------------------------------- the program

class Program:
    """The functions of the dump, with each type interned as a number: equal
    types are equal numbers, and `node(t)` is its constructor and the numbers
    of its parts."""

    def __init__(self, dump):
        self.ty_text, self.src_text = {}, {}
        with open(dump) as f:
            for line in f:
                m = re.match(r'def (ty|src)(\d+) : Src(?:Type|Func) := (.*)$', line)
                if m:
                    (self.ty_text if m.group(1) == 'ty' else self.src_text)[int(m.group(2))] = m.group(3)
        self.n = len(self.src_text)
        assert sorted(self.src_text) == list(range(self.n))
        self.nodes, self.handle, self.tys = [], {}, {}
        for k in sorted(self.ty_text):
            self.tys[k] = self.type_of(Parser(self.ty_text[k]).expr())
        self.funcs = [self.func_of(Parser(self.src_text[i]).expr()) for i in range(self.n)]

    def intern(self, node):
        h = self.handle.get(node)
        if h is None:
            h = self.handle[node] = len(self.nodes)
            self.nodes.append(node)
        return h

    def node(self, t):
        return self.nodes[t]

    def type_of(self, t):
        if t[0] == 'name' and re.fullmatch(r'ty\d+', t[1]):
            return self.tys[int(t[1][2:])]
        c, a = ctor(t)
        if c in ('i32', 'bool', 'ptr', 'unit', 'isize'):
            return self.intern((c,))
        if c == 'uint':
            return self.intern(('uint', ctor(a[0])[0]))
        if c == 'struct':
            return self.intern(('struct', a[0][1], tuple(self.type_of(x) for x in a[1][1])))
        if c == 'enum':
            return self.intern(('enum', a[0][1], tuple(tuple(self.type_of(x) for x in v[1]) for v in a[1][1])))
        if c == 'slice':
            return self.intern(('slice', self.type_of(a[0])))
        raise ValueError(f'type {t}')

    def func_of(self, t):
        fs = t[1]
        params = [(p[1]['id'][1], self.type_of(p[1]['ty'])) for p in fs['params'][1]]
        return {'params': params, 'ret': self.type_of(fs['ret']), 'body': fs['body']}

    def type_id(self, t):
        node = self.nodes[t]
        return node[1] if node[0] in ('struct', 'enum') else 0


WIDTH = {'uint8': 8, 'uint32': 32, 'uint64': 64, 'usize': 64}


# ---------------------------------------------------------------- PureFunc, in Python

class Impure(Exception):
    pass


class Checker:
    """A copy of Sim/Check.lean's `PureFunc`, raising the reason it fails."""

    def __init__(self, prog, prims, outside):
        self.prog, self.outside = prog, set(outside)
        self.boxes = {}
        for i in prims['boxed']:
            f = prog.funcs[i]
            if len(f['params']) == 1:
                self.boxes.setdefault(prog.type_id(f['ret']), f['params'][0][1])

    @staticmethod
    def get(tenv, x):
        for k, t in tenv:
            if k == x:
                return t
        raise Impure(f'local {x} unbound')

    def expr(self, tenv, e):
        c, a = ctor(e)
        if c == 'int':
            return self.prog.intern(('i32',))
        if c == 'boolean':
            return self.prog.intern(('bool',))
        if c == 'unsigned':
            kind = ctor(a[0])[0]
            if a[1][1] >= 2 ** WIDTH[kind]:
                raise Impure('unsigned literal too wide')
            return self.prog.intern(('uint', kind))
        if c == 'local':
            return self.get(tenv, a[0][1])
        if c == 'field':
            t = self.prog.node(self.get(tenv, a[0][1]))
            if t[0] != 'struct':
                raise Impure(f'field of a non-struct local {a[0][1]}')
            if t[1] in self.boxes:
                raise Impure(f'field read of the box struct {t[1]} (local {a[0][1]})')
            if a[1][1] >= len(t[2]):
                raise Impure('field index out of range')
            return t[2][a[1][1]]
        if c == 'negate':
            return self.expr(tenv, a[0])
        if c == 'not':
            self.expr(tenv, a[0])
            return self.prog.intern(('bool',))
        if c == 'apply':
            return self.op(ctor(a[0])[0], self.expr(tenv, a[1]), self.expr(tenv, a[2]))
        if c == 'cast':
            self.expr(tenv, a[1])
            return self.prog.type_of(a[0])
        if c == 'null':
            raise Impure('null')
        raise ValueError(c)

    def op(self, op, left, right):
        boolean = self.prog.intern(('bool',))
        if op in ('less', 'lessEq', 'greater', 'greaterEq'):
            return boolean
        if op in ('equal', 'notEqual'):
            kind = self.prog.node(left)[0]
            if kind in ('i32', 'bool', 'uint', 'isize', 'unit'):
                return boolean
            raise Impure(f'`{op}` on a {kind}')
        if op in ('logicalAnd', 'logicalOr'):
            if right == boolean:
                return boolean
            raise Impure(f'`{op}` of a non-bool')
        return left

    def call(self, callee, ts):
        if callee in self.outside:
            raise Impure(f'calls {callee}, which is outside')
        f = self.prog.funcs[callee]
        if list(ts) != [t for _, t in f['params']]:
            raise Impure(f'call of {callee} at other types')
        return f['ret']

    def struct(self, t, ts):
        ty = self.prog.node(t)
        if ty[0] != 'struct' or ty[1] in self.boxes or list(ts) != list(ty[2]):
            raise Impure(f'struct literal of {ty[0]} {self.prog.type_id(t)}' +
                         (' (a box)' if ty[0] == 'struct' and ty[1] in self.boxes else ''))
        return t

    def variant(self, t, k, ts):
        ty = self.prog.node(t)
        if ty[0] != 'enum' or k >= len(ty[2]) or list(ts) != list(ty[2][k]):
            raise Impure('variant literal at other types')
        return t

    def eff(self, tenv, e):
        c, a = ctor(e)
        if c == 'ePure':
            return self.expr(tenv, a[0])
        if c == 'eCall':
            return self.call(a[0][1], [self.eff(tenv, x) for x in a[1][1]])
        if c == 'eApply':
            return self.op(ctor(a[0])[0], self.eff(tenv, a[1]), self.eff(tenv, a[2]))
        if c == 'eNeg':
            return self.eff(tenv, a[0])
        if c == 'eNot':
            self.eff(tenv, a[0])
            return self.prog.intern(('bool',))
        if c == 'eCast':
            self.eff(tenv, a[1])
            return self.prog.type_of(a[0])
        if c == 'eIndex':
            raise Impure('slice index')
        if c == 'eStruct':
            return self.struct(self.prog.type_of(a[0]), [self.eff(tenv, x) for x in a[1][1]])
        if c == 'eVariant':
            return self.variant(self.prog.type_of(a[0]), a[1][1], [self.eff(tenv, x) for x in a[2][1]])
        if c == 'eMatch':
            st = self.eff(tenv, a[0])
            et, rty = self.prog.type_of(a[1]), self.prog.type_of(a[2])
            ety = self.prog.node(et)
            if ety[0] != 'enum' or st != et:
                raise Impure('match scrutinee of another type')
            binders, values = a[3][1], a[4][1]
            if len(binders) != len(values) or len(binders) > len(ety[2]):
                raise Impure('more match arms than variants')
            for fs, bs, v in zip(ety[2], binders, values):
                bs = [b[1] for b in bs[1]]
                if len(bs) != len(fs):
                    raise Impure('match arm binds part of a payload')
                inner = list(tenv)
                for b, t in zip(bs, fs):
                    inner.insert(0, (b, t))
                if self.eff(inner, v) != rty:
                    raise Impure('match arm of another type')
            return rty
        if c == 'eDivide':
            left = self.eff(tenv, a[1])
            self.eff(tenv, a[2])
            return left
        if c == 'eStride':
            raise Impure('stride')
        raise ValueError(c)

    def stmt(self, ret, tenv, s):
        c, a = ctor(s)
        if c in ('nop', 'returnUnit'):
            return
        if c == 'let':
            return self.stmt(ret, [(a[0][1], self.expr(tenv, a[2]))] + tenv, a[3])
        if c == 'letStruct':
            t = self.struct(self.prog.type_of(a[1]), [self.expr(tenv, x) for x in a[2][1]])
            return self.stmt(ret, [(a[0][1], t)] + tenv, a[3])
        if c == 'letCall':
            t = self.call(a[2][1], [self.expr(tenv, x) for x in a[3][1]])
            return self.stmt(ret, [(a[0][1], t)] + tenv, a[4])
        if c == 'letEnum':
            t = self.variant(self.prog.type_of(a[1]), a[2][1], [self.expr(tenv, x) for x in a[3][1]])
            return self.stmt(ret, [(a[0][1], t)] + tenv, a[4])
        if c == 'then':
            self.stmt(ret, tenv, a[0])
            return self.stmt(ret, tenv, a[1])
        if c == 'if':
            self.expr(tenv, a[0])
            self.stmt(ret, tenv, a[1])
            return self.stmt(ret, tenv, a[2])
        if c == 'return':
            if self.expr(tenv, a[0]) != ret:
                raise Impure('return of another type')
            return
        if c == 'letEval':
            return self.stmt(ret, [(a[0][1], self.eff(tenv, a[2]))] + tenv, a[3])
        if c == 'ifEval':
            self.eff(tenv, a[0])
            self.stmt(ret, tenv, a[1])
            return self.stmt(ret, tenv, a[2])
        if c == 'returnEval':
            if self.eff(tenv, a[0]) != ret:
                raise Impure('return of another type')
            return
        if c in ('discard', 'assert'):
            self.eff(tenv, a[0])
            return
        raise Impure(f'statement `{c}`')

    def check(self, i):
        f = self.prog.funcs[i]
        tenv = []
        for p in f['params']:
            tenv.insert(0, p)
        self.stmt(f['ret'], tenv, f['body'])


# ---------------------------------------------------------------- calls and declarations

def walk(term):
    yield term
    if term[0] == 'app':
        for x in term[2]:
            yield from walk(x)
    elif term[0] == 'list':
        for x in term[1]:
            yield from walk(x)
    elif term[0] == 'rec':
        for x in term[1].values():
            yield from walk(x)


def callees(func):
    out = []
    for t in walk(func['body']):
        if t[0] == 'app':
            c, a = ctor(t)
            if c == 'eCall' or c == 'setCall':
                out.append(a[0][1] if c == 'eCall' else a[1][1])
            elif c == 'letCall':
                out.append(a[2][1])
    return out


class Declarer:
    """`declareProgram`'s declarations, in its order (the newest first)."""

    def __init__(self, prog):
        self.prog = prog
        self.structs, self.enums = {}, {}
        self.order_s, self.order_e = [], []

    def ty(self, h):
        t = self.prog.node(h)
        if t[0] == 'struct':
            for x in t[2]:
                self.ty(x)
            if t[1] not in self.structs:
                self.structs[t[1]] = t[2]
                self.order_s.append(t[1])
            elif self.structs[t[1]] != t[2]:
                raise ValueError(f'struct {t[1]} declared twice')
        elif t[0] == 'enum':
            for v in t[2]:
                for x in v:
                    self.ty(x)
            if t[1] not in self.enums:
                self.enums[t[1]] = t[2]
                self.order_e.append(t[1])
            elif self.enums[t[1]] != t[2]:
                raise ValueError(f'enum {t[1]} declared twice')
        elif t[0] == 'slice':
            self.ty(t[1])

    def eff_types(self, e):
        c, a = ctor(e)
        if c in ('ePure', 'eStride'):
            return []
        if c == 'eCall':
            return [t for x in a[1][1] for t in self.eff_types(x)]
        if c in ('eApply', 'eDivide'):
            return self.eff_types(a[1]) + self.eff_types(a[2])
        if c in ('eNeg', 'eNot'):
            return self.eff_types(a[0])
        if c in ('eCast', 'eIndex'):
            return self.eff_types(a[1])
        if c == 'eStruct':
            return [self.prog.type_of(a[0])] + [t for x in a[1][1] for t in self.eff_types(x)]
        if c == 'eVariant':
            return [self.prog.type_of(a[0])] + [t for x in a[2][1] for t in self.eff_types(x)]
        if c == 'eMatch':
            return [self.prog.type_of(a[1])] + self.eff_types(a[0]) + [t for x in a[4][1] for t in self.eff_types(x)]
        raise ValueError(c)

    def stmt(self, s):
        c, a = ctor(s)
        ty = self.prog.type_of
        if c in ('let', 'letStruct', 'letCall', 'letEnum', 'letMatch', 'letIndex'):
            self.ty(ty(a[1]))
            self.stmt(a[-1])
        elif c == 'letSlice':
            self.ty(ty(a[1]))
            self.stmt(a[4])
        elif c in ('then', 'if'):
            self.stmt(a[-2])
            self.stmt(a[-1])
        elif c in ('while', 'letAlloc', 'letLoad'):
            self.stmt(a[-1])
        elif c == 'letEval':
            for t in [ty(a[1])] + self.eff_types(a[2]):
                self.ty(t)
            self.stmt(a[3])
        elif c == 'ifEval':
            for t in self.eff_types(a[0]):
                self.ty(t)
            self.stmt(a[1])
            self.stmt(a[2])
        elif c == 'whileEval':
            for t in self.eff_types(a[0]):
                self.ty(t)
            self.stmt(a[1])
        elif c in ('setEval', 'returnEval', 'discard', 'setFieldEval', 'assert'):
            for t in self.eff_types(a[-1]):
                self.ty(t)
        elif c == 'setIndexEval':
            for t in self.eff_types(a[1]) + self.eff_types(a[2]):
                self.ty(t)

    def run(self):
        for f in self.prog.funcs:
            for _, t in f['params']:
                self.ty(t)
            self.ty(f['ret'])
            self.stmt(f['body'])
        return self


# ---------------------------------------------------------------- Lean text

def write(path, text):
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except FileNotFoundError:
        pass
    with open(path, 'w') as f:
        f.write(text)
    return True


HEADER = '/-! Generated by formal/tools/faithful_pure.py. Do not edit. -/\n'


def main(argv):
    chunk = 100
    if argv[:1] == ['--chunk']:
        chunk, argv = int(argv[1]), argv[2:]
    here = os.path.dirname(os.path.abspath(__file__))
    gen = os.path.join(here, '..', 'Lanius', 'Faithful', 'Gen')
    dump, rep, outdir = argv if argv else (os.path.join(gen, 'Self.lean'), os.path.join(gen, 'SelfProg.lean'), gen)

    names = {}
    with open(dump + '.meta' if os.path.exists(dump + '.meta') else
              os.path.join(here, '..', '..', 'target', 'claude-work', 'faithful', 'Self.lean.meta')) as f:
        for line in f:
            parts = line.split()
            if parts and parts[0] == 'fn':
                names[int(parts[1])] = parts[2] + ('' if parts[4] == '-' else f'<{parts[4]}>')
    with open(rep) as f:
        text = f.read()
    m = re.search(r'def (?:_root_\.Lanius\.Faithful\.SelfRep\.)?prims : Prims :=\s*\{\s*boxed := \[([\d, ]*)\],\s*unbox := \[([\d, ]*)\]\s*\}', text)
    prims = {k: [int(x) for x in m.group(j).split(',') if x.strip()] for j, k in ((1, 'boxed'), (2, 'unbox'))}
    prim_set = set(prims['boxed']) | set(prims['unbox'])

    prog = Program(dump)
    assert len(names) == prog.n, (len(names), prog.n)
    outside = [i for i in range(prog.n) if names[i].startswith(OUTSIDE_PREFIXES)]
    for i in range(prog.n):
        is_prim = names[i].split('<')[0] in PRIM_NAMES
        assert is_prim == (i in prim_set), (i, names[i])

    # What the compiler reaches, through the prims' bodies too.
    graph = [callees(f) for f in prog.funcs]
    roots = [i for i in range(prog.n) if names[i] in ROOTS]
    seen, todo, reached_outside = set(roots), list(roots), {}
    while todo:
        i = todo.pop()
        for j in graph[i]:
            if j in outside and i not in prim_set and i not in outside:
                reached_outside.setdefault(j, i)
            if j not in seen and not (i in prim_set and j in outside):
                seen.add(j)
                todo.append(j)
    checker = Checker(prog, prims, outside)
    failures = []
    for i in range(prog.n):
        if i in prim_set or i in outside:
            continue
        try:
            checker.check(i)
        except Impure as e:
            failures.append((i, str(e)))
    for j, i in sorted(reached_outside.items()):
        print(f'outside {j} {names[j]} is called by {i} {names[i]}', file=sys.stderr)
    for i, why in failures:
        print(f'not pure: {i} {names[i]}{" (reached)" if i in seen else ""}: {why}', file=sys.stderr)
    if reached_outside or failures:
        return 1

    decl = Declarer(prog).run()
    ty_name = {}
    for k in sorted(prog.ty_text):
        ty_name.setdefault(prog.tys[k], f'ty{k}')

    def lean_ty(h):
        if h in ty_name:
            return ty_name[h]
        t = prog.node(h)
        if t[0] == 'uint':
            return f'(.uint .{t[1]})'
        if t[0] == 'slice':
            return f'(.slice {lean_ty(t[1])})'
        if t[0] in ('struct', 'enum'):
            raise ValueError(f'unnamed type {t[0]} {t[1]}')
        return f'.{t[0]}'

    def lean_list(ts):
        return '[' + ', '.join(lean_ty(t) for t in ts) + ']'

    def comment_list(ids):
        return ''.join(f'  -- {i} {names[i]}\n' for i in ids)

    written = []
    base = (f'import Lanius.Faithful.Gen.Self\nimport Lanius.Faithful.Sim.ProgOk\nimport Lanius.Faithful.Sim.CheckFast\n\n{HEADER}\n'
            f'namespace {NS}\n\nopen Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n\n'
            '/-- The prims, as SelfRep has them. -/\n'
            f'def prims : Prims :=\n  {{ boxed := {prims["boxed"]},\n    unbox := {prims["unbox"]} }}\n\n'
            '/-- The functions outside the pure fragment: the driver, and the helpers\n'
            'only the prims call. -/\n'
            'def outside : List Nat := [\n' +
            ''.join(f'  {i}{"," if k + 1 < len(outside) else ""} -- {names[i]}\n' for k, i in enumerate(outside)) +
            ']\n\n'
            '/-- The program\'s declarations, as `declareProgram` gives them. -/\n'
            'def decls : SrcDecls where\n  structs := [\n' +
            ',\n'.join(f'    {{ id := {i}, fields := {lean_list(decl.structs[i])} }}' for i in reversed(decl.order_s)) +
            ']\n  enums := [\n' +
            ',\n'.join(f'    {{ id := {i}, variants := [{", ".join(lean_list(v) for v in decl.enums[i])}] }}'
                       for i in reversed(decl.order_e)) +
            ']\n\n'
            '/-- `boxPair` of each `boxed` prim. -/\n'
            'def boxPairs : List (Option (Nat × SrcType)) := [\n' +
            ',\n'.join(f'  some ({prog.type_id(prog.funcs[i]["ret"])}, {lean_ty(prog.funcs[i]["params"][0][1])})'
                        if len(prog.funcs[i]['params']) == 1 else '  none' for i in prims['boxed']) +
            ']\n\n'
            'theorem boxPairs_same : pairsSame (prims.boxed.map (boxPair prog)) boxPairs = true := by decide +kernel\n\n'
            'theorem boxElem_self : boxElem prog prims = lookupBox boxPairs := boxElem_eq boxPairs_same\n\n'
            '/-- The `sigEntries` of the functions, in blocks. -/\n'
            'def sigBlocks : List (Nat × List SigEntry) := [\n' +
            ',\n'.join(f'  ({min(prog.n, lo + BLOCK) - lo}, [' +
                        ', '.join('none' if i in outside else
                                  f'some ({lean_list([t for _, t in prog.funcs[i]["params"]])}, '
                                  f'{lean_ty(prog.funcs[i]["ret"])})'
                                  for i in range(lo, min(prog.n, lo + BLOCK))) + '])'
                        for lo in range(0, prog.n, BLOCK)) +
            ']\n\n'
            'theorem sigBlocks_len : blocksLen sigBlocks = true := by decide +kernel\n\n'
            'theorem sigBlocks_fit : entriesFit prog.funcs (sigBlocks.map Prod.snd).flatten = true := by decide +kernel\n\n'
            'theorem sigBlocks_outside : noneAt 0 (sigBlocks.map Prod.snd).flatten = outside := by decide +kernel\n\n'
            'theorem callTy_self : callTy prog outside = sigCall (blockGet sigBlocks) :=\n'
            '  callTy_eq_blocks sigBlocks_len sigBlocks_fit sigBlocks_outside\n\n'
            f'end {NS}\n')
    write(os.path.join(outdir, 'SelfPureBase.lean'), base)

    parts = []
    for k, lo in enumerate(range(0, prog.n, chunk)):
        hi = min(prog.n, lo + chunk)
        lines = [f'import Lanius.Faithful.Gen.SelfPureBase\n\n{HEADER}\nnamespace {NS}\n\n'
                 'open Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n\n']
        proofs = []
        for i in range(lo, hi):
            if i in prim_set:
                proofs.append(('funcOk_prim (by decide +kernel)', f' -- {i} {names[i]}, a prim'))
            elif i in outside:
                proofs.append(('funcOk_outside (by decide +kernel)', f' -- {i} {names[i]}, outside'))
            else:
                lines.append(f'/-- {names[i]} -/\ntheorem pure{i} : PureFunc prog prims outside src{i} = true :=\n'
                             '  pureFunc_fast boxElem_self callTy_self (by decide +kernel)\n\n')
                proofs.append((f'funcOk_pure pure{i}', ''))
        lines.append(f'def part{k} : List SrcFunc := [{", ".join(f"src{i}" for i in range(lo, hi))}]\n\n')
        body = ''.join(f'  funcsOk_cons ({p}) <|{c}\n' for p, c in proofs)
        lines.append(f'theorem chunk{k} : FuncsOk prog prims outside {lo} part{k} :=\n{body}  funcsOk_nil\n\n'
                     f'end {NS}\n')
        write(os.path.join(outdir, f'SelfPure{k}.lean'), ''.join(lines))
        parts.append((k, lo, hi))

    decls_mod = (f'import Lanius.Faithful.Gen.SelfPureBase\n\n{HEADER}\nnamespace {NS}\n\n'
                 'open Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n\n'
                 'theorem decls_same : declsSame prog.decls decls = true := by decide +kernel\n\n'
                 'theorem prog_decls : prog.decls = decls := declsSame_eq decls_same\n\n'
                 f'end {NS}\n')
    write(os.path.join(outdir, 'SelfDecls.lean'), decls_mod)

    # The prims' templates.
    def boxed_args(i):
        f, body = prog.funcs[i], prog.src_text[i]
        so = re.search(r'letCall 39 \(SrcType\.uint \(UintTy\.usize\)\) (\d+) \[\]', body)
        sl = re.search(r'letCall 203 \S+ (\d+) \[', body)
        pa = re.search(r'discard \(SrcEff\.eCall (\d+) \[\]\)', body)
        return lean_ty(f['params'][0][1]), prog.type_id(f['ret']), int(so.group(1)), int(sl.group(1)), int(pa.group(1))

    def unbox_args(i):
        f, body = prog.funcs[i], prog.src_text[i]
        sl = re.search(r'letCall 39 \S+ (\d+) \[', body)
        return lean_ty(f['ret']), prog.type_id(f['params'][0][1]), int(sl.group(1))

    def forall(items):
        if not items:
            return 'fun _ h => nomatch h'
        return f'List.forall_mem_cons.2 ⟨{items[0]},\n    {forall(items[1:])}⟩'

    plines = [f'import Lanius.Faithful.Gen.SelfDecls\n\n{HEADER}\nnamespace {NS}\n\n'
              'open Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n\n'
              '-- `rfl` on `prog.funcs[i]?` unfolds the function list one function at a time.\n'
              'set_option maxRecDepth 100000\n\n']
    boxed_names, unbox_names = [], []
    for i in prims['boxed']:
        t, tid, so, sl, pa = boxed_args(i)
        plines.append(f'/-- {names[i]} -/\ntheorem boxed{i} : BoxedAt prog prims {i} :=\n'
                      f'  ⟨{t}, {tid}, {so}, {sl}, {pa}, rfl, rfl, rfl, rfl,\n'
                      f'    by rw [prog_decls]; decide +kernel, by rw [boxElem_self]; rfl⟩\n\n')
        boxed_names.append(f'boxed{i}')
    for i in prims['unbox']:
        t, tid, sl = unbox_args(i)
        plines.append(f'/-- {names[i]} -/\ntheorem unbox{i} : UnboxAt prog prims {i} :=\n'
                      f'  ⟨{t}, {tid}, {sl}, rfl, rfl, by rw [prog_decls]; decide +kernel, by rw [boxElem_self]; rfl⟩\n\n')
        unbox_names.append(f'unbox{i}')
    plines.append(f'theorem primsOk : PrimsOk prog prims :=\n  ⟨{forall(boxed_names)},\n  {forall(unbox_names)}⟩\n\n'
                  f'end {NS}\n')
    write(os.path.join(outdir, 'SelfPrims.lean'), ''.join(plines))

    agg = ([f'import Lanius.Faithful.Gen.SelfRep\nimport Lanius.Faithful.Gen.SelfPrims\n'] +
           [f'import Lanius.Faithful.Gen.SelfPure{k}\n' for k, _, _ in parts] +
           [f'\n{HEADER}\nnamespace {NS}\n\nopen Lanius.Mini\nopen Lanius.Faithful\nopen Lanius.Faithful.Self\n\n'
            '-- `rfl` and the chunks\' numbering unfold the function list one function at a time.\n'
            'set_option maxRecDepth 100000\n\n'
            f'theorem funcs_parts : prog.funcs = {" ++ (".join(f"part{k}" for k, _, _ in parts)}{")" * (len(parts) - 1)} := rfl\n\n'
            'theorem funcsOk : FuncsOk prog prims outside 0 prog.funcs := by\n  rw [funcs_parts]\n  exact\n'])
    expr = f'chunk{parts[-1][0]}'
    for k, lo, hi in reversed(parts[:-1]):
        expr = f'funcsOk_append chunk{k} ({expr})'
    agg.append(f'    {expr}\n\n'
               'theorem prims_eq : SelfRep.prims = prims := rfl\n\n'
               '/-- Every function of the self program but the prims and those `outside` has a\npure meaning. -/\n'
               'theorem selfPure : PureProg prog SelfRep.prims outside :=\n'
               '  prims_eq ▸ pureProg_of_funcsOk funcsOk\n\n'
               '/-- The self program\'s `boxed` and `unbox` prims are the templates. -/\n'
               'theorem selfPrims : PrimsOk prog SelfRep.prims := prims_eq ▸ primsOk\n\n'
               '#print axioms selfPure\n#print axioms selfPrims\n\n'
               f'end {NS}\n')
    write(os.path.join(outdir, 'SelfPure.lean'), ''.join(agg))

    print(f'{prog.n} functions: {prog.n - len(outside) - len(prim_set)} pure, {len(prim_set)} prims, '
          f'{len(outside)} outside; {len(parts)} chunks; {len(seen)} reached from the roots; '
          f'{len(decl.order_s)} structs, {len(decl.order_e)} enums declared')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
