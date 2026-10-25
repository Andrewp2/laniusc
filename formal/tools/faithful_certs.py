#!/usr/bin/env python3
"""The extraction certificates of a program dumped by faithful_dump.py.

    python3 -I formal/tools/faithful_certs.py [--dev] DUMP NS OUTDIR [ROOT...]

DUMP is the Lean file faithful_dump.py wrote (namespace NS, with DUMP.meta
next to it). OUTDIR gets

  SelfRep.lean one inductive `Rep<Name>` per struct and enum of the program,
              with its constructors as `rep_rule`s, the prims, and each named
              type's `typeId`;
  SelfCert.lean for each function, `Cert<i> n`: a pure run of function i with
              fuel n on values representing Lean arguments returns a value
              representing the extracted Lean function at those arguments;
              and its proof, one recursive group at a time, callees first.

--dev proves with `faithful_dev`, which admits what it cannot prove and
warns, for working on the tactic. With ROOTs (function indices), only the functions they call, directly or
not, get certificates. The Lean meaning of each function is its extraction
(formal/tools/extract.py): `name` or `Type.name` for a method, the list
operations and the prelude's arithmetic as the Lean terms the extraction
writes for their calls, and `Inline.name` (extract.py --inline) for an
`// extract: inline` function.
"""

import os
import re
import sys

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
    lines = [f'import Lanius.Faithful.Rep\nimport {ns_module(ns)}\n',
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
    prims = {'boxed': [], 'unbox': []}
    for i, f in sorted(prog.fns.items()):
        if f['name'] in PRIMS:
            prims[f['name'][len(SELF):]].append(str(i))
    lines.append(f'def prims : Prims :=\n  {{ boxed := [{", ".join(prims["boxed"])}],\n'
                 f'    unbox := [{", ".join(prims["unbox"])}] }}\n')
    for k, i in sorted(prog.named.items()):
        lines.append(f'@[pure_rule] theorem ty{k}_typeId : ty{k}.typeId = {i} := rfl')
    lines.append(f'\nend {out_ns}\n')
    return '\n'.join(lines)


def ns_module(ns):
    return {'Lanius.Faithful.Self': 'Lanius.Faithful.Gen.Self'}[ns]


def cert_files(prog, ns, out_ns, roots, inline, imports, chunk):
    """The certificates in modules of about `chunk` functions, callees first:
    module k imports module k - 1."""
    wanted = set()
    todo = list(roots)
    while todo:
        i = todo.pop()
        if i in wanted or prog.role(i) == 'skip':
            continue
        wanted.add(i)
        if prog.role(i) == 'fn':
            todo += prog.sigs[i]['calls']
    order = sccs(sorted(wanted), lambda i: [c for c in prog.sigs[i]['calls'] if c in wanted])
    groups, group = [], []
    for comp in order:
        group.append(comp)
        if sum(len(c) for c in group) >= chunk:
            groups.append(group)
            group = []
    if group:
        groups.append(group)
    texts = []
    for k, group in enumerate(groups):
        deps = imports if k == 0 else [f'Lanius.Faithful.Gen.SelfCert{k - 1}']
        lines = [''.join(f'import {m}\n' for m in deps),
                 f'/-! Generated by formal/tools/faithful_certs.py: extraction certificates of\n'
                 f'`{ns}.prog`, part {k}. Do not edit. -/\n',
                 'set_option maxHeartbeats 10000000\n',
                 f'namespace {out_ns}\n', 'open Lanius.Mini', 'open Lanius.Core (Value)', 'open Lanius.Faithful',
                 f'open {ns}', f'open {ns}Rep\n']
        for comp in group:
            for i in comp:
                lines.append(statement(prog, i, inline))
            lines.append(proof(prog, comp, inline))
        lines.append(f'end {out_ns}\n')
        texts.append('\n'.join(lines))
    return texts, wanted


def statement(prog, i, inline):
    sig, role = prog.sigs[i], prog.role(i)
    n = len(sig['params'])
    vs = ', '.join(f'v{j}' for j in range(n))
    name = prog.fns[i]['name']
    head = f'/-- {name} -/\ndef Cert{i} (n : Nat) : Prop :=\n  ∀ '
    if role == 'panic':
        return head + f'{{vs : List Value}} {{w : Value}}, pcall prog prims n {i} vs = some w → False\n'
    binders = ''.join(f'{{x{j} : {prog.lean(p)}}} ' for j, p in enumerate(sig['params']))
    binders += f'{{{" ".join([f"v{j}" for j in range(n)] + ["w"])} : Value}}'
    prems = ''.join(f' {prog.rep(p)} x{j} v{j} →' for j, p in enumerate(sig['params']))
    if role == 'prim':
        result = f'{prog.rep(sig["params"][0])} x0 w'
    else:
        result = f'{prog.rep(sig["ret"])} ({prog.term(i, [f"x{j}" for j in range(n)], inline)}) w'
    return head + f'{binders}, pcall prog prims n {i} [{vs}] = some w →{prems}\n    {result}\n'


def proof(prog, comp, inline):
    lines = []
    if len(comp) == 1 and prog.role(comp[0]) == 'prim':
        i = comp[0]
        return f'theorem cert{i} {{n : Nat}} : Cert{i} n := fun h r => prim_cert rfl h r\n'
    recursive = len(comp) > 1 or comp[0] in prog.sigs[comp[0]]['calls']
    for i in comp:
        lines.append(f'set_option maxRecDepth 100000 in\ntheorem fn{i} : prog.funcs[{i}]? = some src{i} := rfl')
    lines.append('')

    def intro(i):
        n = len(prog.sigs[i]['params'])
        if prog.role(i) == 'panic':
            return 'intro vs w h'
        return 'intro ' + ' '.join([f'x{j}' for j in range(n)] + [f'v{j}' for j in range(n)] +
                                   ['w', 'h'] + [f'r{j}' for j in range(n)])

    def body(i, pad):
        heads = [h for h in [prog.head(i, inline)] if h] if prog.role(i) == 'fn' else []
        return [f'{pad}rw [pcall_succ (c := {i}) (f := src{i}) rfl fn{i}] at h',
                f'{pad}simp only [src{i}] at h',
                f'{pad}{TACTIC} [{", ".join(heads)}]']

    if not recursive:
        i = comp[0]
        lines += [f'theorem cert{i} {{n : Nat}} : Cert{i} n := by', f'  {intro(i)}', '  rcases n with _ | n',
                  '  · simp [pcall] at h'] + body(i, '  ')
        return '\n'.join(lines) + '\n'
    first = comp[0]
    conj = ' ∧ '.join(f'Cert{i} n' for i in comp)
    lines += [f'theorem certs{first} : ∀ n, {conj} := by', '  intro n', '  induction n with',
              '  | zero =>', f'    refine ⟨{", ".join("?_" for _ in comp)}⟩' if len(comp) > 1 else '    skip']
    for i in comp:
        lines += [f'    · {intro(i)}', '      simp [pcall] at h'] if len(comp) > 1 else [
            f'    {intro(i)}', '    simp [pcall] at h']
    lines += [f'  | succ n {"ih" if len(comp) > 1 else f"ih{first}"} =>']
    if len(comp) > 1:
        lines += [f'    obtain ⟨{", ".join(f"ih{i}" for i in comp)}⟩ := ih',
                  f'    refine ⟨{", ".join("?_" for _ in comp)}⟩']
        for i in comp:
            lines += [f'    · {intro(i)}'] + body(i, '      ')
    else:
        lines += [f'    {intro(first)}'] + body(first, '    ')
    lines.append('')
    for k, i in enumerate(comp):
        pick = '' if len(comp) == 1 else '.' + '.'.join(['2'] * k + (['1'] if k < len(comp) - 1 else []))
        lines.append(f'theorem cert{i} {{n : Nat}} : Cert{i} n := (certs{first} n){pick}')
    return '\n'.join(lines) + '\n'


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    global TACTIC
    args = sys.argv[1:]
    if '--dev' in args:
        args.remove('--dev')
        TACTIC = 'faithful_dev'
    dump, ns, outdir = args[:3]
    roots = [int(r) for r in args[3:]]
    prog = Program(dump)
    formal = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    inline = set()
    for path in ['Lanius/Faithful/Gen/CompilerInline.lean', 'Lanius/Faithful/Gen/FrontendInline.lean']:
        full = os.path.join(formal, path)
        if os.path.exists(full):
            inline |= set(re.findall(r'^def Inline\.(\w+)', open(full).read(), re.M))
    rep_ns = ns + 'Rep'
    os.makedirs(outdir, exist_ok=True)
    if not roots:
        roots = [i for i in prog.fns if prog.role(i) != 'skip']
    imports = ['Lanius.Faithful.Auto', 'Lanius.Faithful.Gen.SelfRep', 'Lanius.Faithful.Gen.CompilerInline']
    texts, wanted = cert_files(prog, ns, ns + 'Cert', roots, inline, imports, 40)
    open(os.path.join(outdir, 'SelfRep.lean'), 'w').write(rep_file(prog, ns, rep_ns, wanted))
    for name in os.listdir(outdir):
        if re.fullmatch(r'SelfCert\d+\.lean', name):
            os.remove(os.path.join(outdir, name))
    for k, text in enumerate(texts):
        open(os.path.join(outdir, f'SelfCert{k}.lean'), 'w').write(text)
    open(os.path.join(outdir, 'SelfCert.lean'), 'w').write(
        f'import Lanius.Faithful.Gen.SelfCert{len(texts) - 1}\n\n'
        f'/-! Generated by formal/tools/faithful_certs.py: all the certificates. -/\n')
    print(f'{len(wanted)} certificates in {len(texts)} modules')


if __name__ == '__main__':
    main()
