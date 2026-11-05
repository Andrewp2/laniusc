# groups.py: per failing theorem of DBGALL.lean/out, its distinct failed omega goals and premises
import re, collections
P = '/home/andrew-peterson/code/laniusc-wt/leafB/target/claude-work/leafB/probe/'
src = open(P + 'DBGALL.lean').read().split('\n')
starts = [(i + 1, re.match(r'theorem (\S+)', l).group(1)) for i, l in enumerate(src) if l.startswith('theorem ')]
lines = open(P + 'DBGALL.out').read().split('\n')
cur = None; res = collections.OrderedDict(); last = None
for l in lines:
    m = re.search(r'DBGALL\.lean:(\d+):\d+: error', l)
    if m:
        cur = [n for s, n in starts if s <= int(m.group(1))][-1]; res.setdefault(cur, [[], []]); continue
    if cur is None: continue
    if l.startswith('OMEGA '): last = l[6:]
    elif l.startswith('omegaAtoms: failed') and last:
        if last not in res[cur][0]: res[cur][0].append(last)
    elif l.startswith('premise failed: '):
        p = l[16:]
        if p not in res[cur][1]: res[cur][1].append(p)
for n, (gs, ps) in res.items():
    print(n)
    for p in ps: print('   P', p[:160])
    for g in gs:
        if g not in ps: print('   O', g[:160])
