#!/usr/bin/env python3
"""Targeted bad certificates: each must be rejected (exit 1) by the checker,
and the honest one accepted.  attacks.py CHECKER"""
import os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
from certlib import Cert, HYP
import gen

def base():
    c = Cert(); gen.signature(c); return c

def run(checker, c):
    with tempfile.NamedTemporaryFile(suffix='.cert', delete=False) as f:
        path = f.name
    c.write(path)
    r = subprocess.run([checker], stdin=open(path, 'rb'), capture_output=True, text=True)
    os.unlink(path)
    return r.returncode, r.stdout.strip()

def thm(c, name, nvars, hyps, concl, steps):
    start = len(c.steps)
    c.steps.extend(steps)
    c.add_rule(name, 1, nvars, hyps, concl, (start, len(c.steps)))

def main(checker):
    R = lambda c, n: c.rule_ix[n]
    z = lambda c: c.mk('z')
    one = lambda c: c.mk('b1', c.mk('z'))
    cases = []
    # honest: le z (add z z) by le_add_r
    c = base(); s = c.mk('le', z(c), c.mk('add', z(c), z(c)))
    thm(c, 't', 0, [], s, [(R(c, 'le_add_r'), (z(c), z(c)), (), s)]); cases.append(('honest', c, 0))
    # false conclusion claimed for an honest step: le 1 0
    c = base(); bad = c.mk('le', one(c), z(c))
    thm(c, 't', 0, [], bad, [(R(c, 'le_add_r'), (one(c), z(c)), (), bad)]); cases.append(('wrong result', c, 1))
    # a theorem citing itself
    c = base(); bad = c.mk('le', one(c), z(c))
    thm(c, 't', 0, [], bad, [(len(c.rules), (), (), bad)]); cases.append(('self citation', c, 1))
    # premise from a later step
    c = base(); a = c.mk('le', z(c), z(c)); b = c.mk('le', z(c), z(c))
    thm(c, 't', 0, [], a, [(R(c, 'le_trans'), (z(c), z(c), z(c)), (1, 1), a), (R(c, 'le_refl'), (z(c),), (), a)])
    cases.append(('forward premise', c, 1))
    # hypothesis step naming no hypothesis
    c = base(); a = c.mk('le', one(c), z(c))
    thm(c, 't', 0, [], a, [(HYP, 0, (), a)]); cases.append(('missing hypothesis', c, 1))
    # ill-sorted substitution: a wff for a nat variable
    c = base(); w = c.mk('le', z(c), z(c))
    t = c.mk('eq', z(c), z(c))
    thm(c, 't', 0, [], t, [(R(c, 'eq_refl'), (w,), (), t)]); cases.append(('ill-sorted sigma', c, 1))
    # last step not the conclusion
    c = base(); a = c.mk('le', z(c), z(c)); bad = c.mk('le', one(c), z(c))
    thm(c, 't', 0, [], bad, [(R(c, 'le_refl'), (z(c),), (), a)]); cases.append(('other conclusion', c, 1))
    ok = True
    for name, c, want in cases:
        rc, out = run(checker, c)
        good = (rc == 0) == (want == 0) and rc in (0, 1)
        ok &= good
        print(f'{"PASS" if good else "FAIL"} {name}: {out}')
    return 0 if ok else 1

if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
