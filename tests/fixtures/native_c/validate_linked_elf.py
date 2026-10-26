#!/usr/bin/env python3
"""Check the system-linked ELF profile and branches in sized Lanius symbols.

CRT and PLT functions legitimately tail jump across symbol boundaries. Lanius
functions retain their own sizes in .symtab, so apply the compiler's stricter
local branch contract to those symbols and the generated main bridge only.
"""

from bisect import bisect_left
import re
import struct
import subprocess
import sys
from pathlib import Path


def check(condition, message):
    if not condition:
        raise ValueError(message)


def validate_function_instructions(functions, instructions, executable_range):
    """Check every covered instruction, without scanning unrelated functions."""
    addresses = sorted(instructions)
    branches = 0
    for name, start, size in functions:
        check(size > 0 and executable_range(start, size), f"{name}: invalid executable symbol range")
        check(start in instructions, f"{name}: entry is not an instruction boundary")
        # Each overlapping symbol range retains its own validation. A single
        # instruction-to-owner map would silently drop checks for aliases.
        first = bisect_left(addresses, start)
        last = bisect_left(addresses, start + size, lo=first)
        for index in range(first, last):
            address = addresses[index]
            mnemonic, arguments = instructions[address]
            check(mnemonic != "(bad)" and not mnemonic.startswith("."),
                  f"{name}: invalid instruction at {address:#x}")
            is_branch = mnemonic.startswith("j") or mnemonic.startswith("loop")
            is_call = mnemonic in {"call", "callq"}
            if not (is_branch or is_call) or not arguments:
                continue
            target = arguments[0]
            if target.startswith("*"):  # GOT/PLT and indirect runtime calls.
                continue
            check(re.fullmatch(r"[0-9a-f]+", target), f"{name}: unrecognized direct branch target {target}")
            target = int(target, 16)
            check(target in instructions, f"{name}: target {target:#x} is not an instruction boundary")
            if is_branch:
                branches += 1
                check(start < target < start + size,
                      f"{name}: jump at {address:#x} leaves its function for {target:#x}")
            else:
                check(executable_range(target), f"{name}: call target is outside executable PT_LOAD")
    return branches


def validate(path):
    image = Path(path).read_bytes()

    def unpack(format_, offset):
        size = struct.calcsize(format_)
        check(0 <= offset <= len(image) - size, "ELF record lies outside the file")
        return struct.unpack_from(format_, image, offset)

    def region(offset, size):
        check(0 <= offset <= len(image) and 0 <= size <= len(image) - offset,
              "ELF region lies outside the file")
        return image[offset:offset + size]

    def cstring(table, offset):
        check(0 <= offset < len(table), "ELF string offset lies outside its table")
        end = table.find(b"\0", offset)
        check(end >= 0, "ELF string is unterminated")
        return table[offset:end].decode("utf-8")

    check(image[:7] == b"\x7fELF\x02\x01\x01", "expected little-endian ELF64")
    header = unpack("<16sHHIQQQIHHHHHH", 0)
    (_, kind, machine, version, entry, phoff, shoff, _, ehsize,
     phsize, phcount, shsize, shcount, _) = header
    check((kind, machine, version, ehsize) == (2, 62, 1, 64),
          "expected an ET_EXEC x86-64 executable")
    check(phsize == 56 and 0 < phcount < 1024, "invalid ELF program header table")
    segments = [unpack("<IIQQQQQQ", phoff + index * phsize) for index in range(phcount)]
    loads = [segment for segment in segments if segment[0] == 1]
    check(loads, "missing PT_LOAD")
    for _, flags, offset, _, _, filesz, memsz, _ in loads:
        region(offset, filesz)
        check(filesz <= memsz, "PT_LOAD file size exceeds memory size")
        check(flags & 3 != 3, "PT_LOAD is both writable and executable")

    def executable_range(address, size=1):
        return any(flags & 1 and address >= vaddr and size <= filesz
                   and address - vaddr <= filesz - size
                   for _, flags, _, vaddr, _, filesz, _, _ in loads)

    check(executable_range(entry), "ELF entry point is outside executable PT_LOAD")
    interpreters = [segment for segment in segments if segment[0] == 3]
    check(len(interpreters) == 1, "expected one CRT dynamic interpreter")
    interpreter = region(interpreters[0][2], interpreters[0][5])
    check(interpreter.startswith(b"/") and interpreter.endswith(b"\0"), "invalid PT_INTERP")
    check(any(segment[0] == 2 for segment in segments), "missing PT_DYNAMIC")

    check(shsize == 64 and 0 < shcount < 65536, "invalid ELF section header table")
    sections = [unpack("<IIQQQQIIQQ", shoff + index * shsize) for index in range(shcount)]
    symbols = []
    for section in sections:
        _, kind, _, _, offset, size, link, _, _, stride = section
        if kind != 2:  # SHT_SYMTAB, retaining the compiler's function sizes.
            continue
        check(stride == 24 and size % stride == 0, "invalid ELF symbol table")
        check(link < len(sections), "invalid symbol string-table link")
        strings = region(sections[link][4], sections[link][5])
        for index in range(size // stride):
            name, info, _, section_index, address, length = unpack("<IBBHQQ", offset + index * stride)
            name = cstring(strings, name)
            if info & 15 == 2 and section_index != 0:
                symbols.append((name, address, length))
    functions = [(name, address, size) for name, address, size in symbols
                 if re.fullmatch(r"__lanius_\d+_\d+_\d+", name) or name == "main"]
    check(any(name.startswith("__lanius_") for name, _, _ in functions),
          "missing sized Lanius function symbols")
    check(sum(name == "main" for name, _, _ in functions) == 1, "missing unique CRT main bridge")

    result = subprocess.run(["objdump", "-d", "--no-show-raw-insn", str(path)],
                            capture_output=True, text=True, timeout=20, check=True)
    instructions = {}
    prefixes = {"addr32", "bnd", "cs", "data16", "ds", "es", "fs", "gs",
                "lock", "notrack", "rep", "repe", "repne", "repnz", "repz", "ss"}
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+(\S.*)$", line)
        if not match:
            continue
        address = int(match[1], 16)
        tokens = match[2].split()
        while tokens and (tokens[0] in prefixes or tokens[0].startswith("rex")):
            tokens.pop(0)
        check(tokens, "instruction has no mnemonic")
        instructions[address] = (tokens[0], tokens[1:])

    branches = validate_function_instructions(functions, instructions, executable_range)
    return len(functions), branches


if __name__ == "__main__":
    try:
        functions, branches = validate(sys.argv[1])
        print(f"checked {functions} Lanius/bridge functions and {branches} local branches")
    except (ValueError, OSError, UnicodeError, struct.error, subprocess.SubprocessError) as error:
        print(f"linked ELF validation failed: {error}", file=sys.stderr)
        sys.exit(1)
