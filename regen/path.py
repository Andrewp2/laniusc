"""path.py FROM TO: a shortest import path from module FROM to TO (all import kinds)."""
import os,re,sys,collections
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
def imps(m):
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): return []
    return [(k.strip(),i) for k,i in re.findall(r'^((?:public |private )?import (?:all )?)(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
src,dst=sys.argv[1],sys.argv[2]
prev={src:None};q=collections.deque([src])
while q:
    m=q.popleft()
    if m==dst: break
    for k,i in imps(m):
        if i not in prev: prev[i]=(m,k); q.append(i)
if dst not in prev: print('no path'); sys.exit()
out=[];m=dst
while prev[m]: out.append((prev[m][1],m)); m=prev[m][0]
print(src); [print(f'  {k} {m}') for k,m in reversed(out)]
