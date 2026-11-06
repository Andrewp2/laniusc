"""Independent field selection and exact source-owner/publication observations."""
from collections import Counter
import importlib.util
from pathlib import Path
import os
import random
import re
import subprocess
import sys
import tempfile

INPUT = 1048576
RECORDS = 65536
READ_CALLS = 16384
WRITE_CALLS = 8192
MAX_U64 = (1 << 64) - 1
DIAGNOSTIC = b"select_field: operation failed\n"
TRACE = "mmap,munmap,read,write,rt_sigaction,openat,close"


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
SOURCE = load("select_field_source_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("select_field_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")


def reference(data, delimiter, number, right=False):
    source = data.decode("utf-8")
    pieces = []
    for found in re.finditer(r"[^\n]*\n|[^\n]+$", source):
        line = found[0]
        if line.endswith("\n"):
            line = line[:-1]
            if line.endswith("\r"):
                line = line[:-1]
        # Reverse Unicode scalars, not UTF-8 bytes. Regex supplies independent
        # complete partitions; the program instead pulls bounded lazy cursors.
        if right:
            fields = [piece[::-1] for piece in re.split(re.escape(delimiter[::-1]), line[::-1])]
        else:
            fields = re.split(re.escape(delimiter), line)
        pieces.append(fields[number - 1] if number <= len(fields) else "")
    return ("\n".join(pieces) + ("\n" if pieces else "")).encode("utf-8")


def arguments(delimiter="::", number=2, right=False):
    return ["--delimiter", delimiter, "--field", str(number)] + (["--from-right"] if right else [])


def observe(text, profile, directory, *, help_mode=False):
    events, memory, counts = [], [], Counter()
    eof, published = False, False
    source_reads = 0
    source_writes = Counter()
    for line in text.splitlines():
        match = OWNERS.LINE.fullmatch(line)
        assert match and match[2] in TRACE.split(","), line
        ip, name, args, result = match.groups()
        counts[name] += 1
        authority = SOURCE.classify(profile, int(ip, 16))
        assert authority in ("source", "native", "bootstrap-" + name), (authority, line)
        event = dict(name=name, args=args, result=result, ordinal=counts[name], authority=authority, line=line)
        if name in ("mmap", "munmap"):
            memory.append(line + "\n")
        if authority != "source":
            assert "INJECTED" not in result, ("injection outside source", line)
            continue
        events.append(event)
        if name == "read":
            assert not help_mode and not eof and not published and args.split(",")[0] == "0", line
            requested = int(args.rsplit(",", 1)[1])
            assert 1 <= requested <= 1024, line
            source_reads += 1
            if result.split()[0] == "0":
                eof = True
        elif name == "write":
            descriptor = int(args.split(",")[0])
            assert descriptor in (1, 2), line
            requested = int(args.rsplit(",", 1)[1])
            assert 1 <= requested <= 1024, line
            source_writes[descriptor] += 1
            if descriptor == 1:
                assert help_mode or eof, ("publication before input EOF", line)
                published = True
        elif name == "mmap":
            assert not published, ("allocation during publication", line)
        elif name in ("openat", "close"):
            raise AssertionError(("unexpected source file service", line))
    assert source_reads <= READ_CALLS and source_writes[1] <= WRITE_CALLS and source_writes[2] <= 8
    OWNERS.source_maps("".join(memory), profile, directory)
    return events


class Runner:
    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"select-field-{group}-"))
        self.count = 0
        self.profile = None

    def run(self, name, data=b"", args=None, *, status=0, expected=None, trace=False,
            injections=(), help_mode=False, closed_stdout=False, quiet_error=False):
        directory = self.directory / name
        directory.mkdir()
        source = directory / "input"
        source.write_bytes(data)
        command = [self.executable, *(arguments() if args is None else args)]
        if trace:
            if self.profile is None:
                self.profile = SOURCE.verified_sites(self.executable)
            command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx",
                       "-s", "16", "-e", "signal=none", "-e", "trace=" + TRACE,
                       "-o", str(directory / "trace"), *command]
            for call, position, action in injections:
                at = command.index(self.executable)
                command[at:at] = ["-e", f"inject={call}:{action}:when={position}"]
        with source.open("rb") as input_file:
            if closed_stdout:
                reader, writer = os.pipe()
                os.close(reader)
                try:
                    result = subprocess.run(command, stdin=input_file, stdout=writer,
                                            stderr=subprocess.PIPE, timeout=12)
                finally:
                    os.close(writer)
                stdout = b""
            else:
                result = subprocess.run(command, stdin=input_file, capture_output=True, timeout=12)
                stdout = result.stdout
        wanted = b"" if expected is None else expected
        assert result.returncode == status and stdout == wanted, (name, result.returncode, status, stdout[:160], wanted[:160], result.stderr)
        assert result.stderr == (b"" if status == 0 or quiet_error else DIAGNOSTIC), (name, result.stderr)
        self.count += 1
        if not trace:
            return []
        events = observe((directory / "trace").read_text(), self.profile, directory, help_mode=help_mode)
        marked = [event for event in events if "INJECTED" in event["result"]]
        if injections:
            assert marked, ("unreached injection", name)
            for call, position, action in injections:
                if isinstance(position, int):
                    found = [event for event in marked if event["name"] == call and event["ordinal"] == position]
                    assert len(found) == 1, (name, call, position, found)
                    kind, value = action.split("=", 1)
                    if kind == "retval":
                        assert found[0]["result"].split()[0] == value, (name, action, found)
                    else:
                        assert re.search(r"^-1 " + re.escape(value) + r"\b", found[0]["result"]), (name, action, found)
        else:
            assert not marked
        return events


def model_cases():
    cases = [
        (b"", "::", 1, False), (b"\n", "::", 1, False),
        (b"a::b::c\nx::y::z", "::", 2, False),
        (b"a::b::c\nx::y::z", "::", 2, True),
        (b"::a::::b::\n", "::", 1, False), (b"::a::::b::\n", "::", 2, True),
        (b"ababa\naba\n", "aba", 2, False), (b"ababa\naba\n", "aba", 2, True),
        ("Aé界😀\n\nx".encode(), "", 2, False), ("Aé界😀\n\nx".encode(), "", 2, True),
        ("Aé界😀\n".encode(), "", 5, False), ("Aé界😀\n".encode(), "", 5, True),
        ("é💠界💠🙂\r\nx💠y\r".encode(), "💠", 2, False),
        ("é💠界💠🙂\r\nx💠y\r".encode(), "💠", 1, True),
        (b"a\rb::c\r\nx::y\r", "::", 1, True),
        (b"a\0b::c\0d\nx::\0y\n", "::", 2, False),
        (b"a\tb::c\v\f\n", "::", 1, False),
        ("e\u0301é e\u0301é\n".encode(), "é ", 2, False),
        (b"a::b\n\nc\n", "::", MAX_U64, False),
        (b"a::b\n\nc\n", "", MAX_U64, True),
    ]
    rng = random.Random(0xF1E1D2026)
    alphabet = ["a", "b", "é", "界", "🙂", "\0", "\r", "\t", "e\u0301"]
    delimiters = ["", "a", "ab", "aa", "::", "界", "🙂é", "\r", "e\u0301"]
    for index in range(24):
        delimiter = rng.choice(delimiters)
        records = []
        for _ in range(1 + index % 7):
            cells = ["".join(rng.choice(alphabet) for _ in range(rng.randrange(6))) for _ in range(rng.randrange(1, 7))]
            records.append(delimiter.join(cells))
        source = "\n".join(records) + ("\n" if index % 3 else "")
        cases.append((source.encode(), delimiter, 1 + index % 7, bool(index % 2)))
    return cases


def model(runner):
    for index, (data, delimiter, number, right) in enumerate(model_cases()):
        runner.run(f"case-{index}", data, arguments(delimiter, number, right),
                   expected=reference(data, delimiter, number, right))


def admission(runner):
    invalid = [
        [], ["--delimiter", "::"], ["--field", "1"],
        ["--delimiter", "::", "--field", "0"], ["--delimiter", "::", "--field", "-1"],
        ["--delimiter", "::", "--field", "+1"], ["--delimiter", "::", "--field", " 1"],
        ["--delimiter", "::", "--field", "1x"], ["--delimiter", "::", "--field", str(MAX_U64 + 1)],
        ["--delimiter", "::", "--field", "0" * 65 + "1"],
        ["--delimiter", "::", "--field", "1", "--field", "2"],
        ["--delimiter", "::", "--field", "1", "--delimiter", ","],
        ["--delimiter", "::", "--field", "1", "--from-right", "--from-right"],
        ["--delimiter", "::", "--field", "1", "operand"], ["--unknown"],
        ["--help", "--field", "1"], ["--delimiter", "\n", "--field", "1"],
        [b"--delimiter", b"\xff", b"--field", b"1"],
    ]
    for index, args in enumerate(invalid):
        runner.run(f"arguments-{index}", b"a::b\n", args, status=2)
    for index, data in enumerate([b"\xff", b"a::b\n\xed\xa0\x80", b"a::b\n\xf0\x9f\x99", b"a::b\n\xc0\x80"]):
        runner.run(f"utf8-{index}", data, status=2)
    data = b"a::b::c\n"
    runner.run("short", data, ["-d", "::", "-f", "0002", "-r"], expected=b"b\n")
    runner.run("equals-empty", b"abc\n", ["--delimiter=", "--field=2"], expected=b"a\n")
    runner.run("leading-zero-width", data, ["--delimiter", "::", "--field", "0" * 63 + "1"], expected=b"a\n")
    for index, flag in enumerate(["--help", "-h"]):
        # The full help is not a protocol; check useful content and input bypass.
        completed = subprocess.run([runner.executable, flag], input=b"\xff", capture_output=True, timeout=6)
        assert completed.returncode == 0 and not completed.stderr
        assert completed.stdout.startswith(b"Usage: select_field ") and b"Missing fields emit empty lines." in completed.stdout
        runner.count += 1


def limits(runner):
    runner.run("exact-input", b"a" * INPUT, arguments("::", 1), expected=b"a" * INPUT + b"\n")
    runner.run("excess-input", b"a" * (INPUT + 1), arguments("::", 1), status=2)
    runner.run("exact-records", b"\n" * RECORDS, arguments("::", 1), expected=b"\n" * RECORDS)
    runner.run("excess-records", b"\n" * (RECORDS + 1), arguments("::", 1), status=2)
    delimiter = "x" * 1024
    data = ("a" + delimiter + "b\n").encode()
    runner.run("exact-delimiter", data, arguments(delimiter, 2), expected=b"b\n")
    runner.run("excess-delimiter", data, arguments(delimiter + "x", 2), status=2)
    runner.run("unterminated-cr", b"left::right\r", arguments("::", 2), expected=b"right\r\n")
    runner.run("empty-last-record", b"a::b\n\n", expected=b"b\n\n")


def resources(runner):
    data = (("left::" + "é" * 1200 + "::tail\r\n") * 3).encode()
    expected = reference(data, "::", 2)
    base = runner.run("baseline", data, expected=expected, trace=True)
    allocations = [event for event in base if event["name"] == "mmap"]
    assert allocations and all(event["result"].startswith("0x") for event in allocations)
    for index, event in enumerate(allocations):
        runner.run(f"oom-{index}", data, status=4, trace=True,
                   injections=(("mmap", event["ordinal"], "error=ENOMEM"),))
    reads = [event for event in base if event["name"] == "read"]
    writes = [event for event in base if event["name"] == "write" and event["args"].startswith("1,")]
    signal = next(event for event in base if event["name"] == "rt_sigaction")
    assert len(reads) > 1 and len(writes) > 1
    runner.run("read-eio", data, status=3, trace=True, injections=(("read", reads[0]["ordinal"], "error=EIO"),))
    runner.run("read-late-eio", data, status=3, trace=True, injections=(("read", reads[1]["ordinal"], "error=EIO"),))
    runner.run("read-eintr", data, expected=expected, trace=True, injections=(("read", reads[0]["ordinal"], "error=EINTR"),))
    runner.run("write-eio", data, status=5, trace=True, injections=(("write", writes[0]["ordinal"], "error=EIO"),))
    runner.run("write-late-eio", data, status=5, expected=expected[:1024], trace=True,
               injections=(("write", writes[1]["ordinal"], "error=EIO"),))
    runner.run("write-zero", data, status=5, trace=True, injections=(("write", writes[0]["ordinal"], "retval=0"),))
    runner.run("write-eintr", data, expected=expected, trace=True, injections=(("write", writes[0]["ordinal"], "error=EINTR"),))
    runner.run("signal-eio", data, status=3, trace=True, injections=(("rt_sigaction", signal["ordinal"], "error=EIO"),))
    read_budget = runner.run("read-budget", data, status=2, trace=True,
               injections=(("read", f'{reads[0]["ordinal"]}+', "error=EINTR"),))
    assert sum(event["name"] == "read" for event in read_budget) == READ_CALLS
    write_budget = runner.run("write-budget", data, status=5, trace=True, quiet_error=True,
               injections=(("write", f'{writes[0]["ordinal"]}+', "error=EINTR"),))
    assert sum(event["name"] == "write" and event["args"].startswith("1,") for event in write_budget) == WRITE_CALLS
    assert sum(event["name"] == "write" and event["args"].startswith("2,") for event in write_budget) == 8
    runner.run("closed-stdout", b"a::b\n", status=5, trace=True, closed_stdout=True)
    runner.run("closed-stdout-empty", b"", trace=True, closed_stdout=True)
    return len(allocations)


def controls():
    assert reference(b"ababa\n", "aba", 2) == b"ba\n"
    assert reference(b"ababa\n", "aba", 2, True) == b"ab\n"
    assert reference("Aé界😀\r\n".encode(), "", 2, True) == "😀\n".encode()
    assert reference(b"a::b::c\n", "::", 2) == b"b\n"
    assert reference(b"left::right\r", "::", 2) == b"right\r\n"
    assert reference(b"\n", "", MAX_U64) == b"\n"
    pairs = SOURCE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}
    pairs.executable_ranges = [(0x401000, 0x401030)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022}
    pairs.bootstrap_sites = {0x402002: "bootstrap-mmap", 0x402012: "bootstrap-munmap"}
    pairs.image_ranges = [(0x401000, 0x403000)]
    profile = pairs, []
    def event(line, ip=0x401022):
        return f"[{ip:016x}] {line}\n"
    allocate = event("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", 0x401002)
    release = event("munmap(0x7fff10000000, 37) = 0", 0x401012)
    eof = event('read(0, "", 1024) = 0')
    output = event('write(1, "\\x0a", 1) = 1')
    valid = allocate + eof + output + release
    native = event("mmap(NULL, 8388608, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000", 0x402002)
    native_end = event("munmap(0x7fff20000000, 8388608) = 0", 0x402012)
    with tempfile.TemporaryDirectory(prefix="select-field-controls-") as directory:
        observe(valid, profile, directory)
        observe(native + valid + native_end, profile, directory)
        mutations = [
            allocate + output + eof + release,
            valid.replace(release, ""),
            valid + release,
            valid.replace("0000000000401002", "0000000000401052"),
            eof + output + allocate + release,
            valid + eof,
            event("read(3, \"\", 16) = -1 EIO (Input/output error) (INJECTED)", 0x7fff00001000) + valid,
        ]
        for altered in mutations:
            try:
                observe(altered, profile, directory)
            except (AssertionError, ValueError):
                continue
            raise AssertionError(("field observer admitted corruption", altered))
    return 6 + 2 + len(mutations)


GROUPS = dict(model=model, admission=admission, limits=limits, resources=resources)


def main():
    assert controls() == 15
    if sys.argv[1:] == ["controls"]:
        print(f"select-field-controls=15 model={len(model_cases())} admission=27 limits=8 resources=13+A")
        return
    assert len(sys.argv) == 3 and sys.argv[1] in GROUPS, sys.argv
    group = sys.argv[1]
    runner = Runner(sys.argv[2], group)
    allocations = GROUPS[group](runner) or 0
    expected = dict(model=len(model_cases()), admission=27, limits=8, resources=13 + allocations)[group]
    assert runner.count == expected, (group, runner.count, expected)
    print(f"select-field-{group} cases={runner.count} reached_allocations={allocations} evidence={runner.directory}")


if __name__ == "__main__":
    main()
