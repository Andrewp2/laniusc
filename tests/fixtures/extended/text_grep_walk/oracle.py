"""Bounded native consumer checks; Python/GNU grep/Git are test oracles only.

Each subprocess has a six-second deadline. Native-linked source allocation
sites use the shared exact authority verifier, not whole-process mmap counts.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ENV = dict(os.environ, LC_ALL="C.UTF-8", GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
GNU = "/usr/bin/grep"


def run(command, cwd, **kwargs):
    return subprocess.run(command, cwd=cwd, env=ENV, input=b"", capture_output=True, timeout=6, **kwargs)


def write(root, path, content):
    target = os.path.join(os.fsencode(root), os.fsencode(path))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "wb") as output:
        output.write(content)


def equal(label, actual, expected):
    assert (actual.returncode, actual.stdout, actual.stderr) == (expected.returncode, expected.stdout, expected.stderr), (label, actual, expected)


def tree(root):
    for path, content in [
        ("top.txt", b"hit top\nmiss\n"), ("top.md", b"hit markdown\n"),
        ("sub/keep.txt", b"hit child\n"), ("sub/drop.txt", b"hit excluded child\n"),
        ("sub/local.tmp", b"hit local\n"), ("sub/nested/drop.txt", b"hit nested\n"),
        ("other/drop.txt", b"hit sibling\n"), ("other/local.tmp", b"hit ignored tmp\n"),
        ("keep.tmp", b"hit reinclude\n"), ("drop.tmp", b"hit ignored\n"),
        ("blocked/hidden.txt", b"hit hidden\n"), ("empty.txt", b""),
        ("z space.txt", "hit café\r\n".encode()), (b"raw-\xff.txt", b"hit raw name\n"),
        (".gitignore", b"*.tmp\nblocked/\n!keep.tmp\n"),
        ("sub/.gitignore", b"/drop.txt\n!local.tmp\n"),
        ("sub/nested/.gitignore", b"!drop.txt\n"),
    ]:
        write(root, path, content)
    os.mkdir(root / "empty")
    os.symlink("sub", root / "directory-link")
    os.symlink("top.txt", root / "file-link")
    os.symlink("..", root / "cycle")
    os.symlink("missing", root / "dangling")
    os.mkfifo(root / "pipe")


def regular_paths(root, prefix=b""):
    """Independent DFS in host directory order, without following symlinks."""
    found = []
    with os.scandir(os.fsencode(root)) as children:
        for child in children:
            path = prefix + child.name
            if child.is_dir(follow_symlinks=False):
                if child.name != b".git":
                    found.extend(regular_paths(child.path, path + b"/"))
            elif child.is_file(follow_symlinks=False):
                found.append(path)
    return found


def compare(executable, work):
    root = work / "tree"
    tree(root)
    os.symlink("tree", work / "alias")
    cases = 0
    options = [[], ["-n"], ["-c"], ["-vc"], ["--include=*.txt"],
               ["--exclude=*.txt", "--include=*.txt"],
               ["--include=*.txt", "--exclude=drop*"],
               ["--exclude-dir=sub"], ["--exclude-dir=*blocked*", "-n"]]
    for flags in options:
        arguments = ["-r", *flags, "--", "hit"]
        equal(flags, run([executable, *arguments], root), run([GNU, "-E", *arguments], root))
        cases += 1
    for operand in ["tree", "tree/", "alias"]:
        arguments = ["-rn", "--", "hit", operand]
        equal(operand, run([executable, *arguments], work), run([GNU, "-E", *arguments], work))
        cases += 1
    for arguments in [["--", "hit", "tree/file-link"], ["-r", "--", "never", "tree"],
                      ["-r", "--exclude-dir=tree", "--", "hit", "tree"],
                      ["-r", "--", "hit", "tree/top.txt", "alias/sub"]]:
        equal(arguments, run([executable, *arguments], work), run([GNU, "-E", *arguments], work))
        cases += 1
    initialized = run(["git", "init", "-q", str(root)], work)
    assert initialized.returncode == 0, initialized
    listing = run(["git", "ls-files", "-o", "--exclude-standard", "-z"], root)
    assert listing.returncode == 0 and not listing.stderr, listing
    admitted = set(listing.stdout.split(b"\0"))
    ordered = [path for path in regular_paths(root) if path in admitted]
    assert b"sub/local.tmp" in ordered and b"other/local.tmp" not in ordered
    assert b"other/drop.txt" in ordered and b"sub/drop.txt" not in ordered
    assert b"sub/nested/drop.txt" in ordered and b"blocked/hidden.txt" not in ordered
    for flags in [[], ["-n"], ["-c"], ["--include=*.txt"], ["--exclude=*.txt", "--include=*.txt"]]:
        actual = run([executable, "-r", "--gitignore", *flags, "--", "hit"], root)
        expected = run([GNU, "-E", "-H", *flags, "--", "hit", *ordered], root)
        equal(("git", flags), actual, expected)
        cases += 1
    write(work, "second/drop.tmp", b"hit second root\n")
    actual = run([executable, "-r", "--gitignore", "--", "hit", "tree", "second"], work)
    expected = run([GNU, "-E", "-H", "--", "hit", *[b"tree/" + path for path in ordered], "second/drop.tmp"], work)
    equal("independent operand scopes", actual, expected)
    cases += 1
    # The app intentionally preserves its existing 512-open-directory cap.
    # The rejected child must not hide a file in its parent or a root sibling.
    deep = work / "deep"
    deep.mkdir()
    current = deep
    for depth in range(1, 513):
        current = current / "d"
        current.mkdir()
        if depth == 511:
            write(current, "edge.txt", b"hit edge\n")
    write(current, "hidden.txt", b"hit too deep\n")
    write(deep, "tail.txt", b"hit tail\n")
    actual = run([executable, "-r", "--", "hit", "deep"], work)
    edge = b"deep/" + b"d/" * 511 + b"edge.txt:hit edge\n"
    rejected = b"deep/" + b"d/" * 511 + b"d"
    # Sibling order comes from the filesystem, not creation order. GNU grep
    # supplies the independently observed ordering; remove only the pruned file.
    expected = run([GNU, "-E", "-r", "-H", "--", "hit", "deep"], work)
    hidden = b"deep/" + b"d/" * 512 + b"hidden.txt:hit too deep\n"
    assert expected.returncode == 0 and not expected.stderr, expected
    assert actual.returncode == 2 and actual.stdout == expected.stdout.replace(hidden, b""), actual
    assert sorted(actual.stdout.splitlines(keepends=True)) == sorted([edge, b"deep/tail.txt:hit tail\n"]), actual
    assert actual.stderr.startswith(b"text-grep: " + rejected + b": resource-limit stage=input"), actual
    cases += 1
    print(f"text-grep-walk compare={cases} byte_order=exact git_scopes=yes failures=0")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
NATIVE = load("grep_walk_source_authority", FIXTURES / "native_c/source_allocations.py")
OWNERS = load("grep_walk_source_owners", FIXTURES / "stdlib_execution/temp_file/ledger.py")
CALLS = "mmap,munmap,openat,close,read,write,getdents64,statx"


def inspect(text, profile, directory):
    assert text.endswith("\n"), "truncated recursive grep trace"
    counts, events, descriptors = Counter(), [], {}
    for line in text.splitlines():
        matched = OWNERS.LINE.fullmatch(line)
        assert matched, line
        ip, name, args, result = matched.groups()
        assert name in CALLS.split(","), line
        counts[name] += 1
        event = dict(ip=int(ip, 16), name=name, args=args, result=result,
                     ordinal=counts[name], line=line, index=len(events),
                     authority=NATIVE.classify(profile, int(ip, 16)))
        events.append(event)
        if event["authority"] != "source":
            continue
        if name == "openat" and result.split()[0].isdigit():
            parts = OWNERS.arguments(args)
            fd = int(result.split()[0])
            assert fd not in descriptors, (event, descriptors)
            parent = b"" if parts[0] == "AT_FDCWD" else descriptors[int(parts[0])]["path"] + b"/"
            event["path"] = parent + OWNERS.quoted(parts[1])
            event["directory"] = "O_DIRECTORY" in parts[2]
            descriptors[fd] = event
        elif name in ("read", "getdents64", "close"):
            fd = int(args.split(",", 1)[0])
            if fd in descriptors:
                event["owner"] = descriptors[fd]
                if name == "close":
                    # close consumes ownership even if a synthetic EIO prevents
                    # the syscall. Retrying could close a reused descriptor.
                    assert result == "0" or result.startswith("-1 EIO ") and "INJECTED" in result, event
                    del descriptors[fd]
            elif name == "close":
                raise AssertionError(("close without source owner", event))
    assert not descriptors, ("unclosed source descriptors", descriptors)
    maps = "".join(e["line"] + "\n" for e in events if e["name"] in ("mmap", "munmap"))
    OWNERS.source_maps(maps, profile, directory)
    return events


def traced(executable, work, profile, label, injection=None):
    directory = work / label
    directory.mkdir()
    trace = directory / "trace"
    command = ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx", "-s", "4096",
               "-e", "signal=none", "-e", f"trace={CALLS}", "-o", str(trace)]
    if injection:
        command += ["-e", "inject=" + injection]
    command += [executable, "-r", "--gitignore", "--", "hit", "tree"]
    result = run(command, work)
    events = inspect(trace.read_text(), profile, directory)
    marked = [e for e in events if "INJECTED" in e["result"] or "POKED" in e["result"]]
    if injection:
        assert len(marked) == 1 and marked[0]["authority"] == "source", (injection, marked)
        syscall, _, when = injection.partition(":error=")
        error, _, position = when.partition(":when=")
        assert marked[0]["name"] == syscall and marked[0]["ordinal"] == int(position), marked
        assert marked[0]["result"].startswith("-1 " + error + " "), marked
    else:
        assert not marked, marked
    return result, events


def faults(executable, work):
    for name, contents in [("tree/sub/a.txt", b"hit child\n"), ("tree/b.txt", b"hit sibling\n"),
                           ("tree/.gitignore", b"blocked/\n"), ("tree/blocked/hidden.txt", b"hit hidden\n")]:
        write(work, name, contents)
    profile = NATIVE.verified_sites(Path(executable))
    baseline, events = traced(executable, work, profile, "baseline")
    assert baseline.returncode == 0 and not baseline.stderr, baseline
    assert set(baseline.stdout.splitlines()) == {b"tree/sub/a.txt:hit child", b"tree/b.txt:hit sibling"}, baseline
    source = [e for e in events if e["authority"] == "source"]
    assert not any(e["name"] == "openat" and e.get("directory") and e.get("path", b"").endswith(b"/blocked") for e in source), "ignored directory opened"
    child_open = next(e for e in source if e["name"] == "openat" and e.get("directory") and e["path"].endswith(b"/sub"))
    root_open = next(e for e in source if e["name"] == "openat" and e.get("directory"))
    child_read = next(e for e in source if e["name"] == "getdents64" and e["owner"] == child_open)
    child_close = next(e for e in source if e["name"] == "close" and e["owner"] == child_open)
    file_read = next(e for e in source if e["name"] == "read" and e.get("owner", {}).get("path", b"").endswith(b"/a.txt"))
    rule_read = next(e for e in source if e["name"] == "read" and e.get("owner", {}).get("path", b"").endswith(b"/.gitignore"))
    metadata = next(e for e in source if e["name"] == "statx" and '\\x73\\x75\\x62"' in e["args"])
    output = next(e for e in source if e["name"] == "write" and e["args"].startswith("1,"))
    cases = 1
    for label, event, code, path in [
        ("child-open", child_open, 2, b"tree/sub"), ("child-read", child_read, 2, b"tree/sub"),
        ("child-metadata", metadata, 2, b"tree/sub"), ("file-read", file_read, 2, b"tree/sub/a.txt"),
        ("rules-read", rule_read, 2, b"tree/.gitignore"), ("child-close", child_close, 2, b"tree/sub"),
        ("output", output, 3, None),
    ]:
        actual, _ = traced(executable, work, profile, label, f'{event["name"]}:error=EIO:when={event["ordinal"]}')
        assert actual.returncode == code and b"io-failure" in actual.stderr, (label, actual)
        if path:
            assert actual.stderr.startswith(b"text-grep: " + path + b": io-failure stage=input"), (label, actual)
            assert b"tree/b.txt:hit sibling\n" in actual.stdout, (label, actual)
        else:
            assert b"stage=output" in actual.stderr and baseline.stdout.startswith(actual.stdout), actual
        if label == "child-close":
            assert actual.stdout == baseline.stdout, actual
        elif label == "rules-read":
            assert b"tree/blocked/hidden.txt:hit hidden\n" in actual.stdout, actual
        elif path:
            assert b"tree/sub/a.txt:" not in actual.stdout, (label, actual)
        cases += 1
    allocations = [e for e in source if e["name"] == "mmap"]
    selected = {allocations[0]["ordinal"]}
    for checkpoint in (root_open, child_open, file_read):
        selected.add(next(e["ordinal"] for e in allocations if e["index"] > checkpoint["index"]))
    for ordinal in sorted(selected):
        actual, _ = traced(executable, work, profile, f"oom-{ordinal}", f"mmap:error=ENOMEM:when={ordinal}")
        assert actual.returncode == 4 and b"allocation-failure" in actual.stderr, actual
        assert baseline.stdout.startswith(actual.stdout), actual
        cases += 1
    print(f"text-grep-walk faults={cases} source_owners=balanced sibling_recovery=yes failures=0")


def main():
    assert len(sys.argv) == 3 and sys.argv[2] in ("compare", "faults"), sys.argv
    executable = str(Path(sys.argv[1]).resolve())
    with tempfile.TemporaryDirectory(prefix="text-grep-walk-") as temporary:
        function = compare if sys.argv[2] == "compare" else faults
        function(executable, Path(temporary))


if __name__ == "__main__":
    main()
