# fixarms.py LOG CTOR PATTERN: for each "file:line:col: Alternative `CTOR` has not been provided",
# add `| CTOR PATTERN => body` copying a rejecting single-line arm of the same cases block.
import re, sys
log, ctor, pat = sys.argv[1], sys.argv[2], sys.argv[3]
errs = {}
for m in re.finditer(r'error: (\S+\.lean):(\d+):(\d+): Alternative `' + ctor + '` has not been provided', open(log).read()):
    errs.setdefault(m.group(1), set()).add((int(m.group(2)), int(m.group(3))))
skip = []
for f, locs in errs.items():
    lines = open(f).read().split('\n')
    inserts = []
    for (ln, col) in sorted(locs):
        i = ln - 1
        # arms: first line after i starting with spaces + '|'
        j = i + 1
        while j < len(lines) and not re.match(r'^\s*\| ', lines[j]): j += 1
        ind = len(lines[j]) - len(lines[j].lstrip())
        arms = []
        k = j
        while k < len(lines):
            L = lines[k]
            if L.strip() == '': break
            cur = len(L) - len(L.lstrip())
            if cur < ind: break
            if cur == ind and not L.lstrip().startswith('|'): break
            if cur == ind:
                arms.append(k)
            k += 1
        end = k
        best = None
        for a in arms:
            nxt = arms[arms.index(a)+1] if arms.index(a)+1 < len(arms) else end
            single = (nxt == a + 1)
            m = re.match(r'^\s*\| (\w+)((?: _)*) => (.*)$', lines[a])
            if not m or not single: continue
            body = m.group(3)
            if 'exact' in body or '⟨' in body or 'rfl' == body.strip(): continue
            if re.search(r'\b(e|n|k|ft|d|args|x)\b', body) and m.group(2) == '': pass
            best = body; break
        if best is None:
            skip.append(f'{f}:{ln}'); continue
        inserts.append((end, ' ' * ind + f'| {ctor}{pat} => {best}'))
    for pos, text in sorted(inserts, reverse=True):
        lines.insert(pos, text)
    open(f, 'w').write('\n'.join(lines))
    print(f, len(inserts), 'inserted')
print('manual:', skip)
