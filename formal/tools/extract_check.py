#!/usr/bin/env python3
"""The extractor in Lanius against the checked-in extraction.

    python3 -I formal/tools/extract_check.py WORKDIR

Run from the repository root. For each program the verified compiler is
written in (compiler.lani, frontend.lani and extract.lani itself), laniusc's
parse tree of it is written (stdlib_oracle.parse_checked, cached), and
`lake exe extract --check` (formal/Lanius/Tools/Extract.lean) extracts it
from that tree and fails unless every module it would write, every part it
would remove and every import block it would rewrite is as checked in. The
checked-in files are extract.py's, so the two extractors agree byte for
byte.
"""

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stdlib_oracle  # noqa: E402

PROGRAMS = [('compiler', 'Lanius.Mini.Compiler'), ('frontend', 'Lanius.Mini.Frontend'),
            ('extract', 'Lanius.Mini.Extract')]
EXTRACT = 'formal/.lake/build/bin/extract'


def main(argv):
    if len(argv) != 1:
        print(__doc__.split('\n\n')[1], file=sys.stderr)
        return 2
    work = os.path.abspath(argv[0])
    os.makedirs(work, exist_ok=True)
    failed = 0
    for name, module in PROGRAMS:
        source = f'formal/lani/mini/{name}.lani'
        base = os.path.join(work, name)
        shutil.copyfile(source, base + '.lani')
        if not stdlib_oracle.parse_checked('target/release/laniusc', base, work):
            print(f'{name}: laniusc gives no tree')
            failed += 1
            continue
        run = subprocess.run([EXTRACT, '--check', source, base, source, module, 'formal', 'formal'],
                             capture_output=True, text=True)
        print(f'{name}: {"ok" if run.returncode == 0 else "FAIL " + run.stderr.strip()}')
        failed += run.returncode != 0
    print(f'{len(PROGRAMS) - failed}/{len(PROGRAMS)} extractions agree')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
