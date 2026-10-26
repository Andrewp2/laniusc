"""Actual Server ownership checkpoint, reusing the accepted source/FD ledger."""
import os
from pathlib import Path
import re
import select
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "server_poll"))
from publication_oracle import resources


def run(executable):
    directory = Path(tempfile.mkdtemp(prefix="server-poll-ownership-"))
    trace = directory / "trace.txt"
    command = ["strace", "--kill-on-exit", "-qq", "-o", str(trace), "-e", "trace=mmap,munmap,socket,accept4,close,recvfrom,read,write", str(executable)]
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    captured = bytearray()
    try:
        deadline = time.monotonic() + 12
        while len(captured) < 16:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], "native owner control stalled"
            chunk = os.read(process.stdout.fileno(), 16 - len(captured))
            assert chunk, "native owner control exited before checkpoint"
            captured.extend(chunk)
        assert struct.unpack("<4i", captured) == (0x53504F4C, 3, 6, 6), captured
        children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
        assert len(children) == 1, children
        assert set(os.listdir(f"/proc/{int(children[0])}/fd")) == {"0", "1", "2"}
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
        print("server-poll-ownership cases=3")
    except BaseException:
        (directory / "stdout.bin").write_bytes(captured)
        if process.poll() is None:
            process.kill()
        output, error = process.communicate(timeout=3)
        (directory / "tail.bin").write_bytes(output)
        (directory / "stderr.bin").write_bytes(error)
        print(f"actual Server ownership evidence: {directory}", file=sys.stderr)
        raise


if __name__ == "__main__":
    run(Path(sys.argv[1]).resolve())
