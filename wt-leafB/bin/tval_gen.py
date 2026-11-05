# tval_gen.py OUT.lean: `val_F : ts (F xs) ≤ max (ts x..) 16` for the functions SrcEff.eval reaches
# whose results carry types (a one-off writer of CompileEvalTypes.lean's statements; the proofs are uniform)
import re, glob, sys
F = '/home/andrew-peterson/code/laniusc-wt/leafB/formal/'
defs = {}
for p in glob.glob(F + 'Lanius/Mini/Compiler/P/*.lean'):
    txt = open(p).read()
    for m in re.finditer(r'^def ([\w.]+) ([^\n]*) :=\n(.*?)(?=^def |^mutual|^end|^/--|^theorem|\Z)', txt, re.S | re.M):
        head, d, cut = m.group(2), 0, None
        for i, ch in enumerate(head):
            d += ch == '('
            d -= ch == ')'
            if d == 0 and head.startswith(' : ', i):
                cut = i
        if head.startswith(': '):
            pstr, ret = '', head[2:]
        else:
            pstr, ret = head[:cut], head[cut + 3:]
        params = re.findall(r'\((\w+) : ([^()]*(?:\([^()]*\))?[^()]*)\)', pstr)
        defs[m.group(1)] = (params, ret.strip(), m.group(3))
tsl = open(F + 'Lanius/Faithful/SelfPre/TS.lean').read()
ts_types = set(re.findall(r'instance : TS Lanius\.Mini\.(\w+) := ⟨(?!fun _ => 0)', tsl))
def nonflat(t):
    t = t.strip()
    while t.startswith('(') and t.endswith(')'): t = t[1:-1].strip()
    m = re.match(r'(List|Option) (.+)$', t)
    if m: return nonflat(m.group(2))
    return t in ts_types
have = set(re.findall(r'theorem (val_\w+)', open(F + 'Lanius/Faithful/SelfPre/CompileTypes.lean').read() +
                      open(F + 'Lanius/Faithful/SelfPre/CompileValues.lean').read()))
def lname(f):
    return 'val_' + f.replace('.', '_') if '.' in f else 'val_' + f
def calls(f):
    body = defs[f][2]
    return {g for g in set(re.findall(r'(?<![\w.])([A-Za-z]\w*(?:\.[a-z]\w*)?)\b', body)) if g in defs and g != f}
seen, order = set(), []
def visit(f, stack=()):
    if f in seen or f not in defs: return
    seen.add(f)
    for g in sorted(calls(f)):
        if nonflat(defs[g][1]): visit(g)
    order.append(f)
visit(sys.argv[2] if len(sys.argv) > 2 else 'SrcEff.eval')
mutual = {'SrcEff.eval', 'evalArgs', 'evalArms'}
out = []
for f in order:
    if f in mutual or lname(f) in have: continue
    params, ret, body = defs[f]
    if not nonflat(ret): continue
    args = ' '.join(x for x, _ in params)
    bs = ' '.join(f'({x} : {t})' for x, t in params)
    rhs = '16'
    for x, t in reversed([(x, t) for x, t in params if nonflat(t)]):
        rhs = f'max (ts {x}) ({rhs})' if rhs != '16' else f'max (ts {x}) 16'
    rec = re.search(r'(?<![\w.])' + re.escape(f) + r'\b', body) is not None
    tac = f'fun_induction {f} {args} <;> ts_auto' if rec else f'unfold {f}; ts_auto'
    out.append(f'theorem {lname(f)} {bs} :\n    ts ({f} {args}) ≤ {rhs} := by\n  {tac}\n')
open(sys.argv[1], 'w').write('\n'.join(out))
print(len(out), 'lemmas')
