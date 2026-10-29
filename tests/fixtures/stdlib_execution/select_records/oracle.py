"""Independent raw-byte record model and finite native I/O observations."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 1048576
RECORD_CAP = 65536
HELP = (b"Usage: select_records DELIMITER EVERY\n"
        b"Select zero-based records 0, EVERY, 2*EVERY, ... from binary stdin.\n"
        b"DELIMITER is ASCII decimal 0..255; EVERY is 1..65536. Leading zeros are allowed.\n"
        b"Keep delimiters and a final unterminated record; trailing delimiters add no record.\n"
        b"Limits: 1048576 input/output bytes, 65536 records, 65536 bytes per record including delimiter.\n"
        b"Use a 4096-byte buffered reader and 1024-byte scratch; stage all output through EOF.\n"
        b"8192 input/output attempts, 16384 provider calls per helper. Sole --help or -h bypasses input.\n")
ERROR = b"select_records: operation failed\n"
COUNTS = {"model": 33, "limits": 8, "cli": 33, "io": 17}


def records(data, delimiter):
    """Split bytes independently of streaming/refill/call-budget machinery."""
    if not data:
        return []
    marker = bytes([delimiter])
    parts = data.split(marker)
    return [part + marker for part in parts[:-1]] + ([parts[-1]] if parts[-1] else [])


def pattern(length, excluded=10):
    block = bytes(value for value in range(256) if value != excluded)
    return (block * ((length + len(block) - 1) // len(block)))[:length]


def select_records(data, delimiter=10, every=2):
    if not 0 <= delimiter <= 255 or not 1 <= every <= 65536 or len(data) > CAP:
        raise ValueError("argument/input bound")
    source = records(data, delimiter)
    if len(source) > RECORD_CAP or any(len(record) > RECORD_CAP for record in source):
        raise ValueError("record/count bound")
    return b"".join(source[::every])


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        result.append(item)
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
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"select-records-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", trace=False, injection=None,
            read_error=False, closed_stdout=False, diagnostic=True, budget=None, preflight=False):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..8192", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,munmap,mremap,brk,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
            finally:
                os.close(descriptor)
        elif closed_stdout:
            reader, writer = os.pipe(); os.close(reader)
            try:
                result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            calls = "8193" if budget == "write" else "8192"
            assert len(selected) == 1 and selected[0][-3:] == [calls, "8192", budget], rows
        if preflight:
            assert not any(item["name"] == "read" for item in found)
        self.count += 1
        return found

    def model(self, name, data, delimiter=10, every=2, **options):
        return self.run(name, [str(delimiter), str(every)], data, output=select_records(data, delimiter, every), **options)


def model(r):
    examples = [("empty", b"", 10, 2), ("only-delimiter", b"\n", 10, 2),
                ("consecutive-delimiters", b"\n\n\n\n\n", 10, 2),
                ("all-bytes-selected", bytes(range(256)), 10, 1),
                ("nul-delimiter", b"\0\xffa\0b\0last", 0, 2),
                ("nonutf8-delimiter", b"\0\xff\x80a\xff\xfe\xfftail", 255, 2),
                ("unterminated-first", b"\0\xfffirst", 10, 65536),
                ("unterminated-skipped", b"a\nb", 10, 2),
                ("trailing-delimiter", b"a\nb\n", 10, 2),
                ("selection-period-three", b"0\n1\n2\n3\n4\n5\n6\n", 10, 3)]
    for name, data, delimiter, every in examples:
        r.model(name, data, delimiter, every)
    for length in (1023, 1024, 1025, 4095, 4096, 4097):
        r.model(f"selected-record-length-{length}", pattern(length - 1) + b"\n", every=1)
        r.model(f"skipped-record-length-{length}", b"first\n" + pattern(length - 1) + b"\nlast\n", every=2)
    for terminated in (False, True):
        record = pattern(RECORD_CAP - int(terminated)) + (b"\n" if terminated else b"")
        r.model(f"maximum-selected-record-{int(terminated)}", record, every=1)
        r.model(f"maximum-skipped-record-{int(terminated)}", b"first\n" + record, every=65536)
    r.model("maximum-record-count", b"\n" * RECORD_CAP, every=65536)
    huge = b"x" * 15 + b"\n"
    found = r.model("maximum-input-sparse-selection", huge * RECORD_CAP, every=65536, trace=True)
    assert len([item for item in found if item["name"] == "mmap"]) <= 4, "sparse skips retained source-sized backing"
    r.model("maximum-input-all-selected", huge * RECORD_CAP, every=1)
    rng = random.Random(0x5E1EC7)
    for index in range(4):
        delimiter = (0, 10, 128, 255)[index]
        choices = [value for value in range(256) if value != delimiter]
        fields = [bytes(rng.choice(choices) for _ in range(rng.randrange(0, 100))) for _ in range(35)]
        data = bytes([delimiter]).join(fields)
        if index % 2: data += bytes([delimiter])
        r.model(f"seeded-{index}", data, delimiter, (1, 2, 3, 65536)[index])


def limits(r):
    for terminated in (False, True):
        record = b"x" * (RECORD_CAP + 1 - int(terminated)) + (b"\n" if terminated else b"")
        r.run(f"selected-record-over-cap-{int(terminated)}", ["10", "1"], record, status=2)
        r.run(f"skipped-record-over-cap-{int(terminated)}", ["10", "65536"], b"first\n" + record, status=2)
    r.run("record-count-over-cap", ["10", "65536"], b"\n" * (RECORD_CAP + 1), status=2)
    data = (b"x" * 31 + b"\n") * 32768 + b"x"
    r.run("input-over-cap-selected", ["10", "1"], data, status=2)
    r.run("input-over-cap-skipped", ["10", "65536"], data, status=2)
    r.run("later-selected-over-cap", ["10", "1"], b"valid\n" + b"x" * (RECORD_CAP + 1), status=2)


def cli(r):
    invalid = [[], ["10"], ["10", "2", "x"], ["-1", "1"], ["+0", "1"], ["256", "1"],
               ["", "1"], [" 1", "1"], ["1.0", "1"], ["١", "1"], ["0x10", "1"],
               ["10", "0"], ["10", "65537"], ["10", "-1"], ["10", "+1"], ["10", "1 "],
               ["10", "1.0"], ["10", "1_0"], ["0" * 65, "1"], ["10", "0" * 65],
               ["9" * 64, "1"], ["10", "18446744073709551616"],
               ["--help", "1"], ["-h", "1"], ["--help", "--help"], ["-hh"], ["--help=yes"],
               ["--"], [b"\xff", "1"]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, trace=True, read_error=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, read_error=True, preflight=True)
    data = b"a\0b\0c"
    r.run("leading-zero-arguments", ["000", "0002"], data, output=select_records(data, 0, 2))
    r.run("exact-argument-cap", ["0" * 64, "0" * 63 + "1"], data, output=data)


def io(r):
    data = (pattern(1024) + b"\n") * 5
    args = ["10", "2"]
    wanted = select_records(data)
    baseline = r.run("baseline", args, data, output=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    reader_map = next(item for item in reversed(baseline[:first_read]) if item["name"] == "mmap")
    output_maps = [item for item in baseline[first_read + 1:] if item["name"] == "mmap"]
    selected = [maps[0], maps[1], reader_map, output_maps[0], output_maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 5
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    first_output = next(index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    assert baseline.index(eof) < first_output
    reader_address = reader_map["answer"]
    assert next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == reader_address) < first_output
    assert not any(item["name"] == "mmap" for item in baseline[baseline.index(eof) + 1:])
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"owner-oom-{ordinal}", args, data, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("stdin-directory", args, status=3, trace=True, read_error=True)
    r.run("closed-data-stdout", args, data, status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, output=wanted, trace=True, injection=(call, 1, "EINTR"))
    failed = r.run("later-read-eio", args, data, status=3, trace=True, injection=("read", 2, "EIO"))
    assert int(next(item["answer"] for item in failed if item["name"] == "read")) > 0
    failed = r.run("required-eof-eio", args, data, status=3, trace=True, injection=("read", eof["ordinal"], "EIO"))
    assert sum(int(item["answer"]) for item in failed if item["name"] == "read" and item["answer"].isdigit()) == len(data)
    partial = r.run("actual-output-prefix", args, data, status=5, output=wanted[:1024], trace=True, injection=("write", 2, "EIO"))
    assert next(item["answer"] for item in partial if item["name"] == "write") == "1024"
    r.run("signal-setup-eio", args, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("input-attempt-cap", args, status=2, budget="read")
    r.run("output-attempt-cap", args, data, status=5, budget="write")


def controls():
    assert len(HELP) == 546 and len(ERROR) == 33
    assert records(b"", 10) == []
    assert records(b"\n", 10) == [b"\n"]
    assert records(b"a\nb\n", 10) == [b"a\n", b"b\n"]
    assert records(b"a\nb", 10) == [b"a\n", b"b"]
    assert select_records(b"\0\xff\0x", 0, 2) == b"\0x"
    assert select_records(b"0\n1\n2\n3\n4\n", 10, 2) == b"0\n2\n4\n"
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs):
            if len(args) >= 3 and kwargs.get("status") == 2:
                try: select_records(args[2], int(args[1][0]), int(args[1][1]))
                except ValueError: pass
                else: raise AssertionError("limit reference accepted invalid input")
            self.count += 1; return []
        def model(self, name, data, delimiter=10, every=2, **kwargs):
            select_records(data, delimiter, every); self.count += 1; return []
    for function in (model, limits, cli):
        runner = CounterOnly(); function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    for delimiter in range(256):
        data = bytes(range(256)) + bytes([delimiter])
        assert b"".join(records(data, delimiter)) == data
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n"
    assert len(events(trace)) == 2
    try: events(trace.split("munmap")[0])
    except AssertionError: pass
    else: raise AssertionError("missing release accepted")
    print(f"select-records CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "limits": limits, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"select-records-{mode} cases={runner.count} evidence={runner.directory}")
