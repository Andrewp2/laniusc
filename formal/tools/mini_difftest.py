#!/usr/bin/env python3
"""Differential test of the mini compiler: the Lean definitions extracted from
formal/lani/mini/compiler.lani (run by `#eval`) against the same Lanius source
compiled by laniusc, on random programs (some deliberately ill-formed).

    python3 formal/tools/mini_difftest.py WORKDIR [--count N] [--seed S] [--chunk K] [--laniusc PATH]

Run from the repository root. laniusc runs under target/claude-work/bin/heavy.
Prints one line per mismatch and a summary; exits nonzero on any mismatch.
"""

import argparse
import os
import random
import subprocess
import sys

BINOPS = ['add', 'sub', 'mul', 'and', 'or', 'xor']
CMPOPS = ['eq', 'ne', 'lt', 'le', 'gt', 'ge']
WORDS = ['s32', 'u64']
EDGES = [0, 1, 2, 7, 100, 65536, 2 ** 31 - 1, 2 ** 31, 2 ** 32 - 1, 2 ** 32, 2 ** 32 + 5, 2 ** 63, 2 ** 64 - 1,
         2 ** 64 - 7, 2 ** 32 - 7]


def gen_lit(rng):
    pick = rng.random()
    if pick < 0.5:
        return rng.choice(EDGES)
    if pick < 0.75:
        return rng.randint(-2 ** 31, 2 ** 31 - 1) & (2 ** 32 - 1)
    return rng.randrange(2 ** 64)


def gen_expr(rng, depth, locals_):
    if depth == 0 or rng.random() < 0.3:
        if locals_ and rng.random() < 0.6:
            return ('var', rng.randrange(locals_))
        return ('lit', gen_lit(rng))
    kind = rng.choice(['neg', 'binary', 'binary', 'compare'])
    if kind == 'neg':
        return ('neg', gen_expr(rng, depth - 1, locals_))
    op = rng.choice(BINOPS if kind == 'binary' else CMPOPS)
    return (kind, rng.choice(WORDS), op, gen_expr(rng, depth - 1, locals_), gen_expr(rng, depth - 1, locals_))


def gen_stmt(rng, depth, locals_, arities, results):
    if depth == 0:
        return ('assign', rng.randrange(locals_), gen_expr(rng, 2, locals_)) if locals_ else ('skip',)
    kind = rng.choice(['skip', 'assign', 'seq', 'seq', 'ite', 'loop', 'call', 'ret', 'alloc', 'loadByte',
                       'storeByte', 'loadWord', 'storeWord'])
    if kind == 'skip' or (kind in ('assign', 'call', 'alloc', 'loadByte', 'loadWord') and not locals_):
        return ('skip',)
    if kind == 'alloc':
        return ('alloc', rng.randrange(locals_), rng.choice([0, 0, 1, 3, 4, 12, 31, 32]), gen_expr(rng, 2, locals_))
    if kind == 'loadByte':
        return ('loadByte', rng.randrange(locals_), gen_expr(rng, 2, locals_))
    if kind == 'storeByte':
        return ('storeByte', gen_expr(rng, 2, locals_), gen_expr(rng, 2, locals_))
    if kind == 'loadWord':
        return ('loadWord', rng.choice(['m32', 'm64']), rng.randrange(locals_), gen_expr(rng, 2, locals_))
    if kind == 'storeWord':
        return ('storeWord', rng.choice(['m32', 'm64']), gen_expr(rng, 2, locals_), gen_expr(rng, 2, locals_))
    if kind == 'assign':
        return ('assign', rng.randrange(locals_), gen_expr(rng, 3, locals_))
    if kind == 'seq':
        return ('seq', gen_stmt(rng, depth - 1, locals_, arities, results), gen_stmt(rng, depth - 1, locals_, arities, results))
    if kind == 'ite':
        return ('ite', gen_expr(rng, 2, locals_), gen_stmt(rng, depth - 1, locals_, arities, results),
                gen_stmt(rng, depth - 1, locals_, arities, results))
    if kind == 'loop':
        return ('loop', gen_expr(rng, 2, locals_), gen_stmt(rng, depth - 1, locals_, arities, results))
    if kind == 'call':
        callee = rng.randrange(len(arities))
        params, count = arities[callee]
        target = rng.randrange(max(1, locals_ - count + 1))
        return ('call', target, count, callee, [gen_expr(rng, 2, locals_) for _ in range(params)])
    return ('ret', [gen_expr(rng, 3, locals_) for _ in range(results)])


def break_program(rng, funcs):
    """Make one function ill-formed: a local out of range, a wrong arity or
    result count, a call writing past the locals, params > locals, or no results."""
    f = rng.randrange(len(funcs))
    params, results, locals_, body = funcs[f]
    how = rng.choice(['var', 'arity', 'count', 'target', 'results', 'params', 'none'])
    if how == 'var':
        body = ('seq', body, ('ret', [('var', locals_ + rng.randrange(3))] * results))
    elif how == 'arity':
        body = ('seq', ('call', 0, funcs[0][1], 0, [('lit', 1)] * (funcs[0][0] + 1)), body)
    elif how == 'count':
        body = ('seq', ('call', 0, funcs[0][1] + 1, 0, [('lit', 1)] * funcs[0][0]), body)
    elif how == 'target':
        body = ('seq', ('call', locals_, funcs[0][1], 0, [('lit', 1)] * funcs[0][0]), body)
    elif how == 'results':
        body = ('seq', body, ('ret', [('lit', 3)] * (results + 1)))
    elif how == 'params':
        params = locals_ + 1
    else:
        results = 0
    funcs[f] = (params, results, locals_, body)


def gen_program(rng, broken):
    count = rng.randint(1, 4)
    arities = [(rng.randint(0, 3), rng.randint(1, 3)) for _ in range(count)]
    funcs = []
    for params, results in arities:
        locals_ = max(params, results) + rng.randint(0, 3)
        funcs.append((params, results, locals_, gen_stmt(rng, rng.randint(1, 4), locals_, arities, results)))
    if broken:
        break_program(rng, funcs)
    return funcs


# The native test program (fact, fib, mix, gcd), as in difftest.lani.
def seqs(stmts):
    return stmts[0] if len(stmts) == 1 else ('seq', stmts[0], seqs(stmts[1:]))


def v(i):
    return ('var', i)


def n(k):
    return ('lit', k & (2 ** 32 - 1))


def b(op, l, r):
    return ('binary', 's32', op, l, r)


def c(op, l, r):
    return ('compare', 's32', op, l, r)


NATIVE = [
    (1, 1, 2, seqs([('assign', 1, n(1)),
                 ('loop', c('gt', v(0), n(0)),
                  seqs([('assign', 1, b('mul', v(1), v(0))), ('assign', 0, b('sub', v(0), n(1)))])),
                 ('ret', [v(1)])])),
    (1, 1, 3, ('ite', c('lt', v(0), n(2)), ('ret', [v(0)]),
            seqs([('call', 1, 1, 1, [b('sub', v(0), n(1))]), ('call', 2, 1, 1, [b('sub', v(0), n(2))]),
                  ('ret', [b('add', v(1), v(2))])]))),
    (3, 1, 5, seqs([
        ('assign', 3, b('add', c('le', v(0), v(1)), b('mul', c('ge', v(1), v(2)), n(2)))),
        ('assign', 3, b('add', v(3), b('mul', c('eq', v(0), v(2)), n(4)))),
        ('assign', 3, b('add', v(3), b('mul', c('ne', v(0), v(1)), n(8)))),
        ('call', 4, 1, 0, [b('and', v(2), n(7))]),
        ('ite', c('lt', v(3), n(100)),
         ('ret', [b('xor', b('or', v(4), b('mul', v(3), n(65536))), ('neg', v(0)))]),
         ('ret', [n(-1)]))])),
    (2, 1, 2, seqs([('loop', c('ne', v(0), v(1)),
                  ('ite', c('gt', v(0), v(1)), ('assign', 0, b('sub', v(0), v(1))),
                   ('assign', 1, b('sub', v(1), v(0))))),
                 ('ret', [v(0)])])),
]


# ---------------------------------------------------------------- Lean

def lean_expr(e):
    k = e[0]
    if k == 'lit':
        return f'(.lit (BitVec.ofNat 64 {e[1]}))'
    if k == 'var':
        return f'(.var {e[1]})'
    if k == 'neg':
        return f'(.neg {lean_expr(e[1])})'
    return f'(.{k} .{e[1]} .{e[2]} {lean_expr(e[3])} {lean_expr(e[4])})'


def lean_stmt(s):
    k = s[0]
    if k == 'skip':
        return '.skip'
    if k == 'assign':
        return f'(.assign {s[1]} {lean_expr(s[2])})'
    if k == 'seq':
        return f'(.seq {lean_stmt(s[1])} {lean_stmt(s[2])})'
    if k == 'ite':
        return f'(.ite {lean_expr(s[1])} {lean_stmt(s[2])} {lean_stmt(s[3])})'
    if k == 'loop':
        return f'(.loop {lean_expr(s[1])} {lean_stmt(s[2])})'
    if k == 'call':
        return f'(.call {s[1]} {s[2]} {s[3]} [{", ".join(lean_expr(a) for a in s[4])}])'
    if k == 'alloc':
        return f'(.alloc {s[1]} {s[2]} {lean_expr(s[3])})'
    if k == 'loadByte':
        return f'(.loadByte {s[1]} {lean_expr(s[2])})'
    if k == 'storeByte':
        return f'(.storeByte {lean_expr(s[1])} {lean_expr(s[2])})'
    if k == 'loadWord':
        return f'(.loadWord .{s[1]} {s[2]} {lean_expr(s[3])})'
    if k == 'storeWord':
        return f'(.storeWord .{s[1]} {lean_expr(s[2])} {lean_expr(s[3])})'
    return f'(.ret [{", ".join(lean_expr(a) for a in s[1])}])'


def lean_file(programs):
    out = ['import Lanius.Mini.Compiler', 'open Lanius.Mini', '',
           'def render (p : Program) : String :=',
           '  match compileProgram p with',
           '  | none => "none"',
           '  | some b => String.join (b.image.map fun byte => String.ofList ((Nat.toDigits 16 (byte.toNat + 256)).drop 1))', '']
    for index, funcs in enumerate(programs):
        fs = ', '.join(f'{{ params := {p}, results := {r}, locals := {l}, body := {lean_stmt(b)} }}'
                       for p, r, l, b in funcs)
        out.append(f'def p{index} : Program := {{ funcs := [{fs}] }}')
    out.append('')
    out.append('#eval IO.println (String.intercalate "\\n" [' + ', '.join(f'render p{i}' for i in range(len(programs))) + '])')
    return '\n'.join(out) + '\n'


# ---------------------------------------------------------------- Lanius

M = 'mini::compiler::'


def lani_expr(e):
    k = e[0]
    if k == 'lit':
        # laniusc literals are i32, so build the word from 16-bit pieces.
        parts = [f'(({(e[1] >> shift) & 65535} as u64) << {shift})' for shift in (48, 32, 16)]
        return 'n(' + ' | '.join(parts + [f'({e[1] & 65535} as u64)']) + ')'
    if k == 'var':
        return f'v({e[1]})'
    if k == 'neg':
        return f'neg({lani_expr(e[1])})'
    word = e[1].upper()
    op = e[2][:1].upper() + e[2][1:]
    return f'{"bin" if k == "binary" else "cmp"}({M}{word}, {M}{op}, {lani_expr(e[3])}, {lani_expr(e[4])})'


def lani_stmt(s):
    k = s[0]
    if k == 'skip':
        return f'{M}Skip'
    if k == 'assign':
        return f'{M}Assign({s[1]}, {lani_expr(s[2])})'
    if k == 'seq':
        return f'seq({lani_stmt(s[1])}, {lani_stmt(s[2])})'
    if k == 'ite':
        return f'ite({lani_expr(s[1])}, {lani_stmt(s[2])}, {lani_stmt(s[3])})'
    if k == 'loop':
        return f'loop_while({lani_expr(s[1])}, {lani_stmt(s[2])})'
    if k == 'call':
        return f'{M}Stmt::Call({s[1]}, {s[2]}, {s[3]}, {lani_exprs(s[4])})'
    if k == 'alloc':
        return f'{M}Stmt::Alloc({s[1]}, {s[2]}, {lani_expr(s[3])})'
    if k == 'loadByte':
        return f'{M}Stmt::LoadByte({s[1]}, {lani_expr(s[2])})'
    if k == 'storeByte':
        return f'{M}Stmt::StoreByte({lani_expr(s[1])}, {lani_expr(s[2])})'
    if k == 'loadWord':
        return f'{M}Stmt::LoadWord({M}{s[1].upper()}, {s[2]}, {lani_expr(s[3])})'
    if k == 'storeWord':
        return f'{M}Stmt::StoreWord({M}{s[1].upper()}, {lani_expr(s[2])}, {lani_expr(s[3])})'
    return f'{M}Stmt::Ret({lani_exprs(s[1])})'


def lani_exprs(es):
    out = 'no_args()'
    for e in reversed(es):
        out = f'{M}cons({lani_expr(e)}, {out})'
    return out


LANI_HEAD = f'''module app::main;
import core::option;
import mini::compiler;
import std::io_byte;

fn v(index: usize) -> {M}Expr {{ return {M}Var(index); }}
fn n(value: u64) -> {M}Expr {{ return {M}Lit(value); }}
fn neg(e: {M}Expr) -> {M}Expr {{ return {M}Expr::Neg({M}boxed(e)); }}
fn bin(word: {M}Word, op: {M}BinOp, l: {M}Expr, r: {M}Expr) -> {M}Expr {{ return {M}Binary(word, op, {M}boxed(l), {M}boxed(r)); }}
fn cmp(word: {M}Word, op: {M}CmpOp, l: {M}Expr, r: {M}Expr) -> {M}Expr {{ return {M}Compare(word, op, {M}boxed(l), {M}boxed(r)); }}
fn seq(a: {M}Stmt, b: {M}Stmt) -> {M}Stmt {{ return {M}Seq({M}boxed(a), {M}boxed(b)); }}
fn ite(c: {M}Expr, a: {M}Stmt, b: {M}Stmt) -> {M}Stmt {{ return {M}Ite(c, {M}boxed(a), {M}boxed(b)); }}
fn loop_while(c: {M}Expr, b: {M}Stmt) -> {M}Stmt {{ return {M}Loop(c, {M}boxed(b)); }}
fn no_args() -> {M}List<{M}Expr> {{ return {M}empty(); }}
fn func(params: usize, results: usize, locals: usize, body: {M}Stmt) -> {M}Func {{ return {M}Func {{ params: params, results: results, locals: locals, body: body }}; }}
fn no_funcs() -> {M}List<{M}Func> {{ return {M}empty(); }}

fn put(value: i32) -> i32 {{
    let written: bool = std::io_byte::write_stdout_byte(value);
    return 0;
}}

fn put_then(value: u8, rest: {M}List<u8>) -> i32 {{
    put(value as i32);
    return put_all(rest);
}}

fn put_all(bytes: {M}List<u8>) -> i32 {{
    return match (bytes) {{
        Nil -> 0,
        Cons(value, rest) -> put_then(value, {M}unbox(rest)),
    }};
}}

// Each program writes 4 length bytes (255 255 255 255 for none), then its image.
fn emit(prog: {M}Program) -> i32 {{
    let none: {M}List<u8> = {M}empty();
    let image: {M}List<u8> = match ({M}compile_program(prog)) {{
        Some(binary) -> binary.image,
        None -> none,
    }};
    let ok: bool = match ({M}compile_program(prog)) {{
        Some(binary) -> true,
        None -> false,
    }};
    let length: i32 = {M}length(image) as i32;
    if (ok) {{
        put(length % 256);
        put((length / 256) % 256);
        put((length / 65536) % 256);
        put(length / 16777216);
    }} else {{
        put(255);
        put(255);
        put(255);
        put(255);
    }}
    return put_all(image);
}}
'''


def lani_file(programs):
    out = [LANI_HEAD]
    for index, funcs in enumerate(programs):
        fs = 'no_funcs()'
        for p, r, l, b in reversed(funcs):
            fs = f'{M}cons(func({p}, {r}, {l}, {lani_stmt(b)}), {fs})'
        out.append(f'fn p{index}() -> {M}Program {{ return {M}Program {{ funcs: {fs} }}; }}')
    out.append('fn main() -> i32 {')
    for index in range(len(programs)):
        out.append(f'    emit(p{index}());')
    out.append('    return 0;\n}')
    return '\n'.join(out) + '\n'


def parse_lanius(data, count):
    images, pos = [], 0
    for _ in range(count):
        head = data[pos:pos + 4]
        pos += 4
        if head == b'\xff\xff\xff\xff':
            images.append(None)
            continue
        length = int.from_bytes(head, 'little')
        images.append(data[pos:pos + length])
        pos += length
    if pos != len(data):
        raise SystemExit(f'lanius output has {len(data) - pos} trailing bytes')
    return images


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=40)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--chunk', type=int, default=40)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    programs = [NATIVE] + [gen_program(rng, broken=rng.random() < 0.25) for _ in range(args.count)]
    os.makedirs(args.workdir, exist_ok=True)
    lean_path = os.path.abspath(os.path.join(args.workdir, 'programs.lean'))
    open(lean_path, 'w').write(lean_file(programs))
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    lean = subprocess.run(['lake', 'env', 'lean', lean_path], cwd='formal', env=env, capture_output=True, text=True)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout + lean.stderr)
    expected = [None if line == 'none' else bytes.fromhex(line) for line in lean.stdout.strip().split('\n')]
    # The Lanius runtime gives each allocation its own page in a 1 GiB window,
    # and the prelude never frees, so each harness binary compiles a few programs.
    got = []
    for start in range(0, len(programs), args.chunk):
        chunk = programs[start:start + args.chunk]
        lani_path = os.path.join(args.workdir, 'programs.lani')
        exe_path = os.path.join(args.workdir, 'programs')
        open(lani_path, 'w').write(lani_file(chunk))
        build = subprocess.run(['target/claude-work/bin/heavy', '-t', '20', args.laniusc, '--stdlib-root', 'stdlib',
                                '--source-root', 'formal/lani', '-o', exe_path, lani_path],
                               capture_output=True, text=True)
        if build.returncode != 0:
            raise SystemExit('laniusc failed:\n' + build.stdout + build.stderr)
        run = subprocess.run([exe_path], capture_output=True)
        if run.returncode != 0:
            raise SystemExit(f'compiled harness exited {run.returncode} on programs {start}..')
        got += parse_lanius(run.stdout, len(chunk))
    mismatches = 0
    for index, (want, have) in enumerate(zip(expected, got)):
        if want != have:
            mismatches += 1
            print(f'program {index}: lean {"none" if want is None else len(want)} bytes, '
                  f'lanius {"none" if have is None else len(have)} bytes')
    rejected = sum(image is None for image in expected)
    total = sum(len(image) for image in expected if image is not None)
    print(f'{len(programs)} programs ({rejected} rejected), {total} image bytes, {mismatches} mismatches')
    return 1 if mismatches else 0


if __name__ == '__main__':
    sys.exit(main())
