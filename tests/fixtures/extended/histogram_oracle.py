#!/usr/bin/env python3
"""Compare seq-diff --histogram with git diff --histogram.

usage: histogram_oracle.py SEQ_DIFF WORKDIR [PAIRS]

Each pair is compared on exact output bytes from the first hunk header on
(git also prints diff --git/index/---/+++ lines) and on exit status:

  seq-diff --histogram [-U N] A B  vs  git diff --no-index --histogram [-U N] A B

git runs with its default indent heuristic pinned on and with hunk-header
function names switched off (a global attributes file maps every path to a
diff driver whose xfuncname never matches), since seq-diff prints bare
`@@ ... @@` headers. Groups:

  distinct   all lines distinct, small random edits
  repeated   a few line values repeated (ties between equal-length runs)
  code       indented blocks, braces and blank lines; blocks inserted,
             deleted and duplicated (the indent heuristic places them)
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
ATTRS = os.path.join(WORK, "attributes")
CONFIG = os.path.join(WORK, "gitconfig")
with open(ATTRS, "w") as f:
    f.write("* diff=nofunc\n")
with open(CONFIG, "w") as f:
    f.write(f'[core]\n\tattributesFile = {ATTRS}\n[diff "nofunc"]\n\txfuncname = "^NO-FUNCNAME-PATTERN-MATCHES-THIS-LINE$"\n')
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


GROUPS = [("distinct", pair_distinct, 6), ("repeated", pair_repeated, 6), ("code", pair_code, 6),
          ("heavy", pair_heavy, 2), ("mixed", pair_mixed, 2), ("big", pair_big, 2)]


def check(rng, group, a, b):
    ta, tb = finish(rng, a), finish(rng, b)
    pa, pb = os.path.join(WORK, "p", "a"), os.path.join(WORK, "p", "b")
    write(pa, ta)
    write(pb, tb)
    ctx = []
    if rng.random() < 0.3:
        ctx = ["-U", str(rng.choice([0, 1, 2, 5, 8]))]
    mine = run([SEQ, "--histogram"] + ctx + [pa, pb])
    gctx = ["-U" + ctx[1]] if ctx else []
    ref = run(["git", "-c", "diff.indentHeuristic=true", "diff", "--no-index", "--no-color", "--histogram"] + gctx + [pa, pb])
    bump(group + "/pairs")
    if ref.returncode == 1:
        bump(group + "/different")
    if mine.returncode != ref.returncode or body(mine.stdout) != body(ref.stdout):
        fail(f"{group} {' '.join(ctx)} rc {mine.returncode}/{ref.returncode}", ta, tb, body(mine.stdout), body(ref.stdout))
    else:
        bump(group + "/agree")


def main():
    rng = random.Random(20261101)
    made = 0
    while made < COUNT:
        for name, maker, w in GROUPS:
            for _ in range(w):
                if made >= COUNT:
                    break
                a, b = maker(rng)
                check(rng, name, a, b)
                made += 1
    shutil.rmtree(os.path.join(WORK, "p"), ignore_errors=True)
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
