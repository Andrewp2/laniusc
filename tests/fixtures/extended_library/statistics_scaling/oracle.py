"""Independent exact-rational oracle for bounded binary64 products/quotients.

The reference multiplies Fraction.from_float inputs directly: no exponent
splitting or production mantissa mask is reproduced. The implementation allows
rounding between factors, so general cases allow eight ULP and a 9u relative
bound plus half a minimum subnormal. Exact dyadic/cancellation cases require
bit equality. Python supplies test references and binary transport only.
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from fractions import Fraction
import math
from pathlib import Path
import random
import struct
import subprocess

SIGN = 1 << 63
FRAC = (1 << 52) - 1
INF = 0x7FF0000000000000
MASK = (1 << 64) - 1
ONE = 0x3FF0000000000000
MINIMUM = Fraction(1, 1 << 1074)
UNIT = Fraction(1, 1 << 53)
RELATIVE_BOUND = 9 * UNIT
OVERFLOW_EDGE = Fraction(1 << 1024) - Fraction(1 << 970)
SEED = 0x5343414C45323026
# (name, numerator count, denominator count)
OPS = (("product3", 3, 0), ("product5", 5, 0), ("quotient2", 2, 1),
       ("quotient4", 4, 1), ("quotient5", 5, 1), ("quotient2_2", 2, 2))


def bits(value: float) -> int:
    return struct.unpack("<Q", struct.pack("<d", value))[0]


def value(raw: int) -> float:
    return struct.unpack("<d", struct.pack("<Q", raw))[0]


def ordered(raw: int) -> int:
    return (~raw & MASK) if raw & SIGN else raw | SIGN


@dataclass(frozen=True)
class Case:
    op: int
    inputs: tuple[int, ...]
    label: str
    exact: bool = False


def reference(case: Case) -> tuple[Fraction | None, int]:
    _, numerators, denominators = OPS[case.op]
    assert len(case.inputs) == numerators + denominators
    incoming = tuple(value(raw) for raw in case.inputs)
    sign = 0
    for index, (number, raw) in enumerate(zip(incoming, case.inputs)):
        if not math.isfinite(number) or (index >= numerators and number == 0):
            return None, 0
        sign ^= raw & SIGN
    product = Fraction(1)
    for number in incoming[:numerators]:
        product *= Fraction.from_float(number)
    for number in incoming[numerators:]:
        product /= Fraction.from_float(number)
    return product, sign


def rounded(exact: Fraction, sign: int) -> int:
    if not exact:
        return sign
    try:
        return bits(float(exact))
    except OverflowError:
        return INF | sign


def verify_one(case: Case, actual: int, index: int) -> int:
    exact, sign = reference(case)
    diagnostic = (f"seed={SEED:#x}", index, OPS[case.op][0], case.label,
                  tuple(f"{raw:016x}" for raw in case.inputs), f"got={actual:016x}")
    got = value(actual)
    if exact is None:
        assert math.isnan(got), (diagnostic, "invalid input must return NaN")
        return 0
    expected = rounded(exact, sign)
    if not exact or case.exact:
        assert actual == expected, (diagnostic, "exact contract", f"want={expected:016x}")
        return 0
    assert not math.isnan(got) and actual & SIGN == sign, (diagnostic, "class/sign")
    magnitude = abs(exact)
    if math.isinf(got):
        # Intermediate rounding may cross the final overflow edge. Only a
        # relative-rounding-width neighborhood of that edge admits this.
        assert magnitude >= OVERFLOW_EDGE / (1 + RELATIVE_BOUND), (diagnostic, "premature overflow")
        return 0
    error = abs(Fraction.from_float(got) - exact)
    assert error <= magnitude * RELATIVE_BOUND + MINIMUM / 2, (diagnostic, "relative/subnormal error")
    if expected & ~SIGN < INF:
        ulp = abs(ordered(actual) - ordered(expected))
        assert ulp <= 8, (diagnostic, f"ULP={ulp}", f"want={expected:016x}")
        return ulp
    # A finite answer for an exact result above the overflow edge is allowed
    # only when the same small relative-error bound holds.
    return 0


def cases() -> list[Case]:
    result: list[Case] = []
    rng = random.Random(SEED)

    def add(op: int, inputs: list[float] | tuple[float, ...], label: str,
            exact: bool = False) -> None:
        result.append(Case(op, tuple(bits(x) for x in inputs), label, exact))

    def power(exponent: int) -> float:
        return math.ldexp(1.0, exponent)

    # Products that lose range with ordinary left-to-right arithmetic even
    # though their final answer is finite and representable.
    hi, lo = power(900), power(-900)
    cancellation = (([hi, hi, lo], [lo, lo, hi]),
                    ([hi, hi, lo, lo, 3.0], [lo, lo, hi, hi, 3.0]),
                    ([hi, hi, hi], [lo, lo, lo]),
                    ([hi, hi, lo, lo, lo], [lo, lo, hi, hi, hi]),
                    ([hi, hi, lo, lo, 1.0, lo], [lo, lo, hi, hi, 1.0, hi]),
                    ([hi, hi, hi, hi], [lo, lo, lo, lo]))
    for op, pairs in enumerate(cancellation):
        for inputs in pairs:
            add(op, inputs, "avoid intermediate range loss", True)
            negative = list(inputs)
            negative[-1] = -negative[-1]
            add(op, negative, "signed exponent cancellation", True)

    # Recover a factor exactly through each public arity. Chosen exponent
    # fields/fraction bits catch sign, exponent and fraction-mask mistakes.
    raw_probes = [1, 2, 3, 1 << 30, (1 << 51) - 1, 1 << 51, FRAC]
    for exponent in (1, 2, 3, 511, 512, 1022, 1023, 1024, 1535, 1536, 2045, 2046):
        for fraction in (0, 1, 1 << 51, FRAC):
            raw_probes.append((exponent << 52) | fraction)
    for op, (_, numerators, denominators) in enumerate(OPS):
        count = numerators + denominators
        for raw in raw_probes:
            for sign in (0, SIGN):
                inputs = [1.0] * count
                inputs[0] = value(raw | sign)
                add(op, inputs, "single-factor recovery", True)
        if denominators:
            for raw in (1, 3, FRAC, ONE - 1, ONE + 1, INF - 1):
                for offset in range(denominators):
                    inputs = [1.0] * count
                    inputs[0] = value(raw)
                    inputs[numerators + offset] = value(raw)
                    add(op, inputs, "numerator/denominator cancel", True)
        for signs in range(1 << count):
            inputs = [-1.0 if signs & (1 << i) else 1.0 for i in range(count)]
            inputs[0] = -0.0 if signs & 1 else 0.0
            add(op, inputs, "zero sign across all positions", True)
        for position in range(count):
            for bad in (math.inf, -math.inf, value(INF | 1), value(SIGN | INF | (1 << 51) | 17)):
                for earlier_zero in (False, True):
                    inputs = [1.0] * count
                    if earlier_zero and position != 0:
                        inputs[0] = -0.0
                    inputs[position] = bad
                    add(op, inputs, "validate all inputs before zero")
            if position >= numerators:
                for zero in (0.0, -0.0):
                    inputs = [1.0] * count
                    inputs[position] = zero
                    add(op, inputs, "invalid zero denominator")
                    inputs[0] = 0.0
                    add(op, inputs, "zero does not bypass denominator validation")

        # Solve the final exponent so the *total* exponent lands at selected
        # normal, subnormal and final range boundaries. Powers of two make
        # these exact contracts independent of multiplication association.
        choices = (-1074, -1022, -1000, -900, -500, -54, -1, 0, 1, 54, 500, 900, 1000, 1023)
        coefficients = [1] * numerators + [-1] * denominators
        for total in (-2200, -1077, -1075, -1074, -1073, -1022, -1, 0, 1, 900, 1023, 1024, 2048):
            produced = 0
            for _ in range(100):
                exponents = [rng.choice(choices) for _ in range(count - 1)]
                remainder = total - sum(c * e for c, e in zip(coefficients, exponents))
                last = coefficients[-1] * remainder
                if not -1074 <= last <= 1023:
                    continue
                inputs = [power(e) for e in exponents + [last]]
                for i in range(count):
                    if rng.getrandbits(1):
                        inputs[i] = -inputs[i]
                add(op, inputs, f"exact total exponent {total}", True)
                produced += 1
                if produced == 3:
                    break
            assert produced == 3, (op, total, produced)

        # Full binary64 exponent spread and independent random fractions.
        # Include very small denominators and final overflow/underflow cases.
        for sample in range(96):
            inputs = []
            for _ in range(count):
                biased = rng.choice((0, 1, 2, 127, 511, 1022, 1023, 1024, 1535, 2045, 2046))
                fraction = rng.getrandbits(52)
                raw = (biased << 52) | fraction
                if raw == 0:
                    raw = 1
                if rng.getrandbits(1):
                    raw |= SIGN
                inputs.append(value(raw))
            add(op, inputs, f"random factors {sample}")

    # Rounding to subnormals includes exact half-way ties and nonzero signs.
    minimum = value(1)
    for factor in (0.25, 0.5, 0.75, 1.0, 1.5, 2.5, 3.5):
        add(0, [minimum, factor, 1.0], "subnormal round-to-even", True)
        add(0, [-minimum, factor, 1.0], "signed subnormal round-to-even", True)
    assert len(result) <= 8192
    return result


def packet(values: list[Case]) -> bytes:
    return struct.pack("<Q", len(values)) + b"".join(
        struct.pack("<7Q", case.op, *(case.inputs + (ONE,) * (6 - len(case.inputs))))
        for case in values
    )


def verify(actual: bytes, values: list[Case]) -> dict[str, int]:
    assert len(actual) == 8 * len(values), (len(actual), len(values))
    maxima = {name: 0 for name, _, _ in OPS}
    for index, (case, (raw,)) in enumerate(zip(values, struct.iter_unpack("<Q", actual))):
        error = verify_one(case, raw, index)
        name = OPS[case.op][0]
        maxima[name] = max(maxima[name], error)
    return maxima


def self_check() -> None:
    values = cases()
    assert len(packet(values)) == 8 + len(values) * 56
    expected = []
    for case in values:
        exact, sign = reference(case)
        expected.append(INF | (1 << 51) if exact is None else rounded(exact, sign))
    verify(b"".join(struct.pack("<Q", raw) for raw in expected), values)
    # The checker must reject plausible faults: total exponent dropped,
    # mantissa changed, lost zero sign, early-zero validation and range loss.
    controls = ((Case(0, (bits(2.0), ONE, ONE), "exponent"), ONE),
                (Case(0, (bits(1.5), ONE, ONE), "fraction"), ONE),
                (Case(2, (SIGN, ONE, bits(-1.0)), "zero sign", True), SIGN),
                (Case(0, (0, ONE, INF), "short-circuit validation"), 0),
                (Case(0, (bits(math.ldexp(1.0, 900)), bits(math.ldexp(1.0, 900)), bits(math.ldexp(1.0, -900))), "premature overflow"), INF),
                (Case(0, (bits(math.ldexp(1.0, -900)), bits(math.ldexp(1.0, -900)), bits(math.ldexp(1.0, 900))), "premature underflow"), 0))
    for case, corrupted in controls:
        try:
            verify_one(case, corrupted, -1)
        except AssertionError:
            pass
        else:
            raise AssertionError(("control accepted bad output", case))
    print(f"statistics-scaling oracle-self-check cases={len(values)} controls={len(controls)} seed={SEED:#x}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("executable", type=Path, nargs="?")
    parser.add_argument("--self-check", action="store_true")
    arguments = parser.parse_args()
    if arguments.self_check:
        self_check()
        return
    if arguments.executable is None:
        parser.error("executable is required unless --self-check is supplied")
    values = cases()
    result = subprocess.run([str(arguments.executable.resolve())], input=packet(values),
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            timeout=25, check=False)
    assert result.returncode == 0 and not result.stderr, (result.returncode, result.stderr, len(result.stdout))
    maxima = verify(result.stdout, values)
    exact_count = sum(case.exact for case in values)
    print(f"statistics-scaling cases={len(values)} arities=6 exact-cases={exact_count} seed={SEED:#x}")
    print("max-observed-ULP " + " ".join(f"{name}={error}" for name, error in maxima.items()))


if __name__ == "__main__":
    main()
