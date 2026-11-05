# defs.py NAME...: the Lean definitions of Lanius.Mini compiler functions (camelCase names) from Compiler/P
import sys, glob, re
src = {}
for f in glob.glob('/home/andrew-peterson/code/laniusc-wt/leafB/formal/Lanius/Mini/Compiler/P/*.lean'):
    lines = open(f).read().split('\n')
    for i, l in enumerate(lines):
        m = re.match(r'def (\S+)', l)
        if m:
            j = i + 1
            while j < len(lines) and lines[j].strip() and not re.match(r'(def|/--|end|mutual|theorem)\b', lines[j]):
                j += 1
            src[m.group(1)] = '\n'.join(lines[i:j])
for n in sys.argv[1:]:
    print(src.get(n, f'-- {n}: not found')); print()
