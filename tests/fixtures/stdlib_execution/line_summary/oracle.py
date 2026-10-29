"""Independent LF/CRLF, ASCII-word and Unicode-scalar application model."""
from collections import Counter
from pathlib import Path
import os
import random
import re
import subprocess
import sys
import tempfile

BYTE_CAP = 1048576
LINE_CAP = 65536
HEADER = b'line\tbytes\twords\tlast_word_bytes\tlast_scalar\n'
ERRORS = {
    'arguments': b'line_summary: arguments are not supported\n',
    'argument_read': b'line_summary: could not read arguments\n',
    'utf8': b'line_summary: input is not valid UTF-8\n',
    'bytes': b'line_summary: input exceeds 1048576 bytes\n',
    'lines': b'line_summary: input exceeds 65536 lines\n',
    'reads': b'line_summary: read attempt limit exceeded\n',
    'writes': b'line_summary: write attempt limit exceeded\n',
    'allocation': b'line_summary: allocation failed\n',
    'input': b'line_summary: input operation failed\n',
    'output': b'line_summary: output operation failed\n',
}
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'


def lines(data):
    data.decode('utf-8')
    if not data:
        return []
    pieces = data.split(b'\n')
    result = []
    for index, piece in enumerate(pieces):
        terminated = index + 1 < len(pieces)
        if not terminated and not piece:
            continue
        result.append(piece[:-1] if terminated and piece.endswith(b'\r') else piece)
    return result


def reference(data):
    result = bytearray(HEADER)
    for number, line in enumerate(lines(data), 1):
        # Explicit existing six-byte ASCII predicate; no Unicode splitlines/split.
        words = re.findall(rb'[^\x09-\x0d\x20]+', line)
        last = ord(line.decode('utf-8')[-1]) if line else -1
        result += f'{number}\t{len(line)}\t{len(words)}\t{len(words[-1]) if words else 0}\t{last}\n'.encode('ascii')
    return bytes(result)


def model_cases():
    cases = [
        ('empty', b''), ('one-lf', b'\n'), ('one-crlf', b'\r\n'), ('lone-cr', b'\r'),
        ('repeated-lf', b'\n\n\n'), ('repeated-crlf', b'\r\n\r\n'),
        ('leading', b'\nalpha'), ('trailing', b'alpha\n'), ('cr-before-crlf', b'alpha\r\r\n'),
        ('mixed', b'\nalpha beta\r\n\rgamma\n\ndelta\r'),
        ('nul', b'\0\nA\0 B\0\n'), ('six-ascii-separators', b' a\tb\vc\fd\re \n'),
        ('all-empty-words', b' \t\v\f\r\n'), ('spaces-after-word', b'alpha beta \t'),
        ('non-ascii-space', 'a\u00a0b\u2003c\u2028d\u2029e'.encode()),
        ('unicode-widths', '\0Aé中😀\n😀中éA'.encode()),
        ('combining', 'é e\u0301\n\u0301'.encode()), ('noncharacters', '\ufdd0\ufffe\U0010ffff'.encode()),
        ('word-byte-length', 'ascii é中😀\n'.encode()),
        ('report', 'build started\r\n\ncompiling café\nitems: α β γ\r\nfinished 😀\n'.encode()),
    ]
    for size in (1023, 1024, 1025, 4095, 4096, 4097):
        cases.append((f'long-line-{size}', b'a' * size))
    cases += [('split-scalar', b'a' * 1023 + '😀\n'.encode()),
              ('split-crlf', b'a' * 1023 + b'\r\nb\r\n')]
    rng = random.Random(0x51A1E)
    fragments = ['a', 'xyz', '\0', '\t', '\v', '\f', '\r', '\n', '\r\n', ' ', 'é', '中', '😀', '\u00a0', '\u2028', '\u2029']
    for index in range(16):
        cases.append((f'seeded-{index}', ''.join(rng.choice(fragments) for _ in range(150 + index * 31)).encode()))
    return cases


def ledger(text, *, preflight=False):
    result = []; counts = Counter(); live = {}; consumed = 0; eof = False; started = False
    peak = 0
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        event = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started, ('allocation after publication', line)
            size = int(args.split(',')[1].strip()); event['extent'] = size
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live; live[address] = size
                peak = max(peak, sum(live.values()))
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer
        elif name == 'munmap':
            address, size = args.split(',')
            assert answer == '0' and live.pop(address.strip(), None) == int(size), line
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation or file service', line))
        elif name == 'read':
            assert not preflight and not started and not eof and args.split(',')[0] == '0'
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            remaining = BYTE_CAP - consumed
            assert 0 < requested <= (min(1024, remaining) if remaining else 1), (line, consumed)
            if answer.isdigit():
                got = int(answer); assert got <= requested; consumed += got; eof = got == 0
        elif name == 'write':
            descriptor = int(args.split(',')[0]); assert descriptor in (1, 2)
            requested = int(args.rsplit(',', 1)[1]); event['requested'] = requested
            if descriptor == 1:
                assert not preflight and eof and len(live) == 1, ('publication before admission or with extra owners', line, live)
                started = True
            else:
                assert not live, ('diagnostic before owner retirement', line, live)
            if answer.isdigit():
                assert int(answer) <= requested
            event['descriptor'] = descriptor
        result.append(event)
    assert not live, ('unreleased mappings', live)
    assert counts['read'] <= 16384
    assert sum(x['name'] == 'write' and x.get('descriptor') == 1 for x in result) <= 131072
    assert sum(x['name'] == 'write' and x.get('descriptor') == 2 for x in result) <= 64
    return dict(events=result, consumed=consumed, eof=eof, peak=peak)


class Runner:
    observes = True

    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b'\x7fELF\x02\x01'
        assert int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'line-summary-{group}-'))
        self.count = 0

    def run(self, name, data=b'', *, arguments=(), status=0, output=None, error=None,
            injections=(), preflight=False, closed_stdout=False, closed_stderr=False, directory_stdin=False):
        directory = self.directory / name; directory.mkdir()
        source = directory / 'input'; source.write_bytes(data)
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '16', '-e', 'signal=none',
                   '-e', 'trace=' + TRACE, '-o', str(directory / 'trace')]
        if any(isinstance(position, str) and position.endswith('+') for _, position, _ in injections):
            command[5] = '64'  # Observe the complete selected diagnostic, even when its write fails.
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
        assert result.stderr == (ERRORS[error] if error is not None else b''), (name, result.stderr, error)
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
        for descriptor, published in ((1, result.stdout), (2, result.stderr)):
            confirmed = sum(int(event['answer']) for event in found
                            if event['name'] == 'write' and event['descriptor'] == descriptor and event['answer'].isdigit())
            assert confirmed == len(published), (name, descriptor, confirmed, len(published))
        if preflight:
            assert not any(event['name'] in ('mmap', 'munmap', 'read') for event in found)
        if status == 0:
            assert traced['eof'] and traced['consumed'] == len(data)
        assert source.read_bytes() == data
        self.count += 1
        return traced


def model(runner):
    for name, data in model_cases():
        runner.run(name, data)


def admission(runner):
    for index, args in enumerate(([''], ['--help'], ['-h'], ['--'], ['word'],
                                  [os.fsdecode(b'\xff')], ['x'] * 17, ['x' * 8193])):
        runner.run(f'arguments-{index}', arguments=args, status=2, error='arguments', preflight=True)
    invalid = [b'\x80', b'\xc0\x80', b'\xe0\x80\x80', b'\xf0\x80\x80\x80',
               b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'\xff', b'\xc2', b'\xe2\x82',
               b'\xf0\x9f\x98', b'\xc2 ', b'good\n\xf5\x80\x80\x80']
    for index, data in enumerate(invalid):
        runner.run(f'utf8-{index}', data, status=2, error='utf8')


def limits(runner):
    exact = runner.run('exact-byte-cap', b'a' * BYTE_CAP)
    unicode = runner.run('exact-byte-cap-unicode', b'a' * (BYTE_CAP - 4) + '😀'.encode())
    excess = runner.run('excess-byte-probe', b'a' * (BYTE_CAP + 1), status=2, error='bytes')
    runner.run('invalid-at-byte-cap', b'a' * (BYTE_CAP - 1) + b'\xff', status=2, error='utf8')
    runner.run('exact-line-cap-empty', b'\n' * LINE_CAP)
    runner.run('excess-line-cap-empty', b'\n' * (LINE_CAP + 1), status=2, error='lines')
    runner.run('exact-line-cap-final-lf', b'a\n' * LINE_CAP)
    runner.run('excess-line-cap-final-fragment', b'\n' * LINE_CAP + b'x', status=2, error='lines')
    if runner.observes:
        for traced, probe in ((exact, 0), (unicode, 0), (excess, 1)):
            reads = [event for event in traced['events'] if event['name'] == 'read']
            assert sum(int(event['answer']) for event in reads[:-1]) == BYTE_CAP
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == str(probe)


def io(runner):
    data = b'x' * BYTE_CAP
    base = runner.run('allocation-baseline', data)
    mappings = [event for event in base['events'] if event['name'] == 'mmap']
    assert mappings and mappings[-1]['extent'] == BYTE_CAP
    for old in mappings:
        actual = runner.run(f'oom-{old["ordinal"]}', data, status=4, error='allocation',
                            injections=(('mmap', old['ordinal'], 'ENOMEM'),))
        reached = [event for event in actual['events'] if event['name'] == 'mmap']
        assert [event['args'] for event in reached] == [event['args'] for event in mappings[:old['ordinal']]]
    reads = [event for event in base['events'] if event['name'] == 'read']
    writes = [event for event in base['events'] if event['name'] == 'write' and event['descriptor'] == 1]
    assert len(reads) > 1 and len(writes) > 1
    runner.run('read-first-eio', data, status=3, error='input', injections=(('read', reads[0]['ordinal'], 'EIO'),))
    runner.run('read-after-prefix-eio', data, status=3, error='input', injections=(('read', reads[1]['ordinal'], 'EIO'),))
    runner.run('read-eintr', data, injections=(('read', reads[0]['ordinal'], 'EINTR'),))
    runner.run('write-first-eio', data, status=3, error='output', injections=(('write', writes[0]['ordinal'], 'EIO'),))
    prefix = sum(int(event['answer']) for event in writes[:1])
    runner.run('write-after-prefix-eio', data, status=3, output=reference(data)[:prefix], error='output',
               injections=(('write', writes[1]['ordinal'], 'EIO'),))
    runner.run('write-eintr', data, injections=(('write', writes[0]['ordinal'], 'EINTR'),))
    runner.run('write-zero', data, status=3, error='output', injections=(('write', writes[0]['ordinal'], 'retval=0'),))
    runner.run('diagnostic-eio', arguments=['bad'], status=3, preflight=True, injections=(('write', 1, 'EIO'),))
    runner.run('diagnostic-eintr', arguments=['bad'], status=2, error='arguments', preflight=True,
               injections=(('write', 1, 'EINTR'),))
    runner.run('allocation-and-diagnostic-eio', data, status=3,
               injections=(('mmap', mappings[0]['ordinal'], 'ENOMEM'), ('write', 1, 'EIO')))
    runner.run('signal-eio', status=3, preflight=True, injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('signal-eio-closed-stderr', status=3, preflight=True, closed_stderr=True,
               injections=(('rt_sigaction', 1, 'EIO'),))
    runner.run('closed-stdout', b'valid\n', status=3, error='output', closed_stdout=True)
    runner.run('directory-stdin', status=3, error='input', directory_stdin=True)
    runner.run('read-call-budget', status=2, error='reads', injections=(('read', '1..16384', 'EINTR'),))
    # strace's finite LAST is at most65534. Continuous injection reaches the
    # full payload budget but also fails diagnostics, which honestly yields3.
    for name, content, prefix, start in (('write-call-budget', b'', b'', '1+'),
                                         ('write-budget-after-header', b'row\n', HEADER, '2+')):
        traced = runner.run(name, content, status=3, output=prefix,
                            injections=(('write', start, 'EINTR'),))
        writes = [event for event in traced['events'] if event['name'] == 'write']
        payload = [event for event in writes if event['descriptor'] == 1]
        diagnostic = [event for event in writes if event['descriptor'] == 2]
        assert len(payload) == 131072 and len(diagnostic) == 64
        assert writes == payload + diagnostic
        for event in diagnostic:
            quoted = event['args'].split(',')[1].strip()
            assert quoted.startswith('"') and quoted.endswith('"')
            requested = bytes.fromhex(quoted[1:-1].replace('\\x', ''))
            assert requested == ERRORS['writes'] and event['requested'] == 43
            assert event['answer'].startswith('-1 EINTR ') and 'INJECTED' in event['answer']
    runner.run('diagnostic-call-budget', arguments=['bad'], status=3, preflight=True,
               injections=(('write', '1..64', 'EINTR'),))
    return len(mappings)


def controls():
    assert lines(b'') == [] and lines(b'\n') == [b'']
    assert lines(b'\r\n\nA\rB\r\nC\r') == [b'', b'', b'A\rB', b'C\r']
    assert reference(b'\r\nA\0 \xc3\xa9\rB\r\nx\r') == HEADER + b'1\t0\t0\t0\t-1\n2\t7\t3\t1\t66\n3\t2\t1\t1\t13\n'
    assert reference('a\u00a0b\u2028c'.encode()) == HEADER + b'1\t8\t1\t8\t99\n'
    assert len(model_cases()) == 44
    good = 'mmap(NULL, 16, X, Y, -1, 0) = 0x100000000\nread(0, "", 1) = 0\nwrite(1, "x", 1) = 1\nmunmap(0x100000000, 16) = 0\n'
    assert ledger(good)['peak'] == 16
    bad = (good.replace('read(0, "", 1) = 0\n', ''),
           good.replace('munmap(0x100000000, 16) = 0\n', ''),
           good.replace('munmap(0x100000000, 16)', 'munmap(0x100000000, 15)'))
    for text in bad:
        try:
            ledger(text)
        except AssertionError:
            pass
        else:
            raise AssertionError('broken resource/admission trace accepted')
    class CountOnly:
        observes = False
        def __init__(self):
            self.count = 0
        def run(self, *args, **kwargs):
            self.count += 1
    for function, wanted in ((model, 44), (admission, 20), (limits, 8)):
        counter = CountOnly(); function(counter); assert counter.count == wanted
    print('line-summary CPU controls passed; model=44 admission=20 limits=8 io=19+A')


if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        group, executable = sys.argv[1:]
        runner = Runner(executable, group)
        extra = {'model': model, 'admission': admission, 'limits': limits, 'io': io}[group](runner)
        print(f'line-summary-{group} cases={runner.count} reached_allocations={extra or 0} evidence={runner.directory}')
