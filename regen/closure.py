"""closure.py MODULE..: the Lanius modules in the import closure, summarized by prefix."""
import os,re,sys,collections
os.chdir('/home/andrew-peterson/code/laniusc-wt/regen/formal')
seen=set();todo=list(sys.argv[1:])
while todo:
    m=todo.pop()
    if m in seen: continue
    p=m.replace('.','/')+'.lean'
    if not os.path.exists(p): continue
    seen.add(m)
    todo+=[i for i in re.findall(r'^(?:public |private )?import (?:all )?(\S+)',open(p).read(),re.M) if i.startswith('Lanius')]
c=collections.Counter('.'.join(m.split('.')[:3]) + ('.P' if '.P.' in m else '') for m in seen)
print(len(seen)); print(sorted(c.items(), key=lambda x:-x[1])[:25])
