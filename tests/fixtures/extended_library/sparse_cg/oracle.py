"""Independent CG acceptance: exact Gaussian systems and fresh residuals.

The oracle does not reproduce CG to predict iterates. It solves small dense
systems with Fraction Gaussian elimination, recomputes b-Ax independently in
ascending-column IEEE order, checks robust norms and stopping, and checks
solution error against a diagonal-dominance residual bound. A separate scalar
control demonstrates one deterministic recursive/fresh disagreement.
"""
from __future__ import annotations
from dataclasses import dataclass, replace
from fractions import Fraction
from functools import lru_cache
import math
from pathlib import Path
import random
import struct
import subprocess
import sys

SEED = 0xC6A20261028
MASK = (1 << 64) - 1
MIN = math.ulp(0.0)
HUGE = sys.float_info.max
F = Fraction


def bits(value): return struct.unpack("<Q", struct.pack("<d", value))[0]
def floating(value): return struct.unpack("<d", struct.pack("<Q", value))[0]


@dataclass(frozen=True)
class Case:
    n: int
    a: tuple
    b: tuple
    initial: tuple
    jacobi: int = 1
    cap: int = 40
    rtol: float = 1e-10
    atol: float = 0.0
    layout: int = 0
    error: tuple | None = None  # kind,wrappedSparse,row,entry,attempt
    exact_steps: int | None = None
    exact_restarts: int | None = None
    must_converge: bool = False
    reference: bool = True
    label: str = ""


def case(n, a=(), b=(), initial=(), **keywords):
    return Case(n, tuple(sorted(dict(a).items())), tuple(b), tuple(initial), **keywords)


def csr(value):
    items = sorted(dict(value.a).items())
    offsets = [0]
    for row in range(value.n):
        offsets.append(offsets[-1] + sum(r == row for (r, c), number in items))
    return offsets, [c for (r, c), number in items], [number for key, number in items]


def product(n, a, x):
    matrix = dict(a)
    result = []
    for row in range(n):
        total = 0.0
        for col in range(n):
            if (row, col) in matrix:
                term = matrix[row, col] * x[col]
                assert math.isfinite(term)
                total += term
                assert math.isfinite(total)
        result.append(total)
    return result


def residual(value, x):
    ax = product(value.n, value.a, x)
    answer = [right - left for right, left in zip(value.b, ax)]
    assert all(math.isfinite(item) for item in answer)
    return answer


def norm(values):
    if len(values) == 1:
        return abs(values[0])
    return math.hypot(*values)


def converged(residual_norm, rhs_norm, value):
    return residual_norm <= value.atol or (value.rtol > 0 and rhs_norm > 0 and residual_norm / rhs_norm <= value.rtol)


@lru_cache(maxsize=None)
def exact_solution(n, a, b):
    matrix = dict(a)
    augmented = [[F(matrix.get((r, c), 0.0)) for c in range(n)] + [F(b[r])] for r in range(n)]
    for column in range(n):
        pivot = next(row for row in range(column, n) if augmented[row][column])
        augmented[column], augmented[pivot] = augmented[pivot], augmented[column]
        divisor = augmented[column][column]
        augmented[column] = [item / divisor for item in augmented[column]]
        for row in range(n):
            if row == column:
                continue
            factor = augmented[row][column]
            augmented[row] = [left - factor * right for left, right in zip(augmented[row], augmented[column])]
    solution = tuple(row[-1] for row in augmented)
    margins = [F(matrix.get((row, row), 0.0)) - sum((abs(F(matrix.get((row, col), 0.0)))
               for col in range(n) if col != row), F(0)) for row in range(n)]
    return solution, min(margins) if margins else F(1)


def check_norm(actual, want, values, label):
    assert math.isfinite(actual) and actual >= 0, (label, actual)
    if want == 0:
        assert bits(actual) == bits(0.0), (label, actual, want)
        return
    assert actual > 0, (label, "lost nonzero norm", actual, want)
    tolerance = 0.0 if len(values) <= 1 else max(8 * math.ulp(want), 4e-15 * want)
    assert abs(actual - want) <= tolerance, (label, actual, want, tolerance)


def check_success(value, header, x):
    status, wrapped, row, entry, attempted, stop, iterations, restarts, count, rhs_bits, residual_bits = header
    label = (value.label, value.jacobi, value.cap, value.layout)
    assert (status, wrapped, row, entry, attempted, count) == (0, 0, MASK, MASK, MASK, value.n), (label, header)
    assert stop in (0, 1) and 0 <= iterations <= value.cap and 0 <= restarts <= iterations, (label, header)
    assert len(x) == value.n and all(math.isfinite(item) for item in x), (label, x)
    actual_rhs, actual_residual = floating(rhs_bits), floating(residual_bits)
    fresh = residual(value, x)
    rhs_norm, fresh_norm = norm(value.b), norm(fresh)
    check_norm(actual_rhs, rhs_norm, value.b, (label, "rhs norm"))
    check_norm(actual_residual, fresh_norm, fresh, (label, "fresh residual norm"))
    assert (stop == 0) == converged(actual_residual, actual_rhs, value), (label, header, "published stop")
    assert (stop == 0) == converged(fresh_norm, rhs_norm, value), (label, header, "independent fresh stop")
    initial_fresh = residual(value, value.initial)
    if converged(norm(initial_fresh), rhs_norm, value):
        assert iterations == 0 and restarts == 0, (label, "already-converged initial guess was advanced", header)
    if stop == 1:
        assert iterations == value.cap, (label, "early iteration-limit publication", header)
    if value.must_converge:
        assert stop == 0, (label, "well-conditioned manufactured system did not converge", header)
    if value.exact_steps is not None:
        assert iterations == value.exact_steps, (label, iterations, value.exact_steps)
    if value.exact_restarts is not None:
        assert restarts == value.exact_restarts, (label, restarts, value.exact_restarts)
    if iterations == 0:
        assert list(map(bits, x)) == list(map(bits, value.initial)), (label, "zero-step iterate changed")
    if value.label == "recursive-fresh-refusal":
        assert stop == 1 and x == [0.0] and actual_residual == 1.0, (label, header, x)
    if value.reference and stop == 0 and value.n:
        reference, margin = exact_solution(value.n, value.a, value.b)
        assert margin > 0, (label, "reference family must be strictly diagonally dominant")
        matrix = dict(value.a)
        # Fresh IEEE products have finite rounding. Bound the exact residual's
        # difference from those products before applying the inverse infinity
        # bound 1/min(diagonal minus off-diagonal absolute row sum).
        rounding = F(0)
        for r in range(value.n):
            magnitude = abs(F(value.b[r])) + sum((abs(F(matrix.get((r, c), 0.0)) * F(x[c])) for c in range(value.n)), F(0))
            rounding = max(rounding, F(64) * F(sys.float_info.epsilon) * magnitude + F(16) * F(MIN))
        threshold = max(F(value.atol), F(value.rtol) * F(rhs_norm))
        bound = (threshold + rounding) / margin
        error = max((abs(F(got) - wanted) for got, wanted in zip(x, reference)), default=F(0))
        assert error <= bound, (label, "independent Gaussian solution error", float(error), float(bound))


def cases():
    bases = []
    rng = random.Random(SEED)
    for number in range(40):
        n = rng.randrange(1, 9)
        matrix = {}
        scale = 2.0 ** rng.randrange(-16, 17)
        for row in range(n):
            for col in range(row + 1, n):
                if rng.randrange(3):
                    matrix[row, col] = matrix[col, row] = scale * rng.randrange(-4, 5) / 4
        for row in range(n):
            matrix[row, row] = sum(abs(matrix.get((row, col), 0.0)) for col in range(n) if col != row) + scale * rng.choice((.5, 1., 2.))
        truth = [rng.randrange(-6, 7) / 4 for _ in range(n)]
        if not any(truth): truth[0] = 1.
        rhs = product(n, tuple(sorted(matrix.items())), truth)
        for jacobi in range(2):
            for guess_id, guess in enumerate(([0.0] * n, truth, [item + (1e-12 if index % 2 else -1e-12) for index, item in enumerate(truth)])):
                for cap in sorted({0, 1, n, 4 * n + 8}):
                    bases.append(case(n, matrix, rhs, guess, jacobi=jacobi, cap=cap,
                                      exact_steps=0 if guess_id == 1 else None,
                                      exact_restarts=0 if guess_id == 1 or cap == 0 else None,
                                      must_converge=guess_id == 1 or cap == 4 * n + 8,
                                      label=f"manufactured-{number}-guess{guess_id}"))
    for jacobi in range(2):
        bases += [
            case(0, jacobi=jacobi, cap=0, must_converge=True, exact_steps=0, exact_restarts=0, label="empty-zero-cap"),
            case(0, jacobi=jacobi, cap=5, must_converge=True, exact_steps=0, exact_restarts=0, label="empty"),
            case(2, {(0, 0): 2., (0, 1): -0., (1, 1): 4.}, (0., 0.), (0., -0.), jacobi=jacobi, cap=0, must_converge=True, exact_steps=0, exact_restarts=0, label="zero-rhs-zero-guess"),
            case(2, {(0, 0): 2., (1, 1): 4.}, (0., 0.), (1., -1.), jacobi=jacobi, cap=8, atol=1e-12, must_converge=True, label="zero-rhs-nonzero-guess"),
            case(1, {(0, 0): 2.}, (4.,), (0.,), jacobi=jacobi, cap=1, must_converge=True, exact_steps=1, exact_restarts=0, label="last-step-convergence"),
            case(2, {(0, 0): 1., (0, 1): 2., (1, 0): 2., (1, 1): 1.}, (1., -1.), (0., 0.), jacobi=jacobi, cap=3, error=(10, 0, -1, -1, 0), reference=False, label="positive-diagonal-indefinite"),
            case(2, {(0, 0): 1., (0, 1): 1., (1, 0): 1., (1, 1): 1.}, (1., -1.), (0., 0.), jacobi=jacobi, cap=3, error=(11, 0, -1, -1, 0), reference=False, label="zero-curvature"),
            case(2, {(0, 0): 2., (0, 1): 1., (1, 1): 2.}, (0., 0.), (0., 0.), jacobi=jacobi, cap=0, error=(8, 0, 0, 1, -1), reference=False, label="missing-symmetric-entry"),
            case(2, {(0, 0): 2., (0, 1): 1., (1, 0): 2., (1, 1): 2.}, (0., 0.), (0., 0.), jacobi=jacobi, cap=0, error=(8, 0, 0, 1, -1), reference=False, label="unequal-symmetric-entry"),
            case(1, {(0, 0): 1.}, (float("nan"),), (0.,), jacobi=jacobi, cap=0, error=(7, 0, -1, 0, -1), reference=False, label="nonfinite-rhs"),
            case(1, {(0, 0): 1.}, (1.,), (float("inf"),), jacobi=jacobi, cap=0, error=(7, 0, -1, 0, -1), reference=False, label="nonfinite-initial"),
            case(1, {(0, 0): HUGE}, (1.,), (2.,), jacobi=jacobi, cap=0, error=(1, 11, 0, 0, -1), reference=False, label="initial-product-overflow"),
            case(2, {(0, 0): 1., (1, 1): 1.}, (HUGE, HUGE), (0., 0.), jacobi=jacobi, cap=0, error=(12, 0, -1, 1, -1), reference=False, label="rhs-norm-overflow"),
        ]
    bases += [
        case(1, {(0, 0): -1.}, (1.,), (0.,), jacobi=0, cap=1, error=(10, 0, -1, -1, 0), reference=False, label="negative-curvature"),
        case(1, {}, (1.,), (0.,), jacobi=0, cap=1, error=(11, 0, -1, -1, 0), reference=False, label="breakdown-zero-operator"),
        case(1, {}, (0.,), (0.,), jacobi=1, cap=0, error=(9, 0, 0, -1, -1), reference=False, label="missing-jacobi-diagonal"),
        case(1, {(0, 0): 0.}, (0.,), (0.,), jacobi=1, cap=0, error=(9, 0, 0, 0, -1), reference=False, label="zero-jacobi-diagonal"),
        case(1, {(0, 0): 1.}, (MIN,), (0.,), jacobi=0, cap=1, rtol=0., error=(11, 0, -1, -1, 0), reference=False, label="rho-underflow"),
        case(1, {(0, 0): 1.}, (HUGE,), (0.,), jacobi=0, cap=1, error=(12, 0, -1, -1, 0), reference=False, label="rho-overflow"),
        case(1, {(0, 0): MIN}, (MIN,), (0.,), jacobi=1, cap=1, rtol=0., must_converge=True, exact_steps=1, exact_restarts=0, label="jacobi-division-no-inverse"),
        case(1, {(0, 0): 1e308}, (1.,), (1.,), jacobi=1, cap=1, exact_steps=1, exact_restarts=0, label="recursive-fresh-refusal"),
        case(1, {(0, 0): 1e308}, (1.,), (1.,), jacobi=1, cap=2, must_converge=True, exact_steps=2, exact_restarts=1, label="recursive-fresh-restart"),
    ]
    return [replace(value, layout=layout) for value in bases for layout in range(2)]


def packet(values):
    output = bytearray()
    for value in values:
        offsets, columns, stored = csr(value)
        output += struct.pack("<8Q", value.n, len(stored), value.layout, value.jacobi, value.cap, 0, bits(value.rtol), bits(value.atol))
        output += struct.pack("<" + "i" * len(offsets), *offsets)
        output += struct.pack("<" + "i" * len(columns), *columns)
        for items in (stored, value.b, value.initial):
            output += struct.pack("<" + "d" * len(items), *items)
    return output


def verify(actual, values):
    offset = 0
    for index, value in enumerate(values):
        assert offset + 88 <= len(actual), (index, value.label, "truncated header")
        header = struct.unpack_from("<11Q", actual, offset)
        offset += 88
        count = header[8]
        assert count <= 8 and offset + count * 8 <= len(actual), (index, value.label, count)
        x = list(struct.unpack_from("<" + "d" * count, actual, offset))
        offset += count * 8
        if value.error:
            kind, wrapped, row, entry, attempt = value.error
            want = (kind, wrapped, row & MASK, entry & MASK, attempt & MASK, 2, 0, 0, 0, 0, 0)
            assert header == want, (f"seed={SEED:#x}", index, value.label, value.layout, header, want)
        else:
            check_success(value, header, x)
    assert offset == len(actual), (offset, len(actual), "extra output")


def controls():
    values = cases()
    success = next(value for value in values if value.n and value.must_converge and value.exact_steps == 0)
    x = list(success.initial)
    header = (0, 0, MASK, MASK, MASK, 0, 0, 0, success.n, bits(norm(success.b)), bits(norm(residual(success, x))))
    check_success(success, header, x)
    bad = list(header); bad[10] = bits(1.)
    try:
        check_success(success, bad, x)
    except AssertionError:
        pass
    else:
        raise AssertionError("oracle accepted a forged residual norm")
    # Scalar IEEE tripwire only; solution acceptance uses Gaussian/Fraction
    # and an independent fresh b-Ax above, never a CG recurrence model.
    a, b, initial = 1e308, 1., 1.
    recursive = b - a * initial
    z = recursive / a
    rho = recursive * z
    q = a * z
    alpha = rho / (z * q)
    updated = initial + alpha * z
    recursive -= alpha * q
    fresh = b - a * updated
    assert alpha == 1. and updated == 0. and recursive == 0. and fresh == 1.
    matrices = {(value.n, value.a, value.b) for value in values if value.reference and not value.error}
    for n, a, rhs in matrices:
        solution, margin = exact_solution(n, a, rhs)
        assert margin > 0
    print(f"sparse-cg CPU cases={len(values)} independent-systems={len(matrices)} forged-residual=rejected recursive0-fresh1=checked")


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    executable, = sys.argv[1:]
    values = cases()
    result = subprocess.run([str(Path(executable).resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=70, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr)
    verify(result.stdout, values)
    print(f"sparse-cg cases={len(values)} storage_forms=2 seed={SEED:#x} gaussian=fraction fresh-residual=checked")


if __name__ == "__main__":
    main()
