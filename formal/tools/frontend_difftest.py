#!/usr/bin/env python3
"""The front end against laniusc's parse trees (roadmap step 8).

    python3 -I formal/tools/frontend_difftest.py WORKDIR [--count N] [--seed S] [--chunk C] [--mutations M] [--laniusc PATH] [--heavy PATH]

Run from the repository root. Programs come from oracle_difftest.py's
generator (the front pass's subset: integers, bool, structs, enums, match,
if, while, calls, return), printed as Lanius, C programs to a file. laniusc
parses each file on the GPU, under target/claude-work/bin/heavy; its parse
tree (the node_kind and parent arrays) is captured right after the kernel
that builds it (LANIUS_DEBUG_CAPTURE_PASS=parser/tree/parent_parallel), and
its lexer tokens are dumped (LANIUS_DEBUG_DUMP_BUFFERS=token_words).

Then, under `lake env lean`, `sourceProgram` (the Lean lexer, then the
extracted validator and builder) reads each file with laniusc's tree, and the
result must be the program this script expects the text to mean: the
generated program with each local named by the byte offset of its binding,
literals as the text writes them (`(-5)` is a negation, `(7 as u8)` a cast),
and statement lists nested the way the reader nests them. The Lean lexer's
tokens must also be laniusc's (kind, start and length). Finally M mutated
copies of each tree (a production id or a parent index changed) and of each
source (one `+` written as `-`) must be rejected.

Prints one line per difference and a summary; exits nonzero on any.
"""

import argparse
import os
import random
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_difftest as oracle  # noqa: E402
oracle.SLICES = False  # the front end does not read heap and slice constructs yet

HEAVY = 'target/claude-work/bin/heavy'
UINT_LEAN = oracle.UINT_LEAN
UINT_BITS = oracle.UINT_BITS


# ---------------------------------------------------------------- printing

class Printer:
    """Lanius text, with the byte offset of every binding occurrence."""

    def __init__(self):
        self.parts, self.pos, self.binding = [], 0, {}

    def emit(self, text):
        self.parts.append(text)
        self.pos += len(text.encode())

    def bind(self, key, name):
        self.binding[key] = self.pos
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


def lean_uint(ty, k):
    t = f'(.uint {UINT_LEAN[ty]})'
    pieces = uint_pieces(ty, k)
    out = f'(.cast {t} (.int {pieces[0]}))'
    for p in pieces[1:]:
        out = f'(.apply .plus (.apply .times {out} (.cast {t} (.int 65536))) (.cast {t} (.int {p})))'
    return out


class Chunk:
    """Programs printed to one file, with their global type and function numbers."""

    def __init__(self, programs):
        self.programs = programs
        self.type_base, self.fn_base = [], []
        types = fns = 0
        for p in programs:
            self.type_base.append(types)
            self.fn_base.append(fns)
            types += len(p.structs) + len(p.enums)
            fns += len(p)
        self.out = Printer()

    # names
    def ty(self, k, t):
        if t[0] == 'struct':
            return f'P{k}S{t[1]}'
        if t[0] == 'enum':
            return f'P{k}E{t[1]}'
        return t

    def lean_ty(self, k, t):
        if t in UINT_BITS:
            return f'(.uint {UINT_LEAN[t]})'
        if t in ('i32', 'bool'):
            return '.' + t
        p = self.programs[k]
        if t[0] == 'struct':
            return f'(.struct {self.type_base[k] + t[1]} [{", ".join(self.lean_ty(k, f) for f in p.structs[t[1]])}])'
        if t[0] == 'enum':
            variants = ', '.join('[' + ', '.join(self.lean_ty(k, f) for f in v) + ']' for v in p.enums[t[1]])
            return f'(.enum {self.type_base[k] + len(p.structs) + t[1]} [{variants}])'
        raise ValueError(t)

    # expressions: text, and the expected reading (ids by the binding table)
    def lani_expr(self, e):
        kind = e[0]
        if kind == 'int':
            return lani_i32(e[1])
        if kind == 'bool':
            return 'true' if e[1] else 'false'
        if kind == 'uint':
            return lani_uint(e[1], e[2])
        if kind == 'cast':
            return f'({self.lani_expr(e[2])} as {e[1]})'
        if kind == 'local':
            return f'v{e[1]}'
        if kind == 'field':
            return f'v{e[1]}.f{e[2]}'
        if kind == 'neg':
            return f'(-{self.lani_expr(e[1])})'
        if kind == 'not':
            return f'(!{self.lani_expr(e[1])})'
        return f'({self.lani_expr(e[3])} {e[2]} {self.lani_expr(e[4])})'

    def lean_expr(self, ids, e):
        kind = e[0]
        if kind == 'int':
            return lean_i32(e[1])
        if kind == 'bool':
            return '(.boolean true)' if e[1] else '(.boolean false)'
        if kind == 'uint':
            return lean_uint(e[1], e[2])
        if kind == 'cast':
            return f'(.cast {self.lean_ty(None, e[1])} {self.lean_expr(ids, e[2])})'
        if kind == 'local':
            return f'(.local {ids[e[1]]})'
        if kind == 'field':
            return f'(.field {ids[e[1]]} {e[2]})'
        if kind == 'neg':
            return f'(.negate {self.lean_expr(ids, e[1])})'
        if kind == 'not':
            return f'(.not {self.lean_expr(ids, e[1])})'
        return f'(.apply .{e[1]} {self.lean_expr(ids, e[3])} {self.lean_expr(ids, e[4])})'

    def variant(self, k, enum, v):
        return f'P{k}E{enum}V{v}'

    # statements: print, and return the reader's items: ('let', head) whose
    # term is f'({head} {rest})', or ('stmt', term)
    def stmt(self, k, ids, s, indent):
        out, pad = self.out, '    ' * indent
        kind = s[0]
        if kind == 'nop':
            return []
        if kind == 'then':
            return self.stmt(k, ids, s[1], indent) + self.stmt(k, ids, s[2], indent)
        if kind in ('let', 'call', 'letStruct', 'letEnum', 'letMatch'):
            ident, ty = s[1], s[2]
            out.emit(f'{pad}let ')
            out.bind((k, ident), f'v{ident}')
            ids[ident] = out.binding[(k, ident)]
            out.emit(f': {self.ty(k, ty)} = ')
            lid, lty = ids[ident], self.lean_ty(k, ty)
            if kind == 'let':
                out.emit(self.lani_expr(s[3]) + ';\n')
                head = f'.let {lid} {lty} {self.lean_expr(ids, s[3])}'
            elif kind == 'call':
                out.emit(f'p{k}_f{s[3]}(' + ', '.join(self.lani_expr(a) for a in s[4]) + ');\n')
                head = (f'.letCall {lid} {lty} {self.fn_base[k] + s[3]} '
                        f'[{", ".join(self.lean_expr(ids, a) for a in s[4])}]')
            elif kind == 'letStruct':
                fields = ', '.join(f'f{j}: {self.lani_expr(f)}' for j, f in enumerate(s[3]))
                out.emit(f'{self.ty(k, ty)} {{ {fields} }};\n')
                head = f'.letStruct {lid} {lty} [{", ".join(self.lean_expr(ids, f) for f in s[3])}]'
            elif kind == 'letEnum':
                payload = ', '.join(self.lani_expr(f) for f in s[4])
                out.emit(self.variant(k, ty[1], s[3]) + (f'({payload})' if s[4] else '') + ';\n')
                head = f'.letEnum {lid} {lty} {s[3]} [{", ".join(self.lean_expr(ids, f) for f in s[4])}]'
            else:
                _, _, _, scrutinee, enum, arms, _ = s
                out.emit(f'match (v{scrutinee}) {{\n')
                lean_arms = []
                for v, (binders, value) in enumerate(arms):
                    out.emit(f'{pad}    {self.variant(k, enum, v)}')
                    if binders:
                        out.emit('(')
                        for i, b in enumerate(binders):
                            if i:
                                out.emit(', ')
                            out.bind((k, b), f'v{b}')
                            ids[b] = out.binding[(k, b)]
                        out.emit(')')
                    out.emit(f' -> {self.lani_expr(value)},\n')
                    lean_arms.append(f'{{ binders := [{", ".join(str(ids[b]) for b in binders)}], '
                                     f'value := {self.lean_expr(ids, value)} }}')
                out.emit(f'{pad}}};\n')
                enum_id = self.type_base[k] + len(self.programs[k].structs) + enum
                head = f'.letMatch {lid} {lty} {ids[scrutinee]} {enum_id} [{", ".join(lean_arms)}]'
            return [('let', head)] + self.stmt(k, ids, s[-1], indent)
        if kind == 'set':
            out.emit(f'{pad}v{s[1]} = {self.lani_expr(s[2])};\n')
            return [('stmt', f'(.set {ids[s[1]]} {self.lean_expr(ids, s[2])})')]
        if kind == 'setField':
            out.emit(f'{pad}v{s[1]}.f{s[2]} = {self.lani_expr(s[3])};\n')
            return [('stmt', f'(.setField {ids[s[1]]} {s[2]} {self.lean_expr(ids, s[3])})')]
        if kind == 'if':
            out.emit(f'{pad}if ({self.lani_expr(s[1])}) {{\n')
            a = nest(self.stmt(k, ids, s[2], indent + 1))
            out.emit(f'{pad}}} else {{\n')
            b = nest(self.stmt(k, ids, s[3], indent + 1))
            out.emit(f'{pad}}}\n')
            return [('stmt', f'(.if {self.lean_expr(ids, s[1])} {a} {b})')]
        if kind == 'while':
            out.emit(f'{pad}while ({self.lani_expr(s[1])}) {{\n')
            body = nest(self.stmt(k, ids, s[2], indent + 1))
            out.emit(f'{pad}}}\n')
            return [('stmt', f'(.while {self.lean_expr(ids, s[1])} {body})')]
        out.emit(f'{pad}return {self.lani_expr(s[1])};\n')
        return [('stmt', f'(.return {self.lean_expr(ids, s[1])})')]

    def program(self, k):
        """Print program k; return its functions' expected Lean terms."""
        p, out = self.programs[k], self.out
        oracle.TYPES = p
        for j, fields in enumerate(p.structs):
            out.emit(f'struct P{k}S{j} {{ ' + ', '.join(f'f{i}: {self.ty(k, f)}' for i, f in enumerate(fields)) + ' }\n')
        for j, variants in enumerate(p.enums):
            out.emit(f'enum P{k}E{j} {{\n')
            for v, payload in enumerate(variants):
                inner = '(' + ', '.join(self.ty(k, f) for f in payload) + ')' if payload else ''
                out.emit(f'    P{k}E{j}V{v}{inner},\n')
            out.emit('}\n')
        funcs = []
        for j, (params, ret, body) in enumerate(p):
            ids = {}
            out.emit(f'fn p{k}_f{j}(')
            for i, t in enumerate(params):
                if i:
                    out.emit(', ')
                out.bind((k, (j, i)), f'v{i}')
                ids[i] = out.binding[(k, (j, i))]
                out.emit(f': {self.ty(k, t)}')
            out.emit(f') -> {self.ty(k, ret)} {{\n')
            items = self.stmt(k, ids, body, 1)
            out.emit('}\n\n')
            ps = ', '.join(f'{{ id := {ids[i]}, ty := {self.lean_ty(k, t)} }}' for i, t in enumerate(params))
            funcs.append(f'{{ params := [{ps}], ret := {self.lean_ty(k, ret)}, body := {nest(items)} }}')
        return funcs


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


def parse_with_laniusc(heavy, laniusc, lani_path, workdir):
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
    stage = 'x86_64'
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
  | .uint8 => ".uint8" | .uint32 => ".uint32" | .uint64 => ".uint64" | .usize => ".usize"

def serOp : SrcOp → String
  | .plus => "plus" | .minus => "minus" | .times => "times" | .bitAnd => "bitAnd"
  | .bitOr => "bitOr" | .bitXor => "bitXor" | .less => "less" | .lessEq => "lessEq"
  | .greater => "greater" | .greaterEq => "greaterEq" | .equal => "equal"
  | .notEqual => "notEqual" | .logicalAnd => "logicalAnd" | .logicalOr => "logicalOr"

def bracket (xs : List String) : String := "[" ++ ", ".intercalate xs ++ "]"

partial def serType : SrcType → String
  | .i32 => ".i32" | .bool => ".bool" | .ptr => ".ptr"
  | .uint u => s!"(.uint {serTy u})"
  | .struct n fs => s!"(.struct {n} {bracket (fs.map serType)})"
  | .enum n vs => s!"(.enum {n} {bracket (vs.map fun v => bracket (v.map serType))})"
  | .slice t => s!"(.slice {serType t})"

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

def serExprs (es : List SrcExpr) : String := bracket (es.map serExpr)

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
  | .letAlloc .. | .letLoad .. | .setByte .. | .free .. | .letSlice .. | .letIndex .. | .setIndex .. => "(heap)"

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
'''


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=100)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--chunk', type=int, default=25)
    parser.add_argument('--mutations', type=int, default=3)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--heavy', default=HEAVY)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    programs = [oracle.gen_program(rng) for _ in range(args.count)]
    workdir = os.path.abspath(args.workdir)
    os.makedirs(workdir, exist_ok=True)
    lean = [LEAN_HEAD]
    problems = 0
    tokens_total = nodes_total = mutations = 0
    for c, start in enumerate(range(0, len(programs), args.chunk)):
        chunk = Chunk(programs[start:start + args.chunk])
        funcs = []
        for k in range(len(chunk.programs)):
            funcs += chunk.program(k)
        base = os.path.join(workdir, f'chunk{c}')
        text = chunk.out.text()
        open(base + '.lani', 'w').write(text)
        prods, parents, tokens = parse_with_laniusc(args.heavy, args.laniusc, base + '.lani', workdir)
        tokens_total += len(tokens)
        nodes_total += len(prods)
        open(base + '.prods', 'w').write(' '.join(map(str, prods)))
        open(base + '.parents', 'w').write(' '.join(map(str, parents)))
        open(base + '.gputokens', 'w').write(' '.join(f'{k}:{s}:{n}' for k, s, n in tokens))
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
        lean.append(f'#eval check "{base}" [{", ".join(mutants)}]')
    lean_path = os.path.join(workdir, 'frontend_check.lean')
    open(lean_path, 'w').write('\n'.join(lean) + '\n')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    run = subprocess.run(['lake', 'env', 'lean', lean_path], cwd='formal', env=env, capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit('lean failed:\n' + run.stdout[-4000:] + run.stderr[-4000:])
    lines = run.stdout.strip().split('\n')
    for line in lines:
        if not (line.endswith(': read') or line.endswith(': rejected')):
            print(line)
            problems += 1
    rejected = sum(line.endswith(': rejected') for line in lines)
    lexer_diffs = oks = 0
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
        if not os.path.exists(base + '.leantokens'):
            continue
        if open(base + '.leantokens').read().split() != open(base + '.gputokens').read().split():
            print(f'{base}: the Lean lexer and laniusc disagree')
            lexer_diffs += 1
    problems += lexer_diffs
    print(f'{len(programs)} programs in {oks} files read as expected, {tokens_total} tokens, {nodes_total} tree nodes; '
          f'{rejected}/{mutations} mutations rejected; {lexer_diffs} lexer disagreements; {problems} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
