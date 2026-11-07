"""Source-owned mmap snapshots for pure-worker native pthread fixtures.

Allocation remains in Lanius. Current sized source/runtime authority classifies
every observed syscall in every TID. These fixtures allocate and retire source
owners on the main thread; worker-side source allocation is rejected explicitly.
Native pthread/loader/CRT mappings are not counted as Lanius-owned allocations.
"""
from collections import Counter
import importlib.util
from pathlib import Path
import re
import time


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[1]
SOURCE = load('pool_native_source_authority', FIXTURES / 'native_c/source_allocations.py')
verified_sites = SOURCE.verified_sites
LINE = re.compile(r'^\[([0-9a-fA-F]+)\]\s+([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$')
# With -i, strace also prefixes terminal records with the final instruction
# pointer (or question marks after a thread disappears).
TERMINAL = re.compile(r'^(?:\[(?:[0-9a-fA-F]+|\?+)\]\s+)?\+\+\+ (?:exited with \d+|killed by SIG[A-Z0-9]+(?: \(core dumped\))?) \+\+\+$')
ILLEGAL_INSTRUCTION = re.compile(r'^\[(?:[0-9a-fA-F]+|\?+)\]\s+--- SIGILL \{si_signo=SIGILL, si_code=ILL_[A-Z_]+, si_addr=0x[0-9a-fA-F]+\} ---$')


def arguments(value):
    return [part.strip() for part in re.findall(r'"(?:\\x[0-9a-f]{2})*"|[^,]+', value)]


def quoted(value):
    assert re.fullmatch(r'"(?:\\x[0-9a-f]{2})*"', value), value
    return bytes.fromhex(value[1:-1].replace('\\x', ''))


def overlaps(address, extent, owners):
    assert address >= 0 and extent > 0 and address + extent < (1 << 64)
    return any(address < low + length and low < address + extent for low, length in owners.items())


def decode(text, profile, tid):
    """Decode a completed per-TID strace prefix, preserving native ordinals."""
    found, counts = [], Counter()
    for line in text.splitlines():
        if TERMINAL.fullmatch(line) or ILLEGAL_INSTRUCTION.fullmatch(line):
            continue
        match = LINE.fullmatch(line)
        assert match, ('incomplete/unsupported syscall trace', tid, line)
        ip, name, args, answer = match.groups()
        counts[name] += 1
        authority = SOURCE.classify(profile, int(ip, 16))
        assert authority in ('source', 'native', 'bootstrap-' + name, 'entry-exit'), (authority, line)
        if authority != 'source':
            assert 'INJECTED' not in answer, ('injection outside source authority', tid, line)
        found.append(dict(tid=tid, ip=int(ip, 16), name=name, args=args, answer=answer,
                          authority=authority, ordinal=counts[name], line=line))
    return found


def source_maps(entries, profile, main_pid, *, shared_regions=False):
    """Return exact live requested extents; nonempty is valid before retirement."""
    pairs, named = profile
    assert not named
    allocations_at = {pair[0] for pair in pairs}
    releases_at = {pair[1] for pair in pairs}
    live, kinds, allocations, peak = {}, {}, [], 0
    for entry in entries:
        name, authority = entry['name'], entry['authority']
        if name in ('brk', 'mremap') and authority == 'source':
            raise AssertionError(('unsupported source allocation operation', entry))
        if name not in ('mmap', 'munmap'):
            continue
        args = arguments(entry['args'])
        result = entry['answer'].split()[0]
        if authority == 'source':
            assert entry['tid'] == main_pid, ('fixture source ownership moved to worker', entry)
        if name == 'mmap' and authority == 'source':
            assert len(args) == 6, entry
            kind = 'allocator'
            expected = profile[0].mmap_flags.get(entry['ip'])
            if entry['ip'] in allocations_at:
                assert expected in (0x22, 0x62), entry
                flags = {'MAP_PRIVATE', 'MAP_ANONYMOUS'}
                if expected == 0x62: flags.add('MAP_32BIT')
            else:
                assert shared_regions and authority == 'source', ('unverified source allocation site', entry)
                kind = 'region'
                flags = {'MAP_SHARED', 'MAP_ANONYMOUS'}
            length = int(args[1])
            if kind == 'region': assert length % 4096 == 0, entry
            assert args[0] == 'NULL' and length > 0 and args[2] == 'PROT_READ|PROT_WRITE', entry
            assert set(args[3].split('|')) == flags and args[4:] == ['-1', '0'], entry
            allocation = dict(entry, extent=length, address=None, kind=kind)
            allocations.append(allocation)
            if result.startswith('0x'):
                pointer = int(result, 16)
                assert 0 < pointer < (1 << 64) - length and pointer not in live, (entry, live)
                assert all(pointer + length <= low or low + extent <= pointer for low, extent in live.items()), (entry, live)
                if expected == 0x62: assert pointer < 0x80000000, entry
                allocation['address'] = pointer
                live[pointer] = length
                kinds[pointer] = kind
                peak = max(peak, sum(live.values()))
            else:
                assert result == '-1', entry
        elif name == 'mmap' and result.startswith('0x'):
            pointer, length = int(result, 16), int(args[1])
            assert not overlaps(pointer, length, live), ('native mapping overlaps source owner', entry, live)
        elif name == 'munmap':
            pointer, length = int(args[0], 16), int(args[1])
            if authority == 'source':
                assert result == '0' and live.get(pointer) == length, ('unowned/wrong source release', entry, live)
                if kinds[pointer] == 'allocator':
                    assert entry['ip'] in releases_at, ('source allocator release outside exact helper', entry)
                else:
                    assert shared_regions and entry['ip'] not in releases_at, ('region released through allocator helper', entry)
                del live[pointer]
                del kinds[pointer]
            else:
                assert not overlaps(pointer, length, live), ('native release overlaps source owner', entry, live)
    return dict(maps=live, map_kinds=kinds, allocations=allocations, peak=peak)


def read_traces(prefix, profile, main_pid, checkpoint=None, *, shared_regions=False):
    """Read -ff files; optionally end main trace at exact completed stdout bytes.

    Additional traced syscall names are permitted and retained. All post-IPs
    still receive the same authority check. Main-source allocation order is
    exact; no global chronology is invented across independent TID logs.
    """
    prefix = Path(prefix)
    deadline = time.monotonic() + 3
    while True:
        files = sorted(prefix.parent.glob(prefix.name + '.*'))
        assert files, ('missing per-thread trace files', prefix)
        raw = {}
        for path in files:
            suffix = path.name[len(prefix.name) + 1:]
            assert suffix.isdecimal(), ('unexpected trace suffix', path)
            text = path.read_text()
            # A live tracer may be appending one syscall line. The main
            # checkpoint below requires a fully completed report write.
            if text and not text.endswith('\n'):
                assert checkpoint is not None, ('unterminated completed trace', path)
                text = text[:text.rfind('\n') + 1]
            raw[int(suffix)] = text
        assert main_pid in raw, ('main TID trace missing', main_pid, raw.keys())
        if checkpoint is None:
            break
        matched = None
        lines = raw[main_pid].splitlines(keepends=True)
        for index, line in enumerate(lines):
            match = LINE.fullmatch(line.rstrip('\n'))
            if match and match[2] == 'write' and match[4] == str(len(checkpoint)):
                args = arguments(match[3])
                if args[0] == '1' and quoted(args[1]) == checkpoint:
                    matched = ''.join(lines[:index + 1])
        if matched is not None:
            raw[main_pid] = matched
            break
        assert time.monotonic() < deadline, 'completed checkpoint report was not traced'
        time.sleep(0.002)
    per_tid = {tid: decode(text, profile, tid) for tid, text in raw.items()}
    main_events = per_tid[main_pid]
    worker_events = [entry for tid, entries in per_tid.items() if tid != main_pid for entry in entries]
    assert not [entry for entry in worker_events if entry['authority'] == 'source'
                and entry['name'] in ('mmap', 'munmap', 'brk', 'mremap')], 'worker source allocations outside fixture contract'
    memory = source_maps(main_events, profile, main_pid, shared_regions=shared_regions)
    # Explicit extra fixture restriction: worker native mappings may not touch
    # any historical source interval. This conservative rule can reject valid
    # address reuse after early collector allocations retire; it is not a
    # general cross-TID allocator verdict and invents no event chronology.
    protected = {}
    for item in memory['allocations']:
        if item['address'] is not None:
            protected[item['address']] = max(protected.get(item['address'], 0), item['extent'])
    for entry in worker_events:
        if entry['name'] not in ('mmap', 'munmap'):
            continue
        args, result = arguments(entry['args']), entry['answer'].split()[0]
        if entry['name'] == 'mmap' and not result.startswith('0x'):
            continue
        pointer = int(result, 16) if entry['name'] == 'mmap' else int(args[0], 16)
        assert not overlaps(pointer, int(args[1]), protected), ('worker native mapping overlaps protected source backing', entry, protected)
    return dict(events=main_events + worker_events, main_events=main_events, per_tid=per_tid, **memory)


def assert_empty(snapshot):
    assert not snapshot['maps'], ('source owners survived explicit cleanup', snapshot['maps'])
