"""Independent native owner ledger for actual Server active-cap/cancel controls."""
import os
from pathlib import Path
import re
import select
import struct
import subprocess
import sys
import tempfile
import time


def resources(text, complete):
    maps, fds = {}, set()
    allocations = accepts = eof = polls = 0
    for line in text.splitlines():
        if " = " not in line:
            assert not complete and line.startswith("read(0, "), line
            continue
        name = line.split("(", 1)[0]
        result = line.rsplit(" = ", 1)[1].split()[0]
        if name == "mmap" and result.startswith("0x"):
            # The unlinked ELF has no native CRT/OpenSSL allocation owners.
            assert "MAP_32BIT" in line and result not in maps, line
            maps[result] = int(line.split(",")[1])
            allocations += 1
        elif name == "munmap":
            address, length = line[7:].split(")", 1)[0].split(",")
            assert result == "0" and maps.pop(address, None) == int(length), line
        elif name in ("socket", "accept4") and re.fullmatch(r"\d+", result):
            handle = int(result)
            assert handle not in fds, line
            fds.add(handle)
            accepts += name == "accept4"
        elif name == "close":
            handle = int(line[6:].split(")", 1)[0])
            assert result == "0" and handle in fds, line
            fds.remove(handle)
        elif name == "recvfrom":
            assert result == "0" or (result == "-1" and ("EAGAIN" in line or "EINTR" in line)), line
            eof += result == "0"
        elif name == "poll":
            assert re.fullmatch(r"\d+", result), line
            polls += 1
        else:
            assert name in ("read", "write"), line
    assert not maps and not fds and allocations > 0 and accepts == 13 and eof == 15 and polls > 0, (maps, fds, allocations, accepts, eof, polls, text)


def run(executable):
    directory = Path(tempfile.mkdtemp(prefix="server-poll-limits-"))
    trace = directory / "trace.txt"
    command = ["strace", "--kill-on-exit", "-qq", "-o", str(trace), "-e", "trace=mmap,munmap,socket,accept4,close,recvfrom,poll,read,write", str(executable)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    captured = bytearray()
    try:
        deadline = time.monotonic() + 12
        while len(captured) < 16:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "native cap/cancel control stalled"
            chunk = os.read(process.stdout.fileno(), 16 - len(captured))
            assert chunk, "native control exited before checkpoint"
            captured.extend(chunk)
        assert struct.unpack("<4i", captured) == (0x534C494D, 7, 13, 15), captured
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1, children
        child = int(children[0])
        assert set(os.listdir(f"/proc/{child}/fd")) == {"0", "1", "2"}
        until = time.monotonic() + 2
        while True:
            text = trace.read_text()
            if re.search(r"write\(1, .*16\)\s+= 16", text):
                break
            assert time.monotonic() < until, text
            time.sleep(0.005)
        resources(text, False)
        process.stdin.write(b"\x01")
        process.stdin.flush()
        output, error = process.communicate(timeout=5)
        assert process.returncode == 0 and not output and not error, (process.returncode, output, error)
        resources(trace.read_text(), True)
        print("server-poll-limits cases=7")
    except BaseException:
        (directory / "stdout.bin").write_bytes(captured)
        if process.poll() is None:
            process.kill()
        output, error = process.communicate(timeout=3)
        (directory / "tail.bin").write_bytes(output)
        (directory / "stderr.bin").write_bytes(error)
        print(f"persistent Server cap/cancel evidence: {directory}", file=sys.stderr)
        raise


if __name__ == "__main__":
    run(Path(sys.argv[1]).resolve())
