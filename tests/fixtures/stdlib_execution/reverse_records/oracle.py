"""Independent fixed-width byte reversal and selected real-file observations."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 1048576
MAX_RECORDS = 4096
HELP = (b"Usage: reverse_records PATH WIDTH\n"
        b"Reverse the order of fixed-width binary file records without changing bytes within a record.\n"
        b"WIDTH is ASCII decimal 1..4096; leading zeros are allowed. No stdin is read.\n"
        b"Require a seekable file of at most 1048576 bytes, divisible by WIDTH, with at most 4096 records.\n"
        b"Use buffered End/Start/negative Current seeks; stage the complete result and close before stdout.\n"
        b"Limits: 8192 file-read and output attempts; seeks are not retried. Sole --help or -h shows help.\n")
ERROR = b"reverse_records: operation failed\n"
TRACE = "openat,close,lseek,read,write,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS = {"model": 28, "limits": 7, "cli": 29, "io": 22}


def pattern(length):
    block = bytes((index * 73 + 19) % 256 for index in range(256))
    return (block * ((length + 255) // 256))[:length]


def reversed_records(data, width):
    if not 1 <= width <= 4096 or len(data) > CAP or len(data) % width or len(data) // width > MAX_RECORDS:
        raise ValueError("width/file/record bound")
    source = [data[offset:offset + width] for offset in range(0, len(data), width)]
    return b"".join(reversed(source))


def source_records(width, count):
    source = []
    for index in range(count):
        record = bytearray(pattern(width))
        prefix = index.to_bytes(4, "big")
        length = min(4, width)
        record[:length] = prefix[-length:]
        source.append(bytes(record))
    return b"".join(source)


def events(text):
    result, counts, live, descriptor = [], Counter(), {}, None
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z0-9_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
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
        elif name == "openat":
            assert counts[name] == 1 and descriptor is None
            assert "O_RDONLY" in args and "O_CLOEXEC" in args
            assert not any(flag in args for flag in ("O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND"))
            if not answer.startswith("-1"):
                descriptor = int(answer)
        elif name == "close":
            assert descriptor is not None and int(args) == descriptor and counts[name] == 1
            assert answer == "0" or (answer.startswith("-1 ") and "INJECTED" in answer)
            descriptor = None
        elif name in ("read", "lseek"):
            assert descriptor is not None and int(args.split(",")[0]) == descriptor, line
        elif name == "write":
            target = int(args.split(",")[0])
            assert target in (1, 2), "unexpected file write"
            if target == 1:
                assert descriptor is None, "stdout before file close attempt"
    assert not live, ("observed unreleased mappings", live)
    assert descriptor is None, "file lacks explicit close attempt"
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"reverse-records-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), *, status=0, output=b"", trace=False, injections=(),
            closed_stdout=False, diagnostic=True, budget=None, preflight=False):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..8192", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
                      "-e", "trace=" + TRACE, "-o", str(prefix.with_suffix(".trace"))]
            for call, ordinal, failure in injections:
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        stdin_fd = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    result = subprocess.run(command, stdin=stdin_fd, stdout=writer, stderr=subprocess.PIPE,
                                            cwd=self.directory, timeout=15, check=False)
                finally:
                    os.close(writer)
                result.stdout = b""
            else:
                result = subprocess.run(command, stdin=stdin_fd, capture_output=True, cwd=self.directory, timeout=15, check=False)
        finally:
            os.close(stdin_fd)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        selected = []
        for call, ordinal, failure in injections:
            reached = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(reached) == 1 and reached[0]["answer"].startswith("-1 " + failure + " ")
            selected += reached
        assert {item["line"] for item in marked} == {item["line"] for item in selected}, (name, marked)
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            calls = "8193" if budget == "write" else "8192"
            assert len(selected) == 1 and selected[0][-3:] == [calls, "8192", budget], rows
        if preflight:
            assert not any(item["name"] in ("openat", "read", "lseek", "close") for item in found)
        self.count += 1
        return found

    def reverse(self, name, data, width, *, path_name=None, width_text=None, symlink=False, **options):
        path = os.fsencode(self.directory) + b"/" + os.fsencode(path_name or name + ".bin")
        with open(path, "wb") as target: target.write(data)
        arguments = [path, width_text or str(width)]
        if path_name == "--help": arguments[0] = "--help"
        if symlink:
            link = self.directory / (name + ".link")
            os.symlink(path, link); arguments[0] = str(link)
        status = options.get("status", 0)
        output = options.pop("output", b"" if status else reversed_records(data, width))
        found = self.run(name, arguments, output=output, **options)
        with open(path, "rb") as original: assert original.read() == data, "source file changed"
        assert os.stat(path).st_size == len(data)
        if symlink: assert os.path.islink(arguments[0])
        return found


def model(r):
    for width in (1, 1024, 4096): r.reverse(f"empty-width-{width}", b"", width)
    for width in (1, 4096): r.reverse(f"singleton-width-{width}", source_records(width, 1), width)
    r.reverse("literal-three-byte-records", b"abcDEFghi", 3)
    r.reverse("every-byte-records", bytes(range(256)), 1)
    for width in (255, 256, 257, 1023, 1024, 1025, 4095, 4096):
        r.reverse(f"width-{width}", source_records(width, 7), width)
    r.reverse("maximum-records", source_records(1, MAX_RECORDS), 1)
    r.reverse("maximum-file-and-records", source_records(256, MAX_RECORDS), 256)
    r.reverse("maximum-file-wide-records", source_records(4096, 256), 4096)
    r.reverse("raw-nonutf8-path", source_records(7, 11), 7, path_name=b"records-\xff.bin")
    r.reverse("unicode-path", source_records(3, 11), 3, path_name="records-é.bin")
    r.reverse("literal-help-path", b"abcDEFghi", 3, path_name="--help")
    r.reverse("follow-final-symlink", source_records(9, 7), 9, symlink=True)
    r.reverse("leading-zero-width", b"abcDEFghi", 3, width_text="0003")
    rng = random.Random(0x5EECA11)
    for index in range(4):
        width = rng.choice((1, 7, 1024, 1025, 4096)); count = rng.randrange(1, 16)
        data = bytes(rng.randrange(256) for _ in range(width * count))
        r.reverse(f"seeded-{index}", data, width)
    base = os.fsencode(r.directory) + b"/long/"
    while len(base) + 201 + 8 < 4095: base += b"d" * 200 + b"/"
    os.makedirs(base)
    path = base + b"f" * (4095 - len(base))
    assert len(path) == 4095
    with open(path, "wb") as target: target.write(b"a\0\xff")
    r.run("maximum-path-and-width-token", [path, "0" * 63 + "1"], output=b"\xff\0a")
    with open(path, "rb") as target: assert target.read() == b"a\0\xff"


def limits(r):
    for length in (1, 2, 4): r.reverse(f"not-divisible-{length}", pattern(length), 3, status=2, trace=True)
    r.reverse("large-width-not-divisible", pattern(4095), 4096, status=2, trace=True)
    r.reverse("file-size-over-cap", pattern(CAP + 4096), 4096, status=2, trace=True)
    r.reverse("record-count-over-cap", pattern(MAX_RECORDS + 1), 1, status=2, trace=True)
    r.reverse("wide-record-count-over-cap", pattern(255 * (MAX_RECORDS + 1)), 255, status=2, trace=True)


def cli(r):
    path = str(r.directory / "never-opened")
    invalid = [[], [path], [path, "1", "extra"], ["--help", path], ["-h", path], ["--help", "--help"],
               ["-hh"], ["--help=yes"], ["--"], ["", "1"], ["x" * 4096, "1"],
               [path, "0"], [path, "4097"], [path, "-1"], [path, "+1"], [path, "-0"],
               [path, "1 "], [path, " 1"], [path, "1.0"], [path, "1e2"], [path, "0x10"],
               [path, "1_0"], [path, "١"], [path, b"\xff"], [path, "0" * 65],
               [path, "18446744073709551616"], [path, ""]]
    for index, arguments in enumerate(invalid): r.run(f"invalid-{index}", arguments, status=2, trace=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, preflight=True)


def io(r):
    data, width = source_records(1025, 5), 1025
    wanted = reversed_records(data, width)
    def exercise(name, **options):
        return r.reverse(name, data, width, path_name="io-source.bin", **options)
    baseline = exercise("baseline", trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    opened = next(index for index, item in enumerate(baseline) if item["name"] == "openat")
    reader_map = next(item for item in baseline[opened + 1:first_read] if item["name"] == "mmap")
    selected = [maps[0], maps[1], reader_map, maps[-1]]
    assert len(maps) == 4 and len({item["ordinal"] for item in selected}) == 4
    assert baseline.index(maps[-1]) < first_read, "output reserve occurred after file reads"
    assert not any(item["name"] == "mmap" for item in baseline[first_read + 1:])
    absolute = [int(item["args"].split(",")[1]) for item in baseline if item["name"] == "lseek" and "SEEK_SET" in item["args"]]
    assert absolute == [4100, 3075, 2050, 1025, 0]
    assert sum(item["name"] == "lseek" for item in baseline) == 10
    close_index = next(index for index, item in enumerate(baseline) if item["name"] == "close")
    reader_address = reader_map["answer"]
    released = next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == reader_address)
    assert released < close_index
    for old in selected:
        ordinal = old["ordinal"]
        actual = exercise(f"owner-oom-{ordinal}", status=4, trace=True, injections=(("mmap", ordinal, "ENOMEM"),))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("missing-file", [str(r.directory / "absent"), "1"], status=3, trace=True)
    fifo = r.directory / "unseekable.fifo"; os.mkfifo(fifo)
    anchor = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
    try: r.run("actual-unseekable-fifo", [str(fifo), "1"], status=3, trace=True)
    finally: os.close(anchor)
    exercise("open-eacces", status=3, trace=True, injections=(("openat", 1, "EACCES"),))
    exercise("read-eio", status=3, trace=True, injections=(("read", 1, "EIO"),))
    exercise("read-eintr-retry", trace=True, injections=(("read", 1, "EINTR"),))
    exercise("end-seek-eio", status=3, trace=True, injections=(("lseek", 1, "EIO"),))
    exercise("current-query-eio", status=3, trace=True, injections=(("lseek", 3, "EIO"),))
    failed = exercise("absolute-seek-eintr-no-retry", status=3, trace=True, injections=(("lseek", 4, "EINTR"),))
    assert sum(item["name"] == "lseek" for item in failed) == 4
    exercise("close-eio", status=3, trace=True, injections=(("close", 1, "EIO"),))
    exercise("allocation-primary-survives-close-eio", status=4, trace=True,
              injections=(("mmap", reader_map["ordinal"], "ENOMEM"), ("close", 1, "EIO")))
    exercise("closed-data-stdout", status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    exercise("output-eintr-retry", trace=True, injections=(("write", 1, "EINTR"),))
    partial = exercise("actual-output-prefix", status=5, output=wanted[:1024], trace=True, injections=(("write", 2, "EIO"),))
    assert next(item["answer"] for item in partial if item["name"] == "write") == "1024"
    r.run("signal-setup-eio", status=5, trace=True, injections=(("rt_sigaction", 1, "EIO"),), diagnostic=False)
    exercise("read-attempt-cap", status=2, budget="read")
    exercise("output-attempt-cap", status=5, budget="write")


def controls():
    assert len(HELP) == 496 and len(ERROR) == 34
    assert reversed_records(b"", 1) == b""
    assert reversed_records(b"abcDEFghi", 3) == b"ghiDEFabc"
    assert reversed_records(b"\0\xff\x80\x01", 1) == b"\x01\x80\xff\0"
    class CounterOnly:
        def __init__(self): self.count = 0; self.directory = Path(tempfile.mkdtemp(prefix="reverse-records-cpu-"))
        def run(self, *args, **kwargs): self.count += 1; return []
        def reverse(self, name, data, width, **kwargs):
            if kwargs.get("status") == 2:
                try: reversed_records(data, width)
                except ValueError: pass
                else: raise AssertionError("invalid model case accepted")
            else:
                result = reversed_records(data, width)
                assert reversed_records(result, width) == data
            self.count += 1; return []
    for function in (model, limits, cli):
        runner = CounterOnly(); function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = "openat(AT_FDCWD, \"input\", O_RDONLY|O_CLOEXEC) = 3\nclose(3) = 0\n"
    assert len(events(trace)) == 2
    for bad in (trace.split("close")[0], "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\n"):
        try: events(bad)
        except AssertionError: pass
        else: raise AssertionError("missing cleanup accepted")
    print(f"reverse-records CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "limits": limits, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"reverse-records-{mode} cases={runner.count} evidence={runner.directory}")
