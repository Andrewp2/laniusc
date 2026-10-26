"""Accepted socket generations and verified requested-source-memory accounting.

Native loader/libc/OpenSSL mappings are outside this source ledger. Source
sites use the existing executable-byte/instruction-boundary verifier unchanged.
"""
from pathlib import Path
import re
import struct
import subprocess

from oracle import FIXTURES, helper
from trace_events import Accepted, LINE

RESOURCES = helper("server_scale_verified_resources", FIXTURES / "https_batch/resources.py")


def raw_runtime_pairs(image):
    """Current sectionless compiler output: admit only exact runtime helpers."""
    assert len(image) >= 64 and image[:7] == b"\x7fELF\x02\x01\x01"
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", image)
    assert header[1:4] == (2, 62, 1) and header[8] == 64
    assert header[6] == 0 and header[11:14] == (0, 0, 0), "expected sectionless ELF"
    phoff, phsize, phcount = header[5], header[9], header[10]
    assert phsize == 56 and 0 < phcount < 1024
    assert phoff <= len(image) and phsize * phcount <= len(image) - phoff
    pairs, entry = set(), False
    for index in range(phcount):
        kind, flags, offset, address, _, size, memory, _ = struct.unpack_from(
            "<IIQQQQQQ", image, phoff + index * phsize)
        assert offset <= len(image) and size <= len(image) - offset and size <= memory
        if kind != 1 or not flags & 1:
            continue
        assert address + size < 1 << 64
        entry |= address <= header[4] < address + size
        code = image[offset:offset + size]
        at = code.find(RESOURCES.SITES.RUNTIME)
        while at >= 0:
            pairs.add(tuple(address + at + position + 2 for position in RESOURCES.SITES.SYSCALLS))
            at = code.find(RESOURCES.SITES.RUNTIME, at + 1)
    assert entry and pairs, "missing executable entry or exact allocation runtime"
    return sorted(pairs)


def verified_sites(executable, directory):
    image = Path(executable).read_bytes()
    assert len(image) >= 64
    header = struct.unpack_from("<16sHHIQQQIHHHHHH", image)
    if header[6] != 0:
        # Native-linked OpenSSL output retains the existing stronger named-site
        # verifier unchanged. A rejection here never falls back to raw scanning.
        return RESOURCES.verified_sites(str(executable))
    pairs = raw_runtime_pairs(image)
    # Sectionless files cannot use objdump -d's section/symbol walk. Decode the
    # exact known helper from its entry, retaining syscall instruction checks.
    runtime = Path(directory) / "verified-source-runtime.bin"
    runtime.write_bytes(RESOURCES.SITES.RUNTIME)
    result = subprocess.run(["objdump", "-D", "-b", "binary", "-m", "i386:x86-64",
                             "--no-show-raw-insn", str(runtime)],
                            capture_output=True, text=True, check=True, timeout=10)
    instructions = {}
    for line in result.stdout.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+(\S+)", line)
        if match:
            instructions[int(match[1], 16)] = match[2]
    assert all(instructions.get(offset) == "syscall" for offset in RESOURCES.SITES.SYSCALLS)
    return pairs, []


class Ledger:
    def __init__(self, path, pairs, named):
        self.path = Path(path)
        self.alloc_sites = {a for a, _ in pairs} | set(named)
        self.free_sites = {f for _, f in pairs} | set(named)
        assert self.alloc_sites and self.free_sites
        self.offset, self.partial, self.index = 0, b"", 0
        self.live, self.bytes, self.peak_bytes, self.allocations = {}, 0, 0, 0
        self.sockets, self.files, self.active, self.generations = {}, {}, {}, {}
        self.accepted, self.listener = [], None
        self.peak_active, self.peak_sockets, self.polls = 0, 0, 0

    def refresh(self):
        if not self.path.exists():
            return
        with self.path.open("rb") as source:
            source.seek(self.offset)
            block = source.read()
            self.offset += len(block)
        self.consume(block)

    def consume(self, block):
        lines = (self.partial + block).split(b"\n")
        self.partial = lines.pop()
        for raw in lines:
            line = raw.decode("ascii")
            if not line or line.startswith(("+++", "---")):
                continue
            match = LINE.fullmatch(line)
            assert match, ("unsupported scale trace", line)
            address, name, args, result = match.groups()
            ip, value = int(address, 16), result.split()[0]
            self.index += 1
            if name == "mmap" and "MAP_32BIT" in args:
                assert ip in self.alloc_sites and "PROT_READ|PROT_WRITE" in args, line
                size = int(args.split(",", 2)[1])
                assert size > 0 and value.startswith("0x"), ("failed source allocation", line)
                pointer = int(value, 16)
                assert pointer < 0x80000000 and pointer not in self.live, line
                self.live[pointer] = size
                self.bytes += size
                self.peak_bytes = max(self.peak_bytes, self.bytes)
                self.allocations += 1
            elif name == "munmap":
                pointer, size = args.split(",", 1)
                pointer, size = int(pointer, 16), int(size)
                if pointer in self.live:
                    assert ip in self.free_sites and value == "0", line
                    assert self.live.pop(pointer) == size, ("changed requested release size", line)
                    self.bytes -= size
                elif pointer < 0x80000000:
                    raise AssertionError(("unowned low source release", line))
            elif name in ("socket", "open", "openat") and value.isdecimal():
                fd = int(value)
                assert fd not in self.sockets and fd not in self.files, line
                (self.sockets if name == "socket" else self.files)[fd] = name
            elif name == "listen" and value == "0":
                fd = int(args.split(",", 1)[0])
                assert fd in self.sockets and self.listener is None, line
                self.listener = fd
            elif name == "accept4" and value.isdecimal():
                assert int(args.split(",", 1)[0]) == self.listener, line
                port = re.search(r"sin6?_port=htons\(([0-9]+)\)", args)
                assert port, ("missing accepted source port", line)
                fd = int(value)
                assert fd not in self.sockets and fd not in self.files, line
                generation = self.generations.get(fd, 0) + 1
                self.generations[fd] = generation
                record = Accepted(len(self.accepted), fd, generation, int(port[1]), self.index)
                self.accepted.append(record)
                self.active[fd] = record
                self.sockets[fd] = "accepted"
            elif name == "close":
                fd = int(args)
                assert value == "0", ("failed explicit close", line)
                if fd in self.sockets:
                    del self.sockets[fd]
                    if fd in self.active:
                        self.active.pop(fd).closed = self.index
                elif fd in self.files:
                    del self.files[fd]
                else:
                    assert fd in (0, 1, 2), ("unowned close", line)
            elif name == "poll":
                self.polls += 1
            self.peak_active = max(self.peak_active, len(self.active))
            self.peak_sockets = max(self.peak_sockets, len(self.sockets))
            assert len(self.active) <= 4 and len(self.sockets) <= 5, (
                "scale accepted/socket cap", self.active, self.sockets, line)

    def finish(self, count):
        self.refresh()
        assert not self.partial and not self.live and self.bytes == 0, (
            self.partial, self.live, self.bytes)
        assert not self.active and not self.sockets and not self.files, (
            self.active, self.sockets, self.files)
        assert len(self.accepted) == count and all(r.closed is not None for r in self.accepted)
        assert self.peak_active == 4 and self.peak_sockets == 5 and self.polls > 0
        assert self.allocations > 0 and self.peak_bytes > 0
        return dict(accepted=count, active=self.peak_active, sockets=self.peak_sockets,
                    source_allocations=self.allocations, source_peak_requested=self.peak_bytes)
