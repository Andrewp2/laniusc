"""Independent Fraction/Decimal reference for the numerical CSV application."""
import csv
from decimal import Decimal, localcontext
from fractions import Fraction
from io import StringIO
import math
import os
from pathlib import Path
import random
import subprocess
import sys
import tempfile

HELP = (b"Usage: sample-moments [--help] < samples.csv\n"
        b"Input header: value,weight. Finite numbers, nonnegative weights, at most 4096 rows.\n"
        b"Output: profile,metric,value,status. Higher moments count positive-weight rows once.\n"
        b"Limits: 1 MiB input, 128 bytes per numeric field, 16 KiB staged output.\n")
ERROR = b"sample-moments: operation failed\n"
WEIGHTED = ["count", "total_weight", "effective_count", "mean", "minimum", "maximum", "m2",
            "population_variance", "population_stddev", "reliability_variance"]
HIGHER = ["count", "mean", "minimum", "maximum", "m2", "m3", "m4", "population_variance",
          "population_stddev", "population_skewness", "population_kurtosis",
          "population_excess_kurtosis", "adjusted_skewness", "adjusted_excess_kurtosis"]


def encode(rows):
    output = StringIO(newline="")
    csv.writer(output, lineterminator="\r\n", quoting=csv.QUOTE_ALL).writerows(rows)
    return output.getvalue().encode()


def dec(value):
    if isinstance(value, Fraction):
        return Decimal(value.numerator)/Decimal(value.denominator)
    return Decimal(value)


def reference(rows):
    # Reference the exact binary64 inputs produced by decimal conversion.
    selected = [(Fraction.from_float(float(value)), Fraction.from_float(float(weight)))
                for value, weight in rows if float(weight) > 0]
    n = len(selected)
    result = {}
    def put(profile, metric, value=None, status="ok"):
        result[profile, metric] = (None if value is None else dec(value), status)
    w = "weighted"
    h = "unweighted_positive"
    put(w, "count", n)
    put(w, "total_weight", sum((weight for _, weight in selected), Fraction()))
    put(h, "count", n)
    if not n:
        for name in WEIGHTED[2:]:
            put(w, name, status="insufficient" if name == "reliability_variance" else "empty")
        for name in HIGHER[1:]:
            put(h, name, status="insufficient" if name.startswith("adjusted_") else "empty")
        return result
    values = [value for value, _ in selected]
    total = sum(weight for _, weight in selected)
    squares = sum(weight*weight for _, weight in selected)
    mean = sum(value*weight for value, weight in selected)/total
    m2 = sum(weight*(value-mean)**2 for value, weight in selected)
    put(w, "effective_count", total*total/squares)
    put(w, "mean", mean)
    put(w, "minimum", min(values))
    put(w, "maximum", max(values))
    put(w, "m2", m2)
    put(w, "population_variance", m2/total)
    put(w, "population_stddev", dec(m2/total).sqrt())
    if n < 2:
        put(w, "reliability_variance", status="insufficient")
    else:
        put(w, "reliability_variance", m2/(total-squares/total))
    mean = sum(values)/n
    m2 = sum((value-mean)**2 for value in values)
    m3 = sum((value-mean)**3 for value in values)
    m4 = sum((value-mean)**4 for value in values)
    for name, value in [("mean", mean), ("minimum", min(values)), ("maximum", max(values)),
                        ("m2", m2), ("m3", m3), ("m4", m4),
                        ("population_variance", m2/n), ("population_stddev", dec(m2/n).sqrt())]:
        put(h, name, value)
    if not m2:
        for name in HIGHER[9:]:
            minimum = 3 if name == "adjusted_skewness" else 4 if name == "adjusted_excess_kurtosis" else 0
            put(h, name, status="insufficient" if n < minimum else "degenerate")
        return result
    skew = dec(n).sqrt()*dec(m3)/(dec(m2)*dec(m2).sqrt())
    kurt = dec(n*m4/(m2*m2))
    put(h, "population_skewness", skew)
    put(h, "population_kurtosis", kurt)
    put(h, "population_excess_kurtosis", kurt-3)
    if n < 3:
        put(h, "adjusted_skewness", status="insufficient")
    else:
        put(h, "adjusted_skewness", dec(n*(n-1)).sqrt()/dec(n-2)*skew)
    if n < 4:
        put(h, "adjusted_excess_kurtosis", status="insufficient")
    else:
        put(h, "adjusted_excess_kurtosis", dec(n-1)/dec((n-2)*(n-3))*((n+1)*(kurt-3)+6))
    return result


def verify(output, rows):
    with localcontext() as context:
        context.prec = 110
        expected = reference(rows)
        parsed = list(csv.reader(StringIO(output.decode(), newline=""), strict=True))
        assert parsed[0] == ["profile", "metric", "value", "status"], parsed[:1]
        assert output == encode(parsed), "output is not canonical quoted CRLF CSV"
        keys = [("weighted", name) for name in WEIGHTED]+[("unweighted_positive", name) for name in HIGHER]
        assert len(parsed) == 25 and [tuple(row[:2]) for row in parsed[1:]] == keys
        for profile, name, value, status in parsed[1:]:
            wanted, wanted_status = expected[profile, name]
            assert status == wanted_status, (profile, name, status, wanted_status)
            if status != "ok":
                assert value == "", (profile, name, value, status)
                continue
            actual = Decimal(value)
            assert actual.is_finite(), (profile, name, actual)
            if name in ("count", "total_weight", "minimum", "maximum"):
                assert float(actual) == float(wanted), (profile, name, actual, wanted)
                continue
            # The model computes exact central sums, independent of streaming
            # recurrences. Allow finite binary64 rounding; never NaN equivalence.
            tolerance = max(Decimal("1e-12"), Decimal.from_float(math.ulp(float(wanted)))*512)
            assert abs(actual-wanted) <= tolerance, (profile, name, actual, wanted, tolerance)


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"sample-moments-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"value,weight\n", *, rows=None, output=None, status=0,
            read_error=False, closed_reader=False):
        command = [self.executable, *arguments]
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=20, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            read_fd, write_fd = os.pipe()
            os.close(read_fd)
            try:
                result = subprocess.run(command, input=data, stdout=write_fd, stderr=subprocess.PIPE,
                                        timeout=20, check=False)
            finally:
                os.close(write_fd)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=20, check=False)
        prefix = self.directory/name
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".receipt").write_text(repr((command, result.returncode))+"\n")
        assert result.returncode == status, (name, result.returncode, result.stdout[:160], result.stderr)
        assert result.stderr == (ERROR if status else b""), (name, result.stderr)
        if rows is not None:
            verify(result.stdout, rows)
        else:
            assert result.stdout == (output or b""), (name, result.stdout[:160])
        self.count += 1

    def model(self, name, rows, data=None):
        if data is None:
            data = encode([("value", "weight"), *rows])
        self.run(name, data=data, rows=rows)


def model(r):
    cases = [
        ("empty", []), ("all-zero", [("1", "0"), ("99", "0")]),
        ("one", [("2.5", "3")]), ("two", [("1", "1"), ("4", "2")]),
        ("three", [("1", "1"), ("2", "1"), ("8", "1")]),
        ("constant-four", [("7", str(weight)) for weight in (1, 2, 4, 8)]),
        ("minimum-subnormal-weights", [("7", "5e-324")]*3),
        ("unit-five", [(str(value), "1") for value in (-4, -1, 0, 2, 8)]),
        ("unequal-five", [(str(value), str(weight)) for value, weight in [(-4, 1), (-1, 2), (0, 8), (2, 4), (8, 1)]]),
        ("scaled-weights", [(str(value), str(weight*8)) for value, weight in [(-4, 1), (-1, 2), (0, 8), (2, 4), (8, 1)]]),
        ("zero-outlier", [("10000", "0"), ("1", "1"), ("2", "2"), ("3", "1")]),
        ("zero-extreme", [("1e308", "0"), ("-1e308", "0")]),
        ("signed-zero", [("-0", "-0"), ("0", "1"), ("-0", "1")]),
        ("decimal-underflow-zero", [("1e-9999", "1"), ("1e308", "-1e-9999")]),
        ("asymmetric", [(str(value), "1") for value in (0, 0, 0, 1, 9)]),
        ("shifted", [(str(1000000000+value/4), str(weight)) for value, weight in [(0, 1), (1, 2), (2, 3), (4, 4)]]),
        ("maximum-rows", [("2.5", "1")]*4096),
    ]
    for name, rows in cases:
        r.model(name, rows)
    # Exact input-byte bound, both numeric fields <=128 digits, 4096 records.
    extra = 1048576-len(b"value,weight\n")-4096*4
    lines = []
    for _ in range(4096):
        left = min(extra, 127)
        extra -= left
        right = min(extra, 127)
        extra -= right
        lines.append(b"0"*(left+1)+b","+b"0"*(right+1)+b"\n")
    data = b"value,weight\n"+b"".join(lines)
    assert extra == 0 and len(data) == 1048576
    r.model("maximum-input", [("0", "0")]*4096, data=data)
    rng = random.Random(0x534D)
    for index in range(8):
        rows = [(str(rng.randrange(-32, 33)/4), str(rng.randrange(0, 17)/4)) for _ in range(rng.randrange(4, 33))]
        r.model(f"seeded-{index}", rows)


def rejection(r):
    cases = [
        ("empty-input", b""), ("missing-header", b"1,1\n"), ("wrong-header", b"weight,value\n"),
        ("header-case", b"Value,weight\n"), ("three-fields", b"value,weight,extra\n"),
        ("short-row", b"value,weight\n1\n"), ("extra-row-field", b"value,weight\n1,1,1\n"),
        ("unclosed-quote", b'value,weight\n"1,1'), ("trailing-quote", b'value,weight\n"1"x,1\n'),
        ("invalid-utf8", b"value,weight\n\xff,1\n"), ("nul", b"value,weight\n1,\x00\n"),
        ("tab", b'value,weight\n"1\t",1\n'), ("empty-value", b"value,weight\n,1\n"),
        ("empty-weight", b"value,weight\n1,\n"), ("value-space", b"value,weight\n 1,1\n"),
        ("weight-space", b"value,weight\n1,1 \n"), ("invalid-number", b"value,weight\n1a,1\n"),
        ("negative-weight", b"value,weight\n1,-1\n"), ("nonfinite-value", b"value,weight\nNaN,1\n"),
        ("nonfinite-zero-value", b"value,weight\nNaN,0\n"), ("infinite-weight", b"value,weight\n1,inf\n"),
        ("overflowing-decimal", b"value,weight\n1e9999,1\n"),
        ("field-over-cap", b"value,weight\n"+b"0"*129+b",0\n"),
        ("rows-over-cap", b"value,weight\n"+b"0,0\n"*4097),
        ("input-over-cap", b"x"*1048577),
        ("late-invalid-no-prefix", b"value,weight\n1,1\n2,1\n3,-1\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)
    for name, rows in [
        ("weighted-overflow", [("1e308", "1"), ("-1e308", "1")]),
        ("higher-fourth-overflow", [("0", "1"), ("1e100", "1")]),
        ("weight-total-overflow", [("0", "1e308"), ("0", "1e308")]),
        ("higher-fourth-underflow", [("0", "1"), ("1e-100", "1")]),
    ]:
        r.run(name, data=encode([("value", "weight"), *rows]), status=6)


def cli(r):
    for index, arguments in enumerate([["file.csv"], ["--unknown"], ["--count", "1"], ["--help", "--help"], ["-hh"], ["--help", "extra"]]):
        r.run(f"invalid-{index}", arguments, status=2)
    r.run("help", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)


def io(r):
    r.run("stdin-directory", read_error=True, status=3)
    r.run("closed-stdout", closed_reader=True, status=5)


def controls():
    assert len(HELP) == 286 and len(ERROR) == 33
    with localcontext() as context:
        context.prec = 110
        values = reference([("1", "1"), ("3", "3")])
        assert values["weighted", "mean"] == (Decimal("2.5"), "ok")
        assert values["unweighted_positive", "mean"] == (Decimal("2"), "ok")
        assert values["weighted", "effective_count"] == (Decimal("1.6"), "ok")
        assert values["weighted", "reliability_variance"] == (Decimal("2"), "ok")
        empty = reference([])
        assert empty["weighted", "total_weight"] == (Decimal(0), "ok")
        assert empty["unweighted_positive", "adjusted_skewness"] == (None, "insufficient")
    print("sample-moments CPU controls=7")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        print(f"sample-moments-{mode} cases={runner.count} evidence={runner.directory}")
