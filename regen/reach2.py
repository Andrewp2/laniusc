"""reach2.py: from Open.F5's roots, which compiler parts are reachable using only public/plain imports among
non-part modules plus part->part edges, i.e. if every `import all` of a part in Mini files were dropped."""
import os,re,sys,glob
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
def imps(m):
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): return []
    return [(k.strip(),i) for k,i in re.findall(r'^((?:public |private )?import (?:all )?)(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
roots=set()
for f in glob.glob('Lanius/Open/F5/*/*.lean'):
    roots|={i for _,i in imps(f[:-5].replace('/','.')) if not i.startswith('Lanius.Open')}
cut={'Lanius.Mini.Compiler'}
seen=set();todo=list(roots)
while todo:
    m=todo.pop()
    if m in seen: continue
    seen.add(m)
    for k,i in imps(m):
        if i in cut: continue
        if k=='import all' and '.Compiler.P.' in i and '.Compiler.P.' not in m: continue
        todo.append(i)
parts=sorted(m.split('.')[-1] for m in seen if '.Compiler.P.' in m)
print(len(parts)); print(' '.join(parts))
