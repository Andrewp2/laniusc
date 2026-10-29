"""Independent CSV/list model and reached-failure evidence for move_rows."""
from collections import Counter
import csv
import io
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

INPUT = 4194304
ROWS = 16384
CALLS = 16384
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'
MESSAGES = {
    'arguments': b'move_rows: invalid arguments\n',
    'argument_io': b'move_rows: argument I/O failure\n',
    'input_limit': b'move_rows: input byte limit\n',
    'read_limit': b'move_rows: input read-call limit\n',
    'input_io': b'move_rows: input I/O failure\n',
    'csv': b'move_rows: invalid CSV\n',
    'data': b'move_rows: CSV resource limit\n',
    'bounds': b'move_rows: row boundary out of range\n',
    'allocation': b'move_rows: allocation failed\n',
    'output_limit': b'move_rows: output byte limit\n',
    'write_limit': b'move_rows: output write-call limit\n',
    'output_io': b'move_rows: output I/O failure\n',
    'invariant': b'move_rows: ownership or provider invariant failure\n',
}
HELP = (
    b'Usage: move_rows START END BEFORE\n'
    b'Move CSV rows [START,END) before an original-table boundary.\n'
    b'Indices are zero-based ASCII decimals 0..16384; leading zeros are allowed.\n'
    b'Require START <= END <= rows and BEFORE <= rows; row 0 is ordinary data.\n'
    b'An empty selection or BEFORE within [START,END] keeps the row order.\n'
    b'Read uniform-width UTF-8 CSV through EOF; accept LF and CRLF.\n'
    b'Emit canonical quoted fields and CRLF, including unchanged order.\n'
    b'Limits: 4 MiB input, 8 MiB output, 16384 rows, 64 fields per row,\n'
    b'8192 bytes per field, 65536 bytes per record; 16384 read/write attempts.\n'
    b'65536 staging calls; 64 help/diagnostic attempts; numeric tokens <=64 bytes.\n'
    b'Stage all output and retire input/records before stdout.\n'
    b'Sole --help or -h shows help.\n'
)


def encode(rows, *, quoting=csv.QUOTE_ALL, ending='\r\n'):
    output = io.StringIO(newline='')
    csv.writer(output, quoting=quoting, lineterminator=ending).writerows(rows)
    return output.getvalue().encode('utf-8')


def records(data):
    return [row if row else [''] for row in csv.reader(io.StringIO(data.decode('utf-8'), newline=''), strict=True)]


def relocated(rows, start, end, before):
    assert 0 <= start <= end <= len(rows) and 0 <= before <= len(rows)
    if start == end or start <= before <= end:
        return rows[:]
    # Express the result in original coordinates, without simulating vector
    # extraction/splitting or their capacities.
    if before < start:
        return rows[:before] + rows[start:end] + rows[before:start] + rows[end:]
    return rows[:start] + rows[end:before] + rows[start:end] + rows[before:]


def reference(data, indices):
    return encode(relocated(records(data), *indices))


def model_cases():
    base = [[f'row{i}', ('same' if i % 2 else f'v{i}'), f'#{i}'] for i in range(6)]
    data = encode(base, quoting=csv.QUOTE_MINIMAL, ending='\n')
    choices = ((0, 0, 0), (0, 0, 6), (3, 3, 0), (3, 3, 6), (0, 6, 0), (0, 6, 6),
               (1, 4, 1), (1, 4, 2), (1, 4, 4), (1, 4, 0), (1, 4, 5), (1, 4, 6),
               (0, 2, 6), (4, 6, 0), (1, 2, 0), (1, 2, 3), (0, 1, 1), (5, 6, 5))
    cases = [(f'original-boundaries-{i}', data, indices) for i, indices in enumerate(choices)]
    cases += [('empty', b'', (0, 0, 0)), ('single', b'only', (0, 1, 0)),
              ('blank-records', b'\n\r\n""', (0, 2, 3)),
              ('quoted-multiline', encode([['a,b', '"'], ['one\r\ntwo', ''], ['\r', '\n'], ['z', 'z']]), (1, 3, 0)),
              ('unicode-bom', encode([['\ufeffname', 'city'], ['é🙂', '東京'], ['Ω', 'é🙂']]), (2, 3, 0)),
              ('unterminated-final-record', b'a,b\r\nc,d\ne,f', (0, 1, 3))]
    rng = random.Random(0x5E1EC710)
    dictionary = ['', 'same', 'a,b', '"', 'é🙂', '東京', 'one\ntwo', ' \r ']
    for index in range(6):
        count = 3 + index % 5
        rows = [[rng.choice(dictionary) for _ in range(3)] for _ in range(count)]
        source = encode(rows, quoting=csv.QUOTE_MINIMAL if index % 2 else csv.QUOTE_ALL)
        if index % 2:
            source = source[:-2]
        begin = rng.randrange(count); end = rng.randrange(begin + 1, count + 1)
        before = count if begin == 0 else 0
        cases.append((f'seeded-{index}', source, (begin, end, before)))
    for size in (1023, 1024, 1025):
        cases.append((f'canonical-size-{size}', b'x' * (size - 4), (0, 1, 0)))
    return cases


def ledger(text, *, preflight=False, help_output=False):
    events = []; counts = Counter(); live = {}; latest = None; consumed = 0
    started = False; eof = False; input_address = None; input_retired = False
    output_address = None; output_retired = False
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started, ('allocation during publication', line)
            extent = int(args.split(',')[1]); event['extent'] = extent
            event['phase'] = 'after-input' if input_retired else ('parse' if eof else 'collection-or-arguments')
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live
                live[address] = extent; latest = address; event['address'] = address
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer, line
        elif name == 'munmap':
            address, extent = args.split(','); address = address.strip()
            assert answer == '0' and live.pop(address, None) == int(extent), line
            if eof and not input_retired and address == input_address:
                input_retired = True
            if started and address == output_address:
                output_retired = True
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation or descriptor service', line))
        elif name == 'read':
            assert not preflight and not started and not eof and args.split(',')[0] == '0', line
            input_address = latest
            assert set(live) == {input_address}, ('argv must retire before input; one collector owner', line, live)
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            remaining = INPUT - consumed
            assert 0 < requested <= (min(1024, remaining) if remaining else 1), (line, consumed)
            if answer.isdigit():
                received = int(answer); assert received <= requested
                consumed += received; eof = received == 0
        elif name == 'write':
            descriptor = int(args.split(',')[0]); event['descriptor'] = descriptor
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            assert descriptor in (1, 2) and 0 < requested <= 1024
            if descriptor == 1:
                if help_output:
                    assert not live and not eof
                else:
                    assert not preflight and eof and input_retired and not output_retired
                    if not started:
                        output_address = latest
                    assert set(live) == {output_address}, ('nested records and all other owners must retire before stdout', line, live)
                started = True
            else:
                assert not live, ('diagnostic before all owner cleanup', line, live)
            if answer.isdigit():
                assert int(answer) <= requested
        elif name == 'rt_sigaction':
            assert not events and args.startswith('SIGPIPE,') and 'SIG_IGN' in args, line
        events.append(event)
    assert not live, ('unreleased mappings', live)
    assert counts['rt_sigaction'] == 1 and counts['read'] <= CALLS
    assert sum(item['name'] == 'write' and item['descriptor'] == 1 for item in events) <= CALLS
    if preflight:
        assert not any(item['name'] == 'read' for item in events)
    return dict(events=events, consumed=consumed, eof=eof, input_retired=input_retired)


class Runner:
    observes = True

    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b'\x7fELF\x02\x01'
        assert int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'move-rows-{group}-')); self.count = 0

    def run(self, label, data=b'', indices=(0, 0, 0), *, arguments=None, status=0, reason=None,
            output=None, injections=(), preflight=False, help_output=False, closed_stdout=False, closed_stderr=False):
        if arguments is None:
            arguments = list(map(str, indices))
        directory = self.directory / label; directory.mkdir()
        source = directory / 'input'; source.write_bytes(data)
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '16', '-e', 'signal=none',
                   '-e', 'trace=' + TRACE, '-o', str(directory / 'trace')]
        for call, position, change in injections:
            action = change if change.startswith('retval=') else 'error=' + change
            command += ['-e', f'inject={call}:{action}:when={position}']
        command += [self.executable, *arguments]
        (directory / 'command').write_text(repr(command) + '\n')
        with source.open('rb') as incoming:
            if closed_stdout or closed_stderr:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    result = subprocess.run(command, stdin=incoming,
                                            stdout=writer if closed_stdout else subprocess.PIPE,
                                            stderr=writer if closed_stderr else subprocess.PIPE,
                                            timeout=60, check=False)
                finally:
                    os.close(writer)
                if closed_stdout:
                    result.stdout = b''
                if closed_stderr:
                    result.stderr = b''
            else:
                result = subprocess.run(command, stdin=incoming, capture_output=True, timeout=60, check=False)
        (directory / 'stdout').write_bytes(result.stdout); (directory / 'stderr').write_bytes(result.stderr)
        (directory / 'status').write_text(str(result.returncode) + '\n')
        wanted = reference(data, indices) if output is None and status == 0 else (output or b'')
        message = MESSAGES[reason] if reason else b''
        assert result.returncode == status and result.stdout == wanted and result.stderr == message, (label, result.returncode, status, result.stdout[:100], wanted[:100], result.stderr, message)
        observed = ledger((directory / 'trace').read_text(), preflight=preflight, help_output=help_output)
        events = observed['events']; injected = []
        for call, position, change in injections:
            found = {item['ordinal']: item for item in events if item['name'] == call}
            if isinstance(position, str) and position.endswith('+'):
                positions = range(int(position[:-1]), max(found) + 1)
            elif isinstance(position, str):
                first, last = map(int, position.split('..')); positions = range(first, last + 1)
            else:
                positions = [position]
            for ordinal in positions:
                assert ordinal in found, (label, call, ordinal, 'not reached')
                event = found[ordinal]
                prefix = change.removeprefix('retval=') if change.startswith('retval=') else '-1 ' + change + ' '
                assert event['answer'].startswith(prefix) and 'INJECTED' in event['answer'], event
                injected.append(event)
        assert {item['line'] for item in events if 'INJECTED' in item['answer']} == {item['line'] for item in injected}
        for descriptor, actual in ((1, result.stdout), (2, result.stderr)):
            confirmed = sum(int(item['answer']) for item in events if item['name'] == 'write' and item['descriptor'] == descriptor and item['answer'].isdigit())
            assert confirmed == len(actual), (label, descriptor, confirmed, len(actual))
        if status == 0 and not help_output:
            assert observed['eof'] and observed['input_retired'] and observed['consumed'] == len(data)
        if reason in ('csv', 'data', 'bounds'):
            assert observed['eof'] and observed['input_retired'] and observed['consumed'] == len(data), (label, 'complete source collection must precede CSV/table admission')
        assert source.read_bytes() == data
        self.count += 1; return observed


def model(runner):
    for label, data, indices in model_cases():
        runner.run(label, data, indices)


def admission(runner):
    bad = [[], ['0'], ['0', '1'], ['0', '1', '0', 'extra'], ['1', '0', '0'],
           ['-1', '1', '0'], ['+0', '1', '0'], [' 0', '1', '0'], ['0', '1.0', '0'],
           ['0', '1', '16385'], ['0' * 65, '1', '0'], ['０', '1', '0'],
           ['--help', '0', '0'], ['--', '0', '0'], ['0', '16385', '0']]
    data = b'a\nb\nc\n'
    for index, arguments in enumerate(bad):
        runner.run(f'arguments-{index}', data, arguments=arguments, status=2, reason='arguments', preflight=True)
    for flag in ('--help', '-h'):
        runner.run('help-' + flag, data, arguments=[flag], output=HELP, preflight=True, help_output=True)
    runner.run('leading-zero-indices', data, (0, 1, 3), arguments=['00', '0001', '00003'])
    for index, indices in enumerate(((0, 4, 0), (3, 3, 4), (4, 4, 0), (0, 1, 4), (2, 4, 3))):
        runner.run(f'row-bounds-{index}', data, indices, status=2, reason='bounds')
    for index, invalid in enumerate((b'good\n"unfinished', b'a,b\nc\n', b'good\n\xff',
                                     b'good\n"\0"\n', b'good\nbare\r', b'good\n"closed"extra\n')):
        # Even an impossible table boundary is checked only after full parsing.
        runner.run(f'late-invalid-csv-{index}', invalid, (0, 0, ROWS), status=2, reason='csv')


def limits(runner):
    row = b','.join([b'x' * 8191] * 8) + b'\n'
    data = row * 64; assert len(data) == INPUT
    exact = runner.run('exact-input-cap', data, (1, 3, 5))
    excess = runner.run('excess-input-probe', data + b'x', status=2, reason='input_limit')
    runner.run('exact-row-cap', b'x\n' * ROWS, (1, 3, ROWS))
    runner.run('excess-row-cap', b'x\n' * (ROWS + 1), status=2, reason='data')
    runner.run('exact-field-count', b',' * 63 + b'\n', (0, 1, 0))
    runner.run('excess-field-count', b',' * 64 + b'\n', status=2, reason='data')
    runner.run('exact-field-bytes', b'x' * 8192, (0, 1, 0))
    runner.run('excess-field-bytes', b'x' * 8193, status=2, reason='data')
    runner.run('exact-record-bytes', b','.join([b'x' * 8192] * 8), (0, 1, 0))
    runner.run('excess-record-bytes', b','.join([b'x' * 8192] * 8 + [b'x']), status=2, reason='data')
    runner.run('canonical-empty-field-expansion', (b',' * 63 + b'\n') * 512, (1, 257, 512))
    if runner.observes:
        for observed, probe in ((exact, 0), (excess, 1)):
            reads = [item for item in observed['events'] if item['name'] == 'read']
            assert sum(int(item['answer']) for item in reads[:-1]) == INPUT
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == str(probe)


def io_failures(runner):
    rows = [['id0', 'x' * 2100], ['id1', 'a,b'], ['id2', 'é🙂'],
            ['id3', '"' * 7], ['id4', 'line\r\nnext'], ['id5', 'tail']]
    data = encode(rows, quoting=csv.QUOTE_MINIMAL); indices = (1, 3, 5)
    base = runner.run('allocation-baseline', data, indices)
    mappings = [item for item in base['events'] if item['name'] == 'mmap']; assert mappings
    if runner.observes:
        # Record holds two Vec descriptors, six native words. Original row
        # capacity is retained, so the two appends fit without growth.
        after = [item for item in mappings if item['phase'] == 'after-input']
        assert [item['extent'] for item in after] == [2 * 6 * 8, 6 * 8, len(reference(data, indices))]
    for original in mappings:
        actual = runner.run(f'oom-{original["ordinal"]}', data, indices, status=4, reason='allocation', injections=(('mmap', original['ordinal'], 'ENOMEM'),))
        attempted = [item for item in actual['events'] if item['name'] == 'mmap']
        assert [item['args'] for item in attempted] == [item['args'] for item in mappings[:original['ordinal']]]
    reads = [item for item in base['events'] if item['name'] == 'read']
    writes = [item for item in base['events'] if item['name'] == 'write' and item['descriptor'] == 1]
    assert len(reads) >= 2 and len(writes) >= 2
    for label, call, ordinal, change, reason in (
            ('read-first-eio', 'read', reads[0]['ordinal'], 'EIO', 'input_io'),
            ('read-after-prefix-eio', 'read', reads[1]['ordinal'], 'EIO', 'input_io'),
            ('read-would-block', 'read', reads[0]['ordinal'], 'EAGAIN', 'input_io'),
            ('write-first-eio', 'write', writes[0]['ordinal'], 'EIO', 'output_io'),
            ('write-zero', 'write', writes[0]['ordinal'], 'retval=0', 'output_io'),
            ('write-would-block', 'write', writes[0]['ordinal'], 'EAGAIN', 'output_io')):
        runner.run(label, data, indices, status=3, reason=reason, injections=((call, ordinal, change),))
    prefix = int(writes[0]['answer']); assert prefix == 1024
    runner.run('write-after-confirmed-prefix', data, indices, status=3, reason='output_io', output=reference(data, indices)[:prefix], injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('read-eintr', data, indices, injections=(('read', reads[0]['ordinal'], 'EINTR'),))
    runner.run('write-eintr', data, indices, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('signal-eio', status=3, preflight=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('signal-eio-closed-stderr', status=3, preflight=True, closed_stderr=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('closed-stdout', data, indices, status=3, reason='output_io', closed_stdout=True)
    runner.run('closed-stdout-empty-output', closed_stdout=True)
    runner.run('failed-argument-diagnostic', arguments=[], status=3, preflight=True, injections=(('write', 1, 'EIO'),))
    runner.run('failed-output-diagnostic', data, indices, status=3, injections=(('write', '1+', 'EIO'),))
    read_limit = runner.run('read-call-limit', b'x', (0, 1, 0), status=2, reason='read_limit', injections=(('read', f'1..{CALLS}', 'EINTR'),))
    first = runner.run('write-call-limit', data, indices, status=2, reason='write_limit', injections=(('write', f'1..{CALLS}', 'EINTR'),))
    after = runner.run('write-call-limit-after-prefix', data, indices, status=2, reason='write_limit', output=reference(data, indices)[:prefix], injections=(('write', f'2..{CALLS}', 'EINTR'),))
    failed_report = runner.run('diagnostic-call-limit', arguments=[], status=3, preflight=True, injections=(('write', '1..64', 'EINTR'),))
    if runner.observes:
        assert sum(item['name'] == 'read' for item in read_limit['events']) == CALLS
        for traced in (first, after):
            assert sum(item['name'] == 'write' and item['descriptor'] == 1 for item in traced['events']) == CALLS
            assert sum(item['name'] == 'write' and item['descriptor'] == 2 for item in traced['events']) == 1
        assert sum(item['name'] == 'write' for item in failed_report['events']) == 64
    return len(mappings)


class ControlRunner:
    """Exercise corpus construction without claiming executable behavior."""
    observes = False

    def __init__(self):
        self.count = 0

    def run(self, label, data=b'', indices=(0, 0, 0), *, status=0, output=None, help_output=False, **kwargs):
        self.count += 1
        if status == 0 and not help_output:
            assert len(reference(data, indices)) <= 8388608
        if label == 'allocation-baseline':
            return dict(events=[dict(name='mmap', ordinal=1, args='baseline'),
                                dict(name='read', ordinal=1), dict(name='read', ordinal=2),
                                dict(name='write', ordinal=1, descriptor=1, answer='1024'),
                                dict(name='write', ordinal=2, descriptor=1)])
        if label.startswith('oom-'):
            return dict(events=[dict(name='mmap', ordinal=1, args='baseline')])
        return dict(events=[])


def controls():
    assert len(HELP) == 743 and len(model_cases()) == 33
    assert reference(b'a\nb\nc\nd\n', (1, 3, 4)) == b'"a"\r\n"d"\r\n"b"\r\n"c"\r\n'
    assert reference(b'a\nb\nc\nd\n', (1, 3, 0)) == b'"b"\r\n"c"\r\n"a"\r\n"d"\r\n'
    for _, data, indices in model_cases():
        before = records(data); after = relocated(before, *indices)
        assert Counter(map(tuple, before)) == Counter(map(tuple, after))
        assert records(reference(data, indices)) == after
    trace = [
        'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0',
        'mmap(NULL, 120, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000',
        'munmap(0x100000000, 120) = 0',
        'mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'read(0, "a", 1024) = 1', 'read(0, "", 1024) = 0',
        'mmap(NULL, 24, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x300000000',
        'munmap(0x200000000, 1024) = 0',
        'mmap(NULL, 5, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'munmap(0x300000000, 24) = 0',
        'write(1, "a", 1) = 1', 'munmap(0x200000000, 5) = 0',
    ]
    assert ledger('\n'.join(trace))['input_retired']
    broken = [trace[:-1], trace[:2] + trace[3:] + [trace[2]],
              trace[:9] + trace[10:] + [trace[9]],
              trace[:10] + [trace[11]] + [trace[10]],
              trace[:-1] + [trace[-1].replace(', 5)', ', 4)')],
              trace[:10] + ['write(2, "error", 5) = 5'] + trace[10:]]
    for bad in broken:
        try:
            ledger('\n'.join(bad))
        except AssertionError:
            pass
        else:
            raise AssertionError('ledger missed an owner/order violation')
    counts = []
    for name, run in GROUPS.items():
        runner = ControlRunner(); allocations = run(runner) or 0
        counts.append(f'{name}={runner.count}' if name != 'io' else f'io={runner.count - allocations}+A')
    print('move-rows-controls ' + ' '.join(counts) + ' (host-only corpus/model; no native evidence)')


GROUPS = dict(model=model, admission=admission, limits=limits, io=io_failures)
if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in GROUPS
        group = sys.argv[1]; runner = Runner(sys.argv[2], group)
        allocations = GROUPS[group](runner) or 0
        print(f'move-rows-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
