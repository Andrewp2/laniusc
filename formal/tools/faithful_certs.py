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
    lines = [f'module\n\npublic import Lanius.Faithful.Rep\npublic import Lanius.Mini.Frontend\n'
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


def cert_files(prog, ns, out_ns, roots, inline, imports, chunk, parts):
    """The certificates as three layers, so that a changed proof rebuilds only
    its own module (and the link): `SelfStmt` states every certificate;
    each proof module `SelfProofK` imports only the statements and proves a
    function's certificate from those of its callees outside its recursive
    group, taken as hypotheses (`ext{c}`); `SelfCert` imports the proofs and
    links them, callees first. Returns the module texts by name.

    Every module is a Lean module (module system), and the extracted Lean
    definitions and the functions' sources hide their bodies: a proof module
    sees, by `import all`, the sources of its own functions (`SelfSrcK`) and
    the parts of the extraction that define what it unfolds (`parts`), so a
    changed function rebuilds only the proofs that unfold it."""
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
    units = []
    for comp in order:
        if is_recursive(prog, comp):
            units += [(comp, i) for i in comp]
        else:
            units.append((comp, comp[0]))
    groups = [units[k:k + chunk] for k in range(0, len(units), chunk)]
    head = ['set_option maxHeartbeats 10000000\nset_option maxRecDepth 100000\n',
            f'namespace {out_ns}\n', 'open Lanius.Mini', 'open Lanius.Core (Value)', 'open Lanius.Faithful',
            f'open {ns}', f'open {ns}Rep\n']
    texts = {}
    # The statements without the tactics: changing those rebuilds the proofs only.
    stmt = ['module\n\n' + ''.join(f'public import {m}\n' for m in imports if m != 'Lanius.Faithful.Auto') +
            f'public import {ns_module(ns)}Prog\n\n@[expose] public section\n',
            f'/-! Generated by formal/tools/faithful_certs.py: the extraction certificates\n'
            f'of `{ns}.prog`, stated. Do not edit. -/\n'] + head
    for comp in order:
        for i in comp:
            stmt.append(statement(prog, i, inline))
            if prog.role(i) != 'prim':
                stmt.append(f'set_option maxRecDepth 100000 in\ntheorem fn{i} : prog.funcs[{i}]? = some src{i} := rfl\n')
    stmt.append(f'end {out_ns}\n')
    texts['SelfStmt'] = '\n'.join(stmt)
    for k, group in enumerate(groups):
        alls = [f'{ns_module(ns)}Src{k}'] + sorted({m for comp, i in group for m in parts.of(prog.head(i, inline))})
        lines = ['module\n\npublic import Lanius.Faithful.Auto\npublic import Lanius.Faithful.Gen.SelfStmt\n' +
                 ''.join(f'import all {m}\n' for m in alls) + '\npublic section\n',
                 f'/-! Generated by formal/tools/faithful_certs.py: extraction certificates of\n'
                 f'`{ns}.prog`, part {k}, from those of the callees. Do not edit. -/\n'] + head
        for comp, i in group:
            lines.append(proof(prog, comp, i, inline, externals(prog, i, comp, wanted)))
        lines.append(f'end {out_ns}\n')
        texts[f'SelfProof{k}'] = '\n'.join(lines)
    link = ['module\n\n' + ''.join(f'public import Lanius.Faithful.Gen.SelfProof{k}\n' for k in range(len(groups))) +
            '\npublic section\n',
            f'/-! Generated by formal/tools/faithful_certs.py: every certificate, each proof\n'
            f'given the certificates of its callees. Do not edit. -/\n'] + head
    for comp in order:
        if is_recursive(prog, comp):
            link.append(induction(prog, comp, wanted))
            continue
        i = comp[0]
        args = ' '.join(f'@cert{c}' for c in externals(prog, i, comp, wanted))
        app = f'@proof{i} {args} n'.replace('  ', ' ')
        link.append(f'theorem cert{i} {{n : Nat}} : Cert{i} n := {app}')
    link.append(f'\nend {out_ns}\n')
    texts['SelfCert'] = '\n'.join(link)
    return texts, wanted, groups


# The definitions whose proofs unfold a callee too, where it meets a
# constructor: their proofs also see the parts of the definitions their bodies
# name. (A proof that fails only because a body is hidden needs its head here.)
CALLEE_BODIES = {'Lanius.Mini.effNode', 'Lanius.Mini.exprOf'}


class Parts:
    """Where the extraction defines each Lean name (extract.py's parts), and
    the parts a proof that unfolds a definition imports with `import all`: its
    own, and for the heads in CALLEE_BODIES those of the definitions its body
    names."""

    def __init__(self, formal, inline_files):
        self.where, self.body = {}, {}
        for base in ['Compiler', 'Frontend']:
            d = os.path.join(formal, 'Lanius/Mini', base)
            for n in sorted(os.listdir(d)):
                m = re.fullmatch(r'(P\d+)\.lean', n)
                if m:
                    self.scan(open(os.path.join(d, n)).read(), f'Lanius.Mini.{base}.{m.group(1)}')
        for path in inline_files:
            if os.path.exists(path):
                self.scan(open(path).read(), None)
        self.short = {}
        for name in self.where:
            self.short.setdefault(name.rsplit('.', 1)[-1], set()).add(name)

    def scan(self, text, module):
        for chunk in re.split(r'\n(?=(?:/--.*\n)?(?:@\[expose\] )?(?:def|theorem|structure|inductive) )', text):
            m = re.search(r'^(?:@\[expose\] )?def ([A-Za-z0-9_.]+)', chunk, re.M)
            if m:
                name = 'Lanius.Mini.' + m.group(1)
                self.where[name], self.body[name] = module, chunk

    def of(self, head):
        if head is None or head not in self.body:
            return set()
        if head not in CALLEE_BODIES:
            return {self.where[head]} if self.where.get(head) else set()
        body = self.body[head].split(':=', 1)[-1]
        names = {head}
        for tok in set(re.findall(r'(?<![A-Za-z0-9_.])[A-Za-z_][A-Za-z0-9_.]*', body)):
            if 'Lanius.Mini.' + tok in self.where:
                names.add('Lanius.Mini.' + tok)
            elif '.' in tok and tok.split('.')[0][:1].islower():
                # `x.name`: a method of the type of the local `x`.
                names |= self.short.get(tok.rsplit('.', 1)[-1], set())
        for tok in set(re.findall(r'\)\.([A-Za-z_][A-Za-z0-9_]*)', body)):
            names |= self.short.get(tok, set())
        return {self.where[n] for n in names if self.where.get(n)}


def self_files(dump, ns, groups):
    """The program's source split for the module system: `SelfTypes` (exposed),
    `SelfSrc{K}` with the sources of proof module K's functions and
    `SelfSrcRest` with the others (hidden), `SelfProg` with `prog` (exposed:
    only the list of the sources' names), and `Self` importing it."""
    text = open(dump).read()
    first = text.index('\n/-- ', text.index('noncomputable section'))
    head, rest = text[:first], text[first:]
    head_lines = head.split('\n')
    imports = [l for l in head_lines if l.startswith('import ')]
    preamble = '\n'.join(l for l in head_lines if not l.startswith('import ')).strip('\n')
    tys = '\n'.join(l for l in preamble.split('\n') if l.startswith('def ty'))
    preamble = '\n'.join(l for l in preamble.split('\n') if not l.startswith('def ty')).rstrip() + '\n'
    srcs, prog_def = {}, None
    for entry in re.split(r'\n(?=/-- |def prog )', rest):
        m = re.search(r'^def src(\d+) ', entry, re.M)
        if m:
            srcs[int(m.group(1))] = entry.strip('\n')
        elif entry.startswith('def prog '):
            prog_def = entry.split('\n')[0]
    mod = ns_module(ns)
    out = {}
    out['SelfTypes'] = ('module\n\n' + ''.join(f'public {l}\n' for l in imports) + '\n@[expose] public section\n\n' +
                        preamble + '\n' + tys + '\n\nend\n\nend ' + ns + '\n')
    taken = set()
    for k, group in enumerate(groups):
        mine = sorted({i for _, i in group if i in srcs})
        taken |= set(mine)
        out[f'SelfSrc{k}'] = src_module(mod, ns, mine, srcs, k)
    out['SelfSrcRest'] = src_module(mod, ns, sorted(set(srcs) - taken), srcs, 'Rest')
    names = [f'SelfSrc{k}' for k in range(len(groups))] + ['SelfSrcRest']
    out['SelfProg'] = ('module\n\n' + ''.join(f'public import {mod}{n[4:]}\n' for n in names) +
                       '\n@[expose] public section\n\n' + f'namespace {ns}\n\nopen Lanius.Mini\n\nnoncomputable section\n\n' +
                       prog_def + '\n\nend\n\nend ' + ns + '\n')
    out['Self'] = (f'module\n\npublic import {mod}Prog\n\n/-! The program of the extraction certificates '
                   f'(formal/tools/faithful_certs.py splits faithful_dump.py\'s file into the modules\n'
                   f'`{mod}Types`, `..Src*` and `..Prog`). Do not edit. -/\n')
    return out


def src_module(mod, ns, idx, srcs, k):
    return ('module\n\n' + f'public import {mod}Types\n\npublic section\n\n' +
            f'/-! Generated by formal/tools/faithful_certs.py: sources of `{ns}.prog`, part {k}. Do not edit. -/\n\n' +
            f'namespace {ns}\n\nopen Lanius.Mini\n\nnoncomputable section\n\n' +
            '\n\n'.join(srcs[i] for i in idx) + '\n\nend\n\nend ' + ns + '\n')


def externals(prog, i, comp, wanted):
    """The callees of `i` outside its recursive group `comp`, in a fixed order."""
    if prog.role(i) != 'fn':
        return []
    return sorted({c for c in prog.sigs[i]['calls'] if c in wanted and c not in comp})


def inners(prog, i, comp):
    """The callees of `i` within its recursive group."""
    return [j for j in comp if j in prog.sigs[i]['calls']]


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


def is_recursive(prog, comp):
    return prog.role(comp[0]) == 'fn' and (len(comp) > 1 or comp[0] in prog.sigs[comp[0]]['calls'])


def intro(prog, i):
    n = len(prog.sigs[i]['params'])
    if prog.role(i) == 'panic':
        return 'intro vs w h'
    return 'intro ' + ' '.join([f'x{j}' for j in range(n)] + [f'v{j}' for j in range(n)] +
                               ['w', 'h'] + [f'r{j}' for j in range(n)])


def proof(prog, comp, i, inline, ext):
    """Function `i`'s certificate, `proof{i}`, from `ext{c} : Cert{c}` for its
    callees outside its recursive group; for a member of a recursive group,
    the step `step{i}`: its certificate with one more unit of fuel, from those
    of the group (`ih{j}`) with `n`."""
    hyps = ''.join(f'(ext{c} : ∀ {{n}}, Cert{c} n) ' for c in ext)
    if prog.role(i) == 'prim':
        return f'theorem proof{i} {{n : Nat}} : Cert{i} n := fun h r => prim_cert rfl h r\n'
    heads = [h for h in [prog.head(i, inline)] if h] if prog.role(i) == 'fn' else []
    body = [f'  rw [pcall_succ (c := {i}) (f := src{i}) rfl fn{i}] at h', f'  simp only [src{i}] at h',
            f'  {TACTIC} [{", ".join(heads)}]']
    if not is_recursive(prog, comp):
        return '\n'.join([f'theorem proof{i} {hyps}{{n : Nat}} : Cert{i} n := by', f'  {intro(prog, i)}',
                          '  rcases n with _ | n', '  · simp [pcall] at h'] + body) + '\n'
    ihs = ''.join(f'(ih{j} : Cert{j} n) ' for j in inners(prog, i, comp))
    return '\n'.join([f'theorem step{i} {hyps}{{n : Nat}} {ihs}: Cert{i} (n + 1) := by',
                      f'  {intro(prog, i)}'] + body) + '\n'


def induction(prog, comp, wanted):
    """A recursive group's certificates, by induction on the fuel from its steps."""
    first = comp[0]
    conj = ' ∧ '.join(f'Cert{i} n' for i in comp)
    lines = [f'theorem certs{first} : ∀ n, {conj} := by', '  intro n', '  induction n with', '  | zero =>']
    zero = ', '.join(f'(by {intro(prog, i)}; simp [pcall] at h)' for i in comp)
    lines.append(f'    exact ⟨{zero}⟩' if len(comp) > 1 else f'    exact {zero}')
    names = ' '.join(f'ih{i}' for i in comp)
    lines.append('  | succ n ih =>')
    if len(comp) > 1:
        lines.append(f'    obtain ⟨{", ".join(f"ih{i}" for i in comp)}⟩ := ih')
    else:
        lines.append(f'    have ih{first} : Cert{first} n := ih')
    steps = []
    for i in comp:
        # Explicit: `Cert{i} (n + 1)` unfolds to a function of implicit
        # arguments, which an ordinary application would instantiate.
        args = ' '.join([f'@cert{c}' for c in externals(prog, i, comp, wanted)] + ['n'] +
                        [f'ih{j}' for j in inners(prog, i, comp)])
        steps.append(f'@step{i} {args}')
    lines.append(f'    exact ⟨{", ".join(steps)}⟩' if len(comp) > 1 else f'    exact {steps[0]}')
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
    inline_files = ['Lanius/Faithful/Gen/CompilerInline.lean', 'Lanius/Faithful/Gen/FrontendInline.lean']
    for path in inline_files:
        full = os.path.join(formal, path)
        if os.path.exists(full):
            inline |= set(re.findall(r'^def Inline\.(\w+)', open(full).read(), re.M))
    rep_ns = ns + 'Rep'
    os.makedirs(outdir, exist_ok=True)
    if not roots:
        roots = [i for i in prog.fns if prog.role(i) != 'skip']
    imports = ['Lanius.Faithful.Auto', 'Lanius.Faithful.Gen.SelfRep', 'Lanius.Faithful.Gen.CompilerInline',
               'Lanius.Faithful.Gen.FrontendInline']
    parts = Parts(formal, [os.path.join(formal, p) for p in inline_files])
    texts, wanted, groups = cert_files(prog, ns, ns + 'Cert', roots, inline, imports, 40, parts)
    texts['SelfRep'] = rep_file(prog, ns, rep_ns, wanted)
    texts.update(self_files(dump, ns, groups))
    for name in os.listdir(outdir):
        if re.fullmatch(r'Self(Cert|Proof|Src)\d+\.lean', name) and name[:-5] not in texts:
            os.remove(os.path.join(outdir, name))
    for name, text in texts.items():
        # Unchanged files keep their times: lake rebuilds only what changed.
        path = os.path.join(outdir, f'{name}.lean')
        if not os.path.exists(path) or open(path).read() != text:
            open(path, 'w').write(text)
    print(f'{len(wanted)} certificates in {len(groups)} proof modules')


if __name__ == '__main__':
    main()
