#!/usr/bin/env python3
"""Differential oracle for ext::xz through sample_programs/library/xz_bytes.

Usage: python3 -I xz_oracle.py XZ_BYTES [--quick] [--xz PATH]

Generates many xz and .lzma streams with Python's lzma module (and the xz
CLI when present: multi-block streams with sizes in block headers,
concatenated streams, stream padding), decodes them with xz-bytes under
several input/output step sizes and compares with Python. Corrupt streams
(truncations, bit flips, appended data) must be rejected exactly when a
strict Python decode rejects them; when both accept, outputs must match.

"Strict" means: every xz stream must end at EOF or be followed by stream
padding (a multiple of four zero bytes) and another stream; .lzma must end
exactly at EOF. Python's lzma.decompress silently ignores trailing garbage;
such cases are counted as "python tolerant" (rejected by xz-bytes and by
the strict reference).

Streams go to one `xz-bytes batch` process per section (records on stdin), so
the run costs decoding time, not process start-ups.
"""
import lzma
import os
import random
import resource
import shutil
import struct
import subprocess
import sys
import time

ERRORS = {10: "Bounds", 11: "Header", 12: "Options", 13: "UnsupportedCheck", 14: "UnsupportedFilter",
          15: "Corrupt", 16: "Checksum", 17: "Index", 18: "Footer", 19: "SizeMismatch",
          21: "Truncated", 22: "TrailingData", 23: "Failed"}


def no_core():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


class Oracle:
    def __init__(self, binary, xz):
        self.binary = binary
        self.xz = xz
        self.counts = {}
        self.failures = []
        self.errors = {}
        self.decoded = 0
        self.seconds = 0.0
        self.queue = []
        self.queued = 0
        self.batches = 0

    def bump(self, key, n=1):
        self.counts[key] = self.counts.get(key, 0) + n

    def run(self, fmt, data, step_in=65536, step_out=65536):
        """One stream in its own process (used for timing)."""
        started = time.monotonic()
        done = subprocess.run([self.binary, fmt, str(step_in), str(step_out)], input=data,
                              capture_output=True, timeout=60)
        self.seconds += time.monotonic() - started
        return done.returncode, done.stdout

    def submit(self, fmt, data, step_in, step_out, judge):
        """Queue one decode; judge(code, out) runs when the batch returns."""
        self.queue.append((fmt, data, step_in, step_out, judge))
        self.queued += len(data)
        if len(self.queue) >= 4000 or self.queued > (32 << 20):
            self.flush()

    def flush(self):
        if not self.queue:
            return
        payload = b"".join(struct.pack("<BIII", 1 if fmt == "lzma" else 0, step_in, step_out, len(data)) + data
                           for fmt, data, step_in, step_out, _ in self.queue)
        started = time.monotonic()
        done = subprocess.run([self.binary, "batch"], input=payload, capture_output=True, timeout=240)
        self.seconds += time.monotonic() - started
        self.batches += 1
        out = done.stdout
        position = 0
        for index, (_, _, _, _, judge) in enumerate(self.queue):
            if position + 5 > len(out):
                self.fail("batch", f"exit {done.returncode} after {index} of {len(self.queue)} records")
                break
            code, length = struct.unpack_from("<BI", out, position)
            position += 5
            judge(code, out[position:position + length])
            position += length
        self.queue = []
        self.queued = 0

    def fail(self, label, detail):
        self.failures.append(f"{label}: {detail}")

    def expect_ok(self, group, label, fmt, data, plain, steps):
        for step_in, step_out in steps:
            def judge(code, out, name=f"{group}/{label}/{step_in}x{step_out}"):
                if code != 0 or out != plain:
                    self.fail(name, f"exit {code} ({ERRORS.get(code, '?')}), {len(out)} of {len(plain)} bytes, "
                                    f"equal prefix {out == plain[:len(out)]}")
                else:
                    self.bump(group)
                    self.decoded += len(plain)
            self.submit(fmt, data, step_in, step_out, judge)

    def compare(self, group, label, fmt, data, steps=((65536, 65536),)):
        reference = strict_xz(data) if fmt == "xz" else strict_alone(data)
        tolerant = loose(fmt, data)
        for step_in, step_out in steps:
            def judge(code, out, name=f"{group}/{label}/{step_in}x{step_out}"):
                if reference is None:
                    if code == 0:
                        self.fail(name, f"accepted ({len(out)} bytes) but strict Python rejects")
                    elif code < 10:
                        self.fail(name, f"exit {code} is not a decoder error")
                    else:
                        self.errors[ERRORS.get(code, str(code))] = self.errors.get(ERRORS.get(code, str(code)), 0) + 1
                        self.bump(group + " rejected")
                        if tolerant is not None:
                            self.bump("python tolerant")
                elif code == 13 and fmt == "xz":
                    self.bump("unsupported check (expected)")
                elif code != 0 or out != reference:
                    self.fail(name, f"exit {code} ({ERRORS.get(code, '?')}), {len(out)} bytes, "
                                    f"Python accepts {len(reference)} bytes")
                else:
                    self.bump(group + " accepted")
            self.submit(fmt, data, step_in, step_out, judge)


def strict_xz(data):
    out = []
    rest = data
    while True:
        decoder = lzma.LZMADecompressor(lzma.FORMAT_XZ)
        try:
            out.append(decoder.decompress(rest))
        except lzma.LZMAError:
            return None
        if not decoder.eof:
            return None
        rest = decoder.unused_data
        stripped = rest.lstrip(b"\0")
        if (len(rest) - len(stripped)) % 4:
            return None
        if not stripped:
            return b"".join(out)
        rest = stripped


def strict_alone(data):
    decoder = lzma.LZMADecompressor(lzma.FORMAT_ALONE)
    try:
        out = decoder.decompress(data)
    except lzma.LZMAError:
        return None
    if not decoder.eof or decoder.unused_data:
        return None
    return out


def loose(fmt, data):
    try:
        return lzma.decompress(data, format=lzma.FORMAT_XZ if fmt == "xz" else lzma.FORMAT_ALONE)
    except lzma.LZMAError:
        return None


def datasets(rng, quick):
    words = [bytes(rng.choice(b"abcdefghijklmnopqrstuvwxyz") for _ in range(rng.randint(1, 9))) for _ in range(300)]

    def text(n):
        parts = []
        size = 0
        while size < n:
            w = rng.choice(words) + rng.choice([b" ", b" ", b"\n", b", "])
            parts.append(w)
            size += len(w)
        return b"".join(parts)[:n]

    def far(n, period):
        block = rng.randbytes(period)
        return (block * (n // period + 1))[:n]

    def mixed(n):
        out = bytearray()
        while len(out) < n:
            kind = rng.randint(0, 3)
            size = rng.randint(1, 40000)
            if kind == 0:
                out += rng.randbytes(size)
            elif kind == 1:
                out += bytes([rng.randint(0, 255)]) * size
            elif kind == 2:
                out += text(size)
            else:
                at = rng.randint(0, max(0, len(out) - 1))
                out += out[at:at + size]
        return bytes(out[:n])

    sets = [("empty", b""), ("one", b"x"), ("two", b"ab"), ("zeros4k", bytes(4096)),
            ("rand100", rng.randbytes(100)), ("rand4095", rng.randbytes(4095)),
            ("rand65537", rng.randbytes(65537)), ("text20k", text(20000)), ("text200k", text(200000)),
            ("run1m", b"a" * 1000000), ("far300k", far(300000, 70000)), ("mixed150k", mixed(150000)),
            ("ints", b"".join(i.to_bytes(4, "little") for i in range(30000))),
            ("bytes256", bytes(range(256)) * 40)]
    if not quick:
        sets += [("mixed3m", mixed(3 * 1024 * 1024)), ("rand2.2m", rng.randbytes(2300000)),
                 ("text2.5m", text(2600000))]
    return sets


def filters(lc, lp, pb, dict_size, mode, nice, mf):
    return [{"id": lzma.FILTER_LZMA2, "dict_size": dict_size, "lc": lc, "lp": lp, "pb": pb,
             "mode": mode, "nice_len": nice, "mf": mf}]


def alone_filters(lc, lp, pb, dict_size):
    return [{"id": lzma.FILTER_LZMA1, "dict_size": dict_size, "lc": lc, "lp": lp, "pb": pb}]


def main():
    args = sys.argv[1:]
    quick = "--quick" in args
    xz = shutil.which("xz")
    if "--xz" in args:
        xz = args[args.index("--xz") + 1]
    binary = os.path.abspath(args[0])
    no_core()  # inherited by every xz-bytes run
    oracle = Oracle(binary, xz)
    rng = random.Random(20261031)
    sets = datasets(rng, quick)
    started = time.monotonic()
    corpus = []  # (fmt, label, stream, plain) for the corruption group

    small_steps = ((65536, 65536), (1, 1), (3, 7), (13, 1), (1, 4096), (4096, 5))
    def mark(what):
        oracle.flush()
        print(f"[{time.monotonic() - started:6.1f} s, {oracle.seconds:6.1f} s decoding] {what}", file=sys.stderr, flush=True)

    for name, plain in sets:
        mark(name)
        steps = small_steps if len(plain) <= 5000 else ((65536, 65536), (7, 65536), (65536, 333))
        if len(plain) > 1000000:
            steps = ((65536, 65536),)
        presets = [0, 1, 6, 9, 6 | lzma.PRESET_EXTREME] if len(plain) < 1000000 else [0, 6]
        for preset in presets:
            for check in (lzma.CHECK_NONE, lzma.CHECK_CRC32, lzma.CHECK_CRC64):
                stream = lzma.compress(plain, format=lzma.FORMAT_XZ, check=check, preset=preset)
                oracle.expect_ok("python xz", f"{name}/p{preset}/c{check}", "xz", stream, plain, steps)
                if len(stream) < 3000 and check != lzma.CHECK_CRC32:
                    corpus.append(("xz", f"{name}/p{preset}/c{check}", stream, plain))
        if len(plain) < 1000000:
            for lc, lp, pb in ((0, 0, 0), (4, 0, 2), (0, 4, 0), (1, 3, 4), (3, 1, 1), (2, 2, 3)):
                for dict_size, mode, nice, mf in ((4096, lzma.MODE_FAST, 5, lzma.MF_HC3),
                                                  (1 << 20, lzma.MODE_NORMAL, 273, lzma.MF_BT4),
                                                  (65536, lzma.MODE_NORMAL, 32, lzma.MF_BT2)):
                    chain = filters(lc, lp, pb, dict_size, mode, nice, mf)
                    stream = lzma.compress(plain, format=lzma.FORMAT_XZ, filters=chain)
                    oracle.expect_ok("python xz filters", f"{name}/{lc}{lp}{pb}/{dict_size}", "xz", stream, plain,
                                     steps[:2])
                    alone = lzma.compress(plain, format=lzma.FORMAT_ALONE, filters=alone_filters(lc, lp, pb, dict_size))
                    oracle.expect_ok("python lzma filters", f"{name}/{lc}{lp}{pb}/{dict_size}", "lzma", alone, plain,
                                     steps[:2])
            for preset in (0, 6, 9):
                alone = lzma.compress(plain, format=lzma.FORMAT_ALONE, preset=preset)
                oracle.expect_ok("python lzma", f"{name}/p{preset}", "lzma", alone, plain, steps)
                # Same stream with the size recorded: liblzma then also accepts the end marker.
                sized = alone[:5] + len(plain).to_bytes(8, "little") + alone[13:]
                oracle.compare("lzma known size+marker", f"{name}/p{preset}", "lzma", sized, steps[:2])
                if len(alone) < 3000:
                    corpus.append(("lzma", f"{name}/p{preset}", alone, plain))
            # Known size without an end marker: one LZMA2 chunk's payload is exactly that.
            raw = lzma.compress(plain[:60000], format=lzma.FORMAT_RAW, filters=filters(3, 0, 2, 1 << 16, lzma.MODE_NORMAL, 64, lzma.MF_BT4))
            if len(plain) and raw[0] >= 0xE0 and len(raw) == 6 + ((raw[3] << 8) | raw[4]) + 1 + 1:
                body = raw[6:-1]
                header = bytes([raw[5]]) + (1 << 16).to_bytes(4, "little") + len(plain[:60000]).to_bytes(8, "little")
                oracle.compare("lzma known size", name, "lzma", header + body, steps[:2])
                corpus.append(("lzma", f"{name}/known", header + body, plain[:60000]))
        sha = lzma.compress(plain[:1000], format=lzma.FORMAT_XZ, check=lzma.CHECK_SHA256)
        oracle.compare("sha256", name, "xz", sha)

    mark("xz cli")
    if xz:
        for name, plain in sets:
            if len(plain) > 1000000 and quick:
                continue
            for flags in (["-0"], ["-6e", "--check=crc32"], ["-T2", "--block-size=20000"],
                          ["--block-list=1000,5000,0", "--check=none"], ["--lzma2=preset=1,lc=0,lp=2,pb=0", "--block-size=65536"],
                          ["--format=lzma", "-3"]):
                fmt = "lzma" if "--format=lzma" in flags else "xz"
                stream = subprocess.run([xz, "-c", "-qq", *flags], input=plain, capture_output=True, check=True).stdout
                oracle.expect_ok("xz cli", f"{name}/{' '.join(flags)}", fmt, stream, plain, ((65536, 65536), (5, 9)) if len(plain) < 400000 else ((65536, 65536),))
                if fmt == "xz" and len(stream) < 4000 and "-T2" in flags:
                    corpus.append(("xz", f"{name}/blocks", stream, plain))
            for flags in (["--delta=dist=4", "--lzma2"], ["--x86", "--lzma2"]):
                if not plain:
                    continue  # no blocks, so no filter chain
                stream = subprocess.run([xz, "-c", "-qq", *flags], input=plain[:5000], capture_output=True, check=True).stdout

                def judge(code, out, name=name):
                    if code == 14:
                        oracle.bump("unsupported filter (expected)")
                    else:
                        oracle.fail(f"filter/{name}", f"exit {code}")
                oracle.submit("xz", stream, 65536, 65536, judge)

    mark("concatenation")
    # Concatenation and stream padding.
    pieces = [lzma.compress(p, check=c) for (_, p), c in zip(sets[:8], [0, 1, 4, 0, 1, 4, 0, 1])]
    for count in range(1, len(pieces) + 1):
        for pad in (0, 4, 8, 1, 3, 5):
            stream = (bytes(pad)).join(pieces[:count]) + bytes(pad if count % 2 else 0)
            oracle.compare("concatenated", f"{count}/{pad}", "xz", stream, ((65536, 65536), (1, 3)))
    corpus.append(("xz", "concat", pieces[1] + bytes(4) + pieces[2], None))

    mark(f"corruption over {len(corpus)} streams")
    # Corruption: truncations, flips, appended data, for small streams.
    for fmt, label, stream, _ in corpus:
        positions = list(range(len(stream))) if len(stream) <= 120 else sorted(set(rng.sample(range(len(stream)), 50) + list(range(0, 40)) + list(range(len(stream) - 40, len(stream)))))
        cuts = positions if len(stream) <= 120 else positions[::2]
        for cut in cuts:
            oracle.compare("truncated", f"{label}@{cut}", fmt, stream[:cut], ((65536, 65536), (1, 1)) if cut < 200 else ((65536, 65536),))
        for at in positions:
            for bit in ((1, 128) if len(stream) <= 120 else (rng.choice((1, 2, 4, 8, 16, 32, 64, 128)),)):
                flipped = bytearray(stream)
                flipped[at] ^= bit
                oracle.compare("bit flip", f"{label}@{at}^{bit}", fmt, bytes(flipped))
        for tail in (b"\0", b"\0" * 4, b"\xfd", b"garbage!", stream):
            oracle.compare("appended", f"{label}+{len(tail)}", fmt, stream + tail)

    # Decoder-error sanity: the error class must be right for a few crafted cases.
    base = lzma.compress(b"hello world " * 50)
    check_at = len(base) - 12 - 12 - 8  # footer, index (12 bytes here), CRC64
    for label, data, want in (("bad magic", b"\xfe" + base[1:], 11), ("cut header", base[:7], 21),
                              ("bad check", base[:check_at] + bytes([base[check_at] ^ 1]) + base[check_at + 1:], 16),
                              ("bad footer magic", base[:-1] + b"Q", 18), ("trailing", base + b"x", 22),
                              ("sha256", lzma.compress(b"a", check=lzma.CHECK_SHA256), 13)):
        def judge(code, out, label=label, want=want):
            if code != want:
                oracle.fail(f"class/{label}", f"exit {code}, want {want}")
            else:
                oracle.bump("error class")
        oracle.submit("xz", data, 65536, 65536, judge)
    oracle.flush()

    # Throughput on the largest set (decode time only, one run).
    big = max(sets, key=lambda item: len(item[1]))[1]
    stream = lzma.compress(big, preset=6)
    t0 = time.monotonic()
    code, out = oracle.run("xz", stream)
    elapsed = time.monotonic() - t0
    if code != 0 or out != big:
        oracle.fail("throughput", f"exit {code}")

    total = sum(v for k, v in oracle.counts.items() if "expected" not in k and k != "python tolerant")
    print(f"xz oracle: {total} agreeing cases, {len(oracle.failures)} failures, "
          f"{time.monotonic() - started:.1f} s ({oracle.seconds:.1f} s in {oracle.batches} xz-bytes batches)")
    for key in sorted(oracle.counts):
        print(f"  {key}: {oracle.counts[key]}")
    print("  rejection classes: " + ", ".join(f"{k} {v}" for k, v in sorted(oracle.errors.items())))
    print(f"  decoded {oracle.decoded / 1e6:.1f} MB in checked runs; {len(big) / 1e6:.1f} MB stream in {elapsed:.2f} s "
          f"({len(big) / 1e6 / max(elapsed, 1e-9):.1f} MB/s)")
    for failure in oracle.failures[:40]:
        print("FAIL", failure)
    return 1 if oracle.failures else 0


if __name__ == "__main__":
    sys.exit(main())
