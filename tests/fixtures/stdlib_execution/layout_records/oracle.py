"""Independent record-byte checksum model and selected native failure controls."""
from collections import Counter
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

MAX_COUNT = 65536
HELP = (b"Usage: layout_records COUNT\n"
        b"Build and verify checked arena records, then write a 24-byte binary report.\n"
        b"COUNT is ASCII decimal 0..65536; leading zeros are allowed. No stdin is read.\n"
        b"Record layout: tag u8 at 0, serial LE u32 at 4, value BE u64 at 8; stride 16, alignment 8.\n"
        b"Report: BE u64 count, total bytes, and sum of (byte position + 1) * stored byte.\n"
        b"Padding bytes are zero. A sole --help or -h shows help.\n")
ERROR = b"layout_records: operation failed\n"
COUNTS = {"model": 20, "cli": 28, "io": 10}
TRACE = "read,write,mmap,munmap,mremap,brk,rt_sigaction"


def report(count):
    if not 0 <= count <= MAX_COUNT:
        raise ValueError("count bound")
    # Derive each field's contribution directly. Padding bytes contribute zero;
    # this model never calls the layout, arena or endian implementation.
    checksum = 0
    for index in range(count):
        offset = 16 * index
        checksum += (offset + 1) * ((17 * index + 3) % 256)
        serial = (index * 65537) ^ 0xA5A5A5A5
        value = (index * 281479271743489) ^ 0x0123456789ABCDEF
        for byte in range(4):
            checksum += (offset + 5 + byte) * ((serial >> (8 * byte)) & 255)
        for byte in range(8):
            checksum += (offset + 9 + byte) * ((value >> (8 * (7 - byte))) & 255)
    assert checksum < 1 << 64
    return b"".join(value.to_bytes(8, "big") for value in (count, 16 * count, checksum))


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        result.append(item)
        assert name != "read", "layout_records must never read stdin"
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
        self.directory = Path(tempfile.mkdtemp(prefix=f"layout-records-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), *, status=0, output=b"", trace=False, injection=None,
            closed_stdout=False, diagnostic=True, budget=False):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=write",
                       "-e", "inject=write:error=EINTR:when=1..64", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none", "-e", "trace=" + TRACE,
                      "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if closed_stdout:
                reader, writer = os.pipe()
                os.close(reader)
                try:
                    result = subprocess.run(command, stdin=descriptor, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
                finally:
                    os.close(writer)
                result.stdout = b""
            else:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
        finally:
            os.close(descriptor)
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
            assert len(selected) == 1 and marked == selected
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == ["write"]]
            assert len(selected) == 1 and selected[0][-3:] == ["65", "64", "write"], rows
        self.count += 1
        return found


def model(r):
    for count in (0, 1, 2, 3, 15, 16, 17, 63, 64, 65, 255, 256, 257, 65535, 65536):
        found = r.run(f"count-{count}", [str(count)], output=report(count), trace=count == 0)
        if count == 0:
            assert len([item for item in found if item["name"] == "mmap"]) == 2, "zero-size arena unexpectedly allocated backing"
    for text in ("00000", "00001", "00065536", "0" * 64, "0" * 59 + "65536"):
        r.run(f"leading-zero-{len(text)}-{int(text)}", [text], output=report(int(text)))


def cli(r):
    invalid = [[], ["1", "2"], ["--help", "1"], ["-h", "1"], ["--help", "--help"], ["-hh"],
               ["--help=yes"], ["--"], [""], ["-1"], ["+1"], ["-0"], ["+0"], [" 1"], ["1 "],
               ["1\t"], ["1.0"], ["1e2"], ["0x10"], ["1_0"], ["١"], ["65537"],
               [str((1 << 64) - 1)], [str(1 << 64)], ["0" * 65], [b"\xff"]]
    for index, arguments in enumerate(invalid):
        found = r.run(f"invalid-{index}", arguments, status=2, trace=True)
        assert len([item for item in found if item["name"] == "mmap"]) <= 2, "invalid CLI reached arena allocation"
    r.run("help-long", ["--help"], output=HELP, trace=True)
    r.run("help-short", ["-h"], output=HELP, trace=True)


def io(r):
    count = 257
    wanted = report(count)
    baseline = r.run("baseline", [str(count)], output=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) == 3, "expected two argv owners and one arena chunk"
    arena_address = maps[-1]["answer"]
    released = next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == arena_address)
    first_output = next(index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    assert released < first_output, "arena not destroyed before report publication"
    for old in maps:
        ordinal = old["ordinal"]
        actual = r.run(f"owner-oom-{ordinal}", [str(count)], status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("output-eintr-retry", [str(count)], output=wanted, trace=True, injection=("write", 1, "EINTR"))
    r.run("output-eio", [str(count)], status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("closed-data-stdout", [str(count)], status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    r.run("signal-setup-eio", [str(count)], status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("output-attempt-cap", [str(count)], status=5, budget=True)


def controls():
    assert len(HELP) == 410 and len(ERROR) == 33
    first = bytes.fromhex("03 00 00 00 a5 a5 a5 a5 01 23 45 67 89 ab cd ef")
    second = bytes.fromhex("14 00 00 00 a4 a5 a4 a5 01 22 45 66 89 aa cd ee")
    assert report(0) == b"\0" * 24
    for count, wire in ((1, first), (2, first + second)):
        checksum = sum((position + 1) * value for position, value in enumerate(wire))
        assert report(count) == count.to_bytes(8, "big") + len(wire).to_bytes(8, "big") + checksum.to_bytes(8, "big")
    assert ((65535 * 65537) ^ 0xA5A5A5A5) == 0x5A5A5A5A
    assert ((65535 * 281479271743489) ^ 0x0123456789ABCDEF) == 0xFEDCBA9876543210
    assert int.from_bytes(report(65536)[8:16], "big") == 1048576
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs):
            self.count += 1
            return [dict(name="mmap"), dict(name="mmap")]
    for function in (model, cli):
        runner = CounterOnly(); function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n"
    assert len(events(trace)) == 2
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("missing observed release accepted")
    print(f"layout-records CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"layout-records-{mode} cases={runner.count} evidence={runner.directory}")
