#!/usr/bin/python3 -I
"""Add `import all Lanius.Mini.Compiler.P.X` for every P module a Mini file lacks (after its last import all P line)."""
import os, re, sys
formal = os.getcwd()
pdir = os.path.join(formal, 'Lanius/Mini/Compiler/P')
mods = sorted(f[:-5] for f in os.listdir(pdir) if f.endswith('.lean'))
for path in sys.argv[1:]:
    lines = open(path).read().split('\n')
    have = {m.group(1) for l in lines for m in [re.match(r'import all Lanius\.Mini\.Compiler\.P\.(\S+)', l)] if m}
    missing = [m for m in mods if m not in have]
    idx = max((i for i, l in enumerate(lines) if l.startswith('import all Lanius.Mini.Compiler.P.')), default=None)
    if idx is None:
        idx = max(i for i, l in enumerate(lines) if l.startswith('public import') or l.startswith('import'))
    lines[idx+1:idx+1] = ['import all Lanius.Mini.Compiler.P.' + m for m in missing]
    open(path, 'w').write('\n'.join(lines))
    print(path, 'added', len(missing))
