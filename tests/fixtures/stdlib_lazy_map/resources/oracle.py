"""Reached OOM recovery with exact current-runtime source allocation authority.

Native loader and CRT mappings are classified separately, never counted as
Lanius owners. The existing ledger verifies full-width addresses, requested
lengths, flags and matching releases. This adapter adds operation phases only.
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
NATIVE = load("lazy_map_source_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("lazy_map_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")


def inspect(text, profile, directory):
    assert text.endswith("\n"), "truncated lazy-map trace"
    counts, events, phases, memory = Counter(), [], {}, []
    active, markers, done = None, [], False
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match, ("unsupported lazy-map trace", line)
        ip, name, args, result = match.groups()
        assert name in ("mmap", "munmap", "write"), line
        authority = NATIVE.classify(profile, int(ip, 16))
        counts[name] += 1
        event = dict(name=name, args=args, result=result, ip=int(ip, 16),
                     authority=authority, ordinal=counts[name], phase=active, line=line)
        if name == "write":
            assert authority == "source" and result == "1", line
            mark = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args)
            if mark:
                token = chr(int(mark[1], 16))
                markers.append(token)
                assert not done, line
                if token == "D":
                    assert active is None, line
                    done = True
                elif token in "HMAR":
                    assert active is None and token not in phases, line
                    active = token
                    phases[token] = []
                else:
                    assert token in "hmar" and active == token.upper(), line
                    active = None
            else:
                assert done and re.fullmatch(r'1, "\\x0[0-4]", 1', args), line
        else:
            assert authority in ("source", "native", "bootstrap-" + name), line
            if authority == "source":
                assert not done, ("source allocation after final cleanup", line)
            memory.append(line + "\n")
            if active:
                phases[active].append(event)
        events.append(event)
    assert done and active is None, "missing cleanup checkpoint"
    assert "".join(markers) in ("HhMmAaD", "HhMmAaRrD"), markers
    assert not any(e["authority"] == "source" for e in phases["H"]), "occupied update allocated or released source storage"
    # A mismatched candidate must be fully released before the next operation.
    mismatch = "".join(e["line"] + "\n" for e in phases["M"])
    OWNERS.source_maps(mismatch, profile, directory)
    whole = OWNERS.source_maps("".join(memory), profile, directory)
    return dict(events=events, phases=phases, source=whole, markers="".join(markers))


def run(executable, profile, directory, expected, injection=None):
    directory.mkdir()
    trace = directory / "trace"
    command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx",
               "-e", "signal=none", "-e", "trace=mmap,munmap,write", "-o", str(trace)]
    if injection is not None:
        command += ["-e", f"inject=mmap:error=ENOMEM:when={injection}"]
    command.append(str(executable))
    completed = subprocess.run(command, input=b"", capture_output=True, timeout=6)
    assert completed.returncode == 0, (expected, completed, trace.read_text())
    assert completed.stdout == bytes([expected]), (expected, completed)
    assert completed.stderr == (b"HhMmAaRrD" if expected else b"HhMmAaD"), completed
    ledger = inspect(trace.read_text(), profile, directory)
    source_allocs = [e for e in ledger["events"] if e["name"] == "mmap" and e["authority"] == "source"]
    active = [e for e in source_allocs if e["phase"] == "A"]
    marked = [e for e in ledger["events"] if "INJECTED" in e["result"] or "POKED" in e["result"]]
    if injection is None:
        assert not marked and len(active) == 4, (marked, active)
        assert all(e["result"].startswith("0x") for e in active), active
        return [e["ordinal"] for e in active]
    assert len(marked) == 1 and marked[0] == active[-1], marked
    failed = marked[0]
    assert failed["ordinal"] == injection and failed["result"].startswith("-1 ENOMEM "), failed
    assert len(active) == expected and len([e for e in source_allocs if e["phase"] == "R"]) == (1 if expected == 4 else 4), source_allocs
    if expected < 4:
        # Failed partial construction cannot carry an unreported owner to retry.
        failed_phase = "".join(e["line"] + "\n" for e in ledger["phases"]["A"])
        OWNERS.source_maps(failed_phase, profile, directory)
    return None


def controls():
    pairs = NATIVE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}
    pairs.executable_ranges = [(0x401000, 0x401030)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022}
    pairs.bootstrap_sites = {0x402002: "bootstrap-mmap", 0x402012: "bootstrap-munmap"}
    pairs.image_ranges = [(0x401000, 0x403000)]
    profile = pairs, []

    def event(value, ip=0x401022):
        return f"[{ip:016x}] {value}\n"

    def mark(token):
        return event('write(2, "\\x%02x", 1) = 1' % ord(token))

    allocation = event("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", 0x401002)
    release = event("munmap(0x7fff10000000, 37) = 0", 0x401012)
    native = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000", 0x7fff00001000)
    bootstrap = event("mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff30000000", 0x402002)
    bootstrap_release = event("munmap(0x7fff30000000, 8388608) = 0", 0x402012)
    valid = mark("H") + mark("h") + mark("M") + allocation + release + mark("m") + mark("A") + mark("a") + mark("D")
    with tempfile.TemporaryDirectory(prefix="lazy-map-ledger-controls-") as directory:
        inspect(valid, profile, directory)
        inspect(native + bootstrap + valid + bootstrap_release, profile, directory)
        mutations = [
            valid.replace(release, ""),
            valid.replace(release, release + release),
            valid.replace(", 37) = 0", ", 36) = 0"),
            valid.replace(release, "").replace(mark("A"), release + mark("A")),
            valid.replace(mark("h"), allocation + release + mark("h")),
            valid.replace("0000000000401002", "0000000000401022"),
            valid.replace("0000000000401002", "0000000000401052"),
            valid.replace("0000000000401012", "00007fff00001000"),
            valid.replace("MAP_PRIVATE|MAP_ANONYMOUS,", "MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT,"),
            valid.replace(mark("D"), allocation + mark("D")),
            valid + allocation + release,
            valid.replace(mark("m"), ""),
        ]
        for changed in mutations:
            try:
                inspect(changed, profile, directory)
            except (AssertionError, ValueError):
                continue
            raise AssertionError(("lazy-map owner observer accepted corruption", changed))
    return 2 + len(mutations)


def main():
    if sys.argv[1:] == ["controls"]:
        print(f"lazy-map-owner-controls={controls()}")
        return
    assert len(sys.argv) == 3 and sys.argv[2] in ("hash", "tree"), sys.argv
    assert controls() == 14
    executable = Path(sys.argv[1]).resolve()
    profile = NATIVE.verified_sites(executable)
    with tempfile.TemporaryDirectory(prefix="lazy-map-owners-") as temporary:
        directory = Path(temporary)
        positions = run(executable, profile, directory / "baseline", 0)
        for expected, ordinal in enumerate(positions, 1):
            run(executable, profile, directory / f"failure-{expected}", expected, ordinal)
    print(f"lazy-map-{sys.argv[2]}-owners cases=5 reached=4 recovered=4 balanced=yes")


if __name__ == "__main__":
    main()
