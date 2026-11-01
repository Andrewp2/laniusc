"""Host flock interoperability around the independent real-file patch oracle."""
import fcntl
import importlib.util
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

BASE_PATH = Path(__file__).resolve().parent.parent / "file_patch" / "oracle.py"
specification = importlib.util.spec_from_file_location("file_patch_test_oracle", BASE_PATH)
base = importlib.util.module_from_spec(specification)
specification.loader.exec_module(base)
from protection import verify_protection

DIAGNOSTICS = {**base.DIAGNOSTICS, "lock": b"file_patch: lock failed\n", "unlock": b"file_patch: unlock failed\n"}
COUNTS = {"model": 15, "bounds": 15, "faults": 15, "protection": 4}


def events(text):
    lines = text.splitlines()
    ordinary, allocations = base.events("\n".join(line for line in lines if not line.startswith("flock(")))
    iterator = iter(ordinary)
    found, ordinal = [], 0
    for line in lines:
        if line.startswith("flock("):
            match = re.fullmatch(r"flock\((.*)\)\s+=\s+(.*)", line)
            assert match, line
            ordinal += 1
            found.append(dict(name="flock", args=match[1], answer=match[2], ordinal=ordinal, line=line))
        else:
            found.append(next(iterator))
    return found, allocations


def locking_trace(found, *, preflight=False, locked=True):
    locks = [event for event in found if event["name"] == "flock"]
    opens = [event for event in found if event["name"] == "openat"]
    operations = [event for event in found if event["name"] in ("pread64", "pwrite64")]
    if preflight or not opens or opens[0]["answer"].startswith("-1 ") or not locked:
        assert not locks, locks
        return
    descriptor = int(opens[0]["answer"].split()[0])
    close = next(event for event in found if event["name"] == "close")
    assert locks and int(locks[0]["args"].split(",")[0]) == descriptor
    acquire = locks[0]
    assert "LOCK_EX" in acquire["args"] and "LOCK_NB" in acquire["args"], acquire
    assert found.index(opens[0]) < found.index(acquire) < found.index(close)
    if acquire["answer"] != "0":
        assert len(locks) == 1 and not operations, (locks, operations)
    else:
        assert len(locks) == 2 and "LOCK_UN" in locks[1]["args"], locks
        release = locks[1]
        assert int(release["args"].split(",")[0]) == descriptor
        assert found.index(acquire) < found.index(release) < found.index(close)
        assert all(found.index(acquire) < found.index(event) < found.index(release) for event in operations)
    # Phase and cleanup diagnostics occur only after both cleanup attempts.
    diagnostics = [event for event in found if event["name"] == "write" and event["args"].startswith("2,")]
    assert all(found.index(event) > found.index(close) for event in diagnostics)


class Runner(base.Runner):
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"locked-file-patch-{mode}-"))
        self.count = 0
        self.holder_mode = None

    def run(self, name, arguments, *, status=0, diagnostic=None, output=b"", injection=None,
            preflight=False, position=0, length=1, expect_written=None, closed_stdout=False,
            prepend=True, locked=True):
        assert not closed_stdout, "covered by existing unlocked app oracle"
        if prepend:
            arguments = ["--lock", *arguments]
        prefix = self.directory / name
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-s", "32", "-e", "signal=none",
                   "-e", "trace=" + base.TRACE, "-o", str(prefix.with_suffix(".trace"))]
        injections = [] if injection is None else (list(injection) if isinstance(injection[0], tuple) else [injection])
        for call, ordinal, failure in injections:
            command += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
        command += [self.executable, *arguments]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        holder = None
        try:
            if self.holder_mode is not None:
                holder = os.open(arguments[1], os.O_RDWR)
                fcntl.flock(holder, self.holder_mode | fcntl.LOCK_NB)
            result = subprocess.run(command, cwd=self.directory, stdin=subprocess.DEVNULL, capture_output=True, timeout=15, check=False)
        finally:
            if holder is not None:
                fcntl.flock(holder, fcntl.LOCK_UN)
                os.close(holder)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, result.stderr)
        phases = () if diagnostic is None else ((diagnostic,) if isinstance(diagnostic, str) else diagnostic)
        wanted = b"".join(DIAGNOSTICS[phase] for phase in phases)
        assert result.stderr == wanted, (name, result.stderr, wanted)
        found, allocations = events(prefix.with_suffix(".trace").read_text())
        marked = [event for event in found if "INJECTED" in event["answer"]]
        selected = []
        for call, ordinal, failure in injections:
            matching = [event for event in found if event["name"] == call and event["ordinal"] == ordinal]
            assert len(matching) == 1 and matching[0]["answer"].startswith("-1 " + failure + " "), matching
            selected += matching
        assert {event["line"] for event in marked} == {event["line"] for event in selected}, (marked, selected)
        ordinary = [event for event in found if event["name"] != "flock"]
        read, written = base.positional_trace(ordinary, position, length, preflight=preflight)
        locking_trace(found, preflight=preflight, locked=locked)
        if not preflight and not injections:
            assert allocations == 2, allocations
        if expect_written is not None:
            assert written == expect_written, (name, written, expect_written)
        self.count += 1
        return found

    def held_patch(self, name, original, position, expected, value, mode):
        self.holder_mode = mode
        try:
            self.patch(name, original, position, expected, value, status=6, diagnostic="lock")
        finally:
            self.holder_mode = None


def model(r):
    r.patch("single-byte", b"aTAIL", 0, b"a", b"Z")
    r.patch("middle-range", b"prefixOLDsuffix", 6, b"OLD", b"NEW")
    for length in (1025, 4096):
        old = base.pattern(length)
        r.patch(f"staged-{length}", b"L" * 17 + old + b"R" * 19, 17, old, bytes(byte ^ 255 for byte in old))
    r.patch("uppercase-hex", b"\xab\xcdtail", 0, b"\xab\xcd", b"\xff\xee", mixed_hex=True)
    r.patch("leading-zero-position", b"aBCtail", 1, b"BC", b"xy", offset_text="0001")
    old = base.pattern(1025)
    r.patch("sparse-position", old, (1 << 32) + 37, old, bytes(byte ^ 255 for byte in old), sparse=True)
    r.patch("same-value", b"prefixDATAtrail", 6, b"DATA", b"DATA")
    r.patch("mismatch-still-unlocks", b"abcdef", 1, b"xxx", b"new", status=1, diagnostic="mismatch")
    r.patch("eof-still-unlocks", b"abc", 1, b"xxxx", b"new!", status=3, diagnostic="read")
    literal = r.directory / "--lock"
    literal.write_bytes(b"abc")
    r.run("four-operands-literal-lock-path", ["--lock", "0", "61", "7a"], prepend=False, locked=False, expect_written=1)
    assert literal.read_bytes() == b"zbc"
    rng = random.Random(0x10CC9)
    for index in range(4):
        old = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 500)))
        value = bytes(rng.randrange(256) for _ in old)
        r.patch(f"seeded-{index}", b"L" * 17 + old + b"R" * 19, 17, old, value)


def bounds(r):
    target = str(r.directory / "unchanged.bin")
    Path(target).write_bytes(b"\x00unchanged")
    cases = [
        ["--lock"], ["--lock", target], ["--lock", target, "0", "00"],
        ["--lock", target, "0", "00", "ff", "extra"],
        ["--LOCK", target, "0", "00", "ff"], [target, "0", "00", "ff", "--lock"],
        ["-l", target, "0", "00", "ff"], ["--lock", "--lock", target, "0", "00", "ff"],
        ["--lock", target, "0", "", ""], ["--lock", target, "0", "00", "ffff"],
        ["--lock", target, "0", "0", "f"], ["--lock", target, "0", "zz", "ff"],
        ["--lock", target, str(base.MAX_POSITION), "00", "ff"],
        ["--lock", "", "0", "00", "ff"], ["--lock", "x" * 4096, "0", "00", "ff"],
    ]
    for index, arguments in enumerate(cases):
        r.run(f"invalid-{index}", arguments, prepend=False, preflight=True, status=2, diagnostic="arguments")
    assert Path(target).read_bytes() == b"\x00unchanged"


def faults(r):
    old = base.pattern(2049)
    original, value = b"L" * 17 + old + b"R" * 19, bytes(byte ^ 255 for byte in old)
    for failure in ("EINTR", "EAGAIN", "ENOLCK"):
        r.patch(f"acquire-{failure}", original, 17, old, value, status=6, diagnostic="lock", injection=("flock", 1, failure))
    for failure in ("EINTR", "EIO"):
        r.patch(f"unlock-{failure}", original, 17, old, value, status=6, diagnostic="unlock", expect_written=len(value), injection=("flock", 2, failure))
    r.patch("mismatch-unlock-error", original, 17, b"x" * len(old), value, status=1, diagnostic=("mismatch", "unlock"), injection=("flock", 2, "EIO"))
    r.patch("mismatch-both-cleanup-errors", original, 17, b"x" * len(old), value, status=1, diagnostic=("mismatch", "unlock", "close"), injection=(("flock", 2, "EIO"), ("close", 1, "EIO")))
    r.patch("write-and-both-cleanup-errors", original, 17, old, value, status=3, diagnostic=("write", "unlock", "close"), expect_written=1024,
            injection=(("pwrite64", 2, "EIO"), ("flock", 2, "EIO"), ("close", 1, "EIO")))
    r.patch("close-after-explicit-unlock", original, 17, old, value, status=3, diagnostic="close", expect_written=len(value), injection=("close", 1, "EIO"))
    r.patch("open-error-no-lock", original, 17, old, value, status=3, diagnostic="open", injection=("openat", 1, "EACCES"))
    r.patch("read-error-still-unlocks", original, 17, old, value, status=3, diagnostic="read", injection=("pread64", 2, "EIO"))
    for call in ("pread64", "pwrite64"):
        r.patch(f"retry-{call}-while-held", original, 17, old, value, injection=(call, 1, "EINTR"))
    for ordinal in (1, 2):
        r.patch(f"argument-oom-{ordinal}", original, 17, old, value, status=4, diagnostic="allocation", injection=("mmap", ordinal, "ENOMEM"))


def protection(r):
    old = base.pattern(1025)
    for name, mode in (("shared", fcntl.LOCK_SH), ("exclusive", fcntl.LOCK_EX)):
        r.held_patch("host-held-" + name, b"L" * 17 + old + b"R" * 19, 17, old, bytes(byte ^ 255 for byte in old), mode)
    for length in (3, 4096):
        old = base.pattern(length)
        original = b"L" * 17 + old + b"R" * 19
        verify_protection(r.executable, r.directory / f"barrier-{length}.bin", 17, original,
                          bytes(byte ^ 255 for byte in old), r.directory / f"barrier-{length}")
        r.count += 1


def controls():
    assert len(base.HELP) == 662 and len(DIAGNOSTICS["lock"]) == 24 and len(DIAGNOSTICS["unlock"]) == 26
    assert base.replacement(b"prefixOLDsuffix", 6, b"NEW") == b"prefixNEWsuffix"
    print(f"locked-file-patch CPU controls=2; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "bounds": bounds, "faults": faults, "protection": protection}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"locked-file-patch-{mode} cases={runner.count} evidence={runner.directory}")
