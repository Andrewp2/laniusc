#!/usr/bin/env python3
"""Independent Python csv oracle, process checks and syscall fault injection."""
import csv
import io
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MODE, EXE = sys.argv[1], sys.argv[2]


def canonical(fields):
    if not fields:  # A zero-field Record is no record in the Lanius API.
        return b''
    stream = io.StringIO(newline='')
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator='\r\n').writerow(fields)
    output = stream.getvalue().encode('utf-8')
    assert list(csv.reader(io.StringIO(output.decode(), newline=''))) == [fields]
    return output


def matrix():
    cases = [[], [''], ['', ''], ['plain'], ['a,b', 'a"b'], ['\r', '\n', '\r\n'],
             ['é', '世界', '🙂'], ['\ufeff', '\ufffe', '\U0010ffff'], [' spaces ', '', '"'],
             ['é"\n' * 1024, 'tail'], ['x' * 1023], ['x' * 1024], ['x' * 1025],
             ['é' * 511 + '"' + '🙂' * 600], [''] * 129]
    dictionary = ['', 'a', '"', ',', '\r', '\n', 'é', '🙂', '世界', ' ', '"\r\n,']
    rng = random.Random(0xC5A4180)
    for _ in range(128):
        cases.append([''.join(rng.choice(dictionary) for _ in range(rng.randrange(12)))
                      for _ in range(rng.randrange(17))])
    for fields in cases:
        result = subprocess.run([EXE, *fields], capture_output=True, timeout=5)
        assert result.returncode == 0 and not result.stderr, (fields, result)
        assert result.stdout == canonical(fields), (fields, result)
    invalid = [b'\t', b'\x01', b'\x1f', b'\x7f', b'\xff', b'\xc0\x80', b'\xe2\x82',
               b'\xed\xa0\x80', b'\xf4\x90\x80\x80', b'ab\x80', b'valid\r\nbad\t']
    for data in invalid:
        result = subprocess.run([os.fsencode(EXE), b'earlier valid', data], capture_output=True, timeout=5)
        assert result.returncode == 2 and not result.stdout and not result.stderr, (data, result)
    print(f'csv-write-matrix valid={len(cases)} invalid={len(invalid)} seed=0xc5a4180')


def execute(trace, fail=None, calls='mmap,munmap'):
    command = ['strace', '-qq', '-o', str(trace), '-e', 'trace=' + calls]
    if fail is not None:
        command += ['-e', f'inject=mmap:error=ENOMEM:when={fail}']
    command.append(EXE)
    return subprocess.run(command, capture_output=True, timeout=10)


def ledger(trace):
    live = {}; positions = []; ordinal = 0; failed = 0
    for line in trace.splitlines():
        mapped = re.match(r'mmap\((.*)\)\s+= (\S+)(.*)$', line)
        if mapped:
            ordinal += 1
            args, address, suffix = mapped.groups()
            flags = args.split(', ')[3]
            if 'MAP_32BIT' not in flags:
                continue
            count = int(args.split(', ')[1]); positions.append(ordinal)
            if address.startswith('0x'):
                assert address not in live, line
                live[address] = count
            else:
                assert address == '-1' and 'ENOMEM' in suffix and 'INJECTED' in suffix, line
                failed += 1
            continue
        freed = re.match(r'munmap\((0x[0-9a-f]+), (\d+)\)\s+= (\S+)', line)
        if freed:
            address, count, result = freed.groups()
            if address in live:
                assert result == '0' and live.pop(address) == int(count), line
    assert not live, (live, trace)
    return positions, failed


def allocations():
    with tempfile.TemporaryDirectory(prefix='lanius_csv_write_alloc_') as directory:
        trace = Path(directory)/'trace'
        baseline = execute(trace)
        assert baseline.returncode == 0 and not baseline.stdout and not baseline.stderr, baseline
        positions, failed = ledger(trace.read_text())
        assert len(positions) == 6 and failed == 0, trace.read_text()
        for position in positions:
            result = execute(trace, position)
            _, failures = ledger(trace.read_text())
            assert result.returncode == 4 and not result.stdout and not result.stderr and failures == 1, (position, result, trace.read_text())
        print(f'csv-write-allocation positions={len(positions)} balanced=true strong_capacity_and_view_guarantee=true')


def noalloc():
    with tempfile.TemporaryDirectory(prefix='lanius_csv_write_reuse_') as directory:
        trace = Path(directory)/'trace'
        result = execute(trace, calls='mmap,munmap,write')
        assert result.returncode == 0 and result.stdout == b'BE' and not result.stderr, result
        text = trace.read_text()
        first = text.index('write(1, "B", 1)')
        last = text.index('write(1, "E", 1)')
        assert first < last and 'mmap(' not in text[first:last] and 'munmap(' not in text[first:last], text
        positions, failed = ledger(text)
        assert len(positions) == 2 and failed == 0, text
        print('csv-write-reuse records=4096 allocations_after_warmup=0 flushes=0 balanced=true')


globals()[MODE]()
