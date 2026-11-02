#!/usr/bin/env python3
"""Check the top theorems against formal/TRUSTED_BASE.md (roadmap F13).

    python3 -I formal/tools/trusted_check.py WORKDIR

Prints each top theorem's axioms (what `#print axioms` gives) and fails
- when one depends on an axiom other than propext, Classical.choice and
  Quot.sound (so no sorryAx, no Lean.ofReduceBool from native_decide, no
  axiom of the project's own);
- when a top theorem's statement hash differs from the one beside its entry
  in TRUSTED_BASE.md ("Top theorems"), so a statement cannot change without
  the trusted base changing; the hash is the kernel's structural hash of the
  theorem's type, printed by `lake exe topAxioms`;
- when TRUSTED_BASE.md lists a top theorem that `topAxioms` does not, or the
  other way round;
- when the hash of the trusted definitions differs from the one TRUSTED_BASE.md
  gives ("definitions `HASH`"): every project constant the statements reach,
  stopping at the computations the theorems are about (`cuts` in
  TopAxioms.lean), with its type and body, so a change to Core's semantics,
  the x86 model, the reading or a statement's definitions fails until
  TRUSTED_BASE.md says what changed. WORKDIR/definitions.txt gets each
  constant's own hash, to compare with an earlier run's;
- when the modules of the top theorems are not built from the current
  sources (`lake build --no-build`), so a stale build cannot pass.

The top theorems are the list `tops` in formal/Lanius/Tools/TopAxioms.lean.
Run from the repository root; `topAxioms` must be built (gate.build).
"""

import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import run_cache  # noqa: E402

FORMAL = run_cache.FORMAL
STANDARD = {'propext', 'Classical.choice', 'Quot.sound'}
TRUSTED = os.path.join(FORMAL, 'TRUSTED_BASE.md')
TOPS = os.path.join(FORMAL, 'Lanius', 'Tools', 'TopAxioms.lean')


def top_modules():
    """The modules of the top theorems, from TopAxioms.lean's `tops`."""
    text = open(TOPS).read()
    return sorted({m for m, _ in re.findall(r'\(`([\w.]+), `([\w.]+)\)', text)})


def listed():
    """{theorem: hash} from TRUSTED_BASE.md: each `#### `NAME`` entry under
    "Top theorems" and the `statement `HASH`` in its text."""
    text = open(TRUSTED).read()
    start = text.index('## Top theorems')
    end = text.index('\n## ', start + 1)
    entries = {}
    for m in re.finditer(r'^#### `(Lanius[\w.]+)`\n(.*?)(?=^###|\Z)', text[start:end] + '\n', re.M | re.S):
        h = re.search(r'statement `([0-9a-f]{16})`', m.group(2))
        entries[m.group(1)] = h.group(1) if h else None
    return entries


def listed_definitions():
    """The definitions hash TRUSTED_BASE.md gives, or None."""
    m = re.search(r'definitions `([0-9a-f]{16})`', open(TRUSTED).read())
    return m.group(1) if m else None


def main():
    work = os.path.abspath(sys.argv[1])
    os.makedirs(work, exist_ok=True)
    defs = os.path.join(work, 'definitions.txt')
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    with run_cache.lean_lock():
        current = subprocess.run(['lake', 'build', '--no-build', 'topAxioms'] + top_modules(), cwd=FORMAL, env=env,
                                 capture_output=True, text=True)
        if current.returncode != 0:
            print('the top theorems\' modules are not built from the current sources (lake build --no-build):')
            print((current.stdout + current.stderr)[-2000:])
            return 1
        run = subprocess.run(['systemd-run', '--user', '--scope', '--slice=work.slice', '-q', os.path.join(FORMAL, '.lake/build/bin/topAxioms'), defs],
                             cwd=FORMAL, env=env, capture_output=True, text=True, timeout=240)
    if run.returncode != 0 and not run.stdout:
        print('topAxioms failed:', run.stderr[-2000:])
        return 1
    want = listed()
    problems = []
    seen = set()
    for line in run.stdout.split('\n'):
        if not line.strip():
            continue
        parts = line.split(' ')
        name = parts[0]
        if name == 'definitions':
            print(f'trusted definitions: {parts[2]} constants, hash {parts[1]} (each in {defs})')
            if listed_definitions() != parts[1]:
                problems.append(f'the trusted definitions hash is {parts[1]}, but TRUSTED_BASE.md has '
                                f'{listed_definitions()}: a trusted definition changed; say what in TRUSTED_BASE.md '
                                f'and update the hash')
            continue
        if parts[1] == 'missing':
            problems.append(f'{name}: not found in the built modules (a top theorem, or a cut in TopAxioms.lean)')
            continue
        seen.add(name)
        digest, axioms = parts[1], [a for a in parts[2].split(',') if a] if len(parts) > 2 else []
        print(f'{name}: {", ".join(axioms) or "no axioms"}')
        extra = sorted(set(axioms) - STANDARD)
        if extra:
            problems.append(f'{name} depends on {", ".join(extra)}')
        if name not in want:
            problems.append(f'{name} (statement {digest}) has no entry under "Top theorems" in TRUSTED_BASE.md')
        elif want[name] != digest:
            problems.append(f'{name}: statement {digest}, but TRUSTED_BASE.md has {want[name]}: the statement '
                            f'changed; update its entry (what it says and assumes) and the hash')
    for name in sorted(set(want) - seen):
        problems.append(f'TRUSTED_BASE.md lists {name}, which is not a top theorem in TopAxioms.lean')
    for p in problems:
        print('FAIL', p)
    print(f'{len(seen)} top theorems, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
