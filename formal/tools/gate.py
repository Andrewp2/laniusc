#!/usr/bin/env python3
"""The difftest gate: each test step, timed, with a time limit, and skipped
when nothing it depends on has changed.

    python3 -I formal/tools/gate.py [--tier quick|full] [--only NAME,..] [--seed S] [--force] [--limit SECONDS] [--jobs N]

Run from the repository root. A step that passes is stored (run_cache.py)
under a hash of its command and of what it reads: the built .olean files of
the Lean definitions the tests run (and runAll), the .lani sources, these
scripts and their cases, the laniusc binary, the stdlib. Running the gate
again after a change reruns only the steps the change can affect; the
others print their stored result. --force reruns every step; --seed S runs
other random programs (its results are stored too).

A step that runs past --limit (300 s) is stopped: a test that slow needs
diagnosing, not waiting for. Up to --jobs (2) steps run at once. The quick tier is for routine changes, the full
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
    # The front end's store rule over the stdlib/ and extended/ text: no `v[i] = value;` whose value calls.
    ('store-rule', ['store_rule.py', '{w}'], ['lani', 'stdlib', 'extended_all'], True),
    # F9: the IEEE specification against this CPU's SSE unit.
    ('float', ['float_test.py', '{w}', '--count', '2000', '--seed', '{s}'], ['float_test'], True),
    # Step 14 and F9: the x86 model's decode and execute against this CPU, every emitted form.
    ('x86-model', ['x86_model_test.py', '{w}', '--per-form', '100', '--seed', '{s}'], ['x86_model'], True),
    ('mini', ['mini_difftest.py', '{w}', '--count', '40', '--seed', '{s}'], ['olean:Lanius.Mini.Compiler', 'laniusc', 'stdlib'], True),
    ('oracle', ['oracle_difftest.py', '{w}', '--count', '40', '--seed', '{s}'], ['olean:Lanius.Mini.Compiler', 'laniusc', 'stdlib'], True),
    ('optimize', ['optimize_test.py', '{w}', '--count', '60', '--seed', '{s}'], ['olean:Lanius.Mini.Compiler'], True),
    # V2e: checked traps, stack and heap exhaustion fault natively; a loop that never ends runs on.
    ('traps', ['trap_test.py', '{w}'], ['olean:Lanius.Mini.Compiler'], True),
    ('frontend-cases', ['frontend_difftest.py', '{w}', '--cases', T + 'frontend_cases'], ['olean:Lanius.Mini.FrontLex', 'laniusc', 'stdlib'],
     True),
    # Two shards: laniusc runs out of GPU resources on the whole harness.
    ('fn', ['fn_difftest.py', '{w}', '--per-fn', '5', '--seed', '{s}', '--shard', '0/2'], ['olean:Lanius.Mini.Compiler', 'lani', 'laniusc', 'stdlib'], True),
    ('fn-2', ['fn_difftest.py', '{w}', '--per-fn', '5', '--seed', '{s}', '--shard', '1/2'], ['olean:Lanius.Mini.Compiler', 'lani', 'laniusc', 'stdlib'], True),
    ('self-compile-encode', ['self_compile.py', '{w}', '--count', '40', '--seed', '{s}'],
     ['olean:Lanius.Mini.FrontLex', 'run_all', 'lani', 'laniusc', 'stdlib'], True),
    ('self-compile-program', ['self_compile.py', '{w}', '--stage', 'program', '--count', '40', '--seed', '{s}'],
     ['olean:Lanius.Mini.FrontLex', 'run_all', 'lani', 'laniusc', 'stdlib'], True),
    ('stdlib-scalars', ['stdlib_oracle.py', '{w}', '--modules', 'core::cmp,core::u64,core::option', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib'], True),
    # F8: stdlib output through the host externs, stdout and stderr compared.
    ('stdlib-io', ['stdlib_oracle.py', '{w}', '--modules', 'std::io_byte,std::io_hex,std::io_binary,std::io_hex_wide_u64,std::io_utf8', '--calls', '32', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib'], True),
    # F8: the time externs (sleep_ms_i32 through poll), on small and negative counts.
    ('stdlib-time', ['stdlib_oracle.py', '{w}', '--modules', 'std::time_checked', '--calls', '16', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib'], True),
    # F6: arrays [T; N] passed by value, built by the wrapper from scalars.
    ('stdlib-arrays', ['stdlib_oracle.py', '{w}', '--modules', 'core::array_i32_4,core::array_u8_4', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib'], True),
    ('self-host', ['self_host.py', '{w}'], ['run_all', 'lani', 'laniusc', 'stdlib'], True),
    # V6: the verified compiler's ELF executables exit with main's result.
    ('elf', ['elf_test.py', '{w}'], ['run_all', 'laniusc', 'stdlib'], True),
    # The `&mut` extraction pilot against laniusc's build of the same source.
    ('mut-pilot', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                   'formal/lani/mini/mut_pilot.lani', '--lean-module', 'Lanius.Mini.MutPilot'],
     ['olean:Lanius.Mini.MutPilot', 'lani', 'laniusc', 'stdlib'], True),
    # The sqlite statement machine (docs/state-machines-design.md, M0).
    ('machine-sqlite', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                        'extended/ext/sqlite_statement.lani', '--lean-module', 'Lanius.Machines.SqliteStatement'],
     ['olean:Lanius.Machines.SqliteStatement', 'extended', 'laniusc', 'stdlib'], True),
    # The TLS session's lifecycle machine (M2): event sequences through step.
    ('machine-tls', ['fn_difftest.py', '{w}', '--per-fn', '30', '--seed', '{s}', '--source',
                     'extended/ext/openssl_tls_lifecycle.lani', '--lean-module', 'Lanius.Machines.TlsLifecycle'],
     ['olean:Lanius.Machines.TlsLifecycle', 'extended', 'laniusc', 'stdlib'], True),
    # F2: the extractor in Lanius, run on laniusc's trees, writes the checked-in extraction.
    ('extract', ['lani_extract.py', '--check', '--work', '{w}'], ['extract', 'lani', 'extended', 'laniusc', 'stdlib'], True),
    # F12: Gen/'s self program is the front end's reading of the current self source text.
    # (it reads srcDump's output, the self sources' trees and Gen/ itself)
    # It also reruns term_gen.lean on the program and compares Gen/SelfTerm*.lean.
    ('self-current', ['faithful_current.py', '{w}'], ['src_dump', 'gen', 'genb', 'term', 'lani', 'laniusc', 'stdlib'], True),
    # F13: the top theorems' axioms are the standard three, and each statement is the one TRUSTED_BASE.md lists.
    ('trusted', ['trusted_check.py', '{w}'], ['trusted'], True),
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
] + [(f'stdlib-{k}', ['stdlib_oracle.py', '{w}', '--seed', '{s}', '--shard', f'{k}/3'], ['run_all', 'laniusc', 'stdlib'],
      False) for k in range(3)] + [
    # F11: laniusc's own test programs, a seeded sample of them, run both ways.
    ('programs', ['programs_oracle.py', '{w}', '--sample', '60', '--seed', '{s}'],
     ['lean', 'run_all', 'laniusc', 'stdlib', 'programs', 'extended_all'], False),
    # Random well-typed programs in the verified compiler's subset, run both ways (fuzz_oracle.py).
    ('fuzz', ['fuzz_oracle.py', '{w}', '--count', '200', '--seed', '{s}'], ['run_all', 'laniusc', 'stdlib'], False),
    # F11: every extended/ module's testable targets, as stdlib-* tests the stdlib's.
    ('extended', ['stdlib_oracle.py', '{w}', '--root', 'extended', '--seed', '{s}'],
     ['run_all', 'laniusc', 'stdlib', 'extended_all'], False),
    # M11c: the self-built verified compiler compiles itself to its own image.
    ('self-host-fixpoint', ['self_host.py', '{w}', '--no-cases', '--fixpoint', '--timeout', '280'],
     ['run_all', 'lani', 'laniusc', 'stdlib'], False),
]


def trusted_digest():
    """The top theorems' built modules, their list and TRUSTED_BASE.md, for the `trusted` step."""
    import trusted_check
    modules = ''.join(f'import {m}\n' for m in trusted_check.top_modules())
    exe = os.path.join(run_cache.FORMAL, '.lake/build/bin/topAxioms')
    return ((run_cache.olean_digest(modules) or 'unbuilt') + run_cache.file_digest(trusted_check.TRUSTED)
            + run_cache.file_digest(trusted_check.TOPS) + (run_cache.file_digest(exe) if os.path.exists(exe) else ''))


def inputs():
    """The digest of each kind of input."""
    lean = run_cache.olean_digest('import Lanius.Mini.Process\nimport Lanius.Mini.TextCorrect\nimport Lanius.Mini.FrontLex\nimport Lanius.Mini.MutPilotCorrect\nimport Lanius.Machines.SqliteStatementCorrect\nimport Lanius.Machines.TlsLifecycleCorrect\nimport Lanius.Machines.RunLowering\n')
    if lean is None:
        raise SystemExit('the Lean definitions are not built')
    run_all = os.path.join(run_cache.FORMAL, '.lake/build/bin/runAll')
    return {
        'lean': lean,
        'run_all': run_cache.file_digest(run_all),
        'float_test': run_cache.file_digest(os.path.join(run_cache.FORMAL, '.lake/build/bin/floatTest')),
        'src_dump': run_cache.file_digest(os.path.join(run_cache.FORMAL, '.lake/build/bin/srcDump')),
        'gen': run_cache.tree_digest(os.path.join(run_cache.FORMAL, 'Lanius/Faithful/Gen')),
        # The budget certificates and their generator.
        'genb': run_cache.tree_digest(os.path.join(run_cache.FORMAL, 'Lanius/Faithful/GenB'))
        + run_cache.file_digest(os.path.join(run_cache.FORMAL, 'tools/budget_certs.py')),
        # What term_gen.lean's output depends on beside Gen/: itself and the check.
        'term': run_cache.file_digest(os.path.join(run_cache.FORMAL, 'tools/term_gen.lean'))
        + run_cache.file_digest(os.path.join(run_cache.FORMAL, 'Lanius/Faithful/Sim/Term.lean')),
        'x86_model': run_cache.file_digest(os.path.join(run_cache.FORMAL, '.lake/build/bin/x86ModelTest')),
        'extract': run_cache.file_digest(os.path.join(run_cache.FORMAL, '.lake/build/bin/extract'))
        + run_cache.tree_digest(os.path.join(run_cache.FORMAL, 'Lanius')),
        'lani': run_cache.tree_digest(os.path.join(run_cache.FORMAL, 'lani')),
        'tools': run_cache.tree_digest(os.path.join(ROOT, T)),
        # laniusc loads its kernels at run time from the shader artifacts its
        # build compiled from shaders/, so a shader-only change can leave the
        # binary byte-identical: key on both.
        'laniusc': run_cache.file_digest(LANIUSC) + run_cache.tree_digest(os.path.join(ROOT, 'shaders')),
        'stdlib': run_cache.tree_digest(os.path.join(ROOT, 'stdlib')),
        'programs': run_cache.tree_digest(os.path.join(ROOT, 'tests/fixtures'))
        + run_cache.tree_digest(os.path.join(ROOT, 'sample_programs')),
        'extended_all': run_cache.tree_digest(os.path.join(ROOT, 'extended')),
        'trusted': trusted_digest(),
        'extended': ''.join(run_cache.file_digest(os.path.join(ROOT, 'extended/ext', name))
                            for name in ('sqlite_statement.lani', 'openssl_tls_lifecycle.lani')),
    }


def tools_digest(script):
    """The digest of what a step reads of formal/tools: its script, the tools
    modules it imports or names (X.py), transitively, and frontend_cases when
    one of them names it (not gate.py: its steps' commands are in their keys).
    A change to another tool reruns no step of its."""
    import re
    tools = os.path.join(ROOT, T)
    seen, todo, cases = set(), [script], False
    while todo:
        name = todo.pop()
        if name in seen or name == 'gate' or not os.path.exists(os.path.join(tools, name + '.py')):
            continue
        seen.add(name)
        text = open(os.path.join(tools, name + '.py')).read()
        cases = cases or 'frontend_cases' in text
        todo += re.findall(r'^\s*(?:import|from)\s+(\w+)', text, re.M) + re.findall(r'(\w+)\.py\b', text)
    parts = [n + ':' + run_cache.file_digest(os.path.join(tools, n + '.py')) for n in sorted(seen)]
    if cases:
        parts.append(run_cache.tree_digest(os.path.join(tools, 'frontend_cases')))
    return run_cache.key(*parts)


BUILT = ('runAll', 'extract', 'floatTest', 'x86ModelTest', 'srcDump', 'topAxioms')


def build_stamp():
    """The size and time of every Lean source and Lake file in formal/ and of
    the built executables: when it is the one a successful build left, the
    build would be a no-op (Lake's own check takes about 10 s)."""
    parts = []
    for d, dirs, files in os.walk(run_cache.FORMAL):
        dirs[:] = sorted(x for x in dirs if x not in ('.lake', '__pycache__'))
        for name in sorted(files):
            if name.endswith('.lean') or name in ('lean-toolchain', 'lake-manifest.json'):
                st = os.stat(os.path.join(d, name))
                parts.append(f'{os.path.relpath(os.path.join(d, name), run_cache.FORMAL)} {st.st_size} {st.st_mtime_ns}')
    for exe in BUILT:
        path = os.path.join(run_cache.FORMAL, '.lake/build/bin', exe)
        st = os.stat(path) if os.path.exists(path) else None
        parts.append(f'{exe} {st and st.st_size} {st and st.st_mtime_ns}')
    return run_cache.key(run_cache.FORMAL, *parts)


def build():
    """Build what the tests run (a no-op when it is current, skipped when
    build_stamp is that of the last successful build here)."""
    stamp = build_stamp()
    if run_cache.load('gate-build', stamp) is not None:
        return
    env = dict(os.environ, PATH=os.path.expanduser('~/.elan/bin') + ':' + os.environ['PATH'])
    with run_cache.lean_lock():
        run = subprocess.run(['systemd-run', '--user', '--scope', '--slice=work.slice', '-q',
                              'lake', 'build', *BUILT, 'LaniusMini', 'Lanius.Mini.FrontLex',
                              'Lanius.Mini.MutPilotCorrect', 'Lanius.Machines.SqliteStatementCorrect',
                              'Lanius.Machines.TlsLifecycleCorrect', 'Lanius.Machines.RunLowering',
                              'Lanius.Faithful.SelfBounded'],
                             cwd=run_cache.FORMAL, env=env, capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit('lake build failed:\n' + run.stdout[-3000:] + run.stderr[-3000:])
    run_cache.store('gate-build', build_stamp(), {})


RUNNING = set()  # the process groups of the steps running now


def stop_running(signum, frame):
    """A stopped gate (timeout's SIGTERM, ^C) stops its steps' process groups
    too, which would otherwise run on in their own sessions."""
    for pgid in list(RUNNING):
        try:
            os.killpg(pgid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    raise SystemExit(f'gate stopped by signal {signum}')


def run_step(argv, limit):
    """Run a step in its own process group: (returncode or 'stopped', output, seconds)."""
    began = time.time()
    child = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                             start_new_session=True)
    RUNNING.add(child.pid)
    try:
        out, _ = child.communicate(timeout=limit)
        code = child.returncode
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        out, _ = child.communicate()
        code = 'stopped'
    RUNNING.discard(child.pid)
    return code, out, time.time() - began


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--tier', choices=('quick', 'full'), default='quick')
    parser.add_argument('--only', help='comma-separated step names')
    parser.add_argument('--seed', default='1')
    parser.add_argument('--force', action='store_true')
    parser.add_argument('--limit', type=int, default=300)
    parser.add_argument('--jobs', type=int, default=2, help='steps run at once (default 2)')
    args = parser.parse_args()
    run_cache.no_core_dumps()
    signal.signal(signal.SIGTERM, stop_running)
    signal.signal(signal.SIGINT, stop_running)
    build()
    # The steps' own builds of runAll would only wait on the Lean lock.
    os.environ['LANIUS_BUILT'] = '1'
    digests = inputs()
    steps = [s for s in STEPS if (s[3] or args.tier == 'full')]
    if args.only:
        wanted = args.only.split(',')
        unknown = set(wanted) - {s[0] for s in STEPS}
        if unknown:
            raise SystemExit(f'no step {", ".join(sorted(unknown))}')
        steps = [s for s in STEPS if s[0] in wanted]
    def digest(n):
        # 'olean:M': the built Lean files a step's `import M` loads (run_lean's key)
        if n.startswith('olean:') and n not in digests:
            digests[n] = run_cache.olean_digest(f'import {n[6:]}\n') or 'unbuilt'
        return digests[n]

    failed = 0
    began = time.time()
    todo = []
    for name, cmd, needs, _ in steps:
        workdir = os.path.join(WORK, name)
        argv = [sys.executable, '-I', os.path.join(ROOT, T, cmd[0])] + \
            [a.replace('{w}', workdir).replace('{s}', args.seed) for a in cmd[1:]]
        k = run_cache.key(name, *(a.replace(ROOT, '.') for a in argv[2:]), tools_digest(cmd[0][:-3]), *(digest(n) for n in needs))
        hit = None if args.force else run_cache.load('gate', k)
        if hit is not None:
            print(f'== {name}: unchanged since a pass in {hit["seconds"]:.0f} s: {hit["summary"]}', flush=True)
            continue
        todo.append((name, argv, k, workdir))

    def finish(name, k, workdir, code, out, seconds):
        os.makedirs(workdir, exist_ok=True)
        open(os.path.join(workdir, 'output.txt'), 'w').write(out)
        lines = [line for line in out.strip().split('\n') if line and not line.startswith('time: ')]
        summary = lines[-1] if lines else ''
        if code == 0:
            run_cache.store('gate', k, dict(seconds=seconds, summary=summary))
            print(f'== {name}: passed in {seconds:.0f} s: {summary}', flush=True)
            return 0
        why = f'stopped after {args.limit} s: diagnose it' if code == 'stopped' else f'failed (exit {code})'
        print(f'== {name}: {why}', flush=True)
        print('\n'.join('   ' + line for line in out.strip().split('\n')[-15:]), flush=True)
        return 1

    # Up to --jobs steps at once (GPU work queues in heavy, one job at a
    # time). Memory is not checked per step: each lean, laniusc and cargo
    # process a step starts waits in target/claude-work/bin/memwait.
    import concurrent.futures
    with concurrent.futures.ThreadPoolExecutor(max(1, args.jobs)) as pool:
        running = {}
        while todo or running:
            while todo and len(running) < args.jobs:
                name, argv, k, workdir = todo.pop(0)
                running[pool.submit(run_step, argv, args.limit)] = (name, k, workdir)
            done, _ = concurrent.futures.wait(list(running), timeout=1,
                                              return_when=concurrent.futures.FIRST_COMPLETED)
            for f in done:
                name, k, workdir = running.pop(f)
                failed += finish(name, k, workdir, *f.result())
    print(f'{len(steps)} steps, {failed} failed or stopped, {time.time() - began:.0f} s')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
