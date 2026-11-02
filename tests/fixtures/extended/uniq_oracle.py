#!/usr/bin/env python3
"""Compare text-uniq with GNU uniq under LC_ALL=C, byte for byte.

usage: uniq_oracle.py TEXT_UNIQ WORKDIR [CASES]

Each case draws any of -c, -d, -u, -i, -z, -f N, -s N, -w N (short,
bundled, attached or separate, long and abbreviated long forms, the
obsolete -N and +N forms, invalid numbers now and then) and runs both tools
on the same input: standard input, a named INPUT, INPUT and OUTPUT (the
OUTPUT file's bytes are compared), "--" before operands, a missing input or
an extra operand. stdout (or OUTPUT) and the exit status must match.
Content groups:

  dups      few distinct lines in runs, so groups are long
  case      lines differing only in letter case, for -i
  fields    blank-separated fields with shared tails, for -f, -s, -w
  binary    random bytes with NULs and high bytes, no final line end
  records   NUL-terminated records for -z
  large     300 KB to 1.2 MB, so groups cross the 256 KiB read chunks
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


def lines_of(rng, pool, n, eol=b"\n"):
    out = []
    for _ in range(n):
        out += [rng.choice(pool)] * rng.choice([1, 1, 1, 2, 3, 7])
    return eol.join(out) + (eol if out else b"")


def gen(rng, group):
    if group == "dups":
        t = lines_of(rng, [b"a", b"b", b"", b"abc", b"a ", b"  x"], rng.randint(0, 40))
    elif group == "case":
        t = lines_of(rng, [b"abc", b"ABC", b"aBc", b"abd", b"Abd", b"@[`{", b"`{@["], rng.randint(0, 40))
    elif group == "fields":
        pool = [bytes(rng.choice(b"ab \t") for _ in range(rng.randint(0, 6))) + b" tail" + bytes([rng.choice(b"xy")]) for _ in range(6)]
        t = lines_of(rng, pool, rng.randint(0, 40))
    elif group == "binary":
        t = bytes(rng.choice(b"aab\n\n\x00\x80\xff \t") for _ in range(rng.randint(0, 300)))
    elif group == "records":
        t = lines_of(rng, [b"a", b"a\nb", b"", b"x y", b"A"], rng.randint(0, 30), b"\x00")
    else:
        pool = [b"line %d" % rng.randint(0, 5) for _ in range(6)] + [b"x" * rng.randint(1000, 300000)]
        t = lines_of(rng, pool, rng.randint(200, 3000))
        while len(t) < 300000:
            t += t
        t = t[:rng.randint(300000, 1200000)]
    if t and rng.random() < 0.25:
        t = t[:-1]
    return t


def num(rng):
    r = rng.random()
    if r < 0.85:
        return str(rng.randint(0, 6))
    return rng.choice(["", "x", "-1", " 3", "+2", "99999999999999999999999", "3k", "007"])


def options(rng):
    opts = []
    letters = [c for c in "cdui" if rng.random() < 0.3]
    if letters:
        if rng.random() < 0.5:
            opts.append("-" + "".join(letters))
        else:
            long = {"c": ["--count", "--co"], "d": ["--repeated", "--rep"], "u": ["--unique", "--un"], "i": ["--ignore-case", "--ig"]}
            opts += [rng.choice(long[c]) for c in letters]
    for letter, long in (("f", "--skip-fields"), ("s", "--skip-chars"), ("w", "--check-chars")):
        if rng.random() < 0.2:
            n = num(rng)
            style = rng.randint(0, 3)
            if style == 0:
                opts += ["-" + letter, n]
            elif style == 1:
                opts += ["-" + letter + n] if n else ["-" + letter, n]
            elif style == 2:
                opts += [long + "=" + n]
            else:
                opts += [long[:rng.randint(5, len(long))], n]
    if rng.random() < 0.08:
        opts.append("-" + str(rng.randint(0, 12)))
    zero = rng.random() < 0.1
    if zero:
        opts.append(rng.choice(["-z", "--zero-terminated", "--z"]))
    if rng.random() < 0.03:
        opts.append(rng.choice(["--x", "-q", "--c"]))
    return opts, zero


def run(cmd, stdin_path=None):
    if stdin_path:
        with open(stdin_path, "rb") as f:
            return subprocess.run(cmd, stdin=f, capture_output=True, cwd=WORK, env=ENV, timeout=60)
    return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, cwd=WORK, env=ENV, timeout=60)


def fail(msg, data, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        os.makedirs(d, exist_ok=True)
        for name, blob in (("input", data), ("mine", mine), ("ref", ref)):
            with open(os.path.join(d, name), "wb") as f:
                f.write(blob)
        print("FAIL", msg, "->", d)


def output_of(result, path):
    if path and os.path.exists(path):
        with open(path, "rb") as f:
            data = f.read()
        os.remove(path)
        return result.stdout + b"<file>" + data
    return result.stdout


def main():
    rng = random.Random(20261104)
    for case in range(CASES):
        opts, zero = options(rng)
        group = "large" if case % 40 == 39 else ("records" if zero and rng.random() < 0.7 else rng.choice(["dups", "case", "fields", "binary", "dups"]))
        data = gen(rng, group)
        with open(os.path.join(WORK, "in"), "wb") as f:
            f.write(data)
        mode = rng.choice(["stdin", "stdin", "named", "named", "output", "dashdash", "skip", "missing", "extra"])
        stdin_path = None
        operands = []
        out_path = None
        if mode == "stdin":
            stdin_path = os.path.join(WORK, "in")
        elif mode == "named":
            operands = ["in"]
        elif mode == "output":
            operands = ["in", "out"]
            out_path = os.path.join(WORK, "out")
        elif mode == "dashdash":
            operands = ["--", "in"]
        elif mode == "skip":
            operands = ["+" + str(rng.randint(0, 3)), "in"]
        elif mode == "missing":
            operands = ["no-such-file"]
        else:
            operands = ["in", "out2", "out3"]
        args = opts + operands
        if mode in ("named", "skip") and rng.random() < 0.3:
            args = operands + opts
        mine = run([TOOL] + args, stdin_path)
        mine_out = output_of(mine, out_path)
        ref = run(["uniq"] + args, stdin_path)
        ref_out = output_of(ref, out_path)
        for extra in ("out2", "out3"):
            p = os.path.join(WORK, extra)
            if os.path.exists(p):
                os.remove(p)
        key = f"{group}/{mode}/{'ok' if ref.returncode == 0 else 'error'}"
        bump(key + "/cases")
        if mine.returncode != ref.returncode or mine_out != ref_out:
            fail(f"{key} {' '.join(args)[:200]} rc {mine.returncode}/{ref.returncode}", data, mine_out, ref_out)
        else:
            bump(key + "/agree")
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
