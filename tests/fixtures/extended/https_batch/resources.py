"""Source allocation/FD ownership inside a native-linked OpenSSL process.

Native loader/libc/OpenSSL mappings are deliberately outside this ledger. Exact
compiler runtime opcodes and source-function instruction boundaries identify
Lanius MAP_32BIT owners; address AND original requested size must balance.
"""
import ast
import functools
from collections import Counter
import importlib.util
from pathlib import Path
import re
import struct

SOURCE = Path(__file__).resolve().parents[2] / "stdlib_foundation" / "resolve" / "allocation_sites.py"
SPEC = importlib.util.spec_from_file_location("https_batch_source_allocation_sites", SOURCE)
SITES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SITES)
MAGIC = 1213415985
PATTERN = re.compile(r"^\[([0-9a-fA-F]+)\]\s+([a-z0-9_]+)\((.*)\)\s+=\s+(.+)$")


@functools.cache
def verified_sites(executable):
    return SITES.sites(executable)


def analyze(path, executable, *, epochs=True, injected_close=None):
    pairs, named = verified_sites(str(executable))
    alloc_sites = {a for a, _ in pairs} | set(named)
    free_sites = {f for _, f in pairs} | set(named)
    live, descriptors, attempts = {}, {}, {}
    allocations, epoch_allocations = [], []
    counters = Counter()
    epoch, markers, peak = False, [], 0
    for number, line in enumerate(Path(path).read_text().splitlines()):
        if not line or line.startswith(("+++", "---")):
            continue
        match = PATTERN.match(line)
        assert match, ("unsupported native trace line", line)
        address, name, arguments, result = match.groups()
        ip = int(address, 16)
        counters[name] += 1
        event = {"ip": ip, "args": arguments, "result": result, "line": line,
                 "line_number": number, "ordinal": counters[name], "epoch": epoch,
                 "injected": "INJECTED" in result}
        attempts.setdefault(name, []).append(event)
        if name == "write":
            marker = re.match(r'1, ("(?:\\.|[^"\\])*"), 16$', arguments)
            if marker and result == "16":
                data = ast.literal_eval("b" + marker[1])
                if len(data) == 16 and data[:4] == struct.pack("<i", MAGIC):
                    fields = struct.unpack("<4i", data)
                    assert fields in ((MAGIC, 100, 0, 0), (MAGIC, 101, 0, 0)), fields
                    markers.append(fields[1])
                    epoch = fields[1] == 100
        value = result.split()[0]
        if name == "mmap" and "MAP_32BIT" in arguments:
            assert ip in alloc_sites, ("unverified source allocation site", line)
            length = int(arguments.split(",", 2)[1])
            allocation = {**event, "length": length}
            allocations.append(allocation)
            if epoch:
                epoch_allocations.append(allocation)
            if value.startswith("0x"):
                pointer = int(value, 16)
                assert pointer not in live and pointer < 0x80000000, (line, live)
                live[pointer] = length
        elif name == "munmap":
            pointer, size = arguments.split(",", 1)
            pointer, size = int(pointer, 16), int(size)
            if pointer in live:
                assert ip in free_sites and value == "0" and live.pop(pointer) == size, (line, live)
            elif pointer < 0x80000000:
                # A low release outside the live set cannot be hidden as native
                # heap cleanup (the source bootstrap is a high anonymous map).
                raise AssertionError(("unowned low mapping release", line, live))
        elif name in ("socket", "open", "openat"):
            if int(value) >= 0:
                fd = int(value)
                assert fd not in descriptors, (line, descriptors)
                descriptors[fd] = name == "socket"
                peak = max(peak, sum(descriptors.values()))
        elif name == "close":
            fd = int(arguments)
            assert fd in descriptors, (line, descriptors)
            if value == "0":
                del descriptors[fd]
            else:
                # The direct abort regression repairs strace's skipped kernel
                # close explicitly, then must balance the SAME live fd.
                assert counters[name] == injected_close and event["injected"] and result.startswith("-1 EIO "), line
    assert markers == ([100, 101] if epochs else []) and not epoch, markers
    assert not live and not descriptors, (live, descriptors)
    return {"allocations": allocations, "epoch_allocations": epoch_allocations,
            "attempts": attempts, "calls": dict(counters), "max_sockets": peak}


def injected_at(ledger, syscall, ordinal, error):
    marked = [(name, event) for name, events in ledger["attempts"].items()
              for event in events if event["injected"]]
    assert len(marked) == 1, marked
    name, event = marked[0]
    assert name == syscall and event["ordinal"] == ordinal, marked
    assert re.match(r"^-1 " + error + r"(?:\s|$)", event["result"]), event
    return event


def prefix(before, after, syscall, ordinal):
    # Arguments include loader mapping addresses, peer ports and fd values.
    # For allocation identity the durable binding is site, length and flags.
    def shape(event):
        args = event["args"].split(",")
        # Native DSO instruction addresses change under ASLR between children;
        # retain exact ET_EXEC source IPs, native request size/protection/flags.
        source_ip = event["ip"] if "MAP_32BIT" in event["args"] else None
        return source_ip, int(args[1]), args[2].strip(), args[3].strip()
    assert [shape(e) for e in before["attempts"][syscall][:ordinal]] == [shape(e) for e in after["attempts"][syscall][:ordinal]], (syscall, ordinal)
