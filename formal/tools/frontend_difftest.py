#!/usr/bin/env python3
"""The front end against laniusc's parse trees (roadmap step 8).

    python3 -I formal/tools/frontend_difftest.py WORKDIR [--count N] [--seed S] [--chunk C] [--mutations M] [--laniusc PATH] [--heavy PATH] [--generic]
    python3 -I formal/tools/frontend_difftest.py WORKDIR --cases formal/tools/frontend_cases [--laniusc PATH] [--heavy PATH]

Run from the repository root. Programs come from oracle_difftest.py's
generator (the front pass's subset: integers, bool, structs, enums, match,
if, while, calls, return, heap and slices, and with oracle.EFFECTS calls,
indexing, division, literals and match inside expressions), printed as
Lanius, C programs to a file. laniusc
parses each file on the GPU, under target/claude-work/bin/heavy; its parse
tree (the node_kind and parent arrays) is captured right after the kernel
that builds it (LANIUS_DEBUG_CAPTURE_PASS=parser/tree/parent_parallel), and
its lexer tokens are dumped (LANIUS_DEBUG_DUMP_BUFFERS=token_words).

Then, under `lake env lean`, `sourceProgram` (the Lean lexer, then the
extracted validator and builder) reads each file with laniusc's tree, and the
result must be the program this script expects the text to mean: the
generated program with each local named by the byte offset of its binding
from its function's name,
literals as the text writes them (`(-5)` is a negation, `(7 as u8)` a cast),
statement lists nested the way the reader nests them, and effectful
expressions collapsed the way the reader reads them (see collapse and
let_eval_head: pure parts are pure, and a statement with a pure form keeps
it). The Lean lexer's
tokens must also be laniusc's (kind, start and length). Finally M mutated
copies of each tree (a production id or a parent index changed) and of each
source (one `+` written as `-`) must be rejected.

With --generic, each file's programs are abstracted (see Chunk): generic
structs, enums and functions, a second file for the module gen::lib,
constants and a generic identity function. The expected program is the
generated one numbered as the front end's monomorphizer numbers it. The
generic programs have no effectful expressions (oracle.EFFECTS is off).

With --cases, runs hand-written cases instead (see run_cases).

Prints one line per difference and a summary; exits nonzero on any.
"""

import argparse
import os
import random
import re
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_difftest as oracle  # noqa: E402


def inputs_digest(workdir):
    """A digest of the files a check reads (the run cache keys on the check's
    text, which names these files but not their contents)."""
    import hashlib
    h = hashlib.sha256()
    for root, _, names in sorted(os.walk(workdir)):
        for name in sorted(names):
            if name.endswith(('.lani', '.prods', '.parents')):
                path = os.path.join(root, name)
                h.update(path.encode() + b'\0' + open(path, 'rb').read() + b'\0')
    return h.hexdigest()
import run_cache  # noqa: E402
oracle.EFFECTS = False  # set in main: effectful expressions, except with --generic
oracle.NESTED = False  # nested struct fields: the oracle's, not yet the front end tests'

HEAVY = 'target/claude-work/bin/heavy'
UINT_LEAN = oracle.UINT_LEAN
UINT_BITS = oracle.UINT_BITS


# ---------------------------------------------------------------- printing

class Printer:
    """Lanius text, with the byte offset of every binding occurrence from its
    function's name (the front end's local ids)."""

    def __init__(self):
        self.parts, self.pos, self.base, self.binding = [], 0, 0, {}

    def emit(self, text):
        self.parts.append(text)
        self.pos += len(text.encode())

    def func(self, text):
        """`fn name...`: the name starts the function's local numbering."""
        self.base = self.pos + len('fn ')
        self.emit(text)

    def bind(self, key, name):
        self.binding[key] = self.pos - self.base
        self.emit(name)

    def text(self):
        return ''.join(self.parts)


def lani_i32(k):
    if k == -2 ** 31:
        return '(-2147483647 - 1)'
    return f'({k})' if k < 0 else str(k)


def lean_i32(k):
    if k == -2 ** 31:
        return '(.apply .minus (.negate (.int 2147483647)) (.int 1))'
    if k < 0:
        return f'(.negate (.int {-k}))'
    return f'(.int {k})'


def uint_pieces(ty, k):
    """A literal of an unsigned type, as the text writes it: (k as T) below
    2^31, else 16-bit pieces combined with * 65536 and +."""
    if k < 2 ** 31:
        return [k]
    bits = UINT_BITS[ty]
    return [(k >> s) & 65535 for s in range(bits - 16, -1, -16)]


def lani_uint(ty, k):
    pieces = uint_pieces(ty, k)
    out = f'({pieces[0]} as {ty})'
    for p in pieces[1:]:
        out = f'(({out} * (65536 as {ty})) + ({p} as {ty}))'
    return out


def lani_isize(k, bare):
    """An isize literal as the oracle means it: below 2^31 in magnitude
    `(n as isize)`, or a bare n beside an operand of known type (laniusc
    infers it); else the cast of a u64 literal holding the same bits."""
    if -2 ** 31 <= k < 2 ** 31:
        return lani_i32(k) if bare else f'({lani_i32(k)} as isize)'
    return f'({lani_uint("u64", k & (2 ** 64 - 1))} as isize)'


def lean_isize(k, bare):
    """The reading of lani_isize's text: a bare literal is typed by its
    context, so each integer literal in it is `.cast .isize`."""
    if -2 ** 31 <= k < 2 ** 31:
        if bare:
            return re.sub(r'\(\.int (\d+)\)', r'(.cast .isize (.int \1))', lean_i32(k))
        return f'(.cast .isize {lean_i32(k)})'
    return f'(.cast .isize {lean_uint("u64", k & (2 ** 64 - 1))})'


def bare_beside(e, other):
    """e is an isize literal printed bare, beside the operand other."""
    return oracle.bare_isize(e) and oracle.typed_isize(other)


def lean_uint(ty, k):
    t = f'(.uint {UINT_LEAN[ty]})'
    pieces = uint_pieces(ty, k)
    out = f'(.cast {t} (.int {pieces[0]}))'
    for p in pieces[1:]:
        out = f'(.apply .plus (.apply .times {out} (.cast {t} (.int 65536))) (.cast {t} (.int {p})))'
    return out


class Chunk:
    """Programs printed to one file, and the program the reader must make of
    them. With generic=True some declarations take a type parameter that
    abstracts one of their types (every use writes the type it stands for, as a
    type argument or by inference), some move to a second file, the module
    gen::lib, some literals become constants, and a generic identity function
    is called at several types. The reader's program is then numbered the way
    build numbers it: the first file's non-generic functions in order, then
    each other instance when first called; the first file's non-generic types
    in order, then each other instance as the functions' types first need it."""

    def __init__(self, programs, rng=None, generic=False):
        self.programs = programs
        self.rng = rng
        self.generic = generic
        self.printers = {'main': Printer()}
        if generic:
            self.printers['lib'] = Printer()
            self.printers['main'].emit('module gen::main;\n\n')
            self.printers['lib'].emit('module gen::lib;\n\n')
        self.cur = 'main'
        self.compounds = 0
        self.module = {}      # ('t', k, kind, j) | ('f', k, j) | ('gid', k) | ('c', k, n) -> 'main' or 'lib'
        self.gen_ty = {}      # (k, kind, j) -> the type a generic struct or enum abstracts
        self.gen_fn = {}      # (k, j) -> the type a generic function abstracts
        self.subst = {}       # while printing a generic declaration: its abstracted type -> 'T'
        self.consts = {}      # k -> [(name, type, value text)]
        self.memo = {}        # id(expr) -> (expr, constant name or None)
        self.gid = {}         # k -> (the binding offset of gid's parameter, its file)
        self.gid_types = {}   # k -> the types gid is called at
        self.roots, self.seeds = [], []
        self.calls, self.tys, self.terms = {}, {}, {}
        self.key = None       # the function being printed

    @property
    def out(self):
        return self.printers[self.cur]

    def text(self, name='main'):
        return self.printers[name].text()

    # paths
    def qualify(self, entity, name):
        mod = self.module.get(entity, 'main')
        return name if not self.generic or mod == self.cur else f'gen::{mod}::{name}'

    def type_path(self, k, t):
        kind, j = t
        return self.qualify(('t', k, kind, j), f'P{k}{"S" if kind == "struct" else "E"}{j}')

    def fn_path(self, k, j):
        return self.qualify(('f', k, j), f'p{k}_f{j}')

    # names
    def ty(self, k, t):
        if t in self.subst:
            return self.subst[t]
        if t[0] == 'slice':
            return f'[{self.ty(k, t[1])}]'
        if t[0] in ('struct', 'enum'):
            g = self.gen_ty.get((k, t[0], t[1]))
            return self.type_path(k, t) + (f'<{self.ty(k, g)}>' if g is not None else '')
        return t

    def lean_ty(self, k, t):
        if t in UINT_BITS:
            return f'(.uint {UINT_LEAN[t]})'
        if t in ('i32', 'bool', 'ptr', 'unit', 'isize'):
            return '.' + t
        if t[0] == 'slice':
            return f'(.slice {self.lean_ty(k, t[1])})'
        p = self.programs[k]
        if t[0] == 'struct':
            return f'(.struct @T{k}s{t[1]}@ [{", ".join(self.lean_ty(k, f) for f in p.structs[t[1]])}])'
        if t[0] == 'enum':
            variants = ', '.join('[' + ', '.join(self.lean_ty(k, f) for f in v) + ']' for v in p.enums[t[1]])
            return f'(.enum @T{k}e{t[1]}@ [{variants}])'
        raise ValueError(t)

    # constants
    def constant(self, k, e):
        """The constant a literal is written as, if any (decided once per literal)."""
        if id(e) in self.memo:
            return self.memo[id(e)][1]
        name = None
        small = (e[0] == 'int' and 0 <= e[1]) or (e[0] == 'uint' and 0 <= e[2] < 2 ** 31)
        if self.generic and small and self.rng.random() < 0.15:
            consts = self.consts.setdefault(k, [])
            n = len(consts)
            name = f'K{k}_{n}'
            self.module[('c', k, n)] = 'lib' if self.rng.random() < 0.5 else 'main'
            consts.append((name, 'i32' if e[0] == 'int' else e[1], str(e[1] if e[0] == 'int' else e[2])))
            name = self.qualify(('c', k, n), name)
        self.memo[id(e)] = (e, name)
        return name

    # expressions: text, and the expected reading (ids by the binding table)
    def lani_expr(self, k, e, bare=False):
        kind = e[0]
        if kind in ('int', 'uint') and self.constant(k, e):
            return self.constant(k, e)
        if kind == 'int':
            return lani_i32(e[1])
        if kind == 'bool':
            return 'true' if e[1] else 'false'
        if kind == 'uint' and e[1] == 'isize':
            return lani_isize(e[2], bare)
        if kind == 'uint':
            return lani_uint(e[1], e[2])
        if kind == 'cast':
            return f'({self.lani_expr(k, e[2])} as {e[1]})'
        if kind == 'local':
            return f'v{e[1]}'
        if kind == 'field':
            return f'v{e[1]}.f{e[2]}'
        if kind == 'neg':
            return f'(-{self.lani_expr(k, e[1])})'
        if kind == 'not':
            return f'(!{self.lani_expr(k, e[1])})'
        return (f'({self.lani_expr(k, e[3], bare_beside(e[3], e[4]))} {e[2]} '
                f'{self.lani_expr(k, e[4], bare_beside(e[4], e[3]) and not bare_beside(e[3], e[4]))})')

    def lean_expr(self, k, ids, e, bare=False):
        kind = e[0]
        if kind == 'int':
            return lean_i32(e[1])
        if kind == 'bool':
            return '(.boolean true)' if e[1] else '(.boolean false)'
        if kind == 'uint' and e[1] == 'isize':
            if self.constant(k, e):
                return f'(.cast .isize (.int {e[2]}))'
            return lean_isize(e[2], bare)
        if kind == 'uint':
            if self.constant(k, e):
                return f'(.unsigned {UINT_LEAN[e[1]]} {e[2]})'
            return lean_uint(e[1], e[2])
        if kind == 'cast':
            return f'(.cast {self.lean_ty(None, e[1])} {self.lean_expr(k, ids, e[2])})'
        if kind == 'local':
            return f'(.local {ids[e[1]]})'
        if kind == 'field':
            return f'(.field {ids[e[1]]} {e[2]})'
        if kind == 'neg':
            return f'(.negate {self.lean_expr(k, ids, e[1])})'
        if kind == 'not':
            return f'(.not {self.lean_expr(k, ids, e[1])})'
        return (f'(.apply .{e[1]} {self.lean_expr(k, ids, e[3], bare_beside(e[3], e[4]))} '
                f'{self.lean_expr(k, ids, e[4], bare_beside(e[4], e[3]) and not bare_beside(e[3], e[4]))})')

    def compound(self, target, e):
        """Print every other `x = x op e` as `x op= e`."""
        if e[0] == 'op' and e[2] in ('+', '-', '*', '&', '|', '^') and e[3] == target:
            self.compounds += 1
            return self.compounds % 2 == 1
        return False

    def variant(self, k, enum, v, arm=False):
        name = f'P{k}E{enum}V{v}'
        if arm and self.generic and self.rng.random() < 0.3:
            return f'gen::{self.module[("t", k, "enum", enum)]}::{name}'
        return name if arm else self.qualify(('t', k, 'enum', enum), name)

    def call_text(self, k, j, args):
        """A call of function j: a generic callee's type argument is written,
        or left to inference when it shows in the callee's signature."""
        params, ret, _ = self.programs[k][j]
        g = self.gen_fn.get((k, j))
        targs = ''
        if g is not None and not ((g in params or g == ret) and self.rng.random() < 0.5):
            targs = f'<{self.ty(k, g)}>'
        return f'{self.fn_path(k, j)}{targs}(' + ', '.join(self.lani_expr(k, a) for a in args) + ')'

    def bind_let(self, k, ids, ident, ty):
        out = self.out
        out.bind((self.cur, k, ident), f'v{ident}')
        ids[ident] = out.binding[(self.cur, k, ident)]
        out.emit(f': {self.ty(k, ty)} = ')
        return ids[ident]

    # effectful expressions: print (binding a match's binders), and the
    # expected reading of the collapsed expression (see collapse)
    def emit_eff(self, k, ids, x, top=False):
        out = self.out
        kind = x[0]
        pure = collapse(x)
        if pure[0] == 'ePure':
            # printed as the pure expression it reads as (an isize literal
            # beside a typed operand is bare)
            out.emit(self.lani_expr(k, pure[1]))
        elif kind == 'eCall':
            self.calls[self.key].append(('f', k, x[1]))
            out.emit(self.fn_path(k, x[1]) + '(')
            for i, a in enumerate(x[2]):
                if i:
                    out.emit(', ')
                self.emit_eff(k, ids, a)
            out.emit(')')
        elif kind in ('eNeg', 'eNot'):
            out.emit('(-' if kind == 'eNeg' else '(!')
            self.emit_eff(k, ids, x[1])
            out.emit(')')
        elif kind == 'eCast':
            out.emit('(')
            self.emit_eff(k, ids, x[2])
            out.emit(f' as {x[1]})')
        elif kind == 'eStride':
            out.emit(f'slice_stride(v{x[1]})')
        elif kind == 'eIndex':
            out.emit(f'v{x[1]}[')
            self.emit_eff(k, ids, x[2])
            out.emit(']')
        elif kind in ('eApply', 'eDivide'):
            out.emit('(')
            self.emit_eff(k, ids, x[3])
            out.emit(f' {x[2]} ')
            self.emit_eff(k, ids, x[4])
            out.emit(')')
        elif kind == 'eStruct':
            out.emit(f'{self.type_path(k, x[1])} {{ ')
            for j, f in enumerate(x[2]):
                out.emit((', ' if j else '') + f'f{j}: ')
                self.emit_eff(k, ids, f)
            out.emit(' }')
        elif kind == 'eVariant':
            out.emit(self.variant(k, x[1][1], x[2]))
            if x[3]:
                out.emit('(')
                for i, a in enumerate(x[3]):
                    if i:
                        out.emit(', ')
                    self.emit_eff(k, ids, a)
                out.emit(')')
        elif kind == 'eMatch':
            _, scrutinee, ety, ty, binders, values = x
            out.emit('match (' if top else '(match (')
            self.emit_eff(k, ids, scrutinee)
            out.emit(') { ')
            for v, (names, value) in enumerate(zip(binders, values)):
                out.emit(self.variant(k, ety[1], v, arm=True))
                if names:
                    out.emit('(')
                    for i, b in enumerate(names):
                        if i:
                            out.emit(', ')
                        out.bind((self.cur, k, b), f'v{b}')
                        ids[b] = out.binding[(self.cur, k, b)]
                    out.emit(')')
                out.emit(' -> ')
                self.emit_eff(k, ids, value)
                out.emit(', ')
            out.emit('}' if top else '})')
        else:
            raise ValueError(x)

    def lean_eff(self, k, ids, x):
        kind = x[0]
        if kind == 'ePure':
            return f'(.ePure {self.lean_expr(k, ids, x[1])})'
        if kind == 'eCall':
            return f'(.eCall @F{k}_{x[1]}@ [{", ".join(self.lean_eff(k, ids, a) for a in x[2])}])'
        if kind == 'eNeg':
            return f'(.eNeg {self.lean_eff(k, ids, x[1])})'
        if kind == 'eNot':
            return f'(.eNot {self.lean_eff(k, ids, x[1])})'
        if kind == 'eCast':
            return f'(.eCast {self.lean_ty(k, x[1])} {self.lean_eff(k, ids, x[2])})'
        if kind == 'eIndex':
            return f'(.eIndex {ids[x[1]]} {self.lean_eff(k, ids, x[2])})'
        if kind == 'eStride':
            return f'(.eStride {ids[x[1]]})'
        if kind in ('eApply', 'eDivide'):
            return f'(.{kind} .{x[1]} {self.lean_eff(k, ids, x[3])} {self.lean_eff(k, ids, x[4])})'
        if kind == 'eStruct':
            return f'(.eStruct {self.lean_ty(k, x[1])} [{", ".join(self.lean_eff(k, ids, f) for f in x[2])}])'
        if kind == 'eVariant':
            return f'(.eVariant {self.lean_ty(k, x[1])} {x[2]} [{", ".join(self.lean_eff(k, ids, f) for f in x[3])}])'
        _, scrutinee, ety, ty, binders, values = x
        bs = '[' + ', '.join('[' + ', '.join(str(ids[b]) for b in names) + ']' for names in binders) + ']'
        return (f'(.eMatch {self.lean_eff(k, ids, scrutinee)} {self.lean_ty(k, ety)} {self.lean_ty(k, ty)} {bs} '
                f'[{", ".join(self.lean_eff(k, ids, v) for v in values)}])')

    def let_eval_head(self, k, ids, lid, ty, x):
        """The reader keeps a let's statement form when its value is one (a
        pure expression, a call, literal or variant of pure values, a match
        of a local with pure arms, a slice element at a pure index)."""
        lty = self.lean_ty(k, ty)
        kind = x[0]

        def pures(xs):
            return all(a[0] == 'ePure' for a in xs)

        def exprs(xs):
            return '[' + ', '.join(self.lean_expr(k, ids, a[1]) for a in xs) + ']'
        if kind == 'ePure':
            return f'.let {lid} {lty} {self.lean_expr(k, ids, x[1])}'
        if kind == 'eCall' and pures(x[2]):
            return f'.letCall {lid} {lty} @F{k}_{x[1]}@ {exprs(x[2])}'
        if kind == 'eStruct' and pures(x[2]):
            return f'.letStruct {lid} {lty} {exprs(x[2])}'
        if kind == 'eVariant' and pures(x[3]):
            return f'.letEnum {lid} {lty} {x[2]} {exprs(x[3])}'
        if kind == 'eMatch' and x[1][0] == 'ePure' and x[1][1][0] == 'local' and pures(x[5]):
            arms = ', '.join(f'{{ binders := [{", ".join(str(ids[b]) for b in names)}], '
                             f'value := {self.lean_expr(k, ids, value[1])} }}' for names, value in zip(x[4], x[5]))
            return f'.letMatch {lid} {lty} {ids[x[1][1][1]]} @T{k}e{x[2][1]}@ [{arms}]'
        if kind == 'eIndex' and x[2][0] == 'ePure':
            return f'.letIndex {lid} {lty} {ids[x[1]]} {self.lean_expr(k, ids, x[2][1])}'
        return f'.letEval {lid} {lty} {self.lean_eff(k, ids, x)}'

    def eval_stmt(self, k, ids, s, indent):
        out, pad = self.out, '    ' * indent
        kind = s[0]
        if kind == 'letEval':
            ident, ty, x = s[1], s[2], s[3]
            self.tys[self.key].append(ty)
            out.emit(f'{pad}let ')
            lid = self.bind_let(k, ids, ident, ty)
            self.emit_eff(k, ids, x, top=True)
            out.emit(';\n')
            return [('let', self.let_eval_head(k, ids, lid, ty, collapse(x)))] + self.stmt(k, ids, s[4], indent)
        if kind == 'setEval':
            ident, x = s[1], s[2]
            arith = x[0] == 'eDivide' or (x[0] == 'eApply' and x[1] in oracle.ARITH_NAMES)
            if arith and self.rng.random() < 0.4:
                # `v op= e` reads as `v = v op e`
                x = x[:3] + (('ePure', ('local', ident)), x[4])
                out.emit(f'{pad}v{ident} {x[2]}= ')
                self.emit_eff(k, ids, x[4])
            else:
                out.emit(f'{pad}v{ident} = ')
                self.emit_eff(k, ids, x)
            out.emit(';\n')
            c = collapse(x)
            if c[0] == 'ePure':
                return [('stmt', f'(.set {ids[ident]} {self.lean_expr(k, ids, c[1])})')]
            if c[0] == 'eCall' and all(a[0] == 'ePure' for a in c[2]):
                args = ', '.join(self.lean_expr(k, ids, a[1]) for a in c[2])
                return [('stmt', f'(.setCall {ids[ident]} @F{k}_{c[1]}@ [{args}])')]
            return [('stmt', f'(.setEval {ids[ident]} {self.lean_eff(k, ids, c)})')]
        if kind in ('ifEval', 'whileEval'):
            word = kind[:-4]
            out.emit(f'{pad}{word} (')
            self.emit_eff(k, ids, s[1])
            out.emit(') {\n')
            c = collapse(s[1])
            cond = self.lean_expr(k, ids, c[1]) if c[0] == 'ePure' else self.lean_eff(k, ids, c)
            form = f'.{word}' + ('' if c[0] == 'ePure' else 'Eval')
            a = nest(self.stmt(k, ids, s[2], indent + 1))
            if kind == 'whileEval':
                out.emit(f'{pad}}}\n')
                return [('stmt', f'({form} {cond} {a})')]
            out.emit(f'{pad}}} else {{\n')
            b = nest(self.stmt(k, ids, s[3], indent + 1))
            out.emit(f'{pad}}}\n')
            return [('stmt', f'({form} {cond} {a} {b})')]
        if kind == 'setIndexEval':
            out.emit(f'{pad}v{s[1]}[')
            self.emit_eff(k, ids, s[2])
            out.emit('] = ')
            self.emit_eff(k, ids, s[3])
            out.emit(';\n')
            i, v = collapse(s[2]), collapse(s[3])
            if i[0] == 'ePure' and v[0] == 'ePure':
                return [('stmt', f'(.setIndex {ids[s[1]]} {self.lean_expr(k, ids, i[1])} {self.lean_expr(k, ids, v[1])})')]
            return [('stmt', f'(.setIndexEval {ids[s[1]]} {self.lean_eff(k, ids, i)} {self.lean_eff(k, ids, v)})')]
        if kind == 'setFieldEval':
            out.emit(f'{pad}v{s[1]}.f{s[2]} = ')
            self.emit_eff(k, ids, s[3])
            out.emit(';\n')
            c = collapse(s[3])
            if c[0] == 'ePure':
                return [('stmt', f'(.setField {ids[s[1]]} {s[2]} {self.lean_expr(k, ids, c[1])})')]
            return [('stmt', f'(.setFieldEval {ids[s[1]]} {s[2]} {self.lean_eff(k, ids, c)})')]
        if kind == 'returnUnit':
            out.emit(f'{pad}return;\n')
            return [('stmt', '.returnUnit')]
        if kind == 'assert':
            out.emit(f'{pad}assert(')
            self.emit_eff(k, ids, s[1])
            out.emit(');\n')
            return [('stmt', f'(.assert {self.lean_eff(k, ids, collapse(s[1]))})')]
        if kind == 'returnEval':
            out.emit(f'{pad}return ')
            self.emit_eff(k, ids, s[1])
            out.emit(';\n')
            c = collapse(s[1])
            if c[0] == 'ePure':
                return [('stmt', f'(.return {self.lean_expr(k, ids, c[1])})')]
            return [('stmt', f'(.returnEval {self.lean_eff(k, ids, c)})')]
        out.emit(pad)
        self.emit_eff(k, ids, s[1])
        out.emit(';\n')
        return [('stmt', f'(.discard {self.lean_eff(k, ids, collapse(s[1]))})')]

    # statements: print, and return the reader's items: ('let', head) whose
    # term is f'({head} {rest})', or ('stmt', term)
    def stmt(self, k, ids, s, indent):
        out, pad = self.out, '    ' * indent
        kind = s[0]
        if kind == 'nop':
            return []
        if kind in ('letEval', 'setEval', 'ifEval', 'whileEval', 'returnEval', 'discard', 'setIndexEval', 'setFieldEval',
                    'assert', 'returnUnit'):
            return self.eval_stmt(k, ids, s, indent)
        if kind == 'then':
            return self.stmt(k, ids, s[1], indent) + self.stmt(k, ids, s[2], indent)
        if kind in ('letAlloc', 'letSlice', 'letIndex'):
            ident = s[1]
            ty = 'ptr' if kind == 'letAlloc' else ('slice', s[2]) if kind == 'letSlice' else s[2]
            out.emit(f'{pad}let ')
            lid = self.bind_let(k, ids, ident, ty)
            if kind == 'letAlloc':
                size, shift = s[2], s[3]
                out.emit(f'alloc::allocator::alloc({lani_uint("usize", size)}, {lani_uint("usize", 1 << shift)});\n')
                head = f'.letAlloc {lid} {lean_uint("usize", size)} {shift}'
            elif kind == 'letSlice':
                self.tys[self.key].append(s[2])
                out.emit(f'slice_from_raw_parts({self.lani_expr(k, s[3])}, {s[4]});\n')
                head = f'.letSlice {lid} {self.lean_ty(k, s[2])} {self.lean_expr(k, ids, s[3])} {lean_i32(s[4])}'
            else:
                self.tys[self.key].append(s[2])
                out.emit(f'v{s[3]}[{s[4]}];\n')
                head = f'.letIndex {lid} {self.lean_ty(k, s[2])} {ids[s[3]]} {lean_i32(s[4])}'
            return [('let', head)] + self.stmt(k, ids, s[-1], indent)
        if kind == 'setIndex':
            out.emit(f'{pad}v{s[1]}[{s[2]}] = {self.lani_expr(k, s[3])};\n')
            return [('stmt', f'(.setIndex {ids[s[1]]} {lean_i32(s[2])} {self.lean_expr(k, ids, s[3])})')]
        if kind == 'free':
            size, shift = s[2], s[3]
            out.emit(f'{pad}alloc::allocator::dealloc(v{s[1]}, {lani_uint("usize", size)}, {lani_uint("usize", 1 << shift)});\n')
            return [('stmt', f'(.free (.local {ids[s[1]]}) {lean_uint("usize", size)} {shift})')]
        if kind in ('let', 'call', 'letStruct', 'letEnum', 'letMatch'):
            ident, ty = s[1], s[2]
            self.tys[self.key].append(ty)
            out.emit(f'{pad}let ')
            lid = self.bind_let(k, ids, ident, ty)
            lty = self.lean_ty(k, ty)
            if kind == 'let':
                out.emit(self.lani_expr(k, s[3]) + ';\n')
                head = f'.let {lid} {lty} {self.lean_expr(k, ids, s[3])}'
            elif kind == 'call':
                self.calls[self.key].append(('f', k, s[3]))
                out.emit(self.call_text(k, s[3], s[4]) + ';\n')
                head = (f'.letCall {lid} {lty} @F{k}_{s[3]}@ '
                        f'[{", ".join(self.lean_expr(k, ids, a) for a in s[4])}]')
            elif kind == 'letStruct':
                fields = ', '.join(f'f{j}: {self.lani_expr(k, f)}' for j, f in enumerate(s[3]))
                out.emit(f'{self.type_path(k, ty)} {{ {fields} }};\n')
                head = f'.letStruct {lid} {lty} [{", ".join(self.lean_expr(k, ids, f) for f in s[3])}]'
            elif kind == 'letEnum':
                payload = ', '.join(self.lani_expr(k, f) for f in s[4])
                out.emit(self.variant(k, ty[1], s[3]) + (f'({payload})' if s[4] else '') + ';\n')
                head = f'.letEnum {lid} {lty} {s[3]} [{", ".join(self.lean_expr(k, ids, f) for f in s[4])}]'
            else:
                _, _, _, scrutinee, enum, arms, _ = s
                self.tys[self.key].append(('enum', enum))
                out.emit(f'match (v{scrutinee}) {{\n')
                lean_arms = []
                for v, (binders, value) in enumerate(arms):
                    out.emit(f'{pad}    {self.variant(k, enum, v, arm=True)}')
                    if binders:
                        out.emit('(')
                        for i, b in enumerate(binders):
                            if i:
                                out.emit(', ')
                            out.bind((self.cur, k, b), f'v{b}')
                            ids[b] = out.binding[(self.cur, k, b)]
                        out.emit(')')
                    out.emit(f' -> {self.lani_expr(k, value)},\n')
                    lean_arms.append(f'{{ binders := [{", ".join(str(ids[b]) for b in binders)}], '
                                     f'value := {self.lean_expr(k, ids, value)} }}')
                out.emit(f'{pad}}};\n')
                head = f'.letMatch {lid} {lty} {ids[scrutinee]} @T{k}e{enum}@ [{", ".join(lean_arms)}]'
            return [('let', head)] + self.stmt(k, ids, s[-1], indent)
        if kind == 'set' and self.compound(('local', s[1]), s[2]):
            e = s[2]
            out.emit(f'{pad}v{s[1]} {e[2]}= {self.lani_expr(k, e[4], bare_beside(e[4], e[3]))};\n')
            return [('stmt', f'(.set {ids[s[1]]} {self.lean_expr(k, ids, s[2])})')]
        if kind == 'setField' and self.compound(('field', s[1], s[2]), s[3]):
            e = s[3]
            out.emit(f'{pad}v{s[1]}.f{s[2]} {e[2]}= {self.lani_expr(k, e[4], bare_beside(e[4], e[3]))};\n')
            return [('stmt', f'(.setField {ids[s[1]]} {s[2]} {self.lean_expr(k, ids, s[3])})')]
        if kind == 'set':
            out.emit(f'{pad}v{s[1]} = {self.lani_expr(k, s[2])};\n')
            return [('stmt', f'(.set {ids[s[1]]} {self.lean_expr(k, ids, s[2])})')]
        if kind == 'setField':
            out.emit(f'{pad}v{s[1]}.f{s[2]} = {self.lani_expr(k, s[3])};\n')
            return [('stmt', f'(.setField {ids[s[1]]} {s[2]} {self.lean_expr(k, ids, s[3])})')]
        if kind == 'if':
            out.emit(f'{pad}if ({self.lani_expr(k, s[1])}) {{\n')
            a = nest(self.stmt(k, ids, s[2], indent + 1))
            out.emit(f'{pad}}} else {{\n')
            b = nest(self.stmt(k, ids, s[3], indent + 1))
            out.emit(f'{pad}}}\n')
            return [('stmt', f'(.if {self.lean_expr(k, ids, s[1])} {a} {b})')]
        if kind == 'while':
            out.emit(f'{pad}while ({self.lani_expr(k, s[1])}) {{\n')
            body = nest(self.stmt(k, ids, s[2], indent + 1))
            out.emit(f'{pad}}}\n')
            return [('stmt', f'(.while {self.lean_expr(k, ids, s[1])} {body})')]
        out.emit(f'{pad}return {self.lani_expr(k, s[1])};\n')
        return [('stmt', f'(.return {self.lean_expr(k, ids, s[1])})')]

    # declarations
    def choose(self, k):
        """Which declarations are generic, and which move to gen::lib."""
        p, rng = self.programs[k], self.rng
        for kind, decls in (('struct', p.structs), ('enum', p.enums)):
            for j, d in enumerate(decls):
                fields = d if kind == 'struct' else [f for v in d for f in v]
                if fields and rng.random() < 0.5:
                    self.gen_ty[(k, kind, j)] = rng.choice(fields)
                self.module[('t', k, kind, j)] = 'lib' if rng.random() < 0.3 else 'main'
        # Function 0 calls the others; it stays a root (non-generic, in the
        # first file) so that they are reached.
        for j, (params, ret, body) in enumerate(p):
            if j and rng.random() < 0.5:
                self.gen_fn[(k, j)] = rng.choice(params + [ret] + let_types(body))
            self.module[('f', k, j)] = 'lib' if j and rng.random() < 0.25 else 'main'
        self.module[('gid', k)] = 'lib' if rng.random() < 0.5 else 'main'

    def type_decl(self, k, kind, j, decl):
        self.cur = self.module.get(('t', k, kind, j), 'main')
        g = self.gen_ty.get((k, kind, j))
        self.subst = {g: 'T'} if g is not None else {}
        out, params = self.out, '<T>' if g is not None else ''
        if kind == 'struct':
            out.emit(f'struct P{k}S{j}{params} {{ ' + ', '.join(f'f{i}: {self.ty(k, f)}' for i, f in enumerate(decl)) + ' }\n')
        else:
            out.emit(f'enum P{k}E{j}{params} {{\n')
            for v, payload in enumerate(decl):
                inner = '(' + ', '.join(self.ty(k, f) for f in payload) + ')' if payload else ''
                out.emit(f'    P{k}E{j}V{v}{inner},\n')
            out.emit('}\n')
        self.subst = {}
        if self.cur == 'main' and g is None:
            self.seeds.append((k, kind, j))

    def gid_call(self, k, ids, params):
        """`let gJ: T = gid(vI);` for a parameter I, at the start of a body."""
        i = self.rng.randrange(len(params))
        t = params[i]
        types = self.gid_types.setdefault(k, [])
        if t not in types:
            types.append(t)
        out = self.out
        out.emit('    let ')
        out.bind((self.cur, k, 'gid'), f'g{k}')
        lid = out.binding[(self.cur, k, 'gid')]
        targs = f'<{self.ty(k, t)}>' if self.rng.random() < 0.5 else ''
        out.emit(f': {self.ty(k, t)} = {self.qualify(("gid", k), f"p{k}_gid")}{targs}(v{i});\n')
        self.calls[self.key].append(('gid', k, types.index(t)))
        self.tys[self.key].append(t)
        return ('let', f'.letCall {lid} {self.lean_ty(k, t)} @G{k}_{types.index(t)}@ [(.local {ids[i]})]')

    def program(self, k):
        """Print program k, recording each function's expected Lean term, the
        instances it calls and the types it binds."""
        p = self.programs[k]
        oracle.TYPES = p
        if self.generic:
            self.choose(k)
        for j, fields in enumerate(p.structs):
            self.type_decl(k, 'struct', j, fields)
        for j, variants in enumerate(p.enums):
            self.type_decl(k, 'enum', j, variants)
        if self.generic:
            self.cur = self.module[('gid', k)]
            self.out.func(f'fn p{k}_gid<T>(')
            self.out.bind((self.cur, k, 'gid_x'), 'x')
            self.gid[k] = self.out.binding[(self.cur, k, 'gid_x')]
            self.out.emit(': T) -> T {\n    return x;\n}\n\n')
        for j, (params, ret, body) in enumerate(p):
            self.cur = self.module.get(('f', k, j), 'main')
            g = self.gen_fn.get((k, j))
            self.subst = {g: 'T'} if g is not None else {}
            self.key = ('f', k, j)
            self.calls[self.key], self.tys[self.key] = [], list(params) + [ret]
            out, ids = self.out, {}
            out.func(f'fn p{k}_f{j}' + ('<T>' if g is not None else '') + '(')
            for i, t in enumerate(params):
                if i:
                    out.emit(', ')
                out.bind((self.cur, k, (j, i)), f'v{i}')
                ids[i] = out.binding[(self.cur, k, (j, i))]
                out.emit(f': {self.ty(k, t)}')
            out.emit(') {\n' if ret == 'unit' else f') -> {self.ty(k, ret)} {{\n')
            items = []
            if self.generic and self.rng.random() < 0.5:
                items.append(self.gid_call(k, ids, params))
            items += self.stmt(k, ids, body, 1)
            out.emit('}\n\n')
            ps = ', '.join(f'{{ id := {ids[i]}, ty := {self.lean_ty(k, t)} }}' for i, t in enumerate(params))
            self.terms[self.key] = f'{{ params := [{ps}], ret := {self.lean_ty(k, ret)}, body := {nest(items)} }}'
            if self.cur == 'main' and g is None:
                self.roots.append(self.key)
            self.subst = {}
        for n, (name, t, value) in enumerate(self.consts.get(k, [])):
            self.cur = self.module[('c', k, n)]
            self.out.emit(f'const {name}: {t} = {value};\n')
        self.cur = 'main'
        for idx, t in enumerate(self.gid_types.get(k, [])):
            key, x, lt = ('gid', k, idx), self.gid[k], self.lean_ty(k, t)
            self.calls[key], self.tys[key] = [], [t, t]
            self.terms[key] = f'{{ params := [{{ id := {x}, ty := {lt} }}], ret := {lt}, body := (.return (.local {x})) }}'

    # numbering
    def insts(self, k, t):
        """The type instances t's source type has ids for, in build's order."""
        if t[0] == 'slice':
            return self.insts(k, t[1])
        if t[0] not in ('struct', 'enum'):
            return []
        p = self.programs[k]
        fields = p.structs[t[1]] if t[0] == 'struct' else [f for v in p.enums[t[1]] for f in v]
        return [(k, t[0], t[1])] + [x for f in fields for x in self.insts(k, f)]

    def finish(self):
        """The expected functions, one Lean term per line, numbered as build numbers them."""
        table = list(self.roots)
        i = 0
        while i < len(table):
            for c in self.calls[table[i]]:
                if c not in table:
                    table.append(c)
            i += 1
        types = list(self.seeds)
        for k, kind, j in list(self.seeds):
            for x in self.insts(k, (kind, j)):
                if x not in types:
                    types.append(x)
        for key in table:
            k = key[1]
            for t in self.tys[key]:
                for x in self.insts(k, t):
                    if x not in types:
                        types.append(x)
        fn_id = {key: n for n, key in enumerate(table)}
        type_id = {key: n for n, key in enumerate(types)}

        def fill(m):
            tag = m.group(1)
            if tag[0] == 'T':
                k, rest = tag[1:].split('s') if 's' in tag else tag[1:].split('e')
                kind = 'struct' if 's' in tag else 'enum'
                return str(type_id[(int(k), kind, int(rest))])
            k, j = tag[1:].split('_')
            return str(fn_id[('f' if tag[0] == 'F' else 'gid', int(k), int(j))])
        return [re.sub(r'@([TFG][0-9a-z_]+)@', fill, self.terms[key]) for key in table]


def collapse(x):
    """An effectful expression as the reader reads it: the operators, casts
    and negations of pure operands are pure."""
    kind = x[0]
    if kind in ('ePure', 'eStride'):
        return x
    if kind == 'eCall':
        return ('eCall', x[1], [collapse(a) for a in x[2]])
    if kind in ('eNeg', 'eNot'):
        a = collapse(x[1])
        if a[0] == 'ePure':
            return ('ePure', ('neg' if kind == 'eNeg' else 'not', a[1]))
        return (kind, a)
    if kind == 'eCast':
        a = collapse(x[2])
        return ('ePure', ('cast', x[1], a[1])) if a[0] == 'ePure' else ('eCast', x[1], a)
    if kind == 'eIndex':
        return ('eIndex', x[1], collapse(x[2]))
    if kind in ('eApply', 'eDivide'):
        a, b = collapse(x[3]), collapse(x[4])
        if kind == 'eApply' and a[0] == 'ePure' and b[0] == 'ePure':
            return ('ePure', ('op', x[1], x[2], a[1], b[1]))
        return (kind, x[1], x[2], a, b)
    if kind == 'eStruct':
        return ('eStruct', x[1], [collapse(f) for f in x[2]])
    if kind == 'eVariant':
        return ('eVariant', x[1], x[2], [collapse(f) for f in x[3]])
    return ('eMatch', collapse(x[1]), x[2], x[3], x[4], [collapse(v) for v in x[5]])


def let_types(s):
    """The types a statement's lets bind (a slice's element type)."""
    if not isinstance(s, tuple) or not s:
        return []
    kind = s[0]
    here = []
    if kind in ('let', 'call', 'letStruct', 'letEnum', 'letMatch', 'letIndex', 'letSlice'):
        here = [s[2]]
    return here + [t for x in s[1:] if isinstance(x, tuple) for t in let_types(x)]


def add_frees(rng, s):
    """Free some allocations at the end of their scope (the reader does not
    run the program, so where does not matter)."""
    if not isinstance(s, tuple) or not s:
        return s
    out = tuple(add_frees(rng, x) if isinstance(x, tuple) else x for x in s)
    if out[0] == 'letAlloc' and rng.random() < 0.5:
        out = out[:-1] + (('then', out[-1], ('free', out[1], out[2], out[3])),)
    return out


def nest(items):
    """The reader's statement list: a let scopes over the rest."""
    if not items:
        return '.nop'
    (kind, term), rest = items[0], items[1:]
    if kind == 'let':
        return f'({term} {nest(rest)})'
    if not rest:
        return term
    return f'(.then {term} {nest(rest)})'


# ---------------------------------------------------------------- laniusc

def words(path):
    data = open(path, 'rb').read()
    return list(struct.unpack('<%dI' % (len(data) // 4), data))


IMPORT_LINE = re.compile(rb'^[ \t]*import[ \t]+([A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*)[ \t]*;', re.M)
GAP = re.compile(rb'(?:\s|//[^\n]*)*')


def import_lines(source):
    """The `import m;` lines of a file: they must come together, right after
    its `module` item (or first), with only blanks and comments around."""
    found = list(IMPORT_LINE.finditer(source))
    if not found:
        return []
    head = source[:found[0].start()]
    head = re.sub(rb'//[^\n]*', b'', head)
    if head.strip() and not re.fullmatch(rb'\s*module[ \t]+[A-Za-z_][A-Za-z0-9_:]*[ \t]*;\s*', head):
        raise SystemExit('import lines must follow the module line')
    for a, b in zip(found, found[1:]):
        if not GAP.fullmatch(source, a.end(), b.start()):
            raise SystemExit('import lines must come together')
    return found


def import_spans(path):
    """The byte spans of a file's import lines (laniusc's dump skips their tokens)."""
    return [(m.start(), m.end()) for m in import_lines(open(path, 'rb').read())]


def splice_imports(prods, parents, k, paths):
    """laniusc's tree of the file with these imports (each a list of path
    segments) as items k, k+1, ... of its item list. laniusc parsed the file
    with the import lines blanked (with them it parses the whole program).
    The front end validates the result against the file's own tokens."""
    # item_list -> item item_list (1) | (2): the chain of item_list nodes
    kids = {}
    for i, q in enumerate(parents):
        kids.setdefault(q, []).append(i)
    chain = [1]
    while prods[chain[-1]] == 1:
        chain.append(kids[chain[-1]][-1])
    at = chain[k]
    new_prods, new_parents = [], []
    up = parents[at]
    for segs in paths:
        base = at + len(new_prods)
        nodes = [(1, up), (6, base), (43, base + 1), (44, base + 2), (47, base + 3), (48, base + 4)]
        tail = base + 4
        for _ in segs[1:]:
            nodes += [(50, tail), (48, base + len(nodes))]
            tail = base + len(nodes) - 2
        nodes.append((51, tail))
        new_prods += [a for a, _ in nodes]
        new_parents += [b for _, b in nodes]
        up = base
    n = len(new_prods)
    shifted = [q + n if q != 4294967295 and q >= at else q for q in parents]
    shifted[at] = up
    return (prods[:at] + new_prods + prods[at:], shifted[:at] + new_parents + shifted[at:])


def parse_with_laniusc(heavy, laniusc, lani_path, workdir):
    source = open(lani_path, 'rb').read()
    found = import_lines(source)
    if found:
        blank = bytearray(source)
        for m in found:
            blank[m.start():m.end()] = b' ' * (m.end() - m.start())
        blanked = os.path.join(workdir, 'blanked_' + os.path.basename(lani_path))
        open(blanked, 'wb').write(bytes(blank))
        prods, parents, tokens = parse_plain(heavy, laniusc, blanked, workdir)
        k = 1 if re.match(rb'(?:\s|//[^\n]*)*module\b', source) else 0
        prods, parents = splice_imports(prods, parents, k, [m.group(1).decode().split('::') for m in found])
        return prods, parents, tokens
    return parse_plain(heavy, laniusc, lani_path, workdir)


def parse_plain(heavy, laniusc, lani_path, workdir):
    """laniusc's tree and tokens of one file (cached by its bytes and laniusc)."""
    k = run_cache.key(run_cache.file_digest(laniusc), open(lani_path, 'rb').read())
    hit = run_cache.load('parse', k)
    if hit is not None:
        return hit['prods'], hit['parents'], [tuple(t) for t in hit['tokens']]
    prods, parents, tokens = parse_uncached(heavy, laniusc, lani_path, workdir)
    run_cache.store('parse', k, dict(prods=prods, parents=parents, tokens=tokens))
    return prods, parents, tokens


def parse_uncached(heavy, laniusc, lani_path, workdir):
    cap = os.path.join(workdir, 'cap')
    env = dict(os.environ,
               LANIUS_DEBUG_CAPTURE_PASS='parser/tree/parent_parallel',
               LANIUS_DEBUG_CAPTURE_DIR=cap,
               LANIUS_DEBUG_DUMP_BUFFERS='token_words,token_count',
               LANIUS_DEBUG_DUMP_WORDS='4000000',
               LANIUS_DEBUG_DUMP_DIR=workdir)
    shutil.rmtree(cap, ignore_errors=True)
    for name in os.listdir(workdir):
        if name.endswith('.bin'):
            os.remove(os.path.join(workdir, name))
    # The file has no main, so the compile fails after parsing; the capture
    # and the dump are written anyway.
    subprocess.run([heavy, '-t', '10', laniusc, '--stdlib-root', 'stdlib', '-o', os.path.join(workdir, 'a.out'),
                    lani_path], env=env, capture_output=True, text=True)
    count = words(os.path.join(cap, 'post', '002_tree_count_status.bin'))[5]
    prods = words(os.path.join(cap, 'post', '006_node_kind.bin'))[:count]
    parents = words(os.path.join(cap, 'post', '007_parent.bin'))[:count]
    # A generic program is lexed twice: as written (type_check), and again
    # after laniusc's own monomorphization (x86_64).
    stage = 'type_check' if os.path.exists(os.path.join(workdir, 'type_check.token_count.bin')) else 'x86_64'
    ntok = words(os.path.join(workdir, f'{stage}.token_count.bin'))[0]
    tw = words(os.path.join(workdir, f'{stage}.token_words.bin'))
    tokens = [(tw[3 * i], tw[3 * i + 1], tw[3 * i + 2]) for i in range(ntok)]
    if len(prods) != count or len(tw) < 3 * ntok:
        raise SystemExit(f'{lani_path}: the capture or the dump is short')
    return prods, parents, tokens


# ---------------------------------------------------------------- Lean

LEAN_HEAD = '''import Lanius.Mini.FrontLex
open Lanius.Mini
set_option linter.unusedVariables false

-- The front end's program, written the way this script writes the expected
-- one (elaborating the expected programs as Lean terms is far too slow).
def serTy : UintTy → String
  | .uint8 => ".uint8" | .uint32 => ".uint32" | .uint64 => ".uint64" | .usize => ".usize" | .uint16 => ".uint16"

def serOp : SrcOp → String
  | .plus => "plus" | .minus => "minus" | .times => "times" | .bitAnd => "bitAnd"
  | .bitOr => "bitOr" | .bitXor => "bitXor" | .shiftLeft => "shiftLeft" | .shiftRight => "shiftRight"
  | .less => "less" | .lessEq => "lessEq"
  | .greater => "greater" | .greaterEq => "greaterEq" | .equal => "equal"
  | .notEqual => "notEqual" | .logicalAnd => "logicalAnd" | .logicalOr => "logicalOr"

def bracket (xs : List String) : String := "[" ++ ", ".intercalate xs ++ "]"

partial def serType : SrcType → String
  | .i32 => ".i32" | .bool => ".bool" | .ptr => ".ptr"
  | .uint u => s!"(.uint {serTy u})"
  | .struct n fs => s!"(.struct {n} {bracket (fs.map serType)})"
  | .enum n vs => s!"(.enum {n} {bracket (vs.map fun v => bracket (v.map serType))})"
  | .slice t => s!"(.slice {serType t})"
  | .unit => ".unit"
  | .isize => ".isize"
  | .char => ".char"
  | .sint u => s!"(.sint {serTy u})"

partial def serExpr : SrcExpr → String
  | .int k => s!"(.int {k.toNat})"
  | .boolean b => s!"(.boolean {b})"
  | .unsigned u k => s!"(.unsigned {serTy u} {k.toNat})"
  | .local n => s!"(.local {n})"
  | .field n f => s!"(.field {n} {f})"
  | .negate e => s!"(.negate {serExpr e})"
  | .not e => s!"(.not {serExpr e})"
  | .apply o a b => s!"(.apply .{serOp o} {serExpr a} {serExpr b})"
  | .cast t e => s!"(.cast {serType t} {serExpr e})"
  | .null => ".null"
  | .char c => s!"(.char {c.toNat})"

def serExprs (es : List SrcExpr) : String := bracket (es.map serExpr)

def serDiv : SrcDivOp → String
  | .quotient => ".quotient" | .remainder => ".remainder"

partial def serEff : SrcEff → String
  | .ePure e => s!"(.ePure {serExpr e})"
  | .eCall f args => s!"(.eCall {f} {bracket (args.map serEff)})"
  | .eApply o a b => s!"(.eApply .{serOp o} {serEff a} {serEff b})"
  | .eNeg a => s!"(.eNeg {serEff a})"
  | .eNot a => s!"(.eNot {serEff a})"
  | .eCast t a => s!"(.eCast {serType t} {serEff a})"
  | .eIndex sl i => s!"(.eIndex {sl} {serEff i})"
  | .eStruct t fs => s!"(.eStruct {serType t} {bracket (fs.map serEff)})"
  | .eVariant t k ps => s!"(.eVariant {serType t} {k} {bracket (ps.map serEff)})"
  | .eMatch x e t bs vs =>
    s!"(.eMatch {serEff x} {serType e} {serType t} {bracket (bs.map fun b => bracket (b.map toString))} {bracket (vs.map serEff)})"
  | .eDivide o a b => s!"(.eDivide {serDiv o} {serEff a} {serEff b})"
  | .eStride sl => s!"(.eStride {sl})"

def serArm (a : SrcArm) : String :=
  "{ binders := " ++ bracket (a.binders.map toString) ++ ", value := " ++ serExpr a.value ++ " }"

partial def serStmt : SrcStmt → String
  | .nop => ".nop"
  | .let n t e r => s!"(.let {n} {serType t} {serExpr e} {serStmt r})"
  | .letStruct n t es r => s!"(.letStruct {n} {serType t} {serExprs es} {serStmt r})"
  | .letCall n t f es r => s!"(.letCall {n} {serType t} {f} {serExprs es} {serStmt r})"
  | .letEnum n t v es r => s!"(.letEnum {n} {serType t} {v} {serExprs es} {serStmt r})"
  | .letMatch n t x e arms r => s!"(.letMatch {n} {serType t} {x} {e} {bracket (arms.map serArm)} {serStmt r})"
  | .set n e => s!"(.set {n} {serExpr e})"
  | .setField n f e => s!"(.setField {n} {f} {serExpr e})"
  | .setCall n f es => s!"(.setCall {n} {f} {serExprs es})"
  | .then a b => s!"(.then {serStmt a} {serStmt b})"
  | .if e a b => s!"(.if {serExpr e} {serStmt a} {serStmt b})"
  | .while e b => s!"(.while {serExpr e} {serStmt b})"
  | .return e => s!"(.return {serExpr e})"
  | .letAlloc n size shift r => s!"(.letAlloc {n} {serExpr size} {shift} {serStmt r})"
  | .letLoad n p o r => s!"(.letLoad {n} {serExpr p} {serExpr o} {serStmt r})"
  | .setByte p o v => s!"(.setByte {serExpr p} {serExpr o} {serExpr v})"
  | .free p size shift => s!"(.free {serExpr p} {serExpr size} {shift})"
  | .letSlice n t p len r => s!"(.letSlice {n} {serType t} {serExpr p} {serExpr len} {serStmt r})"
  | .letIndex n t sl i r => s!"(.letIndex {n} {serType t} {sl} {serExpr i} {serStmt r})"
  | .setIndex sl i v => s!"(.setIndex {sl} {serExpr i} {serExpr v})"
  | .letEval n t x r => s!"(.letEval {n} {serType t} {serEff x} {serStmt r})"
  | .setEval n x => s!"(.setEval {n} {serEff x})"
  | .ifEval x a b => s!"(.ifEval {serEff x} {serStmt a} {serStmt b})"
  | .whileEval x b => s!"(.whileEval {serEff x} {serStmt b})"
  | .returnEval x => s!"(.returnEval {serEff x})"
  | .discard x => s!"(.discard {serEff x})"
  | .setIndexEval sl i v => s!"(.setIndexEval {sl} {serEff i} {serEff v})"
  | .setFieldEval n f x => s!"(.setFieldEval {n} {f} {serEff x})"
  | .returnUnit => ".returnUnit"
  | .assert x => s!"(.assert {serEff x})"

def serParam (p : SrcParam) : String := "{ id := " ++ toString p.id ++ ", ty := " ++ serType p.ty ++ " }"

def serFunc (f : SrcFunc) : String :=
  "{ params := " ++ bracket (f.params.map serParam) ++ ", ret := " ++ serType f.ret ++ ", body := " ++ serStmt f.body ++ " }"

def readNats (path : String) : IO (List Nat) := do
  let text ← IO.FS.readFile path
  return (text.splitOn " ").filterMap String.toNat?

def readSource (path : String) : IO (List Lanius.Compiler.Lexer.Byte) := do
  let bytes ← IO.FS.readBinFile path
  return bytes.toList.map (fun b => Fin.ofNat 256 b.toNat)

-- One file: write its Lean tokens and its program (one function per line),
-- then report each mutant (its base, and the source it uses) as rejected or
-- accepted.
def check (base : String) (mutants : List (String × String)) : IO Unit := do
  let source ← readSource (base ++ ".lani")
  let prods ← readNats (base ++ ".prods")
  let parents ← readNats (base ++ ".parents")
  match lexTokens source with
  | none => IO.println s!"{base}: does not lex"
  | some tokens =>
    IO.FS.writeFile (base ++ ".leantokens")
      (" ".intercalate (tokens.map fun t => s!"{t.kind}:{t.start}:{t.text.length}"))
    -- sourceProgram source prods parents, without lexing twice
    match frontEnd grammar tokens prods parents with
    | none => IO.println s!"{base}: rejected by the front end"
    | some got =>
      IO.FS.writeFile (base ++ ".got") (String.join (got.funcs.map fun f => serFunc f ++ "\\n"))
      IO.println s!"{base}: read"
    for (mb, src) in mutants do
      let toks ← if src == base ++ ".lani" then pure (some tokens) else do
        let s ← readSource src
        pure (lexTokens s)
      let mp ← readNats (mb ++ ".prods")
      let mq ← readNats (mb ++ ".parents")
      match toks with
      | none => IO.println s!"{mb}: rejected"
      | some ts =>
        match validateTree grammar ts mp mq with
        | none => IO.println s!"{mb}: rejected"
        | some root => IO.println s!"{mb}: ACCEPTED"

-- Several files, the program's own first: as `check`, with the several-file
-- front end, and mutants of the first file.
def checkMulti (bases : List String) (mutants : List (String × String)) : IO Unit := do
  let mut files : List FileInput := []
  let mut firstTokens : List Token := []
  for base in bases do
    let source ← readSource (base ++ ".lani")
    let prods ← readNats (base ++ ".prods")
    let parents ← readNats (base ++ ".parents")
    match lexTokens source with
    | none => IO.println s!"{base}: does not lex"
    | some tokens =>
      IO.FS.writeFile (base ++ ".leantokens")
        (" ".intercalate (tokens.map fun t => s!"{t.kind}:{t.start}:{t.text.length}"))
      if files.isEmpty then firstTokens := tokens
      files := files ++ [{ tokens := tokens, prods := prods, parents := parents }]
  let first := bases.headD ""
  match frontEndFiles grammar files with
  | none => IO.println s!"{first}: rejected by the front end"
  | some got =>
    IO.FS.writeFile (first ++ ".got") (String.join (got.funcs.map fun f => serFunc f ++ "\\n"))
    IO.println s!"{first}: read"
  for (mb, src) in mutants do
    let toks ← if src == first ++ ".lani" then pure (some firstTokens) else do
      let s ← readSource src
      pure (lexTokens s)
    let mp ← readNats (mb ++ ".prods")
    let mq ← readNats (mb ++ ".parents")
    match toks with
    | none => IO.println s!"{mb}: rejected"
    | some ts =>
      match validateTree grammar ts mp mq with
      | none => IO.println s!"{mb}: rejected"
      | some root => IO.println s!"{mb}: ACCEPTED"

-- Locals renamed to their rank among the function's binding ids, so that two
-- texts of one program (a generic one and its hand-monomorphized copy) can be
-- compared.
partial def effBinders : SrcEff → List Nat
  | .ePure _ | .eStride _ => []
  | .eCall _ xs | .eStruct _ xs | .eVariant _ _ xs => xs.flatMap effBinders
  | .eApply _ a b | .eDivide _ a b => effBinders a ++ effBinders b
  | .eNeg a | .eNot a | .eCast _ a | .eIndex _ a => effBinders a
  | .eMatch x _ _ bs vs => effBinders x ++ bs.flatten ++ vs.flatMap effBinders

partial def bindersOf : SrcStmt → List Nat
  | .let n _ _ r | .letStruct n _ _ r | .letCall n _ _ _ r | .letEnum n _ _ _ r => n :: bindersOf r
  | .letMatch n _ _ _ arms r => n :: arms.flatMap (·.binders) ++ bindersOf r
  | .letAlloc n _ _ r | .letLoad n _ _ r | .letSlice n _ _ _ r | .letIndex n _ _ _ r => n :: bindersOf r
  | .then a b | .if _ a b => bindersOf a ++ bindersOf b
  | .while _ b => bindersOf b
  | .letEval n _ x r => n :: effBinders x ++ bindersOf r
  | .setEval _ x | .returnEval x | .discard x => effBinders x
  | .ifEval x a b => effBinders x ++ bindersOf a ++ bindersOf b
  | .whileEval x b => effBinders x ++ bindersOf b
  | .setIndexEval _ i v => effBinders i ++ effBinders v
  | .setFieldEval _ _ x | .assert x => effBinders x
  | _ => []

partial def renExpr (f : Nat → Nat) : SrcExpr → SrcExpr
  | .local n => .local (f n)
  | .field n j => .field (f n) j
  | .negate e => .negate (renExpr f e)
  | .not e => .not (renExpr f e)
  | .apply o a b => .apply o (renExpr f a) (renExpr f b)
  | .cast t e => .cast t (renExpr f e)
  | e => e

partial def renEff (f : Nat → Nat) : SrcEff → SrcEff
  | .ePure e => .ePure (renExpr f e)
  | .eCall c xs => .eCall c (xs.map (renEff f))
  | .eApply o a b => .eApply o (renEff f a) (renEff f b)
  | .eNeg a => .eNeg (renEff f a)
  | .eNot a => .eNot (renEff f a)
  | .eCast t a => .eCast t (renEff f a)
  | .eIndex sl i => .eIndex (f sl) (renEff f i)
  | .eStruct t xs => .eStruct t (xs.map (renEff f))
  | .eVariant t k xs => .eVariant t k (xs.map (renEff f))
  | .eMatch x e t bs vs => .eMatch (renEff f x) e t (bs.map (·.map f)) (vs.map (renEff f))
  | .eDivide o a b => .eDivide o (renEff f a) (renEff f b)
  | .eStride sl => .eStride (f sl)

partial def renStmt (f : Nat → Nat) : SrcStmt → SrcStmt
  | .nop => .nop
  | .let n t e r => .let (f n) t (renExpr f e) (renStmt f r)
  | .letStruct n t es r => .letStruct (f n) t (es.map (renExpr f)) (renStmt f r)
  | .letCall n t c es r => .letCall (f n) t c (es.map (renExpr f)) (renStmt f r)
  | .letEnum n t v es r => .letEnum (f n) t v (es.map (renExpr f)) (renStmt f r)
  | .letMatch n t x e arms r =>
    .letMatch (f n) t (f x) e (arms.map fun a => { binders := a.binders.map f, value := renExpr f a.value }) (renStmt f r)
  | .set n e => .set (f n) (renExpr f e)
  | .setField n j e => .setField (f n) j (renExpr f e)
  | .setCall n c es => .setCall (f n) c (es.map (renExpr f))
  | .then a b => .then (renStmt f a) (renStmt f b)
  | .if e a b => .if (renExpr f e) (renStmt f a) (renStmt f b)
  | .while e b => .while (renExpr f e) (renStmt f b)
  | .return e => .return (renExpr f e)
  | .letAlloc n s k r => .letAlloc (f n) (renExpr f s) k (renStmt f r)
  | .letLoad n p o r => .letLoad (f n) (renExpr f p) (renExpr f o) (renStmt f r)
  | .setByte p o v => .setByte (renExpr f p) (renExpr f o) (renExpr f v)
  | .free p s k => .free (renExpr f p) (renExpr f s) k
  | .letSlice n t p l r => .letSlice (f n) t (renExpr f p) (renExpr f l) (renStmt f r)
  | .letIndex n t s i r => .letIndex (f n) t (f s) (renExpr f i) (renStmt f r)
  | .setIndex s i v => .setIndex (f s) (renExpr f i) (renExpr f v)
  | .letEval n t x r => .letEval (f n) t (renEff f x) (renStmt f r)
  | .setEval n x => .setEval (f n) (renEff f x)
  | .ifEval x a b => .ifEval (renEff f x) (renStmt f a) (renStmt f b)
  | .whileEval x b => .whileEval (renEff f x) (renStmt f b)
  | .returnEval x => .returnEval (renEff f x)
  | .discard x => .discard (renEff f x)
  | .setIndexEval sl i v => .setIndexEval (f sl) (renEff f i) (renEff f v)
  | .setFieldEval n k x => .setFieldEval (f n) k (renEff f x)
  | .returnUnit => .returnUnit
  | .assert x => .assert (renEff f x)

def canonFunc (fn : SrcFunc) : SrcFunc :=
  let ids := (fn.params.map (·.id) ++ bindersOf fn.body).mergeSort (· ≤ ·)
  let f := fun n => ids.findIdx (· == n)
  { params := fn.params.map fun p => { id := f p.id, ty := p.ty }, ret := fn.ret, body := renStmt f fn.body }

-- Several files, the program's own first: write the program with locals
-- renamed by rank, or report a rejection.
def checkFiles (bases : List String) (out : String) : IO Unit := do
  let mut files : List FileInput := []
  for base in bases do
    let source ← readSource (base ++ ".lani")
    let prods ← readNats (base ++ ".prods")
    let parents ← readNats (base ++ ".parents")
    match lexTokens source with
    | none => IO.println s!"{base}: does not lex"
    | some tokens =>
      IO.FS.writeFile (base ++ ".leantokens")
        (" ".intercalate (tokens.map fun t => s!"{t.kind}:{t.start}:{t.text.length}"))
      files := files ++ [{ tokens := tokens, prods := prods, parents := parents }]
  match frontEndFiles grammar files with
  | none =>
    IO.FS.writeFile out "rejected\\n"
    IO.println s!"{out}: rejected"
  | some got =>
    IO.FS.writeFile out (String.join (got.funcs.map fun f => serFunc (canonFunc f) ++ "\\n"))
    IO.println s!"{out}: read"
    IO.FS.writeFile (out ++ ".compile") (if (compileSource got).isSome then "compiles\\n" else "rejected\\n")
'''


def run_cases(args, cases_dir):
    """Hand-written cases. A case directory holds the files of one program
    (main.lani first, then the others in name order) and either want.lani,
    a single-file monomorphic copy that must read as the same program up to
    local names, or a file named reject, when the program must be rejected."""
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)
    lean = [LEAN_HEAD]
    checks = []
    for case in sorted(os.listdir(cases_dir)):
        src = os.path.join(cases_dir, case)
        if not os.path.isdir(src):
            continue
        names = sorted(n for n in os.listdir(src) if n.endswith('.lani') and n not in ('main.lani', 'want.lani'))
        groups = [('got', ['main.lani'] + names)]
        if os.path.exists(os.path.join(src, 'want.lani')):
            groups.append(('want', ['want.lani']))
        out_dir = os.path.join(workdir, case)
        os.makedirs(out_dir, exist_ok=True)
        for kind, files in groups:
            bases = []
            for name in files:
                base = os.path.join(out_dir, kind + '_' + name[:-5])
                shutil.copy(os.path.join(src, name), base + '.lani')
                prods, parents, tokens = parse_with_laniusc(args.heavy, args.laniusc, base + '.lani', out_dir)
                open(base + '.gputokens', 'w').write(' '.join(f'{k}:{s}:{n}' for k, s, n in tokens))
                open(base + '.prods', 'w').write(' '.join(map(str, prods)))
                open(base + '.parents', 'w').write(' '.join(map(str, parents)))
                bases.append(base)
            out = os.path.join(out_dir, kind + '.out')
            lean.append(f'#eval checkFiles [{", ".join(chr(34) + b + chr(34) for b in bases)}] "{out}"')
        checks.append((case, out_dir, os.path.exists(os.path.join(src, 'reject'))))
    lean_path = os.path.join(workdir, 'cases_check.lean')
    lean.append(f'-- inputs {inputs_digest(workdir)}')
    open(lean_path, 'w').write('\n'.join(lean) + '\n')
    run = run_cache.run_lean(lean_path)
    if run.returncode != 0:
        raise SystemExit('lean failed:\n' + run.stdout[-4000:] + run.stderr[-4000:])
    problems = unchecked = 0
    for case, out_dir, reject in checks:
        for name in sorted(os.listdir(out_dir)):
            if name.endswith('.gputokens'):
                base = os.path.join(out_dir, name[:-len('.gputokens')])
                lean_tokens = open(base + '.leantokens').read().split() if os.path.exists(base + '.leantokens') else None
                gpu_tokens = open(base + '.gputokens').read().split()
                spans = import_spans(base + '.lani')
                if lean_tokens is not None and spans:
                    # laniusc lexed the file with its import lines blanked
                    lean_tokens = [t for t in lean_tokens
                                   if not any(a <= int(t.split(':')[1]) < b for a, b in spans)]
                size = os.path.getsize(base + '.lani')
                if any(int(t.split(':')[1]) + int(t.split(':')[2]) > size for t in gpu_tokens):
                    # laniusc lexed a rewritten text after this one (its own
                    # handling of generics); its dump is not this file's.
                    unchecked += 1
                    continue
                if lean_tokens != gpu_tokens:
                    problems += 1
                    print(f'{base}: the Lean lexer and laniusc disagree')
        got = open(os.path.join(out_dir, 'got.out')).read()
        if os.path.exists(os.path.join(cases_dir, case, 'compiles')):
            # the program read must also pass compileSource
            compiled = os.path.join(out_dir, 'got.out.compile')
            if not os.path.exists(compiled) or open(compiled).read() != 'compiles\n':
                problems += 1
                print(f'{case}: compileSource rejects the program read')
        if reject:
            ok = got == 'rejected\n'
        else:
            want = open(os.path.join(out_dir, 'want.out')).read()
            ok = got != 'rejected\n' and got == want
        if not ok:
            problems += 1
            print(f'{case}: {"accepted, should be rejected" if reject else "differs (see got.out and want.out)"}')
    print(f'{len(checks)} cases, {problems} problems ({unchecked} files whose tokens laniusc does not dump as written)')
    return 1 if problems else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=100)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--chunk', type=int, default=25)
    parser.add_argument('--mutations', type=int, default=3)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--heavy', default=HEAVY)
    parser.add_argument('--generic', action='store_true', help='abstract types into type parameters, and use two modules')
    parser.add_argument('--cases', help='run the hand-written cases in this directory instead')
    args = parser.parse_args()
    if args.cases:
        return run_cases(args, args.cases)
    oracle.EFFECTS = not args.generic
    oracle.enable_isize()
    rng = random.Random(args.seed)
    programs = [oracle.gen_program(rng) for _ in range(args.count)]
    for p in programs:
        p[:] = [(params, ret, add_frees(rng, body)) for params, ret, body in p]
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)
    lean = [LEAN_HEAD]
    problems = 0
    tokens_total = nodes_total = mutations = 0
    generic_total = moved_total = consts_total = 0
    for c, start in enumerate(range(0, len(programs), args.chunk)):
        chunk = Chunk(programs[start:start + args.chunk], rng, args.generic)
        for k in range(len(chunk.programs)):
            chunk.program(k)
        funcs = chunk.finish()
        base = os.path.join(workdir, f'chunk{c}')
        bases = [base] + ([base + '_lib'] if args.generic else [])
        for b, name in zip(bases, ['main', 'lib']):
            for ext in ('.got', '.leantokens'):
                if os.path.exists(b + ext):
                    os.remove(b + ext)
            open(b + '.lani', 'w').write(chunk.text(name))
            prods, parents, tokens = parse_with_laniusc(args.heavy, args.laniusc, b + '.lani', workdir)
            tokens_total += len(tokens)
            nodes_total += len(prods)
            open(b + '.prods', 'w').write(' '.join(map(str, prods)))
            open(b + '.parents', 'w').write(' '.join(map(str, parents)))
            open(b + '.gputokens', 'w').write(' '.join(f'{k}:{s}:{n}' for k, s, n in tokens))
            if name == 'main':
                main_prods, main_parents = prods, parents
        prods, parents, text = main_prods, main_parents, chunk.text('main')
        open(base + '.want', 'w').write(''.join(f + '\n' for f in funcs))
        mutants = []
        plus_at = [i for i, ch in enumerate(text) if ch == '+']
        for m in range(args.mutations):
            mb = f'{base}.m{m}'
            mp, mq, src = list(prods), list(parents), base + '.lani'
            which = m % 3
            if which == 0:
                i = rng.randrange(len(mp))
                mp[i] = rng.choice([p for p in range(318) if p != mp[i]])
            elif which == 1:
                i = rng.randrange(1, len(mq))
                mq[i] = rng.choice([p for p in range(len(mq)) if p != mq[i]])
            elif plus_at:
                i = rng.choice(plus_at)
                src = mb + '.lani'
                open(src, 'w').write(text[:i] + '-' + text[i + 1:])
            else:
                continue
            open(mb + '.prods', 'w').write(' '.join(map(str, mp)))
            open(mb + '.parents', 'w').write(' '.join(map(str, mq)))
            mutants.append(f'("{mb}", "{src}")')
            mutations += 1
        if args.generic:
            lean.append(f'#eval checkMulti [{", ".join(chr(34) + b + chr(34) for b in bases)}] [{", ".join(mutants)}]')
        else:
            lean.append(f'#eval check "{base}" [{", ".join(mutants)}]')
        generic_total += len(chunk.gen_ty) + len(chunk.gen_fn)
        moved_total += sum(1 for m in chunk.module.values() if m == 'lib')
        consts_total += sum(len(v) for v in chunk.consts.values())
    lean_path = os.path.join(workdir, 'frontend_check.lean')
    lean.append(f'-- inputs {inputs_digest(workdir)}')
    open(lean_path, 'w').write('\n'.join(lean) + '\n')
    run = run_cache.run_lean(lean_path)
    if run.returncode != 0:
        raise SystemExit('lean failed:\n' + run.stdout[-4000:] + run.stderr[-4000:])
    lines = run.stdout.strip().split('\n')
    for line in lines:
        if not (line.endswith(': read') or line.endswith(': rejected')):
            print(line)
            problems += 1
    rejected = sum(line.endswith(': rejected') for line in lines)
    lexer_diffs = oks = unchecked = 0
    for c in range((len(programs) + args.chunk - 1) // args.chunk):
        base = os.path.join(workdir, f'chunk{c}')
        if os.path.exists(base + '.got'):
            got = open(base + '.got').read().split('\n')
            want = open(base + '.want').read().split('\n')
            if got == want:
                oks += 1
            else:
                problems += 1
                diff = [i for i, (g, w) in enumerate(zip(got, want)) if g != w]
                where = f'function {diff[0]}' if diff else f'{len(got)} lines, want {len(want)}'
                print(f'{base}: the program differs from the expected one at {where} (see .got and .want)')
        for b in [base] + ([base + '_lib'] if args.generic else []):
            if not os.path.exists(b + '.leantokens'):
                continue
            gpu_tokens = open(b + '.gputokens').read().split()
            size = os.path.getsize(b + '.lani')
            if any(int(t.split(':')[1]) + int(t.split(':')[2]) > size for t in gpu_tokens):
                # laniusc lexed a rewritten text after this one (its own
                # handling of generics); its dump is not this file's.
                unchecked += 1
                continue
            if open(b + '.leantokens').read().split() != gpu_tokens:
                print(f'{b}: the Lean lexer and laniusc disagree')
                lexer_diffs += 1
    problems += lexer_diffs
    print(f'{len(programs)} programs in {oks} files read as expected, {tokens_total} tokens, {nodes_total} tree nodes; '
          f'{rejected}/{mutations} mutations rejected; {lexer_diffs} lexer disagreements; {problems} problems')
    if args.generic:
        print(f'generic: {generic_total} declarations made generic, {moved_total} moved to gen::lib, '
              f'{consts_total} literals written as constants; {unchecked} files whose tokens laniusc does not dump as written')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
