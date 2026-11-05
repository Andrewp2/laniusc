"""direct.py FILE [--write]: the Mini compiler parts FILE's text names directly (no closure through bodies),
compared with its `import all` lines of parts; --write keeps only the named ones (and non-part import alls)."""
import os,re,sys,glob
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'
defs={}
for p in sorted(glob.glob(F+'/Lanius/Mini/Compiler/P/*.lean')):
    part='Lanius.Mini.Compiler.P.'+os.path.basename(p)[:-5]
    for l in open(p):
        m=re.match(r'(?:@\[expose\] )?def ([A-Za-z0-9_.\']+)',l)
        if m: defs.setdefault(m.group(1),part)
bylast={}
for n in defs: bylast.setdefault(n.split('.')[-1],[]).append(n)
def named(w):
    if w.startswith('Lanius.Mini.'): w=w[12:]
    ps=w.split('.'); out=[]
    if w in defs: out.append(w)
    if len(ps)>=2:
        f='.'.join(ps[:-1])
        if f in defs: out.append(f)
        out+=bylast.get(ps[-1],[])
    return out
path=sys.argv[1]; t=open(path).read()
body='\n'.join(l for l in t.split('\n') if not re.match(r'(public |private )?import ',l))
words=re.findall(r"[A-Za-z0-9_'.]+",body)
D=sorted({defs[n] for w in words for n in named(w)})
alls=re.findall(r'^import all (Lanius\.Mini\.Compiler\.P\.\S+)$',t,re.M)
keep=[a for a in alls if a in D]
print(f'{path}: {len(alls)} part import alls, {len(D)} parts named, keep {len(keep)}; named but not imported: {sorted(set(D)-set(alls))[:10]}')
if '--write' in sys.argv:
    drop=set(alls)-set(keep)
    open(path,'w').write(''.join(l for l in t.splitlines(True) if not (l.startswith('import all ') and l.split()[2] in drop)))
