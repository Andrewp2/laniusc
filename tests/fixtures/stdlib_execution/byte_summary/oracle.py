"""Independent binary-byte summaries and selected reached native I/O faults."""
from collections import Counter
import csv
from io import StringIO
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 4 << 20
HEADER = ("count", "sum", "min", "max", "first", "last")
HELP = (b"Usage: byte-summary [--batch N] [--reverse] [--help]\n"
        b"Read binary stdin through EOF; summarize bytes with bounded fallible iterator folds.\n"
        b"Output CSV: count,sum,min,max,first,last; reverse changes traversal first/last.\n"
        b"Batch: 1..1048576 (default 4096). Empty byte fields are blank for empty input.\n"
        b"Short options: -b N, -r, -h. Duplicate options are errors.\n"
        b"Limits: 4 MiB input, 16384 read calls, 8388608 fold calls, 4096 staged output bytes.\n")
ERROR = b"byte-summary: operation failed\n"
COUNTS = {"model": 40, "bounds": 1, "cli": 32, "io": 14}


def encode(rows):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL, lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode("ascii")


def summary(data, reverse=False):
    """Builtins over the byte sequence; no fold/batching implementation."""
    if not data:
        fields = (0, 0, "", "", "", "")
    else:
        fields = (len(data), sum(data), min(data), max(data),
                  data[-1] if reverse else data[0], data[0] if reverse else data[-1])
    return encode([HEADER, fields])


def pattern(length):
    block = bytes((index * 73 + 19) % 256 for index in range(256))
    return (block * ((length + 255) // 256))[:length]


def events(text):
    found, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        found.append(item)
        if name == "mmap":
            item["size"] = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, (line, live)
                live[address] = item["size"]
            else:
                assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk"):
            raise AssertionError(("unexpected allocation service", line))
    assert not live, ("observed unreleased mappings", live)
    return found


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"byte-summary-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, reverse=False,
            output=None, read_error=False, closed_reader=False, trace=False,
            injection=None, diagnostic=True, persistent_interrupts=False):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if persistent_interrupts:
            # Summary-only tracing avoids retaining 16384 repetitive lines.
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=read",
                       "-e", "inject=read:error=EINTR:when=1+", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,munmap,mremap,brk,rt_sigaction",
                      "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=25, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE,
                                        timeout=25, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=25, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status, (name, result.returncode, status, result.stdout[:120], result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        if output is None:
            output = b"" if status else summary(data, reverse)
        assert result.stdout == output, (name, result.stdout[:180], output[:180])
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, injection, marked)
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        if persistent_interrupts:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            read_rows = [row.split() for row in rows if row.split()[-1:] == ["read"]]
            assert len(read_rows) == 1 and read_rows[0][-3:] == ["16384", "16384", "read"], rows
        self.count += 1
        return found

    def model(self, name, data, *, batch=None, reverse=False, arguments=None):
        if arguments is None:
            arguments = []
            if batch is not None:
                arguments += ["--batch", str(batch)]
            if reverse:
                arguments += ["--reverse"]
        self.run(name, arguments, data, reverse=reverse)


def model(r):
    r.model("empty", b"")
    r.model("empty-reverse", b"", batch=1, reverse=True)
    r.model("single-zero", b"\x00", batch=1)
    r.model("single-maximum", b"\xff", batch=2)
    r.model("single-reverse", b"*", batch=1, reverse=True)
    binary = b"\x00\xff\x80\xc0\x00\n\r,\"\xfe"
    r.model("raw-binary", binary, batch=3)
    r.model("raw-binary-reverse", binary, batch=3, reverse=True)
    r.model("every-byte", bytes(range(256)), batch=255)
    r.model("every-byte-reverse", bytes(range(256)), batch=256, reverse=True)
    r.model("one-byte-batches", b"\x09\x01\xfe\x00\x07", batch=1)
    r.model("one-byte-batches-reverse", b"\x09\x01\xfe\x00\x07", batch=1, reverse=True)
    for length in (6, 7, 8, 14, 15):
        for reverse in (False, True):
            r.model(f"seven-boundary-{length}-{int(reverse)}", pattern(length), batch=7, reverse=reverse)
    for length in (4095, 4096, 4097):
        r.model(f"default-boundary-{length}", pattern(length))
    r.model("maximum-batch-exact", pattern(1048576), batch=1048576)
    r.model("maximum-batch-plus-one-reverse", pattern(1048576) + b"*", batch=1048576, reverse=True)
    r.model("exact-input-cap", b"\xff" * CAP)
    r.model("batch-larger-than-input", b"\x09\x01\x07", batch=1048576)
    r.model("zero-filled-multiple-batches", b"\x00" * 8193, batch=4096)
    r.model("maximum-byte-multiple-batches", b"\xff" * 8193, batch=4096, reverse=True)
    rng = random.Random(0xB17E5)
    for index in range(10):
        data = bytes(rng.randrange(256) for _ in range(rng.randrange(0, 8193)))
        r.model(f"seeded-{index}", data, batch=rng.choice([1, 2, 3, 7, 255, 256, 4096, 1048576]), reverse=bool(index % 2))


def bounds(r):
    r.run("input-over-cap", data=b"\x00" * CAP + b"\xff", status=2)


def cli(r):
    invalid = [
        ["--batch"], ["--batch", "0"], ["--batch", "1048577"], ["--batch", "-1"],
        ["--batch", "+1"], ["--batch", "1.0"], ["--batch", ""], ["--batch", "18446744073709551616"],
        ["--batch", " 1"], ["--batch", "1 "], ["--unknown"], ["input.bin"],
        ["--batch", "1", "-b2"], ["--reverse", "--reverse"], ["-rr"],
        ["--help", "--help"], ["-hh"], ["--batch=yes"], ["--reverse=yes"], ["--help=yes"],
        ["--help", "--batch", "0"], ["--", "operand"], [""] * 25,
        ["--batch", "0" * 1025], ["-x"], ["--batch", "-r"],
    ]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-valid-options", ["--batch", "1048576", "--reverse", "--help"], output=HELP, read_error=True)
    r.model("short-attached-leading-zero", b"\x03\x00\xff", reverse=True, arguments=["-b0007", "-r"])
    r.model("long-equals-leading-zero", b"\x03\x00\xff", batch=1, arguments=["--batch=0001"])
    r.run("duplicate-reverse-alias", ["--reverse", "-r"], status=2, read_error=True)


def io(r):
    data = pattern(8193)
    args = ["--batch", "7", "--reverse"]
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", args, data, status=5, closed_reader=True)
    r.run("closed-help-output", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", args, data, reverse=True, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    last_read = max(index for index, item in enumerate(baseline) if item["name"] == "read")
    input_map = next(item for item in baseline[first_read + 1:] if item["name"] == "mmap")
    output_map = next(item for item in baseline[last_read + 1:] if item["name"] == "mmap")
    selected = [maps[0], input_map, output_map, maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 4
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"reached-oom-{ordinal}", args, data, status=4, trace=True,
                       injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"], (old, fault)
    r.run("retry-read-eintr", args, data, reverse=True, trace=True, injection=("read", 1, "EINTR"))
    r.run("retry-write-eintr", args, data, reverse=True, trace=True, injection=("write", 1, "EINTR"))
    partial = r.run("later-read-eio-no-prefix", args, data, status=3, trace=True, injection=("read", 2, "EIO"))
    first = next(item for item in partial if item["name"] == "read")
    assert first["answer"].isdigit() and int(first["answer"]) > 0, first
    r.run("first-write-eio-no-prefix", args, data, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-failure", args, data, status=5, trace=True,
          injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("read-eintr-attempt-budget", status=2, persistent_interrupts=True)


def controls():
    assert len(HELP) == 441 and len(ERROR) == 31
    assert summary(b"") == b'"count","sum","min","max","first","last"\r\n"0","0","","","",""\r\n'
    expected = encode([HEADER, (5, 271, 0, 254, 9, 7)])
    assert summary(b"\x09\x01\xfe\x00\x07") == expected
    assert summary(b"\x09\x01\xfe\x00\x07", True) == encode([HEADER, (5, 271, 0, 254, 7, 9)])
    assert summary(bytes(range(256))) == encode([HEADER, (256, 32640, 0, 255, 0, 255)])
    assert len(pattern(CAP)) == CAP and summary(b"\xff" * CAP) == encode([HEADER, (CAP, CAP * 255, 255, 255, 255, 255)])
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, *args, **kwargs): self.count += 1
    for function in (model, bounds, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = ("mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
             "mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory) (INJECTED)\n"
             "munmap(0x1000, 4096) = 0\n")
    assert len(events(trace)) == 3
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("cleanup control accepted an observed unreleased mapping")
    print(f"byte-summary CPU controls=9; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "bounds": bounds, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"byte-summary-{mode} cases={runner.count} evidence={runner.directory}")
