"""Verified raw source owners for lexer and its real command-line consumer.

The ELF scanner and full-width map accounting are imported unchanged. This
module supplies only finite test phases, causal fault binding, and checkpoints.
"""
from collections import Counter
import importlib.util
import os
from pathlib import Path
import re
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


SOURCE = load("lexer_live_source", Path(__file__).resolve().parents[1] / "archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
CALLS = {"mmap", "munmap", "read", "write", "open", "openat", "close", "getpid"}
TRACE = ",".join(sorted(CALLS))


def profile(executable, directory):
    value = TRUSTED.verified_sites(Path(executable), Path(directory))
    assert value[0] and not value[1], "raw source requires verified opcode sites, not a named fallback"
    assert getattr(value[0], "executable_ranges", []), "missing raw executable ranges"
    return value


def events(text):
    assert not text or text.endswith("\n"), "partial trace passed as complete evidence"
    counts, output = Counter(), []
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unknown raw trace", line)
        ip, name, arguments, result = match.groups()
        counts[name] += 1
        output.append(dict(ip=int(ip, 16), name=name, args=arguments, result=result,
                           ordinal=counts[name], index=index, line=line))
    return output


def analyze(text, sites, directory, *, final=True):
    found = events(text)
    ranges = sites[0].executable_ranges
    assert all(any(low <= item["ip"] < high for low, high in ranges) for item in found), "syscall outside verified raw image"
    maps = "".join(item["line"] + "\n" for item in found if item["name"] in ("mmap", "munmap"))
    source = SOURCE.source(maps, sites)
    if final:
        assert not source["live"], ("source owner survives explicit release", source["live"])
        TRUSTED.source_maps(maps, sites, Path(directory))
    return dict(events=found, source=source)


def normalized(text):
    return "".join(item["line"].split("] ", 1)[1] + "\n" for item in events(text))


def bind(before, after, point, *, continuation_check=True):
    left = [item for item in before["events"] if item["name"] == "mmap"]
    right = [item for item in after["events"] if item["name"] == "mmap"]
    assert 1 <= point <= len(left) and len(right) >= point, (point, len(left), len(right))
    # Every preceding request and the reached fault retain source IP and all
    # arguments. ASLR changes returned addresses, not these allocation inputs.
    assert [(item["ip"], item["args"]) for item in left[:point]] == [(item["ip"], item["args"]) for item in right[:point]]
    marked = [item for item in after["events"] if "INJECTED" in item["result"]]
    assert marked == [right[point-1]] and marked[0]["result"].startswith("-1 ENOMEM "), marked
    if not continuation_check:
        return
    continuation = right[point:]
    if not continuation:
        return
    # Preserve the existing compiler's finite eager Frame episode only when
    # that exact owner/lifetime episode is present in this executable baseline.
    memory = [item for item in before["events"] if item["name"] in ("mmap", "munmap")]
    candidates = []
    for parent, temporary, released in zip(memory, memory[1:], memory[2:]):
        if parent["name"] != "mmap" or temporary["name"] != "mmap" or released["name"] != "munmap":
            continue
        args = TRUSTED.arguments(released["args"])
        if temporary["result"].split()[0] == args[0] and TRUSTED.arguments(temporary["args"])[1] == args[1]:
            candidates.append((parent, temporary))
    assert len(candidates) == 1, ("ambiguous eager-frame observation", candidates)
    parent, temporary = candidates[0]
    assert point == parent["ordinal"] and len(continuation) == 1, (point, continuation, candidates)
    actual = continuation[0]
    assert (actual["ip"], actual["args"]) == (temporary["ip"], temporary["args"])
    memory = [item for item in after["events"] if item["name"] in ("mmap", "munmap")]
    index = memory.index(actual)
    released = memory[index+1]
    assert released["name"] == "munmap" and released["result"] == "0"
    assert TRUSTED.arguments(released["args"]) == [actual["result"].split()[0], TRUSTED.arguments(actual["args"])[1]]


def read_exact(stream, count, deadline):
    output = bytearray()
    while len(output) < count:
        remaining = deadline-time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], "native checkpoint timed out"
        piece = os.read(stream.fileno(), count-len(output))
        assert piece, ("premature native EOF", len(output), count)
        output.extend(piece)
    return bytes(output)


def tagged(found, allowed):
    active, output = None, []
    for item in found:
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', item["args"]) if item["name"] == "write" and item["result"] == "1" else None
        if marker:
            value = chr(int(marker[1], 16))
            assert value in allowed, item
            if value.isupper():
                assert active is None, item
                active = dict(name=value, events=[])
                output.append(active)
            else:
                assert active and value == active["name"].lower(), item
                active = None
        elif active:
            active["events"].append(item)
    assert active is None, "unfinished operation phase"
    return output


def phases(found):
    output = tagged(found, "CcAaBbNnFfDdGgEeHhZzRr")
    for phase in output:
        names = [item["name"] for item in phase["events"]]
        if phase["name"] in "NZ":
            assert not names, ("nonterminal/admission operation performed native work", phase)
        if phase["name"] in "FDER":
            assert names and all(name == "munmap" for name in names), ("terminal release performed allocation/other work", phase)
        if phase["name"] in "ABGH":
            assert names and all(name == "mmap" for name in names), ("constructor did not reserve exactly its source owners", phase)
    return output


def library_allocations(executable):
    directory = Path(tempfile.mkdtemp(prefix="lexer-constructor-oom-"))
    sites = profile(executable, directory)
    started = time.monotonic()
    def execute(point=None):
        assert time.monotonic()-started < 62, "split finite OOM campaign before increasing runtime"
        trace = directory / ("baseline.trace" if point is None else f"oom-{point}.trace")
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none", "-e", "trace="+TRACE, "-o", str(trace)]
        if point is not None:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={point}"]
        command.append(str(Path(executable).resolve()))
        result = subprocess.run(command, capture_output=True, timeout=9)
        text = trace.read_text()
        owners = analyze(text, sites, directory)
        marked = tagged(owners["events"], "IiPpCcAaBbRrNnTt")
        for phase in marked:
            names = [item["name"] for item in phase["events"]]
            if phase["name"] == "N":
                assert not names, ("nonterminal next performed native work", phase)
            if phase["name"] == "T":
                assert names and all(name == "munmap" for name in names), phase
        markers = b"".join(bytes.fromhex(re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', item["args"])[1]) for item in owners["events"] if item["name"] == "write" and item["args"].startswith("2, "))
        assert result.stderr == markers, result
        assert all(item["name"] in ("mmap", "munmap", "write") for item in owners["events"]), "unexpected lexer host service"
        return result, owners, marked
    try:
        result, baseline, marked = execute()
        assert result.returncode == 0 and result.stdout == b"0\n", result
        role = {item["ordinal"]: {"I":1,"P":2,"C":3,"A":4,"B":5}[phase["name"]]
                for phase in marked for item in phase["events"] if item["name"] == "mmap"}
        attempts = baseline["source"]["attempts"]
        assert attempts and len(role) == len(attempts) and set(role.values()) == {1,2,3,4,5}, role
        stages = Counter()
        for item in attempts:
            point = item["ordinal"]
            result, actual, _ = execute(point)
            bind(baseline, actual, point, continuation_check=False)
            assert result.returncode == 4 and result.stdout == f"{role[point]}\n".encode(), (point, role[point], result)
            stages[role[point]] += 1
        print(f"lexer-resources allocations cases={len(attempts)} stages=" + ",".join(str(stages[index]) for index in range(1,6)))
    except BaseException:
        print(f"lexer allocation evidence: {directory}", file=sys.stderr)
        raise


def reuse(executable):
    directory = Path(tempfile.mkdtemp(prefix="lexer-cursor-reuse-"))
    sites = profile(executable, directory)
    trace = directory / "native.trace"
    command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none", "-e", "trace="+TRACE, "-o", str(trace), str(Path(executable).resolve())]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    frames, stdout = [], bytearray()
    try:
        for index in range(9):
            deadline = time.monotonic()+9
            frame = read_exact(process.stdout, 12, deadline)
            stdout.extend(frame)
            magic, actual, pid = struct.unpack("<3I", frame)
            assert magic == 1279613016 and actual == index and (not frames or pid == frames[0]["pid"])
            while True:
                try:
                    text = SOURCE.output_prefix(trace.read_text(), bytes(stdout))
                    break
                except (AssertionError, FileNotFoundError):
                    assert time.monotonic() < deadline, "checkpoint trace missing"
                    time.sleep(0.005)
            current = analyze(text, sites, directory, final=index == 8)
            ranges = SOURCE.process_owners(pid, current["source"]["live"])
            Path(directory, f"checkpoint-{index}.maps").write_text(Path(f"/proc/{pid}/maps").read_text())
            for attempt in current["source"]["attempts"]:
                result = attempt["result"].split()[0]
                if result.startswith("0x") and int(result, 16) not in current["source"]["live"]:
                    assert not any(low <= int(result, 16) < high for low, high in ranges), "released mapping still exists"
            phases(current["events"])
            frames.append(dict(pid=pid, live=current["source"]["live"], owners=current))
            live = frames[-1]["live"]
            if index == 0:
                assert live, "compiled rule owners are absent"
            if index == 1:
                first = {key:value for key,value in live.items() if key not in frames[0]["live"]}
                assert first and live == frames[0]["live"] | first
            if index == 2:
                second = {key:value for key,value in live.items() if key not in frames[1]["live"]}
                assert second and live == frames[1]["live"] | second
                assert sorted(first.values()) == sorted(second.values()), "independent cursor capacities differ"
            if index == 3:
                assert live == frames[2]["live"], "interleaved next changed source owners"
            if index == 4:
                assert live == frames[0]["live"] | second, "retiring first cursor touched the second"
            if index in (5, 6, 7):
                assert live == frames[0]["live"], "terminal cursor retained or consumed another owner"
            if index == 8:
                assert not live
            assert process.stdin.write(b"A") == 1
        process.stdin.close()
        process.stdin = None
        extra, stderr = process.communicate(timeout=3)
        assert process.returncode == 0 and not extra, (process.returncode, extra, stderr)
        whole = analyze(trace.read_text(), sites, directory)
        phases(whole["events"])
        markers = b"".join(bytes.fromhex(re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', item["args"])[1]) for item in whole["events"] if item["name"] == "write" and item["args"].startswith("2, "))
        assert markers == stderr
        assert whole["events"][-1]["name"] == "read" and whole["events"][-1]["args"] == '0, "\\x41", 1'
        print("lexer-resources reuse checkpoints=9 cases=1")
    except BaseException:
        if process.poll() is None:
            process.kill()
        try:
            process.communicate(timeout=3)
        except Exception:
            pass
        print(f"lexer resource evidence: {directory}", file=sys.stderr)
        raise


def controls():
    count = SOURCE.controls()
    def line(body, ip=0x401002):
        return f"[{ip:016x}] {body}\n"
    def marker(value):
        return line('write(2, "\\x%02x", 1) = 1' % ord(value))
    allocation = line("mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000")
    release = line("munmap(0x7fff10000000, 37) = 0", 0x401012)
    phases(events(marker("N") + marker("n")))
    phases(events(marker("F") + release + marker("f")))
    count += 2
    for text in (marker("N") + allocation + marker("n"), marker("Z") + release + marker("z"),
                 marker("F") + allocation + marker("f"), marker("N"), marker("n")):
        try:
            phases(events(text))
        except AssertionError:
            count += 1
        else:
            raise AssertionError("phase guard accepted allocation/release/fusion mutation")
    before = dict(events=events(allocation))
    failure = allocation.replace(" = 0x7fff10000000", " = -1 ENOMEM (Cannot allocate memory) (INJECTED)")
    bind(before, dict(events=events(failure)), 1)
    count += 1
    for text in (failure.replace("401002", "401003"), failure.replace(", 37,", ", 38,"),
                 failure.replace("ENOMEM", "EIO"), failure.replace(" (INJECTED)", "")):
        try:
            bind(before, dict(events=events(text)), 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("fault guard accepted unreachable/different source request")
    assert normalized(allocation).startswith("mmap(")
    count += 1
    print(f"lexer-resources controls={count}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    if len(sys.argv) == 3 and sys.argv[1] == "allocations":
        library_allocations(sys.argv[2])
        return
    if len(sys.argv) == 3 and sys.argv[1] == "reuse":
        reuse(sys.argv[2])
        return
    assert len(sys.argv) in (4, 6), "resources.py verify EXE TRACE | bind EXE BASELINE TRACE POINT | reuse EXE"
    mode, executable = sys.argv[1:3]
    with tempfile.TemporaryDirectory(prefix="lexer-verified-source-") as directory:
        sites = profile(executable, directory)
        if mode == "verify":
            text = Path(sys.argv[3]).read_text()
            analyze(text, sites, directory)
            sys.stdout.write(normalized(text))
            return
        assert mode == "bind" and len(sys.argv) == 6
        before = analyze(Path(sys.argv[3]).read_text(), sites, directory)
        after = analyze(Path(sys.argv[4]).read_text(), sites, directory)
        bind(before, after, int(sys.argv[5]))


if __name__ == "__main__":
    main()
