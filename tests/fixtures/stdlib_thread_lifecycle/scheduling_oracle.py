"""One reached syscall per case: preserve kernel errors and validate raw counts."""
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile


def inspect(text, operation, injected):
    lines = text.splitlines()
    assert len(lines) == 1, lines
    line = lines[0]
    assert line.startswith(operation + "("), line
    if operation == "sched_yield":
        assert line.startswith("sched_yield()"), line
    else:
        assert line.startswith("sched_getaffinity(0, 128, "), line
    marked = "INJECTED" in line or "POKED" in line
    assert marked == injected, line
    assert re.search(r"\)\s+=\s+", line), line


def diagnostics(stderr, fault):
    # Some strace versions warn about an unused compat personality while
    # correctly injecting the full x86_64 result. Admit only these two exact
    # warnings; the output and trace still have to prove the 64-bit result.
    if not stderr:
        return
    values = {"retval=4294967296": (4294967296, 0),
              "retval=4294967297:poke_exit=@arg3=01": (4294967297, 1)}
    assert fault in values, (fault, stderr)
    value, clipped = values[fault]
    expected = f"strace: Injected return value {value} will be clipped to {clipped} in compat personality\n".encode()
    assert stderr == expected, (fault, stderr)


def controls():
    inspect("sched_yield() = 0\n", "sched_yield", False)
    inspect("sched_getaffinity(0, 128, [0]) = 1 (INJECTED)\n", "sched_getaffinity", True)
    corruptions = [
        ("sched_yield() = 0\nsched_yield() = 0\n", "sched_yield", False),
        ("sched_yield() = 0 (INJECTED)\n", "sched_yield", False),
        ("sched_yield() = 0\n", "sched_yield", True),
        ("sched_getaffinity(1, 128, [0]) = 1 (INJECTED)\n", "sched_getaffinity", True),
        ("sched_getaffinity(0, 256, [0]) = 1\n", "sched_getaffinity", False),
    ]
    for args in corruptions:
        try:
            inspect(*args)
        except AssertionError:
            continue
        raise AssertionError(("scheduling observer admitted an invalid trace", args))
    warning = b"strace: Injected return value 4294967296 will be clipped to 0 in compat personality\n"
    diagnostics(warning, "retval=4294967296")
    diagnostics(warning.replace(b"4294967296", b"4294967297").replace(b"clipped to 0", b"clipped to 1"), "retval=4294967297:poke_exit=@arg3=01")
    for stderr, fault in ((warning, "retval=1"), (warning + b"other error\n", "retval=4294967296")):
        try:
            diagnostics(stderr, fault)
        except AssertionError:
            continue
        raise AssertionError(("scheduling observer admitted unrelated stderr", stderr, fault))
    return 2 + len(corruptions) + 4


def main():
    checked = controls()
    if sys.argv[1:] == ["controls"]:
        print(f"thread-scheduling-controls={checked}")
        return
    assert len(sys.argv) == 2
    executable = Path(sys.argv[1]).resolve()
    cases = [
        (0, None, (0, 0)),
        (0, "error=EIO", (1, 5)),
        (0, "retval=1", (1, -2)),
        (0, "retval=4294967296", (1, -2)),
        (1, None, (0, len(os.sched_getaffinity(0)))),
        (1, "error=EINVAL", (1, 22)),
        (1, "retval=0", (1, -2)),
        (1, "retval=129", (1, -2)),
        # A nonzero first byte distinguishes full-width rejection from a
        # narrowing bug that would accept length1 and count this bit.
        (1, "retval=4294967297:poke_exit=@arg3=01", (1, -2)),
        (1, "retval=1", (1, -2)),
        (1, "retval=128", (1, -2)),
        (1, "retval=1:poke_exit=@arg3=81", (0, 2)),
        (1, "retval=128:poke_exit=@arg3=" + "01" + "00" * 126 + "80", (0, 2)),
    ]
    with tempfile.TemporaryDirectory(prefix="thread-scheduling-") as directory:
        for index, (mode, fault, expected) in enumerate(cases):
            trace = Path(directory) / str(index)
            operation = "sched_yield" if mode == 0 else "sched_getaffinity"
            command = ["strace", "--kill-on-exit", "-qq", "-e", "signal=none", "-e", "trace=sched_yield,sched_getaffinity", "-o", str(trace)]
            if fault:
                command += ["-e", "inject=" + operation + ":" + fault + ":when=1"]
            command.append(str(executable))
            result = subprocess.run(command, input=bytes([mode]), capture_output=True, timeout=5)
            assert result.returncode == 0, (index, result, trace.read_text())
            diagnostics(result.stderr, fault)
            assert len(result.stdout) == 8 and struct.unpack("<ii", result.stdout) == expected, (index, expected, result)
            observed = trace.read_text()
            inspect(observed, operation, fault is not None)
            if fault and fault.startswith("retval="):
                returned = re.search(r"\)\s+=\s+(-?\d+)\b", observed)
                assert returned and int(returned[1]) == int(fault.split(":", 1)[0][7:]), observed
    print(f"thread-scheduling cases={len(cases)} injected={sum(fault is not None for _, fault, _ in cases)} controls={checked}")


if __name__ == "__main__":
    main()
