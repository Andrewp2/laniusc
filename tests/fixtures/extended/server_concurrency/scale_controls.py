"""Pure CPU scale-ledger mutations; no executable or network is started."""
from pathlib import Path
import struct

from scale_ledger import Ledger, RESOURCES, raw_runtime_pairs

A, F, NATIVE = 0x401002, 0x401012, 0x7fff12340000


def event(text, ip=A):
    return f"[{ip:016x}] {text}\n"


def allocate(pointer, size, ip=A):
    return event(f"mmap(NULL, {size}, PROT_READ|PROT_WRITE, "
                 f"MAP_PRIVATE|MAP_ANONYMOUS|MAP_32BIT, -1, 0) = {pointer}", ip)


def release(pointer, size, ip=F):
    return event(f"munmap({pointer}, {size}) = 0", ip)


def accepted(fd, port):
    return event(f"accept4(3, {{sa_family=AF_INET, sin_port=htons({port}), "
                 f'sin_addr=inet_addr("127.0.0.1")}}, [128 => 16], '
                 f"SOCK_NONBLOCK|SOCK_CLOEXEC) = {fd}")


def parse(text):
    ledger = Ledger(Path("/nonexistent/server-scale-cpu.trace"), [(A, F)], [])
    ledger.consume(text.encode())
    result = ledger.finish(5)
    return ledger, result


def denied(text):
    try:
        parse(text)
    except AssertionError:
        return
    raise AssertionError("scale ledger accepted corrupted ownership trace")


def main():
    count = 0
    a, b, c = allocate("0x40001000", 97), allocate("0x40002000", 31), allocate("0x40001000", 17)
    fa, fb, fc = release("0x40001000", 97), release("0x40002000", 31), release("0x40001000", 17)
    start = event('openat(AT_FDCWD, "native.pem", O_RDONLY) = 9')
    start += event("socket(AF_INET, SOCK_STREAM|SOCK_NONBLOCK, IPPROTO_TCP) = 3")
    start += event("listen(3, 16) = 0")
    start += "".join(accepted(fd, 10000 + fd) for fd in range(4, 8))
    recycled = event("close(4) = 0") + accepted(4, 10008)
    end = event("poll([], 0, 0) = 0 (Timeout)")
    end += "".join(event(f"close({fd}) = 0") for fd in range(4, 8))
    end += event("close(3) = 0") + event("close(9) = 0")
    valid = start + a + b + fa + c + recycled + fb + fc + end
    ledger, observed = parse(valid)
    assert observed == dict(accepted=5, active=4, sockets=5,
                            source_allocations=3, source_peak_requested=128)
    assert ledger.accepted[-1].fd == ledger.accepted[0].fd
    assert (ledger.accepted[0].generation, ledger.accepted[-1].generation) == (1, 2)
    count += 1
    native = event("mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7fff20000000", NATIVE)
    native += event("munmap(0x7fff20000000, 8192) = 0", NATIVE)
    assert parse(native + valid)[1] == observed
    count += 1
    # Exact requested lengths, rather than page-rounded or cumulative bytes,
    # determine the simultaneously-live source peak; native maps cannot add it.
    mutations = [valid.replace(a, allocate("0x40001000", 97, NATIVE)),
                 valid.replace(fa, release("0x40001000", 97, NATIVE)),
                 valid.replace(fa, release("0x40001000", 96)),
                 valid.replace(fc, ""), valid + fc,
                 valid.replace(b, allocate("0x40001000", 31)),
                 valid + release("0x40008000", 5),
                 valid.replace(a, a.replace("0x40001000", "-1 ENOMEM (Cannot allocate memory)")),
                 valid.replace(recycled, accepted(8, 10009) + recycled),
                 valid.replace(event("close(7) = 0"), ""),
                 valid + event("close(7) = 0"),
                 valid.replace(event("close(7) = 0"), event("close(7) = -1 EIO (Input/output error)")),
                 valid.replace(accepted(5, 10005), accepted(9, 10005)),
                 valid.replace("accept4(3,", "accept4(8,"),
                 valid.replace("sin_port=htons(10005)", "sin_port=0"),
                 valid.rstrip("\n")]
    for mutation in mutations:
        denied(mutation)
        count += 1
    # Fragmented reads must carry an incomplete syscall line to the next block.
    fragmented = Ledger(Path("/nonexistent/server-scale-cpu.trace"), [(A, F)], [])
    data = valid.encode()
    for offset in range(0, len(data), 37):
        fragmented.consume(data[offset:offset + 37])
    assert fragmented.finish(5) == observed
    count += 1

    # The current plain output has no section table. Only executable-LOAD
    # runtime bytes, not arbitrary low mappings or a failed linked verifier,
    # establish its admitted allocation/free post-syscall addresses.
    runtime = RESOURCES.SITES.RUNTIME
    size = 120 + len(runtime)
    header = struct.pack("<16sHHIQQQIHHHHHH", b"\x7fELF\x02\x01\x01" + bytes(9),
                         2, 62, 1, 0x400078, 64, 0, 0, 64, 56, 1, 0, 0, 0)
    program = struct.pack("<IIQQQQQQ", 1, 5, 0, 0x400000, 0x400000, size, size, 4096)
    image = header + program + runtime
    expected = tuple(0x400078 + offset + 2 for offset in RESOURCES.SITES.SYSCALLS)
    assert raw_runtime_pairs(image) == [expected]
    count += 1
    current = runtime.replace(bytes.fromhex("41ba62000000"), bytes.fromhex("41ba22000000"))
    current_image = header + program + current
    current_pairs = raw_runtime_pairs(current_image)
    assert current_pairs == [expected] and current_pairs.mmap_flags == {expected[0]: 0x22}
    assert raw_runtime_pairs(image).mmap_flags == {expected[0]: 0x62}
    count += 1
    both_size = 120 + len(runtime) + len(current)
    both_program = struct.pack("<IIQQQQQQ", 1, 5, 0, 0x400000, 0x400000, both_size, both_size, 4096)
    both_pairs = raw_runtime_pairs(header + both_program + runtime + current)
    assert both_pairs.mmap_flags == {expected[0]: 0x62, expected[0] + len(runtime): 0x22}
    count += 1
    for unsupported in (current_pairs, both_pairs):
        try:
            Ledger(Path("/nonexistent/unsupported-full-width.trace"), unsupported, [])
        except AssertionError:
            count += 1
        else:
            raise AssertionError("historical scale ledger silently accepted a full-width source profile")

    def changed(offset, replacement):
        return image[:offset] + replacement + image[offset + len(replacement):]
    invalid = [changed(0, b"NOPE"), changed(4, b"\x01"),
               changed(40, struct.pack("<Q", 120)),
               changed(32, struct.pack("<Q", len(image) + 1)),
               changed(68, struct.pack("<I", 4)), changed(24, bytes(8)),
               changed(len(image) - 1, b"\x00"),
               header + program + current.replace(bytes.fromhex("41ba22000000"), bytes.fromhex("41ba42000000")),
               header + program + current.replace(bytes.fromhex("b80b0000000f05c3"), bytes.fromhex("b80a0000000f05c3")),
               header + program + current.replace(bytes.fromhex("4885c0790231c0c3"), bytes.fromhex("4885c0780231c0c3"))]
    for mutant in invalid:
        try:
            raw_runtime_pairs(mutant)
        except AssertionError:
            count += 1
            continue
        raise AssertionError("sectionless runtime verifier accepted malformed ELF/runtime")
    print(f"server-scale ledger controls={count} native-cases=0")


if __name__ == "__main__":
    main()
