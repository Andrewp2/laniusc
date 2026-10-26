"""Atomic-publication test ledger, including live checkpoint ownership.

Raw ELF admission and final source-map accounting reuse the accepted TempFile
helpers. This module adds fd generations, bounded publication phases and live
checkpoints; it changes no production runtime or existing fixture.
"""
from collections import Counter
import importlib.util
from pathlib import Path
import re
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


TEMP = load("atomic_accepted_temp_file_ledger", Path(__file__).resolve().parents[1] / "temp_file/ledger.py")
verified_sites = TEMP.verified_sites
quoted = TEMP.quoted
arguments = TEMP.arguments
LINE = TEMP.LINE
CALLS = TEMP.CALLS | {"open", "ftruncate"}
TRACE = ",".join(sorted(CALLS))
PHASES = "CcWwMmVvDdKkAaBbXxQqPpRrHh"
U64_MAX = TEMP.U64_MAX


def check_injections(result, rules):
    expanded = []
    for item in rules:
        if "last" not in item:
            expanded.append(item)
            continue
        assert not item.get("repeat") and item["last"] >= item["when"], item
        for ordinal in range(item["when"], item["last"] + 1):
            value = dict(item, when=ordinal)
            value.pop("last")
            expanded.append(value)
    TEMP.check_injections(result, expanded)


def events(text, *, phase_markers=True):
    assert not text or text.endswith("\n"), "incomplete native trace"
    entries, epochs, phase, counts = [], [], None, Counter()
    for index, line in enumerate(text.splitlines()):
        match = LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported native trace", line)
        address, name, args, result = match.groups()
        counts[name] += 1
        entry = dict(ip=int(address, 16), name=name, args=args, result=result,
                     ordinal=counts[name], index=index, line=line, phase=phase)
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if phase_markers and name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in PHASES, entry
            if token.isupper():
                assert phase is None, (phase, entry)
                phase = token
                entry["phase"] = phase
                epochs.append(dict(phase=phase, start=index, end=None, events=[]))
            else:
                assert phase == token.upper(), (phase, entry)
                entry["phase"] = phase
                epochs[-1]["end"] = index
                phase = None
            entry["marker"] = token
        elif phase is not None:
            epochs[-1]["events"].append(entry)
        entries.append(entry)
    assert phase is None, ("unclosed operation marker", phase)
    return entries, epochs


def analyze(text, profile, directory, *, final=True, repaired_close=None, repair_phase="M", phase_markers=True):
    assert all(flags == 0x62 for flags in getattr(profile[0], "mmap_flags", {}).values()), "Atomic checkpoint ledger requires its historical MAP_32BIT profile; full-width source accounting is not migrated"
    entries, epochs = events(text, phase_markers=phase_markers)
    live, generations, acquisitions, closes = {}, Counter(), [], []
    pairs, named = profile
    allocate = {a for a, _ in pairs} | set(named)
    release = {f for _, f in pairs} | set(named)
    mappings, allocations = {}, []
    counts = Counter()
    attempts = {}
    for entry in entries:
        name, args = entry["name"], arguments(entry["args"])
        result = entry["result"].split()[0]
        counts[name] += 1
        attempts.setdefault(name, []).append(entry)
        if name == "mmap" and "MAP_32BIT" in entry["args"]:
            assert entry["ip"] in allocate, ("unverified source allocation", entry)
            length = int(args[1])
            allocation = dict(entry, length=length)
            allocations.append(allocation)
            if result.startswith("0x"):
                pointer = int(result, 16)
                assert 0 < pointer < 0x80000000 and pointer not in mappings, (entry, mappings)
                mappings[pointer] = dict(length=length, acquired=allocation)
        elif name == "munmap":
            pointer, length = int(args[0], 16), int(args[1])
            if pointer in mappings:
                assert entry["ip"] in release and result == "0" and mappings[pointer]["length"] == length, (entry, mappings)
                del mappings[pointer]
            elif pointer < 0x80000000:
                raise AssertionError(("unowned low mapping release", entry))
        if name in ("open", "openat") and result.isdecimal():
            fd = int(result)
            assert fd not in live, ("reacquired live fd", entry, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=entry, closed=None)
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "fcntl" and len(args) >= 2 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC") and result.isdecimal():
            source, fd = int(args[0]), int(result)
            assert source in live and fd not in live, (entry, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=entry, closed=None,
                         duplicate_of=(source, live[source]["generation"]))
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned or repeated close", entry, live)
            entry["generation"] = live[fd]["generation"]
            closes.append(entry)
            if result == "0":
                live.pop(fd)["closed"] = entry
            else:
                # A strace-skipped close leaves the actual native generation
                # live. Logical retirement is checked in the probe's report;
                # only the separately marked raw repair may close it later.
                assert entry["ordinal"] == repaired_close and entry["phase"] == repair_phase, entry
                assert entry["result"].startswith("-1 EIO ") and "INJECTED" in entry["result"], entry
    if repaired_close is not None:
        failures = [entry for entry in closes if entry["ordinal"] == repaired_close]
        assert len(failures) <= 1, failures
        if final:
            assert failures, "declared close fault did not occur"
        if failures:
            assert failures[0]["result"].startswith("-1 EIO "), failures
            failed = failures[0]
            repair = [entry for entry in closes if entry["index"] > failed["index"]
                      and entry["args"] == failed["args"] and entry["generation"] == failed["generation"]]
            if final or repair:
                assert len(repair) == 1 and repair[0]["phase"] == "Q" and repair[0]["result"] == "0", repair
    for epoch in epochs:
        phase, body = epoch["phase"], epoch["events"]
        if phase in ("V", "K", "X"):
            assert not body, ("cached commit/keep/terminal destroy made native work", epoch)
        if phase == "D":
            assert sum(entry["name"] == "fsync" for entry in body) <= 1, epoch
            assert not any(entry["name"] in ("renameat2", "unlinkat", "openat", "getrandom", "write", "mmap") for entry in body), epoch
        if phase == "Q":
            assert len(body) == 1 and body[0]["name"] == "close" and body[0]["result"] == "0", epoch
    source = dict(allocations=allocations, attempts=attempts, calls=dict(counts))
    if final:
        assert not live and not mappings, ("owners survived final release", live, mappings)
        # The trusted final accounting independently validates the source
        # ownership sequence using verified addresses and requested lengths.
        map_text = "".join(entry["line"] + "\n" for entry in entries if entry["name"] in ("mmap", "munmap"))
        source = TEMP.source_maps(map_text, profile, directory)
        assert len(source["allocations"]) == len(allocations)
    return dict(events=entries, epochs=epochs, acquisitions=acquisitions, closes=closes,
                live=live, mappings=mappings, source=source, attempts=attempts,
                markers="".join(entry["marker"] for entry in entries if "marker" in entry).encode())


def bind_target(before, after, syscall, ordinal):
    """Bind the reached injection to a baseline site, owner role and prefix."""
    prior = [entry for entry in before["events"] if entry["name"] == syscall]
    actual = [entry for entry in after["events"] if entry["name"] == syscall]
    assert len(prior) >= ordinal and len(actual) >= ordinal, (syscall, ordinal)
    left, right = prior[ordinal - 1], actual[ordinal - 1]
    assert (left["ip"], left["phase"]) == (right["ip"], right["phase"]), (left, right)
    a, b = arguments(left["args"]), arguments(right["args"])
    if syscall == "mmap":
        def shape(entry):
            values = arguments(entry["args"])
            return entry["ip"], values[1:4], values[4:]
        assert [shape(e) for e in prior[:ordinal]] == [shape(e) for e in actual[:ordinal]], (prior, actual)
    elif syscall in ("close", "fsync", "fcntl"):
        assert a == b, (left, right)
    elif syscall == "write":
        assert a[0] == b[0] and a[1:] == b[1:], (left, right)
        assert [e["args"] for e in prior[:ordinal]] == [e["args"] for e in actual[:ordinal]], (left, right)
    elif syscall == "renameat2":
        # Random temporary bytes differ across children; the actual name is
        # checked separately against the create event and captured owner view.
        assert a[0] == b[0] and a[2:] == b[2:], (left, right)
    elif syscall == "unlinkat":
        assert a[0] == b[0] and a[2] == b[2], (left, right)
    else:
        raise AssertionError(("unsupported fault binding", syscall))
    return right


def controls():
    count = TEMP.controls()
    a, f = 0x401002, 0x401012
    def call(text, ip=a):
        return "[%016x] %s\n" % (ip, text)
    def marker(token):
        return call('write(2, "\\x%02x", 1) = 1' % ord(token))
    parent = call('openat(AT_FDCWD, "\\x61", O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3')
    allocated = call('mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x41000000')
    duplicated = call('fcntl(3, F_DUPFD_CLOEXEC, 0) = 4')
    free = call('munmap(0x41000000, 37) = 0', f)
    close = call('close(4) = 0')
    first = parent + marker('C') + allocated + duplicated + marker('c') + marker('M') + call('fsync(4) = -1 EIO (Input/output error) (INJECTED)') + marker('m')
    final = first + marker('V') + marker('v') + marker('D') + call('fsync(4) = 0') + close + free + marker('d') + marker('A') + marker('a') + marker('B') + marker('b') + marker('X') + marker('x') + marker('P') + call('close(3) = 0') + marker('p')
    with tempfile.TemporaryDirectory(prefix='atomic-file-ledger-cpu-') as directory:
        class FullWidth(list):
            pass
        unsupported = FullWidth([(a, f)])
        unsupported.mmap_flags = {a: 0x22}
        for final_checkpoint in (False, True):
            try:
                analyze('', (unsupported, []), directory, final=final_checkpoint)
            except AssertionError:
                count += 1
            else:
                raise AssertionError('historical Atomic checkpoint ledger accepted a full-width source profile')
        held = analyze(first, ([(a, f)], []), directory, final=False)
        assert set(held['live']) == {3, 4} and set(held['mappings']) == {0x41000000}
        count += 1
        assert not analyze(final, ([(a, f)], []), directory)['live']
        count += 1
        legacy = final.replace('openat(AT_FDCWD, "\\x61", O_RDONLY|O_DIRECTORY|O_CLOEXEC)',
                               'open("\\x61", O_RDONLY|O_DIRECTORY|O_CLOEXEC)')
        assert not analyze(legacy, ([(a, f)], []), directory, phase_markers=False)['live']
        count += 1
        for text in (final.replace(marker('v'), close + marker('v')),
                     final.replace(marker('d'), call('fsync(4) = 0') + marker('d')),
                     final.replace(marker('D'), marker('D') + call('renameat2(4, "\\x61", 4, "\\x62", 0) = 0')),
                     final.replace(free, ''), final.replace(close, ''),
                     final.replace(allocated, allocated.replace('0000000000401002', '00007fff00001000'))):
            try:
                analyze(text, ([(a, f)], []), directory)
            except AssertionError:
                count += 1
            else:
                raise AssertionError('atomic-file ledger accepted a publication ownership mutation')
    return count


if __name__ == '__main__':
    print('atomic-file ledger CPU-controls=%d native-cases=0' % controls())
