#!/usr/bin/env python3
"""Compare seq-merge with `git merge-file` and GNU `diff3 -m` on generated triples.

usage: merge3_oracle.py SEQ_MERGE WORKDIR [TRIPLES] [--strict-repeated]

Each triple has a base and two sides edited independently, sometimes with the
same edit on both. Four comparisons per triple, each on exact output bytes and
on clean/conflicted status:
  seq-merge            vs git merge-file -p            (merge markers, zealous-alnum)
  seq-merge --diff3    vs git merge-file -p --diff3    (base section, eager)
  seq-merge --gnu      vs diff3 -m                     (GNU identical-change form)
plus independent properties: a side equal to the base yields the other side,
and clean merges contain no markers.
Distinct-line triples must agree exactly. Repeated-line triples can admit
several minimal diffs; their agreement is counted and, with --strict-repeated,
required.
"""
import os
import random
import subprocess
import sys

SEQ, WORK = sys.argv[1], sys.argv[2]
COUNT = int(sys.argv[3]) if len(sys.argv) > 3 and not sys.argv[3].startswith("--") else 400
STRICT = "--strict-repeated" in sys.argv
os.makedirs(WORK, exist_ok=True)
O, A, B = (os.path.join(WORK, n) for n in ("base", "ours", "theirs"))
counts = {}
LABELS = ["-L", "ours", "-L", "base", "-L", "theirs"]


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def run(args):
    return subprocess.run(args, capture_output=True, timeout=60)


def write(path, data):
    with open(path, "wb") as f:
        f.write(data)


def edit(rng, lines, pool):
    out = list(lines)
    for _ in range(rng.randint(0, 4)):
        at = rng.randint(0, len(out))
        op = rng.randint(0, 2)
        k = rng.randint(1, 3)
        if op == 0:
            out[at:at] = [pool() for _ in range(k)]
        elif op == 1:
            del out[at:at + k]
        else:
            out[at:at + k] = [pool() for _ in range(k)]
    return out


def triple(rng, distinct):
    serial = [0]
    if distinct:
        def pool():
            serial[0] += 1
            return b"line %d %d\n" % (serial[0], rng.randint(0, 10 ** 6))
        base = [pool() for _ in range(rng.choice([0, 1, 3, 8, 20, 50]))]
    else:
        words = rng.choice([[b"a\n", b"b\n", b"c\n"], [b"x\n", b"{\n", b"}\n", b"\n", b"  return;\n", b"y\n"]])
        def pool():
            return rng.choice(words)
        base = [pool() for _ in range(rng.choice([0, 1, 3, 8, 20, 50]))]
    ours = edit(rng, base, pool)
    theirs = edit(rng, base, pool)
    if rng.random() < 0.25 and base:  # same change on both sides
        at = rng.randint(0, len(base) - 1)
        shared = [pool() for _ in range(rng.randint(0, 2))]
        ours = ours[:]
        if at < len(ours):
            ours[at:at + 1] = shared
        if at < len(theirs):
            theirs[at:at + 1] = shared
    if rng.random() < 0.15:
        ours = list(base)
    return b"".join(base), b"".join(ours), b"".join(theirs)


def compare(label, ours_args, tool_args, group, o, a, b):
    mine = run([SEQ] + ours_args + LABELS + [A, O, B])
    ref = run(tool_args)
    if mine.returncode not in (0, 1):
        fail("%s: seq-merge failed %r" % (label, mine.stderr), o, a, b)
    same_status = (mine.returncode == 0) == (ref.returncode == 0)
    if mine.stdout == ref.stdout and same_status:
        bump("%s %s: identical output and status" % (group, label))
        if mine.returncode == 1:
            bump("%s %s: ... of which conflicted" % (group, label))
        return
    bump("%s %s: DIFFERENT" % (group, label))
    if group == "distinct" or STRICT:
        fail("%s output differs" % label, o, a, b, mine.stdout, ref.stdout)


def fail(msg, o, a, b, mine=b"", ref=b""):
    for name, data in (("fail_base", o), ("fail_ours", a), ("fail_theirs", b), ("fail_mine", mine), ("fail_ref", ref)):
        write(os.path.join(WORK, name), data)
    print("FAIL:", msg)
    report()
    sys.exit(1)


def report():
    for k in sorted(counts):
        print("%6d  %s" % (counts[k], k))


def main():
    rng = random.Random(20261031)
    for case in range(COUNT):
        group = "distinct" if case % 2 == 0 else "repeated"
        o, a, b = triple(rng, group == "distinct")
        write(O, o)
        write(A, a)
        write(B, b)
        compare("git merge-file", [], ["git", "merge-file", "-p"] + LABELS + [A, O, B], group, o, a, b)
        compare("git merge-file --diff3", ["--diff3"], ["git", "merge-file", "-p", "--diff3"] + LABELS + [A, O, B], group, o, a, b)
        compare("diff3 -m", ["--gnu"], ["diff3", "-m"] + LABELS + [A, O, B], group, o, a, b)
        # Independent properties.
        r = run([SEQ] + LABELS + [A, O, B])
        if a == o and (r.returncode != 0 or r.stdout != b):
            fail("ours == base must yield theirs", o, a, b, r.stdout)
        if b == o and (r.returncode != 0 or r.stdout != a):
            fail("theirs == base must yield ours", o, a, b, r.stdout)
        if r.returncode == 0 and b"<<<<<<<" in r.stdout and b"<<<<<<<" not in a + b + o:
            fail("clean merge contains markers", o, a, b, r.stdout)
        bump("%s properties hold" % group)
    report()
    print("OK")


if __name__ == "__main__":
    main()
