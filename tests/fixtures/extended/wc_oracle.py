#!/usr/bin/env python3
"""Compare text-wc with GNU wc under LC_ALL=C, byte for byte.

usage: wc_oracle.py TEXT_WC WORKDIR [CASES]

Each case writes one to three generated files and runs both tools with the
same random options (-c -m -l -w -L, bundled or separate, long forms, or
none), comparing stdout and the exit status. Inputs reach the tools as named
files, as `-` or no name with standard input redirected from a file, as a
pipe (GNU then pads columns to 7), or as a missing file. Content groups:

  words      ASCII words, spaces and LFs, some lines without a final LF
  spaces     every whitespace byte (\\t \\n \\v \\f \\r and space) in runs
  binary     uniformly random bytes 0-255, NULs and high bytes included
  columns    tabs, printable and control bytes for -L's column rule
  empty      empty files and files of only LFs
  large      300 KB to 1.2 MB, so input crosses the 256 KiB read chunks
"""
import os
import random
import shutil
import subprocess
import sys

TOOL, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
CASES = int(sys.argv[3]) if len(sys.argv) > 3 else 600
os.makedirs(WORK, exist_ok=True)
ENV = dict(os.environ, LC_ALL="C")
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def gen(rng, group):
    if group == "words":
        out = []
        for _ in range(rng.randint(0, 60)):
            out.append(" ".join(rng.choice(["a", "bb", "ccc", "x1", "--", "é".encode().decode("latin-1")]) for _ in range(rng.randint(0, 8))) + "\n")
        t = "".join(out).encode("latin-1")
    elif group == "spaces":
        t = bytes(rng.choice(b" \t\n\v\f\rab\x00\x80") for _ in range(rng.randint(0, 400)))
    elif group == "binary":
        t = bytes(rng.randint(0, 255) for _ in range(rng.randint(0, 600)))
    elif group == "columns":
        t = bytes(rng.choice(b"\t\t abc\x01\x7f\x9f\xff\n\r\f\v") for _ in range(rng.randint(0, 500)))
    elif group == "empty":
        t = b"\n" * rng.choice([0, 0, 1, 3])
    else:
        unit = bytes(rng.choice(b"ab \t\n\x80") for _ in range(rng.randint(500, 3000)))
        t = unit * (rng.randint(300000, 1200000) // len(unit))
    if t and rng.random() < 0.2:
        t = t[:-1]
    return t


def options(rng):
    letters = [c for c in "cmlwL" if rng.random() < 0.35]
    if not letters or rng.random() < 0.2:
        return []
    style = rng.randint(0, 2)
    if style == 0:
        return ["-" + "".join(letters)]
    if style == 1:
        return ["-" + c for c in letters]
    long = {"c": "--bytes", "m": "--chars", "l": "--lines", "w": "--words", "L": "--max-line-length"}
    return [long[c] for c in letters]


def run(cmd, stdin_path=None, pipe=None):
    if pipe is not None:
        return subprocess.run(cmd, input=pipe, capture_output=True, cwd=WORK, env=ENV, timeout=60)
    if stdin_path:
        with open(stdin_path, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, cwd=WORK, env=ENV, timeout=60)
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, cwd=WORK, env=ENV, timeout=60)


def fail(msg, files, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        for name, data in files:
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
        for name, data in (("mine", mine), ("ref", ref)):
            with open(os.path.join(d, name), "wb") as f:
                f.write(data)
        print("FAIL", msg, "->", d)


GROUPS = ["words", "spaces", "binary", "columns", "empty", "words", "spaces", "binary", "columns"]


def main():
    rng = random.Random(20261101)
    for case in range(CASES):
        group = "large" if case % 40 == 39 else rng.choice(GROUPS)
        files = []
        for i in range(rng.randint(1, 3)):
            files.append((f"f{i}", gen(rng, group)))
        for name, data in files:
            with open(os.path.join(WORK, name), "wb") as f:
                f.write(data)
        opts = options(rng)
        mode = rng.choice(["named", "named", "named", "dash", "stdin", "pipe", "missing"])
        names = [n for n, _ in files]
        stdin_path = None
        pipe = None
        if mode == "dash":
            names[0] = "-"
            stdin_path = os.path.join(WORK, files[0][0])
        elif mode == "stdin":
            names = []
            stdin_path = os.path.join(WORK, files[0][0])
        elif mode == "pipe":
            names[0] = "-"
            pipe = files[0][1]
        elif mode == "missing":
            names.insert(rng.randint(0, len(names)), "no-such-file")
        mine = run([TOOL] + opts + names, stdin_path, pipe)
        ref = run(["wc"] + opts + names, stdin_path, pipe)
        key = f"{group}/{mode}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine.stdout != ref.stdout:
            fail(f"{key} {' '.join(opts + names)} rc {mine.returncode}/{ref.returncode}", files, mine.stdout, ref.stdout)
        else:
            bump(key + "/agree")
    for name in ("f0", "f1", "f2"):
        p = os.path.join(WORK, name)
        if os.path.exists(p):
            os.remove(p)
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
