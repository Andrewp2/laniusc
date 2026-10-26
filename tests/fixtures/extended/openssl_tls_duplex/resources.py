"""Source-owned mmap ledger for a linked libc/OpenSSL executable.

Only exact emitted allocator/deallocator instruction sites are owners here.
Loader, CRT bootstrap, libc and OpenSSL mappings are deliberately separate.
"""
import importlib.util
from pathlib import Path
import re

PATH = Path(__file__).resolve().parents[2] / "stdlib_foundation" / "resolve" / "allocation_sites.py"
SPEC = importlib.util.spec_from_file_location("duplex_allocation_sites", PATH)
SITES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SITES)


def parse(trace, pairs):
    allocations = {allocation for allocation, _ in pairs}
    releases = {release for _, release in pairs}
    assert allocations and releases
    live, requests, ordinal, active, completed = {}, [], 0, False, False
    for original in trace.splitlines():
        match = re.fullmatch(r"\[([0-9a-f]+)\] (.*)", original)
        assert match, original
        instruction, line = int(match[1], 16), match[2]
        if line.startswith('write(2, "A\\n", 2)'):
            assert not active and not completed
            active = True
        elif line.startswith('write(2, "B\\n", 2)'):
            assert active and not any(owned for _, owned in live.values()), (live, original)
            active, completed = False, True
        if line.startswith("mmap("):
            ordinal += 1
            if instruction not in allocations:
                assert "MAP_32BIT" not in line, original
                continue
            assert "MAP_32BIT" in line and "PROT_READ|PROT_WRITE" in line, original
            length = int(line.split(",", 2)[1])
            result = line.rsplit(" = ", 1)[1]
            address = result.split()[0]
            if address.startswith("0x"):
                assert address not in live
                live[address] = (length, active)
            else:
                assert result.startswith("-1 ENOMEM "), original
            requests.append(dict(ordinal=ordinal, ip=instruction, length=length,
                                 address=address, active=active,
                                 injected="(INJECTED)" in result, result=result))
        elif line.startswith("munmap("):
            address, size = line[7:].split(")", 1)[0].split(",")
            if address in live:
                assert instruction in releases and line.endswith(" = 0"), original
                assert live.pop(address)[0] == int(size), original
            elif instruction in releases and int(address, 16) < 0x80000000:
                raise AssertionError(("unowned/repeated source release", original))
    assert not active and not live and completed, (live, active, completed)
    return requests


def analyze(executable, trace):
    pairs, _ = SITES.sites(executable)
    return parse(trace, pairs)


def controls():
    """Mutation checks exercise this exact ledger without product execution."""
    a, f, native = 0x401002, 0x401012, 0x7fff00001000
    def event(ip, text):
        return f"[{ip:016x}] {text}\n"
    start, end = event(a, 'write(2, "A\\n", 2) = 2'), event(a, 'write(2, "B\\n", 2) = 2')
    alloc = event(a, "mmap(NULL, 32, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = 0x40001000")
    free = event(f, "munmap(0x40001000, 32) = 0")
    high = event(native, "mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff10000000") + event(native, "munmap(0x7fff10000000, 8192) = 0")
    assert len(parse(start + alloc + free + end, [(a, f)])) == 1
    assert parse(start + high + end, [(a, f)]) == []
    mutations = [start + alloc + end, start + free + end,
                 start + alloc + free + free + end,
                 start + alloc + free.replace(", 32)", ", 16)") + end,
                 start + alloc + free.replace(" = 0", " = -1 EIO (Input/output error)") + end,
                 start + alloc.replace(f"{a:016x}", f"{native:016x}") + free + end,
                 start + alloc + free.replace(f"{f:016x}", f"{native:016x}") + end]
    for mutation in mutations:
        try:
            parse(mutation, [(a, f)])
        except AssertionError:
            continue
        raise AssertionError(("ledger accepted mutant", mutation))
    return 2 + len(mutations)


if __name__ == "__main__":
    print(f"openssl-tls-duplex source-ledger CPU controls={controls()}")
