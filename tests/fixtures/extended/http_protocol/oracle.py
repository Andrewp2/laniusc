"""Run public Protocol assertions and reuse the syscall-only ownership ledger.

There is no HTTP parser or transport implementation in this harness. The Lanius
fixture supplies its own in-memory transport completions and checks typed API
values. The trace proves that all allocations were explicitly released and
that the Protocol tests performed no network or poll operations.
"""
import importlib.util
import pathlib
import subprocess
import sys
import tempfile


def main(executable):
    source = pathlib.Path(__file__).resolve().parents[1] / "http_batch" / "resources.py"
    spec = importlib.util.spec_from_file_location("http_protocol_resources", source)
    resources = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(resources)
    with tempfile.TemporaryDirectory(prefix="lanius-http-protocol-") as directory:
        trace = pathlib.Path(directory) / "syscalls"
        result = subprocess.run(
            ["strace", "--kill-on-exit", "-qq", "-o", str(trace), "-e",
             "trace=mmap,munmap,socket,connect,poll,sendto,recvfrom,shutdown,close",
             executable],
            stdin=subprocess.DEVNULL, capture_output=True, timeout=20,
        )
        assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
        assert result.stdout == b"protocol states checked\n" and not result.stderr, result
        ledger = resources.analyze(trace)
        for operation in ("socket", "connect", "poll", "sendto", "recvfrom", "shutdown", "close"):
            assert ledger["calls"].get(operation, 0) == 0, (operation, ledger)
        assert ledger["allocations"] and ledger["max_sockets"] == 0, ledger
        print("http-protocol states checked allocations=" + str(len(ledger["allocations"])) +
              " explicit-owner-ledger=balanced no-network")


if __name__ == "__main__":
    assert len(sys.argv) == 2, sys.argv
    main(sys.argv[1])
