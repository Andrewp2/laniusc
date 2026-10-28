"""Finite binary-slicing oracle and focused native syscall faults; test-only."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MAX = (1 << 64) - 1
CAP = 1 << 20
HELP = (b"Usage: sample-bytes [--offset N] [--step N] [--count N] [--reverse] [--help]\n"
        b"Read binary stdin through EOF; reverse if requested, skip offset, step, then take count.\n"
        b"Defaults: offset 0, step 1, count 18446744073709551615. Decimal u64 values; step must be positive.\n"
        b"Short options: -o N, -s N, -n N, -r, -h. Duplicate options are errors.\n"
        b"Limits: 1 MiB input and staged output; 4096 input calls, 4096 output calls.\n")
ERROR = b"sample-bytes: operation failed\n"


def expected(data, offset=0, step=1, count=MAX, reverse=False):
    """Python bytes slicing is independent of the production cursor chain."""
    assert 0 <= offset <= MAX and 1 <= step <= MAX and 0 <= count <= MAX
    return (data[::-1] if reverse else data)[offset::step][:count]


def events(text):
    found, counts = [], Counter()
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|mmap|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        found.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
    return found


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"sample-bytes-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, output=b"", status=0,
            read_error=False, closed_reader=False, would_block=False,
            trace=False, injection=None, diagnostic=True):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, error, repeat = injection
                action = "retval=0" if error == "ZERO" else "error=" + error
                traced += ["-e", f"inject={call}:{action}:when={ordinal}{'+' if repeat else ''}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=20, check=False)
            finally:
                os.close(descriptor)
        elif would_block:
            reader, writer = os.pipe2(os.O_NONBLOCK)
            try:
                result = subprocess.run(command, stdin=reader, capture_output=True, timeout=20, check=False)
            finally:
                os.close(reader)
                os.close(writer)
        elif closed_reader:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE,
                                        timeout=20, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=20, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status, (name, result.returncode, status, result.stdout[:120], result.stderr)
        assert result.stdout == output, (name, len(result.stdout), len(output), result.stdout[:120], output[:120])
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [entry for entry in found if "INJECTED" in entry["answer"]]
        if injection:
            call, ordinal, error, repeat = injection
            selected = [entry for entry in found if entry["name"] == call and
                        (entry["ordinal"] >= ordinal if repeat else entry["ordinal"] == ordinal)]
            assert selected and marked == selected, (name, "fault not reached exactly", injection, marked)
            for entry in selected:
                assert entry["answer"].startswith("0 " if error == "ZERO" else "-1 " + error + " "), entry
        else:
            assert not marked, (name, marked)
        self.count += 1
        return found

    def model(self, name, data, *, offset=0, step=1, count=MAX, reverse=False, arguments=None):
        if arguments is None:
            arguments = ["--offset", str(offset), "--step", str(step), "--count", str(count)]
            if reverse:
                arguments += ["--reverse"]
        self.run(name, arguments, data, output=expected(data, offset, step, count, reverse))


def model(r):
    binary = bytes(range(256))
    r.model("empty", b"")
    r.model("default-binary-identity", binary, arguments=[])
    r.model("one-byte", b"x")
    r.model("nul-high-bytes", b"\x00\xff\x80\x00\x7f")
    r.model("reverse", binary, reverse=True)
    r.model("offset", b"0123456789", offset=3)
    r.model("step", b"0123456789", step=3)
    r.model("count", b"0123456789", count=4)
    r.model("combined", b"0123456789", offset=1, step=3, count=2)
    r.model("reversed-combined", b"0123456789", offset=1, step=3, count=2, reverse=True)
    r.model("offset-at-end", b"abcd", offset=4)
    r.model("offset-past-end", b"abcd", offset=5)
    r.model("count-zero", binary, count=0)
    r.model("maximum-offset", binary, offset=MAX)
    r.model("maximum-step", binary, step=MAX)
    r.model("maximum-count", binary, count=MAX)
    r.model("all-maximum", binary, offset=MAX, step=MAX, count=MAX, reverse=True)
    r.model("maximum-step-reversed-offset", binary, offset=1, step=MAX, reverse=True)
    maximum = binary * (CAP // len(binary))
    r.model("exact-input-cap-identity", maximum, arguments=[])
    r.model("exact-input-cap-reversed-step", maximum, offset=19, step=257, reverse=True)
    r.model("wide-offset", binary * 300, offset=65536, step=19, count=105)
    r.model("count-greater-than-remaining", b"abcdef", offset=4, step=2, count=1000)
    rng = random.Random(0x5A4D1E)
    for index in range(15):
        data = rng.randbytes(rng.randrange(0, 8193))
        r.model(f"seeded-{index}", data,
                offset=rng.choice([0, 1, len(data), len(data) + 1, rng.randrange(10000), MAX]),
                step=rng.choice([1, 2, 3, 1024, MAX]),
                count=rng.choice([0, 1, 7, 4096, MAX]), reverse=bool(rng.randrange(2)))


def limits(r):
    oversized = b"\x00\xff" * (CAP // 2) + b"!"
    r.run("one-over-input-cap", data=oversized, status=2)
    r.run("count-zero-still-checks-input-cap", ["--count", "0"], oversized, status=2)
    r.run("huge-offset-still-checks-input-cap", ["--offset", str(MAX)], oversized, status=2)


def cli(r):
    invalid = [
        ["file.bin"], ["-"], ["--unknown"], ["--offset"], ["--step"], ["--count"],
        ["--offset", ""], ["--step="], ["--count", ""], ["--offset", "-1"],
        ["--step", "+1"], ["--count", "1.5"], ["--count", " 1"], ["--step", "1_0"],
        ["--offset", "١"], ["--offset", str(MAX + 1)], ["--step", str(MAX + 1)],
        ["--count", str(MAX + 1)], ["--step", "0"],
        ["--offset", "0", "--offset", "1"], ["--step", "1", "-s2"],
        ["--count", "0", "--count", "1"], ["--reverse", "-r"], ["-rr"],
        ["--help", "--help"], ["-hh"], ["--help", "--unknown"], ["--help", "--step", "0"],
        ["--reverse=yes"], ["--help=yes"], ["--", "operand"], [""] * 25,
        ["--count", "0" * 1025],
    ]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-validates-other-options", ["--help", "--reverse", "--step", str(MAX)], output=HELP, read_error=True)
    r.model("short-attached-cluster", b"0123456789", offset=1, step=2, count=3, reverse=True,
            arguments=["-ro1", "-s2", "-n3"])
    r.model("long-equals-leading-zeroes", b"0123456789", offset=1, step=2, count=3,
            arguments=["--offset=001", "--step=002", "--count=003"])
    r.model("bare-terminator", b"\x00\xff", arguments=["--"])


def bind(before, after, call, ordinal):
    old = next(item for item in before if item["name"] == call and item["ordinal"] == ordinal)
    new = next(item for item in after if item["name"] == call and item["ordinal"] == ordinal)
    if call in ("read", "write"):
        assert old["args"].split(",", 1)[0] == new["args"].split(",", 1)[0], (old, new)
        assert old["args"].rsplit(",", 1)[1] == new["args"].rsplit(",", 1)[1], (old, new)
    elif call == "mmap":
        # No argument owner with an empty CLI; these are the actual app allocations.
        assert old["args"] == new["args"], (old, new)
    else:
        assert old["args"].split(",", 1)[0] == new["args"].split(",", 1)[0], (old, new)


def io(r):
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", data=b"\x00\xffbinary", status=5, closed_reader=True)
    r.run("empty-closed-stdout", ["--count", "0"], b"still-read", closed_reader=True)
    r.run("help-closed-stdout", ["--help"], status=5, closed_reader=True)
    data = bytes(range(256)) * 16 + b"!"
    baseline = r.run("native-multi-transfer-baseline", data=data, output=data, trace=True)
    reads = [entry for entry in baseline if entry["name"] == "read"]
    writes = [entry for entry in baseline if entry["name"] == "write"]
    maps = [entry for entry in baseline if entry["name"] == "mmap"]
    assert all(entry["args"].startswith("0, ") for entry in reads)
    assert len(reads) >= 6 and reads[-1]["answer"] == "0", reads
    assert len(writes) == 5 and all(entry["args"].startswith("1, ") for entry in writes), writes
    assert [int(entry["answer"]) for entry in writes] == [1024, 1024, 1024, 1024, 1], writes
    assert len(maps) >= 2 and all(entry["answer"].startswith("0x") for entry in maps), maps
    assert baseline.index(reads[0]) < baseline.index(maps[0]), "first allocation must follow actual stdin data"
    assert baseline.index(reads[-1]) < baseline.index(maps[-1]) < baseline.index(writes[0]), "last allocation must stage output after EOF"
    faults = [
        ("read-eintr", "read", 1, "EINTR", 0, data),
        ("write-eintr", "write", 1, "EINTR", 0, data),
        ("read-eio", "read", 1, "EIO", 3, b""),
        ("write-eio-after-real-prefix", "write", 2, "EIO", 5, data[:1024]),
        ("zero-write", "write", 1, "ZERO", 5, b""),
        ("input-allocation-denied", "mmap", 1, "ENOMEM", 4, b""),
        ("output-reservation-denied", "mmap", len(maps), "ENOMEM", 4, b""),
        ("signal-setup-denied", "rt_sigaction", 1, "EIO", 5, b""),
    ]
    for name, call, ordinal, error, status, output in faults:
        actual = r.run(name, data=data, status=status, output=output, trace=True,
                       injection=(call, ordinal, error, False), diagnostic=call != "rt_sigaction")
        bind(baseline, actual, call, ordinal)
    actual = r.run("read-interruption-cap", data=data, status=2, trace=True,
                   injection=("read", 1, "EINTR", True))
    assert len([entry for entry in actual if entry["name"] == "read"]) == 4096
    assert all(entry["args"].startswith("0, ") for entry in actual if entry["name"] == "read")
    actual = r.run("write-interruption-cap", data=data, status=5, trace=True,
                   injection=("write", 1, "EINTR", True), diagnostic=False)
    assert len([entry for entry in actual if entry["name"] == "write" and entry["args"].startswith("1, ")]) == 4096
    assert len([entry for entry in actual if entry["name"] == "write" and entry["args"].startswith("2, ")]) == 8
    r.run("actual-would-block-input", status=3, would_block=True)


def controls():
    assert len(HELP) == 412 and len(ERROR) == 31
    assert expected(b"0123456789", 1, 3, 2, True) == b"85"
    assert expected(b"\x00\xff\x80\x7f", 1, 2, MAX) == b"\xff\x7f"
    assert expected(b"abc", MAX, MAX, MAX) == b""
    assert expected(b"abc", 0, MAX, MAX) == b"a"
    assert expected(b"abc", 0, 1, 0, True) == b""
    parsed = events('read(0, "a", 1024) = -1 EINTR (Interrupted system call) (INJECTED)\n'
                    'mmap(NULL, 4097, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1234\n'
                    'write(1, "a", 1) = 1\n')
    assert [item["name"] for item in parsed] == ["read", "mmap", "write"]
    class CounterOnly:
        def __init__(self):
            self.count = 0
        def run(self, *args, **kwargs):
            self.count += 1
        def model(self, *args, **kwargs):
            self.count += 1
    for function, count in ((model, 37), (limits, 3), (cli, 39)):
        runner = CounterOnly()
        function(runner)
        assert runner.count == count, (function.__name__, runner.count, count)
    print("sample-bytes CPU controls=8")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "limits": limits, "cli": cli, "io": io}[mode](runner)
        print(f"sample-bytes-{mode} cases={runner.count} evidence={runner.directory}")
