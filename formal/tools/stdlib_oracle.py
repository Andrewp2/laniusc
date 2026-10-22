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
   has (i32, bool, u8, u32, u64, usize, isize) or `core::option::Option` of
   one; others are counted by the type that stops them.
2. Each testable target gets a program of its own: a first file, the module
   app::main, holding one wrapper `w` that takes scalar arguments (an
   Option as a flag and a payload), calls the target and returns an i32 (a
   bool as 0 or 1, a 64-bit result as its low or high 32 bits, an Option as
   its flag or payload). A trait method is called through a generic helper
   `T::m(..)`, the way the stdlib's own generic code calls it. The program's
   other files are the target's module and the modules it reaches by import
   or path, read from stdlib/ as written.
3. laniusc parses each file (under heavy), and under `lake env lean`
   `frontEndFiles` reads the program, then `compileSource` compiles it.
4. Each compiled image runs natively on K argument tuples, each call in a
   forked child (a trap or a two-second timeout is a result, not a crash).
   The wrappers that compiled, with every call that did not trap, are also
   compiled by laniusc in one harness binary per chunk, which prints each
   result; the two must agree. A call that trapped natively must also stop
   the laniusc binary (checked one call per binary, at most 20).

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
import shutil
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import frontend_difftest as front  # noqa: E402
import oracle_difftest as oracle  # noqa: E402

STDLIB = 'stdlib'
HEAVY = 'target/claude-work/bin/heavy'
SCALARS = ('i32', 'bool', 'u8', 'u32', 'u64', 'usize', 'isize')
WIDE = ('u64', 'usize', 'isize')


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
    m = re.match(r'^(?:core::option::)?Option<(.*)>$', t)
    if m:
        inner = resolve(mods, module, m.group(1), subst)
        return f'Option<{inner}>' if inner else None
    if '::' in t:
        path, name = t.rsplit('::', 1)
        if path in mods and name in mods[path].aliases:
            return resolve(mods, path, mods[path].aliases[name], {})
        return None
    if module in mods and t in mods[module].aliases:
        return resolve(mods, module, mods[module].aliases[t], {})
    return None


def testable(t):
    if t in SCALARS:
        return True
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
        elif not testable(ret):
            t.why = 'type ' + fn['ret']
        elif bad or any(not testable(ty) for _, ty in params):
            t.why = 'type ' + next(orig for (p, ty), (_, orig) in zip(params, fn['params']) if not testable(ty))
        else:
            t.params, t.ret = params, ret
    return out


def results_of(ret):
    """The parts of a result the wrapper can return, one wrapper each."""
    if ret in WIDE:
        return ['lo', 'hi']
    if ret.startswith('Option<'):
        return ['tag', 'val']
    return ['all']


def wrapper_text(mods, t, part):
    """The first file of a target's program, and the wrapper's scalar parameter types."""
    fn = t.fn
    lines = ['module app::main;', '']
    for dep in sorted({t.module, 'core::option'} if any(ty.startswith('Option<') for _, ty in t.params) or
                      t.ret.startswith('Option<') else {t.module}):
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
        else:
            wparams.append((f'a{k}', ty))
            args.append(f'a{k}')
    ret = t.ret if not t.ret.startswith('Option<') else f'core::option::Option<{t.ret[7:-1]}>'
    if t.trait:
        # A generic helper calls the method as T::m, as the stdlib's generic code does.
        tparams = ', '.join(f'{p}: {"T" if ty == t.impl_type else ty}' for p, ty in fn['params'])
        hret = 'T' if fn['ret'] == t.impl_type else fn['ret']
        trait = re.sub(rf'\b{t.impl_type}\b', 'T', t.trait)
        tname = re.match(r'[\w:]+', t.trait).group(0)
        if '::' not in tname:
            home = t.module if tname in mods[t.module].traits else next(
                (n for n in mods if tname in mods[n].traits), t.module)
            trait = f'{home}::{trait}'
        lines += [f'fn oracle_helper<T>({tparams}) -> {hret} where T: {trait} {{',
                  f'    return T::{fn["name"]}({", ".join(p for p, _ in fn["params"])});', '}', '']
        call = f'oracle_helper<{t.impl_type}>({", ".join(args)})'
    else:
        targs = f'<{t.targs or ", ".join("i32" for _ in fn["generics"])}>' if fn['generics'] else ''
        call = f'{t.module}::{fn["name"]}{targs}({", ".join(args)})'
    sig = ', '.join(f'{p}: {ty}' for p, ty in wparams)
    lines.append(f'fn w({sig}) -> i32 {{')
    lines += setup
    lines.append(f'    let r: {ret} = {call};')
    base = t.ret
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
            conv = 'x' if inner == 'i32' else '(x as i32)'
            if inner == 'bool':
                lines.append('    let t: i32 = match (r) { Some(x) -> oracle_flag(x), None -> 0 };')
            else:
                lines.append(f'    let t: i32 = match (r) {{ Some(x) -> {conv}, None -> 0 }};')
        lines.append('    return t;')
    lines.append('}')
    if t.ret == 'Option<bool>' and part == 'val':
        lines += ['', 'fn oracle_flag(b: bool) -> i32 {', '    if (b) {', '        return 1;', '    }', '    return 0;', '}']
    return '\n'.join(lines) + '\n', wparams


# ---------------------------------------------------------------- laniusc's trees

def parse_tree(laniusc, lani_path, workdir):
    """laniusc's parse tree of one file: its node kinds and parents, or None.

    laniusc parses the modules a file imports first, as one pack, then the
    file: so the file's tree is the second capture of the parser's last pass
    when it has imports, the first when it has none (a third, for generic
    code, is laniusc's text after its own monomorphization)."""
    has_imports = bool(re.search(r'^\s*import\s', strip_comments(open(lani_path).read()), re.M))
    cap = os.path.join(workdir, 'cap')
    env = dict(os.environ, LANIUS_DEBUG_CAPTURE_PASS='parser/tree/parent_parallel', LANIUS_DEBUG_CAPTURE_DIR=cap,
               LANIUS_DEBUG_CAPTURE_INDEX='1' if has_imports else '0')
    shutil.rmtree(cap, ignore_errors=True)
    subprocess.run([HEAVY, '-t', '10', laniusc, '--stdlib-root', STDLIB, '-o', os.path.join(workdir, 'a.out'),
                    lani_path], env=env, capture_output=True, text=True)
    status = os.path.join(cap, 'post', '002_tree_count_status.bin')
    if not os.path.exists(status):
        return None
    count = front.words(status)[5]
    prods = front.words(os.path.join(cap, 'post', '006_node_kind.bin'))[:count]
    parents = front.words(os.path.join(cap, 'post', '007_parent.bin'))[:count]
    return prods, parents


# ---------------------------------------------------------------- Lean

LEAN = '''import Lanius.Mini.FrontLex
open Lanius.Mini

def readNats (path : String) : IO (List Nat) := do
  let text ← IO.FS.readFile path
  return (text.splitOn " ").filterMap String.toNat?

def readSource (path : String) : IO (List Lanius.Compiler.Lexer.Byte) := do
  let bytes ← IO.FS.readBinFile path
  return bytes.toList.map (fun b => Fin.ofNat 256 b.toNat)

def loadFile (cache : IO.Ref (List (String × Option FileInput))) (base : String) : IO (Option FileInput) := do
  match (← cache.get).lookup base with
  | some r => return r
  | none =>
    let source ← readSource (base ++ ".lani")
    let prods ← readNats (base ++ ".prods")
    let parents ← readNats (base ++ ".parents")
    let r := (lexTokens source).map fun tokens => ({ tokens := tokens, prods := prods, parents := parents } : FileInput)
    cache.modify fun c => (base, r) :: c
    return r

-- One line per program: its name, then its files' bases. Prints the name and
-- nolex, tree (a tree the grammar rejects), unread (the builder rejects it),
-- uncompiled (compileSource rejects the program read), or the image.
def runAll (manifest : String) : IO Unit := do
  let cache ← IO.mkRef ([] : List (String × Option FileInput))
  let lines := ((← IO.FS.readFile manifest).splitOn "\\n").filter (· ≠ "")
  for line in lines do
    let parts := line.splitOn " "
    let name := parts.headD ""
    let mut files : List FileInput := []
    let mut lexed := true
    for b in parts.tail do
      match ← loadFile cache b with
      | none => lexed := false
      | some f => files := files ++ [f]
    if !lexed then
      IO.println s!"{name} nolex"
    else
      match frontEndFiles grammar files with
      | none =>
        match validateFiles grammar files with
        | none => IO.println s!"{name} tree"
        | some _ => IO.println s!"{name} unread"
      | some p =>
        match compileSource p with
        | none => IO.println s!"{name} uncompiled"
        | some b => IO.println s!"{name} image {b.entries} {b.image.map (·.toNat)}"
'''


# ---------------------------------------------------------------- native side

ARG_STORES = [bytes([0x48, 0x89, 0x7C, 0x24]), bytes([0x48, 0x89, 0x74, 0x24]), bytes([0x48, 0x89, 0x54, 0x24]),
              bytes([0x48, 0x89, 0x4C, 0x24]), bytes([0x4C, 0x89, 0x44, 0x24]), bytes([0x4C, 0x89, 0x4C, 0x24])]


class Native(oracle.Native):
    """oracle_difftest's stub, with up to six arguments (rdi, rsi, rdx, rcx, r8, r9)."""

    def load(self, entries, image, arity):
        self.code[0:len(image)] = image
        at = len(image)
        stub = bytes([0x41, 0x54, 0x41, 0x55, 0x41, 0x56])
        stub += bytes([0x49, 0xBC]) + self.heap_base.to_bytes(8, 'little')
        stub += bytes([0x49, 0xBD]) + (1).to_bytes(8, 'little')
        stub += bytes([0x49, 0xBE]) + (self.HEAP - 64).to_bytes(8, 'little')
        for k in range(arity):
            stub += ARG_STORES[k] + bytes([(256 - (8 * k + 24)) & 0xff])
        rel = entries[0] - (at + len(stub) + 5)
        stub += b'\xe8' + (rel & 0xffffffff).to_bytes(4, 'little')
        stub += bytes([0x41, 0x5E, 0x41, 0x5D, 0x41, 0x5C, 0xC3])
        self.code[at:at + len(stub)] = stub
        self.fn = ctypes.CFUNCTYPE(ctypes.c_uint64, *([ctypes.c_uint64] * arity))(self.base + at)


def slot(value, ty):
    if ty == 'i32':
        return value & 0xffffffff
    return value & (2 ** 64 - 1)


def native_call(native, args, types):
    """The wrapper's result, or 'trap' (a signal) or 'timeout', from a forked child."""
    r, w = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(r)
        signal.alarm(2)
        native.heap[0:native.HEAP] = bytes(native.HEAP)
        value = native.fn(*[slot(a, t) for a, t in zip(args, types)])
        os.write(w, str(oracle.i32(value)).encode())
        os._exit(0)
    os.close(w)
    data = b''
    while True:
        chunk = os.read(r, 64)
        if not chunk:
            break
        data += chunk
    os.close(r)
    _, status = os.waitpid(pid, 0)
    if os.WIFSIGNALED(status):
        return 'timeout' if os.WTERMSIG(status) == signal.SIGALRM else 'trap'
    return int(data)


# ---------------------------------------------------------------- arguments

SMALL = [0, 1, 2, 3, 5, 7, 10, 31, 32, 63, 64, 100, 255, 256]


def gen_arg(rng, ty):
    if ty == 'bool':
        return int(rng.random() < 0.5)
    if rng.random() < 0.3:
        v = rng.choice([v for v in SMALL if ty not in oracle.UINT_BITS or v < 2 ** oracle.UINT_BITS[ty]])
        if ty in ('i32', 'isize') and rng.random() < 0.4:
            v = -v
        return v
    if ty == 'i32':
        return rng.choice(oracle.I32_EDGES) if rng.random() < 0.4 else rng.randint(-2 ** 31, 2 ** 31 - 1)
    if ty == 'isize':
        return rng.choice(oracle.ISIZE_EDGES) if rng.random() < 0.4 else rng.randint(-2 ** 63, 2 ** 63 - 1)
    bits = oracle.UINT_BITS[ty]
    if rng.random() < 0.3:
        return rng.choice([0, 1, 2 ** bits - 1, 2 ** (bits - 1), 2 ** (bits - 1) - 1])
    return rng.randrange(1 << bits)


def lani_arg(value, ty):
    if ty == 'i32':
        return oracle.lani_expr(('int', value))
    if ty == 'bool':
        return 'true' if value else 'false'
    return oracle.lani_expr(('uint', ty, value))


# ---------------------------------------------------------------- reasons

UNREAD_TYPES = ('i8', 'i16', 'i64', 'u16', 'char', 'f32', 'f64', 'str')


def constructs(mods, module, fn):
    """Constructs in fn's signature or body that the front end does not read."""
    out = []
    sig = ' '.join(ty or 'self' for _, ty in fn['params']) + ' ' + fn['ret']
    body = fn['body'] or ''
    text = sig + ' ' + body
    for ty in UNREAD_TYPES:
        if re.search(rf'\b{ty}\b', text):
            out.append(f'type {ty}')
    if re.search(r'<<|>>=|>>\s*[\w(]', body):
        out.append('shift')
    if re.search(r'\b(i8|i16|i64|u16|char|f32)::\w+\s*\(', body):
        out.append('builtin type::method call')
    if '=>' in body:
        out.append('=> arm')
    if re.search(r'->\s*(\{|if\b)', body):
        out.append('block or if arm')
    if re.search(r'&\s*(mut\b|self\b)', text) or 'self' in sig:
        out.append('self or reference')
    if re.search(r'"', body):
        out.append('string literal')
    if re.search(r"'(\\.|[^'\\])'", body):
        out.append('char literal')
    if re.search(r'\b(for|loop|break|continue)\b', body):
        out.append('for/loop/break/continue')
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
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--modules', help='comma-separated module names (default: every stdlib module)')
    parser.add_argument('--calls', type=int, default=8)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--chunk', type=int, default=40)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    args = parser.parse_args()
    rng = random.Random(args.seed)
    mods = load_modules()
    wanted = set(args.modules.split(',')) if args.modules else None
    all_targets = targets(mods, wanted)
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
            programs.append(dict(target=t, part=part, base=base, wparams=wparams, deps=closure(mods, t.module)))

    # laniusc's parse trees: each stdlib file once, each wrapper once.
    parsed = {}

    def parse(base):
        if base in parsed:
            return
        text = open(base + '.lani').read()
        if os.path.exists(base + '.parsed') and open(base + '.parsed').read() == text and os.path.exists(base + '.prods'):
            parsed[base] = True  # parsed by an earlier run, unchanged
            return
        tree = parse_tree(args.laniusc, base + '.lani', files_dir)
        if tree is None:
            parsed[base] = False
            return
        open(base + '.prods', 'w').write(' '.join(map(str, tree[0])))
        open(base + '.parents', 'w').write(' '.join(map(str, tree[1])))
        open(base + '.parsed', 'w').write(text)
        parsed[base] = True

    manifest = []
    for p in programs:
        bases = [p['base']]
        for dep in p['deps']:
            b = os.path.join(files_dir, dep.replace('::', '__'))
            if not os.path.exists(b + '.lani'):
                shutil.copy(mods[dep].path, b + '.lani')
            bases.append(b)
        for b in bases:
            parse(b)
        if not all(parsed[b] for b in bases):
            p['status'] = 'noparse'
            continue
        manifest.append(f'p{programs.index(p)} ' + ' '.join(bases))
    open(os.path.join(workdir, 'manifest.txt'), 'w').write('\n'.join(manifest) + '\n')
    lean_path = os.path.join(workdir, 'stdlib_oracle.lean')
    open(lean_path, 'w').write(LEAN + f'\n#eval runAll "{os.path.join(workdir, "manifest.txt")}"\n')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    lean = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                           'lake', 'env', 'lean', lean_path], cwd='formal', env=env, capture_output=True, text=True)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    status = {}
    for line in lean.stdout.strip().split('\n'):
        name, rest = line.split(' ', 1)
        status[int(name[1:])] = rest
    expected = sum(1 for p in programs if p.get('status') != 'noparse')
    if len(status) != expected:
        raise SystemExit(f'lean printed {len(status)} results for {expected} programs')

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
        p['calls'] = [[gen_arg(rng, ty) for ty in types] for _ in range(args.calls if types else 1)]
        p['native'] = [native_call(native, a, types) for a in p['calls']]

    # laniusc: the compiled wrappers, renamed, in harness binaries.
    compiled = [p for p in programs if p['status'] == 'image']
    disagreements = []
    agreed = calls_total = trapped_total = 0
    for start in range(0, len(compiled), args.chunk):
        chunk = compiled[start:start + args.chunk]
        results = laniusc_chunk(args, workdir, chunk, start, mods)
        for p, got in zip(chunk, results):
            for a, want, have in zip(p['calls'], p['native'], got):
                if want in ('trap', 'timeout'):
                    continue
                calls_total += 1
                if have == want:
                    agreed += 1
                else:
                    disagreements.append(f'{p["target"].label} [{p["part"]}] args {a}: verified compiler {want}, '
                                         f'laniusc {have}')
    traps = [(p, a) for p in compiled for a, want in zip(p['calls'], p['native']) if want in ('trap', 'timeout')]
    for p, a in traps[:20]:
        trapped_total += 1
        code = laniusc_trap(args, workdir, p, a, mods)
        if code == 0:
            disagreements.append(f'{p["target"].label} [{p["part"]}] args {a}: verified compiler traps, '
                                 f'laniusc exits 0')

    report(workdir, mods, all_targets, programs, disagreements, agreed, calls_total, len(traps), trapped_total)
    return 1 if disagreements else 0


def harness_text(chunk, start, calls_of):
    imports = sorted({'std::io_byte'} | {line[7:-1] for p in chunk for line in open(p['base'] + '.lani').read().split('\n')
                                         if line.startswith('import ')})
    out = ['module app::main;'] + [f'import {m};' for m in imports] + ['']
    out += oracle.LANI_HEAD.split('\n', 4)[4].split('\n')
    for j, p in enumerate(chunk):
        text = open(p['base'] + '.lani').read()
        body = '\n'.join(line for line in text.split('\n') if not line.startswith(('module ', 'import ')))
        for name in ('oracle_helper', 'oracle_flag', 'OracleSizeW'):
            body = re.sub(rf'\b{name}\b', f'{name}{start + j}', body)
        body = re.sub(r'\bfn w\(', f'fn w{start + j}(', body)
        out.append(body)
    out.append('fn main() -> i32 {')
    for j, p in enumerate(chunk):
        types = [ty for _, ty in p['wparams']]
        for a in calls_of(p):
            out.append(f'    put32(w{start + j}({", ".join(lani_arg(v, t) for v, t in zip(a, types))}));')
    out.append('    return 0;\n}')
    return '\n'.join(out) + '\n'


def build_and_run(args, workdir, name, text):
    lani_path = os.path.join(workdir, name + '.lani')
    exe = os.path.join(workdir, name)
    open(lani_path, 'w').write(text)
    if os.path.exists(exe):
        os.remove(exe)
    build = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                            HEAVY, '-t', '20', args.laniusc, '--stdlib-root', STDLIB, '-o', exe, lani_path],
                           capture_output=True, text=True)
    if build.returncode != 0 or not os.path.exists(exe):
        return None, build.stdout[-2000:] + build.stderr[-2000:]
    try:
        run = subprocess.run([exe], capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return 'timeout', b''
    return run.returncode, run.stdout


def laniusc_chunk(args, workdir, chunk, start, mods):
    """Each wrapper's laniusc results on its non-trapping calls ('build' if laniusc rejects it)."""
    def calls_of(p):
        return [a for a, want in zip(p['calls'], p['native']) if want not in ('trap', 'timeout')]

    def decode(data, n):
        return [oracle.i32(int.from_bytes(data[4 * i:4 * i + 4], 'little')) if 4 * i + 4 <= len(data) else 'missing'
                for i in range(n)]

    code, data = build_and_run(args, workdir, f'harness{start}', harness_text(chunk, start, calls_of))
    if code is None and len(chunk) > 1:
        # laniusc rejects the chunk: build each wrapper alone to find which.
        out = []
        for j, p in enumerate(chunk):
            out += laniusc_chunk(args, workdir, [p], start + j, mods)
        return out
    results, at = [], 0
    for p in chunk:
        n = len(calls_of(p))
        if code is None:
            got = ['laniusc rejects it'] * n
            open(os.path.join(workdir, f'harness{start}.error'), 'w').write(data)
        else:
            got = decode(data[4 * at:], n)
        at += n
        it = iter(got)
        results.append([next(it) if want not in ('trap', 'timeout') else None for want in p['native']])
    return results


def laniusc_trap(args, workdir, p, a, mods):
    k = p['base'].rsplit('p', 1)[1]
    code, _ = build_and_run(args, workdir, f'trap{k}', harness_text([p], int(k), lambda q: [a]))
    return code


def category(cause):
    c = cause.split(' (in ')[0]
    for prefix, name in (('literal', 'literal >= 2^64'), ('extern', 'extern callee')):
        if c.startswith(prefix):
            return name
    return c


def report(workdir, mods, all_targets, programs, disagreements, agreed, calls_total, traps, traps_checked):
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
        f'{traps_checked} checked against laniusc',
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
