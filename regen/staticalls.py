"""staticalls.py FILE..: add `import all` of every compiler/front-end part defining a name the file unfolds
(`unfold X`, `X.eq_def`, `simp [.. X ..]`, `rw [X]`), without checking it."""
import os,re,sys
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'
defs={}
for d in ('Lanius/Mini/Compiler/P','Lanius/Mini/Frontend/P'):
    for f in os.listdir(F+'/'+d):
        mod=(d+'/'+f[:-5]).replace('/','.')
        for n in re.findall(r"^\s*(?:private |protected |noncomputable )*(?:def|abbrev) ([A-Za-z0-9_.']+)",open(F+'/'+d+'/'+f).read(),re.M):
            defs.setdefault(n,mod); defs.setdefault(n.split('.')[-1],mod)
CLOSE='--closure' in sys.argv
def pclosure(m,seen):
    if m in seen or '.P.' not in m: return
    seen.add(m)
    for x in re.findall(r'^(?:public )?import (?:all )?(\S+)',open(F+'/'+m.replace('.','/')+'.lean').read(),re.M): pclosure(x,seen)
for p in [a for a in sys.argv[1:] if not a.startswith('--')]:
    t=open(p).read()
    names=set(re.findall(r"unfold ([A-Za-z0-9_.' ]+)",t))
    names={w for s in names for w in s.split()}
    names|=set(re.findall(r"([A-Za-z0-9_']+)\.eq_(?:def|\d+)",t))
    for blk in re.findall(r"(?:simp|rw|simp only|dsimp only|simp_all)\s*\[([^\]]*)\]",t):
        names|={w.strip().lstrip('←').strip() for w in blk.split(',')}
    mods={defs[n] for n in names if n in defs}
    if CLOSE:
        s=set()
        for m in mods: pclosure(m,s)
        mods=s
    have=set(re.findall(r'^import all (\S+)',t,re.M)); new=sorted(m for m in mods if m not in have)
    if not new: continue
    ls=t.split('\n'); k=max(i for i,l in enumerate(ls) if re.match(r'(public |private )?import ',l))
    ls[k+1:k+1]=[f'import all {m}' for m in new]; open(p,'w').write('\n'.join(ls)); print(p,'+',len(new))
