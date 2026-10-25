"""Native checked samples: independent result models and reached syscall faults."""
from pathlib import Path
from contextlib import ExitStack
import os
import random
import re
import subprocess
import sys
import tempfile

GROUP = sys.argv[1]
PROGRAMS = dict(zip(sys.argv[2::2], sys.argv[3::2]))
COUNTS = dict(models=0, allocations=0, reads=0, writes=0, other=0, full=0, broken_pipes=0)


def run(name, data=b"", injection=None, traced=False, full=False, broken=False):
    with tempfile.TemporaryDirectory(prefix="lanius-checked-sample-") as folder:
        trace = Path(folder) / "trace"
        command = [PROGRAMS[name]]
        if traced:
            command = ["strace", "-qq", "-o", str(trace), "-e",
                       "trace=mmap,munmap,read,write,open,openat,close,getrandom,rt_sigaction"] + (
                           ["-e", "inject=" + injection] if injection else []) + command
        with ExitStack() as resources:
            sink = subprocess.PIPE
            if full:
                sink = resources.enter_context(open("/dev/full", "wb"))
            if broken:
                reader, sink = os.pipe()
                os.close(reader)
                resources.callback(os.close, sink)
            result = subprocess.run(command, input=data,
                                    stdout=sink,
                                    stderr=subprocess.PIPE, cwd=folder, timeout=6)
        assert result.returncode >= 0, (name, injection, result.returncode, result.stderr)
        events = trace.read_text() if traced else ""
        if injection:
            assert "INJECTED" in events, (name, injection, events)
        if traced:
            released(events)
            if name == "host_runtime_files":
                handles = set()
                for line in events.splitlines():
                    match = re.match(r"open(?:at)?\(.*\)\s+= (\d+)$", line)
                    if match:
                        assert match[1] not in handles, line
                        handles.add(match[1])
                    match = re.match(r"close\((\d+)\)", line)
                    if match:
                        # A close error is ambiguous: ownership ends after
                        # one attempt, and retry could close a reused handle.
                        assert match[1] in handles, line
                        handles.remove(match[1])
                assert not handles, ("missing close attempt", handles, events)
        if name == "host_runtime_files" and result.returncode == 0:
            assert (Path(folder) / "host_runtime_files.txt").read_bytes() == b"12345\n"
        return result, events


def released(trace):
    live = {}
    for line in trace.splitlines():
        match = re.match(r"mmap\(NULL, (\d+),.*\)\s+= (0x[0-9a-f]+)", line)
        if match:
            length, address = match.groups()
            assert address not in live, line
            live[address] = int(length)
        match = re.match(r"munmap\((0x[0-9a-f]+), (\d+)\)\s+= 0", line)
        if match:
            address, length = match.groups()
            assert live.pop(address, None) == int(length), line
    assert not live, ("unreleased application mappings", live, trace)


def check(name, data, expected, status=0, stderr=b""):
    result, _ = run(name, data)
    assert (result.returncode, result.stdout, result.stderr) == (status, expected, stderr), (
        name, data[:120], result.returncode, result.stdout[:120], result.stderr)
    COUNTS["models"] += 1


def faults(name, data, expected, retry_reads=False):
    normal, events = run(name, data, traced=True)
    assert (normal.returncode, normal.stdout, normal.stderr) == (0, expected, b""), (name, normal)
    allocations = sum(bool(re.match(r"mmap\(NULL, \d+,.*\)\s+= 0x", line)) for line in events.splitlines())
    for at in range(1, allocations + 1):
        result, _ = run(name, data, f"mmap:error=ENOMEM:when={at}", traced=True)
        assert result.returncode != 0, (name, "allocation accepted failure", at)
        assert expected.startswith(result.stdout), (name, at, result.stdout)
        COUNTS["allocations"] += 1

    reads = [line for line in events.splitlines() if line.startswith("read(")]
    for at in range(1, len(reads) + 1):
        for fault in ["error=EIO", "error=EINTR"]:
            result, _ = run(name, data, f"read:{fault}:when={at}", traced=True)
            if fault == "error=EINTR" and (retry_reads or name == "host_runtime_files"):
                assert (result.returncode, result.stdout, result.stderr) == (0, expected, b""), (name, at, result)
            else:
                assert result.returncode != 0, (name, at, fault, result)
                assert not result.stdout, (name, at, fault, result.stdout)
            COUNTS["reads"] += 1

    writes = [line for line in events.splitlines() if line.startswith("write(")]
    stdout_before = 0
    for at, line in enumerate(writes, 1):
        match = re.match(r"write\((\d+), .*, (\d+)\)\s+= (\d+)$", line)
        assert match, line
        fd, requested, completed = map(int, match.groups())
        assert completed == requested, line
        for fault in ["error=EIO", "retval=0", "error=EINTR"]:
            result, _ = run(name, data, f"write:{fault}:when={at}", traced=True)
            if fault == "error=EINTR":
                assert (result.returncode, result.stdout, result.stderr) == (0, expected, b""), (name, at, result)
            else:
                assert result.returncode != 0, (name, at, fault, result)
                assert expected.startswith(result.stdout), (name, at, fault, result.stdout)
            COUNTS["writes"] += 1
        if fd == 1 and requested > 1:
            result, _ = run(name, data, f"write:retval=1:when={at}", traced=True)
            # strace pretends the first byte was written without copying it.
            # The retry must continue at the following byte exactly once.
            omitted = expected[:stdout_before] + expected[stdout_before + 1:]
            assert (result.returncode, result.stdout, result.stderr) == (0, omitted, b""), (name, at, result)
            COUNTS["writes"] += 1
        if fd == 1:
            stdout_before += completed

    result, _ = run(name, data, traced=True, full=True)
    assert result.returncode != 0, (name, "accepted /dev/full")
    COUNTS["full"] += 1
    result, _ = run(name, data, traced=True, broken=True)
    assert result.returncode > 0, (name, "closed pipe must report failure, not SIGPIPE termination", result)
    COUNTS["broken_pipes"] += 1
    result, _ = run(name, data, "rt_sigaction:error=EIO:when=1", traced=True)
    assert result.returncode > 0 and not result.stdout and not result.stderr, (name, "signal setup failure", result)
    COUNTS["other"] += 1
    if name == "random_fill":
        for fault in ["error=EIO", "error=EINTR", "retval=0", "retval=1"]:
            result, _ = run(name, data, "getrandom:" + fault + ":when=1", traced=True)
            assert result.returncode == 2 and not result.stdout and not result.stderr, result
            COUNTS["other"] += 1
    if name == "host_runtime_files":
        result, _ = run(name, data, "read:retval=0:when=1", traced=True)
        assert result.returncode == 4 and not result.stdout and not result.stderr, result
        COUNTS["reads"] += 1
        for call in ["open", "openat", "close"]:
            number = sum(line.startswith(call + "(") for line in events.splitlines())
            for at in range(1, number + 1):
                result, fault_events = run(name, data, f"{call}:error=EIO:when={at}", traced=True)
                assert result.returncode != 0 and not result.stdout, (call, at, result)
                # Every successfully opened handle has a close attempt, even
                # after I/O failure. Never retry an ambiguous close error.
                opened = re.findall(r"^open(?:at)?\(.*\)\s+= (\d+)$", fault_events, re.M)
                closed = re.findall(r"^close\((\d+)\)", fault_events, re.M)
                assert all(fd in closed for fd in opened), (call, at, fault_events)
                COUNTS["other"] += 1


if GROUP == "fixed":
    expected = dict(vector_halfword_checksum=b"4\n", vector_unsigned_checksum=b"4\n",
                    vector_signed_byte_sum=b"1\n", vector_signed_halfword_sum=b"1\n",
                    vector_true_count=b"2\n", vector_square_sum=b"285\n", vector_edit_checksum=b"19\n")
    for name in PROGRAMS:
        check(name, b"", expected[name])
        faults(name, b"", expected[name])
elif GROUP == "output":
    expected = dict(result_reading_total=b"20\n-2\n", random_fill=b"91\n", stdio_flush=b"73\n",
                    stdio_print_i32=b"34\n55\n", host_runtime_files=b"12345\n")
    for name in PROGRAMS:
        check(name, b"", expected[name])
        faults(name, b"", expected[name])
elif GROUP == "unicode":
    rng = random.Random(0xA110C_2026)
    alphabet = [0, 9, 10, 13, 32, 65, 97, 0xE9, 0x300, 0x301, 0x3A3, 0x200D, 0x4E00, 0x1F642, 0x10FFFF]
    texts = ["", "\0", "Aé🙂\0", "é\u0301é\u0301", "\r\n\t", chr(0x10FFFF)]
    texts += ["".join(chr(rng.choice(alphabet)) for _ in range(rng.randrange(120))) for _ in range(96)]
    for text in texts:
        raw = text.encode()
        check("unicode_sort_unique", raw, ("".join(sorted(set(text), key=ord)) + "\n").encode())
        check("unicode_text_report", raw, f"{len(raw)} {len(text)}\n".encode() + text[::-1].encode())
    check("unicode_sort_unique", b"A" * 4096, b"A\n")
    check("unicode_sort_unique", b"A" * 4097, b"", 4)
    limited, _ = run("unicode_sort_unique", b"A" * 4097, traced=True)
    assert limited.returncode == 4 and not limited.stdout
    for data in [b"\xff", b"a\xed\xa0\x80", b"A" * 4096 + b"\xff"]:
        check("unicode_sort_unique", data, b"", 2)
        check("unicode_text_report", data, b"", 2, b"invalid UTF-8 input\n")
        for name in PROGRAMS:
            failed, _ = run(name, data, traced=True)
            assert failed.returncode == 2 and not failed.stdout
    for fault in ["error=EIO", "retval=0", "error=EINTR", "retval=1"]:
        result, _ = run("unicode_text_report", b"\xff", "write:" + fault + ":when=1", traced=True)
        if fault in ["error=EIO", "retval=0"]:
            assert result.returncode == 3 and not result.stdout and not result.stderr, result
        else:
            expected_error = b"invalid UTF-8 input\n" if fault == "error=EINTR" else b"nvalid UTF-8 input\n"
            assert result.returncode == 2 and not result.stdout and result.stderr == expected_error, result
        COUNTS["writes"] += 1
    faults("unicode_sort_unique", "é🙂Aé\n".encode(), "\nAé🙂\n".encode())
    witness = "Aé🙂\0Aé🙂\0"
    faults("unicode_text_report", witness.encode(), b"16 8\n" + witness[::-1].encode())
elif GROUP == "wide":
    rng = random.Random(0x6400_A110C)
    for signed in [True, False]:
        name = "wide_signed_sum" if signed else "wide_unsigned_sum"
        low, high = (-(1 << 63), (1 << 63) - 1) if signed else (0, (1 << 64) - 1)
        vectors = [[], [low], [high], [low, high, 0, 1], [high, high, 1, 1]]
        vectors += [[rng.randrange(low, high + 1) for _ in range(rng.randrange(1, 65))] for _ in range(32)]
        for values in vectors:
            data = "".join(f"{value}\n" for value in values).encode()
            total = sum(values) % (1 << 64)
            if signed and total >= 1 << 63:
                total -= 1 << 64
            check(name, data, f"{total}\n".encode())
        for data, code in [(b"\n", 2), (b" 1\n", 3), (b"1" * 21 + b"\n", 2)]:
            check(name, data, b"", code)
            result, _ = run(name, b"1\n2\n" + data, traced=True)
            assert result.returncode == code and not result.stdout
        values = [low, high, 0, 1, 7]
        data = "".join(f"{value}\n" for value in values).encode()
        total = sum(values) % (1 << 64)
        if signed and total >= 1 << 63:
            total -= 1 << 64
        faults(name, data, f"{total}\n".encode())
elif GROUP == "heap":
    name = "top_scores"
    rng = random.Random(0x70_52026)
    values = [-(1 << 63), (1 << 63) - 1, 0, -1, 42, 42] + [rng.randrange(-(1 << 63), 1 << 63) for _ in range(513)]
    for k in [0, 1, 2, 17, 256, 4096]:
        data = f"{k}\n".encode() + "".join(f"{value}\n" for value in values).encode()
        expected = "".join(f"{value}\n" for value in sorted(values, reverse=True)[:k]).encode()
        check(name, data, expected)
    for data in [b"", b"-1\n", b"4097\n", b"0\ninvalid\n", b"2\n9223372036854775808\n", b"2\n1\n2\n3\ninvalid\n"]:
        check(name, data, b"", 2)
        result, _ = run(name, data, traced=True)
        assert result.returncode == 2
    values = [42, -5, 42, (1 << 63) - 1, -(1 << 63), 17, 90, 0, 7]
    data = b"5\n" + "".join(f"{value}\n" for value in values).encode()
    expected = "".join(f"{value}\n" for value in sorted(values, reverse=True)[:5]).encode()
    faults(name, data, expected, retry_reads=True)
else:
    raise AssertionError(GROUP)

print("verified", GROUP, "seeded models and reached native failure/cleanup cases", COUNTS)
