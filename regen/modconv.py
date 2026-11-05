"""modconv.py FILE..: turn a legacy Lean file into a module: `module`, its imports public, and an
`@[expose] public section` after them."""
import re,sys
for p in sys.argv[1:]:
    t=open(p).read()
    if t.startswith('module'): continue
    # a module cannot import a legacy file: leave this one legacy too
    import os
    leg=[m for m in re.findall(r'^import (\S+)',t,re.M) if os.path.exists(m.replace('.','/')+'.lean') and not open(m.replace('.','/')+'.lean').read().startswith('module')]
    if leg: print('skip',p,'imports legacy',leg[0]); continue
    lines=t.split('\n'); i=0
    while i<len(lines) and (lines[i].startswith('import ') or lines[i].strip()==''): i+=1
    head=[('public '+l if l.startswith('import ') else l) for l in lines[:i] if l.strip()]
    open(p,'w').write('module\n\n'+'\n'.join(head)+'\n\n@[expose] public section\n\n'+'\n'.join(lines[i:]))
