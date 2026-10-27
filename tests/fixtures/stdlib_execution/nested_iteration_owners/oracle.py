"""Finite native ownership evidence for the actual nested iterator adapters.

The source allocator verifier and full-width live map ledger are reused, without
changing their authority. The model below describes callback order and owners;
it does not implement flatten/flat_map or reproduce their state machines.
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


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


HERE = Path(__file__).resolve().parent
SOURCE = load("nested_iteration_live_source", HERE.parents[1] / "extended/archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
CALLS = {"mmap", "munmap", "read", "write", "getpid"}
# Observe the established filesystem/resource syscall set too, then reject any
# such work. Restricting strace to the five permitted calls would hide a
# transient open/close effect that happened between live descriptor checkpoints.
TRACE = ",".join(sorted(TRUSTED.CALLS | {"open"}))
MAGIC, WORDS = 1313420337, 24
FIELDS = ("magic", "pid", "phase", "code", "backend", "flavor", "profile",
          "outer", "inner", "retire", "maps", "received", "held", "error_bytes",
          "reserved", "active", "remaining", "recovered_steps", "scratch_freed",
          "backing_freed", "errors_made", "errors_freed", "error_kind", "ready")
PAIRS = {"C": "c", "T": "t", "K": "k", "M": "m", "R": "r"}
SINGLES = set("OIDHE")


def profile(executable, directory):
    value = TRUSTED.verified_sites(executable, directory)
    assert value[0] and not value[1] and value[0].executable_ranges, "expected verified raw source ELF"
    return value


def events(text):
    assert not text or text.endswith("\n"), "partial native trace"
    counts, found, scopes, stack, markers = Counter(), [], [], [], bytearray()
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unsupported native event", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        item = dict(ip=int(ip, 16), name=name, args=args, result=result,
                    ordinal=counts[name], index=index, line=line,
                    phase=stack[0]["name"] if stack else None,
                    role=stack[-1]["name"] if stack and stack[-1]["name"] in "MR" else None)
        if name in ("read", "write"):
            descriptor = TRUSTED.arguments(args)[0]
            assert descriptor == "0" if name == "read" else descriptor in ("1", "2"), ("unexpected I/O descriptor", item)
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in set(PAIRS) | set(PAIRS.values()) | SINGLES, ("unknown callback marker", item)
            item["marker"] = token
            markers.extend(token.encode())
            if token in PAIRS:
                if token in "CTK":
                    assert not stack, ("overlapping outer phase", item)
                else:
                    assert len(stack) == 1 and stack[0]["name"] in "TK", ("callback outside traversal/recovery", item)
                scope = dict(name=token, start=index, events=[])
                scopes.append(scope)
                stack.append(scope)
            elif token in PAIRS.values():
                assert stack and PAIRS[stack[-1]["name"]] == token, ("unmatched phase end", item)
                stack[-1]["end"] = index
                stack.pop()
            else:
                if token in "OI":
                    assert len(stack) == 1 and stack[0]["name"] in "TK", ("source poll outside adapter phase", item)
                if stack and stack[0]["name"] == "C":
                    raise AssertionError(("constructor caused callback", item))
        else:
            for scope in stack:
                scope["events"].append(item)
            if stack and stack[0]["name"] == "C":
                raise AssertionError(("constructor performed native work", item))
            if name == "mmap" and stack:
                assert item["phase"] in "TK" and item["role"] in ("M", "R"), ("adapter allocated outside callback", item)
        found.append(item)
    assert not stack, "unfinished callback phase"
    return dict(events=found, scopes=scopes, markers=bytes(markers))


def analyze(text, authority, directory, final=False):
    parsed = events(text)
    ranges = authority[0].executable_ranges
    assert all(any(low <= item["ip"] < high for low, high in ranges) for item in parsed["events"]), "syscall outside verified image"
    memory = "".join(item["line"] + "\n" for item in parsed["events"] if item["name"] in ("mmap", "munmap"))
    parsed["source"] = SOURCE.source(memory, authority)
    if final:
        assert not parsed["source"]["live"], ("owner remains before exit", parsed["source"]["live"])
        TRUSTED.source_maps(memory, authority, directory)
    return parsed


def source_order(flavor, mode):
    """Independent row schedule: empty, three owned values, three owned values."""
    result = []
    for row, size in enumerate((0, 3, 3)):
        result.append("O")
        if flavor:
            result.extend("Mm")
        if mode == 3 and row == 1:
            return "".join(result)
        for _ in range(size):
            result.append("I")
            if mode == 2 and row == 1:
                return "".join(result)
        result.extend("IRr")
        if mode == 1 and row == 1:
            return "".join(result)
    result.append("O")
    return "".join(result)


def traversal(parsed):
    scopes = [scope for scope in parsed["scopes"] if scope["name"] == "T"]
    assert len(scopes) == 1, scopes
    scope = scopes[0]
    return "".join(item.get("marker", "") for item in parsed["events"][scope["start"] + 1:scope["end"]]
                   if item.get("marker") in set("OIMmRr"))


def causal_empty_retirement(parsed):
    retire = [scope for scope in parsed["scopes"] if scope["name"] == "R"]
    assert retire, "empty inner was not retired"
    empty = retire[0]
    frees = [item for item in empty["events"] if item["name"] == "munmap"]
    assert len(frees) == 2 and not any(item["name"] == "mmap" for item in empty["events"]), empty
    later = [item for item in parsed["events"] if item.get("marker") == "O" and item["index"] > empty["start"]]
    assert later and empty["end"] < later[0]["index"], (empty, later)


def frame(raw):
    values = struct.unpack("<24Q", raw)
    return dict(zip(FIELDS, values))


def check_frame(item, phase, backend, flavor, mode, *, injected):
    assert item["magic"] == MAGIC and item["phase"] == phase
    assert (item["backend"], item["flavor"], item["profile"]) == (backend, flavor, mode)
    assert item["reserved"] == 0 and item["ready"] in (0, 1) and item["active"] in (0, 1)
    assert item["code"] in (0, 4) and item["error_kind"] in (0, 1, 2, 3)
    assert item["held"] in (0, 8) and item["error_bytes"] in (0, 5)
    assert item["errors_freed"] <= item["errors_made"] <= 1 and item["received"] <= 6
    if not item["ready"]:
        assert injected and item["code"] == 4 and item["error_kind"] in (0, 3)
        assert all(item[key] == 0 for key in ("outer", "inner", "retire", "maps", "received", "held", "error_bytes", "active", "remaining"))
    if phase == 0 and item["ready"]:
        assert item["code"] == 0 and item["remaining"] == 3
        assert all(item[key] == 0 for key in ("outer", "inner", "retire", "maps", "received", "active", "held", "error_bytes"))
    if phase >= 2:
        assert item["active"] == item["remaining"] == 0
    if phase == 3:
        assert item["held"] == item["error_bytes"] == item["error_kind"] == 0
        assert item["errors_made"] == item["errors_freed"]
    if injected or phase != 1:
        return
    expected = {
        0: (4, 9, 3, 6, 0, 0, 0, 0),
        1: (2, 5, 2, 3, 1, 1, 1, 5),
        2: (2, 2, 1, 1, 1, 1, 0, 0),
        3: (2, 1, 1, 0, 0, 1, 2, 5),
    }[mode]
    keys = ("outer", "inner", "retire", "received", "active", "remaining", "error_kind", "error_bytes")
    assert tuple(item[key] for key in keys) == expected, (item, expected)
    assert item["maps"] == (min(item["outer"], 3) if flavor else 0)
    assert item["held"] == (8 if mode != 3 else 0)


def check_inner_cleanup(item, flavor, mode):
    # Flatten's outer owns all three inners before traversal. Flat-map owns
    # only rows: a failure on row 1 leaves row 2 unconstructed. Mapping failure
    # does not publish its partial candidate as an inner. Healthy early resume
    # eventually constructs the third inner.
    constructed = [0, 1, 2]
    if flavor and mode == 1:
        constructed = constructed[:2]
    if flavor and mode == 3:
        constructed = constructed[:1]
    assert (item["scratch_freed"], item["backing_freed"]) == (len(constructed), len(constructed)), item


def bind(before, after, point):
    left = [item for item in before["events"] if item["name"] == "mmap"]
    right = [item for item in after["events"] if item["name"] == "mmap"]
    assert 1 <= point <= len(left) and len(right) == point, (point, len(left), len(right))
    def key(item):
        return item["ip"], item["ordinal"], item["args"], item["phase"], item["role"]
    assert [key(item) for item in left[:point]] == [key(item) for item in right], "fault diverged before reached source allocation"
    marked = [item for item in after["events"] if "INJECTED" in item["result"]]
    assert marked == [right[-1]] and right[-1]["result"].startswith("-1 ENOMEM "), marked


def read_exact(stream, count, deadline):
    output = bytearray()
    while len(output) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], "native owner checkpoint deadline"
        part = os.read(stream.fileno(), count - len(output))
        assert part, ("checkpoint EOF", len(output), count)
        output.extend(part)
    return bytes(output)


def prefix(trace, output, deadline):
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), output)
        except (SOURCE.CheckpointPending, FileNotFoundError):
            assert time.monotonic() < deadline, "trace checkpoint flush deadline"
            time.sleep(0.002)


class Suite:
    def __init__(self, group, executable):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="nested-owners-" + group + "-"))
        self.authority = profile(self.executable, self.directory)
        self.deadline, self.count, self.denials = time.monotonic() + 75, 0, 0
        print(f"evidence={self.directory}", flush=True)

    def run(self, backend, flavor, mode, point=None, baseline=None):
        assert time.monotonic() < self.deadline, "split finite owner group before increasing runtime"
        label = f"{self.count:03d}-b{backend}-f{flavor}-p{mode}" + (f"-oom{point}" if point else "-baseline")
        directory = self.directory / label
        directory.mkdir()
        request = struct.pack("<3I", backend, flavor, mode)
        (directory / "request.bin").write_bytes(request)
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
                   "-e", "trace=" + TRACE, "-o", str(trace)]
        if point:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={point}"]
        command.append(str(self.executable))
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        deadline, emitted, checkpoints = min(self.deadline, time.monotonic() + 8), bytearray(), []
        snapshots, admitted = [], set()
        try:
            assert os.write(process.stdin.fileno(), request) == len(request)
            for phase in range(4):
                raw = read_exact(process.stdout, WORDS * 8, deadline)
                emitted.extend(raw)
                values = frame(raw)
                check_frame(values, phase, backend, flavor, mode, injected=point is not None)
                checkpoints.append(values)
                pid = values["pid"]
                assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(pid)]
                parsed = analyze(prefix(trace, bytes(emitted), deadline), self.authority, directory, final=phase == 3)
                live = parsed["source"]["live"]
                maps = SOURCE.process_owners(pid, live)
                admitted.update(live)
                if not values["ready"]:
                    assert not live, ("setup OOM leaked partial owner", live)
                if phase == 2:
                    wanted = [size for size in (values["held"], values["error_bytes"]) if size]
                    assert sorted(live.values()) == sorted(wanted), ("non-output/error owner survives deep cleanup", live, values)
                if phase == 3:
                    assert not live
                    assert all(not any(low <= pointer < high for low, high in maps) for pointer in admitted), "released source mapping remains live"
                snapshots.append(parsed)
                assert os.write(process.stdin.fileno(), b"A") == 1
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            final = analyze(trace.read_text(), self.authority, directory, final=True)
            assert not rest and stderr == final["markers"], (rest, stderr, final["markers"])
            assert process.returncode == (4 if point else 0), (process.returncode, checkpoints, stderr)
            assert len(final["events"]) == len(snapshots[-1]["events"]) + 1 and final["events"][-1]["name"] == "read"
            assert checkpoints[-1]["code"] == (4 if point else 0)
            if point:
                assert baseline is not None
                bind(baseline, final, point)
                self.denials += 1
            else:
                assert traversal(final) == source_order(flavor, mode), (traversal(final), source_order(flavor, mode))
                causal_empty_retirement(final)
                assert [scope["name"] for scope in final["scopes"]].count("C") == 1
                assert checkpoints[2]["received"] == (3 if mode == 1 else 0 if mode == 3 else 6)
                assert checkpoints[2]["recovered_steps"] == int(mode == 1)
                check_inner_cleanup(checkpoints[2], flavor, mode)
                if mode == 1:
                    assert checkpoints[1]["scratch_freed"] == 2 and checkpoints[1]["backing_freed"] == 1
            (directory / "stdout.bin").write_bytes(emitted)
            (directory / "stderr.bin").write_bytes(stderr)
            self.count += 1
            return final
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(emitted)
            if process.poll() is None:
                process.kill()
            out, err = process.communicate(timeout=3)
            (directory / "remaining-stdout.bin").write_bytes(out)
            (directory / "stderr.bin").write_bytes(err)
            raise


def native(group, executable):
    suite = Suite(group, executable)
    if group == "lifecycle":
        for backend in (0, 1):
            for flavor in (0, 1):
                for mode in range(4 if flavor else 3):
                    suite.run(backend, flavor, mode)
        assert suite.count == 14
    else:
        assert group in ("flatten-oom", "flatmap-oom-vec", "flatmap-oom-deque")
        flavor = int(group != "flatten-oom")
        backends = (0, 1) if not flavor else (int(group.endswith("deque")),)
        for backend in backends:
            for mode in ((0, 1, 2, 3) if flavor else (1,)):
                baseline = suite.run(backend, flavor, mode)
                attempts = baseline["source"]["attempts"]
                assert attempts and all(item["result"].startswith("0x") for item in attempts)
                roles = {(item["phase"], item["role"]) for item in baseline["events"] if item["name"] == "mmap"}
                if mode == 1:
                    assert ("T", "R") in roles
                if flavor:
                    assert ("T", "M") in roles
                    if mode == 2:
                        assert ("K", "M") in roles, "early resume did not construct the remaining owned inner"
                else:
                    assert roles == {(None, None), ("T", "R")}
                for point in range(1, len(attempts) + 1):
                    suite.run(backend, flavor, mode, point, baseline)
    print(f"PASS nested-owners group={group} cases={suite.count} reached-oom={suite.denials}")


def controls():
    count = SOURCE.controls()
    def line(body, ip=0x401002):
        return f"[{ip:016x}] {body}\n"
    def marker(token):
        return line(f'write(2, "\\x{ord(token):02x}", 1) = 1')
    allocate = line("mmap(NULL, 8, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000")
    valid = marker("C") + marker("c") + marker("T") + marker("O") + marker("M") + allocate + marker("m") + marker("t")
    parsed = events(valid)
    assert parsed["markers"] == b"CcTOMmt" and parsed["events"][5]["role"] == "M"
    count += 1
    for bad in (marker("C") + allocate + marker("c"), marker("C") + marker("O") + marker("c"),
                marker("T") + allocate + marker("t"), marker("M") + marker("m"), marker("T") + marker("r"),
                marker("T"), marker("Z"), valid + line("openat(AT_FDCWD, NULL, 0) = -1 EFAULT (Bad address)")):
        try:
            events(bad)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("phase ledger accepted mutated callback/effect")
    before = events(valid)
    after = events(valid.replace(" = 0x7fff10000000", " = -1 ENOMEM (Cannot allocate memory) (INJECTED)"))
    bind(before, after, 1)
    count += 1
    for changed in (valid.replace(", 8,", ", 9,"), valid.replace("0000000000401002", "0000000000401003"),
                    valid.replace('\\x4d', '\\x52').replace('\\x6d', '\\x72')):
        bad = events(changed.replace(" = 0x7fff10000000", " = -1 ENOMEM (Cannot allocate memory) (INJECTED)"))
        try:
            bind(before, bad, 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("fault ledger accepted changed site/size/callback")
    for flavor in (0, 1):
        for mode in range(4 if flavor else 3):
            assert source_order(flavor, mode).count("O") == (4 if mode == 0 else 2)
            count += 1
    for flavor, owners in ((0, 3), (1, 2)):
        check_inner_cleanup(dict(scratch_freed=owners, backing_freed=owners), flavor, 1)
        count += 1
        try:
            check_inner_cleanup(dict(scratch_freed=5-owners, backing_freed=5-owners), flavor, 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("cleanup model conflated preconstructed and lazy inner owners")
    print(f"PASS nested-owners CPU controls={count}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        assert len(sys.argv) == 3
        native(sys.argv[1], sys.argv[2])
