#!/usr/bin/env python3
"""addinst.py FILE LINE...: give each enclosing theorem of LINE a [StaticsOf sp sx] binder after {sp : SrcProgram}."""
import sys, re
p=sys.argv[1]; lines=open(p).read().split('\n')
heads=set()
for n in map(int, sys.argv[2:]):
    i=n-1
    while i>=0 and not re.match(r'^(private )?(theorem|lemma|def) ', lines[i]): i-=1
    heads.add(i)
for i in sorted(heads):
    j=i
    while j<len(lines) and '{sp : SrcProgram}' not in lines[j] and ':=' not in lines[j]: j+=1
    if '{sp : SrcProgram}' in lines[j] and '[StaticsOf sp sx]' not in '\n'.join(lines[i:j+3]):
        lines[j]=lines[j].replace('{sp : SrcProgram}','{sp : SrcProgram} [StaticsOf sp sx]',1)
        print('added', p, i+1, lines[i][:70])
    else:
        print('SKIP', p, i+1, lines[i][:70])
open(p,'w').write('\n'.join(lines))
