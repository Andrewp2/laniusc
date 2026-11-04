"""Flat proof certificates (target/claude-work/cert/FORMAT.md): building,
writing, reading and a reference checker.

The search side (gen.py) builds a Cert: sorts, term constructors, a
hash-consed table of term nodes, rules (axioms and theorems) and, for each
theorem, a flat array of steps. A step names a rule, a substitution (node ids,
one per rule variable), its premises (indices of earlier steps of the same
theorem) and its result node. Nothing here is trusted: check.lani is the
checker; `check` below mirrors it, for development and cross-checking.
"""
import struct

MAGIC = 0x5452434C  # 'LCRT'
VERSION = 1
VAR = 0x7FFFFFFF
HYP = 0x7FFFFFFF


class Cert:
    def __init__(self):
        self.sorts = []          # (name, provable)
        self.sort_ix = {}
        self.cons = []           # (name, result sort, [arg sorts])
        self.con_ix = {}
        self.nodes = []          # (head, args tuple) ; for VAR: (VAR, (k, sort))
        self.node_ix = {}
        self.rules = []          # dict(name, kind, nvars, hyps, concl, steps)
        self.rule_ix = {}
        self.steps = []          # (rule, sigma tuple | hyp index, prems tuple, result)

    # -- signature
    def sort(self, name, provable=False):
        self.sort_ix[name] = len(self.sorts)
        self.sorts.append((name, provable))

    def con(self, name, result, args=()):
        self.con_ix[name] = len(self.cons)
        self.cons.append((name, self.sort_ix[result], [self.sort_ix[a] for a in args]))

    # -- terms
    def mk(self, con, *args):
        key = (self.con_ix[con] if isinstance(con, str) else con, tuple(args))
        n = self.node_ix.get(key)
        if n is None:
            n = len(self.nodes)
            self.nodes.append(key)
            self.node_ix[key] = n
        return n

    def var(self, k, sort):
        key = (VAR, (k, self.sort_ix[sort] if isinstance(sort, str) else sort))
        n = self.node_ix.get(key)
        if n is None:
            n = len(self.nodes)
            self.nodes.append(key)
            self.node_ix[key] = n
        return n

    def sort_of(self, n):
        head, args = self.nodes[n]
        return args[1] if head == VAR else self.cons[head][1]

    def subst(self, t, sigma, memo=None):
        """The instance of template t under sigma (search side only)."""
        if memo is None:
            memo = {}
        r = memo.get(t)
        if r is not None:
            return r
        head, args = self.nodes[t]
        if head == VAR:
            r = sigma[args[0]]
        else:
            r = self.mk(head, *[self.subst(a, sigma, memo) for a in args])
        memo[t] = r
        return r

    # -- s-expressions over named variables, for the theory
    def parse(self, text, vars_, sorts):
        toks = text.replace('(', ' ( ').replace(')', ' ) ').split()
        pos = 0

        def go():
            nonlocal pos
            t = toks[pos]
            pos += 1
            if t == '(':
                head = toks[pos]
                pos += 1
                args = []
                while toks[pos] != ')':
                    args.append(go())
                pos += 1
                return self.mk(head, *args)
            if t in vars_:
                return self.var(vars_.index(t), sorts[vars_.index(t)])
            return self.mk(t)
        r = go()
        assert pos == len(toks), text
        return r

    # -- rules
    def axiom(self, name, vars_, hyps, concl, sort='nat'):
        vs = vars_.split()
        sorts = [sort] * len(vs)
        self.add_rule(name, 0, len(vs), [self.parse(h, vs, sorts) for h in hyps],
                      self.parse(concl, vs, sorts))

    def add_rule(self, name, kind, nvars, hyps, concl, steps=None):
        assert name not in self.rule_ix, name
        self.rule_ix[name] = len(self.rules)
        self.rules.append(dict(name=name, kind=kind, nvars=nvars, hyps=list(hyps), concl=concl,
                               steps=steps))
        return self.rule_ix[name]

    def theorem(self, name, nvars, hyps, concl, proof):
        """proof: a Proof whose last step proves concl."""
        assert proof.results[-1] == concl, (name, self.show(proof.results[-1]), self.show(concl))
        start = len(self.steps)
        self.steps.extend(proof.relocate(start))
        return self.add_rule(name, 1, nvars, hyps, concl, (start, len(self.steps)))

    def show(self, n, depth=0):
        head, args = self.nodes[n]
        if head == VAR:
            return f'?{args[0]}'
        name = self.cons[head][0]
        if not args:
            return name
        if depth > 6:
            return '...'
        return '(' + ' '.join([name] + [self.show(a, depth + 1) for a in args]) + ')'

    # -- binary
    def write(self, path):
        pool = []
        sorts = [1 if p else 0 for (_, p) in self.sorts]
        cons = []
        for (_, res, args) in self.cons:
            cons += [res, len(args), len(pool)]
            pool += args
        nodes = []
        for (head, args) in self.nodes:
            if head == VAR:
                nodes += [VAR, args[0], args[1]]
            else:
                nodes += [head, len(pool), 0]
                pool += args
        rules = []
        for r in self.rules:
            end = r['steps'][1] if r['kind'] == 1 else 0
            rules += [r['kind'], r['nvars'], len(r['hyps']), len(pool), r['concl'], end]
            pool += r['hyps']
        steps = []
        for (rule, sigma, prems, result) in self.steps:
            if rule == HYP:
                steps += [HYP, sigma, 0, result]
            else:
                steps += [rule, len(pool), len(pool) + len(sigma), result]
                pool += sigma
                pool += prems
        header = [MAGIC, VERSION, len(self.sorts), len(self.cons), len(self.nodes), len(self.rules),
                  len(self.steps), len(pool)]
        words = header + sorts + cons + nodes + rules + steps + pool
        assert all(0 <= w < 2 ** 31 or w == VAR for w in words)
        with open(path, 'wb') as f:
            f.write(struct.pack('<%dI' % len(words), *words))
        return 4 * len(words)


class Proof:
    """A theorem's steps under construction; step results are nodes."""

    def __init__(self, cert, hyps=()):
        self.c = cert
        self.hyps = list(hyps)
        self.steps = []
        self.results = []
        self.memo = {}   # (rule, sigma, prems) -> step index: identical steps once

    def hyp(self, j):
        key = ('hyp', j)
        if key in self.memo:
            return self.memo[key]
        self.steps.append((HYP, j, (), self.hyps[j]))
        self.results.append(self.hyps[j])
        self.memo[key] = len(self.steps) - 1
        return self.memo[key]

    def use(self, rule, sigma, prems=()):
        c = self.c
        r = c.rules[c.rule_ix[rule]] if isinstance(rule, str) else c.rules[rule]
        ri = c.rule_ix[r['name']]
        sigma = tuple(sigma)
        prems = tuple(prems)
        key = (ri, sigma, prems)
        if key in self.memo:
            return self.memo[key]
        assert len(sigma) == r['nvars'] and len(prems) == len(r['hyps']), r['name']
        for h, p in zip(r['hyps'], prems):
            got = c.subst(h, sigma)
            assert got == self.results[p], (r['name'], c.show(got), c.show(self.results[p]))
        res = c.subst(r['concl'], sigma)
        self.steps.append((ri, sigma, prems, res))
        self.results.append(res)
        self.memo[key] = len(self.steps) - 1
        return self.memo[key]

    def result(self, i):
        return self.results[i]

    def relocate(self, base):
        """Steps with premise indices made absolute (base = first step's index)."""
        out = []
        for (rule, sigma, prems, res) in self.steps:
            out.append((rule, sigma, tuple(p + base for p in prems), res))
        return out


def read(path):
    import array
    a = array.array('I')
    with open(path, 'rb') as f:
        a.frombytes(f.read())
    return a


def check(words):
    """Mirror of check.lani: True or raises."""
    w = words
    assert w[0] == MAGIC and w[1] == VERSION
    ns, nc, nn, nr, nst, npool = w[2:8]
    o_sorts = 8
    o_cons = o_sorts + ns
    o_nodes = o_cons + 3 * nc
    o_rules = o_nodes + 3 * nn
    o_steps = o_rules + 6 * nr
    o_pool = o_steps + 4 * nst
    assert o_pool + npool == len(w)
    pool = lambda i: w[o_pool + i]

    def nsort(n):
        h = w[o_nodes + 3 * n]
        return w[o_nodes + 3 * n + 2] if h == VAR else w[o_cons + 3 * h]
    # nodes
    for n in range(nn):
        h, a, b = w[o_nodes + 3 * n: o_nodes + 3 * n + 3]
        if h == VAR:
            assert b < ns
        else:
            assert h < nc
            res, ar, ao = w[o_cons + 3 * h: o_cons + 3 * h + 3]
            assert res < ns and a + ar <= npool and ao + ar <= npool
            for i in range(ar):
                x = pool(a + i)
                assert x < n and nsort(x) == pool(ao + i)

    def match(t, sigma, nv, target):
        stack = [(t, target)]
        while stack:
            t, x = stack.pop()
            h = w[o_nodes + 3 * t]
            if h == VAR:
                k = w[o_nodes + 3 * t + 1]
                if k >= nv or sigma[k] != x or nsort(x) != w[o_nodes + 3 * t + 2]:
                    return False
            else:
                if w[o_nodes + 3 * x] != h:
                    return False
                ar = w[o_cons + 3 * h + 1]
                ta = w[o_nodes + 3 * t + 1]
                xa = w[o_nodes + 3 * x + 1]
                for i in range(ar):
                    stack.append((pool(ta + i), pool(xa + i)))
        return True
    prev_end = 0
    for r in range(nr):
        kind, nv, nh, ho, concl, end = w[o_rules + 6 * r: o_rules + 6 * r + 6]
        assert concl < nn and w[o_sorts + nsort(concl)] & 1
        for j in range(nh):
            assert pool(ho + j) < nn and w[o_sorts + nsort(pool(ho + j))] & 1
        if kind == 0:
            continue
        assert kind == 1 and prev_end < end <= nst
        s0 = prev_end
        for i in range(s0, end):
            rule, so, po, res = w[o_steps + 4 * i: o_steps + 4 * i + 4]
            assert res < nn
            if rule == HYP:
                assert so < nh and pool(ho + so) == res
                continue
            assert rule < r
            rnv, rnh, rho, rconcl = w[o_rules + 6 * rule + 1: o_rules + 6 * rule + 5]
            assert so + rnv <= npool and po + rnh <= npool
            sigma = [pool(so + k) for k in range(rnv)]
            assert all(s < nn for s in sigma)
            assert match(rconcl, sigma, rnv, res), (r, i)
            for j in range(rnh):
                p = pool(po + j)
                assert s0 <= p < i
                assert match(pool(rho + j), sigma, rnv, w[o_steps + 4 * p + 3]), (r, i, j)
        assert w[o_steps + 4 * (end - 1) + 3] == concl
        prev_end = end
    return True


def _mix(h, v):
    return ((h ^ v) * 16777619) & 0xFFFFFFFF


def digest(cert):
    """The checker's DIGEST of a Cert's rules: kinds, variable and hypothesis
    counts and statement trees in prefix order (for the reviewed statements)."""
    def tree(t, h):
        stack = [t]
        while stack:
            n = stack.pop()
            head, args = cert.nodes[n]
            h = _mix(h, head)
            if head == VAR:
                h = _mix(_mix(h, args[0]), args[1])
            else:
                stack.extend(reversed(args))
        return h
    h = 2166136261
    for r in cert.rules:
        h = _mix(_mix(_mix(h, r['kind']), r['nvars']), len(r['hyps']))
        for x in r['hyps']:
            h = tree(x, h)
        h = tree(r['concl'], h)
    return h
