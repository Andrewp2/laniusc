#!/usr/bin/env python3
"""The budget certificates of the self program (F14), beside the extraction
certificates of faithful_certs.py.

    python3 -I formal/tools/budget_certs.py DUMP OUTDIR [ROOT...]

DUMP is faithful_dump.py's dump of the self program (with DUMP.meta), as
for faithful_certs.py. OUTDIR gets Lean files (not modules: Cost.lean is not
one) for the functions the ROOTs reach (names as faithful_certs.py's keys,
or indices; by default every function):

  SelfBModel  for each function, its Lean cost model `Cost_F` (one per
              function that can reach a `boxed` prim) and precondition
              `Pre_F` (one per function that can reach the prelude's `plus`
              or `times`), by fuel, from its source body;
  SelfBStmt   each budget certificate's statement for any two programs,
              prims and index (`BStmt_F spW sp prims ix n`);
  SelfBProof  its proof for programs that hold the function's source at
              `ix_F` (`bproof_F`, or `bstep_F` in a recursive group), from
              the callees' budget certificates and the function's own
              extraction certificate, by `budget`;
  SelfBCert   the proofs at `progW` and `prog`, recursive groups by
              induction on the fuel, callees first.

A budget certificate says that a run of `progW` (`plus` and `times`
wrapping) on values representing Lean arguments `x`, at a cost `k` in
`boxed` calls (`Budget.uc`) below a budget `b` where `Pre_F n x b` holds, is
the self program's run, at the cost `Cost_F n x`, its value representing the
extracted function at `x`:

    qcall spW prims uc n ix vs = some (w, k) → Rep x vs → k < b → Pre_F n x b →
      qcall sp prims uc n ix vs = some (w, k) ∧ Cost_F n x = k ∧ Rep (F x) w

The models follow the source in its evaluation order (an inlined function
is its own function there, as in the source), each value the Lean term
`pure_simp` and `qsimp` write for it:

  Cost_F (n + 1) x  the sum along the path the arguments take of the costs
              `Cost_G n y` of the calls of functions that can reach `boxed`
              and 1 per `boxed` call (the cost semantics counts nothing
              else); `Cost_F 0 x = 0`;
  Pre_F (n + 1) x b  along the same path, at each call of a function `G`
              with a precondition, `Pre_G n y B`, `B` the budget left: `b`
              less the costs before the call in `F`'s body. After a call
              that costs `c`, what follows is under `c < B →` at the budget
              `B - c`; `Pre_F 0 x b = True`. `Pre_plus n x y b` is
              `x + y < 2 ^ 64`, `Pre_times` likewise (Budget.lean).

A function that reaches no `boxed` has no cost model (its cost is 0), and
one that reaches no `plus` or `times` no precondition.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import faithful_certs as fc  # noqa: E402
import faithful_pure as fp  # noqa: E402

SELF = fc.SELF
POW64 = '18446744073709551616'
NS = 'Lanius.Faithful.SelfBudget'


class Unsupported(Exception):
    pass


def paren(s):
    return s if re.fullmatch(r'[A-Za-z0-9_.]+|\(.*\)', s) and balanced(s) else f'({s})'


def balanced(s):
    if not (s.startswith('(') and s.endswith(')')):
        return True
    depth = 0
    for k, ch in enumerate(s):
        depth += {'(': 1, ')': -1}.get(ch, 0)
        if depth == 0 and k < len(s) - 1:
            return False
    return True


def conj(parts):
    parts = [p for p in parts if p != 'True']
    if not parts:
        return 'True'
    if len(parts) == 1:
        return parts[0]
    return '(' + ' ∧ '.join(paren(p) for p in parts) + ')'


def add(a, b):
    if a == '0':
        return b
    if b == '0':
        return a
    return f'({a} + {b})'


class Gen:
    """The models of the wanted functions."""

    def __init__(self, dump, roots):
        self.prog = fc.Program(dump)
        self.key = fc.keys(self.prog)
        formal = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.parts = fc.Parts(formal)
        self.inline = self.parts.inline
        self.ast = {}
        for i, text in self.prog.bodies.items():
            self.ast[i] = fp.Parser(text).expr()
        by_key = {k: i for i, k in self.key.items()}
        roots = [int(r) if r.isdigit() else by_key[r] for r in roots]
        if not roots:
            roots = [i for i in self.prog.fns if self.prog.role(i) != 'skip']
        self.wanted = set()
        todo = list(roots)
        while todo:
            i = todo.pop()
            if i in self.wanted or self.prog.role(i) == 'skip':
                continue
            self.wanted.add(i)
            if self.prog.role(i) == 'fn' and not self.special(i):
                todo += fc.callees(self.prog, i)
        self.order = fc.sccs(sorted(self.wanted), lambda i: [c for c in self.calls(i) if c in self.wanted])
        self.comp_of = {i: comp for comp in self.order for i in comp}
        # Which functions can reach `boxed` (have a cost) and `plus` or `times` (a precondition).
        self.costly, self.guarded = set(), set()
        for comp in self.order:
            for i in comp:
                if self.is_boxed(i):
                    self.costly.add(i)
                if self.special(i):
                    self.guarded.add(i)
            for i in comp:
                for c in self.calls(i):
                    if c in self.costly:
                        self.costly |= set(comp)
                    if c in self.guarded:
                        self.guarded |= set(comp)

    # the program ------------------------------------------------------

    def name(self, i):
        return self.prog.fns[i]['name']

    def special(self, i):
        """The prelude's `plus` and `times`, whose certificates Budget.lean proves."""
        return self.name(i) in (SELF + 'plus', SELF + 'times')

    def is_boxed(self, i):
        return self.name(i) == SELF + 'boxed'

    def is_fn(self, i):
        """A function of the source with a body the certificates run (not a prim, not `plus` or `times`)."""
        return self.prog.role(i) in ('fn', 'field') and not self.special(i)

    def calls(self, i):
        if self.prog.role(i) != 'fn' or self.special(i):
            return []
        return fc.callees(self.prog, i)

    def type_tok(self, t):
        """A source type (parsed) as the dump's signatures write it."""
        if t[0] == 'name':
            m = re.fullmatch(r'ty(\d+)', t[1])
            if m:
                return f'#{self.prog.named[int(m.group(1))]}'
            c = t[1].rsplit('.', 1)[-1]
            if c in ('bool', 'i32'):
                return c
            raise Unsupported(f'type {t}')
        c, a = fp.ctor(t)
        if c == 'uint':
            return {'usize': 'usize', 'u8': 'u8', 'u32': 'u32', 'u64': 'u64'}[fp.ctor(a[0])[0]]
        raise Unsupported(f'type {t}')

    def lean_ty(self, tok):
        return self.prog.lean(tok)

    def fields(self, tok):
        tid = self.prog.type_id(tok)
        return self.prog.types[tid]['names'], self.prog.variants(tid)

    # values -----------------------------------------------------------

    def lit(self, kind, n):
        if kind == 'usize':
            return str(n)
        if kind == 'u8':
            return f'(UInt8.ofNat {n})'
        if kind == 'u32':
            return f'(BitVec.ofNat 32 {n})'
        if kind == 'u64':
            return f'({n}#64)'
        raise Unsupported(f'literal {kind}')

    def expr(self, env, e):
        """The Lean term of a pure expression and its type."""
        c, a = fp.ctor(e)
        if c == 'local':
            return env[a[0][1]]
        if c == 'field':
            t, ty = env[a[0][1]]
            names, variants = self.fields(ty)
            k = a[1][1]
            f = variants[0][k]
            return f'{paren(t)}.{fc.camel(names[k])}', self.prog.element(f) if self.is_box(f) else f
        if c == 'unsigned':
            kind = fp.ctor(a[0])[0]
            return self.lit(kind, a[1][1]), kind
        if c == 'int':
            return f'({a[0][1]}#32)', 'i32'
        if c == 'boolean':
            return a[0][1].rsplit('.', 1)[-1], 'bool'
        if c == 'apply':
            op = fp.ctor(a[0])[0]
            return self.op(op, self.expr(env, a[1]), self.expr(env, a[2]))
        if c == 'cast':
            return self.cast(self.type_tok(a[0]), self.expr(env, a[1]))
        if c == 'not':
            t, _ = self.expr(env, a[0])
            return f'(!{paren(t)})', 'bool'
        raise Unsupported(f'expression {c}')

    def op(self, op, left, right):
        (a, ty), (b, _) = left, right
        a, b = paren(a), paren(b)
        if op in ('logicalAnd', 'logicalOr'):
            return f'({a} {"&&" if op == "logicalAnd" else "||"} {b})', 'bool'
        if ty == 'bool':
            if op == 'equal':
                return f'({a} == {b})', 'bool'
            if op == 'notEqual':
                return f'(!({a} == {b}))', 'bool'
            raise Unsupported(f'{op} on bool')
        if ty == 'usize':
            arith = {'plus': f'(({a} + {b}) % {POW64})',
                     'minus': f'(({a} + {POW64} - {b} % {POW64}) % {POW64})',
                     'times': f'({a} * {b} % {POW64})'}
            if op in arith:
                return arith[op], 'usize'
            x, y = a, b
        elif ty in ('u64', 'u32', 'u8'):
            arith = {'plus': '+', 'minus': '-', 'times': '*', 'bitAnd': '&&&', 'bitOr': '|||', 'bitXor': '^^^'}
            if op in arith and ty != 'u8':
                return f'({a} {arith[op]} {b})', ty
            if op in ('shiftLeft', 'shiftRight') and ty != 'u8':
                return f'({a} {"<<<" if op == "shiftLeft" else ">>>"} {b}.toNat)', ty
            x, y = f'{a}.toNat', f'{b}.toNat'
        elif ty == 'i32':
            arith = {'plus': '+', 'minus': '-', 'times': '*'}
            if op in arith:
                return f'({a} {arith[op]} {b})', ty
            x, y = f'{a}.toInt', f'{b}.toInt'
        else:
            raise Unsupported(f'{op} on {ty}')
        cmp = {'less': f'(decide ({x} < {y}))', 'lessEq': f'(decide ({x} ≤ {y}))',
               'greater': f'(decide ({y} < {x}))', 'greaterEq': f'(decide ({y} ≤ {x}))',
               'equal': f'(decide ({x} = {y}))', 'notEqual': f'(!decide ({x} = {y}))'}
        if op in cmp:
            return cmp[op], 'bool'
        raise Unsupported(f'{op} on {ty}')

    def cast(self, to, src):
        t, frm = src
        t = paren(t)
        table = {('usize', 'u64'): f'(BitVec.ofNat 64 {t})', ('usize', 'i32'): f'(BitVec.ofNat 32 {t})',
                 ('usize', 'u8'): f'(UInt8.ofNat {t})', ('u32', 'usize'): f'{t}.toNat',
                 ('u32', 'u64'): f'({t}.setWidth 64)', ('i32', 'u32'): t,
                 ('i32', 'u64'): f'(BitVec.ofInt 64 {t}.toInt)', ('i32', 'u8'): f'(UInt8.ofNat {t}.toNat)',
                 ('u8', 'i32'): f'(BitVec.ofNat 32 {t}.toNat)', ('u32', 'u8'): f'(UInt8.ofNat {t}.toNat)',
                 ('u64', 'u8'): f'(UInt8.ofNat {t}.toNat)'}
        if frm == to:
            return t, to
        if (frm, to) in table:
            return table[(frm, to)], to
        raise Unsupported(f'cast {frm} to {to}')

    def struct(self, tok, ts):
        if not ts:
            return f'Lanius.Mini.{self.prog.short(tok)}.mk'
        return f'(Lanius.Mini.{self.prog.short(tok)}.mk {" ".join(paren(x) for x in ts)})'

    def variant(self, tok, k, ts):
        kind = self.prog.kind(tok)
        if kind == 'list':
            return f'([] : {self.lean_ty(tok)})' if k == 0 else f'({paren(ts[0])} :: {paren(ts[1])})'
        if kind == 'option':
            return f'(some {paren(ts[0])})' if k == 0 else f'(none : {self.lean_ty(tok)})'
        name = self.prog.types[self.prog.type_id(tok)]['names'][k]
        ctor = f'Lanius.Mini.{self.prog.short(tok)}.{fc.lower_first(name)}'
        return f'({ctor} {" ".join(paren(x) for x in ts)})' if ts else ctor

    def patterns(self, tok, binders):
        """The Lean patterns of a match's arms, every variant's."""
        kind = self.prog.kind(tok)
        tid = self.prog.type_id(tok)
        out = []
        for k, fields in enumerate(self.prog.variants(tid)):
            bs = binders[k] if k < len(binders) else [f'y{k}_{j}' for j in range(len(fields))]
            if kind == 'list':
                out.append('[]' if k == 0 else f'{bs[0]} :: {bs[1]}')
            elif kind == 'option':
                out.append(f'some {bs[0]}' if k == 0 else 'none')
            else:
                name = self.prog.types[tid]['names'][k]
                out.append(' '.join([f'.{fc.lower_first(name)}'] + bs))
        return out

    # the models ------------------------------------------------------

    def call(self, mode, c, ts, tys, B, k):
        """A call of `c` on terms `ts`, then `k(term, type, B)`."""
        if self.prog.role(c) == 'prim':
            boxed = self.is_boxed(c)
            if mode == 'cost':
                rest = k(ts[0], self.prog.sigs[c]['ret'], B)
                return add('1', rest) if boxed else rest
            if not boxed:
                return k(ts[0], self.prog.sigs[c]['ret'], B)
            rest = k(ts[0], self.prog.sigs[c]['ret'], f'({B} - 1)')
            return 'True' if rest == 'True' else f'(1 < {B} → {rest})'
        if self.prog.role(c) not in ('fn', 'field'):
            raise Unsupported(f'call of {self.name(c)} ({self.prog.role(c)})')
        term = self.prog.term(c, [paren(t) for t in ts], self.inline)
        ret = self.prog.sigs[c]['ret']
        args = ' '.join(paren(t) for t in ts)
        K = self.key[c]
        if mode == 'cost':
            rest = k(term, ret, B)
            return add(f'(Cost_{K} n {args})', rest) if c in self.costly else rest
        parts = []
        if c in self.guarded:
            parts.append(f'(Pre_{K} n {args} {B})')
        if c in self.costly:
            cost = f'(Cost_{K} n {args})'
            rest = k(term, ret, f'({B} - {cost})')
            parts.append('True' if rest == 'True' else f'({cost} < {B} → {rest})')
        else:
            parts.append(k(term, ret, B))
        return conj(parts)

    def effs(self, mode, env, es, B, k, acc=()):
        if not es:
            return k(list(t for t, _ in acc), list(ty for _, ty in acc), B)
        return self.eff(mode, env, es[0], B,
                        lambda t, ty, B2: self.effs(mode, env, es[1:], B2, k, acc + ((t, ty),)))

    def eff(self, mode, env, e, B, k):
        c, a = fp.ctor(e)
        if c == 'ePure':
            t, ty = self.expr(env, a[0])
            return k(t, ty, B)
        if c == 'eCall':
            callee = a[0][1]
            return self.effs(mode, env, a[1][1], B, lambda ts, tys, B2: self.call(mode, callee, ts, tys, B2, k))
        if c == 'eApply':
            op = fp.ctor(a[0])[0]
            if op in ('logicalAnd', 'logicalOr'):
                def left(tl, _ty, B1):
                    if fp.ctor(a[2])[0] == 'ePure':
                        tr, _ = self.expr(env, fp.ctor(a[2])[1][0])
                        return k(f'({paren(tl)} {"&&" if op == "logicalAnd" else "||"} {paren(tr)})', 'bool', B1)
                    other = k('false' if op == 'logicalAnd' else 'true', 'bool', B1)
                    right = self.eff(mode, env, a[2], B1, k)
                    if op == 'logicalAnd':
                        return self.ite(mode, f'{paren(tl)} = true', right, other)
                    return self.ite(mode, f'{paren(tl)} = true', other, right)
                return self.eff(mode, env, a[1], B, left)
            return self.eff(mode, env, a[1], B, lambda tl, tyl, B1: self.eff(
                mode, env, a[2], B1, lambda tr, tyr, B2: k(*self.op(op, (tl, tyl), (tr, tyr)), B2)))
        if c == 'eNot':
            return self.eff(mode, env, a[0], B, lambda t, ty, B1: k(f'(!{paren(t)})', 'bool', B1))
        if c == 'eCast':
            to = self.type_tok(a[0])
            return self.eff(mode, env, a[1], B, lambda t, ty, B1: k(*self.cast(to, (t, ty)), B1))
        if c == 'eStruct':
            tok = self.type_tok(a[0])
            return self.effs(mode, env, a[1][1], B, lambda ts, tys, B1: k(self.struct(tok, ts), tok, B1))
        if c == 'eVariant':
            tok = self.type_tok(a[0])
            return self.effs(mode, env, a[2][1], B,
                             lambda ts, tys, B1: k(self.variant(tok, a[1][1], ts), tok, B1))
        if c == 'eMatch':
            ety = self.type_tok(a[1])
            binders = [[b[1] for b in bs[1]] for bs in a[3][1]]
            values = a[4][1]

            def arms(t, ty, B1):
                tid = self.prog.type_id(ety)
                variants = self.prog.variants(tid)
                names = [[f'x{b}' for b in bs] for bs in binders]
                pats = self.patterns(ety, names)
                bodies = []
                for j, fields in enumerate(variants):
                    if j < len(values):
                        inner = dict(env)
                        for b, f in zip(binders[j], fields):
                            inner[b] = (f'x{b}', f if not self.is_box(f) else self.prog.element(f))
                        bodies.append(self.eff(mode, inner, values[j], B1, k))
                    else:
                        bodies.append('True' if mode == 'pre' else '0')
                return self.match(mode, t, pats, bodies)
            return self.eff(mode, env, a[0], B, arms)
        if c == 'eDivide':
            def div(tl, tyl, B1):
                def right(tr, tyr, B2):
                    if tyl != 'usize':
                        raise Unsupported(f'division on {tyl}')
                    op = fp.ctor(a[0])[0]
                    sym = '/' if op == 'divide' else '%'
                    return k(f'({paren(tl)} {sym} {paren(tr)} % {POW64})', 'usize', B2)
                return self.eff(mode, env, a[2], B1, right)
            return self.eff(mode, env, a[1], B, div)
        raise Unsupported(f'effect {c}')

    def is_box(self, tok):
        return tok.startswith('#') and self.prog.kind(tok) == 'box'

    def ite(self, mode, cond, yes, no):
        if yes == no:
            return yes
        return f'(if {cond} then {yes} else {no})'

    def match(self, mode, t, pats, bodies):
        if all(b == bodies[0] for b in bodies):
            return bodies[0]
        arms = ' '.join(f'| {p} => {b}' for p, b in zip(pats, bodies))
        return f'(match {paren(t)} with {arms})'

    def ret(self, mode):
        return 'True' if mode == 'pre' else '0'

    def stmt(self, mode, env, s, B, nxt):
        """A statement, then `nxt(B)` where it does not return."""
        c, a = fp.ctor(s)
        if c == 'nop':
            return nxt(B)
        if c in ('returnUnit',):
            return self.ret(mode)
        if c == 'return':
            self.expr(env, a[0])
            return self.ret(mode)
        if c == 'returnEval':
            return self.eff(mode, env, a[0], B, lambda t, ty, B1: self.ret(mode))
        if c == 'then':
            return self.stmt(mode, env, a[0], B, lambda B1: self.stmt(mode, env, a[1], B1, nxt))
        if c == 'if':
            cond, _ = self.expr(env, a[0])
            return self.ite(mode, f'{paren(cond)} = true', self.stmt(mode, env, a[1], B, nxt),
                            self.stmt(mode, env, a[2], B, nxt))
        if c == 'ifEval':
            return self.eff(mode, env, a[0], B, lambda t, ty, B1: self.ite(
                mode, f'{paren(t)} = true', self.stmt(mode, env, a[1], B1, nxt), self.stmt(mode, env, a[2], B1, nxt)))
        if c == 'let':
            inner = dict(env)
            inner[a[0][1]] = self.expr(env, a[2])
            return self.stmt(mode, inner, a[3], B, nxt)
        if c == 'letStruct':
            tok = self.type_tok(a[1])
            ts = [self.expr(env, x)[0] for x in a[2][1]]
            inner = dict(env)
            inner[a[0][1]] = (self.struct(tok, ts), tok)
            return self.stmt(mode, inner, a[3], B, nxt)
        if c == 'letEnum':
            tok = self.type_tok(a[1])
            ts = [self.expr(env, x)[0] for x in a[3][1]]
            inner = dict(env)
            inner[a[0][1]] = (self.variant(tok, a[2][1], ts), tok)
            return self.stmt(mode, inner, a[4], B, nxt)
        if c == 'letCall':
            callee = a[2][1]
            ts = [self.expr(env, x) for x in a[3][1]]

            def body(t, ty, B1):
                inner = dict(env)
                inner[a[0][1]] = (t, ty)
                return self.stmt(mode, inner, a[4], B1, nxt)
            return self.call(mode, callee, [t for t, _ in ts], [ty for _, ty in ts], B, body)
        if c == 'letEval':
            def body(t, ty, B1):
                inner = dict(env)
                inner[a[0][1]] = (t, ty)
                return self.stmt(mode, inner, a[3], B1, nxt)
            return self.eff(mode, env, a[2], B, body)
        if c == 'discard':
            return self.eff(mode, env, a[0], B, lambda t, ty, B1: nxt(B1))
        if c == 'assert':
            return self.eff(mode, env, a[0], B, lambda t, ty, B1: self.ite(mode, f'{paren(t)} = true', nxt(B1),
                                                                            self.ret(mode)))
        raise Unsupported(f'statement {c}')

    def params(self, i):
        ast = self.ast[i]
        ps = ast[1]['params'][1]
        return [(p[1]['id'][1], tok) for p, tok in zip(ps, self.prog.sigs[i]['params'])]

    def body(self, mode, i):
        env = {pid: (f'x{pid}', tok) for pid, tok in self.params(i)}
        return self.stmt(mode, env, self.ast[i][1]['body'], 'b', lambda B: self.ret(mode))

    # Lean text --------------------------------------------------------

    def model_defs(self, comp):
        """`Cost_F` and `Pre_F` of a recursive group (or one function)."""
        out = []
        for mode, have, name, ty, zero in [('cost', self.costly, 'Cost', 'Nat', '0'),
                                           ('pre', self.guarded, 'Pre', 'Prop', 'True')]:
            fns = [i for i in comp if i in have and self.is_fn(i)]
            if not fns:
                continue
            defs = []
            for i in fns:
                ps = self.params(i)
                tys = ' → '.join(['Nat'] + [self.lean_ty(tok) for _, tok in ps] + (['Nat'] if mode == 'pre' else []))
                xs = [f'x{pid}' for pid, _ in ps] + (['b'] if mode == 'pre' else [])
                body = self.body(mode, i)
                defs.append(f'def {name}_{self.key[i]} : {tys} → {ty}\n'
                            f'  | 0, {", ".join(xs)} => {zero}\n'
                            f'  | n + 1, {", ".join(xs)} => {body}\n' +
                            ('termination_by structural fuel => fuel\n' if self.recursive(comp) else ''))
            if len(defs) > 1 or self.recursive(comp):
                out.append('mutual\n' + '\n'.join(defs) + 'end\n')
            else:
                out.append(defs[0])
        return out

    def recursive(self, comp):
        return len(comp) > 1 or comp[0] in self.calls(comp[0])

    def has_pre(self, i):
        return i in self.guarded

    def bstmt(self, i):
        prog = self.prog
        sig = prog.sigs[i]
        k = len(sig['params'])
        K = self.key[i]
        vs = ', '.join(f'v{j}' for j in range(k))
        xs = ' '.join(f'x{j}' for j in range(k))
        binders = ''.join(f'{{x{j} : {prog.lean(p)}}} ' for j, p in enumerate(sig['params']))
        binders += f'{{{" ".join([f"v{j}" for j in range(k)] + ["w"])} : Value}} {{k{" b" if self.has_pre(i) else ""} : Nat}}'
        prems = ''.join(f' {prog.rep(p)} x{j} v{j} →' for j, p in enumerate(sig['params']))
        if self.has_pre(i):
            prems += f' k < b → Pre_{K} n {xs} b →'
        cost = f'Cost_{K} n {xs}' if i in self.costly else '0'
        result = f'{prog.rep(sig["ret"])} ({prog.term(i, [f"x{j}" for j in range(k)], self.inline)}) w'
        return (f'abbrev BStmt_{K} (spW sp : SrcProgram) (prims : Prims) (ix n : Nat) : Prop :=\n'
                f'  ∀ {binders},\n    qcall spW prims uc n ix [{vs}] = some (w, k) →{prems}\n'
                f'    qcall sp prims uc n ix [{vs}] = some (w, k) ∧ {cost} = k ∧ {result}\n')

    def bstmt_ref(self, i, sp_w, sp, ix, n):
        if self.special(i):
            return f'BStmt_{"plus" if self.name(i).endswith("plus") else "times"} {sp_w} {sp} prims {ix} {n}'
        return f'BStmt_{self.key[i]} {sp_w} {sp} prims {ix} {n}'

    def ixs(self, i):
        return [i] + [c for c in fc.callees(self.prog, i) if c != i]

    def proof(self, i):
        prog, key = self.prog, self.key
        K = key[i]
        comp = self.comp_of[i]
        rec = self.recursive(comp)
        callees = fc.callees(prog, i)
        binders = f'{{spW sp : SrcProgram}} {{prims : Prims}} {{{" ".join(f"ix_{key[c]}" for c in self.ixs(i))} : Nat}}'
        src = f'src_{K}' + ''.join(f' ix_{key[c]}' for c in callees)
        hyps = (f'\n    (fnW : spW.funcs[ix_{K}]? = some ({src})) (fn : sp.funcs[ix_{K}]? = some ({src}))'
                f'\n    (np : prims.isPrim ix_{K} = false)'
                f'\n    (back : Certified (∀ {{n : Nat}}, Stmt_{K} sp prims ix_{K} n))')
        for c in callees:
            if c in comp:
                continue
            C = key[c]
            if prog.role(c) == 'prim':
                hyps += (f'\n    (pp_{C} : prims.isPrim ix_{C} = true)'
                         f' (bx_{C} : prims.boxed.contains ix_{C} = {"true" if self.is_boxed(c) else "false"})')
            else:
                hyps += f'\n    (b_{C} : Certified (∀ {{n : Nat}}, {self.bstmt_ref(c, "spW", "sp", f"ix_{C}", "n")}))'
        k = len(prog.sigs[i]['params'])
        intro = ' '.join([f'x{j}' for j in range(k)] + [f'v{j}' for j in range(k)] + ['w', 'k'] +
                         (['b'] if self.has_pre(i) else []) + ['h'] + [f'r{j}' for j in range(k)] +
                         (['hb', 'pre'] if self.has_pre(i) else []))
        vs = ', '.join(f'v{j}' for j in range(k))
        xs = ' '.join(f'x{j}' for j in range(k))
        rs = ' '.join(f'r{j}' for j in range(k))
        cost = f'Cost_{K} (n + 1) {xs}' if i in self.costly else '0'
        tactic = f'budget Cost_{K}' if i in self.costly else 'budget'
        body = [f'  have key : qcall sp prims uc (n + 1) ix_{K} [{vs}] = some (w, k) ∧ {cost} = k := by',
                f'    rw [qcall_succ np fnW] at h',
                f'    rw [qcall_succ np fn]',
                f'    simp only [src_{K}, List.length_cons, List.length_nil, if_true] at h ⊢']
        if self.has_pre(i):
            body.append(f'    rw [Pre_{K}.eq_def] at pre')
            body.append(f'    simp only at pre')
        body.append(f'    {tactic}')
        body.append(f'  exact ⟨key.1, key.2, back.out (pcall_of_q key.1) {rs}⟩')
        if not rec:
            return '\n'.join([f'theorem bproof_{K} {binders}{hyps} {{n : Nat}} :',
                              f'    {self.bstmt_ref(i, "spW", "sp", f"ix_{K}", "n")} := by',
                              f'  intro {intro}',
                              '  rcases n with _ | n',
                              '  · simp only [qcall_zero, reduceCtorEq] at h'] + body) + '\n'
        ihs = ''.join(f'\n    (bih_{key[j]} : Certified ({self.bstmt_ref(j, "spW", "sp", f"ix_{key[j]}", "n")}))'
                      for j in comp if j in callees)
        return '\n'.join([f'theorem bstep_{K} {binders}{hyps} {{n : Nat}}{ihs} :',
                          f'    {self.bstmt_ref(i, "spW", "sp", f"ix_{K}", "(n + 1)")} := by',
                          f'  intro {intro}'] + body) + '\n'

    def intro(self, i):
        k = len(self.prog.sigs[i]['params'])
        return 'intro ' + ' '.join([f'x{j}' for j in range(k)] + [f'v{j}' for j in range(k)] + ['w', 'k'] +
                                   (['b'] if self.has_pre(i) else []) + ['h'])

    def app(self, i, ih):
        prog, key = self.prog, self.key
        K = key[i]
        comp = self.comp_of[i]
        ix = ' '.join(str(c) for c in self.ixs(i))
        args = [f'@{"bstep" if ih else "bproof"}_{K} progW prog prims {ix} (fnW_of (by decide) (by decide) fn_{K})',
                f'fn_{K} np_{K} ⟨@cert_{K}⟩']
        for c in fc.callees(prog, i):
            if c in comp:
                continue
            if prog.role(c) == 'prim':
                args.append(f'np_{key[c]} (by decide +kernel)')
            elif self.special(c):
                args.append(f'⟨@bcert_{"plus" if self.name(c).endswith("plus") else "times"}⟩')
            else:
                args.append(f'⟨@bcert_{key[c]}⟩')
        args.append('n')
        if ih:
            args += [f'⟨bih_{key[j]}⟩' for j in comp if j in fc.callees(prog, i)]
        return ' '.join(args)

    def link(self, comp):
        key = self.key
        if self.special(comp[0]) or self.prog.role(comp[0]) == 'prim':
            return ''
        ref = lambda i, n: self.bstmt_ref(i, 'progW', 'prog', str(i), n)  # noqa: E731
        if not self.recursive(comp):
            i = comp[0]
            return f'theorem bcert_{key[i]} {{n : Nat}} :\n    {ref(i, "n")} :=\n  {self.app(i, False)}\n'
        first = key[comp[0]]
        conj_ = ' ∧ '.join(f'({ref(i, "n")})' for i in comp)
        lines = [f'theorem bcerts_{first} : ∀ n, {conj_} := by', '  intro n', '  induction n with', '  | zero =>']
        zero = ', '.join(f'(by {self.intro(i)}; simp only [qcall_zero, reduceCtorEq] at h)' for i in comp)
        lines.append(f'    exact ⟨{zero}⟩' if len(comp) > 1 else f'    exact {zero}')
        lines.append('  | succ n ih =>')
        if len(comp) > 1:
            lines.append(f'    obtain ⟨{", ".join(f"bih_{key[i]}" for i in comp)}⟩ := ih')
        else:
            lines.append(f'    have bih_{first} : {ref(comp[0], "n")} := ih')
        steps = [self.app(i, True) for i in comp]
        lines.append(f'    exact ⟨{", ".join(steps)}⟩' if len(comp) > 1 else f'    exact {steps[0]}')
        lines.append('')
        for k, i in enumerate(comp):
            pick = '' if len(comp) == 1 else '.' + '.'.join(['2'] * k + (['1'] if k < len(comp) - 1 else []))
            lines.append(f'theorem bcert_{key[i]} {{n : Nat}} :\n    {ref(i, "n")} :=\n  (bcerts_{first} n){pick}')
        return '\n'.join(lines) + '\n'

    def files(self):
        head = ('set_option maxHeartbeats 10000000\nset_option maxRecDepth 100000\n'
                'set_option linter.unusedVariables false\n\n')
        opens = (f'namespace {NS}\n\nopen Lanius.Mini\nopen Lanius.Core (Value)\nopen Lanius.Faithful\n'
                 'open Lanius.Faithful.Self\nopen Lanius.Faithful.SelfRep\nopen Lanius.Faithful.SelfCert\n'
                 'open Lanius.Faithful.Budget\n\n')
        fns = [i for comp in self.order for i in comp if self.is_fn(i)]
        models = []
        for comp in self.order:
            if self.is_fn(comp[0]):
                models += self.model_defs(comp)
        texts = {}
        texts['SelfBModel'] = (
            'import Lanius.Faithful.Gen.SelfCert\nimport Lanius.Faithful.Budget\n\n'
            '/-! Generated by formal/tools/budget_certs.py: the cost models and preconditions of the\n'
            'self program\'s functions. Do not edit. -/\n\n' + head + opens + 'noncomputable section\n\n' +
            '\n'.join(models) + f'\nend\n\nend {NS}\n')
        texts['SelfBStmt'] = (
            'import Lanius.Faithful.GenB.SelfBModel\n\n'
            '/-! Generated by formal/tools/budget_certs.py: the budget certificates\' statements. Do not\n'
            'edit. -/\n\n' + head + opens + '\n'.join(self.bstmt(i) for i in fns) + f'\nend {NS}\n')
        texts['SelfBProof'] = (
            'import Lanius.Faithful.GenB.SelfBStmt\nimport Lanius.Faithful.BudgetTactic\n\n'
            '/-! Generated by formal/tools/budget_certs.py: the budget certificates, for any programs\n'
            'that hold the functions. Do not edit. -/\n\n' + head + opens + '\n'.join(self.proof(i) for i in fns) +
            f'\nend {NS}\n')
        texts['SelfBCert'] = (
            'import Lanius.Faithful.GenB.SelfBProof\n\n'
            '/-! Generated by formal/tools/budget_certs.py: the budget certificates at `progW` and\n'
            '`prog`. Do not edit. -/\n\n' + head + opens + 'open Lanius.Faithful.SelfPanics\n\n' +
            '\n'.join(t for t in (self.link(comp) for comp in self.order) if t) + f'\nend {NS}\n')
        return texts


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    dump, outdir = sys.argv[1:3]
    gen = Gen(dump, sys.argv[3:])
    os.makedirs(outdir, exist_ok=True)
    for name, text in gen.files().items():
        path = os.path.join(outdir, f'{name}.lean')
        if not os.path.exists(path) or open(path).read() != text:
            open(path, 'w').write(text)
    print(f'{len(gen.wanted)} functions: {len(gen.costly)} with a cost, {len(gen.guarded)} with a precondition')


if __name__ == '__main__':
    main()
