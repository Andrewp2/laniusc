#!/usr/bin/env python3
"""Compare text-head with GNU head under LC_ALL=C, byte for byte.

usage: head_oracle.py TEXT_HEAD WORKDIR [CASES]

Each case draws counts for -n and -c (plain, with a leading '-' to elide,
'+', leading blanks, size suffixes b k K kB KiB M G ..., bare suffixes,
invalid text and values past 64 bits; short, attached, long and
abbreviated long forms; repeated so the last one wins), GNU's obsolete
first argument (-NUM with b c k l m q v z, and invalid letters), -q, -v,
--silent, -z, "--", unknown options, and one to three inputs (standard
input, "-", named files, a missing file). stdout and the exit status must
match. Input groups:

  lines     short lines, sometimes without a final LF
  records   NUL-terminated records, for -z
  binary    random bytes
  large     300 KB to 1.5 MB, across the 256 KiB read chunks
"""
import os
import random
import subprocess
import sys

TOOL, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
CASES = int(sys.argv[3]) if len(sys.argv) > 3 else 1000
os.makedirs(WORK, exist_ok=True)
ENV = dict(os.environ, LC_ALL="C")
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def gen(rng, group):
    if group == "lines":
        t = b"".join(bytes(rng.choice(b"abc xyz") for _ in range(rng.randint(0, 8))) + b"\n" for _ in range(rng.randint(0, 40)))
    elif group == "records":
        t = b"".join(bytes(rng.choice(b"ab\n ") for _ in range(rng.randint(0, 6))) + b"\x00" for _ in range(rng.randint(0, 30)))
    elif group == "binary":
        t = bytes(rng.choice(b"ab\n\n\x00\x80\xff") for _ in range(rng.randint(0, 400)))
    else:
        unit = b"".join(b"x" * rng.randint(0, 120) + b"\n" for _ in range(50))
        t = unit * (rng.randint(300000, 1500000) // max(1, len(unit)))
    if t and rng.random() < 0.3:
        t = t[:-rng.randint(1, min(5, len(t)))]
    return t


def number(rng, small):
    r = rng.random()
    if r < 0.6:
        return str(rng.randint(0, small))
    if r < 0.75:
        return str(rng.choice([rng.randint(0, 400), rng.randint(1000, 2000000)]))
    return rng.choice(["0", "+3", " 2", "\t4", "1b", "2k", "1K", "1kB", "1KiB", "1kD", "1M", "1MB", "1G", "1T", "1P", "1E",
                       "1Z", "1Y", "1R", "1Q", "k", "b", "", "x", "3x", "1.5", "--2", "+-1", "1kiB", "1iB", "18446744073709551615",
                       "18446744073709551616", "99999999999999999999k", "0x10", "1e3", "1KB", "3 ", "2B"])


def count_opt(rng, which):
    small = 12
    v = number(rng, small)
    if rng.random() < 0.3:
        v = "-" + v
    style = rng.randint(0, 4)
    long = "--lines" if which == "n" else "--bytes"
    if style == 0:
        return ["-" + which, v]
    if style == 1:
        return ["-" + which + v] if v else ["-" + which, v]
    if style == 2:
        return [long + "=" + v]
    if style == 3:
        return [long[:rng.randint(3, len(long))], v]
    return ["-q" + which, v]


def obsolete(rng):
    s = "-" + str(rng.randint(0, 15))
    s += "".join(rng.choice("bcklmqvz") for _ in range(rng.choice([0, 0, 0, 1, 1, 2])))
    if rng.random() < 0.05:
        s += rng.choice(["x", "n", "5"])
    return s


def options(rng):
    opts = []
    zero = False
    for _ in range(rng.choice([0, 1, 1, 1, 2])):
        opts += count_opt(rng, rng.choice("nnc"))
    for flag in [["-q"], ["--quiet"], ["--silent"], ["-v"], ["--verbose"], ["--verb"], ["-z"], ["--zero-terminated"]]:
        if rng.random() < 0.06:
            opts += flag
            if "z" in flag[0]:
                zero = True
    if rng.random() < 0.03:
        opts.append(rng.choice(["--x", "-x", "-5", "--li"]))
    return opts, zero


def run(cmd, stdin_path):
    with open(stdin_path, "rb") as f:
        return subprocess.run(cmd, stdin=f, capture_output=True, cwd=WORK, env=ENV, timeout=60)


def fail(msg, data, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        for name, blob in (("input", data), ("mine", mine), ("ref", ref)):
            with open(os.path.join(d, name), "wb") as f:
                f.write(blob)
        print("FAIL", msg, "->", d)


def main():
    rng = random.Random(20261106)
    for case in range(CASES):
        opts, zero = options(rng)
        group = "large" if case % 40 == 39 else ("records" if zero and rng.random() < 0.7 else rng.choice(["lines", "lines", "binary", "records"]))
        data = gen(rng, group)
        with open(os.path.join(WORK, "in"), "wb") as f:
            f.write(data)
        with open(os.path.join(WORK, "in2"), "wb") as f:
            f.write(gen(rng, "lines"))
        mode = rng.choice(["stdin", "stdin", "named", "files", "dash", "missing", "dashdash"])
        operands = {"stdin": [], "named": ["in"], "files": ["in", "in2"] + (["-"] if rng.random() < 0.3 else []),
                    "dash": ["-"], "missing": ["in", "nope"], "dashdash": ["--", "in"]}[mode]
        args = opts + operands
        if operands and rng.random() < 0.3:
            k = rng.randint(0, len(opts))
            args = opts[:k] + operands + opts[k:]
        if rng.random() < 0.15:
            args = [obsolete(rng)] + args
        mine = run([TOOL] + args, os.path.join(WORK, "in"))
        ref = run(["head"] + args, os.path.join(WORK, "in"))
        key = f"{group}/{mode}/{'ok' if ref.returncode == 0 else 'error'}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine.stdout != ref.stdout:
            fail(f"{key} {' '.join(args)[:200]!r} rc {mine.returncode}/{ref.returncode}", data, mine.stdout, ref.stdout)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
