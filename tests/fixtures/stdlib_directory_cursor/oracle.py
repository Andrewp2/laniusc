"""Finite native cursor cases, OS model, paused mutations, and source owners.

The Python code is an observer/fixture builder; traversal runs in Lanius. Reports
are binary, not a library transport. Sibling order is deliberately unconstrained.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import shutil
import socket
import stat
import struct
import subprocess
import sys
import tempfile
import time


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[1]
SOURCE = load('cursor_native_source_authority', FIXTURES / 'native_c/source_allocations.py')
OWNERS = load('cursor_source_owners', FIXTURES / 'stdlib_execution/temp_file/ledger.py')
TRACE = 'read,write,mmap,munmap,openat,close,statx,getdents64,getpid'
MAGIC = 1463897163
DEFAULT = (64, 65536, 4095, 134217728, 256, 0, 0)
U64 = (1 << 64) - 1


def read_exact(stream, count):
    result = bytearray()
    deadline = time.monotonic() + 5
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], ('report timeout', len(result), count)
        chunk = os.read(stream.fileno(), count - len(result))
        assert chunk, ('premature report EOF', len(result), count)
        result.extend(chunk)
    return bytes(result)


def decode(header, tail):
    words = struct.unpack('<16Q', header)
    assert words[0] == MAGIC and words[10] + words[11] == len(tail), (words, len(tail))
    keys = ('magic', 'event', 'status', 'depth', 'fd', 'parent', 'mode', 'inode',
            'major', 'minor', 'length', 'name_length', 'work', 'entries', 'pid', 'anchor')
    item = dict(zip(keys, words))
    item.update(path=tail[:words[10]], name=tail[words[10]:], header=header)
    assert item['event'] in range(8) and item['length'] <= 1048576, item
    return item


def identity(value):
    return value.st_ino, os.major(value.st_dev), os.minor(value.st_dev)


def reported_identity(item):
    return item['inode'], item['major'], item['minor']


def snapshot(root):
    found = {}
    for parent, directories, files in os.walk(os.fsencode(root), followlinks=False):
        for name in directories + files:
            path = os.path.join(parent, name)
            value = os.lstat(path)
            found[os.path.relpath(path, os.fsencode(root))] = (stat.S_IFMT(value.st_mode), identity(value))
    return found


def events(text, profile):
    found, memory, counts = [], [], Counter()
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match and match[2] in TRACE.split(','), ('unsupported trace event', line)
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
    return found, ''.join(memory)


def resources(text, profile, directory, *, repair=None):
    found, memory = events(text, profile)
    OWNERS.source_maps(memory, profile, directory)
    live, generations, opened, closes, phase = {}, Counter(), [], [], None
    for item in found:
        name, answer = item['name'], item['answer'].split()[0]
        args = OWNERS.arguments(item['args'])
        if name == 'write' and item['args'] in ('2, "\\x51", 1', '2, "\\x71", 1'):
            phase = 'repair' if '\\x51' in item['args'] else None
        if name == 'openat' and answer.isdecimal():
            fd = int(answer)
            assert fd not in live and fd >= 3, ('overlapping fd generation', item, live)
            generations[fd] += 1
            live[fd] = (generations[fd], item)
            opened.append(item)
        elif name == 'close':
            fd = int(args[0])
            assert fd in live, ('unowned/repeated close', item, live)
            item['generation'] = live[fd][0]
            item['repair'] = phase == 'repair'
            closes.append(item)
            if answer == '0':
                live.pop(fd)
            else:
                assert repair == item['ordinal'] and 'INJECTED' in item['answer'], ('unexpected failed close', item)
                assert item['answer'].startswith('-1 EIO '), item
    assert not live, ('fds survived explicit cleanup', live)
    if repair is not None:
        failed = [item for item in closes if item['ordinal'] == repair]
        assert len(failed) == 1 and not failed[0]['repair'], failed
        matching = [item for item in closes if item['repair'] and item['args'] == failed[0]['args']
                    and item['generation'] == failed[0]['generation']]
        assert len(matching) == 1 and matching[0]['answer'] == '0', (failed, matching)
    return found


def command_frames(found, operations):
    """Bind source calls to the probe's explicit command frames."""
    operation = iter(operations)
    frames, active = [], None
    for entry in found:
        if entry['name'] == 'write' and entry['args'] == '2, "\\x43", 1':
            assert active is None
            active = dict(operation=next(operation), body=[])
        elif entry['name'] == 'write' and entry['args'] == '2, "\\x63", 1':
            assert active is not None
            frames.append(active)
            active = None
        elif active is not None:
            active['body'].append(entry)
    assert active is None and list(operation) == [], operations
    return frames


def work_receipt(found, operations, reports, limits):
    """Compute complete ordinary-walk work from native records and API events.

    This does not use a reported work delta to choose the expected answer.
    getdents64 return bytes and record extents come from the authorized trace;
    published names have separately been checked against the filesystem model.
    """
    assert len(operations) == len(reports) and limits[5:] == (0, 0)
    assert reports[0]['event'] == 5 and reports[0]['entries'] == 0
    work = limits[4] + len(b'root') + 2
    admitted, opened_dirs, closed, exhausted = 0, 0, False, False
    for operation, report in zip(operations[1:], reports[1:]):
        if operation == 4:
            closed = True
        if operation != 1 or closed or exhausted:
            continue
        assert report['event'] in (0, 1, 2, 3), report
        work += 1
        if report['event'] == 0:
            exhausted = True
        elif report['event'] == 1:
            admitted += 1
            work += len(report['path']) + len(report['name']) + 2
        elif report['event'] == 2 and report['depth'] > 0:
            opened_dirs += 1
            work += limits[4] + len(report['path'].rsplit(b'/', 1)[-1]) + 2
    records = 0
    for entry in found:
        if entry['name'] != 'getdents64':
            continue
        received = int(entry['answer'])
        lengths = [int(value) for value in re.findall(r'\bd_reclen=(\d+)', entry['args'])]
        assert received >= 0 and sum(lengths) == received, ('incomplete directory record trace', entry)
        assert all(length >= 24 and length % 8 == 0 for length in lengths), entry
        records += len(lengths)
        work += 1 + received + sum(length + 1 for length in lengths)
    assert exhausted and records == admitted + 2 * (1 + opened_dirs), (records, admitted, opened_dirs)
    assert reports[-1]['work'] == work and reports[-1]['entries'] == admitted, (reports[-1], work, admitted)
    return work


def cancellation_close_receipt(found, operations, reports, active_fds, failed_ordinal):
    """All owners are consumed once even when the first cancellation close fails."""
    frames = command_frames(found, operations)
    assert len(frames) == len(reports) and len(active_fds) > 1
    closes = [(frame, report) for frame, report in zip(frames, reports) if frame['operation'] == 4]
    assert len(closes) >= 2, closes
    first, answer = closes[0]
    attempts = [entry for entry in first['body'] if entry['name'] == 'close']
    assert [int(entry['args']) for entry in attempts] == list(reversed(active_fds)), attempts
    assert attempts[0]['ordinal'] == failed_ordinal and attempts[0]['answer'].startswith('-1 EIO '), attempts
    assert all(entry['answer'] == '0' for entry in attempts[1:]), attempts
    assert (answer['event'], answer['status']) == (6, 11005), answer
    for frame, report in closes[1:]:
        assert frame['body'] == [] and (report['event'], report['status']) == (6, 0), (frame, report)


class Session:
    def __init__(self, suite, label, builder=None, limits=DEFAULT, inject=None):
        assert time.monotonic() - suite.started < 72, 'finite oracle group exceeded 72 seconds'
        self.suite, self.limits, self.inject = suite, limits, inject
        self.directory = suite.directory / ('%03d-' % suite.count + label)
        suite.count += 1
        self.directory.mkdir()
        self.cwd = self.directory / 'cwd'
        self.cwd.mkdir()
        self.root = self.cwd / ('anchor/root' if limits[5] else 'root')
        self.root.mkdir(parents=True)
        (self.cwd / 'regular').write_bytes(b'not a directory')
        if builder:
            builder(self.root)
        self.expected = snapshot(self.root)
        self.trace = self.directory / 'syscalls.log'
        command = ['strace', '-E', 'LANIUS_ALLOC=mmap', '--kill-on-exit', '-qq', '-xx', '-i', '-v', '-s', '65536',
                   '-e', 'signal=none', '-e', 'trace=' + TRACE, '-o', str(self.trace)]
        if inject:
            command += ['-e', 'inject=' + inject[0] + ':error=' + inject[1] + ':when=' + str(inject[2])]
        command.append(str(suite.executable))
        (self.directory / 'command.txt').write_text(repr(command) + '\n')
        self.process = subprocess.Popen(command, cwd=self.cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, bufsize=0)
        suite.active = self
        self.process.stdin.write(struct.pack('<7Q', *(value & U64 for value in limits)))
        self.history = []
        self.operations = [0]
        self.current = self.report()
        self.pid = self.current['pid']
        self.anchor_live = bool(limits[5]) and self.current['event'] == 5
        self.repair = None

    def report(self):
        header = read_exact(self.process.stdout, 128)
        fields = struct.unpack('<16Q', header)
        assert fields[10] + fields[11] <= 1048576, fields
        item = decode(header, read_exact(self.process.stdout, fields[10] + fields[11]))
        if self.history:
            assert item['work'] >= self.history[-1]['work'] and item['entries'] >= self.history[-1]['entries'], item
        self.history.append(item)
        self.current = item
        return item

    def command(self, operation, argument=0):
        counters = self.current['work'], self.current['entries']
        self.operations.append(operation)
        self.process.stdin.write(struct.pack('<2Q', operation, argument & U64))
        result = self.report()
        if operation != 1 or (result['event'] == 6 and result['status'] in (2, 5, 6)):
            assert (result['work'], result['entries']) == counters, ('non-traversal operation changed counters', operation, counters, result)
        if operation == 7:
            self.anchor_live = False
        return result

    def outcome(self, operation, status=0):
        item = self.command(operation)
        assert (item['event'], item['status']) == (6, status), item
        return item

    def fd_identity(self, fd):
        return identity(os.stat('/proc/%d/fd/%d' % (self.pid, fd)))

    def check_no_fds(self):
        actual = {int(value) for value in os.listdir('/proc/%d/fd' % self.pid)} - {0, 1, 2}
        expected = {self.current['anchor']} if self.anchor_live else set()
        assert actual == expected, ('native descriptors at checkpoint', actual, expected, self.current)

    def trace_prefix(self):
        # Require the completed write for this unique checkpoint report; no
        # process-exit cleanup can satisfy the ownership checks that follow.
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            text = self.trace.read_text()
            lines = text.splitlines(keepends=True)
            for index, line in enumerate(lines):
                if not line.endswith('\n'):
                    continue
                match = OWNERS.LINE.fullmatch(line.rstrip('\n'))
                if match and match[2] == 'write' and match[4] == '128':
                    args = OWNERS.arguments(match[3])
                    if args[0] == '1' and OWNERS.quoted(args[1]) == self.current['header']:
                        return ''.join(lines[:index + 1])
            time.sleep(0.002)
        raise AssertionError('completed checkpoint write not observed')

    def finish(self, *, constructor_error=False):
        if not constructor_error:
            self.outcome(4)
            self.outcome(4)
            self.outcome(1, 5)
            self.outcome(2, 5)
            self.outcome(3, 5)
            if self.anchor_live:
                self.outcome(7)
            self.outcome(8, 888)
        self.check_no_fds()
        prefix = self.trace_prefix()
        (self.directory / 'before-exit.trace').write_text(prefix)
        resources(prefix, self.suite.profile, self.directory, repair=self.repair)
        self.process.stdin.write(struct.pack('<2Q', 5, 0))
        output, stderr = self.process.communicate(timeout=5)
        assert self.process.returncode == 0 and output == b'' and re.fullmatch(rb'[CcQq]*', stderr), (self.process.returncode, output, stderr)
        self.suite.active = None
        found = resources(self.trace.read_text(), self.suite.profile, self.directory, repair=self.repair)
        # Each command has one C/c frame. Scheduling decisions may emit the
        # probe markers/report but must not touch allocation or host services.
        for frame in command_frames(found, self.operations):
            if frame['operation'] in (2, 3):
                assert frame['body'] == [], ('decision performed native work', frame)
        if self.inject:
            reached = [item for item in found if 'INJECTED' in item['answer']]
            assert len(reached) == 1 and (reached[0]['name'], reached[0]['ordinal']) == (self.inject[0], self.inject[2]), ('injection did not reach exact source call', self.inject, reached)
        return found


def tree(root):
    (root / 'branch/empty').mkdir(parents=True)
    (root / 'branch/deep').mkdir()
    (root / 'branch/deep/leaf').write_bytes(b'leaf')
    (root / 'branch/file').write_bytes(b'branch')
    (root / 'regular').write_bytes(b'root')
    (root / 'spaced name').write_bytes(b'')
    os.close(os.open(os.fsencode(root) + b'/raw-\xff\n', os.O_CREAT | os.O_WRONLY, 0o600))
    (root / 'link-dir').symlink_to('branch', target_is_directory=True)
    (root / 'link-loop').symlink_to('.')
    (root / 'dangling').symlink_to('absent')
    os.mkfifo(root / 'fifo')
    sock = socket.socket(socket.AF_UNIX)
    sock.bind(str(root / 'socket'))
    sock.close()


def small(root):
    (root / 'child').mkdir()
    (root / 'child/inside').write_bytes(b'child')
    (root / 'sibling').write_bytes(b'sibling')


def walk(session, *, prune=(), decisions=False, faults=False, check_metadata=True):
    stack, seen, entered, left, failures = [], {}, [], [], []
    admitted = 0
    while True:
        item = session.command(1)
        event, path = item['event'], item['path']
        if event == 1 or (event == 4 and item['fd'] == 1):
            admitted += 1
        if event != 6:
            assert item['entries'] == admitted, ('entry admission counter', admitted, item)
        if event == 0:
            assert not stack, stack
            counters = item['work'], item['entries']
            again = session.command(1)
            assert again['event'] == 0 and (again['work'], again['entries']) == counters, again
            break
        if event == 6:
            return dict(seen=seen, entered=entered, left=left, faults=failures, error=item['status'], terminal=item)
        if event == 4:
            assert faults, item
            failures.append(item)
            continue
        if event == 1:
            assert stack and item['depth'] == len(stack) and item['parent'] == stack[-1]['fd'], (item, stack)
            assert path.rsplit(b'/', 1)[-1] == item['name'] and path not in seen, item
            assert session.fd_identity(item['parent']) == reported_identity(stack[-1]), item
            kind = stat.S_IFMT(item['mode'])
            seen[path] = kind, reported_identity(item)
            if check_metadata:
                assert seen[path] == session.expected[path], (path, seen[path], session.expected)
            if kind == stat.S_IFDIR:
                counters = item['work'], item['entries']
                if decisions:
                    blocked = session.outcome(1, 2)
                    assert (blocked['work'], blocked['entries']) == counters
                choice = 3 if path in prune else 2
                selected = session.outcome(choice)
                assert (selected['work'], selected['entries']) == counters
                if decisions:
                    session.outcome(choice, 2)
        elif event == 2:
            assert item['depth'] == len(stack), (item, stack)
            if not stack:
                assert path == b'' and reported_identity(item) == identity(os.stat(session.root)), item
            else:
                parent = path.rsplit(b'/', 1)[0] if b'/' in path else b''
                assert seen[path][0] == stat.S_IFDIR and parent == stack[-1]['path'], item
            assert session.fd_identity(item['fd']) == reported_identity(item), item
            stack.append(item)
            entered.append(path)
        elif event == 3:
            assert stack and path == stack[-1]['path'] and item['fd'] == stack[-1]['fd'], (item, stack)
            assert session.fd_identity(item['fd']) == reported_identity(item), ('Leave fd already closed', item)
            stack.pop()
            left.append(path)
        else:
            raise AssertionError(item)
    return dict(seen=seen, entered=entered, left=left, faults=failures, error=None)


class Suite:
    def __init__(self, group, executable):
        self.group, self.executable = group, Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix='directory-cursor-' + group + '-'))
        self.profile = SOURCE.verified_sites(self.executable, self.directory)
        self.started, self.count, self.active = time.monotonic(), 0, None

    def model(self):
        for label, builder, pruned in [('empty', None, ()), ('tree', tree, ()), ('pruned', tree, (b'branch',))]:
            session = Session(self, label, builder)
            assert session.current['event'] == 5
            session.outcome(2, 2)
            session.outcome(3, 2)
            result = walk(session, prune=pruned, decisions=True)
            expected = {path: value for path, value in session.expected.items()
                        if not any(path.startswith(parent + b'/') for parent in pruned)}
            assert result['seen'] == expected and set(result['entered']) == set(result['left']), result
            found = session.finish()
            if pruned:
                child_opens = [item for item in found if item['name'] == 'openat'
                               and OWNERS.quoted(OWNERS.arguments(item['args'])[1]) == b'branch']
                assert not child_opens, ('prune opened child', child_opens)
        peaks = []
        for count in (16, 160):
            def wide(root):
                for index in range(count):
                    (root / ('item-%03d' % index)).write_bytes(b'')
            session = Session(self, 'wide-refills-%d' % count, wide)
            assert walk(session)['seen'] == session.expected
            found = session.finish()
            assert len([item for item in found if item['name'] == 'getdents64']) > 2
            live, maximum = {}, 0
            for item in found:
                if item['name'] == 'mmap':
                    live[item['answer'].split()[0]] = int(OWNERS.arguments(item['args'])[1])
                    maximum = max(maximum, sum(live.values()))
                elif item['name'] == 'munmap':
                    del live[OWNERS.arguments(item['args'])[0]]
            peaks.append(maximum)
        assert peaks[0] == peaks[1], ('retained heap grew with sibling count', peaks)
        def deep(root):
            for _ in range(12):
                root = root / 'd'
                root.mkdir()
            (root / 'leaf').write_bytes(b'')
        session = Session(self, 'deep', deep)
        result = walk(session)
        assert len(result['entered']) == 13 and result['seen'] == session.expected
        session.finish()

    def limits(self):
        for label, index, value in [('zero-depth', 0, 0), ('too-many-open', 0, 4097),
                                    ('negative-path', 2, -1), ('short-buffer', 4, 23), ('large-buffer', 4, 1048577)]:
            limits = list(DEFAULT); limits[index] = value
            session = Session(self, label, limits=limits)
            assert (session.current['event'], session.current['status']) == (7, 1), session.current
            found = session.finish(constructor_error=True)
            assert not [item for item in found if item['name'] in ('mmap', 'openat', 'statx', 'getdents64')]
        for mode in (4, 5, 6):
            session = Session(self, 'invalid-root-view-%d' % mode, limits=(*DEFAULT[:6], mode))
            assert (session.current['event'], session.current['status']) == (7, 1), session.current
            found = session.finish(constructor_error=True)
            assert not [item for item in found if item['name'] in ('mmap', 'openat', 'statx', 'getdents64')]
        session = Session(self, 'zero-entry-empty', limits=(1, 0, 0, DEFAULT[3], 24, 0, 0))
        assert walk(session)['seen'] == {}
        session.finish()
        def one(root): (root / 'abc').write_bytes(b'')
        for label, limits, expected in [('exact-entry-path', (1, 1, 3, DEFAULT[3], 256, 0, 0), None),
                                        ('entry-cap', (1, 0, 3, DEFAULT[3], 256, 0, 0), 3),
                                        ('path-cap', (1, 1, 2, DEFAULT[3], 256, 0, 0), 3)]:
            session = Session(self, label, one, limits)
            result = walk(session)
            assert result['error'] == expected, result
            counted = 0 if label == 'entry-cap' else 1
            assert session.current['entries'] == counted, (label, session.current)
            assert len(result['seen']) == (0 if expected else 1), result
            if expected:
                session.outcome(1, 6); session.outcome(2, 6); session.outcome(3, 6)
            session.finish()
        session = Session(self, 'depth-cap', small, limits=(1, 100, 4095, DEFAULT[3], 256, 0, 0))
        assert session.command(1)['event'] == 2
        while True:
            item = session.command(1)
            assert item['event'] == 1, item
            if stat.S_ISDIR(item['mode']):
                session.outcome(2, 3)
                break
        session.outcome(1, 6)
        found = session.finish()
        assert len([item for item in found if item['name'] == 'openat']) == 1
        baseline = Session(self, 'work-baseline', one)
        walk(baseline)
        found = baseline.finish()
        used = work_receipt(found, baseline.operations, baseline.history, baseline.limits)
        for label, budget in [('exact-work', used), ('work-short', used - 1), ('constructor-work-short', 261)]:
            limits = list(DEFAULT); limits[3] = budget
            session = Session(self, label, one, limits)
            if budget == 261:
                assert (session.current['event'], session.current['status']) == (7, 3)
                session.finish(constructor_error=True)
            else:
                result = walk(session)
                assert result['error'] == (None if budget == used else 3), result
                assert session.current['work'] <= budget
                session.finish()
        for target in (1, 2, 3):
            session = Session(self, 'cancel-at-%d' % target, small)
            while True:
                item = session.command(1)
                if item['event'] == target and (target != 2 or item['depth'] == 1) and (target != 1 or stat.S_ISDIR(item['mode'])):
                    break
                if item['event'] == 1 and stat.S_ISDIR(item['mode']): session.outcome(2)
            session.finish()

    def mutations(self):
        session = Session(self, 'rename-root', small)
        entered = session.command(1)
        assert entered['event'] == 2
        moved = session.cwd / 'moved'
        session.root.rename(moved)
        session.root.mkdir()
        (session.root / 'wrong-root').write_bytes(b'')
        session.root = moved
        # Consume from the already entered root with the ordinary model by
        # treating this one event as the next event; no directory is reopened.
        original = session.command
        pending = [entered]
        def resumed(operation, argument=0):
            if pending and operation == 1: return pending.pop()
            return original(operation, argument)
        session.command = resumed
        assert walk(session)['seen'] == session.expected
        session.finish()
        session = Session(self, 'borrowed-parent', small, limits=(*DEFAULT[:5], 1, 0))
        anchor = session.current['anchor']
        session.outcome(7)
        assert not Path('/proc/%d/fd/%d' % (session.pid, anchor)).exists()
        assert walk(session)['seen'] == session.expected
        session.finish()
        for replacement in ('directory', 'symlink', 'missing'):
            session = Session(self, 'replace-child-' + replacement, small)
            assert session.command(1)['event'] == 2
            while True:
                item = session.command(1)
                assert item['event'] == 1, item
                if item['path'] == b'child': break
            (session.root / 'child').rename(session.root / 'old-child')
            if replacement == 'directory':
                (session.root / 'child').mkdir()
                (session.root / 'child/wrong').write_bytes(b'')
            elif replacement == 'symlink':
                (session.root / 'child').symlink_to('old-child', target_is_directory=True)
            session.outcome(2)
            failure = session.command(1)
            assert failure['event'] == 4 and failure['path'] == b'child', failure
            assert failure['fd'] == (3 if replacement == 'directory' else 2), failure
            assert (failure['status'] == 21 if replacement == 'directory' else failure['status'] >= 1000), failure
            # Namespace enumeration during mutation is intentionally not a
            # snapshot; only reject entry into the replaced child identity.
            while True:
                item = session.command(1)
                if item['event'] == 0: break
                assert not (item['event'] == 2 and item['path'] == b'child'), item
                if item['event'] == 1 and stat.S_ISDIR(item['mode']): session.outcome(3)
            session.finish()
        def symlink_root(root):
            root.rename(root.parent / 'target')
            root.symlink_to('target', target_is_directory=True)
            (root / 'inside').write_bytes(b'')
        for mode in (0, 1):
            session = Session(self, 'root-symlink-%d' % mode, symlink_root, limits=(*DEFAULT[:6], mode))
            if mode == 0:
                assert session.current['event'] == 7 and session.current['status'] >= 11000, session.current
                session.finish(constructor_error=True)
            else:
                assert walk(session)['seen'] == session.expected
                session.finish()
        for mode in (2, 3):
            session = Session(self, 'root-error-%d' % mode, limits=(*DEFAULT[:6], mode))
            assert session.current['event'] == 7 and session.current['status'] >= 11000, session.current
            session.finish(constructor_error=True)

    def faults(self):
        baseline = Session(self, 'baseline', small)
        assert walk(baseline)['seen'] == baseline.expected
        source = baseline.finish()
        work_receipt(source, baseline.operations, baseline.history, baseline.limits)
        allocations = [item for item in source if item['name'] == 'mmap']
        assert allocations
        for item in allocations:
            session = Session(self, 'oom-%d' % item['ordinal'], small, inject=('mmap', 'ENOMEM', item['ordinal']))
            if session.current['event'] == 7:
                assert session.current['status'] == 4, session.current
                session.finish(constructor_error=True)
            else:
                result = walk(session)
                assert result['error'] == 4, result
                session.outcome(1, 6)
                session.finish()
        # Force stack and retained-path growth beyond the initial capacity.
        # Fault the first reached allocation at each new byte extent, covering
        # growth cleanup without multiplying every identical reader buffer.
        def growing(root):
            for _ in range(5):
                root = root / 'long-child-name'
                root.mkdir()
            (root / 'leaf').write_bytes(b'')
        deep = Session(self, 'growing-baseline', growing)
        assert walk(deep)['seen'] == deep.expected
        deep_source = deep.finish()
        known_extents = {int(OWNERS.arguments(item['args'])[1]) for item in allocations}
        for item in deep_source:
            if item['name'] != 'mmap': continue
            extent = int(OWNERS.arguments(item['args'])[1])
            if extent in known_extents: continue
            known_extents.add(extent)
            session = Session(self, 'growing-oom-%d' % item['ordinal'], growing,
                              inject=('mmap', 'ENOMEM', item['ordinal']))
            assert session.current['event'] == 5, session.current
            result = walk(session)
            assert result['error'] == 4, result
            session.outcome(1, 6)
            session.finish()
        # Global syscall ordinals come from the baseline, then each injection
        # must be observed at an authorized source instruction in its own run.
        for syscall in ('openat', 'statx', 'getdents64'):
            for item in [item for item in source if item['name'] == syscall]:
                session = Session(self, '%s-%d' % (syscall, item['ordinal']), small,
                                  inject=(syscall, 'EIO', item['ordinal']))
                if session.current['event'] == 7:
                    assert session.current['status'] == 11005, session.current
                    session.finish(constructor_error=True)
                else:
                    result = walk(session, faults=True)
                    assert result['error'] is None and len(result['faults']) == 1, result
                    failure = result['faults'][0]
                    assert failure['status'] == 1005, result
                    expected_stage = {'openat': 2, 'getdents64': 4}.get(syscall)
                    if syscall == 'statx':
                        expected_stage = 3 if OWNERS.quoted(OWNERS.arguments(item['args'])[1]) == b'' else 1
                    assert failure['fd'] == expected_stage, (failure, item)
                    if failure['path'] == b'child' or failure['path'].startswith(b'child/'):
                        assert b'sibling' in result['seen'], ('child failure lost sibling', result)
                    assert session.current['entries'] == len(result['seen']) + (1 if expected_stage == 1 else 0), result
                    assert set(result['entered']) == set(result['left']), result
                    session.finish()
        # strace's injected close skips the real syscall. Repair that same fd
        # generation explicitly after observing the cursor's one-attempt Fault;
        # this proves owner invalidation, not actual kernel release on EIO.
        close = next(item for item in source if item['name'] == 'close')
        session = Session(self, 'close-once', small, inject=('close', 'EIO', close['ordinal']))
        leaves, failures = {}, []
        while True:
            item = session.command(1)
            if item['event'] == 0: break
            if item['event'] == 1 and stat.S_ISDIR(item['mode']): session.outcome(2)
            if item['event'] == 3: leaves[item['path']] = item['fd']
            if item['event'] == 4:
                assert item['fd'] == 5 and item['status'] == 1005, item
                failures.append(item)
                session.command(6, leaves[item['path']])
        assert len(failures) == 1
        session.repair = close['ordinal']
        session.finish()
        # Cancellation is a different path from advancing after Leave: close
        # every active frame despite EIO and return that first error. The host
        # repairs only strace's deliberately skipped kernel close afterward.
        session = Session(self, 'cancel-close-once', small, inject=('close', 'EIO', close['ordinal']))
        active_fds = []
        while len(active_fds) < 2:
            item = session.command(1)
            if item['event'] == 2:
                active_fds.append(item['fd'])
            elif item['event'] == 1 and stat.S_ISDIR(item['mode']):
                session.outcome(2)
            else:
                assert item['event'] == 1, item
        session.outcome(4, 11005)
        remaining = {int(value) for value in os.listdir('/proc/%d/fd' % session.pid)} - {0, 1, 2}
        assert remaining == {active_fds[-1]}, ('cancellation failed to close other active readers', remaining, active_fds)
        session.outcome(4)
        session.outcome(1, 5)
        session.command(6, active_fds[-1])
        session.repair = close['ordinal']
        found = session.finish()
        cancellation_close_receipt(found, session.operations, session.history, active_fds, close['ordinal'])


def main():
    group, executable = sys.argv[1:]
    suite = Suite(group, executable)
    try:
        getattr(suite, group)()
        print('directory-cursor group=%s cases=%d' % (group, suite.count))
    except BaseException:
        print('cursor artifacts retained at ' + str(suite.directory), file=sys.stderr)
        if suite.active is not None and suite.active.process.poll() is None:
            suite.active.process.kill()
            suite.active.process.communicate(timeout=5)
        raise
    else:
        shutil.rmtree(suite.directory)


if __name__ == '__main__':
    main()
