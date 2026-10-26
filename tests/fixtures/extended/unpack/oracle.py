"""Independent real-program checks for bounded content-only unpack.

Uses the existing independent TAR/ZIP builders and verified raw-ELF source
mapping authority read-only. No compiler or production hooks are introduced.
"""
import ast
from collections import Counter
import importlib.util
import io
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
SOURCE_DIR = HERE.parent / "archive_source"
sys.path.insert(0, str(SOURCE_DIR))
_spec = importlib.util.spec_from_file_location("unpack_independent_archive_builders", SOURCE_DIR / "oracle.py")
SOURCE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(SOURCE)
TRUSTED = SOURCE.ledger.TRUSTED
TRACE = TRUSTED.TRACE
BINARY = b"\0\xff\x80a\r\n"
DEFAULT_FLAGS = [
    "--input-bytes", "1048576", "--entries", "32", "--nodes", "64",
    "--path-storage-bytes", "65536", "--source-owned-bytes", "1048576",
    "--run-owned-bytes", "2097152", "--program-owned-bytes", "8388608",
]
LIMIT_FLAGS = (
    "input-bytes input-reads entries nodes depth path-bytes component-bytes "
    "path-storage-bytes entry-bytes decoded-bytes plan-work zip-work metadata-work "
    "source-owned-bytes run-owned-bytes program-owned-bytes host-calls cleanup-calls "
    "write-calls sync-calls entropy-calls name-attempts steps report-bytes report-writes"
).split()


def flags(overrides=None):
    values = dict(zip(DEFAULT_FLAGS[::2], DEFAULT_FLAGS[1::2]))
    values.update({"--" + key: str(value) for key, value in (overrides or {}).items()})
    return [part for pair in values.items() for part in pair]


def archive(entries, fmt):
    return SOURCE.tar_archive(entries) if fmt == "tar" else SOURCE.zip_raw(entries)


def member(name, data=b"", directory=False, **meta):
    return SOURCE.manifest(name, data, directory, **meta)


def report(data):
    """ASCII key=value rows, rejecting duplicate fields or unescaped raw bytes."""
    assert not data or data.endswith(b"\n"), "unfinished report row"
    text = data.decode("ascii")
    rows = []
    for line in text.splitlines():
        fields = line.split(" ")
        assert fields[0] in ("unpack", "node", "current", "failure", "caller", "recovery", "release"), line
        values = {}
        for field in fields[1:]:
            assert field.count("=") == 1, line
            key, value = field.split("=")
            assert key and key not in values, line
            assert value == "" or re.fullmatch(r"[-a-zA-Z0-9]+", value), line
            values[key] = value
        rows.append((fields[0], values))
    return rows


def one(result, label, **selectors):
    rows = [row for kind, row in result["rows"] if kind == label
            and all(row.get(key) == str(value) for key, value in selectors.items())]
    assert len(rows) == 1, (label, selectors, result["rows"])
    return rows[0]


def raw_events(text):
    entries, counts = [], Counter()
    assert not text or text.endswith("\n"), "unfinished syscall trace"
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in TRUSTED.CALLS, ("unsupported trace", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        entries.append(dict(ip=int(ip, 16), name=name, args=TRUSTED.arguments(args),
                            result=result, ordinal=counts[name], index=index, line=line))
    return entries


def resources(text, profile, directory):
    entries = raw_events(text)
    # Diagnostic stderr is product output, never an implicit phase channel.
    maps = "".join(item["line"] + "\n" for item in entries if item["name"] in ("mmap", "munmap"))
    source = TRUSTED.source_maps(maps, profile, directory)
    live, generation, owners = {}, Counter(), []
    for item in entries:
        name, args, answer = item["name"], item["args"], item["result"].split()[0]
        if name == "openat" and answer.isdecimal():
            fd = int(answer)
            assert fd not in live, ("fd already owned", live, item)
            generation[fd] += 1
            live[fd] = dict(fd=fd, generation=generation[fd], open=item, close=None)
            owners.append(live[fd])
        elif name == "fcntl" and len(args) >= 2 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC") and answer.isdecimal():
            fd, parent = int(answer), int(args[0])
            assert parent in live and fd not in live, (live, item)
            generation[fd] += 1
            live[fd] = dict(fd=fd, generation=generation[fd], open=item, close=None)
            owners.append(live[fd])
        elif name == "close":
            fd = int(args[0])
            assert fd in live and answer == "0", ("unowned/failed close", live, item)
            live.pop(fd)["close"] = item
    assert not live, ("native descriptors survived explicit release", live)
    return dict(events=entries, owners=owners, source=source)


def tree(root):
    result = {}
    for base, dirs, files in os.walk(os.fsencode(root)):
        for name in dirs + files:
            path = os.path.join(base, name)
            info = os.lstat(path)
            relative = os.path.relpath(path, os.fsencode(root))
            assert stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode), path
            result[relative] = ("dir" if stat.S_ISDIR(info.st_mode) else "file",
                                stat.S_IMODE(info.st_mode),
                                Path(os.fsdecode(path)).read_bytes() if stat.S_ISREG(info.st_mode) else b"")
    return result


def expected(entries):
    rows, _ = SOURCE.namespace(entries)
    data = {entry["name"].rstrip(b"/"): entry["data"] for entry in entries if not entry["directory"]}
    return {row["path"]: ("dir", 0o700, b"") if row["kind"] == 1
            else ("file", 0o600, data[row["path"]]) for row in rows}


class Cases:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="unpack-" + group + "-"))
        self.profile = TRUSTED.verified_sites(self.executable, self.directory)
        self.count = 0

    def run(self, name, entries=None, fmt="tar", overrides=None, code=0,
            arguments=None, payload=None, setup=None, closed_report=False,
            injection=None):
        self.count += 1
        folder = self.directory / (f"{self.count:02d}-" + name)
        folder.mkdir()
        root = folder / "out"
        root.mkdir(mode=0o700)
        data = archive(entries or [], fmt) if payload is None else payload
        (folder / "archive").write_bytes(data)
        if setup:
            setup(folder, root)
        args = ["--format", fmt, "--root", "out"] + flags(overrides) + ["--", "archive"]
        if arguments is not None:
            args = arguments
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
                   "-e", "signal=none",
                   "-e", "trace=" + TRACE, "-o", str(folder / "syscalls.log"),
                   ]
        if injection is not None:
            assert injection["syscall"] == "read" and injection["when"] > 0
            assert ("error" in injection) != ("retval" in injection), injection
            action = "error=" + injection["error"] if "error" in injection else "retval=" + str(injection["retval"])
            command += ["-e", "inject=read:" + action + ":when=" + str(injection["when"])]
        command += ["--", str(self.executable)] + args
        (folder / "command.txt").write_text(repr(command))
        read_fd = write_fd = None
        try:
            if closed_report:
                read_fd, write_fd = os.pipe()
                os.close(read_fd)
                read_fd = None
                process = subprocess.run(command, cwd=folder, input=b"", stdout=write_fd,
                                         stderr=subprocess.PIPE, timeout=15)
                stdout = b""
            else:
                process = subprocess.run(command, cwd=folder, input=b"", capture_output=True, timeout=15)
                stdout = process.stdout
            (folder / "stdout").write_bytes(stdout)
            (folder / "stderr").write_bytes(process.stderr)
            (folder / "status").write_text(str(process.returncode))
            assert process.returncode == code, ("exit", code, process.returncode, folder, stdout, process.stderr)
            ledger = resources((folder / "syscalls.log").read_text(), self.profile, folder)
            TRUSTED.check_injections(ledger, [injection] if injection is not None else [])
            rows = [] if stdout.startswith(b"Usage: unpack ") else report(stdout + process.stderr)
            result = dict(directory=folder, root=root, rows=rows,
                          stdout=stdout, stderr=process.stderr, ledger=ledger, data=data)
            return result
        except BaseException as error:
            (folder / "failure.txt").write_text(repr(error))
            raise AssertionError(f"unpack evidence retained at {folder}: {error!r}") from error
        finally:
            if write_fd is not None:
                os.close(write_fd)

    def finish(self, group):
        print(f"PASS unpack group={group} process-cases={self.count}")
        shutil.rmtree(self.directory)


def successful(result, entries):
    assert not result["stderr"], result["stderr"]
    assert tree(result["root"]) == expected(entries), tree(result["root"])
    summary = one(result, "unpack")
    assert summary["code"] == "0" and summary["state"] == "2", summary
    assert int(summary["entries_completed"]) == len(entries), summary
    assert summary["resources_remaining"] == summary["cleanup_errors"] == "0", summary
    release = one(result, "release")
    assert release == {"destroyed": "1", "resources_remaining": "0"}, release
    planned, _ = SOURCE.namespace(entries)
    nodes = [row for kind, row in result["rows"] if kind == "node"]
    assert len(nodes) == len(planned), nodes
    by_path = {bytes.fromhex(row["path_hex"]): row for row in nodes}
    assert len(by_path) == len(nodes) and set(by_path) == {row["path"] for row in planned}
    for row in planned:
        actual = by_path[row["path"]]
        assert int(actual["index"]) == planned.index(row) and int(actual["ordinal"]) == row["ordinal"]
        assert actual["status_available"] == "1" and actual["visited"] == ("1" if row["kind"] == 1 else "0"), actual
        if row["kind"] == 0:
            assert actual["published"] == actual["file_attempted"] == actual["file_synced"] == actual["directory_synced"] == "1", actual
            assert actual["visibility"] == "1" and actual["temporary_owned"] == actual["retained"] == "0", actual
    events = result["ledger"]["events"]
    opened = [owner for owner in result["ledger"]["owners"]
              if owner["open"]["name"] == "openat" and TRUSTED.quoted(owner["open"]["args"][1]) == b"archive"]
    assert len(opened) == 1 and opened[0]["close"], opened
    input_owner = opened[0]
    opts = input_owner["open"]["args"][2]
    assert "O_NOFOLLOW" in opts and "O_NONBLOCK" in opts, input_owner
    mutating = [item for item in events if item["name"] in ("mkdirat", "getrandom", "renameat2", "unlinkat")
                or (item["name"] == "openat" and "O_CREAT" in item["args"][2])]
    assert all(item["index"] > input_owner["close"]["index"] for item in mutating), mutating
    reads = [item for item in events if item["name"] == "read" and int(item["args"][0]) == input_owner["fd"]
             and input_owner["open"]["index"] < item["index"] < input_owner["close"]["index"]]
    assert len(reads) == int(summary["input_reads"]) and reads[-1]["result"] == "0", (summary, reads)


def no_mutation(result):
    assert tree(result["root"]) == {}, tree(result["root"])
    assert not any(item["name"] in ("mkdirat", "getrandom", "renameat2", "unlinkat")
                   or (item["name"] == "openat" and "O_CREAT" in item["args"][2])
                   for item in result["ledger"]["events"]), result["ledger"]


def trees(cases):
    for fmt in ("tar", "zip"):
        entries = [member(b"parent/first", BINARY), member(b"parent/", directory=True),
                   member(b"other/deep/empty"), member(b"standalone", bytes(range(256)) * 9)]
        result = cases.run(fmt + "-tree", entries, fmt)
        successful(result, entries)
        successful(cases.run(fmt + "-empty", [], fmt), [])
        raw = [member(b"raw-\xff/line\n=tail", BINARY)]
        successful(cases.run(fmt + "-raw-byte-path", raw, fmt), raw)
    entries = [member(b"first", b"new"), member(b"blocked", b"overwrite"), member(b"later", b"unreached")]
    def existing(folder, root):
        (root / "blocked").write_bytes(b"original")
    result = cases.run("partial-no-replace", entries, setup=existing, code=5)
    assert (result["root"] / "first").read_bytes() == b"new"
    assert (result["root"] / "blocked").read_bytes() == b"original"
    assert not (result["root"] / "later").exists()
    rows = {bytes.fromhex(row["path_hex"]): row for kind, row in result["rows"] if kind == "node"}
    assert rows[b"first"]["published"] == "1" and rows[b"blocked"]["published"] == rows[b"later"]["published"] == "0", rows
    assert one(result, "failure", kind="execution")["present"] == "1"
    assert one(result, "release")["destroyed"] == "1"


def arguments(cases):
    result = cases.run("help", arguments=["--help"])
    # Help uses a separate static surface, so it is deliberately not parsed as
    # structured result rows (handled in Cases.run before that parser).
    assert result["stdout"].startswith(b"Usage: unpack ") and b"NoReplace" in result["stdout"]
    for name in LIMIT_FLAGS:
        assert ("--" + name).encode() in result["stdout"], name
    assert not any(item["name"] == "openat" for item in result["ledger"]["events"])
    valid = ["--format", "tar", "--root", "out"]
    invalid = [[], ["--help", "extra"], valid + ["archive"], valid + ["--"],
               valid + ["--", "archive", "extra"], valid + ["--", ""],
               ["--format", "rar", "--root", "out", "--", "archive"],
               ["--format", "tar", "--root", "", "--", "archive"],
               valid + ["--unknown", "1", "--", "archive"],
               valid + ["--format", "tar", "--", "archive"],
               valid + ["--root", "out", "--", "archive"],
               valid + ["--input-bytes=10", "--", "archive"],
               valid + ["--entries", "-1", "--", "archive"],
               valid + ["--entries", "+1", "--", "archive"],
               valid + ["--entries", "18446744073709551616", "--", "archive"],
               valid + ["--entries", "2147483648", "--", "archive"],
               valid + ["--depth", "1x", "--", "archive"],
               valid + ["--input-reads", "1", "--input-reads", "2", "--", "archive"]]
    invalid.extend([["argument"] * 129, ["a" * 90000] * 3])
    for index, args in enumerate(invalid):
        result = cases.run(f"arguments-{index}", arguments=args, code=2)
        no_mutation(result)
        assert not any(item["name"] == "openat" for item in result["ledger"]["events"])
    for label, setup in [
        ("symlink", lambda folder, root: ((folder / "archive").unlink(), (folder / "archive").symlink_to("target"))),
        ("fifo", lambda folder, root: ((folder / "archive").unlink(), os.mkfifo(folder / "archive"))),
        ("directory", lambda folder, root: ((folder / "archive").unlink(), (folder / "archive").mkdir())),
    ]:
        result = cases.run("input-" + label, setup=setup, code=3)
        no_mutation(result)
        assert not any(item["name"] == "read" for item in result["ledger"]["events"]), result["ledger"]
    result = cases.run("root-symlink", setup=lambda folder, root: (root.rename(folder / "real"), root.symlink_to("real")), code=3)
    assert tree(result["directory"] / "real") == {}
    no_mutation(result)
    no_mutation(cases.run("root-missing", setup=lambda folder, root: root.rmdir(), code=3))
    result = cases.run("root-regular", setup=lambda folder, root: (root.rmdir(), root.write_bytes(b"existing")), code=3)
    no_mutation(result)
    assert result["root"].read_bytes() == b"existing"


def bounds(cases):
    entries = [member(b"one", BINARY)]
    data = archive(entries, "tar")
    successful(cases.run("input-exact-cap", entries, overrides={"input-bytes": len(data)}), entries)
    result = cases.run("input-cap-overflow", entries, overrides={"input-bytes": len(data) - 1}, code=2)
    no_mutation(result)
    reads = [event for event in result["ledger"]["events"] if event["name"] == "read"]
    assert reads[-1]["args"][2] == "1" and reads[-1]["result"] == "1", reads
    required_reads = (len(data) + 1023) // 1024 + 1
    successful(cases.run("input-exact-read-budget", entries, overrides={"input-reads": required_reads}), entries)
    no_mutation(cases.run("input-read-budget", entries, overrides={"input-reads": required_reads - 1}, code=2))
    no_mutation(cases.run("input-zero-read-budget", entries, overrides={"input-reads": 0}, code=2))
    for label, values in [
        ("entries", {"entries": 0}), ("nodes", {"nodes": 0}), ("depth", {"depth": 0}),
        ("path", {"path-bytes": 2}), ("component", {"component-bytes": 2}),
        ("stored-paths", {"path-storage-bytes": 2}), ("entry", {"entry-bytes": 5}),
        ("total", {"decoded-bytes": 5}), ("plan-work", {"plan-work": 0}),
        ("metadata-work", {"metadata-work": 0}), ("source-owner", {"source-owned-bytes": 1}),
        ("whole-program-owner", {"program-owned-bytes": 1}),
    ]:
        no_mutation(cases.run(label + "-limit", entries, overrides=values, code=2))
    for label, values in [
        ("run-owner", {"run-owned-bytes": 1}), ("host", {"host-calls": 0}),
        ("cleanup", {"cleanup-calls": 0}), ("steps", {"steps": 0}),
    ]:
        no_mutation(cases.run(label + "-limit", entries, overrides=values, code=5))
    no_mutation(cases.run("invalid-archive", payload=b"invalid", code=2))
    no_mutation(cases.run("traversal", [member(b"../escape", b"bad")], code=2))
    no_mutation(cases.run("late-duplicate", [member(b"one", b"first"), member(b"one", b"second")], code=2))
    no_mutation(cases.run("late-file-parent-conflict", [member(b"one", b"first"), member(b"one/two", b"second")], code=2))
    no_mutation(cases.run("zip-work-limit", entries, fmt="zip", overrides={"zip-work": 0}, code=2))
    for key in ("sync-calls", "entropy-calls", "name-attempts"):
        no_mutation(cases.run(key + "-limit", entries, overrides={key: 0}, code=5))
    result = cases.run("write-calls-limit", entries, overrides={"write-calls": 0}, code=5)
    assert tree(result["root"]) == {}
    summary = one(result, "unpack")
    assert summary["bytes"] == summary["writes"] == "0", summary
    assert any(event["name"] == "getrandom" for event in result["ledger"]["events"])
    assert any(event["name"] == "unlinkat" for event in result["ledger"]["events"])


def reports(cases):
    entries = [member(b"published", BINARY)]
    for key in ("report-bytes", "report-writes"):
        result = cases.run(key + "-zero", entries, overrides={key: 0}, code=7)
        assert tree(result["root"]) == expected(entries)
        assert result["stdout"] == b""
    result = cases.run("report-closed-pipe", entries, closed_report=True, code=7)
    assert tree(result["root"]) == expected(entries)
    assert any(event["name"] == "write" and event["result"].startswith("-1 EPIPE")
               for event in result["ledger"]["events"]), result["ledger"]
    # Reporting is secondary to an already known execution failure.
    def existing(folder, root):
        (root / "published").write_bytes(b"original")
    result = cases.run("primary-survives-report-failure", entries,
                       overrides={"report-bytes": 0}, setup=existing, code=5)
    assert (result["root"] / "published").read_bytes() == b"original"
    successful(cases.run("raw-diagnostic-path", [member(b"a\nkey=value\xff", BINARY)]), [member(b"a\nkey=value\xff", BINARY)])


def input_reads(result):
    """Bind reads to the actual archive generation, after its regular-file check."""
    owners = [owner for owner in result["ledger"]["owners"]
              if owner["open"]["name"] == "openat"
              and TRUSTED.quoted(owner["open"]["args"][1]) == b"archive"]
    assert len(owners) == 1 and owners[0]["close"], owners
    owner = owners[0]
    reads = [item for item in result["ledger"]["events"] if item["name"] == "read"
             and item["args"][0] == str(owner["fd"])
             and owner["open"]["index"] < item["index"] < owner["close"]["index"]]
    assert reads, ("no causal archive reads", owner)
    metadata = [item for item in result["ledger"]["events"] if item["name"] == "statx"
                and item["args"][0] == str(owner["fd"]) and item["result"] == "0"
                and owner["open"]["index"] < item["index"] < reads[0]["index"]]
    assert len(metadata) == 1, ("archive read did not follow successful metadata", metadata, reads)
    return owner, reads


def injected_read(result, baseline, rule):
    owner, reads = input_reads(result)
    marked = [item for item in result["ledger"]["events"]
              if "INJECTED" in item["result"] or "POKED" in item["result"]]
    assert len(marked) == 1 and marked[0] is reads[0], (marked, reads)
    item = marked[0]
    assert item["ordinal"] == baseline["ordinal"] == rule["when"], (item, baseline, rule)
    assert item["ip"] == baseline["ip"] and item["args"][0] == baseline["args"][0] == str(owner["fd"]), (item, baseline)
    assert item["args"][2] == baseline["args"][2] == "1024", (item, baseline)
    if "error" in rule:
        assert item["result"].split()[:2] == ["-1", rule["error"]], item
    else:
        assert item["result"].split()[0] == str(rule["retval"]), item
    return reads


def input_faults(cases):
    entries = [member(b"read-prefix", BINARY)]
    baseline = cases.run("read-calibration", entries)
    successful(baseline, entries)
    owner, baseline_reads = input_reads(baseline)
    target = baseline_reads[0]
    assert target["result"] == "1024" and target["args"][2] == "1024", target
    assert TRUSTED.quoted(target["args"][1]) == baseline["data"][:1024], target
    ranges = getattr(cases.profile[0], "executable_ranges", [])
    assert any(start <= target["ip"] < end for start, end in ranges), (target, ranges)
    normal_calls = len(baseline_reads)
    interrupted = dict(syscall="read", error="EINTR", when=target["ordinal"])
    result = cases.run("read-eintr-recovery", entries,
                       overrides={"input-reads": normal_calls + 1}, injection=interrupted)
    successful(result, entries)
    reads = injected_read(result, target, interrupted)
    assert len(reads) == normal_calls + 1 and int(one(result, "unpack")["input_reads"]) == normal_calls + 1
    assert TRUSTED.quoted(reads[1]["args"][1]) == baseline["data"][:1024], reads[1]
    assert sum(int(item["result"].split()[0]) for item in reads[1:]) == len(baseline["data"]), reads
    for label, rule, budget, status, cause in [
        ("read-eintr-budget", interrupted, 1, 2, -5),
        ("read-eio", dict(syscall="read", error="EIO", when=target["ordinal"]), normal_calls + 1, 3, 5),
        ("read-invalid-count", dict(syscall="read", retval=1025, when=target["ordinal"]), normal_calls + 1, 3, -2),
    ]:
        result = cases.run(label, entries, overrides={"input-reads": budget}, code=status, injection=rule)
        reads = injected_read(result, target, rule)
        assert len(reads) == 1, reads
        no_mutation(result)
        summary = one(result, "unpack", phase="input")
        assert summary["code"] == str(status) and summary["cause"] == str(cause), summary
        assert summary["input_bytes"] == "0" and summary["input_reads"] == "1" and summary["input_close_error"] == "0", summary
        assert (result["directory"] / "archive").read_bytes() == baseline["data"]
    # A synthetic positive return does not read or advance the actual file.
    # Its 1025 count is only adapter-rejection evidence, never a physical prefix.
    print("PASS unpack input-faults calibration=1 reached-injections=4")


def controls():
    count = 0
    raw = [member(b"raw-\xff/line\n=tail", BINARY)]
    tar = archive(raw, "tar")
    import tarfile
    with tarfile.open(fileobj=io.BytesIO(tar), encoding="utf-8", errors="surrogateescape") as parsed:
        item = parsed.getmembers()[0]
        assert item.name.encode("utf-8", "surrogateescape") == raw[0]["name"]
        assert parsed.extractfile(item).read() == BINARY
    count += 1
    for method in (0, 8):
        data = archive([member(b"normal", BINARY, method=method)], "zip")
        with zipfile.ZipFile(io.BytesIO(data)) as parsed:
            assert parsed.read("normal") == BINARY
        count += 1
    row = report(b"node index=0 ordinal=-1 path_hex=610aff status_available=0\n")[0][1]
    assert bytes.fromhex(row["path_hex"]) == b"a\n\xff" and row["ordinal"] == "-1"
    count += 1
    for invalid in (b"node x=1 x=2\n", b"node raw=\xff\n", b"node bad\n", b"unknown x=1\n", b"node raw=a=b\n", b"node x=1"):
        try:
            report(invalid)
        except (AssertionError, UnicodeError):
            count += 1
        else:
            raise AssertionError("report parser accepted ambiguous/raw diagnostic")
    # Decimal parser oracle vectors mirror the published syntax, not lexer
    # implementation details or enum serialization values.
    for value in ("0", "18446744073709551615"):
        assert value.isascii() and value.isdecimal() and int(value) < 1 << 64
        count += 1
    for value in ("-1", "+1", "", "1x", "18446744073709551616"):
        assert not (value.isascii() and value.isdecimal() and int(value) < 1 << 64)
        count += 1
    source = (HERE.parents[3] / "sample_programs/library/unpack.lani").read_text()
    literal_count = 0
    for match in re.finditer(r'literal\(("(?:[^"\\]|\\.)*"),(\d+)\)', source):
        assert len(ast.literal_eval(match[1]).encode()) == int(match[2]), match.group()
        literal_count += 1
    assert literal_count > 100
    count += 1
    assert set(re.findall(r'--([a-z-]+)",\d+\)\)\) \{ return \d+;', source)) == set(LIMIT_FLAGS)
    count += 1
    ip = "[0000000000401002] "
    opened = ip + 'openat(AT_FDCWD, "\\x61", O_RDONLY) = 3\n'
    duplicate = ip + 'fcntl(3, F_DUPFD_CLOEXEC, 0) = 4\n'
    close3 = ip + 'close(3) = 0\n'
    close4 = ip + 'close(4) = 0\n'
    with tempfile.TemporaryDirectory(prefix="unpack-controls-") as directory:
        profile = ([(0x401002, 0x401012)], [])
        assert len(resources(opened + duplicate + close3 + close4, profile, directory)["owners"]) == 2
        count += 1
        for invalid in (opened, opened + close3 + close3,
                        duplicate + close4, opened + opened + close3,
                        opened + close3.replace(" = 0", " = -1 EIO (Input/output error)")):
            try:
                resources(invalid, profile, directory)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("CLI ledger accepted broken descriptor ownership")
        metadata = ip + 'statx(3, "", AT_EMPTY_PATH, STATX_TYPE, {}) = 0\n'
        opened = opened.replace('"\\x61"', '"' + ''.join('\\x%02x' % byte for byte in b"archive") + '"')
        read = ip + 'read(3, "' + '\\x61' * 1024 + '", 1024) = 1024\n'
        actual = resources(opened + metadata + read + close3, profile, directory)
        _, selected = input_reads(dict(ledger=actual))
        assert len(selected) == 1 and selected[0]["args"][0] == "3"
        target = selected[0]
        count += 1
        fault = ip + 'read(3, 0x7fff0000, 1024) = -1 EINTR (Interrupted system call) (INJECTED)\n'
        injected = dict(ledger=resources(opened + metadata + fault + close3, profile, directory))
        rule = dict(syscall="read", when=1, error="EINTR")
        assert len(injected_read(injected, target, rule)) == 1
        count += 1
        for trace in (opened + fault + close3,
                      opened + metadata.replace("statx(3", "statx(4") + fault + close3,
                      opened + metadata + close3 + fault,
                      opened + metadata + fault.replace("read(3", "read(4") + close3,
                      opened + metadata + fault.replace("0401002", "0401003") + close3,
                      opened + metadata + fault.replace(", 1024)", ", 1023)") + close3,
                      opened + metadata + fault.replace("EINTR", "EIO") + close3,
                      opened + metadata + fault + fault + close3):
            try:
                injected_read(dict(ledger=resources(trace, profile, directory)), target, rule)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("input injection selector accepted an unbound/mismatched read")
    print(f"PASS unpack CPU controls={count} literal-lengths={literal_count}")
    return count


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 3 and sys.argv[1] in ("tree", "arguments", "bounds", "report", "input_faults"), sys.argv
    group, executable = sys.argv[1:]
    cases = Cases(executable, group)
    {"tree": trees, "arguments": arguments, "bounds": bounds, "report": reports, "input_faults": input_faults}[group](cases)
    cases.finish(group)


if __name__ == "__main__":
    main()
