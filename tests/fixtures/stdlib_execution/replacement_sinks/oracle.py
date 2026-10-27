"""Actual collection owners, independent replacement history, and reached faults.

Only the host model is Python. The child calls the real stdlib transfer and
facades; the unchanged raw verifier/live ledger establishes native ownership.
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


HERE = Path(__file__).resolve().parent
SOURCE = load("replacement_live_source", HERE.parents[1] / "extended/archive_source/ledger.py")
TRUSTED = SOURCE.TRUSTED
CALLS = {"read", "write", "getpid", "mmap", "munmap"}
TRACE = ",".join(sorted(TRUSTED.CALLS | {"open"}))
PAIRS = dict(U="u", C="c", T="t", K="k", A="a", B="b", P="p", H="h", R="r", D="d")
MAGIC = 1347621681
FIELDS = ("magic", "pid", "phase", "backend", "profile", "status", "ready", "tag",
          "committed", "replaced", "source_calls", "replacement_calls", "delivery_calls",
          "dest_count", "dest_capacity", "source_count", "source_capacity", "history_count", "history_capacity",
          "pending", "pending_id", "pending_rep", "held", "held_id", "held_rep", "error_kind", "error_bytes",
          "secondary", "input_count", "setup_count", "item_bytes", "reserved")
GROUPS = ("hash-map-oom", "tree-map-oom", "hash-set-oom", "tree-set-oom")


def events(text):
    assert not text or text.endswith("\n"), "partial native trace"
    counts, found, scopes, stack, markers = Counter(), [], [], [], bytearray()
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unexpected host/native event", line)
        ip, name, args, result = match.groups()
        counts[name] += 1
        item = dict(ip=int(ip, 16), name=name, args=args, result=result, ordinal=counts[name], index=index, line=line,
                    phase=stack[0]["name"] if stack else None, role=stack[-1]["name"] if len(stack) == 2 else None)
        if name in ("read", "write"):
            descriptor = TRUSTED.arguments(args)[0]
            assert (descriptor == "0" if name == "read" else descriptor in ("1", "2")), item
        marker = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args) if name == "write" and result == "1" else None
        if marker:
            token = chr(int(marker[1], 16))
            assert token in set(PAIRS) | set(PAIRS.values()) | set("SFE"), item
            markers.extend(token.encode())
            item["marker"] = token
            if token in PAIRS:
                if token in "UCTK":
                    assert not stack, ("overlapping outer phases", item)
                else:
                    assert len(stack) == 1, ("callback phase nesting", item)
                    assert token in ("ABPH" if stack[0]["name"] == "U" else "RD" if stack[0]["name"] in "TK" else ""), item
                scope = dict(name=token, start=index, events=[])
                scopes.append(scope)
                stack.append(scope)
            elif token in PAIRS.values():
                assert stack and PAIRS[stack[-1]["name"]] == token, item
                stack[-1]["end"] = index
                stack.pop()
            elif token == "S":
                assert len(stack) == 1 and stack[0]["name"] in "TK", ("source reentry/outside transfer", item)
            if stack and stack[0]["name"] == "C" and token != "C":
                raise AssertionError(("zero quota caused callback", item))
        else:
            for scope in stack:
                scope["events"].append(item)
            if stack and stack[0]["name"] == "C":
                raise AssertionError(("zero quota performed native work", item))
            if name == "mmap":
                assert item["role"] in ("A", "B", "P", "H") if item["phase"] == "U" else item["phase"] in ("T", "K") and item["role"] in ("R", "D"), ("helper allocated outside explicit callback", item)
        found.append(item)
    assert not stack, "unfinished callback phase"
    return dict(events=found, scopes=scopes, markers=bytes(markers))


def analyze(text, authority, directory, final=False):
    parsed = events(text)
    assert all(any(low <= item["ip"] < high for low, high in authority[0].executable_ranges) for item in parsed["events"]), "syscall outside verified raw image"
    memory = "".join(item["line"] + "\n" for item in parsed["events"] if item["name"] in ("mmap", "munmap"))
    parsed["source"] = SOURCE.source(memory, authority)
    live = {}
    for item in parsed["events"]:
        result = item["result"].split()[0]
        if item["name"] == "mmap" and result.startswith("0x"):
            live[int(result, 16)] = item
        elif item["name"] == "munmap":
            del live[int(TRUSTED.arguments(item["args"])[0], 16)]
    assert set(live) == set(parsed["source"]["live"])
    parsed["origins"] = live
    if final:
        assert not live, "source owners survive pre-exit cleanup"
        TRUSTED.source_maps(memory, authority, directory)
    return parsed


def row(backend, identity, representative):
    return (identity, representative, 8, 8 if backend < 2 else 0)


def initial(backend, profile, capacity):
    destination = {}
    if profile:
        for identity in range(1, (capacity if profile == 2 else 1) + 1):
            destination[identity] = row(backend, identity, 50 + identity if profile == 2 else 50)
    identities = (1, 2, 1, 3, 1, 4, 5) if profile == 0 else (1, 1, 1)
    source = [row(backend, identity, 65 + index) for index, identity in enumerate(identities)]
    return destination, source


def model(backend, profile, capacity, *, fail_role=None, fail_call=0, fail_length=0):
    destination, source = initial(backend, profile, capacity)
    history, pending, order = [], [], []
    calls, committed, replaced, tag, error, error_bytes = Counter(), 0, 0, 0, 0, 0
    while source:
        incoming = source.pop(0)
        order.extend("SRr")
        calls["source"] += 1
        calls["replacement"] += 1
        if fail_role == "R" and calls["replacement"] == fail_call:
            tag, error, pending = 1, 10, [incoming]
            break
        old = destination.get(incoming[0])
        destination[incoming[0]] = incoming
        committed += 1
        if old is not None:
            replaced += 1
            calls["delivery"] += 1
            order.extend("Dd")
            denied = fail_role == "D" and calls["delivery"] == fail_call
            limit = profile == 3 and len(history) >= 1
            if denied or limit:
                tag, pending = 2, [old]
                error, error_bytes = ((3 if fail_length == 5 else 2), 0) if denied else (1, 5)
                break
            history.append(old)
    else:
        calls["source"] += 1
        order.append("S")
    return dict(destination=list(destination.values()), history=history, source=source, pending=pending, held=[],
                committed=committed, replaced=replaced, tag=tag, error_kind=error, error_bytes=error_bytes,
                calls=calls, order="".join(order))


def completed(backend, profile, capacity):
    destination, source = initial(backend, profile, capacity)
    history = []
    for incoming in source:
        old = destination.get(incoming[0])
        destination[incoming[0]] = incoming
        if old is not None:
            history.append(old)
    return list(destination.values()), history


def transfer_fault(parsed):
    marked = [item for item in parsed["events"] if "INJECTED" in item["result"]]
    assert len(marked) <= 1, marked
    if not marked:
        return None
    item = marked[0]
    assert item["name"] == "mmap" and item["result"].startswith("-1 ENOMEM "), item
    role_scopes = [scope for scope in parsed["scopes"] if scope["name"] == item["role"] and scope["start"] < item["index"] < scope["end"]]
    assert len(role_scopes) == 1
    scopes = [scope for scope in parsed["scopes"] if scope["name"] == item["role"] and parsed["events"][scope["start"]]["phase"] == item["phase"]]
    return dict(item, call=scopes.index(role_scopes[0]) + 1, length=int(TRUSTED.arguments(item["args"])[1]))


def rows_equal(actual, expected):
    assert sorted(actual["destination"]) == sorted(expected["destination"]), (actual, expected)
    for name in ("history", "source", "pending", "held"):
        assert actual[name] == expected[name], (name, actual, expected)


def owners(parsed, values, rows):
    live = parsed["source"]["live"]
    if not values["ready"] or values["phase"] == 4:
        assert not live
        return
    origins = parsed["origins"]
    if values["phase"] == 3:
        sizes = [size for item in rows["held"] for size in item[2:] if size]
        sizes += [values["error_bytes"]] if values["error_bytes"] else []
        assert sorted(live.values()) == sorted(sizes), ("only transferred old/error may remain", live, sizes)
        return
    classifications = Counter()
    for pointer, event in origins.items():
        size, role = live[pointer], event["role"]
        if role == "B":
            assert size == 8
            classifications["payload"] += 1
        elif role == "A":
            assert size == values["source_capacity"] * values["item_bytes"]
            classifications["source"] += 1
        elif role in ("P", "R"):
            classifications["destination"] += 1
        elif role in ("H", "D"):
            if role == "D" and size == 5:
                classifications["error"] += 1
            else:
                assert size == values["history_capacity"] * values["item_bytes"]
                classifications["history"] += 1
        else:
            raise AssertionError(("unclassified live owner", event))
    payloads = sum(bool(size) for entries in rows.values() for item in entries for size in item[2:])
    assert classifications == Counter(payload=payloads, source=int(values["source_capacity"] > 0),
                                      destination=int(values["dest_capacity"] > 0), history=int(values["history_capacity"] > 0),
                                      error=int(values["error_bytes"] > 0)), (classifications, values)


def bind(before, after, point):
    left = [item for item in before["events"] if item["name"] == "mmap"]
    right = [item for item in after["events"] if item["name"] == "mmap"]
    assert 1 <= point <= len(left) and len(right) >= point
    def key(item):
        return item["ip"], item["args"], item["ordinal"], item["phase"], item["role"]
    assert [key(item) for item in left[:point]] == [key(item) for item in right[:point]], "source allocation prefix/provenance changed"
    marked = [item for item in after["events"] if "INJECTED" in item["result"]]
    assert marked == [right[point - 1]] and marked[0]["result"].startswith("-1 ENOMEM ")
    if marked[0]["phase"] == "U":
        assert len(right) == point, "setup failure allocated after rejection"
    else:
        assert all(item["phase"] == "K" and item["role"] in ("R", "D") for item in right[point:]), "post-fault allocation outside explicit recovery callback"


def read_exact(stream, count, deadline):
    result = bytearray()
    while len(result) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0 and select.select([stream], [], [], remaining)[0], "owner checkpoint deadline"
        found = os.read(stream.fileno(), count - len(result))
        assert found, ("native owner checkpoint EOF", len(result), count)
        result.extend(found)
    return bytes(result)


def prefix(path, output, deadline):
    while True:
        try:
            return SOURCE.output_prefix(path.read_text(), output)
        except (SOURCE.CheckpointPending, FileNotFoundError):
            assert time.monotonic() < deadline, "native trace flush deadline"
            time.sleep(0.002)


class Suite:
    def __init__(self, group, executable):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix="replacement-sinks-" + group + "-"))
        self.authority = TRUSTED.verified_sites(self.executable, self.directory)
        assert self.authority[0] and not self.authority[1] and self.authority[0].executable_ranges
        self.deadline, self.count, self.denials, self.classes = time.monotonic() + 75, 0, 0, Counter()
        print(f"evidence={self.directory}", flush=True)

    def run(self, backend, profile, point=None, baseline=None, unreached=False):
        assert time.monotonic() < self.deadline, "split finite resource campaign before increasing runtime"
        directory = self.directory / f"{self.count:03d}-b{backend}-p{profile}-n{point or 0}"
        directory.mkdir()
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none", "-e", "trace=" + TRACE, "-o", str(trace)]
        if point:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={point}"]
        command.append(str(self.executable))
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        deadline, output, frames, parsed_frames = min(self.deadline, time.monotonic() + 8), bytearray(), [], []
        admitted = set()
        try:
            assert os.write(process.stdin.fileno(), struct.pack("<2I", backend, profile)) == 8
            for phase in range(5):
                raw = read_exact(process.stdout, 256, deadline)
                output.extend(raw)
                values = dict(zip(FIELDS, struct.unpack("<32Q", raw)))
                assert (values["magic"], values["phase"], values["backend"], values["profile"], values["reserved"]) == (MAGIC, phase, backend, profile, 0), values
                assert values["ready"] in (0, 1) and values["pending"] in (0, 1) and values["held"] in (0, 1)
                assert values["status"] in (0, 4) and values["tag"] in range(4) and values["item_bytes"] > 5
                assert values["input_count"] == (7 if profile == 0 else 3)
                counts = [values[key] for key in ("dest_count", "history_count", "source_count", "pending", "held")]
                assert sum(counts) <= 32, values
                raw_rows = read_exact(process.stdout, sum(counts) * 32, deadline)
                output.extend(raw_rows)
                words = list(struct.iter_unpack("<4Q", raw_rows))
                rows, at = {}, 0
                for name, count in zip(("destination", "history", "source", "pending", "held"), counts):
                    rows[name] = words[at:at + count]
                    at += count
                assert all(item == row(backend, item[0], item[1]) for group in rows.values() for item in group), rows
                pid = values["pid"]
                assert Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split() == [str(pid)]
                parsed = analyze(prefix(trace, bytes(output), deadline), self.authority, directory, final=phase == 4)
                maps = SOURCE.process_owners(pid, parsed["source"]["live"])
                admitted.update(parsed["source"]["live"])
                owners(parsed, values, rows)
                if phase == 4:
                    assert all(not any(low <= pointer < high for low, high in maps) for pointer in admitted), "released native mappings remain before exit"
                frames.append((values, rows))
                parsed_frames.append(parsed)
                assert os.write(process.stdin.fileno(), b"A") == 1
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            final = analyze(trace.read_text(), self.authority, directory, final=True)
            assert not rest and stderr == final["markers"]
            injected = bool(point and not unreached)
            assert process.returncode == (4 if injected else 0), (process.returncode, frames, stderr)
            assert len(final["events"]) == len(parsed_frames[-1]["events"]) + 1 and final["events"][-1]["name"] == "read"
            self.check(backend, profile, frames, parsed_frames, final, injected)
            if injected:
                bind(baseline, final, point)
                fault = transfer_fault(final)
                category = "setup" if fault["phase"] == "U" else "replacement" if fault["role"] == "R" else "recovery" if fault["phase"] == "K" else "owned-error" if fault["length"] == 5 else "displaced"
                self.classes[category] += 1
                self.denials += 1
            elif unreached:
                assert len(final["source"]["attempts"]) + 1 == point and not any("INJECTED" in item["result"] for item in final["events"])
            (directory / "stdout.bin").write_bytes(output)
            (directory / "stderr.bin").write_bytes(stderr)
            self.count += 1
            return final
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(output)
            if process.poll() is None:
                process.kill()
            out, err = process.communicate(timeout=3)
            (directory / "remaining-stdout.bin").write_bytes(out)
            (directory / "stderr.bin").write_bytes(err)
            raise

    def check(self, backend, profile, frames, parsed_frames, final, injected):
        fault = transfer_fault(final)
        assert bool(fault) == injected
        zero, stop, resolved, held, released = frames
        if not zero[0]["ready"]:
            assert fault and fault["phase"] == "U"
            for values, rows in frames:
                assert values["status"] == 4 and values["tag"] == 3 and not any(rows.values())
                assert (values["committed"], values["replaced"], values["source_calls"], values["replacement_calls"], values["delivery_calls"]) == (0, 0, 0, 0, 0)
            assert not any(scope["name"] in "CT" for scope in final["scopes"])
            return
        assert all(values["ready"] == 1 for values, _ in frames)
        initial_dest, initial_source = initial(backend, profile, zero[0]["dest_capacity"])
        rows_equal(zero[1], dict(destination=list(initial_dest.values()), source=initial_source, history=[], pending=[], held=[]))
        assert zero[0]["setup_count"] == len(initial_dest) and zero[0]["status"] == zero[0]["tag"] == 0
        role = fault["role"] if fault and fault["phase"] == "T" else None
        expected = model(backend, profile, zero[0]["dest_capacity"], fail_role=role,
                         fail_call=fault["call"] if role else 0, fail_length=fault["length"] if role else 0)
        rows_equal(stop[1], expected)
        for key in ("committed", "replaced", "tag", "error_kind", "error_bytes"):
            assert stop[0][key] == expected[key], (key, stop, expected)
        assert stop[0]["status"] == (4 if role else 0)
        for key, field in (("source", "source_calls"), ("replacement", "replacement_calls"), ("delivery", "delivery_calls")):
            assert stop[0][field] == expected["calls"][key]
        scopes = [scope for scope in final["scopes"] if scope["name"] == "T"]
        assert len(scopes) == 1
        scope = scopes[0]
        order = "".join(item.get("marker", "") for item in final["events"][scope["start"] + 1:scope["end"]] if item.get("marker") in set("SRrDd"))
        assert order == expected["order"], (order, expected["order"])
        dest, history = completed(backend, profile, zero[0]["dest_capacity"])
        rows_equal(resolved[1], dict(destination=dest, history=history, source=[], pending=[], held=[]))
        assert resolved[0]["committed"] == len(initial_source) and resolved[0]["replaced"] == len(history)
        assert resolved[0]["source_calls"] == len(initial_source) + 1
        assert resolved[0]["replacement_calls"] == len(initial_source) + int(role == "R")
        extra_delivery = int(profile == 3 or role == "D") + int(bool(fault and fault["phase"] == "K"))
        assert resolved[0]["delivery_calls"] == len(history) + extra_delivery
        assert resolved[0]["error_kind"] == expected["error_kind"] and resolved[0]["error_bytes"] == expected["error_bytes"]
        assert resolved[0]["secondary"] == (2 if fault and fault["phase"] == "K" else 0)
        wanted = expected["pending"] if expected["tag"] == 2 else history[-1:]
        rows_equal(held[1], dict(destination=[], history=[], source=[], pending=[], held=wanted))
        assert held[0]["error_kind"] == expected["error_kind"] and held[0]["error_bytes"] == expected["error_bytes"]
        assert all(not entries for entries in released[1].values()) and released[0]["error_bytes"] == released[0]["error_kind"] == 0
        assert all(values["status"] == int(injected) * 4 for values, _ in frames[2:])
        if profile == 2:
            assert zero[0]["dest_count"] == zero[0]["dest_capacity"]
            assert not any(item["name"] == "mmap" and item["phase"] == "T" for item in final["events"]), "replacement at full capacity allocated"
        if fault and fault["phase"] == "T":
            callback = next(scope for scope in final["scopes"] if scope["name"] == fault["role"] and scope["start"] < fault["index"] < scope["end"])
            before = "".join(item["line"] + "\n" for item in final["events"][:callback["start"]] if item["name"] in ("mmap", "munmap"))
            assert SOURCE.source(before, self.authority)["live"] == parsed_frames[1]["source"]["live"], "failed callback changed native owner allocations"


def native(group, executable):
    suite = Suite(group, executable)
    if group == "lifecycle":
        for backend in range(4):
            for profile in range(4):
                baseline = suite.run(backend, profile)
                if profile == 2:
                    suite.run(backend, profile, len(baseline["source"]["attempts"]) + 1, baseline, unreached=True)
        assert suite.count == 20 and suite.denials == 0
    else:
        backend = GROUPS.index(group)
        for profile in range(4):
            baseline = suite.run(backend, profile)
            for point in range(1, len(baseline["source"]["attempts"]) + 1):
                suite.run(backend, profile, point, baseline)
        assert suite.classes["replacement"] and suite.classes["displaced"] and suite.classes["recovery"] and suite.classes["owned-error"]
    print(f"PASS replacement-sinks group={group} cases={suite.count} reached-oom={suite.denials} classes={dict(sorted(suite.classes.items()))}")


def controls():
    count = SOURCE.controls()
    def line(body):
        return "[0000000000401002] " + body + "\n"
    def marker(token):
        return line(f'write(2, "\\x{ord(token):02x}", 1) = 1')
    allocation = line("mmap(NULL, 48, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000")
    valid = marker("U") + marker("A") + allocation + marker("a") + marker("u") + marker("C") + marker("c") + marker("T") + marker("S") + marker("R") + marker("r") + marker("t")
    assert events(valid)["markers"] == b"UAauCcTSRrt"
    count += 1
    for bad in (marker("C") + allocation + marker("c"), marker("T") + allocation + marker("t"),
                marker("C") + marker("S") + marker("c"), marker("T") + marker("A"), marker("D"),
                valid + line('write(8, "\\x61", 1) = 1'), valid + line('openat(AT_FDCWD, NULL, 0) = -1 EFAULT (Bad address)')):
        try:
            events(bad)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("phase/native control accepted mutated effects")
    for backend in range(4):
        stopped = model(backend, 3, 4)
        assert stopped["tag"] == 2 and stopped["committed"] == stopped["replaced"] == 2
        assert stopped["destination"] == [row(backend, 1, 66)] and stopped["history"] == [row(backend, 1, 50)] and stopped["pending"] == [row(backend, 1, 65)]
        assert stopped["source"] == [row(backend, 1, 67)] and stopped["error_bytes"] == 5
        rejected = model(backend, 0, 0, fail_role="R", fail_call=1)
        assert rejected["tag"] == 1 and rejected["committed"] == rejected["replaced"] == 0 and rejected["pending"] == [row(backend, 1, 65)]
        displaced = model(backend, 1, 4, fail_role="D", fail_call=1)
        assert displaced["tag"] == 2 and displaced["committed"] == displaced["replaced"] == 1 and displaced["pending"] == [row(backend, 1, 50)]
        before = initial(backend, 3, 4)
        dest, history = completed(backend, 3, 4)
        assert sorted(list(before[0].values()) + before[1]) == sorted(dest + history)
        count += 4
    left = events(valid)
    right = events(valid.replace(" = 0x7fff10000000", " = -1 ENOMEM (Cannot allocate memory) (INJECTED)"))
    bind(left, right, 1)
    count += 1
    for changed in (valid.replace(", 48,", ", 49,"), valid.replace("00401002", "00401003"), valid.replace('\\x41', '\\x42').replace('\\x61', '\\x62')):
        try:
            bind(left, events(changed.replace(" = 0x7fff10000000", " = -1 ENOMEM (Cannot allocate memory) (INJECTED)")), 1)
        except AssertionError:
            count += 1
        else:
            raise AssertionError("reached fault accepted changed source prefix/role")
    print(f"PASS replacement-sinks CPU controls={count}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        assert len(sys.argv) == 3
        native(sys.argv[1], sys.argv[2])
