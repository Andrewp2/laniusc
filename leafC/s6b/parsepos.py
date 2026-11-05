# parsepos.py FILE.lani: CPU-parse a .lani; on failure print the furthest token reached.
import os, sys, shutil
T='/home/andrew-peterson/code/laniusc-wt/leafC/formal/tools'
sys.path.insert(0, T)
import run_cache, fuzz_oracle
W='/home/andrew-peterson/code/laniusc/target/claude-work/leafC/s6b/pp'
shutil.copyfile(sys.argv[1], W+'/f.lani')
open(W+'/f.prods','w').close(); open(W+'/f.parents','w').close()
man=W+'/m.txt'; open(man,'w').write(f'dump d0 {W}/f\n')
out=run_cache.run_all(man).stdout
lines=[l for l in out.split('\n') if ' file ' in l]
if not lines: print('NO DUMP LINE'); print(out[-2000:]); sys.exit(1)
line=lines[0]
toks=line.split(' file ',1)[1].split('|')[0].split()
print('tokens', len(toks), 'sample', toks[:3])
class K(list):
    mx=0
    def __getitem__(self,i):
        if isinstance(i,int) and i>K.mx: K.mx=i
        return list.__getitem__(self,i)
p=fuzz_oracle.Parser()
r=p.parse(K(p.tokens(line)))
if r is not None: print('PARSES'); sys.exit(0)
t=toks[K.mx]; off=int(t.split(':')[1]); src=open(sys.argv[1],'rb').read(); ln=src[:off].count(b'\n')+1; print('fail at line', ln); print(src[max(0,off-200):off+80].decode())
