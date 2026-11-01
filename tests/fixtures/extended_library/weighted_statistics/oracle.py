#!/usr/bin/env python3
"""Independent exact weighted sums and Decimal-derived query references.

No streaming or merge recurrence is reproduced. A case's answer is computed
from all its positive-weight observations as exact rational binary64 values.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from decimal import Decimal, getcontext
from fractions import Fraction
from functools import lru_cache
import math
from pathlib import Path
import random
import struct
import subprocess
import sys

F = Fraction
D = Decimal
getcontext().prec = 220
SEED = 0x57E12026
MIN = math.ulp(0.0)
MAX = sys.float_info.max
RESPONSE = struct.Struct("<" + "Q" * 25)


def decimal(value):
    if isinstance(value, F):
        return D(value.numerator) / D(value.denominator)
    return D(value)


def finite_float(value):
    try:
        return float(value)
    except OverflowError:
        return math.inf if value >= 0 else -math.inf


@dataclass(frozen=True)
class Case:
    op: int
    rows: tuple[tuple[float, float, float], ...]
    tree: object = None
    label: str = ""


@lru_cache(None)
def trees(start, count):
    if count == 0:
        return (None,)
    if count == 1:
        return (start,)
    return tuple(
        (left, right)
        for split in range(1, count)
        for left in trees(start, split)
        for right in trees(start + split, count - split)
    )


def balanced(start, count):
    if count <= 1:
        return start if count else None
    half = count // 2
    return balanced(start, half), balanced(start + half, count - half)


def folded(start, count, right=False):
    if count <= 1:
        return start if count else None
    if right:
        return start, folded(start + 1, count - 1, right=True)
    return folded(start, count - 1), start + count - 1


def instructions(tree, leaves):
    result = []

    def visit(node):
        if isinstance(node, int):
            return node
        a = visit(node[0])
        b = visit(node[1])
        result.append((a, b))
        return leaves + len(result) - 1

    if tree is not None:
        visit(tree)
    return result


def cases():
    result = []

    def add(rows, label, all_trees=False):
        rows = tuple(tuple(map(float, row)) for row in rows)
        assert len(rows) <= 32
        for op in (0, 2, 4, 5):
            result.append(Case(op, rows, label=label))
        choices = trees(0, len(rows)) if all_trees else {
            balanced(0, len(rows)), folded(0, len(rows)), folded(0, len(rows), True)
        }
        for tree in choices:
            for op in (1, 3):
                result.append(Case(op, rows, tree, label))

    add([], "empty")
    add([(99, -99, 0), (7, 8, -0.0)], "all validated zeros")
    add([(7, 11, 2)], "singleton")
    base = [(1, 5, 1), (3, 9, 3), (99, -99, 0)]
    add(base, "reliability differs from frequency")
    add([(x, y, w * 8) for x, y, w in base], "weight scaling")
    add([(1, 5, 1), (3, 9, 1), (3, 9, 1), (3, 9, 1)], "duplicated frequency population")
    for count in range(1, 7):
        data = [(i * 0.5 - 1, i * i * 0.25 + 2, [1, 2, 0, 0.5, 4, 1][i]) for i in range(count)]
        add(data, f"every ordered binary merge tree n={count}", all_trees=True)
    for count in (2, 3, 4):
        add([(7, 11, MIN)] * count, f"minimum-subnormal equal mass n={count}")
    for weight in (0.25, 1, 7, 1024):
        add([(x, 3 * x - 2, weight) for x in (-4, -1, 0, 3, 8)], f"equal weights {weight}")
    for rows, label in [
        ([(0, 1, 1e300), (1, 3, 1e-300)], "600 exponent weight ratio"),
        ([(-1e300, -1e150, 1e-300), (1e300, 1e150, 1e300)], "tiny weight first opposite large centers"),
        ([(-MAX, -1e150, 1e-310), (MAX, 1e150, 1e308)], "half-delta opposite maximum centers"),
        ([(-1e-150, 2e-150, 1), (1e-150, -2e-150, 3)], "tiny representable moments"),
        ([(3, 1, 1), (3, 2, 2)], "constant x"),
        ([(1, 9, 1), (2, 9, 3)], "constant y"),
    ]:
        add(rows, label)
        add(list(reversed(rows)), label + " reversed")
    rng = random.Random(SEED)
    for serial in range(60):
        count = rng.randrange(2, 33)
        center = rng.choice([0.0, 1e12, -1e12, 1e16, -1e16])
        step = rng.choice([0.125, 0.5, 2.0, 16.0])
        rows = []
        for index in range(count):
            x = center + rng.randrange(-24, 25) * step
            y = -2.5 * x + 3 + (index % 3) * 0.125
            weight = rng.choice([0.0, 0.0625, 0.125, 0.5, 1.0, 2.0, 16.0])
            rows.append((x, y, weight))
        add(rows, f"dyadic seed={SEED:#x} sample={serial}")
    # Only stream/batch methods receive invalid input; valid tree cases test
    # every public merge instruction without conflating staging-error policy.
    for row, label in [
        ((math.nan, 1, -1), "observation precedes invalid weight"),
        ((1, math.inf, 0), "paired coordinate validated at zero weight"),
        ((math.inf, 1, 0), "nonfinite x at zero weight"),
        ((1, 2, -1), "negative mass"),
        ((1, 2, math.nan), "NaN mass"),
        ((1, 2, math.inf), "infinite mass"),
    ]:
        for op in (0, 2, 4, 5):
            result.append(Case(op, ((1.0, 5.0, 1.0), (3.0, 9.0, 3.0), row), label=label))
    for op in (0, 2, 4, 5):
        result.append(Case(op, ((1.0, 2.0, 1e308), (2.0, 3.0, 1e308)), label="total mass overflow"))
        result.append(Case(op, ((MAX, 1.0, 1.0), (-MAX, 2.0, 1.0)), label="stored second moment overflow"))
    return result


def exact(rows):
    selected = [(F(x), F(y), F(w)) for x, y, w in rows if w > 0]
    if not selected:
        return dict(n=0, W=F(0))
    W = sum((w for _, _, w in selected), F(0))
    mx = sum((w * x for x, _, w in selected), F(0)) / W
    my = sum((w * y for _, y, w in selected), F(0)) / W
    xx = sum((w * (x - mx) ** 2 for x, _, w in selected), F(0))
    yy = sum((w * (y - my) ** 2 for _, y, w in selected), F(0))
    cross = sum((w * (x - mx) * (y - my) for x, y, w in selected), F(0))
    Q = sum((w * w for _, _, w in selected), F(0))
    # Pair mass is independent of the implementation's streaming denominator.
    pair = sum((a[2] * b[2] for i, a in enumerate(selected) for b in selected[i + 1:]), F(0))
    return dict(n=len(selected), W=W, mx=mx, my=my, xx=xx, yy=yy, C=cross,
                D=2 * pair / W, N=W * W / Q,
                low=min(x for x, _, _ in selected), high=max(x for x, _, _ in selected))


def accepted(case):
    prefix = []
    for index, row in enumerate(case.rows):
        x, y, weight = row
        error = 0
        if not math.isfinite(x) or (case.op in (2, 3, 5) and not math.isfinite(y)):
            error = 3
        elif not math.isfinite(weight) or weight < 0:
            error = 4
        elif weight > 0:
            reference = exact(prefix + [row])
            if not math.isfinite(finite_float(reference["W"])) or not math.isfinite(finite_float(reference["xx"])):
                error = 5
            if case.op in (2, 3, 5) and (not math.isfinite(finite_float(reference["yy"])) or not math.isfinite(finite_float(reference["C"]))):
                error = 5
        if error:
            return error, index if case.op in (4, 5) else -1, [] if case.op in (4, 5) else prefix
        prefix.append(row)
    return 0, -1, prefix


def reference_metrics(case, rows):
    s = exact(rows)
    if case.op in (0, 1, 4):
        if not s["n"]:
            return s, [(0, 0), (1, 0), (1, 0), (1, 0), (1, 0), (1, 0), (2, 0), (1, 0), (2, 0), (1, 0), (1, 0)]
        metrics = [(0, s["W"]), (0, s["mx"]), (0, s["low"]), (0, s["high"]), (0, s["xx"]), (0, s["xx"] / s["W"])]
        metrics.append((0, s["xx"] / s["D"]) if s["D"] else (2, 0))
        metrics.append((0, (decimal(s["xx"]) / decimal(s["W"])).sqrt()))
        metrics.append((0, (decimal(s["xx"]) / decimal(s["D"])).sqrt()) if s["D"] else (2, 0))
        metrics.extend([(0, s["N"]), (0, s["D"])])
        return s, metrics
    if not s["n"]:
        return s, [(0, 0), (1, 0), (1, 0), (1, 0), (2, 0), (2, 0), (2, 0), (2, 0), (2, 0), (0, 0), (0, 0)]
    metrics = [(0, s["W"]), (0, s["mx"]), (0, s["my"]), (0, s["C"] / s["W"])]
    metrics.append((0, s["C"] / s["D"]) if s["D"] else (2, 0))
    corr_error = 2 if s["n"] < 2 else 8 if not s["xx"] or not s["yy"] else 0
    corr = decimal(s["C"]) / (decimal(s["xx"]) * decimal(s["yy"])).sqrt() if not corr_error else D(0)
    metrics.append((corr_error, corr))
    fit_error = 2 if s["n"] < 2 else 8 if not s["xx"] else 0
    if fit_error:
        metrics.extend([(fit_error, 0)] * 3)
    else:
        slope = s["C"] / s["xx"]
        intercept = s["my"] - slope * s["mx"]
        metrics.extend([(0, slope), (0, intercept), (0, corr * corr if s["yy"] else 1)])
    return s, metrics + [(0, 0), (0, 0)]


def check(case, status, index, count, metrics, label):
    wanted_status, wanted_index, rows = accepted(case)
    assert (status, index) == (wanted_status, wanted_index), (label, "operation", status, index, wanted_status, wanted_index)
    s, expected = reference_metrics(case, rows)
    assert count == s["n"], (label, "positive count", count, s["n"])
    for metric, ((actual_code, actual), (wanted_code, wanted)) in enumerate(zip(metrics, expected)):
        target = finite_float(wanted)
        if not wanted_code and not math.isfinite(target):
            wanted_code = 5
        if s["n"] and s["D"] and s["D"] < F(MIN) * 16 and metric in ((6, 8) if case.op in (0, 1, 4) else (4,)):
            # The documented binary64 correction denominator may round to zero
            # in this subnormal boundary profile. It never changes the exact
            # effective-count reference, which must still equal n here.
            if actual_code == 2:
                continue
        assert actual_code == wanted_code, (label, "query", metric, actual_code, wanted_code, target)
        if wanted_code:
            continue
        assert math.isfinite(actual), (label, "nonfinite query", metric, actual)
        absolute = 8 * MIN
        paired = case.op in (2, 3, 5)
        if metric == 1 or (paired and metric == 2):
            coordinates = [abs(row[1 if paired and metric == 2 else 0]) for row in rows if row[2] > 0]
            absolute = max(absolute, 8 * sys.float_info.epsilon * max(coordinates, default=0))
        if paired and metric == 5:
            absolute = 2e-12
        if paired and metric == 6:
            absolute = max(absolute, 2e-12)
        if paired and metric == 7 and s["xx"]:
            scale = max(abs(decimal(s["my"])), abs(decimal(s["C"] / s["xx"] * s["mx"])), D(1))
            absolute = max(absolute, finite_float(scale * D("4e-15")))
        if paired and metric in (3, 4) and s["xx"] and s["yy"]:
            divisor = s["W"] if metric == 3 else s["D"]
            if divisor:
                scale = (decimal(s["xx"]) * decimal(s["yy"])).sqrt() / decimal(divisor)
                absolute = max(absolute, finite_float(scale * D("4e-12")))
        tolerance = max(absolute, 2e-11 * abs(target), 8 * math.ulp(target))
        assert abs(actual - target) <= tolerance, (label, "value", metric, actual, target, tolerance)


def packet(all_cases):
    data = bytearray()
    expanded = []
    for serial, case in enumerate(all_cases):
        operations = instructions(case.tree, len(case.rows)) if case.op in (1, 3) else []
        for layout in (0, 1):
            data += struct.pack("<IIII", case.op, len(case.rows), len(operations), layout)
            for row in case.rows:
                data += struct.pack("<ddd", *row)
            for operation in operations:
                data += struct.pack("<II", *operation)
            expanded.append((serial, layout, case))
    return data, expanded


def self_test():
    base = Case(0, ((1.0, 5.0, 1.0), (3.0, 9.0, 3.0)), label="reference control")
    state, reference = reference_metrics(base, base.rows)
    assert state["W"] == 4 and state["mx"] == F(5, 2) and state["xx"] == 3
    assert state["D"] == F(3, 2) and state["N"] == F(8, 5)
    actual = [(kind, finite_float(value)) for kind, value in reference]
    check(base, 0, -1, 2, actual, "reference control")
    rejected = 0
    for changed, value in [(6, 1.0), (9, 2.0), (10, 0.0)]:
        mutation = list(actual)
        mutation[changed] = (0, value)
        try:
            check(base, 0, -1, 2, mutation, "deliberately incorrect weighted answer")
        except AssertionError:
            rejected += 1
    subnormal = Case(0, ((7.0, 11.0, MIN),) * 3)
    _, reference = reference_metrics(subnormal, subnormal.rows)
    mutation = [(kind, finite_float(value)) for kind, value in reference]
    mutation[9] = (0, 2.25)  # Incorrect rounded-sqrt(Q) normalization.
    try:
        check(subnormal, 0, -1, 3, mutation, "subnormal effective-count bug")
    except AssertionError:
        rejected += 1
    invalid = Case(4, ((1.0, 5.0, 1.0), (math.nan, 2.0, -1.0)))
    assert accepted(invalid) == (3, 1, [])
    assert rejected == 4
    print("weighted-statistics reference controls=5 wrong-answer-rejections=4")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path, nargs="?")
    parser.add_argument("--input-copy", type=Path)
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_test:
        self_test()
        return
    if arguments.executable is None:
        parser.error("an executable or --self-test is required")
    data, expanded = packet(cases())
    if arguments.input_copy:
        arguments.input_copy.write_bytes(data)
    result = subprocess.run([str(arguments.executable.resolve())], input=data, capture_output=True, timeout=30)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr[:2000], len(result.stdout))
    assert len(result.stdout) == RESPONSE.size * len(expanded), (len(result.stdout), RESPONSE.size, len(expanded))
    for record, (serial, layout, case) in enumerate(expanded):
        fields = RESPONSE.unpack_from(result.stdout, record * RESPONSE.size)
        status, index, count = fields[:3]
        index = index - (1 << 64) if index & (1 << 63) else index
        metrics = [(fields[3 + 2 * i], struct.unpack("<d", struct.pack("<Q", fields[4 + 2 * i]))[0]) for i in range(11)]
        label = (f"seed={SEED:#x}", serial, layout, case.op, case.label, case.rows, case.tree)
        check(case, status, index, count, metrics, label)
    print(f"weighted-statistics cases={len(expanded)} layouts=2 exact=Fraction derived=Decimal seed={SEED:#x}")


if __name__ == "__main__":
    main()
