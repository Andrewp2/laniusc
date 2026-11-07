"""Finite, reached faults for real single-thread native-linked channels.

Only the existing native source-site verifier classifies source allocations;
only the existing exact source-map ledger owns allocation/release accounting.
Global syscall ordinals choose faults, including intervening native calls.
Fatal post-commit wake cases prove termination, not orderly owner cleanup.
"""
from collections import Counter
import importlib.util
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[1]
SOURCE = load("channel_source_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("channel_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")


def inspect(text, authority, directory, selector, failed=0, terminal=False):
    assert text.endswith("\n"), "truncated channel trace"
    counts, events, phases, memory = Counter(), [], {}, []
    active, markers, done, read, reported = None, [], False, False, False
    lines = text.splitlines()
    if terminal and lines[-1] in ("+++ killed by SIGILL +++", "+++ killed by SIGILL (core dumped) +++"):
        lines = lines[:-1]
    for line in lines:
        match = OWNERS.LINE.fullmatch(line)
        assert match, ("unsupported channel trace", line)
        ip, name, args, result = match.groups()
        assert name in ("mmap", "munmap", "read", "write", "futex"), line
        origin = SOURCE.classify(authority, int(ip, 16))
        counts[name] += 1
        event = dict(name=name, args=args, result=result, ip=int(ip, 16),
                     authority=origin, ordinal=counts[name], phase=active, line=line)
        if name == "write":
            assert origin == "source", line
            mark = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args)
            if mark:
                assert result == "1" and read and not done, line
                token = chr(int(mark[1], 16))
                markers.append(token)
                if token == "D":
                    assert active is None, line
                    done = True
                    # Source owners must already be gone at the program's
                    # cleanup checkpoint, before its success report/exit.
                    OWNERS.source_maps("".join(memory), authority, directory)
                elif token in "AR":
                    assert active is None and token not in phases, line
                    active = token
                    phases[token] = []
                else:
                    assert token in "ar" and active == token.upper(), line
                    active = None
            else:
                expected = '1, "\\x%02x\\x%02x", 2' % (selector, failed)
                assert done and not reported and args == expected and result == "2", line
                reported = True
        elif name == "read":
            if origin == "source":
                assert not read and not markers, line
                assert args == '0, "\\x%02x", 1' % selector and result == "1", line
                read = True
            else:
                assert origin == "native" and not markers, line
        else:
            assert origin in ("source", "native", "bootstrap-" + name), line
            if origin == "source":
                assert not done, ("source operation after cleanup", line)
            if name == "futex" and origin == "source":
                expected_count = 2147483647 if selector in (8, 9, 10) else 1
                assert re.fullmatch(r"0x[0-9a-f]+, FUTEX_WAKE_PRIVATE, " + str(expected_count), args), line
                assert active in ("A", "R"), line
                if not terminal:
                    assert result == "0", line
            if name in ("mmap", "munmap"):
                memory.append(line + "\n")
            if active:
                phases[active].append(event)
        events.append(event)
    assert read, "missing channel input"
    if terminal:
        assert selector in range(5, 11) and markers == ["A"] and active == "A" and not done and not reported, markers
        wakes = [event for event in events if event["name"] == "futex" and event["authority"] == "source"]
        assert len(wakes) == 1 and wakes[0] is events[-1], wakes
        assert wakes[0]["result"].startswith("-1 EIO ") and "INJECTED" in wakes[0]["result"], wakes
    else:
        assert done and active is None and reported, "missing channel completion"
        assert "".join(markers) == "Aa" + ("Rr" if failed else "") + "D", markers
        if selector in (0, 1, 3, 4, 11):
            # Constructor rollback must be complete before a retry starts;
            # setup owners are absent in these self-contained phases.
            for phase in phases.values():
                OWNERS.source_maps("".join(e["line"] + "\n" for e in phase if e["name"] in ("mmap", "munmap")), authority, directory)
        OWNERS.source_maps("".join(memory), authority, directory)
    return dict(events=events, phases=phases)


def source_events(ledger, phase, name):
    return [event for event in ledger["phases"][phase] if event["name"] == name and event["authority"] == "source"]


def run(executable, authority, directory, selector, fault=None, attempt=None):
    directory.mkdir()
    trace = directory / "trace"
    command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx",
               "-e", "signal=none", "-e", "trace=mmap,munmap,read,write,futex", "-o", str(trace)]
    terminal = fault is not None and fault[0] == "futex"
    failed = int(fault is not None and not terminal)
    if fault:
        name, ordinal = fault
        error = "EIO" if terminal else "ENOMEM"
        command += ["-e", f"inject={name}:error={error}:when={ordinal}"]
    command.append(str(executable))
    completed = subprocess.run(command, input=bytes([selector]), capture_output=True, timeout=5)
    assert completed.returncode == (-signal.SIGILL if terminal else 0), (selector, fault, completed, trace.read_text())
    assert completed.stdout == (b"" if terminal else bytes([selector, failed])), completed
    assert completed.stderr == (b"A" if terminal else b"Aa" + (b"Rr" if failed else b"") + b"D"), completed
    ledger = inspect(trace.read_text(), authority, directory, selector, failed, terminal)
    marked = [event for event in ledger["events"] if "INJECTED" in event["result"] or "POKED" in event["result"]]
    if not fault:
        assert not marked, marked
        allocations = source_events(ledger, "A", "mmap")
        if selector in (0, 1, 2):
            assert len(allocations) == (3, 2, 1)[selector], allocations
            return [("mmap", event["ordinal"]) for event in allocations]
        if selector == 4:
            assert not any(event["name"] == "mmap" and event["authority"] == "source" for event in ledger["events"]), ledger
        if selector in range(5, 11):
            wakes = source_events(ledger, "A", "futex")
            assert len(wakes) == 1 and wakes[0]["result"] == "0", wakes
            return [("futex", wakes[0]["ordinal"])]
        return []
    assert len(marked) == 1, marked
    reached = marked[0]
    assert reached["name"] == fault[0] and reached["ordinal"] == fault[1] and reached["authority"] == "source" and reached["phase"] == "A", reached
    if not terminal:
        allocations = source_events(ledger, "A", "mmap")
        assert len(allocations) == attempt and reached == allocations[-1], allocations
        assert reached["result"].startswith("-1 ENOMEM "), reached
        assert not source_events(ledger, "A", "futex"), "rejected operation issued a wake"
        retry = source_events(ledger, "R", "mmap")
        assert len(retry) == (3, 2, 1)[selector] and all(event["result"].startswith("0x") for event in retry), retry
        if selector == 2:
            wakes = source_events(ledger, "R", "futex")
            assert len(wakes) == 1 and wakes[0]["result"] == "0", wakes
    return []


def controls():
    pairs = SOURCE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}
    pairs.executable_ranges = [(0x401000, 0x401060)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022, 0x401032, 0x401042}
    pairs.bootstrap_sites = {0x402002: "bootstrap-mmap", 0x402012: "bootstrap-munmap"}
    pairs.image_ranges = [(0x401000, 0x403000)]
    authority = pairs, []

    def event(value, ip=0x401022):
        return f"[{ip:016x}] {value}\n"

    def mark(token):
        return event('write(2, "\\x%02x", 1) = 1' % ord(token))

    read = event('read(0, "\\x00", 1) = 1', 0x401032)
    report = event('write(1, "\\x00\\x00", 2) = 2')
    allocation = event("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", 0x401002)
    release = event("munmap(0x7fff10000000, 37) = 0", 0x401012)
    native = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000", 0x7fff00001000)
    native_release = event("munmap(0x7fff20000000, 8192) = 0", 0x7fff00001000)
    bootstrap = event("mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff30000000", 0x402002)
    bootstrap_release = event("munmap(0x7fff30000000, 8388608) = 0", 0x402012)
    valid = read + mark("A") + allocation + release + mark("a") + mark("D") + report
    wake = event("futex(0x7fff10000080, FUTEX_WAKE_PRIVATE, 1) = -1 EIO (Input/output error) (INJECTED)", 0x401042)
    fatal = read.replace('"\\x00"', '"\\x05"') + mark("A") + wake
    with tempfile.TemporaryDirectory(prefix="channel-allocation-controls-") as directory:
        inspect(valid, authority, directory, 0)
        decorated = inspect(native + bootstrap + valid + bootstrap_release, authority, directory, 0)
        assert source_events(decorated, "A", "mmap")[0]["ordinal"] == 3
        inspect(native + valid.replace(release, native_release + release), authority, directory, 0)
        inspect(fatal, authority, directory, 5, terminal=True)
        mutations = [
            valid.replace(release, ""),
            valid.replace(release, release + release),
            valid.replace(", 37) = 0", ", 36) = 0"),
            valid.replace(release, "").replace(mark("D"), release + mark("D")),
            valid.replace("0000000000401002", "0000000000401022"),
            valid.replace("0000000000401002", "0000000000401052"),
            valid.replace("0000000000401012", "00007fff00001000"),
            valid.replace("MAP_PRIVATE|MAP_ANONYMOUS,", "MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,"),
            valid + allocation + release,
            valid.replace(mark("a"), ""),
            valid.replace(report, report + report),
            valid.replace(read, ""),
            valid.rstrip("\n"),
            valid.replace(mark("a"), wake + mark("a")),
        ]
        # Different-base native releases must not evade exact owner checks.
        for pointer, length in ((0x7fff10000008, 8), (0x7fff0ffffff8, 16),
                                (0x7fff0ffffff8, 53), (0x7fff10000020, 16)):
            overlap = event(f"munmap({pointer:#x}, {length}) = 0", 0x7fff00001000)
            mutations.append(valid.replace(release, overlap + release))
        fatal_mutations = [fatal + mark("a"), fatal.replace("EIO", "EINVAL"), fatal.replace(" (INJECTED)", ""), fatal.replace("FUTEX_WAKE_PRIVATE, 1", "FUTEX_WAIT_PRIVATE, 1"), fatal + allocation]
        for changed, terminal in [(text, False) for text in mutations] + [(text, True) for text in fatal_mutations]:
            try:
                inspect(changed, authority, directory, 5 if terminal else 0, terminal=terminal)
            except (AssertionError, ValueError):
                continue
            raise AssertionError(("channel observer accepted corruption", changed))
    return 4 + len(mutations) + len(fatal_mutations)


def main():
    checked = controls()
    if sys.argv[1:] == ["controls"]:
        print(f"thread-channel-allocation-controls={checked}")
        return
    assert len(sys.argv) == 2, sys.argv
    executable = Path(sys.argv[1]).resolve()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    authority = SOURCE.verified_sites(executable)
    oom, wakes = 0, 0
    with tempfile.TemporaryDirectory(prefix="channel-allocations-") as temporary:
        directory = Path(temporary)
        for selector in range(12):
            positions = run(executable, authority, directory / f"baseline-{selector}", selector)
            for attempt, fault in enumerate(positions, 1):
                run(executable, authority, directory / f"fault-{selector}-{attempt}", selector, fault, attempt)
                if fault[0] == "mmap":
                    oom += 1
                else:
                    wakes += 1
    assert (oom, wakes) == (6, 6)
    print(f"thread-channel-allocation: profiles=12 reached-oom={oom} reached-wake-eio={wakes} host-controls={checked} balanced-recovery=yes wrap-rounds=2")


if __name__ == "__main__":
    main()
