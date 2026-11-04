#!/usr/bin/env python3
"""Lean baselines for the same obligations as gen.py.

    leanbench.py OBLIGATIONS.jsonl OUTDIR N

Writes OUTDIR/Omega.lean (the first N distinct obligations as plain theorems
proved `by omega`), OUTDIR/Base.lean (no theorems, for the start-up time) and
OUTDIR/distinct.jsonl (the distinct obligations, for KernelBench.lean)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
from gen import statement_key

src, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
seen, obls = set(), []
for line in open(src):
    j = json.loads(line)
    if 'obl' in j:
        k = statement_key(j['obl'])
        if k not in seen:
            seen.add(k)
            obls.append(j['obl'])

def tm(t):
    if t[0] == 'a': return f'a{t[1]}'
    if t[0] == 'k': return str(t[1])
    if t[0] == '+': return f'({tm(t[1])} + {tm(t[2])})'
    return f'({t[1]} * {tm(t[2])})'

def atoms(t, acc):
    if t[0] == 'a': acc.add(t[1])
    elif t[0] == '+': atoms(t[1], acc); atoms(t[2], acc)
    elif t[0] == '*': atoms(t[2], acc)

with open(os.path.join(out, 'distinct.jsonl'), 'w') as f:
    for o in obls:
        f.write(json.dumps(o) + '\n')
with open(os.path.join(out, 'Base.lean'), 'w') as f:
    f.write('theorem base_only : True := trivial\n')
with open(os.path.join(out, 'Omega.lean'), 'w') as f:
    f.write('set_option linter.unusedVariables false\n')
    for i, o in enumerate(obls[:n]):
        acc = set()
        for a, b in o['hyps']: atoms(a, acc); atoms(b, acc)
        atoms(o['goal'][0], acc); atoms(o['goal'][1], acc)
        vs = ' '.join(f'a{k}' for k in sorted(acc))
        binders = f'({vs} : Nat) ' if vs else ''
        hs = ''.join(f'(h{j} : {tm(a)} ≤ {tm(b)}) ' for j, (a, b) in enumerate(o['hyps']))
        f.write(f'theorem o{i} {binders}{hs}: {tm(o["goal"][0])} ≤ {tm(o["goal"][1])} := by omega\n')
print(len(obls), 'distinct;', min(n, len(obls)), 'in Omega.lean')
