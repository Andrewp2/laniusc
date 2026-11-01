"""Independent base-128/ZigZag integers and finite native CLI observations."""
from collections import Counter
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

MAXIMUM = (1 << 64) - 1
MIN_SIGNED, MAX_SIGNED = -(1 << 63), (1 << 63) - 1
HELP = (b"Usage: varint_number MODE VALUE\n"
        b"Modes: encode-u64, encode-i64, decode-u64, decode-i64.\n"
        b"Encode decimal integers as raw base-128 bytes without a newline; signed values use ZigZag.\n"
        b"Decimal input is at most 20 bytes. Unsigned input is digits only; signed input allows + or -.\n"
        b"Leading zeros are allowed. Decode accepts 2..20 ASCII hex digits in pairs, with no prefix or separators.\n"
        b"Decode requires one complete shortest encoding and prints decimal plus LF. No stdin is read.\n"
        b"A sole --help or -h shows help. Output permits 64 write attempts.\n")
ERROR = b"varint_number: operation failed\n"
COUNTS = {"model": 76, "wire": 30, "cli": 34, "io": 10}


def encode(value, signed=False):
    if signed:
        if not MIN_SIGNED <= value <= MAX_SIGNED: raise ValueError("signed range")
        value = 2 * value if value >= 0 else -2 * value - 1
    elif not 0 <= value <= MAXIMUM: raise ValueError("unsigned range")
    digits = []
    while value >= 128:
        value, low = divmod(value, 128); digits.append(low + 128)
    return bytes(digits + [value])


def decode(wire, signed=False):
    if not 1 <= len(wire) <= 10: raise ValueError("wire length")
    if any(byte < 128 for byte in wire[:-1]) or wire[-1] >= 128:
        raise ValueError("truncation or trailing value")
    value = sum((byte % 128) * (128 ** index) for index, byte in enumerate(wire))
    if value > MAXIMUM or encode(value) != wire: raise ValueError("range or nonminimal wire")
    return (-(value + 1) // 2 if value % 2 else value // 2) if signed else value


def events(text):
    result, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|close|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups(); counts[name] += 1
        result.append(dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line))
        if name == "mmap":
            size = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]; assert address not in live; live[address] = size
            else: assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("read", "close", "mremap", "brk"):
            raise AssertionError(("unexpected input/borrowed close/allocation service", line))
        elif name == "write": assert not live, "publication before argument-owner release"
    assert not live, ("observed unreleased mappings", live)
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"varint-number-{mode}-")); self.count = 0

    def run(self, name, arguments=(), *, status=0, output=b"", trace=False, injection=None,
            closed_stdout=False, diagnostic=True, budget=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=write", "-e",
                       "inject=write:error=EINTR:when=1..64", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none", "-e",
                      "trace=read,write,close,mmap,munmap,mremap,brk,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection; traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        try:
            if closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try: result = subprocess.run(command, stdin=descriptor, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
                finally: os.close(writer)
                result.stdout = b""
            else: result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
        finally: os.close(descriptor)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, output, result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected and selected[0]["answer"].startswith("-1 " + failure + " ")
        else: assert not marked, marked
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == ["write"]]
            assert len(selected) == 1 and selected[0][-3:] == ["65", "64", "write"], rows
        self.count += 1; return found


def model(r):
    unsigned = sorted({0, 1, 2, MAXIMUM} | {value for exponent in range(1, 10) for value in ((1 << (7 * exponent)) - 1, 1 << (7 * exponent))})
    signed = [MIN_SIGNED, MIN_SIGNED + 1, -8193, -65, -64, -1, 0, 1, 63, 64, 8192, MAX_SIGNED]
    rng = random.Random(0xA11F1A7)
    unsigned += [rng.randrange(1 << 64) for _ in range(2)]
    signed += [rng.randrange(MIN_SIGNED, MAX_SIGNED + 1) for _ in range(2)]
    for is_signed, values in ((False, unsigned), (True, signed)):
        kind = "i64" if is_signed else "u64"
        for index, value in enumerate(values):
            wire = encode(value, is_signed)
            r.run(f"encode-{kind}-{index}", ["encode-" + kind, str(value)], output=wire)
            token = wire.hex().upper() if index % 2 else wire.hex()
            r.run(f"decode-{kind}-{index}", ["decode-" + kind, token], output=f"{value}\n".encode())


def wire_errors(r):
    invalid = ["", "0", "000", "gg", "0x00", "00 ", " 00 ", "80", "8080", "8000", "8100",
               "ffffffffffffffffff02", "ffffffffffffffffff81", "0001", "80" * 9 + "00"]
    for kind in ("u64", "i64"):
        for index, token in enumerate(invalid): r.run(f"invalid-{kind}-{index}", ["decode-" + kind, token], status=2)


def cli(r):
    invalid = [[], ["encode-u64"], ["encode-u64", "1", "extra"], ["--help", "1"], ["-h", "1"],
               ["--help", "--help"], ["-hh"], ["--help=yes"], ["--"], ["unknown", "0"], ["ENCODE-U64", "0"]]
    invalid += [["encode-u64", token] for token in ("-1", "+1", str(1 << 64), "0" * 21, "", " 1", "1 ", "١", b"\xff")]
    invalid += [["encode-i64", token] for token in (str(MAX_SIGNED + 1), str(MIN_SIGNED - 1), "0" * 21, "+", "--1", "1.0", "1e2")]
    invalid += [["decode-u64", "00" * 11], ["decode-i64", "00" * 11]]
    for index, arguments in enumerate(invalid):
        found = r.run(f"invalid-{index}", arguments, status=2, trace=True)
        assert len([item for item in found if item["name"] == "mmap"]) <= 2
    r.run("help-long", ["--help"], output=HELP, trace=True)
    r.run("help-short", ["-h"], output=HELP, trace=True)
    r.run("unsigned-twenty-digit-leading-zero", ["encode-u64", "0" * 19 + "1"], output=b"\x01")
    r.run("signed-negative-zero", ["encode-i64", "-" + "0" * 19], output=b"\0")
    r.run("signed-explicit-plus", ["encode-i64", "+" + str(MAX_SIGNED)], output=encode(MAX_SIGNED, True))


def io(r):
    args = ["encode-u64", str(MAXIMUM)]; expected = encode(MAXIMUM)
    baseline = r.run("baseline", args, output=expected, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) == 2, "unexpected codec/output allocation beyond argv"
    for old in maps:
        ordinal = old["ordinal"]
        actual = r.run(f"argv-oom-{ordinal}", args, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("closed-data-stdout", args, status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    r.run("output-eio", args, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("output-eintr-retry", args, output=expected, trace=True, injection=("write", 1, "EINTR"))
    r.run("signal-setup-eio", args, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("output-attempt-cap", args, status=5, budget=True)
    r.run("wire-failure-cleanup", ["decode-u64", "8000"], status=2, trace=True)


def controls():
    assert len(HELP) == 536 and len(ERROR) == 32
    assert encode(0) == b"\0" and encode(127) == b"\x7f" and encode(128) == b"\x80\x01"
    assert encode(150) == bytes.fromhex("9601") and decode(bytes.fromhex("9601")) == 150
    assert encode(-1, True) == b"\x01" and encode(1, True) == b"\x02" and encode(-2, True) == b"\x03"
    assert encode(MIN_SIGNED, True) == b"\xff" * 9 + b"\x01"
    assert decode(b"\xff" * 9 + b"\x01", True) == MIN_SIGNED
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, name, arguments=(), **kwargs):
            if name.startswith("decode-") and kwargs.get("status", 0) == 0 and not name.startswith("invalid"):
                assert f"{decode(bytes.fromhex(arguments[1]), arguments[0] == 'decode-i64')}\n".encode() == kwargs["output"]
            if name.startswith("invalid-") and len(arguments) == 2 and arguments[0].startswith("decode-"):
                try:
                    if not re.fullmatch(r"(?:[0-9a-fA-F]{2}){1,10}", arguments[1]): raise ValueError("hex syntax")
                    decode(bytes.fromhex(arguments[1]))
                except ValueError: pass
                else: raise AssertionError("invalid wire reference accepted")
            self.count += 1; return []
    for function, name in ((model, "model"), (wire_errors, "wire"), (cli, "cli")):
        runner = CounterOnly(); function(runner); assert runner.count == COUNTS[name], (name, runner.count)
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(1, \"x\", 1) = 1\n"
    assert len(events(trace)) == 3
    try: events(trace.replace("munmap(0x1000, 16) = 0\n", ""))
    except AssertionError: pass
    else: raise AssertionError("early output or missing release accepted")
    print(f"varint-number CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "wire": wire_errors, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"varint-number-{mode} cases={runner.count} evidence={runner.directory}")
