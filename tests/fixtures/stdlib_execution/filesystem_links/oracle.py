"""Independent finite host oracle for checked link and permission primitives.

All mutations stay in test-owned directories. Raw syscall instruction authority
and full-width source-map accounting are explicit; process exit is not cleanup.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import stat
import struct
import subprocess
import sys
import tempfile
import time


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
SOURCE = load("filesystem_links_live_source", HERE.parents[1] / "extended/archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
MAGIC, MAX = 1179864113, (1 << 64) - 1
DATA = b"source\0\xffdata"
NAMES = ("linkat", "symlinkat", "readlinkat", "fchmod", "fchmodat")
CALLS = TRUSTED.CALLS | set(NAMES) | {"link", "symlink", "readlink", "chmod", "fchmodat2"}
TRACE = ",".join(sorted(CALLS))
# Exact checked std::linux::syscall6 thunk: six complete words, no retry. The
# existing allocator verifier remains unchanged. This is not a generic scanner.
SYSCALL6 = bytes.fromhex("4889f84989f3498b3b498b7308498b53104d8b53184d8b43204d8b4b280f05c3")


def profile(executable, directory):
    source = TRUSTED.verified_sites(executable, directory)
    assert source[0] and not source[1] and source[0].executable_ranges, "expected verified raw source image"
    image = Path(executable).read_bytes()
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", image)
    assert header[6] == 0, "expected sectionless ELF"
    sites = set()
    for index in range(header[10]):
        kind, flags, offset, address, _, size, _memory, _alignment = struct.unpack_from("<IIQQQQQQ", image, header[5] + index * header[9])
        if kind != 1 or not flags & 1:
            continue
        code = image[offset:offset + size]
        at = code.find(SYSCALL6)
        while at >= 0:
            sites.add(address + at + 31)  # strace's post-syscall IP
            at = code.find(SYSCALL6, at + 1)
    assert sites, "missing exact six-word Linux syscall thunk"
    binary = directory / "verified-linux-syscall6.bin"
    binary.write_bytes(SYSCALL6)
    decoded = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "i386:x86-64", "--no-show-raw-insn", str(binary)],
                             capture_output=True, text=True, check=True, timeout=10).stdout
    instructions = {int(match[1], 16): match[2] for line in decoded.splitlines()
                    if (match := re.match(r"^\s*([0-9a-f]+):\s+(\S+)", line))}
    assert instructions.get(29) == "syscall" and instructions.get(31) == "ret", instructions
    return source, sites


def events(text):
    assert not text or text.endswith("\n"), "partial native trace"
    counts, found, phases, active, markers = Counter(), [], [], None, bytearray()
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported native event", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        item = dict(ip=int(ip, 16), name=name, args=args, result=result, ordinal=counts[name], index=index, line=line)
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in "CcPp", item
            markers.extend(token.encode())
            if token.isupper():
                assert active is None, item
                active = dict(name=token, events=[])
                phases.append(active)
            else:
                assert active and active["name"] == token.upper(), item
                active = None
        elif active is not None:
            active["events"].append(item)
        found.append(item)
    assert active is None, "unclosed primitive phase"
    return dict(events=found, phases=phases, markers=bytes(markers))


def analyze(text, authority, directory, final=False):
    source, sites = authority
    parsed = events(text)
    for item in parsed["events"]:
        assert any(low <= item["ip"] < high for low, high in source[0].executable_ranges), ("syscall outside verified image", item)
        if item["name"] in NAMES:
            assert item["ip"] in sites, ("primitive syscall outside exact six-word thunk", item)
    mappings = "".join(item["line"] + "\n" for item in parsed["events"] if item["name"] in ("mmap", "munmap"))
    owned = SOURCE.source(mappings, source)
    assert not owned["attempts"] and not owned["live"], "allocation-free primitive fixture allocated"
    if final:
        TRUSTED.source_maps(mappings, source, directory)
    live = set()
    for item in parsed["events"]:
        args, result = TRUSTED.arguments(item["args"]), item["result"].split()[0]
        if item["name"] == "openat" and result.isdecimal():
            fd = int(result)
            assert fd not in live, item
            live.add(fd)
        elif item["name"] == "close":
            fd = int(args[0])
            assert fd in live and result == "0", ("unowned/repeated/failed close", item, live)
            live.remove(fd)
    parsed["live"] = live
    if final:
        assert not live, ("descriptor owner survived cleanup", live)
    return parsed


def mode_value(value):
    result = 0
    for part in value.split("|"):
        if part in ("S_ISUID", "S_ISGID", "S_ISVTX"):
            result |= {"S_ISUID": 0o4000, "S_ISGID": 0o2000, "S_ISVTX": 0o1000}[part]
        else:
            assert re.fullmatch(r"0[0-7]*", part), value
            result |= int(part, 8)
    return result


def fd_value(value):
    return -100 if value == "AT_FDCWD" else int(value)


def primitive(parsed, op, first, second, follow, cwd, words, destlen, mode, native):
    scopes = [scope["events"] for scope in parsed["phases"] if scope["name"] == "C"]
    assert len(scopes) == 1 and len(scopes[0]) == native, scopes
    all_target = [item for item in parsed["events"] if item["name"] in set(NAMES) | {"link", "symlink", "readlink", "chmod", "fchmodat2"}]
    assert all_target == scopes[0], ("extra primitive/fallback call", all_target, scopes)
    if not native:
        return None
    item = scopes[0][0]
    assert item["name"] == NAMES[op], item
    args = TRUSTED.arguments(item["args"])
    oldfd, newfd = words[6], words[7]
    oldfd = oldfd if oldfd < (1 << 63) else oldfd - (1 << 64)
    newfd = newfd if newfd < (1 << 63) else newfd - (1 << 64)
    if cwd:
        oldfd = newfd = -100
    if op == 0:
        assert len(args) == 5 and fd_value(args[0]) == oldfd and TRUSTED.quoted(args[1]) == first
        assert fd_value(args[2]) == newfd and TRUSTED.quoted(args[3]) == second
        assert args[4] == ("AT_SYMLINK_FOLLOW" if follow else "0"), item
        key = (oldfd, first, newfd, second, follow)
    elif op == 1:
        assert len(args) == 3 and TRUSTED.quoted(args[0]) == first and fd_value(args[1]) == newfd and TRUSTED.quoted(args[2]) == second, item
        key = (first, newfd, second)
    elif op == 2:
        assert len(args) == 4 and fd_value(args[0]) == oldfd and TRUSTED.quoted(args[1]) == first
        request = min(destlen + 1, 4096)
        assert int(args[3]) == request, item
        # The output address varies with ASLR and pretty-printing changes on
        # errno. Input fd/path/request and verified thunk IP remain exact.
        key = (oldfd, first, request)
    elif op == 3:
        assert len(args) == 2 and int(args[0]) == words[5] and mode_value(args[1]) == mode, item
        key = (words[5], mode)
    else:
        assert len(args) == 3 and fd_value(args[0]) == oldfd and TRUSTED.quoted(args[1]) == first and mode_value(args[2]) == mode, item
        key = (oldfd, first, mode)
    return dict(item, key=key)


def read_exact(stream, count, deadline):
    result = bytearray()
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], ("native read deadline", len(result), count)
        chunk = os.read(stream.fileno(), count - len(result))
        assert chunk, ("native report EOF", len(result), count)
        result.extend(chunk)
    return bytes(result)


def prefix(trace, output, deadline):
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), output)
        except (SOURCE.CheckpointPending, FileNotFoundError):
            assert time.monotonic() < deadline, "native trace flush deadline"
            time.sleep(0.002)


def fdinfo(pid, fd):
    result = dict(line.split(":", 1) for line in Path(f"/proc/{pid}/fdinfo/{fd}").read_text().splitlines())
    return int(result["pos"].strip()), int(result["flags"].strip(), 8)


def snapshot(root, readable):
    result = {}
    for current, dirs, files in os.walk(os.fsencode(root), followlinks=False):
        for name in dirs + files:
            path = os.path.join(current, name)
            info = os.lstat(path)
            key = os.path.relpath(path, os.fsencode(root))
            item = (stat.S_IFMT(info.st_mode), stat.S_IMODE(info.st_mode), info.st_dev, info.st_ino, info.st_nlink, info.st_size)
            if stat.S_ISLNK(info.st_mode):
                item += (os.readlink(path),)
            elif stat.S_ISREG(info.st_mode):
                handle = readable.get((info.st_dev, info.st_ino))
                item += (os.pread(handle, info.st_size, 0) if handle is not None else Path(os.fsdecode(path)).read_bytes(),)
            result[key] = item
    return result


def destination(actual, initial, op, code, destlen, payload, values, *, synthetic_count=None, known_prefix=None):
    assert len(actual) == len(initial)
    if synthetic_count is not None:
        # A short strace poke establishes ONLY these bytes. The returned count
        # still exercises the full probe/copy bound, without inventing a full
        # kernel write or relying on the native stack's prior contents.
        assert op == 2 and code == 0 and known_prefix is not None
        request = min(destlen + 1, 4096)
        assert 0 <= synthetic_count <= request
        copied = min(synthetic_count, destlen)
        assert len(known_prefix) <= copied
        assert values[9:11] == (copied, int(synthetic_count < request)), values
        assert actual[:3] == initial[:3], "synthetic readlink changed prefix guard"
        assert actual[3:3 + len(known_prefix)] == known_prefix, "synthetic readlink lost supplied prefix"
        assert actual[3 + copied:] == initial[3 + copied:], "synthetic readlink changed bytes outside copied output"
        # Deliberately do not constrain the unprovided copied interior.
        return
    assert known_prefix is None
    expected = bytearray(initial)
    if op == 2 and code == 0:
        assert payload is not None
        count = min(len(payload), min(destlen + 1, 4096))
        copied, complete = min(count, destlen), count < min(destlen + 1, 4096)
        assert values[9:11] == (copied, int(complete)), values
        expected[3:3 + copied] = payload[:copied]
    else:
        assert values[9:11] == (0, 0), values
    assert actual == expected, "destination atomicity/stride/guard mismatch"


class Suite:
    def __init__(self, group, executable):
        self.group, self.executable = group, Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="filesystem-links-" + group + "-"))
        self.authority = profile(self.executable, self.directory)
        self.deadline, self.count = time.monotonic() + 75, 0
        print(f"evidence={self.directory}", flush=True)

    def run(self, label, op, *, first=b"source", second=b"made", follow=False, cwd=False,
            first_view=0, second_view=0, destlen=16, destview=0, layout=0, descriptors=0,
            mode=0o640, anchored=False, code=0, native=1, setup=None, check=None,
            target=None, injection=None, baseline=None, synthetic=None, synthetic_count=None, known_prefix=None):
        assert time.monotonic() < self.deadline, "finite filesystem group deadline"
        if synthetic_count is not None:
            assert synthetic is None and injection and injection.get("retval") == synthetic_count
            assert injection.get("poke") == known_prefix and len(known_prefix) <= 16
        directory = self.directory / f"{self.count:02d}-{label}"
        directory.mkdir()
        work = directory / "work"
        work.mkdir()
        for name in ("left", "right", "elsewhere"):
            (work / name).mkdir()
        for name in ("left/source", "left/mode-target", "mode-file"):
            (work / name).write_bytes(DATA)
        os.symlink(b"source", os.fsencode(work / "left/sym"))
        os.symlink(b"mode-target", os.fsencode(work / "left/mode-sym"))
        if setup:
            setup(work)
        first = first(work) if callable(first) else first
        second = second(work) if callable(second) else second
        assert len(first) <= 4096 and len(second) <= 4096 and destlen <= 4096
        request = struct.pack("<13Q", op, int(follow), int(cwd), len(first), len(second), first_view,
                              second_view, destlen, destview, layout, descriptors, mode, int(anchored))
        request += first.ljust(4096, b"\0") + second.ljust(4096, b"\0")
        (directory / "request.bin").write_bytes(request)
        initial = bytearray([165] * 4104)
        if layout == 2:
            initial[3:3 + len(first)] = first
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "16384", "-e", "signal=none",
                   "-e", "trace=" + TRACE, "-o", str(trace)]
        if injection:
            fault = NAMES[op] + (":error=" + injection["error"] if "error" in injection else ":retval=" + str(injection["retval"]))
            if "poke" in injection:
                fault += ":poke_exit=@arg3=" + injection["poke"].hex()
            command += ["-e", "inject=" + fault + ":when=" + str(injection["when"])]
        command.append(str(self.executable))
        (directory / "command.txt").write_text(repr(command) + "\n")
        readable, held = {}, []
        for name in ("mode-file", "left/mode-target"):
            fd = os.open(work / name, os.O_RDONLY)
            held.append(fd)
            info = os.fstat(fd)
            readable[(info.st_dev, info.st_ino)] = fd
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=work, bufsize=0, umask=0o022)
        deadline = min(self.deadline, time.monotonic() + 8)
        emitted = bytearray()
        try:
            at = 0
            while at < len(request):
                remaining = deadline - time.monotonic()
                assert remaining > 0 and select.select([], [process.stdin], [], remaining)[1], "native request deadline"
                sent = os.write(process.stdin.fileno(), request[at:at + 4096])
                assert sent > 0
                at += sent
            raw = read_exact(process.stdout, 160, deadline)
            emitted.extend(raw)
            ready = struct.unpack("<20Q", raw)
            assert ready[0:2] == (MAGIC, 0) and ready[8:11] == (0, 0, 0) and ready[16] == op and ready[19] == mode, ready
            pid = ready[2]
            assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(pid)]
            assert {int(item.name) for item in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2, ready[3], ready[4], ready[5]}
            for index, name in ((3, "left"), (4, "right"), (5, "mode-file")):
                a, b = os.stat(f"/proc/{pid}/fd/{ready[index]}"), os.stat(work / name)
                assert (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino)
            before_info = fdinfo(pid, ready[5])
            assert before_info[0] == ready[11] == 3 and before_info[1] & os.O_APPEND and before_info[1] & os.O_NONBLOCK
            assert bool(before_info[1] & os.O_CLOEXEC) == bool(ready[17])
            analyze(prefix(trace, bytes(emitted), deadline), self.authority, directory)
            if anchored:
                for name in ("left", "right"):
                    (work / name).rename(work / ("moved-" + name))
                    (work / name).mkdir()
            before = snapshot(work, readable)
            assert os.write(process.stdin.fileno(), b"!") == 1
            packet = read_exact(process.stdout, 160 + 4104, deadline)
            emitted.extend(packet)
            values = struct.unpack_from("<20Q", packet)
            assert values[0:2] == (MAGIC, 1) and values[2:8] == ready[2:8] and values[16] == op and values[19] == mode, values
            assert values[8] == code and values[13] == ready[13] and values[17] == ready[17], ("typed primitive result", values, code)
            expected_live = {ready[3], ready[4], ready[5]}
            for bit, index in ((16, 3), (32, 4), (64, 5)):
                if descriptors & bit:
                    expected_live.remove(ready[index])
            assert {int(item.name) for item in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2} | expected_live
            if not descriptors & 64:
                assert fdinfo(pid, ready[5]) == before_info
                assert values[11] == values[12] == 3 and values[13] == values[14] and values[17] == values[18]
            current = analyze(prefix(trace, bytes(emitted), deadline), self.authority, directory)
            assert current["live"] == expected_live
            reached = primitive(current, op, first, second, follow, cwd, values, destlen, mode, native)
            marked = [item for item in current["events"] if "INJECTED" in item["result"]]
            assert len(marked) == int(injection is not None), marked
            if injection:
                assert reached and marked == [next(item for item in current["events"] if item["index"] == reached["index"])]
                assert reached["ordinal"] == injection["when"]
                if "error" in injection:
                    assert reached["result"].split()[:2] == ["-1", injection["error"]], reached
                else:
                    assert int(reached["result"].split()[0]) == injection["retval"], reached
            if baseline:
                assert (reached["ip"], reached["ordinal"], reached["key"]) == (baseline["ip"], baseline["ordinal"], baseline["key"]), (reached, baseline)
            destination(packet[160:], initial, op, code, destlen, synthetic if synthetic is not None else target, values,
                        synthetic_count=synthetic_count, known_prefix=known_prefix)
            if code or injection:
                assert snapshot(work, readable) == before, "rejected/skipped syscall changed filesystem"
            if anchored:
                assert not list((work / "left").iterdir()) and not list((work / "right").iterdir())
            if check:
                check(work)
            assert os.write(process.stdin.fileno(), b"!") == 1
            released = read_exact(process.stdout, 160, deadline)
            emitted.extend(released)
            words = struct.unpack("<20Q", released)
            assert words[:1] + words[2:] == values[:1] + values[2:] and words[1] == 2
            final = analyze(prefix(trace, bytes(emitted), deadline), self.authority, directory, final=True)
            assert {int(item.name) for item in Path(f"/proc/{pid}/fd").iterdir()} == {0, 1, 2}
            assert final["markers"] == b"CcPp"
            assert os.write(process.stdin.fileno(), b"!") == 1
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            assert process.returncode == 0 and not rest and stderr == b"CcPp", (process.returncode, rest, stderr)
            complete = analyze(trace.read_text(), self.authority, directory, final=True)
            assert len(complete["events"]) == len(final["events"]) + 1 and complete["events"][-1]["name"] == "read"
            (directory / "stdout.bin").write_bytes(emitted)
            self.count += 1
            return reached
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(emitted)
            if process.poll() is None:
                process.kill()
            try:
                rest, stderr = process.communicate(timeout=2)
                (directory / "stdout-tail.bin").write_bytes(rest)
                (directory / "stderr.bin").write_bytes(stderr)
            except (ValueError, subprocess.TimeoutExpired):
                pass
            print(f"FAILED evidence={directory}", file=sys.stderr, flush=True)
            raise
        finally:
            for fd in held:
                os.close(fd)


def linked(source, destination, follow=True, target=b"source"):
    def check(work):
        a, b = os.stat(work / source, follow_symlinks=follow), os.lstat(work / destination)
        assert (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino) and a.st_nlink == b.st_nlink == 2
        if not follow:
            assert stat.S_ISLNK(b.st_mode) and os.readlink(os.fsencode(work / destination)) == target
        else:
            assert stat.S_ISREG(b.st_mode) and (work / destination).read_bytes() == DATA
    return check


def symlinked(target, name="right/made"):
    def check(work):
        value = os.fsencode(work / name)
        assert stat.S_ISLNK(os.lstat(value).st_mode) and os.readlink(value) == target
    return check


def links(suite):
    suite.run("hardlink", 0, check=linked("left/source", "right/made"))
    suite.run("hardlink-cwd", 0, first=b"left/source", second=b"right/made", cwd=True, check=linked("left/source", "right/made"))
    suite.run("hardlink-symlink-inode", 0, first=b"sym", check=linked("left/sym", "right/made", False))
    suite.run("hardlink-follow-source", 0, first=b"sym", follow=True, check=linked("left/source", "right/made"))
    dangling = lambda w: os.symlink(b"absent", w / "left/dangling")
    suite.run("hardlink-dangling-inode", 0, first=b"dangling", setup=dangling, check=linked("left/dangling", "right/made", False, b"absent"))
    suite.run("hardlink-follow-dangling", 0, first=b"dangling", follow=True, setup=dangling, code=2)
    for kind in ("file", "directory", "symlink"):
        def setup(work, kind=kind):
            name = work / "right/made"
            if kind == "file": name.write_bytes(b"preserved")
            if kind == "directory": name.mkdir()
            if kind == "symlink": os.symlink("absent", name)
        for op in (0, 1):
            suite.run(f"nonreplacement-{op}-{kind}", op, code=17, setup=setup)
    suite.run("hardlink-directory", 0, first=b".", code=1)
    suite.run("hardlink-missing", 0, first=b"absent", code=2)
    suite.run("hardlink-bad-oldfd", 0, descriptors=1, code=9)
    suite.run("hardlink-bad-newfd", 0, descriptors=2, code=9)
    suite.run("hardlink-regular-parent", 0, descriptors=4, code=20)
    suite.run("hardlink-absolute-ignores-fds", 0, descriptors=3,
              first=lambda w: os.fsencode(w / "left/source"), second=lambda w: os.fsencode(w / "right/made"), check=linked("left/source", "right/made"))
    suite.run("hardlink-renamed-anchors", 0, anchored=True, check=linked("moved-left/source", "moved-right/made"))
    for target in (b"source", b"../left/source", b"absent", b"../raw-\xff/\x80", b"/absolute/absent"):
        suite.run("symlink-" + target.hex(), 1, first=target, check=symlinked(target))
    suite.run("symlink-cwd", 1, cwd=True, first=b"../left/source", second=b"right/made", check=symlinked(b"../left/source"))
    suite.run("symlink-renamed-anchor", 1, first=b"../moved-left/source", anchored=True, check=symlinked(b"../moved-left/source", "moved-right/made"))
    suite.run("symlink-empty-target", 1, first=b"", code=2)
    suite.run("symlink-bad-parent", 1, descriptors=2, code=9)


def readlink(suite):
    for payload in (b"x", b"relative/\xff\x80", b"z" * 4095):
        def setup(work, payload=payload): os.symlink(payload, os.fsencode(work / "left/link"))
        lengths = (0, len(payload), max(0, len(payload) - 1), 4096)
        for index, count in enumerate(lengths):
            suite.run(f"read-{len(payload)}-{count}-layout-{index % 3}", 2, first=b"link", destlen=count, layout=index % 3, setup=setup, target=payload)
    payload = b"../target-\xff"
    setup = lambda w: os.symlink(payload, os.fsencode(w / "left/link"))
    suite.run("read-cwd", 2, cwd=True, first=b"left/link", destlen=len(payload), setup=setup, target=payload)
    suite.run("read-absolute-badfd", 2, descriptors=1, first=lambda w: os.fsencode(w / "left/link"), setup=setup, target=payload)
    suite.run("read-renamed-anchor", 2, first=b"link", anchored=True, setup=setup, target=payload)
    suite.run("read-missing", 2, first=b"absent", code=2)
    suite.run("read-not-symlink", 2, first=b"source", code=22)
    suite.run("read-closed-fd", 2, first=b"sym", descriptors=16, code=9)
    suite.run("read-regular-parent", 2, first=b"sym", descriptors=4, code=20)


def permissions(suite):
    for op in (3, 4):
        for value in (0, 0o640, 0o7777):
            def check(work, op=op, value=value):
                selected = work / ("mode-file" if op == 3 else "left/mode-target")
                assert stat.S_IMODE(selected.stat().st_mode) == value
            suite.run(f"mode-{op}-{value}", op, first=b"mode-target", mode=value, check=check)
    def followed(work):
        assert_mode(work / "left/mode-target", 0o604)
        assert stat.S_ISLNK((work / "left/mode-sym").lstat().st_mode)
    suite.run("mode-symlink-follows", 4, first=b"mode-sym", mode=0o604, check=followed)
    suite.run("mode-path-cwd", 4, cwd=True, first=b"left/mode-target", mode=0o600,
              check=lambda w: assert_mode(w / "left/mode-target", 0o600))
    suite.run("mode-fd-closed", 3, descriptors=64, code=9, native=0)
    suite.run("mode-path-bad-fd", 4, first=b"mode-target", descriptors=1, code=9)
    suite.run("mode-path-missing", 4, first=b"absent", code=2)
    suite.run("mode-path-absolute", 4, descriptors=1, first=lambda w: os.fsencode(w / "left/mode-target"),
              check=lambda w: assert_mode(w / "left/mode-target", 0o640))


def assert_mode(path, wanted):
    assert stat.S_IMODE(path.stat().st_mode) == wanted


def bounds(suite):
    for op in (0, 1, 2, 4):
        first = b"sym" if op == 2 else b"mode-target" if op == 4 else b"source"
        for view in (1, 2, 3):
            suite.run(f"first-view-{op}-{view}", op, first=first, first_view=view, code=200, native=0)
        suite.run(f"nul-first-{op}", op, first=b"a\0b", code=200, native=0)
        suite.run(f"long-first-{op}", op, first=b"x" * 4096, code=36, native=0)
        if op == 1:
            suite.run("max-symlink-target-native", op, first=b"x" * 4095, check=symlinked(b"x" * 4095))
        else:
            suite.run(f"max-first-native-{op}", op, first=b"x" * 4095, code=36)
    for op in (0, 1):
        for view in (1, 2, 3):
            suite.run(f"second-view-{op}-{view}", op, second_view=view, code=200, native=0)
        suite.run(f"nul-second-{op}", op, second=b"a\0b", code=200, native=0)
        suite.run(f"long-second-{op}", op, second=b"x" * 4096, code=36, native=0)
        suite.run(f"first-before-second-{op}", op, first=b"x" * 4096, second=b"a\0b", code=36, native=0)
    for view in (1, 2, 3):
        suite.run(f"destination-first-{view}", 2, first=b"x" * 4096, destview=view, code=200, native=0)
    for op in (3, 4):
        for mode in (4096, 0xffffffff, 0o100644):
            suite.run(f"mode-invalid-{op}-{mode}", op, first=b"x" * 4096, mode=mode, code=200, native=0,
                      descriptors=64 if op == 3 else 0)


def faults(suite):
    for op in range(5):
        first = b"link" if op == 2 else b"mode-target" if op == 4 else b"source"
        target = b"abcd"
        setup = (lambda w: os.symlink(target, w / "left/link")) if op == 2 else None
        baseline = suite.run(f"baseline-{op}", op, first=first, setup=setup, target=target)
        for error, code in (("EIO", 5), ("EINTR", 4), ("EAGAIN", 11), ("ENOSYS", 38)):
            suite.run(f"errno-{op}-{error}", op, first=first, setup=setup, target=target, code=code,
                      injection=dict(error=error, when=baseline["ordinal"]), baseline=baseline)
        invalid = 18 if op == 2 else 1
        suite.run(f"invalid-result-{op}", op, first=first, setup=setup, target=target, code=201,
                  injection=dict(retval=invalid, when=baseline["ordinal"]), baseline=baseline)
    setup = lambda w: os.symlink(b"abcd", w / "left/link")
    suite.run("read-zero-return", 2, first=b"link", setup=setup, target=b"abcd", synthetic=b"",
              injection=dict(retval=0, when=1))
    for layout, injection, code in ((1, dict(error="EIO", when=1), 5), (2, dict(retval=18, when=1), 201)):
        suite.run(f"read-atomic-layout-{layout}", 2, first=b"link", setup=setup, target=b"abcd", layout=layout,
                  injection=injection, code=code)
    payload = b"\x7f" * 16
    setup = lambda w: os.symlink(b"z" * 4095, w / "left/link")
    baseline = suite.run("read-full-probe-baseline", 2, first=b"link", destlen=4096, setup=setup, target=b"z" * 4095)
    suite.run("read-full-probe-incomplete", 2, first=b"link", destlen=4096, setup=setup, target=b"z" * 4095,
              synthetic_count=4096, known_prefix=payload,
              injection=dict(retval=4096, poke=payload, when=baseline["ordinal"]), baseline=baseline)


def controls():
    count = SOURCE.controls()
    assert len(SYSCALL6) == 32 and SYSCALL6[29:31] == b"\x0f\x05"
    count += 1
    for value, wanted in (("0640", 0o640), ("S_ISUID|S_ISGID|S_ISVTX|0777", 0o7777), ("0", 0)):
        assert mode_value(value) == wanted
        count += 1
    def line(name, args, result="0"): return f"[000000000040101f] {name}({args}) = {result}\n"
    def marker(token): return line("write", '2, "\\x%02x", 1' % ord(token), "1")
    body = line("linkat", '3, "\\x61", 4, "\\x62", 0')
    words = [0] * 20; words[6:8] = (3, 4)
    valid = marker("C") + body + marker("c")
    assert primitive(events(valid), 0, b"a", b"b", False, False, words, 2, 0, 1)
    count += 1
    for bad in (valid.replace('linkat(3,', 'linkat(5,'), valid.replace('\\x61', '\\x63'),
                valid.replace(', 0)', ', AT_SYMLINK_FOLLOW)'), valid + body):
        try: primitive(events(bad), 0, b"a", b"b", False, False, words, 2, 0, 1)
        except AssertionError: count += 1
        else: raise AssertionError("filesystem oracle accepted altered primitive arguments")
    class Pairs(list):
        pass
    pairs = Pairs()
    pairs.executable_ranges = [(0x400000, 0x402000)]
    authority = ((pairs, []), {0x40101f})
    assert analyze(valid, authority, HERE)["events"]
    count += 1
    for bad in (valid.replace('[000000000040101f] linkat', '[0000000000401020] linkat'),
                valid.replace('[000000000040101f] linkat', '[000000000050101f] linkat')):
        try: analyze(bad, authority, HERE)
        except AssertionError: count += 1
        else: raise AssertionError("filesystem oracle accepted an unverified syscall IP")
    original = bytes([165] * 8)
    good = original[:3] + b"ab" + original[5:]
    words = tuple([0] * 9 + [2, 0] + [0] * 9)
    destination(good, original, 2, 0, 2, b"abc", words)
    count += 1
    for actual, status in ((b"x" + good[1:], 0), (good[:-1] + b"x", 0), (good, 201)):
        values = words if status == 0 else tuple([0] * 20)
        try: destination(actual, original, 2, status, 2, b"abc", values)
        except AssertionError: count += 1
        else: raise AssertionError("filesystem oracle accepted changed guards or error-path output")
    initial = bytes([165] * 4104)
    prefix_bytes = b"\x7f" * 16
    supplied = bytearray(initial)
    supplied[3:4099] = b"x" * 4096
    supplied[3:19] = prefix_bytes
    values = tuple([0] * 9 + [4096, 0] + [0] * 9)
    destination(supplied, initial, 2, 0, 4096, None, values, synthetic_count=4096, known_prefix=prefix_bytes)
    count += 1
    supplied[100] = 0  # Unprovided interior is intentionally unconstrained.
    destination(supplied, initial, 2, 0, 4096, None, values, synthetic_count=4096, known_prefix=prefix_bytes)
    count += 1
    for index in (2, 3, 4099):
        altered = bytearray(supplied)
        altered[index] ^= 1
        try: destination(altered, initial, 2, 0, 4096, None, values, synthetic_count=4096, known_prefix=prefix_bytes)
        except AssertionError: count += 1
        else: raise AssertionError("synthetic readlink accepted an altered guard or supplied byte")
    for index, value in ((9, 4095), (10, 1)):
        altered = list(values)
        altered[index] = value
        try: destination(supplied, initial, 2, 0, 4096, None, tuple(altered), synthetic_count=4096, known_prefix=prefix_bytes)
        except AssertionError: count += 1
        else: raise AssertionError("synthetic readlink accepted an incorrect count/completeness")
    print(f"PASS filesystem-links CPU controls={count} native-cases=0")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
    else:
        assert len(sys.argv) == 3 and sys.argv[1] in ("links", "readlink", "permissions", "bounds", "faults")
        group, executable = sys.argv[1:]
        suite = Suite(group, executable)
        globals()[group](suite)
        print(f"PASS filesystem-links group={group} cases={suite.count}")
