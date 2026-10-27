"""Pre-exit URL ownership and reached constructor OOM, using trusted raw sites.

No new ELF/opcode scanner or source allocation classifier lives here. The
current shared verifier binds both 0x22/0x62 profiles and full-width pointers.
"""
import importlib.util
import os
from pathlib import Path
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
SOURCE = load("http_url_source_ledger", HERE.parent / "archive_source/ledger.py")
MODEL = load("http_url_fixed_catalog", HERE / "model.py")
MAGIC = 0x55524F
ALLOWED = {"read", "write", "getpid", "mmap", "munmap"}


def main_trace(text, *, terminal=False):
    """Admit a full trace, dropping only the checked launch and final raw exit."""
    lines = text.splitlines()
    assert text.endswith("\n") and lines, "incomplete URL owner trace"
    kept = []
    for index, line in enumerate(lines):
        match = SOURCE.TRUSTED.LINE.fullmatch(line)
        assert match, ("unknown full-trace line", line)
        _, name, args, result = match.groups()
        if index == 0:
            assert name == "execve" and result == "0", ("unsuccessful native launch", line)
        elif name == "exit":
            assert terminal and index == len(lines) - 1 and args == "0" and result == "?", line
        else:
            assert name in ALLOWED, ("URL planning performed unexpected host work", line)
            if name in ("read", "write"):
                arguments = SOURCE.TRUSTED.arguments(args)
                assert arguments[0] == ("0" if name == "read" else "1"), line
            kept.append(line + "\n")
    if terminal:
        assert SOURCE.TRUSTED.LINE.fullmatch(lines[-1])[2] == "exit", "missing raw exit"
    return "".join(kept)


def binding(item):
    return item["ip"], item["args"], item["ordinal"]


def bound_failure(actual, baseline, ordinal):
    assert 1 <= len(actual) <= len(baseline), (actual, baseline)
    assert all(binding(now) == binding(old) for now, old in zip(actual, baseline)), (actual, baseline)
    target = actual[-1]
    assert target["ordinal"] == ordinal and target["result"].split()[:2] == ["-1", "ENOMEM"] and "INJECTED" in target["result"], target


def exact_read(fd, count, deadline):
    data = bytearray()
    while len(data) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([fd], [], [], remaining)[0], ("owner frame timeout", len(data), count)
        block = os.read(fd, count - len(data))
        assert block, ("owner frame truncated", len(data), count)
        data.extend(block)
    return bytes(data)


def exact_write(fd, data, deadline):
    at = 0
    while at < len(data):
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([], [fd], [], remaining)[1], "owner ACK timeout"
        count = os.write(fd, data[at:])
        assert count > 0
        at += count


def frame(fd, deadline):
    prefix = exact_read(fd, 8, deadline)
    count, = struct.unpack("<Q", prefix)
    assert 24 <= count <= 2048, ("owner frame size", count)
    body = exact_read(fd, count, deadline)
    return body, prefix + body


def checkpoint(trace, emitted, deadline):
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), bytes(emitted))
        except (SOURCE.CheckpointPending, FileNotFoundError):
            assert time.monotonic() < deadline, "owner trace checkpoint timeout"
            time.sleep(0.002)


def components(case):
    assert struct.unpack_from("<2Q", case.answer) == (MODEL.MAGIC, 0)
    at, result = 40, []
    for _ in range(3):
        count, = struct.unpack_from("<Q", case.answer, at)
        at += 8
        result.append(case.answer[at:at + count])
        at += count
    return tuple(result)


def parse_first(body):
    assert len(body) >= 104
    values = struct.unpack_from("<13Q", body)
    assert values[:2] == (MAGIC, 1) and values[2] > 0
    _, _, pid, failed, kind, offset, layout, stride, start, length, host, authority, target = values
    offset = offset if offset < (1 << 63) else offset - (1 << 64)
    stride = stride if stride < (1 << 63) else stride - (1 << 64)
    assert failed in (0, 1) and len(body) == 104 + host + authority + target
    texts, at = [], 104
    for count in (host, authority, target):
        texts.append(body[at:at + count])
        at += count
    return dict(pid=pid, failed=failed, kind=kind, offset=offset, layout=layout,
                stride=stride, start=start, length=length, texts=tuple(texts))


class Suite:
    def __init__(self, executable):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="lanius-http-url-owners-"))
        self.profile = SOURCE.TRUSTED.verified_sites(self.executable, self.directory)
        self.deadline = time.monotonic() + 65
        self.count = self.oom = 0
        print(f"evidence={self.directory}", flush=True)

    def case(self, label, case, layout=0, *, denied=False, injection=None, baseline=None):
        assert time.monotonic() < self.deadline, "URL owner group deadline"
        directory = self.directory / f"{self.count:03d}-{label}"
        directory.mkdir()
        trace = directory / "native.trace"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
                   "-o", str(trace), "-e", "trace=all"]
        assert not (denied and injection is not None)
        if denied:
            command += ["-e", "inject=mmap:error=ENOMEM:when=1+"]
        if injection is not None:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={injection}"]
        command.append(str(self.executable))
        request = MODEL.packet(case, layout)
        (directory / "request.bin").write_bytes(request)
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, cwd=directory)
        deadline = min(self.deadline, time.monotonic() + 7)
        emitted = bytearray()
        try:
            exact_write(process.stdin.fileno(), request, deadline)
            body, raw = frame(process.stdout.fileno(), deadline)
            emitted.extend(raw)
            result = parse_first(body)
            assert result["layout"] == layout and result["length"] == len(case.raw) and result["start"] == 3, result
            assert (result["stride"] < 0) if layout == 0 else (result["stride"] == 1), result
            if injection is not None:
                assert (result["failed"], result["kind"], result["offset"], result["texts"]) == (1, 10, -1, (b"", b"", b"")), result
            elif struct.unpack_from("<Q", case.answer, 8)[0] == 1:
                _, _, kind, offset, _ = struct.unpack_from("<5Q", case.answer)
                offset = offset if offset < (1 << 63) else offset - (1 << 64)
                assert (result["failed"], result["kind"], result["offset"], result["texts"]) == (1, kind, offset, (b"", b"", b"")), result
            else:
                assert (result["failed"], result["kind"], result["offset"]) == (0, 0, 0), result
                assert result["texts"] == components(case), (result, components(case))
            prefix = main_trace(checkpoint(trace, emitted, deadline))
            admitted = SOURCE.source(prefix, self.profile)
            SOURCE.process_owners(result["pid"], admitted["live"])
            if result["failed"]:
                assert not admitted["live"], ("partial constructor owner escaped failure", admitted)
            else:
                assert admitted["live"] and sum(admitted["live"].values()) >= len(case.raw) + len(result["texts"][2]), admitted
            if denied:
                assert not admitted["attempts"], ("preflight attempted allocation", admitted)
            if injection is not None:
                reached = [item for item in admitted["events"] if "INJECTED" in item["result"]]
                assert len(reached) == 1 and reached[0]["name"] == "mmap" and reached[0]["ordinal"] == injection, reached
                bound_failure(admitted["attempts"], baseline, injection)
            exact_write(process.stdin.fileno(), b"A", deadline)
            released, raw = frame(process.stdout.fileno(), deadline)
            emitted.extend(raw)
            assert released == MODEL.W(MAGIC, 2, result["pid"]), released
            final_prefix = main_trace(checkpoint(trace, emitted, deadline))
            final = SOURCE.source(final_prefix, self.profile)
            assert not final["live"], ("URL owner survived explicit destroy", final)
            # Getters and both destroy calls must issue no new allocation.
            assert len(final["attempts"]) == len(admitted["attempts"]), (admitted, final)
            ranges = SOURCE.process_owners(result["pid"], {})
            for pointer, length in admitted["live"].items():
                assert not any(start < pointer + length and pointer < end for start, end in ranges), (pointer, length, ranges)
            SOURCE.TRUSTED.source_maps(final_prefix, self.profile, directory)
            exact_write(process.stdin.fileno(), b"A", deadline)
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            assert process.returncode == 0 and not rest and not stderr, (process.returncode, rest, stderr)
            complete = main_trace(trace.read_text(), terminal=True)
            final = SOURCE.source(complete, self.profile)
            assert not final["live"] and len(final["attempts"]) == len(admitted["attempts"]), final
            (directory / "stdout.bin").write_bytes(emitted)
            (directory / "stderr.bin").write_bytes(stderr)
            self.count += 1
            self.oom += injection is not None
            return admitted["attempts"]
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(emitted)
            if process.poll() is None:
                process.kill()
            try:
                tail, stderr = process.communicate(timeout=2)
                (directory / "stdout-tail.bin").write_bytes(tail)
                (directory / "stderr.bin").write_bytes(stderr)
            except (ValueError, subprocess.TimeoutExpired):
                pass
            print(f"FAILED label={label} evidence={directory}", file=sys.stderr, flush=True)
            raise


def controls():
    count = SOURCE.controls()
    initial = '[0000000000000000] execve("\\x61", [], []) = 0\n'
    read = '[0000000000401000] read(0, "\\x41", 1) = 1\n'
    end = '[0000000000401010] exit(0) = ?\n'
    assert main_trace(initial + read) == read and main_trace(initial + read + end, terminal=True) == read
    count += 1
    for bad_trace in (initial + initial + read,
                      initial + read.replace("read(0", "read(2"),
                      initial + read.replace("read(0", "socket(0"),
                      initial + read + end.replace("exit(0)", "exit(1)")):
        try:
            main_trace(bad_trace, terminal="exit(" in bad_trace)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("full-trace guard accepted forbidden work")
    old = dict(ip=0x401002, args="NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0", ordinal=1, result="0x7fff10000000")
    failed = dict(old, result="-1 ENOMEM (Cannot allocate memory) (INJECTED)")
    bound_failure([failed], [old], 1)
    count += 1
    for mutation in (dict(failed, ip=0x401003), dict(failed, ordinal=2), dict(failed, args=failed["args"].replace("37", "38")), dict(failed, result="-1 ENOMEM (Cannot allocate memory)")):
        try:
            bound_failure([mutation], [old], 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("OOM binding accepted a changed/missing reached allocation")
    print(f"http-url owner CPU controls={count}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 2, "owners.py EXECUTABLE | controls"
    suite = Suite(sys.argv[1])
    cases = {case.name: case for case in MODEL.CASES}
    for label, layout in (("literal-path", 0), ("ipv6", 1)):
        case = cases[label]
        baseline = suite.case(label, case, layout)
        assert baseline, "successful URL constructor made no source reservation"
        for index, target in enumerate(baseline):
            suite.case(f"{label}-oom-{index}", case, layout,
                       injection=target["ordinal"], baseline=baseline)
    for label in ("bounds-negative-start", "zero-url-cap", "url-cap-below", "unsupported-scheme", "missing-authority",
                  "empty-userinfo", "legacy-whole-hex", "port-overflow", "target-cap-below", "syntax-before-scheme"):
        suite.case(label, cases[label], denied=True)
    print(f"http-url owners cases={suite.count} reached-oom={suite.oom}")


if __name__ == "__main__":
    main()
