#!/usr/bin/env python3
"""Build check_mini.lani with the verified compiler into a Linux executable.

    python3 -I formal/cert/mini_build.py WORKDIR [--run-all PATH] [--diag]

Run from the repository root (through `lv slot` or `lv heavy`: laniusc runs
on the GPU lane for the parse tree). The front end reads laniusc's parse tree
of the program, `compileSource` compiles it, and runAll's `elf` line wraps
the image (`elfFile`) as WORKDIR/check_mini.elf. --diag prints runAll's
`diag` line instead, which says where the front end or the lowering stops.
"""

import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
import stdlib_oracle  # noqa: E402

import subprocess  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
STACK = 1 << 20
HEAP = 1 << 29     # the 2^28-byte input buffer, the stack slice, and room to spare


def main():
    args = sys.argv[1:]
    run_all = stdlib_oracle.RUN_ALL
    if '--run-all' in args:
        i = args.index('--run-all')
        run_all = args[i + 1]
        del args[i:i + 2]
    diag = '--diag' in args
    args = [a for a in args if a != '--diag']
    if len(args) != 1:
        print(__doc__.strip())
        return 2
    work = os.path.abspath(args[0])
    os.makedirs(work, exist_ok=True)
    base = os.path.join(work, 'check_mini')
    shutil.copy(os.path.join(HERE, 'check_mini.lani'), base + '.lani')
    stdlib_oracle.front.PARSE_SERVER.enable()
    if not stdlib_oracle.parse_checked('target/release/laniusc', base, work):
        print('no checked parse tree (laniusc rejected check_mini.lani?)')
        return 1
    manifest = os.path.join(work, 'manifest.txt')
    open(manifest, 'w').write(f'names check_mini {base}\n')
    names = subprocess.run([run_all, manifest], capture_output=True, text=True, timeout=240).stdout.split('\n')
    if not names or not names[0].endswith(' app::main::main 0'):
        print('function 0 is not main (the ELF entry):', names[:1])
        return 1
    line = f'diag check_mini {base}' if diag else f'elf check_mini {base}.elf 0 {STACK} {HEAP} {base}'
    open(manifest, 'w').write(line + '\n')
    out = subprocess.run([run_all, manifest], capture_output=True, text=True, timeout=240)
    print(out.stdout.rstrip())
    if out.returncode != 0 or out.stderr.strip():
        print(out.stderr.rstrip())
        return 1
    if diag:
        return 0
    if not os.path.exists(base + '.elf'):
        print('no executable: the verified compiler rejected the program (run with --diag)')
        return 1
    os.chmod(base + '.elf', 0o755)
    print(f'built {base}.elf ({os.path.getsize(base + ".elf")} bytes)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
