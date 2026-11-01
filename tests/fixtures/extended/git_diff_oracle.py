#!/usr/bin/env python3
"""Compare seq-diff with plain git diff, byte for byte.

usage: git_diff_oracle.py SEQ_DIFF WORKDIR [PAIRS]

Each pair is compared on exact output bytes from the first hunk header on
(git also prints diff --git/index/---/+++ lines) and on exit status, in three
modes:

  default    seq-diff [-U N] A B              vs  git diff --no-index [-U N] A B
             (every fourth pair spells it seq-diff --xdiff)
  histogram  seq-diff --histogram [-U N] A B  vs  git diff --no-index --histogram ...
  function   seq-diff -W|--function-context [--histogram] [-U N] A B
                                              vs  git diff --no-index -W ...

git runs with an empty global configuration (no system file, HOME in the work
directory), so its defaults apply: the indent heuristic is on and hunk headers
carry function names from xdiff's default rule (a line starting with an ASCII
letter, '_' or '$'). Groups:

  distinct   all lines distinct, small random edits
  repeated   a few line values repeated (ties between equal-length runs)
  code       indented blocks, braces and blank lines; blocks inserted,
             deleted and duplicated (the indent heuristic places them)
  funcs      C-like functions separated by blank lines, with comments, long
             signature lines (over 80 bytes, trailing blanks), '_'/'$'/digit/
             non-ASCII first bytes; functions added, removed and edited
  heavy      long files over two to four line values, so every value occurs
             more than 64 times and git falls back to xdiff on the range
  mixed      unique lines among heavy repeats
  big        200-600 lines with moderate repetition and many edits
About 15% of texts lose their final newline and some are empty.
"""
import os
import random
import shutil
import subprocess
import sys

SEQ, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
COUNT = int(sys.argv[3]) if len(sys.argv) > 3 else 1200
os.makedirs(WORK, exist_ok=True)
CONFIG = os.path.join(WORK, "gitconfig")
with open(CONFIG, "w") as f:
    f.write("")
ENV = dict(os.environ)
ENV.update(LC_ALL="C", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=CONFIG, HOME=WORK, GIT_CEILING_DIRECTORIES=os.path.dirname(WORK))
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def run(args):
    return subprocess.run(args, capture_output=True, timeout=60, cwd=WORK, env=ENV)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def body(out):
    if out.startswith(b"@@ "):
        return out
    at = out.find(b"\n@@ ")
    return out[at + 1:] if at >= 0 else b""


def fail(msg, ta, tb, mine, ref):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        for name, data in (("a", ta), ("b", tb), ("mine", mine), ("ref", ref)):
            write(os.path.join(d, name), data)
        print("FAIL", msg, "->", d)


def edit(rng, lines, make, rounds, span):
    b = list(lines)
    for _ in range(rounds):
        at = rng.randint(0, len(b))
        k = rng.randint(1, span)
        op = rng.randint(0, 3)
        if op == 0:
            b[at:at] = [make() for _ in range(k)]
        elif op == 1:
            del b[at:at + k]
        elif op == 2:
            for i in range(at, min(at + k, len(b))):
                b[i] = make()
        else:
            b[at:at] = b[max(0, at - k):at]  # duplicate the run before
    return b


def finish(rng, lines):
    t = "".join(lines).encode()
    if t and rng.random() < 0.15:
        t = t[:-1]
    return t


def pair_distinct(rng):
    n = [0]
    def make():
        n[0] += 1
        return f"line {n[0]} {rng.randint(0, 999)}\n"
    a = [make() for _ in range(rng.randint(0, 14))]
    return a, edit(rng, a, make, rng.randint(0, 5), 3)


def pair_repeated(rng):
    vocab = [f"{w}\n" for w in rng.sample(["x", "y", "z", "{", "}", "", "  a", "b c", "return;", "end"], rng.randint(2, 6))]
    make = lambda: rng.choice(vocab)
    a = [make() for _ in range(rng.randint(0, 30))]
    return a, edit(rng, a, make, rng.randint(0, 6), 4)


def block(rng, depth):
    pad = "\t" * depth if rng.random() < 0.3 else "    " * depth
    out = [f"{pad}{rng.choice(['if', 'for', 'while', 'fn'])} ({rng.choice(['a', 'b', 'c'])}) {{\n"]
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.2 and depth < 3:
            out += block(rng, depth + 1)
        elif r < 0.35:
            out.append("\n")
        elif r < 0.4:
            out.append(pad + "  \n")
        else:
            out.append(f"{pad}    {rng.choice(['x', 'y', 'z'])} = {rng.randint(0, 3)};\n")
    out.append(pad + "}\n")
    if rng.random() < 0.5:
        out.append("\n")
    return out


def pair_code(rng):
    a = []
    for _ in range(rng.randint(1, 8)):
        a += block(rng, rng.randint(0, 1))
    b = list(a)
    for _ in range(rng.randint(1, 4)):
        at = rng.randint(0, len(b))
        op = rng.randint(0, 2)
        if op == 0:
            b[at:at] = block(rng, rng.randint(0, 2))
        elif op == 1:
            del b[at:at + rng.randint(1, 6)]
        else:
            j = rng.randint(0, len(b))
            b[at:at] = b[j:j + rng.randint(1, 8)]
    return a, b


def func(rng, n):
    name = rng.choice(["int", "static void", "_init", "$proc", "fn", "struct", "Type", "9lives", "\u00e9t\u00e9", "  helper", "\tinner"])
    sig = f"{name} f{n}({', '.join(rng.choice(['int a', 'char *s', 'long b']) for _ in range(rng.randint(0, 6)))})"
    if rng.random() < 0.2:
        sig += " /* " + "x" * rng.randint(20, 90) + " */"
    sig += rng.choice(["", " ", "\t", "  "]) + rng.choice(["\n", " {\n"])
    out = []
    if rng.random() < 0.3:
        out.append(f"/* f{n} */\n")
    out.append(sig)
    if not sig.endswith("{\n"):
        out.append("{\n")
    for _ in range(rng.randint(0, 6)):
        r = rng.random()
        if r < 0.15:
            out.append("\n")
        elif r < 0.2:
            out.append("label:\n")
        else:
            out.append(f"\t{rng.choice(['x', 'y', 'z'])} = {rng.randint(0, 9)};\n")
    out.append("}\n")
    for _ in range(rng.choice([0, 1, 1, 1, 2])):
        out.append(rng.choice(["\n", "\n", " \n", "\t\n"]))
    return out


def pair_funcs(rng):
    n = [0]
    def one():
        n[0] += 1
        return func(rng, n[0])
    fs = [one() for _ in range(rng.randint(0, 7))]
    a = [line for f in fs for line in f]
    gs = [list(f) for f in fs]
    for _ in range(rng.randint(1, 4)):
        op = rng.randint(0, 3)
        at = rng.randint(0, len(gs))
        if op == 0:
            gs.insert(at, one())
        elif op == 1 and gs:
            del gs[min(at, len(gs) - 1)]
        elif gs:
            g = gs[min(at, len(gs) - 1)]
            j = rng.randint(0, len(g))
            if rng.random() < 0.5:
                g[j:j] = [f"\tw = {rng.randint(0, 9)};\n" for _ in range(rng.randint(1, 3))]
            else:
                del g[j:j + rng.randint(1, 2)]
    b = [line for g in gs for line in g]
    return a, b


def pair_heavy(rng):
    vocab = [f"{w}\n" for w in rng.sample(["a", "b", "c", "", "}"], rng.randint(2, 4))]
    make = lambda: rng.choice(vocab)
    a = [make() for _ in range(rng.randint(300, 500))]
    return a, edit(rng, a, make, rng.randint(1, 20), 6)


def pair_mixed(rng):
    vocab = ["\n", "}\n", "x\n"]
    n = [0]
    def make():
        if rng.random() < 0.15:
            n[0] += 1
            return f"u{n[0]}\n"
        return rng.choice(vocab)
    a = [make() for _ in range(rng.randint(100, 300))]
    return a, edit(rng, a, make, rng.randint(1, 15), 5)


def pair_big(rng):
    vocab = [f"v{i}\n" for i in range(rng.randint(5, 60))]
    n = [0]
    def make():
        if rng.random() < 0.5:
            n[0] += 1
            return f"line {n[0]}\n"
        return rng.choice(vocab)
    a = [make() for _ in range(rng.randint(200, 600))]
    return a, edit(rng, a, make, rng.randint(10, 60), 10)


GROUPS = [("distinct", pair_distinct, 6), ("repeated", pair_repeated, 6), ("code", pair_code, 6), ("funcs", pair_funcs, 6),
          ("heavy", pair_heavy, 2), ("mixed", pair_mixed, 2), ("big", pair_big, 2)]


def compare(group, mode, args, gargs, ta, tb, pa, pb):
    mine = run([SEQ] + args + [pa, pb])
    ref = run(["git", "diff", "--no-index", "--no-color"] + gargs + [pa, pb])
    key = f"{group}/{mode}"
    bump(key + "/pairs")
    if ref.returncode == 1:
        bump(key + "/different")
    if b" @@ " in ref.stdout:
        bump(key + "/named")
    if mine.returncode != ref.returncode or body(mine.stdout) != body(ref.stdout):
        fail(f"{key} {' '.join(args)} rc {mine.returncode}/{ref.returncode}", ta, tb, body(mine.stdout), body(ref.stdout))
    else:
        bump(key + "/agree")
    return body(ref.stdout)


def check(rng, group, a, b, index):
    ta, tb = finish(rng, a), finish(rng, b)
    pa, pb = os.path.join(WORK, "p", "a"), os.path.join(WORK, "p", "b")
    write(pa, ta)
    write(pb, tb)
    ctx = []
    if rng.random() < 0.3:
        ctx = ["-U", str(rng.choice([0, 1, 2, 5, 8]))]
    gctx = ["-U" + ctx[1]] if ctx else []
    plain = compare(group, "default", (["--xdiff"] if index % 4 == 0 else []) + ctx, gctx, ta, tb, pa, pb)
    compare(group, "histogram", ["--histogram"] + ctx, ["--histogram"] + gctx, ta, tb, pa, pb)
    hist = ["--histogram"] if rng.random() < 0.3 else []
    flag = rng.choice(["-W", "--function-context"])
    wide = compare(group, "function", [flag] + hist + ctx, ["-W"] + hist + gctx, ta, tb, pa, pb)
    if not hist and wide != plain:
        bump(group + "/function/wider")


def main():
    rng = random.Random(20261101)
    made = 0
    while made < COUNT:
        for name, maker, w in GROUPS:
            for _ in range(w):
                if made >= COUNT:
                    break
                a, b = maker(rng)
                check(rng, name, a, b, made)
                made += 1
    shutil.rmtree(os.path.join(WORK, "p"), ignore_errors=True)
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
