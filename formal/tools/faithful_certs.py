#!/usr/bin/env python3
"""The extraction certificates of a program dumped by faithful_dump.py.

    python3 -I formal/tools/faithful_certs.py [--dev] DUMP NS OUTDIR [ROOT...]

DUMP is the Lean file faithful_dump.py wrote (namespace NS, with DUMP.meta
next to it). OUTDIR gets Lean modules (module system), every name the
function's Lanius name (`keys`), never its index:

  SelfTypes, SelfRep  the program's named types; one inductive `Rep<Name>`
              per struct and enum, its constructors `rep_rule`s;
  SelfSrc<B>  each function's source with its callees' indices as
              parameters (`src_name ix..`), bodies hidden;
  SelfStmt<B> each certificate's statement for any program, prims and index
              (`Stmt_name prog prims ix n`): a pure run with fuel n on values
              representing Lean arguments returns a value representing the
              extracted Lean function at those arguments;
  SelfProof<B> its proof (`proof_name`, or `step_name` in a recursive group)
              from the callees' certificates as hypotheses;
  SelfProg    the program (`prog`) and its prims;
  SelfLook<B> where each function is in it (`fn_name`) and whether it is a
              prim (`np_name`);
  SelfCert    `cert_name`: each proof at the program's indices, recursive
              groups by induction on the fuel, callees first.

A bucket B is the extraction part a function's proof unfolds (`C_<part>`,
`F_<part>`), else a hash of its name, so a changed body rebuilds one proof
module.

--dev proves with `faithful_dev`, which admits what it cannot prove and
warns, for working on the tactic. With ROOTs (names as the certificates
spell them after `cert_`, or indices), only the functions they call, directly
or not, get certificates. The Lean meaning of each function is its extraction
(formal/tools/extract.py): `name` or `Type.name` for a method, the list
operations and the prelude's arithmetic as the Lean terms the extraction
writes for their calls, and `Inline.name` (extract.py --inline) for an
`// extract: inline` function.
"""

import os
import re
import sys
import zlib

SCALAR_LEAN = {'usize': 'Nat', 'u64': 'BitVec 64', 'u32': 'BitVec 32', 'i32': 'BitVec 32', 'u8': 'UInt8',
               'bool': 'Bool'}
SCALAR_REP = {'usize': 'RepNat', 'u64': 'RepU64', 'u32': 'RepU32', 'i32': 'RepI32', 'u8': 'RepU8',
              'bool': 'RepBool'}
SELF = 'mini::selfhost::'
LIST, BOX, OPTION = SELF + 'List', SELF + 'Box', 'core::option::Option'
PRIMS = {SELF + 'boxed', SELF + 'unbox'}
SKIP = ('app::', 'core::mem::', 'alloc::')
PANIC = 'core::panic::panic'
# The list operations and the prelude's arithmetic: the Lean term of a call.
TERMS = {
    'empty': lambda xs, ret: f'([] : {ret})',
    'single': lambda xs, ret: f'[{xs[0]}]',
    'cons': lambda xs, ret: f'{xs[0]} :: {xs[1]}',
    'concat': lambda xs, ret: f'{xs[0]} ++ {xs[1]}',
    'length': lambda xs, ret: f'{xs[0]}.length',
    'get': lambda xs, ret: f'{xs[0]}[{xs[1]}]?',
    'get_or': lambda xs, ret: f'{xs[0]}.getD {xs[1]} {xs[2]}',
    'plus': lambda xs, ret: f'{xs[0]} + {xs[1]}',
    'minus': lambda xs, ret: f'{xs[0]} - {xs[1]}',
    'times': lambda xs, ret: f'{xs[0]} * {xs[1]}',
    'max_of': lambda xs, ret: f'max {xs[0]} {xs[1]}',
}
TACTIC = 'faithful'
GENERIC_TERMS = {'empty', 'single', 'cons', 'concat', 'length', 'get', 'get_or'}


def camel(name):
    parts = name.split('_')
    return parts[0] + ''.join(p[:1].upper() + p[1:] for p in parts[1:])


def lower_first(name):
    return name[:1].lower() + name[1:]


def atom(text):
    return f'({text})' if ' ' in text else text


class Program:
    def __init__(self, dump):
        self.fns, self.types, self.shapes, self.sigs = {}, {}, {}, {}
        for line in open(dump + '.meta'):
            p = line.split()
            if not p:
                continue
            if p[0] == 'fn':
                self.fns[int(p[1])] = {'name': p[2], 'self': p[3], 'args': p[4]}
            elif p[0] == 'type':
                self.types[int(p[1])] = {'name': p[2], 'args': p[3], 'kind': p[4], 'names': p[5:]}
            elif p[0] == 'shape':
                self.shapes[int(p[1])] = p[2] if len(p) > 2 else ''
            elif p[0] == 'sig':
                params = [] if p[2] == '-' else p[2].split(',')
                calls = [] if p[4] == '-' else [int(c) for c in p[4].split(',')]
                self.sigs[int(p[1])] = {'params': params, 'ret': p[3], 'calls': calls}
        self.by_text = {}
        for i, t in self.types.items():
            self.by_text[t['name'] if t['args'] == '-' else f'{t["name"]}<{t["args"]}>'] = f'#{i}'
        self.bodies, self.named = {}, {}
        for line in open(dump):
            m = re.match(r'def src(\d+) : SrcFunc := (.*)$', line)
            if m:
                self.bodies[int(m.group(1))] = m.group(2)
            m = re.match(r'def ty(\d+) : SrcType := \.(struct|enum) (\d+) ', line)
            if m:
                self.named[int(m.group(1))] = int(m.group(3))

    # types ------------------------------------------------------------

    def variants(self, i):
        spec = self.shapes[i]
        if self.types[i]['kind'] == 'struct':
            return [[f for f in spec.split(',') if f]]
        return [[f for f in v.split(',') if f] for v in spec.split('|')]

    def type_id(self, tok):
        return int(tok[1:])

    def element(self, tok):
        """The element of a List, Option or Box instance."""
        i = self.type_id(tok)
        t = self.types[i]
        if t['name'] == OPTION:
            return self.variants(i)[0][0]
        if t['name'] == LIST:
            return self.variants(i)[1][0]
        if t['name'] == BOX:
            return self.by_text.get(t['args'], t['args'])
        raise ValueError(tok)

    def kind(self, tok):
        if tok in SCALAR_LEAN:
            return 'scalar'
        if not tok.startswith('#'):
            raise ValueError(f'type {tok} has no Lean meaning')
        name = self.types[self.type_id(tok)]['name']
        return {LIST: 'list', OPTION: 'option', BOX: 'box'}.get(name, 'user')

    def short(self, tok):
        return self.types[self.type_id(tok)]['name'].split('::')[-1]

    def lean(self, tok):
        k = self.kind(tok)
        if k == 'scalar':
            return SCALAR_LEAN[tok]
        if k == 'list':
            return f'List {atom(self.lean(self.element(tok)))}'
        if k == 'option':
            return f'Option {atom(self.lean(self.element(tok)))}'
        if k == 'box':
            return self.lean(self.element(tok))
        return f'Lanius.Mini.{self.short(tok)}'

    def rep(self, tok):
        k = self.kind(tok)
        if k == 'scalar':
            return SCALAR_REP[tok]
        if k == 'list':
            return f'(RepList {self.type_id(tok)} {self.rep(self.element(tok))})'
        if k == 'option':
            return f'(RepOption {self.type_id(tok)} {self.rep(self.element(tok))})'
        if k == 'box':
            return self.rep(self.element(tok))
        return f'Rep{self.short(tok)}'

    def user_deps(self, tok):
        """The user types a value of this type contains, through the generic ones."""
        k = self.kind(tok)
        if k == 'scalar':
            return set()
        if k in ('list', 'option', 'box'):
            return self.user_deps(self.element(tok))
        return {tok}

    # functions --------------------------------------------------------

    def role(self, i):
        f = self.fns[i]
        name = f['name']
        if name in PRIMS:
            return 'prim'
        if name == PANIC:
            return 'panic'
        if name.startswith(SKIP):
            return 'skip'
        if name == '?':
            return 'field'
        return 'fn'

    def term(self, i, xs, inline):
        """The extracted Lean term of a call of function i on xs."""
        f, sig = self.fns[i], self.sigs[i]
        if self.role(i) == 'field':
            m = re.search(r'body := SrcStmt\.return \(SrcExpr\.field (\d+) (\d+)\) \}$', self.bodies[i])
            param = self.sigs[i]['params'][0]
            field = self.types[self.type_id(param)]['names'][int(m.group(2))]
            return f'{atom(xs[0])}.{camel(field)}'
        base = f['name'][len(SELF):] if f['name'].startswith(SELF) else f['name']
        if base in TERMS and (f['args'] != '-' or base not in GENERIC_TERMS):
            return TERMS[base](xs, self.lean(sig['ret']))
        if f['self'] != '-':
            head = f'Lanius.Mini.{f["self"]}.{camel(base)}'
        elif camel(base) in inline:
            head = f'Lanius.Mini.Inline.{camel(base)}'
        else:
            head = f'Lanius.Mini.{camel(base)}'
        return ' '.join([head] + [atom(x) for x in xs])

    def head(self, i, inline):
        """The definition a certificate's proof unfolds, if any."""
        t = self.term(i, ['x'] * len(self.sigs[i]['params']), inline)
        m = re.match(r'(Lanius\.Mini\.[A-Za-z0-9_.]+)', t)
        return m.group(1) if m else None


def sccs(nodes, edges):
    """Tarjan: strongly connected components, callees first."""
    index, low, stack, on, out = {}, {}, [], set(), []
    counter = [0]
    sys.setrecursionlimit(100000)

    def visit(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in edges(v):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            out.append(sorted(comp))

    for v in nodes:
        if v not in index:
            visit(v)
    return out


def rep_file(prog, ns, out_ns, wanted):
    """The representations of the types of the wanted functions."""
    deps, todo = {}, []
    for i in wanted:
        for tok in prog.sigs[i]['params'] + [prog.sigs[i]['ret']]:
            if tok.startswith('#') or tok in SCALAR_LEAN:
                todo += prog.user_deps(tok)
    while todo:
        tok = todo.pop()
        if tok in deps:
            continue
        deps[tok] = set()
        for variant in prog.variants(prog.type_id(tok)):
            for field in variant:
                deps[tok] |= prog.user_deps(field)
        todo += deps[tok]
    users = sorted(deps, key=prog.type_id)
    lines = [f'module\n\npublic import Lanius.Faithful.Rep\npublic import Lanius.Mini.Frontend.Types\n'
             f'public import {ns_module(ns)}Types\n\n@[expose] public section\n',
             f'/-! Generated by formal/tools/faithful_certs.py: the representations of the\n'
             f'types of `{ns}.prog`. Do not edit. -/\n',
             f'namespace {out_ns}\n', 'open Lanius.Mini', 'open Lanius.Core (Value)', 'open Lanius.Faithful',
             f'open {ns}\n']
    rules = []
    for comp in sccs(users, lambda t: sorted(deps[t], key=prog.type_id)):
        mutual = len(comp) > 1 or comp[0] in deps[comp[0]]
        if len(comp) > 1:
            lines.append('mutual')
        for tok in comp:
            i, name = prog.type_id(tok), prog.short(tok)
            t = prog.types[i]
            lines.append(f'inductive Rep{name} : Lanius.Mini.{name} → Value → Prop where')
            for k, fields in enumerate(prog.variants(i)):
                xs = [f'x{j}' for j in range(len(fields))]
                vs = [f'v{j}' for j in range(len(fields))]
                binders = ''.join(f' {{x{j} : {prog.lean(f)}}}' for j, f in enumerate(fields))
                binders += f' {{{" ".join(vs)} : Value}}' if fields else ''
                prems = ''.join(f'{prog.rep(f)} x{j} v{j} → ' for j, f in enumerate(fields))
                if t['kind'] == 'struct':
                    ctor = f'Lanius.Mini.{name}.mk'
                    value = f'.structure {i} [{", ".join(vs)}]'
                else:
                    ctor = f'Lanius.Mini.{name}.{lower_first(t["names"][k])}'
                    value = f'.enumeration {i} {k} [{", ".join(vs)}]'
                lean_value = ' '.join([ctor] + xs)
                lines.append(f'  | c{k}{binders} :')
                lines.append(f'      {prems}Rep{name} ({lean_value}) ({value})')
                rules.append(f'Rep{name}.c{k}')
        if len(comp) > 1:
            lines.append('end')
        lines.append('')
    for k in range(0, len(rules), 8):
        lines.append(f'attribute [rep_rule] {" ".join(rules[k:k + 8])}')
    lines.append('')
    for k, i in sorted(prog.named.items()):
        lines.append(f'@[pure_rule] theorem ty{k}_typeId : ty{k}.typeId = {i} := rfl')
    lines.append(f'\nend {out_ns}\n')
    return '\n'.join(lines)


def ns_module(ns):
    return {'Lanius.Faithful.Self': 'Lanius.Faithful.Gen.Self'}[ns]


# Functions without an extraction part (prims, fields, list operations) by
# hashed name.
BUCKETS = 8


def keys(prog):
    """A Lean name for each function, from its Lanius name, not its index: what
    the sources, proofs and certificates are named by, so that adding a
    function renames nothing."""
    out, seen = {}, {}
    for i, f in sorted(prog.fns.items()):
        name = f['name'][len(SELF):] if f['name'].startswith(SELF) else f['name']
        if prog.role(i) == 'field':
            name = 'field_' + prog.term(i, ['x'], set()).split('.', 1)[1] + '_' + f['args'].split('::')[-1]
        if f['self'] != '-':
            name = f['self'] + '_' + name
        if f['args'] != '-':
            name += '_of_' + f['args']
        key = re.sub(r'_+', '_', re.sub(r'[^A-Za-z0-9]', '_', name)).strip('_')
        if key in seen:
            key += f'_{zlib.crc32((f["name"] + f["self"] + f["args"]).encode()) % 100000}'
        seen[key] = i
        out[i] = key
    return out


def bucket(key):
    return zlib.crc32(key.encode()) % BUCKETS


def call_sites(body):
    """The callee indices of a source body: (start, end, index) of each."""
    out = []
    for m in re.finditer(r'SrcEff\.eCall (\d+)', body):
        out.append((m.start(1), m.end(1), int(m.group(1))))
    for m in re.finditer(r'SrcStmt\.setCall \d+ (\d+)', body):
        out.append((m.start(1), m.end(1), int(m.group(1))))
    for m in re.finditer(r'SrcStmt\.letCall \d+ ', body):
        k = m.end()
        if body[k] == '(':
            depth = 0
            while True:
                depth += {'(': 1, ')': -1}.get(body[k], 0)
                k += 1
                if depth == 0:
                    break
        else:
            while body[k] != ' ':
                k += 1
        c = re.match(r' (\d+)', body[k:])
        out.append((k + 1, k + 1 + len(c.group(1)), int(c.group(1))))
    return sorted(out)


def callees(prog, i):
    return sorted({c for _, _, c in call_sites(prog.bodies[i])})


def src_def(prog, key, i):
    """`src_K (ix_C ..) : SrcFunc`: the source of function i with its callees'
    indices as parameters."""
    body = prog.bodies[i]
    out, last = [], 0
    for a, b, c in call_sites(body):
        out.append(body[last:a] + f'ix_{key[c]}')
        last = b
    out.append(body[last:])
    params = ''.join(f' (ix_{key[c]} : Nat)' for c in callees(prog, i))
    return f'/-- {prog.fns[i]["name"]} -/\ndef src_{key[i]}{params} : SrcFunc := {"".join(out)}'


def stmt(prog, i, inline, ix, n):
    """Function i's certificate with fuel n at index ix, of `prog` and `prims`:
    a pure run on values representing Lean arguments returns a value
    representing the extracted Lean function at those arguments."""
    sig, role = prog.sigs[i], prog.role(i)
    k = len(sig['params'])
    vs = ', '.join(f'v{j}' for j in range(k))
    if role == 'panic':
        return f'∀ {{vs : List Value}} {{w : Value}}, pcall prog prims {n} {ix} vs = some w → False'
    binders = ''.join(f'{{x{j} : {prog.lean(p)}}} ' for j, p in enumerate(sig['params']))
    binders += f'{{{" ".join([f"v{j}" for j in range(k)] + ["w"])} : Value}}'
    prems = ''.join(f' {prog.rep(p)} x{j} v{j} →' for j, p in enumerate(sig['params']))
    if role == 'prim':
        result = f'{prog.rep(sig["params"][0])} x0 w'
    else:
        result = f'{prog.rep(sig["ret"])} ({prog.term(i, [f"x{j}" for j in range(k)], inline)}) w'
    return f'∀ {binders}, pcall prog prims {n} {ix} [{vs}] = some w →{prems}\n    {result}'


def stmt_ref(key, i, ix, n):
    """Function i's statement by name (`SelfStmt*`): proofs and the link
    state it without elaborating it again."""
    return f'Stmt_{key[i]} prog prims {ix} {n}'


def is_recursive(prog, comp):
    return prog.role(comp[0]) == 'fn' and (len(comp) > 1 or comp[0] in prog.sigs[comp[0]]['calls'])


def intro(prog, i):
    n = len(prog.sigs[i]['params'])
    if prog.role(i) == 'panic':
        return 'intro vs w h'
    return 'intro ' + ' '.join([f'x{j}' for j in range(n)] + [f'v{j}' for j in range(n)] +
                               ['w', 'h'] + [f'r{j}' for j in range(n)])


def ixs(prog, key, i):
    """The index parameters of i's proof: its own, then its callees'."""
    return [i] + [c for c in callees(prog, i) if c != i]


def proof(prog, key, comp, i, inline, wanted):
    """Function i's certificate for any program and prims in which it is at
    `ix_K` with its source, `proof_K`, from the certificates `ext_C` of its
    callees outside its recursive group; for a member of a recursive group,
    the step `step_K`: one more unit of fuel, from those of the group (`ih_J`)
    with `n`. Nothing in it depends on other functions' indices or sources."""
    K = key[i]
    binders = f'{{prog : SrcProgram}} {{prims : Prims}} {{{" ".join(f"ix_{key[c]}" for c in ixs(prog, key, i))} : Nat}}'
    if prog.role(i) == 'prim':
        binders = f'{{prog : SrcProgram}} {{prims : Prims}} {{ix_{K} : Nat}}'
        return (f'theorem proof_{K} {binders} (np : prims.isPrim ix_{K} = true) {{n : Nat}} :\n'
                f'    {stmt_ref(key, i, f"ix_{K}", "n")} :=\n  fun h r => prim_cert np h r\n')
    args = ' '.join(f'ix_{key[c]}' for c in callees(prog, i))
    hyps = (f' (fn : prog.funcs[ix_{K}]? = some (src_{K}{" " + args if args else ""}))'
            f' (np : prims.isPrim ix_{K} = false)')
    hyps += ''.join(f'\n    (ext_{key[c]} : Certified (∀ {{n : Nat}}, {stmt_ref(key, c, f"ix_{key[c]}", "n")}))'
                    for c in externals(prog, i, comp, wanted))
    heads = [h for h in [prog.head(i, inline)] if h] if prog.role(i) == 'fn' else []
    body = ['  rw [pcall_succ np fn] at h', f'  simp only [src_{K}] at h', f'  {TACTIC} [{", ".join(heads)}]']
    if not is_recursive(prog, comp):
        return '\n'.join([f'theorem proof_{K} {binders}{hyps} {{n : Nat}} :',
                          f'    {stmt_ref(key, i, f"ix_{K}", "n")} := by', f'  {intro(prog, i)}',
                          '  rcases n with _ | n', '  · simp [pcall] at h'] + body) + '\n'
    ihs = ''.join(f'\n    (ih_{key[j]} : Certified ({stmt_ref(key, j, f"ix_{key[j]}", "n")}))'
                  for j in inners(prog, i, comp))
    return '\n'.join([f'theorem step_{K} {binders}{hyps} {{n : Nat}}{ihs} :',
                      f'    {stmt_ref(key, i, f"ix_{K}", "(n + 1)")} := by',
                      f'  {intro(prog, i)}'] + body) + '\n'


def externals(prog, i, comp, wanted):
    """The callees of `i` outside its recursive group `comp`, in a fixed order."""
    if prog.role(i) != 'fn':
        return []
    return [c for c in callees(prog, i) if c in wanted and c not in comp]


def inners(prog, i, comp):
    """The callees of `i` within its recursive group."""
    return [j for j in comp if j in callees(prog, i)]


# The definitions whose proofs unfold a callee too, where it meets a
# constructor: their proofs also see the parts of the definitions their bodies
# name. (A proof that fails only because a body is hidden needs its head here.)
CALLEE_BODIES = {'Lanius.Mini.effNode', 'Lanius.Mini.exprOf', 'Lanius.Mini.peel'}


class Parts:
    """Where the extraction defines each Lean name (extract.py's parts), and
    the parts a proof that unfolds a definition imports with `import all`: its
    own, and for the heads in CALLEE_BODIES those of the definitions its body
    names."""

    def __init__(self, formal):
        self.where, self.body = {}, {}
        for base in ['Compiler', 'Frontend']:
            d = os.path.join(formal, 'Lanius/Mini', base, 'P')
            for n in sorted(os.listdir(d)):
                if n.endswith('.lean'):
                    self.scan(open(os.path.join(d, n)).read(), f'Lanius.Mini.{base}.P.{n[:-5]}')
        self.short = {}
        for name in self.where:
            self.short.setdefault(name.rsplit('.', 1)[-1], set()).add(name)
        self.inline = {n[len('Lanius.Mini.Inline.'):] for n in self.where if n.startswith('Lanius.Mini.Inline.')}

    def scan(self, text, module):
        for chunk in re.split(r'\n(?=(?:/--.*\n)?(?:@\[expose\] )?(?:def|theorem|structure|inductive) )', text):
            m = re.search(r'^(?:@\[expose\] )?def ([A-Za-z0-9_.]+)', chunk, re.M)
            if m:
                name = 'Lanius.Mini.' + m.group(1)
                self.where[name], self.body[name] = module, chunk

    def defining(self, head):
        return {self.where[head]} if head in self.where else set()

    def of(self, head):
        if head not in CALLEE_BODIES:
            return self.defining(head)
        body = self.body[head].split(':=', 1)[-1]
        names = {head}
        for tok in set(re.findall(r'(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*', body)):
            if 'Lanius.Mini.' + tok in self.where:
                names.add('Lanius.Mini.' + tok)
            elif '.' in tok and tok.split('.')[0][:1].islower():
                names |= self.short.get(tok.rsplit('.', 1)[-1], set())
        for tok in set(re.findall(r'\)\.([A-Za-z_][A-Za-z0-9_]*)', body)):
            names |= self.short.get(tok, set())
        return {self.where[n] for n in names if self.where.get(n)}


HEAD = ['set_option maxHeartbeats 10000000\nset_option maxRecDepth 100000\nset_option linter.unusedVariables false\n']


def opens(ns, out_ns):
    return [f'namespace {out_ns}\n', 'open Lanius.Mini', 'open Lanius.Core (Value)', 'open Lanius.Faithful',
            f'open {ns}', f'open {ns}Rep\n']


def cert_files(prog, ns, out_ns, roots, parts):
    """The certificates as Lean modules (module system), by function name:
    `SelfSrcB` has the sources of the functions in bucket B (hashed names),
    bodies hidden; `SelfProofB` proves each of them for any program and prims
    that hold it, from its callees' certificates as hypotheses, seeing by
    `import all` only its own sources and the extraction's parts it unfolds;
    `SelfProg` is the program and its prims, `SelfLookB` where each function
    of bucket B is in it, and `SelfCert` instantiates the proofs, callees
    first. A changed body rebuilds its part, its source bucket and the proofs
    that unfold it; adding a function rebuilds the proofs whose functions
    reach it, and the program side. Returns the module texts by name."""
    inline, key = parts.inline, keys(prog)
    mod = ns_module(ns)
    wanted = set()
    todo = list(roots)
    while todo:
        i = todo.pop()
        if i in wanted or prog.role(i) == 'skip':
            continue
        wanted.add(i)
        if prog.role(i) == 'fn':
            todo += callees(prog, i)
    order = sccs(sorted(wanted), lambda i: [c for c in callees(prog, i) if c in wanted])
    comp_of = {i: comp for comp in order for i in comp}
    texts = {}
    by_bucket = {}

    def bucket_of(i):
        # A function whose proof unfolds an extraction part goes with that
        # part's other heads: a body edit rebuilds one proof module.
        part = parts.where.get(prog.head(i, inline)) if prog.role(i) == 'fn' else None
        if part:
            return part.split('.')[2][0] + '_' + part.rsplit('.', 1)[1]
        return str(bucket(key[i]))
    for i in sorted(prog.fns):
        by_bucket.setdefault(bucket_of(i) if i in wanted else 'Rest', []).append(i)
    buckets = sorted(b for b in by_bucket if b != 'Rest')
    for b, fns in by_bucket.items():
        texts[f'SelfSrc{b}'] = (
            f'module\n\npublic import {mod}Types\n\npublic section\n\n'
            f'/-! Generated by formal/tools/faithful_certs.py: sources of `{ns}.prog`, bucket {b}, with\n'
            f'their callees\' indices as parameters. Do not edit. -/\n\n'
            f'namespace {ns}\n\nopen Lanius.Mini\n\nnoncomputable section\n\n' +
            '\n\n'.join(src_def(prog, key, i) for i in sorted(fns, key=lambda i: key[i])) +
            f'\n\nend\n\nend {ns}\n')
    for b in buckets:
        mine = sorted(by_bucket[b], key=lambda i: key[i])
        heads = set().union(*(parts.defining(prog.head(i, inline)) for i in mine))
        texts[f'SelfStmt{b}'] = '\n'.join(
            ['module\n\npublic import Lanius.Faithful.Gen.SelfRep\n' +
             ''.join(f'public import {m}\n' for m in sorted(heads)) + '\n@[expose] public section\n',
             f'/-! Generated by formal/tools/faithful_certs.py: the certificates\' statements of the\n'
             f'functions of bucket {b}, at any index of any program. Do not edit. -/\n'] + HEAD + opens(ns, out_ns) +
            [f'abbrev Stmt_{key[i]} (prog : SrcProgram) (prims : Prims) (ix n : Nat) : Prop :=\n  '
             f'{stmt(prog, i, inline, "ix", "n")}\n' for i in mine] + [f'end {out_ns}\n'])
    for b in buckets:
        mine = sorted(by_bucket[b], key=lambda i: key[i])
        stated, unfolded = set(), set()
        for i in mine:
            unfolded |= parts.of(prog.head(i, inline))
            for c in [i] + callees(prog, i):
                stated.add(f'{mod}Stmt{bucket_of(c)}')
        lines = ['module\n\npublic import Lanius.Faithful.Auto\npublic import Lanius.Faithful.Gen.SelfRep\n' +
                 f'public import {mod}Src{b}\n' + ''.join(f'public import {m}\n' for m in sorted(stated)) +
                 f'import all {mod}Src{b}\n' + ''.join(f'import all {m}\n' for m in sorted(unfolded)) +
                 '\npublic section\n',
                 f'/-! Generated by formal/tools/faithful_certs.py: extraction certificates of the\n'
                 f'functions of bucket {b}, for any program that holds them. Do not edit. -/\n'] + HEAD + opens(ns, out_ns)
        for i in mine:
            lines.append(proof(prog, key, comp_of[i], i, inline, wanted))
        lines.append(f'end {out_ns}\n')
        texts[f'SelfProof{b}'] = '\n'.join(lines)
    prims = {'boxed': [], 'unbox': []}
    for i, f in sorted(prog.fns.items()):
        if f['name'] in PRIMS:
            prims[f['name'][len(SELF):]].append(str(i))
    srcs = ', '.join(f'src_{key[i]}' + ''.join(f' {c}' for c in callees(prog, i)) for i in sorted(prog.fns))
    texts['SelfProg'] = (
        'module\n\n' + ''.join(f'public import {mod}Src{b}\n' for b in sorted(by_bucket, key=str)) +
        f'public import Lanius.Faithful.Pure\n\n@[expose] public section\n\n'
        f'/-! Generated by formal/tools/faithful_certs.py: the program, its functions\' sources\n'
        f'at their indices, and its prims. Do not edit. -/\n\n'
        f'namespace {ns}\n\nopen Lanius.Mini\nopen Lanius.Faithful\n\nnoncomputable section\n\n'
        f'def prog : SrcProgram := {{ funcs := [{srcs}] }}\n\n'
        f'def _root_.Lanius.Faithful.SelfRep.prims : Prims :=\n  {{ boxed := [{", ".join(prims["boxed"])}],\n'
        f'    unbox := [{", ".join(prims["unbox"])}] }}\n\n' +
        ''.join(f'abbrev src{i} : SrcFunc := src_{key[i]}' + ''.join(f' {c}' for c in callees(prog, i)) + '\n'
                for i in sorted(prog.fns)) +
        f'\nend\n\nend {ns}\n')
    # Where each function is (`rfl`, about 50 ms each at depth 800) and
    # whether it is a prim (about 30 ms by `rfl`, less by the kernel alone): in
    # buckets, which a body edit leaves alone, rather than in the link.
    for b in buckets:
        mine = sorted(by_bucket[b], key=lambda i: key[i])
        texts[f'SelfLook{b}'] = (
            f'module\n\npublic import {mod}Prog\n\n@[expose] public section\n\n'
            f'/-! Generated by formal/tools/faithful_certs.py. Do not edit. -/\n\n'
            f'set_option maxRecDepth 100000\n\nnamespace {out_ns}\n\nopen {ns}\nopen {ns}Rep\n\n' +
            ''.join(f'theorem fn_{key[i]} : prog.funcs[{i}]? = some (src_{key[i]}' +
                    ''.join(f' {c}' for c in callees(prog, i)) + ') := rfl\n'
                    for i in mine if prog.role(i) != 'prim') +
            ''.join(f'theorem np_{key[i]} : prims.isPrim {i} = {str(prog.role(i) == "prim").lower()} := by decide +kernel\n'
                    for i in mine) +
            f'\nend {out_ns}\n')
    link = ['module\n\n' + ''.join(f'public import {mod}Proof{b}\npublic import {mod}Look{b}\n'
                                    for b in buckets) + '\npublic section\n',
            f'/-! Generated by formal/tools/faithful_certs.py: every certificate of `{ns}.prog`,\n'
            f'each proof given the program, its index and its callees\' certificates. Do not edit. -/\n'] + \
        HEAD + opens(ns, out_ns)

    def app(i, comp, n, ih):
        K = key[i]
        if prog.role(i) == 'prim':
            return f'@proof_{K} prog prims {i} np_{K} {n}'
        ix = ' '.join(str(c) for c in ixs(prog, key, i))
        ext = ' '.join(f'⟨@cert_{key[c]}⟩' for c in externals(prog, i, comp, wanted))
        name = 'step' if ih else 'proof'
        tail = ' '.join(f'⟨ih_{key[j]}⟩' for j in inners(prog, i, comp)) if ih else ''
        return ' '.join(x for x in [f'@{name}_{K} prog prims {ix} fn_{K} np_{K}', ext, n, tail] if x)
    for comp in order:
        if not is_recursive(prog, comp):
            i = comp[0]
            link.append(f'theorem cert_{key[i]} {{n : Nat}} :\n    {stmt_ref(key, i, str(i), "n")} :=\n'
                        f'  {app(i, comp, "n", False)}\n')
            continue
        first = key[comp[0]]
        conj = ' ∧ '.join(f'({stmt_ref(key, i, str(i), "n")})' for i in comp)
        lines = [f'theorem certs_{first} : ∀ n, {conj} := by', '  intro n', '  induction n with', '  | zero =>']
        zero = ', '.join(f'(by {intro(prog, i)}; simp [pcall] at h)' for i in comp)
        lines.append(f'    exact ⟨{zero}⟩' if len(comp) > 1 else f'    exact {zero}')
        lines.append('  | succ n ih =>')
        if len(comp) > 1:
            lines.append(f'    obtain ⟨{", ".join(f"ih_{key[i]}" for i in comp)}⟩ := ih')
        else:
            lines.append(f'    have ih_{first} : {stmt_ref(key, comp[0], str(comp[0]), "n")} := ih')
        steps = [app(i, comp, 'n', True) for i in comp]
        lines.append(f'    exact ⟨{", ".join(steps)}⟩' if len(comp) > 1 else f'    exact {steps[0]}')
        lines.append('')
        for k, i in enumerate(comp):
            pick = '' if len(comp) == 1 else '.' + '.'.join(['2'] * k + (['1'] if k < len(comp) - 1 else []))
            lines.append(f'theorem cert_{key[i]} {{n : Nat}} :\n    {stmt_ref(key, i, str(i), "n")} :=\n'
                         f'  (certs_{first} n){pick}')
        link.append('\n'.join(lines) + '\n')
    link.append(f'\nend {out_ns}\n')
    texts['SelfCert'] = '\n'.join(link)
    return texts, wanted


def types_file(dump, ns):
    """`SelfTypes`: the dump's named types (exposed)."""
    text = open(dump).read()
    first = text.index('\n/-- ', text.index('noncomputable section'))
    head_lines = text[:first].split('\n')
    preamble = '\n'.join(l for l in head_lines if not l.startswith('import ')).strip('\n')
    tys = '\n'.join(l for l in preamble.split('\n') if l.startswith('def ty'))
    preamble = '\n'.join(l for l in preamble.split('\n') if not l.startswith('def ty')).rstrip() + '\n'
    return ('module\n\npublic import Lanius.Mini.Compiler.Types\n\n@[expose] public section\n\n' +
            preamble + '\n' + tys + '\n\nend\n\nend ' + ns + '\n')


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    global TACTIC
    args = sys.argv[1:]
    if '--dev' in args:
        args.remove('--dev')
        TACTIC = 'faithful_dev'
    dump, ns, outdir = args[:3]
    prog = Program(dump)
    by_key = {k: i for i, k in keys(prog).items()}
    roots = [int(r) if r.isdigit() else by_key[r] for r in args[3:]]
    formal = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parts = Parts(formal)
    rep_ns = ns + 'Rep'
    os.makedirs(outdir, exist_ok=True)
    if not roots:
        roots = [i for i in prog.fns if prog.role(i) != 'skip']
    texts, wanted = cert_files(prog, ns, ns + 'Cert', roots, parts)
    texts['SelfRep'] = rep_file(prog, ns, rep_ns, wanted)
    texts['SelfTypes'] = types_file(dump, ns)
    texts['Self'] = (f'module\n\npublic import {ns_module(ns)}Prog\n\n/-! The program of the extraction '
                     f'certificates (formal/tools/faithful_certs.py splits\nfaithful_dump.py\'s file into '
                     f'`SelfTypes`, `SelfSrc*` and `SelfProg`). Do not edit. -/\n')
    for name in os.listdir(outdir):
        if re.fullmatch(r'Self(Cert|Proof|Src|Look|Stmt)\w*\.lean', name) and name[:-5] not in texts:
            os.remove(os.path.join(outdir, name))
    for name, text in texts.items():
        # Unchanged files keep their times: lake rebuilds only what changed.
        path = os.path.join(outdir, f'{name}.lean')
        if not os.path.exists(path) or open(path).read() != text:
            open(path, 'w').write(text)
    print(f'{len(wanted)} certificates in {sum(1 for t in texts if t.startswith("SelfProof"))} proof modules')


if __name__ == '__main__':
    main()
