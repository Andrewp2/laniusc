"""Independent ordered JSON model and bounded real-program resource evidence."""
from collections import Counter
from pathlib import Path
import json
import os
import re
import subprocess
import sys
import tempfile

BYTE_CAP = 1048576
NODE_CAP = 65536
INPUT_CALLS = 16384
COPY_CALLS = 131072
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'


class Number(str):
    """An unrounded source number token, distinct from a JSON string."""


class Object(list):
    """Ordered pairs, including duplicate member names."""


def quoted(value):
    parts = ['"']
    for scalar in value:
        if scalar in ('"', '\\'):
            parts.append('\\' + scalar)
        elif ord(scalar) < 32:
            parts.append(f'\\u{ord(scalar):04x}')
        else:
            parts.append(scalar)
    parts.append('"')
    return ''.join(parts).encode('utf-8')


def render(value):
    if value is None:
        return b'null'
    if value is True:
        return b'true'
    if value is False:
        return b'false'
    if isinstance(value, Number):
        return value.encode('ascii')
    if isinstance(value, str):
        return quoted(value)
    if isinstance(value, Object):
        return b'{' + b','.join(quoted(key) + b':' + render(child) for key, child in value) + b'}'
    assert isinstance(value, list), type(value)
    return b'[' + b','.join(map(render, value)) + b']'


def reject_constant(value):
    raise ValueError(value)


def reference(data):
    value = json.loads(data.decode('utf-8'), parse_int=Number, parse_float=Number,
                       parse_constant=reject_constant, object_pairs_hook=Object)
    return render(value)


def model_cases():
    cases = [
        ('null', b'null'), ('true-whitespace', b' \r\ntrue\t '), ('false', b'false'),
        ('negative-zero', b'-0'), ('fraction-spelling', b'1.2300e+05'),
        ('huge-exponent', b'1e400'), ('wide-integer', b'1844674407370955161600000000001'),
        ('empty-array', b' [ ] '), ('empty-object', b' { } '),
        ('duplicates', b'{"x":1,"x":2,"a":3,"\\u0061":4}'),
        ('nested', b'{"": {"x":[null,true,false,{},[1.5]]}, "z": []}'),
        ('unicode-escapes', b'"\\u0061\\u00E9\\uD83D\\uDE42"'),
        ('maximum-scalar', b'"\\uDBFF\\uDFFF"'),
        ('control-escapes', b'"\\/\\b\\f\\n\\r\\t\\\"\\\\\\u0000"'),
        ('unicode-direct', '"é🙂\u007f\u2028\u2029"'.encode()),
        ('all-controls', ('"' + ''.join(f'\\u{x:04x}' for x in range(32)) + '"').encode()),
        ('string-empty', b'""'),
    ]
    for size in (1023, 1024, 1025, 4095, 4096, 4097):
        cases.append((f'exact-output-size-{size}', b'"' + b'a' * (size - 2) + b'"'))
    cases += [('utf8-across-scratch', ('"' + 'a' * 1022 + 'é🙂' + '"').encode()),
              ('escape-across-scratch', b'"' + b'a' * 1021 + b'\\n\\t"')]
    return cases


def ledger(text, *, preflight=False):
    events = []; counts = Counter(); live = {}; consumed = 0; eof = False
    input_address = None; input_retired = False; started = False; retiring = False; peak = 0
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started and not input_retired, ('allocation after input retirement/preflight boundary', line)
            size = int(args.split(',')[1].strip()); event['extent'] = size
            event['phase'] = 'parse' if eof else 'input'
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live; live[address] = size
                peak = max(peak, sum(live.values()))
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name == 'munmap':
            address, size = args.split(','); address = address.strip()
            assert answer == '0' and live.pop(address, None) == int(size), line
            if eof and address == input_address:
                assert not input_retired; input_retired = True
            elif input_retired:
                retiring = True
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation or file service', line))
        elif name == 'read':
            assert not preflight and not started and not eof and args.split(',')[0] == '0'
            assert len(live) == 1, ('collector must hold one input owner at each actual read', line, live)
            input_address = next(iter(live))
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            remaining = BYTE_CAP - consumed
            assert 0 < requested <= (min(1024, remaining) if remaining else 1), (line, consumed)
            if answer.isdigit():
                got = int(answer); assert got <= requested; consumed += got; eof = got == 0
        elif name == 'write':
            assert args.split(',')[0] == '1', ('normalizer must remain silent on stderr', line)
            assert not preflight and eof and input_retired and live and not retiring, ('publication before admission or after document retirement', line, live)
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
        self.directory = Path(tempfile.mkdtemp(prefix=f'json-normalize-{group}-'))
        self.count = 0

    def run(self, name, data=b'', *, arguments=(), status=0, output=None,
            injections=(), preflight=False, closed_stdout=False, closed_stderr=False, directory_stdin=False):
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
        wanted = reference(data) if output is None and status == 0 else (output or b'')
        assert result.returncode == status and result.stdout == wanted, (name, result.returncode, status, result.stdout[:128], wanted[:128], result.stderr)
        assert result.stderr == b'', (name, result.stderr)
        traced = ledger((directory / 'trace').read_text(), preflight=preflight)
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
    for name, data in model_cases():
        runner.run(name, data)


def admission(runner):
    for index, args in enumerate(([''], ['--help'], ['-h'], ['--'], ['word'],
                                  [os.fsdecode(b'\xff')], ['x'] * 17, ['x' * 8193])):
        runner.run(f'arguments-{index}', arguments=args, status=2, preflight=True)
    for name, data in (
        ('empty', b''), ('partial-owned-document', b'{"a":["owned"],"b":}'),
        ('trailing-data', b'{"ok":true} trailing'), ('invalid-escape', b'"owned\\q"'),
        ('invalid-utf8', b'"\xff"'), ('surrogate-utf8', b'"\xed\xa0\x80"'),
        ('past-unicode', b'"\xf4\x90\x80\x80"'),
    ):
        traced = runner.run(name, data, status=2)
        if runner.observes:
            assert traced['eof'] and traced['consumed'] == len(data)


def limits(runner):
    exact = runner.run('exact-byte-cap', b' ' * (BYTE_CAP - 4) + b'null')
    excess = runner.run('excess-byte-probe', b' ' * (BYTE_CAP - 4) + b'null ', status=2)
    number = runner.run('exact-input-number-output-cap', b'7' * BYTE_CAP)
    controls = (BYTE_CAP - 2) // 6
    source = b'"' + b'\\n' * controls + b'a' * (BYTE_CAP - 2 - controls * 6) + b'"'
    assert len(source) < BYTE_CAP and len(reference(source)) == BYTE_CAP
    runner.run('exact-expanded-output-cap', source)
    rejected = runner.run('excess-expanded-output-preflight', source[:-1] + b'a"', status=2)
    runner.run('exact-depth', b'[' * 128 + b'null' + b']' * 128)
    runner.run('excess-depth', b'[' * 129 + b'null' + b']' * 129, status=2)
    runner.run('exact-nodes', b'[' + b','.join([b'null'] * (NODE_CAP - 1)) + b']')
    runner.run('excess-nodes', b'[' + b','.join([b'null'] * NODE_CAP) + b']', status=2)
    if runner.observes:
        for traced, probe in ((exact, 0), (number, 0), (excess, 1)):
            reads = [event for event in traced['events'] if event['name'] == 'read']
            assert sum(int(event['answer']) for event in reads[:-1]) == BYTE_CAP
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == str(probe)
        assert rejected['eof'] and rejected['input_retired']
        assert not any(event['name'] == 'write' for event in rejected['events'])


def io(runner):
    payload = b'{"dup":[1,"' + b'a' * 4096 + b'",{"leaf":"owned"}],"dup":-0,"tail":true}'
    data = b' ' * (BYTE_CAP - len(payload)) + payload
    base = runner.run('allocation-baseline', data)
    mappings = [event for event in base['events'] if event['name'] == 'mmap']
    assert mappings
    if runner.observes:
        assert {event['phase'] for event in mappings} == {'input', 'parse'}
        assert [event['extent'] for event in mappings if event['phase'] == 'input'] == [1024 << n for n in range(11)]
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
    prefix = int(writes[0]['answer'])
    assert prefix == 1024
    runner.run('write-after-prefix-eio', data, status=3, output=reference(data)[:prefix], injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('write-would-block', data, status=3, injections=(('write', writes[0]['ordinal'], 'EAGAIN'),))
    runner.run('write-eintr', data, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('write-zero', data, status=3, injections=(('write', writes[0]['ordinal'], 'retval=0'),))
    runner.run('signal-eio', status=3, preflight=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('signal-eio-closed-stderr', status=3, preflight=True, closed_stderr=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('closed-stdout', b'{"valid":true}', status=3, closed_stdout=True)
    runner.run('closed-stderr-invalid-input', b'[invalid', status=2, closed_stderr=True)
    runner.run('directory-stdin', status=3, directory_stdin=True)
    read_limit = runner.run('read-call-limit', b'null', status=2, injections=(('read', f'1..{INPUT_CALLS}', 'EINTR'),))
    first = runner.run('copy-call-limit', payload, status=2, injections=(('write', '1+', 'EINTR'),))
    after = runner.run('copy-call-limit-after-prefix', payload, status=2, output=reference(payload)[:prefix], injections=(('write', '2+', 'EINTR'),))
    if runner.observes:
        assert sum(event['name'] == 'read' for event in read_limit['events']) == INPUT_CALLS
        # With 1024 scratch, a stalled first write follows one encoder read.
        # A successful first write lets the second encoder read spend one more
        # call. There are no diagnostic attempts in this quiet application.
        assert sum(event['name'] == 'write' for event in first['events']) == COPY_CALLS - 1
        assert sum(event['name'] == 'write' for event in after['events']) == COPY_CALLS - 2
    return len(mappings)


class ControlRunner:
    """Exercises corpus construction only. Never asserts native behavior."""
    observes = False

    def __init__(self):
        self.count = 0

    def run(self, name, data=b'', *, status=0, output=None, **kwargs):
        self.count += 1
        if status == 0:
            expected = reference(data)
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
    assert reference(b'{"x":1e400,"x":-0,"\\u0061":"\\n"}') == b'{"x":1e400,"x":-0,"a":"\\u000a"}'
    assert reference(b'"\\uD83D\\uDE42\\/\\b"') == '"🙂/\\u0008"'.encode()
    assert len(model_cases()) == 25
    trace = [
        'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0',
        'mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000',
        'read(0, "null", 1024) = 4', 'read(0, "", 1024) = 0',
        'mmap(NULL, 256, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'munmap(0x100000000, 1024) = 0', 'write(1, "null", 4) = 4',
        'munmap(0x200000000, 256) = 0',
    ]
    assert ledger('\n'.join(trace))['input_retired']
    broken = [trace[:-1], trace[:5] + trace[6:],
              trace[:6] + [trace[4].replace('0x200000000', '0x300000000')] + trace[6:],
              trace[:-1] + [trace[-1].replace('256', '255')],
              trace[:5] + [trace[4].replace('0x200000000', '0x300000000'), trace[5],
                           'munmap(0x300000000, 256) = 0'] + trace[6:]]
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
    print('json-normalize-controls ' + ' '.join(groups) + ' (host-only corpus/model; no native evidence)')


GROUPS = dict(model=model, admission=admission, limits=limits, io=io)
if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in GROUPS
        group = sys.argv[1]; runner = Runner(sys.argv[2], group)
        allocations = GROUPS[group](runner) or 0
        print(f'json-normalize-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
