import subprocess, sys, os
os.chdir('/home/andrew-peterson/code/laniusc-wt/leafC/formal')
new = [l.split('/P/')[1][:-5] for l in subprocess.run(['git','status','--short','Lanius/Mini/Frontend/P'],capture_output=True,text=True).stdout.split('\n') if l.startswith('??')]
files = subprocess.run(['grep','-rl','import all Lanius.Mini.Frontend.P.','Lanius','--include=*.lean'],capture_output=True,text=True).stdout.split()
files = [f for f in files if '/Gen/' not in f and '/GenB/' not in f and '/GenP/' not in f and 'Frontend/P/' not in f]
for f in files:
    lines = open(f).read().split('\n')
    idx = max(i for i,l in enumerate(lines) if l.startswith('import '))
    added = 0
    for n in new:
        imp = f'import all Lanius.Mini.Frontend.P.{n}'
        if imp not in lines:
            lines.insert(idx+1, imp); added += 1
    # drop imports of missing P files
    keep = []
    for l in lines:
        if l.startswith('import all Lanius.Mini.Frontend.P.') and not os.path.exists('Lanius/Mini/Frontend/P/' + l.split('P.',1)[1].strip() + '.lean'):
            continue
        keep.append(l)
    open(f,'w').write('\n'.join(keep))
print(len(files), new)
