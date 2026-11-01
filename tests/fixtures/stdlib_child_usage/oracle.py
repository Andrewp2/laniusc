"""Host oracle for child-usage: wait4 rusage against Python's own os.wait4,
child-side CPU and memory observations, and process statuses.
Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import json
import os
import subprocess
import sys
import tempfile

HELP = b"Usage: child-usage [--format json|tsv] -- PROGRAM [ARG...]\n"
INVALID = b"child-usage: invalid arguments; see --help errno=0\n"
FIELDS = ["pid", "status", "code", "signal", "user_ns", "system_ns", "cpu_ns", "max_rss_kib",
          "minor_faults", "major_faults", "block_input", "block_output", "voluntary_switches",
          "involuntary_switches", "children_cpu_ns"]
COUNTS = FIELDS[4:]
PY = [sys.executable, "-I", "-c"]
MS = 1_000_000
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def run(exe, *args):
    return subprocess.run([exe, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)


def report(stderr, tsv=False):
    if tsv:
        lines = stderr.decode().splitlines()
        case(lines[-2].split("\t") == FIELDS, lines)
        row = dict(zip(FIELDS, lines[-1].split("\t")))
        for name in ["pid"] + COUNTS:
            row[name] = int(row[name])
        return row
    value = json.loads(stderr.splitlines()[-1])
    case(list(value) == FIELDS, value)
    case(all(isinstance(value[name], int) and value[name] >= 0 for name in COUNTS), value)
    # Linux reports microsecond timevals; cpu is their sum; one reaped child.
    case(value["user_ns"] % 1000 == 0 and value["system_ns"] % 1000 == 0, value)
    case(value["cpu_ns"] == value["user_ns"] + value["system_ns"] == value["children_cpu_ns"], value)
    return value


def reference(script):
    """Python's own wait4 rusage for the same workload."""
    child = subprocess.Popen(PY + [script], stdout=subprocess.DEVNULL)
    _, status, usage = os.wait4(child.pid, 0)
    assert status == 0
    return usage


def cli(exe):
    out = run(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    for args in ([], ["--bogus"], ["--format", "xml", "--", "true"], ["--format"], ["--"],
                 ["--format", "json", "--format", "tsv", "--", "true"], ["--help", "extra"], ["--clocks"]):
        out = run(exe, *args)
        case(out.returncode == 125 and out.stdout == b"" and out.stderr == INVALID, args, out)
    out = run(exe, "--", "/nonexistent/program")
    case(out.returncode == 127 and out.stderr == b"child-usage: cannot execute errno=2\n", out)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        out = run(exe, "--", directory)
        case(out.returncode == 126 and out.stderr == b"child-usage: cannot execute errno=13\n", out)
    for code in (0, 2, 255):
        out = run(exe, "--", "sh", "-c", f"exit {code}")
        value = report(out.stderr)
        case(out.returncode == code and value["status"] == "exited" and value["code"] == code and value["signal"] is None, value)
    for signal in (9, 15):
        out = run(exe, "--", "sh", "-c", f"kill -{signal} $$")
        value = report(out.stderr)
        case(out.returncode == 128 + signal and value["status"] == "signaled" and value["signal"] == signal and value["code"] is None, value)
    out = run(exe, "--format", "tsv", "--", "sh", "-c", "exit 6")
    row = report(out.stderr, tsv=True)
    case(out.returncode == 6 and row["code"] == "6" and row["signal"] == "-" and row["status"] == "exited", row)
    out = run(exe, "--", *PY, "import sys; sys.stdout.buffer.write(bytes(range(256))); sys.stderr.write('e\\n')")
    case(out.returncode == 0 and out.stdout == bytes(range(256)) and out.stderr.startswith(b"e\n") and len(out.stderr.splitlines()) == 2, out)


def usage(exe):
    # CPU: at least what the child observed of itself just before exiting.
    busy = ("import os,sys,time\nend=time.process_time_ns()+250000000\n"
            "while time.process_time_ns()<end: pass\n"
            "sys.stdout.write(str(time.process_time_ns())); sys.stdout.flush(); os._exit(0)")
    for tsv in (False, True):
        args = ["--format", "tsv"] if tsv else []
        out = run(exe, *args, "--", *PY, busy)
        value = report(out.stderr, tsv)
        observed = int(out.stdout)
        case(out.returncode == 0 and observed >= 250 * MS, out)
        case(observed - 2000 <= value["cpu_ns"] <= observed + 100 * MS, observed, value)
        case(value["user_ns"] > 0, value)
    # Unlike a process CPU clock, wait4 usage includes descendants the child reaped.
    out = run(exe, "--", "sh", "-c", f"{sys.executable} -I -c '{busy}' >/dev/null; exit 0")
    value = report(out.stderr)
    case(out.returncode == 0 and value["cpu_ns"] >= 249 * MS, value)
    # Peak resident set: touching 64 MiB, compared with Python's own wait4 of the same script.
    touch = "b=bytearray(64<<20)\nfor i in range(0,len(b),4096): b[i]=1"
    expected = reference(touch)
    out = run(exe, "--", *PY, touch)
    value = report(out.stderr)
    case(out.returncode == 0 and value["max_rss_kib"] >= 65536, value)
    case(abs(value["max_rss_kib"] - expected.ru_maxrss) < 16384 and value["minor_faults"] > 0, value, expected)
    small = report(run(exe, "--", "true").stderr)
    case(small["max_rss_kib"] < value["max_rss_kib"] - 60000, small, value)
    # Voluntary context switches: twenty sleeps block twenty times.
    out = run(exe, "--", *PY, "import time\nfor i in range(20): time.sleep(0.002)")
    value = report(out.stderr)
    case(value["voluntary_switches"] >= 20, value)
    # Block I/O in 512-byte units: 8 MiB written, then reread after dropping the cache.
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        path = os.path.join(directory, "blocks")
        write = (f"import os\nf=os.open({path!r},os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)\n"
                 "for i in range(64): os.write(f,b'x'*131072)\nos.fsync(f); os.close(f)")
        read = (f"import os\nf=os.open({path!r},os.O_RDONLY)\nos.posix_fadvise(f,0,0,os.POSIX_FADV_DONTNEED)\n"
                "while os.read(f,1<<20): pass\nos.close(f)")
        value = report(run(exe, "--", *PY, write).stderr)
        case(value["block_output"] >= 16384, value)
        value = report(run(exe, "--", *PY, read).stderr)
        case(value["block_input"] >= 16384 and value["block_output"] == 0, value)
        os.unlink(path)


MODES = {"cli": cli, "usage": usage}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"child-usage-{mode} cases={cases}")
