"""Independent zlib CRC32 reports and shared real-pthread ownership observations."""
from collections import Counter
import importlib.util
from pathlib import Path
import os
import random
import re
import signal
import subprocess
import sys
import tempfile
import time
import zlib

INPUT = 1048576
CHUNKS = 65536
READ_CALLS = 16384
WRITE_CALLS = 8192
HEADER = b"chunk,offset,length,crc32\n"
DIAGNOSTIC = b"parallel_checksums: operation failed\n"
TRACE = "mmap,munmap,read,write,rt_sigaction,exit_group"
PROBE = re.compile(rb"thread-probe (init|setstack|create|destroy|join) (\d+) (\d+) (\d+)\n")


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parents[2]
OWNERS = load("parallel_checksums_thread_owners", FIXTURES / "stdlib_thread_pool_lifecycle/resources.py")


def reference(data, chunk):
    rows = [HEADER]
    for index, offset in enumerate(range(0, len(data), chunk)):
        piece = data[offset:offset + chunk]
        rows.append(f"{index},{offset},{len(piece)},{zlib.crc32(piece)}\n".encode())
    return b"".join(rows)


def arguments(workers=4, chunk=4096):
    return ["--workers", str(workers), "--chunk", str(chunk)]


def probe_records(data):
    records = [dict(kind=match[1].decode(), ordinal=int(match[2]), result=int(match[3]), identity=int(match[4]))
               for match in PROBE.finditer(data)]
    return records, PROBE.sub(b"", data)


def observe(snapshot, *, fatal=False):
    """Main-TID order proves admission, joined ownership and publication order."""
    eof, published = False, False
    reads, writes = [], Counter()
    created, joined, events = set(), set(), []
    failure_index = None
    for index, event in enumerate(snapshot["main_events"]):
        name, args, answer, authority = event["name"], event["args"], event["answer"], event["authority"]
        if name == "write" and authority == "native":
            fields = OWNERS.arguments(args)
            if fields[0] == "2" and fields[1].startswith('"'):
                message = OWNERS.quoted(fields[1])
                records, rest = probe_records(message)
                if records:
                    assert not rest and len(records) == 1 and answer == str(len(message)), event
                    record = records[0]; events.append(record)
                    assert not published, ("thread operation after publication", event)
                    if record["kind"] == "create" and record["result"] == 0:
                        assert record["identity"] and record["identity"] not in created, event
                        created.add(record["identity"])
                    if record["kind"] == "join":
                        assert record["identity"] in created and record["identity"] not in joined, event
                        if record["result"] == 0:
                            joined.add(record["identity"])
                        elif failure_index is None:
                            failure_index = index
        if authority != "source":
            continue
        if name == "read":
            assert not eof and not published and args.split(",")[0] == "0", event
            assert 1 <= int(args.rsplit(",", 1)[1]) <= 1024, event
            reads.append(event)
            if answer.split()[0] == "0": eof = True
        if name == "write":
            descriptor = int(args.split(",")[0]); assert descriptor in (1, 2), event
            assert 1 <= int(args.rsplit(",", 1)[1]) <= 1024, event
            writes[descriptor] += 1
            if descriptor == 1:
                assert eof and created == joined and failure_index is None, ("publication before admission/join", event, created, joined)
                published = True
        if name == "mmap":
            assert not published, ("allocation after publication", event)
        if name == "munmap":
            assert created == joined, ("source storage retired before worker joins", event, created, joined)
    assert len(reads) <= READ_CALLS and writes[1] <= WRITE_CALLS and writes[2] <= 8
    if fatal:
        assert failure_index is not None and created != joined and not published
    else:
        assert created == joined and failure_index is None, (created, joined, failure_index)
    return dict(reads=reads, writes=writes, threads=events, created=created, joined=joined, failure_index=failure_index)


class Runner:
    def __init__(self, executable, group):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"parallel-checksums-{group}-"))
        self.profile = None
        self.count = 0

    def run(self, name, data=b"", args=None, *, expected=None, status=0, trace=False,
            inject=(), environment=None, fatal=False, quiet_error=False, closed=False):
        directory = self.directory / name; directory.mkdir()
        input_path = directory / "input"; input_path.write_bytes(data)
        environment_values = os.environ.copy()
        for key in list(environment_values):
            if key.startswith("LANIUS_THREAD_PROBE_"): del environment_values[key]
        environment_values.update(environment or {})
        command = [self.executable, *(arguments() if args is None else args)]
        prefix = directory / "trace"
        if trace:
            if self.profile is None: self.profile = OWNERS.verified_sites(self.executable)
            environment_values.update(LANIUS_ALLOC="mmap", LANIUS_THREAD_PROBE_TRACE="1")
            command = ["strace", "--kill-on-exit", "-ff", "-qq", "-i", "-xx", "-v", "-s", "65536",
                       "-e", "signal=none", "-e", "trace=" + TRACE, "-o", str(prefix), *command]
            for call, ordinal, action in inject:
                where = command.index(self.executable)
                command[where:where] = ["-e", f"inject={call}:{action}:when={ordinal}"]
        start = time.monotonic()
        with input_path.open("rb") as source:
            if closed:
                reader, writer = os.pipe(); os.close(reader)
                try:
                    result = subprocess.run(command, stdin=source, stdout=writer, stderr=subprocess.PIPE,
                                            env=environment_values, timeout=15)
                finally: os.close(writer)
                stdout = b""
            else:
                result = subprocess.run(command, stdin=source, capture_output=True, env=environment_values, timeout=15)
                stdout = result.stdout
        elapsed = time.monotonic() - start
        records, diagnostic = probe_records(result.stderr)
        wanted = b"" if expected is None else expected
        assert stdout == wanted, (name, stdout[:160], wanted[:160], result.stderr)
        if fatal:
            assert result.returncode == -signal.SIGILL and DIAGNOSTIC not in diagnostic, (name, result)
        else:
            assert result.returncode == status, (name, result.returncode, status, result.stderr)
            assert diagnostic == (b"" if status == 0 or quiet_error else DIAGNOSTIC), (name, diagnostic)
        self.count += 1
        if not trace:
            assert not records
            return dict(elapsed=elapsed)
        paths = sorted(directory.glob("trace.*")); assert paths
        decoded = {int(path.suffix[1:]): OWNERS.decode(path.read_text(), self.profile, int(path.suffix[1:])) for path in paths}
        candidates = [tid for tid, events in decoded.items() if any(event["authority"] == "source" and event["name"] == "rt_sigaction" for event in events)]
        assert len(candidates) == 1, candidates
        main_pid = candidates[0]
        snapshot = OWNERS.read_traces(prefix, self.profile, main_pid)
        observation = observe(snapshot, fatal=fatal)
        assert records == observation["threads"], (records, observation)
        if fatal:
            before = OWNERS.source_maps(snapshot["main_events"][:observation["failure_index"] + 1], self.profile, main_pid)
            assert before["maps"] and before["maps"] == snapshot["maps"], (name, before, snapshot)
        else:
            OWNERS.assert_empty(snapshot)
        marked = [event for event in snapshot["events"] if "INJECTED" in event["answer"]]
        assert bool(marked) == bool(inject), (name, marked, inject)
        for call, ordinal, action in inject:
            if isinstance(ordinal, int):
                found = [event for event in marked if event["tid"] == main_pid and event["name"] == call and event["ordinal"] == ordinal]
                assert len(found) == 1 and found[0]["authority"] == "source", (name, found)
                kind, value = action.split("=", 1)
                if kind == "retval": assert found[0]["answer"].split()[0] == value
                else: assert re.search(r"^-1 " + re.escape(value) + r"\b", found[0]["answer"]), found
        return dict(snapshot=snapshot, observation=observation, elapsed=elapsed)


def model_cases():
    cases = [(b"", 4, 4096), (b"123456789", 1, 9), (b"123456789", 4, 4),
             (bytes(range(256)), 4, 1), (b"\0\xff\n\r\x80", 2, 2), (b"a", 8, 1048576),
             (b"abcde" * 19, 1, 19), (bytes(range(256)) * 33, 8, 257)]
    rng = random.Random(0xC32A2026)
    for index in range(24):
        size = [0, 1, 2, 7, 127, 255, 256, 257, 1023, 1024, 1025, 4097][index % 12]
        data = bytes(rng.randrange(256) for _ in range(size))
        cases.append((data, [1, 2, 4, 8][index % 4], [1, 3, 64, 255, 1024, 1048576][index % 6]))
    return cases


def model(runner):
    for index, (data, workers, chunk) in enumerate(model_cases()):
        runner.run(f"case-{index}", data, arguments(workers, chunk), expected=reference(data, chunk))


def admission(runner):
    invalid = [["--unknown"], ["operand"], ["--workers"], ["--chunk"], ["--workers", "0"],
               ["--workers", "33"], ["--workers", "-1"], ["--workers", "+2"], ["--workers", " 2"],
               ["--workers", "1x"], ["--chunk", "0"], ["--chunk", "1048577"], ["--chunk", "-1"],
               ["--chunk", "18446744073709551616"], ["--chunk", "0" * 65 + "1"],
               ["--workers", "2", "-w", "3"], ["--chunk", "4", "-c", "8"],
               ["--help", "--workers", "1"], ["--", "operand"], [b"--chunk", b"\xff"]]
    for index, args in enumerate(invalid): runner.run(f"invalid-{index}", b"payload", args, status=2)
    for name, args, chunk in [("default", [], 4096), ("short", ["-w2", "-c4"], 4),
                              ("equals", ["--workers=2", "--chunk=0004"], 4),
                              ("wide-digits", ["-c", "0" * 63 + "1", "-w", "01"], 1)]:
        runner.run(name, b"123456789", args, expected=reference(b"123456789", chunk))
    for index, option in enumerate(["--help", "-h"]):
        result = subprocess.run([runner.executable, option], input=b"\xff" * (INPUT + 1), capture_output=True, timeout=15)
        assert result.returncode == 0 and not result.stderr and result.stdout.startswith(b"Usage: parallel_checksums ")
        assert b"--workers" in result.stdout and b"--chunk" in result.stdout
        runner.count += 1


def limits(runner):
    data = bytes(range(256)) * 4096
    runner.run("exact-input", data, arguments(4, 65536), expected=reference(data, 65536))
    runner.run("excess-input", data + b"x", arguments(4, 65536), status=2)
    data = b"x" * CHUNKS
    runner.run("exact-chunks", data, arguments(4, 1), expected=reference(data, 1))
    runner.run("excess-chunks", data + b"x", arguments(4, 1), status=2)
    runner.run("maximum-chunk", b"123456789", arguments(1, INPUT), expected=reference(b"123456789", INPUT))
    runner.run("maximum-workers", b"123456789", arguments(32, 2), expected=reference(b"123456789", 2))


def resources(runner):
    data = bytes(range(256)) * 71 + b"x"
    args = arguments(4, 257); expected = reference(data, 257)
    base = runner.run("baseline", data, args, expected=expected, trace=True)
    allocations = base["snapshot"]["allocations"]; assert allocations
    for index, event in enumerate(allocations):
        runner.run(f"oom-{index}", data, args, status=4, trace=True, inject=(("mmap", event["ordinal"], "error=ENOMEM"),))
    source = [event for event in base["snapshot"]["main_events"] if event["authority"] == "source"]
    reads = [event for event in source if event["name"] == "read"]
    writes = [event for event in source if event["name"] == "write" and event["args"].startswith("1,")]
    signal = next(event for event in source if event["name"] == "rt_sigaction")
    assert len(reads) > 1 and len(writes) > 1
    runner.run("read-eio", data, args, status=3, trace=True, inject=(("read", reads[0]["ordinal"], "error=EIO"),))
    runner.run("read-late-eio", data, args, status=3, trace=True, inject=(("read", reads[1]["ordinal"], "error=EIO"),))
    runner.run("read-eintr", data, args, expected=expected, trace=True, inject=(("read", reads[0]["ordinal"], "error=EINTR"),))
    runner.run("write-eio", data, args, status=5, trace=True, inject=(("write", writes[0]["ordinal"], "error=EIO"),))
    runner.run("write-late-eio", data, args, status=5, expected=expected[:1024], trace=True, inject=(("write", writes[1]["ordinal"], "error=EIO"),))
    runner.run("write-zero", data, args, status=5, trace=True, inject=(("write", writes[0]["ordinal"], "retval=0"),))
    runner.run("write-eintr", data, args, expected=expected, trace=True, inject=(("write", writes[0]["ordinal"], "error=EINTR"),))
    runner.run("signal-eio", data, args, status=3, trace=True, inject=(("rt_sigaction", signal["ordinal"], "error=EIO"),))
    limited = runner.run("read-budget", data, args, status=2, trace=True, inject=(("read", f'{reads[0]["ordinal"]}+', "error=EINTR"),))
    assert len(limited["observation"]["reads"]) == READ_CALLS
    assert all("EINTR" in event["answer"] and "INJECTED" in event["answer"] for event in limited["observation"]["reads"])
    limited = runner.run("write-budget", data, args, status=5, trace=True, quiet_error=True,
                         inject=(("write", f'{writes[0]["ordinal"]}+', "error=EINTR"),))
    assert limited["observation"]["writes"] == Counter({1: WRITE_CALLS, 2: 8})
    runner.run("closed-stdout", data, args, status=5, trace=True, closed=True)
    return len(allocations)


def threads(runner):
    invalid = runner.run("cli-before-input", b"must remain unread", ["--workers", "0"], status=2, trace=True)
    assert not invalid["observation"]["reads"] and not invalid["observation"]["threads"]
    assert invalid["observation"]["writes"][1] == 0
    excess = runner.run("input-limit-before-workers", b"x" * (INPUT + 1), arguments(4, 4096), status=2, trace=True)
    assert not excess["observation"]["threads"] and excess["observation"]["writes"][1] == 0
    assert sum(int(event["answer"].split()[0]) for event in excess["observation"]["reads"]) == INPUT + 1
    assert excess["observation"]["reads"][-1]["answer"] == "1"
    excess = runner.run("chunk-limit-before-workers", b"x" * (CHUNKS + 1), arguments(4, 1), status=2, trace=True)
    assert not excess["observation"]["threads"] and excess["observation"]["writes"][1] == 0
    assert excess["observation"]["reads"][-1]["answer"] == "0"
    data = bytes(range(256)) * 4096; expected = reference(data, 4096)
    baseline = runner.run("real-workers", data, arguments(4, 4096), expected=expected, trace=True)
    observed = baseline["observation"]
    assert len(observed["created"]) == len(observed["joined"]) == 3
    assert len(baseline["snapshot"]["per_tid"]) == 4
    single = runner.run("single-worker", data, arguments(1, 4096), expected=expected, trace=True)
    assert not single["observation"]["threads"] and len(single["snapshot"]["per_tid"]) == 1
    for ordinal in (1, 2):
        failed = runner.run(f"create-fallback-{ordinal}", data, arguments(4, 4096), expected=expected, trace=True,
                            environment={"LANIUS_THREAD_PROBE_FAIL_CREATE": f"{ordinal}:11"})
        records = failed["observation"]["threads"]
        assert [event for event in records if event["kind"] == "create" and event["result"]] == [dict(kind="create", ordinal=ordinal, result=11, identity=0)]
        assert len(failed["observation"]["created"]) == ordinal - 1
    for ordinal in (1, 2):
        failed = runner.run(f"join-fatal-{ordinal}", data, arguments(4, 4096), trace=True, fatal=True,
                            environment={"LANIUS_THREAD_PROBE_FAIL_JOIN": f"{ordinal}:16"})
        errors = [event for event in failed["observation"]["threads"] if event["kind"] == "join" and event["result"]]
        assert len(errors) == 1 and errors[0]["ordinal"] == ordinal and errors[0]["result"] == 16
    empty = runner.run("empty-no-workers", b"", arguments(32, 4096), expected=HEADER, trace=True)
    assert not empty["observation"]["threads"] and len(empty["snapshot"]["per_tid"]) == 1
    return dict(real_workers=3, bytes=INPUT, serial_seconds=round(single["elapsed"], 3), threaded_seconds=round(baseline["elapsed"], 3))


def controls():
    assert reference(b"", 1) == HEADER
    assert reference(b"123456789", 9) == HEADER + b"0,0,9,3421780262\n"
    assert reference(b"123456789", 4) == HEADER + b"0,0,4,2615402659\n1,4,4,2119325191\n2,8,1,2366072709\n"
    assert reference(b"\0\xff\n\r", 100) == HEADER + b"0,0,4,461537222\n"
    assert len(reference(b"x" * 17, 4).splitlines()) == 6
    assert len(model_cases()) == 32
    pairs = OWNERS.SOURCE.RuntimePairs([(0x401002, 0x401012)])
    pairs.mmap_flags = {0x401002: 0x22}; pairs.executable_ranges = [(0x401000, 0x401030)]
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022}; pairs.bootstrap_sites = {}; pairs.image_ranges = [(0x401000, 0x403000)]
    profile = pairs, []
    def line(call, ip=0x401022): return f"[{ip:016x}] {call}\n"
    def marker(message):
        value = ''.join(f"\\x{byte:02x}" for byte in message)
        return line(f'write(2, "{value}", {len(message)}) = {len(message)}', 0x7fff00001000)
    allocation = line("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000", 0x401002)
    release = line("munmap(0x7fff10000000, 37) = 0", 0x401012)
    eof = line('read(0, "", 1024) = 0'); output = line('write(1, "\\x0a", 1) = 1')
    create = marker(b"thread-probe create 1 0 11\n"); join = marker(b"thread-probe join 1 0 11\n")
    valid = allocation + eof + create + join + output + release
    def inspect(text):
        events = OWNERS.decode(text, profile, 1)
        snapshot = dict(main_events=events, **OWNERS.source_maps(events, profile, 1))
        observe(snapshot); OWNERS.assert_empty(snapshot)
    inspect(valid)
    mutations = [valid.replace(join, ""), valid.replace(eof, ""), valid.replace(release, ""),
                 valid.replace(create, create + create), valid + eof, eof + create + join + output + allocation + release,
                 allocation + eof + create + release + join + output,
                 valid + marker(b"thread-probe create 2 0 22\n") + marker(b"thread-probe join 2 0 22\n")]
    for text in mutations:
        try: inspect(text)
        except (AssertionError, ValueError): continue
        raise AssertionError("parallel checksum observer admitted corruption")
    return 6 + 1 + len(mutations)


GROUPS = dict(model=model, admission=admission, limits=limits, resources=resources, threads=threads)


def main():
    assert controls() == 15
    if sys.argv[1:] == ["controls"]:
        print("parallel-checksums-controls=15 model=32 admission=26 limits=6 resources=12+A threads=10")
        return
    assert len(sys.argv) == 3 and sys.argv[1] in GROUPS, sys.argv
    group = sys.argv[1]; runner = Runner(sys.argv[2], group); extra = GROUPS[group](runner)
    expected = dict(model=32, admission=26, limits=6, resources=12 + (extra or 0) if group == "resources" else 0, threads=10)[group]
    assert runner.count == expected, (group, runner.count, expected)
    print(f"parallel-checksums-{group} cases={runner.count} detail={extra} evidence={runner.directory}")


if __name__ == "__main__": main()
