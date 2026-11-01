"""Integer-only byte-per-field oracle; IEEE patterns never become Python floats."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MAX_RECORDS = 65536
CAP = 8 + 32 * MAX_RECORDS
WIDTHS = (8, 8, 4, 4, 8)
HELP = (b"Usage: repack_records FROM TO\n"
        b"Convert LNR1 record frames from stdin to stdout; FROM and TO are exactly le or be.\n"
        b"Frame: LNR1, u32 count, then 32-byte records: u64/i64/i32/f32/f64 at offsets 0/8/16/20/24.\n"
        b"All float bits are preserved. Same-order conversion is byte identity.\n"
        b"Limits: 65536 records, 2097160 input/output bytes, 8192 input and output calls each.\n"
        b"Validate the complete frame and EOF before output. A sole --help or -h shows help.\n")
ERROR = b"repack_records: operation failed\n"
COUNTS = {"model": 27, "rejection": 30, "cli": 23, "io": 16}


def integer_bytes(value, width, order):
    bits = value & ((1 << (8 * width)) - 1)
    positions = range(width) if order == "le" else range(width - 1, -1, -1)
    return bytes((bits >> (8 * position)) & 255 for position in positions)


def frame(records, order):
    output = bytearray(b"LNR1" + integer_bytes(len(records), 4, order))
    for record in records:
        assert len(record) == 5
        for value, width in zip(record, WIDTHS):
            output.extend(integer_bytes(value, width, order))
    return bytes(output)


def edge_records():
    samples = [0, 0x80000000, 1, 0x80000001, 0x007fffff, 0x807fffff,
               0x00800000, 0x80800000, 0x3f800000, 0xbf800000, 0x7f7fffff,
               0xff7fffff, 0x7f800000, 0xff800000, 0x7f800001, 0xff800123,
               0x7fc12345, 0xffc54321]
    readings = [0, 0x8000000000000000, 1, 0x8000000000000001, 0x000fffffffffffff,
                0x800fffffffffffff, 0x0010000000000000, 0x8010000000000000,
                0x3ff0000000000000, 0xbff0000000000000, 0x7fefffffffffffff,
                0xffefffffffffffff, 0x7ff0000000000000, 0xfff0000000000000,
                0x7ff0000000000001, 0xfff0000000000123, 0x7ff8123456789abc,
                0xfff8fedcba987654]
    identifiers = [0, 1, 1 << 63, (1 << 64) - 1, 0x0123456789abcdef]
    timestamps = [-(1 << 63), (1 << 63) - 1, -1, 0, 1, -1024]
    channels = [-(1 << 31), (1 << 31) - 1, -1, 0, 1, -65536]
    return [(identifiers[index % len(identifiers)], timestamps[index % len(timestamps)],
             channels[index % len(channels)], sample, readings[index])
            for index, sample in enumerate(samples)]


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
        self.directory = Path(tempfile.mkdtemp(prefix=f"repack-records-{mode}-"))
        self.count = 0

    def run(self, name, arguments=("le", "be"), data=b"", *, status=0, output=b"",
            read_error=False, closed_reader=False, trace=False, injection=None,
            diagnostic=True, budget=None):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..8192", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
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
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout[:64], output[:64], result.stderr)
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
            # write also includes the one successful stderr diagnostic call.
            calls = "8193" if budget == "write" else "8192"
            assert len(selected) == 1 and selected[0][-3:] == [calls, "8192", budget], rows
        self.count += 1
        return found

    def model(self, name, records, origin, destination):
        self.run(name, (origin, destination), frame(records, origin), output=frame(records, destination))


def model(r):
    records = edge_records()
    for origin in ("le", "be"):
        for destination in ("le", "be"):
            r.model(f"edge-bits-{origin}-{destination}", records, origin, destination)
            r.model(f"count-zero-{origin}-{destination}", [], origin, destination)
            r.model(f"singleton-{origin}-{destination}", [records[15]], origin, destination)
    for count in (31, 32, 33):
        rows = [records[index % len(records)] for index in range(count)]
        r.model(f"native-boundary-{count}-le-be", rows, "le", "be")
        r.model(f"native-boundary-{count}-be-le", rows, "be", "le")
    rng = random.Random(0xEAD1A4)
    for index in range(8):
        rows = [(rng.getrandbits(64), rng.getrandbits(64) - (1 << 63), rng.getrandbits(32) - (1 << 31),
                 rng.getrandbits(32), rng.getrandbits(64)) for _ in range(rng.randrange(1, 1000))]
        r.model(f"seeded-bits-{index}", rows, "le" if index % 2 else "be", "le" if index % 4 < 2 else "be")
    rows = [records[index % len(records)] for index in range(MAX_RECORDS)]
    r.model("maximum-record-count", rows, "le", "be")


def rejection(r):
    r.run("empty", status=2)
    empty = frame([], "le")
    for length in range(1, 8):
        r.run(f"truncated-header-{length}", data=empty[:length], status=2)
    for index, magic in enumerate((b"lnr1", b"LNR0", b"XXXX", b"\x00NR1")):
        r.run(f"bad-magic-{index}", data=magic + empty[4:], status=2)
    for order in ("le", "be"):
        r.run("record-count-over-cap-" + order, (order, "le"), b"LNR1" + integer_bytes(MAX_RECORDS + 1, 4, order), status=2)
        r.run("record-count-high-bit-" + order, (order, "le"), b"LNR1" + integer_bytes(0x80000000, 4, order), status=2)
    for suffix in (b"x", b"\x00" * 32):
        r.run("zero-count-trailing-" + str(len(suffix)), data=empty + suffix, status=2)
    one = frame(edge_records()[:1], "le")
    for length in (8, 15, 16, 23, 28, 39):
        r.run(f"truncated-record-{length}", data=one[:length], status=2)
    r.run("later-record-truncated", data=frame(edge_records()[:2], "le")[:-1], status=2)
    r.run("declared-one-trailing-byte", data=one + b"x", status=2)
    r.run("maximum-count-no-body", data=b"LNR1" + integer_bytes(MAX_RECORDS, 4, "le"), status=2)
    r.run("raw-input-over-cap", data=b"x" * (CAP + 1), status=2)
    r.run("wrong-input-order-le-as-be", ("be", "le"), one, status=2)
    r.run("wrong-input-order-be-as-le", ("le", "be"), frame(edge_records()[:1], "be"), status=2)


def cli(r):
    invalid = [[], ["le"], ["le", "be", "extra"], ["LE", "be"], ["le", "BE"],
               ["little", "be"], ["le", "big"], [" le", "be"], ["le", "be "],
               ["", "be"], ["le", ""], ["--help", "be"], ["le", "--help"],
               ["-h", "le"], ["--unknown"], ["--help", "--help"], ["x" * 65, "le"],
               ["le", "x" * 65], ["le\ufeff", "be"], ["le\n", "be"], ["--", "le", "be"]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-long", ["--help"], output=HELP, read_error=True)
    r.run("help-short", ["-h"], output=HELP)


def io(r):
    rows = [edge_records()[index % 18] for index in range(65)]
    data, wanted = frame(rows, "le"), frame(rows, "be")
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-data-stdout", data=data, status=5, closed_reader=True)
    r.run("closed-help-stdout", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", data=data, output=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    eof_index = baseline.index(eof)
    assert not any(item["name"] == "mmap" for item in baseline[eof_index + 1:]), "conversion must not allocate after EOF"
    input_map = next(item for item in baseline[first_read + 1:] if item["name"] == "mmap")
    selected = [maps[0], maps[1], input_map, maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 4
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"reached-oom-{ordinal}", data=data, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"], (old, fault)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", data=data, output=wanted, trace=True, injection=(call, 1, "EINTR"))
    failed_read = r.run("later-read-eio-no-output", data=data, status=3, trace=True, injection=("read", 2, "EIO"))
    first = next(item for item in failed_read if item["name"] == "read")
    assert first["answer"].isdigit() and int(first["answer"]) > 0
    failed_write = r.run("later-write-eio-confirmed-prefix", data=data, status=5, output=wanted[:1024], trace=True, injection=("write", 2, "EIO"))
    first = next(item for item in failed_write if item["name"] == "write")
    assert first["args"].startswith("1,") and first["answer"] == "1024", first
    r.run("signal-setup-failure", data=data, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("read-interruption-attempt-cap", status=2, budget="read")
    r.run("write-interruption-attempt-cap", data=data, status=5, budget="write")
    failed_eof = r.run("required-eof-probe-eio", data=data, status=3, trace=True, injection=("read", eof["ordinal"], "EIO"))
    accepted = [int(item["answer"]) for item in failed_eof if item["name"] == "read" and item["answer"].isdigit()]
    assert sum(accepted) == len(data), ("EOF error must follow the complete frame", accepted, len(data))


def controls():
    assert len(HELP) == 442 and len(ERROR) == 33 and CAP == 2097160
    record = (0x0123456789abcdef, -(1 << 63), -2, 0x7f800001, 0xfff0000000000123)
    expected_be = bytes.fromhex("0123456789abcdef8000000000000000fffffffe7f800001fff0000000000123")
    expected_le = bytes.fromhex("efcdab89674523010000000000000080feffffff0100807f230100000000f0ff")
    assert frame([record], "be") == b"LNR1\x00\x00\x00\x01" + expected_be
    assert frame([record], "le") == b"LNR1\x01\x00\x00\x00" + expected_le
    assert integer_bytes(-1, 8, "le") == b"\xff" * 8 and integer_bytes((1 << 64) - 1, 8, "be") == b"\xff" * 8
    assert frame([], "le") == b"LNR1\x00\x00\x00\x00"
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, *args, **kwargs): self.count += 1
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
    print(f"repack-records CPU controls=7; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"repack-records-{mode} cases={runner.count} evidence={runner.directory}")
