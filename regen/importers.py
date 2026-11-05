"""importers.py FROM TO: modules in FROM's closure that import TO directly, with the import kind."""
import os,re,sys
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
def imps(m):
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): return []
    return [(k.strip(),i) for k,i in re.findall(r'^((?:public |private )?import (?:all )?)(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
seen=set();todo=list(sys.argv[1].split(','))
while todo:
    m=todo.pop()
    if m in seen: continue
    seen.add(m); todo+=[i for _,i in imps(m)]
for m in sorted(seen):
    ks=[k for k,i in imps(m) if i==sys.argv[2]]
    if ks: print(m, ks)
