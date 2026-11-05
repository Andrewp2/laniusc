"""Add a Ref(..) arm after every `Str ->` SrcType arm of a .lani file (F5 stage 1, S1)."""
import re, sys
path = sys.argv[1]
lines = open(path).read().split('\n')
out = []
fn = ''
depth_same = False
for i, line in enumerate(lines):
    out.append(line)
    m = re.match(r'^(\s*)(pub )?fn (\w+)', line)
    if m:
        fn = m.group(3)
    m = re.match(r'^(\s*)Str -> (.*)$', line)
    if not m:
        continue
    ind, val = m.group(1), m.group(2)
    binder = 'referent'
    if fn == 'same':
        if val.startswith('other.is_str'):
            new = 'false,'
        else:
            binder = 'other_referent'
            new = 'false,'
    elif fn == 'is_str':
        new = 'false,'
    elif fn == 'size':
        new = '1,'
    elif fn == 'declare':
        new = 'None,'
    else:
        new = val
    out.append(f'{ind}Ref({binder}) -> {new}')
open(path, 'w').write('\n'.join(out))
