"""Independent raw-byte/strict-Unicode counts and selected owned input faults."""
from collections import Counter
import os
from pathlib import Path
import re
import resource
import signal
import subprocess
import sys
import tempfile

CAP = 1048576
HELP = (b"Usage: input_stats bytes|text [PATH|-]\n"
        b"Read stdin when PATH is omitted or -; otherwise read the literal byte path.\n"
        b"Byte mode prints bytes=N and nul=M on separate LF-terminated lines.\n"
        b"Text mode requires strict UTF-8 and prints bytes=N, scalars=S and lf=L on separate lines.\n"
        b"LF counts byte 0x0A; CR is unchanged and no final line ending is assumed.\n"
        b"Limits: 1 MiB input, 8192 read attempts, 64 output attempts; interruptions spend attempts.\n"
        b"Input is fully collected and validated before output; input errors publish no data.\n"
        b"A sole --help or -h shows help.\n")
ERROR = b"input_stats: operation failed\n"
TRACE = "openat,close,lseek,read,write,mmap,munmap,mremap,brk,rt_sigaction"
COUNTS = {"model": 38, "rejection": 24, "cli": 22, "io": 27}


def pattern(length):
    return (bytes(range(256)) * ((length + 255) // 256))[:length]


def reference(mode, data):
    if len(data) > CAP: raise ValueError("byte cap")
    if mode == "bytes":
        return f"bytes={len(data)}\nnul={data.count(0)}\n".encode()
    if mode != "text": raise ValueError("mode")
    text = data.decode("utf-8", "strict")
    return f"bytes={len(data)}\nscalars={len(text)}\nlf={data.count(10)}\n".encode()


def events(text):
    result, counts, live, descriptor = [], Counter(), {}, None
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z0-9_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
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
        elif name in ("mremap", "brk", "lseek"):
            raise AssertionError(("unexpected allocation or seek service", line))
        elif name == "openat":
            assert counts[name] == 1 and descriptor is None
            assert "O_RDONLY" in args and "O_CLOEXEC" in args
            assert not any(flag in args for flag in ("O_WRONLY", "O_RDWR", "O_CREAT", "O_TRUNC", "O_APPEND"))
            if not answer.startswith("-1"): descriptor = int(answer)
        elif name == "close":
            assert descriptor is not None and int(args) == descriptor and counts[name] == 1
            assert answer == "0" or (answer.startswith("-1 ") and "INJECTED" in answer)
            descriptor = None
        elif name == "read":
            if counts["openat"]: assert descriptor is not None, "read after failed open/explicit close"
            assert int(args.split(",")[0]) == (descriptor if descriptor is not None else 0), line
        elif name == "write":
            assert int(args.split(",")[0]) in (1, 2), line
            assert descriptor is None and not live, "publication/diagnostic before explicit owner retirement"
    assert not live, ("observed unreleased mappings", live)
    assert descriptor is None, "missing explicit owned-file close attempt"
    return result


class Runner:
    observes = True
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        header = Path(self.executable).read_bytes()[:64]
        assert len(header) == 64 and header[:6] == b"\x7fELF\x02\x01"
        assert int.from_bytes(header[16:18], "little") == 2 and int.from_bytes(header[18:20], "little") == 62
        self.directory = Path(tempfile.mkdtemp(prefix=f"input-stats-{mode}-")); self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", trace=False,
            injections=(), read_error=False, closed_stdout=False, diagnostic=True, budget=None,
            preflight=False, stdout_limit=False):
        prefix = self.directory / name; command = [self.executable, *arguments]
        if budget:
            maximum = 8192 if budget == "read" else 64
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..{maximum}",
                       "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
                      "-e", "trace=" + TRACE, "-o", str(prefix.with_suffix(".trace"))]
            for call, ordinal, failure in injections:
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n"); prefix.with_suffix(".input").write_bytes(data)
        source = None
        if read_error: source = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
        options = dict(cwd=self.directory, timeout=15, check=False, stderr=subprocess.PIPE)
        if source is not None: options["stdin"] = source
        else: options["input"] = data
        try:
            if stdout_limit:
                assert not trace and not budget and not closed_stdout
                def set_limit():
                    resource.setrlimit(resource.RLIMIT_FSIZE, (10, 10)); signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
                with tempfile.TemporaryFile() as target:
                    result = subprocess.run(command, stdout=target, preexec_fn=set_limit, **options)
                    target.seek(0); result.stdout = target.read()
            elif closed_stdout:
                reader, writer = os.pipe(); os.close(reader)
                try: result = subprocess.run(command, stdout=writer, **options)
                finally: os.close(writer)
                result.stdout = b""
            else: result = subprocess.run(command, stdout=subprocess.PIPE, **options)
        finally:
            if source is not None: os.close(source)
        prefix.with_suffix(".stdout").write_bytes(result.stdout); prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, result.stdout, output, result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        selected = []
        for call, ordinal, failure in injections:
            reached = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(reached) == 1 and reached[0]["answer"].startswith("-1 " + failure + " ")
            selected += reached
        assert {item["line"] for item in marked} == {item["line"] for item in selected}
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            expected = ["8192", "8192", "read"] if budget == "read" else ["65", "64", "write"]
            assert len(selected) == 1 and selected[0][-3:] == expected, rows
        if preflight: assert not any(item["name"] in ("openat", "read", "close") for item in found)
        self.count += 1; return found

    def collect(self, name, mode, data, *, file=False, filename=None, explicit_stdin=False, symlink=False, **options):
        arguments = [mode]
        path = None
        if file:
            path = os.fsencode(self.directory) + b"/" + os.fsencode(filename or name + ".bin")
            with open(path, "wb") as target: target.write(data)
            argument = path
            if filename in ("--help", "-h"): argument = filename
            if filename == "-": argument = "./-"
            if symlink:
                link = self.directory / (name + ".link"); os.symlink(path, link); argument = str(link)
            arguments += [argument]
        elif explicit_stdin: arguments += ["-"]
        status = options.get("status", 0)
        output = options.pop("output", b"" if status else reference(mode, data))
        found = self.run(name, arguments, data if not file else b"", output=output, read_error=file, **options)
        if path is not None:
            with open(path, "rb") as target: assert target.read() == data, "input file changed"
        return found


def model(r):
    for index, data in enumerate((b"", b"\0", b"\xff", bytes(range(256)), b"a\r\nb\nc\r\0\xff",
                                 pattern(1023), pattern(1024), pattern(1025), pattern(4097), pattern(CAP))):
        found = r.collect(f"binary-stdin-{index}", "bytes", data, explicit_stdin=index % 2 == 1, trace=len(data) == CAP)
        if len(data) == CAP and r.observes:
            reads = [item for item in found if item["name"] == "read"]
            assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"] == "0"
            assert sum(int(item["answer"]) for item in reads) == CAP
    texts = ("", "ASCII without final LF", "\0\n\r\n\r", "é中🙂", "e\u0301\n\U0001f1fa\U0001f1f8",
             "\ufeff\ufffe\uffff\U0010ffff", "".join(map(chr, (0,127,128,2047,2048,55295,57344,65535,65536,1114111))))
    for index, text in enumerate(texts): r.collect(f"text-stdin-{index}", "text", text.encode())
    r.collect("text-maximum-input", "text", b"\xc3\xa9\n\0" * (CAP // 4))
    for width, scalar in ((2, "é"), (3, "中"), (4, "🙂")):
        for split in range(1, width):
            data = b"A" * (1024 - split) + scalar.encode() + b"\nZ"
            r.collect(f"valid-split-{width}-{split}", "text", data, file=True)
    for index, (mode, data) in enumerate((("bytes", b""), ("text", b""), ("bytes", bytes(range(256))),
                                        ("bytes", pattern(4097)), ("text", "é\0中\r\n🙂".encode()),
                                        ("bytes", pattern(CAP)), ("text", b"A" * CAP))):
        r.collect(f"file-{index}", mode, data, file=True)
    r.collect("raw-nonutf8-path", "bytes", b"\xff\0\n", file=True, filename=b"input-\xff.bin")
    r.collect("unicode-path", "text", "é中🙂".encode(), file=True, filename="input-é.bin")
    r.collect("flag-literal-path", "bytes", b"\0\xff", file=True, filename="--help")
    r.collect("short-help-literal-path", "text", b"x\n", file=True, filename="-h")
    r.collect("literal-minus-file", "bytes", b"\0\xff", file=True, filename="-")
    r.collect("follow-final-symlink", "text", "é\0\n".encode(), file=True, symlink=True)
    base = os.fsencode(r.directory) + b"/long/"
    while len(base) + 201 + 8 < 4095: base += b"d" * 200 + b"/"
    os.makedirs(base); path = base + b"f" * (4095 - len(base)); assert len(path) == 4095
    with open(path, "wb") as target: target.write(b"\0\n")
    r.run("maximum-path-and-snapshot", ["bytes", path], read_error=True, output=reference("bytes", b"\0\n"))


def rejection(r):
    invalid = (b"\x80", b"\xc0\x80", b"\xc1\xbf", b"\xf5\x80\x80\x80", b"\xff", b"\xe0\x80\x80",
               b"\xf0\x80\x80\x80", b"\xed\xa0\x80", b"\xf4\x90\x80\x80", b"\xc2", b"\xe2\x82",
               b"\xf0\x9f\x92", b"\xc2A", b"\xe2A\x80", b"\xf0A\x80\x80", b"valid\0\n\xfftail")
    for index, data in enumerate(invalid): r.collect(f"invalid-utf8-{index}", "text", data, file=index % 2 == 1, status=2)
    for index, data in enumerate((b"A" * 1023 + b"\xc2A", b"A" * 1023 + b"\xe2\x82", b"A" * 1022 + b"\xed\xa0\x80")):
        r.collect(f"invalid-split-{index}", "text", data, file=True, status=2)
    for mode in ("bytes", "text"):
        for file in (False, True):
            traced = mode == "bytes" and not file
            found = r.collect(f"over-cap-{mode}-{file}", mode, b"A" * (CAP + 1), file=file, status=2, trace=traced)
            if traced and r.observes:
                reads = [item for item in found if item["name"] == "read"]
                assert reads[-1]["args"].endswith(", 1") and reads[-1]["answer"] == "1"
                assert sum(int(item["answer"]) for item in reads) == CAP + 1
    r.collect("utf8-invalid-at-maximum-byte", "text", b"A" * (CAP - 1) + b"\xc2", status=2)


def cli(r):
    invalid = ([], ["--"], ["BYTES"], ["Text"], [""], ["bytes", "", "extra"], ["bytes", "-", "extra"],
               ["--help", "bytes"], ["-h", "-"], ["--help", "--help"], ["-hh"], ["--help=yes"],
               ["bytes", ""], ["text", "x" * 4096], ["bytes", "x" * 4096], [b"\xff"],
               ["bytes ", "-"], [" bytes"], ["bytes\n"], ["bytes", "p", "q", "r"])
    for index, args in enumerate(invalid): r.run(f"invalid-{index}", args, status=2, trace=True, read_error=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, read_error=True, preflight=True)


def io(r):
    data = (b"\0a\xc3\xa9\n" * 1000) + b"Z"; expected = reference("text", data)
    def exercise(name, **options): return r.collect(name, "text", data, file=True, filename="io-source.bin", **options)
    baseline = exercise("baseline", trace=True)
    maps = [item for item in baseline if item["name"] == "mmap"]
    opened = next(index for index, item in enumerate(baseline) if item["name"] == "openat")
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    eof = next(item for item in baseline if item["name"] == "read" and item["answer"] == "0")
    closed = next(index for index, item in enumerate(baseline) if item["name"] == "close")
    assert len(maps) >= 4 and baseline.index(maps[1]) < opened < baseline.index(maps[2]) < first_read
    assert not any(item["name"] == "mmap" for item in baseline[baseline.index(eof) + 1:]), "text adoption/output allocated after EOF"
    for owner in maps[:2]:
        released = next(index for index, item in enumerate(baseline) if index > baseline.index(owner) and item["name"] == "munmap" and item["args"].split(",")[0] == owner["answer"])
        assert opened < released < baseline.index(maps[2])
    assert max(index for index, item in enumerate(baseline) if item["name"] == "munmap") < closed
    selected = [maps[0], maps[1], maps[2], maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 4
    for old in selected:
        actual = exercise(f"owner-oom-{old['ordinal']}", status=4, trace=True, injections=(("mmap", old["ordinal"], "ENOMEM"),))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == old["ordinal"])
        assert fault["args"] == old["args"]
        before = sum(int(item["answer"]) for item in baseline[:baseline.index(old)] if item["name"] == "read" and item["answer"].isdigit())
        after = sum(int(item["answer"]) for item in actual if item["name"] == "read" and item["answer"].isdigit())
        assert before == after, "failed pre-read reservation consumed more input"
    r.run("stdin-directory", ["bytes"], status=3, trace=True, read_error=True)
    r.run("opened-directory", ["bytes", str(r.directory)], status=3, trace=True, read_error=True)
    r.run("missing-file", ["text", str(r.directory / "missing")], status=3, trace=True, read_error=True)
    exercise("open-eacces", status=3, trace=True, injections=(("openat", 1, "EACCES"),))
    exercise("open-eintr-no-retry", status=3, trace=True, injections=(("openat", 1, "EINTR"),))
    exercise("read-eintr-retry", trace=True, injections=(("read", 1, "EINTR"),))
    exercise("later-read-eio", status=3, trace=True, injections=(("read", 2, "EIO"),))
    failed = exercise("required-eof-eio", status=3, trace=True, injections=(("read", eof["ordinal"], "EIO"),))
    assert sum(int(item["answer"]) for item in failed if item["name"] == "read" and item["answer"].isdigit()) == len(data)
    exercise("close-eio", status=3, trace=True, injections=(("close", 1, "EIO"),))
    exercise("close-eintr-no-retry", status=3, trace=True, injections=(("close", 1, "EINTR"),))
    r.collect("invalid-text-primary-close-eio", "text", b"valid\xfftail", file=True, filename="io-source.bin", status=2,
              trace=True, injections=(("close", 1, "EIO"),))
    exercise("allocation-primary-close-eio", status=4, trace=True,
             injections=(("mmap", maps[-1]["ordinal"], "ENOMEM"), ("close", 1, "EIO")))
    invalid = r.collect("invalid-text-cleanup-after-eof", "text", b"valid\xfftail", file=True, filename="io-source.bin", status=2, trace=True)
    reads = [item for item in invalid if item["name"] == "read"]
    assert reads[-1]["answer"] == "0" and sum(int(item["answer"]) for item in reads) == 10
    r.collect("read-error-precedes-invalid-text", "text", b"valid\xfftail", file=True, filename="io-source.bin", status=3,
              trace=True, injections=(("read", 2, "EIO"),))
    exercise("closed-data-stdout", status=5, trace=True, closed_stdout=True)
    r.run("closed-help-stdout", ["--help"], status=5, trace=True, closed_stdout=True, read_error=True)
    exercise("output-eintr-retry", trace=True, injections=(("write", 1, "EINTR"),))
    exercise("output-eio", status=5, trace=True, injections=(("write", 1, "EIO"),))
    exercise("actual-regular-file-prefix", status=5, output=expected[:10], stdout_limit=True)
    r.run("signal-setup-eio", ["bytes"], status=5, trace=True, injections=(("rt_sigaction", 1, "EIO"),), diagnostic=False)
    exercise("read-attempt-cap", status=2, budget="read")
    exercise("output-attempt-cap", status=5, budget="write")


def controls():
    assert len(HELP) == 554 and len(ERROR) == 30
    assert reference("bytes", b"\0\xff\0\n") == b"bytes=4\nnul=2\n"
    assert reference("text", "\0é中🙂\r\n".encode()) == b"bytes=12\nscalars=6\nlf=1\n"
    assert reference("text", b"") == b"bytes=0\nscalars=0\nlf=0\n"
    class CounterOnly:
        observes = False
        def __init__(self): self.count = 0; self.directory = Path(tempfile.mkdtemp(prefix="input-stats-cpu-"))
        def run(self, *args, **kwargs): self.count += 1; return []
        def collect(self, name, mode, data, **kwargs):
            if kwargs.get("status") == 2:
                try: reference(mode, data)
                except ValueError: pass
                else: raise AssertionError("rejection reference accepted")
            else: reference(mode, data)
            self.count += 1; return []
    for function in (model, rejection, cli):
        runner = CounterOnly(); function(runner)
        assert runner.count == COUNTS[function.__name__]
    good = "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\nmunmap(0x1000, 16) = 0\nwrite(1, X, 1) = 1\n"
    assert len(events(good)) == 3
    for bad in (good.replace("munmap(0x1000, 16) = 0\n", ""), "openat(X, X, O_RDONLY|O_CLOEXEC, 0) = 3\nwrite(1, X, 1) = 1\nclose(3) = 0\n"):
        try: events(bad)
        except AssertionError: pass
        else: raise AssertionError("owner/descriptor ordering violation accepted")
    print(f"input-stats CPU controls passed; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]: controls()
    else:
        mode, executable = sys.argv[1:]; runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"input-stats-{mode} cases={runner.count} evidence={runner.directory}")
