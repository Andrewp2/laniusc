"""probe.py WORK NAME=FILE..: laniusc parse trees, then runAll diag for each."""
import os, sys, subprocess, shutil
sys.path.insert(0, 'formal/tools')
import stdlib_oracle
RUN_ALL = '/home/andrew-peterson/code/laniusc/formal/.lake/build/bin/runAll'
work = os.path.abspath(sys.argv[1]); os.makedirs(work, exist_ok=True)
stdlib_oracle.front.PARSE_SERVER.enable()
lines = []
for arg in sys.argv[2:]:
    name, path = arg.split('=')
    base = os.path.join(work, name)
    shutil.copy(path, base + '.lani')
    if not stdlib_oracle.parse_checked('target/release/laniusc', base, work):
        print(name, 'NO PARSE'); continue
    lines.append(f'diag {name} {base}')
open(os.path.join(work, 'm.txt'), 'w').write('\n'.join(lines) + '\n')
out = subprocess.run([RUN_ALL, os.path.join(work, 'm.txt')], capture_output=True, text=True, timeout=200)
print(out.stdout.rstrip()[:3000]); print(out.stderr.rstrip()[:1000])
