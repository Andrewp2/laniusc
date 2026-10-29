"""Independent real-file byte replacement and positional syscall observations."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MAX_POSITION = (1 << 63) - 1
HELP = (b"Usage: file_patch [--lock] PATH OFFSET EXPECTED_HEX REPLACEMENT_HEX\n"
        b"Replace bytes only after an exact positional comparison of the existing file.\n"
        b"The four-operand form is unlocked; --lock is only a leading fifth operand.\n"
        b"--lock makes one nonblocking exclusive advisory lock attempt for cooperating clients.\n"
        b"Status 6 reports lock/unlock failure; an unlock failure may follow changed file data.\n"
        b"OFFSET is ASCII decimal. Hex strings must have equal nonempty even lengths, up to 4096 bytes.\n"
        b"Open read/write without create, truncate or append; no atomicity or durability promise.\n"
        b"Limits: path 4095 bytes, 16 read attempts, 16 write attempts. --help or -h shows help.\n")
DIAGNOSTICS = {
    "arguments": b"file_patch: invalid arguments\n",
    "allocation": b"file_patch: allocation failed\n",
    "open": b"file_patch: open failed\n",
    "read": b"file_patch: positional read failed\n",
    "mismatch": b"file_patch: expected bytes did not match\n",
    "write": b"file_patch: positional write failed\n",
    "close": b"file_patch: close failed\n",
    "mismatch_close": b"file_patch: expected bytes did not match\nfile_patch: close failed\n",
    "output": b"file_patch: output failed\n",
}
COUNTS = {"model": 24, "preservation": 6, "cli": 35, "io": 17}
TRACE = "openat,close,fcntl,flock,pread64,pwrite64,lseek,read,write,mmap,munmap,mremap,brk,rt_sigaction"


def pattern(length):
    block = bytes((index * 73 + 19) % 256 for index in range(256))
    return (block * ((length + 255) // 256))[:length]


def replacement(original, position, value):
    assert 0 <= position <= len(original) and position + len(value) <= len(original)
    return original[:position] + value + original[position + len(value):]


def events(text):
    result, counts, live, allocations = [], Counter(), {}, 0
    for line in text.splitlines():
        match = re.fullmatch(r"(openat|close|fcntl|pread64|pwrite64|lseek|read|write|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        result.append(item)
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, line
                live[address] = size
                allocations += 1
            else:
                assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk", "lseek"):
            raise AssertionError(("unexpected allocation or cursor movement", line))
    assert not live, ("observed unreleased mappings", live)
    return result, allocations


def positional_trace(found, position, length, *, preflight=False, expected_maps=2):
    maps = [event for event in found if event["name"] == "mmap"]
    assert len(maps) <= expected_maps, ("unexpected payload allocation", maps)
    opens = [event for event in found if event["name"] == "openat"]
    if preflight:
        assert not opens and not any(event["name"] in ("pread64", "pwrite64", "fcntl", "close") for event in found)
        return 0, 0
    assert len(opens) == 1, opens
    opened = opens[0]
    assert "O_RDWR" in opened["args"] and not any(flag in opened["args"] for flag in ("O_CREAT", "O_TRUNC", "O_APPEND")), opened
    if opened["answer"].startswith("-1 "):
        assert not any(event["name"] in ("pread64", "pwrite64", "close") for event in found)
        return 0, 0
    descriptor = int(opened["answer"].split()[0])
    closes = [event for event in found if event["name"] == "close"]
    assert len(closes) == 1 and int(closes[0]["args"]) == descriptor, closes
    read, written, writing = 0, 0, False
    for event in found:
        name = event["name"]
        if name in ("read", "write"):
            assert int(event["args"].split(",")[0]) != descriptor, ("shared-cursor payload operation", event)
        if name not in ("pread64", "pwrite64"):
            continue
        arguments = event["args"].split(",")
        fd, count, offset = int(arguments[0]), int(arguments[-2]), int(arguments[-1])
        assert fd == descriptor and 0 < count <= 1024, event
        if name == "pread64":
            assert not writing and offset == position + read and count == min(1024, length - read), event
        else:
            assert read == length, ("write before complete read", event, read, length)
            writing = True
            assert offset == position + written and count == min(1024, length - written), event
        if event["answer"].split()[0].isdigit():
            accepted = int(event["answer"].split()[0])
            assert 0 <= accepted <= count, event
            if name == "pread64":
                read += accepted
            else:
                written += accepted
    assert found.index(closes[0]) > max([found.index(event) for event in found if event["name"] in ("pread64", "pwrite64")] or [found.index(opened)])
    return read, written


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"file-patch-{mode}-"))
        self.count = 0

    def run(self, name, arguments, *, status=0, diagnostic=None, output=b"", injection=None,
            preflight=False, position=0, length=1, expect_written=None, closed_stdout=False):
        prefix = self.directory / name
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-s", "32", "-e", "signal=none",
                   "-e", "trace=" + TRACE, "-o", str(prefix.with_suffix(".trace"))]
        if injection:
            call, ordinal, failure = injection
            command += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
        command += [self.executable, *arguments]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        if closed_stdout:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                result = subprocess.run(command, stdin=subprocess.DEVNULL, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=15, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, result.stderr)
        wanted = DIAGNOSTICS[diagnostic] if diagnostic is not None else b""
        assert result.stderr == wanted, (name, result.stderr, wanted)
        found, allocations = events(prefix.with_suffix(".trace").read_text())
        marked = [event for event in found if "INJECTED" in event["answer"]]
        if injection:
            call, ordinal, failure = injection
            if isinstance(ordinal, str):
                selected = [event for event in found if event["name"] == call]
                assert len(selected) == 16 and marked == selected, (name, selected)
            else:
                selected = [event for event in found if event["name"] == call and event["ordinal"] == ordinal]
                assert len(selected) == 1 and marked == selected, (name, marked)
            assert all(event["answer"].startswith("-1 " + failure + " ") for event in selected)
        else:
            assert not marked, marked
        read, written = positional_trace(found, position, length, preflight=preflight)
        if len(arguments) == 4 and not injection and not preflight:
            assert allocations == 2, ("CLI snapshot is the only allocating owner", allocations)
        if expect_written is not None:
            assert written == expect_written, (name, written, expect_written)
        self.count += 1
        return found

    def patch(self, name, original, position, expected, value, *, status=0, diagnostic=None,
              injection=None, expect_written=None, path_name=None, offset_text=None, mixed_hex=False,
              sparse=False, symlink=False):
        path = self.directory / (name + ".bin")
        if path_name is not None:
            path = os.fsencode(self.directory) + b"/" + os.fsencode(path_name)
        if sparse:
            size = position + len(expected) + 7
            descriptor = os.open(path, os.O_CREAT | os.O_TRUNC | os.O_RDWR, 0o600)
            try:
                os.ftruncate(descriptor, size)
                os.pwrite(descriptor, b"HEAD", 0)
                os.pwrite(descriptor, b"LEFT", position - 4)
                if any(original):
                    os.pwrite(descriptor, original, position)
                os.pwrite(descriptor, b"RIGHT!!", position + len(expected))
            finally:
                os.close(descriptor)
            before = (b"HEAD", b"LEFT" + original + b"RIGHT!!")
        else:
            with open(path, "wb") as output:
                output.write(original)
            size = len(original)
            before = original
        operand = path
        if symlink:
            operand = self.directory / (name + ".link")
            os.symlink(path, operand)
        first, second = expected.hex(), value.hex()
        if mixed_hex:
            first, second = first.upper(), second.upper()
        arguments = [os.fspath(operand), offset_text or str(position), first, second]
        wanted_written = len(value) if status == 0 else (expect_written or 0)
        self.run(name, arguments, status=status, diagnostic=diagnostic, injection=injection,
                 position=position, length=len(expected), expect_written=wanted_written, preflight=(status == 4))
        changed = value[:wanted_written]
        if sparse:
            descriptor = os.open(path, os.O_RDONLY)
            try:
                assert os.pread(descriptor, 4, 0) == before[0]
                wanted = b"LEFT" + changed + original[len(changed):] + b"RIGHT!!"
                assert os.pread(descriptor, len(wanted), position - 4) == wanted
                assert os.pread(descriptor, 64, 4096) == b"\x00" * 64
                metadata = os.fstat(descriptor)
                assert metadata.st_size == size and metadata.st_blocks * 512 < 1 << 20
                (self.directory / (name + ".before-window")).write_bytes(before[1])
                (self.directory / (name + ".after-window")).write_bytes(wanted)
                (self.directory / (name + ".sparse")).write_text(f"position={position} length={len(expected)} size={size} blocks={metadata.st_blocks}\n")
            finally:
                os.close(descriptor)
        else:
            with open(path, "rb") as source:
                actual = source.read()
            wanted = replacement(before, position, changed) if changed else before
            assert actual == wanted and len(actual) == size, (name, actual[:64], wanted[:64])
            (self.directory / (name + ".before")).write_bytes(before)
            (self.directory / (name + ".after")).write_bytes(actual)
        if symlink:
            assert os.path.islink(operand)


def model(r):
    r.patch("one-byte-at-zero", b"aTAIL", 0, b"a", b"Z")
    r.patch("nonzero-middle", b"prefix-OLD-suffix", 7, b"OLD", b"NEW")
    r.patch("every-byte", b"L" * 17 + bytes(range(256)) + b"R" * 19, 17, bytes(range(256)), bytes(reversed(range(256))))
    for length in (1023, 1024, 1025, 4096):
        old = pattern(length)
        r.patch(f"staging-boundary-{length}", b"L" * 17 + old + b"R" * 19, 17, old, bytes(value ^ 255 for value in old))
    r.patch("identical-replacement", b"prefixDATAtrail", 6, b"DATA", b"DATA")
    r.patch("uppercase-hex", b"\xab\xcd\x00\xff", 0, b"\xab\xcd", b"\xff\xee", mixed_hex=True)
    r.patch("leading-zero-position", b"aBCtail", 1, b"BC", b"xy", offset_text="00001")
    r.patch("unicode-path", b"aBCtail", 1, b"BC", b"xy", path_name="patch-é.bin")
    r.patch("nonutf8-path", b"aBCtail", 1, b"BC", b"xy", path_name=b"patch-\xff.bin")
    r.patch("final-symlink-follows", b"aBCtail", 1, b"BC", b"xy", symlink=True)
    rng = random.Random(0xF11E9)
    for index in range(8):
        old = bytes(rng.randrange(256) for _ in range(rng.randrange(1, 400)))
        value = bytes(rng.randrange(256) for _ in old)
        position = rng.randrange(0, 100)
        r.patch(f"seeded-{index}", pattern(position) + old + pattern(37), position, old, value)
    for index, (position, length) in enumerate((((1 << 32) + 37, 1025), ((1 << 33) + 4097, 4096))):
        old = pattern(length)
        r.patch(f"sparse-high-position-{index}", old, position, old, bytes(value ^ 255 for value in old), sparse=True)
    r.patch("sparse-hole-read", b"\x00" * 1025, (1 << 32) + 8193, b"\x00" * 1025, pattern(1025), sparse=True)


def preservation(r):
    r.patch("first-byte-mismatch", b"abcdef", 1, b"Xcd", b"new", status=1, diagnostic="mismatch")
    old = pattern(1025)
    r.patch("last-byte-mismatch-after-staging", b"L" + old + b"R", 1, old[:-1] + bytes([old[-1] ^ 255]), b"x" * 1025, status=1, diagnostic="mismatch")
    r.patch("empty-file-eof", b"", 0, b"x", b"y", status=3, diagnostic="read")
    r.patch("position-at-eof", b"abc", 3, b"x", b"y", status=3, diagnostic="read")
    r.patch("partial-eof-after-staging", pattern(1536), 0, pattern(2048), b"x" * 2048, status=3, diagnostic="read")
    r.patch("largest-valid-position-host-read", b"abc", MAX_POSITION - 1, b"x", b"y", status=3, diagnostic="read")


def cli(r):
    invalid = [[], ["x"], ["x", "0"], ["x", "0", "00"], ["x", "0", "00", "ff", "extra"],
               ["--help", "extra"], ["--unknown"]]
    target_path = r.directory / "unchanged.bin"
    target_path.write_bytes(b"\x00original")
    target = str(target_path)
    for position in ("", "-1", "+1", "1.0", "1_0", " 1", "1 ", "18446744073709551616", str(MAX_POSITION + 1), str(MAX_POSITION)):
        invalid.append([target, position, "00", "ff"])
    for expected, value in (("", ""), ("0", "f"), ("00", "f"), ("zz", "ff"), ("00", "gg"),
                            ("0x00", "ffff"), ("00 ", "fff"), ("00", "ffff"), ("0000", "ff"), ("00\n", "ffff"),
                            ("00" * 4097, "ff" * 4097), ("é0", "ff")):
        invalid.append([target, "0", expected, value])
    invalid += [["", "0", "00", "ff"], ["x" * 4096, "0", "00", "ff"],
                [target, str(MAX_POSITION - 1), "0000", "ffff"], [target, "0" * 24577, "00", "ff"]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, diagnostic="arguments", preflight=True)
    r.run("help-long", ["--help"], output=HELP, preflight=True)
    r.run("help-short", ["-h"], output=HELP, preflight=True)
    assert target_path.read_bytes() == b"\x00original"


def io(r):
    old = pattern(2049)
    original = b"L" * 17 + old + b"R" * 19
    value = bytes(byte ^ 255 for byte in old)
    r.patch("native-baseline", original, 17, old, value)
    for call in ("pread64", "pwrite64"):
        r.patch(f"retry-{call}-eintr", original, 17, old, value, injection=(call, 1, "EINTR"))
    r.patch("read-eio", original, 17, old, value, status=3, diagnostic="read", injection=("pread64", 2, "EIO"))
    r.patch("write-eio-confirmed-prefix", original, 17, old, value, status=3, diagnostic="write", expect_written=1024, injection=("pwrite64", 2, "EIO"))
    r.patch("open-eacces", original, 17, old, value, status=3, diagnostic="open", injection=("openat", 1, "EACCES"))
    r.patch("close-eio-after-full-write", original, 17, old, value, status=3, diagnostic="close", expect_written=len(value), injection=("close", 1, "EIO"))
    r.patch("mismatch-preserves-primary-on-close-eio", original, 17, b"x" * len(old), value, status=1, diagnostic="mismatch_close", injection=("close", 1, "EIO"))
    for call, phase in (("pread64", "read"), ("pwrite64", "write")):
        r.patch(f"exhaust-{call}-eintr-budget", original, 17, old, value, status=3, diagnostic=phase, injection=(call, "1+", "EINTR"))
    for name, path in (("missing", r.directory / "missing.bin"), ("directory", r.directory)):
        r.run("host-" + name, [str(path), "0", "00", "ff"], status=3, diagnostic="open")
    fifo = r.directory / "pipe"
    os.mkfifo(fifo, 0o600)
    r.run("nonseekable-fifo", [str(fifo), "0", "00", "ff"], status=3, diagnostic="read")
    r.run("closed-help-stdout", ["--help"], status=5, diagnostic="output", preflight=True, closed_stdout=True)
    r.run("signal-setup-failure", ["--help"], status=5, preflight=True, injection=("rt_sigaction", 1, "EIO"))
    for ordinal in (1, 2):
        r.patch(f"argument-oom-{ordinal}", original, 17, old, value, status=4, diagnostic="allocation", injection=("mmap", ordinal, "ENOMEM"))


def controls():
    assert len(HELP) == 662 and len(DIAGNOSTICS["mismatch"]) == 41
    assert replacement(b"prefixOLDsuffix", 6, b"NEW") == b"prefixNEWsuffix"
    assert len(pattern(4096)) == 4096 and len(bytes.fromhex(pattern(4096).hex().upper())) == 4096
    assert MAX_POSITION - 1 + 1 == MAX_POSITION and MAX_POSITION - 1 + 2 > MAX_POSITION
    # These controls remain pure: no files, native child or syscall injection.
    print(f"file-patch CPU byte controls=3; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "preservation": preservation, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"file-patch-{mode} cases={runner.count} evidence={runner.directory}")
