#!/usr/bin/env python3
"""Compare seq-diff --word-diff/--char-diff/--stat and seq-diffstat with git.

usage: wordiff_oracle.py SEQ_DIFF SEQ_DIFFSTAT WORKDIR [PAIRS] [--strict-repeated]

Pairs (exact output bytes and exit status):
  seq-diff --word-diff A B  vs  git diff --no-index --word-diff=plain A B
  seq-diff --char-diff A B  vs  git diff --no-index --word-diff=plain --word-diff-regex=. A B
  seq-diff --stat[=W,N] A B vs  git diff --no-index --stat[=W,N] A B
Word-diff output is compared from the first hunk header on (git also prints
diff --git and index lines). seq-diff uses its port of git's xdiff for these
modes, so repeated-word pairs, character diffs and the long small-alphabet
"heuristic" pairs (edit costs above 256, where xdiff's split heuristics apply)
must agree exactly with --strict-repeated; without it only distinct-word pairs
are required and the rest are counted. WORDIFF_DUMP=1 saves a few
disagreements. Stats depend only on line counts and must agree.

Repositories (PAIRS/4 of them): several files edited, added, deleted, renamed,
mode-changed or left empty; seq-diffstat on `git diff HEAD` output vs
`git diff --stat HEAD`, with --stat=W,N,C variants, and on `diff -ruN` output
(-p 1) vs `git diff --no-renames --stat HEAD` when every change is textual.
"""
import os
import random
import shutil
import subprocess
import sys

SEQ, STAT, WORK = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
SEQ, STAT = os.path.abspath(SEQ), os.path.abspath(STAT)
COUNT = int(sys.argv[4]) if len(sys.argv) > 4 and not sys.argv[4].startswith("--") else 400
STRICT = "--strict-repeated" in sys.argv
os.makedirs(WORK, exist_ok=True)
ENV = dict(os.environ)
ENV.pop("COLUMNS", None)
ENV.update(LC_ALL="C.UTF-8", GIT_CONFIG_NOSYSTEM="1", HOME=WORK, GIT_AUTHOR_NAME="o", GIT_AUTHOR_EMAIL="o@x",
           GIT_COMMITTER_NAME="o", GIT_COMMITTER_EMAIL="o@x")
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def run(args, cwd=WORK, stdin=None):
    return subprocess.run(args, capture_output=True, timeout=60, cwd=cwd, env=ENV, input=stdin)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)


def body(out):
    at = out.find(b"\n@@ ")
    if out.startswith(b"@@ "):
        return out
    return out[at + 1:] if at >= 0 else out


class Words:
    def __init__(self, rng, distinct):
        self.rng, self.distinct, self.n = rng, distinct, 0
        self.vocab = ["the", "a", "x", "foo", "bar", "(", ")", "=", "if", "1", "é", "日本", "_v", "$s", "--"]

    def word(self):
        if self.distinct:
            self.n += 1
            stem = self.rng.choice(["w", "k", "é", "日", "Z", "_", "9", "q("])
            return f"{stem}{self.n}"
        return self.rng.choice(self.vocab)

    def gap(self):
        return self.rng.choice([" ", " ", " ", "  ", "\t", " \t"])

    def line(self):
        lead = self.rng.choice(["", "", "", "  ", "\t", "    "])
        # Distinct pairs need at least one word per line: blank lines repeat.
        k = self.rng.randint(1 if self.distinct else 0, 6)
        text = lead + self.gap().join(self.word() for _ in range(k))
        if self.rng.random() < 0.1:
            text += self.rng.choice([" ", "\t", "\r"])
        return text + "\n"

    def mutate(self, line):
        body = line[:-1]
        parts = body.split(" ")
        for _ in range(self.rng.randint(1, 3)):
            op = self.rng.randint(0, 3)
            at = self.rng.randint(0, len(parts))
            if op == 0:
                parts[at:at] = [self.word()]
            elif op == 1 and parts:
                del parts[min(at, len(parts) - 1)]
            elif op == 2 and parts:
                parts[min(at, len(parts) - 1)] = self.word()
            else:
                parts[at:at] = [""]  # whitespace change
        return " ".join(parts) + "\n"


def make_pair(rng, distinct, big=False):
    w = Words(rng, distinct)
    a = [w.line() for _ in range(rng.randint(200, 400) if big else rng.randint(0, 14))]
    b = list(a)
    for _ in range(rng.randint(60, 120) if big else rng.randint(0, 5)):
        at = rng.randint(0, len(b))
        op = rng.randint(0, 3)
        k = rng.randint(1, 12 if big else 3)
        if op == 0:
            b[at:at] = [w.line() for _ in range(k)]
        elif op == 1:
            del b[at:at + k]
        else:
            for i in range(at, min(at + k, len(b))):
                b[i] = w.mutate(b[i])
    if distinct and len(set(a)) != len(a):
        return None
    ta, tb = "".join(a).encode(), "".join(b).encode()
    if ta and rng.random() < 0.15:
        ta = ta[:-1]
    if tb and rng.random() < 0.15:
        tb = tb[:-1]
    return ta, tb


NAMES = [("a.txt", "b.txt"), ("old/x.txt", "new/x.txt"), ("d/one.txt", "d/two.txt"),
         ("src/lib/a.c", "src/lib/b.c"), ("p/q/r", "p/s/r"), ("long-name-for-stat-scaling.txt", "other.txt")]


def fail(msg, ta, tb, mine=b"", ref=b""):
    failures.append(msg)
    if len(failures) <= 5:
        d = os.path.join(WORK, f"fail{len(failures)}")
        write(os.path.join(d, "a"), ta)
        write(os.path.join(d, "b"), tb)
        write(os.path.join(d, "mine"), mine)
        write(os.path.join(d, "ref"), ref)
        print("FAIL", msg, "->", d)


def check_pair(rng, ta, tb, group):
    na, nb = rng.choice(NAMES)
    pa, pb = os.path.join(WORK, "p", na), os.path.join(WORK, "p", nb)
    shutil.rmtree(os.path.join(WORK, "p"), ignore_errors=True)
    write(pa, ta)
    write(pb, tb)
    ra, rb = os.path.join("p", na), os.path.join("p", nb)
    for mode, gargs in (("word", ["--word-diff=plain"]), ("char", ["--word-diff=plain", "--word-diff-regex=."])):
        mine = run([SEQ, "--" + mode + "-diff", ra, rb])
        ref = run(["git", "diff", "--no-index", "--no-color"] + gargs + [ra, rb])
        key = f"{mode}/{group}"
        bump(key + "/pairs")
        if mine.returncode != ref.returncode or body(mine.stdout) != body(ref.stdout):
            if group.startswith("distinct") and mode == "word" or STRICT:
                fail(f"{key} rc {mine.returncode}/{ref.returncode}", ta, tb, mine.stdout, ref.stdout)
            elif os.environ.get("WORDIFF_DUMP") and counts.get(key + "/dumped", 0) < 4:
                bump(key + "/dumped")
                d = os.path.join(WORK, f"tie-{mode}-{group}-{counts[key + '/dumped']}")
                write(os.path.join(d, "a"), ta); write(os.path.join(d, "b"), tb)
                write(os.path.join(d, "mine"), body(mine.stdout)); write(os.path.join(d, "ref"), body(ref.stdout))
        else:
            bump(key + "/agree")
    stat = []
    if rng.random() < 0.4:
        stat = [f"--stat={rng.randint(10, 120)}" + (f",{rng.randint(5, 30)}" if rng.random() < 0.4 else "")]
    else:
        stat = ["--stat"]
    mine = run([SEQ] + stat + [ra, rb])
    ref = run(["git", "diff", "--no-index", "--no-color"] + stat + [ra, rb])
    bump("stat/pairs")
    if mine.returncode != ref.returncode or mine.stdout != ref.stdout:
        fail(f"stat {stat} rc {mine.returncode}/{ref.returncode}", ta, tb, mine.stdout, ref.stdout)
    else:
        bump("stat/agree")


FILE_NAMES = ["a.txt", "b.c", "dir/c.md", "dir/sub/d.txt", "space name.txt", "é.txt", "quote\"q.txt",
              "very/long/directory/name/for/truncation/of/the/stat/column/file.txt",
              "another-really-long-file-name-that-needs-scaling-in-the-name-column.txt", "z"]


def lines_text(rng, w, n):
    return "".join(w.line() for _ in range(n)).encode()


def plain_counts(patch):
    out, cur, left = [], None, (0, 0)
    for line in patch.splitlines():
        if left[0] > 0 or left[1] > 0:
            c = line[:1]
            if c == b"-":
                cur[1] += 1
                left = (left[0] - 1, left[1])
            elif c == b"+":
                cur[0] += 1
                left = (left[0], left[1] - 1)
            elif c != b"\\":
                left = (left[0] - 1, left[1] - 1)
        elif line.startswith(b"diff "):
            cur = [0, 0]
            out.append(cur)
        elif line.startswith(b"@@ -"):
            o, n = line.split(b" ")[1:3]
            count = lambda r: int(r.split(b",")[1]) if b"," in r else 1
            left = (count(o), count(n))
    return sorted(tuple(c) for c in out)


def check_repo(rng, index):
    root = os.path.join(WORK, "r")
    shutil.rmtree(root, ignore_errors=True)
    os.makedirs(root)
    run(["git", "init", "-q"], cwd=root)
    run(["git", "config", "core.fileMode", "true"], cwd=root)
    w = Words(rng, rng.random() < 0.5)
    names = rng.sample(FILE_NAMES, rng.randint(1, len(FILE_NAMES)))
    big = rng.random() < 0.3
    only_text = index % 2 == 0
    # diff -ruN prints nothing for an empty file that is deleted, so text-only
    # repositories start with nonempty files.
    for n in names:
        write(os.path.join(root, n), lines_text(rng, w, rng.randint(1 if only_text else 0, 200 if big else 20)))
    run(["git", "add", "-A"], cwd=root)
    run(["git", "commit", "-qm", "base"], cwd=root)
    textual = True
    for n in names:
        p = os.path.join(root, n)
        op = rng.randint(0, 3 if only_text else 6)
        if op <= 2:
            with open(p, "rb") as f:
                old = f.read().decode().splitlines(True)
            for _ in range(rng.randint(1, 4)):
                at = rng.randint(0, len(old))
                k = rng.randint(1, 40 if big else 3)
                if rng.random() < 0.5:
                    old[at:at] = [w.line() for _ in range(k)]
                else:
                    del old[at:at + k]
            write(p, "".join(old).encode())
        elif op == 3:
            os.remove(p)
        elif op == 4:
            target = "moved/" + os.path.basename(n) if rng.random() < 0.5 else n + ".renamed"
            if not os.path.exists(os.path.join(root, target)):
                run(["git", "mv", n, target], cwd=root)
                textual = False
        elif op == 5:
            os.chmod(p, 0o755)
            textual = False
    if not only_text and rng.random() < 0.3:
        write(os.path.join(root, "new/empty.txt"), b"")
        textual = False
    if rng.random() < 0.5:
        write(os.path.join(root, "new/added.txt"), lines_text(rng, w, rng.randint(1, 30)))
    # Old mtimes keep index entries from being racily clean (git then lists
    # rewritten-but-equal files as "| 0" in --stat but not in the patch).
    for base, _, files in os.walk(root):
        if ".git" not in base.split(os.sep):
            for f in files:
                os.utime(os.path.join(base, f), (1000000000, 1000000000))
    run(["git", "add", "-A"], cwd=root)
    patch = run(["git", "diff", "--no-color", "HEAD"], cwd=root).stdout
    # git 2.43 prints bytes from outside the name for name widths 1-4, so those are skipped.
    variants = [[]] + [[f"--stat={rng.randint(10, 120)},{rng.choice([0] + list(range(5, 41)))},{rng.randint(0, 6)}"] for _ in range(2)]
    for v in variants:
        ref = run(["git", "diff", "--no-color", "--stat" if not v else v[0], "HEAD"], cwd=root)
        mine = run([STAT] + v, cwd=root, stdin=patch)
        bump("repo/patches")
        if mine.returncode != 0 or mine.stdout != ref.stdout:
            fail(f"repo {index} {v} rc {mine.returncode}", patch, b"", mine.stdout, ref.stdout)
        else:
            bump("repo/agree")
    if textual:
        old_tree, new_tree = os.path.join(WORK, "t", "old"), os.path.join(WORK, "t", "new")
        shutil.rmtree(os.path.join(WORK, "t"), ignore_errors=True)
        os.makedirs(old_tree)
        run(["git", "--work-tree=" + old_tree, "checkout", "HEAD", "--", "."], cwd=root)
        run(["git", "add", "-A"], cwd=root)
        shutil.copytree(root, new_tree, ignore=shutil.ignore_patterns(".git"))
        plain = run(["diff", "-ruN", "old", "new"], cwd=os.path.join(WORK, "t")).stdout
        ref = run(["git", "diff", "--no-color", "--no-renames", "--stat", "HEAD"], cwd=root)
        numstat = run(["git", "diff", "--no-color", "--no-renames", "--numstat", "HEAD"], cwd=root).stdout
        git_counts = sorted(tuple(int(v) for v in l.split(b"\t")[:2]) for l in numstat.splitlines())
        if git_counts != plain_counts(plain):
            bump("plain/gnu-alignment-differs")  # GNU diff and git found different minimal-ish scripts
            return
        mine = run([STAT, "-p", "1"], cwd=root, stdin=plain)
        bump("plain/patches")
        if mine.returncode != 0 or mine.stdout != ref.stdout:
            fail(f"plain {index} rc {mine.returncode}", plain, b"", mine.stdout, ref.stdout)
        else:
            bump("plain/agree")


def main():
    rng = random.Random(20261031)
    made = 0
    while made < COUNT:
        distinct = made % 2 == 0
        big = made % 40 >= 38
        pair = make_pair(rng, distinct, big)
        if pair is None:
            continue
        check_pair(rng, pair[0], pair[1], ("distinct" if distinct else "repeated") + ("-big" if big else ""))
        made += 1
    # Long unrelated texts over small alphabets: edit costs far above 256, so
    # xdiff's snake and cost-limit heuristics decide the split points.
    for i in range(max(2, COUNT // 50)):
        alphabet = rng.choice(["ab", "abc", "abcd ", "a b\t", "xyz é"])
        def text():
            rows = rng.randint(5, 40)
            return "".join("".join(rng.choice(alphabet) for _ in range(rng.randint(20, 200))) + "\n" for _ in range(rows)).encode()
        ta = text()
        tb = text() if i % 2 else bytes(c if rng.random() < 0.9 else ord("a") for c in ta)
        check_pair(rng, ta, tb, "heuristic")
    for i in range(max(1, COUNT // 4)):
        check_repo(rng, i)
    for key in sorted(counts):
        print(f"{key}: {counts[key]}")
    print(f"failures: {len(failures)}")
    sys.exit(1 if failures else 0)


main()
