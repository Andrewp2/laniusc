"""Actual kv_tool consumers and atomic publication; no production logic here."""
import ast
import importlib.util
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
LEDGER = load("kv_publication_current_source_ledger", Path(__file__).with_name("source_ledger.py"))
SNAPSHOT = load("kv_publication_independent_snapshot", Path(__file__).resolve().parents[1] / "kv_oracle.py")
INVALID = b"kv-tool: invalid input or resource limit\n"
EXISTS = b"kv-tool: database already exists\n"
IO = b"kv-tool: I/O failure\n"
ALLOCATION = b"kv-tool: allocation failed\n"
PUBLISHED = b"kv-tool: snapshot published; directory sync unconfirmed\n"
UNCONFIRMED = b"kv-tool: publication visibility unconfirmed\n"
CLEANUP = b"kv-tool: cleanup failed\n"
RETAINED = b"kv-tool: retained temporary name in database directory: "
SENTINEL = b"unrelated file must survive\0\xff"
COMMANDS = (
    (b"init", b"Create an empty database", b"DB"),
    (b"put", b"Insert or replace a byte value", b"DB KEY_HEX VALUE_HEX"),
    (b"remove", b"Remove a byte key", b"DB KEY_HEX"),
    (b"get", b"Write the exact stored value", b"DB KEY_HEX"),
    (b"list", b"List sorted hexadecimal entries", b"DB"),
    (b"check", b"Validate the complete snapshot", b"DB"),
)
HELP_OPTIONS = b"\nOptions:\n  -h, --help    Show command help\n"
ROOT_HELP = b"Usage: kv-tool [OPTIONS] [COMMAND]\nBounded byte-key snapshot store\n" + HELP_OPTIONS + b"\nCommands:\n" + b"".join(b"  " + name + b"    " + summary + b"\n" for name, summary, _ in COMMANDS)
NO_FILESYSTEM = LEDGER.CALLS - {"mmap", "munmap", "write", "rt_sigaction"}


def rule(syscall, ordinal, error, repeat=False):
    return dict(syscall=syscall, when=ordinal, error=error, repeat=repeat)


def command(executable, trace, rules=(), delay=None, string_limit=4096):
    values = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", str(string_limit),
              "-e", "signal=none", "-e", "trace=" + LEDGER.TRACE, "-o", str(trace)]
    for item in rules:
        end = "..%d" % item["last"] if "last" in item else ""
        values += ["-e", "inject=%s:error=%s:when=%d%s%s" % (item["syscall"], item["error"], item["when"], end, "+" if item.get("repeat") else "")]
    if delay is not None:
        values += ["-e", "inject=renameat2:delay_enter=2s:when=%d" % delay]
    return values + [str(executable)]


def selected(result, name):
    return [event for event in result["events"] if event["name"] == name]


def signal_policy(result, installed=True):
    policies = selected(result, "rt_sigaction")
    assert len(policies) == 1 and policies[0]["index"] == 0, policies
    policy = policies[0]
    args = LEDGER.arguments(policy["args"])
    assert args[0] == "SIGPIPE" and args[-1] == "8", policy
    if installed:
        assert policy["result"] == "0" and "sa_handler=SIG_IGN" in policy["args"], policy
    else:
        assert policy["result"].startswith("-1 ") and len(result["events"]) == 1, result


def no_filesystem(result):
    assert not [event for event in result["events"] if event["name"] in NO_FILESYSTEM], result


def bind(before, after, item):
    name, ordinal = item["syscall"], item["when"]
    if name not in ("read", "open", "openat"):
        return LEDGER.bind_target(before, after, name, ordinal)
    prior, actual = selected(before, name), selected(after, name)
    assert len(prior) >= ordinal and len(actual) >= ordinal, (item, prior, actual)
    left, right = prior[ordinal - 1], actual[ordinal - 1]
    assert (left["ip"], left["phase"]) == (right["ip"], right["phase"]), (left, right)
    a, b = LEDGER.arguments(left["args"]), LEDGER.arguments(right["args"])
    if name == "read":
        # strace prints successful buffer contents but an error's raw pointer.
        # Bind source site, descriptor and requested size, plus every preceding
        # read request; no stack address is used as cross-process identity.
        shape = lambda entry: (entry["ip"], LEDGER.arguments(entry["args"])[0], LEDGER.arguments(entry["args"])[-1])
        assert [shape(e) for e in prior[:ordinal]] == [shape(e) for e in actual[:ordinal]], (prior, actual)
    else:
        offset = int(name == "openat")
        if offset:
            assert a[0] == b[0], (left, right)
        assert a[offset + 1:] == b[offset + 1:], (left, right)
        first, second = LEDGER.quoted(a[offset]), LEDGER.quoted(b[offset])
        if first != second:
            assert re.fullmatch(rb"\.tmp-[0-9a-f]{32}", first) and re.fullmatch(rb"\.tmp-[0-9a-f]{32}", second), (left, right)
    return right


def artifact_prefix(count, label=None):
    safe = label if label and re.fullmatch(r"[A-Za-z0-9_-]{1,64}", label) else "run"
    return "%03d-%s" % (count, safe)


class Suite:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.group = group
        self.directory = Path(tempfile.mkdtemp(prefix="kv-application-" + group + "-"))
        self.profile = LEDGER.verified_sites(self.executable, self.directory)
        self.count = 0

    def case(self, label):
        directory = self.directory / label
        directory.mkdir()
        cwd = directory / "cwd"
        cwd.mkdir()
        (cwd / "sentinel").write_bytes(SENTINEL)
        return directory, cwd

    def run(self, directory, cwd, args, *, status=0, output=b"", diagnostic=b"", rules=(), baseline=None, label=None, closed_stdout=False):
        self.count += 1
        prefix = artifact_prefix(self.count, label)
        trace = directory / (prefix + ".trace")
        cmd = command(self.executable, trace, rules, string_limit=64 if self.group == "roundtrips" else 4096) + list(args)
        (directory / (prefix + ".command.txt")).write_text(repr(cmd) + "\n")
        writer = None
        try:
            if closed_stdout:
                reader, writer = os.pipe()
                os.close(reader)
            result = subprocess.run(cmd, cwd=cwd, stdout=writer if closed_stdout else subprocess.PIPE,
                                    stderr=subprocess.PIPE, timeout=8, restore_signals=True)
        finally:
            if writer is not None:
                os.close(writer)
        stdout = b"" if closed_stdout else result.stdout
        (directory / (prefix + ".stdout")).write_bytes(stdout)
        (directory / (prefix + ".stderr")).write_bytes(result.stderr)
        expected_diagnostic = diagnostic() if callable(diagnostic) else diagnostic
        assert (result.returncode, stdout, result.stderr) == (status, output, expected_diagnostic), (cmd, result.returncode, stdout[:256], result.stderr)
        ledger = LEDGER.analyze(trace.read_text(), self.profile, directory, phase_markers=False,
                                executable=self.executable, status=result.returncode)
        LEDGER.check_injections(ledger, rules)
        signal_policy(ledger, installed=not any(item["syscall"] == "rt_sigaction" for item in rules))
        if baseline is not None:
            for item in rules:
                bind(baseline, ledger, item)
        assert (cwd / "sentinel").read_bytes() == SENTINEL
        return ledger

    def done(self, extra=""):
        print("kv-application-%s cases=%d%s" % (self.group, self.count, extra))
        if not os.environ.get("LANIUS_KEEP_TEMP_ARTIFACTS"):
            shutil.rmtree(self.directory)


def contents(cwd, name, records):
    data = (cwd / name).read_bytes()
    assert data == SNAPSHOT.encode(records), (name, len(data), [(len(k), len(v)) for k, v in dict(records).items()])
    assert SNAPSHOT.decode(data) == sorted(dict(records).items())
    assert set(os.listdir(cwd)) == {name, "sentinel"}, os.listdir(cwd)


def child_help(name):
    _, summary, operands = next(row for row in COMMANDS if row[0] == name)
    return b"Usage: kv-tool " + name + b" [OPTIONS] " + operands + b"\n" + summary + b"\n" + HELP_OPTIONS


def tree(cwd):
    result = {}
    def visit(base, prefix=b""):
        for entry in os.scandir(base):
            name = prefix + entry.name
            kind = stat.S_IFMT(entry.stat(follow_symlinks=False).st_mode)
            if kind == stat.S_IFDIR:
                result[name] = (kind, b"")
                visit(entry.path, name + b"/")
            elif kind == stat.S_IFREG:
                result[name] = (kind, Path(os.fsdecode(entry.path)).read_bytes())
            elif kind == stat.S_IFLNK:
                result[name] = (kind, os.readlink(entry.path))
            else:
                result[name] = (kind, b"")
    visit(os.fsencode(cwd))
    return result


def response_only(result, paths, *, partial=False):
    opens = selected(result, "openat")
    observed = []
    for entry in opens:
        args = LEDGER.arguments(entry["args"])
        assert args[0] == "AT_FDCWD", entry
        flags = set(args[2].split("|"))
        assert {"O_RDONLY", "O_CLOEXEC", "O_NONBLOCK", "O_NOCTTY", "O_NOFOLLOW"} <= flags and not flags & {"O_CREAT", "O_TRUNC", "O_RDWR", "O_WRONLY"}, entry
        observed.append(LEDGER.quoted(args[1]))
    assert observed == (list(paths)[:len(observed)] if partial else list(paths)), (observed, paths)
    owners = result["acquisitions"]
    assert all(owner["acquired"]["name"] == "openat" and owner["closed"] is not None for owner in owners), owners
    assert all(left["closed"]["index"] < right["acquired"]["index"] for left, right in zip(owners, owners[1:])), owners
    for entry in result["events"]:
        name, args = entry["name"], LEDGER.arguments(entry["args"])
        assert name in {"mmap", "munmap", "rt_sigaction", "write", "openat", "read", "statx", "close"}, entry
        if name == "write":
            assert args[0] in ("1", "2"), ("response preprocessing wrote a file", entry)
        if name in ("read", "statx", "close"):
            fd = int(args[0])
            active = [owner for owner in owners if owner["fd"] == fd and owner["acquired"]["index"] < entry["index"] <= owner["closed"]["index"]]
            assert len(active) == 1, ("response I/O did not use the actual live source generation", entry, owners)
            if name == "statx":
                assert LEDGER.quoted(args[1]) == b"" and "AT_EMPTY_PATH" in args[2], entry


def response_prefix(result, paths):
    owners = result["acquisitions"][:len(paths)]
    assert len(owners) == len(paths) and paths, owners
    end = owners[-1]["closed"]["index"]
    prefix = dict(result, events=[entry for entry in result["events"] if entry["index"] <= end], acquisitions=owners)
    response_only(prefix, paths)
    return end


def responses(suite):
    directory, cwd = suite.case("ordinary-no-provider")
    for index, args, status, output, diagnostic in [(0, ["--help"], 0, ROOT_HELP, b""), (1, ["unknown"], 2, b"", INVALID),
                                                   (2, ["@@missing.rsp"], 2, b"", INVALID)]:
        result = suite.run(directory, cwd, args, status=status, output=output, diagnostic=diagnostic, label="ordinary-%d" % index)
        no_filesystem(result)
        assert set(os.listdir(cwd)) == {"sentinel"}

    directory, cwd = suite.case("quoted-store-workflow")
    records = {}
    operations = [(b"init 'db name.kv'", 0, b"", None),
                  (b"put 'db name.kv' 00ff 80ff00", 0, b"", {b"\0\xff": b"\x80\xff\0"}),
                  (b'put "db name.kv" "" ""', 0, b"", {b"\0\xff": b"\x80\xff\0", b"": b""}),
                  (b"get 'db name.kv' 00ff", 0, b"\x80\xff\0", None),
                  (b"list 'db name.kv'", 0, b"\t\n00ff\t80ff00\n", None),
                  (b"check 'db name.kv'", 0, b"", None),
                  (b"remove 'db name.kv' 00ff", 0, b"", {b"": b""})]
    for index, (raw, status, output, updated) in enumerate(operations):
        (cwd / "op.rsp").write_bytes(raw)
        before = tree(cwd)
        result = suite.run(directory, cwd, ["@op.rsp"], status=status, output=output, label="operation-%d" % index)
        response_prefix(result, [b"op.rsp"])
        if updated is not None: records = updated
        expected = dict(before)
        expected[b"db name.kv"] = (stat.S_IFREG, SNAPSHOT.encode(records))
        assert tree(cwd) == expected

    directory, cwd = suite.case("fixed-cwd-nesting")
    (cwd / "sub").mkdir()
    (cwd / "sub/start.rsp").write_bytes(b"@args.rsp")
    (cwd / "sub/args.rsp").write_bytes(b"init WRONG.kv")
    (cwd / "args.rsp").write_bytes(b"init right.kv")
    before = tree(cwd)
    result = suite.run(directory, cwd, ["@sub/start.rsp"])
    response_prefix(result, [b"sub/start.rsp", b"args.rsp"])
    before[b"right.kv"] = (stat.S_IFREG, SNAPSHOT.encode({}))
    assert tree(cwd) == before

    for index, name, args in [(0, b"db after.kv", [b"init", b"--", b"@name.rsp"]),
                              (1, b"@literal.kv", [b"init", b"@@literal.kv"]),
                              (2, b"raw-\xff.kv", [b"@raw-\xff.rsp"])]:
        directory, cwd = suite.case("raw-directive-%d" % index)
        paths = []
        if index == 0:
            (cwd / "name.rsp").write_bytes(b"'db after.kv'"); paths = [b"name.rsp"]
        if index == 2:
            Path(os.fsdecode(os.fsencode(cwd) + b"/raw-\xff.rsp")).write_bytes(b"init 'raw-\xff.kv'"); paths = [b"raw-\xff.rsp"]
        before = tree(cwd)
        result = suite.run(directory, cwd, args)
        if paths: response_prefix(result, paths)
        before[name] = (stat.S_IFREG, SNAPSHOT.encode({}))
        assert tree(cwd) == before

    directory, cwd = suite.case("preprocessing-rejection")
    bad = [(b"--help unknown", 2, INVALID), (b"put missing/db 0 00", 2, INVALID),
           (b"'unfinished", 2, INVALID), (b"--help\\", 2, INVALID), (b"--help\0", 2, INVALID),
           (b"", 2, INVALID), (b" ".join([b"--help"] * 9), 2, INVALID)]
    for index, (raw, status, diagnostic) in enumerate(bad):
        (cwd / "bad.rsp").write_bytes(raw)
        before = tree(cwd)
        result = suite.run(directory, cwd, ["@bad.rsp"], status=status, diagnostic=diagnostic, label="bad-%d" % index)
        response_only(result, [b"bad.rsp"])
        assert tree(cwd) == before
    (cwd / "quoted.rsp").write_bytes(b"'@missing.rsp'")
    before = tree(cwd)
    result = suite.run(directory, cwd, ["@quoted.rsp"], status=3, diagnostic=IO)
    response_only(result, [b"quoted.rsp", b"missing.rsp"])
    assert tree(cwd) == before
    (cwd / "-").write_bytes(b"--help")
    before = tree(cwd)
    result = suite.run(directory, cwd, ["@-"], output=ROOT_HELP)
    response_only(result, [b"-"])
    assert tree(cwd) == before
    (cwd / "not-regular").mkdir()
    result = suite.run(directory, cwd, ["@not-regular"], status=2, diagnostic=INVALID)
    response_only(result, [b"not-regular"])
    (cwd / "link.rsp").symlink_to("-")
    result = suite.run(directory, cwd, ["@link.rsp"], status=3, diagnostic=IO)
    response_only(result, [b"link.rsp"])

    directory, cwd = suite.case("response-limits")
    (cwd / "cycle.rsp").write_bytes(b"@cycle.rsp")
    before = tree(cwd)
    result = suite.run(directory, cwd, ["@cycle.rsp"], status=2, diagnostic=INVALID)
    response_only(result, [b"cycle.rsp"] * 8)
    assert tree(cwd) == before
    (cwd / "empty.rsp").write_bytes(b"")
    (cwd / "repeat.rsp").write_bytes(b" ".join([b"@empty.rsp"] * 17))
    before = tree(cwd)
    result = suite.run(directory, cwd, ["@repeat.rsp"], status=2, diagnostic=INVALID)
    response_only(result, [b"repeat.rsp"] + [b"empty.rsp"] * 15)
    assert tree(cwd) == before
    for length, status, output, diagnostic in [(262144, 0, ROOT_HELP, b""), (262145, 2, b"", INVALID)]:
        (cwd / "large.rsp").write_bytes(b"--help" + b" " * (length - 6))
        before = tree(cwd)
        result = suite.run(directory, cwd, ["@large.rsp"], status=status, output=output, diagnostic=diagnostic, label="file-bytes-%d" % length)
        response_only(result, [b"large.rsp"])
        observed_bytes = sum(int(entry["result"].split()[0]) for entry in selected(result, "read") if entry["result"].split()[0].isdecimal())
        assert observed_bytes == length
        assert tree(cwd) == before

    directory, cwd = suite.case("response-owners-baseline")
    (cwd / "outer.rsp").write_bytes(b"@help.rsp")
    (cwd / "help.rsp").write_bytes(b"--help")
    before = tree(cwd)
    baseline = suite.run(directory, cwd, ["@outer.rsp"], output=ROOT_HELP)
    response_only(baseline, [b"outer.rsp", b"help.rsp"])
    points = baseline["source"]["allocations"]
    assert 0 < len(points) <= 256
    for allocation in points:
        result = suite.run(directory, cwd, ["@outer.rsp"], status=4, diagnostic=ALLOCATION,
                           rules=[rule("mmap", allocation["ordinal"], "ENOMEM")], baseline=baseline, label="response-oom-%d" % allocation["ordinal"])
        response_only(result, [b"outer.rsp", b"help.rsp"], partial=True)
        assert tree(cwd) == before
    for call in ("openat", "read"):
        target = selected(baseline, call)[0]
        result = suite.run(directory, cwd, ["@outer.rsp"], status=3, diagnostic=IO,
                           rules=[rule(call, target["ordinal"], "EIO")], baseline=baseline, label="response-" + call + "-eio")
        response_only(result, [b"outer.rsp", b"help.rsp"], partial=True)
    read = selected(baseline, "read")[0]
    recovered = suite.run(directory, cwd, ["@outer.rsp"], output=ROOT_HELP,
                          rules=[rule("read", read["ordinal"], "EINTR")], baseline=baseline, label="response-read-eintr")
    response_only(recovered, [b"outer.rsp", b"help.rsp"])
    broken = suite.run(directory, cwd, ["@outer.rsp"], status=3, diagnostic=IO, closed_stdout=True, label="response-closed-reader")
    response_only(broken, [b"outer.rsp", b"help.rsp"])
    actual = [entry for entry in selected(broken, "write") if LEDGER.arguments(entry["args"])[0] == "1"]
    assert len(actual) == 1 and actual[0]["result"].startswith("-1 EPIPE ") and "INJECTED" not in actual[0]["result"]
    assert tree(cwd) == before

    def mutation_case(label):
        directory, cwd = suite.case(label)
        (cwd / "change.rsp").write_bytes(b"put db.kv 00 ff")
        (cwd / "db.kv").write_bytes(SNAPSHOT.encode({}))
        return directory, cwd
    directory, cwd = mutation_case("response-mutation-baseline")
    mutation = suite.run(directory, cwd, ["@change.rsp"])
    boundary = response_prefix(mutation, [b"change.rsp"])
    assert (cwd / "db.kv").read_bytes() == SNAPSHOT.encode({b"\0": b"\xff"})
    data_owners = [owner for owner in mutation["acquisitions"] if owner["acquired"]["name"] == "openat"
                   and LEDGER.quoted(LEDGER.arguments(owner["acquired"]["args"])[1]) == b"db.kv"]
    assert len(data_owners) == 1 and data_owners[0]["acquired"]["index"] > boundary
    allocations_after_database_open = [entry for entry in mutation["source"]["allocations"] if entry["index"] > data_owners[0]["acquired"]["index"]]
    assert allocations_after_database_open
    directory, cwd = mutation_case("database-oom-retains-expansion-cleanup")
    before = tree(cwd)
    target = allocations_after_database_open[0]
    failed = suite.run(directory, cwd, ["@change.rsp"], status=4, diagnostic=ALLOCATION,
                       rules=[rule("mmap", target["ordinal"], "ENOMEM")], baseline=mutation)
    response_prefix(failed, [b"change.rsp"])
    assert tree(cwd) == before
    syncs = selected(mutation, "fsync")
    assert len(syncs) == 2
    directory, cwd = mutation_case("published-status-retains-expansion-cleanup")
    before = tree(cwd)
    published = suite.run(directory, cwd, ["@change.rsp"], status=6, diagnostic=PUBLISHED,
                          rules=[rule("fsync", syncs[-1]["ordinal"], "EIO")], baseline=mutation)
    response_prefix(published, [b"change.rsp"])
    before[b"db.kv"] = (stat.S_IFREG, SNAPSHOT.encode({b"\0": b"\xff"}))
    assert tree(cwd) == before
    suite.done(" response-source-oom=%d" % len(points))


def hierarchy(suite):
    directory, cwd = suite.case("help-and-no-effects")
    def pure(label, args, **expected):
        result = suite.run(directory, cwd, args, label=label, **expected)
        no_filesystem(result)
        assert set(os.listdir(cwd)) == {"sentinel"}, os.listdir(cwd)
        return result

    baseline = pure("root-help", ["--help"], output=ROOT_HELP)
    pure("root-short-help", ["-h"], output=ROOT_HELP)
    for name, _, _ in COMMANDS:
        pure("child-" + name.decode(), [name, b"--help"], output=child_help(name))
    pure("global-before-selection", ["-h", "put"], output=child_help(b"put"))
    pure("help-with-raw-path", [b"init", b"--help", b"\xff"], output=child_help(b"init"))
    pure("exact-argument-count", ["-h"] * 8, output=ROOT_HELP)
    pure("over-argument-count", ["-h"] * 9, status=2, diagnostic=INVALID)
    invalid = [[], ["--"], ["put"], ["put", "db"], ["get", "db"], ["Init", "db"], ["p", "db"],
               ["unknown"], ["--help", "unknown"], ["--he"], ["--help=yes"], ["put", "--bogus", "--help"],
               ["put", "--help", "--bogus"], ["init", "--help", "one", "two"],
               ["put", "--help", "one", "two", "three", "four"], ["--", "put", "db", "00", "ff"],
               ["--", "--help"], ["init", "--"], ["put", "missing/db", "0", "00"],
               ["put", "missing/db", "gg", "00"], ["get", "missing/db", "gg"],
               ["put", "db", "00", "ff", "--help"], ["get", "db", "--help"]]
    for index, args in enumerate(invalid):
        pure("reject-%d" % index, args, status=2, diagnostic=INVALID)
    exact = [b"--help", b"x" * 131071, b"y" * 131067]
    assert sum(map(len, exact)) == 262144
    accepted_snapshot = pure("exact-argument-bytes", exact, status=2, diagnostic=INVALID)
    assert accepted_snapshot["source"]["allocations"], "exact snapshot byte cap was not admitted"
    denied_snapshot = pure("over-argument-bytes", [*exact[:2], exact[2] + b"y"], status=2, diagnostic=INVALID)
    assert not denied_snapshot["source"]["allocations"], "over-byte snapshot should reject before allocation"

    first_write = selected(baseline, "write")[0]
    assert LEDGER.arguments(first_write["args"])[0] == "1"
    failed = pure("help-write-eio", ["--help"], status=3, diagnostic=IO,
                  rules=[rule("write", first_write["ordinal"], "EIO")], baseline=baseline)
    interrupted = pure("help-write-eintr", ["--help"], output=ROOT_HELP,
                       rules=[rule("write", first_write["ordinal"], "EINTR")], baseline=baseline)
    assert len(selected(interrupted, "write")) == 2
    capped = pure("help-interruption-cap", ["--help"], status=3, diagnostic=IO,
                  rules=[dict(rule("write", first_write["ordinal"], "EINTR"), last=first_write["ordinal"] + 63)])
    stdout_calls = [entry for entry in selected(capped, "write") if LEDGER.arguments(entry["args"])[0] == "1"]
    assert len(stdout_calls) == 64 and all(entry["result"].startswith("-1 EINTR ") for entry in stdout_calls)
    assert stdout_calls[0]["ip"] == first_write["ip"] and stdout_calls[0]["args"] == first_write["args"]
    broken = pure("actual-closed-help-reader", ["--help"], status=3, diagnostic=IO, closed_stdout=True)
    actual = [entry for entry in selected(broken, "write") if LEDGER.arguments(entry["args"])[0] == "1"]
    assert len(actual) == 1 and actual[0]["result"].startswith("-1 EPIPE ") and "INJECTED" not in actual[0]["result"]
    bind(baseline, broken, rule("write", first_write["ordinal"], "EPIPE"))
    uninstalled = pure("signal-policy-unconfirmed", ["--help"], status=3, rules=[rule("rt_sigaction", 1, "EINTR")])
    assert selected(uninstalled, "rt_sigaction")[0]["ip"] == selected(baseline, "rt_sigaction")[0]["ip"]

    for index, name in enumerate((b"list", b"--help", b"--", b"-\xff.kv")):
        directory, cwd = suite.case("raw-leaf-%d" % index)
        escape = [b"--"] if name.startswith(b"-") else []
        suite.run(directory, cwd, [b"init", *escape, name])
        suite.run(directory, cwd, [b"put", *escape, name, b"00ff", b"80ff00"])
        suite.run(directory, cwd, [b"get", *escape, name, b"00ff"], output=b"\x80\xff\0")
        suite.run(directory, cwd, [b"list", *escape, name], output=b"00ff\t80ff00\n")
        suite.run(directory, cwd, [b"check", *escape, name])
        suite.run(directory, cwd, [b"remove", *escape, name, b"00ff"])
        assert Path(os.fsdecode(os.fsencode(cwd) + b"/" + name)).read_bytes() == SNAPSHOT.encode({})
        assert set(os.listdir(os.fsencode(cwd))) == {name, b"sentinel"}
    suite.done()


def roundtrips(suite):
    directory, cwd = suite.case("binary-roundtrip")
    suite.run(directory, cwd, ["--help"], output=ROOT_HELP)
    suite.run(directory, cwd, ["init", "db.kv"])
    records = {}
    contents(cwd, "db.kv", records)
    suite.run(directory, cwd, ["init", "db.kv"], status=2, diagnostic=EXISTS)
    contents(cwd, "db.kv", records)
    for key, value in [("00ff", "000102ff"), ("", ""), ("abcd", "c3a9"), ("00ff", "ff00")]:
        suite.run(directory, cwd, ["put", "db.kv", key, value])
        records[bytes.fromhex(key)] = bytes.fromhex(value)
        contents(cwd, "db.kv", records)
    suite.run(directory, cwd, ["get", "db.kv", "00ff"], output=b"\xff\0")
    suite.run(directory, cwd, ["get", "db.kv", "99"], status=5)
    suite.run(directory, cwd, ["get", "db.kv", ""])
    suite.run(directory, cwd, ["list", "db.kv"], output=b"\t\n00ff\tff00\nabcd\tc3a9\n")
    suite.run(directory, cwd, ["check", "db.kv"])
    suite.run(directory, cwd, ["remove", "db.kv", "00ff"])
    records.pop(b"\0\xff")
    contents(cwd, "db.kv", records)
    missing = suite.run(directory, cwd, ["remove", "db.kv", "00ff"], status=5)
    assert not any(selected(missing, name) for name in ("renameat2", "getrandom", "fsync"))
    for args in (["put", "db.kv", "a", "00"], ["put", "db.kv", "gg", "00"],
                 ["put", "db.kv", "discard.scratch", "00", "00"],
                 ["init", "db.kv", "discard.scratch"], ["remove", "db.kv", "discard.scratch", "00"], ["bad", "db.kv"]):
        suite.run(directory, cwd, args, status=2, diagnostic=INVALID)
        contents(cwd, "db.kv", records)
    (cwd / "db.kv").write_bytes(b"corrupt snapshot")
    suite.run(directory, cwd, ["put", "db.kv", "00", "00"], status=2, diagnostic=INVALID)
    assert (cwd / "db.kv").read_bytes() == b"corrupt snapshot" and set(os.listdir(cwd)) == {"db.kv", "sentinel"}

    directory, cwd = suite.case("independent-binary-and-limits")
    records = {b"\0\xff": bytes(range(256)) * 13 + b"\0\x80\xff", b"": b""}
    (cwd / "db.kv").write_bytes(SNAPSHOT.encode(records))
    suite.run(directory, cwd, ["get", "db.kv", "00ff"], output=records[b"\0\xff"])
    suite.run(directory, cwd, ["check", "db.kv"])
    for records in ({b"k": b"v" * 4194304}, {b"k" * 65536: b"v"},
                    {index.to_bytes(2, "big"): b"" for index in range(4096)}):
        (cwd / "db.kv").write_bytes(SNAPSHOT.encode(records))
        suite.run(directory, cwd, ["check", "db.kv"])
        contents(cwd, "db.kv", records)
    for records in ({b"k": b"v" * 4194305}, {b"k" * 65537: b"v"},
                    {index.to_bytes(2, "big"): b"" for index in range(4097)}):
        data = SNAPSHOT.encode(records)
        (cwd / "db.kv").write_bytes(data)
        suite.run(directory, cwd, ["check", "db.kv"], status=2, diagnostic=INVALID)
        assert (cwd / "db.kv").read_bytes() == data
    (cwd / "db.kv").write_bytes(b"x" * 9437185)
    suite.run(directory, cwd, ["check", "db.kv"], status=2, diagnostic=INVALID)
    directory, cwd = suite.case("raw-final-component")
    name = b"db-\xff.kv"
    suite.run(directory, cwd, [b"init", name])
    suite.run(directory, cwd, [b"put", name, b"00ff", b"80ff00"])
    suite.run(directory, cwd, [b"get", name, b"00ff"], output=b"\x80\xff\0")
    assert Path(os.fsdecode(os.fsencode(cwd) + b"/" + name)).read_bytes() == SNAPSHOT.encode({b"\0\xff": b"\x80\xff\0"})
    assert set(os.listdir(os.fsencode(cwd))) == {name, b"sentinel"}
    suite.done()


def publication(suite):
    original = SNAPSHOT.encode({b"\x01": b"\x07" * 1000})
    expected = SNAPSHOT.encode({b"\x01": b"\x07" * 1000, b"\x02": b"\xff\0"})
    directory, cwd = suite.case("replace-baseline")
    (cwd / "db.kv").write_bytes(original)
    baseline = suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"])
    assert (cwd / "db.kv").read_bytes() == expected and set(os.listdir(cwd)) == {"db.kv", "sentinel"}
    renames, syncs = selected(baseline, "renameat2"), selected(baseline, "fsync")
    assert len(renames) == 1 and LEDGER.arguments(renames[0]["args"])[-1] == "0" and len(syncs) == 2
    assert syncs[0]["index"] < renames[0]["index"] < syncs[1]["index"] and all(e["result"] == "0" for e in syncs)
    allocations = baseline["source"]["allocations"]
    assert allocations and all(e["index"] < renames[0]["index"] for e in allocations), allocations
    # Derive every reached source position, binding the exact allocation site,
    # requested size/flags and preceding mmap request prefix against baseline.
    for allocation in allocations:
        directory, cwd = suite.case("source-oom-%d" % allocation["ordinal"])
        (cwd / "db.kv").write_bytes(original)
        suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"], status=4, diagnostic=ALLOCATION,
                  rules=[rule("mmap", allocation["ordinal"], "ENOMEM")], baseline=baseline)
        assert (cwd / "db.kv").read_bytes() == original and set(os.listdir(cwd)) == {"db.kv", "sentinel"}
    cases = [(entry, 3, IO, original) for name in ("open", "openat", "read", "write") for entry in selected(baseline, name)]
    cases += [(syncs[0], 3, IO, original), (renames[0], 7, UNCONFIRMED, original), (syncs[1], 6, PUBLISHED, expected)]
    cleanup_baseline = published_baseline = None
    for entry, status, diagnostic, target in cases:
        directory, cwd = suite.case("%s-%d-eio" % (entry["name"], entry["ordinal"]))
        (cwd / "db.kv").write_bytes(original)
        result = suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"], status=status, diagnostic=diagnostic,
                           rules=[rule(entry["name"], entry["ordinal"], "EIO")], baseline=baseline)
        assert (cwd / "db.kv").read_bytes() == target and set(os.listdir(cwd)) == {"db.kv", "sentinel"}
        if status == 6:
            published_baseline = result
            assert len(selected(result, "renameat2")) == 1 and selected(result, "renameat2")[0]["result"] == "0" and not selected(result, "unlinkat")
            assert SNAPSHOT.decode(target) == [(b"\x01", b"\x07" * 1000), (b"\x02", b"\xff\0")]
        if status == 3:
            assert not selected(result, "renameat2")
        if entry["name"] == "write" and entry["ordinal"] == selected(baseline, "write")[0]["ordinal"]:
            cleanup_baseline = result
    for name in ("read", "write"):
        entry = selected(baseline, name)[0]
        directory, cwd = suite.case(name + "-eintr")
        (cwd / "db.kv").write_bytes(original)
        suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"], rules=[rule(name, entry["ordinal"], "EINTR")], baseline=baseline)
        assert (cwd / "db.kv").read_bytes() == expected and set(os.listdir(cwd)) == {"db.kv", "sentinel"}
    # A real retained candidate is observable after a skipped cleanup unlink.
    # The application must report it and release source/fd owners by keep,
    # rather than hide the removal error or pretend the file was removed.
    assert cleanup_baseline is not None and len(selected(cleanup_baseline, "unlinkat")) == 1
    directory, cwd = suite.case("write-and-cleanup-failure")
    (cwd / "db.kv").write_bytes(original)
    def retained_diagnostic():
        names = [name for name in os.listdir(cwd) if re.fullmatch(r"\.tmp-[0-9a-f]{32}", name)]
        assert len(names) == 1, names
        return RETAINED + os.fsencode(names[0]) + b"\n" + IO + CLEANUP
    failed_write = selected(baseline, "write")[0]
    failed_unlink = selected(cleanup_baseline, "unlinkat")[0]
    suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"], status=8, diagnostic=retained_diagnostic,
              rules=[rule("write", failed_write["ordinal"], "EIO"), rule("unlinkat", failed_unlink["ordinal"], "EIO")], baseline=cleanup_baseline)
    assert (cwd / "db.kv").read_bytes() == original and len(list(cwd.iterdir())) == 3
    candidates = [path for path in cwd.iterdir() if path.name.startswith(".tmp-")]
    assert len(candidates) == 1 and candidates[0].read_bytes() == b""
    # Reporting failure cannot erase a known publication status. Bind fd2 to
    # the actual reached published/unsynced diagnostic in its own baseline.
    assert published_baseline is not None
    notices = [entry for entry in selected(published_baseline, "write") if LEDGER.arguments(entry["args"])[0] == "2"]
    assert len(notices) == 1 and LEDGER.arguments(notices[0]["args"])[-1] == str(len(PUBLISHED))
    directory, cwd = suite.case("published-diagnostic-undeliverable")
    (cwd / "db.kv").write_bytes(original)
    suite.run(directory, cwd, ["put", "db.kv", "02", "ff00"], status=6,
              rules=[rule("fsync", syncs[1]["ordinal"], "EIO"), rule("write", notices[0]["ordinal"], "EIO")], baseline=published_baseline)
    assert (cwd / "db.kv").read_bytes() == expected and set(os.listdir(cwd)) == {"db.kv", "sentinel"}
    init_race(suite)
    suite.done(" source-oom=%d io-faults=%d" % (len(allocations), len(cases) + 4))


def init_race(suite):
    directory, cwd = suite.case("init-baseline")
    baseline = suite.run(directory, cwd, ["init", "db.kv"])
    rename = selected(baseline, "renameat2")
    assert len(rename) == 1 and LEDGER.arguments(rename[0]["args"])[-1] == "RENAME_NOREPLACE"
    assert (cwd / "db.kv").read_bytes() == SNAPSHOT.encode({})
    directory, cwd = suite.case("init-race")
    trace = directory / "syscalls.trace"
    cmd = command(suite.executable, trace, delay=rename[0]["ordinal"]) + ["init", "db.kv"]
    process = subprocess.Popen(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        deadline = time.monotonic() + 6
        while True:
            candidates = [name for name in os.listdir(cwd) if re.fullmatch(r"\.tmp-[0-9a-f]{32}", name)]
            if candidates:
                assert len(candidates) == 1 and not (cwd / "db.kv").exists()
                break
            assert process.poll() is None and time.monotonic() < deadline, "init did not expose its owned candidate before publication"
            time.sleep(0.005)
        # A distinct real creator wins after init has acquired its private
        # candidate. Only the destination name is mutated, never its temp leaf.
        winner = SNAPSHOT.encode({b"winner\0\xff": b"complete competing snapshot"})
        with (cwd / "db.kv").open("xb") as output:
            output.write(winner)
        stdout, stderr = process.communicate(timeout=6)
        (directory / "stdout").write_bytes(stdout)
        (directory / "stderr").write_bytes(stderr)
        assert (process.returncode, stdout, stderr) == (2, b"", EXISTS), (process.returncode, stdout, stderr)
        result = LEDGER.analyze(trace.read_text(), suite.profile, directory, phase_markers=False,
                                executable=suite.executable, status=process.returncode)
        LEDGER.check_injections(result, [])
        reached = LEDGER.bind_target(baseline, result, "renameat2", rename[0]["ordinal"])
        assert reached["result"].startswith("-1 EEXIST "), reached
        assert (cwd / "db.kv").read_bytes() == winner and SNAPSHOT.decode(winner) == [(b"winner\0\xff", b"complete competing snapshot")]
        assert set(os.listdir(cwd)) == {"db.kv", "sentinel"} and (cwd / "sentinel").read_bytes() == SENTINEL
        suite.count += 1
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate(timeout=3)


def controls():
    count = 0
    def reject(action):
        nonlocal count
        try: action()
        except AssertionError: count += 1
        else: raise AssertionError("invalid signal/no-filesystem witness accepted")
    policy = dict(name="rt_sigaction", args="SIGPIPE, {sa_handler=SIG_IGN, sa_mask=[], sa_flags=0}, NULL, 8", result="0", index=0)
    signal_policy(dict(events=[policy])); count += 1
    reject(lambda: signal_policy(dict(events=[])))
    reject(lambda: signal_policy(dict(events=[dict(policy, args=policy["args"].replace("SIG_IGN", "SIG_DFL"))])))
    reject(lambda: signal_policy(dict(events=[dict(policy, index=1)])))
    no_filesystem(dict(events=[policy])); count += 1
    for name in NO_FILESYSTEM:
        reject(lambda name=name: no_filesystem(dict(events=[policy, dict(name=name)])))
    source = (FIXTURES.parents[1] / "sample_programs/library/kv_tool.lani").read_text()
    for item in re.finditer(r'literal\(("(?:\\.|[^"\\])*"),\s*(\d+)\)', source):
        assert len(ast.literal_eval(item[1]).encode()) == int(item[2]), item[0]
    count += 1
    print("kv-hierarchy CPU-controls=%d native-cases=0" % count)


def response_controls():
    count = 0
    def reject(action):
        nonlocal count
        try: action()
        except AssertionError: count += 1
        else: raise AssertionError("invalid response-file identity/effect witness accepted")
    text = ('[10] openat(AT_FDCWD, "\\x61", O_RDONLY|O_CLOEXEC|O_NONBLOCK|O_NOCTTY|O_NOFOLLOW) = 3\n'
            '[10] statx(3, "", AT_EMPTY_PATH, STATX_BASIC_STATS, {}) = 0\n'
            '[10] read(3, "\\x2d\\x68", 1024) = 2\n'
            '[10] close(3) = 0\n')
    found = LEDGER.events(text)
    owner = dict(fd=3, generation=1, acquired=found[0], closed=found[-1])
    original = dict(events=found, acquisitions=[owner])
    response_only(original, [b"a"]); count += 1
    response_only(original, [b"a", b"b"], partial=True); count += 1
    reject(lambda: response_only(original, [b"a", b"b"]))
    reject(lambda: response_only(original, [b"b"]))
    for index, changes in [(0, dict(args=found[0]["args"].replace("|O_NOFOLLOW", ""))),
                           (1, dict(args=found[1]["args"].replace("AT_EMPTY_PATH", "0"))),
                           (2, dict(args=found[2]["args"].replace("3,", "4,", 1))),
                           (2, dict(index=4))]:
        altered = [dict(entry, **changes) if at == index else entry for at, entry in enumerate(found)]
        reject(lambda altered=altered: response_only(dict(original, events=altered), [b"a"]))
    wrote = dict(name="write", args='3, "\\x61", 1', result="1", index=2)
    reject(lambda: response_only(dict(original, events=[*found[:2], wrote, *found[2:]]), [b"a"]))
    assert response_prefix(original, [b"a"]) == found[-1]["index"]; count += 1
    print("kv-response CPU-controls=%d native-cases=0" % count)


def artifact_controls():
    count = 0
    assert artifact_prefix(11) == "011-run"; count += 1
    assert artifact_prefix(11, "nested-source") == "011-nested-source"; count += 1
    for label in ("@sub/start.rsp", "../../outside", "/absolute", "nul\0byte", ".", "\\windows", "raw-\udcff", "x" * 65):
        prefix = artifact_prefix(11, label)
        assert prefix == "011-run" and Path(prefix).name == prefix and "\0" not in prefix, (label, prefix)
        count += 1
    assert artifact_prefix(11, "same") != artifact_prefix(12, "same"); count += 1
    print("kv-artifact CPU-controls=%d native-cases=0" % count)


if __name__ == "__main__" and sys.argv[1:] == ["controls"]:
    controls()
elif __name__ == "__main__" and sys.argv[1:] == ["response-controls"]:
    response_controls()
elif __name__ == "__main__" and sys.argv[1:] == ["artifact-controls"]:
    artifact_controls()
elif __name__ == "__main__":
    suite = Suite(sys.argv[1], sys.argv[2])
    try:
        {"roundtrips": roundtrips, "publication": publication, "hierarchy": hierarchy, "responses": responses}[suite.group](suite)
    except BaseException:
        print("KV application evidence: %s" % suite.directory, file=sys.stderr)
        raise
