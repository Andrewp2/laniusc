"""After an extraction moved definitions between P parts: for every Lean file
that imports (all) a part of MODULE, also import (the same way) each part that
now holds a definition the old part held at HEAD. argv: MODULE (e.g. Frontend)"""
import os, re, subprocess, sys
mod = sys.argv[1]
root = '/home/andrew-peterson/code/laniusc-wt/rfront/formal'
pdir = f'Lanius/Mini/{mod}/P'
pre = f'Lanius.Mini.{mod}.P.'
def defs(text):
    return set(re.findall(r'^(?:@\[expose\] )?(?:private )?(?:def|theorem|abbrev|structure|inductive) (\S+)', text, re.M))
head = {}
names = subprocess.run(['git', 'ls-tree', '--name-only', 'HEAD', pdir + '/'], cwd=root, capture_output=True, text=True).stdout.split()
for n in names:
    head[os.path.basename(n)[:-5]] = defs(subprocess.run(['git', 'show', 'HEAD:formal/' + n] if False else ['git', 'show', 'HEAD:' + 'formal/' + n], cwd=root, capture_output=True, text=True).stdout)
now = {}
for n in os.listdir(os.path.join(root, pdir)):
    if n.endswith('.lean'):
        now[n[:-5]] = defs(open(os.path.join(root, pdir, n)).read())
where = {}
for p, ds in now.items():
    for d in ds:
        where[d] = p
changed = 0
for dp, _, fs in os.walk(os.path.join(root, 'Lanius')):
    if '/P' in dp.replace(root, '') and dp.endswith('/P'):
        continue
    for f in fs:
        if not f.endswith('.lean'):
            continue
        path = os.path.join(dp, f)
        text = open(path).read()
        if '-- import all: ' in text:
            continue
        lines = text.split('\n')
        out = []; have = set(re.findall(r'^((?:public )?import(?: all)?) ' + re.escape(pre) + r'(\w+)$', text, re.M))
        haveparts = {(k, p) for k, p in have}
        add = []
        for l in lines:
            m = re.match(r'^((?:public )?import(?: all)?) ' + re.escape(pre) + r'(\w+)$', l)
            if m and m.group(2) in head:
                kind, old = m.group(1), m.group(2)
                news = sorted({where[d] for d in head[old] if d in where} - {old})
                if old in now:
                    out.append(l)
                for np in news:
                    if (kind, np) not in haveparts:
                        out.append(f'{kind} {pre}{np}'); haveparts.add((kind, np))
                continue
            out.append(l)
        new = '\n'.join(out)
        if new != text:
            open(path, 'w').write(new); changed += 1; print(path.replace(root + '/', ''))
print('changed', changed)
