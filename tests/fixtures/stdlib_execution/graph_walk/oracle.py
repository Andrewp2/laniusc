"""Independent dense/Fraction graph-walk models and small native fault checks."""
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
HELP = (b"Usage: graph-walk --nodes N [--steps K] [--source S] [--help]\n"
        b"Read CSV source,target,weight; advance a source unit mass on normalized directed edges.\n"
        b"Nodes: 1..4096; steps: 0..1000 (default 1); source: 0..N-1 (default 0).\n"
        b"Dangling nodes keep their mass. Duplicate edge weights coalesce in input order.\n"
        b"Short options: -n N, -k K, -s S, -h. Limits: 4 MiB input, 65536 edges.\n")
ERROR = b"graph-walk: operation failed\n"
NUMBER = re.compile(r"-?(?:[0-9]+(?:\.[0-9]*)?)(?:e[+-]?[0-9]+)?\Z")


def encode(rows, *, quoted=False):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
               lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode()


def model_mass(nodes, edges, steps=1, source=0):
    """Coalesce binary64 inputs, then independently materialize a dense operator.

    Match the specified finite binary64 assembly/normalization profile. The
    subsequent walks use exact rational dense products, not production CSR
    indexing or its iterative floating accumulator.
    """
    assert nodes <= 32, "large admission cases use an explicit known result"
    weights = [[0.0] * nodes for _ in range(nodes)]
    for row, column, spelling in edges:
        value = float(spelling)
        assert math.isfinite(value) and value >= 0
        weights[row][column] += value
        if not math.isfinite(weights[row][column]):
            raise OverflowError("coalescing overflow")
    transition = [[Fraction(0)] * nodes for _ in range(nodes)]
    for row in range(nodes):
        total = 0.0
        for value in weights[row]:
            total += value
            if not math.isfinite(total):
                raise OverflowError("row sum overflow")
        if total == 0:
            transition[row][row] = Fraction(1)
        else:
            for column in range(nodes):
                # Rounding the exact ratio defines the binary64 stored transition.
                ratio = float(Fraction(weights[row][column]) / Fraction(total))
                transition[row][column] = Fraction(ratio)
    mass = [Fraction(int(index == source)) for index in range(nodes)]
    for _ in range(steps):
        mass = [sum((transition[row][column] * mass[row] for row in range(nodes)), Fraction(0))
                for column in range(nodes)]
    return [float(value) for value in mass]


def check_output(raw, expected, exact=False):
    text = raw.decode("ascii")
    rows = list(csv.reader(StringIO(text, newline=""), strict=True))
    assert rows and rows[0] == ["node", "mass"] and len(rows) == len(expected) + 1, rows[:3]
    assert encode(rows, quoted=True) == raw, "output is not fully quoted CRLF CSV"
    for index, (row, wanted) in enumerate(zip(rows[1:], expected)):
        assert len(row) == 2 and row[0] == str(index) and NUMBER.fullmatch(row[1]), (index, row)
        actual = float(row[1])
        assert math.isfinite(actual) and actual >= 0, (index, actual)
        if exact or wanted == 0:
            assert actual == wanted, (index, actual, wanted)
        else:
            tolerance = max(abs(wanted) * 2e-12, 32 * math.ulp(wanted))
            assert abs(actual - wanted) <= tolerance, (index, actual, wanted, tolerance)


def events(text):
    found, counts = [], Counter()
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|mmap|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        found.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
    return found


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"graph-walk-{mode}-"))
        self.count = 0

    def run(self, name, arguments=("--nodes", "2"), data=b"source,target,weight\n", *,
            status=0, expected=None, exact=False, output=None, read_error=False,
            closed_reader=False, trace=False, injection=None, diagnostic=True):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, error = injection
                traced += ["-e", f"inject={call}:error={error}:when={ordinal}"]
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
            check_output(result.stdout, expected, exact)
        else:
            assert result.stdout == (output or b""), (name, result.stdout[:120], output)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [entry for entry in found if "INJECTED" in entry["answer"]]
        if injection:
            call, ordinal, error = injection
            selected = [entry for entry in found if entry["name"] == call and entry["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, injection, marked)
            assert selected[0]["answer"].startswith("-1 " + error + " "), selected[0]
        else:
            assert not marked, marked
        self.count += 1
        return found

    def model(self, name, nodes, edges, *, steps=1, source=0, arguments=None,
              data=None, expected=None, exact=False):
        if arguments is None:
            arguments = ["--nodes", str(nodes), "--steps", str(steps), "--source", str(source)]
        if data is None:
            data = encode([("source", "target", "weight"), *edges])
        if expected is None:
            expected = model_mass(nodes, edges, steps, source)
        self.run(name, arguments, data, expected=expected, exact=exact)


def exact_cap_input():
    header = b"source,target,weight\n"
    maximum = b"0" * 128 + b"," + b"0" * 127 + b"1," + b"0" * 127 + b"1\n"
    full = (CAP - len(header) - 6) // len(maximum)
    data = bytearray(header + maximum * full)
    remaining = CAP - len(data)
    if remaining > len(maximum):
        data.extend(b"0,1,1\n")
        remaining -= 6
    padding = remaining - 6
    fields = []
    for value in (b"0", b"1", b"1"):
        count = min(padding, 127)
        fields.append(b"0" * count + value)
        padding -= count
    assert padding == 0
    data.extend(b",".join(fields) + b"\n")
    assert len(data) == CAP
    return bytes(data)


def model(r):
    r.model("one-dangling-node", 1, [], steps=7, exact=True)
    r.model("all-dangling", 5, [], source=3, exact=True)
    r.model("default-step-source", 3, [(0, 1, "1"), (1, 2, "1")], arguments=["--nodes", "3"], exact=True)
    r.model("directed-chain", 4, [(0, 1, "2"), (1, 2, "3"), (2, 3, "4")], steps=3, exact=True)
    r.model("dangling-retains-arrivals", 3, [(0, 1, "1")], steps=10, exact=True)
    r.model("reverse-directed-edge", 3, [(1, 0, "1"), (2, 1, "1")], source=2, steps=2, exact=True)
    r.model("self-loop", 2, [(0, 0, "5"), (1, 0, "1")], steps=20, exact=True)
    r.model("weighted-split", 3, [(0, 1, "1"), (0, 2, "3")], exact=True)
    r.model("duplicate-coalescing", 3, [(0, 2, "1"), (0, 1, "1"), (0, 2, "2"), (0, 1, "1")])
    r.model("cycles", 3, [(0, 1, "1"), (1, 2, "1"), (2, 0, "1")], steps=1000, exact=True)
    r.model("zero-steps", 3, [(0, 1, "1"), (1, 2, "1")], source=2, steps=0, exact=True)
    r.model("zero-and-negative-zero-weights", 3, [(0, 1, "0"), (0, 2, "-0"), (1, 2, "2")], steps=5, exact=True)
    r.model("minimum-subnormal-row", 2, [(0, 1, "5e-324")], exact=True)
    r.model("subnormal-ratio", 3, [(0, 1, "5e-324"), (0, 2, "1e-323")], exact=True)
    r.model("huge-finite-row", 2, [(0, 1, "1.7976931348623157e308")], exact=True)
    r.model("underflowed-ratio-omitted", 3, [(0, 1, "5e-324"), (0, 2, "1e308")], exact=True)
    r.model("tiny-positive-mass", 3, [(0, 1, "5e-324"), (0, 2, "1")], exact=True)
    r.model("decimal-underflow-to-zero", 2, [(0, 1, "1e-999")], exact=True)
    r.model("quoted-header-leading-zeroes", 2, [(0, 1, "1")],
            data=encode([("source", "target", "weight"), ("000", "001", "+1.0")], quoted=True), exact=True)
    r.model("maximum-nodes", 4096, [], source=4095,
            expected=[0.0] * 4095 + [1.0], exact=True)
    r.model("maximum-raw-edges", 2, [(0, 1, "1")] * 65536, exact=True)
    r.model("exact-four-mib-input", 2, [(0, 1, "1")], data=exact_cap_input(), exact=True)
    rng = random.Random(0xC5A6A)
    for index in range(10):
        nodes = rng.randrange(2, 9)
        edges = [(rng.randrange(nodes), rng.randrange(nodes), str(rng.randrange(0, 9)))
                 for _ in range(rng.randrange(1, 45))]
        r.model(f"seeded-{index}", nodes, edges, steps=rng.randrange(0, 31), source=rng.randrange(nodes))


def rejection(r):
    header = b"source,target,weight\n"
    cases = [
        ("empty", b""), ("wrong-header", b"target,source,weight\n"),
        ("header-case", b"Source,target,weight\n"), ("extra-header", b"source,target,weight,extra\n"),
        ("missing-field", header + b"0,1\n"), ("extra-field", header + b"0,1,1,x\n"),
        ("negative-source", header + b"-1,0,1\n"), ("negative-target", header + b"0,-1,1\n"),
        ("source-bound", header + b"2,0,1\n"), ("target-bound", header + b"0,2,1\n"),
        ("source-plus", header + b"+0,1,1\n"), ("target-fraction", header + b"0,1.0,1\n"),
        ("endpoint-overflow", header + b"18446744073709551616,0,1\n"),
        ("negative-weight", header + b"0,1,-1\n"), ("nan", header + b"0,1,nan\n"),
        ("infinity", header + b"0,1,inf\n"), ("decimal-overflow", header + b"0,1,1e309\n"),
        ("empty-weight", header + b"0,1,\n"), ("trailing-weight", header + b"0,1,1x\n"),
        ("unclosed-quote", header + b'0,1,"1'), ("quote-in-unquoted", header + b'0,1,1"2\n'),
        ("bare-cr", b"source,target,weight\r0,1,1\r"),
        ("invalid-utf8", header + b"0,1,\xff\n"), ("nul", header + b"0,1,\x00\n"),
        ("quoted-tab", header + b'0,1,"\t1"\n'),
        ("field-over-cap", header + b"0,1," + b"0" * 128 + b"1\n"),
        ("edge-count-over-cap", header + b"0,1,1\n" * 65537),
        ("input-over-cap", b"x" * (CAP + 1)),
        ("later-error-no-output", header + b"0,1,1\n1,0,-1\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)
    r.run("zero-steps-still-validates", ["--nodes", "2", "--steps", "0"], header + b"0,1,-1\n", status=2)
    for name, data in [
        ("duplicate-overflow", header + b"0,1,1.7976931348623157e308\n0,1,1.7976931348623157e308\n"),
        ("row-sum-overflow", header + b"0,0,1e308\n0,1,1e308\n"),
    ]:
        r.run(name, data=data, status=6)
    r.run("zero-steps-still-normalizes", ["--nodes", "2", "--steps", "0"],
          header + b"0,0,1e308\n0,1,1e308\n", status=6)


def cli(r):
    invalid = [
        [], ["--nodes"], ["--nodes", "0"], ["--nodes", "4097"], ["--nodes", "-1"],
        ["--nodes", "+1"], ["--nodes", "1.0"], ["--nodes", ""],
        ["--nodes", "18446744073709551616"], ["--steps", "1"], ["--source", "0"],
        ["--nodes", "2", "--steps"], ["--nodes", "2", "--steps", "1001"],
        ["--nodes", "2", "--steps", "-1"], ["--nodes", "2", "--source"],
        ["--nodes", "2", "--source", "2"], ["--nodes", "2", "--source", "-1"],
        ["--nodes", "2", "--source", "1_0"], ["--unknown"], ["graph.csv"],
        ["--nodes", "2", "-n3"], ["--nodes", "2", "--steps", "1", "-k2"],
        ["--nodes", "2", "--source", "0", "--source", "1"],
        ["--help", "--help"], ["-hh"], ["--help", "--nodes", "0"],
        ["--help", "--nodes", "2", "--source", "2"], ["--help", "--source", "4096"],
        ["--help=yes"], ["--nodes", "2", "--", "operand"],
        [""] * 25, ["--nodes", "0" * 1025],
    ]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-nodes-and-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-with-source-without-nodes", ["--help", "--source", "4095"], output=HELP, read_error=True)
    r.run("help-with-valid-options", ["--help", "--nodes", "4096", "--steps", "1000", "--source", "4095"], output=HELP)
    r.model("short-attached", 3, [(0, 1, "1"), (1, 2, "1")], steps=2, arguments=["-n3", "-k2", "-s0"], exact=True)
    r.model("long-equals-leading-zeroes", 2, [], source=1, steps=0,
            arguments=["--nodes=002", "--steps=000", "--source=001"], exact=True)


def io(r):
    args = ["--nodes", "3", "--steps", "2"]
    edges = [(0, 1, "1"), (0, 2, "3"), (1, 2, "2")]
    data = encode([("source", "target", "weight"), *edges])
    wanted = model_mass(3, edges, 2)
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", args, data, status=5, closed_reader=True)
    r.run("closed-help-output", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", args, data, expected=wanted, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) >= 3 and all(item["answer"].startswith("0x") for item in maps), maps
    # Three reached ordinals sample construction, middle processing and staging;
    # these are not asserted to be exhaustive or tied to an owner ledger.
    ordinals = [1, (len(maps) + 1) // 2, len(maps)]
    assert len(set(ordinals)) == 3
    for ordinal in ordinals:
        actual = r.run(f"reached-oom-{ordinal}", args, data, status=4, trace=True,
                       injection=("mmap", ordinal, "ENOMEM"))
        old = next(item for item in maps if item["ordinal"] == ordinal)
        new = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == new["args"], (old, new)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, expected=wanted, trace=True,
              injection=(call, 1, "EINTR"))
    r.run("signal-setup-failure", args, data, status=5, trace=True,
          injection=("rt_sigaction", 1, "EIO"), diagnostic=False)


def controls():
    assert len(HELP) == 373 and len(ERROR) == 29
    assert model_mass(3, [(0, 1, "1"), (0, 2, "3")]) == [0.0, .25, .75]
    assert model_mass(3, [(0, 1, "1")], 4) == [0.0, 1.0, 0.0]
    assert model_mass(3, [(2, 1, "1"), (1, 0, "1")], 2, 2) == [1.0, 0.0, 0.0]
    assert model_mass(2, [(0, 1, "5e-324")]) == [0.0, 1.0]
    assert model_mass(3, [(0, 1, "5e-324"), (0, 2, "1")])[1] == float("5e-324")
    check_output(b'"node","mass"\r\n"0","0.25"\r\n"1","0.75"\r\n', [.25, .75], True)
    assert len(exact_cap_input()) == CAP
    class CounterOnly:
        def __init__(self):
            self.count = 0
        def run(self, *args, **kwargs):
            self.count += 1
        def model(self, *args, **kwargs):
            self.count += 1
    for function, count in ((model, 32), (rejection, 33), (cli, 38)):
        runner = CounterOnly()
        function(runner)
        assert runner.count == count, (function.__name__, runner.count, count)
    print("graph-walk CPU controls=9")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        print(f"graph-walk-{mode} cases={runner.count} evidence={runner.directory}")
