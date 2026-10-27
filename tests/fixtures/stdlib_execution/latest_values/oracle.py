"""Actual latest-values CLI checks with independent TSV/update model."""
import ast
import importlib.util
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("latest_values_strict_app_ledger", HERE.parent / "flatten_sum/oracle.py")
LEDGER = importlib.util.module_from_spec(spec)
spec.loader.exec_module(LEDGER)
TRUSTED = LEDGER.TRUSTED
rule, reached, bind = LEDGER.rule, LEDGER.reached, LEDGER.bind
USAGE = b"usage: latest_values [--input-bytes N] [--rows N] [--key-bytes N] [--value-bytes N] [--history N] [--output-bytes N] [--read-calls N] [--write-calls N]\n"


def parse(data):
    data.decode("utf-8", "strict")
    if any((byte < 32 and byte not in (9, 10)) or byte == 127 for byte in data):
        raise ValueError("C0 or DEL")
    if not data:
        return []
    rows = data.split(b"\n")
    if rows[-1] == b"":
        rows.pop()
    result = []
    for row in rows:
        fields = row.split(b"\t")
        if len(fields) != 2 or not fields[0]:
            raise ValueError("strict TSV row")
        result.append(tuple(fields))
    return result


def model(data, history_limit=None):
    entries = parse(data)
    current, history, replaced = {}, [], 0
    for index, (key, value) in enumerate(entries):
        previous = (key, current[key]) if key in current else None
        current[key] = value
        if previous is not None:
            replaced += 1
            if history_limit is not None and len(history) == history_limit:
                return b"", (index + 1, replaced, len(entries) - index - 1, *previous, key, value)
            history.append(previous)
    rows = [(b"old", key, value) for key, value in history]
    rows += [(b"new", key, current[key]) for key in sorted(current)]
    return b"".join(b"\t".join(row) + b"\n" for row in rows), None


def undelivered(result):
    rows = [line.split(b"\t") for line in result["stderr"].split(b"\n") if line.startswith(b"undelivered\t")]
    if not rows:
        return None
    assert len(rows) == 1 and len(rows[0]) == 8, rows
    row = rows[0]
    assert all(re.fullmatch(rb"[0-9]+", field) for field in row[1:4]), row
    return tuple(int(field) for field in row[1:4]) + tuple(row[4:])


def diagnostic_boundary(result, expected):
    packet = b"undelivered\t" + b"\t".join(str(value).encode() if isinstance(value, int) else value for value in expected) + b"\n"
    collected = bytearray()
    first = None
    for entry in result["events"]:
        if entry["name"] == "write" and entry["args"][0] == "2" and "INJECTED" not in entry["result"]:
            count = entry["result"].split()[0]
            if count.isdecimal() and int(count) > 0:
                supplied = TRUSTED.quoted(entry["args"][1])
                assert int(count) <= min(len(supplied), int(entry["args"][2])), entry
                payload = supplied[:int(count)]
                if first is None:
                    first = entry["index"]
                collected += payload
                assert packet.startswith(collected), ("causal diagnostic prefix differs", packet, collected)
                if collected == packet:
                    return first, entry["index"]
    raise AssertionError("no complete actual-write-backed causal record")


def live_through_diagnostic(result, sizes, boundary):
    first, complete = boundary
    assert first <= complete
    for size in sizes:
        owners = [entry for entry in result["owners"]["allocations"] if entry["length"] == size]
        assert len(owners) == 1, ("ambiguous witness allocation", size, owners)
        owner = owners[0]
        original = [entry for entry in result["events"] if entry["name"] == "mmap" and entry["ordinal"] == owner["ordinal"]]
        assert len(original) == 1, ("missing/ambiguous original allocation", owner, original)
        allocation = original[0]
        assert (allocation["ip"], allocation["args"], allocation["result"]) == (owner["ip"], TRUSTED.arguments(owner["args"]), owner["result"]), ("allocation identity differs", owner, allocation)
        assert allocation["index"] < first, ("owner was not allocated before causal diagnostic began", size, allocation, boundary)
        address = int(owner["result"].split()[0], 16)
        releases = [entry for entry in result["events"] if entry["name"] == "munmap" and int(entry["args"][0], 16) == address]
        assert len(releases) == 1 and releases[0]["index"] > complete, ("current/pending owner freed before causal record completed", size, releases)


class Cases:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.root = Path(tempfile.mkdtemp(prefix="lanius-latest-values-" + group + "-"))
        self.profile = TRUSTED.verified_sites(self.executable, self.root)
        pairs, named = self.profile
        assert pairs and not named and getattr(pairs, "executable_ranges", []), "raw ELF source authority required"
        self.count = 0

    def run(self, label, data=b"", args=(), rules=(), broken_pipe=False):
        directory = self.root / ("%03d-" % self.count + label)
        directory.mkdir()
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096", "-e", "signal=none",
                   "-o", str(trace), "-e", "trace=" + ",".join(sorted(LEDGER.CALLS))]
        assert len({item["call"] for item in rules}) == len(rules), "duplicate injection option"
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
            process = subprocess.run(command, input=data, stdout=writer if broken_pipe else subprocess.PIPE,
                                     stderr=subprocess.PIPE, cwd=directory, timeout=5)
        finally:
            if writer is not None:
                os.close(writer)
        output = process.stdout or b""
        (directory / "stdout.bin").write_bytes(output)
        (directory / "stderr.bin").write_bytes(process.stderr)
        (directory / "status.txt").write_text(str(process.returncode) + "\n")
        found = LEDGER.events(trace.read_text())
        reached(found, rules)
        owners = LEDGER.source_owners(found, self.profile, directory, process.returncode, output)
        self.count += 1
        return dict(code=process.returncode, stdout=output, stderr=process.stderr, events=found, owners=owners, evidence=directory)

    def finish(self, group):
        print("latest-values group=%s cases=%d" % (group, self.count))


def check(result, code=0, output=b""):
    assert result["code"] == code and result["stdout"] == output, (result["evidence"], result["code"], result["stdout"], result["stderr"])
    if code == 0:
        assert not result["stderr"]


def models(cases):
    authored = [b"", b"k\t\n", b"k\tv", b"k\told\nk\tnew\n", b"b\tB\na\tA\nb\tlast\n",
                "é\t值\né\t\né\t最后\n".encode(), b" spaced key \t value with spaces \n", b"k\t\xc2\x80\n"]
    for data in authored:
        check(cases.run("authored", data), output=model(data)[0])
    rng = random.Random(0x48837130)
    keys = [b"a", b"b", b"z", b"aa", b" spaced ", "é".encode(), "é".encode(), "键".encode()]
    values = [b"", b"one", b"two", b"  ", "值".encode(), "🙂".encode()]
    for _ in range(128):
        entries = [(rng.choice(keys), rng.choice(values) + str(index).encode()) for index in range(rng.randrange(18))]
        data = b"\n".join(key + b"\t" + value for key, value in entries)
        if entries and rng.randrange(2):
            data += b"\n"
        check(cases.run("independent-model", data), output=model(data)[0])


def bounds(cases):
    check(cases.run("help", args=("--help",)), output=USAGE)
    invalid = [b"\n", b"missing", b"\tvalue", b"k\tv\textra", b"k\tv\r\n", b"k\t\x00", b"k\t\x01", b"k\t\x7f", b"\xff\tv", b"k\t\xc0\x80", b"k\t\xed\xa0\x80", b"k\t\xf4\x90\x80\x80"]
    for data in invalid:
        check(cases.run("invalid-tsv-or-utf8", data), 2)
    args_bad = [("--unknown", "1"), ("--history",), ("--history", "0", "--history", "1"),
                ("--rows", "-1"), ("--rows", "+1"), ("--rows", "1_0"), ("--rows", "4097"),
                ("--input-bytes", "2097153"), ("--key-bytes", "4097"), ("--value-bytes", "65537"),
                ("--history", "4097"), ("--output-bytes", "4194305"), ("--read-calls", "65537"),
                ("--write-calls", "65537"), ("--help", "x"), tuple(["x"] * 17), ("x" * 1025,)]
    for args in args_bad:
        result = cases.run("invalid-arguments", b"k\tv", args)
        check(result, 2)
        assert not any(entry["name"] == "read" for entry in result["events"]), "admission consumed input"
    for flag, value, data, code in [
        ("--input-bytes", "0", b"", 0), ("--input-bytes", "0", b"k\t", 2),
        ("--input-bytes", "3", b"k\tv", 0), ("--input-bytes", "2", b"k\tv", 2),
        ("--rows", "0", b"", 0), ("--rows", "0", b"k\t", 2), ("--rows", "1", b"k\t\n", 0),
        ("--rows", "1", b"k\t\nk\tv\n", 2), ("--key-bytes", "0", b"", 0), ("--key-bytes", "0", b"k\t", 2),
        ("--key-bytes", "2", "é\t".encode(), 0), ("--key-bytes", "1", "é\t".encode(), 2),
        ("--value-bytes", "0", b"k\t", 0), ("--value-bytes", "0", b"k\tv", 2),
        ("--value-bytes", "2", "k\té".encode(), 0), ("--value-bytes", "1", "k\té".encode(), 2),
        ("--output-bytes", "0", b"", 0), ("--output-bytes", "0", b"k\t", 2),
        ("--output-bytes", "7", b"k\t", 0), ("--output-bytes", "6", b"k\t", 2),
        ("--read-calls", "0", b"", 2), ("--read-calls", "1", b"", 0), ("--read-calls", "1", b"k\tv", 2),
        ("--write-calls", "0", b"", 0), ("--write-calls", "0", b"k\tv", 2), ("--write-calls", "1", b"k\tv", 0)]:
        check(cases.run("exact-or-over-bound", data, (flag, value)), code, model(data)[0] if code == 0 else b"")
    for history in (0, 1, 2, 3):
        data = b"a\tfirst\nb\tB\na\tsecond\na\tthird\nb\tlast\n"
        expected, failure = model(data, history)
        result = cases.run("history-exact-or-rejection", data, ("--history", str(history)))
        check(result, 2 if failure else 0, expected)
        assert undelivered(result) == failure
    data = b"k\t" + b"o" * 89 + b"\nk\t" + b"n" * 127 + b"\ntail\t" + b"t" * 61 + b"\n"
    expected = model(data, 0)[1]
    result = cases.run("causal-current-new-and-unconsumed-owners", data, ("--history", "0", "--input-bytes", "4091", "--output-bytes", "4093"))
    check(result, 2)
    assert undelivered(result) == expected and expected[:3] == (2, 1, 1)
    boundary = diagnostic_boundary(result, expected)
    live_through_diagnostic(result, (89, 127, 61), boundary)


def full_allocation(result, allocation):
    return next(entry for entry in result["events"] if entry["name"] == "mmap" and entry["ordinal"] == allocation["ordinal"])


def allocations(cases):
    entries = [(bytes([97 + index]), b"old-" + bytes([65 + index]) * (index + 7)) for index in range(6)]
    entries += [(key, b"new-" + bytes([97 + index]) * (index + 13)) for index, (key, _) in enumerate(entries)]
    data = b"\n".join(key + b"\t" + value for key, value in entries) + b"\n"
    args = ("--input-bytes", "4091", "--output-bytes", "4093")
    baseline = cases.run("baseline", data, args)
    check(baseline, output=model(data)[0])
    allocations = baseline["owners"]["allocations"]
    assert 0 < len(allocations) <= 192
    input_maps = [allocation for allocation in allocations if allocation["length"] == 4091]
    output_maps = [allocation for allocation in allocations if allocation["length"] == 4093]
    assert len(input_maps) == len(output_maps) == 1
    input_address = int(input_maps[0]["result"].split()[0], 16)
    input_free = [entry for entry in baseline["events"] if entry["name"] == "munmap" and int(entry["args"][0], 16) == input_address][0]["index"]
    stage = full_allocation(baseline, output_maps[0])["index"]
    categories = {"replacement": 0, "history": 0, "output": 0}
    schedule = []
    for allocation in allocations:
        target = rule("mmap", allocation["ordinal"], error="ENOMEM")
        result = cases.run("reached-source-oom", data, args, [target])
        bind(baseline, result, target)
        check(result, 4)
        index = full_allocation(baseline, allocation)["index"]
        category = "construction"
        if input_free < index < stage:
            failed = undelivered(result)
            category = "history" if failed else "replacement"
            categories[category] += 1
            if failed:
                committed, replaced, remaining, old_key, old_value, new_key, new_value = failed
                assert 0 < replaced <= committed <= len(entries) and remaining == len(entries) - committed
                assert (new_key, new_value) == entries[committed - 1]
                expected = model(b"\n".join(key + b"\t" + value for key, value in entries[:committed]), replaced - 1)[1]
                assert failed[:2] + failed[3:] == expected[:2] + expected[3:]
        if index == stage:
            category = "output"; categories[category] += 1
        schedule.append((allocation["ordinal"], allocation["length"], category))
    assert all(categories.values()), ("missing reached producer class", categories)
    (cases.root / "reached-allocation-schedule.txt").write_text(repr((schedule, categories)) + "\n")


def faults(cases):
    data = b"b\told\na\tA\nb\tnew\n"
    output = model(data)[0]
    baseline = cases.run("baseline", data)
    check(baseline, output=output)
    for target in [rule("rt_sigaction", error="EIO"), rule("read", error="EIO"), rule("read", retval=1025),
                   rule("write", error="EIO"), rule("write", retval=0), rule("write", retval=len(output)+1)]:
        result = cases.run("reached-host-error", data, rules=[target])
        bind(baseline, result, target)
        check(result, 3)
    for target in [rule("read", error="EINTR"), rule("write", error="EINTR")]:
        result = cases.run("single-interruption", data, rules=[target])
        bind(baseline, result, target)
        check(result, output=output)
    for call, flag in [("read", "--read-calls"), ("write", "--write-calls")]:
        result = cases.run("interruption-cap", data, (flag, "2"), [rule(call, error="EINTR", repeat=True)])
        check(result, 2)
        assert len([entry for entry in result["events"] if entry["name"] == call and entry["args"][0] in ("0", "1")]) == 2
    for args in [(), ("--help",)]:
        result = cases.run("actual-closed-reader", data, args, broken_pipe=True)
        check(result, 3)
        assert any(entry["name"] == "write" and entry["result"].startswith("-1 EPIPE ") and "INJECTED" not in entry["result"] for entry in result["events"])
    many = b"\n".join(b"k\t" + str(index).zfill(2).encode() + b"x" * 78 for index in range(25)) + b"\n"
    expected = model(many)[0]
    complete = cases.run("multi-write-baseline", many)
    check(complete, output=expected)
    check(cases.run("actual-prefix-quota", many, ("--write-calls", "1")), 2, expected[:1024])
    target = rule("write", 2, error="EIO")
    failed = cases.run("actual-prefix-eio", many, rules=[target])
    bind(complete, failed, target)
    assert next(entry for entry in failed["events"] if entry["name"] == "write" and entry["ordinal"] == 2)["args"][0] == "1"
    check(failed, 3, expected[:1024])
    failed = cases.run("undelivered-with-broken-diagnostic", b"k\told\nk\tnew\ntail\tstillowned\n", ("--history", "0"), [rule("write", error="EIO", repeat=True)])
    check(failed, 2)
    assert not failed["stderr"], "failed diagnostic must not invent delivered evidence"


def controls():
    count = 0
    for data, expected in [(b"", b""), (b"k\t", b"new\tk\t\n"), (b"k\told\nk\tnew\n", b"old\tk\told\nnew\tk\tnew\n"),
                           (b"b\tB\na\tA\n", b"new\ta\tA\nnew\tb\tB\n")]:
        assert model(data) == (expected, None); count += 1
    for data in [b"\n", b"\tv", b"k\tv\r\n", b"k\t\x00", b"k\tv\tt", b"\xff\tv", b"k\t\xc0\x80", b"k\t\x7f"]:
        try: parse(data)
        except (ValueError, UnicodeError): count += 1
        else: raise AssertionError(data)
    failure = model(b"k\told\nk\tnew\ntail\tv\n", 0)[1]
    assert failure == (2, 1, 1, b"k", b"old", b"k", b"new"); count += 1
    record = b"undelivered\t2\t1\t1\tk\told\tk\tnew\nlatest_values: failed\n"
    assert undelivered(dict(stderr=record)) == failure; count += 1
    try: undelivered(dict(stderr=record + record))
    except AssertionError: count += 1
    else: raise AssertionError("duplicate causal records")
    sample = LEDGER.events('[10] write(1, "\\x61", 1) = -1 EIO (INJECTED)\n')
    reached(sample, [rule("write", error="EIO")]); count += 1
    for target in [rule("write", 2, error="EIO"), rule("write", error="EINTR")]:
        try: reached(sample, [target])
        except AssertionError: count += 1
        else: raise AssertionError(target)
    packet = record.split(b"\n")[0] + b"\n"
    quoted = '"' + ''.join('\\x%02x' % byte for byte in packet) + '"'
    written = dict(events=LEDGER.events('[10] write(2, %s, %d) = %d\n' % (quoted, len(packet), len(packet))))
    assert diagnostic_boundary(written, failure) == (0, 0); count += 1
    synthetic = dict(events=LEDGER.events('[10] write(2, %s, %d) = %d (INJECTED)\n' % (quoted, len(packet), len(packet))))
    try: diagnostic_boundary(synthetic, failure)
    except AssertionError: count += 1
    else: raise AssertionError("synthetic positive write accepted as delivered diagnostic")
    sizes = (89, 127, 61)
    maps = ['[20] mmap(NULL, %d, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = %s\n' % (size, hex(0x100000000 + index * 4096)) for index, size in enumerate(sizes)]
    frees = ['[30] munmap(%s, %d) = 0\n' % (hex(0x100000000 + index * 4096), size) for index, size in enumerate(sizes)]
    writes = ['[10] write(2, "%s", %d) = %d\n' % (''.join('\\x%02x' % byte for byte in part), len(part), len(part)) for part in (packet[:10], packet[10:])]
    def owned_trace(lines):
        found = LEDGER.events(''.join(lines))
        allocations = [dict(entry, length=int(entry["args"][1]), args=", ".join(entry["args"])) for entry in found if entry["name"] == "mmap"]
        return dict(owners=dict(allocations=allocations), events=found)
    owned = owned_trace(maps + writes + frees)
    live_through_diagnostic(owned, sizes, diagnostic_boundary(owned, failure)); count += 1
    for lines, label in [
        (maps + writes[:1] + frees[1:2] + writes[1:] + frees[:1] + frees[2:], "current owner freed during diagnostic"),
        (maps[:2] + writes + maps[2:] + frees, "pending owner allocated after complete diagnostic"),
        (maps[:2] + writes[:1] + maps[2:] + writes[1:] + frees, "pending owner allocated after diagnostic began"),
    ]:
        altered = owned_trace(lines)
        try: live_through_diagnostic(altered, sizes, diagnostic_boundary(altered, failure))
        except AssertionError: count += 1
        else: raise AssertionError(label)
    owned["owners"]["allocations"][1]["ordinal"] = 1
    try: live_through_diagnostic(owned, sizes, diagnostic_boundary(owned, failure))
    except AssertionError: count += 1
    else: raise AssertionError("owner ordinal bound to a different original allocation")
    source = (HERE.parents[3] / "sample_programs/library/latest_values.lani").read_text()
    for item in re.finditer(r'literal\(("(?:\\.|[^"\\])*"),(\d+)\)', source):
        assert len(ast.literal_eval(item[1]).encode()) == int(item[2]), item[0]
    count += 1
    print("latest-values CPU controls=%d" % count)


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
        print("latest-values evidence=" + str(cases.root), file=sys.stderr)
        raise


if __name__ == "__main__":
    main()
