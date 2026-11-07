"""Independent finite worker results, real join ownership, and source extents."""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time

SPEC = importlib.util.spec_from_file_location('pool_lifecycle_resources', Path(__file__).with_name('resources.py'))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)
MAGIC = 1347374924
MASK = (1 << 64) - 1
MOD = 1000000007
THREAD_EVENT = re.compile(rb'thread-probe (init|setstack|create|destroy|join) (\d+) (\d+) (\d+)\n')


def read_exact(stream, count, allow_eof=False):
    output = bytearray()
    deadline = time.monotonic() + 6
    while len(output) < count:
        left = deadline - time.monotonic()
        assert left > 0 and select.select([stream], [], [], left)[0], ('report timeout', len(output), count)
        piece = os.read(stream.fileno(), count - len(output))
        if allow_eof and not piece and not output: return None
        assert piece, ('partial report', len(output), count)
        output.extend(piece)
    return bytes(output)


def signed(value):
    return value if value < (1 << 63) else value - (1 << 64)


def decode(raw):
    words = struct.unpack('<32Q', raw)
    assert words[0] == MAGIC, words
    names = ('magic', 'mode', 'phase', 'status', 'open', 'workers', 'submitted', 'completed', 'total',
             'created', 'joined', 'live', 'joins', 'pid', 'entered', 'exited')
    item = dict(zip(names, words[:16]))
    assert item['created'] <= 8 and item['joins'] <= 8
    item.update(ids=words[16:16 + item['created']], attempts=words[24:24 + item['joins']], raw=raw)
    assert item['live'] == item['created'] - item['joined'], item
    return item


def reference(mode, count, grain, workers):
    values = [(index * 17 + 3) % 101 for index in range(count)]
    if mode == 0:
        return sum(((index * 7) % 19 - 7) * 3 + 1 for index in range(count)), [1] * count
    if mode == 1:
        assert count == workers
        return workers, [value * 3 + 1 for value in values]
    if mode == 2:
        return chunks(count, grain, workers), [value * 3 + 5 for value in values]
    if mode == 3:
        value, power = 0, 1
        for element in values:
            value, power = (value * 31 + element) % MOD, (power * 31) % MOD
        return (value, power), values
    output, total = [], 0
    for value in values:
        total += value
        output.append(total)
    return chunks(count, grain, workers), output


def chunks(count, grain, workers):
    if not count: return 0
    if grain <= 0: grain = max(2048, count // (workers * 8))
    return (count - 1) // grain + 1


def shim_events(stderr):
    records = [dict(kind=match[1].decode(), ordinal=int(match[2]), result=int(match[3]), identity=int(match[4]))
               for match in THREAD_EVENT.finditer(stderr)]
    markers = THREAD_EVENT.sub(b'', stderr)
    assert re.fullmatch(rb'[IiCcRUSsu]*', markers), ('unexpected stderr', stderr, markers)
    counts = Counter()
    for record in records:
        counts[record['kind']] += 1
        assert record['ordinal'] == counts[record['kind']], record
    return records, markers


class Suite:
    def __init__(self, group, executable):
        self.group, self.executable = group, Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix='thread-pool-' + group + '-'))
        self.profile = R.verified_sites(self.executable)
        self.count, self.started, self.active = 0, time.monotonic(), None

    def case(self, label, mode=0, workers=3, count=17, grain=4, create=0, join=0, hold=0,
             admission=0, expected=0, inject=None, trap=False):
        assert time.monotonic() - self.started < 72, 'finite pool group exceeded 72 seconds'
        directory = self.directory / ('%03d-' % self.count + label)
        self.count += 1
        directory.mkdir()
        prefix = directory / 'syscalls'
        request = (mode, workers, count, grain, create, join, hold, admission)
        command = ['strace', '--kill-on-exit', '-ff', '-qq', '-i', '-xx', '-v', '-s', '65536',
                   '-e', 'signal=none', '-e', 'trace=mmap,munmap,write,exit_group', '-o', str(prefix),
                   '-E', 'LANIUS_ALLOC=mmap', '-E', 'LANIUS_THREAD_PROBE_TRACE=1']
        if inject: command += ['-e', 'inject=mmap:error=ENOMEM:when=' + str(inject)]
        command.append(str(self.executable))
        (directory / 'request.bin').write_bytes(struct.pack('<8Q', *(value & MASK for value in request)))
        (directory / 'command.txt').write_text(repr(command) + '\n')
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.active = process
        process.stdin.write((directory / 'request.bin').read_bytes())
        reports, snapshots, bodies = [], {}, {}
        while True:
            raw = read_exact(process.stdout, 256, allow_eof=True)
            if raw is None: break
            report = decode(raw)
            assert report['mode'] == mode and report['phase'] not in snapshots, report
            body = []
            if report['phase'] == 2:
                body = list(struct.unpack('<%dq' % count, read_exact(process.stdout, count * 8))) if count else []
            snapshot = R.read_traces(prefix, self.profile, report['pid'], checkpoint=raw)
            reports.append(report); snapshots[report['phase']] = snapshot; bodies[report['phase']] = body
            if report['phase'] == 0:
                assert report['created'] == 0 and report['joins'] == 0
                assert len(snapshot['maps']) == (1 if mode == 0 else 2)
            elif report['phase'] == 1:
                assert mode == 0 and report['status'] == expected, report
                if report['open']:
                    assert all(snapshot['maps'].get(at) == size for at, size in snapshots[0]['maps'].items())
                    assert len(snapshot['maps']) > len(snapshots[0]['maps'])
                    if expected != 0:
                        startup = snapshot['main_events'][len(snapshots[0]['main_events']):]
                        assert not [entry for entry in startup if entry['authority'] == 'source' and entry['name'] == 'munmap'], 'partial startup retired retained source storage'
                    if hold:
                        assert report['entered'] == 0 and report['exited'] == 0
                        assert len(os.listdir('/proc/%d/task' % report['pid'])) > 1, 'held real worker absent'
                else:
                    assert expected != 0 and report['live'] == 0 and snapshot['maps'] == snapshots[0]['maps'], report
            elif report['phase'] == 2:
                assert report['status'] == expected, report
                if expected == 0:
                    result, values = reference(mode, count, grain, workers)
                    assert body == values, (label, body, values)
                    if mode == 0:
                        assert (report['submitted'], report['completed'], signed(report['total'])) == (count, count, result), report
                        assert snapshot['maps'] == snapshots[1]['maps'], 'task execution changed source owners'
                    elif mode == 3:
                        assert (report['open'], report['workers']) == result, report
                    else:
                        assert report['open'] == result, report
                if mode != 0:
                    assert report['live'] == 0 and report['created'] == report['joined'], report
                    assert snapshot['maps'] == snapshots[0]['maps'], 'synchronous call retained its allocations'
                    if mode == 1 and expected == 1011:
                        original = [(index * 17 + 3) % 101 for index in range(count)]
                        started = report['created']
                        wanted = original[:count - started] + [value * 3 + 1 for value in original[count - started:]]
                        assert body == wanted, ('scoped partial startup lost completed real work', body, wanted)
            elif report['phase'] == 3:
                assert mode == 0 and join and report['status'] == 1016 and report['open'] == 1, report
                assert report['live'] == 1 and report['joined'] == report['created'] - 1, report
                assert snapshot['maps'] == snapshots[1]['maps'], 'failed join released worker backing'
                shutdown = snapshot['main_events'][len(snapshots[1]['main_events']):]
                assert not [entry for entry in shutdown if entry['authority'] == 'source' and entry['name'] == 'munmap'], 'failed shutdown freed then replaced retained storage'
            elif report['phase'] == 4:
                assert mode == 0 and report['status'] == 0 and report['open'] == 0 and report['live'] == 0, report
                assert [report[key] for key in ('workers', 'submitted', 'completed', 'total')] == [100004] * 4, report
                assert snapshot['maps'] == snapshots[0]['maps'], 'retired pool leaked storage or freed caller backing'
            elif report['phase'] == 9:
                R.assert_empty(snapshot)
                assert report['live'] == 0, report
                assert len(os.listdir('/proc/%d/task' % report['pid'])) == 1, 'worker remained at cleanup checkpoint'
            else:
                raise AssertionError(report)
            process.stdin.write(b'!')
        output, stderr = process.communicate(timeout=6)
        assert not output, output
        self.active = None
        assert reports and reports[0]['phase'] == 0, reports
        complete = R.read_traces(prefix, self.profile, reports[0]['pid'])
        records, markers = shim_events(stderr)
        (directory / 'stderr.bin').write_bytes(stderr)
        creates = [record for record in records if record['kind'] == 'create']
        joins = [record for record in records if record['kind'] == 'join']
        if trap:
            assert process.returncode == -signal.SIGILL, ('expected join-failure trap', process.returncode, stderr)
            assert list(snapshots) == [0] and b'R' not in markers and b'U' not in markers, (markers, reports)
            successful = [record for record in creates if record['result'] == 0]
            identities = tuple(record['identity'] for record in successful)
            assert identities and all(identities) and len(set(identities)) == len(identities), records
            assert tuple(record['identity'] for record in joins) == identities, ('trap did not attempt every actual join owner once', records)
            assert [record['result'] for record in joins] == [16 if index + 1 == join else 0 for index in range(len(identities))], records
            held = next(record for record in successful if record['ordinal'] == hold)
            assert joins[join - 1]['identity'] == held['identity'], ('join fault missed held real worker', records, hold)
            assert all(complete['maps'].get(at) == size for at, size in snapshots[0]['maps'].items())
            assert len(complete['maps']) > len(snapshots[0]['maps']), 'trap lost pending call storage'
            api_events = complete['main_events'][len(snapshots[0]['main_events']):]
            assert not [entry for entry in api_events if entry['authority'] == 'source' and entry['name'] == 'munmap'], 'source backing retired before failed-join trap'
        else:
            assert process.returncode == 0 and reports[-1]['phase'] == 9, (process.returncode, reports, stderr)
            R.assert_empty(complete)
            successful = [record for record in creates if record['result'] == 0]
            assert len(successful) == reports[-1]['created'] and len([record for record in joins if record['result'] == 0]) == len(successful)
            if mode == 0 and successful:
                identities = tuple(record['identity'] for record in successful)
                assert len(set(identities)) == len(identities)
                expected_attempts = identities + ((identities[join - 1],) if join else ())
                assert reports[-1]['attempts'] == expected_attempts, ('successful join retried or pending join omitted', reports[-1], expected_attempts)
                assert tuple(record['identity'] for record in joins) == expected_attempts
                assert Counter(record['identity'] for record in joins if record['result'] == 0) == Counter(identities)
            if mode != 0 and expected == 0 and count and workers > 1 and not create:
                assert successful, 'parallel operation used no real worker'
        if create:
            assert len([record for record in creates if record['ordinal'] == create and record['result'] == 11]) == 1, records
        if join:
            assert len([record for record in joins if record['ordinal'] == join and record['result'] == 16]) == 1, records
        if inject:
            reached = [entry for entry in complete['events'] if 'INJECTED' in entry['answer']]
            assert len(reached) == 1 and reached[0]['authority'] == 'source' and reached[0]['name'] == 'mmap' and reached[0]['ordinal'] == inject, reached
        return dict(reports=reports, snapshots=snapshots, complete=complete, records=records)

    def model(self):
        for workers, count in [(1, 0), (1, 17), (3, 65), (4, 32)]:
            self.case('pool-%d-%d' % (workers, count), workers=workers, count=count)
        self.case('held-timeout-recovery', workers=1, count=17, hold=1)
        self.case('scoped', mode=1, workers=3, count=3)
        for mode in (2, 3, 4):
            for count, workers, grain in [(0, 4, 4), (17, 1, 3), (65, 4, 7)]:
                self.case('operation-%d-%d-%d' % (mode, count, workers), mode=mode, count=count, workers=workers, grain=grain)
        for mode in (2, 3, 4):
            self.case('spawn-fallback-%d' % mode, mode=mode, workers=4, count=17, create=2)

    def lifecycle(self):
        for fail in (1, 2, 3):
            self.case('partial-start-%d' % fail, workers=4, count=17, create=fail, expected=1011)
        self.case('partial-start-join-retry', workers=4, count=17, create=3, join=1, hold=1, expected=1011)
        self.case('shutdown-join-retry', workers=3, count=17, join=1, hold=1)
        self.case('shutdown-empty-join-retry', workers=1, count=0, join=1, hold=1)
        self.case('scoped-partial-start', mode=1, workers=3, count=3, create=2, expected=1011)

    def admission(self):
        for workers in (0, 257):
            self.case('pool-workers-%d' % workers, workers=workers, count=0, expected=1)
        self.case('pool-null-entry', count=0, admission=1, expected=1)
        self.case('pool-invalid-capacity', count=0, admission=2, expected=2000)
        for mode in (1, 2, 3, 4):
            self.case('bad-workers-%d' % mode, mode=mode, workers=0, count=3, expected=1)
            self.case('null-entry-%d' % mode, mode=mode, workers=3, count=3, admission=1, expected=1)
        self.case('scoped-stride-overflow', mode=1, workers=3, count=3, admission=4, expected=2)
        self.case('map-length-mismatch', mode=2, workers=3, count=3, admission=2, expected=1)
        for mode in (2, 3, 4):
            self.case('null-storage-%d' % mode, mode=mode, workers=3, count=3, admission=3, expected=1)
            self.case('caller-only-null-entry-%d' % mode, mode=mode, workers=1, count=3, admission=1)
            self.case('empty-null-entry-%d' % mode, mode=mode, workers=3, count=0, admission=1)

    def resources(self):
        for mode in range(5):
            count = 3 if mode == 1 else 17
            baseline = self.case('baseline-%d' % mode, mode=mode, workers=3, count=count)
            initial = len(baseline['snapshots'][0]['allocations'])
            targets = baseline['complete']['allocations'][initial:]
            assert targets, ('no source allocation reached owning API', mode)
            for allocation in targets:
                self.case('oom-%d-%d' % (mode, allocation['ordinal']), mode=mode, workers=3, count=count,
                          inject=allocation['ordinal'], expected=3)

    def traps(self):
        for mode in (1, 2, 3, 4):
            self.case('join-trap-%d' % mode, mode=mode, workers=3, count=3 if mode == 1 else 17,
                      join=1, hold=1, trap=True)
        self.case('scoped-partial-start-join-trap', mode=1, workers=3, count=3, create=3, join=1, hold=1, trap=True)


def main():
    group, executable = sys.argv[1:]
    suite = Suite(group, executable)
    try:
        getattr(suite, group)()
        print('thread-pool group=%s cases=%d' % (group, suite.count))
    except BaseException:
        print('thread pool artifacts retained at ' + str(suite.directory), file=sys.stderr)
        if suite.active is not None and suite.active.poll() is None:
            suite.active.kill(); suite.active.communicate(timeout=6)
        raise
    else:
        shutil.rmtree(suite.directory)


if __name__ == '__main__':
    main()
