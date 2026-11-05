"""rewrite_parts.py: after the extractor split its parts one unit each, rewrite each hand-written file's imports of
an old part (outside the extractor's `-- import all uses:` blocks) into the new parts of that old part's units.
Old parts are read from git HEAD."""
import os,re,subprocess,sys
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; os.chdir(F)
DEF=re.compile(r"^\s*(?:@\[[^\]]*\]\s*)?(?:private |protected |noncomputable |partial )*(?:def|abbrev|inductive|structure|instance|theorem) ([A-Za-z0-9_.']+)",re.M)
dirs=['Lanius/Mini/Compiler/P','Lanius/Mini/Frontend/P','Lanius/Mini/Extract/P','Lanius/Machines/SqliteStatement/P']
new_of={}   # def name -> new part module
for d in dirs:
    for f in os.listdir(d):
        mod=(d+'/'+f[:-5]).replace('/','.')
        for n in DEF.findall(open(d+'/'+f).read()): new_of.setdefault((d,n),mod)
old_members={}  # old part module -> new part modules
for d in dirs:
    ls=subprocess.run(['git','ls-tree','--name-only','HEAD',d+'/'],capture_output=True,text=True).stdout.split()
    for p in ls:
        mod=p[:-5].replace('/','.') if p.startswith('Lanius') else (d+'/'+os.path.basename(p))[:-5].replace('/','.')
        txt=subprocess.run(['git','show','HEAD:formal/'+p if not p.startswith('formal/') else 'HEAD:'+p],capture_output=True,text=True).stdout
        if not txt: txt=subprocess.run(['git','show',f'HEAD:formal/{d}/{os.path.basename(p)}'],capture_output=True,text=True).stdout
        mod=(d+'/'+os.path.basename(p)[:-5]).replace('/','.')
        old_members[mod]=sorted({new_of[(d,n)] for n in DEF.findall(txt) if (d,n) in new_of})
print('old parts',len(old_members),'empty',sum(1 for v in old_members.values() if not v),file=sys.stderr)
IMP=re.compile(r'^((?:public )?(?:meta )?import (?:all )?)(Lanius\.(?:Mini\.(?:Compiler|Frontend|Extract)|Machines\.SqliteStatement)\.P\.\S+)$')
changed=0
for root,_,fs in os.walk('Lanius'):
    if root.endswith('/P') or '/Gen' in root: continue
    for f in fs:
        if not f.endswith('.lean'): continue
        p=os.path.join(root,f); ls=open(p).read().split('\n'); out=[]; inblock=False; touched=False; seen=set()
        for l in ls:
            if l.startswith('-- import all uses:'): inblock=True; out.append(l); continue
            m=IMP.match(l)
            if inblock and m and m.group(1)=='import all ': out.append(l); seen.add(l); continue
            inblock=False
            if m and m.group(2) in old_members:
                for nm in old_members[m.group(2)]:
                    nl=m.group(1)+nm
                    if nl not in seen: out.append(nl); seen.add(nl)
                touched=True; continue
            if m: seen.add(l)
            out.append(l)
        if touched:
            open(p,'w').write('\n'.join(out)); changed+=1
print('files rewritten',changed)
