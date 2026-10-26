"""Independent Linux filesystem oracle; this is test machinery, not stdlib.

No fd is inherited by the traced child. TempFile's probe pauses after releasing
its owners so namespace, native descriptors, and verified source mappings are
checked before exit can conceal leaks. Synthetic entropy is confined to strace.
"""
from collections import Counter
import errno
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

MAX = ledger.U64_MAX
DATA = b"\0\xff\x80a\r\n"
LARGE = DATA + bytes((i * 17) & 255 for i in range(1024)) * 33
ZERO_NAME = b".tmp-" + b"0" * 32
ZERO_DRAW = "00" * 16
PACKET = 549


def number(entry):
    return int(entry["result"].split()[0], 0)


def selected(result, name, phase=None):
    return [event for event in result["events"] if event["name"] == name
            and (phase is None or event["phase"] == phase)]


def epoch(result, phase, index=0):
    return [item["events"] for item in result["epochs"] if item["phase"] == phase][index]


def receipt(words, at, expected):
    assert tuple(words[at:at + 10]) == tuple(expected), (at, words[at:at + 10], expected)


def rule(syscall, *, when=1, error=None, retval=None, poke=None, repeat=False):
    result = dict(syscall=syscall, when=when, repeat=repeat)
    if error is not None:
        result["error"] = error
    if retval is not None:
        result["retval"] = retval
    if poke is not None:
        result["poke"] = poke
    assert (error is None) != (retval is None)
    return result


def injection(item):
    value = item["syscall"]
    if "error" in item:
        value += ":error=" + item["error"]
    else:
        value += ":retval=" + str(item["retval"])
    if "poke" in item:
        value += ":poke_exit=@arg1=" + item["poke"]
    return value + ":when=" + str(item["when"]) + ("+" if item["repeat"] else "")


def command(executable, trace, rules, args=()):
    values = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
              "-e", "signal=none", "-e", "trace=" + ledger.TRACE, "-o", str(trace)]
    for item in rules:
        values += ["-e", "inject=" + injection(item)]
    return values + [str(executable)] + list(args)


def read_exact(stream, count, deadline, evidence):
    data = bytearray()
    while len(data) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0, ("native report timeout", len(data), count)
        ready, _, _ = select.select([stream], [], [], remaining)
        assert ready, ("native report timeout", len(data), count)
        chunk = os.read(stream.fileno(), count - len(data))
        assert chunk, ("premature native report EOF", len(data), count)
        data.extend(chunk)
        evidence.write_bytes(data)
    return bytes(data)


def checkpoint(trace, packet, deadline):
    # The next blocking ACK read may be an incomplete trace line. The completed
    # packet write is the precise release checkpoint and must contain our bytes.
    while time.monotonic() < deadline:
        text = trace.read_text() if trace.exists() else ""
        lines = text.splitlines(keepends=True)
        for index, line in enumerate(lines):
            if not line.endswith("\n"):
                continue
            match = ledger.LINE.fullmatch(line.rstrip("\n"))
            if match and match[2] == "write":
                args = ledger.arguments(match[3])
                if len(args) == 3 and args[0] == "1" and args[2] == str(PACKET) and match[4] == str(PACKET):
                    assert ledger.quoted(args[1]) == packet, "trace/native packet disagreement"
                    return "".join(lines[:index + 1])
        time.sleep(0.005)
    raise AssertionError("completed native report was not published in trace")


def snapshot(directory):
    result = {}
    for root, dirs, files in os.walk(os.fsencode(directory), followlinks=False):
        for name in dirs + files:
            path = os.path.join(root, name)
            metadata = os.lstat(path)
            value = dict(mode=oct(stat.S_IMODE(metadata.st_mode)), type=stat.S_IFMT(metadata.st_mode), size=metadata.st_size)
            if stat.S_ISLNK(metadata.st_mode):
                value["target_hex"] = os.readlink(path).hex()
            elif stat.S_ISREG(metadata.st_mode):
                contents = Path(os.fsdecode(path)).read_bytes()
                value["data_hex"] = contents[:35000].hex()
            result[os.path.relpath(path, os.fsencode(directory)).hex()] = value
    return result


class Suite:
    def __init__(self, group, executable):
        self.group = group
        self.executable = Path(executable).resolve()
        assert self.executable.is_file(), self.executable
        self.directory = Path(tempfile.mkdtemp(prefix="temp-file-" + group + "-"))
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
        print("temp-file group=%s cases=%d" % (self.group, self.count))

    def owner(self, label, *, mode=0, names=8, entropy=16, excluded=0, parent=0,
              rules=(), setup=None, check=None, repair=None, baseline=None):
        directory = self.case(label)
        cwd = directory / "cwd"
        cwd.mkdir()
        (cwd / "anchor").mkdir()
        (cwd / "anchor/sentinel").write_bytes(b"anchor-sentinel\0\xff")
        (cwd / "regular").write_bytes(b"regular-parent\0\xfe")
        if setup:
            setup(cwd)
        initial_filesystem = snapshot(cwd)
        request = struct.pack("<5Q", mode, names, entropy, excluded, parent)
        (directory / "request.bin").write_bytes(request)
        trace = directory / "syscalls.log"
        cmd = command(self.executable, trace, rules)
        (directory / "command.json").write_text(json.dumps(cmd, indent=2) + "\n")
        process = None
        stderr = b""
        try:
            process = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, bufsize=0, umask=0o022)
            process.stdin.write(request)
            packet = read_exact(process.stdout, PACKET, time.monotonic() + 15, directory / "response.bin")
            words = struct.unpack("<64Q", packet[:512])
            name = packet[512:]
            prefix = checkpoint(trace, packet, time.monotonic() + 2)
            (directory / "pre-exit.trace").write_text(prefix)
            child = words[13]
            children = Path("/proc/%d/task/%d/children" % (process.pid, process.pid)).read_text().split()
            assert children == [str(child)], ("report pid does not identify traced child", children, child)
            descriptors = sorted(os.listdir("/proc/%d/fd" % child))
            (directory / "pre-exit-fds.json").write_text(json.dumps(descriptors) + "\n")
            assert descriptors == ["0", "1", "2"], ("fd survived pre-exit cleanup", descriptors)
            result = ledger.analyze(prefix, self.profile, directory,
                                    repaired_close=repair[0] if repair else None,
                                    repair_phase=repair[1] if repair else "A")
            ledger.check_injections(result, rules)
            assert words[60] == 5 and words[63] == 0 and words[16:20] == (0, 0, 0, 0), words
            assert not epoch(result, "B") or mode == 3 or mode == 4, epoch(result, "B")
            assert not epoch(result, "X"), epoch(result, "X")
            receipt(words, 50, [0] * 10)
            assert (cwd / "regular").read_bytes() == b"regular-parent\0\xfe"
            anchor = cwd / ("moved" if mode == 7 and words[0] == 0 else "anchor")
            assert (anchor / "sentinel").read_bytes() == b"anchor-sentinel\0\xff"
            candidate_contract(words, name, result, excluded)
            result.update(words=words, name=name, directory=directory)
            if baseline is not None:
                bind_injection(baseline, result, rules)
            if check:
                check(words, name, result, cwd)
            if words[0] != 0:
                assert snapshot(cwd) == initial_filesystem, "failed creation changed the namespace or existing data"
            (directory / "filesystem.json").write_text(json.dumps(snapshot(cwd), indent=2) + "\n")
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            extra, stderr = process.communicate(timeout=3)
            (directory / "native.stderr").write_bytes(stderr)
            assert process.returncode == 0 and extra == b"", ("native termination", process.returncode, extra, stderr)
            final = ledger.analyze(trace.read_text(), self.profile, directory,
                                   repaired_close=repair[0] if repair else None,
                                   repair_phase=repair[1] if repair else "A")
            ledger.check_injections(final, rules)
            assert stderr == result["markers"] == final["markers"], (stderr, result["markers"], final["markers"])
            assert len(final["events"]) == len(result["events"]) + 1, "native work after release checkpoint"
            ack = final["events"][-1]
            assert ack["name"] == "read" and ack["args"] == '0, "\\x21", 1' and ack["result"] == "1", ack
            return result
        except BaseException:
            details = traceback.format_exc()
            if process is not None:
                status_before = process.poll()
                # Killing is failure recovery, never accepted resource evidence.
                if status_before is None:
                    process.kill()
                try:
                    extra, captured = process.communicate(timeout=3)
                    stderr += captured
                    (directory / "post-failure.stdout").write_bytes(extra)
                except BaseException as error:
                    details += "\nfailure collection: " + repr(error)
                details += "\nnative/tracer status before recovery=%r final=%r\n" % (status_before, process.returncode)
            (directory / "native.stderr").write_bytes(stderr)
            (directory / "diagnostic.txt").write_text(details)
            (directory / "filesystem.json").write_text(json.dumps(snapshot(cwd), indent=2) + "\n")
            print("temp-file failure evidence: " + str(directory), file=sys.stderr)
            raise

    def primitive(self, label, args, *, setup, check, status=0, rules=(), bounds=False, profile=None, executable=None):
        directory = self.case(label)
        cwd = directory / "cwd"
        cwd.mkdir()
        if not bounds:
            (cwd / "left").mkdir()
            (cwd / "right").mkdir()
        setup(cwd)
        actual_args = args(cwd) if callable(args) else args
        trace = directory / "syscalls.log"
        cmd = command(executable or self.executable, trace, rules, actual_args)
        # Preserve byte argv without JSON's surrogate handling changing it.
        (directory / "command.json").write_text(json.dumps([os.fsencode(x).hex() for x in cmd], indent=2) + "\n")
        try:
            process = subprocess.run(cmd, cwd=cwd, input=b"", stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, timeout=15, umask=0o022)
            (directory / "native.stderr").write_bytes(process.stderr)
            (directory / "native.stdout").write_bytes(process.stdout)
            (directory / "exit-status.txt").write_text(str(process.returncode) + "\n")
            assert process.returncode == status and not process.stdout and not process.stderr, (process.returncode, status, process.stdout, process.stderr)
            result = ledger.analyze(trace.read_text(), profile or self.profile, directory)
            ledger.check_injections(result, rules)
            assert not result["source"]["allocations"], "allocation-free file primitives allocated"
            check(cwd, result)
            return result
        except BaseException:
            (directory / "diagnostic.txt").write_text(traceback.format_exc())
            (directory / "filesystem.json").write_text(json.dumps(snapshot(cwd), indent=2) + "\n")
            print("temp-file failure evidence: " + str(directory), file=sys.stderr)
            raise


def candidate_contract(words, name, result, excluded):
    """Compare names with actual returned entropy, not a second RNG/hash model."""
    body = epoch(result, "C")
    draws = [entry for entry in body if entry["name"] == "getrandom"]
    opens = [entry for entry in body if entry["name"] == "openat"]
    assert words[5] == len(opens) and words[8] == len(draws), (words, draws, opens)
    assert words[6] == sum(entry["result"].startswith("-1 EEXIST ") for entry in opens)
    pending, candidates = bytearray(), []
    for event in draws:
        args = ledger.arguments(event["args"])
        count = number(event)
        assert args[2] == "GRND_NONBLOCK", event
        requested = int(args[1])
        assert requested == 16 - len(pending), (event, pending)
        if 0 < count <= requested:
            raw = ledger.quoted(args[0])
            assert len(raw) == count, event
            pending.extend(raw)
            if len(pending) == 16:
                candidates.append(b".tmp-" + pending.hex().encode())
                pending.clear()
    expected_excluded = ZERO_NAME if excluded == 1 else None
    opened, skipped = [], 0
    for candidate in candidates:
        if candidate == expected_excluded:
            skipped += 1
        else:
            opened.append(candidate)
    assert words[7] == skipped and len(opened) == len(opens), (words, candidates, opens)
    for candidate, event in zip(opened, opens):
        args = ledger.arguments(event["args"])
        assert args[0] == str(words[11]) and ledger.quoted(args[1]) == candidate, event
        required = {"O_RDWR", "O_CREAT", "O_EXCL", "O_NOFOLLOW", "O_CLOEXEC", "O_NOCTTY"}
        assert set(args[2].split("|")) == required and args[3] == "0600", event
    if words[0] == 0:
        assert words[1:4] == (0, 1, 0) and words[12] == 37, words
        assert len(candidates) and name == candidates[-1] and re.fullmatch(rb"\.tmp-[0-9a-f]{32}", name), (name, candidates)
        assert words[4] == len(candidates), words
        assert words[10] != MAX and words[11] != MAX and len({words[9], words[10], words[11]}) == 3, words
        cloexec = selected(result, "fcntl")
        for fd in (words[10], words[11]):
            assert any(ledger.arguments(event["args"]) == [str(fd), "F_GETFD"] and event["result"] == "0x1 (flags FD_CLOEXEC)" for event in cloexec), (fd, cloexec)
    else:
        assert words[10] == MAX and words[12] == 0 and name == bytes(37), words


def ordinary(words, name, result, cwd, mode=0):
    assert words[0] == 0 and words[61:63] == (0, 0), words
    assert words[4:8] == (1, 1, 0, 0), words
    kept = mode in (1, 10, 11)
    removed = 0 if kept else (2 if mode == 8 else 1)
    receipt(words, 20, [0, 0, int(mode != 2), 0, int(not kept), removed, 0, 1, 0, 0])
    receipt(words, 40, [0] * 10)
    base = os.fsencode(cwd / ("moved" if mode == 7 else "anchor"))
    target = os.path.join(base, name)
    if kept:
        expected = b"" if mode == 11 else (LARGE if mode == 10 else DATA)
        assert Path(os.fsdecode(target)).read_bytes() == expected
        metadata = os.lstat(target)
        assert stat.S_ISREG(metadata.st_mode) and stat.S_IMODE(metadata.st_mode) == 0o600, metadata
        assert words[34:36] == (1, 2), words
    else:
        assert not os.path.lexists(target), target
    if mode == 2:
        assert words[31:33] == (0, 2) and len(selected(result, "close", "F")) == 1, words
    if mode == 7:
        assert list((cwd / "anchor").iterdir()) == [], "replacement anchor was mutated"
        assert len(selected(result, "renameat2", "R")) == 1
    if mode == 8:
        assert len(selected(result, "unlinkat", "U")) == 1
        assert selected(result, "unlinkat", "A")[0]["result"].startswith("-1 ENOENT ")
    if mode == 9:
        assert epoch(result, "C", 1) == [], "active create performed native effects"
    expected_leaves = {b"sentinel"} | ({name} if kept else set())
    assert set(os.listdir(base)) == expected_leaves, (base, os.listdir(base), expected_leaves)


def creation_failure(cause, stage, retained, *, parent=0, stats=None):
    def check(words, name, result, cwd):
        assert words[0:4] == (cause, stage, 4 if retained else 0, int(retained)), words
        assert words[61:63] == (cause, stage), words
        assert not selected(result, "unlinkat"), "unowned candidate was unlinked"
        assert words[10] == MAX
        if stats is not None:
            assert words[4:9] == tuple(stats), (words[4:9], stats)
        anchor_owned = words[11] != MAX
        receipt(words, 20, [0, 0, 0, 0, 0, 0, 0, int(anchor_owned), 0, 0])
        receipt(words, 40, [0] * 10)
        if stage == 1:
            assert not epoch(result, "C"), "invalid input caused native effects"
        assert (cwd / "regular").read_bytes() == b"regular-parent\0\xfe"
    return check


def bind_injection(before, after, rules):
    for item in rules:
        if item["syscall"] == "getrandom":
            continue  # Output bytes/count intentionally change this prefix.
        prior = [event for event in before["events"] if event["name"] == item["syscall"]]
        actual = [event for event in after["events"] if event["name"] == item["syscall"]]
        ordinal = item["when"]
        assert len(prior) >= ordinal and len(actual) >= ordinal, (item, prior, actual)
        left, right = prior[ordinal - 1], actual[ordinal - 1]
        assert (left["ip"], left["phase"]) == (right["ip"], right["phase"]), (left, right)
        if item["syscall"] == "mmap":
            assert ledger.arguments(left["args"])[1:] == ledger.arguments(right["args"])[1:], (left, right)
        elif item["syscall"] in ("close", "fcntl"):
            assert left["args"] == right["args"], (left, right)
        elif item["syscall"] == "openat":
            a, b = ledger.arguments(left["args"]), ledger.arguments(right["args"])
            assert a[0] == b[0] and a[2:] == b[2:], (left, right)
        elif item["syscall"] == "statx":
            # The output structure's stack address changes, while directory,
            # empty path, flags and requested metadata mask bind the call.
            assert left["args"].split(", ", 4)[:4] == right["args"].split(", ", 4)[:4], (left, right)
        elif item["syscall"] == "unlinkat":
            assert ledger.arguments(left["args"])[::2] == ledger.arguments(right["args"])[::2], (left, right)


def owner_group(suite):
    for mode in (0, 1, 2, 7, 8, 9, 10, 11):
        suite.owner("mode-%d" % mode, mode=mode,
                    check=lambda w, n, r, c, mode=mode: ordinary(w, n, r, c, mode))


def collisions_group(suite):
    def regular(cwd):
        (cwd / "anchor" / os.fsdecode(ZERO_NAME)).write_bytes(b"existing\0\xff")
    def symlink(cwd):
        (cwd / "anchor/target").write_bytes(b"symlink-target\0\xfe")
        os.symlink(b"target", os.fsencode(cwd / "anchor") + b"/" + ZERO_NAME)
    for kind, setup in (("regular", regular), ("symlink", symlink)):
        def check(w, n, r, c, kind=kind):
            assert w[0] == 0 and w[4] >= 2 and w[6] >= 1 and n != ZERO_NAME, w
            assert w[5] == w[4] and w[7] == 0
            assert not os.path.lexists(os.fsencode(c / "anchor") + b"/" + n)
            leaf = os.fsencode(c / "anchor") + b"/" + ZERO_NAME
            if kind == "regular":
                assert Path(os.fsdecode(leaf)).read_bytes() == b"existing\0\xff"
            else:
                assert os.readlink(leaf) == b"target" and (c / "anchor/target").read_bytes() == b"symlink-target\0\xfe"
            receipt(w, 20, [0, 0, 1, 0, 1, 1, 0, 1, 0, 0])
            receipt(w, 40, [0] * 10)
        suite.owner("collision-" + kind, setup=setup,
                    rules=[rule("getrandom", retval=16, poke=ZERO_DRAW)], check=check)
    suite.owner("collision-exhaustion", names=3, setup=regular,
                rules=[rule("getrandom", retval=16, poke=ZERO_DRAW, repeat=True)],
                check=creation_failure(8, 7, True, stats=[3, 3, 3, 0, 3]))
    def excluded_check(w, n, r, c):
        assert w[0] == 0 and w[7] >= 1 and w[6] == 0 and n != ZERO_NAME, w
        assert w[4] == w[5] + w[7] and not os.path.lexists(os.fsencode(c / "anchor") + b"/" + n)
        receipt(w, 20, [0, 0, 1, 0, 1, 1, 0, 1, 0, 0])
        receipt(w, 40, [0] * 10)
    suite.owner("excluded-before-open", excluded=1,
                rules=[rule("getrandom", retval=16, poke=ZERO_DRAW)], check=excluded_check)
    suite.owner("excluded-exhaustion", names=3, excluded=1,
                rules=[rule("getrandom", retval=16, poke=ZERO_DRAW, repeat=True)],
                check=creation_failure(8, 7, True, stats=[3, 0, 0, 3, 3]))
    suite.owner("collision-entropy-budget", names=2, entropy=1, setup=regular,
                rules=[rule("getrandom", retval=16, poke=ZERO_DRAW)],
                check=creation_failure(2004, 6, True, stats=[2, 1, 1, 0, 1]))


def validation_group(suite):
    for names, entropy in ((0, 16), (1025, 16), (8, 0), (8, 1048577)):
        suite.owner("limits-%d-%d" % (names, entropy), names=names, entropy=entropy,
                    check=creation_failure(2, 1, False, stats=[0] * 5))
    for excluded in (2, 3, 4, 5, 6, 7, 8, 9, 12):
        suite.owner("excluded-invalid-%d" % excluded, excluded=excluded,
                    check=creation_failure(3, 1, False, stats=[0] * 5))
    for excluded in (10, 11):
        suite.owner("excluded-valid-%d" % excluded, excluded=excluded, check=ordinary)
    for parent, cause, stage in ((1, 6, 4), (2, 1009, 3), (3, 7, 5)):
        suite.owner("parent-%d" % parent, parent=parent,
                    check=creation_failure(cause, stage, True, parent=parent, stats=[0] * 5))


def fault_cleanup(mode):
    def check(w, n, r, c):
        assert w[0] == 0 and w[61:63] == (1005, 9 if mode in (3, 4) else (8 if mode in (2, 5) else 10)), w
        target = os.fsencode(c / "anchor") + b"/" + n
        if mode in (3, 4):
            receipt(w, 20, [1005, 9, 1, 0, 1, 3, 5, 0, 0, 1])
            receipt(w, 40, [0, 0, 0, 0, int(mode == 3), int(mode == 3), 0, 1, 0, 0])
            if mode == 4:
                assert Path(os.fsdecode(target)).read_bytes() == DATA
            else:
                assert not os.path.lexists(target)
        elif mode == 2:
            assert w[31:33] == (1005, 2), w
            assert len(selected(r, "close", "F")) == 1
            receipt(w, 20, [0, 0, 0, 0, 1, 1, 0, 1, 0, 0])
            receipt(w, 40, [0] * 10)
            assert not os.path.lexists(target)
        else:
            receipt(w, 20, [1005, 8 if mode == 5 else 10, 1, 5 if mode == 5 else 0,
                            1, 1, 0, 1, 5 if mode == 6 else 0, 0])
            receipt(w, 40, [0] * 10)
            assert not os.path.lexists(target)
    return check


def faults_group(suite):
    baseline = suite.owner("baseline", check=ordinary)
    source_attempts = baseline["source"]["allocations"]
    assert source_attempts and all(item["length"] == 37 for item in source_attempts), source_attempts
    for allocation in source_attempts:
        suite.owner("source-oom-%d" % allocation["ordinal"],
                    rules=[rule("mmap", when=allocation["ordinal"], error="ENOMEM")],
                    baseline=baseline, check=creation_failure(4, 2, False, stats=[0] * 5))
    operations = [("duplicate", "fcntl", "C", lambda e: "F_DUPFD_CLOEXEC" in e["args"], 3),
                  ("metadata", "statx", "C", lambda e: True, 4),
                  ("status-flags", "fcntl", "C", lambda e: "F_GETFL" in e["args"], 5),
                  ("exclusive-create", "openat", "C", lambda e: True, 7)]
    for label, syscall, phase, predicate, stage in operations:
        matches = [e for e in selected(baseline, syscall, phase) if predicate(e)]
        assert len(matches) == 1, matches
        suite.owner(label + "-eio", rules=[rule(syscall, when=matches[0]["ordinal"], error="EIO")],
                    baseline=baseline, check=creation_failure(1005, stage, True,
                        stats=[1, 1, 0, 0, baseline["words"][8]] if stage == 7 else [0] * 5))
    for label, item, cause in (("entropy-eio", rule("getrandom", error="EIO"), 2105),
                               ("entropy-eagain", rule("getrandom", error="EAGAIN"), 2111),
                               ("entropy-zero", rule("getrandom", retval=0), 2002),
                               ("entropy-overcount", rule("getrandom", retval=17), 2003)):
        suite.owner(label, rules=[item], check=creation_failure(cause, 6, True, stats=[1, 0, 0, 0, 1]))
    suite.owner("entropy-eintr-budget", entropy=3,
                rules=[rule("getrandom", error="EINTR", repeat=True)],
                check=creation_failure(2004, 6, True, stats=[1, 0, 0, 0, 3]))
    suite.owner("entropy-eintr-recovery", rules=[rule("getrandom", error="EINTR")], check=ordinary)
    suite.owner("entropy-partial-recovery", rules=[rule("getrandom", retval=5, poke="0123456789")], check=ordinary)
    unlink = selected(baseline, "unlinkat", "A")
    assert len(unlink) == 1
    for mode in (3, 4):
        suite.owner("unlink-%s" % ("retry" if mode == 3 else "keep"), mode=mode,
                    rules=[rule("unlinkat", when=unlink[0]["ordinal"], error="EIO")],
                    baseline=baseline, check=fault_cleanup(mode))
    for mode, fd_index in ((5, 10), (6, 11)):
        target = [event for event in selected(baseline, "close", "A") if event["args"] == str(baseline["words"][fd_index])]
        assert len(target) == 1
        ordinal = target[0]["ordinal"]
        suite.owner("cleanup-close-%d" % mode, mode=mode,
                    rules=[rule("close", when=ordinal, error="EIO")],
                    repair=(ordinal, "A"), baseline=baseline, check=fault_cleanup(mode))
    explicit = suite.owner("close-file-baseline", mode=2,
                           check=lambda w, n, r, c: ordinary(w, n, r, c, 2))
    target = selected(explicit, "close", "F")
    assert len(target) == 1
    ordinal = target[0]["ordinal"]
    suite.owner("close-file-error", mode=2,
                rules=[rule("close", when=ordinal, error="EIO")],
                repair=(ordinal, "F"), baseline=explicit, check=fault_cleanup(2))


def mutations(result, expected):
    found = [e for e in result["events"] if e["name"] in ("unlinkat", "renameat2")]
    assert [e["name"] for e in found] == expected, found
    return found


def primitive_paths(result, op, first, second=None):
    calls = mutations(result, ["unlinkat" if op == "u" else "renameat2"])
    args = ledger.arguments(calls[0]["args"])
    owners = result["acquisitions"]
    assert ledger.quoted(args[1]) == first
    assert args[0] == str(owners[0]["fd"])
    assert "O_DIRECTORY" in owners[0]["acquired"]["args"] and "O_NOFOLLOW" in owners[0]["acquired"]["args"]
    if op == "u":
        assert args[2] == "0"
    else:
        assert len(owners) == 2 and args[2] == str(owners[1]["fd"])
        assert ledger.quoted(args[3]) == second and args[4] == ("RENAME_NOREPLACE" if op == "n" else "0")
    return calls[0]


def primitives_group(suite, bounds_executable):
    def binary(cwd):
        (cwd / "left/src").write_bytes(DATA)
        (cwd / "right/dst").write_bytes(b"old-destination")
        (cwd / "left/untouched").write_bytes(b"unrelated")
    def rename_check(op, old, new, expected_status=0):
        def check(cwd, result):
            first = old(cwd) if callable(old) else old
            second = new(cwd) if callable(new) else new
            entry = primitive_paths(result, op, first, second)
            if expected_status:
                assert entry["result"].startswith("-1 EEXIST ")
                assert (cwd / "left/src").read_bytes() == DATA
                assert (cwd / "right/dst").read_bytes() == b"old-destination"
            else:
                assert entry["result"] == "0"
                assert not (cwd / "left/src").exists() and (cwd / "right/dst").read_bytes() == DATA
            assert (cwd / "left/untouched").read_bytes() == b"unrelated"
        return check
    suite.primitive("replace", ["r", "src", "dst"], setup=binary, check=rename_check("r", b"src", b"dst"))
    suite.primitive("no-replace-existing", ["n", "src", "dst"], setup=binary, status=errno.EEXIST,
                    check=rename_check("n", b"src", b"dst", errno.EEXIST))
    def vacant(cwd):
        binary(cwd)
        (cwd / "right/dst").unlink()
    suite.primitive("no-replace-vacant", ["n", "src", "dst"], setup=vacant, check=rename_check("n", b"src", b"dst"))
    suite.primitive("absolute-rename", lambda c: ["r", str(c / "left/src"), str(c / "right/dst")], setup=binary,
                    check=rename_check("r", lambda c: os.fsencode(c / "left/src"), lambda c: os.fsencode(c / "right/dst")))
    for op in ("r", "n"):
        def symlink(cwd):
            binary(cwd)
            (cwd / "right/dst").unlink()
            (cwd / "right/target").write_bytes(b"symlink-target")
            os.symlink("target", cwd / "right/dst")
        def check(cwd, result, op=op):
            primitive_paths(result, op, b"src", b"dst")
            assert (cwd / "right/target").read_bytes() == b"symlink-target"
            if op == "n":
                assert (cwd / "right/dst").is_symlink() and os.readlink(cwd / "right/dst") == "target"
                assert (cwd / "left/src").read_bytes() == DATA
            else:
                assert not (cwd / "right/dst").is_symlink() and (cwd / "right/dst").read_bytes() == DATA
                assert not (cwd / "left/src").exists()
        suite.primitive("symlink-destination-" + op, [op, "src", "dst"], setup=symlink,
                        status=errno.EEXIST if op == "n" else 0, check=check)
    for nested in (False, True):
        old, new = (b"\xffsrc", b"\xfedst") if not nested else (b"inner/\xffsrc", b"nested/\xfedst")
        def setup(cwd, old=old):
            (cwd / "left/inner").mkdir()
            (cwd / "right/nested").mkdir()
            Path(os.fsdecode(os.fsencode(cwd / "left") + b"/" + old)).write_bytes(DATA)
        def check(cwd, result, old=old, new=new):
            primitive_paths(result, "n", old, new)
            assert not os.path.lexists(os.fsencode(cwd / "left") + b"/" + old)
            assert Path(os.fsdecode(os.fsencode(cwd / "right") + b"/" + new)).read_bytes() == DATA
        suite.primitive("raw-names-" + str(nested), [b"n", old, new], setup=setup, check=check)
    def unlink_check(cwd, result):
        primitive_paths(result, "u", b"src")
        assert not (cwd / "left/src").exists()
        assert (cwd / "right/dst").read_bytes() == b"old-destination"
    suite.primitive("unlink-binary", ["u", "src"], setup=binary, check=unlink_check)
    def link_setup(cwd):
        (cwd / "left/target").write_bytes(DATA)
        os.symlink("target", cwd / "left/link")
    def link_check(cwd, result):
        primitive_paths(result, "u", b"link")
        assert not (cwd / "left/link").exists() and (cwd / "left/target").read_bytes() == DATA
    suite.primitive("unlink-symlink", ["u", "link"], setup=link_setup, check=link_check)
    def abs_check(cwd, result):
        primitive_paths(result, "u", os.fsencode(cwd / "right/dst"))
        assert not (cwd / "right/dst").exists() and (cwd / "left/src").read_bytes() == DATA
    suite.primitive("unlink-absolute", lambda c: ["u", str(c / "right/dst")], setup=binary, check=abs_check)
    for op, args, code in (("u", ["u", "missing"], errno.ENOENT), ("r", ["r", "missing", "dst"], errno.ENOENT),
                           ("u", ["u", "directory"], errno.EISDIR)):
        def setup(cwd):
            binary(cwd)
            (cwd / "left/directory").mkdir()
        def check(cwd, result, op=op, code=code, args=args):
            item = primitive_paths(result, op, os.fsencode(args[1]), os.fsencode(args[2]) if len(args) == 3 else None)
            assert item["result"].split()[:2] == ["-1", errno.errorcode[code]], item
            assert (cwd / "left/src").read_bytes() == DATA and (cwd / "right/dst").read_bytes() == b"old-destination"
        suite.primitive("native-error-%s-%d" % (op, code), args, setup=setup, check=check, status=code)
    for op, args in (("u", ["u", "x" * 4096]), ("r", ["r", "src", "x" * 4096])):
        def check(cwd, result):
            mutations(result, [])
            assert (cwd / "left/src").read_bytes() == DATA and (cwd / "right/dst").read_bytes() == b"old-destination"
        suite.primitive("preflight-long-" + op, args, setup=binary, check=check, status=errno.ENAMETOOLONG)
    # Each primitive has one syscall attempt even for EINTR or ENOSYS. These
    # tests deliberately require unchanged namespace; no fallback is permitted.
    for op, syscall, args in (("u", "unlinkat", ["u", "src"]), ("r", "renameat2", ["r", "src", "dst"])):
        for error, code in (("EIO", 5), ("EINTR", 4), ("EAGAIN", 11), ("ENOSYS", 38), (None, 201)):
            item = rule(syscall, error=error) if error else rule(syscall, retval=1)
            def check(cwd, result, op=op):
                primitive_paths(result, op, b"src", b"dst" if op == "r" else None)
                assert (cwd / "left/src").read_bytes() == DATA and (cwd / "right/dst").read_bytes() == b"old-destination"
            suite.primitive("one-attempt-%s-%s" % (op, error or "invalid-count"), args,
                            setup=binary, check=check, status=code, rules=[item])
    bounds = Path(bounds_executable).resolve()
    profile = ledger.verified_sites(bounds, suite.directory)
    def setup(cwd):
        (cwd / "src").write_bytes(DATA)
    def check(cwd, result):
        calls = mutations(result, ["renameat2", "renameat2", "unlinkat"])
        expected = [["AT_FDCWD", b"src", "AT_FDCWD", b"src", "0"],
                    ["AT_FDCWD", b"src", "AT_FDCWD", b"dst", "RENAME_NOREPLACE"],
                    ["AT_FDCWD", b"dst", "0"]]
        for event, wanted in zip(calls, expected):
            args = ledger.arguments(event["args"])
            args[1] = ledger.quoted(args[1])
            if len(args) == 5:
                args[3] = ledger.quoted(args[3])
            assert args == wanted and event["result"] == "0", event
        assert not list(cwd.iterdir()), "bounds probe left a namespace owner"
    suite.primitive("logical-bounds", [], setup=setup, check=check, bounds=True,
                    executable=bounds, profile=profile)


def controls():
    count = ledger.controls()
    # Pure packet/phase/name checks; no child process or native executable.
    with tempfile.TemporaryDirectory(prefix="temp-file-oracle-cpu-") as directory:
        root = Path(directory)
        (root / "anchor").mkdir()
        (root / "regular").write_bytes(b"regular-parent\0\xfe")
        (root / "anchor/sentinel").write_bytes(b"anchor-sentinel\0\xff")
        words = [0] * 64
        words[2], words[4], words[5], words[8] = 1, 1, 1, 1
        words[9:14] = [3, 5, 4, 37, 999]
        words[20:30] = [0, 0, 1, 0, 1, 1, 0, 1, 0, 0]
        words[60] = 5
        name = ZERO_NAME
        result = dict(events=[], epochs=[dict(phase="C", events=[]), dict(phase="B", events=[]), dict(phase="X", events=[])])
        ordinary(tuple(words), name, result, root)
        count += 1
        for index, value in ((0, 8), (61, 1005), (25, 3), (29, 1), (47, 1)):
            changed = list(words)
            changed[index] = value
            try:
                ordinary(tuple(changed), name, result, root)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("oracle accepted corrupted cleanup receipt")
        trace = ('[0000000000401002] write(2, "\\x43", 1) = 1\n'
                 '[0000000000401002] getrandom("' + ''.join("\\x%02x" % i for i in range(16)) + '", 16, GRND_NONBLOCK) = 16\n'
                 '[0000000000401002] openat(4, "' + ''.join("\\x%02x" % i for i in b".tmp-" + bytes(range(16)).hex().encode()) + '", O_RDWR|O_CREAT|O_EXCL|O_NOCTTY|O_NOFOLLOW|O_CLOEXEC, 0600) = 5\n'
                 '[0000000000401002] write(2, "\\x63", 1) = 1\n'
                 '[0000000000401002] fcntl(5, F_GETFD) = 0x1 (flags FD_CLOEXEC)\n'
                 '[0000000000401002] fcntl(4, F_GETFD) = 0x1 (flags FD_CLOEXEC)\n')
        events, epochs = ledger.events(trace)
        result = dict(events=events, epochs=epochs)
        candidate = b".tmp-" + bytes(range(16)).hex().encode()
        candidate_contract(tuple(words), candidate, result, 0)
        count += 1
        for bad in (candidate[:-1] + b"0", ZERO_NAME):
            try:
                candidate_contract(tuple(words), bad, result, 0)
            except AssertionError:
                count += 1
            else:
                raise AssertionError("oracle accepted entropy/name disagreement")
    print("temp-file oracle CPU-controls=%d native-cases=0" % count)


def main():
    assert len(sys.argv) >= 2
    group = sys.argv[1]
    if group == "controls":
        assert len(sys.argv) == 2
        controls()
        return
    assert group in ("owner", "collisions", "validation", "faults", "primitives"), group
    assert len(sys.argv) == (4 if group == "primitives" else 3)
    suite = Suite(group, sys.argv[2])
    if group == "primitives":
        primitives_group(suite, sys.argv[3])
    else:
        globals()[group + "_group"](suite)
    suite.done()


if __name__ == "__main__":
    main()
