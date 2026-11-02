"""/usr/bin/xz oracle for the unxz sample (sample_programs/library/unxz.lani).

usage: python3 -I unxz_oracle.py UNXZ WORKDIR [--quick] [--only=GROUP]...

Files written by /usr/bin/xz at presets 0-9 and 0e-9e (checks none, CRC32
and CRC64), multi-block files (threaded block sizes and block lists),
multi-stream files with stream padding, and .lzma files are decoded by the
sample and compared byte for byte. SHA-256 checks, other filters and
trailing garbage must be refused (exit 2). The command line is checked for
output naming, -f, -t, -c and xzcat. Fuzzing truncates and flips bits in
compressed files: the sample must exit 0 or 2, never a signal or a hang, and
must match `xz -d` whenever both accept. Every case is seeded. Prints one
count line per group and exits nonzero on any disagreement.
(tests/fixtures/extended/xz_oracle.py checks ext::xz itself against Python
lzma under step sizes down to one byte.)
"""
import os, random, subprocess, sys, time

UNXZ, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
QUICK = "--quick" in sys.argv
XZ = "/usr/bin/xz"
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
os.makedirs(WORK, exist_ok=True)
counts = {}
failures = []
rng = random.Random(20261102)


def bump(key, n=1):
    counts[key] = counts.get(key, 0) + n


def fail(msg):
    failures.append(msg)
    if len(failures) < 20:
        print("FAIL", msg, file=sys.stderr)


def run(argv, data=b"", timeout=120):
    try:
        p = subprocess.run(argv, input=data, capture_output=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return -999, b"", b"timeout"
    return p.returncode, p.stdout, p.stderr


TEXT = b""
for root in ("extended/ext", "stdlib/core", "docs"):
    for name in sorted(os.listdir(os.path.join(REPO, root)))[:40]:
        path = os.path.join(REPO, root, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                TEXT += f.read()


def content(size):
    kind = rng.randrange(5)
    if kind == 0:
        return rng.randbytes(size)
    if kind == 1:
        return bytes([rng.randrange(256)]) * size
    if kind == 2:
        seed = rng.randbytes(rng.randrange(1, 300))
        return (seed * (size // len(seed) + 1))[:size]
    start = rng.randrange(0, max(1, len(TEXT) - size))
    data = bytearray(TEXT[start:start + size])
    while len(data) < size:
        data += TEXT[:size - len(data)]
    if kind == 3:
        for _ in range(size // 500):
            data[rng.randrange(size)] = rng.randrange(256)
    return bytes(data)


def size():
    return rng.choice([0, 1, 2, 100, 4096, 40000, 65536, 65537, 300000, 1 << 20, 3 << 20])


def compress(data, flags, timeout=200):
    code, out, err = run([XZ, "-q", "-c"] + flags, data, timeout)
    if code != 0:
        fail("xz %s refused: %s" % (flags, err[:200]))
        return None
    return out


def check(group, frame, expected):
    if rng.random() < 0.3:
        path = os.path.join(WORK, "case.xz")
        with open(path, "wb") as f:
            f.write(frame)
        code, out, err = run([UNXZ, "-c", path])
    else:
        code, out, err = run([UNXZ], frame)
    if code != 0 or out != expected:
        fail("%s: exit %d, %d bytes (want %d): %s" % (group, code, len(out), len(expected), err[:200]))
        return False
    bump(group)
    return True


def refused(group, frame):
    code, _, err = run([UNXZ], frame)
    if code != 2:
        fail("%s: exit %d (want 2) %s" % (group, code, err[:200]))
    else:
        bump(group)


def preset_group():
    for preset in range(10):
        for extreme in ("", "e"):
            for _ in range(1 if QUICK else 3):
                data = content(size())
                flags = ["-%d%s" % (preset, extreme), "--check=" + rng.choice(["none", "crc32", "crc64"])]
                frame = compress(data, flags)
                if frame is not None:
                    check("presets 0-9, 0e-9e", frame, data)


def block_group():
    for _ in range(6 if QUICK else 25):
        data = content(rng.choice([100000, 700000, 2 << 20]))
        pick = rng.randrange(3)
        if pick == 0:
            flags = ["-T2", "--block-size=%d" % rng.choice([1000, 20000, 65536, 300000])]
        elif pick == 1:
            flags = ["--block-list=%s" % ",".join([str(rng.choice([1, 500, 5000, 70000])) for _ in range(rng.randrange(1, 6))] + [str(rng.choice([20000, 300000]))])]
        else:
            flags = ["-T3", "--block-size=50000", "--check=crc32"]
        frame = compress(data, ["-%d" % rng.randrange(0, 7)] + flags)
        if frame is not None:
            check("multi-block", frame, data)


def stream_group():
    for _ in range(6 if QUICK else 25):
        parts, expected = [], b""
        for _ in range(rng.randrange(2, 5)):
            data = content(rng.choice([0, 10, 5000, 200000]))
            frame = compress(data, ["-%d" % rng.randrange(0, 10)])
            if frame is None:
                return
            parts.append(frame + b"\0" * (4 * rng.choice([0, 0, 1, 3, 1024])))
            expected += data
        whole = b"".join(parts)
        code, out, _ = run([XZ, "-q", "-d", "-c"], whole)
        if code != 0 or out != expected:
            fail("xz disagrees with the multi-stream expectation")
            continue
        check("multi-stream", whole, expected)
    for _ in range(3 if QUICK else 10):
        data = content(size())
        frame = compress(data, ["--format=lzma", "-%d" % rng.randrange(0, 10)])
        if frame is not None:
            check(".lzma", frame, data)
    one = compress(b"payload" * 100, ["-6"])
    refused("refused", one + b"\x00")
    refused("refused", one + b"garbage!")
    refused("refused", compress(b"sha" * 1000, ["--check=sha256"]))
    refused("refused", compress(b"delta" * 1000, ["--delta=dist=2", "--lzma2=preset=6"]))
    refused("refused", b"")


def cli_group():
    data = content(50000)
    path = os.path.join(WORK, "file.txt")
    for leftover in (path, path + ".xz", os.path.join(WORK, "pack.tar")):
        if os.path.exists(leftover):
            os.remove(leftover)
    with open(path + ".xz", "wb") as f:
        f.write(compress(data, ["-6"]))
    ok = lambda name, cond: bump("cli") if cond else fail("cli: " + name)
    code, out, _ = run([UNXZ, path + ".xz"])
    ok("FILE.xz -> FILE", code == 0 and out == b"" and open(path, "rb").read() == data and os.path.exists(path + ".xz"))
    code, _, _ = run([UNXZ, path + ".xz"])
    ok("existing output refused", code == 2)
    with open(path, "wb") as f:
        f.write(b"old")
    code, _, _ = run([UNXZ, "-f", path + ".xz"])
    ok("-f overwrites", code == 0 and open(path, "rb").read() == data)
    code, out, _ = run([UNXZ, "-t", path + ".xz"])
    ok("-t writes nothing", code == 0 and out == b"")
    code, out, _ = run([UNXZ, "-c", path + ".xz", path + ".xz"])
    ok("-c concatenates", code == 0 and out == data + data)
    tar = os.path.join(WORK, "pack.txz")
    with open(tar, "wb") as f:
        f.write(compress(data, ["-1"]))
    code, _, _ = run([UNXZ, tar])
    ok(".txz -> .tar", code == 0 and open(os.path.join(WORK, "pack.tar"), "rb").read() == data)
    link = os.path.join(WORK, "xzcat")
    if not os.path.lexists(link):
        os.symlink(UNXZ, link)
    code, out, _ = run([link, path + ".xz"])
    ok("xzcat", code == 0 and out == data)
    code, _, _ = run([UNXZ, path])
    ok("unknown suffix", code == 2)
    with open(path + ".xz", "r+b") as f:
        f.seek(100)
        f.write(b"\xff\xff\xff\xff")
    os.remove(path)
    code, _, _ = run([UNXZ, path + ".xz"])
    ok("corrupt input leaves no output", code == 2 and not os.path.exists(path))
    code, _, _ = run([UNXZ, os.path.join(WORK, "missing.xz")])
    ok("missing file", code == 3)


def fuzz_group():
    bases = []
    for _ in range(6 if QUICK else 16):
        data = content(rng.choice([100, 2000, 20000, 150000]))
        flags = ["-%d" % rng.randrange(0, 10), "--check=" + rng.choice(["none", "crc32", "crc64"])]
        if rng.random() < 0.25:
            flags = ["--format=lzma", "-%d" % rng.randrange(0, 10)]
        frame = compress(data, flags)
        if frame is not None:
            bases.append(frame)
    agree = stricter = laxer = 0
    for frame in bases:
        lengths = list(range(len(frame))) if len(frame) <= 80 else [rng.randrange(len(frame)) for _ in range(30 if QUICK else 80)]
        trials = [frame[:n] for n in lengths]
        for _ in range(40 if QUICK else 150):
            mutated = bytearray(frame)
            for _ in range(rng.choice([1, 1, 2, 3])):
                at = rng.randrange(len(mutated))
                mutated[at] ^= 1 << rng.randrange(8)
            trials.append(bytes(mutated))
        for trial in trials:
            code, out, err = run([UNXZ], trial, timeout=20)
            if code not in (0, 2):
                fail("fuzz: exit %d on %d bytes: %s" % (code, len(trial), err[:100]))
                with open(os.path.join(WORK, "fuzz-%d.xz" % len(failures)), "wb") as f:
                    f.write(trial)
                continue
            bump("fuzz")
            # .lzma has no magic: name the format for xz as the sample chose it.
            fmt = "--format=xz" if trial[:6] == b"\xfd7zXZ\x00" else "--format=lzma"
            zcode, zout, _ = run([XZ, "-q", "-d", "-c", fmt], trial, timeout=20)
            if code == 0 and zcode == 0 and out != zout:
                fail("fuzz: both accept, outputs differ (%d bytes)" % len(trial))
            elif (code == 0) == (zcode == 0):
                agree += 1
            elif code == 0:
                laxer += 1
                with open(os.path.join(WORK, "lax-%d.xz" % laxer), "wb") as f:
                    f.write(trial)
            else:
                stricter += 1
                with open(os.path.join(WORK, "strict-%d.xz" % stricter), "wb") as f:
                    f.write(trial)
    counts["fuzz agrees with xz"] = agree
    counts["fuzz stricter than xz"] = stricter
    counts["fuzz laxer than xz"] = laxer


groups = {"presets": preset_group, "blocks": block_group, "streams": stream_group, "cli": cli_group, "fuzz": fuzz_group}
chosen = [a[len("--only="):] for a in sys.argv if a.startswith("--only=")]
for name, group in groups.items():
    if not chosen or name in chosen:
        started = time.time()
        group()
        print("%s: %.1f s" % (name, time.time() - started), file=sys.stderr)
for key in counts:
    print("%-26s %d" % (key, counts[key]))
print("failures", len(failures))
sys.exit(1 if failures else 0)
