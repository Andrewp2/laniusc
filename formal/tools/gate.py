#!/usr/bin/env python3
"""The difftest gate: each test step, timed, with a time limit, and skipped
when nothing it depends on has changed.

    python3 -I formal/tools/gate.py [--tier quick|full] [--only NAME,..] [--seed S] [--force] [--limit SECONDS]

Run from the repository root. A step that passes is stored (run_cache.py)
under a hash of its command and of what it reads: the built .olean files of
the Lean definitions the tests run (and runAll), the .lani sources, these
scripts and their cases, the laniusc binary, the stdlib. Running the gate
again after a change reruns only the steps the change can affect; the
others print their stored result. --force reruns every step; --seed S runs
other random programs (its results are stored too).

A step that runs past --limit (300 s) is stopped: a test that slow needs
diagnosing, not waiting for. The quick tier is for routine changes, the full
tier (larger counts, every stdlib module, the front end's random programs)
for a change the quick one passes. Prints one line per step (the whole output is in
target/claude-work/gate/STEP/output.txt); exits nonzero when a step fails or
is stopped.
"""

import argparse
import os
import signal
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_cache  # noqa: E402

ROOT = run_cache.ROOT
LANIUSC = os.path.join(ROOT, 'target/release/laniusc')
WORK = os.path.join(ROOT, 'target/claude-work/gate')
T = 'formal/tools/'

# (name, script and arguments, inputs, quick tier): inputs are what the
# step reads besides its script, from INPUTS below. {w} is the step's
# workdir, {s} the seed.
STEPS = [
    ('mini', ['mini_difftest.py', '{w}', '--count', '40', '--seed', '{s}'], ['lean', 'laniusc', 'stdlib'], True),
    ('oracle', ['oracle_difftest.py', '{w}', '--count', '40', '--seed', '{s}'], ['lean', 'laniusc', 'stdlib'], True),
    ('optimize', ['optimize_test.py', '{w}', '--count', '60', '--seed', '{s}'], ['lean'], True),
    # V2e: checked traps, stack and heap exhaustion fault natively; a loop that never ends runs on.
    ('traps', ['trap_test.py', '{w}'], ['lean'], True),
    ('frontend-cases', ['frontend_difftest.py', '{w}', '--cases', T + 'frontend_cases'], ['lean', 'laniusc', 'stdlib'],
     True),
    ('fn', ['fn_difftest.py', '{w}', '--per-fn', '5', '--seed', '{s}'], ['lean', 'lani', 'laniusc', 'stdlib'], True),
    ('self-compile-encode', ['self_compile.py', '{w}', '--count', '40', '--seed', '{s}'],
     ['lean', 'run_all', 'lani', 'laniusc', 'stdlib'], True),
    ('self-compile-program', ['self_compile.py', '{w}', '--stage', 'program', '--count', '40', '--seed', '{s}'],
     ['lean', 'run_all', 'lani', 'laniusc', 'stdlib'], True),
    ('stdlib-scalars', ['stdlib_oracle.py', '{w}', '--modules', 'core::cmp,core::u64,core::option', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib'], True),
    ('self-host', ['self_host.py', '{w}'], ['run_all', 'lani', 'laniusc', 'stdlib'], True),
    # V6: the verified compiler's ELF executables exit with main's result.
    ('elf', ['elf_test.py', '{w}'], ['run_all', 'laniusc', 'stdlib'], True),
    # The `&mut` extraction pilot against laniusc's build of the same source.
    ('mut-pilot', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                   'formal/lani/mini/mut_pilot.lani', '--lean-module', 'Lanius.Mini.MutPilot'],
     ['lean', 'lani', 'laniusc', 'stdlib'], True),
    # The sqlite statement machine (docs/state-machines-design.md, M0).
    ('machine-sqlite', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                        'extended/ext/sqlite_statement.lani', '--lean-module', 'Lanius.Machines.SqliteStatement'],
     ['lean', 'extended', 'laniusc', 'stdlib'], True),
    # The TLS session's lifecycle machine (M2): event sequences through step.
    ('machine-tls', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                     'extended/ext/openssl_tls_lifecycle.lani', '--lean-module', 'Lanius.Machines.TlsLifecycle'],
     ['lean', 'extended', 'laniusc', 'stdlib'], True),
    # The full tier: larger counts and the rest.
    ('mini-200', ['mini_difftest.py', '{w}', '--count', '200', '--seed', '{s}'], ['lean', 'laniusc', 'stdlib'], False),
    ('oracle-300', ['oracle_difftest.py', '{w}', '--count', '300', '--seed', '{s}'], ['lean', 'laniusc', 'stdlib'],
     False),
    ('optimize-500', ['optimize_test.py', '{w}', '--count', '500', '--seed', '{s}'], ['lean'], False),
    ('frontend-random', ['frontend_difftest.py', '{w}', '--count', '100', '--seed', '{s}'],
     ['lean', 'laniusc', 'stdlib'], False),
    ('frontend-generic', ['frontend_difftest.py', '{w}', '--generic', '--count', '100', '--seed', '{s}'],
     ['lean', 'laniusc', 'stdlib'], False),
] + [(f'fn-20-{k}', ['fn_difftest.py', '{w}', '--per-fn', '20', '--seed', '{s}', '--shard', f'{k}/6'],
      ['lean', 'lani', 'laniusc', 'stdlib'], False) for k in range(6)] + [
    ('self-compile-encode-100', ['self_compile.py', '{w}', '--count', '100', '--seed', '{s}'],
     ['lean', 'run_all', 'lani', 'laniusc', 'stdlib'], False),
    ('self-compile-program-100', ['self_compile.py', '{w}', '--stage', 'program', '--count', '100', '--seed', '{s}'],
     ['lean', 'run_all', 'lani', 'laniusc', 'stdlib'], False),
    ('stdlib', ['stdlib_oracle.py', '{w}', '--seed', '{s}'], ['run_all', 'laniusc', 'stdlib'], False),
    # M11c: the self-built verified compiler compiles itself to its own image.
    ('self-host-fixpoint', ['self_host.py', '{w}', '--no-cases', '--fixpoint', '--timeout', '280'],
     ['run_all', 'lani', 'laniusc', 'stdlib'], False),
]


def inputs():
    """The digest of each kind of input."""
    lean = run_cache.olean_digest('import Lanius.Mini.FrontLex\nimport Lanius.Mini.MutPilotCorrect\nimport Lanius.Machines.SqliteStatementCorrect\nimport Lanius.Machines.TlsLifecycleCorrect\nimport Lanius.Machines.RunLowering\n')
    if lean is None:
        raise SystemExit('the Lean definitions are not built')
    run_all = os.path.join(run_cache.FORMAL, '.lake/build/bin/runAll')
    return {
        'lean': lean,
        'run_all': run_cache.file_digest(run_all),
        'lani': run_cache.tree_digest(os.path.join(run_cache.FORMAL, 'lani')),
        'tools': run_cache.tree_digest(os.path.join(ROOT, T)),
        'laniusc': run_cache.file_digest(LANIUSC),
        'stdlib': run_cache.tree_digest(os.path.join(ROOT, 'stdlib')),
        'extended': ''.join(run_cache.file_digest(os.path.join(ROOT, 'extended/ext', name))
                            for name in ('sqlite_statement.lani', 'openssl_tls_lifecycle.lani')),
    }


def build():
    """Build what the tests run (a no-op when it is current)."""
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    run = subprocess.run(['systemd-run', '--user', '--scope', '-q', '-p', 'MemoryMax=6G', '-p', 'MemorySwapMax=0',
                          'lake', 'build', 'runAll', 'Lanius.Mini.FrontLex',
                          'Lanius.Mini.MutPilotCorrect', 'Lanius.Machines.SqliteStatementCorrect',
                          'Lanius.Machines.TlsLifecycleCorrect', 'Lanius.Machines.RunLowering'], cwd=run_cache.FORMAL, env=env,
                         capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit('lake build failed:\n' + run.stdout[-3000:] + run.stderr[-3000:])


def run_step(argv, limit):
    """Run a step in its own process group: (returncode or 'stopped', output, seconds)."""
    began = time.time()
    child = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                             start_new_session=True)
    try:
        out, _ = child.communicate(timeout=limit)
        code = child.returncode
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        out, _ = child.communicate()
        code = 'stopped'
    return code, out, time.time() - began


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tier', choices=('quick', 'full'), default='quick')
    parser.add_argument('--only', help='comma-separated step names')
    parser.add_argument('--seed', default='1')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--limit', type=int, default=300)
    args = parser.parse_args()
    run_cache.no_core_dumps()
    build()
    digests = inputs()
    steps = [s for s in STEPS if (s[3] or args.tier == 'full')]
    if args.only:
        wanted = args.only.split(',')
        unknown = set(wanted) - {s[0] for s in STEPS}
        if unknown:
            raise SystemExit(f'no step {", ".join(sorted(unknown))}')
        steps = [s for s in STEPS if s[0] in wanted]
    failed = 0
    began = time.time()
    for name, cmd, needs, _ in steps:
        workdir = os.path.join(WORK, name)
        argv = [sys.executable, '-I', os.path.join(ROOT, T, cmd[0])] + \
            [a.replace('{w}', workdir).replace('{s}', args.seed) for a in cmd[1:]]
        k = run_cache.key(name, *argv[2:], digests['tools'], *(digests[n] for n in needs))
        hit = None if args.force else run_cache.load('gate', k)
        if hit is not None:
            print(f'== {name}: unchanged since a pass in {hit["seconds"]:.0f} s: {hit["summary"]}', flush=True)
            continue
        code, out, seconds = run_step(argv, args.limit)
        os.makedirs(workdir, exist_ok=True)
        open(os.path.join(workdir, 'output.txt'), 'w').write(out)
        lines = [line for line in out.strip().split('\n') if line and not line.startswith('time: ')]
        summary = lines[-1] if lines else ''
        if code == 0:
            run_cache.store('gate', k, dict(seconds=seconds, summary=summary))
            print(f'== {name}: passed in {seconds:.0f} s: {summary}', flush=True)
        else:
            failed += 1
            why = f'stopped after {args.limit} s: diagnose it' if code == 'stopped' else f'failed (exit {code})'
            print(f'== {name}: {why}', flush=True)
            print('\n'.join('   ' + line for line in out.strip().split('\n')[-15:]), flush=True)
    print(f'{len(steps)} steps, {failed} failed or stopped, {time.time() - began:.0f} s')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
