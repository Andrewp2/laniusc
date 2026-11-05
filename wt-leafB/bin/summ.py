# summ.py [NAMES...]: per failing theorem of probe/P02nb.lean, its first error line(s)
import re, sys
P = '/home/andrew-peterson/code/laniusc-wt/leafB/target/claude-work/leafB/probe/'
src = open(P + 'P02nb.lean').read().split('\n')
out = open(P + 'P02nb.out').read()
starts = [(i + 1, re.match(r'theorem (\S+)', l).group(1)) for i, l in enumerate(src) if l.startswith('theorem ')]
seen = {}
for blk in re.split(r'\n(?=\S+P02nb\.lean:\d+:\d+: error)', out):
    m = re.search(r'P02nb\.lean:(\d+):\d+: error: (.*)', blk)
    if not m:
        continue
    nm = [n for s, n in starts if s <= int(m.group(1))][-1]
    if sys.argv[1:] and nm not in sys.argv[1:]:
        continue
    rest = blk[m.end():].strip().split('\n')[0][:150]
    seen.setdefault(nm, []).append(m.group(2)[:110] + ' | ' + rest)
for nm, es in seen.items():
    print(nm, '::', es[0], f'(+{len(es)-1})' if len(es) > 1 else '')
