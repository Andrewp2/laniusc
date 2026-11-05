# For each hand-written Lean file importing an extracted Compiler part X (any keyword), make it
# also import (same keyword) every part that now holds a definition X held at BASE. Run after a
# re-extraction regroups the parts; drops imports of parts that no longer exist.
import os, re, subprocess, sys
BASE = sys.argv[1]
os.chdir('/home/andrew-peterson/code/laniusc-wt/leafC/formal')
P = 'Lanius/Mini/Compiler/P/'
DEF = re.compile(r'^(?:@\[[^\]]*\]\s*)?(?:public |private |partial |noncomputable )*(?:def|theorem|abbrev|inductive|structure|instance)\s+([\w.]+)', re.M)
where = {}
for f in os.listdir(P):
    for n in DEF.findall(open(P + f).read()):
        where.setdefault(n, f[:-5])
oldparts = {}
def old_defs(m):
    if m not in oldparts:
        r = subprocess.run(['git', 'show', f'{BASE}:formal/{P}{m}.lean'], capture_output=True, text=True)
        oldparts[m] = DEF.findall(r.stdout) if r.returncode == 0 else []
    return oldparts[m]
LINE = re.compile(r'^((?:public |private )?import (?:all )?)Lanius\.Mini\.Compiler\.P\.(\w+)[ \t]*\n', re.M)
files = subprocess.run(['git', 'ls-files', 'Lanius'], capture_output=True, text=True).stdout.split()
n = 0
for f in files:
    if not f.endswith('.lean') or not os.path.exists(f) or f.startswith(P):
        continue
    text = open(f).read()
    have = {(kw, m) for kw, m in LINE.findall(text)}
    def sub(mt):
        kw, m = mt.group(1), mt.group(2)
        want = sorted({where[d] for d in old_defs(m) if d in where} | ({m} if os.path.exists(P + m + '.lean') else set()))
        out = []
        for q in want:
            if q == m or (kw, q) not in have:
                out.append(f'{kw}Lanius.Mini.Compiler.P.{q}\n'); have.add((kw, q))
        return ''.join(out)
    new = LINE.sub(sub, text)
    if new != text:
        open(f, 'w').write(new); n += 1
print('files updated', n)
