"""simrebuild.py [--base REV] [--show N]: which modules Lake would rebuild for the working tree's changes against
REV (default HEAD), without building. Lake's rule: a module importer's trace mixes the public oleans of its import's
whole public closure (private ones too for `import all`); a legacy file's mixes everything. A changed module's public
interface is taken to change when it is legacy, its changed text is under `@[expose]`, or a declaration's header
(the text before `:=`) changed; a module rebuilt without a source change is taken to keep its interface."""
import os,re,sys,subprocess,collections
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'; os.chdir(F)
args=sys.argv[1:]; base='HEAD'; show=40
if '--base' in args: base=args[args.index('--base')+1]
if '--show' in args: show=int(args[args.index('--show')+1])
IMP=re.compile(r'^(public )?(meta )?import (all )?(\S+)')
mods={}
for root,_,fs in os.walk('Lanius'):
    for f in fs:
        if f.endswith('.lean'):
            p=os.path.join(root,f); mods[p[:-5].replace('/','.')]=p
for f in os.listdir('.'):
    if f.endswith('.lean'): mods[f[:-5]]=f
def parse(text):
    ism=text.startswith('module'); imps=[]
    for l in text.split('\n'):
        m=IMP.match(l)
        if m: imps.append((m.group(4),bool(m.group(1)),bool(m.group(3))))
    return ism,imps
info={m:parse(open(p).read()) for m,p in mods.items()}
# --what-if: every legacy file a module (its imports public), and GenB models not exposed
WHATIF='--what-if' in args
if WHATIF:
    info={m:(True,[(x,pub or not ism,al) for x,pub,al in imps]) for m,(ism,imps) in info.items()}
changed=[l[len('formal/'):] for l in subprocess.run(['git','diff','--name-only',base,'--','.'],capture_output=True,text=True,cwd=F).stdout.split() ]
changed+= [l[len('formal/'):] if l.startswith('formal/') else l for l in subprocess.run(['git','ls-files','--others','--exclude-standard','.'],capture_output=True,text=True).stdout.split()]
chmods={c[:-5].replace('/','.') for c in changed if c.endswith('.lean')}
def headers(text):
    """declaration headers (before :=) and exposed text"""
    out=[]; exposed=False; cur=None; inthm=False
    for l in text.split('\n'):
        if '@[expose]' in l: exposed=True
        # a theorem's proof is never in the public interface, exposed or not
        if re.match(r'(@\[[^\]]*\]\s*)?(private |protected )*(theorem|lemma)\b',l): inthm=True
        elif l and not l[0].isspace() and not l.startswith(('--','/-','·','|')): inthm=False
        if exposed and not inthm: out.append(l); continue
        if re.match(r'(@\[[^\]]*\]\s*)?(private |protected |noncomputable |partial |unsafe )*(theorem|lemma|def|abbrev|instance|structure|inductive|class|axiom|opaque)\b',l):
            cur=[l]
            if ':=' in l: out.append(l.split(':=')[0]); cur=None
            continue
        if cur is not None:
            if ':=' in l: cur.append(l.split(':=')[0]); out.append('\n'.join(cur)); cur=None
            else: cur.append(l)
        elif re.match(r'(abbrev|instance|structure|inductive|class)',l): out.append(l)
    return '\n'.join(out)
pubch=set(); privch=set()
for m in chmods:
    if m not in mods: continue
    new=open(mods[m]).read()
    old=subprocess.run(['git','show',f'{base}:formal/{mods[m]}'],capture_output=True,text=True).stdout
    ism=info[m][0]
    privch.add(m)
    if (WHATIF or '--models-hidden' in args) and '.GenB.SelfBModel' in m: new=new.replace('@[expose]',''); old=old.replace('@[expose]','')
    stable=[a.split('=',1)[1] for a in args if a.startswith('--stable=')]
    if any(re.search(s,m) for s in stable): continue  # what-if: this module's interface kept
    if not ism or headers(new)!=headers(old): pubch.add(m)
# public closure
pc={}
def pclos(m):
    if m in pc: return pc[m]
    pc[m]=set()
    s=set()
    for x,pub,al in info.get(m,(0,[]))[1]:
        if pub: s.add(x); s|=pclos(x)
    pc[m]=s; return s
fc={}
def fclos(m):
    if m in fc: return fc[m]
    fc[m]=set(); s=set()
    for x,_,_ in info.get(m,(0,[]))[1]:
        s.add(x); s|=fclos(x)
    fc[m]=s; return s
order=[]; seen=set()
def topo(m):
    if m in seen: return
    seen.add(m)
    for x,_,_ in info.get(m,(0,[]))[1]: topo(x)
    order.append(m)
for m in mods: topo(m)
rebuilt=set(); why={}
for m in order:
    if m not in mods: continue
    ism,imps=info[m]
    if m in chmods: rebuilt.add(m); why[m]='source'; continue
    if not ism:
        hit=[x for x in fclos(m) if x in privch or (x in rebuilt and not info.get(x,(1,))[0])]
        if hit: rebuilt.add(m); why[m]='legacy<-'+sorted(hit)[0]; pubch.add(m); privch.add(m)
        continue
    for x,pub,al in imps:
        s={x}|pclos(x)
        hit=[y for y in s if y in pubch]
        if al and x in privch: hit.append(x+'(all)')
        if hit: rebuilt.add(m); why[m]=f'{x}<-{sorted(hit)[0]}'; break
print(f'changed sources {len(chmods)}, public-interface changes {len([m for m in pubch if m in chmods])}, rebuilt {len(rebuilt)}')
g=collections.Counter(re.sub(r'(F_|C_|N\d|\d).*','',m) for m in rebuilt)
for k,v in g.most_common(25): print(f'{v:5} {k}')
roots=collections.Counter(w.split('<-')[-1] for w in why.values() if '<-' in w)
print('culprits:',roots.most_common(15))
