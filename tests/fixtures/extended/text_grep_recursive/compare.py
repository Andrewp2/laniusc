"""text_grep -r against GNU grep -r.

    python3 -I compare.py TEXT_GREP tree ROOT [--exclude-dir D ...]
    python3 -I compare.py TEXT_GREP generated [--seed N] [--count N] [--work DIR]

`tree` runs a fixed list of patterns and option sets over the directory ROOT
with both programs (GNU grep 3.11 as /usr/bin/grep -E, en_US.UTF-8) and
compares stdout bytes, exit status and the stderr lines without the program
name ("PATH: binary file matches"). `generated` builds random trees under
DIR (nested directories, symbolic links, NUL and invalid-UTF-8 files,
.gitignore files) and compares -r with every option set; with --gitignore it
compares against GNU grep over the files `git ls-files -o --exclude-standard`
lists, as sorted lines. Prints agree/total per surface and `disagreements N`.
"""
import argparse, os, random, shutil, subprocess, sys, time

GNU = "/usr/bin/grep"
ENV = dict(os.environ, LC_ALL="en_US.UTF-8")
PATTERNS = ["fn main", "the", r"\bmatch\b", "TODO|FIXME", "zzzz_never", "é"]
OPTION_SETS = [[], ["-n"], ["-c"], ["-v", "-c"], ["--include=*.lani"], ["--include=*.md", "-n"], ["--exclude=*.rs", "--exclude=*.md", "-c"],
               ["--exclude=*.lani", "--include=*.lani"], ["--include=*.py", "--exclude=test_*"], ["--exclude-dir=tests", "-c"], ["--exclude-dir=*e*", "-n"]]
TREE_OPTION_SETS = [[], ["-n"], ["-c"], ["-v", "-c"], ["--include=*.md", "-n"], ["--exclude-dir=tests", "--exclude=*.rs", "-c"]]


def run(cmd, cwd):
    start = time.perf_counter()
    out = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, timeout=280)
    return out.returncode, out.stdout, out.stderr, time.perf_counter() - start


def messages(stderr, program):
    """stderr lines without the program name: "PATH: binary file matches"."""
    prefix = program.encode() + b": "
    return [l[len(prefix):] if l.startswith(prefix) else l for l in stderr.splitlines()]


def first_difference(a, b):
    al, bl = a.split(b"\n"), b.split(b"\n")
    for i, (x, y) in enumerate(zip(al, bl)):
        if x != y: return f"line {i + 1}: {x[:120]!r} vs GNU {y[:120]!r}"
    return f"lengths {len(al)} vs GNU {len(bl)} lines"


def tree(args):
    extra = [f"--exclude-dir={d}" for d in args.exclude_dir]
    bad = 0; total = 0; ours = theirs = 0.0
    for options in TREE_OPTION_SETS:
        for pattern in PATTERNS:
            total += 1
            a = run([args.text_grep, "-r", *extra, *options, "--", pattern, "."], args.root)
            b = run([GNU, "-r", "-E", *extra, *options, "--", pattern, "."], args.root)
            ours += a[3]; theirs += b[3]
            if a[0] != b[0] or a[1] != b[1] or messages(a[2], "text-grep") != messages(b[2], GNU):
                bad += 1
                print(f"  DIFF {options} {pattern!r}: status {a[0]} vs GNU {b[0]}; {first_difference(a[1], b[1])}")
                if a[2]: print("   ours stderr:", a[2][:300])
    print(f"tree {total - bad}/{total} (text_grep {ours:.1f} s, GNU {theirs:.1f} s)")
    return bad


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f: f.write(data)


WORDS = [b"alpha", b"beta", b"gamma", b"main", b"the", b"fn main()", b"x", b"", b"\xc3\xa9t\xc3\xa9", b"TODO", b"1234", b"  indent", b"#hash"]
NAMES = ["a", "b", "src", "lib", "main.c", "x.txt", "y.md", ".hidden", "build", "target", "notes.lani", "z z", "doc.md", "k.py"]
IGNORE_LINES = ["*.md", "build/", "/target", "!keep.md", "x.txt", "src/*.c", "**/lib", "lib/**", "a/**/b", "#comment", "", "\\#hash", "*.py ",
                ".hidden", "!/b", "z\\ z", "*", "!*.lani", "sub/", "[ab]", "?.txt", "/src/main.c"]


def generate_tree(rng, root):
    shutil.rmtree(root, ignore_errors=True); os.makedirs(root)
    dirs = [""]
    for _ in range(rng.randint(3, 25)):
        parent = rng.choice(dirs); name = rng.choice(NAMES); path = os.path.join(parent, name)
        if os.path.lexists(os.path.join(root, path)) or (parent and not os.path.isdir(os.path.join(root, parent))): continue
        kind = rng.random()
        if kind < 0.3:
            os.makedirs(os.path.join(root, path)); dirs.append(path)
        elif kind < 0.8:
            # Some files are long (many selected lines, so output of earlier
            # files fills the output area mid-file); NULs and invalid bytes
            # then land anywhere, not only near the start. Invalid bytes
            # follow a space: next to an encoding error GNU grep's ^, $ and
            # \b differ from text_grep's (see extended-text-grep.md).
            dense = rng.random() < 0.25
            count = rng.randint(100, 900) if dense else rng.randint(0, 12)
            lines = [b" ".join(rng.choice(WORDS) for _ in range(rng.randint(0, 6 if dense else 4))) for _ in range(count)]
            if dense:
                for _ in range(rng.choice([0, 0, 1, 3])):
                    at = rng.randrange(len(lines)); lines[at] = lines[at] + rng.choice([b" \xff", b" \xc3", b" \xe6\x97", b" \xe9t\xe9 the"])
                if rng.random() < 0.15:
                    at = rng.randrange(len(lines)); lines[at] = lines[at][:2] + b"\0" + lines[at][2:]
            data = b"\n".join(lines) + (b"\n" if rng.random() < 0.8 else b"")
            if rng.random() < 0.08: data = data[:3] + b"\0" + data[3:]
            if rng.random() < 0.08: data = data + b"\xe9 the\n"
            if rng.random() < 0.05: data = data.replace(b"\n", b"\r\n")
            write(os.path.join(root, path), data)
        elif kind < 0.9:
            target = rng.choice([".", "..", "x.txt", "missing", "a"])
            os.symlink(target, os.path.join(root, path))
        else:
            lines = [rng.choice(IGNORE_LINES) for _ in range(rng.randint(1, 5))]
            write(os.path.join(root, parent, ".gitignore"), "\n".join(lines).encode() + b"\n")
    return root


def generated(args):
    ignoring = 0
    rng = random.Random(args.seed); work = os.path.abspath(args.work); bad = {"recursive": 0, "gitignore": 0}; total = {"recursive": 0, "gitignore": 0}
    genv = dict(ENV, HOME=work, XDG_CONFIG_HOME=work, GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
    for case in range(args.count):
        root = generate_tree(rng, os.path.join(work, "tree"))
        pattern = rng.choice(["the", "main", "^#", "x", "é", r"\bbeta\b", "zzz", "a|b", ""])
        options = rng.choice(OPTION_SETS[:9] + [["--exclude-dir=lib"], ["--exclude-dir=s*", "-c"], ["--include=*.txt", "--include=*.c"]])
        total["recursive"] += 1
        a = run([args.text_grep, "-r", *options, "--", pattern], root)
        b = run([GNU, "-r", "-E", *options, "--", pattern], root)
        if a[0] != b[0] or a[1] != b[1] or messages(a[2], "text-grep") != messages(b[2], GNU):
            bad["recursive"] += 1
            if bad["recursive"] <= 5: print(f"  DIFF recursive case {case} {options} {pattern!r}: status {a[0]} vs {b[0]}; {first_difference(a[1], b[1])}\n   ours stderr {a[2][:200]!r}")
        # --gitignore against git's own listing of the files it does not ignore.
        if rng.random() < 0.6:
            total["gitignore"] += 1
            if rng.random() < 0.7:
                lines = [rng.choice(IGNORE_LINES) for _ in range(rng.randint(2, 6))]
                with open(os.path.join(root, ".gitignore"), "ab") as f: f.write("\n".join(lines).encode() + b"\n")
            subprocess.run(["git", "init", "-q", root], env=genv, check=True, capture_output=True)
            listed = subprocess.run(["git", "ls-files", "-o", "--exclude-standard", "-z"], cwd=root, env=genv, capture_output=True, check=True).stdout
            files = sorted(f for f in listed.decode("utf-8", "surrogateescape").split("\0") if f and not os.path.islink(os.path.join(root, f)))
            regular = sum(1 for d, _, fs in os.walk(root) if ".git" not in os.path.relpath(d, root).split(os.sep) for f in fs if os.path.isfile(os.path.join(d, f)) and not os.path.islink(os.path.join(d, f)))
            if regular > len(files): ignoring += 1
            flags = rng.choice([[], ["-n"], ["-c"]])
            a = run([args.text_grep, "-r", "--gitignore", *flags, "--", pattern], root)
            if files:
                b = run([GNU, "-H", "-E", *flags, "--", pattern, *files], root)
            else:
                b = (1, b"", b"", 0.0)
            if sorted(a[1].splitlines()) != sorted(b[1].splitlines()) or a[0] != b[0]:
                bad["gitignore"] += 1
                if bad["gitignore"] <= 5:
                    print(f"  DIFF gitignore case {case} {flags} {pattern!r}: status {a[0]} vs {b[0]}")
                    print("   ours", sorted(a[1].splitlines())[:8]); print("   git ", sorted(b[1].splitlines())[:8])
                    for d, _, fs in os.walk(root):
                        if ".git" in d.split(os.sep): continue
                        if ".gitignore" in fs: print("   ", os.path.relpath(os.path.join(d, ".gitignore"), root), open(os.path.join(d, ".gitignore")).read().split("\n"))
    for k in total: print(f"{k} {total[k] - bad[k]}/{total[k]}" + (f" ({ignoring} trees where git ignores a file)" if k == "gitignore" else ""))
    return sum(bad.values())


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("text_grep"); sub = ap.add_subparsers(dest="mode", required=True)
    t = sub.add_parser("tree"); t.add_argument("root"); t.add_argument("--exclude-dir", action="append", default=[])
    g = sub.add_parser("generated"); g.add_argument("--seed", type=int, default=20261101); g.add_argument("--count", type=int, default=200); g.add_argument("--work", default="target/claude-work/s3/rtree")
    args = ap.parse_args(); args.text_grep = os.path.abspath(args.text_grep)
    bad = tree(args) if args.mode == "tree" else generated(args)
    print(f"disagreements {bad}"); sys.exit(1 if bad else 0)


main()
