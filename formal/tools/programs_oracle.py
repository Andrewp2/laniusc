#!/usr/bin/env python3
"""The verified compiler on laniusc's own test programs (roadmap F11).

    python3 -I formal/tools/programs_oracle.py WORKDIR [--sample N] [--seed S] [--laniusc PATH] [--match RE]

Run from the repository root. The programs are the single-file `.lani`
programs with a `fn main` under tests/fixtures/ and sample_programs/; --sample
takes N of them at random (seeded), --match only those whose text the
regular expression matches, as one run over all of them takes far
longer than the gate's limit. Each program is read by the verified front end
with the stdlib modules it reaches (laniusc's parse trees, checked by the
verified validator, as in stdlib_oracle.py), compiled by the verified compiler
and wrapped as a Linux executable (runAll's `elf` line). laniusc builds the same
program. Both run with no input; they must end alike: the same exit status (or
signal), or both at a checked trap (VERIFIED_TRAPS, LANIUSC_TRAPS), and the same bytes on stdout and stderr.

For each program the front end does not read, srcDump says why (the step, or
the function it cannot read) and the constructs of stdlib_oracle.py's list in
it are counted. A program the verified compiler compiles and laniusc rejects
is listed (many fixtures are rejection tests). Prints a summary; exits nonzero
when a program both compile ends differently.
"""

import argparse
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import stdlib_oracle as so  # noqa: E402

ROOTS = ['tests/fixtures', 'sample_programs']
EXTENDED = 'extended'
MIB = 1 << 20


def programs():
    out = []
    for root in ROOTS:
        for d, _, names in os.walk(root):
            for name in sorted(names):
                path = os.path.join(d, name)
                if name.endswith('.lani') and re.search(r'^\s*(pub\s+)?fn\s+main\s*\(', open(path).read(), re.M):
                    out.append(path)
    return sorted(out)


def local_modules(path, m, mods):
    """The modules of a program's own directory that it reaches by import and
    that are neither stdlib nor extended/ modules: its directory is a source
    root (laniusc's --source-root), so `import a::b;` is a/b.lani there."""
    root, out, todo = os.path.dirname(path), {}, list(m.imports)
    while todo:
        name = todo.pop(0)
        file = os.path.join(root, *name.split('::')) + '.lani'
        if name in mods or name in out or not os.path.isfile(file):
            continue
        out[name] = so.Module(file)
        todo += out[name].imports
    return out


def entry_index(text):
    """main's instance: the front end's roots are the functions with no type
    parameters (an impl's included) in declaration order, the first file's
    first (`root_insts`). None when main is not found."""
    clean = so.strip_comments(text)
    k, i, n = 0, 0, len(clean)
    while i < n:
        m = re.compile(r'\b(impl\b|trait\b|fn\s+(\w+)\s*(<)?|extern\b)').search(clean, i)
        if not m:
            return None
        if m.group(0) == 'trait':
            i = so.matching(clean, clean.find('{', m.end()), '{', '}')
            continue
        if m.group(0).startswith('extern'):
            # Only lanius_std host externs are functions of the program.
            semi = clean.find(';', m.end())
            if re.match(r'extern\s+"lanius_std"', clean[m.start():]):
                if not re.match(r'extern\s+"lanius_std"\s+fn\s+\w+\s*<', clean[m.start():]):
                    k += 1
            i = semi + 1
            continue
        if m.group(0).startswith('impl'):
            generic = clean[m.end():].lstrip().startswith('<')
            brace = clean.find('{', m.end())
            end = so.matching(clean, brace, '{', '}')
            for f in re.finditer(r'\bfn\s+(\w+)\s*(<)?', clean[brace:end]):
                if not generic and not f.group(2):
                    k += 1
            i = end
            continue
        if m.group(2) == 'main':
            return k
        if not m.group(3):
            k += 1
        brace = clean.find('{', m.end())
        semi = clean.find(';', m.end())
        i = so.matching(clean, brace, '{', '}') if brace >= 0 and (semi < 0 or brace < semi) else semi + 1
    return None


# A checked trap: the verified compiler's code faults (`#DE` or `ud2`, SEMANTIC_DECISIONS.md, "Traps in compiled
# code"); laniusc's exits 101 (bounds), 102 (shift), 103 (division by zero) or 104 (signed overflow), or faults
# (`assert`). Two programs that trap alike after the same output agree.
VERIFIED_TRAPS = (-signal.SIGFPE, -signal.SIGILL)
LANIUSC_TRAPS = (101, 102, 103, 104, -signal.SIGFPE, -signal.SIGILL)


# Programs that end differently by a recorded decision, not by a fault of
# either compiler: listed, and counted neither as agreeing nor as disagreeing.
KNOWN = {
    'tests/fixtures/stdlib_foundation/raw_host_width_admission.lani':
        "allocates 4 GiB: running out of the verified compiler's heap (64 MiB here) faults, as Core's heap budget "
        'traps (SEMANTIC_DECISIONS.md, "Traps in compiled code"); laniusc\'s mmap succeeds',
}


def run(cmd):
    """How a program ends: (status or -signal, stdout, stderr), or 'timeout'."""
    try:
        r = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
    except subprocess.TimeoutExpired:
        return ('timeout', b'', b'')
    return (r.returncode, r.stdout, r.stderr)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--sample', type=int, default=60)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--laniusc', default='target/release/laniusc')
    parser.add_argument('--match', help='only the programs whose text this regular expression matches')
    args = parser.parse_args()
    workdir = os.path.abspath(args.workdir)
    files_dir = os.path.join(workdir, 'files')
    os.makedirs(files_dir, exist_ok=True)

    began = time.time()
    every = programs()
    if args.match:
        every = [p for p in every if re.search(args.match, open(p).read())]
    picked = sorted(random.Random(args.seed).sample(every, min(args.sample, len(every))))
    mods = so.load_modules()
    ext = so.load_modules(EXTENDED)
    mods.update({n: m for n, m in ext.items() if n not in mods})
    so.build_run_all()

    # The programs and the modules they reach, parsed and checked.
    progs = []
    for k, path in enumerate(picked):
        m = so.Module(path)
        name = m.name or 'app::main'
        base = os.path.join(workdir, f'p{k}')
        shutil.copy(path, base + '.lani')
        local = local_modules(path, m, mods)
        reach = dict(mods, **local)
        reach[name] = m
        deps = [reach[d].path for d in so.closure(reach, name) if d != name]
        main_fn = m.fns.get('main')
        causes = sorted(set(so.causes(reach, so.Target(path, name, main_fn)))) if main_fn else []
        roots = ([EXTENDED] if any(d.startswith(EXTENDED + '/') for d in deps) else []) + \
            ([os.path.dirname(path)] if local else [])
        progs.append(dict(k=k, path=path, base=base, deps=deps, causes=causes, roots=roots))
    deps = sorted({d for p in progs for d in p['deps']})
    dep_base = {d: os.path.join(files_dir, re.sub(r'[^\w]', '_', d[:-5])) for d in deps}
    for d in deps:
        shutil.copy(d, dep_base[d] + '.lani')
    # One validator run for every tree; a rejected one is parsed again from
    # laniusc's captures (as stdlib_oracle.py does).
    trees = {b: so.parse_stdlib_file(args.laniusc, b + '.lani', files_dir)
             for b in [p['base'] for p in progs] + [dep_base[d] for d in deps]}
    for b, tree in trees.items():
        if tree is not None:
            so.write_tree(b, tree)
    good = so.validate_all([b for b, tree in trees.items() if tree is not None], workdir)
    for b in [b for b in trees if b not in good]:
        tree = so.parse_tree(args.laniusc, b + '.lani', files_dir)
        if tree is not None:
            so.write_tree(b, tree)
            good |= so.validate_all([b], workdir)

    parse_s = time.time() - began
    lines = []
    for p in progs:
        p['files'] = [p['base']] + [dep_base[d] for d in p['deps']]
        if not all(b in good for b in p['files']):
            p['status'] = 'noparse'
            continue
        entry = entry_index(open(p['path']).read())
        if entry is None:
            p['status'] = 'nomain'
            continue
        lines.append(f'elf p{p["k"]} {p["base"]}.elf {entry} {16 * MIB} {64 * MIB} ' + ' '.join(p['files']))
    manifest = os.path.join(workdir, 'manifest.txt')
    open(manifest, 'w').write('\n'.join(lines) + '\n')
    subprocess.run([so.RUN_ALL, manifest], capture_output=True, text=True, timeout=240)

    compile_s = time.time() - began - parse_s
    problems, accepted, reasons, constructs = [], [], {}, {}
    compiled = agreed = 0
    for p in progs:
        if p.get('status') in ('noparse', 'nomain'):
            continue
        elf = p['base'] + '.elf'
        if not os.path.exists(elf):
            p['status'] = 'unread'
            r = so.why(p['files'], workdir, p['k'])
            reasons[so.gap(r)] = reasons.get(so.gap(r), 0) + 1
            p['why'] = r
            for c in sorted({c.split(' (in ')[0] for c in p['causes']}) or ['no known cause']:
                constructs[c] = constructs.get(c, 0) + 1
            continue
        compiled += 1
        os.chmod(elf, 0o755)
        exe, error = so.build(args, workdir, f'l{p["k"]}', open(p['path']).read(), p['roots'])
        if exe is None:
            accepted.append(f'{p["path"]}: laniusc ' + ('fails (LNC0057)' if 'LNC0057' in error else 'rejects it'))
            continue
        want, have = run([elf]), run([exe])
        if want != have and p['path'] in KNOWN:
            accepted.append(f'{p["path"]}: ends differently, as known: {KNOWN[p["path"]]}')
            continue
        if want == have or (want[0] in VERIFIED_TRAPS and have[0] in LANIUSC_TRAPS and want[1:] == have[1:]):
            agreed += 1
        else:
            problems.append(f'{p["path"]}: verified compiler {want[0]} {want[1][:60]!r} {want[2][:60]!r}, '
                            f'laniusc {have[0]} {have[1][:60]!r} {have[2][:60]!r}')

    report = [f'{len(picked)} of {len(every)} programs (seed {args.seed}); time: parse {parse_s:.0f} s, '
              f'compile {compile_s:.0f} s, run and diagnose {time.time() - began - parse_s - compile_s:.0f} s',
              f'no checked parse: {sum(1 for p in progs if p.get("status") == "noparse")}',
              f'compiled by the verified compiler: {compiled}; both ran alike: {agreed}',
              'unread, by construct (a program can count under several): ' +
              ', '.join(f'{c} {n}' for c, n in sorted(constructs.items(), key=lambda x: -x[1])),
              'unread, by the gap srcDump names (GAPS):'] + \
        [f'  {n} {r}' for r, n in sorted(reasons.items(), key=lambda x: (-x[1], x[0]))]
    report += [f'compiled, but {a}' for a in accepted]
    report += [f'{len(problems)} disagreements'] + problems
    open(os.path.join(workdir, 'unread.txt'), 'w').write(
        ''.join(f'{p["path"]}: {p["why"]}; {", ".join(p["causes"])}\n' for p in progs if 'why' in p))
    print('\n'.join(report))
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
