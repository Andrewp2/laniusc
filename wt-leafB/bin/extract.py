#!/usr/bin/env python3
"""extract.py SRC OUT NAME... : SRC's header plus the named theorem blocks (and
every block whose name has a listed prefix with '*'), for one-file probes."""
import sys, re
src, out, names = sys.argv[1], sys.argv[2], sys.argv[3:]
txt = open(src).read()
i = txt.index('\ntheorem ')
head, body = txt[:i + 1], txt[i + 1:]
end = body.rfind('\nend ')
tail = body[end:]
body = body[:end]
blocks = re.split(r'\n(?=theorem )', body)
keep = []
for b in blocks:
    m = re.match(r'theorem (\S+)', b)
    n = m.group(1)
    if any(n == x or (x.endswith('*') and n.startswith(x[:-1])) for x in names):
        keep.append(b.rstrip('\n') + '\n')
open(out, 'w').write(head + '\n'.join(keep) + tail)
print(len(keep), 'blocks')
