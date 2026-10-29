"""Independent optional i64 field model and finite native failure controls."""
from collections import Counter
import errno
import os
from pathlib import Path
import random
import re
import resource
import signal
import subprocess
import sys
import tempfile

CAP = 1 << 20
MINIMUM, MAXIMUM = -(1 << 63), (1 << 63) - 1
HEADER = b"present,missing,sum\n"
HELP = (b"Usage: optional_sum [--help]\n"
        b"Read LF-delimited stdin: - means missing; other records are signed decimal i64.\n"
        b"Write CSV present,missing,sum after complete EOF, validation and checked input-order summation.\n"
        b"No whitespace trimming or CR removal; final nonempty records may omit LF.\n"
        b"Limits: 64 bytes per record, 65536 records, 1048576 input bytes, 8192 input/output calls.\n"
        b"Only a sole --help or -h is accepted; help bypasses input.\n")
ERROR = b"optional_sum: operation failed\n"
INTEGER = re.compile(rb"[+-]?[0-9]+\Z")
COUNTS = {"model": 33, "rejection": 30, "cli": 17, "io": 18}


def summarize(data):
    if len(data) > CAP:
        raise ValueError("input cap")
    lines = [] if not data else data.split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    if len(lines) > 65536:
        raise ValueError("record count")
    present, missing, total = 0, 0, 0
    for line in lines:
        if not line or len(line) > 64:
            raise ValueError("record size")
        if line == b"-":
            missing += 1
            continue
        if not INTEGER.fullmatch(line):
            raise ValueError("signed decimal syntax")
        value = int(line)
        if not MINIMUM <= value <= MAXIMUM:
            raise ValueError("signed decimal range")
        total += value
        if not MINIMUM <= total <= MAXIMUM:
            raise ValueError("ordered intermediate overflow")
        present += 1
    return HEADER + f"{present},{missing},{total}\n".encode("ascii")


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
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, line
                live[address] = size
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
        self.directory = Path(tempfile.mkdtemp(prefix=f"optional-sum-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", read_error=False,
            closed_reader=False, trace=False, injection=None, diagnostic=True, budget=None,
            file_limit=None):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..8192", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,munmap,mremap,brk,rt_sigaction",
                      "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + (f"\nRLIMIT_FSIZE={file_limit}; SIGXFSZ=SIG_IGN\n" if file_limit is not None else "\n"))
        prefix.with_suffix(".input").write_bytes(data)
        if file_limit is not None:
            assert not trace and not budget, "the file-size limit must not constrain strace's evidence file"
            def limit_output():
                resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
                signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
            with prefix.with_suffix(".limited-output").open("w+b") as target:
                result = subprocess.run(command, input=data, stdout=target, stderr=subprocess.PIPE,
                                        preexec_fn=limit_output, timeout=20, check=False)
                target.seek(0)
                result.stdout = target.read()
        elif read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=20, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=20, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=20, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, output, result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, marked)
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            calls = "8193" if budget == "write" else "8192"
            assert len(selected) == 1 and selected[0][-3:] == [calls, "8192", budget], rows
        self.count += 1
        return found

    def model(self, name, data):
        self.run(name, data=data, output=summarize(data))


def model(r):
    examples = [
        ("empty", b""), ("only-missing", b"-\n"), ("all-missing", b"-\n" * 100),
        ("signed-zeros-present", b"+0\n-0\n000\n-000\n"), ("mixed", b"1\n-\n3\n-0\n+0\n"),
        ("plus-leading-zeroes", b"+00023\n"), ("negative-leading-zeroes", b"-00023\n"),
        ("maximum-i64", str(MAXIMUM).encode()), ("minimum-i64", str(MINIMUM).encode()),
        ("fullwidth-cancellation", f"{MAXIMUM}\n{MINIMUM}\n".encode()),
        ("fullwidth-reverse-cancellation", f"{MINIMUM}\n{MAXIMUM}\n".encode()),
        ("safe-upper-intermediates", f"{MAXIMUM}\n-1\n1\n".encode()),
        ("safe-lower-intermediates", f"{MINIMUM}\n1\n-1\n".encode()),
        ("unterminated-final-record", b"1\n-\n3"), ("terminating-lf-is-not-record", b"7\n"),
        ("unterminated-missing", b"-"),
        ("line64-positive", b"+" + b"0" * 62 + b"1\n"),
        ("line64-negative", b"-" + b"0" * 62 + b"1\n"),
        ("line64-zero", b"0" * 64),
    ]
    for name, data in examples:
        r.model(name, data)
    for length in (1023, 1024, 1025):
        r.model(f"native-input-boundary-{length}", b"0\n" * (length // 2) + (b"0" if length % 2 else b""))
    r.model("maximum-records-with-lf", b"-\n" * 65536)
    r.model("maximum-records-without-lf", b"-\n" * 65535 + b"-")
    r.model("exact-byte-cap", (b"0" * 31 + b"\n") * 32768)
    rng = random.Random(0x09710A)
    for index in range(8):
        fields = []
        for _ in range(rng.randrange(0, 201)):
            if rng.randrange(3) == 0:
                fields.append(b"-")
            else:
                value = rng.randrange(-1000000, 1000001)
                sign = "-" if value < 0 else rng.choice(["", "+"])
                fields.append((sign + "0" * rng.randrange(6) + str(abs(value))).encode())
        data = b"\n".join(fields)
        if fields and index % 2:
            data += b"\n"
        r.model(f"seeded-{index}", data)


def rejection(r):
    cases = [
        ("lone-lf", b"\n"), ("initial-empty", b"\n1\n"), ("interior-empty", b"1\n\n2\n"),
        ("double-terminal-lf", b"1\n\n"), ("numeric-crlf", b"1\r\n"), ("missing-crlf", b"-\r\n"),
        ("leading-space", b" 1\n"), ("trailing-space", b"1 \n"), ("tab", b"\t1\n"),
        ("nul", b"1\x00\n"), ("del", b"1\x7f\n"), ("invalid-utf8", b"\xff\n"),
        ("unicode-digits", "١\n".encode()), ("plus-alone", b"+\n"), ("double-minus", b"--\n"),
        ("plus-minus", b"+-1\n"), ("decimal", b"1.0\n"), ("scientific", b"1e2\n"),
        ("underscore", b"1_0\n"), ("nan", b"nan\n"), ("infinity", b"inf\n"),
        ("integer-overflow", str(MAXIMUM + 1).encode()), ("integer-underflow", str(MINIMUM - 1).encode()),
        ("line65-zero", b"0" * 65 + b"\n"), ("line65-signed", b"+" + b"0" * 63 + b"1\n"),
        ("record-count-over-cap", b"-\n" * 65537),
        ("byte-cap-plus-valid-record", (b"0" * 31 + b"\n") * 32768 + b"0"),
        ("intermediate-upper-overflow", f"{MAXIMUM}\n1\n-1\n".encode()),
        ("intermediate-lower-overflow", f"{MINIMUM}\n-1\n1\n".encode()),
        ("later-invalid-no-publication", b"1\n-\n2\ninvalid\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)


def cli(r):
    invalid = [["x"], ["-"], ["--"], ["--help", "extra"], ["-h", "extra"],
               ["--help", "--help"], ["-hh"], ["--help=yes"], ["--unknown"], ["--Help"],
               ["--help "], [" -h"], ["x" * 65], [""], ["-h", "--help"]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-long", ["--help"], output=HELP, read_error=True)
    r.run("help-short", ["-h"], output=HELP)


def io(r):
    data = b"1\n-\n" * 1025
    wanted = summarize(data)
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-data-stdout", data=data, status=5, closed_reader=True)
    r.run("closed-help-stdout", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", data=data, output=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    eof_index = baseline.index(eof)
    assert not any(item["name"] == "mmap" for item in baseline[eof_index + 1:])
    assert all(index > eof_index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    selected = [maps[0], maps[len(maps) // 2], maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 3
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"input-oom-{ordinal}", data=data, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"]
    for ordinal in (1, 2):
        r.run(f"help-owner-oom-{ordinal}", ["--help"], status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", data=data, output=wanted, trace=True, injection=(call, 1, "EINTR"))
    failed = r.run("later-read-eio-no-publication", data=data, status=3, trace=True, injection=("read", 2, "EIO"))
    first = next(item for item in failed if item["name"] == "read")
    assert first["answer"].isdigit() and int(first["answer"]) > 0
    failed = r.run("required-eof-eio-no-publication", data=data, status=3, trace=True, injection=("read", eof["ordinal"], "EIO"))
    assert sum(int(item["answer"]) for item in failed if item["name"] == "read" and item["answer"].isdigit()) == len(data)
    r.run("first-output-eio", data=data, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-failure", status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("read-interruption-attempt-cap", status=2, budget="read")
    r.run("write-interruption-attempt-cap", data=data, status=5, budget="write")
    r.run("real-file-size-limit-prefix", data=data, status=5, output=wanted[:10], file_limit=10)


def controls():
    assert len(HEADER) == 20 and len(HELP) == 428 and len(ERROR) == 31
    assert summarize(b"") == HEADER + b"0,0,0\n"
    assert summarize(b"1\n-\n3\n-0\n+0\n") == HEADER + b"4,1,4\n"
    assert summarize(b"-") == summarize(b"-\n") == HEADER + b"0,1,0\n"
    assert summarize(f"{MAXIMUM}\n{MINIMUM}".encode()) == HEADER + b"2,0,-1\n"
    for data in (b"\n", b"1\n\n", b"1\r\n", f"{MAXIMUM}\n1\n-1".encode()):
        try:
            summarize(data)
        except ValueError:
            pass
        else:
            raise AssertionError(("invalid model input accepted", data))
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, name, data): summarize(data); self.count += 1
    for function in (model, rejection, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = "mmap(NULL, 1024, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\nmunmap(0x1000, 1024) = 0\n"
    assert len(events(trace)) == 2
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("cleanup control accepted an observed unreleased mapping")
    print(f"optional-sum CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"optional-sum-{mode} cases={runner.count} evidence={runner.directory}")
