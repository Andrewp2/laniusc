"""fixalls.py FILE..: for a file just made a module, lcheck it; add `import all` of the compiler parts its text
names, then of the modules defining any constant lcheck reports as needing an exposed body; repeat (3 rounds).
Prints what is left failing. Stops starting new files after 230 s."""
import os,re,sys,glob,subprocess,time
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; D='/home/andrew-peterson/code/laniusc/target/claude-work/regen'
began=time.time()
defs={}
thms={}
for p in glob.glob(F+'/Lanius/**/*.lean',recursive=True):
    if '/Open/' in p or '/GenB/' in p: continue
    mod=p[len(F)+1:-5].replace('/','.')
    try: t=open(p).read()
    except: continue
    if not t.startswith('module'): continue
    ns=''
    for l in t.split('\n'):
        m=re.match(r'namespace (\S+)',l)
        if m: ns=m.group(1)
        mt=re.match(r'(?:@\[[^\]]*\] )?(?:protected )?(?:theorem|lemma) ([A-Za-z0-9_.\']+)',l)
        if mt:
            for k in [mt.group(1),mt.group(1).split('.')[-1]]+([ns+'.'+mt.group(1)] if ns else []): thms.setdefault(k,mod)
        m=re.match(r'(?:@\[[^\]]*\] )?(?:private |protected |noncomputable )*(?:def|abbrev|instance|structure|inductive) ([A-Za-z0-9_.\']+)',l)
        if m:
            n=m.group(1)
            for k in [n,n.split('.')[-1]]+([ns+'.'+n] if ns else []):
                # a compiler/front-end part wins over another module of the same short name
                if k not in defs or ('.P.' in mod and '.P.' not in defs[k]): defs[k]=mod
def lcheck(f):
    r=subprocess.run([D.rsplit('/regen',1)[0]+'/bin/lcheck',f],cwd=F,capture_output=True,text=True)
    out=r.stdout+r.stderr
    return r.returncode==0 and ': error' not in out, out
def pclosure(m,seen=None):
    """m and the compiler/front-end parts its bodies use (a part's imports of other parts), transitively."""
    seen=set() if seen is None else seen
    if m in seen or '.P.' not in m: return seen
    seen.add(m)
    p=F+'/'+m.replace('.','/')+'.lean'
    if os.path.exists(p):
        for x in re.findall(r'^(?:public )?import (?:all )?(\S+)',open(p).read(),re.M): pclosure(x,seen)
    return seen
def add(f,mods):
    t=open(F+'/'+f).read(); have=set(re.findall(r'^import all (\S+)',t,re.M)); new=[m for m in sorted(mods) if m not in have and m!=f[:-5].replace('/','.') and re.search(r'\.(P|Gen|GenB)\.',m)]
    if not new: return False
    ls=t.split('\n'); k=max(i for i,l in enumerate(ls) if re.match(r'(public |private )?import ',l))
    ls[k+1:k+1]=[f'import all {m}' for m in new]; open(F+'/'+f,'w').write('\n'.join(ls)); return True
for f in sys.argv[1:]:
    if time.time()-began>230: print('stopping; rerun'); break
    ok,out=lcheck(f)
    rounds=0
    while not ok and rounds<8:
        rounds+=1
        if rounds==1:
            d=subprocess.run(['python3',D+'/direct.py',f],cwd=F,capture_output=True,text=True)
            # parts named directly
            t=open(F+'/'+f).read()
            named=set()
            for w in re.findall(r"[A-Za-z0-9_'.]+",'\n'.join(l for l in t.split('\n') if not l.startswith(('import','public import')))):
                for c in (w, w.split('.')[-1]):
                    if c in defs and '.Compiler.P.' in defs[c]: named.add(defs[c])
            changed=True  # error-driven only: the named-parts guess import-all'd too much (11-04)
        else:
            names=set(re.findall(r'`([^`]+)`: Expected a definition with an exposed body',out))
            names|=set(re.findall(r"failed to unfold '?`?([A-Za-z0-9_.']+)",out))
            names|=set(re.findall(r"No functional induction theorem for `([^`]+)`",out))
            names|=set(re.findall(r"Invalid simp theorem `([^`]+)`",out))
            names|=set(re.findall(r"^\s+([A-Za-z0-9_.']+) ↦",out,re.M))
            ol=out.split('\n')
            for i,l in enumerate(ol):
                if 'error' in l and ('decide' in l or 'split' in l or 'rfl' in l or 'unfold' in l or 'Type mismatch' in l):
                    for w0 in re.findall(r"[A-Za-z_][A-Za-z0-9_.']*",' '.join(ol[i+1:i+4])):
                        for w in [w0]+w0.split('.'):
                            if w in defs and '.P.' in defs[w]: names.add(w)
            unk=set(re.findall(r"Unknown (?:identifier|constant) `([^`]+)`",out))
            unk|=set(re.findall(r"Function expected at\n\s+([A-Za-z_][A-Za-z0-9_.']*)\n",out))
            unk|=set(re.findall(r"Variable `([^`]+)` is not a proposition",out))
            names|=unk
            pubs={defs[n] for n in unk if n in defs}|{defs[n.split('.')[-1]] for n in unk if n.split('.')[-1] in defs}
            pubs|={thms[n] for n in unk if n in thms and n not in defs}|{thms[n.split('.')[-1]] for n in unk if n.split('.')[-1] in thms and n.split('.')[-1] not in defs}
            pubs={m for m in pubs if m!=f[:-5].replace('/','.')}
            tt=open(F+'/'+f).read(); havep=set(re.findall(r'^public import (\S+)',tt,re.M))
            newp=[m for m in sorted(pubs) if m not in havep]
            if newp:
                ls=tt.split('\n'); k=max(i for i,l in enumerate(ls) if re.match(r'public import ',l))
                ls[k+1:k+1]=[f'public import {m}' for m in newp]; open(F+'/'+f,'w').write('\n'.join(ls))
            src=open(F+'/'+f).read().split('\n')
            fixed=False
            for ln in re.findall(r':(\d+):\d+: error: Not a definitional equality',out):
                k=int(ln)-1
                while k<len(src) and k<int(ln)+8:
                    if re.search(r':= rfl\s*$',src[k]): src[k]=re.sub(r':= rfl\s*$',':= by rfl',src[k]); fixed=True; break
                    k+=1
            if fixed: open(F+'/'+f,'w').write('\n'.join(src))
            for ln in re.findall(r':(\d+):\d+: error: Not a definitional equality',out):
                k=int(ln)-1; blk=[]
                while k<len(src) and ':=' not in src[k]: blk.append(src[k]); k+=1
                if k<len(src): blk.append(src[k])
                names|=set(re.findall(r"[A-Za-z_][A-Za-z0-9_.']*",' '.join(blk)))
            names|=set(re.findall(r"\b(src_[A-Za-z0-9_]+)",out))  # a source body the goal shows unreduced
            for n in list(names):
                for c in n.split('.'): names.add(c)
            mods={defs[n] for n in names if n in defs}|{defs[n.split('.')[-1]] for n in names if n.split('.')[-1] in defs}
            if 'Tactic `decide` failed' in out or 'decide +kernel' in out:
                for m in list(mods): mods|=pclosure(m)
            changed=add(f,mods) or fixed or bool(newp)
        if not changed: break
        ok,out=lcheck(f)
    errs=[l[len(F)+1:][:160] for l in out.split('\n') if ': error' in l]
    print(f, 'OK' if ok else f'FAIL {len(errs)}: '+(errs[0] if errs else out[-200:]))
