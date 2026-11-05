import sys, re
# Adds a SrcType.str alternative next to each view pattern segment.
pat = re.compile(r'(?<![\w.])(\.view _|view _|\.view|view)(?![\w])')
for p in sys.argv[1:]:
    lines = open(p).read().split('\n'); out = []; n = 0
    for ln in lines:
        st = ln.lstrip()
        m = pat.search(ln)
        if m and st.startswith('|') and not re.search(r'(?<![\w])\.?str(?![\w])', ln) and ln.find(' =>') > m.start():
            i = m.start()
            s = ln.rfind('| ', 0, i) + 2
            j1 = ln.find(' =>', i); j2 = ln.find(' |', i)
            e = min(j for j in (j1, j2) if j >= 0)
            seg = ln[s:e]
            rep = '.str' if m.group(1).startswith('.') else 'str'
            seg2 = seg[:i-s] + rep + seg[m.end()-s:]
            ln = ln[:s] + seg + ' | ' + seg2 + ln[e:]
            n += 1
        out.append(ln)
    open(p, 'w').write('\n'.join(out)); print(p, n)
