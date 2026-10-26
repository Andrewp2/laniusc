"""Strict syscall ownership ledger for syscall-only test ELFs (no libc loader).

The caller supplies a complete strace -qq [-i] trace. Failed close injection
skips the kernel operation, so it is deliberately excluded from this ledger.
This is test infrastructure, never an HTTP implementation.
"""
import os
import re
from collections import Counter


def analyze(trace):
    if isinstance(trace, os.PathLike) or (isinstance(trace, str) and "\n" not in trace and "(" not in trace):
        with open(trace, encoding="utf-8") as source:
            trace = source.read()
    mappings = {}
    descriptors = {}
    allocations = []
    attempts = {}
    calls = Counter()
    max_sockets = 0
    pattern = re.compile(r"^(?:\[([0-9a-fA-Fx]+)\]\s+)?([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$")
    for line in trace.splitlines():
        if line.startswith(("+++", "---")) or not line:
            continue
        match = pattern.match(line)
        assert match, ("unparsed syscall", line)
        ip, name, arguments, result = match.groups()
        calls[name] += 1
        event = {"ip": int(ip, 16) if ip else None, "args": arguments,
                 "result": result, "ordinal": calls[name], "line": line,
                 "injected": "INJECTED" in result}
        attempts.setdefault(name, []).append(event)
        value = result.split()[0]
        if name == "mmap":
            if value.startswith("0x"):
                length = int(arguments.split(",", 2)[1])
                address = int(value, 16)
                assert address not in mappings, (line, mappings)
                mappings[address] = length
                allocations.append({**event, "length": length, "address": address})
        elif name == "munmap":
            address, length = arguments.split(",", 1)
            address, length = int(address, 16), int(length.strip())
            assert value == "0" and mappings.pop(address, None) == length, (line, mappings)
        elif name in ("socket", "open", "openat", "dup", "dup2", "dup3", "fcntl"):
            # No test uses fcntl except descriptor duplication. Reject accidental
            # expansion rather than interpreting arbitrary fcntl results as fds.
            if name == "fcntl":
                assert "F_DUPFD" in arguments, line
            if int(value) >= 0:
                fd = int(value)
                assert fd not in descriptors, (line, descriptors)
                descriptors[fd] = name == "socket"
                max_sockets = max(max_sockets, sum(descriptors.values()))
        elif name == "close":
            fd = int(arguments)
            assert value == "0" and fd in descriptors, (line, descriptors)
            del descriptors[fd]
    assert not mappings and not descriptors, (mappings, descriptors, trace)
    return {"allocations": allocations, "calls": dict(calls), "attempts": attempts,
            "max_sockets": max_sockets}
