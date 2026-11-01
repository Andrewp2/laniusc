"""zlib.crc32 oracle for ext::compression.crc32_update.

usage: python3 -I oracle.py PROBE

PROBE is crc32_probe.lani compiled with lcc. Seeded random buffers are
checksummed over odd offsets and lengths (0 to 2 MiB, across the 512-byte
slicing threshold) and fed in pieces from 1 byte to 1 MiB. Prints the case
count and exits nonzero on any disagreement.
"""
import random, subprocess, sys, zlib

PROBE = sys.argv[1]
rng = random.Random(20261101)
cases = failures = 0
for round_ in range(40):
    size = rng.choice([64, 1000, 4096, 70000, 1 << 20, (2 << 20) + 13])
    data = rng.randbytes(size) if round_ % 4 else bytes(rng.choice([0, 255]) for _ in range(size))
    pairs = []
    for _ in range(60):
        length = rng.choice([0, 1, 7, 8, 9, 511, 512, 513, 2047, 2048, 4095, rng.randrange(0, size + 1)])
        length = min(length, size)
        offset = rng.randrange(0, size - length + 1)
        pairs.append((offset, length))
    split = rng.choice([1, 3, 8, 511, 512, 4096, 65536, 1 << 20])
    argv = [PROBE, str(split)] + [str(v) for pair in pairs for v in pair]
    out = subprocess.run(argv, input=data, capture_output=True, timeout=60)
    lines = out.stdout.decode().split()
    for (offset, length), line in zip(pairs, lines):
        cases += 1
        want = "%08x" % zlib.crc32(data[offset:offset + length])
        if line != want:
            failures += 1
            if failures < 10:
                print(f"FAIL size {size} split {split} [{offset}:+{length}] {line} != {want}", file=sys.stderr)
    if out.returncode != 0 or len(lines) != len(pairs):
        failures += 1
        print(f"FAIL rc={out.returncode} lines={len(lines)}", file=sys.stderr)
print(f"{cases} CRC-32 cases agree with zlib.crc32; {failures} failures")
sys.exit(1 if failures else 0)
