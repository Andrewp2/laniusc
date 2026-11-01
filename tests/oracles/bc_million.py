#!/usr/bin/env python3
"""Million-digit oracle and timing comparison for sample_programs/library/bc.lani.

usage: bc_million.py BC_EXECUTABLE [OP ...]
Each OP runs in its own bc process. Python's int (3.12, with its own
subquadratic str/int conversion and division) is the reference. The bc time
covers process start, parsing, the operation and printing; the Python time
covers int() parsing, the operation and str().
"""
import random
import subprocess
import sys
import time

sys.set_int_max_str_digits(0)
rng = random.Random(0x1E6)
A = rng.randrange(10 ** 999_999, 10 ** 1_000_000)  # exactly 1,000,000 digits
B = rng.randrange(10 ** 499_999, 10 ** 500_000)  # exactly 500,000 digits
SA, SB = str(A), str(B)
M = rng.randrange(10 ** 2999, 10 ** 3000) | 1


def tdiv(a, b):
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


OPS = {
    "roundtrip": (lambda: SA, lambda: str(int(SA))),
    "add": (lambda: SA + "+" + SB, lambda: str(int(SA) + int(SB))),
    "mul": (lambda: SA + "*" + SB, lambda: str(int(SA) * int(SB))),
    "div": (lambda: SA + "/" + SB, lambda: str(tdiv(int(SA), int(SB)))),
    "rem": (lambda: "(-" + SA + ")%" + SB, lambda: str(-int(SA) - tdiv(-int(SA), int(SB)) * int(SB))),
    "square": (lambda: SB + "*" + SB, lambda: str(int(SB) * int(SB))),
    "modpow": (lambda: "modpow(%s,%s,%d)" % (SB[:20000], SB[:3000], M), lambda: str(pow(int(SB[:20000]), int(SB[:3000]), M))),
}


def main():
    exe = sys.argv[1]
    ops = sys.argv[2:] or list(OPS)
    args = [exe, "--max-limbs", "10000000", "--max-line", "10000000", "--max-output", "10000000",
            "--max-work", "18446744073709551615"]
    for name in ops:
        make_input, reference = OPS[name]
        text = make_input() + "\n"
        start = time.perf_counter()
        expected = reference()
        python_s = time.perf_counter() - start
        start = time.perf_counter()
        proc = subprocess.run(args, input=text.encode(), stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=280)
        bc_s = time.perf_counter() - start
        got = proc.stdout.decode().rstrip("\n")
        if proc.returncode != 0 or got != expected:
            raise SystemExit("%s: mismatch (status %d, %d vs %d digits) %s" % (name, proc.returncode, len(got), len(expected), proc.stderr.decode()[:200]))
        print("%-9s ok  result %8d digits  bc %7.2f s  python %6.2f s  ratio %5.1fx" % (name, len(expected), bc_s, python_s, bc_s / max(python_s, 1e-6)), flush=True)


if __name__ == "__main__":
    main()
