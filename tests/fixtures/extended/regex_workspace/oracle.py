"""Finite independent semantics and verified pre-exit Workspace ownership.

The endpoint oracle and exact raw-ELF/source ledgers are reused, not translated
from the new matcher. Python here is only fixture generation/test transport.
"""
import importlib.util
from pathlib import Path
import os
import re
import select
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


HERE = Path(__file__).resolve().parent
ENDPOINTS = load("regex_workspace_independent_endpoints", HERE.parent / "lexer/reference.py")
LEDGER = load("regex_workspace_source_ledger", HERE.parent / "archive_source/ledger.py")
MAGIC = 1380406097


def case(pattern, text, *, mode=0, layout=0, start=0, flags=0, work=100000, expected=None):
    return dict(pattern=pattern, text=text, mode=mode, layout=layout, start=start,
                flags=flags, work=work, expected=expected)


def reference(row):
    if row["expected"] is not None:
        return row["expected"]
    text, pattern = row["text"], row["pattern"].replace(r"\z", r"\Z")
    offsets = [len(text[:at].encode()) for at in range(len(text) + 1)]
    if row["start"] not in offsets:
        return "E5:0"
    position = offsets.index(row["start"])
    flags = re.ASCII | (re.MULTILINE if row["flags"] & 1 else 0) | (re.DOTALL if row["flags"] & 2 else 0)
    if row["mode"] & 1:
        found = ENDPOINTS.maximal(pattern, text, position, flags)
    else:
        found = re.compile(pattern, flags).search(text, position)
    if found is None:
        return "N"
    groups = range(1 if row["mode"] >= 2 else len(found.groups()) + 1)
    spans = []
    for group in groups:
        begin, end = found.span(group)
        spans.append("-" if begin < 0 else f"{offsets[begin]}:{offsets[end]}")
    return "P" + "/".join(spans)


def model_cases():
    # Ordering is deliberate: a populated result precedes misses, errors and
    # smaller capture dimensions on the SAME explicit Workspace owner.
    rows = [case("(a)(b)?", "ab"), case("(a)(b)?", "a"),
            case("(a|aa)(a?)(b?)(c?)", "aa", mode=1),
            case("a", "a", mode=2), case("(a)(b)?", "x"),
            case("a", "a", work=1, expected="E7:0"), case("a", "a"),
            case(".", "é🙂", start=1), case(".", "é🙂", start=-1),
            case(".", "é🙂", start=2147483647), case(".", "é🙂", start=2, mode=3)]
    patterns = ["a|ab", "a+?", "(a)?(b?)", "(a|aa)(a?)", "[a-z]+", "é|é🙂",
                "(?:é|🙂)+?", r"\Aa", r"\ba", r"a\z", ".", "(?:ab|a)(b?)"]
    texts = ["", "a", "ab", "aaab", "ba", "é🙂é", "x\na", "a\0b"]
    axes = set()
    for p, pattern in enumerate(patterns):
        for t, text in enumerate(texts):
            boundaries = [len(text[:at].encode()) for at in range(len(text) + 1)]
            for mode in range(4):
                start = (0, boundaries[len(boundaries) // 2], boundaries[-1])[(p + t + mode) % 3]
                for layout in range(2):
                    rows.append(case(pattern, text, mode=mode, layout=layout, start=start))
                    axes.add((mode, layout))
    assert len(axes) == 8
    for flags in (1, 2, 3):
        for mode in range(4):
            for layout in range(2):
                rows.append(case("^a$", "x\na\nz", start=2, flags=flags, mode=mode, layout=layout))
                rows.append(case("(.)(.)?", "a\nb", flags=flags, mode=mode, layout=layout))
    # Canonical Pike nullable cycles intentionally have their OWN known results;
    # Python's repeat-capture policy is not substituted for these contracts.
    for pattern, text, mode, expected in (
        ("(a?)*", "aa", 1, "P0:2/1:2"),
        ("(?:|a)*", "aa", 1, "P0:2"),
        ("(?:|a)*", "aa", 0, "P0:0"),
        ("a??", "a", 0, "P0:0"), ("a??", "a", 1, "P0:1"),
        ("(a|aa)(a?)", "aa", 1, "P0:2/0:1/1:2")):
        for layout in range(2):
            rows.append(case(pattern, text, mode=mode, layout=layout, expected=expected))
    return rows


def semantics(executable):
    rows = model_cases()
    request = bytearray()
    for row in rows:
        pattern, text = row["pattern"].encode(), row["text"].encode()
        words = (len(pattern), len(text), row["mode"], row["layout"], row["start"], row["flags"], row["work"])
        request.extend(struct.pack("<7I", *(word & 0xffffffff for word in words)))
        request.extend(pattern + text)
    output = subprocess.run([str(executable)], input=request, capture_output=True, timeout=35)
    assert output.returncode == 0 and not output.stderr, (output.returncode, output.stderr, output.stdout[-200:])
    actual = output.stdout.decode("ascii").splitlines()
    assert len(actual) == len(rows), (len(actual), len(rows))
    for index, (row, value) in enumerate(zip(rows, actual)):
        assert value == reference(row), (index, row, value, reference(row))
    print(f"PASS regex-workspace semantics cases={len(rows)}")


def read_exact(fd, count, deadline):
    output = bytearray()
    while len(output) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0, ("checkpoint read deadline", len(output), count)
        ready, _, _ = select.select([fd], [], [], remaining)
        assert ready, ("checkpoint read timeout", len(output), count)
        part = os.read(fd, count - len(output))
        assert part, ("checkpoint EOF", len(output), count)
        output.extend(part)
    return bytes(output)


def checkpoint(trace, output, deadline):
    while True:
        try:
            return LEDGER.output_prefix(trace.read_text(), bytes(output))
        except (LEDGER.CheckpointPending, FileNotFoundError):
            assert time.monotonic() < deadline, "trace checkpoint timeout"
            time.sleep(0.002)


class Suite:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix=f"lanius-regex-workspace-{group}-"))
        self.profile = LEDGER.TRUSTED.verified_sites(self.executable, self.directory)
        self.deadline = time.monotonic() + 75
        self.count = 0
        print(f"evidence={self.directory}", flush=True)

    def run(self, *, constructor=False, injection=None, baseline=None):
        assert time.monotonic() < self.deadline, "workspace group deadline"
        directory = self.directory / f"{self.count:02d}"
        directory.mkdir()
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-o", str(trace),
                   "-e", "trace=" + LEDGER.TRACE]
        if injection is not None:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={injection}"]
        command.append(str(self.executable))
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=directory)
        deadline = min(self.deadline, time.monotonic() + 7)
        output = bytearray()
        checkpoints = []
        original = {}
        try:
            for phase in ((1, 3) if constructor else (1, 2, 3)):
                frame = read_exact(process.stdout.fileno(), 64, deadline)
                output.extend(frame)
                magic, pid, received, status, states, groups, owned, work = struct.unpack("<8Q", frame)
                assert (magic, received) == (MAGIC, phase), (magic, received, phase)
                assert status == (4 if injection is not None else 0), status
                prefix = checkpoint(trace, output, deadline)
                live = LEDGER.source(prefix, self.profile)
                LEDGER.no_host_effects(live["events"])
                ranges = LEDGER.process_owners(pid, live["live"])
                if phase == 1:
                    if constructor:
                        if injection is None:
                            assert (states, groups) == (17, 5) and len(live["attempts"]) == 9
                            assert sum(live["live"].values()) == owned
                            assert owned > 0 and work == 0
                        else:
                            assert (states, groups, owned, work) == (0, 0, 0, 0)
                            assert not live["live"], live
                    else:
                        assert (states, groups) == (128, 8) and owned > 0
                        assert len(live["live"]) >= 9 and sum(live["live"].values()) >= owned
                    original = dict(live["live"])
                elif phase == 2:
                    assert (states, groups) == (128, 8) and owned > 0
                    assert live["live"] == original, ("workspace probe changed mapping owners", original, live)
                    earlier = checkpoints[-1]["events"]
                    assert not any(item["name"] in ("mmap", "munmap") for item in live["events"][len(earlier):]), live
                else:
                    assert (states, groups, owned) == (0, 0, 0), (states, groups, owned)
                    assert not live["live"], ("owner survived explicit cleanup", live)
                    for pointer, count in original.items():
                        assert not any(begin < pointer + count and pointer < end for begin, end in ranges), (pointer, count, ranges)
                    LEDGER.TRUSTED.source_maps(prefix, self.profile, directory)
                checkpoints.append(live)
                if injection is not None:
                    marked = [item for item in live["events"] if "INJECTED" in item["result"]]
                    assert len(marked) == 1 and marked[0]["name"] == "mmap" and marked[0]["ordinal"] == injection, marked
                    assert marked[0]["result"].split()[:2] == ["-1", "ENOMEM"], marked
                    attempts = live["attempts"]
                    assert len(attempts) == injection
                    for item, old in zip(attempts, baseline):
                        assert (item["ip"], item["args"], item["ordinal"]) == (old["ip"], old["args"], old["ordinal"]), (item, old)
                assert os.write(process.stdin.fileno(), b"A") == 1
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            assert process.returncode == (4 if injection is not None else 0) and not rest and not stderr, (process.returncode, rest, stderr)
            (directory / "stdout.bin").write_bytes(output)
            self.count += 1
            return checkpoints
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(output)
            if process.poll() is None:
                process.kill()
            try:
                rest, stderr = process.communicate(timeout=2)
                (directory / "stdout-tail.bin").write_bytes(rest)
                (directory / "stderr.bin").write_bytes(stderr)
            except (ValueError, subprocess.TimeoutExpired):
                pass
            print(f"FAILED evidence={directory}", file=sys.stderr, flush=True)
            raise


def contracts(executable):
    suite = Suite(executable, "contracts")
    suite.run()
    print(f"PASS regex-workspace contracts process-cases={suite.count}")


def allocations(executable):
    suite = Suite(executable, "allocations")
    baseline = suite.run(constructor=True)[0]["attempts"]
    assert len(baseline) == 9
    for attempt in baseline:
        suite.run(constructor=True, injection=attempt["ordinal"], baseline=baseline)
    print(f"PASS regex-workspace allocations process-cases={suite.count} reached-oom={len(baseline)}")


def controls():
    # Existing raw live-map controls cover high/low pointers, wrong post-IPs,
    # flags, release sizes and addresses, double release and stdout binding.
    count = LEDGER.controls()
    for row, expected in (
        (case("a|ab", "ab"), "P0:1"),
        (case("a|ab", "ab", mode=1), "P0:2"),
        (case("(a)?(b?)", "b", mode=2), "P0:1"),
        (case(".", "é🙂", start=1), "E5:0"),
        (case(".", "é🙂", start=2, mode=3), "P2:6"),
        (case(r"\Aa", "ba", start=1, mode=1), "N"),
        (case(r"\ba", "ba", start=1, mode=1), "N")):
        assert reference(row) == expected, (row, reference(row), expected)
        count += 1
    assert len(model_cases()) == 839
    print(f"PASS regex-workspace CPU controls={count}")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
    else:
        assert len(sys.argv) == 3, "oracle.py semantics|contracts|allocations EXECUTABLE; or controls"
        group, executable = sys.argv[1:]
        assert group in ("semantics", "contracts", "allocations")
        globals()[group](Path(executable).resolve())
