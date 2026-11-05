"""legacyorder.py: the legacy files reachable from the gate's self-chain roots, in layers: a layer's files import only
modules and earlier layers' files."""
import os,re,sys
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; os.chdir(F)
IMP=re.compile(r'^(?:public )?(?:meta )?import (?:all )?(\S+)')
def path(m): return m.replace('.','/')+'.lean'
def imps(m):
    p=path(m)
    return [x.group(1) for l in open(p) for x in [IMP.match(l)] if x] if os.path.exists(p) else []
def legacy(m):
    p=path(m); return os.path.exists(p) and not open(p).read().startswith('module')
roots=sys.argv[1:] or ['LaniusMini','Lanius','LaniusOpen']
seen=set(); todo=list(roots)
while todo:
    m=todo.pop()
    if m in seen: continue
    seen.add(m); todo+=imps(m)
leg={m for m in seen if legacy(m) and m.startswith('Lanius.')}
layer={}
def L(m):
    if m in layer: return layer[m]
    layer[m]=0
    layer[m]=1+max([L(x) for x in imps(m) if x in leg]+[-1])
    return layer[m]
for m in leg: L(m)
by={}
for m,k in layer.items(): by.setdefault(k,[]).append(m)
for k in sorted(by): print(k,len(by[k]),' '.join(sorted(by[k])))
