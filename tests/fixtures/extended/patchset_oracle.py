#!/usr/bin/env python3
"""Compare seq-patch with GNU patch and git apply on generated repositories.

usage: patchset_oracle.py SEQ_PATCH WORKDIR [CASES] [SEED]

Each case builds a base tree, edits it into a target tree (modified files,
renames with and without edits, copies, mode changes, created and deleted
files, nested directories, missing final newlines) and takes the patch from
`git diff --cached -M` (sometimes -C). The patch is then applied to mutated
starting trees:
  clean      the base tree
  shifted    lines inserted or deleted away from every hunk (offsets)
  fuzzed     a context line inside a hunk changed (fuzz, git rejects)
  conflict   a line the patch deletes changed (rejects, 3-way conflicts)
  random     one to three edits anywhere
  reversed   the target tree (the patch is already applied)
  partial    the target tree for some files, the base for the others
and compared, on the resulting tree (file contents, executable bits, the set
of directories) and on the exit status, with:
  GNU patch -p1 -F2 with -t, -N, -f, -R and -R -t    vs seq-patch with the same flags
  git apply and git apply -R                          vs seq-patch --git [-R]
  git apply --3way (base committed, start staged)     vs seq-patch --3way --base-dir BASE
Binary cases add a changed binary file: GNU gets a "GIT binary patch" and
must refuse that file while applying the others; git apply gets "Binary
files differ" and must refuse the whole patch. seq-patch refuses literal
binary patches that git apply could apply; those are counted separately.
"""
import os
import random
import resource
import shutil
import subprocess
import sys

SEQ, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
COUNT = int(sys.argv[3]) if len(sys.argv) > 3 else 200
SEED = int(sys.argv[4]) if len(sys.argv) > 4 else 1
os.makedirs(WORK, exist_ok=True)
ENV = dict(os.environ, GIT_CEILING_DIRECTORIES=WORK, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1",
           GIT_AUTHOR_NAME="o", GIT_AUTHOR_EMAIL="o@o", GIT_COMMITTER_NAME="o", GIT_COMMITTER_EMAIL="o@o",
           GIT_AUTHOR_DATE="2000-01-01T00:00:00Z", GIT_COMMITTER_DATE="2000-01-01T00:00:00Z", LC_ALL="C")
ONLY = int(os.environ["ORACLE_CASE"]) if os.environ.get("ORACLE_CASE") else None
counts = {}
failures = []


def bump(key):
    counts[key] = counts.get(key, 0) + 1


def no_core():
    try:
        resource.setrlimit(resource.RLIMIT_CORE, (0, resource.getrlimit(resource.RLIMIT_CORE)[1]))
    except (ValueError, OSError):
        pass


def run(args, cwd):
    return subprocess.run(args, cwd=cwd, env=ENV, capture_output=True, stdin=subprocess.DEVNULL, timeout=60, preexec_fn=no_core)


def fresh(name):
    d = os.path.join(WORK, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    return d


def write_tree(root, files):
    for name, (data, exe) in files.items():
        p = os.path.join(root, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)
        os.chmod(p, 0o755 if exe else 0o644)


def snapshot(root):
    files, dirs = {}, []
    for base, ds, fs in os.walk(root):
        ds[:] = sorted(d for d in ds if d != ".git")
        for d in ds:
            dirs.append(os.path.relpath(os.path.join(base, d), root))
        for f in fs:
            p = os.path.join(base, f)
            with open(p, "rb") as h:
                files[os.path.relpath(p, root)] = (h.read(), os.access(p, os.X_OK))
    return files, sorted(dirs)


def lines_of(data):
    return data.decode("latin-1").splitlines(keepends=True)


def join(lines):
    return "".join(lines).encode("latin-1")


class Words:
    def __init__(self, rng):
        self.rng, self.n = rng, 0

    def __call__(self):
        self.n += 1
        if self.rng.random() < 0.15:
            return self.rng.choice(["}\n", "\n", "end\n", "return 0;\n"])
        return "line %d %s\n" % (self.n, self.rng.choice("abcdefgh"))


def edit_lines(rng, lines, pool, count):
    out = list(lines)
    for _ in range(count):
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


def make_case(rng):
    pool = Words(rng)
    dirs = ["", "", "d/", "d/e/", "src/"]
    base = {}
    for i in range(rng.randint(2, 6)):
        name = "%sf%d.txt" % (rng.choice(dirs), i)
        body = [pool() for _ in range(rng.randint(6, 50))]
        data = join(body)
        if rng.random() < 0.1:
            data = data.rstrip(b"\n")
        base[name] = (data, rng.random() < 0.2)
    target = dict(base)
    copies = False
    for name in sorted(base):
        data, exe = base[name]
        op = rng.choice(["keep", "modify", "modify", "modify", "rename", "rename-edit", "delete", "mode", "mode-edit", "copy"])
        lines = lines_of(data)
        edited = join(edit_lines(rng, lines, pool, rng.randint(1, 3)))
        if op == "modify":
            target[name] = (edited, exe)
        elif op in ("rename", "rename-edit"):
            new = "%sr_%s" % (rng.choice(dirs), os.path.basename(name))
            if new in target or new in base:
                continue
            del target[name]
            # Keep renames similar enough for -M: few edits on a long file.
            target[new] = (join(edit_lines(rng, lines, pool, 1)) if op == "rename-edit" and len(lines) > 20 else data, exe)
        elif op == "delete":
            del target[name]
        elif op == "mode":
            target[name] = (data, not exe)
        elif op == "mode-edit":
            target[name] = (edited, not exe)
        elif op == "copy" and len(lines) > 20:
            new = "%sc_%s" % (rng.choice(dirs), os.path.basename(name))
            if new in target or new in base:
                continue
            target[new] = (join(edit_lines(rng, lines, pool, 1)), exe)
            target[name] = (join(edit_lines(rng, lines, pool, 1)), exe)
            copies = True
    for i in range(rng.randint(0, 2)):
        name = "%sn%d.txt" % (rng.choice(dirs), i)
        if name not in target and name not in base:
            target[name] = (join([pool() for _ in range(rng.randint(1, 10))]), rng.random() < 0.2)
    return base, target, copies


def diff(base, target, binary_flag, copies):
    repo = fresh("repo")
    run(["git", "init", "-q"], repo)
    write_tree(repo, base)
    run(["git", "add", "-A"], repo)
    run(["git", "commit", "-qm", "base"], repo)
    run(["git", "rm", "-rq", "."], repo)
    write_tree(repo, target)
    run(["git", "add", "-A"], repo)
    args = ["git", "diff", "--cached", "-M"]
    if copies:
        args.append("-C")
    if binary_flag:
        args.append("--binary")
    return run(args, repo).stdout


def hunk_ranges(patch, name):
    """Old-side line ranges (0-based, end exclusive) of hunks for `name`."""
    ranges, current = [], None
    for line in patch.decode("latin-1").splitlines():
        if line.startswith("--- "):
            current = line[4:].split("\t")[0]
        elif line.startswith("@@ -") and current == "a/" + name:
            old = line[4:].split(" ")[0].split(",")
            start, count = int(old[0]), int(old[1]) if len(old) > 1 else 1
            ranges.append((max(start - 1, 0), start - 1 + count))
    return ranges


def hunk_lines(patch, name):
    """(kind, base line index) of each old-side line of hunks for `name`."""
    out, current, at = [], None, 0
    for line in patch.decode("latin-1").splitlines():
        if line.startswith("--- "):
            current = line[4:].split("\t")[0]
        elif line.startswith("@@ -"):
            at = max(int(line[4:].split(" ")[0].split(",")[0]) - 1, 0)
        elif current == "a/" + name and line[:1] in (" ", "-"):
            out.append((line[:1], at))
            at += 1
    return out


def mutate(rng, kind, base, target, patch):
    pool = Words(rng)
    pool.n = 100000
    if kind == "clean":
        return dict(base)
    if kind == "reversed":
        return dict(target)
    if kind == "partial":
        out = dict(base)
        for name in set(base) | set(target):
            if rng.random() < 0.5:
                out.pop(name, None)
                if name in target:
                    out[name] = target[name]
        return out
    out = dict(base)
    touched = [n for n in base if hunk_lines(patch, n)]
    if not touched:
        return out
    name = rng.choice(sorted(touched))
    data, exe = base[name]
    lines = lines_of(data)
    if kind == "shifted":
        ranges = hunk_ranges(patch, name)
        free = [i for i in range(len(lines) + 1) if all(i < a - 3 or i > b + 3 for a, b in ranges)]
        for _ in range(rng.randint(1, 3)):
            if not free:
                break
            at = rng.choice(free)
            if rng.random() < 0.5 and at < len(lines) and all(at < a - 3 or at > b + 3 for a, b in ranges):
                del lines[at]
            else:
                lines[at:at] = [pool()]
            ranges = [(a + 1, b + 1) if a > at else (a, b) for a, b in ranges]
            free = [i for i in range(len(lines) + 1) if all(i < a - 3 or i > b + 3 for a, b in ranges)]
    elif kind in ("fuzzed", "conflict"):
        want = " " if kind == "fuzzed" else "-"
        spots = [at for k, at in hunk_lines(patch, name) if k == want and at < len(lines)]
        if not spots:
            return out
        at = rng.choice(spots)
        lines[at] = pool()
    else:
        lines = edit_lines(rng, lines, pool, rng.randint(1, 3))
    out[name] = (join(lines), exe)
    return out


def compare(label, left, extra=""):
    lt, rt = left
    family = label.split(" on ")[0]
    bump("%s: reference exit %d" % (family, lt[0]))
    if lt == rt:
        bump(label + " agree")
        return
    bump(label + " DIFFER")
    if len(failures) < 12:
        failures.append("%s: %s\n  reference rc %s, seq-patch rc %s\n  reference tree %s\n  seq-patch tree %s%s" % (
            label, extra, lt[0], rt[0], short(lt[1]), short(rt[1]), ""))


def short(tree):
    files, dirs = tree
    return "{%s} dirs %s" % (", ".join("%s%s:%d" % (n, "*" if x else "", len(d)) for n, (d, x) in sorted(files.items())), dirs)


def outcome(start, args, cwd_name, setup=None):
    d = fresh(cwd_name)
    write_tree(d, start)
    if setup:
        setup(d)
    r = run(args, d)
    return (r.returncode, snapshot(d)), r


def main():
    rng = random.Random(SEED)
    pfile = os.path.join(WORK, "case.patch")
    bfile = os.path.join(WORK, "case-binary.patch")
    mfile = os.path.join(WORK, "case-marker.patch")
    kinds = ["clean", "shifted", "fuzzed", "conflict", "random", "reversed", "partial"]
    for case in range(COUNT):
        base, target, copies = make_case(rng)
        if base == target:
            continue
        kind = kinds[case % len(kinds)]
        binary = case % 11 == 5
        if binary:
            base["blob.bin"] = (bytes([0, 1, 2, 3]) + b"x" * rng.randint(1, 40), False)
            target["blob.bin"] = (bytes([0, 9, 2]) + b"y" * rng.randint(1, 40), False)
        patch = diff(base, target, False, copies)
        if not patch:
            continue
        with open(pfile, "wb") as f:
            f.write(patch)
        start = mutate(rng, kind, base, target, patch)
        if ONLY is not None:
            if case != ONLY:
                continue
            write_tree(fresh("start"), start)
            write_tree(fresh("base"), base)
        tag = kind + (" binary" if binary else "")
        bump("cases " + kind)
        gnu_patch = pfile
        if binary:
            with open(bfile, "wb") as f:
                f.write(diff(base, target, True, copies))
            gnu_patch = bfile
        for flags in (["-t"], ["-N"], ["-f"], ["-R"], ["-R", "-t"]):
            if flags[0] == "-R" and kind not in ("reversed", "partial", "clean"):
                continue
            ref, rr = outcome(start, ["patch", "-p1", "-F2", "--no-backup-if-mismatch", "-r", "-", "-i", gnu_patch] + flags, "gnu")
            got, gr = outcome(start, [SEQ, "-p1", "-F", "2", "-i", gnu_patch] + flags, "ours")
            compare("GNU patch %s on %s" % (" ".join(flags), tag), (ref, got), "case %d\n%s\n%s" % (case, rr.stdout.decode(errors="replace"), gr.stdout.decode(errors="replace")))
        for flags in ([], ["-R"]):
            if flags and kind not in ("reversed", "partial"):
                continue
            ref, rr = outcome(start, ["git", "apply"] + flags + [pfile], "gitd")
            got, gr = outcome(start, [SEQ, "--git", "-i", pfile] + flags, "ours")
            ref = (min(ref[0], 2), ref[1])
            compare("git apply %s on %s" % (" ".join(flags), tag), (ref, got), "case %d\n%s\n%s" % (case, rr.stderr.decode(errors="replace"), gr.stderr.decode(errors="replace")))
        basedir = fresh("basetree")
        write_tree(basedir, base)

        def staged(d):
            # HEAD holds the base tree (git's preimage blobs); the index and
            # work tree hold the starting tree.
            run(["git", "init", "-q"], d)
            git = ["git", "--git-dir", os.path.join(d, ".git"), "--work-tree", basedir]
            run(git + ["add", "-A"], d)
            run(git + ["commit", "-qm", "base"], d)
            run(["git", "add", "-A"], d)
        ref, rr = outcome(start, ["git", "apply", "--3way", pfile], "git3", staged)
        got, gr = outcome(start, [SEQ, "--3way", "--base-dir", basedir, "-i", pfile], "ours")
        ref = (min(ref[0], 2), ref[1])
        if any(b"<<<<<<< ours\n" in data for data, _ in ref[1][0].values()):
            bump("git apply --3way runs leaving conflict markers")
        compare("git apply --3way on %s" % tag, (ref, got), "case %d\n%s\n%s" % (case, rr.stderr.decode(errors="replace"), gr.stderr.decode(errors="replace")))
        if binary:
            # git apply can apply a literal binary patch; seq-patch refuses it, atomically.
            got, gr = outcome(start, [SEQ, "--git", "-i", bfile], "ours")
            if got[0] == 1 and got[1] == snapshot_of(start) and b"binary patches are not supported" in gr.stderr:
                bump("literal binary refused by seq-patch --git")
            else:
                bump("literal binary NOT refused")
                failures.append("literal binary case %d: rc %d %s" % (case, got[0], gr.stderr))
    for key in sorted(counts):
        print("%6d  %s" % (counts[key], key))
    for f in failures:
        print("----\n" + f)
    disagreements = sum(v for k, v in counts.items() if k.endswith("DIFFER") or k.endswith("NOT refused"))
    print("failures: %d" % disagreements)
    return 1 if failures else 0


def snapshot_of(files):
    d = fresh("snap")
    write_tree(d, files)
    return snapshot(d)


if __name__ == "__main__":
    sys.exit(main())
