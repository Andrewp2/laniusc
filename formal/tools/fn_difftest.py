#!/usr/bin/env python3
"""Differential test of every extracted function against its Lean definition.

    python3 -I formal/tools/fn_difftest.py WORKDIR [--per-fn N] [--seed S] [--shard i/n] [--laniusc PATH] [--source FILE]

For each function and method that extract.py emits (not the inline helpers or
the list operations, which have spec theorems), generate N random arguments
from the declared types, run the Lean definition with #eval and the Lanius
function natively, and compare canonical renderings of the results.

The Lanius side is a copy of formal/lani/mini/compiler.lani with only its
module line changed, followed by generated renderers and one function per
case, so the code under test is the extracted source byte for byte. A function
with `&mut` parameters (formal/lani/mini/mut_pilot.lani, with --source and
--lean-module) is called with references to locals, and the case prints the
result and then each of those locals, which the Lean side's tuple must match. A Lanius
run that does not return is not a mismatch: the extracted definitions agree
with every run that returns. That covers a panic (minus below zero, which
Lean's Nat truncates) and a native stack overflow (SIGSEGV), since Lean has no
stack limit and the compiler recurses once per list element or local. The
binary restarts after a failed case at the next one, passed as its argument
count, and the summary reports each failure by function and signal.
"""

import argparse
import os
import random
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402
import extract  # noqa: E402
from extract import Ty, camel, lower_first  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SOURCE = os.path.join(ROOT, 'formal/lani/mini/compiler.lani')
FORMAL = os.path.join(ROOT, 'formal')
HEAVY = os.path.join(ROOT, 'target/claude-work/bin/heavy')


def key(t):
    """A name fragment for a type, used in generated Lanius helper names."""
    t = t.strip_box()
    return t.name + ''.join('_' + key(a) for a in t.args)


class Types:
    def __init__(self, ex):
        self.ex = ex

    # ------------------------------------------------------------ values

    def gen(self, t, rng, depth):
        t = t.strip_box()
        n = t.name
        if n == 'usize':
            return ('nat', rng.choice([0, 0, 1, 1, 2, 3, 4, 5, 7, 8, 12, 31, 100, 4096, rng.randrange(1 << 20)]))
        if n in ('i32', 'u32'):
            v = rng.choice([0, 1, -1, 2, 7, -8, 127, 128, 255, 256, -129, 2 ** 31 - 1, -2 ** 31,
                            rng.randrange(-2 ** 31, 2 ** 31)])
            return ('bits', v % 2 ** 32)
        if n == 'u64':
            return ('bits64', rng.choice([0, 1, 2, 255, 256, 2 ** 31, 2 ** 32 - 1, 2 ** 32, 2 ** 63,
                                          2 ** 64 - 1, rng.randrange(2 ** 32), rng.randrange(2 ** 64)]))
        if n == 'u8':
            return ('u8', rng.randrange(256))
        if n == 'bool':
            return ('bool', rng.random() < 0.5)
        if n == 'List':
            count = 0 if depth <= 0 else rng.choice([0, 1, 1, 2, 2, 3, 4])
            return ('list', t.args[0], [self.gen(t.args[0], rng, depth - 1) for _ in range(count)])
        if n == 'Option':
            if depth <= 0 or rng.random() < 0.3:
                return ('none', t.args[0])
            return ('some', t.args[0], self.gen(t.args[0], rng, depth - 1))
        if n in self.ex.enums:
            ctors = self.ex.enums[n]['ctors']
            leaves = [c for c in ctors if not any(p.strip_box().name == n for p in c[1])]
            ctor, payload, _ = rng.choice(leaves if depth <= 0 else ctors)
            if n == 'SrcType' and ctor == 'Array':
                # A short array: a random length would make the functions
                # that walk an array's slots (its size is length * element
                # size) run for minutes.
                return ('enum', n, ctor, [self.gen(payload[0], rng, depth - 1), ('nat', rng.choice([0, 1, 2, 3, 5]))])
            return ('enum', n, ctor, [self.gen(p, rng, depth - 1) for p in payload])
        if n in self.ex.structs:
            fields = self.ex.structs[n]['fields']
            return ('struct', n, [(f, self.gen(ft, rng, depth - 1)) for f, ft, _ in fields])
        raise ValueError(f'cannot generate {t!r}')

    def lean(self, v):
        k = v[0]
        if k == 'nat':
            return str(v[1])
        if k == 'bits':
            return f'(BitVec.ofNat 32 {v[1]})'
        if k == 'bits64':
            return f'(BitVec.ofNat 64 {v[1]})'
        if k == 'u8':
            return f'({v[1]} : UInt8)'
        if k == 'bool':
            return 'true' if v[1] else 'false'
        if k == 'list':
            return '[' + ', '.join(self.lean(x) for x in v[2]) + ']'
        if k == 'none':
            return 'none'
        if k == 'some':
            return f'(some {self.lean(v[2])})'
        if k == 'enum':
            head = f'{v[1]}.{lower_first(v[2])}'
            return f'({" ".join([head] + [self.lean(x) for x in v[3]])})' if v[3] else head
        if k == 'struct':
            return '({ ' + ', '.join(f'{camel(f)} := {self.lean(x)}' for f, x in v[2]) + f' }} : {v[1]})'
        raise ValueError(k)

    def lani(self, v, t):
        """A Lanius expression of type t (Box<T> wraps with boxed)."""
        if t.name == 'Box':
            return f'boxed({self.lani(v, t.args[0])})'
        k = v[0]
        if k == 'nat':
            return f'({v[1]} as usize)'
        if k == 'bits':
            signed = v[1] - 2 ** 32 if v[1] >= 2 ** 31 else v[1]
            text = str(signed) if signed >= 0 else f'(0 - {-signed - 1} - 1)'
            return text if t.name == 'i32' else f'({text} as u32)'
        if k == 'bits64':
            # laniusc literals are i32, so build the word from 16-bit pieces.
            parts = [f'(({(v[1] >> shift) & 65535} as u64) << {shift})' for shift in (48, 32, 16)]
            return '(' + ' | '.join(parts + [f'({v[1] & 65535} as u64)']) + ')'
        if k == 'u8':
            return f'({v[1]} as u8)'
        if k == 'bool':
            return 'true' if v[1] else 'false'
        if k == 'list':
            self.need_nil.add(v[1])
            text = f'nil_{key(v[1])}()'
            for x in reversed(v[2]):
                text = f'cons({self.lani(x, v[1])}, {text})'
            return text
        if k == 'none':
            self.need_none.add(v[1])
            return f'none_{key(v[1])}()'
        if k == 'some':
            return f'Some({self.lani(v[2], v[1])})'
        if k == 'enum':
            payload = next(p for c, p, _ in self.ex.enums[v[1]]['ctors'] if c == v[2])
            head = f'{v[1]}::{v[2]}'
            if not payload:
                return head
            return f'{head}({", ".join(self.lani(x, pt) for x, pt in zip(v[3], payload))})'
        if k == 'struct':
            fields = self.ex.structs[v[1]]['fields']
            parts = [f'{f}: {self.lani(x, ft)}' for (f, x), (_, ft, _) in zip(v[2], fields)]
            return f'{v[1]} {{ {", ".join(parts)} }}'
        raise ValueError(k)

    # ------------------------------------------------------------ rendering

    def lean_render(self, t, term):
        """A Lean String expression rendering term : t."""
        t = t.strip_box()
        n = t.name
        if n == 'usize':
            return f'(toString {term})'
        if n in ('i32', 'u32'):
            return f'(hex8 {term}.toNat)'
        if n == 'u64':
            return f'(hex16 {term}.toNat)'
        if n == 'u8':
            return f'(hex2 {term}.toNat)'
        if n in ('bool', 'List', 'Option') or n in self.ex.enums or n in self.ex.structs:
            self.need_render.add(t)
            return f'(render_{key(t)} {term})'
        raise ValueError(n)

    def lean_renderers(self):
        text, deps, done = {}, {}, set()
        while self.need_render - done:
            t = sorted(self.need_render - done, key=repr)[0]
            done.add(t)
            before = set(self.need_render)
            self.need_render.clear()
            out = []
            n, name = t.name, f'render_{key(t)}'
            lt = extract.lean_type(t)
            if n == 'bool':
                out.append(f'def {name} (b : Bool) : String := if b then "t" else "f"')
            elif n == 'List':
                inner = self.lean_render(t.args[0], 'x')
                out.append(f'def {name} (xs : {lt}) : String :=\n'
                           f'  "[" ++ String.join (xs.map (fun x => {inner} ++ ",")) ++ "]"')
            elif n == 'Option':
                inner = self.lean_render(t.args[0], 'x')
                out.append(f'def {name} : {lt} → String\n  | none => "N"\n  | some x => "S(" ++ {inner} ++ ")"')
            elif n in self.ex.structs:
                fields = self.ex.structs[n]['fields']
                parts = ' ++ '.join(f'{self.lean_render(ft, f"s.{camel(f)}")} ++ ","' for f, ft, _ in fields)
                out.append(f'def {name} (s : {n}) : String := "{{" ++ {parts} ++ "}}"')
            else:
                ctors = self.ex.enums[n]['ctors']
                recursive = any(p.strip_box() == t for _, ps, _ in ctors for p in ps)
                arms = []
                for c, ps, _ in ctors:
                    binders = [f'p{i}' for i in range(len(ps))]
                    pat = ' '.join([f'.{lower_first(c)}'] + binders)
                    body = f'"{c}("' + ''.join(f' ++ {self.lean_render(p, b)} ++ ","' for p, b in zip(ps, binders)) + ' ++ ")"'
                    arms.append(f'  | {pat} => {body}')
                head = f'{"partial " if recursive else ""}def {name} : {n} → String'
                out.append(head + '\n' + '\n'.join(arms))
            text[t], deps[t] = out[0], set(self.need_render) - {t}
            self.need_render |= before
        # Tarjan's algorithm: components come out dependencies first. Renderers
        # that call each other (a type nested in a List of itself) are one
        # mutual block of partial defs.
        order, index, low, stack, on = [], {}, {}, [], set()
        def visit(t):
            index[t] = low[t] = len(index)
            stack.append(t)
            on.add(t)
            for d in sorted(deps[t], key=repr):
                if d not in index:
                    visit(d)
                    low[t] = min(low[t], low[d])
                elif d in on:
                    low[t] = min(low[t], index[d])
            if low[t] == index[t]:
                group = []
                while True:
                    u = stack.pop()
                    on.discard(u)
                    group.append(u)
                    if u == t:
                        break
                if len(group) == 1:
                    order.append(text[t])
                else:
                    defs = [text[u] if text[u].startswith('partial ') else 'partial ' + text[u]
                            for u in sorted(group, key=repr)]
                    order.append('mutual\n' + '\n\n'.join(defs) + '\nend')
        for t in sorted(text, key=repr):
            if t not in index:
                visit(t)
        return '\n\n'.join(order)

    def lani_render(self, t, term):
        """A Lanius statement-free expression (an i32 call) printing term : t."""
        if t.name == 'Box':
            return self.lani_render(t.args[0], f'unbox({term})')
        self.need_lani.add(t)
        return f'r_{key(t)}({term})'

    def lani_renderers(self):
        out, done = [], set()
        while self.need_lani - done:
            t = sorted(self.need_lani - done, key=repr)[0]
            done.add(t)
            n, k = t.name, key(t)
            lt = self.lani_type(t)
            if n == 'usize':
                out.append(f'fn r_{k}(v: usize) -> i32 {{\n    if (v > 9) {{\n        r_{k}(v / 10);\n    }}\n'
                           f'    return put((v % 10) as i32 + 48);\n}}')
            elif n in ('i32', 'u32'):
                bits = 'v' if n == 'i32' else '(v as i32)'
                out.append(f'fn r_{k}(v: {n}) -> i32 {{\n    let b: i32 = {bits};\n    let shift: i32 = 28;\n'
                           f'    while (shift >= 0) {{\n        put_hex((b >> shift) & 15);\n        shift -= 4;\n    }}\n'
                           f'    return 0;\n}}')
            elif n == 'u64':
                out.append(f'fn r_{k}(v: u64) -> i32 {{\n    return r_{k}_digits(v, 16);\n}}')
                out.append(f'fn r_{k}_digits(v: u64, n: i32) -> i32 {{\n    if (n > 1) {{\n'
                           f'        r_{k}_digits(v >> 4, n - 1);\n    }}\n'
                           f'    return put_hex((v & 15) as i32);\n}}')
            elif n == 'u8':
                out.append(f'fn r_{k}(v: u8) -> i32 {{\n    let b: i32 = v as i32;\n    put_hex(b / 16);\n'
                           f'    return put_hex(b % 16);\n}}')
            elif n == 'bool':
                out.append(f'fn r_{k}(v: bool) -> i32 {{\n    if (v) {{\n        return put(116);\n    }}\n'
                           f'    return put(102);\n}}')
            elif n == 'List':
                el = t.args[0]
                out.append(f'fn r_{k}(xs: {lt}) -> i32 {{\n    put(91);\n    r_{k}_items(xs);\n    return put(93);\n}}')
                out.append(f'fn r_{k}_items(xs: {lt}) -> i32 {{\n    return match (xs) {{\n        Nil -> 0,\n'
                           f'        Cons(x, rest) -> r_{k}_item(x, unbox(rest)),\n    }};\n}}')
                out.append(f'fn r_{k}_item(x: {self.lani_type(el)}, rest: {lt}) -> i32 {{\n'
                           f'    {self.lani_render(el, "x")};\n    put(44);\n    return r_{k}_items(rest);\n}}')
            elif n == 'Option':
                el = t.args[0]
                out.append(f'fn r_{k}(v: {lt}) -> i32 {{\n    return match (v) {{\n        None -> put(78),\n'
                           f'        Some(x) -> r_{k}_some(x),\n    }};\n}}')
                out.append(f'fn r_{k}_some(x: {self.lani_type(el)}) -> i32 {{\n    put(83);\n    put(40);\n'
                           f'    {self.lani_render(el, "x")};\n    return put(41);\n}}')
            elif n in self.ex.structs:
                fields = self.ex.structs[n]['fields']
                lines = [f'fn r_{k}(s: {n}) -> i32 {{', '    put(123);']
                for f, ft, _ in fields:
                    lines += [f'    {self.lani_render(ft, f"s.{f}")};', '    put(44);']
                lines += ['    return put(125);', '}']
                out.append('\n'.join(lines))
            else:
                ctors = self.ex.enums[n]['ctors']
                arms = []
                for c, ps, _ in ctors:
                    binders = [f'p{i}' for i in range(len(ps))]
                    pat = f'{n}::{c}' + (f'({", ".join(binders)})' if ps else '')
                    arms.append(f'        {pat} -> r_{k}_{c}({", ".join(binders)}),')
                    lines = [f'fn r_{k}_{c}({", ".join(f"{b}: {self.lani_type(p)}" for b, p in zip(binders, ps))}) -> i32 {{']
                    lines += [f'    put({ord(ch)});' for ch in c + '(']
                    for p, b in zip(ps, binders):
                        lines += [f'    {self.lani_render(p, b)};', '    put(44);']
                    lines += ['    return put(41);', '}']
                    out.append('\n'.join(lines))
                out.append(f'fn r_{k}(v: {n}) -> i32 {{\n    return match (v) {{\n' + '\n'.join(arms) + '\n    };\n}')
        return '\n\n'.join(out)

    def lani_type(self, t):
        names = {'usize': 'usize', 'i32': 'i32', 'u32': 'u32', 'u64': 'u64', 'u8': 'u8', 'bool': 'bool'}
        if t.name in names:
            return names[t.name]
        if t.name == 'Option':
            return f'core::option::Option<{self.lani_type(t.args[0])}>'
        if t.args:
            return f'{t.name}<{", ".join(self.lani_type(a) for a in t.args)}>'
        return t.name


def targets(ex):
    """(label, lean head, lanius call builder, params, ret) for each tested function."""
    out = []
    for item in ex.order:
        if item.get('machine') is not None:
            continue  # machines(): their state field is private in Lanius
        if item['kind'] == 'fn' and not item['inline'] and item['name'] not in extract.SPEC_FNS:
            name = item['name']
            out.append((name, camel(name), item['params'], item['ret'],
                        lambda args, name=name: f'{name}({", ".join(args)})'))
        elif item['kind'] == 'impl':
            for f in item['fns']:
                label = f'{item["name"]}.{f["name"]}'
                out.append((label, f'{item["name"]}.{camel(f["name"])}', f['params'], f['ret'],
                            lambda args, m=f['name']: f'{args[0]}.{m}({", ".join(args[1:])})'))
    return out


def machines(ex):
    """(name, fields, event type, output type or None) of each machine."""
    out = []
    for item in ex.order:
        if item['kind'] == 'struct' and item.get('machine') is not None:
            step = ex.methods[(item['name'], 'step')]
            out.append((item['name'], [(f, ft) for f, ft, _ in item['fields'] if f != 'state'],
                        step['params'][1][1], step['ret']))
    return out


LEAN_HEAD = '''import {module}
open Lanius.Mini

def hexDigit (n : Nat) : String := String.singleton ("0123456789abcdef".toList.getD n '0')
def hex8 (n : Nat) : String := String.join ((List.range 8).reverse.map (fun i => hexDigit (n / 16 ^ i % 16)))
def hex16 (n : Nat) : String := String.join ((List.range 16).reverse.map (fun i => hexDigit (n / 16 ^ i % 16)))
def hex2 (n : Nat) : String := hexDigit (n / 16 % 16) ++ hexDigit (n % 16)
'''

LANI_TAIL_HEAD = '''
fn put(value: i32) -> i32 {
    let written: bool = std::io_byte::write_stdout_byte(value);
    return 0;
}

fn put_hex(digit: i32) -> i32 {
    if (digit > 9) {
        return put(digit + 87);
    }
    return put(digit + 48);
}
'''


def main():
    run_cache.no_core_dumps()
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--per-fn', type=int, default=20)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--shard', default='0/1',
                        help='i/n: test every n-th function from the i-th, so a large harness splits '
                             'into n smaller ones (laniusc runs out of GPU memory on one big one)')
    parser.add_argument('--laniusc', default=os.path.join(ROOT, 'target/release/laniusc'))
    parser.add_argument('--source', default=SOURCE,
                        help='Lanius source (default: the mini compiler; the Lean side is always the built one)')
    parser.add_argument('--lean-module', default='Lanius.Mini.Compiler',
                        help='the Lean module extracted from --source')
    args = parser.parse_args()
    rng = random.Random(args.seed)
    os.makedirs(os.path.join(args.workdir, 'app'), exist_ok=True)

    source = open(args.source).read()
    ex = extract.Extractor(extract.Parser(extract.lex(source)).items())
    ty = Types(ex)
    ty.need_render, ty.need_lani, ty.need_nil, ty.need_none = set(), set(), set(), set()

    shard, shards = (int(part) for part in args.shard.split('/'))
    chosen = [t for i, t in enumerate(targets(ex)) if i % shards == shard]
    cases = []  # (label, lean expr, lanius case fn)
    exclusive = set()  # struct types passed to a `&mut` parameter
    for label, lean_head, params, ret, call in chosen:
        for _ in range(args.per_fn):
            # A `count` is how many copies a function makes (an array's
            # elements): kept short, as an array's length is.
            values = [('nat', rng.choice([0, 1, 2, 3, 5, 12])) if name == 'count' and pt.value().strip_box().name == 'usize'
                      else ty.gen(pt.value(), rng, 3) for name, pt in params]
            lean_args = [ty.lean(v) for v in values]
            lean_term = f'({" ".join([lean_head] + lean_args)})'
            lets = [f'    let a{i}: {ty.lani_type(pt.value())} = {ty.lani(v, pt.value())};'
                    for i, (v, (_, pt)) in enumerate(zip(values, params))]
            index = len(cases)
            mutated = [i for i, (name, pt) in enumerate(params) if pt.is_mut()]
            if not mutated:
                body = '\n'.join(lets + [f'    return {ty.lani_render(ret, call([f"a{i}" for i in range(len(params))]))};'])
                cases.append((label, ty.lean_render(ret, lean_term), f'fn case{index}() -> i32 {{\n{body}\n}}'))
                continue
            # A receiver is borrowed by the method call; other `&mut`
            # arguments by the harness's exclusive() methods.
            receiver = params[0][0] == 'self'
            names = []
            for i, (name, pt) in enumerate(params):
                if pt.is_mut() and not (receiver and i == 0):
                    exclusive.add(pt.value().name)
                    names.append(f'a{i}.harness_exclusive()')
                else:
                    names.append(f'a{i}')
            shown = ([ret] if ret is not None else []) + [params[i][1].value() for i in mutated]
            fields = ['r' + '.2' * k + ('.1' if k < len(shown) - 1 else '') for k in range(len(shown))]
            lean_text = ' ++ ";" ++ '.join(ty.lean_render(t, f) for t, f in zip(shown, fields))
            lines = list(lets)
            if ret is not None:
                lines.append(f'    let r: {ty.lani_type(ret)} = {call(names)};')
                lines.append(f'    {ty.lani_render(ret, "r")};')
            else:
                lines.append(f'    {call(names)};')
            for k, i in enumerate(mutated):
                if k or ret is not None:
                    lines.append('    put(59);')
                lines.append(f'    {ty.lani_render(params[i][1].value(), f"a{i}")};')
            body = '\n'.join(lines + ['    return 0;'])
            cases.append((label, f'(let r := {lean_term}; {lean_text})', f'fn case{index}() -> i32 {{\n{body}\n}}'))

    # A machine: random fields, then a random event sequence from its start
    # state through `step`; each output, then the state and the fields.
    for name, fields, event, out in (machines(ex) if shard == 0 else []):
        for _ in range(args.per_fn * 4):
            values = [ty.gen(ft, rng, 3) for _, ft in fields]
            events = [ty.gen(event, rng, 3) for _ in range(rng.randint(1, 8))]
            start = extract.snake_case(name) + '_start'
            lean_lets = [f'let m := {camel(start)} {" ".join(ty.lean(v) for v in values)}'.rstrip()]
            lines = [f'    let a{i}: {ty.lani_type(ft)} = {ty.lani(v, ft)};' for i, (v, (_, ft)) in enumerate(zip(values, fields))]
            lines.append(f'    let m: {name} = {start}({", ".join(f"a{i}" for i in range(len(fields)))});')
            shown = []
            for k, e in enumerate(events):
                if out is None:
                    lean_lets.append(f'let m := {name}.step m {ty.lean(e)}')
                    lines.append(f'    m.step({ty.lani(e, event)});')
                    continue
                lean_lets.append(f'let r{k} := {name}.step m {ty.lean(e)}; let m := r{k}.2')
                if shown:
                    lines.append('    put(59);')
                lines.append(f'    {ty.lani_render(out, f"m.step({ty.lani(e, event)})")};')
                shown.append(ty.lean_render(out, f'r{k}.1'))
            for k, (t, lean_term, lani_term) in enumerate([(Ty(f'{name}State'), 'm.state', 'm.state()')] +
                                                          [(ft, f'm.{camel(f)}', f'm.{f}') for f, ft in fields]):
                if shown:
                    lines.append('    put(59);')
                lines.append(f'    {ty.lani_render(t, lani_term)};')
                shown.append(ty.lean_render(t, lean_term))
            index = len(cases)
            body = '\n'.join(lines + ['    return 0;'])
            term = '(' + '; '.join(lean_lets) + '; ' + ' ++ ";" ++ '.join(shown) + ')'
            cases.append((f'{name}.step', term, f'fn case{index}() -> i32 {{\n{body}\n}}'))
        chosen.append((f'{name}.step', None, None, None, None))

    # Lean: one line per case.
    lean = [LEAN_HEAD.format(module=args.lean_module), ty.lean_renderers(), '']
    for index, (_, term, _) in enumerate(cases):
        lean.append(f'def case{index} : String := {term}')
    for chunk in range(0, len(cases), 100):
        indices = range(chunk, min(chunk + 100, len(cases)))
        lean.append('#eval IO.println (String.intercalate "\\n" [' +
                    ', '.join(f's!"{i}:{{case{i}}}"' for i in indices) + '])')
    lean_path = os.path.join(args.workdir, 'Cases.lean')
    open(lean_path, 'w').write('\n'.join(lean) + '\n')

    # Lanius: the compiler source as module app::main, then the harness.
    body = re.sub(r'^module \S+;', 'module app::main;\nimport std::io_byte;\nimport std::process;', source, count=1, flags=re.M)
    tail = [LANI_TAIL_HEAD]
    for name in sorted(exclusive):
        tail.append(f'impl {name} {{\n    fn harness_exclusive(&mut self) -> &mut {name} {{\n        return self;\n    }}\n}}')
    for t in sorted(ty.need_nil, key=repr):
        tail.append(f'fn nil_{key(t)}() -> List<{ty.lani_type(t)}> {{\n    return empty();\n}}')
    for t in sorted(ty.need_none, key=repr):
        tail.append(f'fn none_{key(t)}() -> core::option::Option<{ty.lani_type(t)}> {{\n    return None;\n}}')
    tail.append(ty.lani_renderers())
    for _, _, fn in cases:
        tail.append(fn)
    main_lines = ['fn main() -> i32 {', '    let start: i32 = std::process::argc() - 1;']
    for index in range(len(cases)):
        digits = ' '.join(f'put({ord(c)});' for c in f'{index}:')
        main_lines.append(f'    if (start <= {index}) {{ {digits} case{index}(); put(10); }}')
    main_lines += ['    return 0;', '}']
    tail.append('\n'.join(main_lines))
    lani_path = os.path.join(args.workdir, 'app/main.lani')
    open(lani_path, 'w').write(body + '\n'.join(tail) + '\n')

    began = time.time()
    lean_out = run_cache.run_lean(lean_path)
    if lean_out.returncode != 0:
        print(lean_out.stdout[-3000:], lean_out.stderr[-3000:], file=sys.stderr)
        return 1
    expected = dict(line.split(':', 1) for line in lean_out.stdout.splitlines() if ':' in line)

    lean_s = time.time() - began
    binary = os.path.join(args.workdir, 'cases')
    began = time.time()
    built = subprocess.run([HEAVY, '-t', '20', args.laniusc, '--stdlib-root', os.path.join(ROOT, 'stdlib'),
                            '-o', binary, lani_path], capture_output=True, text=True)
    if built.returncode != 0:
        print(built.stdout[-3000:], built.stderr[-3000:], file=sys.stderr)
        return 1

    build_s = time.time() - began
    began = time.time()
    actual, panicked, start, codes = {}, [], 0, {}
    while start < len(cases):
        run = subprocess.run([binary] + ['x'] * start, capture_output=True, timeout=120)
        lines = run.stdout.decode('latin-1').split('\n')
        complete = lines[:-1]  # the last piece has no newline
        for line in complete:
            index, text = line.split(':', 1)
            actual[index] = text
        if run.returncode == 0 and len(complete) == len(cases) - start:
            break
        failed = start + len(complete)
        panicked.append(failed)
        codes[failed] = run.returncode
        start = failed + 1

    print(f'time: lean {lean_s:.0f} s, laniusc {build_s:.0f} s, {len(panicked) + 1} native runs {time.time() - began:.0f} s', file=sys.stderr)
    mismatches = [(i, cases[i][0]) for i in range(len(cases))
                  if str(i) in actual and actual[str(i)] != expected.get(str(i))]
    for i, label in mismatches[:10]:
        print(f'case {i} ({label}):\n  lean   {expected.get(str(i))}\n  lanius {actual[str(i)]}')
    labels = sorted({label for label, _, _, _, _ in chosen})
    by_label = {}
    for i in panicked:
        why = {-11: 'stack overflow', -4: 'panic', -5: 'panic'}.get(codes[i], f'exit {codes[i]}')
        label = f'{cases[i][0]} {why}'
        by_label[label] = by_label.get(label, 0) + 1
    panics = ', '.join(f'{label}: {n}' for label, n in sorted(by_label.items()))
    print(f'{len(labels)} functions, {len(cases)} cases, {len(panicked)} did not return '
          f'({panics or "none"}), {len(mismatches)} mismatches')
    return 1 if mismatches else 0


if __name__ == '__main__':
    sys.exit(main())
