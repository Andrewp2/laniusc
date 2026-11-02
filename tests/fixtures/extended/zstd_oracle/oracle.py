"""/usr/bin/zstd oracle for ext::zstd (sample_programs/library/unzstd.lani
and zstd_probe.lani), ext::zstd_encode (sample_programs/library/zstd.lani and
zstd_encode_probe.lani) and ext::xxhash (xxh64_probe.lani).

usage: python3 -I oracle.py UNZSTD XXH64_PROBE ZSTD_PROBE WORKDIR [--quick] [--only=GROUP]...
          [--zstd=ZSTD_TOOL --encode-probe=ENCODE_PROBE]

The encoder groups run when both encoder programs are given: frames from
levels 1-3 must pass `zstd -t`, decode exactly under /usr/bin/zstd and the
sample decoder, and be identical under every input/output step size; the
sizes against `zstd -1` and `zstd -3` on fixed corpora are printed.

Frames written by /usr/bin/zstd at levels 1-19 (and --ultra 20-22), with
and without checksums and content sizes, piped (no content size), with
advanced parameters (window logs 10-23, every strategy, forced literal
modes, small target blocks), --long=27 with matches beyond the default
window, multi-frame files with empty and skippable frames, are decoded by
the sample and compared byte for byte. The probe replays frames through
the streaming API with 1-byte to 64 KiB input and output steps. Dictionary frames, oversized windows
and trailing garbage must be refused (exit 2). Fuzzing truncates and flips
bits in compressed files: the sample must exit 0 or 2, never a signal or a
hang, and must match zstd's output whenever both accept. XXH64 is checked
against a Python reference (itself checked against zstd frame trailers).
Every case is seeded. Prints one count line per group and exits nonzero on
any disagreement.
"""
import os, random, struct, subprocess, sys

UNZSTD, PROBE, STEPPER, WORK = (os.path.abspath(a) for a in sys.argv[1:5])
def option(name):
    for a in sys.argv:
        if a.startswith(name + "="):
            return os.path.abspath(a[len(name) + 1:])
    return None
ENCODER, ENCODE_PROBE = option("--zstd"), option("--encode-probe")
QUICK = "--quick" in sys.argv
ZSTD = "/usr/bin/zstd"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
os.makedirs(WORK, exist_ok=True)
counts = {}
failures = []
rng = random.Random(20261101)


def bump(key, n=1):
    counts[key] = counts.get(key, 0) + n


def fail(msg):
    failures.append(msg)
    if len(failures) < 20:
        print("FAIL", msg, file=sys.stderr)


def run(argv, data=b"", timeout=60):
    try:
        p = subprocess.run(argv, input=data, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return -999, b"", b"timeout"
    return p.returncode, p.stdout, p.stderr


M = (1 << 64) - 1
P1, P2, P3, P4, P5 = 0x9E3779B185EBCA87, 0xC2B2AE3D27D4EB4F, 0x165667B19E3779F9, 0x85EBCA77C2B2AE63, 0x27D4EB2F165667C5


def rotl(x, r):
    return ((x << r) | (x >> (64 - r))) & M


def rnd(a, lane):
    return (rotl((a + lane * P2) & M, 31) * P1) & M


def xxh64(d, seed=0):
    n, i = len(d), 0
    if n >= 32:
        v = [(seed + P1 + P2) & M, (seed + P2) & M, seed, (seed - P1) & M]
        while i + 32 <= n:
            for k in range(4):
                v[k] = rnd(v[k], int.from_bytes(d[i + 8 * k:i + 8 * k + 8], "little"))
            i += 32
        h = (rotl(v[0], 1) + rotl(v[1], 7) + rotl(v[2], 12) + rotl(v[3], 18)) & M
        for lane in v:
            h = ((h ^ rnd(0, lane)) * P1 + P4) & M
    else:
        h = (seed + P5) & M
    h = (h + n) & M
    while i + 8 <= n:
        h ^= rnd(0, int.from_bytes(d[i:i + 8], "little"))
        h = (rotl(h, 27) * P1 + P4) & M
        i += 8
    if i + 4 <= n:
        h ^= (int.from_bytes(d[i:i + 4], "little") * P1) & M
        h = (rotl(h, 23) * P2 + P3) & M
        i += 4
    while i < n:
        h ^= (d[i] * P5) & M
        h = (rotl(h, 11) * P1) & M
        i += 1
    h ^= h >> 33
    h = (h * P2) & M
    h ^= h >> 29
    h = (h * P3) & M
    return h ^ (h >> 32)


TEXT = b""
for root in ("extended/ext", "stdlib/core", "docs"):
    for name in sorted(os.listdir(os.path.join(REPO, root)))[:40]:
        path = os.path.join(REPO, root, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                TEXT += f.read()
            if len(TEXT) > 4 << 20:
                break


def content(size):
    kind = rng.randrange(6)
    if kind == 0:
        return rng.randbytes(size)
    if kind == 1:
        words = [b"lanius", b"shrike", b"zstd", b"frame", b"\n", b" ", b"0123", b"huffman"]
        return b"".join(rng.choice(words) for _ in range(size // 3 + 1))[:size]
    if kind == 2:
        return bytes([rng.randrange(256)]) * size
    if kind == 3:
        seed = rng.randbytes(rng.randrange(1, 300))
        return (seed * (size // len(seed) + 1))[:size]
    if kind == 4:
        # Text with sparse byte noise: literals, matches and repeat offsets.
        start = rng.randrange(0, max(1, len(TEXT) - size))
        data = bytearray(TEXT[start:start + size])
        while len(data) < size:
            data += TEXT[:size - len(data)]
        for _ in range(size // 500):
            data[rng.randrange(size)] = rng.randrange(256)
        return bytes(data)
    start = rng.randrange(0, max(1, len(TEXT) - size))
    data = TEXT[start:start + size]
    return (data * (size // max(1, len(data)) + 1))[:size]


def size():
    return rng.choice([0, 1, 2, 5, 100, 1000, 4096, 40000, 131071, 131072, 131073, 300000, 1 << 20, 1500000])


def compress(data, flags, timeout=120):
    code, out, err = run([ZSTD, "-q", "-c"] + flags, data, timeout)
    if code != 0:
        fail("zstd %s refused: %s" % (flags, err[:200]))
        return None
    return out


def check(group, frame, expected, via_file=None):
    """Decode frame with the sample (stdin, or as a file) and compare."""
    if via_file is None:
        via_file = rng.random() < 0.3
    if via_file:
        path = os.path.join(WORK, "case.zst")
        with open(path, "wb") as f:
            f.write(frame)
        code, out, err = run([UNZSTD, "-c", path], timeout=120)
    else:
        code, out, err = run([UNZSTD], frame, timeout=120)
    if code != 0 or out != expected:
        fail("%s: exit %d, %d bytes (want %d): %s" % (group, code, len(out), len(expected), err[:200]))
        return False
    bump(group)
    return True


def refused(group, frame, want=2):
    code, out, err = run([UNZSTD], frame, timeout=60)
    if code != want:
        fail("%s: exit %d (want %d) %s" % (group, code, want, err[:200]))
    else:
        bump(group)


# ---------------------------------------------------------------- XXH64
def xxh_group():
    for _ in range(20 if QUICK else 60):
        data = content(rng.choice([0, 1, 3, 4, 7, 8, 31, 32, 33, 63, 64, 100, 1000, 65536, 1 << 20]))
        split = rng.choice([1, 3, 7, 8, 31, 32, 33, 1000, 1 << 20])
        code, out, err = run([PROBE, str(split)], data)
        if code != 0 or out.strip() != b"%016x" % xxh64(data):
            fail("xxh64 len %d split %d: %s" % (len(data), split, out[:40]))
        else:
            bump("xxh64 probe")
    # The Python reference against zstd's own frame trailers.
    for _ in range(20):
        data = content(rng.choice([0, 10, 1000, 100000]))
        frame = compress(data, ["-1", "--check"])
        if frame is not None and frame[-4:] == struct.pack("<I", xxh64(data) & 0xFFFFFFFF):
            bump("xxh64 trailer")
        else:
            fail("xxh64 trailer len %d" % len(data))


# ---------------------------------------------------------------- frames
def level_group():
    levels = list(range(1, 20))
    rounds = 2 if QUICK else 5
    for level in levels:
        for _ in range(rounds):
            data = content(size())
            flags = ["-%d" % level] + rng.choice([[], [], ["--no-check"], ["--no-content-size"], ["--no-check", "--no-content-size"]])
            frame = compress(data, flags)
            if frame is not None:
                check("levels 1-19", frame, data)
        # Piped input: no content size, frames sized by blocks alone.
        data = content(rng.choice([1000, 300000]))
        code, frame, err = run(["sh", "-c", "cat | %s -q -c -%d" % (ZSTD, level)], data)
        if code == 0:
            check("piped", frame, data)
        else:
            fail("piped zstd refused")
    for level in (20, 22) if QUICK else (20, 21, 22):
        data = content(1 << 20)
        frame = compress(data, ["--ultra", "-%d" % level])
        if frame is not None:
            check("ultra 20-22", frame, data)


def params_group():
    for _ in range(15 if QUICK else 60):
        data = content(size())
        wlog = rng.randrange(10, 24)
        strat = rng.randrange(1, 10)
        params = "wlog=%d,strat=%d" % (wlog, strat)
        if rng.random() < 0.5:
            params += ",mml=%d" % rng.randrange(3, 8)
        flags = ["--zstd=" + params] + rng.choice([[], ["--compress-literals"], ["--no-compress-literals"], ["--target-compressed-block-size=1340"], ["--no-check"]])
        frame = compress(data, flags)
        if frame is not None:
            check("params", frame, data)


def long_group():
    # Matches 12 MiB back: beyond the default (level 1-19) windows.
    block = rng.randbytes(3 << 20)
    data = block + rng.randbytes(9 << 20) + block + b"tail" * 1000
    for level in ([1, 3] if QUICK else [1, 3, 9, 15]):
        frame = compress(data, ["--long=27", "-%d" % level], timeout=280)
        if frame is not None:
            if len(frame) > len(data) - (2 << 20):
                fail("--long did not use the long window (level %d)" % level)
            check("long=27", frame, data, via_file=True)
    # A 256 MiB window exceeds zstd's (and the sample's) default limit.
    frame = compress(b"x" * 1000, ["--long=28", "-1", "--no-content-size"])
    if frame is not None:
        code, _, _ = run([ZSTD, "-q", "-d", "-c"], frame)
        if code == 0:
            fail("zstd accepted a 2^28 window")
        refused("window limit", frame)
        code, out, _ = run([UNZSTD, "--memory", "256"], frame)
        if code == 0 and out == b"x" * 1000:
            bump("window limit")
        else:
            fail("--memory 256 refused a 2^28 window")


def skippable(payload, nibble=None):
    if nibble is None:
        nibble = rng.randrange(16)
    return struct.pack("<II", 0x184D2A50 + nibble, len(payload)) + payload


def multi_group():
    for _ in range(10 if QUICK else 40):
        frames, expected = [], b""
        for _ in range(rng.randrange(2, 6)):
            pick = rng.random()
            if pick < 0.2:
                frames.append(skippable(rng.randbytes(rng.choice([0, 1, 100, 70000]))))
                continue
            data = content(rng.choice([0, 0, 10, 1000, 200000]))
            frame = compress(data, ["-%d" % rng.randrange(1, 20)] + rng.choice([[], ["--no-check"], ["--no-content-size"]]))
            if frame is None:
                return
            frames.append(frame)
            expected += data
        whole = b"".join(frames)
        code, out, _ = run([ZSTD, "-q", "-d", "-c"], whole)
        if code != 0 or out != expected:
            fail("zstd disagrees with the multi-frame expectation")
            continue
        check("multi-frame", whole, expected)
    # Edge files.
    check("multi-frame", skippable(b"hidden", 0), b"")
    check("multi-frame", compress(b"", ["-3"]) or b"", b"")
    check("multi-frame", compress(b"", ["-3", "--no-content-size"]) + skippable(b"") + compress(b"a", []), b"a")
    one = compress(b"payload" * 100, ["-5"])
    refused("trailing garbage", one + b"\x00")
    refused("trailing garbage", one + one[:3])
    refused("trailing garbage", b"not zstd at all")
    refused("trailing garbage", skippable(b"abc")[:-1])
    code, _, _ = run([ZSTD, "-q", "-d", "-c"], b"")
    want = 0 if code == 0 else 2
    if want == 0:
        check("empty input", b"", b"")
    else:
        refused("empty input", b"")


def dictionary_group():
    # A frame naming a dictionary ID (the sample has no dictionaries).
    plain = compress(b"dictionary test " * 50, ["-3", "--no-content-size", "--no-check"])
    fhd = plain[4]
    crafted = plain[:4] + bytes([fhd | 1]) + plain[5:6] + b"\x07" + plain[6:]
    refused("dictionary", crafted)
    samples = os.path.join(WORK, "samples")
    os.makedirs(samples, exist_ok=True)
    for i in range(200):
        with open(os.path.join(samples, "s%d" % i), "wb") as f:
            f.write(b"record %d name=shrike%d value=%d\n" % (i, i % 17, i * 7919) * 8)
    dict_path = os.path.join(WORK, "dict")
    code, _, err = run([ZSTD, "-q", "-f", "--train", "--maxdict=4096", "-o", dict_path] + [os.path.join(samples, "s%d" % i) for i in range(200)])
    if code == 0:
        frame = compress(b"record 5 name=shrike5 value=39595\n" * 4, ["-3", "-D", dict_path])
        if frame is not None:
            refused("dictionary", frame)


def cli_group():
    data = content(50000)
    path = os.path.join(WORK, "file.txt")
    for leftover in (path, path + ".zst"):
        if os.path.exists(leftover):
            os.remove(leftover)
    with open(path + ".zst", "wb") as f:
        f.write(compress(data, ["-7"]))
    ok = lambda name, cond: bump("cli") if cond else fail("cli: " + name)
    code, out, _ = run([UNZSTD, path + ".zst"])
    ok("FILE.zst -> FILE", code == 0 and out == b"" and open(path, "rb").read() == data and os.path.exists(path + ".zst"))
    code, _, _ = run([UNZSTD, path + ".zst"])
    ok("existing output refused", code == 2)
    with open(path, "wb") as f:
        f.write(b"old")
    code, _, _ = run([UNZSTD, "-f", path + ".zst"])
    ok("-f overwrites", code == 0 and open(path, "rb").read() == data)
    code, out, _ = run([UNZSTD, "-t", path + ".zst"])
    ok("-t writes nothing", code == 0 and out == b"")
    code, out, _ = run([UNZSTD, "-c", path + ".zst", path + ".zst"])
    ok("-c concatenates", code == 0 and out == data + data)
    link = os.path.join(WORK, "zstdcat")
    if not os.path.lexists(link):
        os.symlink(UNZSTD, link)
    code, out, _ = run([link, path + ".zst"])
    ok("zstdcat", code == 0 and out == data)
    code, _, _ = run([UNZSTD, path])
    ok("unknown suffix", code == 2)
    with open(path + ".zst", "r+b") as f:
        f.seek(40)
        f.write(b"\xff\xff\xff\xff")
    os.remove(path)
    code, _, _ = run([UNZSTD, path + ".zst"])
    ok("corrupt input leaves no output", code == 2 and not os.path.exists(path))
    code, _, _ = run([UNZSTD, os.path.join(WORK, "missing.zst")])
    ok("missing file", code == 3)


def chunked_group():
    for _ in range(15 if QUICK else 50):
        frames, expected = [], b""
        for _ in range(rng.randrange(1, 4)):
            if rng.random() < 0.15:
                frames.append(skippable(rng.randbytes(rng.choice([0, 5, 3000]))))
                continue
            data = content(rng.choice([0, 1, 100, 5000, 140000, 400000]))
            frame = compress(data, ["-%d" % rng.randrange(1, 20)] + rng.choice([[], ["--no-check"], ["--no-content-size"], ["--zstd=wlog=10"]]))
            if frame is None:
                return
            frames.append(frame)
            expected += data
        steps = [str(rng.choice([1, 2, 3, 7, 64, 1000, 65536])), str(rng.choice([1, 5, 300, 4096, 65536]))]
        if len(expected) > 100000 and steps[1] in ("1", "5"):
            steps[1] = "300"
        code, out, err = run([STEPPER] + steps, b"".join(frames), timeout=120)
        if code != 0 or out != expected:
            fail("chunked %s: exit %d, %d bytes (want %d)" % (steps, code, len(out), len(expected)))
        else:
            bump("chunked steps")


# ---------------------------------------------------------------- encoder
def encode_group():
    if not ENCODER or not ENCODE_PROBE:
        return
    sizes = [0, 1, 3, 4, 63, 64, 255, 256, 1023, 1024, 5000, 131071, 131072, 131073, 262144, 700000]
    for _ in range(25 if QUICK else 90):
        data = content(rng.choice(sizes))
        if rng.random() < 0.15:
            # Several distinct pieces: offsets of every size and repeat codes.
            data = b"".join(content(rng.choice([10, 300, 5000, 70000])) for _ in range(rng.randrange(2, 12)))
        level = rng.randrange(1, 4)
        code, frame, err = run([ENCODER, "-%d" % level, "-c"], data, timeout=120)
        if code != 0:
            fail("encode L%d %d bytes: exit %d %s" % (level, len(data), code, err[:100]))
            continue
        zcode, zout, zerr = run([ZSTD, "-q", "-d", "-c"], frame)
        tcode, _, _ = run([ZSTD, "-q", "-t"], frame)
        if zcode != 0 or zout != data or tcode != 0:
            fail("encode L%d %d bytes: zstd -d exit %d %s" % (level, len(data), zcode, zerr[:100]))
            with open(os.path.join(WORK, "enc-%d.zst" % len(failures)), "wb") as f:
                f.write(frame)
            continue
        bump("encode: zstd -d and -t accept")
        if not check("encode: sample decodes", frame, data, via_file=False):
            continue
        steps = [str(rng.choice([1, 7, 4096, 65536, 1 << 20])), str(rng.choice([1, 13, 4096, 1 << 20]))]
        if len(data) > 200000 and "1" in steps:
            steps = ["4096", "13"]
        code, again, _ = run([ENCODE_PROBE, str(level)] + steps, data, timeout=120)
        if code != 0 or again != frame:
            fail("encode L%d %d bytes: steps %s changed the frame" % (level, len(data), steps))
        else:
            bump("encode: step invariant")
    # Window slides and long inputs: 3 MiB to 9 MiB with far repeats.
    for level in (1, 2, 3):
        piece = content(1 << 20)
        data = piece + rng.randbytes(1 << 20) + piece + content(3 << 20) + piece[:300000]
        if QUICK:
            data = data[:3 << 20]
        code, frame, _ = run([ENCODER, "-%d" % level, "-c"], data, timeout=280)
        zcode, zout, _ = run([ZSTD, "-q", "-d", "-c"], frame, timeout=120)
        if code != 0 or zcode != 0 or zout != data:
            fail("encode long input L%d" % level)
        else:
            bump("encode: multi-MiB inputs")


def encode_sizes():
    if not ENCODER:
        return
    corpora = []
    tar = os.path.join(WORK, "corpus.tar")
    subprocess.run(["tar", "cf", tar, "-C", REPO, "stdlib", "extended"], capture_output=True)
    corpora.append(("stdlib+extended tar", open(tar, "rb").read()))
    corpora.append(("text", TEXT[:4 << 20]))
    with open(UNZSTD, "rb") as f:
        corpora.append(("unzstd executable", f.read()))
    for name, data in corpora:
        row = ["%s (%d B):" % (name, len(data))]
        ours = {}
        for level in (1, 2, 3):
            code, frame, _ = run([ENCODER, "-%d" % level, "-c"], data, timeout=280)
            zcode, zout, _ = run([ZSTD, "-q", "-d", "-c"], frame, timeout=120)
            if code != 0 or zcode != 0 or zout != data:
                fail("encode corpus %s L%d" % (name, level))
            ours[level] = len(frame)
            row.append("L%d %d" % (level, len(frame)))
        for level in (1, 3):
            row.append("zstd -%d %d" % (level, len(compress(data, ["-%d" % level]) or b"")))
        bump("encode: corpora")
        print(" ".join(row), file=sys.stderr)


# ---------------------------------------------------------------- fuzz
def fuzz_group():
    bases = []
    for _ in range(6 if QUICK else 16):
        data = content(rng.choice([100, 2000, 20000, 150000]))
        flags = ["-%d" % rng.randrange(1, 20)] + rng.choice([[], ["--no-check"], ["--no-check", "--no-content-size"]])
        frame = compress(data, flags)
        if frame is not None:
            bases.append(frame)
    agree = stricter = laxer = 0
    for frame in bases:
        trials = []
        lengths = list(range(len(frame))) if len(frame) <= 64 else [rng.randrange(len(frame)) for _ in range(30 if QUICK else 80)]
        trials += [frame[:n] for n in lengths]
        for _ in range(40 if QUICK else 150):
            mutated = bytearray(frame)
            for _ in range(rng.choice([1, 1, 2, 3])):
                at = rng.randrange(len(mutated))
                mutated[at] ^= 1 << rng.randrange(8)
            trials.append(bytes(mutated))
        for trial in trials:
            code, out, err = run([UNZSTD], trial, timeout=20)
            if code not in (0, 2):
                fail("fuzz: exit %d on %d bytes: %s" % (code, len(trial), err[:100]))
                with open(os.path.join(WORK, "fuzz-%d.zst" % len(failures)), "wb") as f:
                    f.write(trial)
                continue
            bump("fuzz")
            zcode, zout, _ = run([ZSTD, "-q", "-d", "-c"], trial, timeout=20)
            if code == 0 and zcode == 0 and out != zout:
                fail("fuzz: both accept, outputs differ (%d bytes)" % len(trial))
                with open(os.path.join(WORK, "fuzz-%d.zst" % len(failures)), "wb") as f:
                    f.write(trial)
            elif (code == 0) == (zcode == 0):
                agree += 1
            elif code == 0:
                laxer += 1
                with open(os.path.join(WORK, "lax-%d.zst" % laxer), "wb") as f:
                    f.write(trial)
            else:
                # zstd's fast Huffman loops do not check that each literal
                # stream ends exactly; 1.5.5 also ignores the reserved
                # sequence-mode bits. The sample refuses both.
                stricter += 1
    counts["fuzz agrees with zstd"] = agree
    counts["fuzz stricter than zstd"] = stricter
    counts["fuzz laxer than zstd"] = laxer


groups = {"xxh": xxh_group, "levels": level_group, "params": params_group, "long": long_group, "multi": multi_group,
          "dict": dictionary_group, "cli": cli_group, "chunked": chunked_group, "encode": encode_group,
          "sizes": encode_sizes, "fuzz": fuzz_group}
chosen = [a[len("--only="):] for a in sys.argv if a.startswith("--only=")]
for name, group in groups.items():
    if not chosen or name in chosen:
        group()
for key in counts:
    print("%-26s %d" % (key, counts[key]))
print("failures", len(failures))
sys.exit(1 if failures else 0)
