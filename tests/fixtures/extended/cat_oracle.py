#!/usr/bin/env python3
"""Compare text-cat with GNU cat under LC_ALL=C, byte for byte.

usage: cat_oracle.py TEXT_CAT WORKDIR [CASES]

Each case draws a set of options (-A -b -e -E -n -s -t -T -u -v and their
long forms, abbreviated and ambiguous ones, clusters, unknown options) and
up to 13 inputs: standard input from a file or a pipe, "-" once or
repeated, named files, a missing file and a directory. GNU cat's state
carries across inputs (a line split between files is numbered once, a
blank-line run continues, a CR at one file's end meets the next file's LF
for -E), so inputs are often short and end mid-line. stdout and the exit
status must match. Input groups:

  lines     short lines, sometimes without a final LF
  blanks    runs of empty lines (for -s, -b)
  crlf      CR LF line ends, stray CRs, CR at the end
  binary    every byte value, for -v and -T
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
os.makedirs(os.path.join(WORK, "adir"), exist_ok=True)
ENV = dict(os.environ, LC_ALL="C")
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def gen(rng, group):
    if group == "lines":
        t = b"".join(bytes(rng.choice(b"abc xyz\t") for _ in range(rng.randint(0, 8))) + b"\n" for _ in range(rng.randint(0, 40)))
    elif group == "blanks":
        t = b"".join(rng.choice([b"\n", b"\n", b"\n", b"a\n", b" \n", b"\t\n", b"b"]) for _ in range(rng.randint(0, 40)))
    elif group == "crlf":
        t = b"".join(rng.choice([b"a\r\n", b"\r\n", b"\r", b"b\rc", b"\r\r\n", b"\n", b"x"]) for _ in range(rng.randint(0, 30)))
    elif group == "binary":
        t = bytes(rng.randint(0, 255) if rng.random() < 0.7 else rng.choice(b"\n\t\r") for _ in range(rng.randint(0, 600)))
    elif group == "long":
        t = b"".join(bytes([rng.choice(b"abc\t")]) * rng.randint(0, 300000) + b"\n" for _ in range(rng.randint(1, 6)))
    elif group == "empty":
        t = b""
    else:
        unit = b"".join(rng.choice([b"", b"\n", b"x" * rng.randint(0, 120) + b"\n", b"\t\x01\xff\x80 \r\n"]) for _ in range(50))
        t = unit * (rng.randint(300000, 1500000) // max(1, len(unit)))
    if t and rng.random() < 0.3:
        t = t[:-rng.randint(1, min(5, len(t)))]
    return t


FLAGS = ["-A", "-b", "-e", "-E", "-n", "-s", "-t", "-T", "-u", "-v", "--show-all", "--number-nonblank", "--show-ends",
         "--number", "--squeeze-blank", "--show-tabs", "--show-nonprinting", "--number-n", "--squ", "--show-n", "--show-t"]


def options(rng):
    opts = []
    for _ in range(rng.choice([0, 1, 1, 2, 2, 3])):
        if rng.random() < 0.3:
            opts.append("-" + "".join(rng.choice("AbeEnstTuv") for _ in range(rng.randint(2, 4))))
        else:
            opts.append(rng.choice(FLAGS))
    if rng.random() < 0.03:
        opts.append(rng.choice(["--x", "-x", "--show", "--n", "--num=3", "-5"]))
    return opts


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


GROUPS = ["lines", "lines", "blanks", "blanks", "crlf", "crlf", "binary", "long", "empty"]


def main():
    rng = random.Random(20261108)
    for case in range(CASES):
        opts = options(rng)
        mode = rng.choice(["stdin", "stdin", "named", "files", "dash", "missing", "dashdash", "many", "many", "dashes", "pipe", "dir"])
        group = "large" if case % 40 == 39 else rng.choice(GROUPS)
        data = gen(rng, group)
        with open(os.path.join(WORK, "in"), "wb") as f:
            f.write(data)
        with open(os.path.join(WORK, "in2"), "wb") as f:
            f.write(gen(rng, rng.choice(GROUPS)))
        many = []
        if mode == "many":
            for j in range(rng.randint(3, 12)):
                with open(os.path.join(WORK, f"m{j}"), "wb") as f:
                    f.write(gen(rng, rng.choice(GROUPS))[:rng.choice([3, 10, 1000])])
                many.append(f"m{j}")
            many.insert(rng.randint(0, len(many)), rng.choice(["in", "-", "nope", "adir"]))
        operands = {"stdin": [], "named": ["in"], "files": ["in", "in2"] + (["-"] if rng.random() < 0.3 else []),
                    "dash": ["-"], "missing": ["in", "nope", "in2"], "dashdash": ["--", "in"], "many": many,
                    "dashes": rng.choice([["-", "-"], ["-", "in2", "-"]]), "pipe": rng.choice([[], ["-"], ["in2", "-"]]),
                    "dir": ["in", "adir", "in2"]}[mode]
        args = opts + operands
        if operands and rng.random() < 0.3:
            k = rng.randint(0, len(opts))
            args = opts[:k] + operands + opts[k:]
        mine = run([TOOL] + args, os.path.join(WORK, "in"), mode == "pipe")
        ref = run(["cat"] + args, os.path.join(WORK, "in"), mode == "pipe")
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
