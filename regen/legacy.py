"""legacy.py ROOT..: the non-module Lanius files in the import closure of ROOTs (glob patterns ok), excluding the roots."""
import os,re,sys,glob
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
def path(m): return m.replace('.','/')+'.lean'
def imps(m):
    p=path(m)
    if not os.path.exists(p): return []
    return [i for i in re.findall(r'^(?:public |private )?import (?:all )?(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
roots=set()
for a in sys.argv[1:]: roots|={f[:-5].replace('/','.') for f in glob.glob(a)}
seen=set();todo=list(roots)
while todo:
    m=todo.pop()
    if m in seen: continue
    seen.add(m); todo+=imps(m)
leg=sorted(m for m in seen-roots if os.path.exists(path(m)) and not open(path(m)).read().startswith('module'))
print(len(seen),'in closure;',len(leg),'legacy:'); print('\n'.join(leg))
