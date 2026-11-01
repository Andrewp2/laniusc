"""Host oracle for time-command: Python's own clock reads, CPU accounting and
process statuses. Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import json
import os
import subprocess
import sys
import tempfile
import time

HELP = (b"Usage: time-command [--format json|tsv] -- PROGRAM [ARG...]\n"
        b"       time-command [--format json|tsv] --clocks\n")
INVALID = b"time-command: invalid arguments; see --help errno=0\n"
FIELDS = ["pid", "status", "code", "signal", "real_ns", "boot_ns", "cpu_ns",
          "self_cpu_ns", "start_unix_sec", "start_unix_nsec"]
CLOCKS = [("realtime", 0, "wall"), ("realtime_coarse", 5, "wall"), ("tai", 11, "wall"),
          ("monotonic", 1, "steady"), ("monotonic_raw", 4, "steady"),
          ("monotonic_coarse", 6, "steady"), ("boottime", 7, "steady"),
          ("process_cpu", 2, "cpu"), ("thread_cpu", 3, "cpu")]
PY = [sys.executable, "-I", "-c"]
MS = 1_000_000
cases = 0


def run(exe, *args, stdin=subprocess.DEVNULL):
    return subprocess.run([exe, *args], stdin=stdin, capture_output=True, timeout=30)


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def report_line(stderr):
    line = stderr.splitlines()[-1]
    value = json.loads(line)
    case(list(value) == FIELDS, line)
    case(all(isinstance(value[k], int) for k in FIELDS if k not in ("status", "code", "signal")), line)
    return value


def tsv_report(stderr):
    lines = stderr.decode().splitlines()
    case(lines[-2].split("\t") == FIELDS, lines)
    row = lines[-1].split("\t")
    case(len(row) == len(FIELDS), row)
    return dict(zip(FIELDS, row))


def cli(exe):
    out = run(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    for args in ([], ["--bogus"], ["--format", "xml", "--", "true"], ["--format"],
                 ["--format", "json", "--format", "tsv", "--", "true"], ["--clocks", "extra"],
                 ["--help", "extra"], ["--clocks", "--clocks"], ["--"], ["--format", "tsv"]):
        out = run(exe, *args)
        case(out.returncode == 125 and out.stdout == b"" and out.stderr == INVALID, args, out)
    out = run(exe, "--", "/nonexistent/program")
    case(out.returncode == 127 and out.stdout == b"" and out.stderr == b"time-command: cannot execute errno=2\n", out)
    out = run(exe, "-")  # A lone "-" is a program name, not an option.
    case(out.returncode == 127 and out.stderr == b"time-command: cannot execute errno=2\n", out)
    out = run(exe, "--", "time-command-no-such-program-on-path")
    case(out.returncode == 127 and out.stderr.endswith(b"errno=2\n"), out)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        plain = os.path.join(directory, "plain")
        with open(plain, "wb") as handle:
            handle.write(b"#!/bin/sh\nexit 0\n")
        os.chmod(plain, 0o600)
        out = run(exe, "--", plain)
        case(out.returncode == 126 and out.stderr == b"time-command: cannot execute errno=13\n", out)
        out = run(exe, "--", directory)
        case(out.returncode == 126 and out.stderr.endswith(b"errno=13\n"), out)
    for code in (0, 1, 3, 255):
        out = run(exe, "--", "sh", "-c", f"exit {code}")
        value = report_line(out.stderr)
        case(out.returncode == code and value["status"] == "exited" and value["code"] == code and value["signal"] is None, out)
    for signal in (15, 9, 6):
        out = run(exe, "--", "sh", "-c", f"kill -{signal} $$")
        value = report_line(out.stderr)
        case(out.returncode == 128 + signal and value["status"] == "signaled" and value["code"] is None and value["signal"] == signal, out)
    # Child stdout passes through untouched; its stderr precedes the report.
    payload = bytes(range(256)) * 64
    script = "import sys; sys.stdout.buffer.write(bytes(range(256))*64); sys.stderr.write('child-error\\n')"
    out = run(exe, "--", *PY, script)
    case(out.returncode == 0 and out.stdout == payload and out.stderr.startswith(b"child-error\n"), out.stderr)
    case(len(out.stderr.splitlines()) == 2, out.stderr)
    # The child inherits stdin and a default SIGPIPE disposition.
    out = subprocess.run([exe, "--", "cat"], input=b"stdin-bytes", capture_output=True, timeout=30)
    case(out.returncode == 0 and out.stdout == b"stdin-bytes", out)
    reader, writer = os.pipe()
    os.close(reader)
    status = subprocess.run([exe, "--", "yes"], stdout=writer, stderr=subprocess.PIPE, timeout=30)
    os.close(writer)
    value = report_line(status.stderr)
    case(status.returncode == 141 and value["signal"] == 13, status)
    out = run(exe, "--format", "tsv", "--", "sh", "-c", "exit 7")
    row = tsv_report(out.stderr)
    case(out.returncode == 7 and row["status"] == "exited" and row["code"] == "7" and row["signal"] == "-", row)
    out = run(exe, "--format", "tsv", "--", "sh", "-c", "kill -TERM $$")
    row = tsv_report(out.stderr)
    case(out.returncode == 143 and row["code"] == "-" and row["signal"] == "15", row)
    # Arguments after the program, including option-like ones, belong to it.
    out = run(exe, "--format", "json", "printf", "%s|", "--help", "--clocks", "-")
    case(out.returncode == 0 and out.stdout == b"--help|--clocks|-|", out)


def timing(exe):
    before = time.time_ns()
    out = run(exe, "--", *PY, "import time; time.sleep(0.15)")
    after = time.time_ns()
    value = report_line(out.stderr)
    start = value["start_unix_sec"] * 1_000_000_000 + value["start_unix_nsec"]
    case(out.returncode == 0 and before <= start <= after and 0 <= value["start_unix_nsec"] < 1_000_000_000, value)
    case(value["real_ns"] >= 150 * MS and value["real_ns"] <= after - before, value)
    case(value["cpu_ns"] < value["real_ns"] - 100 * MS, value)
    case(abs(value["boot_ns"] - value["real_ns"]) < 50 * MS, value)
    case(0 < value["self_cpu_ns"] < 1000 * MS, value)
    case(value["pid"] > 0 and value["pid"] != os.getpid(), value)
    # Exact child CPU: at least what the child observed just before exiting.
    busy = ("import os,sys,time\nend=time.process_time_ns()+250000000\n"
            "while time.process_time_ns()<end: pass\n"
            "sys.stdout.write(str(time.process_time_ns())); sys.stdout.flush(); os._exit(0)")
    for format_name in ("json", "tsv"):
        out = run(exe, "--format", format_name, "--", *PY, busy)
        observed = int(out.stdout)
        value = report_line(out.stderr) if format_name == "json" else {k: int(v) for k, v in tsv_report(out.stderr).items() if k not in ("status", "code", "signal")}
        case(out.returncode == 0 and observed >= 250 * MS, out)
        case(observed <= value["cpu_ns"] <= observed + 100 * MS, observed, value)
        case(value["real_ns"] >= value["cpu_ns"], value)
    # The process CPU clock excludes reaped descendants: the shell's own clock
    # stays small although its reaped child consumed 250 ms of CPU.
    out = run(exe, "--", "sh", "-c", f"{sys.executable} -I -c '{busy}' >/dev/null; exit 0")
    value = report_line(out.stderr)
    case(out.returncode == 0 and value["cpu_ns"] < 100 * MS and value["real_ns"] >= 250 * MS, value)


def clocks(exe):
    reference = {}
    for name, number, kind in CLOCKS:
        reference[name] = time.clock_gettime_ns(number)
    json_out = run(exe, "--clocks")
    tsv_out = run(exe, "--format", "tsv", "--clocks")
    later = {name: time.clock_gettime_ns(number) for name, number, kind in CLOCKS}
    case(json_out.returncode == 0 and json_out.stderr == b"" and tsv_out.returncode == 0 and tsv_out.stderr == b"", json_out, tsv_out)
    rows = [json.loads(line) for line in json_out.stdout.splitlines()]
    lines = tsv_out.stdout.decode().splitlines()
    case(lines[0].split("\t") == ["clock", "kind", "resolution_ns", "sec", "nsec"] and len(lines) == 10, lines)
    case(len(rows) == 9, rows)
    for (name, number, kind), row, line in zip(CLOCKS, rows, lines[1:]):
        fields = line.split("\t")
        case(list(row) == ["clock", "kind", "resolution_ns", "sec", "nsec"], row)
        case(row["clock"] == name and row["kind"] == kind and fields[:2] == [name, kind], row, fields)
        resolution = round(time.clock_getres(number) * 1_000_000_000)
        case(row["resolution_ns"] == resolution and int(fields[2]) == resolution, name, row, resolution)
        reading = row["sec"] * 1_000_000_000 + row["nsec"]
        case(0 <= row["nsec"] < 1_000_000_000, row)
        if kind == "cpu":
            case(0 < reading < 1_000_000_000, row)
        else:
            case(reference[name] <= reading <= later[name], name, reference[name], reading, later[name])


MODES = {"cli": cli, "timing": timing, "clocks": clocks}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"time-command-{mode} cases={cases}")
