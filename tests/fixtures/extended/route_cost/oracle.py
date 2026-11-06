"""Small simple-path model and bounded route-cost application failure evidence.

This is a test oracle, not a library implementation. It deliberately enumerates
paths/cycles instead of implementing either production shortest-path algorithm.
"""
from collections import Counter
import csv
import importlib.util
import io
import os
from pathlib import Path
import random
import re
import socket
import struct
import subprocess
import sys
import tempfile
import time

MAX = (1 << 63) - 1
MIN = -(1 << 63)
DIAGNOSTIC = {
    2: b'route-cost: invalid input or arguments\n',
    3: b'route-cost: input I/O failed\n',
    4: b'route-cost: allocation failed\n',
    5: b'route-cost: output I/O failed\n',
    6: b'route-cost: negative edge requires bellman-ford\n',
    7: b'route-cost: reachable negative cycle\n',
    8: b'route-cost: i64 path arithmetic overflow\n',
    9: b'route-cost: resource limit exceeded\n',
}
TRACE = 'read,write,mmap,munmap,rt_sigaction'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
SOURCE = load('route_cost_native_source_authority', FIXTURES / 'native_c/source_allocations.py')
OWNERS = load('route_cost_source_owners', FIXTURES / 'stdlib_execution/temp_file/ledger.py')


def encode(rows):
    out = io.StringIO(newline='')
    csv.writer(out, quoting=csv.QUOTE_ALL, lineterminator='\r\n').writerows(rows)
    return out.getvalue().encode()


def input_csv(edges):
    return encode([['source', 'target', 'cost'], *edges])


def reference(nodes, edges, source):
    """Enumerate all vertex-simple paths using unbounded host integers."""
    adjacency = [[] for _ in range(nodes)]
    for a, b, cost in edges:
        adjacency[a].append((b, cost))
    distance = [None] * nodes

    def walk(node, cost, seen):
        if distance[node] is None or cost < distance[node]:
            distance[node] = cost
        for target, weight in adjacency[node]:
            if target not in seen:
                walk(target, cost + weight, seen | {target})

    walk(source, 0, {source})

    def cycle(start, node, cost, seen):
        for target, weight in adjacency[node]:
            if target == start and cost + weight < 0:
                return True
            if target not in seen and cycle(start, target, cost + weight, seen | {target}):
                return True
        return False

    negative = any(distance[node] is not None and cycle(node, node, 0, {node})
                   for node in range(nodes))
    return distance, negative


def check_output(data, nodes, edges, source, target=None):
    distances, negative = reference(nodes, edges, source)
    assert not negative
    rows = list(csv.reader(io.StringIO(data.decode(), newline=''), strict=True))
    assert encode(rows) == data, 'output must be canonical quoted CRLF CSV'
    if target is not None:
        assert rows[0] == ['source', 'target', 'reachable', 'cost', 'path'] and len(rows) == 2, rows
        row = rows[1]
        assert len(row) == 5 and row[:2] == [str(source), str(target)], rows
        expected = distances[target]
        if expected is None:
            assert row[2:] == ['false', '', ''], rows
            return
        assert row[2:4] == ['true', str(expected)], rows
        route = [int(part) for part in row[4].split(';')]
        assert ';'.join(map(str, route)) == row[4], row
        assert route[0] == source and route[-1] == target and len(set(route)) == len(route), row
        cost = 0
        for a, b in zip(route, route[1:]):
            choices = [weight for x, y, weight in edges if (x, y) == (a, b)]
            assert choices, ('path includes absent arc', row, edges)
            cost += min(choices)
        assert cost == expected, ('nonoptimal route witness', rows, distances)
        return
    assert rows[0] == ['node', 'reachable', 'cost', 'predecessor'] and len(rows) == nodes + 1, rows
    parents = [None] * nodes
    for node, (row, expected) in enumerate(zip(rows[1:], distances)):
        assert len(row) == 4 and row[0] == str(node), rows
        if expected is None:
            assert row[1:] == ['false', '', ''], row
            continue
        assert row[1:3] == ['true', str(expected)], (row, expected)
        if node == source:
            assert row[3] == '', row
            continue
        parent = int(row[3])
        assert 0 <= parent < nodes and str(parent) == row[3] and distances[parent] is not None, row
        assert any((a, b) == (parent, node) and distances[parent] + cost == expected
                   for a, b, cost in edges), ('predecessor lacks tight arc', row, edges)
        parents[node] = parent
    for node, value in enumerate(distances):
        if value is not None:
            seen = set()
            while node != source:
                assert node not in seen and parents[node] is not None, ('invalid predecessor chain', rows)
                seen.add(node)
                node = parents[node]


class Runner:
    def __init__(self, executable):
        self.executable = str(Path(executable).resolve())
        self.count = 0

    def run(self, name, data=b'', *, arguments=None, status=0, graph=None, target=None, help=False):
        args = arguments if arguments is not None else ['--nodes', str(graph[0]), '--source', str(graph[2])]
        result = subprocess.run([self.executable, *args], input=data, capture_output=True,
                                timeout=10, check=False)
        assert result.returncode == status, (name, args, result.returncode, status, result.stdout[:256], result.stderr)
        assert result.stderr == DIAGNOSTIC.get(status, b''), (name, result.stderr)
        if status:
            assert result.stdout == b'', (name, 'failure published prefix', result.stdout[:256])
        elif help:
            assert result.stdout.startswith(b'Usage: route-cost --nodes N --source S '), result.stdout
            assert b'--algorithm dijkstra|bellman-ford' in result.stdout and b'4096 nodes' in result.stdout
        else:
            check_output(result.stdout, *graph, target)
        self.count += 1
        return result


def model(runner):
    cases = [
        (1, [], 0), (4, [], 2),
        (5, [(0, 1, 8), (0, 2, 2), (2, 1, 1), (1, 3, 3), (2, 3, 20)], 0),
        (4, [(1, 0, 0), (0, 1, 0), (0, 0, 0), (1, 2, 5), (1, 2, 5), (1, 2, 9)], 1),
        (4, [(0, 2, 1), (0, 1, 1), (1, 3, 1), (2, 3, 1)], 0),
        (4, [(0, 1, 2), (1, 2, -1), (3, 3, -1)], 0),
        (2, [(0, 1, MAX)], 0), (2, [(0, 1, MIN)], 0),
    ]
    randomizer = random.Random(0x726F757465)
    for index in range(6):
        nodes = 3 + index % 3
        edges = [(a, b, randomizer.randrange(0, 10))
                 for a in range(nodes) for b in range(nodes) if randomizer.randrange(4) == 0]
        cases.append((nodes, edges, randomizer.randrange(nodes)))
    for index in range(4):
        nodes = 5
        edges = [(a, b, randomizer.randrange(-8, 10))
                 for a in range(nodes) for b in range(a + 1, nodes) if randomizer.randrange(2)]
        cases.append((nodes, edges, 0))
    for index, graph in enumerate(cases):
        nodes, edges, source = graph
        algorithms = ['bellman-ford'] if any(cost < 0 for _, _, cost in edges) else ['dijkstra', 'bellman-ford']
        for algorithm in algorithms:
            args = ['-n', str(nodes), '-s', str(source), '-a', algorithm]
            runner.run(f'graph-{index}-{algorithm}', input_csv(edges), arguments=args, graph=graph)
            target = nodes - 1
            runner.run(f'target-{index}-{algorithm}', input_csv(edges), arguments=args + ['-t', str(target)], graph=graph, target=target)
    # Omitted algorithm means Dijkstra, and an empty reachable path is a node.
    runner.run('default-source-is-target', input_csv([(0, 1, 7)]),
               arguments=['--nodes=2', '--source=1', '--target=1'], graph=(2, [(0, 1, 7)], 1), target=1)
    runner.run('quoted-lf-no-terminal-newline', b'"source","target","cost"\n"0","1","+0009"',
               graph=(2, [(0, 1, 9)], 0))


def rejection(runner):
    args = ['--nodes', '3', '--source', '0']
    malformed = [b'', b'wrong,target,cost\n', b'source,target\n', b'source,target,cost\n0,1\n',
                 b'source,target,cost\n0,1,2,3\n', b'source,target,cost\n"0,1,2\n',
                 b'source,target,cost\n0,1,"2"x\n', b'source,target,cost\n0,1,\xff\n',
                 b'source,target,cost\n0,1,\x00\n', b'source,target,cost\r0,1,2\r']
    for value in ['', '+', '-', ' 1', '1 ', '1.0', '1e0', '--1', str(MAX + 1), str(MIN - 1)]:
        malformed.append(f'source,target,cost\n0,1,{value}\n'.encode())
    for endpoint in ['3', '-1', '+1', '18446744073709551616']:
        malformed.append(f'source,target,cost\n{endpoint},1,0\n'.encode())
        malformed.append(f'source,target,cost\n0,{endpoint},0\n'.encode())
    for index, data in enumerate(malformed):
        # Four fields crosses the declared resource limit before row width admission.
        status = 9 if index == 4 else 2
        runner.run(f'malformed-{index}', data, arguments=args, status=status)
    for name, edges, algorithm, status in [
        ('negative-reachable', [(0, 1, -1)], 'dijkstra', 6),
        ('negative-unreachable', [(2, 2, -1)], 'dijkstra', 6),
        ('negative-cycle', [(0, 1, 1), (1, 2, -2), (2, 1, 1)], 'bellman-ford', 7),
        ('negative-self', [(0, 0, -1)], 'bellman-ford', 7),
        ('positive-overflow', [(0, 1, MAX), (1, 2, 1)], 'dijkstra', 8),
        ('positive-overflow-bf', [(0, 1, MAX), (1, 2, 1)], 'bellman-ford', 8),
        ('negative-overflow', [(0, 1, MIN), (1, 2, -1)], 'bellman-ford', 8),
        ('nonimproving-overflow', [(0, 1, MAX), (0, 2, 0), (1, 2, 1)], 'dijkstra', 8),
        ('overflow-before-cycle', [(0, 1, MIN), (1, 1, -1)], 'bellman-ford', 8),
    ]:
        runner.run(name, input_csv(edges), arguments=args + ['-a', algorithm], status=status)
    runner.run('field-cap', input_csv([(0, 1, '0' * 129)]), arguments=args, status=9)
    runner.run('edge-cap', b'source,target,cost\n' + b'0,1,0\n' * 65537, arguments=args, status=9)
    runner.run('input-cap', b'x' * (4194304 + 1), arguments=args, status=9)
    # Bellman-Ford conservatively admits work before allocating its result.
    runner.run('work-cap', b'source,target,cost\n' + b'0,1,0\n' * 22000,
               arguments=['-n', '4096', '-s', '0', '-a', 'bellman-ford'], status=9)


def cli(runner):
    graph = (2, [(0, 1, 3)], 0)
    bad = [[], ['-n', '2'], ['-s', '0'], ['-n', '0', '-s', '0'],
           ['-n', '2', '-s', '2'], ['-n', '2', '-s', '0', '-t', '2'],
           ['-n', '2', '-s', '0', '-a', 'auto'], ['--unknown'], ['word'], ['--', 'word'],
           ['--nodes'], ['-n', '-1', '-s', '0'], ['-n', '+2', '-s', '0'],
           ['-n', '2', '-s', '0', '-s', '0'], ['-n', '2', '-n', '2', '-s', '0'],
           ['-n', '2', '-s', '0', '-t', '1', '-t', '1'],
           ['-n', '2', '-s', '0', '-a', 'dijkstra', '-a', 'dijkstra'],
           ['--help', '--help'], ['--help', '--unknown'], ['--help', '-n', 'zero'],
           ['-n', '18446744073709551616', '-s', '0'], ['x'] * 25, ['x' * 1025]]
    for index, args in enumerate(bad):
        runner.run(f'cli-{index}', input_csv(graph[1]), arguments=args, status=2)
    runner.run('nodes-cap', arguments=['-n', '4097', '-s', '0'], status=9)
    for args in [['--help'], ['-h'], ['--help', '-n', '2']]:
        runner.run('help', arguments=args, help=True)
    runner.run('short-attached', input_csv(graph[1]), arguments=['-n2', '-s0', '-adijkstra', '-t1'], graph=graph, target=1)
    runner.run('max-nodes-empty', input_csv([]), arguments=['-n', '4096', '-s', '4095'], graph=(4096, [], 4095))
    runner.run('max-node-source-path', input_csv([]), arguments=['-n', '4096', '-s', '4095', '-t', '4095'], graph=(4096, [], 4095), target=4095)
    duplicates = [(0, 1, 0)] * 65536
    runner.run('exact-edge-cap', input_csv(duplicates), arguments=['-n2', '-s0', '-t1'], graph=(2, duplicates, 0), target=1)


def source_events(text, profile, directory):
    """Verify full-width source owners and preserve global injection ordinals."""
    found, memory, counts = [], [], Counter()
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match and match[2] in TRACE.split(','), line
        ip, name, args, answer = match.groups()
        counts[name] += 1
        authority = SOURCE.classify(profile, int(ip, 16))
        assert authority in ('source', 'native', 'bootstrap-' + name), (authority, line)
        if name in ('mmap', 'munmap'):
            memory.append(line + '\n')
        if authority == 'source':
            found.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
        else:
            assert 'INJECTED' not in answer, ('fault outside source authority', line)
    OWNERS.source_maps(''.join(memory), profile, directory)
    return found


def check_stdout_progress(events, expected, captured, completed):
    """Bind 1024-byte Descriptor writes to the app's remaining output/offset."""
    sent, partial, failed = 0, False, False
    writes = [event for event in events if event['name'] == 'write' and event['args'].startswith('1,')]
    assert writes, 'missing stdout publication'
    for event in writes:
        assert not failed and 'INJECTED' not in event['answer'], event
        fields = re.fullmatch(r'1, "((?:\\x[0-9a-f]{2})*)"(?:\.\.\.)?, ([0-9]+)', event['args'])
        assert fields, event
        sample = bytes.fromhex(fields[1].replace('\\x', ''))
        requested = int(fields[2])
        remaining = len(expected) - sent
        # std::stream::Descriptor.write returns after one host transfer and
        # caps that syscall to 1024 bytes, even for a larger application view.
        assert requested == min(1024, remaining) and sample == expected[sent:sent + len(sample)], (sent, event)
        result = event['answer'].split()[0]
        if result.isdecimal():
            count = int(result)
            assert 0 < count <= requested, event
            partial |= count < remaining
            sent += count
        else:
            assert event['answer'].startswith('-1 EAGAIN '), event
            failed = True
    assert partial, 'application did not resume after positive partial progress'
    assert captured == expected[:sent] and len(captured) == sent, (sent, len(captured))
    if completed:
        assert not failed and sent == len(expected), (sent, len(expected), writes)
    else:
        assert failed and 0 < sent < len(expected), (sent, len(expected), writes)


def socket_publication(runner, profile, root, completed):
    """Bounded stream writes publish a prefix; later calls complete or fail.

    No synthetic positive syscall result is used. In the success case the
    receiver waits for the first completed chunk, then drains. In the failure
    case it waits for process exit, so a later write times out after filling
    the socket. Each host write may transfer its full 1024-byte request; the
    application must still advance through its larger output view. Only stdout
    has a timeout; no global limits affect strace.
    """
    directory = root / ('chunked-write-resume' if completed else 'chunked-write-then-error')
    directory.mkdir()
    trace = directory / 'trace'
    input_path = directory / 'input.csv'
    input_path.write_bytes(input_csv([]))
    expected = encode([['node', 'reachable', 'cost', 'predecessor'],
                       ['0', 'true', '0', ''],
                       *[[str(node), 'false', '', ''] for node in range(1, 4096)]])
    receiver, sender = socket.socketpair()
    receiver.settimeout(8)
    sender.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
    sender.setsockopt(socket.SOL_SOCKET, socket.SO_SNDTIMEO, struct.pack('@ll', 1, 0))
    assert len(expected) > 4 * sender.getsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF)
    command = ['strace', '--kill-on-exit', '-i', '-qq', '-xx', '-s', '128',
               '-o', str(trace), '-e', 'trace=' + TRACE, '-e', 'signal=none',
               runner.executable, '-n', '4096', '-s', '0']
    process = None
    try:
        with input_path.open('rb') as source:
            process = subprocess.Popen(command, stdin=source, stdout=sender, stderr=subprocess.PIPE,
                                       env=dict(os.environ, LANIUS_ALLOC='mmap'))
        sender.close()
        if completed:
            # Observing the complete positive result establishes that the
            # initial bytes reached the socket before this reader is enabled.
            deadline = time.monotonic() + 5
            first = None
            while time.monotonic() < deadline:
                content = trace.read_text() if trace.exists() else ''
                for line in content.splitlines():
                    match = OWNERS.LINE.fullmatch(line)
                    if match and match[2] == 'write' and match[3].startswith('1,'):
                        assert SOURCE.classify(profile, int(match[1], 16)) == 'source', line
                        if match[4].isdecimal():
                            first = int(match[4])
                            break
                if first is not None:
                    break
                assert process.poll() is None, ('process exited before a completed chunk', content)
                time.sleep(0.002)
            assert first is not None and 0 < first < len(expected), first
        else:
            # There is no reader to make room: a positive prefix, then EAGAIN.
            process.wait(timeout=8)
        output = bytearray()
        while True:
            part = receiver.recv(65536)
            if not part:
                break
            output.extend(part)
        _, diagnostic = process.communicate(timeout=8)
        status = 0 if completed else 5
        assert process.returncode == status and diagnostic == DIAGNOSTIC.get(status, b''), (process.returncode, diagnostic)
        events = source_events(trace.read_text(), profile, directory)
        check_stdout_progress(events, expected, bytes(output), completed)
        if completed:
            check_output(bytes(output), 4096, [], 0)
        runner.count += 1
    finally:
        sender.close()
        receiver.close()
        if process is not None:
            if process.poll() is None:
                process.kill()
            process.communicate(timeout=5)


def io_failures(runner):
    graph = (5, [(0, 1, 8), (0, 2, 2), (2, 1, 1), (1, 3, 3), (2, 3, 20)], 0)
    payload = input_csv(graph[1])
    with tempfile.TemporaryDirectory(prefix='route-cost-io-') as temp:
        root = Path(temp)
        profile = SOURCE.verified_sites(runner.executable, root)

        def traced(name, status=0, injection=None, closed_stdout=False, directory_stdin=False):
            directory = root / name
            directory.mkdir()
            input_path = directory / 'input.csv'
            input_path.write_bytes(payload)
            trace = directory / 'trace'
            command = ['strace', '-i', '-qq', '-xx', '-s', '128', '-o', str(trace),
                       '-e', 'trace=' + TRACE, '-e', 'signal=none']
            if injection:
                call, ordinal, change = injection
                action = change if change.startswith('retval=') else 'error=' + change
                command += ['-e', f'inject={call}:{action}:when={ordinal}']
            command += [runner.executable, '-n', '5', '-s', '0', '-t', '3']
            descriptor = os.open(directory if directory_stdin else input_path, os.O_RDONLY)
            environment = dict(os.environ, LANIUS_ALLOC='mmap')
            try:
                if closed_stdout:
                    read_end, write_end = os.pipe()
                    os.close(read_end)
                    try:
                        result = subprocess.run(command, stdin=descriptor, stdout=write_end,
                                                stderr=subprocess.PIPE, env=environment, timeout=10, check=False)
                        result.stdout = b''
                    finally:
                        os.close(write_end)
                else:
                    result = subprocess.run(command, stdin=descriptor, capture_output=True,
                                            env=environment, timeout=10, check=False)
            finally:
                os.close(descriptor)
            assert result.returncode == status and result.stderr == DIAGNOSTIC.get(status, b''), (name, result)
            if status:
                assert result.stdout == b'', (name, result.stdout)
            else:
                check_output(result.stdout, *graph, 3)
            events = source_events(trace.read_text(), profile, directory)
            marked = [event for event in events if 'INJECTED' in event['answer']]
            if injection:
                call, ordinal, change = injection
                selected = [event for event in events if (event['name'], event['ordinal']) == (call, ordinal)]
                assert len(selected) == 1 and marked == selected, ('injection not reached exactly', name, marked, selected)
                expected = change.removeprefix('retval=') if change.startswith('retval=') else '-1 ' + change
                assert selected[0]['answer'].startswith(expected), selected
            else:
                assert not marked
            # The complete trace balances source owners, including argument
            # and output storage still live during stdout publication.
            runner.count += 1
            return events

        base = traced('baseline')
        mappings = [event for event in base if event['name'] == 'mmap']
        assert len(mappings) >= 3
        # These are three actual reached failures, not an exhaustive OOM sweep.
        for index in sorted({0, len(mappings) // 2, len(mappings) - 1}):
            traced(f'oom-{index}', 4, ('mmap', mappings[index]['ordinal'], 'ENOMEM'))
        first_read = next(event['ordinal'] for event in base if event['name'] == 'read')
        first_write = next(event['ordinal'] for event in base if event['name'] == 'write' and event['args'].startswith('1,'))
        signal = next(event['ordinal'] for event in base if event['name'] == 'rt_sigaction')
        traced('read-eio', 3, ('read', first_read, 'EIO'))
        traced('read-eintr', 0, ('read', first_read, 'EINTR'))
        traced('write-eio', 5, ('write', first_write, 'EIO'))
        traced('write-zero', 5, ('write', first_write, 'retval=0'))
        traced('write-eintr', 0, ('write', first_write, 'EINTR'))
        traced('signal-eio', 5, ('rt_sigaction', signal, 'EIO'))
        traced('closed-stdout', 5, closed_stdout=True)
        traced('directory-stdin', 3, directory_stdin=True)
        socket_publication(runner, profile, root, True)
        socket_publication(runner, profile, root, False)


def controls():
    """Check model and observer signal without compiling or running Lanius."""
    assert reference(3, [(0, 1, 4), (0, 2, 9), (1, 2, -1)], 0) == ([0, 4, 3], False)
    assert reference(3, [(0, 1, 0), (1, 1, -1)], 0)[1]
    assert reference(3, [(2, 2, -1)], 0) == ([0, None, None], False)
    graph = (3, [(0, 1, 4), (0, 2, 9), (1, 2, -1)], 0)
    valid = [['node', 'reachable', 'cost', 'predecessor'], ['0', 'true', '0', ''],
             ['1', 'true', '4', '0'], ['2', 'true', '3', '1']]
    check_output(encode(valid), *graph)
    route = [['source', 'target', 'reachable', 'cost', 'path'], ['0', '2', 'true', '3', '0;1;2']]
    check_output(encode(route), *graph, 2)
    bad = []
    for row, column, value in [(3, 2, '9'), (3, 3, '0'), (2, 3, '2'), (1, 1, 'false')]:
        mutation = [part[:] for part in valid]
        mutation[row][column] = value
        bad.append((encode(mutation), None))
    mutation = [part[:] for part in route]
    mutation[1][4] = '0;2'
    bad.append((encode(mutation), 2))
    for data, target in bad:
        try:
            check_output(data, *graph, target)
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError('oracle accepted wrong distance or route witness')

    def write_event(data, requested, answer):
        value = ''.join(f'\\x{byte:02x}' for byte in data)
        return dict(name='write', args=f'1, "{value}", {requested}', answer=answer)

    first = write_event(b'abcdef', 6, '2')
    resumed = write_event(b'cdef', 4, '4')
    failed = write_event(b'cdef', 4, '-1 EAGAIN (Resource temporarily unavailable)')
    check_stdout_progress([first, resumed], b'abcdef', b'abcdef', True)
    check_stdout_progress([first, failed], b'abcdef', b'ab', False)
    layered = b'a' * 1024 + b'b' * 1024 + b'c'
    chunk = write_event(b'a' * 128, 1024, '1024')
    next_chunk = write_event(b'b' * 128, 1024, '1024')
    tail = write_event(b'c', 1, '1')
    check_stdout_progress([chunk, next_chunk, tail], layered, layered, True)
    check_stdout_progress([chunk, dict(next_chunk, answer='-1 EAGAIN (Resource temporarily unavailable)')],
                          layered, layered[:1024], False)
    bad_progress = [
        ([first, write_event(b'abcd', 4, '4')], b'abcdef', True),
        ([first, write_event(b'cdef', 6, '4')], b'abcdef', True),
        ([first, failed], b'abcd', False),
        ([first, resumed], b'abcdef', False),
        ([first, dict(resumed, answer='4 (INJECTED)')], b'abcdef', True),
    ]
    for events, captured, completed in bad_progress:
        try:
            check_stdout_progress(events, b'abcdef', captured, completed)
        except AssertionError:
            pass
        else:
            raise AssertionError('publication oracle accepted wrong offset/count/effect')
    for broken in [[write_event(b'a' * 128, len(layered), '1024'), next_chunk, tail],
                   [chunk, write_event(b'a' * 128, 1024, '1024'), tail]]:
        try:
            check_stdout_progress(broken, layered, layered, True)
        except AssertionError:
            pass
        else:
            raise AssertionError('publication oracle accepted wrong layered request/offset')

    sites = SOURCE.RuntimePairs([(0x401002, 0x401012)])
    sites.mmap_flags = {0x401002: 0x22}
    sites.executable_ranges = [(0x401000, 0x401030)]
    sites.source_syscall_sites = {0x401002, 0x401012, 0x401022}
    sites.bootstrap_sites = {0x402002: 'bootstrap-mmap', 0x402012: 'bootstrap-munmap'}
    sites.image_ranges = [(0x400000, 0x403000)]
    profile = sites, []

    def event(ip, text):
        return f'[{ip:016x}] {text}\n'

    allocate = event(0x401002, 'mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000')
    release = event(0x401012, 'munmap(0x100000000, 37) = 0')
    native = event(0x7fff00001000, 'read(3, "loader", 16) = 6')
    native += event(0x402002, 'mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff30000000')
    end = event(0x402012, 'munmap(0x7fff30000000, 8388608) = 0')
    with tempfile.TemporaryDirectory(prefix='route-cost-controls-') as directory:
        assert len(source_events(native + allocate + release + end, profile, directory)) == 2
        mutations = [allocate, allocate + release + release,
                     allocate + release.replace(', 37)', ', 36)'),
                     allocate.replace('0000000000401002', '0000000000401052') + release,
                     allocate + release.replace('0000000000401012', '00007fff00001000'),
                     allocate.replace('MAP_ANONYMOUS,', 'MAP_ANONYMOUS|MAP_32BIT,') + release]
        for broken in mutations:
            try:
                source_events(broken, profile, directory)
            except (AssertionError, ValueError):
                pass
            else:
                raise AssertionError('observer accepted source owner/authority violation')
    class Corpus:
        def __init__(self):
            self.count = 0

        def run(self, name, data=b'', *, status=0, graph=None, help=False, **kwargs):
            self.count += 1
            if status == 0 and not help:
                distances, negative = reference(*graph)
                assert not negative and all(value is None or MIN <= value <= MAX for value in distances), name
            elif status:
                assert status in DIAGNOSTIC

    groups = []
    for name, group in [('model', model), ('rejection', rejection), ('cli', cli)]:
        corpus = Corpus()
        group(corpus)
        groups.append(f'{name}={corpus.count}')
    print('route-cost-controls ' + ' '.join(groups) + ' model mutations=5 ledger mutations=6 publication mutations=7 (host-only; no native evidence)')


if __name__ == '__main__':
    if len(sys.argv) == 2 and sys.argv[1] == 'controls':
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in ('model', 'rejection', 'cli', 'io')
        mode, executable = sys.argv[1:]
        runner = Runner(executable)
        {'model': model, 'rejection': rejection, 'cli': cli, 'io': io_failures}[mode](runner)
        print(f'route-cost-{mode} cases={runner.count} evidence=executed')
