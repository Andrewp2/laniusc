"""Finite higher-moment checks using exact centered sums, not recurrences.

Inputs are binary64 values. Fraction computes each exact mean and centered
M2/M3/M4 directly; Decimal supplies square roots and normalization. This is
independent test code, never an implementation used by the language library.
"""
from __future__ import annotations

from decimal import Decimal, localcontext
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
SEED = 0x48344D2026
RECORD = 196
NAMES = ("mean", "minimum", "maximum", "m2", "m3", "m4", "population_variance",
         "sample_variance", "population_stddev", "sample_stddev", "population_skewness",
         "population_kurtosis", "population_excess_kurtosis", "adjusted_skewness",
         "adjusted_excess_kurtosis")


def decimal(value):
    if isinstance(value, F):
        return D(value.numerator) / D(value.denominator)
    return D.from_float(value)


def datasets():
    rows = [(), (7.0,), (-0.0, 0.0), (1.0, 3.0), (1.0, 2.0, 3.0),
            (1.0, 2.0, 3.0, 9.0), (-4.0, -2.0, -1.0, 0.0, 1.0, 2.0, 4.0),
            (-4.0, -2.0, -1.0, 0.0, 1.0, 2.0, 4.0 + 2.0**-30),
            (3.0, 3.0, 1.0, 9.0, 1.0, 1.0), (5.0,) * 11,
            tuple(1e12 + i * .125 for i in (0, 1, 7, 2, 1, 5, 9)),
            tuple(1e16 + i * 2 for i in (0, 1, 4, 7, 9)),
            tuple(-1e16 + i * 2 for i in (0, 1, 4, 7, 9)),
            (float.fromhex("0x1.fffffffffffffp+1023"),) * 9,
            (math.ulp(0.0), -math.ulp(0.0), 0.0),
            (math.ulp(0.0),) * 5]
    rows.append(tuple(1e-80 * i for i in (-4, -2, 0, 2, 4)))
    for scale in (1e-75, 1e-70, 1e70, 1e75):
        rows.append(tuple(scale * i for i in (-3, -1, 0, 1, 6)))
    for sign in (-1, 1):
        rows.append(tuple(sign * 2.0**250 + i * 2.0**210 for i in (-9, -2, -1, 0, 1, 4, 13)))
    rng = random.Random(SEED)
    for _ in range(28):
        n = rng.randrange(4, 97)
        center = rng.choice((0.0, 1e12, -1e12, 1e16, -1e16))
        step = rng.choice((.125, .5, 2.0, 7.0))
        rows.append(tuple(center + step * rng.randrange(-30, 31) for _ in range(n)))
    return rows


def cases():
    result = []
    for dataset, rows in enumerate(datasets()):
        for layout in range(2):
            for op in (0, 1, 4, 5, 6, 7):
                result.append((dataset, op, 0, layout, rows))
            for split in sorted({0, len(rows) // 2, len(rows)}):
                for op in (2, 3):
                    result.append((dataset, op, split, layout, rows))
    return result


@lru_cache(maxsize=None)
def invalid_state(rows):
    if not rows or min(rows) == max(rows):
        return 0
    spread = max(rows) - min(rows)
    # These bounds are far inside representable fourth moments for <=256
    # rows; exact arithmetic below handles underflow/overflow boundary cases.
    if 1e-70 <= spread <= 1e75:
        return 0
    exact = tuple(map(F, rows))
    mean = sum(exact, F(0)) / len(rows)
    fourth = sum(((value - mean)**4 for value in exact), F(0))
    try:
        rounded = float(fourth)
    except OverflowError:
        return 4
    return 13 if rounded <= 0 else 0


def stream(rows):
    state = ()
    for value in rows:
        code = invalid_state(state + (value,))
        if code:
            return code, -1, state
        state += (value,)
    return 0, -1, state


def operation(case):
    dataset, op, split, layout, rows = case
    if op in (0, 5, 6):
        code, index, state = stream(rows)
        if code or op != 6:
            return code, index, state
        code = invalid_state(state * 2)
        return code, -1, state if code else state * 2
    if op in (1, 7):
        code, index, state = stream(rows)
        return (code, len(state), ()) if code else (0, -1, state)
    if op in (2, 3):
        code, index, left = stream(rows[:split])
        if code:
            return code, index, left
        code, index, right = stream(rows[split:])
        if code:
            return code, index, left
        code = invalid_state(left + right)
        return code, -1, ((left if op == 2 else right) if code else left + right)
    assert op == 4
    groups = [(value,) for value in rows]
    while len(groups) > 1:
        next_groups = []
        for index in range(0, len(groups), 2):
            left = groups[index]
            if index + 1 < len(groups):
                code = invalid_state(left + groups[index + 1])
                if code:
                    next_groups.append(left)
                    return code, -1, next_groups[0]
                left += groups[index + 1]
            next_groups.append(left)
        groups = next_groups
    return 0, -1, groups[0] if groups else ()


@lru_cache(maxsize=None)
def reference(rows):
    n = len(rows)
    status = [0] * 15
    values = [D(0)] * 15
    if not n:
        status = [1] * 15
        for i in (7, 9, 13, 14):
            status[i] = 2
        return status, values, [F(0)] * 3
    exact = tuple(map(F, rows))
    mean = sum(exact, F(0)) / n
    centered = tuple(value - mean for value in exact)
    moments = tuple(sum((value**power for value in centered), F(0)) for power in (2, 3, 4))
    scales = [sum((abs(value)**power for value in centered), F(0)) for power in (2, 3, 4)]
    m2, m3, m4 = moments
    values[:8] = [decimal(mean), D.from_float(min(rows)), D.from_float(max(rows)),
                  decimal(m2), decimal(m3), decimal(m4), decimal(m2 / n), D(0)]
    if n >= 2:
        values[7] = decimal(m2 / (n - 1))
    else:
        status[7] = status[9] = 2
    # The documented finite binary64 profile permits raw-moment underflow.
    # A stored zero M2 has zero variance/stddev and degenerate normalization.
    if float(m2) == 0:
        values[6] = values[7] = values[8] = values[9] = D(0)
        for i in (10, 11, 12, 13, 14):
            status[i] = 12
    else:
        values[8] = decimal(m2 / n).sqrt()
        if n >= 2:
            values[9] = decimal(m2 / (n - 1)).sqrt()
        skew = D(n).sqrt() * decimal(m3) / (decimal(m2) * decimal(m2).sqrt())
        kurtosis = D(n) * decimal(m4) / (decimal(m2) * decimal(m2))
        excess = kurtosis - 3
        values[10:13] = [skew, kurtosis, excess]
        if n >= 3:
            values[13] = (D(n) * D(n - 1)).sqrt() / D(n - 2) * skew
        if n >= 4:
            values[14] = D(n - 1) / (D(n - 2) * D(n - 3)) * (D(n + 1) * excess + 6)
    if n < 3:
        status[13] = 2
    if n < 4:
        status[14] = 2
    return status, values, scales


def packet(values):
    output = bytearray()
    for dataset, op, split, layout, rows in values:
        output += struct.pack("<4i", op, len(rows), split, layout)
        output += struct.pack("<" + "d" * len(rows), *rows)
    return output


def verify(output, values):
    assert len(output) == RECORD * len(values), (len(output), RECORD * len(values))
    for case, (dataset, op, split, layout, source) in enumerate(values):
        expected_update, expected_index, rows = operation(values[case])
        status, failure_index, count = struct.unpack_from("<iiQ", output, case * RECORD)
        label = (f"seed={SEED:#x}", case, dataset, op, split, layout, source)
        assert (status, failure_index, count) == (expected_update, expected_index, len(rows)), (label, status, failure_index, count, expected_update, expected_index, len(rows))
        expected_status, expected, scales = reference(rows)
        for index, name in enumerate(NAMES):
            code, got = struct.unpack_from("<id", output, case * RECORD + 16 + index * 12)
            assert code == expected_status[index], (label, name, code, expected_status[index])
            if code:
                continue
            want = float(expected[index])
            assert math.isfinite(got) and math.isfinite(want), (label, name, got, want)
            if index in (1, 2):
                tolerance = 0.0
            elif index == 0:
                spread = max(source, default=0) - min(source, default=0)
                tolerance = max(2 * math.ulp(want), 4e-15 * spread)
            elif index in (3, 4, 5):
                # Near-zero odd moments are cancellation-conditioned. Budget
                # error against the exact sum of absolute centered powers.
                tolerance = max(4e-12 * float(scales[index - 3]), 64 * math.ulp(0.0))
            elif index in (6, 7, 8, 9):
                tolerance = max(6e-12 * abs(want), 64 * math.ulp(0.0))
            else:
                tolerance = 8e-11 * max(1.0, abs(want))
                if index in (11, 12, 14) and scales[2]:
                    # Retained positive subnormal M4 has an absolute rounding
                    # floor; its normalized ratios cannot promise uniform
                    # relative accuracy. Keep that finite profile explicit.
                    tolerance += float(decimal(F(math.ulp(0.0)) * 128 / scales[2])) * max(1.0, abs(want))
            assert abs(got - want) <= tolerance, (label, name, got, want, tolerance)


def controls():
    values = cases()
    output = bytearray()
    with localcontext() as context:
        context.prec = 110
        for dataset, op, split, layout, source in values:
            update, failure_index, rows = operation((dataset, op, split, layout, source))
            statuses, expected, scales = reference(rows)
            output += struct.pack("<iiQ", update, failure_index, len(rows))
            output += b"".join(struct.pack("<id", code, 0.0 if code else float(value))
                               for code, value in zip(statuses, expected))
        verify(output, values)
        candidate = next(i for i, value in enumerate(values) if len(value[4]) >= 4)
        offset = candidate * RECORD + 20 + 11 * 12
        original, = struct.unpack_from("<d", output, offset)
        struct.pack_into("<d", output, offset, original + 1)
        try:
            verify(output, values)
        except AssertionError:
            pass
        else:
            raise AssertionError("oracle ignored a corrupted population kurtosis")
    print(f"higher-statistics CPU controls={len(values)} synthetic-records corruption=rejected")


def main():
    if sys.argv[1:] == ["controls"]:
        controls()
        return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    with localcontext() as context:
        context.prec = 110
        verify(result.stdout, values)
    print(f"higher-statistics cases={len(values)} datasets={len(datasets())} storage_forms=2 modes=8 seed={SEED:#x}")


if __name__ == "__main__":
    main()
