#!/usr/bin/python3 -I
"""errs.py LOG FILE [LO HI] [N]: each error in FILE between lines LO..HI: first N lines of its message."""
import re, sys
log, fname = sys.argv[1], sys.argv[2]
lo = int(sys.argv[3]) if len(sys.argv) > 3 else 0
hi = int(sys.argv[4]) if len(sys.argv) > 4 else 10**9
n = int(sys.argv[5]) if len(sys.argv) > 5 else 12
text = open(log).read()
parts = re.split(r'(?m)^(?=\S*' + re.escape(fname) + r':\d+:\d+: )', text)
for p in parts:
    m = re.match(r'\S*' + re.escape(fname) + r':(\d+):(\d+): (.*)', p)
    if not m: continue
    ln = int(m.group(1))
    if lo <= ln <= hi:
        body = p.split('\n')
        print(f'--- {ln}:{m.group(2)} ' + body[0].split(': ', 1)[1][:200])
        for l in body[1:n]:
            print('   ' + l[:220])
