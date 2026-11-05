#!/bin/bash
# Re-extract compiler and frontend with the built extractor, then drop imports of parts that no longer exist.
cd /home/andrew-peterson/code/laniusc-wt/leafC
timeout 250 python3 -u /home/andrew-peterson/code/laniusc/target/claude-work/leafC/s6c/lx_nobuild.py --work /home/andrew-peterson/code/laniusc/target/claude-work/leafC/s6b/lx compiler frontend 2>&1 | tail -3 | cut -c1-200
python3 /home/andrew-peterson/code/laniusc/target/claude-work/leafC/s6c/fix_imports.py ${BASE:-HEAD}
python3 - <<'PY'
import sys,subprocess
sys.path.insert(0,'formal/tools')
import regen
files=subprocess.run(['git','ls-files','formal/Lanius'],capture_output=True,text=True).stdout.split()
files=[f for f in files if f.endswith('.lean')]
print('imports dropped in', len(regen.drop_missing_parts(files)), 'files')
PY
