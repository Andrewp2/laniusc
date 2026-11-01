#!/usr/bin/env python3
"""Native test of `compileSource_stops`: programs whose Core run traps at a
checked trap (a shift amount past the width, a division by zero, the least
i32 divided by -1, an index past a slice's length, a false assert), runs out
of stack or of heap, or never ends, compiled by the verified compiler
(`compileSource`, run by `#eval`) and run natively. Each call runs in a
forked child: a trapping call must end at a fault (SIGFPE for `#DE`, SIGILL
for `ud2`), a call that never ends must still be running after a second, and
the same program on arguments that do not trap must return Core's value.

    python3 formal/tools/trap_test.py WORKDIR

Run from the repository root. Prints one line per problem and a summary;
exits nonzero on any problem.
"""

import os
import signal
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import oracle_difftest  # noqa: E402
import run_cache  # noqa: E402

I32 = '{ id := 0, ty := .i32 }'


def fn(body, params=I32):
    return f'{{ params := [{params}], ret := .i32, body := {body} }}'


def i32(k):
    return f'(.int (BitVec.ofInt 32 ({k})))'


# (name, functions, [(argument, expected)]): expected is an i32, 'fault' or
# 'running'.
CASES = [
    ('shift', [fn(f'(.return (.apply .shiftLeft {i32(1)} (.local 0)))')],
     [(3, 8), (31, -2 ** 31), (32, 'fault'), (40, 'fault'), (-1, 'fault')]),
    # Shifts by an amount of another integer type: Core traps on the amount's
    # number, so 256 as a u32 amount traps a u8 shift (its low 8 bits are 0).
    ('shift-u8-by-u32', [fn('(.return (.cast .i32 (.apply .shiftLeft (.unsigned .uint8 1) '
                            '(.cast (.uint .uint32) (.local 0)))))')],
     [(3, 8), (7, 128), (8, 'fault'), (256, 'fault'), (-1, 'fault')]),
    ('shift-i8-by-u32', [fn(f'(.return (.cast .i32 (.apply .shiftRight (.cast (.sint .uint8) {i32(-128)}) '
                            '(.cast (.uint .uint32) (.local 0)))))')],
     [(0, -128), (7, -1), (8, 'fault'), (264, 'fault')]),
    ('shift-i64-by-u8', [fn(f'(.return (.cast .i32 (.apply .shiftLeft (.cast (.sint .uint64) {i32(1)}) '
                            '(.cast (.uint .uint8) (.local 0)))))')],
     [(31, -2 ** 31), (32, 0), (64, 'fault'), (256, 1)]),
    ('quotient', [fn(f'(.returnEval (.eDivide .quotient (.ePure {i32(100)}) (.ePure (.local 0))))')],
     [(7, 14), (-3, -33), (0, 'fault')]),
    ('remainder', [fn(f'(.returnEval (.eDivide .remainder (.ePure {i32(100)}) (.ePure (.local 0))))')],
     [(7, 2), (0, 'fault')]),
    ('overflow', [fn(f'(.returnEval (.eDivide .quotient (.ePure (.local 0)) (.ePure {i32(-1)})))')],
     [(5, -5), (2 ** 31 - 1, -(2 ** 31 - 1)), (-2 ** 31, 'fault')]),
    ('bounds', [fn(f'(.letAlloc 1 (.unsigned .usize 64) 3 (.letSlice 2 .i32 (.local 1) {i32(4)} '
                   f'(.then (.setIndex 2 (.local 0) {i32(7)}) (.return {i32(0)}))))')],
     [(0, 0), (3, 0), (4, 'fault'), (100, 'fault'), (-1, 'fault')]),
    ('bounds-read', [fn(f'(.letAlloc 1 (.unsigned .usize 64) 3 (.letSlice 2 .i32 (.local 1) {i32(4)} '
                        f'(.letIndex 3 .i32 2 (.local 0) (.return (.local 3)))))')],
     [(2, 0), (4, 'fault'), (-5, 'fault')]),
    ('assert', [fn(f'(.then (.assert (.eApply .less (.ePure (.local 0)) (.ePure {i32(10)}))) (.return {i32(5)}))')],
     [(3, 5), (20, 'fault')]),
    ('stack', [fn(f'(.if (.apply .greater (.local 0) {i32(0)}) '
                  f'(.letCall 1 .i32 0 [(.apply .minus (.local 0) {i32(1)})] '
                  f'(.return (.apply .plus (.local 1) {i32(1)}))) (.return {i32(0)}))')],
     [(10, 10), (1000, 1000), (10 ** 7, 'fault')]),
    ('heap', [fn(f'(.letAlloc 1 (.cast (.uint .usize) (.local 0)) 3 (.return {i32(1)}))')],
     [(16, 1), (1000, 1), (10 ** 6, 'fault')]),
    ('diverge', [fn(f'(.then (.while (.apply .greater (.local 0) {i32(0)}) .nop) (.return {i32(9)}))')],
     [(0, 9), (1, 'running')]),
]


def lean_file():
    out = [oracle_difftest.LEAN_HEAD]
    for k, (_, funcs, _) in enumerate(CASES):
        out.append(f'def p{k} : SrcProgram := {{ funcs := [{", ".join(funcs)}] }}')
        out.append(f'#eval IO.println (render (compileSource p{k}))')
    return '\n'.join(out) + '\n'


def run_child(native, arg):
    """The call's i32 result, 'fault' (SIGFPE or SIGILL), 'running' (alive
    after a second) or what else ended the child."""
    read, write = os.pipe()
    pid = os.fork()
    if pid == 0:
        os.close(read)
        signal.alarm(1)
        try:
            os.write(write, str(native.call([arg], ['i32'])).encode())
        finally:
            os._exit(0)
    os.close(write)
    data = b''
    while chunk := os.read(read, 64):
        data += chunk
    os.close(read)
    _, status = os.waitpid(pid, 0)
    if os.WIFSIGNALED(status):
        sig = os.WTERMSIG(status)
        if sig in (signal.SIGFPE, signal.SIGILL):
            return 'fault', signal.Signals(sig).name
        if sig == signal.SIGALRM:
            return 'running', None
        return f'signal {signal.Signals(sig).name}', None
    return (int(data) if data else f'exit {os.WEXITSTATUS(status)}'), None


def main():
    run_cache.no_core_dumps()
    workdir = sys.argv[1]
    os.makedirs(workdir, exist_ok=True)
    lean_path = os.path.abspath(os.path.join(workdir, 'traps.lean'))
    open(lean_path, 'w').write(lean_file())
    lean = run_cache.run_lean(lean_path)
    if lean.returncode != 0:
        raise SystemExit('lean failed:\n' + lean.stdout[-4000:] + lean.stderr[-4000:])
    lines = lean.stdout.strip().split('\n')
    if len(lines) != len(CASES):
        raise SystemExit(f'lean printed {len(lines)} lines for {len(CASES)} programs')
    native = oracle_difftest.Native()
    problems = calls = 0
    signals = {}
    for (name, _, runs), line in zip(CASES, lines):
        if line == 'none':
            print(f'{name}: compileSource rejected it')
            problems += 1
            continue
        entries_s, image_s = line[1:].split('] [')
        native.load([int(x) for x in entries_s.split(',')], bytes(int(x) for x in image_s[:-1].split(',')), 1)
        for arg, want in runs:
            calls += 1
            got, sig = run_child(native, arg)
            if sig:
                signals[sig] = signals.get(sig, 0) + 1
            if got != want:
                print(f'{name}({arg}): expected {want}, got {got}')
                problems += 1
    faults = ', '.join(f'{k}: {v}' for k, v in sorted(signals.items()))
    print(f'{len(CASES)} programs, {calls} calls ({faults}), {problems} problems')
    sys.exit(1 if problems else 0)


if __name__ == '__main__':
    main()
