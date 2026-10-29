"""Independent binary framing model, real Unix peers and finite native faults."""
from collections import Counter
import os
from pathlib import Path
import re
import resource
import select
import signal
import socket
import subprocess
import sys
import tempfile
import time

CAP = 1048576
ERROR = b"unix_request: operation failed\n"
HELP = (b"Usage: unix_request path|abstract NAME\n"
        b"Send one binary stdin request over a Unix stream and print one admitted response.\n"
        b"Namespaces are explicit: path NAME is 1..107 bytes; abstract NAME is 0..107 bytes.\n"
        b"Wire format: big-endian u32 length plus payload; each payload is at most 1048576 bytes.\n"
        b"Require stdin EOF before connect, shutdown Write after request, and response EOF before output.\n"
        b"Limits: 8192 stdin calls, 8192 public network transfers, 8192 output calls; one 5-second network deadline.\n"
        b"A sole --help or -h shows help. NAME is raw argv bytes; @ has no special meaning.\n")
COUNTS = {"model": 24, "rejection": 17, "cli": 19, "io": 24}
TRACE = "read,write,mmap,munmap,mremap,brk,rt_sigaction,socket,connect,sendto,recvfrom,shutdown,close,poll,clock_gettime"
PEER = Path(__file__).with_name("peer.py")


def pattern(length):
    block = bytes((index * 73 + 19) % 256 for index in range(256))
    return (block * ((length + 255) // 256))[:length]


def frame(payload):
    assert len(payload) <= CAP
    return len(payload).to_bytes(4, "big") + payload


def decode(wire):
    if len(wire) < 4:
        raise ValueError("truncated header")
    size = int.from_bytes(wire[:4], "big")
    if size > CAP or len(wire) != 4 + size:
        raise ValueError("size, truncation or trailing bytes")
    return wire[4:]


def events(text):
    result, counts, live, descriptor = [], Counter(), {}, None
    for line in text.splitlines():
        match = re.fullmatch(r"([a-z_]+)\((.*)\)\s+=\s+(.*)", line)
        assert match and match[1] in TRACE.split(","), ("unexpected trace line", line)
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
            else:
                assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk"):
            raise AssertionError(("unexpected allocation service", line))
        elif name == "socket":
            assert descriptor is None and counts[name] == 1, line
            assert "AF_UNIX" in args and "SOCK_STREAM" in args and "SOCK_NONBLOCK" in args and "SOCK_CLOEXEC" in args, line
            if not answer.startswith("-1"):
                descriptor = int(answer)
        elif name == "close":
            assert descriptor is not None and int(args) == descriptor and counts[name] == 1, line
            assert answer == "0" or (answer.startswith("-1 ") and "INJECTED" in answer), line
            descriptor = None
        elif name in ("connect", "sendto", "recvfrom", "shutdown"):
            assert descriptor is not None and int(args.split(",")[0]) == descriptor, line
            if name == "sendto":
                assert "MSG_NOSIGNAL" in args and "MSG_DONTWAIT" in args, line
            elif name == "recvfrom":
                assert "MSG_DONTWAIT" in args, line
    assert not live, ("observed unreleased mappings", live)
    assert descriptor is None, "acquired socket lacks its explicit close attempt"
    assert counts["connect"] <= 1 and counts["shutdown"] <= 1
    return result


class Peer:
    def __init__(self, prefix, namespace, name, response, action, chunk):
        self.prefix, self.namespace, self.name = prefix, namespace, name
        prefix.with_suffix(".response-wire").write_bytes(response)
        read_ready, write_ready = os.pipe()
        read_release, self.write_release = os.pipe()
        command = [sys.executable, "-B", str(PEER), namespace, name.hex(),
                   str(prefix.with_suffix(".request-wire")), str(prefix.with_suffix(".response-wire")),
                   action, str(chunk), str(write_ready), str(read_release), str(prefix.with_suffix(".peer-log"))]
        prefix.with_suffix(".peer-command").write_text(repr(command) + "\n")
        self.stdout = prefix.with_suffix(".peer-stdout").open("wb")
        self.stderr = prefix.with_suffix(".peer-stderr").open("wb")
        try:
            self.process = subprocess.Popen(command, pass_fds=(write_ready, read_release), stdout=self.stdout, stderr=self.stderr)
        finally:
            os.close(write_ready)
            os.close(read_release)
        try:
            assert select.select([read_ready], [], [], 3)[0], "peer readiness timeout"
            assert os.read(read_ready, 1) == b"R", "peer failed before binding"
        finally:
            os.close(read_ready)

    def finish(self, expected_request):
        try:
            try:
                os.write(self.write_release, b"C")
            except BrokenPipeError:
                pass
            finally:
                os.close(self.write_release)
            if expected_request is None:
                try:
                    self.process.wait(timeout=0.25)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    self.process.wait(timeout=2)
            else:
                assert self.process.wait(timeout=3) == 0, self.prefix
                assert self.prefix.with_suffix(".request-wire").read_bytes() == frame(expected_request), self.prefix
                assert "request-eof\n" in self.prefix.with_suffix(".peer-log").read_text()
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=2)
            self.stdout.close()
            self.stderr.close()
            if self.namespace == "path":
                assert os.path.exists(self.name), "client unlinked peer pathname"
                os.unlink(self.name)


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"unix-request-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"", namespace=None,
            endpoint=None, response=b"", action="normal", chunk=4096, expect_request=False,
            trace=False, injection=None, read_error=False, closed_stdout=False, budget=None,
            diagnostic=True, file_limit=None, preflight=False, deadline=False):
        prefix = self.directory / name
        if namespace is not None:
            if endpoint is None:
                endpoint = os.fsencode(prefix.with_suffix(".sock")) if namespace == "path" else f"ur-{os.getpid()}-{self.count}".encode()
            arguments = [namespace, endpoint]
            peer = Peer(prefix, namespace, endpoint, response, action, chunk)
        else:
            peer = None
        command = [self.executable, *arguments]
        if budget:
            command = ["strace", "--kill-on-exit", "-qq", "-c", "-e", "trace=" + budget,
                       "-e", f"inject={budget}:error=EINTR:when=1..8192", "-o", str(prefix.with_suffix(".trace")), *command]
        elif trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "32", "-e", "signal=none",
                      "-e", "trace=" + TRACE, "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + (f"\nRLIMIT_FSIZE={file_limit}; SIGXFSZ=SIG_IGN\n" if file_limit is not None else "\n"))
        prefix.with_suffix(".input").write_bytes(data)
        started = time.monotonic()
        try:
            if file_limit is not None:
                assert not trace and not budget
                def limit_output():
                    resource.setrlimit(resource.RLIMIT_FSIZE, (file_limit, file_limit))
                    signal.signal(signal.SIGXFSZ, signal.SIG_IGN)
                with prefix.with_suffix(".limited-output").open("w+b") as target:
                    result = subprocess.run(command, input=data, stdout=target, stderr=subprocess.PIPE,
                                            preexec_fn=limit_output, timeout=15, check=False)
                    target.seek(0)
                    result.stdout = target.read()
            elif read_error:
                descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=15, check=False)
                finally:
                    os.close(descriptor)
            elif closed_stdout:
                reader, writer = os.pipe()
                os.close(reader)
                try:
                    result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE, timeout=15, check=False)
                finally:
                    os.close(writer)
                result.stdout = b""
            else:
                result = subprocess.run(command, input=data, capture_output=True, timeout=15, check=False)
        finally:
            if peer is not None:
                peer.finish(data if expect_request else None)
        elapsed = time.monotonic() - started
        prefix.with_suffix(".elapsed").write_text(f"{elapsed:.6f}\n")
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status and result.stdout == output, (name, result.returncode, status, len(result.stdout), len(output), result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, marked)
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        if preflight:
            assert not any(item["name"] in ("read", "socket", "connect", "sendto", "recvfrom") for item in found)
        if budget:
            rows = prefix.with_suffix(".trace").read_text().splitlines()
            selected = [row.split() for row in rows if row.split()[-1:] == [budget]]
            calls = "8193" if budget == "write" else "8192"
            assert len(selected) == 1 and selected[0][-3:] == [calls, "8192", budget], rows
        if deadline:
            assert 3.5 <= elapsed < 12, (name, elapsed)
            assert any(item["name"] == "poll" for item in found), "deadline case never waited"
        self.count += 1
        return found

    def exchange(self, name, data, response, namespace="path", **options):
        return self.run(name, data=data, output=response, namespace=namespace,
                        response=frame(response), expect_request=True, **options)


def model(r):
    for namespace in ("path", "abstract"):
        for length in (0, 1, 256, 1023, 1024, 1025, 8193):
            data = pattern(length)
            response = bytes(value ^ 255 for value in data[::-1])
            r.exchange(f"{namespace}-binary-{length}", data, response, namespace, chunk=1 if length == 1 else 4096)
    r.exchange("maximum-input", pattern(CAP), b"max-input-ok", "path")
    r.exchange("maximum-response", b"max-response", pattern(CAP), "abstract")
    path_base = f"/tmp/ur-{os.getpid()}-".encode()
    special = [("path107", "path", path_base + b"p" * (107 - len(path_base))),
               ("abstract107", "abstract", f"ur-{os.getpid()}-".encode().ljust(107, b"a")),
               ("literal-at", "abstract", f"@ur-{os.getpid()}".encode()),
               ("raw-path", "path", path_base + b"\xff"),
               ("raw-abstract", "abstract", f"ur-{os.getpid()}-".encode() + b"\xff"),
               ("empty-abstract", "abstract", b"")]
    for name, namespace, endpoint in special:
        r.exchange(name, b"\0\xffrequest", b"\xff\0reply", namespace, endpoint=endpoint)
    for length in (65535, 65536):
        r.exchange(f"response-length-{length}", b"check-BE32", pattern(length), "abstract")


def rejection(r):
    no_socket = r.run("input-over-cap", ["abstract", "unused"], data=pattern(CAP + 1), status=2, trace=True)
    assert not any(item["name"] == "socket" for item in no_socket)
    r.run("missing-path", ["path", os.fsencode(r.directory / "absent.sock")], status=6, trace=True)
    r.run("missing-abstract", ["abstract", f"missing-ur-{os.getpid()}"], status=6, trace=True)
    wires = [("no-header", b""), ("header1", b"\0"), ("header2", b"\0\0"), ("header3", b"\0\0\0"),
             ("body-empty", (1).to_bytes(4, "big")), ("body-short", (7).to_bytes(4, "big") + b"abc"),
             ("over-response-cap", (CAP + 1).to_bytes(4, "big")),
             ("high-bit-response-count", (1 << 31).to_bytes(4, "big")),
             ("maximum-response-count", ((1 << 32) - 1).to_bytes(4, "big")),
             ("trailing-after-empty", frame(b"") + b"x"),
             ("trailing-after-payload", frame(b"ok") + b"x"),
             ("second-response-frame", frame(b"ok") + frame(b"next"))]
    for name, response in wires:
        r.run(name, data=b"request", namespace="abstract", response=response, status=6, expect_request=True, trace=True)
    r.run("deadline-no-response", data=b"request", namespace="abstract", action="stall", status=6,
          expect_request=True, trace=True, deadline=True)
    r.run("deadline-missing-eof", data=b"request", namespace="path", response=frame(b"staged"), action="hold",
          status=6, expect_request=True, trace=True, deadline=True)


def cli(r):
    invalid = [[], ["path"], ["abstract"], ["foo", "x"], ["Path", "x"], ["--help", "x"], ["-h", "x"],
               ["path", "x", "extra"], ["--help", "--help"], ["-hh"], ["--help=yes"], ["--"],
               ["x" * 129], ["path", ""], ["path", "x" * 108], ["abstract", "x" * 108], ["abstract", "x" * 129]]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, trace=True, read_error=True, preflight=True)
    r.run("help-long", ["--help"], output=HELP, trace=True, read_error=True, preflight=True)
    r.run("help-short", ["-h"], output=HELP, trace=True, read_error=True, preflight=True)


def io(r):
    data, response = pattern(4100), pattern(5000)
    baseline = r.exchange("baseline", data, response, "abstract", trace=True)
    created = next(index for index, item in enumerate(baseline) if item["name"] == "socket")
    input_eof = next(index for index, item in enumerate(baseline) if item["name"] == "read" and item["answer"] == "0")
    assert input_eof < created, "socket created before actual input EOF"
    closed = next(index for index, item in enumerate(baseline) if item["name"] == "close")
    response_eof = max(index for index, item in enumerate(baseline) if item["name"] == "recvfrom" and item["answer"] == "0")
    assert response_eof < closed
    assert all(index > closed for index, item in enumerate(baseline) if item["name"] == "write" and item["args"].startswith("1,"))
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    input_maps = [item for index, item in enumerate(baseline) if item["name"] == "mmap" and first_read < index < created]
    response_maps = [item for index, item in enumerate(baseline) if item["name"] == "mmap" and index > created]
    for phase, selected in (("input", [input_maps[0], input_maps[-1]]), ("response", [response_maps[0], response_maps[-1]])):
        assert selected[0]["ordinal"] != selected[1]["ordinal"]
        for old in selected:
            ordinal = old["ordinal"]
            actual = r.run(f"{phase}-oom-{ordinal}", data=data, namespace="abstract", response=frame(response), status=4,
                           trace=True, injection=("mmap", ordinal, "ENOMEM"), expect_request=phase == "response")
            fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
            assert fault["args"] == old["args"]
    for ordinal in (1, 2):
        r.run(f"help-owner-oom-{ordinal}", ["--help"], status=4, trace=True, injection=("mmap", ordinal, "ENOMEM"))
    for call in ("read", "sendto", "recvfrom"):
        r.exchange(f"retry-{call}-eintr", data, response, "abstract", trace=True, injection=(call, 1, "EINTR"))
    r.run("stdin-directory", ["abstract", "unused"], status=3, trace=True, read_error=True)
    r.run("closed-stdout", data=data, namespace="abstract", response=frame(response), status=5, expect_request=True,
          trace=True, closed_stdout=True)
    for failure in ("EIO", "EINTR"):
        found = r.run(f"connect-{failure.lower()}", data=data, namespace="abstract", response=frame(response), status=6,
                      trace=True, injection=("connect", 1, failure))
        assert not any(item["name"] in ("sendto", "recvfrom", "shutdown") for item in found)
    for call in ("sendto", "recvfrom", "shutdown", "close", "clock_gettime"):
        r.run(f"{call}-eio", data=data, namespace="abstract", response=frame(response), status=6, trace=True,
              injection=(call, 1, "EIO"), expect_request=call in ("recvfrom", "close"))
    r.run("stdout-eio", data=data, namespace="abstract", response=frame(response), status=5, expect_request=True,
          trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-eio", status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)
    r.run("input-attempt-cap", ["abstract", "unused"], status=2, budget="read")
    r.run("output-attempt-cap", data=data, namespace="abstract", response=frame(response), status=5,
          expect_request=True, budget="write")
    r.run("actual-output-prefix", data=data, namespace="abstract", response=frame(response), status=5,
          expect_request=True, output=response[:10], file_limit=10)


def controls():
    assert len(ERROR) == 31 and len(HELP) == 577
    for length in (0, 1, 256, 1024, 65536, CAP):
        payload = pattern(length)
        assert decode(frame(payload)) == payload
    assert frame(b"x")[:4] == b"\0\0\0\1" and frame(pattern(256))[:4] == b"\0\0\1\0"
    for wire in (b"", b"\0\0\0", frame(b"x")[:-1], frame(b"") + b"x", (1 << 31).to_bytes(4, "big")):
        try:
            decode(wire)
        except ValueError:
            pass
        else:
            raise AssertionError("invalid wire accepted")
    trace = "socket(AF_UNIX, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, 0) = 3\nclose(3) = 0\n"
    assert len(events(trace)) == 2
    for bad in (trace.split("close")[0], "mmap(NULL, 16, X, Y, -1, 0) = 0x1000\n"):
        try:
            events(bad)
        except AssertionError:
            pass
        else:
            raise AssertionError("missing cleanup accepted")
    class CounterOnly:
        directory = Path("/tmp/unix-request-controls-unused")
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1; return []
        def exchange(self, *args, **kwargs): self.count += 1; return []
    for function in (model, rejection, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    print(f"unix-request CPU controls=10; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"unix-request-{mode} cases={runner.count} evidence={runner.directory}")
