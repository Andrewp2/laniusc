"""Reached OOM and natural-failure cleanup using current source-site authority.

All trace IPs are classified before native/CRT activity is excluded. Fault
positions use global mmap ordinals, while accounting uses verified Lanius
allocation/release sites and full-width exact extents. Operation phases must
balance independently before retry; setup owners survive until final cleanup.
"""
from collections import Counter
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
NATIVE = load("weighted_source_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("weighted_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")


def inspect(text, authority, directory, selector, failed):
    assert text.endswith("\n"), "truncated weighted owner trace"
    counts, events, phases, memory = Counter(), [], {}, []
    active, markers, done, read, reported = None, [], False, False, False
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match, ("unsupported weighted trace", line)
        ip, name, args, result = match.groups()
        assert name in ("mmap", "munmap", "read", "write"), line
        source = NATIVE.classify(authority, int(ip, 16))
        counts[name] += 1
        event = dict(name=name, args=args, result=result, ip=int(ip, 16),
                     authority=source, ordinal=counts[name], phase=active, line=line)
        if name == "write":
            assert source == "source", line
            mark = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args)
            if mark:
                assert result == "1" and read and not done, line
                token = chr(int(mark[1], 16))
                markers.append(token)
                if token == "D":
                    assert active is None, line
                    done = True
                elif token in "NAR":
                    assert active is None and token not in phases, line
                    active = token
                    phases[token] = []
                else:
                    assert token in "nar" and active == token.upper(), line
                    active = None
            else:
                expected = '1, "\\x%02x\\x%02x", 2' % (selector, failed)
                assert done and not reported and args == expected and result == "2", line
                reported = True
        elif name == "read":
            if source == "source":
                assert not read and not markers and active is None, line
                assert args == '0, "\\x%02x", 1' % selector and result == "1", line
                read = True
            else:
                assert source == "native" and not markers, line
        else:
            assert source in ("source", "native", "bootstrap-" + name), line
            if source == "source":
                assert not done, ("source memory operation after cleanup", line)
            memory.append(line + "\n")
            if active:
                phases[active].append(event)
        events.append(event)
    assert done and active is None and read and reported, "missing owner checkpoints"
    expected = ("Nn" if selector in (2, 3) else "") + "Aa" + ("Rr" if failed else "") + "D"
    assert "".join(markers) == expected, markers
    for name, phase in phases.items():
        OWNERS.source_maps("".join(e["line"] + "\n" for e in phase), authority, directory)
    whole = OWNERS.source_maps("".join(memory), authority, directory)
    return dict(events=events, phases=phases, source=whole, markers="".join(markers))


def run(executable, authority, directory, selector, injection=None, expected_attempt=None, baseline_attempts=None):
    directory.mkdir()
    trace = directory / "trace"
    command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx",
               "-e", "signal=none", "-e", "trace=mmap,munmap,read,write", "-o", str(trace)]
    if injection is not None:
        command += ["-e", f"inject=mmap:error=ENOMEM:when={injection}"]
    command.append(str(executable))
    completed = subprocess.run(command, input=bytes([selector]), capture_output=True, timeout=6)
    failed = int(injection is not None)
    assert completed.returncode == 0, (selector, injection, completed, trace.read_text())
    assert completed.stdout == bytes([selector, failed]), completed
    expected = (b"Nn" if selector in (2, 3) else b"") + b"Aa" + (b"Rr" if failed else b"") + b"D"
    assert completed.stderr == expected, completed
    ledger = inspect(trace.read_text(), authority, directory, selector, failed)
    active = [e for e in ledger["phases"]["A"] if e["name"] == "mmap" and e["authority"] == "source"]
    marked = [e for e in ledger["events"] if "INJECTED" in e["result"] or "POKED" in e["result"]]
    if injection is None:
        assert not marked and 1 <= len(active) <= 8, (marked, active)
        assert all(e["result"].startswith("0x") for e in active), active
        # The full traversal reserves labels and (Dijkstra only) one queue.
        # Repeated tentative improvements in this graph need no loop growth.
        if selector in (2, 3):
            assert len(active) == (2 if selector == 2 else 1), active
        return [e["ordinal"] for e in active]
    assert len(marked) == 1 and marked[0] == active[-1], marked
    fault = marked[0]
    assert fault["ordinal"] == injection and fault["result"].startswith("-1 ENOMEM "), fault
    assert len(active) == expected_attempt, active
    retried = [e for e in ledger["phases"]["R"] if e["name"] == "mmap" and e["authority"] == "source"]
    assert len(retried) == baseline_attempts and all(e["result"].startswith("0x") for e in retried), retried
    return None


def controls():
    pairs = NATIVE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}
    pairs.executable_ranges = [(0x401000, 0x401040)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022, 0x401032}
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
    bootstrap = event("mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff30000000", 0x402002)
    bootstrap_release = event("munmap(0x7fff30000000, 8388608) = 0", 0x402012)
    valid = read + mark("A") + allocation + release + mark("a") + mark("D") + report
    with tempfile.TemporaryDirectory(prefix="weighted-owner-controls-") as directory:
        inspect(valid, authority, directory, 0, 0)
        with_bootstrap = inspect(native + bootstrap + valid + bootstrap_release, authority, directory, 0, 0)
        active = [e for e in with_bootstrap["phases"]["A"] if e["name"] == "mmap"]
        assert len(active) == 1 and active[0]["ordinal"] == 3, active
        mutations = [
            valid.replace(release, ""),
            valid.replace(release, release + release),
            valid.replace(", 37) = 0", ", 36) = 0"),
            valid.replace(release, "").replace(mark("D"), release + mark("D")),
            valid.replace("0000000000401002", "0000000000401022"),
            valid.replace("0000000000401002", "0000000000401052"),
            valid.replace("0000000000401012", "00007fff00001000"),
            valid.replace("MAP_PRIVATE|MAP_ANONYMOUS,", "MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,"),
            valid.replace(mark("D"), allocation + mark("D")),
            valid + allocation + release,
            valid.replace(mark("a"), ""),
            valid.replace(report, report + report),
            valid.replace(read, ""),
            valid.rstrip("\n"),
        ]
        for changed in mutations:
            try:
                inspect(changed, authority, directory, 0, 0)
            except (AssertionError, ValueError):
                continue
            raise AssertionError(("weighted owner observer accepted corruption", changed))
    return 2 + len(mutations)


def main():
    checked = controls()
    if sys.argv[1:] == ["controls"]:
        print(f"weighted-graph-owner-controls={checked}")
        return
    assert len(sys.argv) == 2, sys.argv
    executable = Path(sys.argv[1]).resolve()
    authority = NATIVE.verified_sites(executable)
    reached = 0
    with tempfile.TemporaryDirectory(prefix="weighted-owners-") as temporary:
        directory = Path(temporary)
        for selector in range(5):
            positions = run(executable, authority, directory / f"baseline-{selector}", selector)
            for attempt, ordinal in enumerate(positions, 1):
                run(executable, authority, directory / f"failure-{selector}-{attempt}", selector,
                    ordinal, attempt, len(positions))
                reached += 1
    print(f"weighted-graph-owners profiles=5 reached={reached} controls={checked} balanced=yes recovered=yes")


if __name__ == "__main__":
    main()
