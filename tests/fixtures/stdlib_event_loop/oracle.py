"""Host oracle for tee-children: scheduled child output against the reported
order, timestamps, line kinds, statuses and timeouts.
Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import os
import subprocess
import sys
import tempfile
import time

HELP = b"Usage: tee-children [--timeout-ms N] [--max-line N] -- PROGRAM1 [ARG...] ::: PROGRAM2 [ARG...]\n"
INVALID = b"tee-children: invalid arguments; see --help errno=0\n"
PY = [sys.executable, "-I", "-c"]
MS = 1_000_000
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def run(exe, *args, timeout=30):
    began = time.monotonic_ns()
    out = subprocess.run([exe, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=timeout)
    return out, time.monotonic_ns() - began


def rows(stdout):
    result = []
    for line in stdout.split(b"\n")[:-1]:
        fields = line.split(b"\t", 4)
        case(len(fields) == 5, line)
        result.append((int(fields[0]), int(fields[1]), fields[2].decode(), fields[3].decode(), fields[4]))
    case(stdout == b"" or stdout.endswith(b"\n"), stdout[-20:])
    stamps = [row[0] for row in result]
    case(stamps == sorted(stamps), stamps)
    return result


def data(result, child, stream):
    return [(kind, value) for _, number, name, kind, value in result if number == child and name == stream]


def status(result, child):
    found = [(kind, int(value)) for _, number, name, kind, value in result if number == child and name == "status"]
    case(len(found) == 1, result)
    return found[0]


def cli(exe):
    out, _ = run(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    for args in ([], ["--"], ["--", "true"], ["--", "true", ":::"], ["--", ":::", "true"],
                 ["--", "true", ":::", "true", ":::", "true"], ["--timeout-ms", "x", "--", "true", ":::", "true"],
                 ["--max-line", "0", "--", "true", ":::", "true"], ["--max-line", "65537", "--", "true", ":::", "true"],
                 ["--timeout-ms", "86400001", "--", "true", ":::", "true"], ["--bogus", "--", "true", ":::", "true"],
                 ["--timeout-ms", "5", "--timeout-ms", "5", "--", "true", ":::", "true"], ["--help", "--"], ["true", ":::", "true"]):
        out, _ = run(exe, *args)
        case(out.returncode == 125 and out.stdout == b"" and out.stderr == INVALID, args, out)
    out, _ = run(exe, "--", "/nonexistent/one", ":::", "true")
    case(out.returncode == 127 and out.stdout == b"" and out.stderr == b"tee-children: cannot execute errno=2\n", out)
    # A failed second spawn kills and reaps the first child promptly.
    out, duration = run(exe, "--", "sleep", "5", ":::", "/nonexistent/two")
    case(out.returncode == 127 and out.stdout == b"" and duration < 2000 * MS, out, duration)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        out, _ = run(exe, "--", "true", ":::", directory)
        case(out.returncode == 126 and out.stderr == b"tee-children: cannot execute errno=13\n", out)
    for first, second, expected in ((0, 0, 0), (0, 7, 7), (3, 0, 3), (4, 9, 4)):
        out, _ = run(exe, "--", "sh", "-c", f"exit {first}", ":::", "sh", "-c", f"exit {second}")
        result = rows(out.stdout)
        case(out.returncode == expected and status(result, 1) == ("exited", first) and status(result, 2) == ("exited", second), out)
        case(len(result) == 2 and out.stderr == b"", result)
    out, _ = run(exe, "--", "sh", "-c", "kill -TERM $$", ":::", "true")
    result = rows(out.stdout)
    case(out.returncode == 143 and status(result, 1) == ("signaled", 15), out)


def tee(exe):
    # Four streams on one shared 20 ms CLOCK_MONOTONIC schedule: the merged
    # order follows the schedule and the stamps keep its spacing.
    base = time.monotonic() + 0.4
    def writer(name, offsets):
        return (f"import sys,time\nfor i in range(5):\n"
                f" for o,s,p in {offsets!r}:\n"
                f"  time.sleep(max(0,{base}+i*0.08+o-time.monotonic()))\n"
                f"  f=getattr(sys,s); f.write(p%i+'\\n'); f.flush()\n")
    a = writer("a", [(0.0, "stdout", "a%d"), (0.04, "stderr", "ae%d")])
    b = writer("b", [(0.02, "stdout", "b%d"), (0.06, "stderr", "be%d")])
    out, duration = run(exe, "--", *PY, a, ":::", *PY, b)
    result = rows(out.stdout)
    case(out.returncode == 0 and out.stderr == b"", out)
    expected = []
    for i in range(5):
        expected += [(1, "out", f"a{i}".encode()), (2, "out", f"b{i}".encode()), (1, "err", f"ae{i}".encode()), (2, "err", f"be{i}".encode())]
    merged = [(number, name, value) for _, number, name, kind, value in result if name != "status"]
    case(merged == expected, merged)
    case(all(kind == "line" for _, _, name, kind, _ in result if name != "status"), result)
    stamps = [row[0] for row in result if row[2] != "status"]
    gaps = sorted(later - earlier for earlier, later in zip(stamps, stamps[1:]))
    case(gaps[len(gaps) // 2] >= 10 * MS and stamps[-1] - stamps[0] >= 300 * MS, gaps)
    case(stamps[0] >= 200 * MS and result[-1][0] <= duration, stamps[0], duration)
    case(status(result, 1) == ("exited", 0) and status(result, 2) == ("exited", 0) and len(result) == 22, result)
    # Line kinds: split at the limit, empty lines, partial final line, raw bytes.
    raw = "import sys\nsys.stdout.buffer.write(b'x'*20+b'\\n\\n'+b'\\tq\\xff\\r\\n'+b'12345678'+b'\\n'+b'tail')"
    out, _ = run(exe, "--max-line", "8", "--", *PY, raw, ":::", *PY, "import sys; sys.stderr.write('e'*9)")
    result = rows(out.stdout)
    case(out.returncode == 0, out)
    case(data(result, 1, "out") == [("split", b"x" * 8), ("split", b"x" * 8), ("line", b"xxxx"), ("line", b""),
                                    ("line", b"\tq\xff\r"), ("line", b"12345678"), ("partial", b"tail")], data(result, 1, "out"))
    case(data(result, 2, "err") == [("split", b"e" * 8), ("partial", b"e")] and data(result, 1, "err") == [] and data(result, 2, "out") == [], result)
    # Volume: 1 MiB of numbered lines on one stream while the other child writes stderr.
    bulk = "import sys\nw=sys.stdout.write\nfor i in range(10486): w('%099d\\n'%i)\nsys.stdout.flush()"
    noise = "import sys\nfor i in range(2000): sys.stderr.write('n%d\\n'%i)\nsys.stderr.flush()"
    out, _ = run(exe, "--", *PY, bulk, ":::", *PY, noise)
    result = rows(out.stdout)
    case(out.returncode == 0, out.stderr)
    case(data(result, 1, "out") == [("line", b"%099d" % i) for i in range(10486)], len(data(result, 1, "out")))
    case(data(result, 2, "err") == [("line", b"n%d" % i) for i in range(2000)], len(data(result, 2, "err")))
    # Timeout kills both children; output before it is kept.
    out, duration = run(exe, "--timeout-ms", "150", "--", "sh", "-c", "echo x; exec sleep 5", ":::", "sh", "-c", "echo y >&2; exec sleep 5")
    result = rows(out.stdout)
    timeouts = [row for row in result if row[1] == 0]
    case(out.returncode == 124 and out.stderr == b"" and duration < 2000 * MS, out, duration)
    case(len(timeouts) == 1 and timeouts[0][2:] == ("status", "timeout", b"150") and timeouts[0][0] >= 150 * MS, timeouts)
    case(status(result, 1) == ("signaled", 9) and status(result, 2) == ("signaled", 9), result)
    case(data(result, 1, "out") == [("line", b"x")] and data(result, 2, "err") == [("line", b"y")], result)
    # A descendant holding a pipe: children exit, the timeout plus grace closes the streams.
    out, duration = run(exe, "--timeout-ms", "200", "--", "sh", "-c", "sleep 3 & echo z; printf part", ":::", "true")
    result = rows(out.stdout)
    case(out.returncode == 124 and 200 * MS <= duration < 1500 * MS, out, duration)
    case(status(result, 1) == ("exited", 0) and status(result, 2) == ("exited", 0), result)
    case(data(result, 1, "out") == [("line", b"z"), ("partial", b"part")], result)
    # Finishing before the timeout reports no timeout row.
    out, duration = run(exe, "--timeout-ms", "5000", "--", "true", ":::", "sh", "-c", "exit 2")
    result = rows(out.stdout)
    case(out.returncode == 2 and duration < 2000 * MS and all(row[1] != 0 for row in result), out)


MODES = {"cli": cli, "tee": tee}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"tee-children-{mode} cases={cases}")
