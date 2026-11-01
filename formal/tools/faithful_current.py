#!/usr/bin/env python3
"""Check that the self program in formal/Lanius/Faithful/Gen/ is the front
end's reading of the current self source text (roadmap F12).

    python3 -I formal/tools/faithful_current.py WORKDIR

`selfHost_fixpoint` (Lanius/Faithful/SelfHost.lean) assumes that the front
end reads the self program's files as `Lanius.Faithful.Self.prog` (`read`,
TRUSTED_BASE.md section 5). This regenerates `Gen/` as the certificate
pipeline does, under WORKDIR: the files (the driver and the module closure of
`mini::selfhost`, each with laniusc's tree, as self_host.py lays them out),
`lake exe srcDump` through faithful_dump.py, then faithful_certs.py and
faithful_pure.py, and fails unless every generated file is as checked in.
The one line allowed to differ is the dump's header line naming the files'
paths. Run from the repository root; `srcDump` must be built (gate.build).
"""

import os
import shutil
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import self_host  # noqa: E402
import stdlib_oracle  # noqa: E402

GEN = os.path.join(TOOLS, '..', 'Lanius', 'Faithful', 'Gen')
NS = 'Lanius.Faithful.Self'
ROOTS = ['front_end_words', 'grammar', 'compile_words']


def self_files(workdir, laniusc):
    """Write the self program's files and trees under workdir; return their bases."""
    root = os.path.join(workdir, 'root')
    shutil.rmtree(root, ignore_errors=True)
    shutil.copytree('stdlib', root)
    os.makedirs(os.path.join(root, 'mini'))
    open(os.path.join(root, 'mini', 'selfhost.lani'), 'w').write(self_host.selfhost_text())
    stdlib_oracle.STDLIB = root
    mods = stdlib_oracle.load_modules()
    files_dir = os.path.join(workdir, 'files')
    os.makedirs(files_dir, exist_ok=True)
    driver = os.path.join(files_dir, 'driver')
    open(driver + '.lani', 'w').write(self_host.DRIVER)
    if not stdlib_oracle.parse_checked(laniusc, driver, files_dir):
        raise SystemExit('laniusc does not parse the driver')
    bases = [driver]
    for dep in stdlib_oracle.closure(mods, 'mini::selfhost'):
        b = os.path.join(files_dir, dep.replace('::', '__'))
        shutil.copy(mods[dep].path, b + '.lani')
        if not stdlib_oracle.parse_checked(laniusc, b, files_dir):
            raise SystemExit(f'laniusc does not parse {dep}')
        bases.append(b)
    return bases


def lines(path):
    return [line for line in open(path).read().split('\n') if not line.startswith('self /')]


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    workdir = os.path.abspath(sys.argv[1])
    os.makedirs(workdir, exist_ok=True)
    bases = self_files(workdir, 'target/release/laniusc')
    manifest = os.path.join(workdir, 'self.txt')
    open(manifest, 'w').write('self ' + ' '.join(bases) + '\n')
    dump = os.path.join(workdir, 'Self.lean')
    gen = os.path.join(workdir, 'gen')
    shutil.rmtree(gen, ignore_errors=True)
    shutil.copytree(GEN, gen)
    py = [sys.executable, '-I']
    subprocess.run(py + [os.path.join(TOOLS, 'faithful_dump.py'), manifest, dump, NS], check=True)
    subprocess.run(py + [os.path.join(TOOLS, 'faithful_certs.py'), dump, NS, gen] + ROOTS, check=True)
    subprocess.run(py + [os.path.join(TOOLS, 'faithful_pure.py'), dump, os.path.join(gen, 'SelfProg.lean'), gen],
                   check=True, stdout=subprocess.DEVNULL)
    have, want = sorted(os.listdir(GEN)), sorted(os.listdir(gen))
    differ = sorted(set(have) ^ set(want))
    differ += [n for n in sorted(set(have) & set(want)) if lines(os.path.join(GEN, n)) != lines(os.path.join(gen, n))]
    if differ:
        print(f'Gen/ is not the reading of the current sources: {", ".join(differ[:10])}'
              + (f' and {len(differ) - 10} more' if len(differ) > 10 else '')
              + '; regenerate the certificates (target/claude-work/l2/pipeline.sh)')
        return 1
    print(f'{len(bases)} files, {len(want)} generated files as checked in')
    return 0


if __name__ == '__main__':
    sys.exit(main())
