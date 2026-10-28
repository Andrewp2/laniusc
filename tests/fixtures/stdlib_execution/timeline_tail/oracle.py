"""Finite independent CSV timeline model; test code, no resource tracing."""
import csv
from io import StringIO
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile

HELP = (b"Usage: timeline-tail [--count N] [--level LEVEL] [--help]\n"
        b"Read CSV level,message through EOF; print CSV rank,level,message newest first.\n"
        b"Default count: 10; count range: 0..4096; level is an exact case-sensitive token.\n"
        b"Limits: 1 MiB input, 4096 events, 8192 bytes per message, 2 MiB staged output.\n")
ERROR = b"timeline-tail: operation failed\n"


def encode(rows, *, quoted=False):
    output = StringIO(newline="")
    writer = csv.writer(output, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
                        lineterminator="\r\n")
    writer.writerows(rows)
    return output.getvalue().encode()


def expected(rows, count=10, level=None):
    latest = [row for row in reversed(rows) if level is None or row[0] == level][:count]
    return encode([("rank", "level", "message"), *[(str(index), *row) for index, row in enumerate(latest, 1)]], quoted=True)


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"timeline-tail-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"level,message\n", *, output=b"", status=0,
            closed_reader=False, read_error=False):
        command = [self.executable, *arguments]
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            read_fd, write_fd = os.pipe()
            os.close(read_fd)
            try:
                result = subprocess.run(command, input=data, stdout=write_fd, stderr=subprocess.PIPE,
                                        timeout=15, check=False)
            finally:
                os.close(write_fd)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        prefix = self.directory / name
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".receipt").write_text(repr((command, result.returncode)) + "\n")
        assert result.returncode == status, (name, result.returncode, result.stdout[:120], result.stderr)
        assert result.stdout == output, (name, len(result.stdout), len(output), result.stdout[:120], output[:120])
        assert result.stderr == (ERROR if status else b""), (name, result.stderr)
        self.count += 1

    def model(self, name, rows, *, count=10, level=None, arguments=None, data=None):
        if arguments is None:
            arguments = ["--count", str(count)]
            if level is not None:
                arguments += ["--level", level]
        if data is None:
            data = encode([("level", "message"), *rows])
        self.run(name, arguments, data, output=expected(rows, count, level))


def model(r):
    rows = [("INFO", "old"), ("WARN", "middle"), ("INFO", "new"), ("WARN", "latest")]
    r.model("header-only", [])
    r.model("empty-message", [("INFO", "")])
    r.model("default-count", rows, arguments=[])
    r.model("latest-two", rows, count=2)
    r.model("filter-before-take", rows, count=2, level="INFO")
    r.model("missing-level", rows, level="ERROR")
    r.model("count-zero", rows, count=0)
    r.model("count-one", rows, count=1)
    r.model("case-sensitive", [("INFO", "upper"), ("info", "lower")], level="INFO")
    r.model("quoted-utf8", [("INFO", 'comma, quote" newline\r\n☃'), ("WARN", "日本語\nsecond")])
    r.model("lf-no-final-newline", [("INFO", "first"), ("WARN", "last")], data=b"level,message\nINFO,first\nWARN,last")
    r.model("short-options", rows, count=1, level="WARN", arguments=["-n", "1", "-l", "WARN"])
    r.model("maximum-fields", [("A"*32, "x"*8192)])
    r.model("maximum-events", [("INFO", str(index)) for index in range(4096)], count=4096)
    # Exactly 1 MiB of valid CSV, with every decoded message within its cap.
    data = b"level,message\n"
    large = []
    while len(data)+8198+6 <= 1048576:
        data += b"INFO,"+b"x"*8192+b"\n"
        large.append(("INFO", "x"*8192))
    remaining = 1048576-len(data)-6
    assert 0 <= remaining <= 8192
    data += b"INFO,"+b"y"*remaining+b"\n"
    large.append(("INFO", "y"*remaining))
    assert len(data) == 1048576
    r.model("maximum-input", large, count=3, data=data)
    rng = random.Random(0x71A1)
    messages = ["", "plain", "two,fields", 'a"b', "line\nnext", "☃", "spaces value"]
    for index in range(10):
        generated = [(rng.choice(["INFO", "WARN", "DEBUG", "info"]), rng.choice(messages)+str(row))
                     for row in range(rng.randrange(1, 65))]
        r.model(f"seeded-{index}", generated, count=rng.randrange(0, 20), level=rng.choice([None, "INFO", "WARN", "ABSENT"]))


def rejection(r):
    cases = [
        ("empty-input", b""), ("missing-header", b"INFO,event\n"),
        ("reordered-header", b"message,level\n"), ("header-case", b"Level,message\n"),
        ("header-width", b"level,message,extra\n"), ("row-width", b"level,message\nINFO\n"),
        ("extra-field", b"level,message\nINFO,a,b\n"),
        ("unclosed-quote", b'level,message\nINFO,"oops'),
        ("quote-in-unquoted", b'level,message\nINFO,a"b\n'),
        ("text-after-quote", b'level,message\nINFO,"a"b\n'),
        ("bare-cr", b"level,message\rINFO,a\r"),
        ("invalid-utf8", b"level,message\nINFO,\xff\n"),
        ("invalid-unselected-utf8", b"level,message\nDEBUG,\xff\nINFO,ok\n"),
        ("nul", b"level,message\nINFO,\x00\n"),
        ("quoted-tab", b'level,message\nINFO,"tab\tvalue"\n'),
        ("empty-level", b"level,message\n,event\n"),
        ("digit-level", b"level,message\n1INFO,event\n"),
        ("space-level", b"level,message\nINFO WARN,event\n"),
        ("level-over-cap", encode([("level", "message"), ("A"*33, "event")])),
        ("message-over-cap", encode([("level", "message"), ("INFO", "x"*8193)])),
        ("events-over-cap", b"level,message\n"+b"INFO,x\n"*4097),
        ("input-over-cap", b"x"*1048577),
    ]
    for name, data in cases:
        r.run(name, ["--level", "INFO"], data, status=2)
    r.run("count-zero-still-validates", ["--count", "0"], b'level,message\nINFO,"oops', status=2)
    r.run("later-error-no-prefix", ["--count", "1"], b'level,message\nINFO,valid\nWARN,"oops', status=2)


def cli(r):
    invalid = [[], ["file.csv"], ["--unknown"], ["--count"], ["--count", ""],
               ["--count", "-1"], ["--count", "4097"], ["--count", "1.5"],
               ["--count", "18446744073709551616"], ["--count", "0", "--count", "1"],
               ["--level"], ["--level", ""], ["--level", "1INFO"], ["--level", "é"],
               ["--level", "A"*33], ["--level", "INFO", "--level", "WARN"],
               ["--help", "--help"], ["-hh"]]
    # The first entry is an invalid-input check under the default CLI.
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, b"", status=2)
    r.run("help", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)


def io(r):
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", data=b"level,message\nINFO,complete\n", status=5, closed_reader=True)


def controls():
    assert len(HELP) == 297 and len(ERROR) == 32
    rows = [("INFO", "old"), ("WARN", "middle"), ("INFO", "new")]
    assert list(csv.reader(StringIO(expected(rows, 1, "INFO").decode(), newline=""))) == [
        ["rank", "level", "message"], ["1", "INFO", "new"]]
    assert expected(rows, 0) == b'"rank","level","message"\r\n'
    quoted = [("INFO", 'a,"\n☃')]
    assert list(csv.reader(StringIO(encode(quoted).decode(), newline=""))) == [list(quoted[0])]
    print("timeline-tail CPU controls=4")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        print(f"timeline-tail-{mode} cases={runner.count} evidence={runner.directory}")
