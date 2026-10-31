#!/usr/bin/env python3
"""The verified compiler as an oracle for laniusc on the stdlib (roadmap step 12).

    python3 -I formal/tools/stdlib_oracle.py WORKDIR [--modules core::cmp,core::mem,..] [--calls K] [--seed S] [--laniusc PATH]

Run from the repository root. The fuzzed half of step 12 is
oracle_difftest.py; this is the stdlib half. The stdlib files are read as
they are, never edited.

1. Every top-level `pub fn` of the stdlib modules (all of them, or those
   named by --modules), and every method of a trait impl for a scalar type
   (`pub impl Ord<i32> for i32 { pub fn lt(..) }`), is a target. A target is
   testable when its parameter and result types, after the module's type
   aliases and with every type parameter at i32, are scalars the front pass
   has (i32, bool, u8, u16, u32, u64, usize, isize, i8, i16, i64, char, f32,
   f64) or `core::option::Option` of one; others are counted by the type
   that stops them. A float goes in and out as its bit pattern (FLOATS).
2. Each testable target gets a program of its own: a first file, the module
   app::main, holding one wrapper `w` that takes scalar arguments (an
   Option as a flag and a payload), calls the target and returns an i32 (a
   bool as 0 or 1, a 64-bit result as its low or high 32 bits, an Option as
   its flag or payload). A trait method is called through a generic helper
   `T::m(..)`, the way the stdlib's own generic code calls it. The program's
   other files are the target's module and the modules it reaches by import
   or path, read from stdlib/ as written.
3. laniusc parses each stdlib file once, with its import lines blanked, and
   the wrappers in batches of many, its tree of a batch split back into the
   wrappers'; the verified validator checks every tree (a rejected one is
   parsed again from laniusc's captures of the whole program). Trees and
   builds are cached (run_cache.py). Then the compiled runAll reads each
   program with `frontEndFiles` and compiles it with `compileSource`.
4. Each compiled image runs natively on K argument tuples, each call in a
   forked child whose stdout and stderr are pipes (a trap or a two-second
   timeout is a result, not a crash). The wrappers that compiled are also
   compiled by laniusc in one harness binary per chunk, which ends each
   call's output on both streams with a frame marker (FRAME), the result
   after it on stdout; the two must agree on the result and on the bytes
   written to each stream, and a call that traps natively must stop the
   laniusc binary too, after the same output (it is then run again from
   the next call).

The front end gives no reason for a rejection, so for each target it does
not read, WORKDIR/unread.txt lists the constructs, in the target or in the
stdlib functions it calls, that the front end is known not to read; a
target with none of them is listed as "no known cause". Prints a summary;
exits nonzero on any disagreement.
"""

import argparse
import ctypes
import json
import mmap
import os
import random
import re
import select
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frontend_difftest as front  # noqa: E402
import oracle_difftest as oracle  # noqa: E402
import run_cache  # noqa: E402

STDLIB = 'stdlib'
HEAVY = 'target/claude-work/bin/heavy'
SCALARS = ('i32', 'bool', 'u8', 'u16', 'u32', 'u64', 'usize', 'isize', 'i8', 'i16', 'i64', 'char', 'f32', 'f64')
WIDE = ('u64', 'usize', 'isize', 'i64')
# F9: a float argument is passed as its bit pattern in the slot (an f32 one
# zero-extended), and a float result is the wrapper's own result, read as its
# bits (an f64 in two halves, as a 64-bit integer is). laniusc's harness
# makes the argument with core::f32::from_bits and reads the result with
# to_bits; inside a struct or enum result a float leaf is read by to_bits in
# the wrapper.
FLOATS = ('f32', 'f64')


# ---------------------------------------------------------------- scanning

def strip_comments(text):
    """The text with // comments blanked (string and char literals kept)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            j = n if j < 0 else j
            out.append(' ' * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return ''.join(out)


def matching(text, i, open_c, close_c):
    """The index just past the bracket that closes the one at text[i]."""
    depth = 0
    while i < len(text):
        if text[i] == open_c:
            depth += 1
        elif text[i] == close_c:
            depth -= 1
            if depth == 0:
                return i + 1
        else:
            j = skip_literal(text, i)
            if j is not None:
                i = j
                continue
        i += 1
    raise ValueError('unbalanced')


def split_top(text, sep=','):
    """text split at sep outside <>, () and []."""
    parts, depth, cur = [], 0, []
    for c in text:
        if c in '<([':
            depth += 1
        elif c in '>)]':
            depth -= 1
        if c == sep and depth == 0:
            parts.append(''.join(cur))
            cur = []
        else:
            cur.append(c)
    if ''.join(cur).strip():
        parts.append(''.join(cur))
    return [p.strip() for p in parts]


def norm(t):
    t = re.sub(r'\s+', ' ', t.strip())
    return re.sub(r'\s*([<>,:])\s*', lambda m: m.group(1) + (' ' if m.group(1) == ',' else ''), t)


FN_HEAD = re.compile(r'(pub\s+)?(extern\s+(?:"[^"]*"\s+)?)?fn\s+(\w+)\s*(<[^(]*?>)?\s*\(')
CHAR = re.compile(r"'(\\.|[^'\\])'")


def skip_literal(text, i):
    """The index past a string or char literal at text[i], or None."""
    if text[i] == '"':
        j = i + 1
        while j < len(text) and text[j] != '"':
            j += 2 if text[j] == '\\' else 1
        return j + 1
    if text[i] == "'":
        m = CHAR.match(text, i)
        if m:
            return m.end()
    return None


def parse_fn(clean, start):
    """The fn whose `fn` keyword region starts at start: (fields, end)."""
    m = FN_HEAD.match(clean, start)
    name = m.group(3)
    generics = [g.split(':')[0].strip() for g in split_top(m.group(4)[1:-1])] if m.group(4) else []
    lp = m.end() - 1
    rp = matching(clean, lp, '(', ')')
    params = []
    for p in split_top(clean[lp + 1:rp - 1]):
        if ':' in p:
            pname, ptype = p.split(':', 1)
            params.append((pname.strip(), norm(ptype)))
        else:
            params.append((p.strip(), None))  # self
    rest = clean[rp:]
    body_at = None
    semi = None
    k = rp
    while k < len(clean):
        if clean[k] == '{':
            body_at = k
            break
        if clean[k] == ';':
            semi = k
            break
        k += 1
    header = clean[rp:body_at if body_at is not None else semi]
    ret = 'unit'
    where = ''
    hm = re.match(r'\s*->\s*(.*?)\s*(where\b.*)?$', header, re.S)
    if hm:
        ret = norm(hm.group(1))
        where = hm.group(2) or ''
    elif 'where' in header:
        where = header[header.index('where'):]
    if body_at is None:
        return dict(name=name, generics=generics, params=params, ret=ret, where=where, body=None,
                    extern=True, pub=bool(m.group(1)), start=start), semi + 1
    end = matching(clean, body_at, '{', '}')
    return dict(name=name, generics=generics, params=params, ret=ret, where=where.strip(),
                body=clean[body_at:end], extern=bool(m.group(2)), pub=bool(m.group(1)), start=start), end


class Module:
    def __init__(self, path):
        self.path = path
        self.text = open(path).read()
        clean = strip_comments(self.text)
        m = re.search(r'^\s*module\s+([\w:]+)\s*;', clean, re.M)
        self.name = m.group(1) if m else None
        self.imports = re.findall(r'^\s*import\s+([\w:]+)\s*;', clean, re.M)
        self.aliases = {a: norm(t) for a, t in re.findall(r'^\s*(?:pub\s+)?type\s+(\w+)\s*=\s*([^;]+);', clean, re.M)}
        self.traits = set(re.findall(r'^\s*(?:pub\s+)?trait\s+(\w+)', clean, re.M))
        self.types = set(re.findall(r'^\s*(?:pub\s+)?(?:struct|enum)\s+(\w+)', clean, re.M))
        # Non-generic structs: their fields' names and types, in order.
        self.structs = {name: [tuple(x.strip() for x in f.split(':', 1)) for f in body.split(',') if ':' in f]
                        for name, body in re.findall(r'^\s*(?:pub\s+)?struct\s+(\w+)\s*\{([^}]*)\}', clean, re.M)}
        # Enums: their type parameters and variants, each with its payload types.
        self.enums = {}
        for em in re.finditer(r'^\s*(?:pub\s+)?enum\s+(\w+)\s*(?:<([^>{]*)>)?\s*\{', clean, re.M):
            body = clean[em.end():matching(clean, em.end() - 1, '{', '}') - 1]
            variants = []
            for v in split_top(body):
                vm = re.match(r'^(\w+)\s*(?:\((.*)\))?$', v, re.S)
                if not vm:
                    variants = None
                    break
                variants.append((vm.group(1), [norm(x) for x in split_top(vm.group(2))] if vm.group(2) else []))
            if variants:
                self.enums[em.group(1)] = ([g.strip() for g in em.group(2).split(',')] if em.group(2) else [], variants)
        self.fns = {}           # name -> fn (top level)
        self.trait_methods = []  # (trait text, impl type, fn)
        self.paths = set(re.findall(r'\b([a-z_][a-z0-9_]*(?:::[a-z_][a-z0-9_]*)+)::', clean))
        i, depth, n = 0, 0, len(clean)
        while i < n:
            c = clean[i]
            j = skip_literal(clean, i)
            if j is not None:
                i = j
                continue
            if depth == 0 and (i == 0 or not (clean[i - 1].isalnum() or clean[i - 1] == '_')):
                if FN_HEAD.match(clean, i):
                    fn, i = parse_fn(clean, i)
                    fn['module'] = self.name
                    self.fns.setdefault(fn['name'], fn)
                    continue
                im = re.match(r'(pub\s+)?impl\s+([\w:]+(?:<[^{]*?>)?)\s+for\s+(\w+)\s*\{', clean[i:])
                if im:
                    lb = i + im.end() - 1
                    end = matching(clean, lb, '{', '}')
                    inner = clean[lb + 1:end - 1]
                    j = 0
                    while j < len(inner):
                        lit = skip_literal(inner, j)
                        if lit is not None:
                            j = lit
                            continue
                        if (j == 0 or not (inner[j - 1].isalnum() or inner[j - 1] == '_')) and FN_HEAD.match(inner, j):
                            fn, j = parse_fn(inner, j)
                            fn['module'] = self.name
                            self.trait_methods.append((norm(im.group(2)), im.group(3), fn))
                            continue
                        j += 1
                    i = end
                    continue
            if c == '{':
                depth += 1
            elif c == '}':
                depth -= 1
            i += 1


def load_modules():
    mods = {}
    for root, _, names in os.walk(STDLIB):
        for name in sorted(names):
            if name.endswith('.lani'):
                m = Module(os.path.join(root, name))
                if m.name and m.name not in mods:
                    mods[m.name] = m
    return mods


def closure(mods, name):
    """The module and the stdlib modules it reaches by import or path, in order."""
    seen, todo = [], [name]
    while todo:
        m = todo.pop(0)
        if m in seen or m not in mods:
            continue
        seen.append(m)
        for dep in mods[m].imports + sorted(mods[m].paths):
            if dep in mods and dep not in seen:
                todo.append(dep)
    return seen


def resolve(mods, module, t, subst):
    """t with type parameters substituted and aliases expanded, or None."""
    t = norm(t)
    if t in subst:
        return subst[t]
    if t in SCALARS or t in ('unit', '!'):
        return t
    m = re.match(r'^\[\s*(.+?)\s*;\s*(\d+)\s*\]$', t)
    if m:
        # An array of scalars, by its written type `[T; N]`: its leaves are
        # its elements.
        inner = resolve(mods, module, m.group(1), subst)
        return f'[{inner}; {int(m.group(2))}]' if inner in SCALARS and int(m.group(2)) > 0 else None
    m = re.match(r'^(?:core::option::)?Option<(.*)>$', t)
    if m:
        inner = resolve(mods, module, m.group(1), subst)
        if inner in SCALARS:
            return f'Option<{inner}>'
        return resolve_enum(mods, 'core::option', 'Option', [inner]) if inner else None
    m = re.match(r'^([\w:]+)<(.*)>$', t)
    base, targs = (m.group(1), split_top(m.group(2))) if m else (t, [])
    path, name = base.rsplit('::', 1) if '::' in base else (module, base)
    if path not in mods:
        return None
    if name in mods[path].aliases and not targs:
        return resolve(mods, path, mods[path].aliases[name], {})
    if name in mods[path].structs and not targs:
        return resolve_struct(mods, path, name)
    if name in mods[path].enums:
        args = [resolve(mods, module, a, subst) for a in targs]
        return resolve_enum(mods, path, name, args) if all(args) else None
    return None


# A struct a target passes or returns: its fields, each a scalar or such a
# struct, by its resolved name `struct:m::S`.
STRUCTS = {}


def resolve_struct(mods, module, name):
    key = f'struct:{module}::{name}'
    if key not in STRUCTS:
        STRUCTS[key] = None  # a struct that contains itself is not testable
        fields = [(f, resolve(mods, module, ty, {})) for f, ty in mods[module].structs[name]]
        if fields and all(leaf_type(ty) for _, ty in fields):
            STRUCTS[key] = fields
    return key if STRUCTS[key] else None


# An enum a target returns: its variants, each with its payload types (each
# a scalar or a struct), by its resolved name `enum:` and the type as written.
ENUMS = {}


def resolve_enum(mods, module, name, args):
    params, variants = mods[module].enums[name]
    if len(params) != len(args):
        return None
    key = f'enum:{module}::{name}' + (f'<{", ".join(written(a) for a in args)}>' if args else '')
    if key not in ENUMS:
        ENUMS[key] = None
        subst = dict(zip(params, args))
        vs = [(v, [resolve(mods, module, p, subst) for p in ps]) for v, ps in variants]
        if all(leaf_type(ty) for _, ps in vs for ty in ps):
            ENUMS[key] = (f'{module}::{name}', vs)
    return key if ENUMS[key] else None


def flat_enum(ty):
    """An enum none of whose variants has a payload: a leaf, read by its tag."""
    return ty.startswith('enum:') and bool(ENUMS.get(ty)) and all(not ps for _, ps in ENUMS[ty][1])


def leaf_type(ty):
    """A type a struct field or a variant payload may have."""
    return bool(ty) and (ty in SCALARS or (ty.startswith('struct:') and bool(STRUCTS.get(ty))) or flat_enum(ty))


def variant_leaves(ps):
    """A variant's payload leaves: (payload index, field path, scalar type)."""
    return [(j, path, lty) for j, p in enumerate(ps) for path, lty in leaves(p)]


def array_parts(ty):
    """An array type's element type and length, or None."""
    m = re.match(r'^\[(.+); (\d+)\]$', ty or '')
    return (m.group(1), int(m.group(2))) if m else None


def leaves(ty, path=''):
    """A type's scalar leaves: (field path, scalar type)."""
    if array_parts(ty):
        inner, n = array_parts(ty)
        return [(f'{path}[{i}]', inner) for i in range(n)]
    if ty.startswith('struct:'):
        return [leaf for f, fty in STRUCTS[ty] for leaf in leaves(fty, f'{path}.{f}')]
    return [(path, ty)]


def type_text(ty):
    for prefix in ('struct:', 'enum:'):
        if ty.startswith(prefix):
            return ty[len(prefix):]
    return ty


def struct_value(ty, names):
    """The literal of a struct type from its leaves' wrapper parameters."""
    if not ty.startswith('struct:'):
        return next(names)
    return type_text(ty) + ' { ' + ', '.join(f'{f}: {struct_value(fty, names)}' for f, fty in STRUCTS[ty]) + ' }'


def struct_modules(ty):
    if ty.startswith('enum:'):
        home, vs = ENUMS[ty]
        return {home.rsplit('::', 1)[0]} | {m for _, ps in vs for p in ps for m in struct_modules(p)}
    if not ty.startswith('struct:'):
        return set()
    return {type_text(ty).rsplit('::', 1)[0]} | {m for _, fty in STRUCTS[ty] for m in struct_modules(fty)}


def testable(t):
    if t in SCALARS:
        return True
    if (t or '').startswith('struct:') or array_parts(t):
        return all(lty in SCALARS for _, lty in leaves(t))
    m = re.match(r'^Option<(.*)>$', t or '')
    return bool(m) and m.group(1) in SCALARS


# ---------------------------------------------------------------- targets

class Target:
    def __init__(self, label, module, fn, trait=None, impl_type=None):
        self.label, self.module, self.fn = label, module, fn
        self.trait, self.impl_type = trait, impl_type
        self.params, self.ret, self.why = None, None, None
        self.targs, self.decls = None, []


def targets(mods, wanted):
    out = []
    for name in sorted(mods):
        if wanted and name not in wanted:
            continue
        m = mods[name]
        for fn in m.fns.values():
            if fn['pub']:
                out.append(Target(f'{name}::{fn["name"]}', name, fn))
        for trait, ty, fn in m.trait_methods:
            if any(p[1] is None for p in fn['params']):
                continue
            out.append(Target(f'{name}::<{ty} as {trait}>::{fn["name"]}', name, fn, trait, ty))
    # core::mem::size_of at more than i32: a struct of the wrapper's and u8.
    if 'core::mem' in mods and 'size_of' in mods['core::mem'].fns and (not wanted or 'core::mem' in wanted):
        for ty, decls in (('OracleSizeW', ['struct OracleSizeW { a: i32, b: bool }']), ('u8', []), ('bool', [])):
            t = Target(f'core::mem::size_of<{ty}>', 'core::mem', mods['core::mem'].fns['size_of'])
            t.targs, t.decls, t.params, t.ret = ty, decls, [], 'usize'
            out.append(t)
    for t in out:
        fn = t.fn
        if t.targs:
            continue
        if fn['extern'] or fn['body'] is None:
            t.why = 'extern'
            continue
        if any(p[1] is None for p in fn['params']):
            t.why = 'self'
            continue
        subst = {g: 'i32' for g in fn['generics']}
        params = [(p, resolve(mods, t.module, ty, subst)) for p, ty in fn['params']]
        ret = resolve(mods, t.module, fn['ret'], subst)
        bad = [ty for (p, ty), (_, orig) in zip(params, fn['params']) if not testable(ty)]
        if ret in ('unit', '!'):
            t.why = 'result ' + fn['ret']
        elif not (testable(ret) or (ret or '').startswith('enum:')):
            t.why = 'type ' + fn['ret']
        elif bad or any(not testable(ty) for _, ty in params):
            t.why = 'type ' + next(orig for (p, ty), (_, orig) in zip(params, fn['params']) if not testable(ty))
        elif sum(arg_words(ty) for _, ty in params) > 6:
            t.why = 'more than six argument words'
        else:
            t.params, t.ret = params, ret
    return out


def arg_words(ty):
    """How many wrapper parameters an argument of the type takes."""
    if ty.startswith('Option<'):
        return 2
    return len(leaves(ty))


def results_of(ret):
    """The parts of a result the wrapper can return, one wrapper each."""
    if ret.startswith('struct:') or array_parts(ret):
        return [f'f{j}:{sub}' for j, (_, ty) in enumerate(leaves(ret)) for sub in results_of(ty)]
    if flat_enum(ret):
        return ['tag']
    if ret.startswith('enum:'):
        return ['tag'] + [f'e{i}_{n}:{sub}' for i, (_, ps) in enumerate(ENUMS[ret][1])
                          for n, (_, _, lty) in enumerate(variant_leaves(ps)) for sub in results_of(lty)]
    if ret in WIDE or ret == 'f64':
        return ['lo', 'hi']
    if ret.startswith('Option<'):
        return ['tag', 'val']
    return ['all']


def trait_home(mods, t):
    """The trait's qualified name: module::Trait."""
    tname = re.match(r'[\w:]+', t.trait).group(0)
    if '::' in tname:
        return tname
    home = t.module if tname in mods[t.module].traits else next(
        (n for n in mods if tname in mods[n].traits), t.module)
    return f'{home}::{tname}'


def written(ty):
    """A resolved type as the wrapper writes it."""
    if ty.startswith('Option<'):
        return f'core::option::Option<{ty[7:-1]}>'
    return type_text(ty)


def variant_pattern(home, v, ps, bind):
    """A match pattern for variant v, binding payload `bind` as x."""
    if not ps:
        return f'{home}::{v}'
    return f'{home}::{v}(' + ', '.join('x' if j == bind else '_' for j in range(len(ps))) + ')'


def scalar_lines(base, part):
    """The wrapper's statements that return part of its result r as an i32."""
    lines = []
    if base.startswith('enum:'):
        home, vs = ENUMS[base]
        arms = [f'{variant_pattern(home, v, ps, None)} -> {i}' for i, (v, ps) in enumerate(vs)]
        return [f'    let t: i32 = match (r) {{ {", ".join(arms)} }};', '    return t;']
    if base in FLOATS:
        bits = f'core::{base}::to_bits(r)'
        if part == 'hi':
            return [f'    let b: u64 = {bits};', '    let high: u64 = 4294967296;', '    let top: u64 = b / high;',
                    '    return (top as i32);']
        return [f'    return ({bits} as i32);']
    if part == 'all':
        if base == 'bool':
            lines += ['    if (r) {', '        return 1;', '    }', '    return 0;']
        else:
            lines.append(f'    return {"r" if base == "i32" else "(r as i32)"};')
    elif part in ('lo', 'hi'):
        if part == 'lo':
            lines.append('    return (r as i32);')
        else:
            lines += [f'    let high: {base} = (65536 as {base}) * (65536 as {base});',
                      '    let top: ' + base + ' = r / high;', '    return (top as i32);']
    else:
        inner = base[7:-1]
        if part == 'tag':
            lines.append('    let t: i32 = match (r) { Some(x) -> 1, None -> 0 };')
        else:
            conv = 'x' if inner == 'i32' else f'(core::{inner}::to_bits(x) as i32)' if inner in FLOATS \
                else '(x as i32)'
            if inner == 'bool':
                lines.append('    let t: i32 = match (r) { Some(x) -> oracle_flag(x), None -> 0 };')
            else:
                lines.append(f'    let t: i32 = match (r) {{ Some(x) -> {conv}, None -> 0 }};')
        lines.append('    return t;')
    return lines


def wrapper_text(mods, t, part):
    """The first file of a target's program, and the wrapper's scalar parameter types."""
    fn = t.fn
    lines = ['module app::main;', '']
    imports = {t.module, 'core::option'} if any(ty.startswith('Option<') for _, ty in t.params) or \
        t.ret.startswith('Option<') else {t.module}
    if t.ret not in FLOATS:
        # a float leaf of a struct, enum or Option result is read by to_bits
        rleaves = [lty for _, ps in ENUMS[t.ret][1] for _, _, lty in variant_leaves(ps)] \
            if t.ret.startswith('enum:') else [lty for _, lty in leaves(t.ret)] \
            if t.ret.startswith('struct:') else [t.ret[7:-1]] if t.ret.startswith('Option<') else []
        imports |= {f'core::{f}' for f in FLOATS if f in rleaves}
    if t.trait:
        imports.add(trait_home(mods, t).rsplit('::', 1)[0])
    for dep in sorted(imports | {m for ty in [t.ret] + [ty for _, ty in t.params] for m in struct_modules(ty)}):
        lines.append(f'import {dep};')
    lines.append('')
    lines += t.decls + ([''] if t.decls else [])
    wparams, setup, args = [], [], []
    for k, (p, ty) in enumerate(t.params):
        if ty.startswith('Option<'):
            inner = ty[7:-1]
            wparams += [(f'a{k}s', 'bool'), (f'a{k}', inner)]
            setup += [f'    let o{k}: core::option::Option<{inner}> = None();',
                      f'    if (a{k}s) {{', f'        o{k} = Some(a{k});', '    }']
            args.append(f'o{k}')
        elif ty.startswith('struct:'):
            names = [f'a{k}_{j}' for j in range(len(leaves(ty)))]
            wparams += [(n, lty) for n, (_, lty) in zip(names, leaves(ty))]
            setup.append(f'    let s{k}: {type_text(ty)} = {struct_value(ty, iter(names))};')
            args.append(f's{k}')
        elif array_parts(ty):
            names = [f'a{k}_{j}' for j in range(len(leaves(ty)))]
            wparams += [(n, lty) for n, (_, lty) in zip(names, leaves(ty))]
            setup.append(f'    let s{k}: {ty} = [{", ".join(names)}];')
            args.append(f's{k}')
        else:
            wparams.append((f'a{k}', ty))
            args.append(f'a{k}')
    ret = t.ret if not t.ret.startswith('Option<') else f'core::option::Option<{t.ret[7:-1]}>'
    ret = type_text(ret)
    if t.trait:
        # A generic helper calls the method as T::m, as the stdlib's generic code does.
        itype = type_text(resolve(mods, t.module, t.impl_type, {}))
        tparams = ', '.join(f'{p}: {"T" if ty == t.impl_type else written(rty)}'
                            for (p, ty), (_, rty) in zip(fn['params'], t.params))
        hret = 'T' if fn['ret'] == t.impl_type else written(t.ret)
        trait = re.sub(rf'\b{t.impl_type}\b', 'T', t.trait)
        if '::' not in re.match(r'[\w:]+', t.trait).group(0):
            trait = f'{trait_home(mods, t).rsplit("::", 1)[0]}::{trait}'
        lines += [f'fn oracle_helper<T>({tparams}) -> {hret} where T: {trait} {{',
                  f'    return T::{fn["name"]}({", ".join(p for p, _ in fn["params"])});', '}', '']
        call = f'oracle_helper<{itype}>({", ".join(args)})'
    else:
        targs = f'<{t.targs or ", ".join("i32" for _ in fn["generics"])}>' if fn['generics'] else ''
        call = f'{t.module}::{fn["name"]}{targs}({", ".join(args)})'
    sig = ', '.join(f'{p}: {ty}' for p, ty in wparams)
    if t.ret in FLOATS:
        # The float itself is the result; its bits are what the image returns.
        lines += [f'fn w({sig}) -> {t.ret} {{'] + setup + [f'    let r: {t.ret} = {call};', '    return r;', '}']
        return '\n'.join(lines) + '\n', wparams
    lines.append(f'fn w({sig}) -> i32 {{')
    lines += setup
    base = t.ret
    if t.ret.startswith('enum:'):
        # The tag (the variant's index) or one leaf of one variant's payload,
        # read by a match and returned as a scalar result is.
        home, vs = ENUMS[t.ret]
        lines.append(f'    let r: {ret} = {call};')
        if part == 'tag':
            arms = [f'{variant_pattern(home, v, ps, None)} -> {i}' for i, (v, ps) in enumerate(vs)]
            helper = []
        else:
            at, part = part[1:].split(':')
            i, n = (int(x) for x in at.split('_'))
            j, path, base = variant_leaves(vs[i][1])[n]
            arms = [f'{variant_pattern(home, v, ps, j if k == i else None)} -> '
                    f'{f"oracle_part(x{path})" if k == i else "0"}' for k, (v, ps) in enumerate(vs)]
            helper = ['', f'fn oracle_part(r: {type_text(base)}) -> i32 {{'] + scalar_lines(base, part) + ['}']
        lines.append(f'    let t: i32 = match (r) {{ {", ".join(arms)} }};')
        lines += ['    return t;', '}'] + helper
        return '\n'.join(lines) + '\n', wparams
    if part.startswith('f'):
        # One scalar leaf of a struct result, returned as a scalar result is.
        j, part = part[1:].split(':')
        path, base = leaves(t.ret)[int(j)]
        lines.append(f'    let r0: {ret} = {call};')
        lines.append(f'    let r: {type_text(base)} = r0{path};')
    else:
        lines.append(f'    let r: {ret} = {call};')
    lines += scalar_lines(base, part)
    lines.append('}')
    if t.ret == 'Option<bool>' and part == 'val':
        lines += ['', 'fn oracle_flag(b: bool) -> i32 {', '    if (b) {', '        return 1;', '    }', '    return 0;', '}']
    return '\n'.join(lines) + '\n', wparams


# ---------------------------------------------------------------- laniusc's trees

RUN_ALL = 'formal/.lake/build/bin/runAll'


def capture_tree(laniusc, lani_path, workdir, index):
    """The parser's tree at one capture index, or None."""
    cap = os.path.join(workdir, 'cap')
    env = dict(os.environ, LANIUS_DEBUG_CAPTURE_PASS='parser/tree/parent_parallel', LANIUS_DEBUG_CAPTURE_DIR=cap,
               LANIUS_DEBUG_CAPTURE_INDEX=str(index))
    shutil.rmtree(cap, ignore_errors=True)
    subprocess.run([HEAVY, '-t', '10', laniusc, '--stdlib-root', STDLIB, '-o', os.path.join(workdir, 'a.out'),
                    lani_path], env=env, capture_output=True, text=True)
    status = os.path.join(cap, 'post', '002_tree_count_status.bin')
    if not os.path.exists(status):
        return None
    count = front.words(status)[5]
    if count == 0:
        return None
    prods = front.words(os.path.join(cap, 'post', '006_node_kind.bin'))[:count]
    parents = front.words(os.path.join(cap, 'post', '007_parent.bin'))[:count]
    return prods, parents


def accepted(lani_path, tree, workdir):
    """Whether the verified validator accepts tree as lani_path's parse tree."""
    if not os.path.exists(RUN_ALL):
        env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
        with run_cache.lean_lock():
            subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                            'lake', 'build', 'runAll'], cwd='formal', env=env, capture_output=True, check=True)
    base = os.path.join(workdir, 'candidate')
    shutil.copy(lani_path, base + '.lani')
    open(base + '.prods', 'w').write(' '.join(map(str, tree[0])))
    open(base + '.parents', 'w').write(' '.join(map(str, tree[1])))
    manifest = os.path.join(workdir, 'candidate.txt')
    open(manifest, 'w').write(f'validate c {base}\n')
    out = subprocess.run([RUN_ALL, manifest], capture_output=True, text=True).stdout
    return out.strip() == 'c ok'


def parse_tree(laniusc, lani_path, workdir):
    """laniusc's parse tree of one file: its node kinds and parents, or None.

    laniusc parses the modules a file imports first, as one or more packs,
    then the file (a later capture, for generic code, is laniusc's text after
    its own monomorphization). The captures are tried in order (the first
    when the file has no imports, from the second when it has) and the first
    tree the verified validator accepts for the file is its tree; when none
    is, the first nonempty one is returned for the caller to reject."""
    has_imports = bool(re.search(r'^\s*import\s', strip_comments(open(lani_path).read()), re.M))
    first = None
    for index in ([1, 2, 3, 0] if has_imports else [0]):
        tree = capture_tree(laniusc, lani_path, workdir, index)
        if tree is None:
            continue
        if first is None:
            first = tree
        if not has_imports or accepted(lani_path, tree, workdir):
            return tree
    return first


NONE = 4294967295

# Put between the wrappers of a batch: an item no wrapper has the shape of.
MARK = 'fn oracle_mark(a: u8, b: u8, c: u8, d: u8, e: u8) -> u8 {\n    return a;\n}\n'


def item_trees(prods, parents):
    """A file tree's items, in order, each a list of (prod, parent) with the
    parent relative to the item's first node (None for that node). The tree
    is in preorder: node 0 is the file, then the item_list chain
    (item_list -> item item_list | empty), each item's nodes before the next
    link's."""
    kids = {}
    for i, q in enumerate(parents):
        kids.setdefault(q, []).append(i)
    items, c = [], 1
    while prods[c] == 1:
        nxt = kids[c][-1]
        items.append([(prods[i], None if i == c + 1 else parents[i] - (c + 1)) for i in range(c + 1, nxt)])
        c = nxt
    return items


def file_tree(items):
    """The tree of a file with these items (item_trees' inverse)."""
    prods, parents, up = [0], [NONE], 0
    for item in items:
        link = len(prods)
        prods.append(1)
        parents.append(up)
        base = len(prods)
        for p, q in item:
            prods.append(p)
            parents.append(link if q is None else base + q)
        up = link
    prods.append(2)
    parents.append(up)
    return prods, parents


def parse_wrappers(laniusc, texts, workdir, batch_bytes=1 << 16):
    """laniusc's trees of the wrappers (each `module app::main;`, imports, then
    items), parsed in batches: one file of the module line and each wrapper's
    items after a MARK, whose tree is split back into the wrappers'. The
    caller validates each tree."""
    trees, start = [], 0
    while start < len(texts):
        end, size = start, 0
        while end < len(texts) and (end == start or size + len(texts[end]) < batch_bytes):
            size += len(texts[end])
            end += 1
        bodies, imports = [], []
        for text in texts[start:end]:
            lines = text.split('\n')
            imports.append([line[7:-1].split('::') for line in lines if line.startswith('import ')])
            bodies.append('\n'.join(line for line in lines if not line.startswith(('module ', 'import '))))
        path = os.path.join(workdir, 'batch.lani')
        open(path, 'w').write('module app::main;\n' + ''.join(MARK + b + '\n' for b in bodies))
        prods, parents, _ = front.parse_plain(HEAVY, laniusc, path, workdir)
        items = item_trees(prods, parents)
        mark = items[1]
        groups = []
        for item in items[1:]:
            if item == mark:
                groups.append([])
            else:
                groups[-1].append(item)
        if len(groups) != end - start:
            raise SystemExit(f'batch of {end - start} wrappers split into {len(groups)}')
        for group, paths in zip(groups, imports):
            tree = file_tree([items[0]] + group)
            trees.append(front.splice_imports(*tree, 1, paths) if paths else tree)
        start = end
    return trees


def parse_stdlib_file(laniusc, lani_path, workdir):
    """laniusc's tree of a stdlib file: with its import lines blanked (one
    cached laniusc run), else as parse_tree finds it."""
    try:
        prods, parents, _ = front.parse_with_laniusc(HEAVY, laniusc, lani_path, workdir)
        return prods, parents
    except (SystemExit, OSError, IndexError):
        return parse_tree(laniusc, lani_path, workdir)


def parse_checked(laniusc, base, workdir):
    """Write laniusc's tree of base.lani (parse_stdlib_file), if the verified
    validator accepts it, else from laniusc's whole-program captures; returns
    whether a tree was written."""
    tree = parse_stdlib_file(laniusc, base + '.lani', workdir)
    if tree is None:
        return False
    write_tree(base, tree)
    if validate_all([base], workdir):
        return True
    tree = parse_tree(laniusc, base + '.lani', workdir)
    if tree is not None:
        write_tree(base, tree)
    return tree is not None


def build_run_all():
    """Build runAll (a no-op when it is current)."""
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    with run_cache.lean_lock():
        subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                        'lake', 'build', 'runAll'], cwd='formal', env=env, capture_output=True, check=True)


def validate_all(bases, workdir):
    """The bases whose stored tree the verified validator accepts."""
    manifest = os.path.join(workdir, 'validate.txt')
    open(manifest, 'w').write(''.join(f'validate {i} {b}\n' for i, b in enumerate(bases)))
    out = subprocess.run([RUN_ALL, manifest], capture_output=True, text=True, check=True).stdout
    ok = {int(line.split(' ')[0]) for line in out.split('\n') if line.endswith(' ok')}
    return {b for i, b in enumerate(bases) if i in ok}


def write_tree(base, tree):
    open(base + '.prods', 'w').write(' '.join(map(str, tree[0])))
    open(base + '.parents', 'w').write(' '.join(map(str, tree[1])))


# ---------------------------------------------------------------- native side

ARG_STORES = [bytes([0x48, 0x89, 0x7C, 0x24]), bytes([0x48, 0x89, 0x74, 0x24]), bytes([0x48, 0x89, 0x54, 0x24]),
              bytes([0x48, 0x89, 0x4C, 0x24]), bytes([0x4C, 0x89, 0x44, 0x24]), bytes([0x4C, 0x89, 0x4C, 0x24])]


class Native(oracle.Native):
    """oracle_difftest's stub, with up to six arguments (rdi, rsi, rdx, rcx, r8, r9)."""

    def load(self, entries, image, arity):
        self.code[0:len(image)] = image
        at = len(image)
        stub = bytes([0x41, 0x54, 0x41, 0x55, 0x41, 0x56, 0x41, 0x57])
        stub += bytes([0x49, 0xBC]) + self.heap_base.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBD]) + (1).to_bytes(8, 'little')
        stub += bytes([0x49, 0xBE]) + (self.HEAP - 64).to_bytes(8, 'little')
        stub += bytes([0x4C, 0x8D, 0xBC, 0x24]) + (-oracle.STACK_ROOM & 0xffffffff).to_bytes(4, 'little')
        for k in range(arity):
            stub += ARG_STORES[k] + bytes([(256 - (8 * k + 24)) & 0xff])
        rel = entries[0] - (at + len(stub) + 5)
        stub += b'\xe8' + (rel & 0xffffffff).to_bytes(4, 'little')
        stub += bytes([0x41, 0x5F, 0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0xC3])
        self.code[at:at + len(stub)] = stub
        self.fn = ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * arity))(self.base + at)


def slot(value, ty):
    if ty in ('i32', 'i8', 'i16', 'f32'):
        return value & 0xffffffff
    return value & (2 ** 64 - 1)


def read_all(fd):
    data = b''
    while True:
        chunk = os.read(fd, 1 << 16)
        if not chunk:
            break
        data += chunk
    os.close(fd)
    return data


def read_both(a, b):
    """Everything written to two pipes, read as it comes (so neither fills)."""
    got = {a: b'', b: b''}
    live = [a, b]
    while live:
        ready, _, _ = select.select(live, [], [])
        for fd in ready:
            chunk = os.read(fd, 1 << 16)
            if chunk:
                got[fd] += chunk
            else:
                os.close(fd)
                live.remove(fd)
    return got[a], got[b]


def native_call(native, args, types, high=False):
    """The wrapper's result (its high 32 bits when high), or 'trap' (a signal)
    or 'timeout', and the bytes
    it wrote to stdout and to stderr, from a forked child (both pipes)."""
    r, w = os.pipe()
    out_r, out_w = os.pipe()
    err_r, err_w = os.pipe()
    sys.stdout.flush()
    sys.stderr.flush()
    pid = os.fork()
    if pid == 0:
        os.close(r)
        os.close(out_r)
        os.close(err_r)
        os.dup2(out_w, 1)
        os.dup2(err_w, 2)
        signal.alarm(2)
        native.heap[0:native.HEAP] = bytes(native.HEAP)
        value = native.fn(*[slot(a, t) for a, t in zip(args, types)])
        os.write(w, str(oracle.i32(value >> 32 if high else value)).encode())
        os._exit(0)
    os.close(w)
    os.close(out_w)
    os.close(err_w)
    out, err = read_both(out_r, err_r)
    data = read_all(r)
    _, status = os.waitpid(pid, 0)
    if os.WIFSIGNALED(status):
        return ('timeout' if os.WTERMSIG(status) == signal.SIGALRM else 'trap'), out, err
    return int(data), out, err


# ---------------------------------------------------------------- arguments

SMALL = [0, 1, 2, 3, 5, 7, 10, 31, 32, 63, 64, 100, 255, 256]


SIGNED_BITS = {'i8': 8, 'i16': 16}


# Char arguments: edges of the UTF-8 lengths and the surrogate gap, and the
# escapes; no other control characters (a literal would hold the raw byte).
CHAR_EDGES = [0, 9, 10, 13, 32, 34, 39, 48, 65, 92, 97, 126, 128, 255, 0x7ff, 0x800, 0xd7ff, 0xe000,
              0xfffd, 0xffff, 0x10000, 0x10ffff]


def gen_char(rng):
    if rng.random() < 0.4:
        return rng.choice(CHAR_EDGES)
    while True:
        v = rng.choice([rng.randrange(32, 127), rng.randrange(128, 0x800), rng.randrange(0x800, 0x10000),
                        rng.randrange(0x10000, 0x110000)])
        if not 0xd800 <= v < 0xe000:
            return v


F32_EDGES = [0, 0x80000000, 0x3F800000, 0xBF800000, 0x7F800000, 0xFF800000, 0x7FC00000, 0xFFC00000,
             0x7F800001, 0x7FA00000, 0xFFA00001, 1, 0x80000001, 0x007FFFFF, 0x00800000, 0x7F7FFFFF, 0xFF7FFFFF,
             0x3F000000, 0x3FC00000, 0x40000000, 0x4B000000, 0x4B7FFFFF, 0xCB000001, 0x3EFFFFFF, 0x3F7FFFFF]
F64_EDGES = [0, 1 << 63, 0x3FF0000000000000, 0xBFF0000000000000, 0x7FF0000000000000, 0xFFF0000000000000,
             0x7FF8000000000000, 0xFFF8000000000000, 0x7FF0000000000001, 0x7FF4000000000000,
             0xFFF4000000000001, 1, (1 << 63) | 1, 0x000FFFFFFFFFFFFF, 0x0010000000000000, 0x7FEFFFFFFFFFFFFF,
             0xFFEFFFFFFFFFFFFF, 0x3FE0000000000000, 0x3FF8000000000000, 0x4000000000000000,
             0x4330000000000000, 0x433FFFFFFFFFFFFF, 0xC330000000000001, 0x3FDFFFFFFFFFFFFF,
             0x3FEFFFFFFFFFFFFF]


def gen_float(rng, ty):
    """A float argument's bit pattern: an edge, a value near 1 of either sign,
    an integer-valued one, or random bits."""
    width, frac, bias = (32, 23, 127) if ty == 'f32' else (64, 52, 1023)
    roll = rng.random()
    if roll < 0.35:
        return rng.choice(F32_EDGES if ty == 'f32' else F64_EDGES)
    sign = rng.randrange(2) << (width - 1)
    if roll < 0.6:
        exponent = bias + rng.randrange(-4, 5)
        return sign | exponent << frac | rng.randrange(1 << frac)
    if roll < 0.75:
        exponent = bias + rng.randrange(0, frac + 3)
        unit = frac - min(exponent - bias, frac)
        return sign | exponent << frac | (rng.randrange(1 << frac) >> unit << unit)
    return rng.randrange(1 << width)


def gen_arg(rng, ty):
    if ty in FLOATS:
        return gen_float(rng, ty)
    if ty == 'bool':
        return int(rng.random() < 0.5)
    if ty == 'char':
        return gen_char(rng)
    if rng.random() < 0.3:
        v = rng.choice([v for v in SMALL if (ty not in oracle.UINT_BITS or v < 2 ** oracle.UINT_BITS[ty])
                        and (ty not in SIGNED_BITS or v < 2 ** (SIGNED_BITS[ty] - 1))])
        if ty in ('i32', 'isize') + tuple(SIGNED_BITS) and rng.random() < 0.4:
            v = -v
        return v
    if ty == 'i32':
        return rng.choice(oracle.I32_EDGES) if rng.random() < 0.4 else rng.randint(-2 ** 31, 2 ** 31 - 1)
    if ty in ('isize', 'i64'):
        return rng.choice(oracle.ISIZE_EDGES) if rng.random() < 0.4 else rng.randint(-2 ** 63, 2 ** 63 - 1)
    if ty in SIGNED_BITS:
        half = 2 ** (SIGNED_BITS[ty] - 1)
        return rng.choice([0, 1, -1, half - 1, -half, -half + 1]) if rng.random() < 0.4 else rng.randrange(-half, half)
    bits = oracle.UINT_BITS[ty]
    if rng.random() < 0.3:
        return rng.choice([0, 1, 2 ** bits - 1, 2 ** (bits - 1), 2 ** (bits - 1) - 1])
    return rng.randrange(1 << bits)


CHAR_ESCAPES = {0: '\\0', 9: '\\t', 10: '\\n', 13: '\\r', 39: "\\'", 92: '\\\\'}


def lani_arg(value, ty):
    if ty in FLOATS:
        return f'core::{ty}::from_bits({oracle.lani_expr(("uint", "u32" if ty == "f32" else "u64", value))})'
    if ty == 'char':
        return "'" + CHAR_ESCAPES.get(value, chr(value)) + "'"
    if ty == 'i32':
        return oracle.lani_expr(('int', value))
    if ty in SIGNED_BITS:
        return f'({oracle.lani_expr(("int", value))} as {ty})'
    if ty == 'i64':
        return f'({oracle.lani_expr(("uint", "isize", value))} as i64)'
    if ty == 'bool':
        return 'true' if value else 'false'
    return oracle.lani_expr(('uint', ty, value))


# ---------------------------------------------------------------- reasons

UNREAD_TYPES = ('str',)


def constructs(mods, module, fn):
    """Constructs in fn's signature or body that the front end does not read."""
    out = []
    sig = ' '.join(ty or 'self' for _, ty in fn['params']) + ' ' + fn['ret']
    body = fn['body'] or ''
    text = sig + ' ' + body
    for ty in UNREAD_TYPES:
        if re.search(rf'\b{ty}\b', text):
            out.append(f'type {ty}')
    if '=>' in body:
        out.append('=> arm')
    if re.search(r'->\s*(\{|if\b)', body):
        out.append('block or if arm')
    if re.search(r'&\s*(mut\b|self\b)', text) or 'self' in sig:
        out.append('self or reference')
    if re.search(r'"', body):
        out.append('string literal')
    fors = re.findall(r'\bfor\s+\w+\s+in\s+[^{]*\{', body)
    if any(not re.fullmatch(r'for\s+\w+\s+in\s+\d+\s*\.\.\s*[a-z_]\w*\s*\{', f) for f in fors):
        out.append('for other than literal..local')
    big = [int(x) for x in re.findall(r'(?<![\w.])(\d+)(?![\w.])', body) if int(x) >= 2 ** 64]
    if big:
        out.append(f'literal {big[0]} >= 2^64')
    if re.search(r'\)\s*\.\s*\w+', body):
        out.append('field or method of a call result')
    if re.search(r'\b(?!self\b)[a-z_]\w*\s*\.\s*\w+\s*\(', body):
        out.append('method call')
    if re.search(r'\b[A-Z]\w*::[a-z_]\w*\s*\(', body) and not re.search(r'\b[A-Z]::[a-z_]\w*\s*\(', body):
        out.append('Type::method call')
    if re.search(r'\[[^\]]*;[^\]]*\]', text):
        out.append('array')
    if fn['where'] or re.search(r'\b[A-Z]::\w+\s*\(', body):
        pass  # bounds are ignored and T::m is read
    return out


def compile_constructs(mods, module, fn):
    """Constructs the front end reads that compileSource is known to reject."""
    body = fn['body'] or ''
    out = []
    if re.search(r'\[\s*u8\s*\]', body):
        out.append('a raw view of u8')
    return out


def callees(mods, module, fn):
    """The stdlib fns that fn's body calls (by bare name in its module, or by path)."""
    body = fn['body'] or ''
    out = []
    for path, name in re.findall(r'\b((?:[a-z_]\w*::)*)([a-z_]\w*)\s*(?:<[^()]*?>)?\s*\(', body):
        mod = path[:-2] if path else module
        if mod in mods and name in mods[mod].fns:
            out.append((mod, mods[mod].fns[name]))
    return out


def causes(mods, t, find=None):
    find = find or constructs
    seen, out, todo = set(), [], [(t.module, t.fn, None)]
    while todo:
        module, fn, via = todo.pop(0)
        key = (module, fn['name'], fn['start'])
        if key in seen:
            continue
        seen.add(key)
        for c in find(mods, module, fn):
            out.append(c if via is None else f'{c} (in {module}::{fn["name"]})')
        if fn['extern'] or fn['body'] is None:
            out.append(f'extern {module}::{fn["name"]}')
        for mod, callee in callees(mods, module, fn):
            todo.append((mod, callee, fn['name']))
    return out


# ---------------------------------------------------------------- main

def main():
    run_cache.no_core_dumps()
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--modules', help='comma-separated module names (default: every stdlib module)')
    parser.add_argument('--calls', type=int, default=8)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--chunk', type=int, default=40)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--shard', default='0/1', help='k/n: every nth target from the kth')
    args = parser.parse_args()
    rng = random.Random(args.seed)
    mods = load_modules()
    wanted = set(args.modules.split(',')) if args.modules else None
    all_targets = targets(mods, wanted)
    shard, shards = (int(x) for x in args.shard.split('/'))
    all_targets = all_targets[shard::shards]
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)
    files_dir = os.path.join(workdir, 'files')
    os.makedirs(files_dir, exist_ok=True)

    # Programs: one per testable target and result part.
    programs = []
    for t in all_targets:
        if t.params is None:
            continue
        for part in results_of(t.ret):
            k = len(programs)
            text, wparams = wrapper_text(mods, t, part)
            base = os.path.join(workdir, f'p{k}')
            open(base + '.lani', 'w').write(text)
            deps = closure(mods, t.module)
            for m in sorted({m for ty in [t.ret] + [ty for _, ty in t.params] for m in struct_modules(ty)}):
                deps += [d for d in closure(mods, m) if d not in deps]
            programs.append(dict(target=t, part=part, base=base, wparams=wparams, deps=deps))

    # laniusc's parse trees: the stdlib files one by one, the wrappers in
    # batches (both cached); a tree the validator rejects is parsed again the
    # slow way (parse_tree), and a file with none is left out.
    began = time.time()
    build_run_all()
    deps = sorted({dep for p in programs for dep in p['deps']})
    dep_base = {dep: os.path.join(files_dir, dep.replace('::', '__')) for dep in deps}
    trees = {}
    for dep in deps:
        shutil.copy(mods[dep].path, dep_base[dep] + '.lani')
        trees[dep_base[dep]] = parse_stdlib_file(args.laniusc, dep_base[dep] + '.lani', files_dir)
    for p, tree in zip(programs, parse_wrappers(args.laniusc, [open(p['base'] + '.lani').read() for p in programs],
                                                files_dir)):
        trees[p['base']] = tree
    for b, tree in trees.items():
        if tree is not None:
            write_tree(b, tree)
    good = validate_all([b for b, tree in trees.items() if tree is not None], workdir)
    for b in [b for b in trees if b not in good]:
        tree = parse_tree(args.laniusc, b + '.lani', files_dir)
        if tree is not None:
            write_tree(b, tree)
            good |= validate_all([b], workdir)

    parse_s = time.time() - began
    manifest = []
    for k, p in enumerate(programs):
        bases = [p['base']] + [dep_base[dep] for dep in p['deps']]
        if not all(b in good for b in bases):
            p['status'] = 'noparse'
            continue
        manifest.append(f'compile p{k} ' + ' '.join(bases))
    open(os.path.join(workdir, 'manifest.txt'), 'w').write('\n'.join(manifest) + '\n')
    run = subprocess.run([RUN_ALL, os.path.join(workdir, 'manifest.txt')], capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit('runAll failed:\n' + run.stdout[-4000:] + run.stderr[-4000:])
    status = {}
    for line in run.stdout.strip().split('\n'):
        name, rest = line.split(' ', 1)
        status[int(name[1:])] = rest
    expected = sum(1 for p in programs if p.get('status') != 'noparse')
    if len(status) != expected:
        raise SystemExit(f'runAll printed {len(status)} results for {expected} programs')

    compile_s = time.time() - began - parse_s
    # Native runs.
    native = Native()
    for k, p in enumerate(programs):
        if p.get('status') == 'noparse':
            continue
        p['status'] = status[k].split(' ')[0]
        if p['status'] != 'image':
            continue
        entries_s, image_s = re.match(r'image \[(.*?)\] \[(.*?)\]$', status[k]).groups()
        native.load([int(x) for x in entries_s.split(',')], bytes(int(x) for x in image_s.split(',')),
                    len(p['wparams']))
        types = [ty for _, ty in p['wparams']]
        # A stdio handle is 1 or 2: the verified compiler's programs (and
        # Core's world) have no other file open, where laniusc's process has
        # (SEMANTIC_DECISIONS.md, "Externs and the runtime").
        handles = {f'a{k}' for k, (name, ty) in enumerate(p['target'].params) if name == 'handle' and ty == 'i32'}
        p['calls'] = [[rng.choice((1, 2)) if name in handles else gen_arg(rng, ty) for name, ty in p['wparams']]
                      for _ in range(args.calls if types else 1)]
        high = p['target'].ret in FLOATS and p['part'] == 'hi'
        p['native'] = [native_call(native, a, types, high) for a in p['calls']]

    native_s = time.time() - began - parse_s - compile_s
    # laniusc: the compiled wrappers, renamed, in harness binaries.
    compiled = [p for p in programs if p['status'] == 'image']
    disagreements = []
    agreed = calls_total = traps = written = 0
    for start in range(0, len(compiled), args.chunk):
        chunk = compiled[start:start + args.chunk]
        results = laniusc_chunk(args, workdir, chunk, start)
        for p, got in zip(chunk, results):
            for a, want, have in zip(p['calls'], p['native'], got):
                if want[0] in ('trap', 'timeout'):
                    traps += 1
                    if have[0] not in ('trap', 'timeout', 'laniusc rejects it'):
                        disagreements.append(f'{p["target"].label} [{p["part"]}] args {a}: verified compiler traps, '
                                             f'laniusc {shown(have)}')
                    elif want[0] == 'trap' and have[0] == 'trap' and want[1:] != have[1:]:
                        disagreements.append(f'{p["target"].label} [{p["part"]}] args {a}: both trap, the verified '
                                             f'compiler {shown(want)}, laniusc {shown(have)}')
                    continue
                calls_total += 1
                if have == want:
                    agreed += 1
                    written += len(want[1]) + len(want[2])
                else:
                    disagreements.append(f'{p["target"].label} [{p["part"]}] args {a}: verified compiler {shown(want)}, '
                                         f'laniusc {shown(have)}')

    print(f'output: {written} bytes written alike to stdout and stderr', file=sys.stderr)
    print(f'time: parse {parse_s:.0f} s, runAll {compile_s:.0f} s, native {native_s:.0f} s, '
          f'laniusc {time.time() - began - parse_s - compile_s - native_s:.0f} s',
          file=sys.stderr)
    report(workdir, mods, all_targets, programs, disagreements, agreed, calls_total, traps)
    return 1 if disagreements else 0


def shown(result):
    """A call's result, with what it wrote to stdout and stderr."""
    value, out, err = result
    return f'{value}' + (f' stdout {out!r}' if out else '') + (f' stderr {err!r}' if err else '')


# In the harness's output each call's result follows its stdout after
# these bytes, and its stderr ends with them (see frame in harness_text).
FRAME = bytes([255, 0, 76, 78, 83, 79, 0, 255])


def harness_text(chunk, start):
    """One binary for a chunk's wrappers: main makes every call, from the one
    numbered by its argument count on, printing each result (laniusc's
    output is unbuffered, so the results before a trap are kept)."""
    floats = {f'core::{ty}' for p in chunk for ty in [p['target'].ret] + [t for _, t in p['wparams']] if ty in FLOATS}
    imports = sorted({'std::io_byte', 'std::process'} | floats |
                     {line[7:-1] for p in chunk for line in open(p['base'] + '.lani').read().split('\n')
                      if line.startswith('import ')})
    out = ['module app::main;'] + [f'import {m};' for m in imports] + ['']
    out += oracle.LANI_HEAD.split('\n', 4)[4].split('\n')
    for j, p in enumerate(chunk):
        text = open(p['base'] + '.lani').read()
        body = '\n'.join(line for line in text.split('\n') if not line.startswith(('module ', 'import ')))
        for name in ('oracle_helper', 'oracle_flag', 'oracle_part', 'OracleSizeW'):
            body = re.sub(rf'\b{name}\b', f'{name}{start + j}', body)
        body = re.sub(r'\bfn w\(', f'fn w{start + j}(', body)
        out.append(body)
    out += (['fn frame(value: i32) -> i32 {'] + [f'    put({b});' for b in FRAME] + ['    put32(value);'] +
            [f'    let e{k}: bool = std::io_byte::write_stderr_byte({b});' for k, b in enumerate(FRAME)] +
            ['    return 0;', '}', ''])
    out += ['fn main() -> i32 {', '    let start: i32 = std::process::argc() - 1;']
    n = 0
    for j, p in enumerate(chunk):
        types = [ty for _, ty in p['wparams']]
        ret, part = p['target'].ret, p['part']
        for a in p['calls']:
            call = f'w{start + j}({", ".join(lani_arg(v, t) for v, t in zip(a, types))})'
            if ret in FLOATS:
                # the result's bits, as the verified compiler's image returns them
                call = f'core::{ret}::to_bits({call})'
                call = f'(({call} >> 32) as i32)' if part == 'hi' else f'({call} as i32)'
            out.append(f'    if (start <= {n}) {{ frame({call}); }}')
            n += 1
    out.append('    return 0;\n}')
    return '\n'.join(out) + '\n'


def build(args, workdir, name, text):
    """laniusc's binary of a harness (cached), or None and its error output."""
    lani_path = os.path.join(workdir, name + '.lani')
    open(lani_path, 'w').write(text)
    k = run_cache.key(run_cache.file_digest(args.laniusc), run_cache.tree_digest(STDLIB), text)
    hit = run_cache.load_file('build', k)
    if hit is not None:
        return hit, ''
    exe = os.path.join(workdir, name)
    if os.path.exists(exe):
        os.remove(exe)
    built = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                            HEAVY, '-t', '20', args.laniusc, '--stdlib-root', STDLIB, '-o', exe, lani_path],
                           capture_output=True, text=True)
    if built.returncode != 0 or not os.path.exists(exe):
        return None, built.stdout[-2000:] + built.stderr[-2000:]
    return run_cache.store_file('build', k, exe), ''


def run_calls(exe, n):
    """The binary's result for each of its n calls, with the call's stdout and
    stderr (each call's output ends with FRAME on both): a value, or 'trap'
    or 'timeout' for the call it stopped at (it is run again from the next)."""
    got = []
    while len(got) < n:
        try:
            run = subprocess.run([exe] + ['x'] * len(got), capture_output=True, timeout=10)
            data, errors, code = run.stdout, run.stderr, run.returncode
        except subprocess.TimeoutExpired as e:
            data, errors, code = e.stdout or b'', e.stderr or b'', 'timeout'
        errs = iter(errors.split(FRAME))
        parts = data.split(FRAME)
        out = parts[0]
        for part in parts[1:]:
            if len(got) == n or len(part) < 4:
                break
            got.append((oracle.i32(int.from_bytes(part[:4], 'little')), out, next(errs, b'')))
            out = part[4:]
        if len(got) < n:
            got.append(('missing' if code == 0 else 'timeout' if code == 'timeout' else 'trap', out,
                        next(errs, b'')))
    return got


def laniusc_chunk(args, workdir, chunk, start):
    """Each wrapper's laniusc result on each call ('laniusc rejects it' when
    laniusc does not build it)."""
    exe, error = build(args, workdir, f'harness{start}', harness_text(chunk, start))
    if exe is None and len(chunk) > 1:
        # laniusc rejects the chunk: build each wrapper alone to find which.
        out = []
        for j, p in enumerate(chunk):
            out += laniusc_chunk(args, workdir, [p], start + j)
        return out
    if exe is None:
        open(os.path.join(workdir, f'harness{start}.error'), 'w').write(error)
        return [[('laniusc rejects it', b'', b'')] * len(chunk[0]['calls'])]
    got = iter(run_calls(exe, sum(len(p['calls']) for p in chunk)))
    return [[next(got) for _ in p['calls']] for p in chunk]


def category(cause):
    c = cause.split(' (in ')[0]
    for prefix, name in (('literal', 'literal >= 2^64'), ('extern', 'extern callee')):
        if c.startswith(prefix):
            return name
    return c


def report(workdir, mods, all_targets, programs, disagreements, agreed, calls_total, traps):
    by_target = {}
    for p in programs:
        by_target.setdefault(p['target'].label, []).append(p)
    untestable = {}
    for t in all_targets:
        if t.params is None:
            key = t.why.split(' ')[0] if t.why.startswith(('extern', 'self', 'result')) else t.why
            untestable[key] = untestable.get(key, 0) + 1
    tested = [t for t in all_targets if t.params is not None]
    states = {}
    for t in tested:
        ps = by_target[t.label]
        s = 'compiled' if all(p['status'] == 'image' for p in ps) else next(p['status'] for p in ps if p['status'] != 'image')
        states.setdefault(s, []).append(t)
    unread_lines = []
    reason_counts = {}
    for s in ('unread', 'tree', 'nolex', 'noparse', 'uncompiled'):
        for t in states.get(s, []):
            cs = causes(mods, t, compile_constructs if s == 'uncompiled' else constructs) \
                if s in ('unread', 'uncompiled') else []
            kinds = sorted({category(c) for c in cs})
            for kind in kinds or ['no known cause']:
                key = ('compileSource: ' if s == 'uncompiled' else '') + kind
                if s in ('unread', 'uncompiled'):
                    reason_counts[key] = reason_counts.get(key, 0) + 1
            unread_lines.append(f'{t.label} [{s}]: ' + ('; '.join(dict.fromkeys(cs)) if cs else
                                                        ('no known cause' if s in ('unread', 'uncompiled') else s)))
    modules = sorted({t.module for t in all_targets})
    per_module = []
    for m in modules:
        ts = [t for t in all_targets if t.module == m]
        te = [t for t in ts if t.params is not None]
        ok = [t for t in te if t in states.get('compiled', [])]
        per_module.append(f'{m}: {len(ts)} targets, {len(te)} testable, {len(ok)} read and compiled')
    open(os.path.join(workdir, 'unread.txt'), 'w').write('\n'.join(unread_lines) + '\n')
    open(os.path.join(workdir, 'modules.txt'), 'w').write('\n'.join(per_module) + '\n')
    summary = [
        f'{len(modules)} modules, {len(all_targets)} targets (pub fns and scalar trait-impl methods)',
        f'not testable by this harness: {sum(untestable.values())} '
        + ', '.join(f'{k} {v}' for k, v in sorted(untestable.items(), key=lambda kv: -kv[1])[:12]),
        f'testable: {len(tested)}; ' + ', '.join(f'{s} {len(v)}' for s, v in sorted(states.items())),
        'not read or not compiled, by construct (a target can count under several): '
        + ', '.join(f'{k} {v}' for k, v in sorted(reason_counts.items(), key=lambda kv: -kv[1])),
        f'{calls_total} calls compared with laniusc, {agreed} agree; {traps} calls trap natively, '
        f'each checked to stop laniusc\'s binary too',
        f'{len(disagreements)} disagreements',
    ]
    for d in disagreements:
        print(d)
    open(os.path.join(workdir, 'summary.txt'), 'w').write('\n'.join(summary + disagreements) + '\n')
    json.dump({t.label: t.why or 'tested' for t in all_targets}, open(os.path.join(workdir, 'targets.json'), 'w'),
              indent=0)
    print('\n'.join(summary))


if __name__ == '__main__':
    sys.exit(main())
