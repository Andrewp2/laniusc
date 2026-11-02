#!/usr/bin/env python3
"""Compare text-tee with GNU tee under LC_ALL=C.

usage: tee_oracle.py TEXT_TEE WORKDIR [CASES]

Each case runs both tools in twin directories set up the same way, with
options -a/--append, -i/--ignore-interrupts, -p and --output-error with
every mode, prefixes, empty, ambiguous and invalid values (and unknown
options), and up to 13 outputs: new files, files with earlier contents
(overwritten, or kept for -a), "-" (a file named "-"), the same file twice,
a file in a missing directory and /dev/full (a failing write: warn modes go
on, exit modes stop at the first block). Input is standard input from a
file or a pipe: empty, lines without a final LF, CRLF, binary bytes, 300 KB
lines, and 300 KB to 1.5 MB. stdout, the exit status and every output
file (present or not, and its bytes) must match.
"""
import os
import random
import shutil
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
    elif group == "crlf":
        t = b"".join(bytes(rng.choice(b"ab \r") for _ in range(rng.randint(0, 8))) + b"\r\n" for _ in range(rng.randint(0, 30)))
    elif group == "binary":
        t = bytes(rng.randint(0, 255) for _ in range(rng.randint(0, 600)))
    elif group == "long":
        t = b"".join(bytes([rng.choice(b"abc")]) * rng.randint(0, 300000) + b"\n" for _ in range(rng.randint(1, 4)))
    elif group == "empty":
        t = b""
    else:
        unit = b"".join(b"x" * rng.randint(0, 120) + b"\n" for _ in range(50))
        t = unit * (rng.randint(300000, 1500000) // max(1, len(unit)))
    if t and rng.random() < 0.3:
        t = t[:-rng.randint(1, min(5, len(t)))]
    return t


MODES = ["warn", "warn-nopipe", "exit", "exit-nopipe", "w", "warn-", "e", "exit-", "x", "", "warn-nopip"]


def options(rng):
    opts = []
    for _ in range(rng.choice([0, 0, 1, 1, 2, 3])):
        r = rng.random()
        if r < 0.25:
            opts.append(rng.choice(["-a", "--append", "--app"]))
        elif r < 0.4:
            opts.append(rng.choice(["-i", "--ignore-interrupts", "--ig", "-ai", "-ia"]))
        elif r < 0.55:
            opts.append(rng.choice(["-p", "-pa", "-ap"]))
        else:
            opts.append(rng.choice(["--output-error", "--output-error=" + rng.choice(MODES), "--output=" + rng.choice(MODES), "--o"]))
    if rng.random() < 0.03:
        opts.append(rng.choice(["--x", "-x", "-5", "--output-error", "-o"]))
    return opts


def setup(d, rng_state, outputs, old):
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for name, blob in old.items():
        with open(os.path.join(d, name), "wb") as f:
            f.write(blob)


def run(cmd, d, stdin_path, pipe):
    with open(stdin_path, "rb") as f:
        if pipe:
            return subprocess.run(cmd, input=f.read(), capture_output=True, cwd=d, env=ENV, timeout=60)
        return subprocess.run(cmd, stdin=f, capture_output=True, cwd=d, env=ENV, timeout=60)


def files(d):
    out = {}
    for name in sorted(os.listdir(d)):
        with open(os.path.join(d, name), "rb") as f:
            out[name] = f.read()
    return out


def fail(msg, data):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "input"), "wb") as f:
            f.write(data)
        print("FAIL", msg, "->", d)


def main():
    rng = random.Random(20261109)
    a, b = os.path.join(WORK, "mine"), os.path.join(WORK, "ref")
    for case in range(CASES):
        opts = options(rng)
        group = "large" if case % 40 == 39 else rng.choice(["lines", "lines", "crlf", "binary", "long", "empty"])
        data = gen(rng, group)
        src = os.path.join(WORK, "input")
        with open(src, "wb") as f:
            f.write(data)
        outputs = []
        old = {}
        for j in range(rng.choice([0, 1, 1, 2, 3, rng.randint(4, 12)])):
            kind = rng.random()
            if kind < 0.55:
                outputs.append(f"o{j}")
            elif kind < 0.7:
                outputs.append(f"o{j}")
                old[f"o{j}"] = gen(rng, "lines")
            elif kind < 0.75:
                outputs.append("-")
            elif kind < 0.82 and outputs:
                outputs.append(rng.choice(outputs))
            elif kind < 0.9:
                outputs.append("nodir/x")
            else:
                outputs.append("/dev/full")
        args = opts + outputs
        if outputs and rng.random() < 0.2:
            k = rng.randint(0, len(opts))
            args = opts[:k] + ["--"] + outputs if rng.random() < 0.5 else opts[:k] + outputs + opts[k:]
        # A pipe delivers blocks of any size, so the bytes written before an
        # exit-mode failure are only fixed for a file on standard input.
        pipe = "/dev/full" not in outputs and rng.random() < 0.3
        setup(a, None, outputs, old)
        setup(b, None, outputs, old)
        mine = run([TOOL] + args, a, src, pipe)
        ref = run(["tee"] + args, b, src, pipe)
        mode = "full" if "/dev/full" in outputs else ("pipe" if pipe else "file")
        key = f"{group}/{mode}/{'ok' if ref.returncode == 0 else 'error'}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine.stdout != ref.stdout or files(a) != files(b):
            fail(f"{key} {' '.join(args)[:200]!r} rc {mine.returncode}/{ref.returncode} stdout {mine.stdout == ref.stdout} files {files(a) == files(b)}", data)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
