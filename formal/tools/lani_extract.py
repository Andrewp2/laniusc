#!/usr/bin/env python3
"""Extract the programs the front end reads with the extractor in Lanius.

    python3 -I formal/tools/lani_extract.py [--check] [--work DIR] [NAME..]

Run from the repository root. For each program (all of PROGRAMS, or those
NAMEd), laniusc's parse tree of it is written under DIR
(stdlib_oracle.parse_checked, cached by the source's bytes), and `lake exe
extract` (formal/Lanius/Tools/Extract.lean, running formal/lani/mini/extract.lani)
extracts it from that tree, as checked by the front end's validator (and
checks its external sections against their files' trees): the
modules, the parts it no longer writes removed, and the import blocks of the
Lean files that name it. With --check nothing is written, and it fails
unless every such file is as checked in.

When extract.lani itself changes, its new extraction is built and run on it
again, until the extraction it writes is the one it runs as (a fixpoint;
two rounds when the change is not to the output).

Programs the front end does not read yet (`&mut`, loops: mut_pilot.lani,
openssl_tls_lifecycle.lani) are still extracted by formal/tools/extract.py.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stdlib_oracle  # noqa: E402
import run_cache  # noqa: E402

PROGRAMS = {
    'compiler': ('formal/lani/mini/compiler.lani', 'Lanius.Mini.Compiler'),
    'frontend': ('formal/lani/mini/frontend.lani', 'Lanius.Mini.Frontend'),
    'extract': ('formal/lani/mini/extract.lani', 'Lanius.Mini.Extract'),
    'sqlite': ('extended/ext/sqlite_statement.lani', 'Lanius.Machines.SqliteStatement'),
}
EXTRACT = 'formal/.lake/build/bin/extract'
LANIUSC = 'target/release/laniusc'


def build_extract():
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'],
               LEAN_NUM_THREADS='3')
    with run_cache.lean_lock():
        run = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                              'lake', 'build', 'extract'], cwd='formal', env=env, capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit('lake build extract failed:\n' + run.stdout[-3000:] + run.stderr[-3000:])


def extract(name, work, check):
    """Run the extractor on one program: (returncode, stderr)."""
    source, module = PROGRAMS[name]
    base = os.path.join(work, name)
    shutil.copyfile(source, base + '.lani')
    if not stdlib_oracle.parse_checked(LANIUSC, base, work):
        return 1, 'laniusc gives no tree'
    trees = []
    for path in re.findall(r'^// extract: external begin \S+ from (\S+)$', open(source).read(), re.M):
        ext = os.path.join(work, 'ext_' + re.sub(r'[^A-Za-z0-9]', '_', path))
        shutil.copyfile(path, ext + '.lani')
        if not stdlib_oracle.parse_checked(LANIUSC, ext, work):
            return 1, f'laniusc gives no tree of {path}'
        trees += ['--tree', f'{path}={ext}']
    run = subprocess.run([EXTRACT] + (['--check'] if check else []) + trees + [source, base, source, module, 'formal', 'formal'],
                         capture_output=True, text=True)
    return run.returncode, run.stderr.strip()


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--work', default='target/claude-work/lani_extract')
    parser.add_argument('names', nargs='*')
    args = parser.parse_args(argv)
    names = args.names or list(PROGRAMS)
    work = os.path.abspath(args.work)
    os.makedirs(work, exist_ok=True)
    failed = 0
    for name in names:
        if name not in PROGRAMS:
            raise SystemExit(f'no program {name}: {", ".join(PROGRAMS)}')
        if args.check or name != 'extract':
            code, err = extract(name, work, args.check)
        else:
            # Rebuild and rerun until the extraction stops changing.
            for _ in range(4):
                if extract(name, work, True)[0] == 0:
                    code, err = 0, ''
                    break
                code, err = extract(name, work, False)
                if code != 0:
                    break
                build_extract()
            else:
                code, err = 1, 'no fixpoint after 4 rounds'
        print(f'{name}: {"ok" if code == 0 else "FAIL " + err}')
        failed += code != 0
    print(f'{len(names) - failed}/{len(names)} extractions {"agree" if args.check else "written"}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
