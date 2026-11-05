"""addimp.py FILE NAME...: add `import all` of the Frontend/Compiler P part defining each NAME to FILE (after its last import all)."""
import os, re, sys
f = sys.argv[1]; names = sys.argv[2:]
defs = {}
for d in ['Lanius/Mini/Frontend/P', 'Lanius/Mini/Compiler/P']:
    for n in os.listdir(d):
        if n.endswith('.lean'):
            for m in re.finditer(r'^(?:@\[[^\]]*\]\s*)?(?:private |partial |noncomputable )*(?:def|abbrev|structure|inductive) ([A-Za-z_][\w.]*)', open(os.path.join(d, n)).read(), re.M):
                defs.setdefault(m.group(1), d.replace('/', '.') + '.' + n[:-5])
text = open(f).read()
lines = text.split('\n')
last = max(i for i, l in enumerate(lines) if l.startswith('import all ') or l.startswith('public import '))
add = []
for nm in names:
    mod = defs.get(nm)
    if mod is None:
        print('no def', nm); continue
    line = f'import all {mod}'
    if line not in lines and line not in add:
        add.append(line)
print(add)
lines[last+1:last+1] = add
open(f, 'w').write('\n'.join(lines))
