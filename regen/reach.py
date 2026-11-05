"""reach.py ROOTS [--cut M,..] [--noall]: compiler parts reachable from ROOTS (comma list or 'openF5'), cutting edges into the cut modules."""
import os,re,sys,glob
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
def imps(m):
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): return []
    return [(k.strip(),i) for k,i in re.findall(r'^((?:public |private )?import (?:all )?)(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
roots=sys.argv[1]
if roots=='openF5':
    roots=set()
    for f in glob.glob('Lanius/Open/F5/*/*.lean'):
        roots|={i for _,i in imps(f[:-5].replace('/','.')) if not i.startswith('Lanius.Open')}
else: roots=set(roots.split(','))
cut=set(sys.argv[sys.argv.index('--cut')+1].split(',')) if '--cut' in sys.argv else set()
seen=set();todo=list(roots)
while todo:
    m=todo.pop()
    if m in seen: continue
    seen.add(m); todo+=[i for k,i in imps(m) if i not in cut]
parts=sorted(m for m in seen if '.Compiler.P.' in m)
print(len(seen),'modules',len(parts),'compiler parts; roots',sorted(roots) if len(roots)<12 else len(roots))
if '-v' in sys.argv: print(parts)
