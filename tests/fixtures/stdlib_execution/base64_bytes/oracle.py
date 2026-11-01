"""Independent Python Base64 bytes with explicit strict canonical admission."""
import base64
from collections import Counter
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

CAP = 1048576
PROFILES = ("standard", "standard-unpadded", "url", "url-unpadded")
HELP = (b"Usage: base64_bytes encode|decode PROFILE\n"
        b"Profiles: standard, standard-unpadded, url, url-unpadded.\n"
        b"Read binary stdin through EOF and write the converted bytes without a newline.\n"
        b"Standard uses +/; URL uses -_. Padded profiles require canonical = padding when needed.\n"
        b"Unpadded profiles forbid =. Decode rejects whitespace, other alphabets and nonzero unused bits.\n"
        b"Limits: 1 MiB input; 8192 read attempts and 2048 output attempts, including interruptions.\n"
        b"Input is fully validated and converted before output; input errors publish no data.\n"
        b"A sole --help or -h shows help.\n")
ERROR = b"base64_bytes: operation failed\n"
COUNTS = {"model": 100, "rejection": 56, "cli": 20, "io": 18}
RFC = ((b"", b""), (b"f", b"Zg=="), (b"fo", b"Zm8="), (b"foo", b"Zm9v"),
       (b"foob", b"Zm9vYg=="), (b"fooba", b"Zm9vYmE="), (b"foobar", b"Zm9vYmFy"))


def encode(data, profile):
    if profile not in PROFILES: raise ValueError("profile")
    wire = base64.urlsafe_b64encode(data) if profile.startswith("url") else base64.b64encode(data)
    return wire.rstrip(b"=") if profile.endswith("unpadded") else wire


def decode(wire, profile):
    if profile not in PROFILES: raise ValueError("profile")
    padded = not profile.endswith("unpadded")
    alphabet = rb"A-Za-z0-9_-" if profile.startswith("url") else rb"A-Za-z0-9+/"
    if padded:
        if len(wire) % 4 or not re.fullmatch(b"[" + alphabet + b"]*={0,2}", wire): raise ValueError("padded structure")
    elif len(wire) % 4 == 1 or not re.fullmatch(b"[" + alphabet + b"]*", wire):
        raise ValueError("unpadded structure")
    normal = wire.translate(bytes.maketrans(b"-_", b"+/")) if profile.startswith("url") else wire
    plain = base64.b64decode(normal + b"=" * (-len(normal) % 4), validate=True)
    if encode(plain, profile) != wire: raise ValueError("noncanonical tail bits or padding")
    return plain


def reference(mode, profile, data):
    if len(data) > CAP: raise ValueError("input cap")
    return {"encode": encode, "decode": decode}[mode](data, profile)


def pattern(length):
    return (bytes(range(256)) * ((length + 255) // 256))[:length]


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
        elif name in ("close", "mremap", "brk"):
            raise AssertionError(("unexpected borrowed close/allocation service", line))
        elif name == "write" and args.startswith("2,"):
            assert not live, "diagnostic before owned storage cleanup"
    assert not live, ("observed unreleased mappings", live)
    return result


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"base64-bytes-{mode}-")); self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", trace=False, injection=None,
            read_error=False, closed_stdout=False, diagnostic=True, budget=None, preflight=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            maximum = 8192 if budget == "read" else 2048
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget, "-e",
                       f"inject={budget}:error=EINTR:when=1..{maximum}", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none", "-e",
                      "trace=read,write,close,mmap,munmap,mremap,brk,rt_sigaction", "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection; traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n"); prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try: result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
            finally: os.close(descriptor)
        elif closed_stdout:
            reader, writer = os.pipe(); os.close(reader)
            try: result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
            finally: os.close(writer)
            result.stdout = b""
        else: result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
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
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            expected = ["8192", "8192", "read"] if budget == "read" else ["2049", "2048", "write"]
            assert len(selected) == 1 and selected[0][-3:] == expected, rows
        if preflight: assert not any(item["name"] == "read" for item in found)
        self.count += 1; return found

    def model(self, name, mode, profile, data):
        return self.run(name, [mode, profile], data, output=reference(mode, profile, data))


def model(r):
    for profile in PROFILES:
        for index, (plain, padded) in enumerate(RFC):
            r.model(f"{profile}-rfc-encode-{index}", "encode", profile, plain)
            if index in (0, 1, 2, 6):
                r.model(f"{profile}-rfc-decode-{index}", "decode", profile, encode(plain, profile))
        binary = bytes(range(256))
        r.model(f"{profile}-all-bytes-encode", "encode", profile, binary)
        r.model(f"{profile}-all-bytes-decode", "decode", profile, encode(binary, profile))
        for size in (1, 2, 3):
            plain = b"\xff" * size
            r.model(f"{profile}-tail-encode-{size}", "encode", profile, plain)
            r.model(f"{profile}-tail-decode-{size}", "decode", profile, encode(plain, profile))
        for size in (1023, 1024, 1025): r.model(f"{profile}-encode-boundary-{size}", "encode", profile, pattern(size))
        r.model(f"{profile}-decode-crosses-read-boundary", "decode", profile, encode(pattern(769), profile))
        r.model(f"{profile}-maximum-encode-input", "encode", profile, pattern(CAP))
        r.model(f"{profile}-maximum-decode-input", "decode", profile, b"A" * CAP)


def rejection(r):
    for profile in PROFILES:
        unpadded = profile.endswith("unpadded"); valid = encode(b"f", profile)
        wrong = (b"/w" if profile.startswith("url") else b"_w") + (b"" if unpadded else b"==")
        invalid = [b"A", b" " + valid, valid + b"\n", b"Z g" + (b"" if unpadded else b"=="),
                   b"Zm9v\0", b"Zm9v\xff", b"\xc2\xa0" + valid, wrong, b"AA=A",
                   b"Zh" + (b"" if unpadded else b"=="), b"Zm9" + (b"" if unpadded else b"="),
                   b"Zg==" if unpadded else b"Zg"]
        for index, wire in enumerate(invalid): r.run(f"{profile}-invalid-{index}", ["decode", profile], wire, status=2)
        for mode in ("encode", "decode"):
            r.run(f"{profile}-{mode}-input-over-cap", [mode, profile], b"A" * (CAP + 1), status=2)


def cli(r):
    invalid = [[], ["encode"], ["encode", "standard", "extra"], ["--help", "x"], ["-h", "x"],
               ["--help", "--help"], ["-hh"], ["--help=yes"], ["--"], ["ENCODE", "standard"],
               ["encode", "STANDARD"], ["encode", ""], ["", "standard"], ["encode", "urlsafe"],
               ["decode", "standard-unpad"], ["encode", "x" * 65], ["encode", "x" * 58], ["encode", b"\xff"]]
    for index, arguments in enumerate(invalid): r.run(f"invalid-{index}", arguments, status=2, trace=True, read_error=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, read_error=True, preflight=True)


def io(r):
    args, data = ["encode", "url"], pattern(4097); expected = encode(data, "url")
    baseline = r.run("baseline", args, data, output=expected, trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    assert len(maps) == 4 and int(maps[2]["args"].split(",")[1]) == CAP
    assert int(maps[3]["args"].split(",")[1]) == len(expected)
    input_reserve, output_reserve = baseline.index(maps[2]), baseline.index(maps[3])
    for owner in maps[:2]:
        assert next(index for index, item in enumerate(baseline) if item["name"] == "munmap" and item["args"].split(",")[0] == owner["answer"]) < input_reserve
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    assert baseline.index(eof) < output_reserve
    writes = [index for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,")]
    input_release = next(index for index, item in enumerate(baseline) if index > input_reserve and item["name"] == "munmap" and item["args"].split(",")[0] == maps[2]["answer"])
    output_release = next(index for index, item in enumerate(baseline) if index > output_reserve and item["name"] == "munmap" and item["args"].split(",")[0] == maps[3]["answer"])
    assert input_release < min(writes) and output_release > max(writes)
    for old in maps:
        ordinal = old["ordinal"]
        actual = r.run(f"owner-oom-{ordinal}", args, data, status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert fault["args"] == old["args"]
    r.run("stdin-directory", args, status=3, trace=True, read_error=True)
    r.run("closed-data-stdout", args, data, status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True)
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, output=expected, trace=True, injection=(call, 1, "EINTR"))
    later = r.run("later-read-eio", args, data, status=3, trace=True, injection=("read", 2, "EIO"))
    assert int(next(item["answer"] for item in later if item["name"] == "read")) > 0
    failed = r.run("required-eof-eio", args, data, status=3, trace=True, injection=("read", eof["ordinal"], "EIO"))
    assert sum(int(item["answer"]) for item in failed if item["name"] == "read" and item["answer"].isdigit()) == len(data)
    partial = r.run("actual-output-prefix", args, data, status=5, output=expected[:1024], trace=True, injection=("write", 2, "EIO"))
    assert next(item["answer"] for item in partial if item["name"] == "write") == "1024"
    r.run("signal-setup-eio", args, data, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("read-attempt-cap", args, status=2, budget="read")
    r.run("output-attempt-cap", args, data, status=5, budget="write")
    rejected = r.run("noncanonical-before-output-reserve", ["decode", "url"], b"Zh==", status=2, trace=True)
    assert len([item for item in rejected if item["name"] == "mmap"]) == 3
    empty = r.run("empty-no-output-backing", args, trace=True)
    assert len([item for item in empty if item["name"] == "mmap"]) == 3


def controls():
    assert len(HELP) == 570 and len(ERROR) == 31
    for plain, wire in RFC:
        assert encode(plain, "standard") == wire and decode(wire, "standard") == plain
    assert encode(b"\xff", "standard") == b"/w==" and encode(b"\xff", "url") == b"_w=="
    assert encode(b"\xff\xff", "url-unpadded") == b"__8"
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs):
            if len(args) >= 3 and kwargs.get("status") == 2:
                try: reference(args[1][0], args[1][1], args[2])
                except ValueError: pass
                else: raise AssertionError("invalid reference accepted")
            self.count += 1; return []
        def model(self, name, mode, profile, data): reference(mode, profile, data); self.count += 1; return []
    for function in (model, rejection, cli):
        runner = CounterOnly(); function(runner); assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    trace = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\n"
    assert len(events(trace)) == 2
    try: events(trace.split("munmap")[0])
    except AssertionError: pass
    else: raise AssertionError("missing release accepted")
    print(f"base64-bytes CPU controls=8; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"base64-bytes-{mode} cases={runner.count} evidence={runner.directory}")
