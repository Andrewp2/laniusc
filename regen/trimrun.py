"""trimrun.py: for each Lean file with `import all` of Mini compiler parts, keep only the directly named ones
(direct.py --write) and lcheck it; a failing file goes back to its text. Resumable: results in trim/state.txt;
stops starting new checks after 230 s."""
import os,re,sys,glob,subprocess,time,shutil
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; D='/home/andrew-peterson/code/laniusc/target/claude-work/regen'
st=D+'/trim/state.txt'; os.makedirs(D+'/trim/orig',exist_ok=True)
done={l.split()[0] for l in open(st)} if os.path.exists(st) else set()
files=sorted(p[len(F)+1:] for p in glob.glob(F+'/Lanius/**/*.lean',recursive=True)
             if re.search(r'^import all Lanius\.Mini\.Compiler\.P\.',open(p).read(),re.M)
             and '/Compiler/P/' not in p and '/Faithful/Gen/' not in p and '/GenB/' not in p)
began=time.time()
for f in files:
    if f in done: continue
    if time.time()-began>230: print('stopping; rerun'); break
    p=F+'/'+f; orig=open(p).read(); bak=D+'/trim/orig/'+f.replace('/','_')
    if not os.path.exists(bak): open(bak,'w').write(orig)
    out=subprocess.run(['python3',D+'/direct.py',f,'--write'],cwd=F,capture_output=True,text=True).stdout.strip()
    if open(p).read()==orig:
        res='same'
    else:
        t=time.time()
        r=subprocess.run([D.rsplit('/regen',1)[0]+'/bin/lcheck',f],cwd=F,capture_output=True,text=True)
        errs=[l for l in (r.stdout+r.stderr).split('\n') if ': error' in l]
        if r.returncode==0 and not errs: res=f'pass {time.time()-t:.0f}s'
        else:
            open(p,'w').write(orig); res=f'FAIL {time.time()-t:.0f}s rc={r.returncode} '+(errs[0][len(F)+1:][:200] if errs else (r.stdout+r.stderr)[-200:].replace('\n',' '))
    line=f'{f} {res} | {out.split(": ",1)[1] if ": " in out else out}'
    print(line); open(st,'a').write(line+'\n')
print(len(done)+0, 'previously;', len(files),'files')
