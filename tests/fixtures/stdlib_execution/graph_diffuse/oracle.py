"""Dense Fraction elimination and true-residual checks for graph diffusion."""
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
HEADER = b"kind,source,target,value\n"
HELP = (b"Usage: graph-diffuse --nodes N [--lambda V] [--iterations K] [--rtol V] [--atol V] [--help]\n"
        b"Read CSV kind,source,target,value: edge,u,v,weight or source,node,,value.\n"
        b"Solve (I + lambda*L)x=b with Jacobi CG; edge weights are finite and nonnegative.\n"
        b"Nodes: 1..4096; iterations: 0..1000 (default 100); lambda: finite >=0 (default 1).\n"
        b"Tolerances: finite >=0; rtol default 1e-10, atol default 0. Sources may be signed.\n"
        b"Short options: -n N, -k K, -h. Limits: 4 MiB input, 65536 records, 1 MiB staged output.\n")
ERROR = b"graph-diffuse: operation failed\n"
NUMBER = re.compile(r"-?(?:[0-9]+(?:\.[0-9]*)?)(?:e[+-]?[0-9]+)?\Z")
COUNTS = {"model": 36, "rejection": 48, "cli": 55, "io": 15}


def encode(rows, *, quoted=False):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
               lineterminator="\r\n").writerows(rows)
    return stream.getvalue().encode()


def edge(u, v, value):
    return "edge", u, v, str(value)


def source(u, value):
    return "source", u, "", str(value)


def assemble(nodes, records, scale=1.0):
    """Independent dense I+lambda*L, using the documented assembly rounding.

    This does not sort triplets, use CSR, run CG or imitate its preconditioner.
    Identity coefficients precede original-order edge contributions. Source
    terms accumulate separately in original input order.
    """
    assert 1 <= nodes <= 32 and math.isfinite(scale) and scale >= 0
    matrix = [[float(row == column) for column in range(nodes)] for row in range(nodes)]
    rhs = [0.0] * nodes
    adjacency = [set() for _ in range(nodes)]
    for kind, u, v, spelling in records:
        value = float(spelling)
        assert math.isfinite(value) and 0 <= u < nodes
        if kind == "source":
            assert v == ""
            rhs[u] += value
            if not math.isfinite(rhs[u]):
                raise OverflowError("source sum")
        else:
            assert kind == "edge" and 0 <= v < nodes and value >= 0
            if u == v:
                continue
            weight = scale * value
            if not math.isfinite(weight):
                raise OverflowError("scaled edge")
            if weight == 0:
                continue
            adjacency[u].add(v)
            adjacency[v].add(u)
            for row, column, coefficient in ((u, u, weight), (v, v, weight), (u, v, -weight), (v, u, -weight)):
                matrix[row][column] += coefficient
                if not math.isfinite(matrix[row][column]):
                    raise OverflowError("coefficient sum")
    return matrix, rhs, adjacency


def gaussian(matrix, rhs):
    """Exact rational dense Gaussian elimination, not a CG recurrence."""
    n = len(rhs)
    work = [[Fraction(value) for value in row] + [Fraction(rhs[index])]
            for index, row in enumerate(matrix)]
    for column in range(n):
        pivot = next(row for row in range(column, n) if work[row][column])
        work[column], work[pivot] = work[pivot], work[column]
        divisor = work[column][column]
        work[column] = [value / divisor for value in work[column]]
        for row in range(column + 1, n):
            factor = work[row][column]
            for entry in range(column, n + 1):
                work[row][entry] -= factor * work[column][entry]
    result = [Fraction(0)] * n
    for row in range(n - 1, -1, -1):
        result[row] = work[row][n] - sum((work[row][column] * result[column]
                                         for column in range(row + 1, n)), Fraction(0))
    return [float(value) for value in result]


def parse_output(raw, nodes):
    rows = list(csv.reader(StringIO(raw.decode("ascii"), newline=""), strict=True))
    assert rows and rows[0] == ["node", "value"] and len(rows) == nodes + 1, rows[:3]
    assert encode(rows, quoted=True) == raw, "output is not fully quoted CRLF CSV"
    result = []
    for index, record in enumerate(rows[1:]):
        assert len(record) == 2 and record[0] == str(index) and NUMBER.fullmatch(record[1]), (index, record)
        value = float(record[1])
        assert math.isfinite(value), record
        result.append(value)
    return result


def check_solution(raw, nodes, expected, *, system=None, rtol=1e-10, atol=0.0, exact=False):
    actual = parse_output(raw, nodes)
    assert len(expected) == nodes
    magnitude = max(1.0, *(abs(value) for value in expected))
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        tolerance = max(2e-8 * magnitude, 64 * math.ulp(wanted))
        assert got == wanted if exact else abs(got - wanted) <= tolerance, (index, got, wanted, tolerance)
    if system is None:
        return
    matrix, rhs, adjacency = system
    residual = []
    for row, coefficients in enumerate(matrix):
        product = 0.0
        for column in range(nodes):
            product += coefficients[column] * actual[column]
        residual.append(rhs[row] - product)
    residual_norm = math.hypot(*residual)
    rhs_norm = math.hypot(*rhs)
    # Independent hypot and the library's scaled norm can differ by a few
    # rounding bits. This allowance is 2e-14 relative to the stopping boundary,
    # not an additional absolute tolerance for a nonzero residual.
    stopped = residual_norm <= atol * (1 + 2e-14)
    if rtol > 0 and rhs_norm > 0:
        stopped |= residual_norm / rhs_norm <= rtol * (1 + 2e-14)
    assert stopped, ("fresh residual", residual_norm, rhs_norm, rtol, atol, actual)
    if rtol >= 1 or atol > 0:
        return  # Loose stopping can legitimately retain the initial zero iterate.
    unseen = set(range(nodes))
    while unseen:
        component = {min(unseen)}
        frontier = list(component)
        while frontier:
            current = frontier.pop()
            for following in adjacency[current] - component:
                component.add(following)
                frontier.append(following)
        unseen -= component
        wanted_sum = math.fsum(rhs[index] for index in component)
        actual_sum = math.fsum(actual[index] for index in component)
        # Diffusion preserves component mass and keeps values in the convex
        # hull of its source values, up to this finite rounding tolerance.
        tolerance = 4e-8 * max(1.0, math.fsum(abs(rhs[index]) for index in component))
        assert abs(actual_sum - wanted_sum) <= tolerance, (component, actual_sum, wanted_sum)
        low = min(rhs[index] for index in component)
        high = max(rhs[index] for index in component)
        assert all(low - tolerance <= actual[index] <= high + tolerance for index in component)


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
            item["size"] = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, (line, live)
                live[address] = item["size"]
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
        self.directory = Path(tempfile.mkdtemp(prefix=f"graph-diffuse-{mode}-"))
        self.count = 0

    def run(self, name, arguments=("--nodes", "2"), data=HEADER, *, status=0,
            expected=None, nodes=2, system=None, rtol=1e-10, atol=0.0, exact=False,
            output=None, read_error=False, closed_reader=False, trace=False,
            injection=None, diagnostic=True):
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
            check_solution(result.stdout, nodes, expected, system=system, rtol=rtol, atol=atol, exact=exact)
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

    def model(self, name, nodes, records, *, scale=1.0, iterations=100,
              rtol=1e-10, atol=0.0, arguments=None, data=None, expected=None,
              exact=False, check_system=True):
        if arguments is None:
            arguments = ["--nodes", str(nodes), "--lambda", str(scale), "--iterations", str(iterations),
                         "--rtol", str(rtol), "--atol", str(atol)]
        if data is None:
            data = encode([("kind", "source", "target", "value"), *records])
        system = assemble(nodes, records, scale) if nodes <= 32 and check_system else None
        if expected is None:
            assert system is not None
            expected = gaussian(system[0], system[1])
        self.run(name, arguments, data, nodes=nodes, expected=expected, system=system,
                 rtol=rtol, atol=atol, exact=exact)


def exact_cap_input():
    maximum = b"edge," + b"0" * 128 + b"," + b"0" * 128 + b"," + b"0" * 128 + b"\n"
    minimum = b"edge,0,0,0\n"
    full = (CAP - len(HEADER) - len(minimum)) // len(maximum)
    data = bytearray(HEADER + maximum * full)
    remaining = CAP - len(data)
    if remaining > len(maximum):
        data.extend(minimum)
        remaining -= len(minimum)
    padding = remaining - len(minimum)
    fields = []
    for _ in range(3):
        amount = min(padding, 127)
        fields.append(b"0" * amount + b"0")
        padding -= amount
    assert padding == 0
    data.extend(b"edge," + b",".join(fields) + b"\n")
    assert len(data) == CAP
    return bytes(data)


def model(r):
    r.model("single-source", 1, [source(0, 3)], exact=True)
    r.model("header-only-zero", 3, [], exact=True)
    r.model("unforced-connected", 4, [edge(0, 1, 2), edge(1, 2, 1)], exact=True)
    r.model("two-node-closed-form", 2, [edge(0, 1, 1), source(0, 1)], expected=[2 / 3, 1 / 3])
    r.model("lambda-two-closed-form", 2, [edge(0, 1, 1), source(0, 1)], scale=2, expected=[3 / 5, 2 / 5])
    r.model("edge-lambda-product", 2, [edge(0, 1, 2), source(0, 1)], scale=.5)
    r.model("signed-source", 2, [edge(0, 1, 1), source(0, 1), source(1, -1)])
    r.model("antisymmetric-chain", 3, [edge(0, 1, 1), edge(1, 2, 1), source(0, 1), source(2, -1)])
    r.model("parallel-reversed-edges", 2, [edge(0, 1, .5), edge(1, 0, .25), edge(0, 1, .25), source(0, 1)])
    r.model("self-loops-ignored", 2, [edge(0, 0, 4), edge(1, 1, 7), source(0, -2)], exact=True)
    r.model("huge-self-loop-skips-scaling", 1, [edge(0, 0, "1e308"), source(0, 2)], scale=1e308, exact=True)
    r.model("disconnected-components", 5, [edge(0, 1, 1), edge(2, 3, 2), source(0, 2), source(2, -3), source(4, 5)])
    r.model("ordered-source-sum", 1, [source(0, "1e16"), source(0, 1), source(0, "-1e16"), source(0, 2)], exact=True)
    r.model("cancelled-source-zero-iterations", 2, [edge(0, 1, 1), source(0, 3), source(0, -3)], iterations=0, exact=True)
    r.model("signed-zero-edge", 2, [edge(0, 1, "-0"), source(1, -2)], exact=True)
    r.model("zero-lambda-identity", 3, [edge(0, 1, 5), edge(1, 2, 3), source(0, -2), source(1, 4)], scale=0, exact=True)
    r.model("zero-rhs-zero-iterations", 2, [edge(0, 1, 2)], iterations=0, exact=True)
    r.model("absolute-stop-zero-iterations", 1, [source(0, .125)], iterations=0, atol=.25,
            expected=[0.0], exact=True)
    r.model("relative-stop-zero-iterations", 2, [edge(0, 1, 1), source(0, 1)], iterations=0, rtol=1,
            expected=[0.0, 0.0], exact=True)
    r.model("last-allowed-update-converges", 2, [edge(0, 1, 1), source(0, 1), source(1, 1)], iterations=1, exact=True)
    r.model("two-allowed-updates-converge", 2, [edge(0, 1, 1), source(0, 1)], iterations=2)
    r.model("maximum-iterations-option", 2, [edge(0, 1, 1), source(0, 1)], iterations=1000)
    r.model("subnormal-edge-zero-rhs", 2, [edge(0, 1, "5e-324")], iterations=0, exact=True)
    r.model("underflowed-scaled-edge", 2, [edge(0, 1, "5e-324"), source(0, 2)], scale=.5, exact=True)
    r.model("decimal-underflow-source", 2, [source(0, "1e-999")], exact=True)
    r.model("quoted-fields-leading-zeroes", 2, [edge(0, 1, 1), source(0, 2)],
            data=encode([("kind", "source", "target", "value"), ("edge", "000", "001", "+1.0"),
                         ("source", "000", "", "2")], quoted=True))
    r.model("maximum-nodes-zero", 4096, [], expected=[0.0] * 4096, exact=True)
    r.model("maximum-nodes-isolated-source", 4096, [source(4095, 3)], expected=[0.0] * 4095 + [3.0], exact=True)
    r.model("maximum-records", 1, [source(0, 1)] * 65536, expected=[65536.0], exact=True)
    r.model("exact-four-mib", 2, [], iterations=0, data=exact_cap_input(), expected=[0.0, 0.0], exact=True)
    rng = random.Random(0xD1FF05E)
    for index in range(6):
        nodes = rng.randrange(2, 9)
        records = [edge(rng.randrange(nodes), rng.randrange(nodes), rng.randrange(0, 9) / 4)
                   for _ in range(rng.randrange(1, 25))]
        records += [source(node, rng.randrange(-8, 9) / 2) for node in range(nodes)]
        r.model(f"seeded-dense-{index}", nodes, records, scale=rng.choice([.25, .5, 1, 2]))


def rejection(r):
    cases = [
        ("empty", b""), ("wrong-header", b"kind,target,source,value\n"),
        ("header-case", b"Kind,source,target,value\n"), ("extra-header", b"kind,source,target,value,x\n"),
        ("bom", b"\xef\xbb\xbf" + HEADER), ("blank-row", HEADER + b"\n"),
        ("unknown-kind", HEADER + b"other,0,1,1\n"), ("kind-case", HEADER + b"Edge,0,1,1\n"),
        ("missing-field", HEADER + b"edge,0,1\n"), ("extra-field", HEADER + b"edge,0,1,1,x\n"),
        ("negative-source", HEADER + b"edge,-1,0,1\n"), ("negative-target", HEADER + b"edge,0,-1,1\n"),
        ("source-bound", HEADER + b"source,2,,1\n"), ("target-bound", HEADER + b"edge,0,2,1\n"),
        ("source-plus", HEADER + b"source,+0,,1\n"), ("target-fraction", HEADER + b"edge,0,1.0,1\n"),
        ("endpoint-overflow", HEADER + b"edge,18446744073709551616,0,1\n"),
        ("edge-empty-target", HEADER + b"edge,0,,1\n"), ("source-nonempty-target", HEADER + b"source,0,0,1\n"),
        ("negative-edge", HEADER + b"edge,0,1,-1\n"), ("nan", HEADER + b"source,0,,nan\n"),
        ("infinity", HEADER + b"edge,0,1,inf\n"), ("decimal-overflow", HEADER + b"source,0,,1e309\n"),
        ("empty-value", HEADER + b"source,0,,\n"), ("trailing-value", HEADER + b"edge,0,1,1x\n"),
        ("unclosed-quote", HEADER + b'edge,0,1,"1'), ("quote-in-unquoted", HEADER + b'edge,0,1,1"2\n'),
        ("bare-cr", b"kind,source,target,value\redge,0,1,1\r"),
        ("invalid-utf8", HEADER + b"edge,0,1,\xff\n"), ("nul", HEADER + b"source,0,,\x00\n"),
        ("quoted-tab", HEADER + b'source,0,,"\t1"\n'),
        ("field-over-cap", HEADER + b"source,0,," + b"0" * 128 + b"1\n"),
        ("record-over-cap", HEADER + b"source,0,,1\n" * 65537),
        ("input-over-cap", b"x" * (CAP + 1)),
        ("later-invalid-no-prefix", HEADER + b"source,0,,1\nedge,0,2,1\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)
    r.run("zero-lambda-still-validates", ["--nodes", "2", "--lambda", "0"], HEADER + b"edge,0,1,-1\n", status=2)
    r.run("self-loop-still-validates", data=HEADER + b"edge,0,0,-1\n", status=2)
    r.run("later-invalid-precedes-source-arithmetic", data=HEADER + b"source,0,,1e308\nsource,0,,1e308\nedge,0,2,1\n", status=2)
    r.run("later-invalid-precedes-edge-arithmetic", ["--nodes", "2", "--lambda", "2"],
          HEADER + b"edge,0,1,1e308\nsource,2,,1\n", status=2)
    r.run("nonzero-rhs-zero-iterations", ["--nodes", "2", "--iterations", "0"], HEADER + b"source,0,,1\n", status=6)
    r.run("honest-one-step-limit", ["--nodes", "2", "--iterations", "1"], HEADER + b"edge,0,1,1\nsource,0,,1\n", status=6)
    r.run("full-requested-work-cap", ["--nodes", "4096", "--iterations", "1000"], status=2)
    r.run("source-sum-overflow", data=HEADER + b"source,0,,1e308\nsource,0,,1e308\nsource,0,,-1e308\n", status=6)
    r.run("scaled-edge-overflow", ["--nodes", "2", "--lambda", "2"], HEADER + b"edge,0,1,1e308\n", status=6)
    r.run("diagonal-sum-overflow", data=HEADER + b"edge,0,1,1e308\nedge,0,1,1e308\n", status=6)
    r.run("lost-identity-breakdown", data=HEADER + b"edge,0,1,1e200\nsource,0,,1\nsource,1,,1\n", status=6)
    r.run("dot-overflow", ["--nodes", "1"], HEADER + b"source,0,,1e200\n", status=6)
    r.run("dot-underflow", ["--nodes", "1"], HEADER + b"source,0,,5e-324\n", status=6)


def cli(r):
    invalid = [
        [], ["--nodes"], ["--nodes", "0"], ["--nodes", "4097"], ["--nodes", "-1"],
        ["--nodes", "+1"], ["--nodes", "1.0"], ["--nodes", ""], ["--nodes", "18446744073709551616"],
        ["--iterations", "1"], ["--nodes", "2", "--iterations"], ["--nodes", "2", "--iterations", "1001"],
        ["--nodes", "2", "--iterations", "-1"], ["--nodes", "2", "--iterations", "+1"],
        ["--nodes", "2", "--iterations", "1.0"], ["--nodes", "2", "--iterations", ""],
        ["--nodes", "2", "--iterations", "18446744073709551616"],
        ["--unknown"], ["graph.csv"], ["--nodes", "2", "-n3"],
        ["--nodes", "2", "--iterations", "1", "-k2"], ["--help", "--help"], ["-hh"],
        ["--help", "--nodes", "0"], ["--help", "--iterations", "1001"], ["--help=yes"],
        ["--nodes", "2", "--", "operand"], [""] * 25, ["--nodes", "0" * 1025],
    ]
    for option in ("--lambda", "--rtol", "--atol"):
        for value in ("-1", "nan", "inf", "1e309", "0" * 129):
            invalid.append(["--help", option, value])
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-nodes-and-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-all-valid-options", ["--help", "--nodes", "4096", "--iterations", "1000", "--lambda", "-0", "--rtol", "0", "--atol", "1"], output=HELP)
    r.model("short-attached", 2, [edge(0, 1, 1), source(0, 1)], iterations=2,
            arguments=["-n2", "-k2"])
    r.model("long-equals-leading-zeroes", 1, [source(0, -2)], iterations=1,
            arguments=["--nodes=001", "--iterations=001", "--lambda=+0", "--rtol=0", "--atol=0"], exact=True)
    for option in ("--lambda", "--rtol", "--atol"):
        r.run(f"duplicate-{option[2:]}", ["--help", option, "1", option, "2"], status=2, read_error=True)
    r.run("missing-lambda-value", ["--help", "--lambda"], status=2, read_error=True)
    r.run("missing-rtol-value", ["--help", "--rtol"], status=2, read_error=True)
    r.run("missing-atol-value", ["--help", "--atol"], status=2, read_error=True)


def io(r):
    nodes = 7
    args = ["--nodes", str(nodes)]
    records = [edge(row, row + 1, 1) for row in range(nodes - 1)] + [source(0, 2), source(6, -1)]
    data = encode([("kind", "source", "target", "value"), *records])
    system = assemble(nodes, records)
    wanted = gaussian(system[0], system[1])
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", args, data, status=5, closed_reader=True)
    r.run("closed-help-output", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", args, data, nodes=nodes, expected=wanted, system=system, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    size = 8 * nodes
    # Current CG uses six n-element f64 buffers (x/r/z/p/q/diagonal). Select
    # the last six-map run of that size; this is fault-site discovery only.
    matches = [index for index in range(len(maps) - 5)
               if all(item["size"] == size for item in maps[index:index + 6])]
    assert matches, ("CG workspace recipe", [item["size"] for item in maps])
    start = matches[-1]
    selected = [maps[0], *maps[start:start + 6], maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 8
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"reached-oom-{ordinal}", args, data, status=4, trace=True,
                       injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"], (old, fault)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, nodes=nodes, expected=wanted, system=system, trace=True,
              injection=(call, 1, "EINTR"))
    r.run("signal-setup-failure", args, data, status=5, trace=True,
          injection=("rt_sigaction", 1, "EIO"), diagnostic=False)


def controls():
    assert len(HELP) == 501 and len(ERROR) == 32
    matrix, rhs, _ = assemble(2, [edge(0, 1, 1), source(0, 1)])
    assert matrix == [[2.0, -1.0], [-1.0, 2.0]] and gaussian(matrix, rhs) == [2 / 3, 1 / 3]
    m, b, _ = assemble(1, [edge(0, 0, "1e308"), source(0, 2)], 1e308)
    assert m == [[1.0]] and gaussian(m, b) == [2.0]
    m, b, _ = assemble(1, [source(0, "1e16"), source(0, 1), source(0, "-1e16"), source(0, 2)])
    assert gaussian(m, b) == [2.0]
    data = exact_cap_input()
    records = list(csv.reader(StringIO(data.decode())))
    assert len(data) == CAP and len(records) - 1 <= 65536
    assert all(len(field) <= 128 for row in records for field in row)
    assert all(sum(map(len, row)) <= 512 for row in records)
    valid = encode([("node", "value"), (0, "0.6666666666666666"), (1, "0.3333333333333333")], quoted=True)
    check_solution(valid, 2, [2 / 3, 1 / 3], system=assemble(2, [edge(0, 1, 1), source(0, 1)]))
    try:
        check_solution(encode([("node", "value"), (0, 0), (1, 0)], quoted=True), 2, [0, 0],
                       system=assemble(2, [edge(0, 1, 1), source(0, 1)]))
    except AssertionError:
        pass
    else:
        raise AssertionError("residual control accepted false convergence")
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, *args, **kwargs): self.count += 1
    for function in (model, rejection, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    class ReferenceChecks(CounterOnly):
        def model(self, name, nodes, records, **options):
            system = assemble(nodes, records, options.get("scale", 1.0)) if nodes <= 32 else None
            wanted = options.get("expected")
            if wanted is None:
                wanted = gaussian(system[0], system[1])
            raw = encode([("node", "value"), *[(node, str(value)) for node, value in enumerate(wanted)]], quoted=True)
            check_solution(raw, nodes, wanted, system=system,
                           rtol=options.get("rtol", 1e-10), atol=options.get("atol", 0.0),
                           exact=options.get("exact", False))
            self.count += 1
    reference = ReferenceChecks()
    model(reference)
    assert reference.count == COUNTS["model"]
    trace = ("mmap(NULL, 56, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
             "munmap(0x1000, 56) = 0\n")
    assert len(events(trace)) == 2
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("cleanup control accepted an observed unreleased mapping")
    print("graph-diffuse CPU controls=11")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"graph-diffuse-{mode} cases={runner.count} evidence={runner.directory}")
