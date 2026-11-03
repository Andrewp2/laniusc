#!/usr/bin/env python3
"""The graph of open statements under formal/Lanius/Open (OPEN_STATEMENTS.md).

    python3 -I formal/tools/open_graph.py status [--all]
    python3 -I formal/tools/open_graph.py check [WORKDIR]
    python3 -I formal/tools/open_graph.py claim NAME --agent WHO
    python3 -I formal/tools/open_graph.py release NAME

status lists what is proved, ready to assemble (with the line to write),
blocked and open. check is the gate's `open` step: docstrings, statements
unchanged since first committed, reductions and proofs of the right shape, no
forbidden constructs. Lean itself checks the declarations (the gate builds
LaniusOpen); this script checks what Lean would accept but the convention
does not.
"""

import argparse
import os
import re
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OPEN = os.environ.get('LANIUS_OPEN_DIR') or os.path.join(ROOT, 'formal', 'Lanius', 'Open')
def _main_checkout():
    """The main checkout (where the shared .git lives), so every worktree sees the same claims."""
    common = subprocess.run(['git', 'rev-parse', '--path-format=absolute', '--git-common-dir'], cwd=ROOT,
                            capture_output=True, text=True).stdout.strip()
    return os.path.dirname(common) if common else ROOT


CLAIMS = os.path.join(_main_checkout(), 'target', 'claude-work', 'open', 'claims')
CLAIM_HOURS = 6
PREFIX = 'Lanius.Open.'

NAME = r"Lanius\.Open\.[A-Za-z_][\w'.]*"
STMT_RE = re.compile(r'(/--(?:(?!-/).)*-/)?\s*def\s+(' + NAME + r')\s*:\s*Prop\s*:=', re.S)
RED_RE = re.compile(r'theorem\s+(' + NAME + r')\.(red\w*)\b(.*?):=', re.S)
PROOF_RE = re.compile(r'theorem\s+(' + NAME + r')\.proof\s*:\s*(' + NAME + r')\s*:=', re.S)
BINDER_RE = re.compile(r'[(\[{]\s*([^:()\[\]{}]*?)\s*:\s*([^()\[\]{}]*?)\s*[)\]}]')
FORBIDDEN = re.compile(r'\b(sorry|admit|native_decide|bv_decide|implemented_by)\b|^\s*axiom\b|@\[\s*extern\b', re.M)


def strip_comments(text):
    """Lean text without -- line comments and /- -/ block comments (docstrings kept apart)."""
    out, i, depth = [], 0, 0
    while i < len(text):
        if text.startswith('/-', i):
            depth += 1
            i += 2
        elif depth and text.startswith('-/', i):
            depth -= 1
            i += 2
        elif depth:
            i += 1
        elif text.startswith('--', i):
            j = text.find('\n', i)
            i = len(text) if j < 0 else j
        else:
            out.append(text[i])
            i += 1
    return ''.join(out)


def short(name):
    return name[len(PREFIX):] if name.startswith(PREFIX) else name


def scan():
    """{name: {dir, stmt, doc, reds: {red: [hyps]}, proof, problems}} for every statement directory."""
    graph, problems = {}, []
    if not os.path.isdir(OPEN):
        return graph, problems
    for d, _, files in sorted(os.walk(OPEN)):
        if 'Stmt.lean' not in files:
            for f in files:
                if f.endswith('.lean'):
                    problems.append(f'{os.path.relpath(os.path.join(d, f), ROOT)}: a Lean file outside a statement '
                                    'directory (each directory holding Stmt.lean is one statement)')
            continue
        rel = os.path.relpath(d, ROOT)
        text = open(os.path.join(d, 'Stmt.lean')).read()
        found = STMT_RE.findall(text)
        if len(found) != 1:
            problems.append(f'{rel}/Stmt.lean: needs exactly one `def Lanius.Open.<Name> : Prop :=` (found {len(found)})')
            continue
        doc, name = found[0]
        if not doc or len(doc.strip('/-! \n')) < 20:
            problems.append(f'{rel}/Stmt.lean: {short(name)} needs a docstring saying what it claims and why')
        node = graph.setdefault(name, {'dir': d, 'doc': doc, 'reds': {}, 'proof': None, 'files': []})
        node['files'].append(os.path.join(d, 'Stmt.lean'))
        for f in sorted(files):
            path = os.path.join(d, f)
            if f == 'Stmt.lean' or not f.endswith('.lean'):
                continue
            node['files'].append(path)
            body = strip_comments(open(path).read())
            if re.fullmatch(r'Red\w*\.lean', f):
                reds = RED_RE.findall(body)
                if not reds:
                    problems.append(f'{rel}/{f}: no `theorem {short(name)}.red<k> ... : {short(name)} :=`')
                for owner, red, sig in reds:
                    if owner != name:
                        problems.append(f'{rel}/{f}: {red} belongs to {short(owner)}, not {short(name)}')
                        continue
                    binders, _, concl = sig.rpartition(':')
                    concl = concl.strip()
                    if concl != name:
                        problems.append(f'{rel}/{f}: {short(name)}.{red} must conclude `{name}` (concludes `{concl}`)')
                    hyps = []
                    for names_, ty in BINDER_RE.findall(binders):
                        ty = ty.strip()
                        if not re.fullmatch(NAME, ty):
                            problems.append(f'{rel}/{f}: {short(name)}.{red}: hypothesis `{ty}` is not an open '
                                            'statement (reductions take only `(h : Lanius.Open.X)` hypotheses)')
                        hyps += [ty] * max(1, len(names_.split()))
                    node['reds'][red] = hyps
            elif f == 'Proof.lean':
                proofs = PROOF_RE.findall(body)
                if len(proofs) != 1 or proofs[0][0] != name or proofs[0][1] != name:
                    problems.append(f'{rel}/Proof.lean: needs `theorem {name}.proof : {name} :=`')
                else:
                    node['proof'] = path
            else:
                problems.append(f'{rel}/{f}: only Stmt.lean, Red<k>.lean and Proof.lean belong in a statement '
                                'directory (helper lemmas go in the Red or Proof file that uses them)')
    for name, node in graph.items():
        for red, hyps in node['reds'].items():
            for h in hyps:
                if h not in graph:
                    problems.append(f'{short(name)}.{red}: hypothesis {short(h)} has no Stmt.lean')
    return graph, problems


def proved(graph):
    """Statements with a proof, plus those whose some reduction has every hypothesis proved (ready)."""
    done = {n for n, v in graph.items() if v['proof']}
    ready = {}
    for n, v in graph.items():
        if n in done:
            continue
        for red, hyps in sorted(v['reds'].items()):
            if all(h in done for h in hyps):
                ready[n] = (red, hyps)
                break
    return done, ready


def first_line(doc):
    text = ' '.join(doc.strip('/-! \n').split())
    return text[:110] + ('...' if len(text) > 110 else '')


def claims():
    out = {}
    if os.path.isdir(CLAIMS):
        for f in os.listdir(CLAIMS):
            path = os.path.join(CLAIMS, f)
            age = (time.time() - os.path.getmtime(path)) / 3600
            if age < CLAIM_HOURS:
                out[PREFIX + f] = (open(path).read().strip(), age)
    return out


def status(show_all):
    graph, problems = scan()
    done, ready = proved(graph)
    held = claims()
    used = {h for v in graph.values() for hyps in v['reds'].values() for h in hyps}
    leaves = sorted(n for n, v in graph.items() if n not in done and n not in ready and not v['reds'])
    blocked = sorted(n for n, v in graph.items() if n not in done and n not in ready and v['reds'])
    roots = sorted(n for n in graph if n not in used)
    print(f'{len(graph)} statements: {len(done)} proved, {len(ready)} ready to assemble, '
          f'{len(blocked)} blocked, {len(leaves)} open leaves; roots: {", ".join(short(r) for r in roots) or "none"}')
    def line(n):
        c = held.get(n)
        tag = f'  [claimed by {c[0]}, {c[1]:.1f} h ago]' if c else ''
        return f'  {short(n)}{tag}\n      {first_line(graph[n]["doc"])}'
    if ready:
        print('\nReady to assemble (write Proof.lean):')
        for n in sorted(ready):
            red, hyps = ready[n]
            print(line(n))
            print(f'      theorem {n}.proof : {n} := {n}.{red} ' + ' '.join(f'{h}.proof' for h in hyps))
    if leaves:
        print('\nOpen leaves:')
        for n in leaves:
            print(line(n))
    if blocked:
        print('\nBlocked (a reduction waits on open statements):')
        for n in blocked:
            waits = sorted({short(h) for hyps in graph[n]['reds'].values() for h in hyps if h not in done})
            print(line(n) + f'\n      waits on: {", ".join(waits)}')
    if show_all and done:
        print('\nProved:')
        for n in sorted(done):
            print(f'  {short(n)}')
    if problems:
        print(f'\n{len(problems)} problems (open_graph.py check):')
        for p in problems:
            print(f'  {p}')


def git(*args):
    return subprocess.run(['git', *args], cwd=ROOT, capture_output=True, text=True)


def unchanged_problems(graph):
    """Each Stmt.lean against the version the commit that added it had (whitespace ignored)."""
    out = []
    for name, node in graph.items():
        path = os.path.relpath(os.path.join(node['dir'], 'Stmt.lean'), ROOT)
        added = git('log', '--format=%H', '--diff-filter=A', '--', path).stdout.split()
        if not added:
            continue  # not committed yet: free to edit
        first = git('show', f'{added[-1]}:{path}')
        if first.returncode != 0:
            out.append(f'{path}: cannot read its first committed version ({first.stderr.strip()})')
            continue
        norm = lambda s: ' '.join(s.split())
        if norm(first.stdout) != norm(open(os.path.join(ROOT, path)).read()):
            out.append(f'{path}: {short(name)} changed since {added[-1][:9]} first committed it; a statement '
                       'never changes (write a new one under a new name)')
    return out


def check(workdir):
    graph, problems = scan()
    for node in graph.values():
        for path in node['files']:
            body = strip_comments(open(path).read())
            for m in FORBIDDEN.finditer(body):
                problems.append(f'{os.path.relpath(path, ROOT)}: `{m.group(0).strip()}` is not allowed')
    problems += unchanged_problems(graph)
    done, ready = proved(graph)
    if workdir:
        os.makedirs(workdir, exist_ok=True)
    if problems:
        for p in problems:
            print(p)
        print(f'open: {len(graph)} statements, {len(problems)} problems')
        return 1
    print(f'open: {len(graph)} statements ({len(done)} proved, {len(ready)} ready to assemble), 0 problems')
    return 0


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='cmd', required=True)
    s = sub.add_parser('status')
    s.add_argument('--all', action='store_true', help='also list the proved statements')
    c = sub.add_parser('check')
    c.add_argument('workdir', nargs='?')
    cl = sub.add_parser('claim')
    cl.add_argument('name')
    cl.add_argument('--agent', required=True)
    r = sub.add_parser('release')
    r.add_argument('name')
    args = parser.parse_args()
    if args.cmd == 'status':
        status(args.all)
    elif args.cmd == 'check':
        sys.exit(check(args.workdir))
    else:
        name = short(args.name)
        graph, _ = scan()
        if PREFIX + name not in graph:
            sys.exit(f'no statement {name}')
        path = os.path.join(CLAIMS, name)
        if args.cmd == 'claim':
            held = claims().get(PREFIX + name)
            if held and held[0] != args.agent:
                sys.exit(f'{name} is claimed by {held[0]} ({held[1]:.1f} h ago)')
            os.makedirs(CLAIMS, exist_ok=True)
            with open(path, 'w') as f:
                f.write(args.agent + '\n')
            print(f'{name} claimed by {args.agent} for {CLAIM_HOURS} h')
        else:
            if os.path.exists(path):
                os.remove(path)
            print(f'{name} released')


if __name__ == '__main__':
    main()
