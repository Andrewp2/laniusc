#!/usr/bin/env python3
"""Compare text-tr with GNU tr under LC_ALL=C, byte for byte.

usage: tr_oracle.py TEXT_TR WORKDIR [CASES]

Each case draws random options (-c/-C, -d, -s, -t, bundled, separate or
long), zero to three SET operands from a grammar of literal bytes, escapes
(\\n \\t \\\\ \\a \\b \\f \\r \\v, octal \\ooo up to \\777, a trailing
backslash), ranges (some reversed), character classes (valid and invalid),
equivalence classes ([=c=] and invalid ones) and repeats ([c*], [c*n],
octal [c*0n], invalid counts), and an input from one of the groups below.
Both tools read the input on standard input; stdout and the exit status
must match. (Messages are not compared: GNU's quote the offending operand
or construct, which text-tr's do not.)

  text      letters, digits, punctuation, spaces and LFs
  runs      runs of repeated bytes, for -s
  binary    uniformly random bytes 0-255
  large     300 KB to 1.2 MB, so input crosses the 256 KiB read chunks
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

POOL = b"abcxyzABCXYZ0189 .,-*[]=:\\\n\t"
CLASSES = ["alpha", "upper", "lower", "digit", "space", "punct", "xdigit", "alnum", "blank", "cntrl", "graph", "print"]


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def char(rng):
    r = rng.random()
    if r < 0.55:
        return bytes([rng.choice(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,;!?")])
    if r < 0.7:
        return b"\\" + bytes([rng.choice(b"ntabfrv\\-[]")])
    if r < 0.85:
        return b"\\" + str(oct(rng.randint(0, 511))[2:]).encode()
    if r < 0.95:
        return bytes([rng.randint(1, 255)])
    return rng.choice([b"-", b"[", b"]", b"*", b":", b"="])


def element(rng, second):
    r = rng.random()
    if r < 0.45:
        return char(rng)
    if r < 0.7:
        a, b = rng.choice([(b"a", b"z"), (b"A", b"Z"), (b"0", b"9"), (b"a", b"m"), (b"n", b"z"), (b"\\000", b"\\037"), (b"\\200", b"\\377"), (b"a", b"z"), (b"z", b"a")])
        if rng.random() < 0.15:
            a, b = char(rng), char(rng)
        return a + b"-" + b
    if r < 0.82:
        if second and rng.random() < 0.8:
            name = rng.choice(["upper", "lower"])
        else:
            name = rng.choice(CLASSES) if rng.random() < 0.95 else rng.choice(["foo", "", "Alpha"])
        return b"[:" + name.encode() + b":]"
    if r < 0.88 or not second:
        c = rng.choice([b"a", b"x", b"\\n", b"a", b"x", b"[", b"\\101", b"ab", b""])
        return b"[=" + c + b"=]"
    c = rng.choice([b"a", b"x", b".", b"\\n", b"\\377"])
    n = rng.choice([b"", b"", b"3", b"010", b"0", b"12", b"3", b"", b"x", b"99999999999999999999"])
    return b"[" + c + b"*" + n + b"]"


def gen_set(rng, second):
    s = b"".join(element(rng, second) for _ in range(rng.randint(0, 4)))
    if rng.random() < 0.03:
        s += b"\\"
    return s


def gen_input(rng, group):
    if group == "text":
        t = bytes(rng.choice(POOL) for _ in range(rng.randint(0, 600)))
    elif group == "runs":
        out = bytearray()
        for _ in range(rng.randint(0, 80)):
            out += bytes([rng.choice(b"aaxyz  \n\n.0\x80\xff")]) * rng.randint(1, 9)
        t = bytes(out)
    elif group == "binary":
        t = bytes(rng.randint(0, 255) for _ in range(rng.randint(0, 700)))
    else:
        unit = bytes(rng.choice(b"abcxyzAZ09  ..\n\t\x00\x80\xff") for _ in range(rng.randint(500, 3000)))
        t = unit * (rng.randint(300000, 1200000) // len(unit))
    return t


def options(rng):
    letters = [c for c in "cdst" if rng.random() < 0.3]
    if rng.random() < 0.1 and "c" in letters:
        letters[letters.index("c")] = "C"
    if not letters:
        return []
    style = rng.randint(0, 2)
    if style == 0:
        return ["-" + "".join(letters)]
    if style == 1:
        return ["-" + c for c in letters]
    long = {"c": "--complement", "C": "-C", "d": "--delete", "s": "--squeeze-repeats", "t": "--truncate-set1"}
    return [long[c] for c in letters]


def run(cmd, data):
    return subprocess.run(cmd, input=data, capture_output=True, cwd=WORK, env=ENV, timeout=60)


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
    rng = random.Random(20261102)
    for case in range(CASES):
        group = "large" if case % 40 == 39 else rng.choice(["text", "runs", "binary", "text", "runs"])
        data = gen_input(rng, group)
        opts = options(rng)
        joined = "".join(opts)
        deleting, squeezing = "d" in joined, "s" in joined or "squeeze" in joined
        nsets = 1 if deleting and not squeezing else 2
        if squeezing and not deleting and rng.random() < 0.5:
            nsets = 1
        if rng.random() < 0.1:
            nsets = rng.choice([0, 1, 2, 3])
        sets = [gen_set(rng, i > 0) for i in range(nsets)]
        args = [o.encode() for o in opts] + sets
        if sets and rng.random() < 0.05:
            args = sets[:1] + [o.encode() for o in opts] + sets[1:]
        mine = run([TOOL.encode()] + args, data)
        ref = run([b"tr"] + args, data)
        kind = "ok" if ref.returncode == 0 else "error"
        key = f"{group}/{kind}"
        bump(key + "/cases")
        shown = repr(b" ".join(args))[:200]
        if mine.returncode != ref.returncode or mine.stdout != ref.stdout:
            fail(f"{key} {shown} rc {mine.returncode}/{ref.returncode}", data, mine.stdout, ref.stdout)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
