#!/usr/bin/env python3
"""Independent oracles for the seq_diff / seq_patch sample programs.

usage: seqdiff_oracle.py SEQ_DIFF SEQ_PATCH WORKDIR [CASES]

1. Minimality: Myers output edit length equals an O(N*M) LCS distance.
2. Round trip: GNU patch and seq_patch applied to our diffs reproduce targets
   (Myers and patience, several context widths).
3. Interop: seq_patch applies real GNU `diff -u` / `-U0` / `-U5` output.
4. Offset and fuzz: shifted and context-edited bases agree with GNU patch -F2
   on output bytes and on the set of rejected hunks.
Prints exact counts; exits nonzero on the first disagreement.
"""
import os
import random
import re
import subprocess
import sys

SEQ_DIFF, SEQ_PATCH, WORK = sys.argv[1], sys.argv[2], sys.argv[3]
CASES = int(sys.argv[4]) if len(sys.argv) > 4 else 300
os.makedirs(WORK, exist_ok=True)
A, B, P, O = (os.path.join(WORK, n) for n in ("a.txt", "b.txt", "p.diff", "out.txt"))
counts = {}


def bump(key, n=1):
    counts[key] = counts.get(key, 0) + n


def run(args, stdin=None):
    return subprocess.run(args, capture_output=True, timeout=60)


def lines(data):
    return data.splitlines(keepends=True)


def lcs_distance(a, b):
    a, b = lines(a), lines(b)
    prev = [0] * (len(b) + 1)
    for x in a:
        cur = [0]
        for j, y in enumerate(b):
            cur.append(prev[j] + 1 if x == y else max(prev[j + 1], cur[j]))
        prev = cur
    return len(a) + len(b) - 2 * prev[-1]


def body_edits(diff):
    out = lines(diff)[2:]
    return sum(1 for l in out if l[:1] in (b"-", b"+"))


DICTS = [
    [b"a\n", b"b\n", b"c\n", b"\n"],
    [b"alpha\n", b"beta\n", b"gamma\n", b"delta\n", b"{\n", b"}\n", b"\treturn 0;\n"],
    [b"x\n", b"y\n", b"x y\n", b"--- x\n", b"+++ y\n", b"@@ -1 +1 @@\n", b"\\ z\n", b" lead\n"],
    [b"\0\xff\n", b"q\r\n", b"q\n", b"\xc3\xa9\n", b"  \n"],
]


def gen_pair(rng):
    d = rng.choice(DICTS)
    n = rng.choice([0, 1, 2, 5, 10, 30, 80, 200])
    a = [rng.choice(d) for _ in range(n)]
    b = list(a)
    for _ in range(rng.randint(0, 6)):
        op = rng.randint(0, 2)
        at = rng.randint(0, len(b))
        k = rng.randint(1, 4)
        if op == 0:
            b[at:at] = [rng.choice(d) for _ in range(k)]
        elif op == 1:
            del b[at:at + k]
        else:
            b[at:at + k] = [rng.choice(d) for _ in range(k)]
    a, b = b"".join(a), b"".join(b)
    if a and rng.random() < 0.2:
        a = a[:-1]
    if b and rng.random() < 0.2:
        b = b[:-1]
    if rng.random() < 0.05:
        a = b""
    return a, b


def write(path, data):
    with open(path, "wb") as f:
        f.write(data)


def read(path):
    with open(path, "rb") as f:
        return f.read()


def fail(msg, a, b, extra=b""):
    write(os.path.join(WORK, "fail_a.txt"), a)
    write(os.path.join(WORK, "fail_b.txt"), b)
    write(os.path.join(WORK, "fail_extra"), extra)
    print("FAIL:", msg, counts)
    sys.exit(1)


def gnu_patch(base, patch, fuzz=2):
    if os.path.exists(O):
        os.remove(O)
    r = run(["patch", "-f", "-F", str(fuzz), "--no-backup-if-mismatch",
             "-r", os.path.join(WORK, "rej"), "-o", O, base, patch])
    out = read(O) if os.path.exists(O) else None
    failed = sorted(int(m) for m in re.findall(rb"Hunk #(\d+) FAILED", r.stdout + r.stderr))
    return r.returncode, out, failed


def ours_patch(base, patch, fuzz=2):
    r = run([SEQ_PATCH, "-F", str(fuzz), base, patch])
    failed = sorted(int(m) for m in re.findall(rb"Hunk #(\d+) FAILED", r.stderr))
    return r.returncode, r.stdout, failed


def roundtrip(a, b, extra_args, label):
    write(A, a)
    write(B, b)
    r = run([SEQ_DIFF] + extra_args + [A, B])
    if r.returncode != (0 if a == b else 1):
        fail(label + " exit status %d" % r.returncode, a, b, r.stderr)
    diff = r.stdout
    write(P, diff)
    if a == b:
        if diff:
            fail(label + " identical but output", a, b, diff)
        bump(label + " identical")
        return None
    rc, out, _ = gnu_patch(A, P, 0)
    if rc != 0 or out != b:
        fail(label + " GNU patch did not reproduce target", a, b, diff)
    bump(label + " GNU patch reproduced")
    rc, out, _ = ours_patch(A, P, 0)
    if rc != 0 or out != b:
        fail(label + " seq_patch did not reproduce target", a, b, diff)
    bump(label + " seq_patch reproduced")
    return body_edits(diff)


def main():
    rng = random.Random(20261031)
    for case in range(CASES):
        a, b = gen_pair(rng)
        best = lcs_distance(a, b)
        got = roundtrip(a, b, [], "myers -U3")
        if got is not None:
            if got != best:
                fail("myers edit length %d != LCS distance %d" % (got, best), a, b)
            bump("myers minimal (== O(NM) LCS)")
        ctx = rng.choice(["0", "1", "5"])
        got = roundtrip(a, b, ["-U", ctx], "myers -U" + ctx)
        if got is not None and got != best:
            fail("myers -U%s not minimal" % ctx, a, b)
        got = roundtrip(a, b, ["--patience"], "patience -U3")
        if got is not None:
            if got < best:
                fail("patience shorter than LCS bound", a, b)
            bump("patience valid (>= LCS bound)")
            if got == best:
                bump("patience also minimal")
        # Real GNU diff output.
        if a != b:
            for flag in ("-u", "-U0", "-U5"):
                g = run(["diff", "-a", flag, A, B]).stdout
                write(P, g)
                rc, out, _ = ours_patch(A, P, 0)
                if rc != 0 or out != b:
                    fail("seq_patch on GNU diff " + flag, a, b, g)
                bump("GNU diff %s applied by seq_patch" % flag)
    fuzz_cases(rng)
    scale_cases(rng)
    for k in sorted(counts):
        print("%6d  %s" % (counts[k], k))
    print("OK")


def uniq_lines(rng, tag, n):
    return [b"%s line %d %d\n" % (tag, i, rng.randint(0, 10 ** 6)) for i in range(n)]


def fuzz_cases(rng):
    """Shift and edit bases so hunks need offset or fuzz; compare with GNU."""
    for case in range(max(40, CASES // 3)):
        a = uniq_lines(rng, b"base", rng.randint(20, 80))
        b = list(a)
        for _ in range(rng.randint(1, 4)):
            at = rng.randint(0, len(b) - 1)
            b[at:at + 1] = uniq_lines(rng, b"new", rng.randint(0, 2))
        write(A, b"".join(a))
        write(B, b"".join(b))
        diff = run([SEQ_DIFF, A, B]).stdout
        if not diff:
            continue
        write(P, diff)
        base = list(a)
        mode = rng.randint(0, 3)
        if mode in (0, 2):  # offset: unrelated lines at the top
            base[0:0] = uniq_lines(rng, b"pre", rng.randint(1, 7))
        if mode in (1, 2):  # fuzz: edit lines next to changes
            for _ in range(rng.randint(1, 3)):
                at = rng.randint(0, len(base) - 1)
                base[at] = b"edited %d\n" % rng.randint(0, 10 ** 6)
        if mode == 3:  # conflict: delete a block
            at = rng.randint(0, len(base) - 5)
            del base[at:at + 5]
        write(A, b"".join(base))
        for fuzz in (0, 2):
            grc, gout, gfail = gnu_patch(A, P, fuzz)
            orc, oout, ofail = ours_patch(A, P, fuzz)
            if gfail != ofail:
                fail("reject sets differ GNU %r ours %r (fuzz %d)" % (gfail, ofail, fuzz), b"".join(base), b"".join(b), diff)
            if (grc == 0) != (orc == 0):
                fail("exit status differs", b"".join(base), b"".join(b), diff)
            if gout != oout:
                fail("output differs from GNU patch -F%d" % fuzz, b"".join(base), b"".join(b), diff)
            bump("offset/fuzz F%d agrees with GNU patch (output+rejects)" % fuzz)
            if ofail:
                bump("offset/fuzz F%d cases with rejected hunks" % fuzz)
            if orc == 0 and oout == b"".join(b):
                bump("offset/fuzz F%d reproduced target" % fuzz)


def scale_cases(rng):
    """Large files: edit length equals GNU `diff --minimal`, round trip holds."""
    for n, edits in ((2000, 40), (20000, 200), (100000, 300)):
        a = uniq_lines(rng, b"s", n)
        a = [l if rng.random() < 0.7 else b"common\n" for l in a]
        b = list(a)
        for _ in range(edits):
            at = rng.randint(0, len(b) - 1)
            b[at:at + rng.randint(0, 3)] = uniq_lines(rng, b"t", rng.randint(0, 3))
        a, b = b"".join(a), b"".join(b)
        write(A, a)
        write(B, b)
        for args, label in (([], "myers"), (["--patience"], "patience")):
            r = run([SEQ_DIFF] + args + [A, B])
            write(P, r.stdout)
            rc, out, _ = ours_patch(A, P, 0)
            if r.returncode != 1 or rc != 0 or out != b:
                fail("scale %d %s round trip" % (n, label), a, b, r.stdout)
            got = body_edits(r.stdout)
            gnu = body_edits(run(["diff", "-a", "--minimal", "-u", A, B]).stdout)
            if label == "myers" and got != gnu:
                fail("scale %d edit length %d != GNU --minimal %d" % (n, got, gnu), a, b)
            if label == "patience" and got < gnu:
                fail("scale patience below minimum", a, b)
            bump("scale %d-line %s round trip (edit length %d, GNU --minimal %d)" % (n, label, got, gnu))
        if n == 2000:
            if body_edits(run([SEQ_DIFF, A, B]).stdout) != lcs_distance(a, b):
                fail("scale 2000 LCS", a, b)
            bump("scale 2000-line myers == O(NM) LCS")


if __name__ == "__main__":
    main()
