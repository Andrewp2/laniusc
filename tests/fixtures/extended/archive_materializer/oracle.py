"""Actual Lanius materialization, independent lstat/content and resource gates."""
import json
import os
from pathlib import Path
import resource
import select as select_io
import struct
import subprocess
import sys
import tempfile
import time
import traceback

import cases
import ledger

MAX = (1 << 64) - 1
STATS = "seen completed created published bytes writes names entropy syncs host cleanup_reserved cleanup_charged closes cleanup_errors steps owned peak_fds".split()
RECEIPT = ("state visibility bytes writes file_syncs renames directory_syncs file_synced directory_synced file_open anchor_open temporary_owned retained "
           "file_close_attempted file_close_error remove_attempted removal remove_error directory_close_attempted directory_close_error cleanup_retained "
           "names opens collisions excluded entropy latest_cause latest_stage latest_completed reserved0 reserved1 reserved2").split()
NODE = ("node ordinal kind explicit visited created created_ordinal opens opened child_syncs child_synced child_error parent_syncs parent_synced parent_error "
        "closes close_error file_attempted published kept identity inode device_major device_minor receipt_present").split()
REQUEST_NAMES = ("format layout mode length repair root_case max_archive max_entry max_total zip_work metadata_work source_owned entries nodes path component "
                 "depth stored_paths plan_work owned run_depth host cleanup writes syncs entropy names zip_output steps").split()


def request(format, length, **changes):
    value = dict(format=format, layout=0, mode=0, length=length, repair=MAX, root_case=0,
                 max_archive=65536, max_entry=1048576, max_total=2097152, zip_work=1048576,
                 metadata_work=1048576, source_owned=2097152, entries=48, nodes=48, path=4095,
                 component=255, depth=16, stored_paths=65536, plan_work=1048576,
                 owned=8388608, run_depth=16, host=16384, cleanup=1024, writes=4096,
                 syncs=1024, entropy=512, names=128, zip_output=1048576, steps=1048576)
    assert not set(changes) - set(value), changes
    value.update(changes)
    return value


def read_exact(stream, count, deadline):
    result = bytearray()
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select_io.select([stream], [], [], remaining)[0], ("checkpoint timeout", len(result), count)
        piece = os.read(stream.fileno(), count-len(result))
        assert piece, ("premature native EOF", len(result), count)
        result.extend(piece)
    return bytes(result)


def failure(words):
    assert len(words) == 40 and words[7] == 0
    return dict(zip(("cause", "stage", "ordinal", "node", "detail", "atomic_stage", "completed"), words[:7]),
                receipt=dict(zip(RECEIPT, words[8:])))


def decode(packet):
    assert len(packet) >= 1610
    words = struct.unpack_from("<192Q", packet)
    assert words[:2] == (1096303960, 1), words[:2]
    result = dict(checkpoint=words[2], pid=words[3], source_cause=words[4] & 0xffffffff,
                  source_detail=words[4] >> 32, source_ordinal=words[5],
                  result=words[6], state=words[7], remaining=words[8], root_fd=words[9],
                  layout=words[10], stride=words[11], start=words[12], length=words[13],
                  node_count=words[14], recovery_length=words[15], current_node=words[16],
                  current_ordinal=words[17], action_result=words[18], taken_length=words[19],
                  stats=dict(zip(STATS, words[20:37])), primary=failure(words[37:77]),
                  cleanup=failure(words[77:117]), action=failure(words[117:157]),
                  receipt=dict(zip(RECEIPT, words[157:189])), cached=words[189],
                  root_close_error=words[190], receipt_present=words[191], nodes=[])
    result["primary_bytes"] = packet[37*8:77*8]
    assert result["recovery_length"] in (0, 37) and result["taken_length"] in (0, 37)
    result["recovery"] = packet[1536:1573][:result["recovery_length"]]
    result["taken"] = packet[1573:1610][:result["taken_length"]]
    at = 1610
    for _ in range(result["node_count"]):
        raw = struct.unpack_from("<58Q", packet, at)
        at += 464
        item = dict(zip(NODE, raw[:25]), receipt=dict(zip(RECEIPT, raw[25:57])))
        item["path"] = packet[at:at+raw[57]]
        at += raw[57]
        assert item["node"] == len(result["nodes"]) and len(item["path"]) == raw[57]
        result["nodes"].append(item)
    assert at == len(packet), (at, len(packet))
    return result


def rule(syscall, when, *, error=None, retval=None, last=None):
    value = dict(syscall=syscall, when=when)
    assert when > 0 and (error is None) != (retval is None)
    value["error" if error is not None else "retval"] = error if error is not None else retval
    if last is not None:
        assert last >= when
        value["last"] = last
    return value


def injection(value):
    result = value["syscall"] + ":" + ("error=" + value["error"] if "error" in value else "retval=" + str(value["retval"]))
    return result + ":when=" + str(value["when"]) + (".." + str(value["last"]) if "last" in value else "")


def serializable(snapshot):
    return {key.hex(): value for key, value in snapshot.items()}


def primary_preserved(first, later):
    assert later["primary_bytes"] == first["primary_bytes"], ("first execution failure changed", first["primary"], later["primary"])


def caller_preserved(first, later, root_case):
    if first["source_cause"] or root_case == 3:
        return
    fd = first["root_fd"]
    assert later["root_fd"] == fd and fd in later["owners"]["live"], ("borrowed caller root retired", first, later)
    assert later["owners"]["live"][fd]["generation"] == first["owners"]["live"][fd]["generation"], "borrowed caller fd reused"


def allocation_role(item, baseline, entries):
    maps = [entry for entry in baseline["events"] if entry["name"] == "mmap"]
    before = [entry for entry in maps if entry["phase"] is None]
    if item["phase"] is None:
        assert item in before
        return ("source", 8, 0) if item == before[-1] else ("source", 9, 12)
    assert item["phase"] == "E", item
    anchor = next(entry for entry in baseline["events"] if entry["phase"] == "E" and entry["name"] == "fcntl" and "F_DUPFD_CLOEXEC" in entry["args"])
    if item["index"] < anchor["index"]:
        return ("run", 13, 2, 0, 0, 0xffffffff)
    def ordinal(entry):
        return sum(value["name"] == "renameat2" and value["result"] == "0" and value["index"] < entry["index"] for value in baseline["events"])
    index = ordinal(item)
    assert index < len(entries)
    group = [entry for entry in maps if entry["index"] > anchor["index"] and ordinal(entry) == index]
    role = group.index(item)
    sizes = [len(entries[index]["data"]), len(entries[index]["name"].split(b"/")[-1]), 37]
    assert role < len(sizes) and int(ledger.arguments(item["args"])[1]) == sizes[role], ("unexpected allocation role/size", item, index, role, sizes)
    return (("run", 21, 4, 25, 0, index), ("run", 22, 10, 4, 2, index),
            ("run", 22, 10, 10004, 3, index))[role]


def allocation_failed(first, expected):
    if expected[0] == "source":
        assert (first["source_cause"], first["source_detail"]) == expected[1:], (first, expected)
        assert first["source_ordinal"] == 0xffffffff and first["result"] == 0
    else:
        assert first["source_cause"] == 0 and first["result"] == 3
        primary = first["primary"]
        assert tuple(primary[name] for name in ("cause", "stage", "detail", "atomic_stage", "ordinal")) == expected[1:], (primary, expected)


class Suite:
    def __init__(self, executable):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="archive-materializer-"))
        self.profile = ledger.verified_sites(self.executable, self.directory)
        assert not self.profile[1], "raw ELF requires verified opcode sites, not named fallback"
        assert getattr(self.profile[0], "executable_ranges", []), "missing verified executable address ranges"
        self.count, self.started = 0, time.monotonic()

    def case(self, label):
        assert time.monotonic() - self.started < 62, "split this finite group before extending runtime"
        self.count += 1
        directory = self.directory / f"{self.count:03d}-{label}"
        directory.mkdir()
        return directory


class Session:
    def __init__(self, suite, label, entries, *, format=1, producer=None, rules=(), baseline=None,
                 setup=None, before=None, changes=None, repair=None):
        self.suite, self.directory = suite, suite.case(label)
        self.cwd = self.directory / "cwd"
        self.cwd.mkdir()
        self.root = self.cwd / "root"
        self.root.mkdir(mode=0o751)
        (self.cwd / "outside").write_bytes(cases.OLD)
        (self.cwd / "regular-root").write_bytes(cases.OLD)
        self.entries = entries
        if setup:
            setup(self.cwd)
        self.prior = cases.snapshot(self.root)
        self.outside = cases.snapshot(self.cwd)
        self.root_identity = tuple(getattr(os.stat(self.root), field) for field in ("st_ino", "st_uid", "st_gid", "st_mode"))
        self.archive = (producer or (cases.raw_zip if format else cases.ustar))(entries)
        self.request = request(format, len(self.archive), **(changes or {}))
        self.rules, self.baseline, self.repair = list(rules), baseline, repair
        if repair:
            self.request["repair"] = repair[1]
        self.trace = self.directory / "syscalls.log"
        self.frames, self.stdout = [], bytearray()
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
                   "-e", "trace=" + ledger.TRACE, "-o", str(self.trace)]
        for item in self.rules:
            command += ["-e", "inject=" + injection(item)]
        command.append(str(suite.executable))
        (self.directory / "command.json").write_text(json.dumps(command, indent=2) + "\n")
        payload = struct.pack("<29Q", *(self.request[name] for name in REQUEST_NAMES)) + self.archive
        (self.directory / "request.bin").write_bytes(payload)
        self.process = subprocess.Popen(command, cwd=self.cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, bufsize=0, umask=0o022)
        try:
            at = 0
            while at < len(payload):
                written = self.process.stdin.write(payload[at:])
                assert written and written <= len(payload)-at
                at += written
            first = self.frame(0)
            assert first["state"] == 0 and not first["remaining"] and first["result"] == 0
            assert cases.snapshot(self.root) == self.prior, "metadata admission changed namespace"
            if before:
                before(self, first)
            if self.request["mode"] == 3:
                resource.prlimit(first["pid"], resource.RLIMIT_FSIZE, (3, 3))
            self.ack()
            self.first = self.frame(1)
        except BaseException:
            self.fail()
            raise

    def frame(self, checkpoint):
        deadline = time.monotonic() + 9
        prefix = read_exact(self.process.stdout, 4, deadline)
        size = struct.unpack("<I", prefix)[0]
        assert 1610 <= size <= 32764, size
        packet = read_exact(self.process.stdout, size, deadline)
        self.stdout.extend(prefix + packet)
        text = ""
        while time.monotonic() < deadline:
            try:
                text = ledger.SOURCE.output_prefix(self.trace.read_text(), bytes(self.stdout))
                break
            except (AssertionError, FileNotFoundError):
                time.sleep(0.005)
        else:
            raise AssertionError("complete checkpoint not captured in native trace")
        result = decode(packet)
        assert result["checkpoint"] == checkpoint and result["layout"] == self.request["layout"]
        owners = ledger.analyze(text, self.suite.profile, self.directory, final=checkpoint == 3, repair=self.repair)
        result.update(owners=owners)
        if checkpoint in (1, 2):
            caller_preserved(self.frames[0], result, self.request["root_case"])
        if checkpoint in (2, 3):
            first = next(value for value in self.frames if value["checkpoint"] == 1)
            primary_preserved(first, result)
        if checkpoint == 3:
            assert result["root_fd"] == 0xffffffff, "caller root not logically retired at final release"
        ledger.process_owners(result["pid"], owners, self.directory, f"checkpoint-{checkpoint}")
        ledger.check_injections(owners, self.rules, final=checkpoint == 3)
        self.frames.append(result)
        (self.directory / f"checkpoint-{checkpoint}.bin").write_bytes(packet)
        (self.directory / f"checkpoint-{checkpoint}-tree.json").write_text(json.dumps(serializable(cases.snapshot(self.root)), indent=2) + "\n")
        return result

    def ack(self):
        assert self.process.stdin.write(b"A") == 1

    def action(self):
        self.ack()
        return self.frame(2)

    def finish(self):
        if self.frames[-1]["checkpoint"] == 1:
            self.action()
        self.ack()
        final = self.frame(3)
        assert not final["remaining"] and final["state"] == 4
        assert not final["owners"]["source"]["live"] and not final["owners"]["live"]
        self.ack()
        self.process.stdin.close()
        self.process.stdin = None
        extra, stderr = self.process.communicate(timeout=3)
        assert self.process.returncode == 0 and not extra, (self.process.returncode, extra, stderr)
        whole = ledger.analyze(self.trace.read_text(), self.suite.profile, self.directory, final=True, repair=self.repair)
        ledger.check_injections(whole, self.rules)
        assert whole["markers"] == stderr
        assert len(whole["events"]) == len(final["owners"]["events"]) + 1
        last = whole["events"][-1]
        assert last["name"] == "read" and last["args"] == '0, "\\x41", 1' and last["result"] == "1", last
        if self.baseline:
            for item in self.rules:
                reference = self.baseline if "events" in self.baseline else self.baseline[item["syscall"]]
                ledger.bind_target(reference, whole, item)
        assert (self.cwd / "outside").read_bytes() == cases.OLD
        for path in (b"outside", b"regular-root"):
            assert cases.snapshot(self.cwd)[path] == self.outside[path], ("outside object changed", path)
        if hasattr(self, "replacement_snapshot"):
            assert cases.snapshot(self.cwd / "root") == self.replacement_snapshot, "replacement root was modified"
        current = tuple(getattr(os.stat(self.root), field) for field in ("st_ino", "st_uid", "st_gid", "st_mode"))
        assert current == self.root_identity, ("root metadata changed", current, self.root_identity)
        for key, maximum in (("writes", "writes"), ("names", "names"), ("entropy", "entropy"),
                             ("syncs", "syncs"), ("host", "host"), ("cleanup_reserved", "cleanup"), ("steps", "steps"), ("owned", "owned")):
            assert final["stats"][key] <= self.request[maximum], (key, final["stats"], self.request)
        assert whole["peak_fds"] <= max(self.request["run_depth"], 0) + 4
        initial_owned = self.frames[0]["owners"]["source"]["peak"]
        assert whole["source"]["peak"] <= max(self.request["owned"], initial_owned), (whole["source"]["peak"], self.request)
        (self.directory / "native.stderr").write_bytes(stderr)
        (self.directory / "status").write_text("0\n")
        self.final = final
        return whole

    def fail(self):
        if self.process.poll() is None:
            self.process.kill()  # Diagnostic recovery, never acceptance.
        try:
            stdout, stderr = self.process.communicate(timeout=3)
            (self.directory / "failure.stdout").write_bytes(stdout)
            (self.directory / "failure.stderr").write_bytes(stderr)
        except Exception:
            pass
        (self.directory / "failure.txt").write_text(traceback.format_exc())
        print(f"failed materializer evidence: {self.directory}", file=sys.stderr)


def run(suite, label, entries, check, **options):
    session = Session(suite, label, entries, **options)
    try:
        check(session)
        return session.finish()
    except BaseException:
        session.fail()
        raise


def success(session):
    first = session.first
    assert first["source_cause"] == 0 and first["result"] == 1 and first["state"] == 2 and first["cached"]
    assert first["primary"]["cause"] == first["cleanup"]["cause"] == 0 and not first["remaining"]
    assert first["stats"]["completed"] == len(session.entries)
    assert first["stats"]["published"] == sum(item["kind"] == "file" for item in session.entries)
    assert first["stats"]["bytes"] == sum(len(item["data"]) for item in session.entries)
    assert sum(item["created"] for item in first["nodes"]) == first["stats"]["created"]
    assert first["stats"]["syncs"] == 2*first["stats"]["created"] + 2*first["stats"]["published"]
    writes = [item for item in first["owners"]["events"] if item["name"] == "write" and item["phase"] == "E"
              and int(ledger.arguments(item["args"])[0]) > 2]
    assert len(writes) == first["stats"]["writes"]
    assert sum(int(item["result"]) for item in writes if item["result"].isdecimal()) == first["stats"]["bytes"]
    for item in first["nodes"]:
        if item["created"]:
            assert item["opened"] and item["child_synced"] and item["parent_synced"]
            assert item["child_syncs"] == item["parent_syncs"] == 1
        if item["published"]:
            assert item["receipt"]["visibility"] == 1 and item["receipt"]["directory_synced"]
    cases.assert_manifest(session.root, session.entries, prior=session.prior)


def failed(session, *, category=None, detail=None, stage=None, published=None):
    first = session.first
    assert first["source_cause"] == 0 and first["result"] == 3 and first["state"] == 3 and first["cached"], first
    if category is not None:
        assert first["primary"]["cause"] == category, first
    if detail is not None:
        assert first["primary"]["detail"] == detail, first
    if stage is not None:
        assert first["primary"]["stage"] == stage, first
    if published is not None:
        assert first["stats"]["published"] == published, first


def successful_groups(suite):
    mixed = [cases.file("a/b/binary"), cases.file("empty", b""), cases.directory("a/b/"), cases.directory("a/"), cases.directory("empty-dir/")]
    run(suite, "ustar-mixed", mixed, success, format=0)
    run(suite, "python-zip-dynamic", [cases.file("dynamic", cases.LARGE)], success, producer=cases.python_zip)
    for method in ("stored", "fixed", "dynamic"):
        values = [cases.file("a/b/data", cases.LARGE if method != "stored" else cases.DATA, method), cases.directory("a/b/"), cases.directory("a/")]
        run(suite, f"zip-{method}", values, success)
    for format in (0, 1):
        run(suite, f"empty-{format}", [], success, format=format)
        for layout in (1, 2):
            run(suite, f"raw-view-{format}-{layout}", [cases.file(b"raw-\xff/data-\x80")], success, format=format, changes=dict(layout=layout))
    def moved(session, checkpoint):
        destination = session.cwd / "moved"
        session.root.rename(destination)
        session.root.mkdir()
        (session.root / "replacement").write_bytes(cases.OLD)
        session.replacement_snapshot = cases.snapshot(session.root)
        session.root = destination
    run(suite, "renamed-anchor", [cases.file("anchored")], success, before=moved)


def existing_group(suite):
    def parents(cwd):
        cases.setup_conflict(cwd, b"a", "dir")
    run(suite, "existing-parent", [cases.file("a/child")], success, setup=parents)
    for kind in ("file", "symlink", "fifo", "socket", "hardlink"):
        def setup(cwd, kind=kind):
            cases.setup_conflict(cwd, b"leaf", kind)
        def check(session):
            failed(session, category=22, detail=1017, stage=12, published=0)
            assert cases.snapshot(session.root) == session.prior
            assert not any(item["name"] == "openat" and ledger.quoted(ledger.arguments(item["args"])[1]) == b"leaf"
                           for item in session.first["owners"]["events"])
        run(suite, f"leaf-{kind}", [cases.file("leaf")], check, setup=setup)
    for kind in ("file", "symlink"):
        def setup(cwd, kind=kind):
            if kind == "symlink":
                outside = cwd / "outside-directory"
                outside.mkdir()
                (outside / "sentinel").write_bytes(cases.OLD)
                os.symlink(outside, cwd / "root/a")
            else:
                cases.setup_conflict(cwd, b"a", kind)
        def check(session):
            failed(session, category=20, stage=7, published=0)
            assert cases.snapshot(session.root) == session.prior
            outside = session.cwd / "outside-directory"
            if outside.exists():
                assert cases.snapshot(outside) == {b"sentinel": session.outside[b"outside-directory/sentinel"]}
        run(suite, f"intermediate-{kind}", [cases.file("a/child")], check, setup=setup)


def partial_group(suite):
    for error in ("bad_crc", "broken"):
        entries = [cases.file("first"), cases.file("not-created/late", cases.DATA, "broken" if error == "broken" else "stored", **({"bad_crc": True} if error == "bad_crc" else {}))]
        def check(session, error=error):
            failed(session, category=21, detail=26 if error == "broken" else 21, stage=4, published=1)
            cases.assert_manifest(session.root, session.entries[:1])
            assert not (session.root / "not-created").exists()
        run(suite, error, entries, check)
    def setup(cwd):
        cases.setup_conflict(cwd, b"late", "file")
    def check(session):
        failed(session, category=22, detail=1017, published=1)
        cases.assert_manifest(session.root, session.entries[:1], prior=session.prior)
    run(suite, "late-conflict", [cases.file("first"), cases.file("late")], check, setup=setup)


def bounds_group(suite):
    entries = [cases.file("a/b/file")]
    for field, cap, category in (("owned", 0, 4), ("run_depth", 1, 5), ("host", 0, 6), ("cleanup", 0, 7),
                                 ("writes", 0, 8), ("syncs", 0, 9), ("entropy", 0, 10), ("names", 0, 11), ("steps", 0, 12)):
        def check(session, category=category):
            failed(session, category=category, published=0)
        run(suite, f"cap-{field}", entries, check, changes={field: cap})
    for root_case, category in ((1, 16), (2, 15), (3, 20)):
        run(suite, f"root-{root_case}", entries,
            lambda session, category=category: failed(session, category=category, published=0), changes=dict(root_case=root_case))
    first, _ = baseline_session(suite, "exact-baseline", [cases.file("only")])
    # Actual baseline counters establish paired exact/one-under bounds.
    for field, counter, category in (("owned", "owned", 4), ("host", "host", 6),
                                      ("cleanup", "cleanup_reserved", 7), ("writes", "writes", 8),
                                      ("syncs", "syncs", 9), ("steps", "steps", 12)):
        cap = first["stats"][counter]
        assert cap > 0
        run(suite, f"exact-{field}", [cases.file("only")], success, changes={field: cap})
        run(suite, f"one-under-{field}", [cases.file("only")],
            lambda session, category=category: failed(session, category=category), changes={field: cap-1})


def baseline_session(suite, label, entries, **options):
    session = Session(suite, label, entries, **options)
    try:
        success(session)
        first = session.first
        whole = session.finish()
        return first, whole
    except BaseException:
        session.fail()
        raise


def select(result, syscall, predicate=lambda item: True):
    values = [item for item in result["events"] if item["name"] == syscall and predicate(item)]
    assert values, (syscall, result["events"])
    return values


def allocation_group(suite, second):
    entries = [cases.file("a/first", cases.DATA, "fixed"), cases.file("a/second", cases.LARGE, "dynamic")]
    _, baseline = baseline_session(suite, "allocation-baseline", entries)
    allocations = [item for item in baseline["events"] if item["name"] == "mmap"]
    assert len(allocations) == len(baseline["source"]["attempts"]), "unexpected non-source mappings in raw baseline"
    assert allocations and all(item["result"].split()[0].startswith("0x") for item in allocations)
    boundary = (len(allocations)+1)//2
    selected = allocations[boundary:] if second else allocations[:boundary]
    assert selected
    for item in selected:
        fault = rule("mmap", item["ordinal"], error="ENOMEM")
        expected = allocation_role(item, baseline, entries)
        def check(session, expected=expected):
            allocation_failed(session.first, expected)
            assert session.first["result"] != 1
            # Every surviving regular destination is a fully published earlier file.
            actual = cases.snapshot(session.root)
            for entry in entries:
                if entry["name"] in actual:
                    assert actual[entry["name"]]["data"] == entry["data"].hex()
        run(suite, f"allocation-{item['ordinal']}", entries, check, rules=[fault], baseline=baseline)


def host_fault_group(suite, part):
    entries = [cases.file("a/file", cases.LARGE, "fixed")]
    first, baseline = baseline_session(suite, "host-baseline", entries)
    events = baseline["events"]
    if part == "namespace":
        candidates = [(item, "EIO") for item in events if item["phase"] == "E" and item["name"] in ("fcntl", "statx")]
        opens = select(baseline, "openat", lambda item: item["phase"] == "E" and item["result"].split()[0].isdecimal() and "O_DIRECTORY" in item["args"])
        candidates.append((opens[0], "EIO"))
        for item, error in candidates:
            def check(session, item=item):
                failed(session, published=0)
                if item["name"] == "openat":
                    status = next(value for value in session.first["nodes"] if value["path"] == b"a")
                    assert status["created"] and not status["opened"]
                    assert status["opens"] == 2 and status["child_syncs"] == status["parent_syncs"] == 0
                    assert (session.root / "a").is_dir()
            run(suite, f"namespace-{item['name']}-{item['ordinal']}", entries,
                check, rules=[rule(item["name"], item["ordinal"], error=error)], baseline=baseline)
    elif part == "sync":
        for position, item in enumerate(select(baseline, "fsync")):
            def check(session, item=item, position=position):
                failed(session, category=20 if position < 2 else 22,
                       detail=5 if position < 2 else 1005, stage=(8, 9, 12, 12)[position])
                mkdirs = select(session.first["owners"], "mkdirat")
                assert sum(value["result"] == "0" for value in mkdirs) == session.first["stats"]["created"]
                if item == select(baseline, "fsync")[-1]:
                    assert session.first["receipt"]["visibility"] == 1 and not session.first["receipt"]["directory_synced"]
                    assert (session.root / "a/file").read_bytes() == cases.LARGE
                    assert session.first["remaining"]
                    after = session.action()
                    assert after["receipt"]["directory_synced"] and after["action_result"] == 1
                    assert after["stats"]["published"] == 1
            mode = 1 if item == select(baseline, "fsync")[-1] else 0
            run(suite, f"sync-{item['ordinal']}", entries, check, rules=[rule("fsync", item["ordinal"], error="EIO")], baseline=baseline, changes=dict(mode=mode))
    elif part == "writes":
        payload = select(baseline, "write", lambda item: item["phase"] == "E" and int(ledger.arguments(item["args"])[0]) > 2)
        for error, returned in (("EIO", None), (None, 0), (None, 1025), ("EINTR", None)):
            item = payload[0]
            fault = rule("write", item["ordinal"], error=error, retval=returned)
            check = success if error == "EINTR" else lambda session: failed(session, category=22, published=0)
            run(suite, f"write-{error or returned}", entries, check, rules=[fault], baseline=baseline)
        interrupted = rule("write", payload[0]["ordinal"], error="EINTR", last=payload[0]["ordinal"]+2)
        def exhausted(session):
            failed(session, category=8, published=0)
            assert session.first["stats"]["writes"] == 3 and session.first["stats"]["bytes"] == 0
        run(suite, "write-finite-EINTR", entries, exhausted, rules=[interrupted], baseline=baseline, changes=dict(writes=3))
        random = select(baseline, "getrandom")[0]
        run(suite, "entropy-EIO", entries, lambda session: failed(session, category=22, published=0), rules=[rule("getrandom", random["ordinal"], error="EIO")], baseline=baseline)
        def exhausted_entropy(session):
            failed(session, category=22, published=0)
            assert session.first["stats"]["entropy"] == 3
        run(suite, "entropy-finite-EINTR", entries, exhausted_entropy,
            rules=[rule("getrandom", random["ordinal"], error="EINTR", last=random["ordinal"]+2)], baseline=baseline, changes=dict(entropy=3))
    elif part == "close_rename":
        for item in select(baseline, "close", lambda item: item["phase"] == "E"):
            fd = int(ledger.arguments(item["args"])[0])
            def check(session):
                failed(session)
                assert session.first["cleanup"]["cause"] and session.first["cleanup"]["detail"] in (5, 11005), session.first
            run(suite, f"close-{item['ordinal']}", entries, check,
                rules=[rule("close", item["ordinal"], error="EIO")], baseline=baseline, repair=(item["ordinal"], fd))
        renamed = select(baseline, "renameat2")[0]
        def check(session):
            failed(session, category=22, detail=1005, published=0)
            assert session.first["primary"]["receipt"]["visibility"] == 2
            assert not (session.root / "a/file").exists()
        run(suite, "ambiguous-rename", entries, check, rules=[rule("renameat2", renamed["ordinal"], error="EIO")], baseline=baseline)
    else:
        raise AssertionError(part)


def recovery_group(suite):
    entries = [cases.file("only", cases.LARGE, "stored")]
    first, baseline = baseline_session(suite, "recovery-baseline", entries)
    synced = select(baseline, "fsync")[-1]
    for tight in (False, True):
        changes = dict(mode=1)
        if tight:
            changes.update(host=first["stats"]["host"], cleanup=4)
        def check(session, tight=tight):
            failed(session, category=22, published=1)
            assert session.first["remaining"] and session.first["receipt"]["visibility"] == 1
            assert (session.root / "only").read_bytes() == cases.LARGE
            after = session.action()
            body = [epoch for epoch in after["owners"]["epochs"] if epoch["phase"] == "R"]
            assert len(body) == 1
            if tight:
                assert not body[0]["events"] and after["action"]["cause"] == 6
                assert after["stats"]["cleanup_charged"] == session.first["stats"]["cleanup_charged"]
            else:
                assert after["action_result"] == 1 and after["receipt"]["directory_synced"]
            assert len(select(after["owners"], "renameat2")) == 1
        run(suite, f"retry-lease-{tight}", entries, check, changes=changes,
            rules=[rule("fsync", synced["ordinal"], error="EIO")], baseline=baseline)
    # Pair a real kernel short write with one cleanup denial to inspect bytes.
    def prefix(session):
        failed(session, category=22, published=0)
        assert session.first["receipt"]["bytes"] == 3 and session.first["receipt"]["temporary_owned"]
        temporary = [path for path in session.root.iterdir() if path.name.startswith(".tmp-")]
        assert len(temporary) == 1 and temporary[0].read_bytes() == cases.LARGE[:3]
        writes = select(session.first["owners"], "write", lambda item: item["phase"] == "E" and int(ledger.arguments(item["args"])[0]) > 2)
        assert writes[0]["result"] == "3" and writes[1]["result"].startswith("-1 EFBIG ")
        assert "INJECTED" not in writes[0]["result"] + writes[1]["result"]
    short_control = run(suite, "real-short-control", entries,
                        lambda session: failed(session, category=22, published=0), changes=dict(mode=3))
    short_unlink = select(short_control, "unlinkat")[0]
    run(suite, "real-short-prefix", entries, prefix, changes=dict(mode=3),
        rules=[rule("unlinkat", short_unlink["ordinal"], error="EIO")], baseline=short_control)
    # Reached write failure + retained automatic cleanup, then explicit keep/transfer.
    written = select(baseline, "write", lambda item: item["phase"] == "E" and int(ledger.arguments(item["args"])[0]) > 2)[1]
    write_fault = rule("write", written["ordinal"], error="EIO")
    write_control = run(suite, "write-cleanup-control", entries,
                        lambda session: failed(session, category=22, published=0), rules=[write_fault], baseline=baseline)
    unlink = select(write_control, "unlinkat")[0]
    for keep in (False, True):
        def check(session, keep=keep):
            failed(session, category=22, published=0)
            assert session.first["receipt"]["bytes"] == 1024 and session.first["remaining"]
            name = session.first["recovery"]
            assert len(name) == 37 and (session.root / os.fsdecode(name)).read_bytes() == cases.LARGE[:1024]
            after = session.action()
            if keep:
                assert after["taken"] == name and after["taken_length"] == 37 and not after["remaining"]
                assert (session.root / os.fsdecode(name)).read_bytes() == cases.LARGE[:1024]
            else:
                assert not (session.root / os.fsdecode(name)).exists()
        run(suite, f"unlink-{'keep' if keep else 'retry'}", entries, check, changes=dict(mode=2 if keep else 0),
            rules=[write_fault, rule("unlinkat", unlink["ordinal"], error="EIO")],
            baseline={"write": baseline, "unlinkat": write_control})


def controls():
    count = cases.controls() + ledger.controls()
    assert len(REQUEST_NAMES) == 29 and len(RECEIPT) == 32 and len(NODE) == 25 and len(STATS) == 17
    count += 1
    words = [0]*192
    words[0:2] = [1096303960, 1]
    packet = struct.pack("<192Q", *words) + bytes(74)
    assert decode(packet)["nodes"] == []
    count += 1
    for broken in (packet[:-1], packet + b"x", bytes(len(packet))):
        try:
            decode(broken)
        except (AssertionError, struct.error):
            count += 1
        else:
            raise AssertionError("accepted changed binary report")
    first = decode(packet)
    primary_preserved(first, decode(packet))
    count += 1
    for word in (0, 4, 10, 18, 34):
        changed = bytearray(first["primary_bytes"])
        changed[word*8] ^= 1
        try:
            primary_preserved(first, dict(first, primary_bytes=bytes(changed)))
        except AssertionError:
            count += 1
        else:
            raise AssertionError("first failure comparison ignored an outer/nested field")
    root = dict(source_cause=0, root_fd=3, owners=dict(live={3: dict(generation=1)}))
    caller_preserved(root, root, 0)
    count += 1
    for changed in (dict(root, root_fd=4), dict(root, owners=dict(live={})),
                    dict(root, owners=dict(live={3: dict(generation=2)}))):
        try:
            caller_preserved(root, changed, 0)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("caller root comparison ignored retirement/reuse")
    source = dict(source_cause=9, source_detail=12, source_ordinal=0xffffffff, result=0)
    allocation_failed(source, ("source", 9, 12))
    count += 1
    try:
        allocation_failed(dict(source, source_detail=0), ("source", 9, 12))
    except AssertionError:
        count += 1
    else:
        raise AssertionError("ENOMEM accepted an unspecified planner error")
    for expected in (("run", 13, 2, 0, 0, 0xffffffff), ("run", 21, 4, 25, 0, 0),
                     ("run", 22, 10, 4, 2, 0), ("run", 22, 10, 10004, 3, 0)):
        primary = dict(zip(("cause", "stage", "detail", "atomic_stage", "ordinal"), expected[1:]))
        result = dict(source_cause=0, result=3, primary=primary)
        allocation_failed(result, expected)
        count += 1
        changed = dict(primary, detail=primary["detail"]+1)
        try:
            allocation_failed(dict(result, primary=changed), expected)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("ENOMEM accepted an unrelated nested failure")
    print(f"archive-materializer controls={count}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 3, "oracle.py GROUP EXECUTABLE"
    group, executable = sys.argv[1:]
    suite = Suite(executable)
    if group == "success": successful_groups(suite)
    elif group == "existing": existing_group(suite)
    elif group == "partial": partial_group(suite)
    elif group == "bounds": bounds_group(suite)
    elif group == "allocations_first": allocation_group(suite, False)
    elif group == "allocations_second": allocation_group(suite, True)
    elif group == "recovery": recovery_group(suite)
    elif group in ("namespace", "sync", "writes", "close_rename"): host_fault_group(suite, group)
    else: raise AssertionError(group)
    assert suite.count > 0
    print(f"archive-materializer group={group} cases={suite.count}")


if __name__ == "__main__":
    main()
