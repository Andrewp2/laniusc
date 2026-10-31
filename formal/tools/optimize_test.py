#!/usr/bin/env python3
"""Test of the unverified optimizer and its proved validator (roadmap step 13).

    python3 -I formal/tools/optimize_test.py WORKDIR [--count N] [--seed S] [--calls K]

Run from the repository root. Everything runs in Lean with `#eval` and, for
the front-pass programs, natively here; laniusc is not used.

Two sets of random programs:

- mini IR programs from mini_difftest.py's generator (well-formed ones), and
- source programs from oracle_difftest.py's generator, lowered by the front
  pass (`lowerFuncs`).

For each program it reports whether the optimizer changed it, whether the
validator accepts the change, and the image size with and without the
optimizer. A mutant of each optimized program (every literal plus one) checks
that the validator rejects wrong rewrites. The source programs are also
compiled by `compileSource`, which now optimizes, and each image is run
natively against oracle_difftest.py's reference interpreter.
Exits nonzero when a native result disagrees with the reference.
"""

import argparse
import os
import random
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402
import mini_difftest  # noqa: E402
import oracle_difftest  # noqa: E402

LEAN_HEAD = '''import Lanius.Mini.Compiler
namespace Lanius.Mini

def size : Option Binary → Nat
  | none => 0
  | some b => b.image.length

def Expr.bump : Expr → Expr
  | .lit v => .lit (v + 1)
  | .var i => .var i
  | .neg e => .neg e.bump
  | .binary w o l r => .binary w o l.bump r.bump
  | .compare w o l r => .compare w o l.bump r.bump
  | .fp o l r => .fp o l.bump r.bump

partial def Stmt.bump : Stmt → Stmt
  | .skip => .skip
  | .assign i e => .assign i e.bump
  | .seq a b => .seq a.bump b.bump
  | .ite c a b => .ite c.bump a.bump b.bump
  | .loop c b => .loop c.bump b.bump
  | .call t n f args => .call t n f (args.map Expr.bump)
  | .ret vs => .ret (vs.map Expr.bump)
  | .alloc t s e => .alloc t s e.bump
  | .loadByte t a => .loadByte t a.bump
  | .storeByte a v => .storeByte a.bump v.bump
  | .loadWord w t a => .loadWord w t a.bump
  | .storeWord w a v => .storeWord w a.bump v.bump
  | .divide w o t l r => .divide w o t l.bump r.bump
  | .brk => .brk
  | .cont => .cont
  | .sys k t args => .sys k t (args.map Expr.bump)
  | .frame t b => .frame t b

def mutant (p : Program) : Program :=
  { funcs := p.funcs.map fun f => { f with body := f.body.bump } }

/-- changed accepted original-size optimized-size mutant-differs mutant-accepted -/
def report (p : Program) : String :=
  let q := optimizeProgram p
  let m := mutant q
  s!"{decide (q ≠ p)} {validate p q} {size (compileProgram p)} {size (compileOptimized p)} {decide (m ≠ q)} {validate p m}"

def reportSource (sp : SrcProgram) : String :=
  match declareProgram sp with
  | none => "none"
  | some decls =>
    match lowerFuncs (sigs sp.funcs) decls sp.funcs with
    | none => "none"
    | some fs => report { funcs := fs }

def renderImage : Option Binary → String
  | none => "none"
  | some b => s!"{b.entries} {b.image.map (·.toNat)}"

end Lanius.Mini
open Lanius.Mini
'''


def mini_program(funcs):
    fs = ', '.join(f'{{ params := {p}, results := {r}, locals := {l}, body := {mini_difftest.lean_stmt(b)} }}'
                   for p, r, l, b in funcs)
    return f'{{ funcs := [{fs}] }}'


def lean_file(minis, sources):
    out = [LEAN_HEAD]
    for k, funcs in enumerate(minis):
        out.append(f'def m{k} : Program := {mini_program(funcs)}')
        out.append(f'#eval IO.println ("mini " ++ report m{k})')
    for k, funcs in enumerate(sources):
        out.append(f'def s{k} : SrcProgram := {oracle_difftest.lean_program(funcs)}')
        out.append(f'#eval IO.println ("source " ++ reportSource s{k})')
        out.append(f'#eval IO.println ("image " ++ renderImage (compileSource s{k}))')
    return '\n'.join(out) + '\n'


class Tally:
    def __init__(self):
        self.programs = self.lowered = self.changed = self.accepted = 0
        self.before = self.after = 0
        self.mutants = self.mutants_rejected = 0

    def add(self, fields):
        changed, accepted, before, after, differs, mutant_ok = fields
        self.programs += 1
        if changed == 'true':
            self.changed += 1
            self.accepted += accepted == 'true'
        self.before += int(before)
        self.after += int(after)
        if differs == 'true':
            self.mutants += 1
            self.mutants_rejected += mutant_ok == 'false'

    def line(self, name):
        rate = 100.0 * self.accepted / self.changed if self.changed else 100.0
        shrink = 100.0 * (self.before - self.after) / self.before if self.before else 0.0
        return (f'{name}: {self.programs} programs, optimizer changed {self.changed}, validator accepted '
                f'{self.accepted} ({rate:.1f}%); image bytes {self.before} -> {self.after} ({shrink:.1f}% smaller); '
                f'mutants rejected {self.mutants_rejected}/{self.mutants}')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=200)
    parser.add_argument('--seed', type=int, default=1)
    parser.add_argument('--calls', type=int, default=8)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    minis = [mini_difftest.gen_program(rng, False) for _ in range(args.count)]
    sources = [oracle_difftest.gen_program(rng) for _ in range(args.count)]
    calls = [[oracle_difftest.gen_args(rng, funcs[0][0]) for _ in range(args.calls)] for funcs in sources]
    os.makedirs(args.workdir, exist_ok=True)
    lean_path = os.path.abspath(os.path.join(args.workdir, 'optimize.lean'))
    open(lean_path, 'w').write(lean_file(minis, sources))
    lean = run_cache.run_lean(lean_path)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    lines = lean.stdout.strip().split('\n')
    mini, source = Tally(), Tally()
    images = []
    for line in lines:
        kind, rest = line.split(' ', 1)
        if kind == 'mini':
            mini.add(rest.split())
        elif kind == 'source':
            if rest != 'none':
                source.add(rest.split())
        else:
            images.append(rest)
    if mini.programs != len(minis) or len(images) != len(sources):
        raise SystemExit(f'lean printed {len(lines)} lines for {len(minis)} + {len(sources)} programs')

    native = oracle_difftest.Native()
    disagreements = rejected = total = 0
    for k, line in enumerate(images):
        if line == 'none':
            rejected += 1
            continue
        entries_s, image_s = re.match(r'\[(.*?)\] \[(.*?)\]$', line).groups()
        native.load([int(x) for x in entries_s.split(',')], bytes(int(x) for x in image_s.split(',')),
                    len(sources[k][0][0]))
        for a in calls[k]:
            total += 1
            got = native.call(a)
            want = oracle_difftest.i32(oracle_difftest.interpret(sources[k], 0, a))
            if got != want:
                disagreements += 1
                print(f'source program {k} args {a}: optimized image {got}, reference {want}')
    print(mini.line('mini IR'))
    print(source.line('front pass'))
    print(f'compileSource: {len(sources)} programs ({rejected} rejected), {total} native calls, '
          f'{disagreements} disagreements with the reference')
    return 1 if disagreements else 0


if __name__ == '__main__':
    sys.exit(main())
