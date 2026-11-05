import sys, re
# Adds an eStr alternative next to each `.eLen _` pattern segment.
for p in sys.argv[1:]:
    lines = open(p).read().split('\n')
    out = []
    n = 0
    for ln in lines:
        i = ln.find('.eLen _')
        if i >= 0 and '.eStr' not in ln and ln.lstrip().startswith('|'):
            s = ln.rfind('| ', 0, i) + 2
            j1 = ln.find(' =>', i); j2 = ln.find(' |', i)
            js = [j for j in (j1, j2) if j >= 0]
            e = min(js) if js else len(ln)
            seg = ln[s:e]
            ln = ln[:s] + seg + ' | ' + seg.replace('.eLen _', '.eStr _ _') + ln[e:]
            n += 1
        out.append(ln)
    open(p, 'w').write('\n'.join(out))
    print(p, n)
