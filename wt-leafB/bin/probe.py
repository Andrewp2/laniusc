#!/usr/bin/env python3
"""probe.py SRC OUT KEY... : SRC's header plus the post/pre blocks of KEYs and of
every key their models call (transitively) that SRC defines; KEYs' own blocks get
`set_option lanius.hb.debug true in` when DEBUG=1. Run from formal/."""
import os, sys, re
sys.path.insert(0, 'tools')
import pre_certs as pc
src, out, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
m = pc.Models('Lanius/Faithful/GenB')
txt = open(src).read()
i = txt.index('\ntheorem ')
head, body = txt[:i + 1], txt[i + 1:]
end = body.rfind('\nend ')
tail, body = body[end:], body[:end]
blocks = re.split(r'\n(?=theorem |set_option lanius)', body)
names = {}
for b in blocks:
    mm = re.match(r'theorem (\S+)', b)
    if mm:
        names[mm.group(1)] = b
kind = 'Pre' if any(n.startswith('pre_') for n in names) else 'Cost'
lem = 'pre' if kind == 'Pre' else 'post'
seen, st = set(), list(keys)
while st:
    k = st.pop()
    if k in seen:
        continue
    seen.add(k)
    for g in m.group.get(f'{kind}_{k}', ()):
        st.append(g.split('_', 1)[1])
    for d in m.deps(f'{kind}_{k}'):
        if d.startswith(kind + '_'):
            st.append(d.split('_', 1)[1])
keep = []
for b in blocks:
    mm = re.match(r'theorem (\S+)', b)
    if not mm:
        continue
    n = mm.group(1)
    for pre in (f'{lem}_step_', f'{lem}_group_', f'{lem}_'):
        if n.startswith(pre) and n[len(pre):] in seen:
            dbg = os.environ.get('DEBUG') and n[len(pre):] in keys and pre != f'{lem}_group_'
            keep.append(('set_option lanius.hb.debug true in\n' if dbg else '') + b.rstrip('\n') + '\n')
            break
open(out, 'w').write(head + '\n'.join(keep) + tail)
print(len(keep), 'blocks', len(seen), 'keys')
