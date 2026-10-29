"""Independent binary form selection model and bounded application resource evidence."""
from collections import Counter
from pathlib import Path
from urllib.parse import quote_from_bytes, unquote_to_bytes
import os
import re
import subprocess
import sys
import tempfile

BYTE_CAP = 1048576
PAIR_CAP = 65536
INPUT_CALLS = 16384
COPY_CALLS = 131072
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'


def pairs(data):
    result = []
    for segment in data.split(b'&'):
        if not segment:
            continue
        name, _, value = segment.partition(b'=')
        result.append((unquote_to_bytes(name.replace(b'+', b' ')),
                       unquote_to_bytes(value.replace(b'+', b' '))))
    return result


def quote(value):
    # urllib uses RFC-unreserved '~'; the form safe set deliberately does not.
    return quote_from_bytes(value, safe='*-._').replace('~', '%7E').replace('%20', '+').encode('ascii')


def reference(data, key=b'k'):
    return b'&'.join(quote(name) + b'=' + quote(value) for name, value in pairs(data) if name == key)


def model_cases():
    cases = [
        ('empty', b'', b'k'), ('empty-segments', b'&&&', b'k'),
        ('single', b'k=value', b'k'), ('duplicates', b'k=one&x=skip&k=two&k=', b'k'),
        ('absent', b'x=one&y=two', b'k'), ('bare-name', b'k', b'k'),
        ('empty-name', b'=one&&=&x=skip', b''), ('empty-pair', b'=', b''),
        ('space-key', b'a+b=one&a%20b=two&a%2Bb=skip', b'a b'),
        ('literal-plus-key', b'a+b=skip&a%2bb=plus', b'a+b'),
        ('raw-argv-percent', b'%2541=literal&%41=skip', b'%41'),
        ('lowercase-escapes', b'k=%00%ff%2b%26%3d', b'k'),
        ('decode-once', b'k=%252B%2526%253D', b'k'),
        ('malformed-percent', b'k=%&k=%a&k=%zz&k=%%41&k=%+&k=%2+', b'k'),
        ('all-byte-values', b'k=' + b''.join(f'%{x:02X}'.encode() for x in range(256)), b'k'),
        ('raw-binary', b'k=\0\xff\xc0\x80\xed\xa0\x80\xf4\x90\x80\x80', b'k'),
        ('nonutf8-key', b'%FF=one&\xff=two&k=skip', b'\xff'),
        ('unicode-key', 'é=🙂&%C3%A9=é&k=skip'.encode(), 'é'.encode()),
        ('no-question-prefix-removal', b'?k=one&k=two', b'?k'),
        ('semicolon-ordinary', b'k=a;b=c&k=d=e=f', b'k'),
        ('charset-ordinary', b'_charset=bogus&k=%FF', b'k'),
        ('newline-ordinary', b'k=one\r\ntwo\n', b'k'),
        ('form-safe-set', b'k=~*-._+/%20', b'k'),
        ('literal-help-key', b'--help=yes&k=skip', b'--help'),
        ('literal-double-dash-key', b'--=yes', b'--'),
        ('empty-name-binary', b'=%00%FF&=x', b''),
    ]
    for size in (1023, 1024, 1025, 4095, 4096, 4097):
        cases.append((f'exact-output-size-{size}', b'k=' + b'a' * (size - 2), b'k'))
    return cases


def ledger(text, *, data=b'k=v', key=b'k', preflight=False):
    decoded = pairs(data)
    # Native record slots occupy eight bytes, including i32 fields. A View is
    # slice(3) + start + length = five words; Pair is two Views. These are the
    # current x86-64 layouts, also used by the direct form resource fixture.
    expected = []
    if len(decoded) <= PAIR_CAP:
        byte_count = sum(len(name) + len(value) for name, value in decoded)
        if byte_count:
            expected.append(('form-bytes', byte_count))
        if decoded:
            expected.append(('form-spans', len(decoded) * 3 * 8))
        selected_count = sum(name == key for name, _ in decoded)
        capacity = 0
        while capacity < selected_count:
            capacity = max(4, capacity * 2)
            expected.append(('selection', capacity * 2 * 5 * 8))
    allocated = 0; owners = {}; selected_address = None

    events = []; counts = Counter(); live = {}; consumed = 0; eof = False
    input_address = None; arguments = None; latest = None
    input_retired = False; started = False; retiring = False; peak = 0
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started and not input_retired, ('allocation after publication/input retirement', line)
            size = int(args.split(',')[1].strip()); event['extent'] = size
            event['phase'] = 'form-or-selection' if eof else 'before-eof'
            kind = None
            if eof:
                assert allocated < len(expected), ('unexpected post-EOF allocation', line, expected)
                kind, extent = expected[allocated]; allocated += 1
                assert size == extent, ('unexpected owner extent', kind, size, extent)
                event['owner'] = kind
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live; live[address] = size; latest = address
                peak = max(peak, sum(live.values()))
                if kind == 'selection':
                    selected_address = address
                elif kind is not None:
                    assert kind not in owners; owners[kind] = (address, size)
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name == 'munmap':
            address, size = args.split(','); address = address.strip()
            assert answer == '0' and live.pop(address, None) == int(size), line
            if eof and address == input_address:
                assert not input_retired and set(live) == arguments, ('input retired before form/selection or after argv', line, live, arguments)
                input_retired = True
            elif eof and address in arguments:
                assert input_retired, ('argv retired before borrowed-key use ended', line)
            if started:
                retiring = True
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation or file service', line))
        elif name == 'read':
            assert not preflight and not started and not eof and args.split(',')[0] == '0'
            input_address = latest
            assert input_address in live
            if arguments is None:
                arguments = set(live) - {input_address}
                assert 1 <= len(arguments) <= 2, ('argv must precede input collection', line, live)
            assert set(live) == arguments | {input_address}, ('unexpected owner during collection', line, live)
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            remaining = BYTE_CAP - consumed
            assert 0 < requested <= (min(1024, remaining) if remaining else 1), (line, consumed)
            if answer.isdigit():
                got = int(answer); assert got <= requested; consumed += got; eof = got == 0
        elif name == 'write':
            assert args.split(',')[0] == '1', ('form_select must remain silent on stderr', line)
            assert not preflight and eof and not input_retired and input_address in live and arguments <= set(live) and not retiring, ('publication before admission or after owner retirement', line, live)
            assert allocated == len(expected), ('publication before all selection storage', line)
            assert all(live.get(address) == extent for address, extent in owners.values()), ('Form retired before or during publication', line, owners, live)
            assert 'form-spans' in owners and selected_address in live, ('selection descriptors retired before or during publication', line)
            assert set(live) == arguments | {input_address, selected_address} | {address for address, _ in owners.values()}, ('unexpected publication owner', line, live)
            started = True
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            assert 0 < requested <= 1024
            if answer.isdigit():
                assert int(answer) <= requested
        elif name == 'rt_sigaction':
            assert len(events) == 0 and args.startswith('SIGPIPE,') and 'SIG_IGN' in args, line
        events.append(event)
    assert not live, ('unreleased mappings', live)
    assert counts['rt_sigaction'] == 1
    assert counts['read'] <= INPUT_CALLS and counts['write'] < COPY_CALLS
    return dict(events=events, consumed=consumed, eof=eof, peak=peak, input_retired=input_retired)


class Runner:
    observes = True

    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b'\x7fELF\x02\x01'
        assert int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'form-select-{group}-'))
        self.count = 0

    def run(self, name, data=b'', *, key=b'k', arguments=None, status=0, output=None,
            injections=(), preflight=False, closed_stdout=False, closed_stderr=False, directory_stdin=False):
        if arguments is None:
            arguments = [os.fsdecode(key)]
        directory = self.directory / name; directory.mkdir()
        source = directory / 'input'; source.write_bytes(data)
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '16', '-e', 'signal=none',
                   '-e', 'trace=' + TRACE, '-o', str(directory / 'trace')]
        for call, position, change in injections:
            action = change if change.startswith('retval=') else 'error=' + change
            command += ['-e', f'inject={call}:{action}:when={position}']
        command += [self.executable, *arguments]
        (directory / 'command').write_text(repr(command) + '\n')
        descriptor = os.open(directory if directory_stdin else source, os.O_RDONLY)
        try:
            if closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    result = subprocess.run(command, stdin=descriptor, stdout=writer,
                                            stderr=subprocess.PIPE, timeout=60, check=False)
                finally:
                    os.close(writer)
                result.stdout = b''
            elif closed_stderr:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    result = subprocess.run(command, stdin=descriptor, stdout=subprocess.PIPE,
                                            stderr=writer, timeout=60, check=False)
                finally:
                    os.close(writer)
                result.stderr = b''
            else:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=60, check=False)
        finally:
            os.close(descriptor)
        (directory / 'stdout').write_bytes(result.stdout)
        (directory / 'stderr').write_bytes(result.stderr)
        (directory / 'status').write_text(str(result.returncode) + '\n')
        wanted = reference(data, key) if output is None and status == 0 else (output or b'')
        assert result.returncode == status and result.stdout == wanted, (name, result.returncode, status, result.stdout[:128], wanted[:128], result.stderr)
        assert result.stderr == b'', (name, result.stderr)
        traced = ledger((directory / 'trace').read_text(), data=data, key=key, preflight=preflight)
        found = traced['events']; selected = []
        for call, position, change in injections:
            events = {event['ordinal']: event for event in found if event['name'] == call}
            if isinstance(position, str) and position.endswith('+'):
                positions = range(int(position[:-1]), max(events) + 1)
            elif isinstance(position, str):
                positions = range(int(position.split('..')[0]), int(position.split('..')[1]) + 1)
            else:
                positions = [position]
            for ordinal in positions:
                assert ordinal in events, (name, call, ordinal, 'not reached')
                event = events[ordinal]
                prefix = change.removeprefix('retval=') if change.startswith('retval=') else '-1 ' + change + ' '
                assert event['answer'].startswith(prefix) and 'INJECTED' in event['answer'], event
                selected.append(event)
        marked = [event for event in found if 'INJECTED' in event['answer']]
        assert {event['line'] for event in marked} == {event['line'] for event in selected}
        confirmed = sum(int(event['answer']) for event in found if event['name'] == 'write' and event['answer'].isdigit())
        assert confirmed == len(result.stdout), (name, confirmed, len(result.stdout))
        if preflight:
            assert not any(event['name'] in ('mmap', 'munmap', 'read', 'write') for event in found)
        if status == 0:
            assert traced['eof'] and traced['consumed'] == len(data) and traced['input_retired']
        assert source.read_bytes() == data
        self.count += 1
        return traced


def model(runner):
    for name, data, key in model_cases():
        runner.run(name, data, key=key)


def admission(runner):
    for index, args in enumerate(([], ['k', 'extra'], ['x'] * 17, ['k' * 4097], [os.fsdecode(b'\xff' * 4097)])):
        runner.run(f'arguments-{index}', arguments=args, status=2, preflight=True)


def limits(runner):
    exact = runner.run('exact-byte-and-output-cap', b'k=' + b'a' * (BYTE_CAP - 2))
    excess = runner.run('excess-byte-probe', b'k=' + b'a' * (BYTE_CAP - 1), status=2)
    empty = runner.run('exact-byte-cap-empty-segments', b'&' * BYTE_CAP)
    component = runner.run('exact-decoded-and-component-cap-unmatched', b'a' * BYTE_CAP)
    runner.run('exact-argv-key-cap', b'a' * 4096 + b'=value', key=b'a' * 4096)
    count = (BYTE_CAP - 2) // 3
    expanded = b'k=' + b'\xff' * count + b'a' * (BYTE_CAP - 2 - count * 3)
    assert len(expanded) < BYTE_CAP and len(reference(expanded)) == BYTE_CAP
    runner.run('exact-selected-output-cap', expanded)
    rejected = runner.run('excess-selected-output-preflight', expanded + b'a', status=2)
    runner.run('oversize-unselected-wire-is-not-output', b'x' + expanded[1:] + b'a')
    runner.run('exact-pair-cap', b'&'.join([b'='] * PAIR_CAP), key=b'')
    whole = runner.run('excess-pair-cap-even-with-no-match', b'&'.join([b'='] * (PAIR_CAP + 1)), status=2)
    if runner.observes:
        for traced, probe in ((exact, 0), (empty, 0), (component, 0), (excess, 1)):
            reads = [event for event in traced['events'] if event['name'] == 'read']
            assert sum(int(event['answer']) for event in reads[:-1]) == BYTE_CAP
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == str(probe)
        for traced in (rejected, whole):
            assert traced['eof'] and traced['input_retired']
            assert not any(event['name'] == 'write' for event in traced['events'])


def io(runner):
    payload = b'k=' + b'x' * 3072 + b'&x=ignore&' + b'&'.join([b'k=%00%FF'] * 63)
    data = b'&' * (BYTE_CAP - len(payload)) + payload
    base = runner.run('allocation-baseline', data)
    mappings = [event for event in base['events'] if event['name'] == 'mmap']
    assert mappings
    if runner.observes:
        # The baseline must reach argv, every collector growth, owned form
        # storage and several selected-descriptor growth allocations.
        before = [event for event in mappings if event['phase'] == 'before-eof']
        after = [event for event in mappings if event['phase'] == 'form-or-selection']
        assert len(before) == 13 and [event['extent'] for event in before[2:]] == [1024 << n for n in range(11)]
        assert len(after) >= 5
    for old in mappings:
        actual = runner.run(f'oom-{old["ordinal"]}', data, status=4, injections=(('mmap', old['ordinal'], 'ENOMEM'),))
        reached = [event for event in actual['events'] if event['name'] == 'mmap']
        assert [event['args'] for event in reached] == [event['args'] for event in mappings[:old['ordinal']]]
    reads = [event for event in base['events'] if event['name'] == 'read']
    writes = [event for event in base['events'] if event['name'] == 'write']
    assert len(reads) > 1 and len(writes) > 1
    runner.run('read-first-eio', data, status=3, injections=(('read', reads[0]['ordinal'], 'EIO'),))
    runner.run('read-after-prefix-eio', data, status=3, injections=(('read', reads[1]['ordinal'], 'EIO'),))
    runner.run('read-would-block', data, status=3, injections=(('read', reads[0]['ordinal'], 'EAGAIN'),))
    runner.run('read-eintr', data, injections=(('read', reads[0]['ordinal'], 'EINTR'),))
    runner.run('write-first-eio', data, status=3, injections=(('write', writes[0]['ordinal'], 'EIO'),))
    prefix = int(writes[0]['answer']); assert prefix == 1024
    runner.run('write-after-prefix-eio', data, status=3, output=reference(data)[:prefix], injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('write-would-block', data, status=3, injections=(('write', writes[0]['ordinal'], 'EAGAIN'),))
    runner.run('write-eintr', data, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('write-zero', data, status=3, injections=(('write', writes[0]['ordinal'], 'retval=0'),))
    runner.run('signal-eio', status=3, preflight=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('signal-eio-closed-stderr', status=3, preflight=True, closed_stderr=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('closed-stdout', b'k=value', status=3, closed_stdout=True)
    runner.run('closed-stdout-no-matches', b'x=value', closed_stdout=True)
    runner.run('closed-stderr-invalid-arguments', arguments=[], status=2, preflight=True, closed_stderr=True)
    runner.run('directory-stdin', status=3, directory_stdin=True)
    read_limit = runner.run('read-call-limit', b'k=value', status=2, injections=(('read', f'1..{INPUT_CALLS}', 'EINTR'),))
    first = runner.run('copy-call-limit', payload, status=2, injections=(('write', '1+', 'EINTR'),))
    after = runner.run('copy-call-limit-after-prefix', payload, status=2, output=reference(payload)[:prefix], injections=(('write', '2+', 'EINTR'),))
    if runner.observes:
        assert sum(event['name'] == 'read' for event in read_limit['events']) == INPUT_CALLS
        assert sum(event['name'] == 'write' for event in first['events']) == COPY_CALLS - 1
        assert sum(event['name'] == 'write' for event in after['events']) == COPY_CALLS - 2
    return len(mappings)


class ControlRunner:
    """Exercises corpus construction only. Never asserts native behavior."""
    observes = False

    def __init__(self):
        self.count = 0

    def run(self, name, data=b'', *, key=b'k', status=0, output=None, **kwargs):
        self.count += 1
        if status == 0:
            expected = reference(data, key)
            assert len(expected) <= BYTE_CAP
            if output is not None:
                assert output == expected
        if name == 'allocation-baseline':
            return dict(events=[dict(name='mmap', ordinal=1, args='baseline', extent=1024),
                                dict(name='read', ordinal=1), dict(name='read', ordinal=2),
                                dict(name='write', ordinal=1, answer='1024'), dict(name='write', ordinal=2)])
        if name.startswith('oom-'):
            return dict(events=[dict(name='mmap', ordinal=1, args='baseline')])
        return dict(events=[])


def controls():
    assert reference(b'k=%&k=%a&k=%zz&k=%%41') == b'k=%25&k=%25a&k=%25zz&k=%25A'
    assert reference(b'a+b=%2B&%61%20b=%FF', b'a b') == b'a+b=%2B&a+b=%FF'
    assert reference(b'k=~*-._%20%2B') == b'k=%7E*-._+%2B'
    assert len(model_cases()) == 32
    trace = [
        'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0',
        'mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000',
        'mmap(NULL, 1, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x300000000',
        'read(0, "k=v", 1024) = 3', 'read(0, "", 1024) = 0',
        'mmap(NULL, 2, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x400000000',
        'mmap(NULL, 24, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x500000000',
        'mmap(NULL, 320, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x600000000',
        'write(1, "k=v", 3) = 3', 'munmap(0x600000000, 320) = 0',
        'munmap(0x400000000, 2) = 0', 'munmap(0x500000000, 24) = 0',
        'munmap(0x300000000, 1024) = 0', 'munmap(0x100000000, 32) = 0', 'munmap(0x200000000, 1) = 0',
    ]
    assert ledger('\n'.join(trace))['input_retired']
    broken = [trace[:-1], trace[:9] + [trace[13]] + trace[9:13] + trace[14:],
              trace[:9] + [trace[14]] + trace[9:14] + trace[15:],
              trace[:10] + [trace[8].replace('0x600000000', '0x700000000')] + trace[10:],
              trace[:-1] + [trace[-1].replace(', 1)', ', 2)')],
              trace[:11] + [trace[9]] + trace[11:],
              # Retire packed Form bytes before the first stdout operation,
              # leaving spans/selection/input live: owner counts alone miss it.
              trace[:9] + [trace[11]] + trace[9:11] + trace[12:],
              trace[:9] + [trace[12]] + trace[9:12] + trace[13:],
              trace[:9] + [trace[10]] + trace[9:10] + trace[11:]]
    for bad in broken:
        try:
            ledger('\n'.join(bad))
        except AssertionError:
            pass
        else:
            raise AssertionError('ledger control admitted an ownership/order violation')
    groups = []
    for name, run in GROUPS.items():
        runner = ControlRunner(); allocations = run(runner) or 0
        groups.append(f'{name}={runner.count}' if name != 'io' else f'io={runner.count - allocations}+A')
    print('form-select-controls ' + ' '.join(groups) + ' (host-only corpus/model; no native evidence)')


GROUPS = dict(model=model, admission=admission, limits=limits, io=io)
if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in GROUPS
        group = sys.argv[1]; runner = Runner(sys.argv[2], group)
        allocations = GROUPS[group](runner) or 0
        print(f'form-select-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
