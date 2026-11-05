#!/usr/bin/env python3
"""addview.py LOG: for each 'Alternative `view` has not been provided' error in the build log,
add a `| view => RHS` arm to that cases block, RHS copied from a one-line unit/array/slice/struct arm."""
import re, sys
log = open(sys.argv[1]).read()
errs = re.findall(r'^error: ([^:]+\.lean):(\d+):(\d+): Alternative `view` has not been provided', log, re.M)
byfile = {}
for f, l, c in errs:
    byfile.setdefault(f, []).append((int(l), int(c)))
for f, items in byfile.items():
    L = open(f).read().split('\n')
    inserts = []
    for line, col in items:
        i = line - 1
        # arms: lines starting with col spaces + '|'
        ind = ' ' * col
        # find first arm at/after i
        j = i
        while j < len(L) and not L[j].startswith(ind + '| '):
            j += 1
        arms = []
        k = j
        last = j
        while k < len(L):
            s = L[k]
            if s.startswith(ind + '| '):
                arms.append(k); last = k
            elif s.strip() == '' or (len(s) - len(s.lstrip()) <= col and not s.startswith(ind + '|')):
                break
            else:
                last = k
            k += 1
        rhs = None
        for pref in ('unit', 'array', 'slice', 'struct', 'enum'):
            for a in arms:
                m = re.match(r'^\s*\| ' + pref + r'(?:\s+\w+)*\s*=>\s*(.+)$', L[a])
                nxt = L[a + 1] if a + 1 < len(L) else ''
                if m and m.group(1).strip() and not (nxt.startswith(ind + '  ') and not nxt.startswith(ind + '|')):
                    rhs = m.group(1); break
            if rhs: break
        if rhs is None:
            print(f'{f}:{line}: no one-line arm to copy'); continue
        inserts.append((last + 1, ind + '| view => ' + rhs))
    for pos, text in sorted(inserts, reverse=True):
        L.insert(pos, text)
    open(f, 'w').write('\n'.join(L))
    print(f, len(inserts))
