"""Regenerate formal/Lanius/Faithful/Gen in place (faithful_current.py's steps). Run from the worktree root.
argv: WORKDIR [term]"""
import os, shutil, subprocess, sys
sys.path.insert(0, os.path.abspath('formal/tools'))
import faithful_current as fc
w = os.path.abspath(sys.argv[1]); os.makedirs(w, exist_ok=True)
GEN = os.path.abspath(fc.GEN)
if sys.argv[2:] != ['term']:
    bases = fc.self_files(w, 'target/release/laniusc')
    manifest = os.path.join(w, 'self.txt')
    open(manifest, 'w').write('self ' + ' '.join(bases) + '\n')
    dump = os.path.join(w, 'Self.lean')
    gen = os.path.join(w, 'gen'); shutil.rmtree(gen, ignore_errors=True); shutil.copytree(GEN, gen)
    py = [sys.executable, '-I']
    subprocess.run(py + [os.path.join(fc.TOOLS, 'faithful_dump.py'), manifest, dump, fc.NS], check=True)
    subprocess.run(py + [os.path.join(fc.TOOLS, 'faithful_certs.py'), dump, fc.NS, gen] + fc.ROOTS, check=True)
    subprocess.run(py + [os.path.join(fc.TOOLS, 'faithful_pure.py'), dump, os.path.join(gen, 'SelfProg.lean'), gen],
                   check=True, stdout=subprocess.DEVNULL)
    have, want = set(os.listdir(GEN)), set(os.listdir(gen))
    changed = []
    for n in sorted(have - want):
        if not n.startswith('SelfTerm'):
            os.remove(os.path.join(GEN, n)); changed.append('-' + n)
    for n in sorted(want):
        src = os.path.join(gen, n); dst = os.path.join(GEN, n)
        if not os.path.exists(dst) or open(src).read() != open(dst).read():
            shutil.copy(src, dst); changed.append(n)
    print('gen changed:', len(changed), ' '.join(changed[:40]))
else:
    term = os.path.join(w, 'term'); shutil.rmtree(term, ignore_errors=True); os.makedirs(term)
    fc.term_modules(term)
    ch = []
    for n in sorted(os.listdir(term)):
        src = os.path.join(term, n); dst = os.path.join(GEN, n)
        if not os.path.exists(dst) or open(src).read() != open(dst).read():
            shutil.copy(src, dst); ch.append(n)
    print('term changed:', ch)
