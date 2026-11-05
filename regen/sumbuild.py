"""sumbuild.py LOG..: modules built and their seconds, by group."""
import sys,re,collections
g=collections.defaultdict(lambda:[0,0.0]); tot=[0,0.0]
for p in sys.argv[1:]:
    for line in open(p):
        m=re.search(r'Built (\S+) \(([\d.]+)(ms|s)\)',line)
        if not m: continue
        n=m.group(1); s=float(m.group(2))/(1000 if m.group(3)=='ms' else 1)
        if n.startswith('Lanius.Faithful.GenB'): k='GenB.'+re.sub(r'(C_|F_|N|\d).*','',n.split('.')[-1])
        elif n.startswith('Lanius.Faithful.Gen.'): k='Gen.'+re.sub(r'(C_|F_|\d).*','',n.split('.')[-1])
        elif 'Open.F5' in n: k='Open.F5'
        elif 'Open.F14' in n: k='Open.F14'
        else: k='.'.join(n.split('.')[:3])
        g[k][0]+=1; g[k][1]+=s; tot[0]+=1; tot[1]+=s
print(f'total {tot[0]} modules, {tot[1]:.0f} s')
for k,v in sorted(g.items(), key=lambda x:-x[1][1])[:22]: print(f'{v[1]:7.0f} s {v[0]:4d} {k}')
