"""Finite connector admission/fallback/cleanup gates, using shared authority.

No resolver or connector implementation lives here. The existing C observer
supplies ordered backed native results; real loopback sockets establish effects.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SOURCE = load("url_connector_live_source", HERE.parent / "archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
NATIVE = load("url_connector_native_authority", HERE.parents[1] / "native_c/source_allocations.py")
U64, MAGIC, FRAME = (1 << 64) - 1, 1431456845, 320
LEAVES = {"socket", "connect", "poll", "getsockopt", "getpeername", "close"}
PHASES = {"U": "u", "C": "c", "D": "d", "Q": "q"}


def quoted(value):
    return '"' + "".join("\\x%02x" % byte for byte in os.fsencode(value)) + '"'


def entries(text):
    values, counts = [], Counter()
    for line in SOURCE.completed(text).splitlines():
        match = TRUSTED.LINE.fullmatch(line)
        assert match, ("unsupported full trace line", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        values.append(dict(ip=int(ip, 16), name=name, args=args, result=result,
                           line=line, ordinal=counts[name], index=len(values)))
    return values


def endpoints(values, profile, executable, final):
    assert values and values[0]["name"] == "execve" and values[0]["result"] == "0", values[:1]
    assert values[0]["args"].startswith(quoted(Path(executable).resolve()) + ", ["), values[0]
    assert sum(item["name"] == "execve" for item in values) == 1
    assert NATIVE.classify(profile, values[0]["ip"]) == "native"
    ends = [item for item in values if item["name"] in ("exit", "exit_group")]
    if final:
        assert ends == [values[-1]] and ends[0]["args"] == "0" and ends[0]["result"] == "?", ends
        assert NATIVE.classify(profile, ends[0]["ip"]) in ("native", "entry-exit")
    else:
        assert not ends, ("exit before ACK checkpoint", ends)


def memory(values):
    return "".join(item["line"] + "\n" for item in values if item["name"] in ("mmap", "munmap"))


def phase_admission(item):
    name, phase, args = item["name"], item["phase"], item["args"]
    if "marker" in item:
        return
    if phase is None:
        if name == "getpid":
            assert args == "" and item["result"].isdecimal() and int(item["result"]) > 0, item
        else:
            assert name in ("read", "write"), ("source effect outside fixture action", item)
            fields = TRUSTED.arguments(args)
            assert fields[0] == ("0" if name == "read" else "1"), item
            assert 0 < int(item["result"]) <= int(fields[-1]) <= 1024, item
        return
    allowed = {"U": {"mmap", "munmap", "clock_gettime"},
               "C": LEAVES | {"mmap", "munmap", "clock_gettime"},
               "D": {"munmap", "close"}, "Q": {"close"}}
    assert name in allowed[phase], ("source syscall not authorized in phase", item)
    if name == "clock_gettime":
        assert args.startswith("CLOCK_MONOTONIC, "), item


def fd(item):
    if item["name"] == "poll":
        found = re.fullmatch(r"\[\{fd=(\d+), events=POLLOUT\}\], 1, (\d+)", item["args"])
        assert found and 0 < int(found[2]) <= 2147483647, item
        return int(found[1])
    return int(item["args"].split(",", 1)[0])


def analyze(text, profile, executable, *, final=False, injection=None):
    values = entries(text)
    endpoints(values, profile, executable, final)
    found, markers, phase = [], bytearray(), None
    for item in values:
        authority = NATIVE.classify(profile, item["ip"])
        item["authority"] = authority
        if authority != "source":
            if authority.startswith("bootstrap-"):
                assert item["name"] == ("mmap" if authority == "bootstrap-mmap" else "munmap"), item
            elif authority == "entry-exit":
                assert item["name"] == "exit", item
            continue
        item["phase"] = phase
        token = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', item["args"]) if item["name"] == "write" and item["result"] == "1" else None
        if token:
            token = chr(int(token[1], 16))
            assert token in set(PHASES) | set(PHASES.values()), item
            if token in PHASES:
                assert phase is None, ("overlapping fixture phase", item)
                phase = token
            else:
                assert phase is not None and PHASES[phase] == token, ("unmatched fixture phase", item)
                phase = None
            item["marker"] = token
            markers.extend(token.encode())
        phase_admission(item)
        found.append(item)
    assert phase is None, "unfinished fixture phase"
    live, generations, opened, failed_closes = {}, Counter(), [], []
    for item in found:
        name, answer = item["name"], item["result"].split()[0]
        if name == "socket":
            assert item["phase"] == "C" and item["args"] == "AF_INET, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, IPPROTO_IP", item
            if answer.isdecimal():
                number = int(answer)
                assert number > 2 and number not in live and not live, ("more than one owned socket", item, live)
                generations[number] += 1
                owner = dict(fd=number, generation=generations[number], opened=item, failed=None)
                live[number] = owner
                opened.append(owner)
        elif name in LEAVES - {"socket"}:
            number = fd(item)
            assert number in live and number > 2, ("unowned/protocol socket use", item, live)
            owner = live[number]
            item["generation"] = owner["generation"]
            if name == "close":
                if answer == "0":
                    if owner["failed"] is not None:
                        assert item["phase"] == "Q", ("production retried skipped close", item)
                        owner["failed"]["repair"] = item
                    else:
                        assert item["phase"] != "Q", ("repair without reached failed close", item)
                    del live[number]
                else:
                    assert injection == ("close", item["ordinal"]) and "INJECTED" in item["result"], item
                    assert item["phase"] == "C" and "EIO" in item["result"] and owner["failed"] is None, item
                    failed = dict(event=item, owner=owner, repair=None)
                    owner["failed"] = failed
                    failed_closes.append(failed)
            else:
                assert item["phase"] == "C" and owner["failed"] is None, ("use after logical retirement", item)
    if final:
        assert not live and all(item["repair"] is not None for item in failed_closes), (live, failed_closes)
    source = SOURCE.source(memory(values), profile)
    if final:
        assert not source["live"], ("source owner survives final cleanup", source)
    return dict(events=values, source_events=found, source=source, markers=bytes(markers), live=live,
                opened=opened, failed_closes=failed_closes)


def calls(result):
    return [item for item in result["source_events"] if item["phase"] == "C" and item["name"] in LEAVES]


def check_stats(words, result, cap):
    issued = calls(result)
    assert words[9] == len(issued) <= cap, ("physical connector call count", words, issued)
    assert words[8] == sum(item["name"] == "socket" for item in issued), (words, issued)
    assert words[10] == sum(item["name"] == "poll" for item in issued), (words, issued)
    if words[8] == 0:
        assert words[11] == U64 and words[12] == 0, ("unattempted endpoint published", words)


def checkpoint(trace, output, deadline):
    while True:
        try:
            return SOURCE.output_prefix(trace.read_text(), output)
        except (FileNotFoundError, SOURCE.CheckpointPending):
            assert time.monotonic() < deadline, "trace checkpoint missing"
            time.sleep(0.003)


def exact_read(stream, count, deadline):
    output = bytearray()
    while len(output) < count:
        left = deadline - time.monotonic()
        assert left > 0 and select.select([stream], [], [], left)[0], ("native report timeout", len(output), count)
        part = os.read(stream.fileno(), count - len(output))
        assert part, ("premature native report EOF", len(output), count)
        output.extend(part)
    return bytes(output)


def process_owners(pid, result):
    actual = {int(path.name) for path in Path(f"/proc/{pid}/fd").iterdir()}
    assert actual == {0, 1, 2} | set(result["live"]), ("physical FD checkpoint", pid, actual, result["live"])
    ranges = [(int(line.split()[0].split("-")[0], 16), int(line.split()[0].split("-")[1], 16))
              for line in Path(f"/proc/{pid}/maps").read_text().splitlines()]
    for pointer, length in result["source"]["live"].items():
        assert any(low <= pointer and pointer + length <= high for low, high in ranges), (pointer, length)
    return ranges


class Suite:
    def __init__(self, executable, observer, group):
        self.executable, self.observer = Path(executable).resolve(), Path(observer).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="url-connector-" + group + "-"))
        self.profile = NATIVE.verified_sites(self.executable, self.directory)
        self.count, self.deadline = 0, time.monotonic() + 65
        print("evidence=" + str(self.directory), flush=True)

    def run(self, label, url, *, selected=0, family=0, results=32, attempts=16, cap=512,
            seconds=1, nanos=0, observer_mode=None, ordered=False, injection=None, listener=None):
        self.count += 1
        directory = self.directory / ("%02d-" % self.count + label)
        directory.mkdir()
        trace, native = directory / "syscalls.log", directory / "resolver.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "65536", "-e", "signal=none", "-e", "trace=all", "-o", str(trace)]
        if injection:
            command += ["-e", "inject=close:error=EIO:when=%d" % injection[1]]
        command.append(str(self.executable))
        environment = dict(os.environ)
        for name in ("LD_PRELOAD", "LANIUS_URL_RESOLVE_SCRIPT", "LANIUS_RESOLVE_MODE", "LANIUS_RESOLVE_COUNT", "LANIUS_RESOLVE_TRACE"):
            environment.pop(name, None)
        if observer_mode is not None or ordered:
            environment.update(LD_PRELOAD=str(self.observer), LANIUS_RESOLVE_TRACE=str(native))
            if ordered:
                environment["LANIUS_URL_RESOLVE_SCRIPT"] = "ordered"
            else:
                environment["LANIUS_RESOLVE_MODE"] = str(observer_mode)
        data = struct.pack("<8Q", selected, family, results & U64, attempts & U64, cap, seconds, nanos, len(url)) + url
        (directory / "request.bin").write_bytes(data)
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment, bufsize=0)
        deadline, captured, frames, snapshots, known, peer = min(self.deadline, time.monotonic() + 10), bytearray(), [], [], set(), None
        try:
            process.stdin.write(data)
            for index in range(3):
                packet = exact_read(process.stdout, FRAME, deadline)
                captured.extend(packet)
                words = struct.unpack("<40Q", packet)
                assert words[:2] == (MAGIC, index) and words[39] == 0, words
                assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(words[2])]
                result = analyze(checkpoint(trace, bytes(captured), deadline), self.profile, self.executable, injection=injection)
                ranges = process_owners(words[2], result)
                known.update(result["source"]["live"])
                if index < 2:
                    assert result["source"]["live"], "URL backing not live through report"
                if index == 1:
                    check_stats(words, result, cap)
                    if words[3]:
                        assert set(result["live"]) == {words[33]} and listener is not None, words
                        listener.settimeout(2)
                        peer, _ = listener.accept()
                    elif not injection:
                        assert not result["live"], result["live"]
                if index == 2:
                    assert not result["live"] and not result["source"]["live"]
                    assert not any(any(low <= pointer < high for low, high in ranges) for pointer in known), "released source owner still mapped"
                    assert words[36:38] == (1, 0) and words[33] == U64, words
                    if peer:
                        peer.settimeout(2)
                        assert peer.recv(1) == b"", "successful Connection did not close before final ACK"
                frames.append(words)
                snapshots.append(result)
                process.stdin.write(b"+")
                if index == 1:
                    repair = U64
                    if injection:
                        assert len(result["failed_closes"]) == 1 and words[28] == 5, (words, result["failed_closes"])
                        repair = fd(result["failed_closes"][0]["event"])
                        assert set(result["live"]) == {repair}, result["live"]
                    process.stdin.write(struct.pack("<Q", repair))
            process.stdin.close()
            process.stdin = None
            tail, stderr = process.communicate(timeout=max(0.1, deadline - time.monotonic()))
            (directory / "stdout.bin").write_bytes(captured + tail)
            (directory / "stderr.bin").write_bytes(stderr)
            assert process.returncode == 0 and not tail, (directory, process.returncode, tail, stderr)
            full = analyze(trace.read_text(), self.profile, self.executable, final=True, injection=injection)
            assert stderr == full["markers"], (stderr, full["markers"])
            TRUSTED.source_maps(memory(full["events"]), self.profile, directory)
            return dict(words=frames[1], frames=frames, snapshots=snapshots, ledger=full, directory=directory,
                        native=native.read_text().splitlines() if native.exists() else [])
        except BaseException as error:
            if process.poll() is None:
                process.kill()
            if process.stdin is not None:
                process.stdin.close()
                process.stdin = None
            tail, stderr = process.communicate(timeout=3)
            (directory / "stdout-prefix.bin").write_bytes(captured)
            (directory / "remaining-stdout.bin").write_bytes(tail)
            (directory / "stderr.bin").write_bytes(stderr)
            (directory / "failure.txt").write_text(repr(error) + "\nreturncode=" + str(process.returncode) + "\n")
            raise
        finally:
            if peer:
                peer.close()


def preattempt(result, cause, stage):
    words = result["words"]
    assert words[3:6] == (0, stage, cause) and words[6] == words[8] == words[9] == words[10] == 0, words
    assert words[11] == U64 and words[12] == words[18] == words[28] == 0, words
    assert not result["native"] and not calls(result["ledger"])
    assert not [item for item in result["ledger"]["source_events"] if item["phase"] == "C" and item["name"] in ("mmap", "munmap")]


def admission(suite, port):
    numeric = f"http://127.0.0.1:{port}/".encode()
    preattempt(suite.run("expired", numeric, selected=1), 7, 3)
    preattempt(suite.run("time-overflow", numeric, selected=3), 201, 3)
    preattempt(suite.run("unnormalized-deadline", numeric, selected=2), 2, 1)
    for label, options in (("results-zero", dict(results=0)), ("results-large", dict(results=4097)),
                           ("attempts-zero", dict(attempts=0)), ("attempts-large", dict(attempts=4097)),
                           ("duration-zero", dict(seconds=0)), ("duration-nanos", dict(nanos=1000000000)),
                           ("calls-zero", dict(cap=0)), ("calls-one", dict(cap=1))):
        # A DNS spelling plus an armed observer makes accidental lookup visible.
        result = suite.run(label, f"http://url.example.test:{port}/".encode(), ordered=True, **options)
        preattempt(result, 6 if "cap" in options else 2, 1)
    preattempt(suite.run("numeric-family-mismatch", numeric, family=2), 3, 2)


def refused(result, attempts, cause):
    words = result["words"]
    assert words[3] == 0 and words[5] == cause and words[8] == attempts, words
    assert words[11] == attempts - 1 and words[12] == words[18] == 1 and words[19] == attempts - 1, words
    assert words[21:23] == (111, 0) and words[28] == 0, words
    assert len(result["ledger"]["opened"]) == attempts
    connect = [item for item in calls(result["ledger"]) if item["name"] == "connect"]
    assert len(connect) == attempts and all("INJECTED" not in item["result"] for item in connect), connect


def native_log(result, port, mode, ordered=False):
    expected = [f"G 1024 0 1 6 0 0 16 {len(str(port))} {mode}"]
    if ordered:
        expected += ["U url.example.test ordered4 loopback", "F"]
    assert result["native"] == expected, (result["native"], expected)


def bind_close(before, after, target):
    left, right = calls(before["ledger"]), calls(after["ledger"])
    assert len(left) == len(right) and target["ordinal"] == after["ledger"]["failed_closes"][0]["event"]["ordinal"]
    for prior, actual in zip(left, right):
        assert (prior["name"], prior["ip"], prior["phase"]) == (actual["name"], actual["ip"], actual["phase"])
        if prior["name"] == "socket":
            assert prior["args"] == actual["args"] and prior["result"] == actual["result"]
        else:
            assert (fd(prior), prior["generation"]) == (fd(actual), actual["generation"])
            if prior["name"] == "connect":
                assert prior["args"] == actual["args"]
    reached = after["ledger"]["failed_closes"][0]
    assert reached["event"]["ip"] == target["ip"] and reached["repair"]["phase"] == "Q"
    assert before["words"][6:28] == after["words"][6:28], "fault changed completed attempt metadata"


def failures(suite, port):
    numeric = f"http://127.0.0.2:{port}/".encode()
    baseline = suite.run("numeric-refusal-baseline", numeric)
    refused(baseline, 1, 4)
    assert baseline["words"][6:8] == (0, 1) and not baseline["native"]
    limited = suite.run("live-close-reservation", numeric, cap=2)
    assert limited["words"][4:11] == (4, 6, 0, 1, 1, 2, 0) and limited["words"][18] == 0, limited["words"]
    assert [item["name"] for item in calls(limited["ledger"])] == ["socket", "close"]
    dns = f"http://url.example.test:{port}/".encode()
    capped = suite.run("dns-attempt-cap", dns, ordered=True, attempts=1)
    refused(capped, 1, 5)
    native_log(capped, port, 1, True)
    assert capped["words"][6:8] == (1, 4)
    exhausted = suite.run("dns-exhausted", dns, ordered=True)
    refused(exhausted, 4, 4)
    native_log(exhausted, port, 1, True)
    addresses = []
    for item in calls(exhausted["ledger"]):
        if item["name"] == "connect":
            match = re.search(r'inet_addr\(("[^"\n]*")\)', item["args"])
            assert match, item
            # strace's inet_addr decoder may print ordinary address text even
            # with -xx; byte-string syscall arguments still require hex form.
            encoded = match[1]
            addresses.append(TRUSTED.quoted(encoded) if "\\x" in encoded else encoded[1:-1].encode("ascii"))
    assert addresses == [b"127.0.0.2", b"127.0.0.1", b"127.0.0.3", b"127.0.0.1"], addresses
    for mode, code, system in ((3, -11, 13), (4, -2, 0)):
        result = suite.run("eai-%d" % mode, dns, observer_mode=mode)
        words = result["words"]
        assert words[3:11] == (0, 2, 300, 1, 0, 0, 0, 0) and words[11] == U64 and words[12] == words[18] == words[28] == 0, words
        assert words[29:33] == (4, 11, code & U64, system), words
        native_log(result, port, mode)
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        selected = suite.run("numeric-success-close", f"http://127.0.0.1:{listener.getsockname()[1]}/".encode(), listener=listener)
        assert selected["words"][3:11][:2] == (1, 0) and selected["words"][6:9] == (0, 1, 1), selected["words"]
        assert selected["frames"][2][34:36] == (1, 0) and not selected["native"]
    target, = [item for item in calls(baseline["ledger"]) if item["name"] == "close"]
    failed = suite.run("reached-close-eio", numeric, injection=("close", target["ordinal"]))
    words = failed["words"]
    assert words[5] == 1111 and words[21] == 111 and words[28] == 5 and words[8] == 1, words
    bind_close(baseline, failed, target)


def controls():
    # Mutation controls exercise only this fixture's phase/FD/packet policy;
    # the shared byte/shape verifier has its own independent CPU controls.
    pairs = NATIVE.RuntimePairs([(0x401012, 0x401022)])
    pairs.mmap_flags = {0x401012: 0x22}
    pairs.executable_ranges = [(0x401000, 0x402000)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022, 0x401032, 0x401042, 0x401052}
    pairs.bootstrap_sites, pairs.image_ranges = {}, [(0x401000, 0x402000)]
    profile, executable = (pairs, []), Path("/tmp/connector-control")
    def line(body, ip=0x401002):
        return "[%016x] %s\n" % (ip, body)
    launch = line("execve(%s, [%s], NULL) = 0" % (quoted(executable), quoted(executable)), 0x7fff00100000)
    begin, end = line('write(2, "\\x43", 1) = 1'), line('write(2, "\\x63", 1) = 1')
    opened = line("socket(AF_INET, SOCK_STREAM|SOCK_CLOEXEC|SOCK_NONBLOCK, IPPROTO_IP) = 3", 0x401032)
    closed = line("close(3) = 0", 0x401052)
    finish = line("exit_group(0) = ?", 0x7fff00100000)
    good = launch + begin + opened + closed + end + finish
    accepted = analyze(good, profile, executable, final=True)
    count = 1
    packet = [0] * 40
    packet[8], packet[9], packet[11], packet[12] = 1, 2, 0, 1
    check_stats(packet, accepted, 2)
    count += 1
    mutations = [good.replace(closed, line("close(4) = 0", 0x401052)),
                 good.replace(closed, closed + closed), good.replace(opened, opened + opened),
                 good.replace(closed, line('unlinkat(AT_FDCWD, "\\x78", 0) = 0', 0x401052)),
                 good.replace(opened, opened.replace("401032", "401033")),
                 good.replace(closed, line("close(3) = -1 EIO (Input/output error) (INJECTED)", 0x401052)),
                 good.replace(end, ""), good.replace("exit_group(0)", "exit_group(1)"),
                 good.replace(quoted(executable), quoted("/tmp/other"), 1),
                 good.replace(begin, line('write(2, "\\x51", 1) = 1')).replace(end, line('write(2, "\\x71", 1) = 1'))]
    for changed in mutations:
        try:
            analyze(changed, profile, executable, final=True)
        except (AssertionError, ValueError):
            count += 1
        else:
            raise AssertionError("connector ledger accepted invalid phase/owner/endpoint")
    for change in (dict(index=9, value=1), dict(index=8, value=0), dict(index=10, value=1)):
        changed = list(packet)
        changed[change["index"]] = change["value"]
        try:
            check_stats(changed, accepted, 2)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("connector ledger accepted invalid physical stats")
    no_attempt = list(packet)
    no_attempt[8:11] = [0, 0, 0]
    try:
        check_stats(no_attempt, analyze(launch + begin + end + finish, profile, executable, final=True), 2)
    except AssertionError:
        count += 1
    else:
        raise AssertionError("connector ledger accepted unattempted endpoint metadata")
    print("url-connect CPU controls=%d" % count)


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        group, executable, observer = sys.argv[1:4]
        suite = Suite(executable, observer, group)
        with socket.socket() as reserved:
            reserved.bind(("127.0.0.1", 0))
            port = reserved.getsockname()[1]  # Bound but deliberately not listening.
            if group == "admission":
                admission(suite, port)
            else:
                assert group == "failures", group
                failures(suite, port)
        print("url-connect group=%s cases=%d evidence=%s" % (group, suite.count, suite.directory))
