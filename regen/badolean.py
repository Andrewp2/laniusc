"""badolean.py MODULE: find the first module in MODULE's import closure (topological order) whose olean crashes lean
on import (prefix bisection with lcheck probes)."""
import os,re,sys,subprocess
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; os.chdir(F)
order=[];seen=set()
def visit(m):
    if m in seen: return
    seen.add(m)
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): return
    for l in open(p):
        x=re.match(r'(?:public )?(?:meta )?import (?:all )?(\S+)',l)
        if x: visit(x.group(1))
        elif l.strip() and not l.startswith(('module','--','/-')) and not l.startswith(' '): 
            if not l.startswith(('public','import')): break
    order.append(m)
visit(sys.argv[1])
def crash(k):
    open('.probe/P.lean','w').write(''.join(f'import {m}\n' for m in order[:k]))
    r=subprocess.run(['/home/andrew-peterson/code/laniusc/target/claude-work/bin/lcheck','.probe/P.lean'],capture_output=True)
    return r.returncode==139
lo,hi=0,len(order)
assert crash(hi)
while hi-lo>1:
    mid=(lo+hi)//2
    if crash(mid): hi=mid
    else: lo=mid
print(len(order),'bad:',order[hi-1])
