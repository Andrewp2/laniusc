"""Finite source staging/OOM campaign; native OpenSSL mappings are not owners."""
from pathlib import Path
import socket
import struct
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
from resources import analyze, controls


def invoke(executable, certificates, trace, fault=None):
    parent, inherited = socket.socketpair()
    inherited.setblocking(False)
    command = ["strace", "--kill-on-exit", "-qq", "-i", "-o", str(trace),
               "-e", "trace=mmap,munmap,write"]
    if fault is not None:
        command += ["-e", f"inject=mmap:error=ENOMEM:when={fault['ordinal']}"]
    command += [str(executable), str(inherited.fileno()), str(certificates / "root.pem")]
    try:
        result = subprocess.run(command, pass_fds=(inherited.fileno(),), stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=7)
        assert result.returncode == 0 and len(result.stdout) == 8 and result.stderr == b"A\nB\n", (command, result)
    finally:
        parent.close(); inherited.close()
    text = trace.read_text()
    requests = analyze(executable, text)
    targeted = [request for request in requests if request["active"]]
    markers = [line for line in text.splitlines() if "(INJECTED)" in line]
    if fault is None:
        assert not markers
    else:
        assert len(markers) == 1 and "mmap(" in markers[0] and " = -1 ENOMEM " in markers[0], markers
        failed = [request for request in requests if request["injected"]]
        assert len(failed) == 1 and failed[0]["active"], (failed, requests)
        assert {key: failed[0][key] for key in ("ordinal", "ip", "length")} == {
            key: fault[key] for key in ("ordinal", "ip", "length")}, (failed, fault)
    return struct.unpack("<Q", result.stdout)[0], targeted


def main(executable, certificates):
    assert controls() == 9
    with tempfile.TemporaryDirectory(prefix="tls_duplex_alloc_") as directory:
        directory = Path(directory)
        outcome, baseline = invoke(executable, certificates, directory / "baseline")
        assert outcome == 0
        # Exact source roles: packed trust, packed identity, reader, writer,
        # independent read/write size_t cells. Retain itself adds no source map.
        sizes = [len(str(certificates / "root.pem").encode()) + 1, 10, 97, 97, 16]
        assert [request["length"] for request in baseline] == sizes, baseline
        for index, fault in enumerate(baseline):
            outcome, attempts = invoke(executable, certificates, directory / f"oom-{index}", fault)
            assert outcome == (1 if index == 0 else 2 if index == 1 else 3), (index, outcome)
            assert len(attempts) == index + 1
            assert [(row["ip"], row["length"]) for row in attempts] == [
                (row["ip"], row["length"]) for row in baseline[:index + 1]], (attempts, baseline)
    print("openssl-tls-duplex allocations cases=6 reached-source-oom=5 ledger-controls=9")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
