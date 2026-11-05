"""wholeprog.py FILE..: `import all` the generated modules that define the self program as a whole (Self, SelfProg,
SelfPure*, SelfPrim*, SelfTypes and every SelfSrc), for a module whose kernel checks evaluate the whole program."""
import glob,os,re,sys
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'
gen=sorted('Lanius.Faithful.Gen.'+os.path.basename(p)[:-5] for p in glob.glob(F+'/Lanius/Faithful/Gen/*.lean')
           if re.match(r'(SelfSrc.*|SelfProg|SelfPure|SelfPureBase|SelfPureTab|SelfPrims|SelfPrimTab|SelfTypes|Self)\.lean$',os.path.basename(p)))
for p in sys.argv[1:]:
    t=open(p).read(); have=set(re.findall(r'^import all (\S+)',t,re.M))
    ls=t.split('\n'); k=max(i for i,l in enumerate(ls) if re.match(r'(public |private )?import ',l))
    ls[k+1:k+1]=[f'import all {m}' for m in gen if m not in have]; open(p,'w').write('\n'.join(ls))
