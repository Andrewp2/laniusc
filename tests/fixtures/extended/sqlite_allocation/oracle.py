"""Reached Lanius staging mmap failures around real SQLite calls."""

from dataclasses import dataclass
from pathlib import Path
import os
import re
import subprocess
import sys
import tempfile

SIZES = [97, 209, 313, 521]
MMAP = re.compile(r"mmap\((.*)\)\s+= (\S+)(.*)$")
MUNMAP = re.compile(r"munmap\((0x[0-9a-f]+), (\d+)\)\s+= (\S+)(.*)$")
IP = re.compile(r"\[([0-9a-f]+)\]\s+(.*)$")


@dataclass
class Attempt:
    ordinal: int
    size: int
    ip: str
    address: str
    injected: bool


def mappings(trace):
    """Track only the application's small anonymous MAP_32BIT allocations."""
    ordinal = 0
    live = {}
    attempts = []
    released = 0
    for line in trace.splitlines():
        location = IP.fullmatch(line)
        if location is None:
            assert "mmap(" not in line and "munmap(" not in line, line
            continue
        ip, body = location.groups()
        mapped = MMAP.fullmatch(body)
        if mapped:
            ordinal += 1
            arguments, address, suffix = mapped.groups()
            address_hint, size, protection, flags, descriptor, offset = arguments.split(", ")
            if "MAP_32BIT" not in flags:
                # Dynamic loader, libc and the CRT process-vector mapping do
                # not belong to the wrapper's temporary staging owners.
                continue
            size = int(size)
            assert (address_hint, protection, descriptor, offset) == (
                "NULL", "PROT_READ|PROT_WRITE", "-1", "0"
            ), line
            assert set(flags.split("|")) == {"MAP_PRIVATE", "MAP_ANONYMOUS", "MAP_32BIT"}, line
            assert 0 < size < 4096 and size in SIZES, line
            injected = "INJECTED" in suffix
            if address.startswith("0x"):
                assert not injected and address not in live, line
                live[address] = size
            else:
                assert address == "-1" and "ENOMEM" in suffix and injected, line
            attempts.append(Attempt(ordinal, size, ip, address, injected))
            continue
        unmapped = MUNMAP.fullmatch(body)
        if unmapped:
            address, size, result, _ = unmapped.groups()
            if address in live:
                assert result == "0" and live.pop(address) == int(size), line
                released += 1
    assert not live, ("unreleased Lanius SQLite staging owners", live, trace)
    assert released == sum(attempt.address.startswith("0x") for attempt in attempts), trace
    return attempts


def execute(executable, observer, fail_at=None):
    with tempfile.TemporaryDirectory(prefix="laniusc-sqlite-allocation-") as directory:
        directory = Path(directory)
        trace = directory / "mappings.trace"
        lifecycle = directory / "lifecycle.trace"
        with lifecycle.open("wb") as events:
            environment = os.environ.copy()
            environment["LD_PRELOAD"] = str(observer)
            environment["LANIUS_SQLITE_ALLOCATION_FD"] = str(events.fileno())
            command = ["strace", "-i", "-qq", "-o", str(trace), "-e", "trace=mmap,munmap"]
            if fail_at is not None:
                command += ["-e", f"inject=mmap:error=ENOMEM:when={fail_at}"]
            command.append(str(executable))
            output = subprocess.run(command, cwd=directory, env=environment,
                                    pass_fds=(events.fileno(),), capture_output=True, timeout=8)
        text = trace.read_text()
        assert output.stdout == b"" and output.stderr == b"", (output, text)
        assert lifecycle.read_bytes() == b"OPTBFC", (output, lifecycle.read_bytes(), text)
        attempts = mappings(text)
        assert text.count("INJECTED") == (0 if fail_at is None else 1), text
        databases = list(directory.glob("*.db"))
        assert len(databases) == 1, (output, list(directory.iterdir()))
        # The SELECT-only connection must leave no statement, lock or journal
        # behind. Actual native close/finalize calls are observed above.
        assert not list(directory.glob("*.db-*")), list(directory.iterdir())
        return output.returncode, attempts


def main():
    executable, observer = (Path(argument).resolve() for argument in sys.argv[1:])
    status, baseline = execute(executable, observer)
    assert status == 0, (status, baseline)
    assert [attempt.size for attempt in baseline] == SIZES, baseline
    assert len({attempt.ip for attempt in baseline}) == 1, baseline
    allocator_ip = baseline[0].ip
    for stage, selected in enumerate(baseline, 1):
        status, attempts = execute(executable, observer, selected.ordinal)
        # This tag is produced only after the fixture observes the typed
        # AllocationFailed phase, checks preserved state and completes retry.
        assert status == stage, (stage, status, attempts)
        expected = SIZES[:stage] + SIZES[stage - 1:]
        assert [attempt.size for attempt in attempts] == expected, (stage, attempts)
        assert {attempt.ip for attempt in attempts} == {allocator_ip}, attempts
        failed = [attempt for attempt in attempts if attempt.injected]
        assert len(failed) == 1 and failed[0].ordinal == selected.ordinal, (selected, failed)
        assert failed[0].size == selected.size and failed[0].ip == allocator_ip, failed
    print("sqlite-allocation cases=5 reached_oom=4 staging_sizes=97,209,313,521 lifecycle=OPTBFC")


if __name__ == "__main__":
    main()
