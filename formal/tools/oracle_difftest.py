#!/usr/bin/env python3
"""The verified compiler as an oracle for laniusc (roadmap step 12).

Random source programs in the front pass's subset are compiled twice: by the
verified compiler (`compileSource`, the extracted Lean definitions, run by
`#eval`), whose image runs natively here, and by laniusc, from the same
program printed as Lanius. Every call of each program's entry function on its
argument tuples must give the same result.

    python3 -I formal/tools/oracle_difftest.py WORKDIR [--count N] [--seed S] [--calls K] [--chunk C] [--only K,..] [--laniusc PATH]

Run from the repository root. laniusc runs under target/claude-work/bin/heavy.
A Python interpreter of the generated programs gives a third answer, so a
disagreement shows which side is wrong. Prints one line per disagreement and a
summary; exits nonzero on any.

The programs use i32, bool, the unsigned types, structs and enums of those:
literals, locals, fields, the operators, casts, variants, `match`, `let`,
assignment, `if`, bounded `while` loops, calls to later functions (so every
run ends) and `return`. A function's first parameter is an i32 the harness
passes; the entry function returns an i32.
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


def i32(x):
    x &= 0xffffffff
    return x - (1 << 32) if x >> 31 else x


# ---------------------------------------------------------------- generator
# Types: 'i32' 'bool' 'u8' 'u32' 'u64' 'usize' ('struct', k) ('enum', k), struct k's
# field types TYPES.structs[k], enum k's variants' payload types TYPES.enums[k].
# Expressions: ('int', k) ('bool', b) ('uint', ty, k) ('local', id) ('field', id, j) ('neg', e)
#              ('not', e) ('cast', ty, e) ('op', name, sym, l, r)
# Statements: ('nop',) ('let', id, ty, e, body) ('call', id, ty, callee, args, body) ('set', id, e)
#             ('letStruct', id, ty, fields, body) ('letEnum', id, ty, variant, payload, body)
#             ('letMatch', id, ty, scrutinee, enum, arms, body) with arms [(binders, value)]
#             ('setField', id, j, e) ('then', a, b) ('if', c, a, b) ('while', c, body) ('return', e)

SCALARS = ['i32', 'bool'] + list(UINT_BITS)
LETS = ('let', 'call', 'letStruct', 'letEnum', 'letMatch')


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

    def new_id(self):
        self.fresh += 1
        return self.fresh

    def lit_i32(self):
        if self.rng.random() < 0.6:
            return self.rng.choice(I32_EDGES)
        return self.rng.randint(-2 ** 31, 2 ** 31 - 1)

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
            return ('uint', ty, self.lit_uint(ty))
        if ty in UINT_BITS:
            if rng.random() < 0.2:
                return ('cast', ty, self.expr(rng.choice(INTEGERS), depth - 1, env))
            name, sym = rng.choice(ARITH)
            return ('op', name, sym, self.expr(ty, depth - 1, env), self.expr(ty, depth - 1, env))
        if ty == 'i32' and rng.random() < 0.1:
            return ('cast', 'i32', self.expr(rng.choice(list(UINT_BITS)), depth - 1, env))
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
            operand = rng.choice(['i32', 'i32'] + list(UINT_BITS))
            return ('op', name, sym, self.expr(operand, depth - 1, env), self.expr(operand, depth - 1, env))
        if pick < 0.7:
            name, sym = rng.choice(EQUAL)
            return ('op', name, sym, self.expr('bool', depth - 1, env), self.expr('bool', depth - 1, env))
        name, sym = rng.choice(LOGIC)
        return ('op', name, sym, self.expr('bool', depth - 1, env), self.expr('bool', depth - 1, env))

    def make_struct(self, env, items):
        k = self.rng.randrange(len(TYPES.structs))
        ident = self.new_id()
        items.append(('letStruct', ident, ('struct', k), [self.expr(f, 2, env) for f in TYPES.structs[k]]))
        env.append((ident, ('struct', k)))

    def make_enum(self, env, items):
        k = self.rng.randrange(len(TYPES.enums))
        variant = self.rng.randrange(len(TYPES.enums[k]))
        ident = self.new_id()
        payload = [self.expr(f, 2, env) for f in TYPES.enums[k][variant]]
        items.append(('letEnum', ident, ('enum', k), variant, payload))
        env.append((ident, ('enum', k)))
        return ident, k

    def block(self, depth, env, ret, must_return, mutable):
        """A statement list ending in a return when must_return. mutable: the ids
        assignments may change (loop counters are left out)."""
        rng = self.rng
        items = []
        env = list(env)
        mutable = list(mutable)
        returned = False
        for _ in range(rng.randint(0, 4 if depth > 0 else 2)):
            kind = rng.choice(['let', 'let', 'set', 'if', 'while', 'call', 'struct', 'enum', 'match', 'setField']
                              if depth > 0 else ['let', 'set', 'struct', 'setField'])
            if kind == 'let':
                ty = rng.choice(['i32', 'i32', 'bool'] + list(UINT_BITS))
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
            elif kind == 'call':
                later = list(range(self.index + 1, len(self.sigs)))
                if not later:
                    continue
                callee = rng.choice(later)
                params, cret = self.sigs[callee]
                args = [self.expr(t, 2, env) for t in params]
                ident = self.new_id()
                items.append(('call', ident, cret, callee, args))
                env.append((ident, cret))
                mutable.append((ident, cret))
        if must_return and not returned:
            items.append(('return', self.expr(ret, 3, env)))
        return nest(items)


def returns(s):
    kind = s[0]
    if kind in LETS:
        return returns(s[-1])
    if kind == 'then':
        return returns(s[1]) or returns(s[2])
    if kind == 'if':
        return returns(s[2]) and returns(s[3])
    return kind == 'return'


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
    structs = [[rng.choice(SCALARS) for _ in range(rng.randint(1, 3))] for _ in range(rng.randint(0, 2))]
    enums = [[[rng.choice(SCALARS) for _ in range(rng.randint(0, 2))] for _ in range(rng.randint(1, 3))]
             for _ in range(rng.randint(0, 2))]
    TYPES = Program([], structs, enums)
    count = rng.randint(1, 4)
    sigs = [(['i32'] + [rng.choice(SCALARS) for _ in range(rng.randint(0, 2))],
             'i32' if k == 0 else rng.choice(SCALARS)) for k in range(count)]
    funcs = []
    for k, (params, ret) in enumerate(sigs):
        g = Gen(rng, sigs, k)
        env = [(j, t) for j, t in enumerate(params)]
        body = g.block(3, env, ret, True, [])
        funcs.append((params, ret, body))
    return Program(funcs, structs, enums)


def gen_args(rng, params):
    out = []
    for t in params:
        if t == 'i32':
            out.append(rng.choice(I32_EDGES) if rng.random() < 0.5 else rng.randint(-2 ** 31, 2 ** 31 - 1))
        elif t == 'bool':
            out.append(int(rng.random() < 0.5))
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
    return x & ((1 << UINT_BITS[ty]) - 1)


def ty_of(e, env):
    kind = e[0]
    if kind == 'int' or kind == 'neg':
        return 'i32'
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
        return i32(-ev(e[1], env))
    if kind == 'not':
        return not ev(e[1], env)
    if kind == 'cast':
        return wrap_to(e[1], ev(e[2], env))
    l, r = ev(e[3], env), ev(e[4], env)
    name = e[1]
    if name in ('plus', 'minus', 'times', 'bitAnd', 'bitOr', 'bitXor'):
        x = {'plus': l + r, 'minus': l - r, 'times': l * r, 'bitAnd': l & r, 'bitOr': l | r, 'bitXor': l ^ r}[name]
        return wrap_to(ty_of(e[3], env), x)
    return {'less': l < r, 'lessEq': l <= r, 'greater': l > r, 'greaterEq': l >= r, 'equal': l == r,
            'notEqual': l != r, 'logicalAnd': l and r, 'logicalOr': l or r}[name]


def run_stmt(s, env, funcs):
    kind = s[0]
    if kind == 'let':
        env[s[1]] = [ev(s[3], env), s[2]]
        run_stmt(s[4], env, funcs)
    elif kind == 'call':
        env[s[1]] = [interpret(funcs, s[3], [ev(a, env) for a in s[4]]), s[2]]
        run_stmt(s[5], env, funcs)
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


def interpret(funcs, index, args):
    global TYPES
    TYPES = funcs
    params, ret, body = funcs[index]
    env = {j: [a if t != 'bool' else bool(a), t] for j, (a, t) in enumerate(zip(args, params))}
    try:
        run_stmt(body, env, funcs)
    except Returned as r:
        return int(r.value) if ret == 'bool' else r.value
    raise SystemExit('a generated function fell off its end')


# ---------------------------------------------------------------- Lean side

def lean_ty(t):
    if t in UINT_BITS:
        return f'(.uint {UINT_LEAN[t]})'
    if t[0] == 'struct':
        return f'(.struct {t[1]} [{", ".join(lean_ty(f) for f in TYPES.structs[t[1]])}])'
    if t[0] == 'enum':
        variants = ', '.join('[' + ', '.join(lean_ty(f) for f in v) + ']' for v in TYPES.enums[t[1]])
        return f'(.enum {len(TYPES.structs) + t[1]} [{variants}])'
    return '.' + t


def lean_list(es):
    return '[' + ', '.join(lean_expr(e) for e in es) + ']'


def lean_expr(e):
    kind = e[0]
    if kind == 'int':
        return f'(.int (BitVec.ofInt 32 ({e[1]})))'
    if kind == 'bool':
        return '(.boolean true)' if e[1] else '(.boolean false)'
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


def lean_stmt(s):
    kind = s[0]
    if kind == 'nop':
        return '.nop'
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
    return f'({lani_expr(e[3])} {e[2]} {lani_expr(e[4])})'


def lani_stmt(s, prefix, indent):
    pad = '    ' * indent
    kind = s[0]
    if kind == 'nop':
        return []
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
            out.append(f'fn p{k}_f{j}({ps}) -> {lani_ty(ret)} {{')
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

    def call(self, args):
        # An i32 sits zero-extended in its slot, an unsigned value as itself.
        self.heap[0:self.HEAP] = bytes(self.HEAP)
        return i32(self.fn(*[a & 0xffffffff if a < 0 else a for a in args]))


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
        expected.append([native.call(a) for a in calls[k]])

    # One harness binary per chunk keeps each laniusc input small.
    data = b''
    for start in range(0, len(programs), args.chunk):
        lani_path = os.path.join(args.workdir, 'programs.lani')
        exe_path = os.path.join(args.workdir, 'programs')
        open(lani_path, 'w').write(lani_file(programs[start:start + args.chunk], calls[start:start + args.chunk]))
        build = subprocess.run(['target/claude-work/bin/heavy', '-t', '20', args.laniusc, '--stdlib-root', 'stdlib',
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
