"""Independent Python CSV/stable-sort model and bounded native fault checks."""
from collections import Counter
import csv
from io import StringIO
import os
from pathlib import Path
import random
import re
import subprocess
import sys
import tempfile

CAP = 4 << 20
HELP = (b"Usage: sort-rows [--column N] [--numeric] [--descending] [--header] [--help]\n"
        b"Read UTF-8 CSV through EOF; sort by a 1-based column (default 1).\n"
        b"Text order compares UTF-8 bytes; numeric order requires strict signed i64 cells.\n"
        b"Equal keys retain input order, including descending. --header preserves the first row.\n"
        b"Short options: -c N, -n, -r, -H, -h. Empty input is allowed.\n"
        b"Limits: 4 MiB input, 16384 data rows, 64 fields, 8 MiB staged output.\n")
ERROR = b"sort-rows: operation failed\n"
COUNTS = {"model": 37, "rejection": 33, "cli": 39, "io": 14}
INTEGER = re.compile(r"[+-]?[0-9]+\Z", re.ASCII)


def encode(rows, *, quoted=True, ending="\r\n"):
    stream = StringIO(newline="")
    csv.writer(stream, quoting=csv.QUOTE_ALL if quoted else csv.QUOTE_MINIMAL,
               lineterminator=ending).writerows(rows)
    return stream.getvalue().encode("utf-8")


def integer(text):
    assert INTEGER.fullmatch(text), ("strict signed decimal", text)
    value = int(text)
    assert -(1 << 63) <= value < (1 << 63), ("signed 64-bit bounds", text)
    return value


def model_rows(rows, column=1, numeric=False, descending=False, header=False):
    if not rows:
        return []
    assert 1 <= column <= len(rows[0])
    assert all(len(row) == len(rows[0]) for row in rows)
    begin = 1 if header else 0
    key = (lambda row: integer(row[column - 1])) if numeric else (lambda row: row[column - 1].encode("utf-8"))
    # Python's stable sorting reverses only key order: equivalent rows retain
    # input order even in descending mode. This does not reproduce merge passes.
    return rows[:begin] + sorted(rows[begin:], key=key, reverse=descending)


def events(text):
    found, counts, live = [], Counter(), {}
    for line in text.splitlines():
        match = re.fullmatch(r"(read|write|mmap|munmap|mremap|brk|rt_sigaction)\((.*)\)\s+=\s+(.*)", line)
        assert match, ("unexpected trace line", line)
        name, args, answer = match.groups()
        counts[name] += 1
        item = dict(name=name, args=args, answer=answer, ordinal=counts[name], line=line)
        found.append(item)
        if name == "mmap":
            item["size"] = int(args.split(",")[1].strip())
            if answer.startswith("0x"):
                address = answer.split()[0]
                assert address not in live, (line, live)
                live[address] = item["size"]
            else:
                assert answer.startswith("-1 ENOMEM ") and "INJECTED" in answer, line
        elif name == "munmap":
            address, size = args.split(",")
            assert answer == "0" and live.pop(address.strip(), None) == int(size.strip()), line
        elif name in ("mremap", "brk"):
            raise AssertionError(("unexpected allocation service", line))
    assert not live, ("observed unreleased mappings", live)
    return found


def same_release(item, allocation):
    return (item["name"] == "munmap" and item["answer"] == "0"
            and item["args"] == f'{allocation["answer"].split()[0]}, {allocation["size"]}')


def release_position(found, position):
    allocation = found[position]
    return next(index for index in range(position + 1, len(found))
                if same_release(found[index], allocation))


def stable_workspace(found, count):
    # Source-bound identification, without assuming the private Row ABI width:
    # five pushes grow Row Vec capacity 4 -> 8. Stable sort alone reserves five
    # rows and makes no host calls between that mmap and its exact munmap.
    # Its unit must match both real Vec generations, the capacity-eight owner
    # must stay live, and output staging must follow the scratch release.
    assert count == 5
    candidates = []
    for index, item in enumerate(found[:-1]):
        if item["name"] != "mmap" or not item["answer"].startswith("0x"):
            continue
        if item["size"] == 0 or item["size"] % count or not same_release(found[index + 1], item):
            continue
        unit = item["size"] // count
        for source_index, source in enumerate(found[:index]):
            if (source["name"] != "mmap" or not source["answer"].startswith("0x")
                    or source["size"] != 8 * unit):
                continue
            source_end = release_position(found, source_index)
            if source_end <= index + 1:
                continue
            for prior_index, prior in enumerate(found[:source_index]):
                if (prior["name"] != "mmap" or not prior["answer"].startswith("0x")
                        or prior["size"] != 4 * unit
                        or not same_release(found[source_index + 1], prior)):
                    continue
                # Whole-input EOF precedes parsing; sorting is after all reads.
                if not any(event["name"] == "read" and event["answer"] == "0"
                           for event in found[:prior_index]):
                    continue
                if any(event["name"] == "read" for event in found[index:]):
                    continue
                later_maps = [position for position in range(index + 2, source_end)
                              if found[position]["name"] == "mmap"]
                publications = [position for position, event in enumerate(found)
                                if event["name"] == "write" and event["args"].startswith("1,")]
                if not later_maps or not publications or min(publications) <= source_end:
                    continue
                candidates.append((index, source_index, prior_index))
    assert len(candidates) == 1, ("ambiguous or missing stable-sort workspace", candidates)
    scratch_index, source_index, prior_index = candidates[0]
    return found[scratch_index], found[source_index], found[prior_index]


class Runner:
    def __init__(self, executable, mode):
        self.executable = str(Path(executable).resolve())
        self.directory = Path(tempfile.mkdtemp(prefix=f"sort-rows-{mode}-"))
        self.count = 0

    def run(self, name, arguments=(), data=b"", *, status=0, output=b"",
            read_error=False, closed_reader=False, trace=False, injection=None, diagnostic=True):
        prefix = self.directory / name
        command = [self.executable, *arguments]
        if trace:
            traced = ["strace", "--kill-on-exit", "-qq", "-s", "64", "-e", "signal=none",
                      "-e", "trace=read,write,mmap,munmap,mremap,brk,rt_sigaction",
                      "-o", str(prefix.with_suffix(".trace"))]
            if injection:
                call, ordinal, failure = injection
                traced += ["-e", f"inject={call}:error={failure}:when={ordinal}"]
            command = [*traced, *command]
        prefix.with_suffix(".command").write_text(repr(command) + "\n")
        prefix.with_suffix(".input").write_bytes(data)
        if read_error:
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                result = subprocess.run(command, stdin=descriptor, capture_output=True, timeout=25, check=False)
            finally:
                os.close(descriptor)
        elif closed_reader:
            reader, writer = os.pipe()
            os.close(reader)
            try:
                result = subprocess.run(command, input=data, stdout=writer, stderr=subprocess.PIPE,
                                        timeout=25, check=False)
            finally:
                os.close(writer)
            result.stdout = b""
        else:
            result = subprocess.run(command, input=data, capture_output=True, timeout=25, check=False)
        prefix.with_suffix(".stdout").write_bytes(result.stdout)
        prefix.with_suffix(".stderr").write_bytes(result.stderr)
        prefix.with_suffix(".status").write_text(str(result.returncode) + "\n")
        assert result.returncode == status, (name, result.returncode, status, result.stdout[:120], result.stderr)
        assert result.stderr == (ERROR if status and diagnostic else b""), (name, result.stderr)
        assert result.stdout == output, (name, result.stdout[:180], output[:180])
        found = events(prefix.with_suffix(".trace").read_text()) if trace else []
        marked = [item for item in found if "INJECTED" in item["answer"]]
        if injection:
            call, ordinal, failure = injection
            selected = [item for item in found if item["name"] == call and item["ordinal"] == ordinal]
            assert len(selected) == 1 and marked == selected, (name, injection, marked)
            assert selected[0]["answer"].startswith("-1 " + failure + " "), selected[0]
        else:
            assert not marked, marked
        self.count += 1
        return found

    def model(self, name, rows, *, column=1, numeric=False, descending=False,
              header=False, arguments=None, data=None):
        if arguments is None:
            arguments = ["--column", str(column)]
            for enabled, flag in ((numeric, "--numeric"), (descending, "--descending"), (header, "--header")):
                if enabled:
                    arguments.append(flag)
        if data is None:
            data = encode(rows)
        output = encode(model_rows(rows, column, numeric, descending, header))
        self.run(name, arguments, data, output=output)


def exact_cap_input():
    rows = [[str(value), "x" * 8180] for value in range(511, -1, -1)]
    remaining = CAP - sum(len(row[0]) + len(row[1]) + 2 for row in rows)
    for row in rows:
        added = min(12, remaining)
        row[1] += "x" * added
        remaining -= added
    assert remaining == 0 and all(len(row[1]) <= 8192 for row in rows)
    data = "".join(row[0] + "," + row[1] + "\n" for row in rows).encode()
    assert len(data) == CAP
    return rows, data


def model(r):
    r.model("empty-default", [], arguments=[])
    r.model("empty-header-numeric-column64", [], column=64, numeric=True, header=True)
    r.model("singleton", [["one", "payload"]])
    r.model("header-only-nonnumeric", [["name", "value"]], column=2, numeric=True, header=True)
    r.model("default-first-column", [["z", "1"], ["a", "9"], ["m", "0"]], arguments=[])
    rows = [["b", "first"], ["a", "second"], ["b", "third"], ["a", "fourth"], ["b", "fifth"]]
    r.model("stable-text-ties", rows)
    r.model("stable-text-ties-descending", rows, descending=True)
    numeric = [["first", "01"], ["second", "-2"], ["third", "+1"], ["fourth", "1"], ["fifth", "10"]]
    r.model("numeric-second-column-stability", numeric, column=2, numeric=True)
    r.model("numeric-descending-ties", numeric, column=2, numeric=True, descending=True)
    r.model("numeric-extrema", [[str(value), str(index)] for index, value in enumerate([0, (1 << 63) - 1, -(1 << 63), -1, 1])], numeric=True, descending=True)
    r.model("numeric-signed-zero-ties", [["-0", "z"], ["+0", "a"], ["00", "c"], ["0", "b"]], numeric=True)
    r.model("header-retained-descending", [["id", "score"], *numeric], column=2, numeric=True, descending=True, header=True)
    r.model("text-numeric-distinction", [["10"], ["2"], ["-3"], ["+1"], ["01"]])
    r.model("empty-text-keys", [["", "first"], ["z", "second"], ["", "third"], ["a", "fourth"]], descending=True)
    unicode = [[value, str(index)] for index, value in enumerate(["é", "e\u0301", "E", "e", "😀", "\ufeff", "\ufffe", "z", "Ä", "א"])]
    r.model("utf8-byte-order-no-normalization", unicode)
    r.model("utf8-byte-order-descending", unicode, descending=True)
    quoted = [["a,b", 'quote"one'], ["a\nb", "line\r\ntwo"], ["a\rb", "lone\rCR"], ["a\"b", "tail"]]
    r.model("quoted-comma-quote-and-newlines", quoted)
    r.model("quoted-newlines-descending", quoted, descending=True)
    r.model("spaces-remain-text", [[" a"], ["a "], ["a"], [" "]])
    r.model("lf-record-separators", [["b", "2"], ["a", "1"]], data=b"b,2\na,1\n")
    r.model("eof-without-record-separator", [["b", "2"], ["a", "1"]], data=b"b,2\na,1")
    r.model("trailing-empty-fields", [["b", "", ""], ["a", "value", ""], ["a", "", ""]], data=b"b,,\na,value,\na,,\n")
    r.model("blank-records", [[""], ["z"], [""]], data=b"\nz\n\n")
    r.model("maximum-field-singleton", [["x" * 8192]])
    r.model("maximum-record-singleton", [[str(index) * 8192 for index in range(8)]])
    width = [[f"v{column}" for column in range(64)] for _ in range(3)]
    width[0][63], width[1][63], width[2][63] = "z", "a", "m"
    r.model("maximum-fields-selected64", width, column=64)
    r.model("maximum-data-rows-with-header", [["number"], *[[str(value)] for value in range(16383, -1, -1)]], numeric=True, header=True)
    r.model("text-work-just-under-cap", [["x" * 2440] for _ in range(512)])
    rows, data = exact_cap_input()
    r.model("exact-four-mib-input", rows, numeric=True, data=data)
    rng = random.Random(0x5077A0)
    for index in range(8):
        rows = [[rng.choice(["", "é", "same", "A", "a,b", "x\ny"]), str(rng.randrange(-7, 8)), str(row)]
                for row in range(rng.randrange(1, 90))]
        numeric = bool(index % 2)
        r.model(f"seeded-{index}", rows, column=2 if numeric else 1, numeric=numeric, descending=bool(index % 3))


def rejection(r):
    cases = [
        ("unequal-width", b"a,b\nc\n"), ("quote-in-unquoted", b'a"b,c\n'),
        ("unclosed-quote", b'"abc'), ("trailing-quote-text", b'"a"x,b\n'),
        ("bare-cr", b"a,b\rc,d\r"), ("invalid-utf8", b"a,\xff\n"),
        ("nul-unquoted", b"a,\x00\n"), ("nul-quoted", b'a,"\x00"\n'),
        ("tab-quoted", b'a,"\t"\n'), ("del", b"a,\x7f\n"),
        ("too-many-fields", b",".join([b"x"] * 65) + b"\n"),
        ("field-over-cap", b"x" * 8193 + b"\n"),
        ("record-over-cap", b",".join([b"x" * 8192] * 8 + [b"x"]) + b"\n"),
        ("data-rows-over-cap", b"a\n" * 16385),
        ("raw-input-over-cap", b"x" * (CAP + 1)),
        ("later-malformed-no-output", b"a,first\nz,second\nq\n"),
    ]
    for name, data in cases:
        r.run(name, data=data, status=2)
    for index, value in enumerate(("", "+", "-", "1.0", "1e2", " 1", "1 ", "1_0", "١", "\ufeff1", "9223372036854775808", "-9223372036854775809")):
        r.run(f"invalid-i64-{index}", ["--numeric"], encode([[value]]), status=2)
    r.run("selected-column-missing", ["--column", "3"], b"a,b\n", status=2)
    r.run("header-selected-column-missing", ["--header", "--column", "2", "--numeric"], b"name\n", status=2)
    r.run("later-key-invalid-no-output", ["--numeric", "--header"], b"number\n1\n2\nnot-a-number\n", status=2)
    r.run("text-work-just-over-cap", data=(b"x" * 2441 + b"\n") * 512, status=2)
    r.run("header-data-width-mismatch", ["--header"], b"one,two\nonly\n", status=2)


def cli(r):
    invalid = [
        ["--column"], ["--column", "0"], ["--column", "65"], ["--column", "-1"],
        ["--column", "+1"], ["--column", "1.0"], ["--column", ""],
        ["--column", "18446744073709551616"], ["--column", " 1"], ["--column", "1 "],
        ["--unknown"], ["input.csv"], ["--column", "1", "-c2"],
        ["--numeric", "-n"], ["-nn"], ["--descending", "-r"], ["-rr"],
        ["--header", "-H"], ["-HH"], ["--help", "-h"], ["-hh"],
        ["--numeric=yes"], ["--descending=yes"], ["--header=yes"], ["--help=yes"],
        ["--help", "--column", "0"], ["--", "operand"], [""] * 25,
        ["--column", "0" * 1025], ["-x"], ["--column", "-r"],
    ]
    for index, arguments in enumerate(invalid):
        r.run(f"invalid-{index}", arguments, status=2, read_error=True)
    r.run("help-bypasses-input", ["--help"], output=HELP, read_error=True)
    r.run("short-help", ["-h"], output=HELP)
    r.run("help-valid-options", ["--column", "64", "--numeric", "--descending", "--header", "--help"], output=HELP, read_error=True)
    r.model("short-attached-and-cluster", [["id", "value"], ["a", "2"], ["b", "1"]], column=2, numeric=True, descending=True, header=True,
            arguments=["-c02", "-nrH"])
    r.model("long-equals-leading-zero", [["z"], ["a"]], arguments=["--column=001"])
    r.run("header-case-sensitive-short", ["-hHh"], status=2, read_error=True)
    r.run("help-still-rejects-operand", ["--help", "data.csv"], status=2, read_error=True)
    r.model("end-options-without-operand", [["z"], ["a"]], arguments=["--"])


def io(r):
    rows = [["id", "key"], ["first", "01"], ["second", "-2"], ["third", "+1"], ["fourth", "1"], ["last", "10"]]
    data = encode(rows)
    args = ["--column", "2", "--numeric", "--descending", "--header"]
    wanted = encode(model_rows(rows, 2, True, True, True))
    r.run("stdin-directory", status=3, read_error=True)
    r.run("closed-stdout", args, data, status=5, closed_reader=True)
    r.run("closed-help-output", ["--help"], status=5, closed_reader=True)
    baseline = r.run("native-baseline", args, data, output=wanted, trace=True)
    scratch, source, prior = stable_workspace(baseline, len(rows) - 1)
    maps = [item for item in baseline if item["name"] == "mmap"]
    first_read = next(index for index, item in enumerate(baseline) if item["name"] == "read")
    input_map = next(item for item in baseline[first_read + 1:] if item["name"] == "mmap")
    selected = [maps[0], input_map, maps[len(maps) // 2], maps[-1]]
    assert len({item["ordinal"] for item in selected}) == 4
    for old in selected:
        ordinal = old["ordinal"]
        actual = r.run(f"reached-oom-{ordinal}", args, data, status=4, trace=True,
                       injection=("mmap", ordinal, "ENOMEM"))
        fault = next(item for item in actual if item["name"] == "mmap" and item["ordinal"] == ordinal)
        assert old["args"] == fault["args"], (old, fault)
    ordinal = scratch["ordinal"]
    assert ordinal not in {item["ordinal"] for item in selected}, ("workspace must add a distinct fault process", scratch, selected)
    actual = r.run("stable-sort-workspace-oom", args, data, status=4, trace=True,
                   injection=("mmap", ordinal, "ENOMEM"))
    actual_maps = [item for item in actual if item["name"] == "mmap"]
    assert [item["args"] for item in actual_maps] == [item["args"] for item in maps[:ordinal]]
    assert actual_maps[-1]["args"] == scratch["args"]
    assert actual_maps[-1]["answer"].startswith("-1 ENOMEM ")
    assert source["size"] * 5 == scratch["size"] * 8 and prior["size"] * 5 == scratch["size"] * 4
    for call in ("read", "write"):
        r.run(f"retry-{call}-eintr", args, data, output=wanted, trace=True, injection=(call, 1, "EINTR"))
    long_input = encode([["id", "key"], ["x" * 5000, "2"], ["y", "1"]])
    partial = r.run("later-read-eio-no-prefix", args, long_input, status=3, trace=True, injection=("read", 2, "EIO"))
    first = next(item for item in partial if item["name"] == "read")
    assert first["answer"].isdigit() and int(first["answer"]) > 0, first
    r.run("first-write-eio-no-prefix", args, data, status=5, trace=True, injection=("write", 1, "EIO"))
    r.run("signal-setup-failure", args, data, status=5, trace=True, injection=("rt_sigaction", 1, "EIO"), diagnostic=False)


def controls():
    assert len(HELP) == 442 and len(ERROR) == 28
    ties = [["b", "first"], ["a", "second"], ["b", "third"], ["a", "fourth"]]
    assert model_rows(ties, descending=True) == [ties[0], ties[2], ties[1], ties[3]]
    nums = [["first", "01"], ["second", "+1"], ["third", "-2"]]
    assert model_rows(nums, 2, True, True) == nums
    assert integer("-9223372036854775808") == -(1 << 63) and integer("+9223372036854775807") == (1 << 63) - 1
    for invalid in ("", "١", "1_0", " 1", "9223372036854775808"):
        try:
            integer(invalid)
        except AssertionError:
            pass
        else:
            raise AssertionError(("integer control accepted", invalid))
    quoted = [["a,b", 'c"d'], ["é\nline", "\ufeff\ufffe"]]
    assert list(csv.reader(StringIO(encode(quoted).decode(), newline=""), strict=True)) == quoted
    assert 4 * 512 * 10 * (2 * 2440 + 2) <= 100000000 < 4 * 512 * 10 * (2 * 2441 + 2)
    cap_rows, cap_input = exact_cap_input()
    assert len(cap_input) == CAP and list(csv.reader(StringIO(cap_input.decode(), newline=""))) == cap_rows
    class CounterOnly:
        def __init__(self): self.count = 0
        def run(self, *args, **kwargs): self.count += 1
        def model(self, *args, **kwargs): self.count += 1
    for function in (model, rejection, cli):
        runner = CounterOnly()
        function(runner)
        assert runner.count == COUNTS[function.__name__], (function.__name__, runner.count)
    class ReferenceChecks(CounterOnly):
        def model(self, name, rows, **options):
            raw = options.get("data", encode(rows))
            decoded = [row or [""] for row in csv.reader(StringIO(raw.decode("utf-8"), newline=""), strict=True)]
            assert decoded == rows, (name, "input reference mismatch")
            ordered = model_rows(rows, options.get("column", 1), options.get("numeric", False),
                                 options.get("descending", False), options.get("header", False))
            decoded_output = list(csv.reader(StringIO(encode(ordered).decode(), newline=""), strict=True))
            assert decoded_output == ordered, (name, "output round trip")
            self.count += 1
    reference = ReferenceChecks()
    model(reference)
    assert reference.count == COUNTS["model"]
    trace = "mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\nmunmap(0x1000, 64) = 0\n"
    assert len(events(trace)) == 2
    try:
        events(trace.split("munmap")[0])
    except AssertionError:
        pass
    else:
        raise AssertionError("cleanup control accepted an observed unreleased mapping")
    workspace_trace = (
        "mmap(NULL, 40, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x3000\n"
        'read(0, "x", 1024) = 1\nread(0, "", 1024) = 0\n'
        "mmap(NULL, 64, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
        "mmap(NULL, 128, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x2000\n"
        "munmap(0x1000, 64) = 0\n"
        "mmap(NULL, 80, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
        "munmap(0x1000, 80) = 0\n"
        "mmap(NULL, 100, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
        "munmap(0x2000, 128) = 0\n"
        'write(1, "report", 6) = 6\n'
        "munmap(0x1000, 100) = 0\nmunmap(0x3000, 40) = 0\n")
    assert stable_workspace(events(workspace_trace), 5)[0]["size"] == 80
    corruptions = [
        workspace_trace.replace("mmap(NULL, 80,", "mmap(NULL, 85,").replace("munmap(0x1000, 80)", "munmap(0x1000, 85)"),
        workspace_trace.replace("mmap(NULL, 128,", "mmap(NULL, 120,").replace("munmap(0x2000, 128)", "munmap(0x2000, 120)"),
        workspace_trace.replace("munmap(0x1000, 80) = 0\n", ""),
        workspace_trace.replace('write(1, "report", 6) = 6\n', ""),
        workspace_trace.replace(
            "munmap(0x1000, 80) = 0\n", "munmap(0x1000, 80) = 0\n"
            "mmap(NULL, 80, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x1000\n"
            "munmap(0x1000, 80) = 0\n"),
    ]
    for corrupted in corruptions:
        try:
            stable_workspace(events(corrupted), 5)
        except (AssertionError, StopIteration):
            pass
        else:
            raise AssertionError("workspace control accepted corrupted size/lifetime/identity")
    print(f"sort-rows CPU controls=16; native cases={sum(COUNTS.values())}")


if __name__ == "__main__":
    if sys.argv[1:] == ["controls"]:
        controls()
    else:
        mode, executable = sys.argv[1:]
        runner = Runner(executable, mode)
        {"model": model, "rejection": rejection, "cli": cli, "io": io}[mode](runner)
        assert runner.count == COUNTS[mode], (mode, runner.count)
        print(f"sort-rows-{mode} cases={runner.count} evidence={runner.directory}")
