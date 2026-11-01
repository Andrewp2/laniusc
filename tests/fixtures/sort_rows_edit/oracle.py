"""Focused real CSV consumer model and finite owner/failure observations."""
from collections import Counter
import csv
import importlib.util
from io import StringIO
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

SPEC = importlib.util.spec_from_file_location('sort_rows_reference', Path(__file__).resolve().parents[1] / 'stdlib_execution/sort_rows/oracle.py')
OLD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OLD)
encode, integer = OLD.encode, OLD.integer
INPUT = 4 << 20
TRACE = 'read,write,mmap,munmap,mremap,brk,openat,close,rt_sigaction'
COUNTS = {'model': 22, 'admission': 17, 'cli': 26}
ERROR = b'sort-rows: operation failed\n'


def model_rows(rows, *, column=1, numeric=False, descending=False, header=False,
               drop=False, unique=False, limit=None):
    if not rows:
        return []
    assert 1 <= column <= len(rows[0]) and all(len(row) == len(rows[0]) for row in rows)
    leading, data = (rows[:1], rows[1:]) if header else ([], rows)
    # Validate every numeric key before any selection. The model uses Python's
    # stable sorting and a set of seen keys, not the vector editing algorithms.
    keyed = [(integer(row[column - 1]) if numeric else row[column - 1].encode(), row) for row in data]
    selected = [(key, row) for key, row in keyed if not drop or row[column - 1] != '']
    selected = sorted(selected, key=lambda item: item[0], reverse=descending)
    result, seen = [], set()
    for key, row in selected:
        if not unique or key not in seen:
            result.append(row)
        seen.add(key)
    return leading + (result if limit is None else result[:limit])


def arguments(options):
    result = ['--column', str(options.get('column', 1))]
    for key, flag in [('numeric', '--numeric'), ('descending', '--descending'), ('header', '--header'),
                      ('drop', '--drop-empty'), ('unique', '--unique')]:
        if options.get(key):
            result.append(flag)
    if options.get('limit') is not None:
        result += ['--limit', str(options['limit'])]
    return result


def model_cases():
    rows = [['b', 'first-b'], ['', 'first-empty'], ['a', 'first-a'], ['b', 'second-b'],
            ['a', 'second-a'], ['', 'second-empty'], ['c', 'last']]
    result = []
    for bits in range(8):
        result.append((f'text-combination-{bits}', rows, dict(drop=bool(bits & 1), unique=bool(bits & 2), descending=bool(bits & 4)), None))
    numeric = [['01', 'first-one'], ['-0', 'first-zero'], ['+1', 'second-one'], ['0', 'second-zero'],
               ['-2', 'negative'], ['10', 'ten']]
    for descending in (False, True):
        for header in (False, True):
            result.append((f'numeric-{descending}-{header}', ([['number', 'label']] if header else []) + numeric,
                           dict(numeric=True, descending=descending, header=header, unique=True, drop=True, limit=3), None))
    quoted = [['é\nline', 'first'], ['e\u0301', 'decomposed'], ['', 'empty'], ['é\nline', 'second'],
              ['a,b', 'comma'], ['a"b', 'quote'], ['\r', 'carriage'], ['🙂', 'emoji']]
    result += [
        ('unicode-quoted-header', [['key', 'id']] + quoted, dict(header=True, drop=True, unique=True, limit=4), None),
        ('unicode-quoted-descending', quoted, dict(drop=True, unique=True, descending=True, limit=5), None),
        ('selected-second-column', [['z', '2'], ['first', '1'], ['second', '+1'], ['third', '-1']], dict(column=2, numeric=True, unique=True), None),
        ('dedup-before-limit', rows, dict(drop=True, unique=True, limit=2), None),
        ('empty-all-options', [], dict(drop=True, unique=True, limit=0), None),
        ('all-empty-dropped', [[''], [''], ['']], dict(drop=True, unique=True, limit=1), b'\n\r\n""'),
        ('header-only-limit-zero', [['', 'id']], dict(header=True, drop=True, unique=True, limit=0), None),
        ('header-kept-limit-zero', [['key', 'id']] + rows, dict(header=True, drop=True, unique=True, limit=0), None),
        ('unterminated-final-record', [['b', 'first'], ['a', 'second'], ['b', 'third']], dict(unique=True, limit=2), b'b,first\na,second\nb,third'),
        ('whitespace-is-not-empty', [[' ', 'space'], ['', 'empty'], [' ', 'duplicate'], ['a', 'letter']], dict(drop=True, unique=True), None),
    ]
    return result


def ledger(text, *, preflight=False, help_output=False):
    found, counts, live = [], Counter(), {}
    arguments_live = None; latest = None; input_owner = None; output_owner = None
    eof = False; started = False; consumed = 0; next_generation = 0
    for line in text.splitlines():
        match = re.fullmatch(r'([a-z0-9_]+)\((.*)\)\s+=\s+(.*)', line)
        assert match and match[1] in TRACE.split(','), line
        name, args, answer = match.groups(); counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        if name == 'mmap':
            assert not started, ('allocation during stdout', line)
            item['size'] = int(args.split(',')[1])
            if answer.startswith('0x'):
                address = answer.split()[0]; assert address not in live
                next_generation += 1; latest = (address, item['size'], next_generation)
                live[address] = latest; item['owner'] = latest
            else:
                assert answer.startswith('-1 ENOMEM ') and 'INJECTED' in answer, line
        elif name == 'munmap':
            address, size = args.split(','); address = address.strip()
            owner = live.pop(address, None)
            assert answer == '0' and owner and owner[1] == int(size), line
        elif name in ('mremap', 'brk', 'openat', 'close'):
            raise AssertionError(('unexpected allocation or descriptor service', line))
        elif name == 'read':
            assert not preflight and not started and not eof and args.split(',')[0] == '0', line
            if arguments_live is None:
                arguments_live = set(live.values())
            current = set(live.values())
            assert arguments_live <= current, ('argv retired before input/processing', line)
            remaining_owners = current - arguments_live
            assert len(remaining_owners) <= 1
            input_owner = next(iter(remaining_owners), None)
            requested = int(args.rsplit(',', 1)[1]); item['requested'] = requested
            remaining = INPUT - consumed
            assert 0 < requested <= (min(1024, remaining) if remaining else 1), (line, consumed)
            if answer.isdigit():
                got = int(answer); assert got <= requested
                consumed += got; eof = got == 0
        elif name == 'write':
            descriptor = int(args.split(',')[0]); requested = int(args.rsplit(',', 1)[1])
            item.update(descriptor=descriptor, requested=requested)
            assert descriptor in (1, 2) and 0 < requested <= 1024
            current = set(live.values())
            if arguments_live is None:
                # Before input, only the argument snapshot may own mappings.
                arguments_live = current.copy()
            if descriptor == 1:
                if help_output:
                    assert not eof and current == arguments_live
                else:
                    assert not preflight and eof
                    if not started:
                        output_owner = latest
                    assert output_owner and output_owner != input_owner
                    assert current == arguments_live | {output_owner}, ('only argv and staged output may survive stdout', line, current)
                    assert input_owner not in current
                started = True
            else:
                assert current <= arguments_live, ('non-argv owner survives diagnostic', line, current)
            if answer.isdigit():
                assert int(answer) <= requested
        elif name == 'rt_sigaction':
            assert not found and args.startswith('SIGPIPE,') and 'SIG_IGN' in args
        found.append(item)
    assert not live, ('unreleased mappings', live)
    assert counts['rt_sigaction'] == 1 and counts['read'] <= 16384
    assert sum(item['name'] == 'write' and item['descriptor'] == 1 for item in found) <= (64 if help_output else 16384)
    assert sum(item['name'] == 'write' and item['descriptor'] == 2 for item in found) <= 8
    return dict(events=found, consumed=consumed, eof=eof)


class Runner:
    observes = True

    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:20]
        assert header[:6] == b'\x7fELF\x02\x01' and int.from_bytes(header[16:18], 'little') == 2 and int.from_bytes(header[18:20], 'little') == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f'sort-rows-edit-{group}-'))
        self.count = 0; self.denials = 0

    def run(self, label, args=(), data=b'', *, output=b'', status=0, preflight=False, help_output=False,
            injections=(), closed_stdout=False, diagnostic=True):
        directory = self.directory / label; directory.mkdir()
        source = directory / 'input'; source.write_bytes(data)
        command = ['strace', '--kill-on-exit', '-qq', '-xx', '-s', '64', '-e', 'signal=none',
                   '-e', 'trace=' + TRACE, '-o', str(directory / 'trace')]
        for call, position, failure in injections:
            command += ['-e', f'inject={call}:error={failure}:when={position}']
        command += [self.executable, *args]
        (directory / 'command').write_text(repr(command) + '\n')
        with source.open('rb') as incoming:
            if closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    actual = subprocess.run(command, stdin=incoming, stdout=writer, stderr=subprocess.PIPE, timeout=30)
                finally:
                    os.close(writer)
                actual.stdout = b''
            else:
                actual = subprocess.run(command, stdin=incoming, capture_output=True, timeout=30)
        for name, value in [('stdout', actual.stdout), ('stderr', actual.stderr)]:
            (directory / name).write_bytes(value)
        (directory / 'status').write_text(str(actual.returncode) + '\n')
        assert (actual.returncode, actual.stdout, actual.stderr) == (status, output, ERROR if status and diagnostic else b''), (label, actual.returncode, actual.stdout[:120], actual.stderr)
        evidence = ledger((directory / 'trace').read_text(), preflight=preflight, help_output=help_output)
        marked = [item for item in evidence['events'] if 'INJECTED' in item['answer']]
        for call, position, failure in injections:
            if '..' in str(position):
                first, last = map(int, str(position).split('..')); positions = range(first, last + 1)
            else:
                positions = [int(position)]
            selected = [item for item in marked if item['name'] == call and item['ordinal'] in positions]
            assert len(selected) == len(positions) and all(item['answer'].startswith('-1 ' + failure + ' ') for item in selected), (label, call, position)
        assert len(marked) == sum((int(str(position).split('..')[1]) - int(str(position).split('..')[0]) + 1) if '..' in str(position) else 1 for _, position, _ in injections)
        confirmed = sum(int(item['answer']) for item in evidence['events'] if item['name'] == 'write' and item['descriptor'] == 1 and item['answer'].isdigit())
        assert confirmed == len(output), (label, confirmed, len(output))
        self.count += 1
        return evidence

    def model(self, name, rows, options, data=None, args=None):
        return self.run(name, arguments(options) if args is None else args,
                        encode(rows) if data is None else data, output=encode(model_rows(rows, **options)))


def model(r):
    for name, rows, options, data in model_cases():
        r.model(name, rows, options, data)


def admission(r):
    flags = ['--drop-empty', '--unique', '--limit=0']
    invalid = [b'a,ok\nb\n', b'a,ok\n"unfinished', b'a,ok\nq,"bad"tail\n', b'a,\xff\n',
               b'a,"\x00"\n', b'a,"\t"\n', b'a,\x7f\n', b'x' * 8193 + b'\n']
    for index, data in enumerate(invalid):
        r.run(f'limit-zero-still-validates-{index}', flags, data, status=2)
    for index, data in enumerate((b'\n1\n', b'1\nnot-a-number\n', b'1\n9223372036854775808\n')):
        r.run(f'numeric-before-selection-{index}', [*flags, '--numeric'], data, status=2)
    r.run('selected-column-before-limit', [*flags, '--column=2'], b'one\n', status=2)
    rows = [[str(index)] for index in range(16383, -1, -1)]
    r.model('maximum-data-rows-with-edits', rows, dict(numeric=True, unique=True, drop=True, limit=16384))
    r.run('data-cap-not-bypassed', flags, b'x\n' * 16385, status=2)
    r.run('unique-work-admission-before-limit', flags, (b'x' * 2440 + b'\n') * 512, status=2)
    cap_rows, cap = OLD.exact_cap_input()
    for excess in (False, True):
        result = r.run('real-input-cap-' + str(excess), [*flags, '--numeric'], cap + (b'x' if excess else b''), status=2 if excess else 0)
        if r.observes:
            reads = [item for item in result['events'] if item['name'] == 'read']
            assert reads[-1]['requested'] == 1 and reads[-1]['answer'] == ('1' if excess else '0')
            assert sum(int(item['answer']) for item in reads[:-1]) == INPUT


def cli(r):
    invalid = [
        ['--drop-empty', '--drop-empty'], ['--unique', '--unique'], ['--limit=1', '--limit', '2'],
        ['--drop-empty=yes'], ['--unique=yes'], ['--limit'], ['--limit='], ['--limit=-1'],
        ['--limit=+1'], ['--limit=16385'], ['--limit=18446744073709551616'], ['--limit= 1'],
        ['--limit=1 '], ['--limit=1.0'], ['--limit=١'], ['-u'], ['-l1'],
        ['--help', '--unique', '--unique'], ['--help', '--limit=0', '--limit=0'],
        ['--help', '--drop-empty=yes'], ['--limit', '--unique'], ['--unique', 'operand'],
    ]
    for index, args in enumerate(invalid):
        r.run(f'bad-option-{index}', args, b'input must not be read', status=2, preflight=True)
    r.run('help-new-options', ['--drop-empty', '--unique', '--limit=0', '--help'], output=OLD.HELP, preflight=True, help_output=True)
    r.model('limit-leading-zero', [['b'], ['a'], ['a']], dict(unique=True, limit=1), args=['--unique', '--limit', '0001'])
    r.model('maximum-limit-valid', [['b'], ['a']], dict(drop=True, limit=16384), args=['--limit=16384', '--drop-empty'])
    r.model('empty-after-end-options', [], dict(drop=True, unique=True, limit=0), args=['--unique', '--limit=0', '--drop-empty', '--'])


def io(r):
    rows = [['key', 'payload'], ['', 'drop' * 20], ['b', 'b' * 550], ['a', 'a' * 550],
            ['b', 'duplicate'], ['c', 'truncate'], ['a', 'other duplicate'], ['', 'drop again']]
    options = dict(header=True, drop=True, unique=True, limit=2)
    args, data, wanted = arguments(options), encode(rows), encode(model_rows(rows, **options))
    baseline = r.run('owner-baseline', args, data, output=wanted)
    if not r.observes:
        return
    maps = [item for item in baseline['events'] if item['name'] == 'mmap']
    for item in maps:
        ordinal = item['ordinal']
        denied = r.run(f'oom-{ordinal}', args, data, status=4, injections=[('mmap', ordinal, 'ENOMEM')])
        actual_maps = [event for event in denied['events'] if event['name'] == 'mmap']
        assert [event['args'] for event in actual_maps] == [event['args'] for event in maps[:ordinal]]
        assert actual_maps[-1]['answer'].startswith('-1 ENOMEM ')
        r.denials += 1
    r.run('read-interrupted', args, data, output=wanted, injections=[('read', 1, 'EINTR')])
    partial = r.run('second-read-eio', args, data, status=3, injections=[('read', 2, 'EIO')])
    assert next(item for item in partial['events'] if item['name'] == 'read')['answer'] == '1024'
    r.run('write-interrupted', args, data, output=wanted, injections=[('write', 1, 'EINTR')])
    r.run('first-write-eio', args, data, status=5, injections=[('write', 1, 'EIO')])
    writes = [item for item in baseline['events'] if item['name'] == 'write' and item['descriptor'] == 1]
    assert len(writes) >= 2 and writes[0]['answer'] == '1024'
    r.run('second-write-eio-real-prefix', args, data, status=5, output=wanted[:1024], injections=[('write', 2, 'EIO')])
    r.run('closed-stdout', args, data, status=5, closed_stdout=True)
    r.run('signal-setup-failure', args, data, status=5, injections=[('rt_sigaction', 1, 'EIO')], diagnostic=False)
    r.run('write-call-bound-prefix', args, data, status=5, output=wanted[:1024], injections=[('write', '2..16384', 'EINTR')])
    r.run('diagnostic-failure-keeps-primary', ['--limit=-1'], status=2, preflight=True,
          injections=[('write', 1, 'EIO')], diagnostic=False)
    assert r.count == 10 + r.denials


def controls():
    class Control:
        observes = False
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, name, rows, options, data=None, args=None):
            raw = encode(rows) if data is None else data
            actual = [row or [''] for row in csv.reader(StringIO(raw.decode(), newline=''), strict=True)]
            assert actual == rows, name
            expected = model_rows(rows, **options)
            assert list(csv.reader(StringIO(encode(expected).decode(), newline=''), strict=True)) == expected
            self.count += 1
    for mode in COUNTS:
        runner = Control(); globals()[mode](runner); assert runner.count == COUNTS[mode], (mode, runner.count)
    assert model_rows([['1', 'first'], ['+1', 'second'], ['2', 'two']], numeric=True, unique=True, descending=True) == [['2', 'two'], ['1', 'first']]
    assert model_rows([['a'], ['a'], ['b']], unique=True, limit=2) == [['a'], ['b']]
    try:
        model_rows([['']], numeric=True, drop=True, limit=0)
    except AssertionError:
        pass
    else:
        raise AssertionError('numeric validation must precede filtering')
    mapping = lambda address, size: f'mmap(NULL, {size}, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = {address}\n'
    release = lambda address, size: f'munmap({address}, {size}) = 0\n'
    signal = 'rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN}, NULL, 8) = 0\n'
    good = (signal + mapping('0x1000', 40) + 'read(0, "x", 1024) = 1\n' + mapping('0x2000', 4)
            + 'read(0, "", 1024) = 0\n' + mapping('0x3000', 16) + mapping('0x4000', 100)
            + release('0x3000', 16) + release('0x2000', 4) + 'write(1, "x", 1) = 1\n'
            + release('0x4000', 100) + release('0x1000', 40))
    assert ledger(good)['eof']
    corruptions = [good.replace(release('0x3000', 16), ''),
                   good.replace(release('0x3000', 16), '').replace('write(1, "x", 1) = 1\n', 'write(1, "x", 1) = 1\n' + release('0x3000', 16)),
                   good.replace(release('0x2000', 4), '').replace('write(1, "x", 1) = 1\n', 'write(1, "x", 1) = 1\n' + release('0x2000', 4)),
                   good.replace('munmap(0x4000, 100)', 'munmap(0x4000, 99)'),
                   good.replace('write(1, "x", 1) = 1\n', 'write(2, "x", 1) = 1\n'),
                   good.replace('read(0, "", 1024) = 0\n', '')]
    for trace in corruptions:
        try:
            ledger(trace)
        except AssertionError:
            pass
        else:
            raise AssertionError('owner observer accepted corrupted evidence')
    assert 4 * 512 * 10 * 4882 <= 100000000 < (4 * 512 * 10 + 511) * 4882
    print('sort-rows-edit host controls passed; model=22 admission=17 cli=26 io=10+A')


if __name__ == '__main__':
    if sys.argv[1:] == ['controls']:
        controls()
    else:
        group, executable = sys.argv[1:]
        runner = Runner(executable, group); globals()[group](runner)
        assert runner.count == (10 + runner.denials if group == 'io' else COUNTS[group])
        print(f'sort-rows-edit-{group} cases={runner.count} reached_allocations={runner.denials} evidence={runner.directory}')
