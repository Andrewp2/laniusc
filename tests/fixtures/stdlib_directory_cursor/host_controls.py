"""Fast negative controls for the cursor oracle; no compiler/native probe runs."""
import copy
import importlib.util
from pathlib import Path
import tempfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location('cursor_control_oracle', HERE / 'oracle.py')
ORACLE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ORACLE)


def rejects(function):
    try:
        function()
    except (AssertionError, ValueError, KeyError):
        return
    raise AssertionError('mutant was accepted')


def main():
    count = 0
    with tempfile.TemporaryDirectory(prefix='cursor-observer-controls-') as name:
        directory = Path(name)
        pairs = ORACLE.SOURCE.RuntimePairs([(0x110, 0x120)])
        pairs.mmap_flags = {0x110: 0x22}
        pairs.source_syscall_sites = {0x110, 0x120, 0x130}
        pairs.bootstrap_sites = {}
        pairs.image_ranges = [(0x100, 0x200)]
        pairs.executable_ranges = [(0x100, 0x200)]
        profile = (pairs, [])
        mapping = '[110] mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000\n'
        release = '[120] munmap(0x100000000, 32) = 0\n'
        opened = '[130] openat(AT_FDCWD, "\\x72", O_RDONLY|O_DIRECTORY) = 3\n'
        closed = '[130] close(3) = 0\n'
        good = mapping + opened + closed + release
        assert len(ORACLE.resources(good, profile, directory)) == 4
        count += 1
        mutants = [mapping + opened + release, mapping + opened + closed,
                   good + closed, good.replace(', 32) = 0', ', 31) = 0'),
                   good.replace('[130]', '[140]', 1), good + release,
                   mapping + opened + opened + closed + release,
                   good.replace('MAP_PRIVATE|MAP_ANONYMOUS', 'MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT'),
                   good.replace('close(3) = 0', 'close(3) = -1 EIO (Input/output error)')]
        for mutant in mutants:
            rejects(lambda: ORACLE.resources(mutant, profile, directory))
            count += 1
        failed = '[130] close(3) = -1 EIO (Input/output error) (INJECTED)\n'
        q = '[130] write(2, "\\x51", 1) = 1\n'
        end_q = '[130] write(2, "\\x71", 1) = 1\n'
        repaired = mapping + opened + failed + q + closed + end_q + release
        ORACLE.resources(repaired, profile, directory, repair=1)
        count += 1
        for mutant in [repaired.replace(q, ''), repaired.replace(closed, ''),
                       repaired.replace('close(3) = 0', 'close(4) = 0')]:
            rejects(lambda: ORACLE.resources(mutant, profile, directory, repair=1))
            count += 1
        root = directory / 'root'
        root.mkdir()
        (root / 'file').write_bytes(b'')
        expected = ORACLE.snapshot(root)
        root_identity = ORACLE.identity(root.stat())
        def event(kind, path=b'', depth=0, mode=0, value=root_identity, fd=3, parent=0):
            return dict(event=kind, path=path, name=path, depth=depth, mode=mode,
                        inode=value[0], major=value[1], minor=value[2], fd=fd,
                        parent=parent, work=10, entries=1, status=0)
        reports = [event(2, mode=root.stat().st_mode),
                   event(1, b'file', 1, (root / 'file').stat().st_mode, expected[b'file'][1], parent=3),
                   event(3, mode=root.stat().st_mode), event(0), event(0)]
        reports[0]['entries'] = 0
        class Model:
            def __init__(self, records):
                self.root, self.expected, self.records = root, expected, records
            def command(self, operation):
                assert operation == 1
                return self.records.pop(0)
            def fd_identity(self, fd):
                assert fd == 3
                return root_identity
        def check(records):
            model = Model(copy.deepcopy(records))
            result = ORACLE.walk(model)
            assert result['seen'] == expected and not model.records
        check(reports)
        count += 1
        for index, field, value in [(1, 'parent', 4), (1, 'depth', 2), (1, 'inode', 0),
                                    (1, 'name', b'other'), (2, 'fd', 4), (2, 'path', b'wrong'),
                                    (4, 'work', 11), (0, 'entries', 1), (1, 'entries', 0), (2, 'entries', 2)]:
            mutant = copy.deepcopy(reports)
            mutant[index][field] = value
            rejects(lambda: check(mutant))
            count += 1
        rejects(lambda: check([reports[0], *reports[2:]]))
        count += 1
        metadata_fault = copy.deepcopy(reports)
        metadata_fault[1].update(event=4, fd=1, status=1005)
        def check_metadata_fault(records):
            result = ORACLE.walk(Model(copy.deepcopy(records)), faults=True)
            assert result['seen'] == {} and len(result['faults']) == 1
        check_metadata_fault(metadata_fault)
        count += 1
        for index, value in [(1, 0), (2, 2)]:
            mutant = copy.deepcopy(metadata_fault)
            mutant[index]['entries'] = value
            rejects(lambda: check_metadata_fault(mutant))
            count += 1
        records = [dict(name='getdents64', args='3, [{d_reclen=24}, {d_reclen=24}, {d_reclen=24}], 256', answer='72'),
                   dict(name='getdents64', args='3, [], 256', answer='0')]
        operations = [0, 1, 1, 1, 1, 1, 4, 4, 1]
        work_reports = [event(5), *copy.deepcopy(reports), event(6), event(6), event(6)]
        work_reports[0]['entries'] = 0
        # 24+4+2 constructor; four active next calls; 72 received bytes,
        # three decoded 24-byte records plus one unit each; two read calls;
        # file path/name admission costs 4+4+2. Total 193, independently.
        work_reports[-1]['work'] = 193
        limits = (64, 65536, 4095, 134217728, 24, 0, 0)
        assert ORACLE.work_receipt(records, operations, work_reports, limits) == 193
        count += 1
        for total in (192, 194, 183):
            mutant = copy.deepcopy(work_reports)
            mutant[-1]['work'] = total
            rejects(lambda: ORACLE.work_receipt(records, operations, mutant, limits))
            count += 1
        bad_records = copy.deepcopy(records)
        bad_records[0]['answer'] = '64'
        rejects(lambda: ORACLE.work_receipt(bad_records, operations, work_reports, limits))
        count += 1
        def marker(token):
            return dict(name='write', args='2, "\\x%02x", 1' % ord(token), answer='1')
        first = dict(name='close', args='4', answer='-1 EIO (Input/output error) (INJECTED)', ordinal=3)
        second = dict(name='close', args='3', answer='0', ordinal=4)
        cancellation = [marker('C'), marker('c'), marker('C'), first, second, marker('c'), marker('C'), marker('c')]
        outcomes = [dict(event=5, status=0), dict(event=6, status=11005), dict(event=6, status=0)]
        def check_cancellation(found, answers=outcomes):
            ORACLE.cancellation_close_receipt(found, [0, 4, 4], answers, [3, 4], 3)
        check_cancellation(cancellation)
        count += 1
        for mutant in [cancellation[:4] + cancellation[5:],
                       cancellation[:3] + [second, first] + cancellation[5:],
                       cancellation[:-1] + [second] + cancellation[-1:]]:
            rejects(lambda: check_cancellation(mutant))
            count += 1
        lost_error = copy.deepcopy(outcomes)
        lost_error[1]['status'] = 0
        rejects(lambda: check_cancellation(cancellation, lost_error))
        count += 1
    print('directory-cursor observer controls=%d' % count)


if __name__ == '__main__':
    main()
