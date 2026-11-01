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
paths. Then, with that program current, it builds `Lanius.Faithful.Gen.SelfProg`
and has term_gen.lean write the termination modules (`Gen/SelfTerm*.lean`)
for TERM_ROOTS, which must be as checked in too: a regeneration of the
certificates must regenerate them. Run from the repository root; `srcDump`
must be built (gate.build).
"""

import os
import shutil
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import self_host  # noqa: E402
import stdlib_oracle  # noqa: E402
import cert_trees  # noqa: E402

GEN = os.path.join(TOOLS, '..', 'Lanius', 'Faithful', 'Gen')
NS = 'Lanius.Faithful.Self'
ROOTS = ['front_end_words', 'grammar', 'compile_words']
# The functions whose pure calls `Gen/SelfTerm.lean` proves settle.
TERM_ROOTS = ROOTS + ['lex_source', 'validate_files']
FORMAL = os.path.join(TOOLS, '..')


def term_modules(out):
    """Write the termination modules term_gen.lean makes of the built program to out."""
    import run_cache
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    scope = ['systemd-run', '--user', '--scope', '--slice=lean.slice', '-q', '-p', 'MemoryMax=4G', '-p',
             'MemorySwapMax=0']
    with run_cache.lean_lock():
        for argv in (['lake', 'build', 'Lanius.Faithful.Sim.Term', 'Lanius.Faithful.Gen.SelfProg'],
                     ['lake', 'env', 'lean', '--run', 'tools/term_gen.lean', '--out', out] + TERM_ROOTS):
            run = subprocess.run(scope + argv, cwd=FORMAL, env=env, capture_output=True, text=True)
            if run.returncode != 0:
                raise SystemExit(f'{" ".join(argv[:3])} failed:\n' + run.stdout[-3000:] + run.stderr[-3000:])


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
    bases = [driver]
    for dep in stdlib_oracle.closure(mods, 'mini::selfhost'):
        b = os.path.join(files_dir, dep.replace('::', '__'))
        shutil.copy(mods[dep].path, b + '.lani')
        bases.append(b)
    # Validated trees (cert_trees), laniusc's only where needed.
    ok = cert_trees.write(bases, files_dir, laniusc)
    for b in bases:
        if b not in ok:
            raise SystemExit(f'no tree the validator accepts for {os.path.basename(b)}')
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
    term = os.path.join(workdir, 'term')
    shutil.rmtree(term, ignore_errors=True)
    os.makedirs(term)
    term_modules(term)
    made = sorted(os.listdir(term))
    have = sorted(n for n in os.listdir(GEN) if n.startswith('SelfTerm'))
    differ = sorted(set(have) ^ set(made))
    differ += [n for n in sorted(set(have) & set(made))
               if open(os.path.join(GEN, n)).read() != open(os.path.join(term, n)).read()]
    if differ:
        print(f'Gen/SelfTerm*.lean is not what term_gen.lean makes of the program: {", ".join(differ[:10])}'
              + '; rerun it (cd formal && lake env lean --run tools/term_gen.lean '
              + ' '.join(TERM_ROOTS) + ')')
        return 1
    print(f'{len(bases)} files, {len(want)} generated files as checked in, {len(made)} of them termination modules')
    return 0


if __name__ == '__main__':
    sys.exit(main())
