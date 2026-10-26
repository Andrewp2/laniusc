"""Independent filesystem/errno/attempt oracle for two Lanius primitives."""
import importlib.util
import json
import os
from pathlib import Path
import select
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import time
import traceback

SOURCE = Path(__file__).resolve().parents[1] / "temp_file/ledger.py"
SPEC = importlib.util.spec_from_file_location("directory_at_verified_ledger", SOURCE)
LEDGER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LEDGER)
MAGIC = 1145655857
MAX = (1 << 64) - 1
SENTINEL = b"namespace-sentinel\0\xff"


def read_exact(stream, count, path):
    result = bytearray()
    deadline = time.monotonic() + 12
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], ("report timeout", len(result))
        chunk = os.read(stream.fileno(), count - len(result))
        assert chunk, ("premature report EOF", len(result), count)
        result.extend(chunk)
        path.write_bytes(result)
    return bytes(result)


def snapshot(root):
    result = {}
    for current, directories, files in os.walk(os.fsencode(root), followlinks=False):
        for name in directories + files:
            path = os.path.join(current, name)
            value = os.lstat(path)
            item = dict(kind=stat.S_IFMT(value.st_mode), mode=stat.S_IMODE(value.st_mode), size=value.st_size)
            if stat.S_ISLNK(value.st_mode):
                item["target"] = os.readlink(path).hex()
            elif stat.S_ISREG(value.st_mode):
                item["contents"] = Path(os.fsdecode(path)).read_bytes().hex()
            result[os.path.relpath(path, os.fsencode(root)).hex()] = item
    return result


def prefix(trace, packet):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        lines = trace.read_text().splitlines(keepends=True) if trace.exists() else []
        for index, line in enumerate(lines):
            if not line.endswith("\n"):
                continue
            match = LEDGER.LINE.fullmatch(line.rstrip("\n"))
            if match and match[2] == "write" and match[4] == "64":
                args = LEDGER.arguments(match[3])
                if len(args) == 3 and args[0] == "1" and args[2] == "64" and LEDGER.quoted(args[1]) == packet:
                    return "".join(lines[:index + 1])
        time.sleep(0.005)
    raise AssertionError("report was not published as completed native bytes")


def report(packet, phase, operation, mode):
    words = struct.unpack("<8Q", packet)
    assert words[0] == MAGIC and words[1] == phase and words[6:] == (operation, mode), words
    assert words[2] > 0 and words[3] >= 3 and words[4] in (words[3], MAX), words
    return words


def calls(result, operation, path, mode, target_fd, expected):
    entries = result["events"]
    mutation = [entry for entry in entries if entry["name"] in ("mkdirat", "unlinkat")]
    scopes = [item for item in result["epochs"] if item["phase"] == "C"]
    assert len(scopes) == 1 and len(mutation) == expected, (mutation, scopes)
    body = scopes[0]["events"]
    assert body == mutation, ("primitive did extra native work or mutation escaped its frame", body, mutation)
    if not mutation:
        return None
    item = mutation[0]
    assert item["name"] == ("mkdirat" if operation == 0 else "unlinkat")
    args = LEDGER.arguments(item["args"])
    assert len(args) == 3 and args[0] == str(target_fd) and LEDGER.quoted(args[1]) == path, item
    if operation == 0:
        assert int(args[2], 8) == mode, item
    else:
        assert args[2] == "AT_REMOVEDIR", item
    return item


class Suite:
    def __init__(self, group, executable):
        self.group, self.executable = group, Path(executable).resolve()
        assert self.executable.is_file()
        self.directory = Path(tempfile.mkdtemp(prefix="directory-at-" + group + "-"))
        self.profile = LEDGER.verified_sites(self.executable, self.directory)
        self.started, self.count = time.monotonic(), 0

    def case(self, label, operation, *, path=b"child", mode=0o700, view=0, parent=0,
             code=0, native=1, setup=None, check=None, inject=None, baseline=None):
        assert time.monotonic() - self.started < 65, "finite oracle group exceeded 65 seconds"
        directory = self.directory / ("%02d-" % self.count + label)
        self.count += 1
        directory.mkdir()
        cwd = directory / "cwd"
        cwd.mkdir()
        (cwd / "anchor").mkdir()
        (cwd / "elsewhere").mkdir()
        (cwd / "anchor/sentinel").write_bytes(SENTINEL)
        (cwd / "regular").write_bytes(SENTINEL)
        if setup:
            setup(cwd)
        actual_path = path(cwd) if callable(path) else path
        assert len(actual_path) <= 4096
        request = struct.pack("<5Q", operation, mode, len(actual_path), view, parent) + actual_path.ljust(4096, b"\0")
        (directory / "request.bin").write_bytes(request)
        trace = directory / "syscalls.log"
        cmd = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "8192", "-e", "signal=none",
               "-e", "trace=" + LEDGER.TRACE, "-o", str(trace)]
        if inject:
            value = inject["syscall"] + (":error=" + inject["error"] if "error" in inject else ":retval=" + str(inject["retval"]))
            cmd += ["-e", "inject=" + value + ":when=" + str(inject["when"])]
        cmd.append(str(self.executable))
        (directory / "command.json").write_text(json.dumps(cmd, indent=2) + "\n")
        process, stderr = None, b""
        try:
            process = subprocess.Popen(cmd, cwd=cwd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE, bufsize=0, umask=0o022)
            process.stdin.write(request)
            ready_packet = read_exact(process.stdout, 64, directory / "ready.bin")
            ready = report(ready_packet, 0, operation, mode)
            assert ready[5] == 0
            ready_text = prefix(trace, ready_packet)
            (directory / "ready.trace").write_text(ready_text)
            entries, epochs = LEDGER.events(ready_text)
            assert not epochs and not any(e["name"] in ("mkdirat", "unlinkat") for e in entries)
            opened = [e for e in entries if e["name"] == "openat"]
            assert len(opened) == 1 and opened[0]["result"] == str(ready[3])
            children = Path("/proc/%d/task/%d/children" % (process.pid, process.pid)).read_text().split()
            assert children == [str(ready[2])], (children, ready)
            actual_fds = sorted(int(fd) for fd in os.listdir("/proc/%d/fd" % ready[2]))
            assert actual_fds == [0, 1, 2, ready[3]], actual_fds
            original = cwd / ("regular" if parent == 2 else "anchor")
            owner_stat = os.stat("/proc/%d/fd/%d" % (ready[2], ready[3]))
            wanted = original.stat()
            assert (owner_stat.st_dev, owner_stat.st_ino) == (wanted.st_dev, wanted.st_ino)
            if parent == 3:
                (cwd / "anchor").rename(cwd / "moved")
                (cwd / "anchor").mkdir()
                held = os.stat("/proc/%d/fd/%d" % (ready[2], ready[3]))
                assert (held.st_dev, held.st_ino) == (wanted.st_dev, wanted.st_ino), "renamed anchor owner changed"
            before = snapshot(cwd)
            process.stdin.write(b"!")
            result_packet = read_exact(process.stdout, 64, directory / "result.bin")
            words = report(result_packet, 1, operation, mode)
            assert words[:1] + words[2:5] + words[6:] == ready[:1] + ready[2:5] + ready[6:], (ready, words)
            assert words[5] == code, ("typed result", words[5], code)
            text = prefix(trace, result_packet)
            (directory / "pre-exit.trace").write_text(text)
            result = LEDGER.analyze(text, self.profile, directory)
            assert not result["source"]["allocations"], "directory primitive allocated source backing"
            descriptors = sorted(os.listdir("/proc/%d/fd" % words[2]))
            (directory / "pre-exit-fds.json").write_text(json.dumps(descriptors) + "\n")
            assert descriptors == ["0", "1", "2"], descriptors
            target_fd = -1 if words[4] == MAX else words[4]
            event = calls(result, operation, actual_path, mode, target_fd, native)
            LEDGER.check_injections(result, [inject] if inject else [])
            if baseline:
                prior = baseline["event"]
                assert event and (event["ip"], event["ordinal"], event["phase"], event["args"]) == (prior["ip"], prior["ordinal"], prior["phase"], prior["args"]), (prior, event)
            if code or inject:
                assert snapshot(cwd) == before, "rejected/skipped call changed namespace or contents"
            if parent == 3:
                assert len([e for e in result["events"] if e["name"] == "chdir" and e["result"] == "0"]) == 1
                assert list((cwd / "anchor").iterdir()) == list((cwd / "elsewhere").iterdir()) == [], "operation used replaced pathname or changed cwd"
            anchor = cwd / ("moved" if parent == 3 else "anchor")
            assert (anchor / "sentinel").read_bytes() == (cwd / "regular").read_bytes() == SENTINEL
            if check:
                check(cwd)
            (directory / "filesystem.json").write_text(json.dumps(snapshot(cwd), indent=2) + "\n")
            process.stdin.write(b"!")
            process.stdin.close()
            process.stdin = None
            extra, stderr = process.communicate(timeout=3)
            (directory / "native.stderr").write_bytes(stderr)
            (directory / "exit-status.txt").write_text(str(process.returncode) + "\n")
            assert process.returncode == 0 and not extra and stderr == result["markers"], (process.returncode, extra, stderr)
            final = LEDGER.analyze(trace.read_text(), self.profile, directory)
            LEDGER.check_injections(final, [inject] if inject else [])
            assert len(final["events"]) == len(result["events"]) + 1 and final["markers"] == stderr
            last = final["events"][-1]
            assert last["name"] == "read" and last["args"] == '0, "\\x21", 1' and last["result"] == "1", last
            return dict(event=event, words=words)
        except BaseException:
            diagnostic = traceback.format_exc()
            if process is not None:
                previous = process.poll()
                if previous is None:
                    process.kill()
                try:
                    extra, captured = process.communicate(timeout=3)
                    stderr += captured
                    (directory / "post-failure.stdout").write_bytes(extra)
                except BaseException as error:
                    diagnostic += "\ncollection failed: " + repr(error)
                diagnostic += "\nstatus before recovery=%r final=%r\n" % (previous, process.returncode)
            (directory / "native.stderr").write_bytes(stderr)
            (directory / "diagnostic.txt").write_text(diagnostic)
            (directory / "filesystem.json").write_text(json.dumps(snapshot(cwd), indent=2) + "\n")
            print("directory-at failure evidence: " + str(directory), file=sys.stderr)
            raise

    def done(self):
        # Only successful test-artifact cleanup; this is never a library effect.
        for root, directories, _ in os.walk(self.directory):
            for name in directories:
                path = Path(root) / name
                if not path.is_symlink():
                    path.chmod(0o700)
        shutil.rmtree(self.directory)
        print("directory-at group=%s cases=%d" % (self.group, self.count))


def made(path, permissions=None):
    def check(cwd):
        value = path(cwd) if callable(path) else cwd / "anchor" / path
        info = value.lstat()
        assert stat.S_ISDIR(info.st_mode) and not value.is_symlink()
        if permissions is not None:
            assert stat.S_IMODE(info.st_mode) == permissions, info
    return check


def absent(path):
    def check(cwd):
        value = path(cwd) if callable(path) else cwd / "anchor" / path
        assert not os.path.lexists(value), value
    return check


def namespace(suite):
    suite.case("create-private", 0, check=made("child", 0o700))
    suite.case("create-umask", 0, mode=0o777, check=made("child", 0o755))
    suite.case("create-nested", 0, path=b"nested/child", setup=lambda c: (c / "anchor/nested").mkdir(), check=made("nested/child", 0o700))
    raw = b"\xffdir"
    suite.case("create-raw", 0, path=raw, check=lambda c: made(lambda c: Path(os.fsdecode(os.fsencode(c / 'anchor') + b'/' + raw)), 0o700)(c))
    for kind in ("directory", "file", "dangling", "symlink-directory"):
        def setup(cwd, kind=kind):
            leaf = cwd / "anchor/child"
            if kind == "directory": leaf.mkdir()
            if kind == "file": leaf.write_bytes(SENTINEL)
            if kind == "dangling": os.symlink("missing", leaf)
            if kind == "symlink-directory":
                (cwd / "anchor/real-directory").mkdir()
                os.symlink("real-directory", leaf)
        suite.case("create-existing-" + kind, 0, setup=setup, code=17)
    suite.case("create-missing-parent", 0, path=b"missing/child", code=2)
    suite.case("create-bad-dirfd", 0, parent=1, code=9)
    suite.case("create-regular-dirfd", 0, parent=2, code=20)
    suite.case("create-absolute-ignores-bad-fd", 0, parent=1,
               path=lambda c: os.fsencode(c / "anchor/child"), check=made("child", 0o700))
    suite.case("create-renamed-anchor-cwd", 0, parent=3, check=made(lambda c: c / "moved/child", 0o700))
    suite.case("remove-empty", 1, setup=lambda c: (c / "anchor/child").mkdir(), check=absent("child"))
    def nested(cwd):
        (cwd / "anchor/nested").mkdir()
        os.mkdir(os.fsencode(cwd / "anchor/nested") + b"/" + raw)
    suite.case("remove-raw-nested", 1, path=b"nested/" + raw, setup=nested,
               check=absent(lambda c: Path(os.fsdecode(os.fsencode(c / 'anchor/nested') + b'/' + raw))))
    suite.case("remove-missing", 1, code=2)
    suite.case("remove-regular-file", 1, setup=lambda c: (c / "anchor/child").write_bytes(SENTINEL), code=20)
    suite.case("remove-dangling-symlink", 1, setup=lambda c: os.symlink("missing", c / "anchor/child"), code=20)
    def symlink(cwd):
        (cwd / "anchor/real-directory").mkdir()
        os.symlink("real-directory", cwd / "anchor/child")
    suite.case("remove-symlink-directory", 1, setup=symlink, code=20)
    def nonempty(cwd):
        (cwd / "anchor/child").mkdir()
        (cwd / "anchor/child/data").write_bytes(SENTINEL)
    suite.case("remove-nonempty", 1, setup=nonempty, code=39)
    suite.case("remove-bad-dirfd", 1, parent=1, code=9)
    suite.case("remove-regular-dirfd", 1, parent=2, code=20)
    suite.case("remove-absolute-ignores-bad-fd", 1, parent=1, path=lambda c: os.fsencode(c / "anchor/child"),
               setup=lambda c: (c / "anchor/child").mkdir(), check=absent("child"))
    suite.case("remove-renamed-anchor-cwd", 1, parent=3, setup=lambda c: (c / "anchor/child").mkdir(),
               check=absent(lambda c: c / "moved/child"))


def bounds(suite):
    for operation in (0, 1):
        for view in (1, 2, 3):
            suite.case("view-%d-%d" % (operation, view), operation, view=view, code=200, native=0)
        suite.case("nul-%d" % operation, operation, path=b"a\0b", code=200, native=0)
        suite.case("path-4096-%d" % operation, operation, path=b"x" * 4096, code=36, native=0)
        suite.case("path-4095-native-%d" % operation, operation, path=b"x" * 4095, code=36)
        suite.case("empty-native-%d" % operation, operation, path=b"", code=2)
    for mode in (4096, 4294967295):
        suite.case("mode-%d" % mode, 0, mode=mode, code=200, native=0)
    suite.case("mode-before-path", 0, mode=4096, path=b"x" * 4096, code=200, native=0)
    suite.case("mode-max-native", 0, mode=4095, check=made("child"))
    suite.case("mode-zero-native", 0, mode=0, check=made("child", 0))


def faults(suite):
    for operation in (0, 1):
        setup = (lambda c: (c / "anchor/child").mkdir()) if operation else None
        check = absent("child") if operation else made("child", 0o700)
        baseline = suite.case("baseline-%d" % operation, operation, setup=setup, check=check)
        target = baseline["event"]
        for error, code in (("EIO", 5), ("EINTR", 4), ("EAGAIN", 11), ("ENOSYS", 38), (None, 201)):
            inject = dict(syscall=target["name"], when=target["ordinal"], repeat=False)
            inject.update(error=error) if error else inject.update(retval=1)
            suite.case("fault-%d-%s" % (operation, error or "invalid-count"), operation,
                       setup=setup, code=code, inject=inject, baseline=baseline)


def controls():
    count = 0
    def event(name, args, result="0"):
        return '[0000000000401002] %s(%s) = %s\n' % (name, args, result)
    def marker(token):
        return event("write", '2, "\\x%02x", 1' % ord(token), "1")
    valid = marker("C") + event("mkdirat", '3, "\\x63", 0700') + marker("c")
    def parsed(text):
        entries, epochs = LEDGER.events(text)
        return dict(events=entries, epochs=epochs)
    assert calls(parsed(valid), 0, b"c", 0o700, 3, 1)["name"] == "mkdirat"
    count += 1
    empty = marker("C") + marker("c")
    assert calls(parsed(empty), 0, b"c", 0o700, 3, 0) is None
    count += 1
    removed = marker("C") + event("unlinkat", '3, "\\x63", AT_REMOVEDIR') + marker("c")
    assert calls(parsed(removed), 1, b"c", 0o700, 3, 1)["name"] == "unlinkat"
    count += 1
    for text, operation in ((valid.replace('mkdirat(3,', 'mkdirat(4,'), 0),
                            (valid.replace('\\x63', '\\x64'), 0),
                            (valid.replace('0700', '0777'), 0),
                            (valid.replace(marker('c'), event('mkdirat', '3, "\\x63", 0700') + marker('c')), 0),
                            (valid + event('unlinkat', '3, "\\x63", AT_REMOVEDIR'), 0),
                            (removed.replace('AT_REMOVEDIR', '0'), 1)):
        try:
            calls(parsed(text), operation, b"c", 0o700, 3, 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("directory oracle accepted incorrect primitive arguments/attempts")
    packet = struct.pack('<8Q', MAGIC, 1, 999, 3, 3, 0, 0, 448)
    assert report(packet, 1, 0, 448)[5] == 0
    count += 1
    for index, value in ((0, 0), (1, 0), (6, 1), (7, 4096)):
        words = list(struct.unpack('<8Q', packet))
        words[index] = value
        try:
            report(struct.pack('<8Q', *words), 1, 0, 448)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("directory oracle accepted incorrect response identity")
    print("directory-at oracle CPU-controls=%d native-cases=0" % count)


def main():
    assert len(sys.argv) >= 2
    group = sys.argv[1]
    if group == "controls":
        assert len(sys.argv) == 2
        controls()
        return
    assert group in ("namespace", "bounds", "faults") and len(sys.argv) == 3
    suite = Suite(group, sys.argv[2])
    globals()[group](suite)
    suite.done()


if __name__ == "__main__":
    main()
