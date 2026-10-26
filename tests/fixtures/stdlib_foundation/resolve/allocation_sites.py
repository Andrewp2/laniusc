"""Recognize the emitted Linux allocation runtime, including unsized thunks.

The native linker retains sized source functions, but the compiler's per-unit
runtime helpers can lie outside those symbols. This helper validates exact
runtime instruction bytes inside executable ELF LOADs, plus objdump instruction
boundaries. It never classifies libc or the separate bootstrap mapping.
"""
import re
import struct
import subprocess
import sys
from pathlib import Path

# size=RDI -> RSI; addr=0; prot=3; flags=0x62 (PRIVATE|ANON|32BIT);
# fd=-1; offset=0; syscall9; failure maps to NULL. Adjacent deallocator is
# syscall11 with its original address/length arguments. Both helpers return.
RUNTIME = bytes.fromhex(
    "4889fe31ffba0300000041ba6200000041b8ffffffff4531c9"
    "b8090000000f054885c0790231c0c3b80b0000000f05c3"
)
SYSCALLS = [index for index in range(len(RUNTIME) - 1) if RUNTIME[index:index + 2] == b"\x0f\x05"]
assert len(SYSCALLS) == 2


def sites(path):
    image = Path(path).read_bytes()
    assert image[:7] == b"\x7fELF\x02\x01\x01", "expected LE ELF64"
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", image)
    assert header[1:4] == (2, 62, 1), "expected ET_EXEC/x86_64"
    phoff, phsize, phcount = header[5], header[9], header[10]
    assert phsize == 56 and 0 < phcount < 1024
    pairs = set()
    for index in range(phcount):
        kind, flags, offset, address, _, size, memory, _ = struct.unpack_from("<IIQQQQQQ", image, phoff + index * phsize)
        assert offset <= len(image) and size <= len(image) - offset and size <= memory
        if kind != 1 or not flags & 1:
            continue
        code = image[offset:offset + size]
        at = code.find(RUNTIME)
        while at >= 0:
            pairs.add(tuple(address + at + position for position in SYSCALLS))
            at = code.find(RUNTIME, at + 1)
    assert pairs, "unsupported emitted allocation runtime: no verified syscall9/11 pair"
    disassembly = subprocess.run(
        ["objdump", "-d", "--no-show-raw-insn", str(path)],
        capture_output=True, text=True, check=True, timeout=20,
    ).stdout
    instructions = {}
    for line in disassembly.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+(\S+)", line)
        if match:
            instructions[int(match[1], 16)] = match[2]
    for allocation, release in pairs:
        assert instructions.get(allocation) == "syscall", f"not an mmap instruction boundary: {allocation:#x}"
        assert instructions.get(release) == "syscall", f"not a munmap instruction boundary: {release:#x}"
    symbols = subprocess.run(["nm", "-S", "--defined-only", str(path)], capture_output=True, text=True, check=True, timeout=20).stdout
    ranges = []
    for line in symbols.splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2] in ("T", "t") and re.fullmatch(r"(?:__lanius_\d+_\d+_\d+|main)", fields[3]):
            start, size = int(fields[0], 16), int(fields[1], 16)
            assert size > 0
            ranges.append((start, start + size))
    assert ranges, "missing sized source functions"
    named = {address + 2 for address, instruction in instructions.items()
             if instruction == "syscall" and any(start <= address < end for start, end in ranges)}
    # strace -i reports the instruction pointer following the two-byte syscall.
    return sorted((allocation + 2, release + 2) for allocation, release in pairs), sorted(named)


if __name__ == "__main__":
    pairs, named = sites(sys.argv[1])
    for allocation, release in pairs:
        print(f"A {allocation:x}")
        print(f"F {release:x}")
    for syscall in named:
        print(f"S {syscall:x}")
