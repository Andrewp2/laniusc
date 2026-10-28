"""Independent dense/Fraction powers, native boundaries and reached fault checks."""
from collections import Counter
import csv
from fractions import Fraction
from io import StringIO
import math
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 4 << 20
HEADER = b"source,target,weight\n"
HELP = (b"Usage: sparse-paths --nodes N [--length K] [--help]\n"
        b"Read CSV source,target,weight; write canonical nonzero entries of A^K.\n"
        b"Nodes: 1..4096; length: 1..16 (default 2). Finite signed weights are allowed.\n"
        b"Products associate left: ((A*A)*A)...; duplicate edges coalesce in input order.\n"
        b"Short options: -n N, -k K, -h. Limits: 4 MiB input, 65536 edges/result entries, 16 MiB staged output.\n")
ERROR = b"sparse-paths: operation failed\n"
NUMBER = re.compile(r"-?(?:[0-9]+(?:\.[0-9]*)?)(?:e[+-]?[0-9]+)?\Z")
COUNTS = {"model": 34, "rejection": 37, "cli": 36, "io": 15}


def encode(rows, *, quoted=False):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
               lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode()


def dense_power(nodes, edges, length, *, rational=True):
    """Dense reference, independent of CSR indexing, touched sets and passes.

    Duplicate inputs first use the required ordered binary64 addition. Exact
    Fraction products then model small dyadic cases without reproducing the
    production accumulator. The separate binary64 mode defines the specified
    increasing-inner-index product/add order for rounding/underflow cases.
    """
    assert 1 <= nodes <= 32 and 1 <= length <= 16
    base = [[0.0] * nodes for _ in range(nodes)]
    for row, column, spelling in edges:
        value = float(spelling)
        assert math.isfinite(value)
        base[row][column] += value
        if not math.isfinite(base[row][column]):
            raise OverflowError("ordered duplicate sum")
    if rational:
        base = [[Fraction(value) for value in row] for row in base]
    result = [row[:] for row in base]
    for _ in range(1, length):
        product = [[Fraction(0) if rational else 0.0 for _ in range(nodes)] for _ in range(nodes)]
        for row in range(nodes):
            for column in range(nodes):
                for inner in range(nodes):
                    term = result[row][inner] * base[inner][column]
                    if not rational and not math.isfinite(term):
                        raise OverflowError("product")
                    product[row][column] += term
                    if not rational and not math.isfinite(product[row][column]):
                        raise OverflowError("sum")
        result = product
    return {(row, column): float(result[row][column])
            for row in range(nodes) for column in range(nodes)
            if float(result[row][column]) != 0.0}


def check_output(raw, nodes, expected, exact=True):
    rows = list(csv.reader(StringIO(raw.decode("ascii"), newline=""), strict=True))
    assert rows and rows[0] == ["source", "target", "weight"], rows[:2]
    assert encode(rows, quoted=True) == raw, "output is not fully quoted CRLF CSV"
    actual = {}
    previous = (-1, -1)
    for record in rows[1:]:
        assert len(record) == 3 and record[0].isascii() and record[0].isdigit(), record
        assert record[1].isascii() and record[1].isdigit() and NUMBER.fullmatch(record[2]), record
        row, column = int(record[0]), int(record[1])
        assert str(row) == record[0] and str(column) == record[1], record
        assert 0 <= row < nodes and 0 <= column < nodes and (row, column) > previous, record
        value = float(record[2])
        assert math.isfinite(value) and value != 0.0, record
        actual[(row, column)] = value
        previous = (row, column)
    assert actual.keys() == expected.keys(), (list(actual.items())[:12], list(expected.items())[:12])
    for key, wanted in expected.items():
        got = actual[key]
        if exact:
            assert got == wanted, (key, got, wanted)
        else:
            tolerance = max(abs(wanted) * 2e-12, 32 * math.ulp(wanted))
            assert abs(got - wanted) <= tolerance, (key, got, wanted, tolerance)


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
            item["size"] = size
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, (line, live)
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
        self.directory = Path(tempfile.mkdtemp(prefix=f"sparse-paths-{mode}-"))
        self.count = 0

    def run(self, name, arguments=("--nodes", "2"), data=HEADER, *, status=0,
            expected=None, nodes=2, exact=True, output=None, read_error=False,
            closed_reader=False, trace=False, injection=None, diagnostic=True):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if trace:
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
        if expected is not None:
            check_output(result.stdout, nodes, expected, exact)
        else:
            assert result.stdout == (output or b""), (name, result.stdout[:120], output)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, injection, marked)
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        self.count += 1
        return found

    def model(self, name, nodes, edges, *, length=2, arguments=None, data=None,
              expected=None, rational=True, exact=True):
        if arguments is None:
            arguments = ["--nodes", str(nodes), "--length", str(length)]
        if data is None:
            data = encode([("source", "target", "weight"), *edges])
        if expected is None:
            expected = dense_power(nodes, edges, length, rational=rational)
        self.run(name, arguments, data, expected=expected, nodes=nodes, exact=exact)


def exact_cap_input():
    maximum = b"0" * 128 + b"," + b"0" * 127 + b"1," + b"0" * 127 + b"1\n"
    full = (CAP - len(HEADER) - 6) // len(maximum)
    data = bytearray(HEADER + maximum * full)
    remaining = CAP - len(data)
    count = full
    if remaining > len(maximum):
        data.extend(b"0,1,1\n")
        remaining -= 6
        count += 1
    padding = remaining - 6
    fields = []
    for value in (b"0", b"1", b"1"):
        amount = min(padding, 127)
        fields.append(b"0" * amount + value)
        padding -= amount
    assert padding == 0
    data.extend(b",".join(fields) + b"\n")
    assert len(data) == CAP
    return bytes(data), count + 1


def fork_graph(sources=256, targets=256):
    hub = sources
    edges = [(source, hub, "1") for source in range(sources)]
    edges += [(hub, sources + 1 + target, "1") for target in range(targets)]
    return sources + 1 + targets, edges


def model(r):
    r.model("one-node-empty-length-one", 1, [], length=1)
    r.model("empty-length-sixteen", 5, [], length=16)
    r.model("default-length", 3, [(0, 1, "2"), (1, 2, "3")], arguments=["--nodes", "3"])
    r.model("directed-chain", 4, [(0, 1, "2"), (1, 2, "-3"), (2, 3, "4")], length=3)
    r.model("reverse-orientation", 3, [(2, 1, "2"), (1, 0, "-3")])
    r.model("signed-branching", 4, [(0, 1, "2"), (0, 2, "-1"), (1, 3, "3"), (2, 3, "4")])
    r.model("negative-self-loop-sixteen", 1, [(0, 0, "-0.5")], length=16)
    r.model("rounded-left-association", 1, [(0, 0, "1.1")], length=4, rational=False)
    r.model("exact-cancellation", 4, [(0, 1, "1"), (0, 2, "1"), (1, 3, "2"), (2, 3, "-2")])
    r.model("duplicate-order", 2, [(0, 1, "1e16"), (0, 1, "1"), (0, 1, "-1e16"), (0, 1, "2")], length=1)
    r.model("zero-entries-omitted", 3, [(0, 1, "0"), (0, 2, "-0"), (1, 2, "1"), (1, 2, "-1")], length=1)
    r.model("signed-base-length-one", 3, [(2, 0, "-3"), (0, 2, "2"), (0, 1, "-4")], length=1)
    r.model("nilpotent-length-sixteen", 3, [(0, 1, "7"), (1, 2, "-9")], length=16)
    r.model("identity-length-sixteen", 4, [(i, i, "1") for i in range(4)], length=16)
    r.model("minimum-subnormal-base", 2, [(0, 1, "5e-324")], length=1)
    r.model("underflowed-product-omitted", 3, [(0, 1, "5e-324"), (1, 2, "0.5")], rational=False)
    r.model("gradual-subnormal-product", 3, [(0, 1, "5e-324"), (1, 2, "2")], rational=False)
    r.model("huge-finite-base", 2, [(0, 1, "1.7976931348623157e308")], length=1)
    r.model("decimal-underflow-base", 2, [(0, 1, "1e-999")], length=1)
    r.model("quoted-header-leading-zeroes", 2, [(0, 1, "-1")], length=1,
            data=encode([("source", "target", "weight"), ("000", "001", "-1.0")], quoted=True))
    r.model("maximum-nodes-empty", 4096, [], length=16, expected={})
    r.model("maximum-raw-edges", 2, [(0, 1, "1")] * 65536, length=1)
    data, count = exact_cap_input()
    r.model("exact-four-mib", 2, [], length=1, data=data, expected={(0, 1): float(count)})
    nodes, edges = fork_graph()
    expected = {(row, 257 + column): 1.0 for row in range(256) for column in range(256)}
    r.model("exact-result-entry-cap", nodes, edges, expected=expected)
    rng = random.Random(0x5A25E)
    for index in range(10):
        nodes = rng.randrange(2, 9)
        edges = [(rng.randrange(nodes), rng.randrange(nodes), str(rng.randrange(-8, 9) / 4))
                 for _ in range(rng.randrange(1, 40))]
        r.model(f"seeded-dyadic-{index}", nodes, edges, length=rng.randrange(1, 6))


def rejection(r):
    cases = [
        ("empty", b""), ("wrong-header", b"target,source,weight\n"),
        ("header-case", b"Source,target,weight\n"), ("extra-header", b"source,target,weight,x\n"),
        ("bom", b"\xef\xbb\xbf" + HEADER), ("blank-row", HEADER + b"\n"),
        ("missing-field", HEADER + b"0,1\n"), ("extra-field", HEADER + b"0,1,1,x\n"),
        ("negative-source", HEADER + b"-1,0,1\n"), ("negative-target", HEADER + b"0,-1,1\n"),
        ("source-bound", HEADER + b"2,0,1\n"), ("target-bound", HEADER + b"0,2,1\n"),
        ("source-plus", HEADER + b"+0,1,1\n"), ("target-fraction", HEADER + b"0,1.0,1\n"),
        ("endpoint-overflow", HEADER + b"18446744073709551616,0,1\n"),
        ("nan", HEADER + b"0,1,nan\n"), ("infinity", HEADER + b"0,1,inf\n"),
        ("decimal-overflow", HEADER + b"0,1,1e309\n"), ("empty-weight", HEADER + b"0,1,\n"),
        ("trailing-weight", HEADER + b"0,1,1x\n"), ("unclosed-quote", HEADER + b'0,1,"1'),
        ("quote-in-unquoted", HEADER + b'0,1,1"2\n'), ("bare-cr", b"source,target,weight\r0,1,1\r"),
        ("invalid-utf8", HEADER + b"0,1,\xff\n"), ("nul", HEADER + b"0,1,\x00\n"),
        ("quoted-tab", HEADER + b'0,1,"\t1"\n'),
        ("field-over-cap", HEADER + b"0,1," + b"0" * 128 + b"1\n"),
        ("raw-edge-over-cap", HEADER + b"0,1,1\n" * 65537),
        ("input-over-cap", b"x" * (CAP + 1)),
        ("later-invalid-no-prefix", HEADER + b"0,1,1\n1,2,1\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)
    r.run("length-one-validates-later-input", ["--nodes", "2", "--length", "1"],
          HEADER + b"0,1,1\n0,2,1\n", status=2)
    r.run("ordered-duplicate-overflow", ["--nodes", "2", "--length", "1"],
          HEADER + b"0,1,1e308\n0,1,1e308\n0,1,-1e308\n", status=6)
    r.run("product-overflow", ["--nodes", "3"], HEADER + b"0,1,1e308\n1,2,2\n", status=6)
    r.run("sum-overflow-before-cancellation", ["--nodes", "4"],
          HEADER + b"0,1,1e308\n0,2,1e308\n0,3,-1e308\n1,0,1\n2,0,1\n3,0,1\n", status=6)
    nodes, edges = fork_graph(257, 256)
    r.run("result-entry-over-cap", ["--nodes", str(nodes)], encode([("source", "target", "weight"), *edges]), status=2)
    dense = [(row, column, "1") for row in range(256) for column in range(256)]
    r.run("product-work-over-cap", ["--nodes", "256"], encode([("source", "target", "weight"), *dense]), status=2)
    r.run("later-power-overflow-no-prefix", ["--nodes", "1", "--length", "3"], HEADER + b"0,0,1e103\n", status=6)


def cli(r):
    invalid = [
        [], ["--nodes"], ["--nodes", "0"], ["--nodes", "4097"], ["--nodes", "-1"],
        ["--nodes", "+1"], ["--nodes", "1.0"], ["--nodes", ""], ["--nodes", "18446744073709551616"],
        ["--length", "2"], ["--nodes", "2", "--length"], ["--nodes", "2", "--length", "0"],
        ["--nodes", "2", "--length", "17"], ["--nodes", "2", "--length", "-1"],
        ["--nodes", "2", "--length", "+1"], ["--nodes", "2", "--length", "1.0"],
        ["--nodes", "2", "--length", ""], ["--nodes", "2", "--length", "18446744073709551616"],
        ["--unknown"], ["graph.csv"], ["--nodes", "2", "-n3"], ["--nodes", "2", "--length", "1", "-k2"],
        ["--help", "--help"], ["-hh"], ["--help", "--nodes", "0"], ["--help", "--length", "0"],
        ["--help=yes"], ["--nodes", "2", "--", "operand"], [""] * 25, ["--nodes", "0" * 1025],
    ]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-nodes-and-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-length-without-nodes", ["--help", "--length", "16"], output=HELP, read_error=True)
    r.run("help-valid-options", ["--help", "--nodes", "4096", "--length", "16"], output=HELP)
    r.model("short-attached", 3, [(0, 1, "2"), (1, 2, "-3")], arguments=["-n3", "-k2"])
    r.model("long-equals-leading-zeroes", 2, [(0, 1, "-2")], length=1,
            arguments=["--nodes=002", "--length=001"])


def io(r):
    nodes = 7
    args = ["--nodes", str(nodes), "--length", "2"]
    edges = [(row, row, "1") for row in range(nodes)] + [(row, (row + 1) % nodes, "-0.5") for row in range(nodes)]
    data = encode([("source", "target", "weight"), *edges])
    wanted = dense_power(nodes, edges, 2)
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", args, data, status=5, closed_reader=True)
    r.run("closed-help-output", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", args, data, nodes=nodes, expected=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    sizes = [item["size"] for item in maps]
    # Identify this source's three scratch reservations and following exact
    # result buffers. This selects fault sites, not a public allocation ABI.
    recipe = [4 * nodes, 8 * nodes, 4 * nodes, 4 * (nodes + 1), 4 * len(wanted), 8 * len(wanted)]
    matches = [index for index in range(len(maps) - len(recipe) + 1) if sizes[index:index + len(recipe)] == recipe]
    assert len(matches) == 1, (recipe, sizes)
    start = matches[0]
    selected = [maps[0], *maps[start:start + len(recipe)], maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 8
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"reached-oom-{ordinal}", args, data, status=4, trace=True,
                       injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"], (old, fault)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, nodes=nodes, expected=wanted, trace=True,
              injection=(call, 1, "EINTR"))
    r.run("signal-setup-failure", args, data, status=5, trace=True,
          injection=("rt_sigaction", 1, "EIO"), diagnostic=False)


def controls():
    assert len(HELP) == 383 and len(ERROR) == 31
    assert dense_power(3, [(0, 1, "2"), (1, 2, "-3")], 2) == {(0, 2): -6.0}
    assert dense_power(3, [(2, 1, "2"), (1, 0, "-3")], 2) == {(2, 0): -6.0}
    assert dense_power(1, [(0, 0, "-0.5")], 16) == {(0, 0): 2 ** -16}
    left = dense_power(1, [(0, 0, "1.1")], 4, rational=False)
    assert left == {(0, 0): 1.4641000000000006}
    square = 1.1 * 1.1
    assert square * square == 1.4641000000000004 and left[(0, 0)] != square * square
    assert dense_power(2, [(0, 1, "1e16"), (0, 1, "1"), (0, 1, "-1e16"), (0, 1, "2")], 1) == {(0, 1): 2.0}
    assert dense_power(3, [(0, 1, "5e-324"), (1, 2, "0.5")], 2, rational=False) == {}
    assert dense_power(3, [(0, 1, "5e-324"), (1, 2, "2")], 2, rational=False) == {(0, 2): float("1e-323")}
    check_output(b'"source","target","weight"\r\n"0","1","-2"\r\n', 2, {(0, 1): -2.0})
    data, count = exact_cap_input()
    records = list(csv.reader(StringIO(data.decode())))
    assert len(data) == CAP and len(records) - 1 == count and count <= 65536
    assert all(len(field) <= 128 for row in records for field in row)
    assert all(sum(map(len, row)) <= 384 for row in records)
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, *args, **kwargs): self.count += 1
    for function in (model, rejection, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = ("mmap(NULL, 28, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
             "mmap(NULL, 56, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (Cannot allocate memory) (INJECTED)\n"
             "munmap(0x1000, 28) = 0\n")
    assert len(events(trace)) == 3
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("cleanup control accepted an observed unreleased mapping")
    print("sparse-paths CPU controls=14")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"sparse-paths-{mode} cases={runner.count} evidence={runner.directory}")
