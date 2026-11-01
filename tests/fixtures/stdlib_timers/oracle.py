"""Host oracle for timer-ticks: timerfd expiration arithmetic against the
reported elapsed times, Python's own wall-clock bounds and the process's
CAP_WAKE_ALARM. Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import json
import subprocess
import sys
import time

HELP = (b"Usage: timer-ticks [--clock monotonic|boottime|realtime|realtime-alarm|boottime-alarm]"
        b" [--interval-ms N] [--initial-ms N] [--count N] [--work-ms N] [--absolute] [--format json|tsv]\n")
INVALID = b"timer-ticks: invalid arguments; see --help errno=0\n"
MS = 1_000_000
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


def run(exe, *args):
    return subprocess.run([exe, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)


def wake_alarm_capability():
    for line in open("/proc/self/status"):
        if line.startswith("CapEff:"):
            return (int(line.split()[1], 16) >> 35) & 1 == 1
    return False


def rows(out, tsv):
    if tsv:
        lines = out.decode().splitlines()
        case(lines[0] == "read\texpirations\ttotal\telapsed_ns", lines)
        return [dict(zip(("read", "expirations", "total", "elapsed_ns"), map(int, line.split("\t")))) for line in lines[1:]]
    values = [json.loads(line) for line in out.splitlines()]
    for value in values:
        case(list(value) == ["read", "expirations", "total", "elapsed_ns"], value)
    return values


def cli(exe):
    out = run(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    for args in (["--bogus"], ["--count", "2"], ["--count", "0", "--interval-ms", "5"], ["--initial-ms", "0"],
                 ["--interval-ms", "60001"], ["--count", "10001", "--interval-ms", "1"], ["--work-ms", "x"],
                 ["--clock", "tai"], ["--clock"], ["--absolute", "--absolute"], ["--format", "xml"],
                 ["--interval-ms", "5", "--interval-ms", "5"], ["extra"], ["--help", "--count", "1"],
                 ["--count", "-1"], ["--initial-ms", "+5"]):
        out = run(exe, *args)
        case(out.returncode == 2 and out.stdout == b"" and out.stderr == INVALID, args, out)
    capable = wake_alarm_capability()
    for clock in ("realtime-alarm", "boottime-alarm"):
        out = run(exe, "--clock", clock, "--initial-ms", "5")
        if capable:
            case(out.returncode == 0 and rows(out.stdout, False)[0]["total"] == 1, out)
        else:
            case(out.returncode == 3 and out.stdout == b"" and out.stderr == b"timer-ticks: create failed errno=1\n", out)


def check(exe, clock, interval, initial, count, work=0, absolute=False, tsv=False):
    args = ["--clock", clock, "--initial-ms", str(initial), "--count", str(count)]
    if interval:
        args += ["--interval-ms", str(interval)]
    if work:
        args += ["--work-ms", str(work)]
    if absolute:
        args.append("--absolute")
    if tsv:
        args += ["--format", "tsv"]
    began = time.monotonic_ns()
    out = run(exe, *args)
    duration = time.monotonic_ns() - began
    case(out.returncode == 0 and out.stderr == b"", args, out)
    values = rows(out.stdout, tsv)
    case([value["read"] for value in values] == list(range(1, count + 1)), values)
    total = 0
    previous = None
    for value in values:
        total += value["expirations"]
        case(value["expirations"] >= 1 and value["total"] == total, value)
        # The total-th expiration happened before the read returned.
        case(value["elapsed_ns"] >= (initial + (total - 1) * interval) * MS, args, value)
        if interval:
            # No expiration counted after the clock read that follows the read.
            case(total <= (value["elapsed_ns"] - initial * MS) // (interval * MS) + 1, args, value)
            if previous is not None and work:
                # Every period that ended before the slow consumer's next read is counted.
                slack = 0 if absolute else MS
                floor = (previous["elapsed_ns"] + work * MS - slack - initial * MS) // (interval * MS) + 1
                case(total >= floor, args, previous, value)
        previous = value
    case(duration >= (initial + (count - 1) * interval) * MS, args, duration)
    if not interval:
        case(values[0]["expirations"] == 1, values)
    return values


def ticks(exe):
    check(exe, "monotonic", 20, 20, 4)
    check(exe, "monotonic", 0, 30, 1)
    check(exe, "monotonic", 7, 3, 5, absolute=True, tsv=True)
    slow = check(exe, "boottime", 10, 10, 3, work=35, absolute=True, tsv=True)
    case(all(value["expirations"] >= 3 for value in slow[1:]), slow)
    slow = check(exe, "monotonic", 5, 5, 4, work=17)
    case(all(value["expirations"] >= 3 for value in slow[1:]), slow)
    check(exe, "boottime", 0, 12, 1)
    check(exe, "realtime", 0, 15, 1, absolute=True)
    check(exe, "realtime", 5, 5, 5)
    check(exe, "realtime", 8, 4, 3, work=20, absolute=True)


MODES = {"cli": cli, "ticks": ticks}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"timer-ticks-{mode} cases={cases}")
