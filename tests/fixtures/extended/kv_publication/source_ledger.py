"""Current raw KV application owners, separate from historical Atomic gates.

Memory authority comes from the unchanged TempFile ELF verifier/final source
ledger. This app-only layer supplies complete event indices and fd generations;
it does not reinterpret flags, lower pointers, or infer cleanup from child exit.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
ATOMIC = load("kv_historical_atomic_bindings", FIXTURES / "stdlib_execution/atomic_file/ledger.py")
TRUSTED = ATOMIC.TEMP
arguments, quoted, LINE = TRUSTED.arguments, TRUSTED.quoted, TRUSTED.LINE
CALLS = ATOMIC.CALLS | {"rt_sigaction"}
# Observe every syscall, then reject every unapproved body event. Tracing only
# CALLS would hide transient effects such as unlink or socket/create+close.
TRACE = "all"
check_injections = ATOMIC.check_injections
bind_target = ATOMIC.bind_target


def authority(profile):
    pairs, named = profile
    assert pairs and not named, "current KV gate requires verified raw opcode sites"
    ranges = getattr(pairs, "executable_ranges", [])
    assert ranges, "missing verified raw executable ranges"
    flags = getattr(pairs, "mmap_flags", {})
    assert all(flags.get(site) in (0x22, 0x62) for site, _ in pairs), "missing or unsupported verified source mmap flags"
    return ranges


def verified_sites(executable, directory):
    profile = TRUSTED.verified_sites(Path(executable), Path(directory))
    authority(profile)
    return profile


def events(text, *, phase_markers=False):
    """Parse only the body returned by normalize_trace, with no silent skips."""
    assert phase_markers is False, "application events have no fixture phase markers"
    assert not text or text.endswith("\n"), "incomplete application trace"
    counts, found = Counter(), []
    for index, line in enumerate(text.splitlines()):
        match = LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported application event", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        found.append(dict(ip=int(ip, 16), name=name, args=args, result=result,
                          ordinal=counts[name], index=index, line=line, phase=None))
    return found


def normalize_trace(text, profile, *, executable, status):
    """Remove only one verified launch and one terminal raw-image exit.

    Application event indices start after the launch. All body calls, including
    allocation and rename calls, retain one common index space. Signals are
    suppressed by the explicit strace signal=none option, not by this parser.
    """
    assert isinstance(status, int) and 0 <= status <= 255, ("invalid captured exit status", status)
    assert text.endswith("\n"), "incomplete full application trace"
    lines = text.splitlines(keepends=True)
    assert len(lines) >= 2, "missing launch or exit event"
    ranges = authority(profile)

    def endpoint(line):
        match = LINE.fullmatch(line.rstrip("\n"))
        assert match, ("invalid launch/exit event", line)
        ip, name, args, result = match.groups()
        return dict(ip=int(ip, 16), name=name, args=args, result=result, line=line.rstrip("\n"))

    launch, terminal = endpoint(lines[0]), endpoint(lines[-1])
    assert launch["name"] == "execve" and launch["result"] == "0", ("expected one successful initial launch", launch)
    assert not any(low <= launch["ip"] < high for low, high in ranges), ("launch IP is inside the new raw image", launch)
    launch_path = re.fullmatch(r'("(?:\\x[0-9a-f]{2})*"), \[.*\], (?:0x[0-9a-f]+(?: /\* [0-9]+ vars \*/)?|NULL)', launch["args"])
    assert launch_path, ("unsupported execve launch shape", launch)
    assert quoted(launch_path[1]) == os.fsencode(Path(executable).resolve()), ("wrong launch executable", launch)
    assert terminal["name"] in ("exit", "exit_group") and terminal["result"] == "?", ("expected one terminal exit", terminal)
    assert re.fullmatch(r'(?:0|[1-9][0-9]*)', terminal["args"]), ("invalid terminal status", terminal)
    assert int(terminal["args"]) == status, ("terminal/captured status disagreement", terminal, status)
    assert any(low <= terminal["ip"] < high for low, high in ranges), ("terminal exit is outside verified raw image", terminal)
    body = "".join(lines[1:-1])
    # This rejects secondary exec/exit, loader work, fork/network calls and any
    # other unexpected full-trace event; only the two validated endpoints vanish.
    events(body)
    return body, launch, terminal


def _analyze_body(text, profile, directory, *, phase_markers=False):
    """Normalized-body accounting, also used explicitly by isolated CPU controls."""
    ranges = authority(profile)
    found = events(text, phase_markers=phase_markers)
    assert all(any(low <= item["ip"] < high for low, high in ranges) for item in found), "application syscall outside verified raw image"
    memory = "".join(item["line"] + "\n" for item in found if item["name"] in ("mmap", "munmap"))
    # This unchanged implementation checks exact verified sites, both admitted
    # flags, requested lengths, full-width pointers, and every release. It fails
    # if any source mapping survives the observed release sequence.
    source = TRUSTED.source_maps(memory, profile, directory)
    allocate = {site for site, _ in profile[0]}
    allocations = [dict(item, length=int(arguments(item["args"])[1]))
                   for item in found if item["name"] == "mmap" and item["ip"] in allocate]
    assert len(allocations) == len(source["allocations"])
    assert [(item["ip"], item["args"], item["result"], item["ordinal"]) for item in allocations] == [
        (item["ip"], item["args"], item["result"], item["ordinal"]) for item in source["allocations"]]
    # Keep the complete application event indices, so comparing a source mmap
    # against rename/write/sync order cannot compare two different index spaces.
    source = dict(source, allocations=allocations)
    live, generations, acquisitions, closes, attempts = {}, Counter(), [], [], {}
    for item in found:
        name, args, result = item["name"], arguments(item["args"]), item["result"].split()[0]
        attempts.setdefault(name, []).append(item)
        if name in ("open", "openat") and result.isdecimal():
            fd = int(result)
            assert fd not in live, ("descriptor acquired while still live", item, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=item, closed=None)
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "fcntl" and len(args) >= 2 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC") and result.isdecimal():
            original, fd = int(args[0]), int(result)
            assert original in live and fd not in live, ("duplicate lacks source or replaces live descriptor", item, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=item, closed=None,
                         duplicate_of=(original, live[original]["generation"]))
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned or repeated descriptor release", item, live)
            item["generation"] = live[fd]["generation"]
            closes.append(item)
            # Skipped close injection leaves a real descriptor live. The real
            # app has no repair hook, so this gate does not pretend it closed.
            assert result == "0", ("unconfirmed descriptor release", item)
            live.pop(fd)["closed"] = item
    assert not live, ("application descriptors survived explicit release", live)
    return dict(events=found, epochs=[], acquisitions=acquisitions, closes=closes,
                live=live, source=source, attempts=attempts, markers=b"")


def analyze(text, profile, directory, *, executable, status, phase_markers=False):
    body, launch, terminal = normalize_trace(text, profile, executable=executable, status=status)
    result = _analyze_body(body, profile, directory, phase_markers=phase_markers)
    return dict(result, launch=launch, termination=terminal, native_exit=status)


def controls():
    class Pairs(list):
        pass

    count = 0
    allocate, release, host = 0x401002, 0x401012, 0x401022

    def call(text, ip=host):
        return "[%016x] %s\n" % (ip, text)

    def reject(action):
        nonlocal count
        try:
            action()
        except AssertionError:
            count += 1
        else:
            raise AssertionError("current KV ledger accepted an ownership/provenance mutation")

    with tempfile.TemporaryDirectory(prefix="kv-source-ledger-cpu-") as temporary:
        directory = Path(temporary)
        profiles = []
        for flags, pointer in ((0x22, 0x123456789000), (0x62, 0x41000000)):
            pairs = Pairs([(allocate, release)])
            pairs.mmap_flags = {allocate: flags}
            pairs.executable_ranges = [(0x400000, 0x402000)]
            profile = (pairs, [])
            open_call = call('openat(AT_FDCWD, "\\x61", O_RDONLY|O_DIRECTORY|O_CLOEXEC) = 3')
            duplicate = call('fcntl(3, F_DUPFD_CLOEXEC, 0) = 4')
            mapping = call('mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS%s, -1, 0) = 0x%x' %
                           ('|MAP_32BIT' if flags == 0x62 else '', pointer), allocate)
            free = call('munmap(0x%x, 37) = 0' % pointer, release)
            close4, close3 = call('close(4) = 0'), call('close(3) = 0')
            base = open_call + duplicate + mapping + free + close4 + close3
            found = _analyze_body(base, profile, directory)
            assert len(found['source']['allocations']) == 1 and found['source']['allocations'][0]['index'] == 2
            assert found['acquisitions'][1]['duplicate_of'] == (3, 1) and not found['live']
            assert all(item['phase'] is None for item in found['events'])
            count += 1
            profiles.append((profile, base, mapping, free, open_call, close3))

        profile, base, mapping, free, open_call, close3 = profiles[0]
        policy = call('rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=0}, NULL, 8) = 0')
        with_policy = _analyze_body(policy + base, profile, directory)
        assert with_policy['events'][0]['name'] == 'rt_sigaction' and with_policy['source']['allocations'][0]['index'] == 3
        count += 1
        failed_policy = call('rt_sigaction(SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=0}, NULL, 8) = -1 EINTR (Interrupted system call) (INJECTED)')
        failure = _analyze_body(failed_policy, profile, directory)
        check_injections(failure, [dict(syscall='rt_sigaction', when=1, error='EINTR')])
        assert not failure['source']['allocations'] and not failure['acquisitions']
        count += 1
        recycled = _analyze_body(base + open_call + close3, profile, directory)
        assert [owner['generation'] for owner in recycled['acquisitions'] if owner['fd'] == 3] == [1, 2]
        assert [item['generation'] for item in recycled['closes'] if arguments(item['args'])[0] == '3'] == [1, 2]
        count += 1
        denied = mapping.split(' = ')[0] + ' = -1 ENOMEM (Cannot allocate memory) (INJECTED)\n'
        denial = _analyze_body(base.replace(mapping, denied).replace(free, ''), profile, directory)
        check_injections(denial, [dict(syscall='mmap', when=1, error='ENOMEM')])
        assert len(denial['source']['allocations']) == 1 and denial['source']['allocations'][0]['length'] == 37
        count += 1

        for changed in (
            base.replace('%016x' % allocate, '%016x' % (allocate + 1)),
            base.replace(free, free.replace(', 37)', ', 36)')),
            base.replace(free, ''),
            base.replace(free, free + free),
            base.replace(close3, ''),
            base.replace(close3, call('close(5) = 0')),
            base.replace(open_call, open_call + open_call),
            base.replace('fcntl(3, F_DUPFD_CLOEXEC', 'fcntl(1, F_DUPFD_CLOEXEC'),
            base + close3,
            base.replace('MAP_PRIVATE|MAP_ANONYMOUS,', 'MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,'),
            base.replace('0x123456789000', '0xfffffffffffffff0'),
            base.replace('%016x' % host, '%016x' % 0x501022, 1),
            base + call('socket(AF_INET, SOCK_STREAM, 0) = 3'),
            base[:-1],
            base.replace(close3, call('close(3) = -1 EINTR (Interrupted system call)')),
        ):
            reject(lambda changed=changed: _analyze_body(changed, profile, directory))
        reject(lambda: _analyze_body(base, profile, directory, phase_markers=True))
        reject(lambda: authority((profile[0], [host])))
        incomplete = Pairs([(allocate, release)])
        incomplete.executable_ranges = [(0x400000, 0x402000)]
        reject(lambda: authority((incomplete, [])))

        # Exercise the actual full-trace boundary, not only the isolated body
        # parser. The observation option itself is part of this contract.
        assert TRACE == 'all'
        count += 1
        executable = directory / 'raw-kv.elf'
        name = '"' + ''.join('\\x%02x' % value for value in os.fsencode(executable.resolve())) + '"'
        launch = call('execve(%s, [%s, "\\x2d\\x68"], 0x7fff00002000 /* 2 vars */) = 0' % (name, name), 0x7fff00001002)
        exit_call = call('exit(0) = ?')

        def full(body, termination=exit_call):
            return launch + body + termination

        complete = analyze(full(base), profile, directory, executable=executable, status=0)
        assert complete['events'][0]['index'] == 0 and complete['source']['allocations'][0]['index'] == 2
        assert complete['launch']['name'] == 'execve' and complete['termination']['name'] == 'exit' and complete['native_exit'] == 0
        count += 1
        policy_exit = call('exit_group(3) = ?')
        complete = analyze(full(failed_policy, policy_exit), profile, directory, executable=executable, status=3)
        assert len(complete['events']) == 1 and complete['events'][0]['name'] == 'rt_sigaction' and complete['native_exit'] == 3
        count += 1

        for transient in (
            'unlink("\\x61") = 0',
            'rename("\\x61", "\\x62") = 0',
            'renameat(3, "\\x61", 3, "\\x62") = 0',
            'rmdir("\\x61") = 0',
            'socket(AF_INET, SOCK_STREAM, 0) = 3',
            'fork() = 1234',
            'clone(child_stack=NULL, flags=SIGCHLD) = 1234',
            'execve("\\x61", ["\\x61"], NULL) = 0',
            'exit(0) = ?',
        ):
            reject(lambda transient=transient: analyze(full(base + call(transient)), profile, directory, executable=executable, status=0))
        for malformed in (
            base + exit_call,
            launch + base,
            full(base).replace(launch, launch.replace(' = 0\n', ' = -1 ENOENT (No such file or directory)\n')),
            full(base).replace(launch, launch.replace('%016x' % 0x7fff00001002, '%016x' % host)),
            full(base).replace(launch, launch.replace(name, '"\\x61"', 1)),
            full(base).replace(exit_call, exit_call.replace('%016x' % host, '%016x' % 0x7fff00001002)),
            full(base).replace(exit_call, call('exit(2) = ?')),
            full(base).replace(exit_call, call('exit(-1) = ?')),
            full(base).replace(exit_call, call('exit(0) = 0')),
            full(base) + call('write(2, "\\x61", 1) = 1'),
            full(base)[:-1],
        ):
            reject(lambda malformed=malformed: analyze(malformed, profile, directory, executable=executable, status=0))
        reject(lambda: analyze(full(base), profile, directory, executable=executable, status=-13))
    return count


if __name__ == '__main__':
    print('kv-current-source-ledger CPU-controls=%d native-cases=0' % controls())
