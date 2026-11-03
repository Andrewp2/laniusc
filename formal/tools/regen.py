#!/usr/bin/env python3
"""Regenerate every generated Lean file from the current sources and generators.

    target/claude-work/bin/leanslot timeout 295 python3 -I formal/tools/regen.py [--work DIR]
        [--only STAGE,..] [--force] [--trusted] [--check] [--resolve]

Run from the repository root. The stages, in dependency order:

  extract  lani_extract.py: formal/lani/mini/*.lani (and the other PROGRAMS)
           to Lanius/Mini/{Compiler,Frontend,Extract}/P, the machines and the
           import blocks of the files that name them;
  dump     `lake build srcDump`, the self program's files (faithful_current.py's
           self_files) and faithful_dump.py: the dump WORK/Self.lean (not a
           checked-in file; the next three stages read it);
  gen      faithful_certs.py and faithful_pure.py, in one run each, into an
           empty WORK/gen: Faithful/Gen/ but the termination modules;
  genb     budget_certs.py: Faithful/GenB/;
  term     `lake build Lanius.Faithful.Sim.Term Lanius.Faithful.Gen.SelfProg`
           and term_gen.lean: Faithful/Gen/SelfTerm*.lean;
  hb       hb_gen.py in its four modes: Faithful/SelfPre/{HB,SZ,TS,NB}.lean;
  pre      pre_certs.py: Faithful/SelfPre/GenP (build_files) and GenPC (the
           compile side, `--compile`). Only the modules already checked in are
           written (lang keeps GenPC's SelfP02, whose proofs fail, out); a
           module the generator makes beyond them is reported, not added;
  trusted  (with --trusted only) builds topAxioms and the top theorems' modules
           (one pass of at most the time left) and runs trusted_check.py; when
           the definitions hash is the only problem, the new hash and constant
           count replace the old in TRUSTED_BASE.md's `definitions `HASH` (N
           constants)`, and the last-change sentence is left to write.

Each stage writes into WORK first and copies only the files whose text changed
(their times kept otherwise, so Lake rebuilds only what changed), and removes
the generated files the run no longer makes. A stage is skipped when the
digest of its inputs and its outputs (run_cache's file digests) is one a run of
it left: then it would change nothing. --force runs every stage. The report
lists each stage's time and its changed files. With --check nothing is
written: the run fails when a generated file differs from what it would write
(the gate's `regen-current` step).

Nothing here changes what a generator writes: the files are each generator's
own output, byte for byte. One pass suffices: faithful_pure.py reads the
import closures of the modules it is writing from its own output directory.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import time

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import run_cache  # noqa: E402

ROOT = run_cache.ROOT
FORMAL = run_cache.FORMAL
LANIUS = os.path.join(FORMAL, 'Lanius')
FAITHFUL = os.path.join(LANIUS, 'Faithful')
GEN = os.path.join(FAITHFUL, 'Gen')
GENB = os.path.join(FAITHFUL, 'GenB')
SELFPRE = os.path.join(FAITHFUL, 'SelfPre')
NS = 'Lanius.Faithful.Self'
ROOTS = ['front_end_words', 'grammar', 'compile_words']
TERM_ROOTS = ROOTS + ['lex_source', 'validate_files']
HB_MODES = (('', 'HB.lean'), ('--sum', 'SZ.lean'), ('--slots', 'TS.lean'), ('--nums', 'NB.lean'))
HB_TYPES = ['Lanius/Mini/Compiler/Types.lean', 'Lanius/Mini/Frontend/Types.lean']
# (directory, pre_certs.py options, roots)
PRE = (('GenP', [], ['build_files']),
       ('GenPC', ['--compile', '--ns', 'Lanius.Faithful.SelfPre.Compile', '--base',
                  'Lanius.Faithful.SelfPre.CompileValues'], ['compile_source', 'binary_words']))
# What the extraction's digest leaves out of formal/Lanius: the files the later stages write.
DOWNSTREAM = ('Faithful/Gen/', 'Faithful/GenB/', 'Faithful/SelfPre/GenP/', 'Faithful/SelfPre/GenPC/') + tuple(
    'Faithful/SelfPre/' + name for _, name in HB_MODES)

PY = [sys.executable, '-I']
ENV = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
SCOPE = ['systemd-run', '--user', '--scope', run_cache.SLICE, '-q']


def fail(what, run):
    raise SystemExit(f'{what} failed (exit {run.returncode}):\n' + (run.stdout or '')[-3000:] + (run.stderr or '')[-3000:])


def run(argv, what, cwd=ROOT, quiet=True):
    r = subprocess.run(argv, cwd=cwd, env=ENV, capture_output=True, text=True)
    if r.returncode != 0:
        fail(what, r)
    return r


DEADLINE = [None]  # when the run must stop (--limit)
WORK = [None]


def lake_build(targets):
    """`lake build TARGETS` unless they are current, within the run's time
    limit (a build cut short keeps what it built: rerunning regen.py goes on
    from there); returns the seconds it took. The build's output is in
    WORK/lake-<first target>.log, with each module's time."""
    began = time.time()
    if all(run_cache.lake_current(t, ENV) for t in targets):
        return time.time() - began
    left = int(DEADLINE[0] - time.time()) if DEADLINE[0] else 280
    if left < 20:
        raise SystemExit(f'no time left to build {" ".join(targets)}: rerun regen.py')
    with run_cache.lean_lock():
        r = subprocess.run(['timeout', str(left)] + SCOPE + ['lake', 'build'] + targets, cwd=FORMAL, env=ENV,
                           capture_output=True, text=True)
    log = os.path.join(WORK[0], 'lake-' + targets[0].split('.')[-1] + '.log')
    open(log, 'w').write(r.stdout + r.stderr)
    if r.returncode == 124:
        raise SystemExit(f'lake build {" ".join(targets)} was not done after {left} s (log {log}): '
                         'rerun regen.py, which goes on from what it built')
    if r.returncode != 0:
        fail('lake build ' + ' '.join(targets), r)
    return time.time() - began


# ------------------------------------------------------------------ digests

def files_digest(paths):
    """A digest of these files and directories (absent ones too), by path and bytes."""
    parts = []
    for p in paths:
        rel = os.path.relpath(p, ROOT)
        if os.path.isdir(p):
            parts.append(rel + '/' + run_cache.tree_digest(p))
        elif os.path.exists(p):
            parts.append(rel + ' ' + run_cache.file_digest(p))
        else:
            parts.append(rel + ' absent')
    return run_cache.key(*parts)


def tools(*names):
    return [os.path.join(TOOLS, n) for n in names]


def lanius_digest():
    """formal/Lanius but the files the later stages write (the extraction's inputs and outputs)."""
    parts = []
    for d, dirs, files in sorted(os.walk(LANIUS)):
        dirs[:] = sorted(x for x in dirs if x != '__pycache__')
        for name in sorted(files):
            path = os.path.join(d, name)
            rel = os.path.relpath(path, LANIUS)
            if not rel.startswith(DOWNSTREAM) and rel not in tuple(x.rstrip('/') for x in DOWNSTREAM):
                parts.append(rel + ' ' + run_cache.file_digest(path))
    return run_cache.key(*parts)


def fixpoint(stage, digest):
    """Whether a run of stage left the inputs and outputs with this digest."""
    return run_cache.load('regen', run_cache.key(stage, digest)) is not None


CHECK = [False]  # --check: write nothing, report what differs


def record(stage, digest, changed=()):
    """Note that the inputs and outputs with this digest are a fixpoint of stage
    (with --check, only when the stage found nothing to change)."""
    if not (CHECK[0] and changed):
        run_cache.store('regen', run_cache.key(stage, digest), {})


# ------------------------------------------------------------------ syncing

def same(a, b):
    with open(a, 'rb') as f, open(b, 'rb') as g:
        return f.read() == g.read()


def sync(made, dest, governs=lambda n: True, only_present=False):
    """Copy the files of made whose text differs into dest; remove the files of
    dest that governs selects and made lacks. With only_present, a file dest
    does not have is not added: returned as `skipped`. Returns (changed, skipped)."""
    os.makedirs(dest, exist_ok=True)
    have = {n for n in os.listdir(dest) if governs(n) and os.path.isfile(os.path.join(dest, n))}
    want = {n for n in os.listdir(made) if governs(n)}
    changed, skipped = [], []
    for n in sorted(want):
        src, dst = os.path.join(made, n), os.path.join(dest, n)
        if n not in have and only_present:
            skipped.append(n)
            continue
        if n not in have or not same(src, dst):
            if not CHECK[0]:
                shutil.copyfile(src, dst)
            changed.append(n if n in have else '+' + n)
    for n in sorted(have - want):
        if not CHECK[0]:
            os.remove(os.path.join(dest, n))
        changed.append('-' + n)
    return changed, skipped


def fresh(path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path)
    return path


# ------------------------------------------------------------------ stages

class Regen:
    def __init__(self, work, force):
        self.work = work
        self.force = force
        self.dump = os.path.join(work, 'Self.lean')
        self.report = []  # (stage, seconds, note, changed)

    def done(self, stage, began, note, changed=()):
        self.report.append((stage, time.time() - began, note, list(changed)))
        line = f'{stage:8s} {time.time() - began:6.1f} s  {note}'
        if changed:
            line += f': {len(changed)} changed ' + ' '.join(changed[:12]) + (' ..' if len(changed) > 12 else '')
        print(line, flush=True)

    def skip(self, stage, digest):
        return not self.force and fixpoint(stage, digest)

    def extract(self):
        began = time.time()
        lani = [os.path.join(FORMAL, 'lani'), os.path.join(ROOT, 'extended', 'ext'), os.path.join(ROOT, 'stdlib')]
        inputs = lambda: run_cache.key(files_digest(lani + tools('lani_extract.py', 'cert_trees.py')), lanius_digest())
        if self.skip('extract', inputs()):
            return self.done('extract', began, 'skipped (inputs and outputs as a run left them)')
        if CHECK[0]:
            r = subprocess.run(PY + [os.path.join(TOOLS, 'lani_extract.py'), '--check', '--work',
                                     os.path.join(self.work, 'lx')], cwd=ROOT, env=ENV, capture_output=True, text=True)
            changed = [line for line in r.stdout.split('\n') if 'FAIL' in line] or (['(exit %d)' % r.returncode]
                                                                                   if r.returncode else [])
            record('extract', inputs(), changed)
            return self.done('extract', began, 'lani_extract.py --check', changed)
        before = snapshot([os.path.join(LANIUS, 'Mini'), os.path.join(LANIUS, 'Machines')], LANIUS)
        run(PY + [os.path.join(TOOLS, 'lani_extract.py'), '--work', os.path.join(self.work, 'lx')], 'lani_extract.py')
        changed = changes(before, snapshot([os.path.join(LANIUS, 'Mini'), os.path.join(LANIUS, 'Machines')], LANIUS))
        record('extract', inputs())
        self.done('extract', began, 'lani_extract.py', changed)

    def make_dump(self):
        began = time.time()
        built = lake_build(['srcDump'])
        import faithful_current
        bases = faithful_current.self_files(self.work, 'target/release/laniusc')
        manifest = os.path.join(self.work, 'self.txt')
        open(manifest, 'w').write('self ' + ' '.join(bases) + '\n')
        run(PY + [os.path.join(TOOLS, 'faithful_dump.py'), manifest, self.dump, NS], 'faithful_dump.py')
        self.done('dump', began, f'srcDump build {built:.1f} s, {len(bases)} files')

    def dump_digest(self):
        return files_digest([self.dump, self.dump + '.meta'])

    def gen(self):
        began = time.time()
        governs = lambda n: n.endswith('.lean') and not n.startswith('SelfTerm')
        sim = [os.path.join(FAITHFUL, 'Sim', c + '.lean') for c in ('CheckFast', 'Check', 'ProgOk', 'DeclStep', 'Boxed')]
        digest = run_cache.key(self.dump_digest(), files_digest(
            tools('faithful_certs.py', 'faithful_pure.py') + sim
            + [os.path.join(LANIUS, 'Mini', d, 'P') for d in ('Compiler', 'Frontend')]),
            gen_digest(governs))
        if self.skip('gen', digest):
            return self.done('gen', began, 'skipped')
        out = fresh(os.path.join(self.work, 'gen'))
        run(PY + [os.path.join(TOOLS, 'faithful_certs.py'), self.dump, NS, out] + ROOTS, 'faithful_certs.py')
        t1 = time.time() - began
        run(PY + [os.path.join(TOOLS, 'faithful_pure.py'), self.dump, os.path.join(out, 'SelfProg.lean'), out],
            'faithful_pure.py')
        t2 = time.time() - began - t1
        changed, _ = sync(out, GEN, governs)
        record('gen', run_cache.key(self.dump_digest(), files_digest(
            tools('faithful_certs.py', 'faithful_pure.py') + sim
            + [os.path.join(LANIUS, 'Mini', d, 'P') for d in ('Compiler', 'Frontend')]), gen_digest(governs)), changed)
        self.done('gen', began, f'faithful_certs {t1:.1f} s, faithful_pure {t2:.1f} s', changed)

    def genb(self):
        began = time.time()
        digest = lambda: run_cache.key(self.dump_digest(), files_digest(
            tools('budget_certs.py', 'faithful_certs.py', 'faithful_pure.py') + [GENB]))
        if self.skip('genb', digest()):
            return self.done('genb', began, 'skipped')
        out = fresh(os.path.join(self.work, 'genb'))
        run(PY + [os.path.join(TOOLS, 'budget_certs.py'), self.dump, out] + ROOTS, 'budget_certs.py')
        changed, _ = sync(out, GENB, lambda n: n.endswith('.lean'))
        record('genb', digest(), changed)
        self.done('genb', began, 'budget_certs.py', changed)

    def term(self):
        began = time.time()
        built = lake_build(['Lanius.Faithful.Sim.Term', 'Lanius.Faithful.Gen.SelfProg'])
        governs = lambda n: n.startswith('SelfTerm') and n.endswith('.lean')
        olean = run_cache.olean_digest('import Lanius.Faithful.Sim.Term\nimport Lanius.Faithful.Gen.SelfProg\n')
        digest = lambda: run_cache.key(olean or 'unbuilt', files_digest(tools('term_gen.lean')), gen_digest(governs))
        if olean and self.skip('term', digest()):
            return self.done('term', began, f'skipped (build {built:.1f} s)')
        out = fresh(os.path.join(self.work, 'term'))
        t = time.time()
        with run_cache.lean_lock():
            run(SCOPE + ['lake', 'env', 'lean', '--run', 'tools/term_gen.lean', '--out', out] + TERM_ROOTS,
                'term_gen.lean', cwd=FORMAL)
        changed, _ = sync(out, GEN, governs)
        if olean:
            record('term', digest(), changed)
        self.done('term', began, f'build {built:.1f} s, term_gen {time.time() - t:.1f} s', changed)

    def hb(self):
        began = time.time()
        types = [os.path.join(FORMAL, p) for p in HB_TYPES]
        outs = [os.path.join(SELFPRE, name) for _, name in HB_MODES]
        digest = lambda: files_digest(tools('hb_gen.py') + types + outs)
        if self.skip('hb', digest()):
            return self.done('hb', began, 'skipped')
        out = fresh(os.path.join(self.work, 'hb'))
        for mode, name in HB_MODES:
            run(PY + [os.path.join(TOOLS, 'hb_gen.py')] + ([mode] if mode else []) + [os.path.join(out, name)] + HB_TYPES,
                'hb_gen.py ' + mode, cwd=FORMAL)
        changed, _ = sync(out, SELFPRE, lambda n: n in {name for _, name in HB_MODES})
        record('hb', digest(), changed)
        self.done('hb', began, 'hb_gen.py x4', changed)

    def pre(self):
        began = time.time()
        digest = lambda: files_digest(tools('pre_certs.py', 'hb_gen.py') + [GENB, os.path.join(LANIUS, 'Mini'), SELFPRE])
        if self.skip('pre', digest()):
            return self.done('pre', began, 'skipped')
        changed, notes = [], []
        for d, opts, roots in PRE:
            t = time.time()
            out = fresh(os.path.join(self.work, d))
            run(PY + [os.path.join(TOOLS, 'pre_certs.py')] + opts + ['--prefix', 'Lanius.Faithful.SelfPre.' + d,
                                                                    'Lanius/Faithful/GenB', out] + roots,
                'pre_certs.py ' + d, cwd=FORMAL)
            ch, skipped = sync(out, os.path.join(SELFPRE, d), lambda n: n.endswith('.lean'), only_present=True)
            changed += [f'{d}/{n}' for n in ch]
            notes.append(f'{d} {time.time() - t:.1f} s' + (f' (not added: {", ".join(skipped)})' if skipped else ''))
        record('pre', digest(), changed)
        self.done('pre', began, ', '.join(notes), changed)

    def trusted(self, deadline):
        began = time.time()
        import trusted_check
        left = deadline - time.time()
        if left < 30:
            return self.done('trusted', began, 'no time left: rerun with --only trusted --trusted')
        with run_cache.lean_lock():
            r = subprocess.run(['timeout', str(int(left - 20))] + SCOPE + ['lake', 'build', 'topAxioms']
                               + trusted_check.top_modules(), cwd=FORMAL, env=ENV, capture_output=True, text=True)
        if r.returncode != 0:
            return self.done('trusted', began, f'the top modules are not built yet (exit {r.returncode}): build '
                             'them (lake build, repeated until it succeeds), then rerun with --only trusted --trusted')
        r = subprocess.run(PY + [os.path.join(TOOLS, 'trusted_check.py'), os.path.join(self.work, 'trusted')],
                           cwd=ROOT, env=ENV, capture_output=True, text=True)
        m = re.search(r'trusted definitions: (\d+) constants, hash ([0-9a-f]{16})', r.stdout)
        problems = [line for line in r.stdout.split('\n') if line.startswith('FAIL')]
        if not m:
            fail('trusted_check.py', r)
        count, digest = m.group(1), m.group(2)
        old = trusted_check.listed_definitions()
        other = [p for p in problems if 'trusted definitions hash' not in p]
        if old == digest:
            note = f'definitions {digest} as listed'
        elif other:
            note = f'definitions {digest} (listed {old}) not written: other problems first'
        else:
            text = open(trusted_check.TRUSTED).read()
            text, n = re.subn(r'definitions `[0-9a-f]{16}` \(\d+ constants\)', f'definitions `{digest}` ({count} constants)', text, count=1)
            if n != 1:
                raise SystemExit('TRUSTED_BASE.md has no "definitions `HASH` (N constants)"')
            open(trusted_check.TRUSTED, 'w').write(text)
            note = (f'definitions {old} -> {digest} ({count} constants) written to TRUSTED_BASE.md: say what changed '
                    f'in its last-change sentence')
        self.done('trusted', began, note + ''.join('\n  ' + p for p in other))


def gen_digest(governs):
    return run_cache.key(*[n + ' ' + run_cache.file_digest(os.path.join(GEN, n))
                           for n in sorted(os.listdir(GEN)) if governs(n)])


def snapshot(dirs, base):
    out = {}
    for top in dirs:
        for d, _, files in os.walk(top):
            for name in files:
                if name.endswith('.lean'):
                    p = os.path.join(d, name)
                    out[os.path.relpath(p, base)] = run_cache.file_digest(p)
    return out


def changes(before, after):
    return ([('+' if k not in before else '') + k for k in sorted(after) if before.get(k) != after[k]]
            + ['-' + k for k in sorted(set(before) - set(after))])


STAGES = ('extract', 'dump', 'gen', 'genb', 'term', 'hb', 'pre', 'trusted')


def git(*argv, check=True):
    r = subprocess.run(['git'] + list(argv), cwd=ROOT, capture_output=True, text=True)
    if check and r.returncode != 0:
        fail('git ' + ' '.join(argv), r)
    return r.stdout


def stale_path():
    return os.path.join(ROOT, git('rev-parse', '--git-dir').strip(), 'lanius-regen-stale')


def stale_entries():
    """What the merge drivers listed (merge_driver.py): [(kind, path)]."""
    try:
        with open(stale_path()) as f:
            return sorted({tuple(line.split(' ', 1)) for line in f.read().split('\n') if ' ' in line})
    except FileNotFoundError:
        return []


GENERATED = ':(attr:merge=lanius-generated)formal'


def resolve():
    """Settle the merge's unmerged generated files (a side deleted one, which the
    driver does not see): ours where ours has it, else none. regen.py rewrites
    them all anyway."""
    unmerged = git('diff', '--name-only', '--diff-filter=U', '--', GENERATED).split()
    for path in unmerged:
        if ' 2\t' in git('ls-files', '-u', '--', path):  # ours (stage 2) has it
            git('checkout', '--ours', '--', path)
        elif os.path.exists(os.path.join(ROOT, path)):
            os.remove(os.path.join(ROOT, path))
    if unmerged:
        print(f'resolve: {len(unmerged)} unmerged generated files taken from ours (or removed)')
    return unmerged


PART_IMPORT = re.compile(r'^(?:public |private )?import (?:all )?(Lanius\.(?:Mini\.(?:Compiler|Frontend|Extract)|'
                         r'Machines\.SqliteStatement)\.P\.\w+)\s*\n', re.M)


def drop_missing_parts(paths):
    """Remove from these files each import of an extracted part that does not exist."""
    fixed = []
    for rel in paths:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        text = open(path).read()
        new = PART_IMPORT.sub(lambda m: m.group(0) if os.path.exists(
            os.path.join(FORMAL, m.group(1).replace('.', '/') + '.lean')) else '', text)
        if new != text:
            open(path, 'w').write(new)
            fixed.append(rel)
    return fixed


def main(argv):
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('--work', default=os.path.join(ROOT, 'target', 'claude-work', 'regen-work'))
    p.add_argument('--only', help='stages, comma-separated: ' + ','.join(STAGES))
    p.add_argument('--force', action='store_true', help='run every stage even when its digest is a recorded run')
    p.add_argument('--trusted', action='store_true', help='also build the top modules and update the trusted hash')
    p.add_argument('--check', action='store_true',
                   help='write nothing; fail when a generated file differs from what regen.py would write')
    p.add_argument('--resolve', action='store_true',
                   help='after a merge: settle unmerged generated files first and `git add` the generated files after')
    p.add_argument('--limit', type=float, default=285, help='seconds for the whole run (the trusted build gets what is left)')
    args = p.parse_args(argv)
    began = time.time()
    if os.path.abspath(os.getcwd()) != ROOT:
        raise SystemExit(f'run from the repository root {ROOT}')
    stages = args.only.split(',') if args.only else [s for s in STAGES if s != 'trusted' or args.trusted]
    for s in stages:
        if s not in STAGES:
            raise SystemExit(f'no stage {s}: {", ".join(STAGES)}')
    os.makedirs(args.work, exist_ok=True)
    DEADLINE[0], WORK[0] = began + args.limit, os.path.abspath(args.work)
    CHECK[0] = args.check
    if args.check and (args.resolve or args.trusted):
        raise SystemExit('--check writes nothing: not with --resolve or --trusted')
    entries = stale_entries()
    if entries:
        kinds = {k: sum(1 for x, _ in entries if x == k) for k, _ in entries}
        print('merge: ' + ', '.join(f'{n} {k}' for k, n in sorted(kinds.items())) + ' files listed by the merge drivers')
    if args.resolve:
        resolve()
    g = Regen(os.path.abspath(args.work), args.force)
    if 'extract' in stages:
        g.extract()
    fixed = [] if args.check else drop_missing_parts([path for kind, path in entries if kind == 'imports'])
    if fixed:
        print(f'imports  removed imports of parts that no longer exist from {", ".join(fixed)}')
    if {'dump', 'gen', 'genb'} & set(stages):
        g.make_dump()
    for s in ('gen', 'genb', 'term', 'hb', 'pre'):
        if s in stages:
            getattr(g, s)()
    if 'trusted' in stages:
        g.trusted(began + args.limit)
    if args.resolve:
        git('add', '-A', '--', GENERATED)
        print('resolve: generated files staged (git add)')
    if entries and not args.check and set(STAGES) - {'trusted'} <= set(stages):
        os.remove(stale_path())
    total = sum(len(c) for _, _, _, c in g.report)
    if args.check:
        stale = [f'{s}: {" ".join(c[:5])}' for s, _, _, c in g.report if c]
        print(f'regen --check: {"stale: " + "; ".join(stale) + " (run regen.py)" if stale else "every generated file is what regen.py writes"}'
              f' ({time.time() - began:.1f} s)')
        return 1 if stale else 0
    print(f'regen: {total} files changed in {time.time() - began:.1f} s')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
