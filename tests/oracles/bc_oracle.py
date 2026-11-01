#!/usr/bin/env python3
"""Independent Python-int oracle for sample_programs/library/bc.lani.

usage: bc_oracle.py BC_EXECUTABLE
Generates deterministic expressions, runs the native bc once per radix pass,
and checks every stdout value and every stderr diagnostic. Prints exact counts.
"""
import random
import subprocess
import sys

DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
LIMB_SIZES = [0, 1, 2, 3, 30, 31, 32, 33, 34, 63, 64, 65, 66, 95, 96, 97, 127, 128, 129, 200, 257, 513]
THRESHOLD = 32  # alloc::big_uint::KARATSUBA_THRESHOLD


sys.set_int_max_str_digits(0)


def lit(n, radix):
    """Input literal: uppercase digits; a negative value is parenthesized unary minus."""
    m = abs(n)
    if radix in (2, 8, 10, 16):
        s = format(m, {2: "b", 8: "o", 10: "d", 16: "X"}[radix])
    elif m == 0:
        s = "0"
    else:
        out = []
        while m:
            m, d = divmod(m, radix)
            out.append(DIGITS[d])
        s = "".join(reversed(out))
    return "(-%s)" % s if n < 0 else s


def fmt(n, radix):
    return lit(n, radix).replace("(", "").replace(")", "").lower()


def tdiv(a, b):
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q, a - q * b


class Error(Exception):
    def __init__(self, kind):
        self.kind = kind


def value_of_limbs(rng, limbs, pattern):
    if limbs == 0:
        return 0
    bits = 32 * limbs
    if pattern == 0:
        return rng.getrandbits(bits) | (1 << (bits - 1 - rng.randrange(32)))
    if pattern == 1:
        return (1 << bits) - 1  # all ones: maximal carries
    if pattern == 2:
        return 1 << (bits - 1)
    if pattern == 3:
        # sparse: a few set limbs, mostly zero limbs (exercises window trimming)
        v = 1 << (bits - 1)
        for _ in range(3):
            v |= rng.getrandbits(32) << (32 * rng.randrange(limbs))
        return v
    return (1 << (bits - 32)) + rng.getrandbits(32)  # top limb is exactly 1


def signed(rng, v):
    return -v if rng.random() < 0.4 else v


def make_cases(rng, radix):
    """Returns (category, input_text, expected) with expected int or Error."""
    cases = []
    sizes = LIMB_SIZES if radix in (10, 16) else [0, 1, 2, 31, 32, 33, 64, 65]
    # Multiplication straddling the Karatsuba threshold, both orders, squares.
    for la in sizes:
        for lb in sizes:
            for pattern in range(5):
                if pattern and rng.random() < 0.6:
                    continue
                a = signed(rng, value_of_limbs(rng, la, pattern))
                b = signed(rng, value_of_limbs(rng, lb, rng.randrange(5)))
                cat = "mul-karatsuba" if min(la, lb) >= THRESHOLD else "mul-schoolbook"
                cases.append((cat, "%s*%s" % (lit(a, radix), lit(b, radix)), a * b))
        a = signed(rng, value_of_limbs(rng, la, rng.randrange(5)))
        cases.append(("square", "%s*%s" % (lit(a, radix), lit(a, radix)), a * a))
    # Division and remainder (Knuth D), including zero divisors.
    for la in sizes:
        for lb in sizes:
            if rng.random() < 0.5:
                continue
            a = signed(rng, value_of_limbs(rng, la, rng.randrange(5)))
            b = signed(rng, value_of_limbs(rng, lb, rng.randrange(5)))
            if b == 0:
                cases.append(("div-by-zero", "%s/%s" % (lit(a, radix), lit(b, radix)), Error("division-by-zero")))
                cases.append(("div-by-zero", "%s%%%s" % (lit(a, radix), lit(b, radix)), Error("division-by-zero")))
                continue
            q, r = tdiv(a, b)
            cases.append(("div", "%s/%s" % (lit(a, radix), lit(b, radix)), q))
            cases.append(("rem", "%s%%%s" % (lit(a, radix), lit(b, radix)), r))
            # identity on a product: (a*b+r')/b with a known remainder
            if abs(b) > 1:
                rr = rng.randrange(abs(b))
                n = a * b + (rr if a * b >= 0 else -rr)
                q2, r2 = tdiv(n, b)
                cases.append(("div", "%s/%s" % (lit(n, radix), lit(b, radix)), q2))
                cases.append(("rem", "%s%%%s" % (lit(n, radix), lit(b, radix)), r2))
    # Add, subtract, bitwise and shifts.
    for _ in range(60):
        a = signed(rng, value_of_limbs(rng, rng.choice(sizes), rng.randrange(5)))
        b = signed(rng, value_of_limbs(rng, rng.choice(sizes), rng.randrange(5)))
        s = rng.randrange(0, 200)
        cases.append(("add", "%s+%s" % (lit(a, radix), lit(b, radix)), a + b))
        cases.append(("sub", "%s-%s" % (lit(a, radix), lit(b, radix)), a - b))
        cases.append(("and", "%s&%s" % (lit(a, radix), lit(b, radix)), a & b))
        cases.append(("or", "%s|%s" % (lit(a, radix), lit(b, radix)), a | b))
        cases.append(("shl", "%s<<%s" % (lit(a, radix), lit(s, radix)), a << s))
        cases.append(("shr", "%s>>%s" % (lit(a, radix), lit(s, radix)), a >> s))
    cases.append(("shl", "1<<(-1)", Error("invalid-shift")))
    # gcd and abs.
    for _ in range(40):
        g = value_of_limbs(rng, rng.choice([0, 1, 2, 33]), 0)
        a = signed(rng, g * value_of_limbs(rng, rng.choice([0, 1, 3, 40]), 0))
        b = signed(rng, g * value_of_limbs(rng, rng.choice([0, 1, 5, 35]), 0))
        import math
        cases.append(("gcd", "gcd(%s,%s)" % (lit(a, radix), lit(b, radix)), math.gcd(a, b)))
        cases.append(("abs", "abs(%s)" % lit(a, radix), abs(a)))
    # Powers.
    for _ in range(40):
        a = signed(rng, value_of_limbs(rng, rng.choice([0, 1, 2, 5, 33]), rng.randrange(5)))
        e = rng.randrange(0, 40)
        cases.append(("pow", "%s^%s" % (lit(a, radix), lit(e, radix)), a ** e))
    cases.append(("pow", "0^0", 1))
    cases.append(("pow", "%s^(-1)" % lit(2, radix), Error("negative-exponent")))
    cases.append(("pow", "%s^%s" % (lit(2, radix), lit(1 << 32, radix)), Error("invalid-exponent")))
    # Modular exponentiation, Python pow(a, e, m) semantics.
    for _ in range(60):
        a = signed(rng, value_of_limbs(rng, rng.choice([0, 1, 2, 8, 33, 40]), rng.randrange(5)))
        e = value_of_limbs(rng, rng.choice([0, 1, 2, 4]), rng.randrange(5))
        m = signed(rng, value_of_limbs(rng, rng.choice([1, 2, 8, 33, 34]), rng.randrange(5)))
        cases.append(("modpow", "modpow(%s,%s,%s)" % (lit(a, radix), lit(e, radix), lit(m, radix)), pow(a, e, m)))
    for m in (1, -1):
        cases.append(("modpow", "modpow(%s,%s,%s)" % (lit(7, radix), lit(5, radix), lit(m, radix)), pow(7, 5, m)))
    cases.append(("modpow", "modpow(%s,%s,0)" % (lit(3, radix), lit(5, radix)), Error("division-by-zero")))
    # Modular inverses and negative exponents, Python pow(a, -e, m).
    for _ in range(60):
        m = signed(rng, value_of_limbs(rng, rng.choice([1, 2, 8, 33, 70]), rng.randrange(5)))
        a = signed(rng, value_of_limbs(rng, rng.choice([0, 1, 2, 8, 33, 70]), rng.randrange(5)))
        try:
            want = pow(a, -1, m)
        except ValueError:
            want = Error("not-invertible")
        cases.append(("modinv", "modinv(%s,%s)" % (lit(a, radix), lit(m, radix)), want))
        e = value_of_limbs(rng, rng.choice([0, 1, 2]), 0)
        if not isinstance(want, Error):
            cases.append(("modpow-negative", "modpow(%s,(-%s),%s)" % (lit(a, radix), lit(e, radix), lit(m, radix)), pow(a, -e, m) if e else pow(a, 0, m)))
    cases.append(("modinv", "modinv(%s,%s)" % (lit(6, radix), lit(9, radix)), Error("not-invertible")))
    cases.append(("modinv", "modinv(%s,0)" % lit(3, radix), Error("division-by-zero")))
    cases.append(("modinv", "modinv(%s,%s)" % (lit(5, radix), lit(1, radix)), 0))
    # Random fully parenthesized expression trees.
    def tree(depth):
        if depth == 0 or rng.random() < 0.25:
            v = signed(rng, value_of_limbs(rng, rng.choice([0, 1, 2, 33]), rng.randrange(5)))
            return lit(v, radix), v
        op = rng.choice("+-*/%&|")
        ls, lv = tree(depth - 1)
        rs, rv = tree(depth - 1)
        text = "(%s%s%s)" % (ls, op, rs)
        if op in "/%":
            if rv == 0:
                raise Error("division-by-zero")
            q, r = tdiv(lv, rv)
            return text, q if op == "/" else r
        return text, {"+": lv + rv, "-": lv - rv, "*": lv * rv, "&": lv & rv, "|": lv | rv}[op]
    for _ in range(150):
        try:
            text, value = tree(4)
            cases.append(("expr", text, value))
        except Error:
            pass
    return cases


FIXED = [
    # precedence and syntax, decimal only
    ("precedence", "1+2*3", 7), ("precedence", "(1+2)*3", 9), ("precedence", "-2^2", -4),
    ("precedence", "2^3^2", 512), ("precedence", "1<<3+1", 16), ("precedence", "12&10|1", 9),
    ("precedence", "7/-2", -3), ("precedence", "-7%3", -1), ("precedence", "--5", 5),
    ("precedence", "  3 *\t4  # trailing comment", 12),
    ("zero", "0", 0), ("zero", "-0", 0), ("zero", "000", 0), ("zero", "0*123456789012345678901234567890", 0),
    ("zero", "5-5", 0), ("zero", "(-5)%5", 0),
    ("syntax", "(1", Error("syntax-error")), ("syntax", "1+", Error("syntax-error")),
    ("syntax", "1 2", Error("syntax-error")), ("syntax", "foo(1)", Error("unknown-function")),
    ("syntax", "1A", Error("invalid-digit")), ("syntax", "gcd(1)", Error("syntax-error")),
    ("syntax", "(" * 300 + "1" + ")" * 300, Error("nesting-limit")),
]


def run(exe, radix, cases):
    text = "".join(c[1] + "\n" for c in cases)
    args = [exe, "--ibase", str(radix), "--obase", str(radix)]
    proc = subprocess.run(args, input=text.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=240)
    out = proc.stdout.decode().split("\n")
    err = [line for line in proc.stderr.decode().split("\n") if line]
    expected_out, expected_err = [], []
    for number, (_, _, want) in enumerate(cases, 1):
        if isinstance(want, Error):
            expected_err.append((want.kind, number))
        else:
            expected_out.append(fmt(want, radix))
    got_err = []
    for line in err:
        parts = line.split()
        assert parts[0] == "bc:", line
        got_err.append((parts[1], int(parts[2].split("=")[1])))
    if out[-1] != "":
        raise SystemExit("radix %d: missing final newline" % radix)
    out = out[:-1]
    if out != expected_out:
        for index, (a, b) in enumerate(zip(out, expected_out)):
            if a != b:
                raise SystemExit("radix %d: value %d differs: got %s... expected %s..." % (radix, index, a[:60], b[:60]))
        raise SystemExit("radix %d: %d values, expected %d" % (radix, len(out), len(expected_out)))
    if got_err != expected_err:
        diff = sorted(set(got_err) ^ set(expected_err), key=lambda x: x[1])[:5]
        raise SystemExit("radix %d: diagnostics differ at %r; inputs %r" % (radix, diff, [cases[d[1] - 1][1][:80] for d in diff]))
    want_status = 1 if expected_err else 0
    if proc.returncode != want_status:
        raise SystemExit("radix %d: status %d expected %d" % (radix, proc.returncode, want_status))
    return len(expected_out), len(expected_err)


def main():
    exe = sys.argv[1]
    rng = random.Random(0xBC2026)
    counts = {}
    total_values = total_errors = 0
    radices = [int(r) for r in sys.argv[2].split(",")] if len(sys.argv) > 2 else [10, 16, 2, 3, 7, 36]
    for radix in (10, 16, 2, 3, 7, 36):
        if radix not in radices:
            make_cases(rng, radix)
            continue
        cases = make_cases(rng, radix)
        if radix == 10:
            cases = FIXED + cases
        values, errors = run(exe, radix, cases)
        total_values += values
        total_errors += errors
        for cat, _, _ in cases:
            counts[cat] = counts.get(cat, 0) + 1
    print("categories: " + " ".join("%s=%d" % kv for kv in sorted(counts.items())))
    print("checked %d values and %d diagnostics across %d radices" % (total_values, total_errors, len(radices)))


if __name__ == "__main__":
    main()
