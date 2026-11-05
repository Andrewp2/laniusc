# Replace each import of an extracted Compiler part that no longer exists by imports of the
# parts that now hold its definitions (same import keyword), as of the base commit BASE.
import os, re, subprocess, sys
BASE = sys.argv[1]
os.chdir('/home/andrew-peterson/code/laniusc-wt/leafC/formal')
P = 'Lanius/Mini/Compiler/P/'
DEF = re.compile(r'^(?:@\[[^\]]*\]\s*)?(?:public |private |partial |noncomputable )*(?:def|theorem|abbrev|inductive|structure|instance)\s+([\w.]+)', re.M)
where = {}
for f in os.listdir(P):
    for n in DEF.findall(open(P + f).read()):
        where.setdefault(n, f[:-5])
old = subprocess.run(['git', 'ls-tree', '--name-only', BASE, P], capture_output=True, text=True).stdout.split()
gone = {}
for path in old:
    m = os.path.basename(path)[:-5]
    if not os.path.exists(P + m + '.lean'):
        text = subprocess.run(['git', 'show', f'{BASE}:formal/{path}'], capture_output=True, text=True).stdout
        gone[m] = sorted({where[n] for n in DEF.findall(text) if n in where})
print('gone parts:', {k: v for k, v in gone.items()})
LINE = re.compile(r'^((?:public |private )?import (?:all )?)Lanius\.Mini\.Compiler\.P\.(\w+)[ \t]*\n', re.M)
files = subprocess.run(['git', 'ls-files', 'Lanius'], capture_output=True, text=True).stdout.split()
n = 0
for f in files:
    if not f.endswith('.lean') or not os.path.exists(f) or f.startswith(P):
        continue
    text = open(f).read()
    have = set(LINE.findall(text))
    have_mods = {m for _, m in have}
    def sub(mt):
        kw, m = mt.group(1), mt.group(2)
        if m not in gone:
            return mt.group(0)
        return ''.join(f'{kw}Lanius.Mini.Compiler.P.{q}\n' for q in gone[m] if q not in have_mods)
    new = LINE.sub(sub, text)
    if new != text:
        open(f, 'w').write(new); n += 1
print('files fixed', n)
