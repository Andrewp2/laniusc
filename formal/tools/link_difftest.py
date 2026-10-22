#!/usr/bin/env python3
"""Test of separate compilation (roadmap step 9): random multi-module mini
programs, each module compiled alone by `compileModule` and the objects
linked by `linkObjects`, against `compileProgram` on the modules' program
(`linkProgram`), all in Lean with `#eval`. `Lanius/Mini/Link.lean` proves the
two equal (`link_eq`); this checks the extracted definitions run and agree.

    python3 -I formal/tools/link_difftest.py WORKDIR [--count N] [--seed S] [--chunk K]

Run from the repository root. Lean only: no laniusc, no GPU. A quarter of the
programs are broken (an import with the wrong arity or naming a missing
module or function, a call past the module's callees, or an ill-formed
function), so both sides must reject them the same way. Prints one line per
mismatch and a summary; exits nonzero on any mismatch.
"""

import argparse
import os
import random
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mini_difftest import gen_stmt, break_program, lean_stmt  # noqa: E402


def gen_modules(rng, broken):
    """Modules as (funcs, imports); funcs as in mini_difftest, imports as
    (module, func, params, results). Calls inside a module use its own
    callee numbering: its functions, then its imports."""
    count = rng.randint(1, 4)
    shapes = [[(rng.randint(0, 3), rng.randint(1, 3)) for _ in range(rng.randint(1, 3))] for _ in range(count)]
    modules = []
    for own in shapes:
        imports = []
        for _ in range(rng.randint(0, 3)):
            module = rng.randrange(count)
            func = rng.randrange(len(shapes[module]))
            imports.append((module, func) + shapes[module][func])
        callees = own + [(p, r) for _, _, p, r in imports]
        funcs = []
        for params, results in own:
            locals_ = max(params, results) + rng.randint(0, 3)
            body = gen_stmt(rng, rng.randint(1, 4), locals_, callees, results)
            # Most functions also call one of the module's imports.
            if imports and rng.random() < 0.7:
                k = rng.randrange(len(imports))
                _, _, p, r = imports[k]
                if r <= locals_:
                    call = ('call', rng.randrange(locals_ - r + 1), r, len(own) + k,
                            [('var', rng.randrange(locals_)) if locals_ else ('lit', 1) for _ in range(p)])
                    body = ('seq', call, body)
            funcs.append((params, results, locals_, body))
        modules.append((funcs, imports))
    if broken:
        m = rng.randrange(count)
        funcs, imports = modules[m]
        how = rng.choice(['arity', 'module', 'func', 'callee', 'body'] if imports else ['callee', 'body'])
        if how == 'arity':
            k = rng.randrange(len(imports))
            module, func, params, results = imports[k]
            imports[k] = (module, func, params + 1, results) if rng.random() < 0.5 else (module, func, params, results + 1)
        elif how == 'module':
            k = rng.randrange(len(imports))
            imports[k] = (count + rng.randrange(2),) + imports[k][1:]
        elif how == 'func':
            k = rng.randrange(len(imports))
            module = imports[k][0]
            imports[k] = (module, len(shapes[module]) + rng.randrange(2)) + imports[k][2:]
        elif how == 'callee':
            f = rng.randrange(len(funcs))
            params, results, locals_, body = funcs[f]
            callee = len(funcs) + len(imports) + rng.randrange(2)
            funcs[f] = (params, results, locals_, ('seq', ('call', 0, 1, callee, []), body))
        else:
            break_program(rng, funcs)
    return modules


def lean_file(programs):
    out = ['import Lanius.Mini.Link', 'open Lanius.Mini', '',
           'def Piece.isHole : Piece → Bool',
           '  | .bytes _ => false',
           '  | .rel _ => true', '',
           'def holes (objs : List Object) : Nat :=',
           '  (objs.map fun o => (o.funcs.map fun f => (f.pieces.filter Piece.isHole).length).sum).sum', '',
           'def check (ms : List Module) : String :=',
           '  let separate := (compileModules ms).bind linkObjects',
           '  let whole := ((linkProgram ms).bind compileProgram).map Binary.executable',
           '  if separate == whole then',
           '    match separate with',
           '    | none => "rejected"',
           '    | some exe => s!"same {exe.image.length} {((compileModules ms).map holes).getD 0}"',
           '  else "DIFFERENT"', '']
    for index, modules in enumerate(programs):
        ms = []
        for funcs, imports in modules:
            fs = ', '.join(f'{{ params := {p}, results := {r}, locals := {l}, body := {lean_stmt(b)} }}'
                           for p, r, l, b in funcs)
            imps = ', '.join(f'{{ owner := {mod}, func := {fn}, arity := {{ params := {p}, results := {r} }} }}'
                             for mod, fn, p, r in imports)
            ms.append(f'{{ funcs := [{fs}], imports := [{imps}] }}')
        out.append(f'def p{index} : List Module := [{", ".join(ms)}]')
    out.append('')
    out.append('#eval IO.println (String.intercalate "\\n" [' +
               ', '.join(f'check p{i}' for i in range(len(programs))) + '])')
    return '\n'.join(out) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('workdir')
    parser.add_argument('--count', type=int, default=300)
    parser.add_argument('--seed', type=int, default=9)
    parser.add_argument('--chunk', type=int, default=100)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    programs = [gen_modules(rng, broken=rng.random() < 0.25) for _ in range(args.count)]
    os.makedirs(args.workdir, exist_ok=True)
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    lines = []
    for start in range(0, len(programs), args.chunk):
        path = os.path.abspath(os.path.join(args.workdir, f'modules{start // args.chunk}.lean'))
        open(path, 'w').write(lean_file(programs[start:start + args.chunk]))
        lean = subprocess.run(['lake', 'env', 'lean', path], cwd='formal', env=env, capture_output=True, text=True)
        if lean.returncode != 0:
            raise SystemExit('lean failed:\n' + lean.stdout + lean.stderr)
        lines += lean.stdout.strip().split('\n')
    if len(lines) != len(programs):
        raise SystemExit(f'expected {len(programs)} results, got {len(lines)}')
    mismatches = [i for i, line in enumerate(lines) if line == 'DIFFERENT']
    for i in mismatches:
        print(f'program {i}: separate compilation and compileProgram differ')
    accepted = [line for line in lines if line.startswith('same')]
    total = sum(int(line.split()[1]) for line in accepted)
    holes = sum(int(line.split()[2]) for line in accepted)
    modules = sum(len(p) for p in programs)
    cross = sum(1 for p in programs if any(imports for _, imports in p))
    print(f'{len(programs)} programs ({modules} modules, {cross} with imports), {len(accepted)} linked, '
          f'{len(lines) - len(accepted) - len(mismatches)} rejected by both, {total} image bytes, {holes} holes filled, '
          f'{len(mismatches)} mismatches')
    return 1 if mismatches else 0


if __name__ == '__main__':
    sys.exit(main())
