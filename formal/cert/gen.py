#!/usr/bin/env python3
"""Certificates for the linear side conditions of pre_auto/post_auto (F14).

    gen.py OBLIGATIONS.jsonl OUT.cert [--limit N] [--stats STATS.json]

OBLIGATIONS.jsonl is Export.lean's dump of the generated precondition
modules: every `SelfPre.LinCert.cert` use, an obligation `L ≤ R` from
hypotheses `Lᵢ ≤ Rᵢ` over atoms (naturals) that the search in Tactic.lean had
already chosen. This program is the search side: it proves each distinct
obligation in the theory below (THEORY, the trusted part with check.lani)
and writes the flat certificate. Nothing it computes is trusted.
"""
import hashlib
import json
import sys
import time

sys.path.insert(0, __import__('os').path.dirname(__file__))
from certlib import Cert, Proof  # noqa: E402

# The theory: naturals in binary (b0 x = 2x, b1 x = 2x+1), +, *, ≤, =.
# Every axiom is true of Nat; this list and the statement rendering are what a
# reader must trust (with check.lani).
THEORY = [
    ('eq_refl', 'a', [], '(eq a a)'),
    ('eq_symm', 'a b', ['(eq a b)'], '(eq b a)'),
    ('eq_trans', 'a b c', ['(eq a b)', '(eq b c)'], '(eq a c)'),
    ('cong_add', 'a b c d', ['(eq a b)', '(eq c d)'], '(eq (add a c) (add b d))'),
    ('cong_mul', 'a b c d', ['(eq a b)', '(eq c d)'], '(eq (mul a c) (mul b d))'),
    ('cong_b0', 'a b', ['(eq a b)'], '(eq (b0 a) (b0 b))'),
    ('cong_b1', 'a b', ['(eq a b)'], '(eq (b1 a) (b1 b))'),
    ('le_eq', 'a b c', ['(le a b)', '(eq b c)'], '(le a c)'),
    ('le_refl', 'a', [], '(le a a)'),
    ('le_trans', 'a b c', ['(le a b)', '(le b c)'], '(le a c)'),
    ('le_add_r', 'a b', [], '(le a (add a b))'),
    ('add_le_add', 'a b c d', ['(le a b)', '(le c d)'], '(le (add a c) (add b d))'),
    ('le_cancel', 'a b c', ['(le (add a c) (add b c))'], '(le a b)'),
    ('add_comm', 'a b', [], '(eq (add a b) (add b a))'),
    ('add_assoc', 'a b c', [], '(eq (add (add a b) c) (add a (add b c)))'),
    ('add_z', 'a', [], '(eq (add a z) a)'),
    ('mul_comm', 'a b', [], '(eq (mul a b) (mul b a))'),
    ('mul_assoc', 'a b c', [], '(eq (mul a (mul b c)) (mul (mul a b) c))'),
    ('mul_z', 'a', [], '(eq (mul z a) z)'),
    ('mul_b0', 'x a', [], '(eq (mul (b0 x) a) (add (mul x a) (mul x a)))'),
    ('mul_b1', 'x a', [], '(eq (mul (b1 x) a) (add (add (mul x a) (mul x a)) a))'),
    ('distrib', 'x a b', [], '(eq (mul x (add a b)) (add (mul x a) (mul x b)))'),
    ('rdistrib', 'x y a', [], '(eq (add (mul x a) (mul y a)) (mul (add x y) a))'),
    ('add_b0_b0', 'a b', [], '(eq (add (b0 a) (b0 b)) (b0 (add a b)))'),
    ('add_b0_b1', 'a b', [], '(eq (add (b0 a) (b1 b)) (b1 (add a b)))'),
    ('add_b1_b0', 'a b', [], '(eq (add (b1 a) (b0 b)) (b1 (add a b)))'),
    ('add_b1_b1', 'a b', [], '(eq (add (b1 a) (b1 b)) (b0 (add (add a b) (b1 z))))'),
]


def signature(c):
    c.sort('wff', provable=True)
    c.sort('nat')
    c.con('z', 'nat')
    c.con('b0', 'nat', ['nat'])
    c.con('b1', 'nat', ['nat'])
    c.con('add', 'nat', ['nat', 'nat'])
    c.con('mul', 'nat', ['nat', 'nat'])
    c.con('le', 'wff', ['nat', 'nat'])
    c.con('eq', 'wff', ['nat', 'nat'])
    for (name, vs, hyps, concl) in THEORY:
        c.axiom(name, vs, hyps, concl)


class Arith:
    """The search: normal forms of linear terms, as steps."""

    def __init__(self, c):
        self.c = c
        self.z = c.mk('z')
        self.one = c.mk('b1', self.z)
        self.numc = {0: self.z}
        self.numv = {self.z: 0}
        self.lemmas = {}      # statement node -> rule index (numeral facts)
        self.n_lemma_steps = 0
        self.prelude()

    # -- terms
    def num(self, k):
        n = self.numc.get(k)
        if n is None:
            n = self.c.mk('b1' if k & 1 else 'b0', self.num(k >> 1))
            self.numc[k] = n
            self.numv[n] = k
        return n

    def add(self, a, b):
        return self.c.mk('add', a, b)

    def mul(self, a, b):
        return self.c.mk('mul', a, b)

    def eq(self, a, b):
        return self.c.mk('eq', a, b)

    def le(self, a, b):
        return self.c.mk('le', a, b)

    def parts(self, n):
        head, args = self.c.nodes[n]
        return self.c.cons[head][0], args

    def var(self, k):
        return self.c.var(k, 'nat')

    # -- derived lemmas, proved once
    def prelude(self):
        c = self.c
        a, b, cc, d = (self.var(i) for i in range(4))
        z, one = self.z, self.one
        p = Proof(c)
        s1 = p.use('add_comm', [z, a])
        s2 = p.use('add_z', [a])
        p.use('eq_trans', [self.add(z, a), self.add(a, z), a], [s1, s2])
        c.theorem('z_add', 1, [], self.eq(self.add(z, a), a), p)

        p = Proof(c)
        s1 = p.use('add_assoc', [a, b, cc])
        s1 = p.use('eq_symm', [self.add(self.add(a, b), cc), self.add(a, self.add(b, cc))], [s1])
        s2 = p.use('add_comm', [a, b])
        s3 = p.use('eq_refl', [cc])
        s4 = p.use('cong_add', [self.add(a, b), self.add(b, a), cc, cc], [s2, s3])
        s5 = p.use('eq_trans', [self.add(a, self.add(b, cc)), self.add(self.add(a, b), cc),
                                self.add(self.add(b, a), cc)], [s1, s4])
        s6 = p.use('add_assoc', [b, a, cc])
        p.use('eq_trans', [self.add(a, self.add(b, cc)), self.add(self.add(b, a), cc),
                           self.add(b, self.add(a, cc))], [s5, s6])
        c.theorem('add_left_comm', 3, [], self.eq(self.add(a, self.add(b, cc)), self.add(b, self.add(a, cc))), p)

        p = Proof(c)
        ab, cd = self.add(a, b), self.add(cc, d)
        s1 = p.use('add_assoc', [a, b, cd])
        s2 = p.use('eq_refl', [a])
        s3 = p.use('add_left_comm', [b, cc, d])
        s4 = p.use('cong_add', [a, a, self.add(b, cd), self.add(cc, self.add(b, d))], [s2, s3])
        s5 = p.use('eq_trans', [self.add(ab, cd), self.add(a, self.add(b, cd)), self.add(a, self.add(cc, self.add(b, d)))], [s1, s4])
        s6 = p.use('add_assoc', [a, cc, self.add(b, d)])
        s7 = p.use('eq_symm', [self.add(self.add(a, cc), self.add(b, d)), self.add(a, self.add(cc, self.add(b, d)))], [s6])
        p.use('eq_trans', [self.add(ab, cd), self.add(a, self.add(cc, self.add(b, d))), self.add(self.add(a, cc), self.add(b, d))], [s5, s7])
        c.theorem('add4', 4, [], self.eq(self.add(ab, cd), self.add(self.add(a, cc), self.add(b, d))), p)

        # mul (b1 z) a = a
        p = Proof(c)
        za = self.mul(z, a)
        s1 = p.use('mul_b1', [z, a])                       # 1a = (za + za) + a
        s2 = p.use('mul_z', [a])                           # za = z
        s3 = p.use('cong_add', [za, z, za, z], [s2, s2])   # za + za = z + z
        s4 = p.use('add_z', [z])                           # z + z = z
        s5 = p.use('eq_trans', [self.add(za, za), self.add(z, z), z], [s3, s4])
        s6 = p.use('eq_refl', [a])
        s7 = p.use('cong_add', [self.add(za, za), z, a, a], [s5, s6])
        s8 = p.use('eq_trans', [self.mul(one, a), self.add(self.add(za, za), a), self.add(z, a)], [s1, s7])
        s9 = p.use('z_add', [a])
        p.use('eq_trans', [self.mul(one, a), self.add(z, a), a], [s8, s9])
        c.theorem('mul_one', 1, [], self.eq(self.mul(one, a), a), p)

        # a = 1a + z
        p = Proof(c)
        s1 = p.use('add_z', [self.mul(one, a)])
        s2 = p.use('mul_one', [a])
        s3 = p.use('eq_trans', [self.add(self.mul(one, a), z), self.mul(one, a), a], [s1, s2])
        p.use('eq_symm', [self.add(self.mul(one, a), z), a], [s3])
        c.theorem('nf_var', 1, [], self.eq(a, self.add(self.mul(one, a), z)), p)

    # -- proof combinators inside a Proof p; an equation step proves (eq lhs rhs)
    def lhs_rhs(self, p, s):
        _, (l, r) = self.parts(p.result(s))
        return l, r

    def trans(self, p, s1, s2):
        a, b = self.lhs_rhs(p, s1)
        b2, c = self.lhs_rhs(p, s2)
        assert b == b2
        return p.use('eq_trans', [a, b, c], [s1, s2])

    def refl(self, p, a):
        return p.use('eq_refl', [a])

    def cong(self, p, op, s1, s2):
        a, b = self.lhs_rhs(p, s1)
        c, d = self.lhs_rhs(p, s2)
        return p.use('cong_' + op, [a, b, c, d], [s1, s2])

    def lemma(self, p, stmt, build):
        """Use the numeral fact `stmt` (no variables), proving it first if new."""
        r = self.lemmas.get(stmt)
        if r is None:
            q = Proof(self.c)
            build(q)
            before = len(self.c.steps)
            r = self.c.theorem('num%d' % len(self.lemmas), 0, [], stmt, q)
            self.n_lemma_steps += len(self.c.steps) - before
            self.lemmas[stmt] = r
        return p.use(r, [])

    # -- numerals
    def numadd(self, p, x, y):
        """Step of (eq (add x y) s) with s the numeral; x, y canonical numerals."""
        s = self.num(self.numv[x] + self.numv[y])
        return s, self.lemma(p, self.eq(self.add(x, y), s), lambda q: self.numadd_proof(q, x, y))

    def numadd_proof(self, q, x, y):
        z = self.z
        if y == z:
            return q.use('add_z', [x])
        if x == z:
            return q.use('z_add', [y])
        hx, (a,) = self.parts(x)
        hy, (b,) = self.parts(y)
        if hx == 'b1' and hy == 'b1':
            s0 = q.use('add_b1_b1', [a, b])
            _, e1 = self.numadd(q, a, b)                # a + b = s1
            s1, _ = self.lhs_rhs(q, e1)[1], None
            _, e2 = self.numadd(q, s1, self.one)        # s1 + 1 = s2
            e3 = self.cong(q, 'add', e1, self.refl(q, self.one))
            e4 = self.trans(q, e3, e2)                  # (a+b)+1 = s2
            l, r = self.lhs_rhs(q, e4)
            e5 = q.use('cong_b0', [l, r], [e4])
            return self.trans(q, s0, e5)
        rule = 'add_%s_%s' % (hx, hy)
        s0 = q.use(rule, [a, b])
        _, e1 = self.numadd(q, a, b)
        l, r = self.lhs_rhs(q, e1)
        out = 'b1' if 'b1' in (hx, hy) else 'b0'
        e2 = q.use('cong_' + out, [l, r], [e1])
        return self.trans(q, s0, e2)

    def nummul(self, p, x, y):
        s = self.num(self.numv[x] * self.numv[y])
        return s, self.lemma(p, self.eq(self.mul(x, y), s), lambda q: self.nummul_proof(q, x, y))

    def nummul_proof(self, q, x, y):
        if x == self.z:
            return q.use('mul_z', [y])
        hx, (a,) = self.parts(x)
        s0 = q.use('mul_' + hx, [a, y])
        _, m = self.nummul(q, a, y)                     # a*y = k
        e1 = self.cong(q, 'add', m, m)                  # ay + ay = k + k
        k, _ = self.lhs_rhs(q, m)[1], None
        _, e2 = self.numadd(q, k, k)
        e3 = self.trans(q, e1, e2)                      # ay + ay = 2k
        if hx == 'b1':
            e3 = self.cong(q, 'add', e3, self.refl(q, y))
            d, _ = self.lhs_rhs(q, e3)[1], None
            _, dd = self.parts(d)
            _, e4 = self.numadd(q, dd[0], y)
            e3 = self.trans(q, e3, e4)
        return self.trans(q, s0, e3)

    # -- normal forms: a numeral, or (add (mul c x) rest) with atoms ascending
    def isnum(self, n):
        return n in self.numv

    def head_atom(self, n):
        _, (m, rest) = self.parts(n)
        _, (cf, x) = self.parts(m)
        return m, rest, cf, self.c.nodes[x][1][0], x

    def norm(self, p, t):
        """(nf, step of eq t nf)."""
        if self.isnum(t):
            return t, self.refl(p, t)
        head, args = self.c.nodes[t]
        if head == 0x7FFFFFFF:
            s = p.use('nf_var', [t])
            return self.lhs_rhs(p, s)[1], s
        name = self.c.cons[head][0]
        u, v = args
        if name == 'add':
            _, su = self.norm(p, u)
            _, sv = self.norm(p, v)
            s1 = self.cong(p, 'add', su, sv)
            nu, nv = self.parts(self.lhs_rhs(p, s1)[1])[1]
            n, s2 = self.merge(p, nu, nv)
            return n, self.trans(p, s1, s2)
        assert name == 'mul'
        if not self.isnum(u):
            s0 = p.use('mul_comm', [u, v])
            u, v = v, u
        else:
            s0 = None
        assert self.isnum(u)
        _, sv = self.norm(p, v)
        s1 = self.cong(p, 'mul', self.refl(p, u), sv)
        nv = self.lhs_rhs(p, s1)[1]
        n, s2 = self.scale(p, u, self.parts(nv)[1][1])
        s = self.trans(p, s1, s2)
        if s0 is not None:
            s = self.trans(p, s0, s)
        return n, s

    def merge(self, p, x, y):
        """(nf, step of eq (add x y) nf), x and y normal forms."""
        if self.isnum(x) and self.isnum(y):
            return self.numadd(p, x, y)
        if self.isnum(x):
            m, rest, _, _, _ = self.head_atom(y)
            s0 = p.use('add_left_comm', [x, m, rest])
            r, s1 = self.merge(p, x, rest)
            return self.add(m, r), self.trans(p, s0, self.cong(p, 'add', self.refl(p, m), s1))
        if self.isnum(y):
            m, rest, _, _, _ = self.head_atom(x)
            s0 = p.use('add_assoc', [m, rest, y])
            r, s1 = self.merge(p, rest, y)
            return self.add(m, r), self.trans(p, s0, self.cong(p, 'add', self.refl(p, m), s1))
        m1, r1, c1, i, xa = self.head_atom(x)
        m2, r2, c2, j, _ = self.head_atom(y)
        if i < j:
            s0 = p.use('add_assoc', [m1, r1, y])
            r, s1 = self.merge(p, r1, y)
            return self.add(m1, r), self.trans(p, s0, self.cong(p, 'add', self.refl(p, m1), s1))
        if i > j:
            s0 = p.use('add_left_comm', [x, m2, r2])
            r, s1 = self.merge(p, x, r2)
            return self.add(m2, r), self.trans(p, s0, self.cong(p, 'add', self.refl(p, m2), s1))
        s0 = p.use('add4', [m1, r1, m2, r2])                 # = (m1+m2) + (r1+r2)
        s1 = p.use('rdistrib', [c1, c2, xa])                  # m1+m2 = (c1+c2) x
        e, s2 = self.numadd(p, c1, c2)
        s3 = self.cong(p, 'mul', s2, self.refl(p, xa))
        s4 = self.trans(p, s1, s3)                            # m1+m2 = e x
        r, s5 = self.merge(p, r1, r2)
        s6 = self.cong(p, 'add', s4, s5)
        return self.add(self.mul(e, xa), r), self.trans(p, s0, s6)

    def scale(self, p, k, x):
        """(nf, step of eq (mul k x) nf), k a numeral, x a normal form."""
        if k == self.z:
            s = p.use('mul_z', [x])
            return self.z, s
        if self.isnum(x):
            return self.nummul(p, k, x)
        m, rest, cf, _, xa = self.head_atom(x)
        s0 = p.use('distrib', [k, m, rest])                   # = k m + k rest
        s1 = p.use('mul_assoc', [k, cf, xa])                  # k (c x) = (k c) x
        e, s2 = self.nummul(p, k, cf)
        s3 = self.trans(p, s1, self.cong(p, 'mul', s2, self.refl(p, xa)))
        r, s4 = self.scale(p, k, rest)
        return self.add(self.mul(e, xa), r), self.trans(p, s0, self.cong(p, 'add', s3, s4))

    # -- linear forms (search only), to build the slack
    def lin(self, t, acc, k=1):
        if self.isnum(t):
            acc[None] = acc.get(None, 0) + k * self.numv[t]
            return
        head, args = self.c.nodes[t]
        if head == 0x7FFFFFFF:
            acc[args[0]] = acc.get(args[0], 0) + k
            return
        name = self.c.cons[head][0]
        u, v = args
        if name == 'add':
            self.lin(u, acc, k)
            self.lin(v, acc, k)
        elif self.isnum(u):
            self.lin(v, acc, k * self.numv[u])
        else:
            self.lin(u, acc, k * self.numv[v])

    def nf_of(self, acc):
        n = self.num(acc.get(None, 0))
        for atom in sorted((a for a in acc if a is not None), reverse=True):
            if acc[atom]:
                n = self.add(self.mul(self.num(acc[atom]), self.var(atom)), n)
        return n

    # -- an obligation
    def obligation(self, hyps, l, r):
        """A Proof of (le l r) from hyps [(li, ri)] as nodes."""
        p = Proof(self.c, [self.le(a, b) for (a, b) in hyps])
        slack = {}
        self.lin(r, slack)
        self.lin(l, slack, -1)
        for (a, b) in hyps:
            self.lin(a, slack)
            self.lin(b, slack, -1)
        assert all(v >= 0 for v in slack.values()), 'not a linear certificate'
        S = self.nf_of(slack)

        def same(x, y):
            # step of (eq x y) when their normal forms agree
            nx, sx = self.norm(p, x)
            ny, sy = self.norm(p, y)
            assert nx == ny
            return self.trans(p, sx, p.use('eq_symm', [y, ny], [sy]))
        if not hyps:
            s1 = p.use('le_add_r', [l, S])
            e = same(self.add(l, S), r)
            p.use('le_eq', [l, self.add(l, S), r], [s1, e])
            return p
        A, B = hyps[0]
        ab = p.hyp(0)
        for j in range(1, len(hyps)):
            a, b = hyps[j]
            ab = p.use('add_le_add', [A, B, a, b], [ab, p.hyp(j)])
            A, B = self.add(A, a), self.add(B, b)
        LB = self.add(l, B)
        s1 = p.use('le_add_r', [LB, S])
        e = same(self.add(LB, S), self.add(r, A))
        s2 = p.use('le_eq', [LB, self.add(LB, S), self.add(r, A)], [s1, e])
        s3 = p.use('add_le_add', [r, r, A, B], [p.use('le_refl', [r]), ab])
        s4 = p.use('le_trans', [LB, self.add(r, A), self.add(r, B)], [s2, s3])
        p.use('le_cancel', [l, r, B], [s4])
        return p


def term(ar, t, atoms):
    """An LTm (Export.lean's JSON) as a node; atoms gets the atoms used."""
    tag = t[0]
    if tag == 'a':
        atoms.add(t[1])
        return ar.var(t[1])
    if tag == 'k':
        return ar.num(t[1])
    if tag == '+':
        return ar.add(term(ar, t[1], atoms), term(ar, t[2], atoms))
    assert tag == '*'
    return ar.mul(ar.num(t[1]), term(ar, t[2], atoms))


def statement_key(o):
    return hashlib.sha256(json.dumps([o['hyps'], o['goal']]).encode()).hexdigest()


def main(argv):
    src, out = argv[0], argv[1]
    limit = None
    stats_path = None
    if '--limit' in argv:
        limit = int(argv[argv.index('--limit') + 1])
    if '--stats' in argv:
        stats_path = argv[argv.index('--stats') + 1]
    obls = []
    for line in open(src):
        j = json.loads(line)
        if 'obl' in j:
            obls.append(j['obl'])
    t0 = time.perf_counter()
    c = Cert()
    signature(c)
    ar = Arith(c)
    t_prelude = time.perf_counter() - t0
    seen = {}
    per = []
    for o in obls:
        key = statement_key(o)
        if key in seen:
            continue
        if limit is not None and len(seen) >= limit:
            break
        t1 = time.perf_counter()
        steps0, lemma0, nodes0 = len(c.steps), ar.n_lemma_steps, len(c.nodes)
        atoms = set()
        hyps = [(term(ar, a, atoms), term(ar, b, atoms)) for (a, b) in o['hyps']]
        l = term(ar, o['goal'][0], atoms)
        r = term(ar, o['goal'][1], atoms)
        p = ar.obligation(hyps, l, r)
        nv = max(atoms) + 1 if atoms else 0
        seen[key] = c.theorem('obl_' + key[:16], nv, [ar.le(a, b) for (a, b) in hyps], ar.le(l, r), p)
        per.append(dict(key=key[:16], steps=len(c.steps) - steps0, own=len(p.steps),
                        lemma_steps=ar.n_lemma_steps - lemma0, nodes=len(c.nodes) - nodes0,
                        hyps=len(hyps), atoms=len(atoms), us=round((time.perf_counter() - t1) * 1e6)))
    t_gen = time.perf_counter() - t0
    size = c.write(out)
    t_all = time.perf_counter() - t0
    summary = dict(obligations=len(obls), distinct=len(seen), rules=len(c.rules), steps=len(c.steps),
                   nodes=len(c.nodes), lemma_steps=ar.n_lemma_steps, numeral_lemmas=len(ar.lemmas),
                   bytes=size, prelude_s=round(t_prelude, 3), gen_s=round(t_gen, 3), write_s=round(t_all - t_gen, 3))
    print(json.dumps(summary))
    if stats_path:
        json.dump(dict(summary=summary, per=per), open(stats_path, 'w'))
    return c


if __name__ == '__main__':
    main(sys.argv[1:])
