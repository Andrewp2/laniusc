#!/usr/bin/env python3
"""The front end's program of some files as a Lean file, for the extraction
certificates (formal/Lanius/Faithful/).

    python3 -I formal/tools/faithful_dump.py MANIFEST OUT NAMESPACE

MANIFEST's first line is `NAME BASE...` as runAll reads it (each BASE has
.lani, .prods and .parents files). `lake exe srcDump` writes each type once
as `def tyK` and prints each function with placeholders for the named types,
`SrcType.struct (1000000000 + K) []`, which this replaces by `tyK`.
"""

import os
import re
import subprocess
import sys

FORMAL = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLACEHOLDER = re.compile(r'\(Lanius\.Mini\.SrcType\.struct 1(\d{9}) \[\]\)|Lanius\.Mini\.SrcType\.struct 1(\d{9}) \[\]')


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    manifest, out, ns = sys.argv[1:]
    exe = os.path.join(FORMAL, '.lake/build/bin/srcDump')
    run = subprocess.run([exe, manifest, out, ns], capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit(run.stderr)
    text = open(out).read()
    text = PLACEHOLDER.sub(lambda m: f'ty{int(m.group(1) or m.group(2))}', text)
    text = re.sub(r'Lanius\.Mini\.(?=[A-Z][A-Za-z]*\.)', '', text)
    open(out, 'w').write(text)


if __name__ == '__main__':
    main()
