"""Independent signed-token sorted reference and selected native fault evidence."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 1048576
MAX_COUNT = 65536
MINIMUM, MAXIMUM = -(1 << 63), (1 << 63) - 1
HELP = (b"Usage: select_value INDEX\n"
        b"Read signed decimal i64 tokens from stdin and print the zero-based ascending order statistic.\n"
        b"INDEX is ASCII decimal 0..65535; leading zeros are allowed.\n"
        b"Input whitespace is only ASCII space, tab, CR and LF; signs follow the decimal parser.\n"
        b"Limits: 1048576 input bytes, 65536 values, 64 bytes per token, 8192 read attempts.\n"
        b"Input is fully validated before output; input errors publish no data.\n"
        b"A sole --help or -h shows help without reading stdin.\n")
ERROR = b"select_value: operation failed\n"
COUNTS = {"model": 33, "rejection": 25, "cli": 28, "io": 15}
INTEGER = re.compile(rb"[+-]?[0-9]+\Z")


def select_value(data, index):
    if len(data) > CAP or not 0 <= index < MAX_COUNT:
        raise ValueError("input/index bound")
    tokens = [token for token in re.split(rb"[ \t\r\n]+", data) if token]
    if not tokens or len(tokens) > MAX_COUNT or index >= len(tokens):
        raise ValueError("value count/rank")
    values = []
    for token in tokens:
        if len(token) > 64 or not INTEGER.fullmatch(token):
            raise ValueError("token length/syntax")
        value = int(token)
        if not MINIMUM <= value <= MAXIMUM:
            raise ValueError("signed range")
        values.append(value)
    return f"{sorted(values)[index]}\n".encode("ascii")


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|close|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        result.append(item)
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]; assert address not in live
                live[address] = size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk", "close"):
            raise AssertionError(("unexpected allocator service or borrowed descriptor close", line))
        elif name == "write" and args.startswith("1,"):
            assert not live, "stdout published while an owned mapping remains live"
    assert not live, ("observed unreleased mappings", live)
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"select-value-{mode}-")); self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", trace=False, injection=None,
            read_error=False, closed_stdout=False, diagnostic=True, budget=None, preflight=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            maximum = 8192 if budget == "read" else 64
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..{maximum}", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
                      "-e", "trace=read,write,close,mmap,munmap,mremap,brk,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n"); prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try: result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
            finally: os.close(descriptor)
        elif closed_stdout:
            reader, writer = os.pipe(); os.close(reader)
            try: result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
            finally: os.close(writer)
            result.stdout = b""
        else: result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, output, result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else: assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            expected = ["8192", "8192", "read"] if budget == "read" else ["65", "64", "write"]
            assert len(selected) == 1 and selected[0][-3:] == expected, rows
        if preflight: assert not any(item["name"] == "read" for item in found)
        self.count += 1; return found

    def model(self, name, data, index, **options):
        return self.run(name, [str(index)], data, output=select_value(data, index), **options)


def model(r):
    for name, token in (("zero", b"0"), ("positive", b"+9"), ("negative", b"-9"),
                        ("minimum", str(MINIMUM).encode()), ("maximum", str(MAXIMUM).encode()), ("negative-zero", b"-000")):
        r.model(name, token, 0)
    extremes = f"{MINIMUM} {MAXIMUM} 0 -1 +1 {MINIMUM} {MAXIMUM}".encode()
    for index in (0, 3, 6): r.model(f"extremes-rank-{index}", extremes, index)
    r.model("all-equal-duplicates", b"7 7 7 7 7 7 7", 2)
    r.model("all-admitted-ascii-whitespace", b" \t\r\n3\t-1\r+2\n0 ", 2)
    r.model("unterminated-last-token", b"9 -8 4", 1)
    for name, token in (("positive64", b"+" + b"0" * 62 + b"1"),
                        ("negative64", b"-" + b"0" * 62 + b"1"), ("zero64", b"0" * 64)):
        r.model(name, token, 0)
    for offset in (1023, 1024): r.model(f"token-crosses-read-{offset}", b" " * offset + b"-7 2", 0)
    for index in range(5): r.model(f"small-all-ranks-{index}", b"8 -2 8 0 5", index)
    ascending = b" ".join(str(value).encode() for value in range(257))
    r.model("ascending", ascending, 128); r.model("descending", b" ".join(reversed(ascending.split())), 3)
    maximum = b" ".join(str(value).encode() for value in reversed(range(MAX_COUNT)))
    for index in (0, 32768, 65535): r.model(f"maximum-count-rank-{index}", maximum, index)
    r.model("exact-byte-cap-final-token", b" " * (CAP - 1) + b"0", 0)
    r.model("exact-byte-and-value-caps", (b"0" * 15 + b" ") * MAX_COUNT, 32768)
    rng = random.Random(0x5E1EC7ED)
    for index in range(4):
        values = [rng.randrange(-1000000, 1000001) for _ in range(97)]
        data = b"\t".join(("+" if value >= 0 and index % 2 else "").encode() + str(value).encode() for value in values)
        r.model(f"seeded-{index}", data, (0, 1, 48, 96)[index])


def rejection(r):
    cases = [("empty", b"", 0), ("only-whitespace", b" \t\r\n", 0), ("rank-at-length", b"1 2", 2),
             ("maximum-index-short-input", b"1", 65535), ("plus-alone", b"+", 0), ("minus-alone", b"-", 0),
             ("double-sign", b"--1", 0), ("plus-minus", b"+-1", 0), ("decimal", b"1.0", 0),
             ("scientific", b"1e2", 0), ("underscore", b"1_0", 0), ("nan", b"nan", 0),
             ("nul", b"1\0", 0), ("invalid-utf8", b"\xff", 0), ("unicode-digit", "١".encode(), 0),
             ("vertical-tab", b"1\v2", 0), ("form-feed", b"1\f2", 0), ("nonbreaking-space", b"1\xc2\xa02", 0),
             ("positive-overflow", str(MAXIMUM + 1).encode(), 0), ("negative-overflow", str(MINIMUM - 1).encode(), 0),
             ("token65-zero", b"0" * 65, 0), ("token65-signed", b"+" + b"0" * 64, 0),
             ("value-count-over-cap", b"0 " * (MAX_COUNT + 1), 0),
             ("late-invalid-after-valid-prefix", b"3 1 2 4 invalid", 2),
             ("input-over-cap-single-value", b"0" + b" " * CAP, 0)]
    for name, data, index in cases: r.run(name, [str(index)], data, status=2)


def cli(r):
    invalid = [[], ["1", "2"], ["--help", "0"], ["-h", "0"], ["--help", "--help"], ["-hh"],
               ["--help=yes"], ["--"], [""], ["-1"], ["+0"], ["-0"], ["65536"], [" 1"], ["1 "],
               ["1.0"], ["1e2"], ["0x10"], ["1_0"], ["١"], [b"\xff"], ["0" * 65],
               ["18446744073709551616"], ["--unknown"]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, trace=True, read_error=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("leading-zero-index", ["0001"], b"7 2 3", output=b"3\n")
    r.run("index-token64", ["0" * 64], b"7", output=b"7\n")


def io(r):
    args, data = ["17"], b"8 -1 5 0\n" * 600
    wanted = select_value(data, 17)
    baseline = r.run("baseline", args, data, output=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) == 3, "expected argv owners plus single pre-reserved value Vec"
    assert int(maps[-1]["args"].split(",")[1]) == 524288, "value reserve is not 65536 native i64 values"
    reserve_index = baseline.index(maps[-1])
    for owner in maps[:2]:
        address = owner["answer"]
        release_index = next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == address)
        assert release_index < reserve_index, "argv owner survived into value storage allocation"
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    assert all(baseline.index(item) < first_read for item in maps), "allocation after reading began"
    first_output = next(index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    assert all(index < first_output for index, item in enumerate(baseline) if item["name"] == "munmap")
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    assert baseline.index(eof) < first_output
    for old in maps:
        ordinal = old["ordinal"]
        actual = r.run(f"owner-oom-{ordinal}", args, data, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("stdin-directory", args, status=3, trace=True, read_error=True)
    r.run("closed-data-stdout", args, data, status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, output=wanted, trace=True, injection=(call, 1, "EINTR"))
    r.run("first-read-eio", args, data, status=3, trace=True, injection=("read", 1, "EIO"))
    failed = r.run("required-eof-eio", args, data, status=3, trace=True, injection=("read", eof["ordinal"], "EIO"))
    assert sum(int(item["answer"]) for item in failed if item["name"] == "read" and item["answer"].isdigit()) == len(data)
    r.run("output-eio", args, data, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-eio", args, data, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("read-attempt-cap", args, status=2, budget="read")
    r.run("output-attempt-cap", args, data, status=5, budget="write")


def controls():
    assert len(HELP) == 474 and len(ERROR) == 31
    assert select_value(b"8 -2 8 0 5", 0) == b"-2\n" and select_value(b"8 -2 8 0 5", 4) == b"8\n"
    assert select_value(f"{MINIMUM} {MAXIMUM}".encode(), 0) == str(MINIMUM).encode() + b"\n"
    assert select_value(b" \t\r\n+0 -000\n", 1) == b"0\n"
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs):
            if len(args) >= 3 and kwargs.get("status") == 2:
                try: select_value(args[2], int(args[1][0]))
                except ValueError: pass
                else: raise AssertionError("invalid token reference accepted")
            self.count += 1; return []
        def model(self, name, data, index, **kwargs): select_value(data, index); self.count += 1; return []
    for function in (model, rejection, cli):
        runner = CounterOnly(); function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(1, \"0\\n\", 2) = 2\n"
    assert len(events(trace)) == 3
    for bad in (trace.split("munmap")[0], trace.replace("munmap(0x1000, 16) = 0\n", "")):
        try: events(bad)
        except AssertionError: pass
        else: raise AssertionError("missing cleanup or early publication accepted")
    print(f"select-value CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"select-value-{mode} cases={runner.count} evidence={runner.directory}")
