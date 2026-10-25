"""Streaming CSV projection: independent Python CSV and native I/O oracles."""
import csv
import io
import os
from pathlib import Path
import random
import re
import resource
import signal
import subprocess
import sys
import tempfile
import time

MODE, EXE = sys.argv[1:3]
CASES = 0
csv.field_size_limit(16777216)


def encode(rows, *, quoting=csv.QUOTE_ALL, terminator="\r\n"):
    output = io.StringIO(newline="")
    csv.writer(output, quoting=quoting, lineterminator=terminator).writerows(rows)
    return output.getvalue().encode()


def project(source, columns):
    rows = list(csv.reader(io.StringIO(source.decode(), newline=""), strict=True))
    # The repository dialect defines a blank record as one empty field.
    rows = [row if row else [""] for row in rows]
    return encode([[row[index] for index in columns] for row in rows])


def inspect(result, expected=0, output=None, *, report=True, diagnostic=True):
    assert result.returncode == expected, (expected, result.returncode, result.stdout, result.stderr)
    if output is not None:
        assert result.stdout == output, (len(result.stdout), len(output), result.stdout[:200], output[:200])
    lines = result.stderr.splitlines()
    records = [line for line in lines if line.startswith(b"input=")]
    diagnostics = [line for line in lines if not line.startswith(b"input=")]
    assert len(records) in (0, 1) if report is None else len(records) == int(report), result.stderr
    if expected and diagnostic:
        assert len(diagnostics) == 1 and diagnostics[0].startswith(b"csv-rewrite: "), result.stderr
        assert b"\0" not in diagnostics[0]
    else:
        assert not diagnostics, result.stderr
    stats = dict(item.split("=") for item in records[0].decode().split()) if records else {}
    stats = {key: int(value) for key, value in stats.items()}
    if stats:
        assert stats["consumed"] <= stats["input"]
        if result.stdout is not None:
            assert stats["output"] == len(result.stdout), stats
    return stats


def run(source=b"", columns=(0,), *, options=(), expected=0, output=None, report=True, command=None, diagnostic=True, optional_report=False):
    global CASES
    arguments = [EXE, ",".join(map(str, columns)), *map(str, options)]
    if report:
        arguments.append("--report")
    if command is not None:
        arguments = [*command, *arguments]
    result = subprocess.run(arguments, input=source, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=8)
    CASES += 1
    if output is None and expected == 0:
        output = project(source, columns)
    return result, inspect(result, expected, output, report=None if optional_report else report, diagnostic=diagnostic)


def matrix():
    examples = [
        (b"", (0,)), (b"\n", (0,)), (b"\r\n", (0,)), (b"\"\"", (0,)),
        (b",", (1, 0, 1)), (b"a,b\r\nc,d", (1, 0)),
        (b"a,\n", (1, 0, 1)), (b"\"a,b\",\"c\"\"d\"\r\n", (1, 0, 1)),
        ('"é","🙂"\n"東京","Ω"\n'.encode(), (1, 0, 1)),
        (b'"a\r\nb","c\nd"\r\n', (1, 0)),
        (b'"\r","\n"', (0, 1, 0)),
        ('\ufeffname,city\nAndré,東京\n'.encode(), (0, 1)),
        (b"id,name,city\n1,Alice,Paris\n", (2, 0, 2)),
        (encode([["x" * 4095 + "é", '"' * 511, "tail"]]), (1, 0, 1)),
    ]
    for source, columns in examples:
        run(source, columns)
    generator = random.Random(0xC5A52026)
    dictionary = ["", "a", "a,b", '"', "a\r\nb", "é🙂", "東京", " Ω ", "\ufeff", "\u0080"]
    for index in range(48):
        width = 1 + index % 7
        rows = [[generator.choice(dictionary) for _ in range(width)] for _ in range(1 + index % 6)]
        source = encode(rows, quoting=csv.QUOTE_ALL if index % 2 else csv.QUOTE_MINIMAL)
        if index % 3:
            source = source[:-2]
        columns = [generator.randrange(width) for _ in range(1 + index % 9)]
        run(source, columns)


def limits():
    global CASES
    first = encode([["a"]])
    two = encode([["a"], ["b"]])
    for source, columns, option, exact, failed in [
        (b"a\nb\n", (0,), "--max-input", 4, first),
        (b"a\nb\n", (0,), "--max-records", 2, first),
        (b"a,b\n", (0,), "--max-fields", 2, b""),
        ("é\n".encode(), (0,), "--max-field-bytes", 2, b""),
        (b"a,bb\n", (1, 0), "--max-record-bytes", 3, b""),
        (b"ab,c\n", (0, 0), "--max-record-bytes", 4, b""),
        (b"a\nb\n", (0,), "--max-output", len(two), first),
    ]:
        run(source, columns, options=(option, exact))
        run(source, columns, options=(option, exact - 1), expected=2, output=failed)
    run(b"", options=("--max-input", 0, "--max-output", 0, "--max-records", 0,
                        "--max-field-bytes", 0, "--max-record-bytes", 0, "--max-write-calls", 0))
    for option in ("--max-input", "--max-output", "--max-records", "--max-field-bytes", "--max-record-bytes", "--max-work", "--max-read-calls", "--max-write-calls"):
        run(b"a\n", options=(option, 0), expected=2, output=b"")
    run(b"\n", options=("--max-field-bytes", 0, "--max-record-bytes", 0))
    _, baseline = run(b"a\n")
    work = baseline["work"]
    run(b"a\n", options=("--max-work", work))
    run(b"a\n", options=("--max-work", work - 1), expected=2, output=first)
    run(b"a\n", options=("--max-work", work - 2), expected=2, output=b"")
    run(b"a\n", options=("--max-read-calls", 2))
    run(b"a\n", options=("--max-read-calls", 1), expected=2, output=first)
    run(b"a\nb\n", options=("--max-write-calls", 3))
    run(b"a\nb\n", options=("--max-write-calls", 2), expected=2, output=two)
    run(b"a\nb\n", options=("--max-write-calls", 1), expected=2, output=first)
    large = "x" * 1021
    wire = encode([[large], [large]])
    canonical = project(wire, [0])
    _, stats = run(wire, options=("--max-write-calls", 3), expected=2, output=canonical[:2049])
    assert stats["rows"] == 1 and stats["write-calls"] == 3
    run(wire, options=("--max-write-calls", 5))
    invalid = [
        b'"a', b'a"b', b'"a"x', b'a\rb', b'a\r', b'\xff',
        b'"\xf0\x9f', b'\xc0\x80', b'\xed\xa0\x80', b'\0', b'"\0"', b'\t', b'\x7f',
    ]
    for source in invalid:
        run(source, expected=2, output=b"")
        run(b"good\n" + source, expected=2, output=encode([["good"]]))
    run(b"a,b\nx\n", expected=2, output=first)
    run(b"a,b\n", columns=(2,), expected=2, output=b"")
    for arguments in [[], [""], [","], ["0,"], [",0"], ["0,,1"], ["-1"], ["+1"],
                      [" 0"], ["1.0"], ["256"], ["4294967296"], ["0", "1"],
                      ["0", "--max-fields", "0"], ["0", "--max-fields", "4097"],
                      ["0", "--max-records", "1000001"], ["0", "--max-input", "1073741825"],
                      ["0", "--max-output", "1073741825"], ["0", "--max-field-bytes", "16777217"],
                      ["0", "--max-work", "2147483648"], ["0", "--max-read-calls", "-1"],
                      ["0", "--max-output"], ["0", "--unknown"]]:
        result = subprocess.run([EXE, *arguments], input=b"ignored", stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, timeout=3)
        CASES += 1
        inspect(result, 2, b"", report=False)
    run(b"a,b\n", (1, 0), options=("--max-output=1", "--max-output=9"))
    result = subprocess.run([EXE, "--help"], input=b"ignored", stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3)
    CASES += 1
    assert result.returncode == 0 and not result.stderr and result.stdout.startswith(b"Usage: csv-rewrite COLUMNS"), result


def io_failures(directory):
    global CASES
    source = encode([["x" * 2500, "é"]])
    canonical = project(source, [0])
    for size in (1, 1031, 2049):
        path = directory / "short-output"
        def restrict():
            signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
            resource.setrlimit(resource.RLIMIT_FSIZE, (size, size))
        with path.open("wb") as output:
            result = subprocess.run([EXE, "0", "--report"], input=source, stdout=output,
                                    stderr=subprocess.PIPE, preexec_fn=restrict, timeout=4)
        CASES += 1
        stats = inspect(result, 3, report=True)
        assert path.read_bytes() == canonical[:size] and stats["output"] == size and stats["rows"] == 0
    with open("/dev/full", "wb") as output:
        result = subprocess.run([EXE, "0", "--report"], input=b"a\n", stdout=output, stderr=subprocess.PIPE, timeout=3)
    CASES += 1
    assert inspect(result, 3)["output"] == 0
    read_fd, write_fd = os.pipe()
    os.close(read_fd)
    try:
        result = subprocess.run([EXE, "0", "--report"], input=b"a\n", stdout=write_fd, stderr=subprocess.PIPE, timeout=3)
    finally:
        os.close(write_fd)
    CASES += 1
    assert inspect(result, 3)["output"] == 0
    trace = directory / "io.trace"
    for fault, expected in (("inject=read:error=EINTR:when=1", 0),
                            ("inject=write:error=EINTR:when=1", 0),
                            ("inject=read:error=EIO:when=1", 3),
                            ("inject=write:error=EIO:when=1", 3),
                            ("inject=read:error=EINTR:when=1+", 2),
                            ("inject=write:error=EINTR:when=1+", 2)):
        result, _ = run(b"a\n", options=("--max-read-calls", 4, "--max-write-calls", 4), expected=expected,
                        output=encode([["a"]]) if expected == 0 else b"", report=False,
                        diagnostic=fault != "inject=write:error=EINTR:when=1+",
                        command=("strace", "-qq", "-o", trace, "-e", "trace=read,write,mmap,munmap", "-e", fault))
        events = trace.read_text()
        assert "INJECTED" in events
        allocations(events)
        # Injecting every write also prevents the bounded diagnostic. Exit
        # status and the syscall trace remain authoritative in that case.


def allocations(events):
    live = {}
    count = 0
    peak = 0
    current = 0
    mapped = 0
    peak_mapped = 0
    page = os.sysconf("SC_PAGE_SIZE")
    for line in events.splitlines():
        if line.startswith("mmap("):
            address = line.rsplit(" = ", 1)[-1].split()[0]
            if address.startswith("0x"):
                length = int(line.split(",", 2)[1].strip())
                assert address not in live, line
                live[address] = length
                current += length
                mapped += (length + page - 1) // page * page
                peak = max(peak, current)
                peak_mapped = max(peak_mapped, mapped)
                count += 1
        elif line.startswith("munmap("):
            address = line[7:].split(",", 1)[0]
            assert line.endswith(" = 0") and address in live, line
            length = live.pop(address)
            current -= length
            mapped -= (length + page - 1) // page * page
    assert not live, live
    return count, peak, peak_mapped


def resources(directory):
    global CASES
    source = encode([["a", "b"], ["x" * 257, 'é,"' * 47]])
    trace = directory / "alloc.trace"
    command = ("strace", "-qq", "-o", trace, "-e", "trace=mmap,munmap")
    baseline, _ = run(source, (1, 0, 1), command=command)
    count, _, _ = allocations(trace.read_text())
    assert count >= 10, count
    for ordinal in range(1, count + 1):
        result, _ = run(source, (1, 0, 1), command=(*command, "-e", f"inject=mmap:error=ENOMEM:when={ordinal}+"),
                        expected=4, optional_report=True)
        assert baseline.stdout.startswith(result.stdout)
        assert result.stdout in (b"", project(encode([["a", "b"]]), [1, 0, 1]))
        events = trace.read_text()
        assert "INJECTED" in events
        allocations(events)
    # A fixed shape has the same allocator peak and allocation count at one
    # row and 4,096 rows; source/output storage belongs to the Python oracle.
    row = ["x" * 257, 'é,"' * 47, "line\r\ninside"]
    observations = []
    for rows in (1, 4096):
        wire = encode([row] * rows, quoting=csv.QUOTE_MINIMAL)
        start = time.monotonic()
        result, stats = run(wire, (2, 0, 2, 1), command=command)
        elapsed = time.monotonic() - start
        count, peak, mapped = allocations(trace.read_text())
        assert stats["rows"] == rows and stats["input"] == len(wire) and stats["output"] == len(result.stdout)
        observations.append((count, peak, mapped, stats, elapsed))
    small, large = observations
    assert small[:3] == large[:3], observations
    for name in ("decoder-bytes", "decoder-fields", "record-bytes", "record-fields"):
        assert small[3][name] == large[3][name], observations
    assert large[3]["decoder-bytes"] <= 1024 and large[3]["record-bytes"] <= 1024
    print(f"csv-rewrite-resources cases={CASES} rows=4096 allocations={large[0]} peak-requested-bytes={large[1]} peak-mapped-bytes={large[2]} seconds={large[4]:.3f}")


with tempfile.TemporaryDirectory(prefix="lanius_csv_rewrite_") as temporary:
    directory = Path(temporary)
    if MODE == "matrix":
        matrix()
    elif MODE == "limits":
        limits()
    elif MODE == "io":
        io_failures(directory)
    elif MODE == "resources":
        resources(directory)
    else:
        raise AssertionError(MODE)
if MODE != "resources":
    print(f"csv-rewrite-{MODE} cases={CASES}")
