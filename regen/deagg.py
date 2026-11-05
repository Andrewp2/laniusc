"""deagg.py FILE..: replace `[public] import Lanius.Mini.Compiler` / `.Frontend` (the aggregators: every part) by
public imports of the module's Types and the parts defining the names the file uses, so that adding a function (a
new part) does not reach the file."""
import os,re,sys
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'
DEF=re.compile(r"^\s*(?:@\[[^\]]*\]\s*)?(?:private |protected |noncomputable |partial )*(?:def|abbrev|inductive|structure|instance|theorem) ([A-Za-z0-9_.']+)",re.M)
full={}; short={}
for base in ('Compiler','Frontend'):
    d=f'{F}/Lanius/Mini/{base}/P'
    for f in os.listdir(d):
        mod=f'Lanius.Mini.{base}.P.{f[:-5]}'
        for n in DEF.findall(open(f'{d}/{f}').read()):
            full.setdefault(n,mod); short.setdefault(n.split('.')[-1],set()).add(mod)
for p in sys.argv[1:]:
    t=open(p).read()
    aggs=re.findall(r'^(?:public )?import (?:all )?Lanius\.Mini\.(Compiler|Frontend)$',t,re.M)
    if not aggs: continue
    body='\n'.join(l for l in t.split('\n') if not re.match(r'(public |private )?(meta )?import ',l))
    mods=set()
    for w in set(re.findall(r"[A-Za-z_][A-Za-z0-9_.']*",body)):
        w2=w[len('Lanius.Mini.'):] if w.startswith('Lanius.Mini.') else w
        if w2 in full: mods.add(full[w2])
        else:
            last=w2.split('.')[-1]
            if '.' in w2 or w2 in short: mods|=short.get(last,set())
    keep=[m for m in mods if any(f'.{a}.P.' in m for a in aggs)]
    lines=t.split('\n'); out=[]
    for l in lines:
        m=re.match(r'^(public )?import (all )?Lanius\.Mini\.(Compiler|Frontend)$',l)
        if m:
            out.append(f'public import Lanius.Mini.{m.group(3)}.Types')
            out+= [f'public import {x}' for x in sorted(keep) if f'.{m.group(3)}.P.' in x]
            continue
        out.append(l)
    open(p,'w').write('\n'.join(out)); print(p,len(keep))
