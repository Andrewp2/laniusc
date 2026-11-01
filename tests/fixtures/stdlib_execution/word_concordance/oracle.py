"""Independent UTF-8 word/byte-position model and application resource evidence."""
from collections import Counter
from pathlib import Path
import random
import os
import re
import subprocess
import sys
import tempfile

BYTE_CAP = 1048576
WORD_CAP = 65536
INPUT_CALLS = 16384
WRITE_CALLS = 131072
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'


def reference(data):
    data.decode('utf-8')
    words = {}
    for match in re.finditer(rb'[^ \t\r\n\v\f]+', data):
        words.setdefault(match[0], []).append(match.start())
    return b''.join(word + b'\t' + b','.join(str(at).encode() for at in words[word]) + b'\n'
                    for word in sorted(words))


def model_cases():
    cases = [
        ('empty', b''), ('all-ascii-space', b' \t\r\n\v\f'), ('one-word', b'word'),
        ('one-repeat', b'word word'), ('sorted', b'z a m z A'),
        ('separators', b'one\ttwo\rthree\nfour\vfive\fsix'),
        ('punctuation', b'a,b a.b a,b "a" \\'), ('nul', b'a\0b a\0b \0'),
        ('nonspace-controls', b'\0\x01\x08\x0e\x1f\x7f'),
        ('unicode', 'é a é 🙂 a\n'.encode()),
        ('unicode-whitespace-is-word-content', 'a\u00a0b a\u2003b a\u0085b\n'.encode()),
        ('no-unicode-normalization', 'é e\u0301 é'.encode()),
        ('prefix-keys', b'a aa aaa aa a aaaa'), ('leading-trailing', b' \talpha\nalpha\r\n'),
        ('key-case', b'Z z A a Z'), ('positions-not-scalar-counts', '🙂é x 🙂é x'.encode()),
    ]
    for size in (1023, 1024, 1025, 4095, 4096, 4097):
        # One key plus TAB, decimal zero and LF produces exactly size bytes.
        cases.append((f'exact-output-size-{size}', b'a' * (size - 3)))
    rng = random.Random(0xC0AC0D)
    words = ['a', 'bb', 'é', '🙂', 'a,b', '\0x', 'e\u0301', 'x\u00a0y']
    spaces = [' ', '\t', '\r\n', '\v', '\f', '  ']
    for index in range(6):
        text = ''.join(rng.choice(words) + rng.choice(spaces) for _ in range(25 + index * 7))
        cases.append((f'seeded-mixture-{index}', text.encode()))
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
            assert not started and not input_retired, ('allocation after publication/input retirement', line)
            size = int(args.split(',')[1].strip()); event['extent'] = size
            event['phase'] = 'index' if eof else 'input'
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live; live[address] = size
                peak = max(peak, sum(live.values()))
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name == 'munmap':
            address, size = args.split(','); address = address.strip()
            assert answer == '0' and live.pop(address, None) == int(size), line
            if eof and address == input_address:
                assert not input_retired and not live, ('borrowed-key input retired before other owners', line, live)
                input_retired = True
            if started:
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
            assert args.split(',')[0] == '1', ('concordance must remain silent on stderr', line)
            assert not preflight and eof and not input_retired and input_address in live and len(live) >= 3 and not retiring, ('publication before admission or after owner retirement', line, live)
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
    assert counts['read'] <= INPUT_CALLS and counts['write'] <= WRITE_CALLS
    return dict(events=events, consumed=consumed, eof=eof, peak=peak, input_retired=input_retired)


class Runner:
    observes = True

    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b'\x7fELF\x02\x01'
        assert int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'word-concordance-{group}-'))
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
    for name, data in (('invalid-byte', b'ok \xff'), ('surrogate', b'\xed\xa0\x80'),
                       ('too-high', b'\xf4\x90\x80\x80'), ('truncated', b'valid \xe2\x82')):
        traced = runner.run(name, data, status=2)
        if runner.observes:
            assert traced['eof'] and traced['consumed'] == len(data)


def limits(runner):
    exact = runner.run('exact-byte-cap-one-key', b'a' * BYTE_CAP)
    excess = runner.run('excess-byte-probe', b'a' * (BYTE_CAP + 1), status=2)
    empty = runner.run('exact-byte-cap-whitespace', b' ' * BYTE_CAP)
    expanded = runner.run('large-position-expansion', b'a ' * (BYTE_CAP // 2))
    distinct = b' '.join(f'w{index:04x}'.encode() for index in range(WORD_CAP))
    runner.run('exact-distinct-word-cap', distinct)
    rejected = runner.run('excess-distinct-word-cap', distinct + b' w10000', status=2)
    if runner.observes:
        for traced, probe in ((exact, 0), (empty, 0), (expanded, 0), (excess, 1)):
            reads = [event for event in traced['events'] if event['name'] == 'read']
            assert sum(int(event['answer']) for event in reads[:-1]) == BYTE_CAP
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == str(probe)
        assert rejected['eof'] and rejected['input_retired']
        assert not any(event['name'] == 'write' for event in rejected['events'])
        assert len(reference(b'a ' * (BYTE_CAP // 2))) > 3 * BYTE_CAP


def io(runner):
    payload = b' '.join([b'gamma', b'alpha', b'beta', b'alpha', b'delta', b'epsilon', b'zeta'] * 32)
    data = b' ' * (BYTE_CAP - len(payload)) + payload
    base = runner.run('allocation-baseline', data)
    mappings = [event for event in base['events'] if event['name'] == 'mmap']
    assert mappings
    if runner.observes:
        assert {event['phase'] for event in mappings} == {'input', 'index'}
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
    prefix = int(writes[0]['answer']); assert prefix == 1024
    runner.run('write-after-prefix-eio', data, status=3, output=reference(data)[:prefix], injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('write-would-block', data, status=3, injections=(('write', writes[0]['ordinal'], 'EAGAIN'),))
    runner.run('write-eintr', data, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('write-zero', data, status=3, injections=(('write', writes[0]['ordinal'], 'retval=0'),))
    runner.run('signal-eio', status=3, preflight=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('signal-eio-closed-stderr', status=3, preflight=True, closed_stderr=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('closed-stdout', b'valid', status=3, closed_stdout=True)
    runner.run('closed-stdout-empty-output', b' \n', closed_stdout=True)
    runner.run('closed-stderr-invalid-input', b'\xff', status=2, closed_stderr=True)
    runner.run('directory-stdin', status=3, directory_stdin=True)
    read_limit = runner.run('read-call-limit', b'word', status=2, injections=(('read', f'1..{INPUT_CALLS}', 'EINTR'),))
    first = runner.run('write-call-limit', payload, status=2, injections=(('write', '1+', 'EINTR'),))
    after = runner.run('write-call-limit-after-prefix', data, status=2, output=reference(data)[:prefix], injections=(('write', '2+', 'EINTR'),))
    if runner.observes:
        assert sum(event['name'] == 'read' for event in read_limit['events']) == INPUT_CALLS
        # This app budgets actual writes only, unlike the JSON Copier app.
        assert sum(event['name'] == 'write' for event in first['events']) == WRITE_CALLS
        assert sum(event['name'] == 'write' for event in after['events']) == WRITE_CALLS
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
            assert len(expected) <= 8388608
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
    assert reference(b'pear apple pear\n') == b'apple\t5\npear\t0,11\n'
    assert reference('é a é 🙂 a\n'.encode()) == 'a\t3,13\né\t0,5\n🙂\t8\n'.encode()
    assert reference('a\u00a0b a\u00a0b'.encode()) == 'a\u00a0b\t0,5\n'.encode()
    assert len(model_cases()) == 28
    trace = [
        'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0',
        'mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000',
        'read(0, "word", 1024) = 4', 'read(0, "", 1024) = 0',
        'mmap(NULL, 256, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000',
        'mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x300000000',
        'write(1, "word\\t0\\n", 7) = 7', 'munmap(0x300000000, 32) = 0',
        'munmap(0x200000000, 256) = 0', 'munmap(0x100000000, 1024) = 0',
    ]
    assert ledger('\n'.join(trace))['input_retired']
    broken = [trace[:-1], trace[:6] + [trace[-1]] + trace[6:-1],
              trace[:7] + [trace[4].replace('0x200000000', '0x400000000')] + trace[7:],
              trace[:-1] + [trace[-1].replace('1024', '1023')],
              trace[:8] + [trace[6]] + trace[8:]]
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
    print('word-concordance-controls ' + ' '.join(groups) + ' (host-only corpus/model; no native evidence)')


GROUPS = dict(model=model, admission=admission, limits=limits, io=io)
if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in GROUPS
        group = sys.argv[1]; runner = Runner(sys.argv[2], group)
        allocations = GROUPS[group](runner) or 0
        print(f'word-concordance-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}')
