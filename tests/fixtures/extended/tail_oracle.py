#!/usr/bin/env python3
"""Compare text-tail with GNU tail (no following) under LC_ALL=C.

usage: tail_oracle.py TEXT_TAIL WORKDIR [CASES]

Each case draws counts for -n and -c (plain, with a leading '+' to count
from the start or '-', leading blanks, size suffixes b k K kB KiB M G ...,
bare suffixes, invalid text and values past 64 bits; short, attached, long
and abbreviated long forms; repeated so the last one wins, while a '+'
stays set as in GNU), GNU's obsolete form ([-+]NUM[bcl] as the only option,
before at most one file or after "--", and look-alikes that are not it),
digit options out of place, -q, -v, --silent, -z, -s, --pid, --retry,
--max-unchanged-stats, ---disable-inotify, ---presume-input-pipe with
valid and invalid values, "--", unknown and ambiguous options, and up to
13 inputs (standard
input from a file or a pipe, "-" once or repeated so later ones continue
where GNU leaves the file offset, named files, a missing file). stdout and the exit status must
match. Input groups:

  lines     short lines, sometimes without a final LF
  records   NUL-terminated records, for -z
  binary    random bytes
  crlf      CR LF line ends
  long      a few lines of up to 300 KB
  empty     no bytes at all
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
    elif group == "crlf":
        t = b"".join(bytes(rng.choice(b"ab \r") for _ in range(rng.randint(0, 8))) + b"\r\n" for _ in range(rng.randint(0, 30)))
    elif group == "long":
        t = b"".join(bytes([rng.choice(b"abc")]) * rng.randint(0, 300000) + b"\n" for _ in range(rng.randint(1, 6)))
    elif group == "empty":
        t = b""
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
                       "1Z", "1Y", "1R", "1Q", "k", "b", "", "x", "3x", "1.5", "--2", "+-1", "-+2", "1kiB", "1iB", "18446744073709551615",
                       "18446744073709551616", "99999999999999999999k", "0x10", "1e3", "1KB", "3 ", "2B", " +4", " -4"])


def count_opt(rng, which):
    v = number(rng, 12)
    r = rng.random()
    if r < 0.3:
        v = "+" + v
    elif r < 0.45:
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
    s = rng.choice("-+-") + rng.choice(["", str(rng.randint(0, 15)), str(rng.randint(0, 3000)), "99999999999999999999"])
    s += rng.choice(["", "", "", "b", "c", "l"])
    if rng.random() < 0.05:
        s += rng.choice(["x", "n", "5", "k", "cc"])
    if rng.random() < 0.03:
        s = rng.choice(["-c", "-", "+", "-l", "-b", "+c", "-5c4"])
    return s


VALUES = {
    "-s": ["1", "0", "1.5", ".5", "5.", "1e3", "1e", "inf", "INF", "infinity", "-inf", "nan", "x", "", " 2", "2 ", "-0", "-1",
           "0x10", "0x", "0x1p3", "+3", "1e+2", ",5"],
    "--pid=": ["0", "1", "12345", "2147483647", "2147483648", "-1", "-0", "x", "", " 5", "+5", "5k"],
    "--max-unchanged-stats=": ["0", "5", "18446744073709551615", "18446744073709551616", "-1", "x", "", "5k", " 3", "+3"],
}


def options(rng):
    opts = []
    zero = False
    for _ in range(rng.choice([0, 1, 1, 1, 2])):
        opts += count_opt(rng, rng.choice("nnc"))
    for flag in [["-q"], ["--quiet"], ["--silent"], ["-v"], ["--verbose"], ["--verb"], ["-z"], ["--zero-terminated"],
                 ["--retry"], ["---disable-inotify"], ["---presume-input-pipe"], ["---pres"]]:
        if rng.random() < 0.05:
            opts += flag
            if "z" in flag[0]:
                zero = True
    for key, values in VALUES.items():
        if rng.random() < 0.04:
            v = rng.choice(values)
            opts += ["-s", v] if key == "-s" else [key + v]
    if rng.random() < 0.03:
        opts.append(rng.choice(["--x", "-x", "-5", "--li", "--s", "--ver", "---", "-n"]))
    return opts, zero

def run(cmd, stdin_path, pipe):
    with open(stdin_path, "rb") as f:
        if pipe:
            return subprocess.run(cmd, input=f.read(), capture_output=True, cwd=WORK, env=ENV, timeout=60)
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
    rng = random.Random(20261107)
    for case in range(CASES):
        opts, zero = options(rng)
        mode = rng.choice(["stdin", "stdin", "named", "files", "dash", "missing", "dashdash", "many", "dashes", "pipe"])
        group = "large" if case % 40 == 39 or (mode == "dashes" and rng.random() < 0.5) else ("records" if zero and rng.random() < 0.7 else rng.choice(["lines", "lines", "binary", "records", "crlf", "long", "empty"]))
        data = gen(rng, group)
        with open(os.path.join(WORK, "in"), "wb") as f:
            f.write(data)
        with open(os.path.join(WORK, "in2"), "wb") as f:
            f.write(gen(rng, "lines"))
        many = []
        if mode == "many":
            for j in range(rng.randint(3, 12)):
                with open(os.path.join(WORK, f"m{j}"), "wb") as f:
                    f.write(gen(rng, rng.choice(["lines", "empty", "crlf", "binary"])))
                many.append(f"m{j}")
            many.insert(rng.randint(0, len(many)), rng.choice(["in", "-", "nope"]))
        operands = {"stdin": [], "named": ["in"], "files": ["in", "in2"] + (["-"] if rng.random() < 0.3 else []),
                    "dash": ["-"], "missing": ["in", "nope"], "dashdash": ["--", "in"], "many": many,
                    "dashes": rng.choice([["-", "-"], ["-", "in2", "-"], ["-", "-", "-"]]), "pipe": rng.choice([[], ["-"]])}[mode]
        args = opts + operands
        if operands and rng.random() < 0.3:
            k = rng.randint(0, len(opts))
            args = opts[:k] + operands + opts[k:]
        if rng.random() < 0.2:
            # The obsolete form alone, before one operand, or before "--".
            shape = rng.choice(["alone", "one", "dashdash", "with"])
            one = rng.choice(["in", "-", "nope", "in2"])
            args = {"alone": [obsolete(rng)], "one": [obsolete(rng), one], "dashdash": [obsolete(rng), "--"] + ([one] if rng.random() < 0.7 else []),
                    "with": [obsolete(rng)] + args}[shape]
        mine = run([TOOL] + args, os.path.join(WORK, "in"), mode == "pipe")
        ref = run(["tail"] + args, os.path.join(WORK, "in"), mode == "pipe")
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
