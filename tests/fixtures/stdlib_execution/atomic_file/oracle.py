"""Independent native namespace/ownership oracle for the AtomicFile probe.

The source library performs all file operations. Checkpoints keep its process
alive while the oracle observes publication and retained owners, then explicitly
permit retry/cleanup. Syscall injections are test artifacts, not physical I/O.
"""
import json
import os
from pathlib import Path
import re
import select
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import traceback

import ledger

TEMP = ledger.load("atomic_accepted_temp_file_oracle", Path(__file__).resolve().parents[1] / "temp_file/oracle.py")
read_exact = TEMP.read_exact
snapshot = TEMP.snapshot
MAX = ledger.U64_MAX
WORDS = 128
FRAME_BYTES = WORDS * 8 + 37 + 255
DATA = b"\0\xff\x80a\r\n"
OLD = b"old-target\0\xff"
LARGE = DATA + bytes((i * 17) & 255 for i in range(1024)) * 33
FIELDS = ("state", "visibility", "bytes", "writes", "file_syncs", "renames", "directory_syncs",
          "file_synced", "directory_synced", "file_open", "anchor_open", "temporary_owned", "retained",
          "file_close_attempted", "file_close_error", "remove_attempted", "removal", "remove_error",
          "directory_close_attempted", "directory_close_error", "cleanup_retained",
          "name_attempts", "open_attempts", "collisions", "excluded", "entropy_calls",
          "latest_cause", "latest_stage", "latest_completed", "reserved0", "reserved1", "reserved2")


def rule(syscall, *, last=None, **values):
    result = TEMP.rule(syscall, **values)
    if last is not None:
        assert last >= result["when"] and not result["repeat"]
        result["last"] = last
    return result


def injection(item):
    value = TEMP.injection(item)
    if "last" in item:
        value += ".." + str(item["last"])
    return value


def command(executable, trace, rules):
    values = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
              "-e", "signal=none", "-e", "trace=" + ledger.TRACE, "-o", str(trace)]
    for item in rules:
        values += ["-e", "inject=" + injection(item)]
    return values + [str(executable)]


def request(*, mode=0, policy=0, max_bytes=1048576, writes=128, names=8,
            entropy=16, destination=0, parent=0, payload=0, write_case=0,
            repair=MAX, directory_syncs=8):
    return (mode, policy, max_bytes, writes, names, entropy, destination,
            parent, payload, write_case, repair, directory_syncs)


def block(words, offset):
    return dict(zip(FIELDS, words[offset:offset + 32]))


def decode(result):
    words = result["words"]
    assert len(words) == WORDS and words[119:] == (0,) * 9, words
    assert words[6] in (0, 37) and words[7] <= 255, words
    assert not any(result["temporary"][words[6]:]) and not any(result["destination"][words[7]:])
    result["temporary"] = result["temporary"][:words[6]]
    result["destination"] = result["destination"][:words[7]]
    result["current"], result["first"] = block(words, 8), block(words, 40)
    result["cause"], result["stage"], result["completed"] = words[4], words[5], words[118]
    result["file_fd"], result["anchor_fd"], result["parent_fd"] = words[115:118]
    return result


def selected(result, name, phase=None):
    return [entry for entry in result["events"] if entry["name"] == name
            and (phase is None or entry["phase"] == phase)]


def payload_writes(result):
    return [entry for entry in selected(result, "write", "W")
            if ledger.arguments(entry["args"])[0] == str(result["file_fd"])]


def epoch(result, phase):
    return [item for item in result["epochs"] if item["phase"] == phase]


def checkpoint(trace, packet, deadline):
    """Cut at the exact completed frame write, excluding a pending ACK read."""
    while time.monotonic() < deadline:
        text = trace.read_text() if trace.exists() else ""
        lines = text.splitlines(keepends=True)
        transmitted = bytearray()
        for index, line in enumerate(lines):
            if not line.endswith("\n"):
                continue
            match = ledger.LINE.fullmatch(line.rstrip("\n"))
            if match and match[2] == "write":
                args = ledger.arguments(match[3])
                if len(args) == 3 and args[0] == "1":
                    count = int(match[4].split()[0])
                    assert 0 < count <= int(args[2]) <= 1024 and "INJECTED" not in match[4], line
                    raw = ledger.quoted(args[1])
                    assert len(raw) == count, line
                    transmitted.extend(raw)
                    assert len(transmitted) <= FRAME_BYTES, "stdout frame boundary drift"
                    if len(transmitted) == FRAME_BYTES and bytes(transmitted) == packet:
                        return "".join(lines[:index + 1])
                    if len(transmitted) == FRAME_BYTES:
                        transmitted.clear()
        time.sleep(0.005)
    raise AssertionError("completed report frame was not published in trace")


def proc_owners(pid, result, directory, label):
    descriptors = sorted(int(fd) for fd in os.listdir("/proc/%d/fd" % pid))
    expected = sorted({0, 1, 2} | set(result["live"]))
    assert descriptors == expected, ("checkpoint descriptor disagreement", descriptors, expected)
    maps = Path("/proc/%d/maps" % pid).read_text()
    (directory / (label + ".maps")).write_text(maps)
    (directory / (label + "-fds.json")).write_text(json.dumps(descriptors) + "\n")
    ranges = []
    for line in maps.splitlines():
        address, permissions, *_ = line.split()
        low, high = [int(value, 16) for value in address.split("-")]
        ranges.append((low, high, permissions))
    for pointer, owner in result["mappings"].items():
        assert any(low <= pointer and pointer + owner["length"] <= high and permissions.startswith("rw")
                   for low, high, permissions in ranges), ("live source owner has no mapping", pointer, owner)
    for allocation in result["source"]["allocations"]:
        value = allocation["result"].split()[0]
        if value.startswith("0x"):
            pointer = int(value, 16)
            if pointer not in result["mappings"]:
                assert not any(low <= pointer < high for low, high, _ in ranges), ("released source owner remains mapped", pointer)


class Session:
    def __init__(self, suite, label, request, *, rules=(), setup=None, cwd=None,
                 repair=None, baseline=None):
        self.suite = suite
        self.directory = suite.case(label)
        self.cwd = cwd or self.directory / "cwd"
        if cwd is None:
            self.cwd.mkdir()
            (self.cwd / "anchor").mkdir()
            (self.cwd / "elsewhere").mkdir()
            (self.cwd / "anchor/sentinel").write_bytes(b"anchor-sentinel\0\xff")
            (self.cwd / "anchor/target").write_bytes(OLD)
            (self.cwd / "regular").write_bytes(b"regular-parent\0\xfe")
        if setup:
            setup(self.cwd)
        self.initial_namespace = snapshot(self.cwd)
        self.request = tuple(request)
        assert len(self.request) == 12
        self.rules, self.repair, self.baseline = list(rules), repair, baseline
        self.trace = self.directory / "syscalls.log"
        self.frames = []
        self.packet = b""
        self.stderr = b""
        encoded = struct.pack("<12Q", *self.request)
        (self.directory / "request.bin").write_bytes(encoded)
        cmd = command(suite.executable, self.trace, self.rules)
        (self.directory / "command.json").write_text(json.dumps(cmd, indent=2) + "\n")
        self.process = subprocess.Popen(cmd, cwd=self.cwd, stdin=subprocess.PIPE,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        bufsize=0, umask=0o022)
        self.process.stdin.write(encoded)

    def frame(self, expected):
        packet = read_exact(self.process.stdout, FRAME_BYTES, time.monotonic() + 15,
                            self.directory / ("checkpoint-%d.bin" % expected))
        words = struct.unpack("<128Q", packet[:1024])
        assert words[0:3] == (1, expected, self.request[0]), words
        pid = words[3]
        children = Path("/proc/%d/task/%d/children" % (self.process.pid, self.process.pid)).read_text().split()
        assert children == [str(pid)], ("frame pid is not the traced child", pid, children)
        prefix = checkpoint(self.trace, packet, time.monotonic() + 2)
        (self.directory / ("checkpoint-%d.trace" % expected)).write_text(prefix)
        result = ledger.analyze(prefix, self.suite.profile, self.directory,
                                final=expected == 2,
                                repaired_close=self.repair[0] if self.repair else None,
                                repair_phase=self.repair[1] if self.repair else "M")
        proc_owners(pid, result, self.directory, "checkpoint-%d" % expected)
        reached = [item for item in self.rules if any(entry["name"] == item["syscall"] and entry["ordinal"] >= item["when"] for entry in result["events"])]
        ledger.check_injections(result, reached)
        if self.baseline is not None:
            for item in reached:
                if item["syscall"] != "getrandom":
                    ledger.bind_target(self.baseline, result, item["syscall"], item["when"])
        result.update(words=words, temporary=packet[1024:1061], destination=packet[1061:], checkpoint=expected)
        decode(result)
        self.frames.append(result)
        (self.directory / ("checkpoint-%d-namespace.json" % expected)).write_text(json.dumps(snapshot(self.cwd), indent=2) + "\n")
        return result

    def ack(self):
        self.process.stdin.write(b"!")

    def finish(self):
        final = self.frames[-1]
        assert final["checkpoint"] == 2
        self.ack()
        self.process.stdin.close()
        self.process.stdin = None
        extra, self.stderr = self.process.communicate(timeout=3)
        (self.directory / "native.stderr").write_bytes(self.stderr)
        (self.directory / "exit-status.txt").write_text(str(self.process.returncode) + "\n")
        assert self.process.returncode == 0 and not extra, (self.process.returncode, extra, self.stderr)
        result = ledger.analyze(self.trace.read_text(), self.suite.profile, self.directory,
                                repaired_close=self.repair[0] if self.repair else None,
                                repair_phase=self.repair[1] if self.repair else "M")
        ledger.check_injections(result, self.rules)
        assert result["markers"] == final["markers"] == self.stderr
        assert len(result["events"]) == len(final["events"]) + 1, "native operation after final resource checkpoint"
        last = result["events"][-1]
        assert last["name"] == "read" and last["args"] == '0, "\\x21", 1' and last["result"] == "1", last
        return final

    def fail(self):
        diagnostic = traceback.format_exc()
        status = self.process.poll()
        if status is None:
            self.process.kill()  # Diagnostic recovery cannot make a test pass.
        try:
            extra, stderr = self.process.communicate(timeout=3)
            (self.directory / "post-failure.stdout").write_bytes(extra)
            self.stderr += stderr
        except BaseException as error:
            diagnostic += "\nfailed to collect: " + repr(error)
        (self.directory / "native.stderr").write_bytes(self.stderr)
        diagnostic += "\nstatus before recovery=%r after=%r\n" % (status, self.process.returncode)
        (self.directory / "diagnostic.txt").write_text(diagnostic)
        (self.directory / "failure-namespace.json").write_text(json.dumps(snapshot(self.cwd), indent=2) + "\n")
        print("atomic-file failure evidence: " + str(self.directory), file=sys.stderr)


class Suite:
    def __init__(self, group, executable):
        self.group = group
        self.executable = Path(executable).resolve()
        assert self.executable.is_file(), self.executable
        self.directory = Path(tempfile.mkdtemp(prefix="atomic-file-" + group + "-"))
        self.profile = ledger.verified_sites(self.executable, self.directory)
        self.started = time.monotonic()
        self.count = 0

    def case(self, label):
        assert time.monotonic() - self.started < 65, "finite oracle group exceeded 65 seconds"
        directory = self.directory / ("%02d-" % self.count + label)
        directory.mkdir()
        self.count += 1
        return directory

    def done(self):
        shutil.rmtree(self.directory)
        print("atomic-file group=%s cases=%d" % (self.group, self.count))

    def run(self, label, options=None, *, rules=(), setup=None, first=None,
            final=None, repair=None, baseline=None):
        session = Session(self, label, options or request(), rules=rules, setup=setup,
                          repair=repair, baseline=baseline)
        try:
            held = session.frame(1)
            common(held, session)
            if first:
                first(held, session)
            session.ack()
            released = session.frame(2)
            common(released, session)
            assert released["words"][40:72] == held["words"][40:72], "first-publication receipt was rewritten"
            if final:
                final(released, session, held)
            session.finish()
            return released, held
        except BaseException:
            session.fail()
            raise


def payload(options):
    return (DATA, b"", LARGE)[options[8]]


def directory(session):
    return session.cwd / ("moved" if session.request[7] == 4 else "anchor")


def name_path(session, value):
    return os.path.join(os.fsencode(directory(session)), value)


def contents(path):
    return Path(os.fsdecode(path)).read_bytes()


def candidate_contract(result):
    current = result["current"]
    draws = selected(result, "getrandom", "C")
    opens = selected(result, "openat", "C")
    assert current["entropy_calls"] == len(draws) and current["open_attempts"] == len(opens)
    assert current["collisions"] == sum(e["result"].startswith("-1 EEXIST ") for e in opens)
    pending, candidates = bytearray(), []
    for entry in draws:
        args = ledger.arguments(entry["args"])
        value = int(entry["result"].split()[0])
        assert args[2] == "GRND_NONBLOCK" and int(args[1]) == 16 - len(pending), entry
        if 0 < value <= int(args[1]):
            raw = ledger.quoted(args[0])
            assert len(raw) == value
            pending.extend(raw)
            if len(pending) == 16:
                candidates.append(b".tmp-" + pending.hex().encode())
                pending.clear()
    skipped = [value for value in candidates if value == result["destination"]]
    actual = [value for value in candidates if value != result["destination"]]
    assert current["excluded"] == len(skipped) and len(opens) == len(actual), (result, candidates)
    for entry, name in zip(opens, actual):
        args = ledger.arguments(entry["args"])
        assert args[0] == str(result["anchor_fd"]) and ledger.quoted(args[1]) == name
        assert set(args[2].split("|")) == {"O_RDWR", "O_CREAT", "O_EXCL", "O_NOCTTY", "O_NOFOLLOW", "O_CLOEXEC"} and args[3] == "0600", entry
    if result["temporary"]:
        assert actual and result["temporary"] == actual[-1] and result["temporary"] != result["destination"]
        assert re.fullmatch(rb"\.tmp-[0-9a-f]{32}", result["temporary"])


def common(result, session):
    value = result["current"]
    for key in ("file_synced", "directory_synced", "file_open", "anchor_open", "temporary_owned", "retained",
                "file_close_attempted", "remove_attempted", "directory_close_attempted", "cleanup_retained"):
        assert value[key] in (0, 1), (key, value)
    assert value["state"] <= 5 and value["visibility"] <= 2 and value["removal"] <= 3
    assert not any(value[key] for key in ("reserved0", "reserved1", "reserved2"))
    assert value["bytes"] <= session.request[2] and value["writes"] <= session.request[3]
    assert value["directory_syncs"] <= session.request[11]
    candidate_contract(result)
    file_fd, anchor_fd, parent_fd = result["file_fd"], result["anchor_fd"], result["parent_fd"]
    writes = [e for e in selected(result, "write", "W") if ledger.arguments(e["args"])[0] == str(file_fd)]
    assert value["writes"] == len(writes)
    confirmed = 0
    for entry in writes:
        args = ledger.arguments(entry["args"])
        requested, count = int(args[2]), int(entry["result"].split()[0])
        assert 0 < requested <= 1024, entry
        if 0 < count <= requested:
            confirmed += count
    assert value["bytes"] == confirmed, (value, writes)
    renames = selected(result, "renameat2", "M")
    assert value["renames"] == len(renames) <= 1, renames
    syncs = selected(result, "fsync")
    assert value["file_syncs"] == sum(e["args"] == str(file_fd) for e in syncs)
    assert value["directory_syncs"] == sum(e["args"] == str(anchor_fd) for e in syncs)
    for entry in renames:
        args = ledger.arguments(entry["args"])
        assert args[0] == args[2] == str(anchor_fd)
        assert ledger.quoted(args[1]) == result["temporary"] and ledger.quoted(args[3]) == result["destination"]
        assert args[4] == ("RENAME_NOREPLACE" if session.request[1] else "0")
    for entry in selected(result, "unlinkat"):
        args = ledger.arguments(entry["args"])
        assert args[0] == str(anchor_fd) and args[2] == "0"
        assert ledger.quoted(args[1]) == result["temporary"] != result["destination"], "cleanup touched destination or another name"
    for entry in selected(result, "mmap"):
        if "MAP_32BIT" in entry["args"]:
            assert entry["phase"] == "C", ("atomic continuation allocated", entry)
    raw_skipped = set()
    if session.repair:
        for entry in result["closes"]:
            if entry["ordinal"] == session.repair[0] and entry["result"].startswith("-1 EIO "):
                raw_skipped.add(int(entry["args"]))
        for entry in selected(result, "close", "Q"):
            raw_skipped.discard(int(entry["args"]))
    expected = ({parent_fd} if parent_fd in result["live"] else set()) | raw_skipped
    if value["file_open"]:
        expected.add(file_fd)
    if value["anchor_open"]:
        expected.add(anchor_fd)
    assert set(result["live"]) == expected, ("logical owners disagree with actual fd generations", value, result["live"], expected)
    assert bool(value["retained"]) == bool(result["mappings"] or value["file_open"] or value["anchor_open"] or value["temporary_owned"])
    if result["checkpoint"] == 2:
        assert value["state"] == 5 and not any(value[key] for key in ("file_open", "anchor_open", "temporary_owned", "retained"))
        assert not epoch(result, "B")[0]["events"] or session.request[0] in (4, 5)
        assert not epoch(result, "X")[0]["events"]
    if epoch(result, "M"):
        assert result["words"][113] == 1, "cached commit differs from first result"
    if (directory(session) / "sentinel").exists():
        assert (directory(session) / "sentinel").read_bytes() == b"anchor-sentinel\0\xff"


def expect_error(result, cause, stage, completed=None):
    assert (result["cause"], result["stage"]) == (cause, stage), (result["cause"], result["stage"], cause, stage)
    if completed is not None:
        assert result["completed"] == completed, (result["completed"], completed)


def published(result, session):
    current = result["current"]
    expect_error(result, 0, 0)
    assert current["visibility"] == 1 and current["file_synced"] == current["directory_synced"] == 1
    assert current["file_syncs"] == current["renames"] == current["directory_syncs"] == 1
    assert not any(current[key] for key in ("temporary_owned", "file_open", "anchor_open", "retained"))
    assert current["bytes"] == len(payload(session.request))
    target = name_path(session, result["destination"])
    assert contents(target) == payload(session.request)
    metadata = os.lstat(target)
    assert stat.S_ISREG(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600
    assert not os.path.lexists(name_path(session, result["temporary"]))
    assert not selected(result, "unlinkat"), "published cleanup attempted deletion"


def owner_group(suite):
    old_reader = []
    def setup(cwd):
        old_reader.append(os.open(cwd / "anchor/target", os.O_RDONLY | os.O_CLOEXEC))
    def old_reader_check(result, session):
        published(result, session)
        assert os.read(old_reader[0], len(OLD) + 1) == OLD, "replacement mutated an existing reader's inode"
    try:
        suite.run("replace-binary", setup=setup, first=old_reader_check)
    finally:
        for fd in old_reader:
            os.close(fd)
    suite.run("empty-zero-limits", request(payload=1, max_bytes=0, writes=0), first=published)
    suite.run("large-binary", request(payload=2), first=published)
    suite.run("no-replace-vacant", request(policy=1),
              setup=lambda c: (c / "anchor/target").unlink(), first=published)
    for parent in (4, 5):
        def check(result, session, parent=parent):
            published(result, session)
            if parent == 4:
                assert list((session.cwd / "anchor").iterdir()) == [], "replaced anchor pathname was mutated"
            else:
                assert list((session.cwd / "elsewhere").iterdir()) == [], "cwd-relative publication escaped the anchor"
        suite.run("parent-%d" % parent, request(parent=parent), first=check)
    for mode in (1, 2):
        def first(result, session):
            expect_error(result, 0, 0)
            assert result["current"]["state"] == 1 and result["current"]["visibility"] == 0
            assert result["current"]["file_open"] == result["current"]["anchor_open"] == result["current"]["temporary_owned"] == 1
            assert contents(name_path(session, result["temporary"])) == DATA
            assert contents(name_path(session, result["destination"])) == OLD
        def final(result, session, held, mode=mode):
            assert result["current"]["visibility"] == 0 and not selected(result, "renameat2", "M")
            assert contents(name_path(session, result["destination"])) == OLD
            temporary = name_path(session, result["temporary"])
            if mode == 1:
                assert contents(temporary) == DATA and result["words"][114] & 3 == 3
                assert not selected(result, "unlinkat")
            else:
                assert not os.path.lexists(temporary) and len(selected(result, "unlinkat", "A")) == 1
        suite.run("keep" if mode == 1 else "cleanup", request(mode=mode), first=first, final=final)
    def symlink(cwd):
        (cwd / "anchor/target").unlink()
        (cwd / "anchor/link-target").write_bytes(b"symlink-target\0\xff")
        os.symlink("link-target", cwd / "anchor/target")
    def check(result, session):
        published(result, session)
        assert (directory(session) / "link-target").read_bytes() == b"symlink-target\0\xff"
    suite.run("replace-symlink-leaf", setup=symlink, first=check)


def publication_group(suite):
    baseline, _ = suite.run("baseline", first=published)
    directory_sync = [entry for entry in selected(baseline, "fsync", "M") if entry["args"] == str(baseline["anchor_fd"])]
    assert len(directory_sync) == 1
    ordinal = directory_sync[0]["ordinal"]
    def held(result, session):
        expect_error(result, 1005, 9, 0)
        current = result["current"]
        assert current["visibility"] == 1 and current["file_synced"] == 1 and current["directory_synced"] == 0
        assert current["file_syncs"] == current["renames"] == current["directory_syncs"] == 1
        assert current["state"] == 3 and current["anchor_open"] == current["retained"] == 1
        assert current["file_open"] == current["temporary_owned"] == 0
        assert current["latest_cause"] == 1005 and current["latest_stage"] == 9
        assert result["words"][110:113] == (1005, 9, 0)
        assert contents(name_path(session, result["destination"])) == DATA
        assert not os.path.lexists(name_path(session, result["temporary"]))
        assert not selected(result, "unlinkat"), "post-publication failure attempted rollback"
        assert len(result["mappings"]) > 0 and set(result["live"]) == {result["parent_fd"], result["anchor_fd"]}
    def retried(result, session, first):
        current = result["current"]
        assert current["visibility"] == current["file_synced"] == current["directory_synced"] == 1
        assert current["renames"] == 1 and current["directory_syncs"] == 2
        assert current["latest_cause"] == current["latest_stage"] == current["latest_completed"] == 0
        assert result["words"][72:80] == (0, 0, 1, 0, 2, 0, 0, 1)
        assert result["words"][110:113] == (1005, 9, 0), "successful retry erased first fatal diagnostic"
        assert len(selected(result, "fsync", "D")) == 1 and len(selected(result, "renameat2", "M")) == 1
        assert not selected(result, "unlinkat") and contents(name_path(session, result["destination"])) == DATA
    suite.run("published-directory-sync-retry", request(mode=3, directory_syncs=2),
              rules=[rule("fsync", when=ordinal, error="EIO")], baseline=baseline,
              first=held, final=retried)
    def exhausted(result, session, first):
        current = result["current"]
        assert current["visibility"] == current["file_synced"] == 1 and current["directory_synced"] == 0
        assert current["renames"] == current["directory_syncs"] == 1
        # Failure keeps the first primary EIO; latest receipt diagnostic tells
        # the sync-budget failure apart. Cleanup later clears latest_error.
        assert result["words"][72:80] == (1005, 9, 1, 8, 1, 1, 0, 1)
        assert result["words"][110:113] == (1005, 9, 0)
        assert not selected(result, "fsync", "D") and not selected(result, "unlinkat")
        assert contents(name_path(session, result["destination"])) == DATA
    suite.run("published-sync-budget-exhaustion", request(mode=3, directory_syncs=1),
              rules=[rule("fsync", when=ordinal, error="EIO")], baseline=baseline,
              first=held, final=exhausted)
    def conflict(result, session):
        expect_error(result, 1017, 7, 0)
        current = result["current"]
        assert current["visibility"] == 0 and current["file_synced"] == 1 and current["directory_syncs"] == 0
        assert current["temporary_owned"] == current["anchor_open"] == current["retained"] == 1 and current["file_open"] == 0
        assert contents(name_path(session, result["destination"])) == OLD
        assert contents(name_path(session, result["temporary"])) == DATA
    def conflict_released(result, session, first):
        assert result["current"]["visibility"] == 0 and contents(name_path(session, result["destination"])) == OLD
        assert not os.path.lexists(name_path(session, result["temporary"]))
    suite.run("no-replace-conflict", request(policy=1), first=conflict, final=conflict_released)
    # Both real owners reach a precommit checkpoint in the same directory.
    # No timing ratio or guessed sleep establishes the contention precondition.
    shared = suite.directory / "contention-cwd"
    shared.mkdir()
    (shared / "anchor").mkdir()
    (shared / "elsewhere").mkdir()
    (shared / "anchor/sentinel").write_bytes(b"anchor-sentinel\0\xff")
    (shared / "regular").write_bytes(b"regular-parent\0\xfe")
    contenders = []
    try:
        for index, kind in enumerate((0, 2)):
            item = Session(suite, "no-replace-contender-%d" % index,
                           request(mode=8, policy=1, payload=kind), cwd=shared)
            contenders.append(item)
            ready = item.frame(0)
            common(ready, item)
            assert ready["current"]["state"] == 1 and ready["current"]["temporary_owned"] == 1
            assert ready["current"]["renames"] == 0 and contents(name_path(item, ready["temporary"])) == payload(item.request)
            assert not (shared / "anchor/target").exists()
        assert contenders[0].frames[0]["temporary"] != contenders[1].frames[0]["temporary"]
        for item in contenders:
            item.ack()
        held = [item.frame(1) for item in contenders]
        for item, result in zip(contenders, held):
            common(result, item)
        winners = [index for index, result in enumerate(held) if result["cause"] == 0 and result["current"]["visibility"] == 1]
        losers = [index for index, result in enumerate(held) if result["cause"] == 1017 and result["current"]["visibility"] == 0]
        assert len(winners) == len(losers) == 1 and winners[0] != losers[0], [(x["cause"], x["current"]) for x in held]
        assert (shared / "anchor/target").read_bytes() == payload(contenders[winners[0]].request)
        for item in contenders:
            item.ack()
        for item, first in zip(contenders, held):
            result = item.frame(2)
            common(result, item)
            assert result["words"][40:72] == first["words"][40:72]
            item.finish()
        assert not list((shared / "anchor").glob(".tmp-*"))
        assert (shared / "anchor/target").read_bytes() == payload(contenders[winners[0]].request)
    except BaseException:
        for item in contenders:
            if item.process.poll() is None:
                item.fail()
        raise


def bounds_group(suite):
    def rejected(cause, stage):
        def check(result, session):
            expect_error(result, cause, stage, 0)
            current = result["current"]
            assert current["visibility"] == 0 and current["bytes"] == current["writes"] == current["renames"] == 0
            assert not result["mappings"] and not epoch(result, "C")[0]["events"], "invalid input had effects"
            assert snapshot(session.cwd) == session.initial_namespace
        return check
    for options in (request(names=0), request(names=1025), request(entropy=0), request(entropy=1048577), request(directory_syncs=0)):
        suite.run("invalid-options-%d" % suite.count, options, first=rejected(2, 1))
    for destination in (2, 3, 4, 5, 6, 7, 8, 9, 12):
        suite.run("invalid-destination-%d" % destination, request(destination=destination), first=rejected(3, 1))
    for destination in (10, 11):
        suite.run("valid-destination-%d" % destination, request(destination=destination), first=published)
    for parent, cause in ((1, 10006), (2, 11009), (3, 10007)):
        def check(result, session, cause=cause):
            expect_error(result, cause, 3, 0)
            assert result["current"]["retained"] == 1 and not selected(result, "unlinkat")
            assert result["current"]["writes"] == result["current"]["renames"] == 0
            assert snapshot(session.cwd) == session.initial_namespace
        suite.run("invalid-parent-%d" % parent, request(parent=parent), first=check)
    for write_case in (1, 2, 5):
        def check(result, session):
            expect_error(result, 5, 4, 0)
            assert result["current"]["state"] == 1 and result["current"]["writes"] == result["current"]["bytes"] == 0
            assert contents(name_path(session, result["temporary"])) == b""
            assert not payload_writes(result), "invalid view reached owned file writer"
        suite.run("write-view-%d" % write_case, request(mode=2, write_case=write_case), first=check)
    def empty(result, session):
        expect_error(result, 0, 0)
        assert result["current"]["writes"] == result["current"]["bytes"] == 0
        assert not payload_writes(result) and contents(name_path(session, result["temporary"])) == b""
    suite.run("empty-write-zero-budget", request(mode=2, write_case=4, writes=0, max_bytes=0), first=empty)
    def recovery(result, session, flag, cause, length):
        expect_error(result, 0, 0, 0)
        current = result["current"]
        assert current["state"] == 1 and current["bytes"] == length and current["writes"] == 1
        assert current["latest_cause"] == current["latest_stage"] == 0 and result["words"][110:113] == (0, 0, 0)
        assert result["words"][114] & flag
        assert contents(name_path(session, result["temporary"])) == DATA[:length]
    suite.run("bounds-then-recover", request(mode=2, write_case=8),
              first=lambda r, s: recovery(r, s, 32, 5, 6))
    suite.run("byte-limit-then-recover", request(mode=2, write_case=9, max_bytes=5),
              first=lambda r, s: recovery(r, s, 64, 6, 3))


def fault_writer(cause, confirmed=0, physical=b"", completed=0):
    def check(result, session):
        expect_error(result, cause, 4, completed)
        current = result["current"]
        assert current["state"] == 2 and current["visibility"] == 0
        assert current["bytes"] == confirmed and current["file_syncs"] == current["renames"] == current["directory_syncs"] == 0
        assert current["file_open"] == current["anchor_open"] == current["temporary_owned"] == 1
        assert contents(name_path(session, result["temporary"])) == physical
        assert contents(name_path(session, result["destination"])) == OLD
        assert result["words"][110:113] == (cause, 4, completed), "first fatal write prefix was changed by commit replay"
    return check


def faults_group(suite):
    baseline, _ = suite.run("baseline", first=published)
    allocations = baseline["source"]["allocations"]
    assert allocations, "no source allocation position reached"
    for allocation in allocations:
        assert allocation["phase"] == "C" if "phase" in allocation else True
        cause, stage = (10004, 3) if allocation["length"] == 37 else (4, 2)
        def check(result, session, cause=cause, stage=stage):
            expect_error(result, cause, stage, 0)
            current = result["current"]
            assert current["visibility"] == current["bytes"] == current["writes"] == current["renames"] == 0
            assert not selected(result, "unlinkat") and snapshot(session.cwd) == session.initial_namespace
            assert result["words"][110:113] == (cause, stage, 0)
        suite.run("source-oom-%d" % allocation["ordinal"],
                  rules=[rule("mmap", when=allocation["ordinal"], error="ENOMEM")],
                  first=check, baseline=baseline)
    writes = [entry for entry in selected(baseline, "write", "W") if ledger.arguments(entry["args"])[0] == str(baseline["file_fd"])]
    assert len(writes) == 1
    write_ordinal = writes[0]["ordinal"]
    for label, item, cause in (("write-eio", rule("write", when=write_ordinal, error="EIO"), 1005),
                               ("write-enospc", rule("write", when=write_ordinal, error="ENOSPC"), 1028),
                               ("write-zero", rule("write", when=write_ordinal, retval=0), 9),
                               ("write-overcount", rule("write", when=write_ordinal, retval=7), 10)):
        suite.run(label, rules=[item], first=fault_writer(cause), baseline=baseline)
    suite.run("write-all-eintr-recovers", rules=[rule("write", when=write_ordinal, error="EINTR")],
              first=published, baseline=baseline)
    def explicit_eintr(result, session):
        published(result, session)
        assert result["words"][114] & 16 and result["current"]["writes"] == 2
        assert result["words"][110:113] == (0, 0, 0)
    suite.run("direct-write-eintr-recovers", request(write_case=7),
              rules=[rule("write", when=write_ordinal, error="EINTR")], first=explicit_eintr,
              baseline=baseline)
    suite.run("write-eintr-budget", request(writes=3),
              rules=[rule("write", when=write_ordinal, last=write_ordinal + 2, error="EINTR")],
              first=fault_writer(7), baseline=baseline)
    suite.run("write-zero-budget", request(writes=0), first=fault_writer(7))
    def synthetic_positive(result, session):
        expect_error(result, 0, 0, 0)
        assert result["current"]["state"] == 1 and result["current"]["bytes"] == 3 and result["current"]["writes"] == 1
        # strace skipped this write, so its reported positive count has no
        # physical bytes. Never treat it as evidence of a real file prefix.
        assert contents(name_path(session, result["temporary"])) == b""
        assert result["current"]["visibility"] == 0 and not selected(result, "renameat2", "M")
    suite.run("synthetic-positive-count-not-physical", request(mode=2, write_case=6),
              rules=[rule("write", when=write_ordinal, retval=3)], first=synthetic_positive,
              baseline=baseline)
    large, _ = suite.run("real-prefix-baseline", request(payload=2), first=published)
    large_writes = [entry for entry in selected(large, "write", "W") if ledger.arguments(entry["args"])[0] == str(large["file_fd"])]
    assert len(large_writes) > 1 and ledger.arguments(large_writes[0]["args"])[2] == "1024" and large_writes[0]["result"] == "1024"
    suite.run("real-write-prefix-then-eio", request(payload=2),
              rules=[rule("write", when=large_writes[1]["ordinal"], error="EIO")],
              first=fault_writer(1005, 1024, LARGE[:1024], 1024), baseline=large)
    file_sync = [entry for entry in selected(baseline, "fsync", "M") if entry["args"] == str(baseline["file_fd"])]
    assert len(file_sync) == 1
    for label, item, cause in (("file-sync-eio", rule("fsync", when=file_sync[0]["ordinal"], error="EIO"), 1005),
                               ("file-sync-invalid-count", rule("fsync", when=file_sync[0]["ordinal"], retval=1), 1901)):
        def check(result, session, cause=cause):
            expect_error(result, cause, 5, 0)
            current = result["current"]
            assert current["file_synced"] == current["renames"] == current["directory_syncs"] == current["visibility"] == 0
            assert current["file_syncs"] == current["file_open"] == current["temporary_owned"] == current["anchor_open"] == 1
            assert contents(name_path(session, result["temporary"])) == DATA and contents(name_path(session, result["destination"])) == OLD
        suite.run(label, rules=[item], first=check, baseline=baseline)
    close_file = [entry for entry in selected(baseline, "close", "M") if entry["args"] == str(baseline["file_fd"])]
    assert len(close_file) == 1
    def closed_file(result, session):
        expect_error(result, 11005, 6, 0)
        current = result["current"]
        assert current["file_synced"] == current["temporary_owned"] == current["anchor_open"] == 1
        assert current["file_open"] == current["renames"] == current["directory_syncs"] == current["visibility"] == 0
        assert current["file_close_attempted"] == 1 and current["file_close_error"] == 5
        assert contents(name_path(session, result["temporary"])) == DATA and contents(name_path(session, result["destination"])) == OLD
    suite.run("file-close-eio", request(mode=6, repair=baseline["file_fd"]),
              rules=[rule("close", when=close_file[0]["ordinal"], error="EIO")],
              repair=(close_file[0]["ordinal"], "M"), first=closed_file, baseline=baseline)
    rename = selected(baseline, "renameat2", "M")
    assert len(rename) == 1
    for label, item, cause, visibility in (("rename-eio", rule("renameat2", when=rename[0]["ordinal"], error="EIO"), 1005, 2),
                                         ("rename-eintr", rule("renameat2", when=rename[0]["ordinal"], error="EINTR"), 1004, 2),
                                         ("rename-invalid-count", rule("renameat2", when=rename[0]["ordinal"], retval=1), 1901, 2),
                                         ("rename-enosys", rule("renameat2", when=rename[0]["ordinal"], error="ENOSYS"), 1038, 0)):
        def check(result, session, cause=cause, visibility=visibility):
            expect_error(result, cause, 7, 0)
            current = result["current"]
            assert current["visibility"] == visibility and current["renames"] == current["file_synced"] == 1
            assert current["directory_syncs"] == 0 and current["file_open"] == 0
            assert current["temporary_owned"] == current["anchor_open"] == current["retained"] == 1
            # The injection skipped rename, independently observed here. The
            # API must still report Unconfirmed for ambiguous native results.
            assert contents(name_path(session, result["temporary"])) == DATA and contents(name_path(session, result["destination"])) == OLD
        suite.run(label, rules=[item], first=check, baseline=baseline)
    directory_sync = [entry for entry in selected(baseline, "fsync", "M") if entry["args"] == str(baseline["anchor_fd"])]
    assert len(directory_sync) == 1
    def invalid_directory_sync(result, session):
        expect_error(result, 1901, 9, 0)
        current = result["current"]
        assert current["visibility"] == current["file_synced"] == current["anchor_open"] == current["retained"] == 1
        assert current["directory_synced"] == current["temporary_owned"] == current["file_open"] == 0
        assert contents(name_path(session, result["destination"])) == DATA and not selected(result, "unlinkat")
    suite.run("directory-sync-invalid-count", rules=[rule("fsync", when=directory_sync[0]["ordinal"], retval=1)],
              first=invalid_directory_sync, baseline=baseline)
    cleanup, _ = suite.run("cleanup-baseline", request(mode=2), first=lambda r, s: None)
    unlink = selected(cleanup, "unlinkat", "A")
    assert len(unlink) == 1
    for mode in (4, 5):
        def first(result, session):
            expect_error(result, 0, 0)
            assert contents(name_path(session, result["temporary"])) == DATA and contents(name_path(session, result["destination"])) == OLD
        def final(result, session, held, mode=mode):
            current = result["current"]
            assert result["words"][80:90] == (11005, 10, 1, 0, 1, 3, 5, 0, 0, 1)
            assert current["remove_error"] == 5 and result["words"][110:113] == (11005, 10, 0)
            assert contents(name_path(session, result["destination"])) == OLD
            if mode == 4:
                assert result["words"][90:100] == (0, 0, 0, 0, 1, 1, 0, 1, 0, 0)
                assert not os.path.lexists(name_path(session, result["temporary"]))
            else:
                assert result["words"][90:100] == (0, 0, 0, 0, 0, 0, 0, 1, 0, 0)
                assert contents(name_path(session, result["temporary"])) == DATA and result["words"][114] & 3 == 3
        suite.run("unlink-retry" if mode == 4 else "unlink-keep", request(mode=mode),
                  rules=[rule("unlinkat", when=unlink[0]["ordinal"], error="EIO")],
                  first=first, final=final, baseline=cleanup)
    close_directory = [entry for entry in selected(baseline, "close", "M") if entry["args"] == str(baseline["anchor_fd"])]
    assert len(close_directory) == 1
    def closed_directory(result, session):
        expect_error(result, 11005, 10, 0)
        current = result["current"]
        assert current["visibility"] == current["file_synced"] == current["directory_synced"] == 1
        assert current["file_open"] == current["anchor_open"] == current["temporary_owned"] == current["retained"] == 0
        assert current["directory_close_attempted"] == 1 and current["directory_close_error"] == 5
        assert contents(name_path(session, result["destination"])) == DATA and not selected(result, "unlinkat")
    suite.run("directory-close-eio-after-publication", request(mode=7, repair=baseline["anchor_fd"]),
              rules=[rule("close", when=close_directory[0]["ordinal"], error="EIO")],
              repair=(close_directory[0]["ordinal"], "M"), first=closed_directory, baseline=baseline)


def controls():
    count = ledger.controls()
    words = [0] * WORDS
    words[:4] = [1, 1, 0, 999]
    words[6], words[7] = 37, 6
    def result(value):
        return dict(words=tuple(value), temporary=b".tmp-" + b"0" * 32,
                    destination=b"target" + bytes(249))
    assert decode(result(words))["destination"] == b"target"
    count += 1
    for offset, value in ((119, 1), (6, 36), (7, 256)):
        bad = list(words)
        bad[offset] = value
        try:
            decode(result(bad))
        except AssertionError:
            count += 1
        else:
            raise AssertionError("atomic oracle accepted malformed frame metadata")
    # Check the actual descriptor's two-chunk transport and reject framing
    # drift, without launching a compiler, native program or tracing process.
    raw = struct.pack("<128Q", *words) + b".tmp-" + b"0" * 32 + b"target" + bytes(249)
    def write(data):
        encoded = '"' + ''.join('\\x%02x' % byte for byte in data) + '"'
        return '[0000000000401002] write(1, %s, %d) = %d\n' % (encoded, len(data), len(data))
    with tempfile.TemporaryDirectory(prefix="atomic-frame-cpu-") as directory:
        trace = Path(directory) / "trace"
        text = write(raw[:1024]) + write(raw[1024:])
        trace.write_text(text + '[0000000000401002] read(0, ')
        assert checkpoint(trace, raw, time.monotonic() + 1) == text
        count += 1
        wrong = write(raw[:1024]) + write(raw[1024:] + b'x')
        trace.write_text(wrong)
        try:
            checkpoint(trace, raw, time.monotonic() + 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("atomic oracle accepted frame boundary drift")
    range_rule = rule("write", when=4, last=6, error="EINTR")
    assert injection(range_rule) == "write:error=EINTR:when=4..6"
    fake = dict(events=[dict(name='write', ordinal=i, index=i, result='-1 EINTR (Interrupted system call) (INJECTED)') for i in range(4, 7)])
    ledger.check_injections(fake, [range_rule])
    count += 1
    assert "ftruncate" in command("not-executed", "not-written", [range_rule])[10]
    count += 1
    markers = ('[0000000000401002] write(2, "\\x57", 1) = 1\n'
               '[0000000000401002] write(2, "\\x77", 1) = 1\n')
    assert not payload_writes(dict(events=ledger.events(markers)[0], file_fd=5))
    count += 1
    real = markers.replace('[0000000000401002] write(2, "\\x77", 1) = 1\n',
                           '[0000000000401002] write(5, "\\x00\\xff\\x80\\x61\\x0d\\x0a", 6) = 6\n'
                           '[0000000000401002] write(2, "\\x77", 1) = 1\n')
    assert len(payload_writes(dict(events=ledger.events(real)[0], file_fd=5))) == 1
    count += 1
    print("atomic-file oracle CPU-controls=%d native-cases=0" % count)


def main():
    assert len(sys.argv) >= 2
    group = sys.argv[1]
    if group == "controls":
        assert len(sys.argv) == 2
        controls()
        return
    assert group in ("owner", "publication", "faults", "bounds"), group
    assert len(sys.argv) == 3
    suite = Suite(group, sys.argv[2])
    globals()[group + "_group"](suite)
    suite.done()


if __name__ == "__main__":
    main()
