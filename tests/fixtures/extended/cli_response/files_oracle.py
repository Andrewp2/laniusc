"""Real response-file provider and Expansion ownership; no production codec here.

Full-trace endpoints/events and exact raw ELF authority reuse the unchanged KV
helper. Live source accounting reuses the unchanged archive prefix ledger.
Only this fixture's phase/fd/ACK protocol and expected filesystem bytes are new.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import struct
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


HERE = Path(__file__).resolve().parent
LEDGER = load("response_files_full_trace", HERE.parent / "kv_publication/source_ledger.py")
SOURCE = load("response_files_live_source", HERE.parent / "archive_source/ledger.py")
TRUSTED = LEDGER.TRUSTED
U64 = (1 << 64) - 1
MAGIC, OWNER_MAGIC = 1381189169, 1381189170
PHASES = {value: value.lower() for value in "BLEVDPQRH"}
DATA = b"\0\xff\x80a\r\n"


def rule(name, ordinal, error=None, retval=None):
    result = dict(syscall=name, when=ordinal)
    result["error" if error is not None else "retval"] = error if error is not None else retval
    return result


def command(executable, trace, rules):
    result = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
              "-e", "signal=none", "-e", "trace=" + LEDGER.TRACE, "-o", str(trace)]
    for item in rules:
        field = "error" if "error" in item else "retval"
        result += ["-e", "inject=%s:%s=%s:when=%d" %
                   (item["syscall"], field, item[field], item["when"])]
    return result + [str(executable)]


def prefix_body(text, profile, executable):
    """ACK prefixes have no exit. Validate their actual launch, never invent one."""
    assert text.endswith("\n"), "partial checkpoint prefix"
    launch, body = text.split("\n", 1)
    match = LEDGER.LINE.fullmatch(launch)
    assert match and match[2] == "execve" and match[4] == "0", ("invalid checkpoint launch", launch)
    assert not any(low <= int(match[1], 16) < high for low, high in LEDGER.authority(profile))
    arguments = re.fullmatch(r'("(?:\\x[0-9a-f]{2})*"), \[.*\], (?:0x[0-9a-f]+(?: /\* [0-9]+ vars \*/)?|NULL)', match[3])
    assert arguments and LEDGER.quoted(arguments[1]) == os.fsencode(Path(executable).resolve()), launch
    LEDGER.events(body)  # no other launch, exit or unobserved syscall is accepted
    return body


def phase_admission(item, owner):
    """The shared KV set observes calls; this probe's phases authorize them."""
    name, phase, args = item["name"], item["phase"], LEDGER.arguments(item["args"])
    if "marker" in item:
        assert not owner or item["marker"].upper() in "EDH", ("foreign owner marker", item)
        return
    if phase is None:
        if name == "getpid":
            assert item["args"] == "" and item["result"].isdecimal() and int(item["result"]) > 0, item
        else:
            assert name in ("read", "write"), ("host effect outside fixture action", item)
            assert args[0] == ("0" if name == "read" else "1"), ("nonprotocol descriptor", item)
            assert 1 <= int(args[-1]) <= 1024 and item["result"].isdecimal(), item
            assert 0 < int(item["result"]) <= int(args[-1]), item
        return
    if owner:
        allowed = {"E": {"mmap", "munmap"}, "D": {"munmap"}, "H": {"munmap"}}
    else:
        allowed = {
            "B": {"openat"}, "L": {"openat", "statx", "read", "close", "mmap", "munmap"},
            "E": {"openat", "statx", "read", "close", "mmap", "munmap"},
            "V": {"fcntl"}, "D": {"munmap"}, "P": {"close"}, "Q": {"close"},
            "R": {"renameat2", "mkdirat"}, "H": {"openat", "fchdir", "close"},
        }
    assert name in allowed.get(phase, set()), ("syscall not authorized by fixture phase", owner, item)
    if phase == "V":
        assert len(args) == 2 and args[1] == "F_GETFD", ("base check changed descriptor state", item)
    if phase in ("L", "E") and name == "read":
        assert args[0].isdecimal() and int(args[0]) > 2, ("provider used protocol descriptor", item)


def analyze_body(body, profile, directory, rules=(), final=False, owner=False):
    events = LEDGER.events(body)
    ranges = LEDGER.authority(profile)
    assert all(any(low <= item["ip"] < high for low, high in ranges) for item in events)
    phase, markers = None, bytearray()
    for item in events:
        item["phase"] = phase
        token = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', item["args"]) if item["name"] == "write" and item["result"] == "1" else None
        if token:
            value = chr(int(token[1], 16))
            assert value in set(PHASES) | set(PHASES.values()), ("unknown fixture marker", item)
            if value in PHASES:
                assert phase is None, ("overlapping fixture phase", item)
                phase = value
                item["phase"] = phase
            else:
                assert phase is not None and PHASES[phase] == value, ("unmatched fixture marker", item)
                phase = None
            item["marker"] = value
            markers.extend(value.encode())
        phase_admission(item, owner)
    assert phase is None, "unfinished fixture phase"
    memory = "".join(item["line"] + "\n" for item in events if item["name"] in ("mmap", "munmap"))
    source = SOURCE.source(memory, profile)
    allocation_sites = {site for site, _ in profile[0]}
    source["allocations"] = [dict(item, length=int(LEDGER.arguments(item["args"])[1]))
                             for item in events if item["name"] == "mmap" and item["ip"] in allocation_sites]
    live, generations, acquisitions = {}, Counter(), []
    failed = {}
    for item in events:
        name, args, result = item["name"], LEDGER.arguments(item["args"]), item["result"].split()[0]
        if name in ("open", "openat") and result.isdecimal():
            fd = int(result)
            assert fd not in live, ("reacquired live descriptor", item, live)
            generations[fd] += 1
            owner = dict(fd=fd, generation=generations[fd], acquired=item, logical_error=None)
            live[fd] = owner
            acquisitions.append(owner)
        elif name == "fcntl" and len(args) > 1 and args[1] in ("F_DUPFD", "F_DUPFD_CLOEXEC"):
            raise AssertionError(("provider/probe unexpectedly duplicated a descriptor", item))
        elif name in ("read", "statx") and item["phase"] in ("L", "E"):
            assert args[0].isdecimal() and int(args[0]) in live, ("provider used an unowned file", item)
            assert live[int(args[0])]["acquired"]["phase"] == item["phase"], ("provider used borrowed/setup fd", item)
        elif name == "close":
            fd = int(args[0])
            assert fd in live, ("unowned/repeated close", item)
            owner = live[fd]
            item["generation"] = owner["generation"]
            assert not (owner["acquired"]["phase"] == "B" and item["phase"] in ("L", "E")), "provider closed borrowed base"
            if result == "0":
                if owner["logical_error"] is not None:
                    assert item["phase"] == "Q", ("skipped close retried by production", item)
                    failed[owner["logical_error"]]["repair"] = item
                else:
                    assert item["phase"] != "Q", ("repair had no skipped close", item)
                live.pop(fd)
            else:
                target = [value for value in rules if value["syscall"] == "close" and value["when"] == item["ordinal"]]
                assert len(target) == 1 and target[0].get("error") in ("EIO", "EINTR"), item
                assert item["phase"] in ("L", "E") and owner["logical_error"] is None and "INJECTED" in item["result"], item
                owner["logical_error"] = item["ordinal"]
                failed[item["ordinal"]] = dict(event=item, repair=None)
    if final:
        assert not live and not source["live"], ("owner survives explicit final release", live, source["live"])
        assert all(value["repair"] is not None for value in failed.values()), failed
        TRUSTED.source_maps(memory, profile, directory)
    result = dict(events=events, source=source, live=live, acquisitions=acquisitions,
                  failed=failed, markers=bytes(markers))
    if final:
        LEDGER.check_injections(result, rules)
    return result


def selected(result, name, phase=None):
    return [item for item in result["events"] if item["name"] == name and (phase is None or item["phase"] == phase)]


def bind(before, after, target):
    name, ordinal = target["syscall"], target["when"]
    prior, actual = selected(before, name), selected(after, name)
    assert len(prior) >= ordinal and len(actual) >= ordinal, target
    left, right = prior[ordinal - 1], actual[ordinal - 1]
    assert (left["ip"], left["phase"]) == (right["ip"], right["phase"]), (left, right)
    if name == "mmap":
        return LEDGER.bind_target(before, after, name, ordinal)
    def shape(item):
        args = LEDGER.arguments(item["args"])
        if name == "read":
            return item["ip"], item["phase"], args[0], args[-1]
        if name == "statx":
            # Its output is a printed struct on success and a raw pointer on
            # error. Bind the four actual input arguments, never that output.
            return item["ip"], item["phase"], args[:4]
        return item["ip"], item["phase"], args
    assert [shape(value) for value in prior[:ordinal]] == [shape(value) for value in actual[:ordinal]], ("fault request prefix differs", name)
    return right


def read_exact(stream, length, deadline):
    output = bytearray()
    while len(output) < length:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], "native report deadline"
        part = os.read(stream.fileno(), length - len(output))
        assert part, ("premature native report EOF", len(output), length)
        output.extend(part)
    return bytes(output)


def checkpoint(trace, output, deadline):
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), output)
        except (FileNotFoundError, SOURCE.CheckpointPending):
            assert time.monotonic() < deadline, "trace did not publish the completed report"
            time.sleep(0.002)


def process_owners(pid, live, descriptors):
    assert {int(path.name) for path in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2} | set(descriptors), ("live fd mismatch", pid, descriptors)
    ranges = []
    for line in Path(f"/proc/{pid}/maps").read_text().splitlines():
        low, high = line.split()[0].split("-")
        ranges.append((int(low, 16), int(high, 16)))
    for pointer, length in live.items():
        assert any(low <= pointer and pointer + length <= high for low, high in ranges), ("source owner missing before exit", pointer, length)
    return ranges


class Suite:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="response-files-" + group + "-"))
        self.profile = LEDGER.verified_sites(self.executable, self.directory)
        self.deadline, self.count, self.oom = time.monotonic() + 75, 0, 0
        print("evidence=" + str(self.directory), flush=True)

    def run(self, label, *, mode=0, maximum=16, calls=64, follow=False, repeats=1, selector=0,
            path=b"data", data=DATA, rules=(), baseline=None, repair=U64, owner=False):
        self.count += 1
        directory = self.directory / ("%03d-" % self.count + label)
        directory.mkdir()
        base = directory / "base"
        base.mkdir()
        (directory / "elsewhere").mkdir()
        (directory / "elsewhere/data").write_bytes(b"wrong-base")
        (base / "data").write_bytes(data)
        (base / "empty").write_bytes(b"")
        (base / "dir").mkdir()
        os.mkfifo(base / "fifo")
        os.symlink("data", base / "link")
        os.symlink("absent", base / "dangling")
        (os.fsencode(base) + b"/\xff.rsp")
        with open(os.fsencode(base) + b"/\xff.rsp", "wb") as output:
            output.write(DATA)
        (base / "nested").mkdir()
        (base / "nested/top").write_bytes(b"@child")
        (base / "child").write_bytes(b"'root value'")
        (base / "nested/child").write_bytes(b"wrong-nesting")
        trace = directory / "syscalls.log"
        cmd = command(self.executable, trace, rules)
        request = b"" if owner else struct.pack("<8Q", mode, maximum & U64, calls, follow, repeats, selector, len(path), repair) + path
        (directory / "command.txt").write_text(repr(cmd) + "\n")
        (directory / "request.bin").write_bytes(request)
        process = subprocess.Popen(cmd, cwd=directory, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        deadline, captured, frames, snapshots, admitted = min(self.deadline, time.monotonic() + 8), bytearray(), [], [], set()
        try:
            if request:
                assert os.write(process.stdin.fileno(), request) == len(request)
            for index in range(3 if owner else 2):
                words = 16 if owner else 32
                header = read_exact(process.stdout, words * 8, deadline)
                values = struct.unpack("<%dQ" % words, header)
                length = values[6] if owner else values[7]
                assert length <= 32768
                payload = read_exact(process.stdout, length, deadline)
                captured.extend(header + payload)
                assert values[0] == (OWNER_MAGIC if owner else MAGIC)
                pid = values[1] if owner else values[3]
                assert values[2] == index
                if not owner:
                    assert values[1] == 1 and values[4] == mode and values[24] == repeats
                assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(pid)]
                body = prefix_body(checkpoint(trace, bytes(captured), deadline), self.profile, self.executable)
                result = analyze_body(body, self.profile, directory, rules, final=index == (2 if owner else 1), owner=owner)
                maps = process_owners(pid, result["source"]["live"], result["live"])
                if not owner and index == 0:
                    assert Path(f"/proc/{pid}/cwd").resolve() == (directory / "elsewhere" if mode == 2 else directory), "native cwd transition not observed"
                admitted.update(result["source"]["live"])
                if owner and index == 1:
                    assert sorted(result["source"]["live"].values()) == ([7] if length else []), "Expansion destroyed the caller-owned provider error or kept its own storage"
                if index == (2 if owner else 1):
                    assert not result["source"]["live"] and not result["live"]
                    assert not any(any(low <= pointer < high for low, high in maps) for pointer in admitted), "freed source mapping survives before exit"
                frames.append((values, payload))
                snapshots.append(result)
                assert os.write(process.stdin.fileno(), b"!") == 1
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            (directory / "stdout.bin").write_bytes(captured + rest)
            (directory / "stderr.bin").write_bytes(stderr)
            assert process.returncode == 0 and not rest, (process.returncode, rest, stderr)
            body, _, _ = LEDGER.normalize_trace(trace.read_text(), self.profile, executable=self.executable, status=process.returncode)
            result = analyze_body(body, self.profile, directory, rules, final=True, owner=owner)
            assert stderr == result["markers"], (stderr, result["markers"])
            if baseline is not None:
                for target in rules:
                    bind(baseline["ledger"], result, target)
            result = dict(ledger=result, frames=frames, snapshots=snapshots, directory=directory)
            if owner:
                check_owned(result, bool(rules))
            else:
                check_provider(result, mode, calls, repair)
            return result
        except BaseException as error:
            (directory / "stdout-prefix.bin").write_bytes(captured)
            if process.poll() is None:
                process.kill()
            out, stderr = process.communicate(timeout=3)
            (directory / "remaining-stdout.bin").write_bytes(out)
            (directory / "stderr.bin").write_bytes(stderr)
            (directory / "failure.txt").write_text(repr(error) + "\nreturncode=" + str(process.returncode) + "\n")
            raise


def check_provider(result, mode, allowance, repair):
    values, payload = result["frames"][0]
    entries = result["ledger"]["events"]
    provider_calls = [item for item in entries if item["phase"] in ("L", "E") and item["name"] in ("openat", "statx", "read", "close")]
    assert values[6] == len(provider_calls) <= allowance, (values, provider_calls)
    bases = [item for item in result["ledger"]["acquisitions"] if item["acquired"]["phase"] == "B"]
    if mode not in (3, 4, 6):
        assert len(bases) == 1 and values[25] == 1 and bases[0]["fd"] == values[5]
        assert values[5] in result["snapshots"][0]["live"], "borrowed base not physically live after load"
    for item in provider_calls:
        if item["name"] == "openat":
            args = LEDGER.arguments(item["args"])
            assert args[0] == ("AT_FDCWD" if mode == 6 else str(values[5]))
            assert all(flag in args[2].split("|") for flag in ("O_RDONLY", "O_CLOEXEC", "O_NONBLOCK", "O_NOCTTY")), item
    for item in selected(result["ledger"], "read"):
        args = LEDGER.arguments(item["args"])
        if item["phase"] in ("L", "E"):
            assert args[0] != "0" and 1 <= int(args[-1]) <= 4096
    if repair != U64:
        assert len(result["ledger"]["failed"]) == 1
        failed = next(iter(result["ledger"]["failed"].values()))
        assert int(failed["event"]["args"]) == repair and failed["repair"] is not None
    else:
        assert not result["ledger"]["failed"]
    assert result["frames"][-1][1] == b""
    if mode == 1:
        assert (result["directory"] / "moved/data").read_bytes() == DATA
        assert not list((result["directory"] / "base").iterdir())


def check_owned(result, injected):
    first, held, done = result["frames"]
    values = first[0]
    if not injected:
        assert values[3:11] == (101, 2, 1, 7, 1, 1, 1, 9), values
        assert first[1] == held[1] == b"failure"
    else:
        assert values[3] in (5, 102) and values[6] == 0 and not first[1]
    assert held[0][3:] == tuple(list(values[3:6]) + [held[0][6]] + list(values[7:])), (values, held[0])
    assert done[1] == b"" and done[0][6] == 0
    assert not any(item["name"] not in ("read", "write", "getpid", "mmap", "munmap") for item in result["ledger"]["events"]), "scripted provider accessed host services"


def expected(result, *, phase=0, cause=0, cleanup=0, output=b"", calls=None, second=False):
    values, payload = result["frames"][0]
    start = 16 if second else 8
    actual = values[start:start + 4]
    assert actual == (int(bool(phase)), phase, cause, cleanup), (actual, phase, cause, cleanup)
    assert payload == output, (payload, output)
    if calls is not None:
        assert values[6] == calls, (values[6], calls)
    return result


def provider(executable):
    suite = Suite(executable, "provider")
    expected(suite.run("empty-minimum", path=b"empty", maximum=0, calls=4), calls=4)
    baseline = expected(suite.run("binary-exact", maximum=6, calls=5), output=DATA, calls=5)
    short = expected(suite.run("real-short-read", maximum=16, calls=5), output=DATA, calls=5)
    reads = selected(short["ledger"], "read", "L")
    assert any(item["result"].split()[0].isdecimal() and 0 < int(item["result"].split()[0]) < int(LEDGER.arguments(item["args"])[-1]) for item in reads)
    exact_reads = selected(baseline["ledger"], "read", "L")
    assert [int(LEDGER.arguments(item["args"])[-1]) for item in exact_reads] == [6, 1]
    expected(suite.run("over-cap", maximum=5), phase=4, cause=4, calls=5)
    expected(suite.run("zero-cap-data", maximum=0), phase=4, cause=4, calls=4)
    expected(suite.run("less-than-minimum", calls=3), phase=1, cause=2, calls=0)
    expected(suite.run("read-credit-reserved", maximum=6, calls=4), phase=4, cause=2, calls=4)
    expected(suite.run("aggregate-nine", maximum=6, calls=9, repeats=2), phase=4, cause=2, calls=9, second=True)
    expected(suite.run("aggregate-ten", maximum=6, calls=10, repeats=2), output=DATA, calls=10, second=True)
    for label, path, phase, cause, count in (("missing", b"absent", 2, 1002, 1), ("directory", b"dir", 3, 3, 3),
                                           ("fifo-nonblocking", b"fifo", 3, 3, 3), ("nofollow", b"link", 2, 1040, 1),
                                           ("dangling", b"dangling", 2, 1002, 1)):
        expected(suite.run(label, path=path, follow=label == "dangling"), phase=phase, cause=cause, calls=count)
    for label, options in (("follow", dict(path=b"link", follow=True)), ("raw-path", dict(path=b"\xff.rsp")),
                           ("renamed-anchor", dict(mode=1)), ("changed-cwd", dict(mode=2)),
                           ("cwd-provider", dict(mode=6, path=b"base/data"))):
        expected(suite.run(label, **options), output=DATA, calls=5)
    expected(suite.run("closed-base", mode=3), phase=2, cause=1009, calls=1)
    expected(suite.run("negative-base", mode=4), phase=1, cause=1, calls=0)
    for label, options in (("negative-cap", dict(maximum=-1)), ("negative-start", dict(selector=1)),
                           ("negative-length", dict(selector=2)), ("overflow-range", dict(selector=3)),
                           ("empty-path", dict(selector=4)), ("nul-path", dict(path=b"a\0b")),
                           ("long-path", dict(path=b"a" * 4096))):
        expected(suite.run(label, **options), phase=1, cause=1, calls=0)

    load_open = selected(baseline["ledger"], "openat", "L")[0]
    metadata = selected(baseline["ledger"], "statx", "L")[0]
    read = exact_reads[0]
    close = selected(baseline["ledger"], "close", "L")[0]
    for label, target, phase, cause, count in (("open-eintr", rule("openat", load_open["ordinal"], "EINTR"), 2, 1004, 1),
                                             ("metadata-eio", rule("statx", metadata["ordinal"], "EIO"), 3, 1005, 3),
                                             ("metadata-eintr", rule("statx", metadata["ordinal"], "EINTR"), 3, 1004, 3),
                                             ("metadata-invalid-count", rule("statx", metadata["ordinal"], retval=1), 3, 1901, 3),
                                             ("read-eio", rule("read", read["ordinal"], "EIO"), 4, 1005, 4),
                                             ("read-invalid-count", rule("read", read["ordinal"], retval=7), 4, 1901, 4)):
        value = expected(suite.run(label, maximum=6, calls=5, rules=[target], baseline=baseline), phase=phase, cause=cause, calls=count)
        if label == "read-eio":
            read_error = value
    interrupt = rule("read", read["ordinal"], "EINTR")
    expected(suite.run("read-eintr-recovery", maximum=6, calls=6, rules=[interrupt], baseline=baseline), output=DATA, calls=6)
    expected(suite.run("read-eintr-exhaustion", maximum=6, calls=5, rules=[interrupt], baseline=baseline), phase=4, cause=2, calls=5)
    raw_fd = int(close["args"])
    for errno, code in (("EIO", 1005), ("EINTR", 1004)):
        target = rule("close", close["ordinal"], errno)
        expected(suite.run("close-" + errno.lower(), maximum=6, calls=5, rules=[target], baseline=baseline, repair=raw_fd), phase=5, cause=code, calls=5)
    primary = rule("read", read["ordinal"], "EIO")
    cleanup = rule("close", close["ordinal"], "EIO")
    expected(suite.run("primary-and-close", maximum=6, calls=5, rules=[primary, cleanup], baseline=read_error, repair=raw_fd), phase=4, cause=1005, cleanup=5, calls=4)
    print("response-files group=provider cases=%d" % suite.count)


def oom_campaign(suite, baseline, kwargs):
    positions = baseline["ledger"]["source"]["allocations"]
    assert positions and all(item["result"].startswith("0x") for item in positions), "allocation calibration is not complete"
    for item in positions:
        target = rule("mmap", item["ordinal"], "ENOMEM")
        result = suite.run("oom-%d" % item["ordinal"], rules=[target], baseline=baseline, **kwargs)
        first = result["frames"][0][0]
        if not kwargs.get("owner"):
            assert first[8] == 1 and first[10] in (5, 105) and first[26] == 0 and not result["frames"][0][1], first
        suite.oom += 1


def resources(executable, owners):
    native = Suite(executable, "native-resources")
    baseline = expected(native.run("fixed-base-nested", mode=5, path=b"@nested/top", maximum=64), output=b"root value", calls=10)
    assert baseline["frames"][0][0][12] == 1 and baseline["frames"][0][0][26:28] == (1, 1)
    opens = selected(baseline["ledger"], "openat", "E")
    assert [LEDGER.quoted(LEDGER.arguments(item["args"])[1]) for item in opens] == [b"nested/top", b"child"]
    oom_campaign(native, baseline, dict(mode=5, path=b"@nested/top", maximum=64))
    owned = Suite(owners, "owned-errors")
    retained = owned.run("provider-owned-error", owner=True)
    oom_campaign(owned, retained, dict(owner=True))
    print("response-files group=resources cases=%d reached-oom=%d" % (native.count + owned.count, native.oom + owned.oom))


def controls():
    class Pairs(list):
        pass
    count = 0
    allocate, release, host = 0x401002, 0x401012, 0x401022
    pairs = Pairs([(allocate, release)])
    pairs.mmap_flags = {allocate: 0x22}
    pairs.executable_ranges = [(0x400000, 0x402000)]
    profile = pairs, []
    def line(value, ip=host):
        return "[%016x] %s\n" % (ip, value)
    def mark(value):
        return line('write(2, "\\x%02x", 1) = 1' % ord(value))
    def reject(action):
        nonlocal count
        try:
            action()
        except AssertionError:
            count += 1
        else:
            raise AssertionError("response fixture accepted a causal/resource mutation")
    with tempfile.TemporaryDirectory(prefix="response-files-controls-") as temporary:
        directory = Path(temporary)
        opened = mark("B") + line('openat(AT_FDCWD, "\\x62", O_RDONLY|O_DIRECTORY) = 3') + mark("b")
        loaded = mark("L") + line('openat(3, "\\x64", O_RDONLY) = 4') + line('close(4) = 0') + mark("l")
        closed = mark("P") + line('close(3) = 0') + mark("p")
        clean = opened + loaded + closed
        assert not analyze_body(clean, profile, directory, final=True)["live"]
        count += 1
        for body in (opened + loaded, opened + loaded.replace('close(4)', 'close(3)') + closed,
                     clean + line('close(3) = 0'), clean + line('socket(AF_INET, SOCK_STREAM, 0) = 4'),
                     mark("L") + mark("B"), mark("l"), clean.replace('close(4) = 0', 'close(4) = -1 EIO (Input/output error) (INJECTED)')):
            reject(lambda body=body: analyze_body(body, profile, directory, final=True))
        skipped = opened + mark("L") + line('openat(3, "\\x64", O_RDONLY) = 4') + line('close(4) = -1 EIO (Input/output error) (INJECTED)') + mark("l")
        repaired = skipped + mark("Q") + line('close(4) = 0') + mark("q") + closed
        rules = [rule("close", 1, "EIO")]
        assert not analyze_body(repaired, profile, directory, rules, final=True)["live"]
        count += 1
        reject(lambda: analyze_body(repaired.replace(mark("Q"), mark("L")).replace(mark("q"), mark("l")), profile, directory, rules, final=True))
        reject(lambda: analyze_body(skipped + closed, profile, directory, rules, final=True))
        mapping = mark("E") + line('mmap(NULL, 7, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x123456789000', allocate) + mark("e")
        freed = mark("D") + line('munmap(0x123456789000, 7) = 0', release) + mark("d")
        assert analyze_body(mapping, profile, directory)["source"]["live"] == {0x123456789000: 7}
        assert not analyze_body(mapping + freed, profile, directory, final=True)["source"]["live"]
        count += 2
        reject(lambda: analyze_body(mapping, profile, directory, final=True))
        reject(lambda: analyze_body(mapping + freed.replace(', 7)', ', 6)'), profile, directory, final=True))
        reject(lambda: analyze_body(mapping.replace('%016x' % allocate, '%016x' % (allocate + 1)), profile, directory))
        path = Path('/response-fixture')
        encoded = ''.join('\\x%02x' % value for value in os.fsencode(path))
        launch = line('execve("' + encoded + '", [], NULL) = 0', 0x900002)
        assert prefix_body(launch + clean, profile, path) == clean
        count += 1
        reject(lambda: prefix_body(launch + clean + line('execve("' + encoded + '", [], NULL) = 0'), profile, path))
        reject(lambda: prefix_body(launch.replace(' = 0', ' = -1 ENOENT (No such file or directory)') + clean, profile, path))
        reject(lambda: prefix_body(launch + clean, profile, Path('/wrong-fixture')))
        baseline = dict(events=[dict(ip=host, phase="L", name="read", args='4, "\\x61", 6', result='1', ordinal=1)])
        same = dict(events=[dict(ip=host, phase="L", name="read", args='4, 0xabc, 6', result='-1 EIO', ordinal=1)])
        assert bind(baseline, same, rule("read", 1, "EIO"))["ip"] == host
        count += 1
        for field, value in (("ip", host + 1), ("phase", "E"), ("args", '5, 0xabc, 6'), ("args", '4, 0xabc, 7')):
            bad = dict(events=[dict(same["events"][0], **{field: value})])
            reject(lambda bad=bad: bind(baseline, bad, rule("read", 1, "EIO")))
        # These names are observed/accepted by the shared KV event parser.
        # This fixture must reject them when the action did not authorize them.
        for phase, action in (("L", 'unlinkat(3, "\\x64", 0) = 0'),
                              ("E", 'renameat2(3, "\\x61", 3, "\\x62", 0) = 0'),
                              ("L", 'mkdirat(3, "\\x61", 0700) = 0'),
                              ("E", 'fsync(4) = 0'),
                              ("V", 'fcntl(3, F_SETFD, 0) = 0'),
                              ("D", 'mmap(NULL, 7, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x123456789000'),
                              ("P", 'statx(3, "", AT_EMPTY_PATH, STATX_ALL, 0x100) = 0'),
                              ("L", 'read(0, "\\x61", 1) = 1'),
                              ("E", 'write(1, "\\x61", 1) = 1')):
            body = mark(phase) + line(action, allocate if action.startswith("mmap") else host) + mark(phase.lower())
            reject(lambda body=body: analyze_body(body, profile, directory))
        reject(lambda: analyze_body(line('unlinkat(3, "\\x64", 0) = 0'), profile, directory))
        for phase in ("E", "H"):
            body = mark(phase) + line('openat(AT_FDCWD, "\\x61", O_RDONLY) = 3') + mark(phase.lower())
            reject(lambda body=body: analyze_body(body, profile, directory, owner=True))
        metadata = dict(events=[dict(ip=host, phase="L", name="statx", args='4, "", AT_EMPTY_PATH, STATX_ALL, {stx_mask=STATX_TYPE, stx_mode=S_IFREG|0600}', result='0', ordinal=1)])
        failed_metadata = dict(events=[dict(metadata["events"][0], args='4, "", AT_EMPTY_PATH, STATX_ALL, 0xabc', result='-1 EIO')])
        assert bind(metadata, failed_metadata, rule("statx", 1, "EIO"))["ip"] == host
        count += 1
        changed_mask = dict(events=[dict(failed_metadata["events"][0], args='4, "", AT_EMPTY_PATH, STATX_TYPE, 0xabc')])
        reject(lambda: bind(metadata, changed_mask, rule("statx", 1, "EIO")))
    print("response-files CPU controls=%d" % count)


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    elif len(sys.argv) == 3 and sys.argv[1] == "provider":
        provider(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "resources":
        resources(sys.argv[2], sys.argv[3])
    else:
        raise SystemExit("usage: files_oracle.py controls | provider FILES_ELF | resources FILES_ELF OWNERS_ELF")
