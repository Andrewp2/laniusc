#!/usr/bin/env python3
"""Find jumps that leave their function in Lanius x86_64 ELFs.

usage: tools/x86_jump_check.py ELF...

A correct function only jumps inside itself; a jump whose target lies in another
function is a miscompile even if the program happens to pass. One such bug: the
conditional jump into an `else` block whose arms all return pointed at another
function's `ret`, so the program skipped `leave` and returned to address 0.

The ELFs laniusc writes have one LOAD segment at 0x400000 with code from 0x400078
and no symbols, so this disassembles that segment linearly with objdump and takes
every `push %rbp; mov %rsp,%rbp` prologue as a function start. A jmp or jcc whose
target is outside [its function's start, the next function's start) is reported.
Calls are not checked. Data placed in the code segment can misalign the linear
disassembly, so treat a report as a lead and confirm it in gdb.

CPU only: it never runs the program.
"""

from __future__ import annotations

import bisect
import re
import subprocess
import sys

CODE_START = 0x400078
LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(\S+)\s*(.*)$")


def jumps_leaving_function(elf: str) -> list[dict]:
    """Every jmp/jcc whose target is outside its function, as {at, op, target, function}."""
    text = subprocess.run(
        ["objdump", "-D", "-b", "binary", "-m", "i386:x86-64", "--adjust-vma=0x400000",
         f"--start-address={CODE_START:#x}", elf],
        capture_output=True, text=True, check=True).stdout
    rows = []
    for line in text.splitlines():
        match = LINE.match(line)
        if match:
            rows.append((int(match.group(1), 16), match.group(2).strip(), match.group(3), match.group(4)))
    starts = [address for index, (address, code, _, _) in enumerate(rows)
              if code == "55" and index + 1 < len(rows) and rows[index + 1][1] == "48 89 e5"]
    found = []
    for address, _, mnemonic, operands in rows:
        target = re.match(r"0x([0-9a-f]+)", operands) if mnemonic.startswith("j") else None
        if not target:
            continue
        target = int(target.group(1), 16)
        index = bisect.bisect_right(starts, address) - 1
        if index < 0:
            continue
        end = starts[index + 1] if index + 1 < len(starts) else 1 << 64
        if not starts[index] <= target < end:
            found.append({"at": address, "op": mnemonic, "target": target, "function": starts[index]})
    return found


def describe(jump: dict) -> str:
    return f"{jump['op']} at {jump['at']:#x} -> {jump['target']:#x} (function at {jump['function']:#x})"


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    bad = 0
    for elf in sys.argv[1:]:
        jumps = jumps_leaving_function(elf)
        bad += bool(jumps)
        print(f"{len(jumps):4} jumps leave their function  {elf}"
              + "".join(f"\n       {describe(jump)}" for jump in jumps[:5]))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
