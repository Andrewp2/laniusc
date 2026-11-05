"""warnfix.py FILE..: lcheck each file and fix its warnings mechanically: unused simp arguments (removed),
unused variables (prefixed `_`), unused section variables (`omit .. in` before the declaration).
Repeats until no warnings (3 rounds); a file whose fix breaks it goes back. Results in trim/warn.txt.
Stops starting new files after 220 s."""
import os,re,sys,subprocess,time
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; D='/home/andrew-peterson/code/laniusc/target/claude-work/regen'
began=time.time()
def lcheck(f):
    r=subprocess.run([D.rsplit('/regen',1)[0]+'/bin/lcheck',f],cwd=F,capture_output=True,text=True)
    return r.returncode, r.stdout+r.stderr
def msgs(out,f):
    ab=os.path.join(F,f); res=[]
    parts=re.split(r'^(?='+re.escape(ab)+r':\d+:\d+: )',out,flags=re.M)
    for p in parts:
        m=re.match(re.escape(ab)+r':(\d+):(\d+): (warning|error): (.*)',p,re.S)
        if m: res.append((int(m.group(1)),int(m.group(2)),m.group(3),m.group(4)))
    return res
def fix(text,ws):
    ls=text.split('\n'); inserts=[]; n=0
    # apply right-to-left within lines
    for line,col,kind,body in sorted(ws,key=lambda w:(-w[0],-w[1])):
        L=ls[line-1]
        if body.startswith('This simp argument is unused'):
            # remove the argument starting at col: up to the next top-level ',' or ']'
            depth=0;j=col
            while j<len(L):
                c=L[j]
                if c in '([{': depth+=1
                elif c in ')]}':
                    if depth==0: break
                    depth-=1
                elif c==',' and depth==0: break
                j+=1
            if j>=len(L) and depth==0 and not L[col:].strip():
                continue
            if j<len(L) and L[j]==',':
                L=L[:col]+L[j+1:].lstrip(' ')
            else:
                k=col
                while k>0 and L[k-1]==' ': k-=1
                if k>0 and L[k-1]==',': L=L[:k-1]+L[j:]
                elif k>0 and L[k-1]=='[' and j<len(L) and L[j]==']':
                    s=k-1
                    while s>0 and L[s-1]==' ': s-=1
                    rest=L[j+1:]
                    head=L[:s]
                    L=head+(' []' if head.rstrip().endswith('only') else '')+rest
                else: continue
            ls[line-1]=L; n+=1
        elif body.startswith('Variable name `'):
            name=re.match(r'Variable name `([^`]+)`',body).group(1)
            if L[col:col+len(name)]==name:
                ls[line-1]=L[:col]+'_'+L[col:]; n+=1
        elif body.startswith('automatically included section variable'):
            m=re.search(r'theorem `[^`]*`:\n\s*(.*?)\n',body)
            if not m: continue
            vs=m.group(1).strip()
            # the declaration's start: back over its docstring and attributes
            s=line-1
            while s>0 and not re.match(r'(theorem|lemma|def|private|protected|@\[|/--)',ls[s]): s-=1
            k=s
            while k>0 and ls[k-1].strip() and not ls[k-1].startswith(('theorem','lemma','def','end','namespace','section','variable','open')) and (ls[k-1].startswith(('/--','@[',' ')) or '-/' in ls[k-1] or ls[k-1].startswith(tuple('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ`(*'))):
                if ls[k-1].startswith('/--'): k-=1; break
                k-=1
            if not ls[k].startswith(('/--','@[','theorem','lemma','private','protected')): k=s
            inserts.append((k,f'omit {vs} in')); n+=1
    for k,t in sorted(inserts,reverse=True): ls.insert(k,t)
    return '\n'.join(ls),n
done={l.split()[0] for l in open(D+'/trim/warn.txt')} if os.path.exists(D+'/trim/warn.txt') else set()
for f in sys.argv[1:]:
    if f in done: continue
    if time.time()-began>140: print('stopping; rerun'); break
    orig=open(os.path.join(F,f)).read()
    rc,out=lcheck(f); res='clean'
    for r in range(3):
        ws=[w for w in msgs(out,f) if w[2]=='warning']
        es=[w for w in msgs(out,f) if w[2]=='error']
        if es: res=f'ERROR {es[0][0]}: {es[0][3][:120]}'; open(os.path.join(F,f),'w').write(orig); break
        if not ws: res='clean' if r==0 else f'fixed in {r} rounds'; break
        t,n=fix(open(os.path.join(F,f)).read(),ws)
        if n==0: res=f'{len(ws)} left: '+'; '.join(w[3].split(chr(10))[0][:60] for w in ws[:3]); break
        open(os.path.join(F,f),'w').write(t)
        rc,out=lcheck(f)
    else:
        ws=[w for w in msgs(out,f) if w[2]=='warning']; es=[w for w in msgs(out,f) if w[2]=='error']
        if es: res=f'ERROR {es[0][0]}: {es[0][3][:120]}'; open(os.path.join(F,f),'w').write(orig)
        else: res=f'{len(ws)} left after 3 rounds'
    line=f'{f} {res}'; print(line); open(D+'/trim/warn.txt','a').write(line+'\n')
