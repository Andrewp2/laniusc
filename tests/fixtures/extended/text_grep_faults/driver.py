"""Allocation and I/O fault matrix for sample_programs/library/text_grep.lani.

    python3 -I driver.py FAULTINJ TEXT_GREP

FAULTINJ is faultinj.c built with any C compiler. For each pattern the driver
runs one clean search, then denies every observed mmap with ENOMEM, fails every
observed read with EIO and EINTR, and fails every stdout write with EIO, a zero
return, EINTR and a faked one-byte transfer. Every run must give the documented
status and diagnostic, keep stdout a prefix of the clean output, and leave
/proc/PID/maps at exit identical to its state at the first trapped call.
"""
import os
import subprocess
import sys
import tempfile

INPUT = "aaé\r\nnope\néa".encode()
EXPECTED = "1:aaé\r\n3:éa".encode()
# The first pattern has assertions and runs on the VM. The second is
# assertion-free, so text_grep answers each record with its lazy DFA.
PATTERNS = [("vm", "^(?:a|é)+$"), ("dfa", "(?:a|é)+")]


def main():
    inj, exe = sys.argv[1], sys.argv[2]
    work = tempfile.mkdtemp(prefix="text_grep_faults_", dir=os.environ.get("FAULT_DIR"))
    source = os.path.join(work, "input")
    with open(source, "wb") as f:
        f.write(INPUT)
    report_path = os.path.join(work, "report")
    failures = []

    def execute(args, syscall="none", when=0, action="e0", stdout=None):
        with open(source, "rb") as stdin:
            p = subprocess.run([inj, report_path, syscall, str(when), action, "--", exe, *args],
                               stdin=stdin, stdout=stdout or subprocess.PIPE,
                               stderr=subprocess.PIPE, timeout=20)
        report = {}
        for line in open(report_path):
            key, _, value = line.rstrip("\n").partition(" ")
            report.setdefault(key, []).append(value)
        return p, report

    def check(label, ok, detail):
        if not ok:
            failures.append((label, detail))

    def clean(label, p, r, wanted):
        check(label, p.returncode == 0 and p.stdout == wanted and p.stderr == b"",
              (p.returncode, p.stdout, p.stderr))
        check(label + " maps", r["maps_changed"] == ["0"], r)

    def failed(label, p, r, status, reason, injected=True):
        message = p.stderr.decode(errors="replace")
        check(label, p.returncode == status and EXPECTED.startswith(p.stdout or b"")
              and message.startswith("text-grep: ") and message.endswith("\n") and reason in message,
              (p.returncode, p.stdout, p.stderr))
        check(label + " maps", r["maps_changed"] == ["0"], r)
        if injected:
            check(label + " injected", r["injected"] == ["1"], r)

    totals = {}
    for name, pattern in PATTERNS:
        args = ["-n", pattern]
        p, r = execute(args)
        clean(name + " baseline", p, r, EXPECTED)
        mmaps, reads = int(r["mmap"][0]), int(r["read"][0])
        writes = [int(w) for w in r["stdout_writes"][0].split()]
        check(name + " balanced", r["munmap"] == r["mmap"], r)
        for when in range(1, mmaps + 1):
            p, r = execute(args, "mmap", when, "e12")
            failed(f"{name} mmap {when}", p, r, 4, "allocation-failure")
        for when in range(1, reads + 1):
            p, r = execute(args, "read", when, "e5")
            failed(f"{name} read EIO {when}", p, r, 3, "io-failure stage=input")
            p, r = execute(args, "read", when, "e4")
            clean(f"{name} read EINTR {when}", p, r, EXPECTED)
        # Writes to fds other than 1 are not expected before the last stdout
        # write, so the write ordinal of stdout write k is k.
        offset = 0
        for index, count in enumerate(writes):
            when = index + 1
            for action in ("e5", "r0"):
                p, r = execute(args, "write", when, action)
                failed(f"{name} write {action} {when}", p, r, 3, "io-failure stage=output")
            p, r = execute(args, "write", when, "e4")
            clean(f"{name} write EINTR {when}", p, r, EXPECTED)
            shortened = EXPECTED[:offset] + EXPECTED[offset + 1:]
            p, r = execute(args, "write", when, "r1")
            clean(f"{name} write short {when}", p, r, shortened)
            offset += count
        check(name + " write lengths", offset == len(EXPECTED), writes)
        totals[name] = (mmaps, reads, len(writes))
        print(f"{name} {pattern!r}: {mmaps} mmap/{mmaps} munmap, {mmaps} allocation failures, "
              f"{reads} reads x2 faults, {len(writes)} stdout writes x4 faults")
    with open("/dev/full", "wb") as full:
        p, r = execute([".",], stdout=full)
    failed("/dev/full", p, r, 3, "io-failure stage=output", injected=False)
    p, r = execute(["--bad"], "write", 1, "e5")
    check("failed diagnostic", p.returncode == 3 and p.stdout == b"" and p.stderr == b"",
          (p.returncode, p.stdout, p.stderr))
    check("failed diagnostic maps", r["maps_changed"] == ["0"], r)
    runs = sum(1 + m + 2 * rd + 4 * w for m, rd, w in totals.values()) + 2
    print(f"runs {runs}")
    print(f"failures {len(failures)}")
    for label, detail in failures[:20]:
        print(" ", label, detail)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
