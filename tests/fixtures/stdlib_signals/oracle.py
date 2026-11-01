"""Host oracle for supervise: restart counts, backoff delays, signal
forwarding, grace kills and the child's signal/limit environment, against
independently scheduled Python children.
Usage: oracle.py MODE EXECUTABLE. No production code is imported."""
import os
import resource
import signal
import subprocess
import sys
import tempfile
import threading
import time

HELP = (b"Usage: supervise [--max-restarts N] [--backoff-ms N] [--max-backoff-ms N] [--grace-ms N]"
        b" [--stable-ms N] [--max-open-files N] -- PROGRAM [ARG...]\n")
INVALID = b"supervise: invalid arguments; see --help errno=0\n"
PY = [sys.executable, "-I", "-c"]
MS = 1_000_000
cases = 0


def case(condition, *detail):
    global cases
    assert condition, detail
    cases += 1


class Run:
    """The supervisor with its stdout and stderr read by background threads."""

    def __init__(self, exe, *args, session=False):
        self.began = time.monotonic_ns()
        self.process = subprocess.Popen([exe, *args], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=session)
        self.out, self.err, self.lock = [], [], threading.Condition()
        self.threads = [threading.Thread(target=self.pump, args=(self.process.stdout, self.out)),
                        threading.Thread(target=self.pump, args=(self.process.stderr, self.err))]
        for thread in self.threads:
            thread.start()

    def pump(self, stream, lines):
        for line in stream:
            with self.lock:
                lines.append(line)
                self.lock.notify_all()

    def wait_for(self, lines, predicate, limit=10):
        with self.lock:
            case(self.lock.wait_for(lambda: any(predicate(line) for line in lines), timeout=limit), lines)

    def send(self, number):
        self.process.send_signal(number)

    def finish(self, limit=30):
        code = self.process.wait(timeout=limit)
        for thread in self.threads:
            thread.join()
        self.duration = time.monotonic_ns() - self.began
        self.rows = rows(self.err)
        return code


def rows(lines):
    result = []
    for line in lines:
        if line.startswith(b"supervise\t"):
            fields = line.rstrip(b"\n").decode().split("\t")
            case(line.endswith(b"\n") and len(fields) in (4, 5, 6), line)
            result.append((int(fields[1]), fields[2], fields[3:]))
    stamps = [row[0] for row in result]
    case(stamps == sorted(stamps), stamps)
    return result


def kinds(result):
    return [row[1] for row in result]


def stamp(result, kind, index=0):
    return [row[0] for row in result if row[1] == kind][index]


def simple(exe, *args):
    out = subprocess.run([exe, *args], stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    return out


def cli(exe):
    out = simple(exe, "--help")
    case(out.returncode == 0 and out.stdout == HELP and out.stderr == b"", out)
    tail = ["--", "true"]
    for args in ([], ["--"], ["--backoff-ms", "0", *tail], ["--grace-ms", "0", *tail], ["--max-restarts", "1001", *tail],
                 ["--max-open-files", "15", *tail], ["--max-open-files", "1048577", *tail], ["--backoff-ms", "100", "--max-backoff-ms", "50", *tail],
                 ["--grace-ms", "5", "--grace-ms", "5", *tail], ["--bogus", *tail], ["--help", "--"], ["--backoff-ms"],
                 ["--stable-ms", "86400001", *tail], ["--grace-ms", "1x", *tail], ["--max-backoff-ms", "3600001", *tail], ["true"]):
        out = simple(exe, *args)
        case(out.returncode == 125 and out.stdout == b"" and out.stderr == INVALID, args, out)
    out = simple(exe, "--", "/nonexistent/program")
    case(out.returncode == 127 and out.stdout == b"" and out.stderr == b"supervise: cannot execute errno=2\n", out)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        out = simple(exe, "--", directory)
        case(out.returncode == 126 and out.stderr == b"supervise: cannot execute errno=13\n", out)
    # The child environment: empty block mask, nothing ignored, its own process
    # group, the supervisor as parent, and the requested open-file soft limit.
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    # A shell probe: Python itself would ignore SIGPIPE and SIGXFSZ.
    probe = ("read -r stat < /proc/$$/stat; set -- $stat; echo $$ $4 $5;"
             " grep -E '^Sig(Blk|Ign)' /proc/$$/status | cut -f2; ulimit -Sn; ulimit -Hn")
    for files in (None, 40, 64):
        extra = [] if files is None else ["--max-open-files", str(files)]
        run = Run(exe, *extra, "--", "sh", "-c", probe)
        code = run.finish()
        case(code == 0 and len(run.out) == 5, code, run.out)
        pid, parent, group = (int(value) for value in run.out[0].split())
        case(parent == run.process.pid and group == pid and run.out[1:3] == [b"0" * 16 + b"\n"] * 2, run.out)
        case(int(run.out[3]) == (soft if files is None else files) and int(run.out[4]) == hard, run.out, soft, hard)
        case(kinds(run.rows) == ["start", "exit"] and run.rows[1][2] == ["1", "exited", "0"] and run.rows[0][2] == ["1", str(pid)], run.rows)
    # A soft limit above the hard one (testable when the hard limit is below the
    # option's maximum) fails before any child starts.
    refused = True
    if hard < 1048576:
        out = simple(exe, "--max-open-files", str(hard + 1), "--", "true")
        refused = out.returncode == 125 and out.stderr == b"supervise: open-file limit failed errno=22\n"
    case(refused, hard)
    for code in (0, 4):
        run = Run(exe, "--max-restarts", "0", "--", "sh", "-c", f"exit {code}")
        result = run.finish()
        expected = ["start", "exit"] if code == 0 else ["start", "exit", "giveup"]
        case(result == code and kinds(run.rows) == expected, result, run.rows)


def counted(directory, script):
    """A child that numbers its runs in a file, then runs script with n set."""
    path = os.path.join(directory, "runs")
    return ("import os,sys,time,signal\n"
            f"p={path!r}\nn=len(open(p).read()) + 1 if os.path.exists(p) else 1\nopen(p,'a').write('x')\n"
            "print('run',n,os.getpid(),flush=True)\n" + script)


def starts_and_exits(result):
    return [row for row in result if row[1] in ("start", "exit")]


def supervise(exe):
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        # Three crashes then success: delays double from 40 ms and cap at 100.
        run = Run(exe, "--backoff-ms", "40", "--max-backoff-ms", "100", "--", *PY, counted(directory, "sys.exit(3 if n <= 3 else 0)"))
        code = run.finish()
        result = run.rows
        case(code == 0 and kinds(result) == ["start", "exit", "backoff"] * 3 + ["start", "exit"], result)
        backoffs = [row[2] for row in result if row[1] == "backoff"]
        case(backoffs == [["1", "40"], ["2", "80"], ["3", "100"]], backoffs)
        pids = [int(line.split()[2]) for line in run.out]
        case([int(row[2][1]) for row in result if row[1] == "start"] == pids and len(set(pids)) == 4, pids, result)
        for k, wait in enumerate((40, 80, 100)):
            gap = stamp(result, "start", k + 1) - stamp(result, "exit", k)
            case(wait * MS <= gap < (wait + 500) * MS, k, gap)
        case([row[2] for row in result if row[1] == "exit"] == [["1", "exited", "3"], ["2", "exited", "3"], ["3", "exited", "3"], ["4", "exited", "0"]], result)
    with tempfile.TemporaryDirectory(dir=os.environ.get("ORACLE_TMP")) as directory:
        # Stable runs reset the crash count: every delay stays at the base and
        # more crashes than --max-restarts are tolerated.
        run = Run(exe, "--backoff-ms", "30", "--stable-ms", "100", "--max-restarts", "1", "--",
                  *PY, counted(directory, "time.sleep(0.15)\nsys.exit(1 if n <= 3 else 0)"))
        code = run.finish()
        case(code == 0 and [row[2][1] for row in run.rows if row[1] == "backoff"] == ["30", "30", "30"], run.rows)
    # Give up after --max-restarts consecutive crashes; status of the last run.
    run = Run(exe, "--max-restarts", "2", "--backoff-ms", "10", "--", "sh", "-c", "kill -KILL $$")
    code = run.finish()
    case(code == 137 and kinds(run.rows) == ["start", "exit", "backoff"] * 2 + ["start", "exit", "giveup"], run.rows)
    case(all(row[2][1:] == ["signaled", "9"] for row in run.rows if row[1] == "exit") and run.rows[-1][2] == ["2"], run.rows)
    # Forwarding: the child's own handler sees the signal and chooses the status.
    for number, status in ((signal.SIGTERM, 0), (signal.SIGINT, 0), (signal.SIGTERM, 7)):
        child = ("import signal,sys,time\n"
                 f"def h(s,f): print('got',s,flush=True); sys.exit({status})\n"
                 "signal.signal(signal.SIGTERM,h); signal.signal(signal.SIGINT,h)\nprint('ready',flush=True)\n"
                 "while True: time.sleep(1)\n")
        run = Run(exe, "--grace-ms", "5000", "--", *PY, child)
        run.wait_for(run.out, lambda line: line == b"ready\n")
        sent = time.monotonic_ns()
        run.send(number)
        code = run.finish()
        case(code == status and run.out == [b"ready\n", f"got {int(number)}\n".encode()], code, run.out)
        case(kinds(run.rows) == ["start", "forward", "exit"] and run.rows[1][2] == [str(int(number))] and run.rows[2][2] == ["1", "exited", str(status)], run.rows)
        case(time.monotonic_ns() - sent < 3000 * MS, run.duration)
    # A child ignoring the signal is killed when the grace period ends.
    ignore = "import signal,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN); signal.signal(signal.SIGINT,signal.SIG_IGN)\nprint('ready',flush=True)\ntime.sleep(30)\n"
    run = Run(exe, "--grace-ms", "200", "--", *PY, ignore)
    run.wait_for(run.out, lambda line: line == b"ready\n")
    run.send(signal.SIGTERM)
    code = run.finish()
    case(code == 137 and kinds(run.rows) == ["start", "forward", "kill", "exit"] and run.rows[3][2] == ["1", "signaled", "9"], code, run.rows)
    waited = stamp(run.rows, "kill") - stamp(run.rows, "forward")
    case(200 * MS <= waited < 1000 * MS, waited)
    # A second signal during the grace period kills at once.
    run = Run(exe, "--grace-ms", "20000", "--", *PY, ignore)
    run.wait_for(run.out, lambda line: line == b"ready\n")
    run.send(signal.SIGTERM)
    run.wait_for(run.err, lambda line: b"\tforward\t" in line)
    run.send(signal.SIGINT)
    code = run.finish()
    case(code == 137 and kinds(run.rows) == ["start", "forward", "kill", "exit"] and run.duration < 5000 * MS, code, run.rows, run.duration)
    # A signal while waiting out the backoff stops without another start.
    run = Run(exe, "--backoff-ms", "5000", "--", "sh", "-c", "exit 1")
    run.wait_for(run.err, lambda line: b"\tbackoff\t" in line)
    run.send(signal.SIGTERM)
    code = run.finish()
    case(code == 143 and kinds(run.rows) == ["start", "exit", "backoff", "stop"] and run.rows[3][2] == ["15"] and run.duration < 3000 * MS, code, run.rows)
    # A signal to the supervisor's whole process group (as a terminal sends)
    # does not reach the child directly: it sees exactly one forwarded SIGINT.
    count = ("import signal,time\nseen=[]\nsignal.signal(signal.SIGINT,lambda s,f: seen.append(s))\nprint('ready',flush=True)\n"
             "t=time.monotonic()\nwhile time.monotonic()-t<1.0 and not seen: time.sleep(0.01)\ntime.sleep(0.3)\nprint('seen',len(seen),flush=True)\n")
    run = Run(exe, "--", *PY, count, session=True)
    run.wait_for(run.out, lambda line: line == b"ready\n")
    os.killpg(run.process.pid, signal.SIGINT)
    code = run.finish()
    case(code == 0 and run.out == [b"ready\n", b"seen 1\n"] and kinds(run.rows) == ["start", "forward", "exit"], code, run.out, run.rows)


MODES = {"cli": cli, "supervise": supervise}

if __name__ == "__main__":
    mode, exe = sys.argv[1], sys.argv[2]
    MODES[mode](exe)
    print(f"supervise-{mode} cases={cases}")
