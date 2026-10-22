#!/usr/bin/env python3
"""The verified compiler as an oracle for laniusc (roadmap step 12).

Random source programs in the front pass's subset are compiled twice: by the
verified compiler (`compileSource`, the extracted Lean definitions, run by
`#eval`), whose image runs natively here, and by laniusc, from the same
program printed as Lanius. Every call of each program's entry function on its
argument tuples must give the same result.

    python3 -I formal/tools/oracle_difftest.py WORKDIR [--count N] [--seed S] [--calls K] [--chunk C] [--only K,..] [--laniusc PATH]

Run from the repository root. laniusc runs under target/claude-work/bin/heavy, in a
systemd-run scope capped at 6 GB.
A Python interpreter of the generated programs gives a third answer, so a
disagreement shows which side is wrong. Prints one line per disagreement and a
summary; exits nonzero on any.

The programs use i32, bool, the unsigned types, isize (frontend_difftest.py
leaves it out), structs and enums of those: literals, locals, fields, the
operators, casts, variants, `match`, `let`,
assignment, `if`, bounded `while` loops, calls to later functions (so every
run ends) and `return`. The entry function also allocates raw slices of i32,
word structs and word enums (`alloc`, `ptr + usize`, `slice_from_raw_parts`),
writes every element, then reads and writes them at literal indices. A
function's first parameter is an i32 the harness passes; the entry function
returns an i32.

With EFFECTS (frontend_difftest.py turns it off) the programs also use the
front pass's effectful expressions (`SrcEff`, in `let`, assignment, `if` and
`while` conditions, `return` and bare call statements): calls nested in the
operators, casts, `/` and `%` (divisors (d | 1), and (d | 1) & -3 for i32, so
no division traps), struct and enum literals with such fields, and
reads of slices of i32, word structs and word enums at computed indices kept
in bounds (a literal,
e & (n - 1) or nonnegative e % n), and `match` expressions of any type on
a call, literal, local or match, whose arms use their binders (an arm makes
no new locals), and `s[i] = value` of a slice of i32, word structs or word
enums with an effectful index and value (for structs and enums often another
slice's element, to[i] = from[j]); often the value calls a function that
writes s at the same literal index, which the store, after the value in
Core's order, overwrites. Also x.f = value for a scalar field of a struct
local with an effectful value. Some later functions return unit (no
`-> T`; mostly ones that write a slice they are passed), are called as
statements, may end without a return and return early with `return;` inside
if and while; `assert` conditions always hold ((c || true), (c || !c) on a
pure c, (e & 255) >= 0, (e % 7) < 7), because the verified compiler's image
does not trap on a false assert (its theorem is about runs that return)
while laniusc's does. Later
functions take struct, enum and slice parameters and return structs and
enums; one with a slice parameter writes into the caller's slice, the right
side of `&&` and `||` often calls one, and the entry's result folds in every
element of its slices, so evaluation order and short circuit show in the
result. `while` conditions are `counter < bound && c` (either way round), so
loops stay bounded whatever c calls.

isize is a 64-bit two's complement slot: + - * & | ^ and unary minus wrap
at 64 bits, < <= > >= are signed, and casts sign-extend an i32, keep an
unsigned value's bits, and wrap on the way out; there is no isize division
and no slice of isize. Its literals, edge values near 2^63 among them, are
`.cast .isize (.int n)` in Lean (a u64 literal's bits beyond i32), and in
Lanius `(n as isize)`, or a bare `n` beside an operand of known type (`x + 5`).
The entry's result also folds in an isize computed from its values and calls
and each isize local and field it has: low and high 32 bits and a signed
comparison, so wraparound and sign reach the answer.
"""

import argparse
import ctypes
import mmap
import os
import random
import re
import subprocess
import sys

I32_EDGES = [0, 1, -1, 2, 7, -7, 100, 65535, 65536, 2 ** 31 - 1, -2 ** 31, 2 ** 30, -2 ** 30]
ARITH = [('plus', '+'), ('minus', '-'), ('times', '*'), ('bitAnd', '&'), ('bitOr', '|'), ('bitXor', '^')]
ORDER = [('less', '<'), ('lessEq', '<='), ('greater', '>'), ('greaterEq', '>=')]
EQUAL = [('equal', '=='), ('notEqual', '!=')]
LOGIC = [('logicalAnd', '&&'), ('logicalOr', '||')]
UINT_BITS = {'u8': 8, 'u32': 32, 'u64': 64, 'usize': 64}
UINT_LEAN = {'u8': '.uint8', 'u32': '.uint32', 'u64': '.uint64', 'usize': '.usize'}
INTEGERS = ['i32'] + list(UINT_BITS)
WORDS = ['i32', 'bool'] + list(UINT_BITS)  # the field types slices hold, one native word each
SLICES = True  # generate heap and slice statements
# Generate effectful expressions (calls inside expressions, in conditions,
# assignments and returns, and as statements) and struct, enum and slice
# parameters and struct and enum results (frontend_difftest.py turns them off).
EFFECTS = True
ARITH_NAMES = [name for name, _ in ARITH]
DIVIDE = [('quotient', '/'), ('remainder', '%')]
# isize (main turns it on; frontend_difftest.py's front end has no isize yet):
# a scalar like the others, but no division and no slices of it.
ISIZE_EDGES = [0, 1, -1, 2, -2, 2 ** 31 - 1, -2 ** 31, 2 ** 32, -2 ** 32, 2 ** 62, -2 ** 62,
               2 ** 63 - 1, -2 ** 63, 2 ** 63 - 2, -2 ** 63 + 1]
EXTRA = []  # ['isize', 'isize'] with isize: weighted into let, comparison and cast choices


def enable_isize():
    if 'isize' not in SCALARS:
        SCALARS.append('isize')
        INTEGERS.append('isize')
        EXTRA.extend(['isize', 'isize'])
        WORDS.append('isize')


def i32(x):
    x &= 0xffffffff
    return x - (1 << 32) if x >> 31 else x


# ---------------------------------------------------------------- generator
# Types: 'i32' 'bool' 'u8' 'u32' 'u64' 'usize' 'ptr' ('struct', k) ('enum', k) ('slice', element, n),
# struct k's field types TYPES.structs[k], enum k's variants' payload types TYPES.enums[k];
# n is the slice's length, known statically.
# Expressions: ('int', k) ('bool', b) ('uint', ty, k) ('local', id) ('field', id, j) ('neg', e)
#              ('not', e) ('cast', ty, e) ('op', name, sym, l, r)
# Effectful expressions: ('ePure', e) ('eCall', callee, args) ('eApply', name, sym, l, r) ('eNeg', x)
#              ('eNot', x) ('eCast', ty, x) ('eDivide', name, sym, l, r) ('eStruct', ty, fields)
#              ('eVariant', ty, variant, payload) ('eIndex', slice, x) of a slice local (i32, word struct
#              or word enum elements) ('eStride', slice) the slice local's slice_stride, an isize
#              ('eMatch', scrutinee, ety, ty, binders, values): arm k binds variant k's payload
# Statements: ('nop',) ('let', id, ty, e, body) ('call', id, ty, callee, args, body) ('set', id, e)
#             ('letStruct', id, ty, fields, body) ('letEnum', id, ty, variant, payload, body)
#             ('letMatch', id, ty, scrutinee, enum, arms, body) with arms [(binders, value)]
#             ('setField', id, j, e) ('then', a, b) ('if', c, a, b) ('while', c, body) ('return', e)
#             ('letAlloc', id, size, shift, body) ('letSlice', id, element, address, n, body)
#             ('letIndex', id, element, slice, k, body) ('setIndex', slice, k, e)
#             ('letEval', id, ty, x, body) ('setEval', id, x) ('ifEval', x, a, b) ('whileEval', x, body)
#             ('returnEval', x) ('discard', x) ('setIndexEval', slice, x, y) ('setFieldEval', id, j, x),
#             ('assert', x) ('returnUnit',), with x, y effectful expressions; a function's ret may be 'unit'

SCALARS = ['i32', 'bool'] + list(UINT_BITS)
LETS = ('let', 'call', 'letStruct', 'letEnum', 'letMatch', 'letAlloc', 'letSlice', 'letIndex', 'letEval')


def is_object(t):
    """A struct or enum type: copied by value, several slots."""
    return isinstance(t, tuple) and t[0] in ('struct', 'enum')


def fits(param, t):
    """A value of type t passes as param: a slice parameter's length is the
    least its body indexes, so a longer slice passes too."""
    if isinstance(param, tuple) and param[0] == 'slice':
        return isinstance(t, tuple) and t[0] == 'slice' and t[1] == param[1] and t[2] >= param[2]
    return t == param


def slice_elements():
    """i32 and the word structs and enums, the element types Core lays out."""
    elements = ['i32'] + [('struct', k) for k, fs in enumerate(TYPES.structs) if all(f in WORDS for f in fs)]
    return elements + [('enum', k) for k, vs in enumerate(TYPES.enums) if all(f in WORDS for v in vs for f in v)]


class Program(list):
    """A program's functions (params, ret, body), with its struct and enum types."""

    def __init__(self, funcs, structs, enums):
        super().__init__(funcs)
        self.structs = structs
        self.enums = enums


TYPES = Program([], [], [])  # the program being generated, printed or run


class Gen:
    def __init__(self, rng, sigs, index):
        self.rng = rng
        self.sigs = sigs
        self.index = index
        self.fresh = 100
        self.slices = 0
        self.sealed = 0  # inside a match arm: no new locals, which could not see its binders

    def new_id(self):
        self.fresh += 1
        return self.fresh

    def lit_i32(self):
        if self.rng.random() < 0.6:
            return self.rng.choice(I32_EDGES)
        return self.rng.randint(-2 ** 31, 2 ** 31 - 1)

    def lit_isize(self):
        if self.rng.random() < 0.6:
            return self.rng.choice(ISIZE_EDGES)
        if self.rng.random() < 0.5:
            return self.rng.randint(-2 ** 31, 2 ** 31 - 1)
        return self.rng.randint(-2 ** 63, 2 ** 63 - 1)

    def lit_uint(self, ty):
        bits = UINT_BITS[ty]
        if self.rng.random() < 0.6:
            return self.rng.choice([0, 1, 2, 255, (1 << bits) - 1, 1 << (bits - 1), (1 << (bits - 1)) - 1])
        return self.rng.randrange(1 << bits)

    def expr(self, ty, depth, env):
        rng = self.rng
        names = [('local', i) for i, t in env if t == ty]
        names += [('field', i, j) for i, t in env if t[0] == 'struct'
                  for j, f in enumerate(TYPES.structs[t[1]]) if f == ty]
        if depth == 0 or rng.random() < 0.25:
            if names and rng.random() < 0.7:
                return rng.choice(names)
            if ty == 'i32':
                return ('int', self.lit_i32())
            if ty == 'bool':
                return ('bool', rng.random() < 0.5)
            if ty == 'isize':
                return ('uint', 'isize', self.lit_isize())
            return ('uint', ty, self.lit_uint(ty))
        if ty == 'isize':
            pick = rng.random()
            if pick < 0.2:
                return ('cast', 'isize', self.expr(rng.choice(INTEGERS), depth - 1, env))
            if pick < 0.3:
                return ('neg', self.expr('isize', depth - 1, env))
            name, sym = rng.choice(ARITH)
            return ('op', name, sym, self.expr(ty, depth - 1, env), self.expr(ty, depth - 1, env))
        if ty in UINT_BITS:
            if rng.random() < 0.2:
                return ('cast', ty, self.expr(rng.choice(INTEGERS), depth - 1, env))
            name, sym = rng.choice(ARITH)
            return ('op', name, sym, self.expr(ty, depth - 1, env), self.expr(ty, depth - 1, env))
        if ty == 'i32' and rng.random() < 0.1:
            return ('cast', 'i32', self.expr(rng.choice(list(UINT_BITS) + EXTRA), depth - 1, env))
        if ty == 'i32':
            if rng.random() < 0.15:
                return ('neg', self.expr('i32', depth - 1, env))
            name, sym = rng.choice(ARITH)
            return ('op', name, sym, self.expr('i32', depth - 1, env), self.expr('i32', depth - 1, env))
        pick = rng.random()
        if pick < 0.15:
            return ('not', self.expr('bool', depth - 1, env))
        if pick < 0.55:
            name, sym = rng.choice(ORDER + EQUAL)
            operand = rng.choice(['i32', 'i32'] + list(UINT_BITS) + EXTRA)
            return ('op', name, sym, self.expr(operand, depth - 1, env), self.expr(operand, depth - 1, env))
        if pick < 0.7:
            name, sym = rng.choice(EQUAL)
            return ('op', name, sym, self.expr('bool', depth - 1, env), self.expr('bool', depth - 1, env))
        name, sym = rng.choice(LOGIC)
        return ('op', name, sym, self.expr('bool', depth - 1, env), self.expr('bool', depth - 1, env))

    def make_struct(self, env, items, k=None):
        if k is None:
            k = self.rng.randrange(len(TYPES.structs))
        ident = self.new_id()
        items.append(('letStruct', ident, ('struct', k), [self.expr(f, 2, env) for f in TYPES.structs[k]]))
        env.append((ident, ('struct', k)))
        return ident

    def make_enum(self, env, items, k=None):
        if k is None:
            k = self.rng.randrange(len(TYPES.enums))
        variant = self.rng.randrange(len(TYPES.enums[k]))
        ident = self.new_id()
        payload = [self.expr(f, 2, env) for f in TYPES.enums[k][variant]]
        items.append(('letEnum', ident, ('enum', k), variant, payload))
        env.append((ident, ('enum', k)))
        return ident, k

    def store(self, env, items, view, element, index):
        if element == 'i32':
            items.append(('setIndex', view, index, self.expr('i32', 2, env)))
        elif element[0] == 'struct':
            items.append(('setIndex', view, index, ('local', self.make_struct(env, items, element[1]))))
        else:
            items.append(('setIndex', view, index, ('local', self.make_enum(env, items, element[1])[0])))

    def make_slice(self, env, items):
        """A fresh allocation viewed as a slice the way Core lays it out: i32
        elements packed upward from the pointer, any other element as
        descending words with element zero at the top. Every element is
        written before anything reads one."""
        rng = self.rng
        wanted = [t for params, _ in self.sigs for t in params if isinstance(t, tuple) and t[0] == 'slice']
        if EFFECTS and wanted and rng.random() < 0.8:
            # Mostly a slice the callees with slice parameters accept.
            element = rng.choice(wanted)[1]
            n = rng.randint(max(t[2] for t in wanted if t[1] == element), 6)
        else:
            element = rng.choice(slice_elements())
            n = rng.randint(1, 6)
        pointer, view = self.new_id(), self.new_id()
        if element == 'i32':
            items.append(('letAlloc', pointer, 4 * n, 2))
            address = ('local', pointer)
        else:
            words = element_words(element)
            items.append(('letAlloc', pointer, 8 * words * n, 3))
            address = ('op', 'plus', '+', ('local', pointer), ('uint', 'usize', 8 * (words * n - 1)))
        env.append((pointer, 'ptr'))
        items.append(('letSlice', view, element, address, n))
        env.append((view, ('slice', element, n)))
        for i in range(n):
            self.store(env, items, view, element, i)

    def callees(self, ret, env):
        """The later functions returning ret (any type when None) whose
        parameters this scope can pass: a slice parameter needs a long enough
        slice local."""
        out = []
        for k in range(self.index + 1, len(self.sigs)):
            params, cret = self.sigs[k]
            if ret is not None and cret != ret:
                continue
            if all(not isinstance(t, tuple) or t[0] != 'slice' or any(fits(t, u) for _, u in env) for t in params):
                out.append(k)
        return out

    def pure_arg(self, t, env, items):
        """A call-free argument of type t: a scalar expression, or a local
        (a new struct or enum when there is none of the type yet)."""
        rng = self.rng
        if not isinstance(t, tuple):
            return self.expr(t, 2, env)
        if t[0] == 'slice':
            return ('local', rng.choice([i for i, u in env if fits(t, u)]))
        named = [i for i, u in env if u == t]
        if named and (self.sealed or rng.random() < 0.7):
            return ('local', rng.choice(named))
        if t[0] == 'struct':
            return ('local', self.make_struct(env, items, t[1]))
        return ('local', self.make_enum(env, items, t[1])[0])

    def eff_call(self, callee, depth, env, items):
        return ('eCall', callee, [self.eff(t, depth - 1, env, items) for t in self.sigs[callee][0]])

    def eff(self, ty, depth, env, items):
        """An effectful expression of type ty. A struct, enum or slice value is
        a local or (struct and enum) a call; scalars nest calls in the
        operators. Struct and enum locals it needs go into items first."""
        rng = self.rng
        calls = self.callees(ty, env) if depth > 0 else []
        if TYPES.enums and depth > 0 and (not isinstance(ty, tuple) or ty[0] != 'slice') and rng.random() < 0.1:
            return self.eff_match(ty, depth, env, items)
        if isinstance(ty, tuple):
            views = [(i, t[2]) for i, t in env if isinstance(t, tuple) and t[0] == 'slice' and t[1] == ty]
            if views and rng.random() < 0.4:
                # A word struct or enum element, read at an effectful index.
                view, n = rng.choice(views)
                return ('eIndex', view, self.in_bounds(n, depth, env, items))
            if calls and rng.random() < 0.5:
                return self.eff_call(rng.choice(calls), depth, env, items)
            if ty[0] != 'slice' and ((depth > 0 and rng.random() < 0.5) or
                                     (self.sealed and all(u != ty for _, u in env))):
                # A literal whose fields or payload may call functions.
                if ty[0] == 'struct':
                    return ('eStruct', ty, [self.eff(f, depth - 1, env, items) for f in TYPES.structs[ty[1]]])
                variant = rng.randrange(len(TYPES.enums[ty[1]]))
                payload = [self.eff(f, depth - 1, env, items) for f in TYPES.enums[ty[1]][variant]]
                return ('eVariant', ty, variant, payload)
            return ('ePure', self.pure_arg(ty, env, items))
        if calls and rng.random() < 0.5:
            return self.eff_call(rng.choice(calls), depth, env, items)
        views = [(i, t[2]) for i, t in env if isinstance(t, tuple) and t[0] == 'slice' and t[1] == 'i32']
        if ty == 'i32' and views and rng.random() < 0.25:
            view, n = rng.choice(views)
            return ('eIndex', view, self.in_bounds(n, depth, env, items))
        slices = [i for i, t in env if isinstance(t, tuple) and t[0] == 'slice']
        if ty == 'isize' and slices and rng.random() < 0.25:
            return ('eStride', rng.choice(slices))
        if depth <= 0 or rng.random() < 0.2:
            return ('ePure', self.expr(ty, rng.randint(0, 2), env))

        def sub(t):
            return self.eff(t, depth - 1, env, items)
        if rng.random() < 0.15 and ty not in ('bool', 'isize'):
            return self.divide(ty, sub)
        if ty == 'isize':
            pick = rng.random()
            if pick < 0.2:
                return ('eCast', 'isize', sub(rng.choice(INTEGERS)))
            if pick < 0.3:
                return ('eNeg', sub('isize'))
            name, sym = rng.choice(ARITH)
            return ('eApply', name, sym, sub(ty), sub(ty))
        if ty in UINT_BITS:
            if rng.random() < 0.2:
                return ('eCast', ty, sub(rng.choice(INTEGERS)))
            name, sym = rng.choice(ARITH)
            return ('eApply', name, sym, sub(ty), sub(ty))
        if ty == 'i32':
            pick = rng.random()
            if pick < 0.1:
                return ('eCast', 'i32', sub(rng.choice(list(UINT_BITS) + EXTRA)))
            if pick < 0.25:
                return ('eNeg', sub('i32'))
            name, sym = rng.choice(ARITH)
            return ('eApply', name, sym, sub('i32'), sub('i32'))
        pick = rng.random()
        if pick < 0.15:
            return ('eNot', sub('bool'))
        if pick < 0.5:
            name, sym = rng.choice(ORDER + EQUAL)
            operand = rng.choice(['i32', 'i32'] + list(UINT_BITS) + EXTRA)
            return ('eApply', name, sym, sub(operand), sub(operand))
        if pick < 0.6:
            name, sym = rng.choice(EQUAL)
            return ('eApply', name, sym, sub('bool'), sub('bool'))
        name, sym = rng.choice(LOGIC)
        left = sub('bool')
        right = self.called_bool(depth - 1, env, items) if rng.random() < 0.6 else None
        return ('eApply', name, sym, left, right or sub('bool'))

    def divide(self, ty, sub):
        """l / r or l % r with a divisor that never traps: (d | 1) for the
        unsigned types, (d | 1) & -3 for i32 (odd, so not zero, and bit 1
        clear, so not -1: no i32::MIN / -1)."""
        name, sym = self.rng.choice(DIVIDE)
        one = ('ePure', ('int', 1) if ty == 'i32' else ('uint', ty, 1))
        divisor = ('eApply', 'bitOr', '|', sub(ty), one)
        if ty == 'i32':
            divisor = ('eApply', 'bitAnd', '&', divisor, ('ePure', ('int', -3)))
        return ('eDivide', name, sym, sub(ty), divisor)

    def eff_match(self, ty, depth, env, items):
        """match scrutinee { arms } of type ty on an enum: the scrutinee a call,
        literal, local or match; arm k binds variant k's payload to fresh
        locals and its value may use them."""
        k = self.rng.randrange(len(TYPES.enums))
        ety = ('enum', k)
        scrutinee = self.eff(ety, depth - 1, env, items)
        binders, values = [], []
        self.sealed += 1
        before = len(items)
        for payload in TYPES.enums[k]:
            names = [self.new_id() for _ in payload]
            binders.append(names)
            values.append(self.eff(ty, depth - 1, env + list(zip(names, payload)), items))
        assert len(items) == before, 'a match arm made a local'
        self.sealed -= 1
        return ('eMatch', scrutinee, ety, ty, binders, values)

    def set_index_eval(self, view, element, n, env, items):
        """view[i] = value, value of the element type (i32, a word struct or a
        word enum). Often the value calls a function that writes view at the
        same literal index, which this store, coming after the value in
        Core's order, must overwrite; a struct or enum value is often
        another slice's element (to[i] = from[j])."""
        rng = self.rng
        writers = []
        for k in self.callees(None, env):
            params, cret = self.sigs[k]
            slots = [j for j, t in enumerate(params) if fits(t, ('slice', element, n)) and isinstance(t, tuple)]
            if slots and (cret in INTEGERS if element == 'i32' else cret == element):
                writers.append((k, slots[0]))
        if writers and rng.random() < 0.5:
            k, slot = rng.choice(writers)
            params, cret = self.sigs[k]
            args = [('ePure', ('local', view)) if j == slot else self.eff(t, 2, env, items) for j, t in enumerate(params)]
            value = ('eCall', k, args)
            if element == 'i32' and cret != 'i32':
                value = ('eCast', 'i32', value)
            if element == 'i32' and rng.random() < 0.5:
                name, sym = rng.choice(ARITH)
                value = ('eApply', name, sym, value, self.eff('i32', 1, env, items))
            index = ('ePure', ('int', rng.randrange(params[slot][2])))
            return ('setIndexEval', view, index, value)
        index = self.in_bounds(n, 3, env, items)
        sources = [(i, t[2]) for i, t in env if isinstance(t, tuple) and t[0] == 'slice' and t[1] == element]
        if element != 'i32' and rng.random() < 0.35:
            source, m = rng.choice(sources)
            return ('setIndexEval', view, index, ('eIndex', source, self.in_bounds(m, 2, env, items)))
        return ('setIndexEval', view, index, self.eff(element, 3, env, items))

    def in_bounds(self, n, depth, env, items):
        """An i32 or usize index below n (the slice's length, or the least a
        slice parameter has), since an index out of bounds traps: a literal,
        e & (n - 1) when n is a power of two, or a nonnegative e % n."""
        rng = self.rng
        ty = rng.choice(['i32', 'usize'])

        def lit(k):
            return ('ePure', ('int', k) if ty == 'i32' else ('uint', 'usize', k))
        if depth <= 0 or rng.random() < 0.2:
            return lit(rng.randrange(n))
        e = self.eff(ty, depth - 1, env, items)
        if n & (n - 1) == 0 and rng.random() < 0.5:
            return ('eApply', 'bitAnd', '&', e, lit(n - 1))
        if ty == 'i32':
            e = ('eApply', 'bitAnd', '&', e, lit(2 ** 31 - 1))
        return ('eDivide', 'remainder', '%', e, lit(n))

    def called_bool(self, depth, env, items):
        """A bool that calls a function, preferring one that writes into a
        slice, for the right side of && and ||: a call short circuit skips.
        None when no later function can be called here."""
        rng = self.rng
        later = [k for k in self.callees(None, env) if self.sigs[k][1] in SCALARS]
        if depth <= 0 or not later:
            return None
        writers = [k for k in later if any(isinstance(t, tuple) and t[0] == 'slice' for t in self.sigs[k][0])]
        callee = rng.choice(writers if writers and rng.random() < 0.7 else later)
        value, cret = self.eff_call(callee, depth, env, items), self.sigs[callee][1]
        if cret == 'bool':
            return value
        name, sym = rng.choice(ORDER + EQUAL)
        return ('eApply', name, sym, value, self.eff(cret, depth - 1, env, items))

    def block(self, depth, env, ret, must_return, mutable):
        """A statement list ending in a return when must_return. mutable: the ids
        assignments may change (loop counters are left out)."""
        rng = self.rng
        items = []
        env = list(env)
        mutable = list(mutable)
        returned = False
        if SLICES and depth == 3 and self.index == 0 and rng.random() < (0.85 if EFFECTS else 0.6):
            self.slices += 1
            self.make_slice(env, items)
        params_slices = [(i, t) for i, t in env if i < 100 and t[0] == 'slice']
        if EFFECTS and depth == 3 and params_slices:
            # A callee writes into the caller's slice: a side effect the caller sees.
            view, (_, element, n) = rng.choice(params_slices)
            self.store(env, items, view, element, rng.randrange(n))
        objects = [('struct', k) for k in range(len(TYPES.structs))] + [('enum', k) for k in range(len(TYPES.enums))]
        for _ in range(rng.randint(0, 4 if depth > 0 else 2)):
            kinds = (['let', 'let', 'set', 'if', 'while', 'call', 'struct', 'enum', 'match', 'setField',
                      'slice', 'index', 'index', 'store']
                     if depth > 0 else ['let', 'set', 'struct', 'setField', 'index', 'store'])
            if EFFECTS:
                kinds += (['letEval', 'letEval', 'setEval', 'ifEval', 'whileEval', 'discard', 'setIndexEval', 'setIndexEval',
                           'setFieldEval', 'setFieldEval', 'assert']
                          if depth > 0 else ['letEval', 'setEval', 'discard', 'setIndexEval', 'setIndexEval',
                                             'setFieldEval', 'assert'])
                kinds += ['discard', 'discard'] + (['earlyReturn', 'earlyReturn'] if ret == 'unit' else [])
            kind = rng.choice(kinds)
            slices = [(i, t) for i, t in env if t[0] == 'slice']
            if kind == 'let':
                ty = rng.choice(['i32', 'i32', 'bool'] + list(UINT_BITS) + EXTRA)
                ident = self.new_id()
                items.append(('let', ident, ty, self.expr(ty, 3, env)))
                env.append((ident, ty))
                mutable.append((ident, ty))
            elif kind == 'set' and mutable:
                ident, ty = rng.choice(mutable)
                items.append(('set', ident, self.expr(ty, 3, env)))
            elif kind == 'if':
                then_ = self.block(depth - 1, env, ret, rng.random() < 0.3, mutable)
                else_ = self.block(depth - 1, env, ret, rng.random() < 0.3, mutable)
                items.append(('if', self.expr('bool', 3, env), then_, else_))
                if returns(then_) and returns(else_):
                    returned = True
                    break
            elif kind == 'while':
                counter = self.new_id()
                bound = rng.choice([0, 1, 3, 10, 50])
                body = self.block(depth - 1, env + [(counter, 'i32')], ret, rng.random() < 0.15, mutable)
                step = ('set', counter, ('op', 'plus', '+', ('local', counter), ('int', 1)))
                loop = ('while', ('op', 'less', '<', ('local', counter), ('int', bound)), seq([body, step]))
                items.append(('let', counter, 'i32', ('int', 0)))
                items.append(loop)
                env.append((counter, 'i32'))
            elif kind == 'struct' and TYPES.structs:
                self.make_struct(env, items)
            elif kind == 'setField' and TYPES.structs:
                fields = [(i, j, f) for i, t in env if t[0] == 'struct' for j, f in enumerate(TYPES.structs[t[1]])]
                if not fields:
                    self.make_struct(env, items)
                    continue
                ident, j, f = rng.choice(fields)
                items.append(('setField', ident, j, self.expr(f, 3, env)))
            elif kind == 'enum' and TYPES.enums:
                self.make_enum(env, items)
            elif kind == 'match' and TYPES.enums:
                scrutinees = [(i, t[1]) for i, t in env if t[0] == 'enum']
                if not scrutinees or rng.random() < 0.3:
                    scrutinees = [self.make_enum(env, items)]
                scrutinee, k = rng.choice(scrutinees)
                ty = rng.choice(SCALARS)
                arms = []
                for payload in TYPES.enums[k]:
                    binders = [self.new_id() for _ in payload]
                    arms.append((binders, self.expr(ty, 2, env + list(zip(binders, payload)))))
                ident = self.new_id()
                items.append(('letMatch', ident, ty, scrutinee, k, arms))
                env.append((ident, ty))
                mutable.append((ident, ty))
            elif kind == 'slice' and SLICES and depth == 3 and self.index == 0 and self.slices < 2:
                # Only the entry's top level allocates, so a run allocates a few blocks at most.
                self.slices += 1
                self.make_slice(env, items)
            elif kind == 'index' and slices:
                view, (_, element, n) = rng.choice(slices)
                ident = self.new_id()
                items.append(('letIndex', ident, element, view, rng.randrange(n)))
                env.append((ident, element))
                if element == 'i32':
                    mutable.append((ident, element))
            elif kind == 'store' and slices:
                view, (_, element, n) = rng.choice(slices)
                self.store(env, items, view, element, rng.randrange(n))
            elif kind == 'call':
                later = [k for k in self.callees(None, env) if self.sigs[k][1] != 'unit']
                if not later:
                    continue
                callee = rng.choice(later)
                params, cret = self.sigs[callee]
                args = [self.pure_arg(t, env, items) for t in params]
                ident = self.new_id()
                items.append(('call', ident, cret, callee, args))
                env.append((ident, cret))
                if not is_object(cret):
                    mutable.append((ident, cret))
            elif kind == 'letEval':
                elements = [t[1] for _, t in env if isinstance(t, tuple) and t[0] == 'slice' and is_object(t[1])]
                if elements and rng.random() < 0.3:
                    ty = rng.choice(elements)  # often read from a slice of word structs or enums
                elif objects and rng.random() < 0.3:
                    ty = rng.choice(objects)
                else:
                    ty = rng.choice(['i32', 'i32', 'bool'] + list(UINT_BITS) + EXTRA)
                probe = self.called_bool(2, env, items) if rng.random() < 0.3 else None
                if probe:
                    # let b: bool = c && f(s, ..) < x: a call short circuit may skip.
                    ty = 'bool'
                    name, sym = rng.choice(LOGIC)
                    value = ('eApply', name, sym, self.eff('bool', 1, env, items), probe)
                else:
                    value = self.eff(ty, 3, env, items)
                ident = self.new_id()
                items.append(('letEval', ident, ty, value))
                env.append((ident, ty))
                if not is_object(ty):
                    mutable.append((ident, ty))
            elif kind == 'setEval':
                # Scalars the body may change, and struct and enum locals (not parameters).
                targets = mutable + [(i, t) for i, t in env if is_object(t) and i > 100]
                if not targets:
                    continue
                ident, ty = rng.choice(targets)
                items.append(('setEval', ident, self.eff(ty, 3, env, items)))
            elif kind == 'ifEval':
                then_ = self.block(depth - 1, env, ret, rng.random() < 0.3, mutable)
                else_ = self.block(depth - 1, env, ret, rng.random() < 0.3, mutable)
                items.append(('ifEval', self.eff('bool', 3, env, items), then_, else_))
                if returns(then_) and returns(else_):
                    returned = True
                    break
            elif kind == 'whileEval':
                # counter < bound && c, either way round: bounded whatever c's calls return.
                counter = self.new_id()
                bound = rng.choice([0, 1, 3, 10, 50])
                items.append(('let', counter, 'i32', ('int', 0)))
                env.append((counter, 'i32'))
                body = self.block(depth - 1, env, ret, rng.random() < 0.15, mutable)
                step = ('set', counter, ('op', 'plus', '+', ('local', counter), ('int', 1)))
                guard = ('ePure', ('op', 'less', '<', ('local', counter), ('int', bound)))
                other = self.eff('bool', 2, env, items)
                cond = ('eApply', 'logicalAnd', '&&') + ((guard, other) if rng.random() < 0.5 else (other, guard))
                items.append(('whileEval', cond, seq([body, step])))
            elif kind == 'discard':
                later = self.callees(None, env)
                units = [k for k in later if self.sigs[k][1] == 'unit']
                if later:
                    callee = rng.choice(units if units and rng.random() < 0.6 else later)
                    items.append(('discard', self.eff_call(callee, 3, env, items)))
            elif kind == 'assert':
                items.append(('assert', self.true_cond(env, items)))
            elif kind == 'earlyReturn':
                # if c { return; } in a unit function, the rest of the body skipped when c holds.
                items.append(('ifEval', self.eff('bool', 3, env, items), ('returnUnit',), ('nop',)))
            elif kind == 'setFieldEval':
                fields = [(i, j, f) for i, t in env if isinstance(t, tuple) and t[0] == 'struct'
                          for j, f in enumerate(TYPES.structs[t[1]])]
                if fields:
                    ident, j, f = rng.choice(fields)
                    items.append(('setFieldEval', ident, j, self.eff(f, 3, env, items)))
            elif kind == 'setIndexEval':
                views = [(i, t[1], t[2]) for i, t in env if isinstance(t, tuple) and t[0] == 'slice']
                if views:
                    view, element, n = rng.choice(views)
                    items.append(self.set_index_eval(view, element, n, env, items))
        if must_return and not returned and ret == 'unit':
            items.append(('returnUnit',))
        elif must_return and not returned:
            if is_object(ret) or (EFFECTS and rng.random() < 0.5):
                value = self.eff(ret, 3, env, items)
                if EFFECTS and depth == 3 and self.index == 0:
                    value = ('eApply', 'bitXor', '^', value, ('ePure', self.digest(env, items)))
                items.append(('returnEval', value))
            else:
                value = self.expr(ret, 3, env)
                if EFFECTS and depth == 3 and self.index == 0:
                    value = ('op', 'bitXor', '^', value, self.digest(env, items))
                items.append(('return', value))
        return nest(items)

    def true_cond(self, env, items):
        """A bool that holds whatever its calls do, for assert: the verified
        compiler's image does not trap on a false assert (the theorem is about
        runs that return) while laniusc's does, so a false one cannot be
        compared."""
        rng = self.rng
        pick = rng.random()
        if pick < 0.3:
            c = self.called_bool(2, env, items) or self.eff('bool', 2, env, items)
            return ('eApply', 'logicalOr', '||', c, ('ePure', ('bool', True)))
        if pick < 0.5:
            c = ('ePure', self.expr('bool', 2, env))
            return ('eApply', 'logicalOr', '||', c, ('eNot', c))
        if pick < 0.75:
            # (e & 255) >= 0 or <= 255
            masked = ('eApply', 'bitAnd', '&', self.eff('i32', 3, env, items), ('ePure', ('int', 255)))
            name, sym, bound = rng.choice([('greaterEq', '>=', 0), ('lessEq', '<=', 255)])
            return ('eApply', name, sym, masked, ('ePure', ('int', bound)))
        # (e % 7) < 7 on usize
        seven = ('ePure', ('uint', 'usize', 7))
        return ('eApply', 'less', '<', ('eDivide', 'remainder', '%', self.eff('usize', 3, env, items), seven), seven)

    def digest(self, env, items):
        """An i32 of the elements of the entry's slices, so that what its
        callees wrote into them (and which calls ran) shows in its result,
        and of its isize locals and fields: their low and high 32 bits (the
        high ones by a u64 division) and a signed comparison, so 64-bit
        wraparound and the sign show."""
        def mix(h, x):
            return ('op', 'plus', '+', ('op', 'times', '*', h, ('int', 31)), x)

        def as_i32(e, ty):
            return e if ty == 'i32' else ('cast', 'i32', e) if ty == 'usize' else None
        h = ('int', 0)
        if 'isize' in SCALARS and self.rng.random() < 0.7:
            # Mostly one more isize, computed from the entry's values and calls.
            extra = self.new_id()
            items.append(('letEval', extra, 'isize', self.eff('isize', 3, env, items)))
            env.append((extra, 'isize'))
        isizes = [('local', i) for i, t in env if t == 'isize']
        isizes += [('field', i, j) for i, t in env if t[0] == 'struct'
                   for j, f in enumerate(TYPES.structs[t[1]]) if f == 'isize']
        for x in isizes:
            high = self.new_id()
            items.append(('letEval', high, 'u64', ('eDivide', 'quotient', '/', ('ePure', ('cast', 'u64', x)),
                                                   ('ePure', ('uint', 'u64', 2 ** 32)))))
            env.append((high, 'u64'))
            h = mix(mix(h, ('cast', 'i32', x)), ('cast', 'i32', ('local', high)))
            # Its signed order against a literal: 1 when x < k (or <=, >, >=).
            name, sym = self.rng.choice(ORDER)
            flag = self.new_id()
            items.append(('let', flag, 'i32', ('int', 0)))
            items.append(('if', ('op', name, sym, x, ('uint', 'isize', self.lit_isize())),
                          ('set', flag, ('int', 1)), ('nop',)))
            env.append((flag, 'i32'))
            h = mix(h, ('local', flag))
        for view, t in list(env):
            if t[0] != 'slice':
                continue
            for i in range(t[2]):
                element, ident = t[1], self.new_id()
                items.append(('letIndex', ident, element, view, i))
                env.append((ident, element))
                if element == 'i32':
                    parts = [('local', ident)]
                elif element[0] == 'struct':
                    parts = [as_i32(('field', ident, j), f) for j, f in enumerate(TYPES.structs[element[1]])]
                else:
                    arms = []
                    for v, payload in enumerate(TYPES.enums[element[1]]):
                        binders = [self.new_id() for _ in payload]
                        value = ('int', v + 1)
                        for b, f in zip(binders, payload):
                            x = as_i32(('local', b), f)
                            value = mix(value, x) if x else value
                        arms.append((binders, value))
                    m = self.new_id()
                    items.append(('letMatch', m, 'i32', ident, element[1], arms))
                    env.append((m, 'i32'))
                    parts = [('local', m)]
                for x in parts:
                    h = mix(h, x) if x else h
        return h


def element_words(t):
    if t[0] == 'struct':
        return len(TYPES.structs[t[1]])
    return 1 + max(len(v) for v in TYPES.enums[t[1]])


def returns(s):
    kind = s[0]
    if kind in LETS:
        return returns(s[-1])
    if kind == 'then':
        return returns(s[1]) or returns(s[2])
    if kind in ('if', 'ifEval'):
        return returns(s[2]) and returns(s[3])
    return kind in ('return', 'returnEval', 'returnUnit')


def seq(stmts):
    stmts = [s for s in stmts if s != ('nop',)]
    if not stmts:
        return ('nop',)
    out = stmts[-1]
    for s in reversed(stmts[:-1]):
        out = ('then', s, out)
    return out


def nest(items):
    """Lets scope over the rest of the list, as Core's letLocal does."""
    if not items:
        return ('nop',)
    head, rest = items[0], items[1:]
    if head[0] in LETS:
        return head + (nest(rest),)
    if not rest:
        return head
    return ('then', head, nest(rest))


def gen_program(rng):
    global TYPES
    # Half the types have only word fields, so slices of them are possible.
    pools = lambda: WORDS if rng.random() < 0.5 else SCALARS
    structs = [[rng.choice(pool) for _ in range(rng.randint(1, 3))]
               for pool in [pools() for _ in range(rng.randint(0, 2))]]
    enums = [[[rng.choice(pool) for _ in range(rng.randint(0, 2))] for _ in range(rng.randint(1, 3))]
             for pool in [pools() for _ in range(rng.randint(0, 2))]]
    TYPES = Program([], structs, enums)
    count = rng.randint(2, 4) if EFFECTS else rng.randint(1, 4)
    objects = [('struct', k) for k in range(len(structs))] + [('enum', k) for k in range(len(enums))]
    sigs = []
    shared = rng.choice(slice_elements()) if EFFECTS else None  # most slice parameters' element type
    for k in range(count):
        params = ['i32'] + [rng.choice(SCALARS) for _ in range(rng.randint(0, 2))]
        ret = 'i32' if k == 0 else rng.choice(SCALARS)
        if EFFECTS and k > 0:
            # The entry's parameters stay scalars the harness passes in registers.
            if objects and rng.random() < 0.4:
                params.insert(rng.randint(1, len(params)), rng.choice(objects))
            if objects and rng.random() < 0.3:
                ret = rng.choice(objects)
            if rng.random() < 0.25:
                ret = 'unit'
            if rng.random() < (0.6 if ret == 'unit' else 0.35):
                # Unit functions mostly work through a slice they are passed.
                element = shared if rng.random() < 0.75 else rng.choice(slice_elements())
                params.insert(rng.randint(1, len(params)), ('slice', element, rng.randint(1, 3)))
        sigs.append((params, ret))
    funcs = []
    for k, (params, ret) in enumerate(sigs):
        g = Gen(rng, sigs, k)
        env = [(j, t) for j, t in enumerate(params)]
        # A unit function may end without a return.
        body = g.block(3, env, ret, ret != 'unit' or rng.random() < 0.5, [])
        funcs.append((params, ret, body))
    return Program(funcs, structs, enums)


def gen_args(rng, params):
    out = []
    for t in params:
        if t == 'i32':
            out.append(rng.choice(I32_EDGES) if rng.random() < 0.5 else rng.randint(-2 ** 31, 2 ** 31 - 1))
        elif t == 'bool':
            out.append(int(rng.random() < 0.5))
        elif t == 'isize':
            out.append(rng.choice(ISIZE_EDGES) if rng.random() < 0.5 else rng.randint(-2 ** 63, 2 ** 63 - 1))
        else:
            out.append(rng.randrange(1 << UINT_BITS[t]))
    return out


# ---------------------------------------------------------------- reference interpreter
# Core's meaning of the generated programs, to tell which compiler is wrong.

class Returned(Exception):
    def __init__(self, value):
        self.value = value


def wrap_to(ty, x):
    if ty == 'i32':
        return i32(x)
    if ty == 'bool':
        return x
    if ty == 'isize':
        # Two's complement at 64 bits: the bits of an unsigned value, an
        # i32 sign-extended.
        x &= (1 << 64) - 1
        return x - (1 << 64) if x >> 63 else x
    return x & ((1 << UINT_BITS[ty]) - 1)


def ty_of(e, env):
    kind = e[0]
    if kind == 'int':
        return 'i32'
    if kind == 'neg':
        return ty_of(e[1], env)
    if kind in ('bool', 'not'):
        return 'bool'
    if kind == 'uint' or kind == 'cast':
        return e[1]
    if kind == 'local':
        return env[e[1]][1]
    if kind == 'field':
        return TYPES.structs[env[e[1]][1][1]][e[2]]
    if e[1] in ('plus', 'minus', 'times', 'bitAnd', 'bitOr', 'bitXor'):
        return ty_of(e[3], env)
    return 'bool'


def ev(e, env):
    kind = e[0]
    if kind in ('int', 'bool'):
        return e[1]
    if kind == 'uint':
        return e[2]
    if kind == 'local':
        return env[e[1]][0]
    if kind == 'field':
        return env[e[1]][0][e[2]]
    if kind == 'neg':
        return wrap_to(ty_of(e[1], env), -ev(e[1], env))
    if kind == 'not':
        return not ev(e[1], env)
    if kind == 'cast':
        return wrap_to(e[1], ev(e[2], env))
    return apply_op(e[1], ev(e[3], env), ev(e[4], env), ty_of(e[3], env))


def apply_op(name, l, r, ty):
    """A binary operator on its operands' values, ty the left operand's type."""
    if name in ARITH_NAMES:
        x = {'plus': l + r, 'minus': l - r, 'times': l * r, 'bitAnd': l & r, 'bitOr': l | r, 'bitXor': l ^ r}[name]
        return wrap_to(ty, x)
    return {'less': l < r, 'lessEq': l <= r, 'greater': l > r, 'greaterEq': l >= r, 'equal': l == r,
            'notEqual': l != r, 'logicalAnd': l and r, 'logicalOr': l or r}[name]


def eff_ty(e, env):
    kind = e[0]
    if kind == 'ePure':
        return ty_of(e[1], env)
    if kind == 'eCall':
        return TYPES[e[1]][1]
    if kind == 'eApply':
        return eff_ty(e[3], env) if e[1] in ARITH_NAMES else 'bool'
    if kind == 'eDivide':
        return eff_ty(e[3], env)
    if kind in ('eStruct', 'eVariant'):
        return e[1]
    if kind == 'eIndex':
        return env[e[1]][1][1]
    if kind == 'eStride':
        return 'isize'
    if kind == 'eMatch':
        return e[3]
    if kind == 'eNeg':
        return eff_ty(e[1], env)
    if kind == 'eNot':
        return 'bool'
    return e[1]


def stride_of(element):
    """slice_stride of a raw view: i32 elements run forward 4 bytes; word
    structs and enums run down 8 bytes a word."""
    if element == 'i32':
        return 4
    if element[0] == 'struct':
        return -8 * len(TYPES.structs[element[1]])
    return -8 * (1 + max(len(p) for p in TYPES.enums[element[1]]))


def ev_eff(e, env, funcs):
    """Core's order: left before right, arguments left to right, and the
    right side of && and || only when the left does not decide."""
    kind = e[0]
    if kind == 'ePure':
        return copy_as(ev(e[1], env), ty_of(e[1], env))
    if kind == 'eCall':
        return call(funcs, e[1], [ev_eff(a, env, funcs) for a in e[2]])
    if kind == 'eNeg':
        return wrap_to(eff_ty(e[1], env), -ev_eff(e[1], env, funcs))
    if kind == 'eNot':
        return not ev_eff(e[1], env, funcs)
    if kind == 'eCast':
        return wrap_to(e[1], ev_eff(e[2], env, funcs))
    if kind == 'eMatch':
        # Binders are fresh ids, so binding them leaves the outer locals alone.
        variant, payload = ev_eff(e[1], env, funcs)
        for b, v, t in zip(e[4][variant], payload, TYPES.enums[e[2][1]][variant]):
            env[b] = [v, t]
        return ev_eff(e[5][variant], env, funcs)
    if kind == 'eStride':
        return stride_of(env[e[1]][1][1])
    if kind == 'eIndex':
        k, elements = ev_eff(e[2], env, funcs), env[e[1]][0]
        if not 0 <= k < len(elements):
            raise SystemExit('a generated index is out of bounds')
        return copy(elements[k])
    if kind == 'eStruct':
        return [ev_eff(f, env, funcs) for f in e[2]]
    if kind == 'eVariant':
        return (e[2], [ev_eff(f, env, funcs) for f in e[3]])
    name = e[1]
    l = ev_eff(e[3], env, funcs)
    if kind == 'eDivide':
        r = ev_eff(e[4], env, funcs)
        if r == 0 or (eff_ty(e[3], env) == 'i32' and l == -2 ** 31 and r == -1):
            raise SystemExit('a generated division traps')
        # Core truncates toward zero; the remainder takes the dividend's sign.
        q = abs(l) // abs(r) * (1 if (l < 0) == (r < 0) else -1)
        return wrap_to(eff_ty(e[3], env), q if name == 'quotient' else l - r * q)
    if name == 'logicalAnd':
        return bool(l) and bool(ev_eff(e[4], env, funcs))
    if name == 'logicalOr':
        return bool(l) or bool(ev_eff(e[4], env, funcs))
    return apply_op(name, l, ev_eff(e[4], env, funcs), eff_ty(e[3], env))


def copy(v):
    if isinstance(v, list):
        return list(v)
    if isinstance(v, tuple):
        return (v[0], list(v[1]))
    return v


def copy_as(v, ty):
    """Struct and enum values are copied; a slice is a view of the heap."""
    return copy(v) if is_object(ty) else v


def run_stmt(s, env, funcs):
    kind = s[0]
    if kind == 'let':
        env[s[1]] = [ev(s[3], env), s[2]]
        run_stmt(s[4], env, funcs)
    elif kind == 'call':
        env[s[1]] = [call(funcs, s[3], [ev(a, env) for a in s[4]]), s[2]]
        run_stmt(s[5], env, funcs)
    elif kind == 'letEval':
        env[s[1]] = [ev_eff(s[3], env, funcs), s[2]]
        run_stmt(s[4], env, funcs)
    elif kind == 'setEval':
        env[s[1]][0] = ev_eff(s[2], env, funcs)
    elif kind == 'ifEval':
        run_stmt(s[2] if ev_eff(s[1], env, funcs) else s[3], env, funcs)
    elif kind == 'whileEval':
        while ev_eff(s[1], env, funcs):
            run_stmt(s[2], env, funcs)
    elif kind == 'returnEval':
        raise Returned(ev_eff(s[1], env, funcs))
    elif kind == 'discard':
        ev_eff(s[1], env, funcs)
    elif kind == 'assert':
        if not ev_eff(s[1], env, funcs):
            raise SystemExit('a generated assert fails')
    elif kind == 'returnUnit':
        raise Returned(None)
    elif kind == 'setFieldEval':
        # A callee cannot reach the caller's locals, so the value cannot move the struct.
        value = ev_eff(s[3], env, funcs)
        env[s[1]][0][s[2]] = value
    elif kind == 'setIndexEval':
        # Core's order: the index, then the value, then the store.
        k, elements = ev_eff(s[2], env, funcs), env[s[1]][0]
        if not 0 <= k < len(elements):
            raise SystemExit('a generated index is out of bounds')
        elements[k] = copy(ev_eff(s[3], env, funcs))
    elif kind == 'letStruct':
        env[s[1]] = [[ev(f, env) for f in s[3]], s[2]]
        run_stmt(s[4], env, funcs)
    elif kind == 'letEnum':
        env[s[1]] = [(s[3], [ev(f, env) for f in s[4]]), s[2]]
        run_stmt(s[5], env, funcs)
    elif kind == 'letMatch':
        variant, payload = env[s[3]][0]
        binders, value = s[5][variant]
        for b, v, ty in zip(binders, payload, TYPES.enums[s[4]][variant]):
            env[b] = [v, ty]
        env[s[1]] = [ev(value, env), s[2]]
        run_stmt(s[6], env, funcs)
    elif kind == 'letAlloc':
        env[s[1]] = [None, 'ptr']
        run_stmt(s[4], env, funcs)
    elif kind == 'letSlice':
        env[s[1]] = [[None] * s[4], ('slice', s[2], s[4])]
        run_stmt(s[5], env, funcs)
    elif kind == 'letIndex':
        env[s[1]] = [copy(env[s[3]][0][s[4]]), s[2]]
        run_stmt(s[5], env, funcs)
    elif kind == 'setIndex':
        env[s[1]][0][s[2]] = copy(ev(s[3], env))
    elif kind == 'set':
        env[s[1]][0] = ev(s[2], env)
    elif kind == 'setField':
        env[s[1]][0][s[2]] = ev(s[3], env)
    elif kind == 'then':
        run_stmt(s[1], env, funcs)
        run_stmt(s[2], env, funcs)
    elif kind == 'if':
        run_stmt(s[2] if ev(s[1], env) else s[3], env, funcs)
    elif kind == 'while':
        while ev(s[1], env):
            run_stmt(s[2], env, funcs)
    elif kind == 'return':
        raise Returned(ev(s[1], env))


def call(funcs, index, args):
    """Function index on its argument values; struct and enum arguments are
    copies, a slice argument shares its elements with the caller."""
    params, ret, body = funcs[index]
    env = {j: [bool(a) if t == 'bool' else copy_as(a, t), t] for j, (a, t) in enumerate(zip(args, params))}
    try:
        run_stmt(body, env, funcs)
    except Returned as r:
        return r.value
    if ret == 'unit':
        return None
    raise SystemExit('a generated function fell off its end')


def interpret(funcs, index, args):
    global TYPES
    TYPES = funcs
    value = call(funcs, index, args)
    return int(value) if funcs[index][1] == 'bool' else value


# ---------------------------------------------------------------- Lean side

def lean_ty(t):
    if t in UINT_BITS:
        return f'(.uint {UINT_LEAN[t]})'
    if t[0] == 'struct':
        return f'(.struct {t[1]} [{", ".join(lean_ty(f) for f in TYPES.structs[t[1]])}])'
    if t[0] == 'enum':
        variants = ', '.join('[' + ', '.join(lean_ty(f) for f in v) + ']' for v in TYPES.enums[t[1]])
        return f'(.enum {len(TYPES.structs) + t[1]} [{variants}])'
    if t[0] == 'slice':
        return f'(.slice {lean_ty(t[1])})'
    return '.' + t


def lean_list(es):
    return '[' + ', '.join(lean_expr(e) for e in es) + ']'


def lean_expr(e):
    kind = e[0]
    if kind == 'int':
        return f'(.int (BitVec.ofInt 32 ({e[1]})))'
    if kind == 'bool':
        return '(.boolean true)' if e[1] else '(.boolean false)'
    if kind == 'uint' and e[1] == 'isize':
        # isize has no literal: an i32 literal cast (sign-extended), or the
        # bits of a u64 one.
        k = e[2]
        if -2 ** 31 <= k < 2 ** 31:
            return f'(.cast .isize {lean_expr(("int", k))})'
        return f'(.cast .isize (.unsigned .uint64 {k & (2 ** 64 - 1)}))'
    if kind == 'uint':
        return f'(.unsigned {UINT_LEAN[e[1]]} {e[2]})'
    if kind == 'cast':
        return f'(.cast {lean_ty(e[1])} {lean_expr(e[2])})'
    if kind == 'local':
        return f'(.local {e[1]})'
    if kind == 'field':
        return f'(.field {e[1]} {e[2]})'
    if kind == 'neg':
        return f'(.negate {lean_expr(e[1])})'
    if kind == 'not':
        return f'(.not {lean_expr(e[1])})'
    return f'(.apply .{e[1]} {lean_expr(e[3])} {lean_expr(e[4])})'


def lean_eff(e):
    kind = e[0]
    if kind == 'ePure':
        return f'(.ePure {lean_expr(e[1])})'
    if kind == 'eCall':
        return f'(.eCall {e[1]} [{", ".join(lean_eff(a) for a in e[2])}])'
    if kind == 'eNeg':
        return f'(.eNeg {lean_eff(e[1])})'
    if kind == 'eNot':
        return f'(.eNot {lean_eff(e[1])})'
    if kind == 'eCast':
        return f'(.eCast {lean_ty(e[1])} {lean_eff(e[2])})'
    if kind == 'eDivide':
        return f'(.eDivide .{e[1]} {lean_eff(e[3])} {lean_eff(e[4])})'
    if kind == 'eIndex':
        return f'(.eIndex {e[1]} {lean_eff(e[2])})'
    if kind == 'eStride':
        return f'(.eStride {e[1]})'
    if kind == 'eMatch':
        return (f'(.eMatch {lean_eff(e[1])} {lean_ty(e[2])} {lean_ty(e[3])} {e[4]} '
                f'[{", ".join(lean_eff(v) for v in e[5])}])')
    if kind == 'eStruct':
        return f'(.eStruct {lean_ty(e[1])} [{", ".join(lean_eff(f) for f in e[2])}])'
    if kind == 'eVariant':
        return f'(.eVariant {lean_ty(e[1])} {e[2]} [{", ".join(lean_eff(f) for f in e[3])}])'
    return f'(.eApply .{e[1]} {lean_eff(e[3])} {lean_eff(e[4])})'


def lean_stmt(s):
    kind = s[0]
    if kind == 'nop':
        return '.nop'
    if kind == 'letEval':
        return f'(.letEval {s[1]} {lean_ty(s[2])} {lean_eff(s[3])} {lean_stmt(s[4])})'
    if kind == 'setEval':
        return f'(.setEval {s[1]} {lean_eff(s[2])})'
    if kind == 'ifEval':
        return f'(.ifEval {lean_eff(s[1])} {lean_stmt(s[2])} {lean_stmt(s[3])})'
    if kind == 'whileEval':
        return f'(.whileEval {lean_eff(s[1])} {lean_stmt(s[2])})'
    if kind == 'returnEval':
        return f'(.returnEval {lean_eff(s[1])})'
    if kind == 'discard':
        return f'(.discard {lean_eff(s[1])})'
    if kind == 'setIndexEval':
        return f'(.setIndexEval {s[1]} {lean_eff(s[2])} {lean_eff(s[3])})'
    if kind == 'setFieldEval':
        return f'(.setFieldEval {s[1]} {s[2]} {lean_eff(s[3])})'
    if kind == 'assert':
        return f'(.assert {lean_eff(s[1])})'
    if kind == 'returnUnit':
        return '.returnUnit'
    if kind == 'let':
        return f'(.let {s[1]} {lean_ty(s[2])} {lean_expr(s[3])} {lean_stmt(s[4])})'
    if kind == 'call':
        args = ', '.join(lean_expr(a) for a in s[4])
        return f'(.letCall {s[1]} {lean_ty(s[2])} {s[3]} [{args}] {lean_stmt(s[5])})'
    if kind == 'letStruct':
        return f'(.letStruct {s[1]} {lean_ty(s[2])} {lean_list(s[3])} {lean_stmt(s[4])})'
    if kind == 'letEnum':
        return f'(.letEnum {s[1]} {lean_ty(s[2])} {s[3]} {lean_list(s[4])} {lean_stmt(s[5])})'
    if kind == 'letMatch':
        arms = ', '.join(f'{{ binders := {b}, value := {lean_expr(v)} }}' for b, v in s[5])
        return (f'(.letMatch {s[1]} {lean_ty(s[2])} {s[3]} {len(TYPES.structs) + s[4]} [{arms}] '
                f'{lean_stmt(s[6])})')
    if kind == 'letAlloc':
        return f'(.letAlloc {s[1]} (.unsigned .usize {s[2]}) {s[3]} {lean_stmt(s[4])})'
    if kind == 'letSlice':
        return f'(.letSlice {s[1]} {lean_ty(s[2])} {lean_expr(s[3])} {lean_expr(("int", s[4]))} {lean_stmt(s[5])})'
    if kind == 'letIndex':
        return f'(.letIndex {s[1]} {lean_ty(s[2])} {s[3]} {lean_expr(("int", s[4]))} {lean_stmt(s[5])})'
    if kind == 'setIndex':
        return f'(.setIndex {s[1]} {lean_expr(("int", s[2]))} {lean_expr(s[3])})'
    if kind == 'set':
        return f'(.set {s[1]} {lean_expr(s[2])})'
    if kind == 'setField':
        return f'(.setField {s[1]} {s[2]} {lean_expr(s[3])})'
    if kind == 'then':
        return f'(.then {lean_stmt(s[1])} {lean_stmt(s[2])})'
    if kind == 'if':
        return f'(.if {lean_expr(s[1])} {lean_stmt(s[2])} {lean_stmt(s[3])})'
    if kind == 'while':
        return f'(.while {lean_expr(s[1])} {lean_stmt(s[2])})'
    return f'(.return {lean_expr(s[1])})'


def lean_program(funcs):
    global TYPES
    TYPES = funcs
    out = []
    for params, ret, body in funcs:
        ps = ', '.join(f'{{ id := {j}, ty := {lean_ty(t)} }}' for j, t in enumerate(params))
        out.append(f'{{ params := [{ps}], ret := {lean_ty(ret)}, body := {lean_stmt(body)} }}')
    return '{ funcs := [' + ', '.join(out) + '] }'


LEAN_HEAD = '''import Lanius.Mini.Compiler
open Lanius.Mini

def render : Option Binary → String
  | none => "none"
  | some b => s!"{b.entries} {b.image.map (·.toNat)}"
'''


def lean_file(programs):
    out = [LEAN_HEAD]
    for k, funcs in enumerate(programs):
        out.append(f'def p{k} : SrcProgram := {lean_program(funcs)}')
        out.append(f'#eval IO.println (render (compileSource p{k}))')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- Lanius side

def lani_ty(t):
    if t[0] == 'struct':
        return f'{TYPES.name}S{t[1]}'
    if t[0] == 'enum':
        return f'{TYPES.name}E{t[1]}'
    if t[0] == 'slice':
        return f'[{lani_ty(t[1])}]'
    return t


def lani_decls():
    out = []
    for k, fields in enumerate(TYPES.structs):
        out.append(f'struct {TYPES.name}S{k} {{ ' + ', '.join(f'f{j}: {lani_ty(f)}' for j, f in enumerate(fields)) + ' }')
    for k, variants in enumerate(TYPES.enums):
        out.append(f'enum {TYPES.name}E{k} {{')
        for v, payload in enumerate(variants):
            inner = '(' + ', '.join(lani_ty(f) for f in payload) + ')' if payload else ''
            out.append(f'    {TYPES.name}E{k}V{v}{inner},')
        out.append('}')
    return out


def lani_variant(k, v, values):
    inner = '(' + ', '.join(values) + ')' if values else ''
    return f'{TYPES.name}E{k}V{v}{inner}'


def lani_expr(e):
    kind = e[0]
    if kind == 'int':
        k = e[1]
        if k == -2 ** 31:
            return '(-2147483647 - 1)'
        return f'({k})' if k < 0 else str(k)
    if kind == 'bool':
        return 'true' if e[1] else 'false'
    if kind == 'uint' and e[1] == 'isize':
        k = e[2]
        if -2 ** 31 <= k < 2 ** 31:
            return f'({lani_expr(("int", k))} as isize)'
        return f'({lani_expr(("uint", "u64", k & (2 ** 64 - 1)))} as isize)'
    if kind == 'uint':
        # laniusc literals are i32, so build the value from 16-bit pieces.
        ty, k = e[1], e[2]
        if k < 65536:
            return f'({k} as {ty})'
        parts = [f'(({(k >> s) & 65535} as {ty}) << {s})' for s in range(UINT_BITS[ty] - 16, 0, -16)]
        return '(' + ' | '.join(parts + [f'({k & 65535} as {ty})']) + ')'
    if kind == 'cast':
        return f'({lani_expr(e[2])} as {e[1]})'
    if kind == 'local':
        return f'v{e[1]}'
    if kind == 'field':
        return f'v{e[1]}.f{e[2]}'
    if kind == 'neg':
        return f'(-{lani_expr(e[1])})'
    if kind == 'not':
        return f'(!{lani_expr(e[1])})'
    l, r = lani_expr(e[3]), lani_expr(e[4])
    # A small isize literal beside an operand whose type laniusc knows is
    # written bare, as `x + 5`, so laniusc infers its type.
    if bare_isize(e[3]) and typed_isize(e[4]):
        l = lani_expr(('int', e[3][2]))
    elif bare_isize(e[4]) and typed_isize(e[3]):
        r = lani_expr(('int', e[4][2]))
    return f'({l} {e[2]} {r})'


def bare_isize(e):
    return e[0] == 'uint' and e[1] == 'isize' and abs(e[2]) < 2 ** 31 - 1


def typed_isize(e):
    """e prints with a type laniusc reads off it (a local, field or cast in it)."""
    if e[0] in ('local', 'field', 'cast'):
        return True
    if e[0] == 'neg':
        return typed_isize(e[1])
    return e[0] == 'op' and e[1] in ARITH_NAMES and (typed_isize(e[3]) or typed_isize(e[4]))


def lani_eff(e, prefix):
    kind = e[0]
    if kind == 'ePure':
        return lani_expr(e[1])
    if kind == 'eCall':
        return f'{prefix}f{e[1]}({", ".join(lani_eff(a, prefix) for a in e[2])})'
    if kind == 'eNeg':
        return f'(-{lani_eff(e[1], prefix)})'
    if kind == 'eNot':
        return f'(!{lani_eff(e[1], prefix)})'
    if kind == 'eCast':
        return f'({lani_eff(e[2], prefix)} as {e[1]})'
    if kind == 'eIndex':
        return f'v{e[1]}[{lani_eff(e[2], prefix)}]'
    if kind == 'eStride':
        return f'slice_stride(v{e[1]})'
    if kind == 'eMatch':
        arms = ' '.join(f'{lani_variant(e[2][1], v, [f"v{b}" for b in names])} -> {lani_eff(value, prefix)},'
                        for v, (names, value) in enumerate(zip(e[4], e[5])))
        return f'(match ({lani_eff(e[1], prefix)}) {{ {arms} }})'
    if kind == 'eStruct':
        fields = ', '.join(f'f{j}: {lani_eff(f, prefix)}' for j, f in enumerate(e[2]))
        return f'{lani_ty(e[1])} {{ {fields} }}'
    if kind == 'eVariant':
        return lani_variant(e[1][1], e[2], [lani_eff(f, prefix) for f in e[3]])
    return f'({lani_eff(e[3], prefix)} {e[2]} {lani_eff(e[4], prefix)})'


def lani_stmt(s, prefix, indent):
    pad = '    ' * indent
    kind = s[0]
    if kind == 'nop':
        return []
    if kind == 'letEval':
        return [f'{pad}let v{s[1]}: {lani_ty(s[2])} = {lani_eff(s[3], prefix)};'] + lani_stmt(s[4], prefix, indent)
    if kind == 'setEval':
        return [f'{pad}v{s[1]} = {lani_eff(s[2], prefix)};']
    if kind == 'ifEval':
        return ([f'{pad}if ({lani_eff(s[1], prefix)}) {{'] + lani_stmt(s[2], prefix, indent + 1) + [f'{pad}}} else {{'] +
                lani_stmt(s[3], prefix, indent + 1) + [f'{pad}}}'])
    if kind == 'whileEval':
        return [f'{pad}while ({lani_eff(s[1], prefix)}) {{'] + lani_stmt(s[2], prefix, indent + 1) + [f'{pad}}}']
    if kind == 'returnEval':
        return [f'{pad}return {lani_eff(s[1], prefix)};']
    if kind == 'discard':
        return [f'{pad}{lani_eff(s[1], prefix)};']
    if kind == 'setIndexEval':
        return [f'{pad}v{s[1]}[{lani_eff(s[2], prefix)}] = {lani_eff(s[3], prefix)};']
    if kind == 'setFieldEval':
        return [f'{pad}v{s[1]}.f{s[2]} = {lani_eff(s[3], prefix)};']
    if kind == 'assert':
        return [f'{pad}assert({lani_eff(s[1], prefix)});']
    if kind == 'returnUnit':
        return [f'{pad}return;']
    if kind == 'let':
        return [f'{pad}let v{s[1]}: {lani_ty(s[2])} = {lani_expr(s[3])};'] + lani_stmt(s[4], prefix, indent)
    if kind == 'call':
        args = ', '.join(lani_expr(a) for a in s[4])
        return [f'{pad}let v{s[1]}: {lani_ty(s[2])} = {prefix}f{s[3]}({args});'] + lani_stmt(s[5], prefix, indent)
    if kind == 'letStruct':
        fields = ', '.join(f'f{j}: {lani_expr(f)}' for j, f in enumerate(s[3]))
        return ([f'{pad}let v{s[1]}: {lani_ty(s[2])} = {lani_ty(s[2])} {{ {fields} }};'] +
                lani_stmt(s[4], prefix, indent))
    if kind == 'letEnum':
        value = lani_variant(s[2][1], s[3], [lani_expr(f) for f in s[4]])
        return [f'{pad}let v{s[1]}: {lani_ty(s[2])} = {value};'] + lani_stmt(s[5], prefix, indent)
    if kind == 'letMatch':
        out = [f'{pad}let v{s[1]}: {lani_ty(s[2])} = match (v{s[3]}) {{']
        for v, (binders, value) in enumerate(s[5]):
            out.append(f'{pad}    {lani_variant(s[4], v, [f"v{b}" for b in binders])} -> {lani_expr(value)},')
        return out + [f'{pad}}};'] + lani_stmt(s[6], prefix, indent)
    if kind == 'letAlloc':
        size, align = lani_expr(('uint', 'usize', s[2])), lani_expr(('uint', 'usize', 1 << s[3]))
        return [f'{pad}let v{s[1]}: ptr = alloc::allocator::alloc({size}, {align});'] + lani_stmt(s[4], prefix, indent)
    if kind == 'letSlice':
        return ([f'{pad}let v{s[1]}: {lani_ty(("slice", s[2], s[4]))} = slice_from_raw_parts({lani_expr(s[3])}, {s[4]});'] +
                lani_stmt(s[5], prefix, indent))
    if kind == 'letIndex':
        return [f'{pad}let v{s[1]}: {lani_ty(s[2])} = v{s[3]}[{s[4]}];'] + lani_stmt(s[5], prefix, indent)
    if kind == 'setIndex':
        return [f'{pad}v{s[1]}[{s[2]}] = {lani_expr(s[3])};']
    if kind == 'set':
        return [f'{pad}v{s[1]} = {lani_expr(s[2])};']
    if kind == 'setField':
        return [f'{pad}v{s[1]}.f{s[2]} = {lani_expr(s[3])};']
    if kind == 'then':
        return lani_stmt(s[1], prefix, indent) + lani_stmt(s[2], prefix, indent)
    if kind == 'if':
        return ([f'{pad}if ({lani_expr(s[1])}) {{'] + lani_stmt(s[2], prefix, indent + 1) + [f'{pad}}} else {{'] +
                lani_stmt(s[3], prefix, indent + 1) + [f'{pad}}}'])
    if kind == 'while':
        return [f'{pad}while ({lani_expr(s[1])}) {{'] + lani_stmt(s[2], prefix, indent + 1) + [f'{pad}}}']
    return [f'{pad}return {lani_expr(s[1])};']


LANI_HEAD = '''module app::main;
import alloc::allocator;
import core::mem;
import std::io_byte;

fn put(value: i32) -> i32 {
    let written: bool = std::io_byte::write_stdout_byte(value);
    return 0;
}

// An i32 as 4 bytes, little-endian.
fn put32(value: i32) -> i32 {
    let bits: i32 = value;
    let sign: i32 = 0;
    if (bits < 0) {
        bits = bits & 2147483647;
        sign = 128;
    }
    put(bits % 256);
    put((bits / 256) % 256);
    put((bits / 65536) % 256);
    put(bits / 16777216 + sign);
    return 0;
}
'''


def lani_arg(value, ty):
    if ty == 'i32':
        return lani_expr(('int', value))
    if ty == 'bool':
        return 'true' if value else 'false'
    return lani_expr(('uint', ty, value))


def lani_file(programs, calls):
    out = [LANI_HEAD]
    global TYPES
    for k, funcs in enumerate(programs):
        TYPES = funcs
        TYPES.name = f'P{k}'
        out += lani_decls()
        for j, (params, ret, body) in enumerate(funcs):
            ps = ', '.join(f'v{i}: {lani_ty(t)}' for i, t in enumerate(params))
            arrow = '' if ret == 'unit' else f' -> {lani_ty(ret)}'
            out.append(f'fn p{k}_f{j}({ps}){arrow} {{')
            out += lani_stmt(body, f'p{k}_', 1)
            out.append('}\n')
    out.append('fn main() -> i32 {')
    for k, funcs in enumerate(programs):
        params = funcs[0][0]
        for args in calls[k]:
            rendered = ', '.join(lani_arg(a, t) for a, t in zip(args, params))
            out.append(f'    put32(p{k}_f0({rendered}));')
    out.append('    return 0;\n}')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- native side

ARG_REGS = [0x7C, 0x74, 0x54]  # rdi, rsi, rdx as the reg field of mov [rsp+disp8], r64


class Native:
    """The verified compiler's image in executable memory. A stub saves r12-r14,
    points r12 at a heap, sets the cursor r13 to 1 (the top theorem's premise)
    and the limit r14, stores the SysV arguments where the mini calling
    convention expects them (below the return address) and calls."""

    HEAP = 1 << 16

    def __init__(self):
        self.code = mmap.mmap(-1, 1 << 22, prot=mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
        self.base = ctypes.addressof(ctypes.c_char.from_buffer(self.code))
        self.heap = mmap.mmap(-1, self.HEAP, prot=mmap.PROT_READ | mmap.PROT_WRITE)
        self.heap_base = ctypes.addressof(ctypes.c_char.from_buffer(self.heap))

    def load(self, entries, image, arity):
        self.code[0:len(image)] = image
        at = len(image)
        stub = bytes([0x41, 0x54, 0x41, 0x55, 0x41, 0x56])
        stub += bytes([0x49, 0xBC]) + self.heap_base.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBD]) + (1).to_bytes(8, 'little')
        stub += bytes([0x49, 0xBE]) + (self.HEAP - 64).to_bytes(8, 'little')
        for k, reg in zip(range(arity), ARG_REGS):
            stub += bytes([0x48, 0x89, reg, 0x24, (256 - (8 * k + 24)) & 0xff])
        rel = entries[0] - (at + len(stub) + 5)
        stub += b'\xe8' + (rel & 0xffffffff).to_bytes(4, 'little')
        stub += bytes([0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0xC3])
        self.code[at:at + len(stub)] = stub
        self.fn = ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * arity))(self.base + at)

    def call(self, args, params=()):
        # An i32 sits zero-extended in its slot, an unsigned value as itself,
        # an isize as its 64 bits.
        self.heap[0:self.HEAP] = bytes(self.HEAP)
        return i32(self.fn(*[a & (2 ** 64 - 1) if t == 'isize' else a & 0xffffffff if a < 0 else a
                             for a, t in zip(args, list(params) + [None] * len(args))]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=100)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--calls', type=int, default=8)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--chunk', type=int, default=25)
    parser.add_argument('--only', help='comma-separated program indices to keep, for reproducing one')
    args = parser.parse_args()
    enable_isize()
    rng = random.Random(args.seed)
    programs = [gen_program(rng) for _ in range(args.count)]
    calls = [[gen_args(rng, funcs[0][0]) for _ in range(args.calls)] for funcs in programs]
    if args.only:
        keep = [int(k) for k in args.only.split(',')]
        programs = [programs[k] for k in keep]
        calls = [calls[k] for k in keep]
    os.makedirs(args.workdir, exist_ok=True)

    lean_path = os.path.abspath(os.path.join(args.workdir, 'programs.lean'))
    open(lean_path, 'w').write(lean_file(programs))
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    lean = subprocess.run(['lake', 'env', 'lean', lean_path], cwd='formal', env=env, capture_output=True, text=True)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    lines = lean.stdout.strip().split('\n')
    if len(lines) != len(programs):
        raise SystemExit(f'lean printed {len(lines)} lines for {len(programs)} programs')
    native = Native()
    expected = []
    rejected = 0
    for k, line in enumerate(lines):
        if line == 'none':
            rejected += 1
            expected.append(None)
            continue
        entries_s, image_s = re.match(r'\[(.*?)\] \[(.*?)\]$', line).groups()
        entries = [int(x) for x in entries_s.split(',')]
        image = bytes(int(x) for x in image_s.split(','))
        native.load(entries, image, len(programs[k][0][0]))
        expected.append([native.call(a, programs[k][0][0]) for a in calls[k]])

    # One harness binary per chunk keeps each laniusc input small.
    data = b''
    for start in range(0, len(programs), args.chunk):
        lani_path = os.path.join(args.workdir, 'programs.lani')
        exe_path = os.path.join(args.workdir, 'programs')
        open(lani_path, 'w').write(lani_file(programs[start:start + args.chunk], calls[start:start + args.chunk]))
        build = subprocess.run(['systemd-run', '--user', '--scope', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                                'target/claude-work/bin/heavy', '-t', '20', args.laniusc, '--stdlib-root', 'stdlib',
                                '-o', exe_path, lani_path], capture_output=True, text=True)
        if build.returncode != 0:
            raise SystemExit('laniusc failed:\n' + build.stdout[-4000:] + build.stderr[-4000:])
        run = subprocess.run([exe_path], capture_output=True)
        if run.returncode != 0:
            raise SystemExit(f'laniusc program exited {run.returncode} on programs {start}..')
        data += run.stdout
    total = sum(len(c) for c in calls)
    if len(data) != 4 * total:
        raise SystemExit(f'laniusc programs wrote {len(data)} bytes, expected {4 * total}')
    got = [i32(int.from_bytes(data[4 * i:4 * i + 4], 'little')) for i in range(total)]

    disagreements = 0
    at = 0
    for k, want in enumerate(expected):
        have = got[at:at + len(calls[k])]
        at += len(calls[k])
        if want is None:
            print(f'program {k}: the verified compiler rejects it')
            disagreements += 1
            continue
        for a, x, y in zip(calls[k], want, have):
            reference = i32(interpret(programs[k], 0, a))
            if x != y or x != reference:
                disagreements += 1
                print(f'program {k} args {a}: verified compiler {x}, laniusc {y}, reference {reference}')
    print(f'{len(programs)} programs ({rejected} rejected), {total} calls, {disagreements} disagreements')
    return 1 if disagreements else 0


if __name__ == '__main__':
    sys.exit(main())
