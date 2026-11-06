"""Borrowed text operations may not allocate or release source storage.

Use the existing exact native/runtime authority. Loader and CRT mappings are
classified separately; an unknown syscall inside the executable is rejected.
"""
import importlib.util
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


FIXTURES = Path(__file__).resolve().parent.parent
NATIVE = load("text_partition_source_authority", FIXTURES / "native_c/source_allocations.py")
LEDGER = load("text_partition_trace_syntax", FIXTURES / "stdlib_execution/temp_file/ledger.py")


def inspect(trace, profile):
    assert trace.endswith("\n"), "truncated text partition trace"
    markers = []
    for line in trace.splitlines():
        match = LEDGER.LINE.fullmatch(line)
        assert match, ("unsupported text partition trace", line)
        ip, name, args, result = match.groups()
        authority = NATIVE.classify(profile, int(ip, 16))
        if name == "write":
            token = re.fullmatch(r'2, "\\x([0-9a-f]{2})", 1', args)
            assert authority == "source" and result == "1" and token, line
            markers.append(chr(int(token[1], 16)))
        else:
            assert name in ("mmap", "munmap"), line
            assert authority in ("native", "bootstrap-" + name), ("borrowed operation touched source allocation", line)
    assert markers == ["P", "p"], markers


def controls():
    pairs = NATIVE.RuntimePairs([(0x401002, 0x401012)])
    pairs.source_syscall_sites = {0x401002, 0x401012, 0x401022}
    pairs.bootstrap_sites = {0x402002: "bootstrap-mmap", 0x402012: "bootstrap-munmap"}
    pairs.image_ranges = [(0x401000, 0x403000)]
    profile = pairs, []
    def event(body, ip):
        return f"[{ip:016x}] {body}\n"
    begin = event('write(2, "\\x50", 1) = 1', 0x401022)
    end = event('write(2, "\\x70", 1) = 1', 0x401022)
    mmap = 'mmap(NULL, 37, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000'
    munmap = 'munmap(0x7fff10000000, 37) = 0'
    valid = event(mmap, 0x7fff00001000) + event(mmap, 0x402002) + begin + end + event(munmap, 0x402012)
    inspect(valid, profile)
    mutations = [
        valid.replace(end, event(mmap, 0x401002) + end),
        valid.replace(end, event(munmap, 0x401012) + end),
        valid.replace(end, event(mmap, 0x401052) + end),
        valid.replace(end, event(mmap, 0x402012) + end),
        valid.replace(end, ""), valid + end, valid[:-1],
        valid.replace(begin, begin.replace(" = 1", " = 0")),
        valid.replace(begin, begin.replace("401022", "402052")),
    ]
    for altered in mutations:
        try:
            inspect(altered, profile)
        except (AssertionError, ValueError):
            continue
        raise AssertionError(("observer accepted corruption", altered))
    return 1 + len(mutations)


def main():
    count = controls()
    if sys.argv[1:] == ["controls"]:
        print(f"text-partition-noalloc-controls={count}")
        return
    assert len(sys.argv) == 2, sys.argv
    executable = Path(sys.argv[1]).resolve()
    profile = NATIVE.verified_sites(executable)
    with tempfile.TemporaryDirectory(prefix="text-partition-noalloc-") as directory:
        trace = Path(directory) / "trace"
        result = subprocess.run(
            ["strace", "-E", "LANIUS_ALLOC=mmap", "--kill-on-exit", "-qq", "-i", "-xx",
             "-e", "signal=none", "-e", "trace=mmap,munmap,write", "-o", str(trace), str(executable)],
            input=b"", capture_output=True, timeout=15)
        assert result.returncode == 0 and result.stdout == b"" and result.stderr == b"Pp", (result, trace.read_text())
        inspect(trace.read_text(), profile)
    print("text-partition-contracts layouts=2 source_allocations=0 source_releases=0")


if __name__ == "__main__":
    main()
