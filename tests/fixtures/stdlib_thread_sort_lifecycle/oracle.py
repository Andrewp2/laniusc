"""Finite sort/lifetime oracle. Python only supplies inputs and observations."""
import importlib.util
import os
from pathlib import Path
import random
import re
import resource
import signal
import struct
import subprocess
import sys
import tempfile


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('par_resources', HERE.parent / 'stdlib_thread_pool_lifecycle/resources.py')
RESOURCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RESOURCES)
EVENT = re.compile(rb'^thread-probe (init|setstack|create|destroy|join) (\d+) (\d+) (\d+)$', re.M)
MAX = 2147483647


def request(mode, workers, keys, grain=7):
    return struct.pack('<4i', mode, workers, len(keys), grain) + b''.join(struct.pack('<q', key) for key in keys)


def events(stderr):
    return [(name.decode(), int(ordinal), int(result), int(identity))
            for name, ordinal, result, identity in EVENT.findall(stderr)]


def ownership(stderr, *, created, joined, create_calls=None, join_calls=None, trap=False):
    found = events(stderr)
    assert all(event[0] in ('create', 'join') for event in found), found
    creates = [event for event in found if event[0] == 'create']
    joins = [event for event in found if event[0] == 'join']
    assert [event[1] for event in creates] == list(range(1, len(creates) + 1)), creates
    assert [event[1] for event in joins] == list(range(1, len(joins) + 1)), joins
    ids = [event[3] for event in creates if event[2] == 0]
    retired = [event[3] for event in joins if event[2] == 0]
    assert len(ids) == created and len(retired) == joined and len(set(ids)) == len(ids), found
    assert all(identity != 0 for identity in ids), found
    assert [event[3] for event in joins] == ids[:len(joins)], found
    assert len(set(event[3] for event in joins)) == len(joins), ('join retry or duplicate', found)
    if create_calls is not None: assert len(creates) == create_calls, found
    if join_calls is not None: assert len(joins) == join_calls, found
    if not trap:
        assert EVENT.sub(b'', stderr).strip() == b'', stderr
        assert retired == ids, found
    return found


def ordinary(output, mode, workers, keys, *, status=0, created=None, create_calls=None, sorted_output=None):
    assert output.returncode == 0, (mode, output.returncode, output.stdout, output.stderr)
    assert output.stdout[:1] == b'R' and output.stdout[-1:] == b'U', output.stdout
    assert len(output.stdout) == 26 + 12 * len(keys), len(output.stdout)
    actual_status, made, joined, live, creates, joins = struct.unpack('<6i', output.stdout[1:25])
    if created is None: created = workers - 1 if len(keys) >= 2 and mode not in (2, 3) else 0
    if create_calls is None: create_calls = created
    assert (actual_status, made, joined, live, creates, joins) == (status, created, created, 0, create_calls, created), output.stdout[:25]
    records = list(struct.iter_unpack('<qi', output.stdout[25:-1]))
    expected = list(enumerate(keys))
    if sorted_output is None: sorted_output = status == 0
    if sorted_output: expected.sort(key=lambda pair: pair[1])
    if mode in (1, 3):
        assert records == [(key, index) for index, key in expected], (mode, records, expected)
    else:
        assert records == [(key, -1) for _, key in expected], (mode, records, expected)
    ownership(output.stderr, created=created, joined=created, create_calls=create_calls, join_calls=created)


def run(executable, payload, faults=None, trace=None, injection=None):
    env = dict(os.environ)
    for key in list(env):
        if key.startswith('LANIUS_THREAD_PROBE_'): del env[key]
    env['LANIUS_THREAD_PROBE_TRACE'] = '1'
    for name, value in (faults or {}).items(): env['LANIUS_THREAD_PROBE_FAIL_' + name.upper()] = value
    command = [str(executable)]
    if trace is not None:
        command = ['strace', '--kill-on-exit', '-ff', '-qq', '-i', '-xx', '-v', '-s', '65536',
                   '-e', 'signal=none', '-e', 'trace=mmap,munmap,write,exit_group,futex', '-o', str(trace)]
        if injection is not None: command += ['-e', injection]
        command += [str(executable)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               env=env, start_new_session=True)
    try:
        stdout, stderr = process.communicate(payload, timeout=7)
    except subprocess.TimeoutExpired:
        # Fork-mode workers share the new process group; strace also kills all
        # tracees on termination. A timed-out test must not orphan either crew.
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate(timeout=2)
        raise AssertionError(('bounded native run timed out', command, stdout, stderr))
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)


def snapshot(prefix, profile):
    candidates = []
    for path in prefix.parent.glob(prefix.name + '.*'):
        if 'mmap(NULL, 2097152, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS' in path.read_text():
            candidates.append(int(path.name.rsplit('.', 1)[1]))
    assert len(candidates) == 1, ('cannot identify the unique source Region owner', candidates)
    return RESOURCES.read_traces(prefix, profile, candidates[0], shared_regions=True)


def retained_region(state, prefix, output):
    assert output.returncode in (-signal.SIGILL, 128 + signal.SIGILL), (output.returncode, output.stderr)
    main_pid = state['main_events'][0]['tid']
    assert re.search(r'^\+\+\+ killed by SIGILL(?: \(core dumped\))? \+\+\+$',
                     Path(str(prefix) + '.' + str(main_pid)).read_text(), re.M), 'main process did not receive SIGILL'
    regions = [allocation for allocation in state['allocations'] if allocation['kind'] == 'region']
    assert len(regions) == 1 and regions[0]['extent'] == 2097152 and regions[0]['address'], regions
    address = regions[0]['address']
    assert state['maps'].get(address) == 2097152 and state['map_kinds'][address] == 'region', state['maps']
    # Temporary source allocations may retire normally. The borrowed Region
    # itself must remain mapped; the shared ledger verifies every release.


def main():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    executable = Path(sys.argv[1]).resolve()
    profile = RESOURCES.verified_sites(executable)
    randomizer = random.Random(0x5A17)
    shapes = [[], [9], [2, -1], list(range(71, -1, -1)), [4] * 95,
              [randomizer.randrange(-9, 10) for _ in range(257)],
              [-(1 << 63), (1 << 63) - 1, 0, -1, (1 << 63) - 1, -(1 << 63)],
              [randomizer.randrange(-(1 << 40), 1 << 40) for _ in range(513)]]
    normal = 0
    for mode in (0, 1):
        for workers in (1, 3):
            for keys in shapes:
                ordinary(run(executable, request(mode, workers, keys)), mode, workers, keys)
                normal += 1
    for mode in (0, 1, 2, 3):
        keys = shapes[-1]
        ordinary(run(executable, request(mode, 3, keys, MAX)), mode, 3, keys)
        normal += 1
    # Fork regression also crosses merge-path task boundaries with small grain.
    for mode in (2, 3):
        keys = shapes[-3]
        ordinary(run(executable, request(mode, 3, keys, 3)), mode, 3, keys)
        normal += 1

    admission = 0
    keys = [5, 1, 4, 1]
    for mode, status in ((10, -1), (11, -2), (12, -3), (13, -3), (14, -1), (15, -1), (16, -1), (17, -1)):
        ordinary(run(executable, request(mode, 3, keys)), mode, 3, keys, status=status, created=0)
        admission += 1
    for workers, keys in ((3, []), (3, [7]), (1, [5, 2, 1])):
        ordinary(run(executable, request(13, workers, keys)), 13, workers, keys, created=0)
        admission += 1
    ordinary(run(executable, request(19, 3, [])), 19, 3, [], created=0)
    admission += 1

    ordinary(run(executable, request(22, 3, shapes[-3])), 22, 3, shapes[-3], status=-5, sorted_output=True)

    faults_count = 0
    traced = 0
    keys = shapes[-3]
    with tempfile.TemporaryDirectory(prefix='lanius-par-lifecycle-') as directory:
        directory = Path(directory)
        # Ordinary cleanup and both partial-start boundaries have no live owners.
        for number, create_fault in enumerate((None, '1:11', '2:11')):
            prefix = directory / f'ordinary-{number}'
            configured = {} if create_fault is None else {'create': create_fault}
            output = run(executable, request(0, 3, keys), configured, prefix)
            count = 2 if create_fault is None else int(create_fault[0]) - 1
            ordinary(output, 0, 3, keys, status=0 if create_fault is None else 11,
                     created=count, create_calls=count if create_fault is None else count + 1)
            state = snapshot(prefix, profile)
            RESOURCES.assert_empty(state)
            assert sum(allocation['kind'] == 'region' for allocation in state['allocations']) == 1
            traced += 1
            if create_fault is not None: faults_count += 1
            if create_fault is None:
                region_map = next(allocation for allocation in state['allocations'] if allocation['kind'] == 'region')

        # Failed join must terminate before the R marker or any source release.
        for number, mode, configured, made, retired, attempts in (
            (0, 30, {'join': '1:16'}, 2, 0, 1),
            (1, 31, {'join': '2:16'}, 2, 1, 2),
            (2, 32, {'create': '2:11', 'join': '1:16'}, 1, 0, 1),
        ):
            prefix = directory / f'join-{number}'
            output = run(executable, request(mode, 3, keys), configured, prefix)
            assert output.returncode != 0 and output.stdout == b'', (output.returncode, output.stdout, output.stderr)
            found = ownership(output.stderr, created=made, joined=retired, join_calls=attempts, trap=True)
            assert [event for event in found if event[0] == 'join'][-1][2] == 16, found
            retained_region(snapshot(prefix, profile), prefix, output)
            faults_count += 1; traced += 1

        prefix = directory / 'wait'
        output = run(executable, request(24, 2, keys), trace=prefix)
        assert output.returncode != 0 and output.stdout == b'', (output.returncode, output.stdout, output.stderr)
        found = events(output.stderr)
        assert [(name, ordinal, result) for name, ordinal, result, identity in found] == [('create', 1, 0), ('join', 1, 0), ('create', 2, 0)], found
        state = snapshot(prefix, profile); retained_region(state, prefix, output)
        failed = [event for event in state['events'] if event['authority'] == 'source'
                  and event['name'] == 'futex' and 'FUTEX_WAIT' in event['args'] and event['answer'].startswith('-1 EIO')]
        assert len(failed) == 1 and failed[0]['tid'] != state['main_events'][0]['tid'], failed
        faults_count += 1; traced += 1

        # Denial is scoped to this Plan's address and FUTEX_WAKE operation.
        # Without create failure this is a phase wake; with it, the stop wake.
        for mode, configured, made in ((20, {}, 2), (21, {'create': '2:11'}, 1)):
            prefix = directory / f'wake-{mode}'
            output = run(executable, request(mode, 3, keys), configured, prefix)
            assert output.returncode != 0 and output.stdout == b'', (output.returncode, output.stdout, output.stderr)
            ownership(output.stderr, created=made, joined=0, join_calls=0, trap=True)
            state = snapshot(prefix, profile)
            retained_region(state, prefix, output)
            failed = [event for event in state['main_events'] if event['authority'] == 'source'
                      and event['name'] == 'futex' and 'FUTEX_WAKE' in event['args'] and event['answer'].startswith('-1 EIO')]
            assert len(failed) == 1, failed
            faults_count += 1; traced += 1

        prefix = directory / 'allocation'
        output = run(executable, request(0, 3, keys), trace=prefix,
                     injection=f'inject=mmap:error=ENOMEM:when={region_map["ordinal"]}')
        assert output.returncode == 4 and output.stdout == b'A' and not events(output.stderr), output
        state = snapshot(prefix, profile)
        RESOURCES.assert_empty(state)
        denied = [allocation for allocation in state['allocations'] if allocation['kind'] == 'region']
        assert len(denied) == 1 and denied[0]['address'] is None and 'INJECTED' in denied[0]['answer'], denied
        faults_count += 1; traced += 1

        prefix = directory / 'exhaustion'
        output = run(executable, request(18, 3, []), trace=prefix)
        assert output.returncode == 0 and output.stdout == b'E' and not events(output.stderr), output
        state = snapshot(prefix, profile); RESOURCES.assert_empty(state)
        assert [allocation['extent'] for allocation in state['allocations'] if allocation['kind'] == 'region'] == [2097152, 4096]
        faults_count += 1; traced += 1
    print(f'thread-sort normal={normal} admission={admission} worker-error=1 faults={faults_count} traced={traced}')


if __name__ == '__main__':
    main()
