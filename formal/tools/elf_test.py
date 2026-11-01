#!/usr/bin/env python3
"""Native test of the process theorems (`formal/Lanius/Mini/Process.lean`,
V6): source programs, read by the front end from laniusc's parse trees,
compiled by the verified compiler and wrapped by `elfFile` (runAll's `elf`
manifest line), then run as Linux executables. A process must exit with the
low byte of `main`'s i32 result, end at a fault (SIGFPE for `#DE`, SIGILL
for the stack check's `ud2`) when Core traps or the stack is too small.

    python3 formal/tools/elf_test.py WORKDIR

Run from the repository root. Prints one line per problem and a summary;
exits nonzero on any problem.
"""

import os
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stdlib_oracle  # noqa: E402

LANIUSC = 'target/release/laniusc'
MIB = 1 << 20


def main_returning(expr, rest=''):
    return f'module app::main;\n\nfn main() -> i32 {{\n    return {expr};\n}}\n{rest}'


DEEP = '\nfn d(n: i32) -> i32 {\n    if (n == 0) {\n        return 7;\n    }\n    return d(n - 1) + 1;\n}\n'

# (name, source, stack bytes, heap bytes, expected): expected is an exit
# status or a signal.
CASES = [
    ('ret42', main_returning('42'), MIB, MIB, 42),
    ('negative', main_returning('0 - 1'), MIB, MIB, 255),
    ('wide', main_returning('1000'), MIB, MIB, 1000 % 256),
    ('loop', 'module app::main;\n\nfn main() -> i32 {\n    let s: i32 = 0;\n    let i: i32 = 0;\n'
     '    while (i < 10) {\n        s = s + f(i);\n        i = i + 1;\n    }\n    return s;\n}\n\n'
     'fn f(x: i32) -> i32 {\n    return x * 3;\n}\n', MIB, MIB, 135),
    ('deep', main_returning('d(100000) % 256', DEEP), 16 * MIB, MIB, 167),
    ('short-stack', main_returning('d(100000) % 256', DEEP), 64 * 1024, MIB, signal.SIGILL),
    ('divide', main_returning('g(0)', '\nfn g(x: i32) -> i32 {\n    return 5 / x;\n}\n'), MIB, MIB, signal.SIGFPE),
]


def main():
    work = os.path.abspath(sys.argv[1])
    os.makedirs(work, exist_ok=True)
    problems = []
    lines = []
    for name, text, stack, heap, _ in CASES:
        base = os.path.join(work, name)
        with open(base + '.lani', 'w') as f:
            f.write(text)
        if not stdlib_oracle.parse_checked(LANIUSC, base, work):
            problems.append(f'{name}: no checked parse tree')
            continue
        lines.append(f'elf {name} {base}.elf 0 {stack} {heap} {base}')
    manifest = os.path.join(work, 'manifest.txt')
    with open(manifest, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    out = subprocess.run([stdlib_oracle.RUN_ALL, manifest], capture_output=True, text=True, timeout=240)
    if out.returncode != 0:
        problems.append(f'runAll failed: {out.stderr.strip()[:400]}')
    for name, _, _, _, expected in CASES:
        elf = os.path.join(work, name + '.elf')
        if not os.path.exists(elf):
            problems.append(f'{name}: no executable')
            continue
        os.chmod(elf, 0o755)
        try:
            run = subprocess.run([elf], capture_output=True, timeout=20)
        except subprocess.TimeoutExpired:
            problems.append(f'{name}: still running after 20 s')
            continue
        got = run.returncode
        want = -expected if isinstance(expected, signal.Signals) else expected
        if got != want:
            problems.append(f'{name}: ended with {got}, expected {want}')
    for problem in problems:
        print(problem)
    print(f'elf: {len(CASES) - len(problems)} of {len(CASES)} cases as expected')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
