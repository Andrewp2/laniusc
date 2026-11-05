"""trimbisect.py FILE..: for files whose directly named parts are not enough, drop as many of the other
`import all` part lines as lcheck allows, by halving (resumable: trim/bisect.json; stops starting checks
after 230 s). The file is left as its original minus the lines found droppable."""
import os,re,sys,json,subprocess,time
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; D='/home/andrew-peterson/code/laniusc/target/claude-work/regen'
sp=D+'/trim/bisect.json'; S=json.load(open(sp)) if os.path.exists(sp) else {}
began=time.time()
def text(orig,drop): return ''.join(l for l in orig.splitlines(True) if not (l.startswith('import all ') and l.split()[2] in drop))
def ok(f):
    r=subprocess.run([D.rsplit('/regen',1)[0]+'/bin/lcheck',f],cwd=F,capture_output=True,text=True)
    return r.returncode==0 and ': error' not in r.stdout+r.stderr
for f in sys.argv[1:]:
    orig=open(D+'/trim/orig/'+f.replace('/','_')).read()
    if f not in S:
        out=subprocess.run(['python3',D+'/direct.py',f],cwd=F,capture_output=True,text=True).stdout
        open(F+'/'+f,'w').write(orig)
        alls=re.findall(r'^import all (Lanius\.Mini\.Compiler\.P\.\S+)$',orig,re.M)
        subprocess.run(['python3',D+'/direct.py',f,'--write'],cwd=F)
        kept=set(re.findall(r'^import all (Lanius\.Mini\.Compiler\.P\.\S+)$',open(F+'/'+f).read(),re.M))
        C=[a for a in alls if a not in kept]  # removing all of C failed (trimrun.py)
        S[f]={'todo':[C[len(C)//2:],C[:len(C)//2]] if len(C)>1 else [],'drop':[],'keep':C if len(C)==1 else []}
    s=S[f]
    while s['todo'] and time.time()-began<230:
        ch=s['todo'].pop()
        open(F+'/'+f,'w').write(text(orig,set(s['drop'])|set(ch)))
        if ok(f): s['drop']+=ch
        elif len(ch)>1: s['todo']+=[ch[len(ch)//2:],ch[:len(ch)//2]]
        else: s['keep']+=ch
        json.dump(S,open(sp,'w'),indent=1)
    open(F+'/'+f,'w').write(text(orig,set(s['drop'])))
    print(f, 'DONE' if not s['todo'] else 'pending', 'dropped',len(s['drop']),'kept extra',s['keep'])
    if time.time()-began>=230: print('stopping; rerun'); break
