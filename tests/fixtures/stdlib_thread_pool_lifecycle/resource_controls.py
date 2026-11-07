"""Negative controls for native pthread source-owner snapshot observation."""
import importlib.util
from pathlib import Path
import tempfile

SPEC = importlib.util.spec_from_file_location('pool_resource_controls', Path(__file__).with_name('resources.py'))
R = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(R)


def rejects(function):
    try:
        function()
    except (AssertionError, ValueError, KeyError):
        return
    raise AssertionError('invalid resource trace accepted')


def main():
    pairs = R.SOURCE.RuntimePairs([(0x110, 0x120)])
    pairs.mmap_flags = {0x110: 0x22}
    pairs.source_syscall_sites = {0x110, 0x120, 0x130}
    pairs.bootstrap_sites = {}
    pairs.image_ranges = [(0x100, 0x200)]
    profile = pairs, []
    alloc = '[110] mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000\n'
    free = '[120] munmap(0x100000000, 32) = 0\n'
    count = 0
    def ledger(text, pid=42, shared=False):
        return R.source_maps(R.decode(text, profile, pid), profile, 42, shared_regions=shared)
    for terminal in ['+++ exited with 0 +++', '[110] +++ exited with 0 +++',
                     '[????????????????] +++ killed by SIGILL +++',
                     '[110] +++ killed by SIGILL (core dumped) +++',
                     '[110] --- SIGILL {si_signo=SIGILL, si_code=ILL_ILLOPN, si_addr=0x110} ---']:
        R.assert_empty(ledger(alloc + free + terminal + '\n')); count += 1
    for terminal in ['[garbage] +++ exited with 0 +++', '+++ killed by SIGILL +++ ignored',
                     '[110] --- SIGILL {unrecognized} ---']:
        rejects(lambda: ledger(alloc + free + terminal + '\n')); count += 1
    assert ledger(alloc)['maps'] == {0x100000000: 32}
    assert ledger(alloc)['peak'] == 32
    R.assert_empty(ledger(alloc + free))
    count += 2
    for text in [free, alloc + free + free, alloc + alloc,
                 alloc + free.replace(', 32)', ', 31)'),
                 alloc.replace('[110]', '[130]'), alloc.replace('[110]', '[140]'),
                 alloc.replace('MAP_PRIVATE', 'MAP_SHARED'), alloc + free.replace('[120]', '[130]'),
                 alloc + free.replace('[120]', '[300]'), alloc.replace('0x100000000', '0xfffffffffffffff0')]:
        rejects(lambda: ledger(text))
        count += 1
    rejects(lambda: ledger(alloc, 43)); count += 1
    rejects(lambda: R.assert_empty(ledger(alloc))); count += 1
    for native in ['[300] munmap(0x100000008, 8) = 0\n',
                   '[300] munmap(0xfffffff8, 48) = 0\n',
                   '[300] mmap(0x100000008, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_FIXED, -1, 0) = 0x100000008\n']:
        rejects(lambda: ledger(alloc + native)); count += 1
    failed = alloc.replace('0x100000000', '-1 ENOMEM (Cannot allocate memory) (INJECTED)')
    assert ledger(failed)['maps'] == {} and len(ledger(failed)['allocations']) == 1
    count += 1
    rejects(lambda: ledger(failed.replace('[110]', '[300]'))); count += 1
    region = '[130] mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_SHARED|MAP_ANONYMOUS, -1, 0) = 0x200000000\n'
    unmap = '[130] munmap(0x200000000, 4096) = 0\n'
    assert ledger(region, shared=True)['map_kinds'] == {0x200000000: 'region'}
    R.assert_empty(ledger(region + unmap, shared=True)); count += 1
    for text, shared in [(region, False), (region.replace('4096', '4095'), True),
                         (region + unmap.replace('[130]', '[120]'), True)]:
        rejects(lambda: ledger(text, shared=shared)); count += 1
    with tempfile.TemporaryDirectory(prefix='thread-resource-controls-') as name:
        prefix = Path(name) / 'trace'
        main = Path(str(prefix) + '.42')
        worker = Path(str(prefix) + '.43')
        report = '[130] write(1, "\\x50", 1) = 1\n'
        main.write_text(alloc + report + free)
        worker.write_text('[300] write(2, "\\x78", 1) = 1\n')
        held = R.read_traces(prefix, profile, 42, checkpoint=b'P')
        assert held['maps'] == {0x100000000: 32} and len(held['per_tid']) == 2
        R.assert_empty(R.read_traces(prefix, profile, 42)); count += 2
        worker.write_text(alloc)
        rejects(lambda: R.read_traces(prefix, profile, 42)); count += 1
        worker.write_text('[140] write(2, "\\x78", 1) = 1\n')
        rejects(lambda: R.read_traces(prefix, profile, 42)); count += 1
        for native in ['[300] munmap(0x100000008, 8) = 0\n',
                       '[300] munmap(0xfffffff8, 48) = 0\n',
                       '[300] mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000008\n']:
            worker.write_text(native)
            rejects(lambda: R.read_traces(prefix, profile, 42)); count += 1
        worker.write_text('[300] munmap(0x100000008, 8) =')
        rejects(lambda: R.read_traces(prefix, profile, 42)); count += 1
    print('thread-pool resource controls=%d' % count)


if __name__ == '__main__':
    main()
