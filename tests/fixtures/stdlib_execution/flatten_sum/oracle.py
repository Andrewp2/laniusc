"""Independent byte grammar/prefix sums and actual app source-owner ledger."""
import ast
from collections import Counter
import importlib.util
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("flatten_sum_source_authority", HERE.parents[1] / "extended/archive_source/ledger.py")
SOURCE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(SOURCE)
TRUSTED = SOURCE.TRUSTED
CALLS = {"mmap", "munmap", "read", "write", "rt_sigaction", "exit", "exit_group"}
HORIZONTAL = b" \t\r\v\f"
MIN, MAX = -(1 << 63), (1 << 63) - 1
USAGE = b"usage: flatten_sum [--input-bytes N] [--rows N] [--values N] [--output-bytes N] [--read-calls N] [--write-calls N]\n"


def model(data):
    """Do not inherit Python int/split's broader Unicode/underscore grammar."""
    if not data:
        return [], b""
    lines = data.split(b"\n")
    if lines[-1] == b"":
        lines.pop()
    rows, total, output = [], 0, bytearray()
    for line in lines:
        tokens = re.findall(rb"[^ \t\r\v\f]+", line)
        values = []
        for token in tokens:
            if not re.fullmatch(rb"[+-]?[0-9]+", token):
                raise ValueError("integer syntax")
            value = int(token)
            if not MIN <= value <= MAX:
                raise ValueError("integer width")
            values.append(value)
        rows.append(values)
    for row in rows:
        for value in row:
            total += value
            if not MIN <= total <= MAX:
                raise ValueError("running overflow")
            output += str(total).encode() + b"\n"
    return rows, bytes(output)


def events(text):
    assert text.endswith("\n"), "unfinished trace"
    result, counts = [], Counter()
    for index, line in enumerate(text.splitlines()):
        match = TRUSTED.LINE.fullmatch(line)
        assert match and match[2] in CALLS, ("unexpected app syscall", line)
        ip, name, arguments, answer = match.groups()
        counts[name] += 1
        result.append(dict(ip=int(ip, 16), name=name, args=TRUSTED.arguments(arguments),
                           result=answer, ordinal=counts[name], index=index, line=line))
    return result


def rule(call, when=1, error=None, retval=None, repeat=False):
    assert call in CALLS and when > 0 and ((error is None) != (retval is None))
    return dict(call=call, when=when, error=error, retval=retval, repeat=repeat)


def reached(found, rules):
    expected = set()
    for item in rules:
        selected = [entry for entry in found if entry["name"] == item["call"] and
                    (entry["ordinal"] >= item["when"] if item["repeat"] else entry["ordinal"] == item["when"])]
        assert selected, ("unreached injection", item)
        for entry in selected:
            assert "INJECTED" in entry["result"], entry
            if item["error"]:
                assert entry["result"].split()[:2] == ["-1", item["error"]], entry
            else:
                assert int(entry["result"].split()[0]) == item["retval"], entry
            expected.add(entry["index"])
    assert expected == {entry["index"] for entry in found if "INJECTED" in entry["result"]}, "unexpected injection"


def bind(baseline, actual, item):
    old = [entry for entry in baseline["events"] if entry["name"] == item["call"] and entry["ordinal"] == item["when"]]
    new = [entry for entry in actual["events"] if entry["name"] == item["call"] and entry["ordinal"] == item["when"]]
    assert len(old) == len(new) == 1, ("no baseline call", item)
    old, new = old[0], new[0]
    assert old["ip"] == new["ip"], ("wrong injected instruction", old, new)
    if item["call"] in ("read", "write"):
        assert old["args"][0] == new["args"][0] and old["args"][2] == new["args"][2], (old, new)
    elif item["call"] == "mmap":
        before = [entry for entry in baseline["events"] if entry["name"] == "mmap" and entry["ordinal"] <= item["when"]]
        after = [entry for entry in actual["events"] if entry["name"] == "mmap" and entry["ordinal"] <= item["when"]]
        assert [(entry["ip"], entry["args"]) for entry in before] == [(entry["ip"], entry["args"]) for entry in after], "allocation prefix changed"
    else:
        assert old["args"][0] == new["args"][0]


def source_owners(found, profile, directory, status, stdout):
    terminals = [entry for entry in found if entry["name"] in ("exit", "exit_group")]
    assert len(terminals) == 1 and terminals[0] is found[-1], "missing final explicit process exit"
    assert int(terminals[0]["args"][0]) == status and terminals[0]["result"] == "?", terminals
    maps = "".join(entry["line"] + "\n" for entry in found if entry["name"] in ("mmap", "munmap"))
    owners = TRUSTED.source_maps(maps, profile, directory)
    # Kernel exit is not a munmap event. The unchanged verifier requires every
    # requested source owner explicitly released before this terminal syscall.
    accepted = bytearray()
    for entry in found:
        if entry["name"] == "write" and entry["args"][0] == "1" and "INJECTED" not in entry["result"]:
            answer = entry["result"].split()[0]
            if answer.isdecimal():
                count = int(answer)
                payload = TRUSTED.quoted(entry["args"][1])
                assert count <= len(payload) and count <= int(entry["args"][2])
                accepted += payload[:count]
    assert bytes(accepted) == stdout, ("stdout not backed by actual writes", accepted, stdout)
    return owners


class Cases:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.root = Path(tempfile.mkdtemp(prefix="lanius-flatten-sum-" + group + "-"))
        self.profile = TRUSTED.verified_sites(self.executable, self.root)
        pairs, named = self.profile
        assert pairs and not named and getattr(pairs, "executable_ranges", []), "raw ELF authority required"
        self.count = 0

    def run(self, label, data=b"", args=(), rules=(), broken_pipe=False):
        directory = self.root / ("%03d-" % self.count + label)
        directory.mkdir()
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
                   "-o", str(trace), "-e", "trace=" + ",".join(sorted(CALLS))]
        assert len({item["call"] for item in rules}) == len(rules), "duplicate injection replaces an earlier rule"
        for item in rules:
            action = "error=" + item["error"] if item["error"] else "retval=" + str(item["retval"])
            command += ["-e", "inject=%s:%s:when=%d%s" % (item["call"], action, item["when"], "+" if item["repeat"] else "")]
        command += [str(self.executable), *args]
        (directory / "input.bin").write_bytes(data)
        (directory / "command.txt").write_text(repr(command) + "\n")
        writer = None
        try:
            if broken_pipe:
                reader, writer = os.pipe()
                os.close(reader)
            output = subprocess.run(command, input=data, stdout=writer if broken_pipe else subprocess.PIPE,
                                    stderr=subprocess.PIPE, cwd=directory, timeout=5)
        finally:
            if writer is not None:
                os.close(writer)
        stdout = output.stdout or b""
        (directory / "stdout.bin").write_bytes(stdout)
        (directory / "stderr.bin").write_bytes(output.stderr)
        (directory / "status.txt").write_text(str(output.returncode) + "\n")
        found = events(trace.read_text())
        reached(found, rules)
        owners = source_owners(found, self.profile, directory, output.returncode, stdout)
        self.count += 1
        return dict(code=output.returncode, stdout=stdout, stderr=output.stderr, events=found,
                    owners=owners, evidence=directory)

    def finish(self, group):
        print("flatten-sum group=%s cases=%d" % (group, self.count))


def check(result, code, output=b""):
    assert result["code"] == code and result["stdout"] == output, (result["evidence"], result["code"], result["stdout"], result["stderr"])
    if code == 0:
        assert not result["stderr"], result


def physical_rows(result, rows, output_capacity):
    """Witness real allocated inners and their release before publication/error.

    The workflow deliberately allocates every physical row, even empty rows.
    Its final reservation is the output stage; adapters introduce no scratch.
    No historical allocator-call floor is used for reached OOM enumeration.
    """
    allocations = result["owners"]["allocations"]
    assert len(allocations) >= len(rows) + 1
    inners, stage = allocations[-len(rows)-1:-1] if rows else [], allocations[-1]
    assert stage["length"] == output_capacity
    assert [entry["length"] for entry in inners] == [max(1, len(row)) * 8 for row in rows], inners
    writes = [entry["index"] for entry in result["events"] if entry["name"] == "write"]
    boundary = min(writes) if writes else result["events"][-1]["index"]
    for inner in inners:
        address = int(inner["result"].split()[0], 16)
        frees = [entry for entry in result["events"] if entry["name"] == "munmap" and int(entry["args"][0], 16) == address]
        assert len(frees) == 1 and frees[0]["index"] < boundary, ("inner not explicitly released before output", inner, frees)


def models(cases):
    authored = [b"", b"\n", b"\n\n", b" \t\r", b"1 2\n\n-3 +4\n", b"-0 +000 001\r\n\v\f5", str(MIN).encode(), str(MAX).encode(), b"0\n" * 12]
    for data in authored:
        _, expected = model(data)
        check(cases.run("authored", data), 0, expected)
    rng = random.Random(0x39E41327)
    for _ in range(128):
        rows = [[rng.randrange(-1000000, 1000001) for _ in range(rng.randrange(6))] for _ in range(rng.randrange(9))]
        encoded = []
        for row in rows:
            encoded.append(rng.choice([b" ", b"\t", b"\r\v"]).join((b"+" if value >= 0 and rng.randrange(2) else b"") + str(value).encode() for value in row))
        data = b"\n".join(encoded)
        if rows and rng.randrange(2):
            data += b"\n"
        _, expected = model(data)
        check(cases.run("independent-model", data), 0, expected)
    data = b"1 2\n\n3 4 5\n \t\n6\n"
    rows, expected = model(data)
    result = cases.run("physical-empty-and-nonempty", data, ("--input-bytes", "257", "--output-bytes", "509"))
    check(result, 0, expected)
    physical_rows(result, rows, 509)


def bounds(cases):
    check(cases.run("help", args=("--help",)), 0, USAGE)
    check(cases.run("closed-help", args=("--help",), broken_pipe=True), 3)
    malformed = [b"+", b"-", b"1_0", b"1.0", b"1\x00", b"\xff", b"\xc2\xa01", b"1,2", b"1#2", b"--1", str(MAX + 1).encode(), str(MIN - 1).encode()]
    for data in malformed:
        check(cases.run("malformed-byte-or-integer", data), 2)
    for data in [(str(MAX) + " 1 8\n9\n\n10\n").encode(), (str(MIN) + " -1 8\n9\n10\n").encode()]:
        result = cases.run("overflow-active-and-outer-remainder", data, ("--input-bytes", "257", "--output-bytes", "509"))
        check(result, 2)
        lines = data.splitlines()
        rows = [[int(value) for value in line.split()] for line in lines]
        physical_rows(result, rows, 509)
    bad_args = [("--unknown", "1"), ("--rows",), ("--rows", "1", "--rows", "2"), ("--rows", "-1"),
                ("--rows", "+1"), ("--rows", "1_0"), ("--rows", "4097"), ("--values", "65537"),
                ("--input-bytes", "1048577"), ("--output-bytes", "1376257"), ("--read-calls", "65537"),
                ("--write-calls", "65537"), ("--help", "x"), tuple(["x"] * 13), ("x" * 513,)]
    for args in bad_args:
        result = cases.run("argument-admission", b"1", args)
        check(result, 2)
        assert not any(entry["name"] == "read" for entry in result["events"]), "invalid argument consumed stdin"
    for flag, value, data, code, expected in [
        ("--input-bytes", "0", b"", 0, b""), ("--input-bytes", "0", b"1", 2, b""),
        ("--input-bytes", "3", b"1 2", 0, b"1\n3\n"), ("--input-bytes", "2", b"1 2", 2, b""),
        ("--rows", "0", b"", 0, b""), ("--rows", "0", b"\n", 2, b""),
        ("--rows", "1", b"\n", 0, b""), ("--rows", "1", b"\n\n", 2, b""),
        ("--values", "0", b"\n\t", 0, b""), ("--values", "0", b"1", 2, b""),
        ("--values", "2", b"1 2", 0, b"1\n3\n"), ("--values", "1", b"1 2", 2, b""),
        ("--output-bytes", "0", b"\n", 0, b""), ("--output-bytes", "0", b"1 2\n3\n", 2, b""),
        ("--output-bytes", "4", b"1 2", 0, b"1\n3\n"), ("--output-bytes", "3", b"1 2\n3\n", 2, b""),
        ("--read-calls", "0", b"", 2, b""), ("--read-calls", "1", b"", 0, b""),
        ("--read-calls", "1", b"1", 2, b""), ("--write-calls", "0", b"", 0, b""),
        ("--write-calls", "0", b"1", 2, b""), ("--write-calls", "1", b"1", 0, b"1\n")]:
        check(cases.run("exact-or-over-limit", data, (flag, value)), code, expected)
    data = b"1 2 3\n4 5\n\n6\n"
    result = cases.run("output-limit-active-and-outer-remainder", data, ("--input-bytes", "257", "--output-bytes", "1"))
    check(result, 2)
    physical_rows(result, model(data)[0], 1)


def allocations(cases):
    data = b"1 2\n\n3 4\n \t\n5\n"
    args = ("--rows", "8", "--input-bytes", "64", "--output-bytes", "256")
    baseline = cases.run("baseline", data, args)
    check(baseline, 0, model(data)[1])
    points = baseline["owners"]["allocations"]
    assert 0 < len(points) <= 128
    for allocation in points:
        item = rule("mmap", allocation["ordinal"], error="ENOMEM")
        result = cases.run("reached-source-oom", data, args, [item])
        bind(baseline, result, item)
        check(result, 4)


def faults(cases):
    data = b"1 2\n\n3 4\n5\n"
    expected = model(data)[1]
    baseline = cases.run("baseline", data)
    check(baseline, 0, expected)
    for item, code in [(rule("rt_sigaction", error="EIO"), 3), (rule("read", error="EIO"), 3),
                       (rule("read", retval=1025), 3), (rule("write", error="EIO"), 3),
                       (rule("write", retval=0), 3), (rule("write", retval=len(expected)+1), 3)]:
        result = cases.run("single-reached-fault", data, rules=[item])
        bind(baseline, result, item)
        check(result, code)
    for item in [rule("read", error="EINTR"), rule("write", error="EINTR")]:
        result = cases.run("one-interruption", data, rules=[item])
        bind(baseline, result, item)
        check(result, 0, expected)
    for call, flag in [("read", "--read-calls"), ("write", "--write-calls")]:
        result = cases.run("interruption-cap", data, (flag, "2"), [rule(call, error="EINTR", repeat=True)])
        check(result, 2)
        assert len([entry for entry in result["events"] if entry["name"] == call and entry["args"][0] in ("0", "1")]) == 2
    for args in [(), ("--help",)]:
        result = cases.run("actual-closed-reader", data, args, broken_pipe=True)
        check(result, 3)
        assert any(entry["name"] == "write" and entry["result"].startswith("-1 EPIPE ") and "INJECTED" not in entry["result"] for entry in result["events"])
    many = b"1 " * 600
    _, output = model(many)
    complete = cases.run("multi-write-baseline", many)
    check(complete, 0, output)
    second = [entry for entry in complete["events"] if entry["name"] == "write" and entry["ordinal"] == 2]
    assert len(second) == 1 and second[0]["args"][0] == "1", "baseline second write is not stdout"
    result = cases.run("real-output-prefix-before-call-cap", many, ("--write-calls", "1"))
    check(result, 2, output[:1024])
    target = rule("write", 2, error="EIO")
    result = cases.run("real-prefix-then-output-error", many, rules=[target])
    bind(complete, result, target)
    assert next(entry for entry in result["events"] if entry["name"] == "write" and entry["ordinal"] == 2)["args"][0] == "1"
    check(result, 3, output[:1024])


def controls():
    count = 0
    for data, rows, out in [(b"", [], b""), (b"\n", [[]], b""), (b"\n\n", [[], []], b""),
                            (b"1\r\v2\f\t-3\n", [[1, 2, -3]], b"1\n3\n0\n")]:
        assert model(data) == (rows, out); count += 1
    for data in [b"1_0", b"\xff", b"\x001", b"\xc2\xa01", b"+", str(MAX+1).encode(), (str(MAX)+" 1").encode()]:
        try: model(data)
        except ValueError: count += 1
        else: raise AssertionError(data)
    sample = events('[10] read(0, 0x1000, 1024) = -1 EIO (INJECTED)\n')
    reached(sample, [rule("read", error="EIO")]); count += 1
    for item in [rule("read", 2, error="EIO"), rule("read", error="EINTR"), rule("read", retval=0)]:
        try: reached(sample, [item])
        except AssertionError: count += 1
        else: raise AssertionError(item)
    a = dict(events=events('[10] mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x10000\n'))
    b = dict(events=events('[10] mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = -1 ENOMEM (INJECTED)\n'))
    bind(a, b, rule("mmap", error="ENOMEM")); count += 1
    b["events"][0]["ip"] += 1
    try: bind(a, b, rule("mmap", error="ENOMEM"))
    except AssertionError: count += 1
    else: raise AssertionError("changed instruction accepted")
    source = (HERE.parents[3] / "sample_programs/library/flatten_sum.lani").read_text()
    for item in re.finditer(r'literal\(("(?:\\.|[^"\\])*"),(\d+)\)', source):
        assert len(ast.literal_eval(item[1]).encode()) == int(item[2]), item[0]
    count += 1
    print("flatten-sum CPU controls=%d" % count)


def main():
    if sys.argv[1:] == ["controls"]:
        controls(); return
    assert len(sys.argv) == 3 and sys.argv[1] in ("models", "bounds", "allocations", "faults")
    group = sys.argv[1]
    cases = Cases(sys.argv[2], group)
    try:
        globals()[group](cases)
        cases.finish(group)
    except BaseException:
        print("flatten-sum evidence=" + str(cases.root), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
