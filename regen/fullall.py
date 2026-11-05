"""fullall.py FILE..: give FILE `import all` of every current Mini compiler part (replacing its part lines)."""
import os,re,sys,glob
F='/home/andrew-peterson/code/laniusc-wt/regen/formal'
parts=sorted('Lanius.Mini.Compiler.P.'+os.path.basename(p)[:-5] for p in glob.glob(F+'/Lanius/Mini/Compiler/P/*.lean'))
for f in sys.argv[1:]:
    ls=open(f).read().splitlines(True)
    idx=[i for i,l in enumerate(ls) if re.match(r'import all Lanius\.Mini\.Compiler\.P\.',l)]
    at=idx[0] if idx else max(i for i,l in enumerate(ls) if re.match(r'(public |private )?import ',l))+1
    ls=[l for i,l in enumerate(ls) if i not in set(idx)]
    ls[at:at]=[f'import all {p}\n' for p in parts]
    open(f,'w').write(''.join(ls))
