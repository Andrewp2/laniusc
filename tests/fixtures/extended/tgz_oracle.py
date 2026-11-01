"""Python zlib/gzip/lzma/tarfile oracles for compress-bytes and tgz.

usage: python3 -I tgz_oracle.py TGZ COMPRESS_BYTES WORKDIR [--quick]

Every generated case is deterministic (seeded). Prints one count line per
group and exits nonzero on any disagreement.
"""
import gzip, hashlib, io, lzma, os, random, resource, shutil, stat, subprocess, sys, tarfile, zlib
GNU_TAR = shutil.which("tar")

TGZ, CODEC, WORK = sys.argv[1:4]
QUICK = "--quick" in sys.argv
os.makedirs(WORK, exist_ok=True)
counts = {}
failures = []


def bump(key, n=1):
    counts[key] = counts.get(key, 0) + n


def fail(msg):
    failures.append(msg)
    if len(failures) < 20:
        print("FAIL", msg, file=sys.stderr)


SUFFIX = {"": "", "z": ".gz", "J": ".xz"}
LABEL = {"": "", "z": " (gzip)", "J": " (xz)"}


def run(argv, data=b"", cwd=None):
    p = subprocess.run(argv, input=data, capture_output=True, timeout=30, cwd=cwd)
    return p.returncode, p.stdout, p.stderr


# ---------------------------------------------------------------- inputs
def inputs(rng, n):
    out = [b"", b"a", b"\x00" * 70000, bytes(range(256)) * 9]
    words = [b"lanius", b"shrike", b"deflate", b"tar", b"\n", b" ", b"0123"]
    while len(out) < n:
        kind = rng.randrange(5)
        size = rng.choice([1, 7, 255, 256, 257, 1000, 4096, 32768, 32769, 65536, 100000, rng.randrange(1, 140000)])
        if kind == 0:
            out.append(rng.randbytes(size))
        elif kind == 1:
            out.append(b"".join(rng.choice(words) for _ in range(size // 4 + 1))[:size])
        elif kind == 2:
            out.append(bytes([rng.randrange(4)]) * size)
        elif kind == 3:
            seed = rng.randbytes(rng.randrange(1, 300))
            out.append((seed * (size // len(seed) + 1))[:size])
        else:
            parts = [rng.randbytes(rng.randrange(1, 2000)) if rng.random() < 0.5 else b"x" * rng.randrange(1, 5000) for _ in range(8)]
            out.append(b"".join(parts)[:size])
    return out


def py_encode(data, fmt, level, strategy):
    wbits = {"raw": -15, "zlib": 15, "gzip": 31}[fmt]
    c = zlib.compressobj(level, zlib.DEFLATED, wbits, 9, strategy)
    return c.compress(data) + c.flush()


def py_decode(data, fmt):
    wbits = {"raw": -15, "zlib": 15, "gzip": 31}[fmt]
    if fmt == "gzip":
        return gzip.decompress(data)
    d = zlib.decompressobj(wbits)
    out = d.decompress(data) + d.flush()
    if not d.eof or d.unused_data:
        raise zlib.error("incomplete or trailing")
    return out


def codec_group(rng):
    data = inputs(rng, 24 if QUICK else 72)
    configs = [(0, zlib.Z_DEFAULT_STRATEGY), (1, zlib.Z_DEFAULT_STRATEGY), (6, zlib.Z_DEFAULT_STRATEGY),
               (9, zlib.Z_DEFAULT_STRATEGY), (6, zlib.Z_FIXED), (6, zlib.Z_HUFFMAN_ONLY), (6, zlib.Z_RLE)]
    for item in data:
        for fmt in ("raw", "zlib", "gzip"):
            code, out, err = run([CODEC, "--format", fmt], item)
            if code != 0:
                fail(f"lanius encode {fmt} len={len(item)} rc={code} {err!r}")
            else:
                try:
                    back = py_decode(out, fmt)
                    if back == item:
                        bump("encode: Lanius -> Python " + fmt)
                    else:
                        fail(f"python decoded mismatch {fmt} len={len(item)}")
                except Exception as e:
                    fail(f"python rejected lanius {fmt} len={len(item)}: {e}")
            for level, strategy in configs:
                stream = py_encode(item, fmt, level, strategy)
                code, out, err = run([CODEC, "-d", "--format", fmt], stream)
                if code == 0 and out == item:
                    bump("decode: Python -> Lanius " + fmt)
                else:
                    fail(f"lanius decode {fmt} level={level} strategy={strategy} len={len(item)} rc={code} {err!r}")
    # Corruption: Lanius must reject every stream Python rejects; when Python
    # accepts a mutated stream, Lanius must reject it or produce the same bytes.
    for index in range(150 if QUICK else 600):
        item = data[rng.randrange(len(data))] or b"seed"
        fmt = rng.choice(["raw", "zlib", "gzip"])
        stream = bytearray(py_encode(item, fmt, rng.choice([1, 6, 9]), zlib.Z_DEFAULT_STRATEGY))
        how = rng.randrange(4)
        if how == 0:
            stream = stream[: rng.randrange(len(stream))]
        elif how == 1:
            stream[rng.randrange(len(stream))] ^= 1 << rng.randrange(8)
        elif how == 2:
            stream += rng.randbytes(rng.randrange(1, 9))
        else:
            for _ in range(rng.randrange(2, 6)):
                stream[rng.randrange(len(stream))] = rng.randrange(256)
        stream = bytes(stream)
        try:
            expected = py_decode(stream, fmt)
        except Exception:
            expected = None
        code, out, err = run([CODEC, "-d", "--format", fmt], stream)
        if expected is None:
            if code == 2 and out == b"":
                bump("corrupt: both reject")
            else:
                fail(f"lanius accepted corrupt {fmt} how={how} rc={code}")
        elif code == 0:
            if out == expected:
                bump("corrupt: both accept, same bytes")
            else:
                fail(f"corrupt {fmt} accepted with different bytes")
        else:
            bump("corrupt: Python accepts, Lanius rejects")


# ---------------------------------------------------------------- trees
def make_tree(root, rng, case):
    os.makedirs(root)
    names = []
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789_-."
    def name():
        r = rng.random()
        if r < 0.1:
            return "ü名" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 8)))
        if r < 0.25:
            return "long_" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(90, 140)))
        n = "".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 12)))
        return n if n not in (".", "..") else n + "x"
    dirs = [""]
    for _ in range(rng.randrange(1, 4 if QUICK else 6)):
        d = os.path.join(rng.choice(dirs), name())
        if len(d.encode()) > 400 or os.path.exists(os.path.join(root, d)):
            continue
        os.makedirs(os.path.join(root, d))
        dirs.append(d)
    for _ in range(rng.randrange(1, 6 if QUICK else 12)):
        f = os.path.join(rng.choice(dirs), name())
        full = os.path.join(root, f)
        if os.path.exists(full) or len(f.encode()) > 600:
            continue
        size = rng.choice([0, 1, 511, 512, 513, 1024, rng.randrange(0, 70000)])
        data = rng.randbytes(size) if rng.random() < 0.5 else (b"tar " * (size // 4 + 1))[:size]
        with open(full, "wb") as h:
            h.write(data)
        os.chmod(full, rng.choice([0o644, 0o600, 0o755, 0o640]))
        names.append(f)
    for _ in range(rng.randrange(0, 3)):
        if names:
            first = rng.choice(names)
            link = os.path.join(rng.choice(dirs), "hl_" + name())
            if not os.path.lexists(os.path.join(root, link)) and len(link.encode()) < 600:
                os.link(os.path.join(root, first), os.path.join(root, link))
    if names and rng.random() < 0.6:
        target = os.path.basename(rng.choice(names))
        if rng.random() < 0.3:
            target = "x" * 120 + target
        link = os.path.join(rng.choice(dirs), "ln_" + str(case))
        if not os.path.lexists(os.path.join(root, link)):
            os.symlink(target, os.path.join(root, link))


def snapshot(root):
    out = {}
    for base, ds, fs in os.walk(root):
        for n in ds + fs:
            full = os.path.join(base, n)
            rel = os.path.relpath(full, root)
            st = os.lstat(full)
            if stat.S_ISLNK(st.st_mode):
                out[rel] = ("l", os.readlink(full))
            elif stat.S_ISDIR(st.st_mode):
                out[rel] = ("d", stat.S_IMODE(st.st_mode), int(st.st_mtime))
            else:
                with open(full, "rb") as h:
                    out[rel] = ("f", hashlib.sha256(h.read()).hexdigest(), stat.S_IMODE(st.st_mode), int(st.st_mtime))
    return out


def groups(root, prefix=""):
    seen = {}
    for base, ds, fs in os.walk(root):
        for n in fs:
            full = os.path.join(base, n)
            st = os.lstat(full)
            if stat.S_ISREG(st.st_mode) and st.st_nlink > 1:
                seen.setdefault(st.st_ino, []).append(prefix + os.path.relpath(full, root))
    return sorted(tuple(sorted(v)) for v in seen.values() if len(v) > 1)


def members(path):
    out = {}
    with tarfile.open(path, "r:*") as t:
        for m in t:
            if m.issym():
                out[m.name] = ("l", m.linkname)
            elif m.isdir():
                out[m.name] = ("d", m.mode, int(m.mtime))
            else:
                # Hard links resolve to their target's data and metadata.
                target = t.getmember(m.linkname) if m.islnk() else m
                out[m.name] = ("f", hashlib.sha256(t.extractfile(m).read()).hexdigest(), target.mode, int(target.mtime))
    return out


def tar_groups(path):
    linked = {}
    with tarfile.open(path, "r:*") as t:
        for m in t:
            if m.islnk():
                linked.setdefault(m.linkname, {m.linkname}).add(m.name)
    return sorted(tuple(sorted(v)) for v in linked.values())


def tar_group(rng):
    cases = 12 if QUICK else 60
    for case in range(cases):
        base = os.path.join(WORK, f"tree{case}")
        shutil.rmtree(base, ignore_errors=True)
        src = os.path.join(base, "src")
        make_tree(os.path.join(src, "top"), rng, case)
        expected = {("top/" + k): v for k, v in snapshot(os.path.join(src, "top")).items()}
        st = os.stat(os.path.join(src, "top"))
        expected["top"] = ("d", stat.S_IMODE(st.st_mode), int(st.st_mtime))
        expected_groups = groups(os.path.join(src, "top"), "top/")
        # Lanius create -> Python tarfile read.
        for gz in ("", "z", "J"):
            archive = os.path.join(base, "lanius.tar" + SUFFIX[gz])
            code, _, err = run([TGZ, "-c" + gz + "f", archive, "-C", src, "top"])
            if code != 0:
                fail(f"tgz create case={case} gz={gz} rc={code} {err!r}")
                continue
            try:
                got = members(archive)
            except Exception as e:
                fail(f"tarfile rejected lanius case={case}: {e}")
                continue
            if got == expected and tar_groups(archive) == expected_groups:
                bump("tar: Lanius create -> Python tarfile" + LABEL[gz])
            else:
                fail(f"tarfile view differs case={case} gz={gz}: {sorted(set(got) ^ set(expected))[:4]}")
            # Lanius list must match Python names in order.
            code, out, _ = run([TGZ, "-tf", archive])
            with tarfile.open(archive, "r:*") as t:
                names = [m.name for m in t]
            listed = [n.rstrip("/") for n in out.decode("utf-8", "surrogateescape").split("\n")[:-1]]
            if code == 0 and listed == names:
                bump("tar: Lanius list == Python names")
            else:
                fail(f"list differs case={case}")
        # Python create (ustar and pax, plain and gzip) -> Lanius extract.
        for fmt, label in ((tarfile.PAX_FORMAT, "pax"), (tarfile.USTAR_FORMAT, "ustar"), (tarfile.GNU_FORMAT, "gnu")):
            for gz in ("", "z", "J"):
                archive = os.path.join(base, f"py-{label}.tar" + SUFFIX[gz])
                try:
                    with tarfile.open(archive, {"": "w", "z": "w:gz", "J": "w:xz"}[gz], format=fmt) as t:
                        t.add(os.path.join(src, "top"), arcname="top")
                except ValueError:
                    bump(f"tar: Python {label} cannot represent tree (skipped)")
                    continue
                out = os.path.join(base, f"out-{label}-{gz}")
                os.makedirs(out)
                code, _, err = run([TGZ, "-xf", archive, "-C", out])
                if code != 0:
                    fail(f"tgz extract {label} gz={gz} case={case} rc={code} {err!r}")
                    continue
                got = {k: v for k, v in snapshot(out).items()}
                if got == expected and groups(out) == expected_groups:
                    bump(f"tar: Python {label} create -> Lanius extract" + LABEL[gz])
                else:
                    fail(f"extract differs {label} gz={gz} case={case}: {sorted(set(got) ^ set(expected))[:4]}")
        # Lanius create -> Lanius extract round trip.
        out = os.path.join(base, "out-self")
        os.makedirs(out)
        code, _, _ = run([TGZ, "-xzf", os.path.join(base, "lanius.tar.gz"), "-C", out])
        if code == 0 and snapshot(out) == expected and groups(out) == expected_groups:
            bump("tar: Lanius create -> Lanius extract")
        else:
            fail(f"self round trip case={case}")
        # GNU tar as a second oracle: its gnu/pax/ustar output -> tgz, and tgz -> GNU tar.
        if GNU_TAR:
            for fmt in ("gnu", "pax", "ustar"):
                for gz in ("", "z", "J"):
                    archive = os.path.join(base, f"gnu-{fmt}.tar" + SUFFIX[gz])
                    code, _, err = run([GNU_TAR, "--format=" + fmt, "-c" + gz + "f", archive, "-C", src, "top"])
                    if code != 0:
                        bump(f"tar: GNU tar {fmt} cannot represent tree (skipped)")
                        continue
                    out = os.path.join(base, f"out-gnu-{fmt}-{gz}")
                    os.makedirs(out)
                    code, _, err = run([TGZ, "-xf", archive, "-C", out])
                    if code == 0 and snapshot(out) == expected and groups(out) == expected_groups:
                        bump(f"tar: GNU tar {fmt} create -> Lanius extract" + LABEL[gz])
                    else:
                        fail(f"gnu tar {fmt} gz={gz} case={case} rc={code} {err!r}")
            for gz in ("z", "J"):
                out = os.path.join(base, "out-by-gnu" + gz)
                os.makedirs(out)
                code, _, err = run([GNU_TAR, "-xp" + gz + "f", os.path.join(base, "lanius.tar" + SUFFIX[gz]), "-C", out])
                if code == 0 and snapshot(out) == expected and groups(out) == expected_groups:
                    bump("tar: Lanius create -> GNU tar extract" + LABEL[gz])
                else:
                    fail(f"gnu tar extract of lanius gz={gz} case={case} rc={code} {err!r}")
        # Lanius xz create -> Lanius extract.
        out = os.path.join(base, "out-self-xz")
        os.makedirs(out)
        code, _, _ = run([TGZ, "-xJf", os.path.join(base, "lanius.tar.xz"), "-C", out])
        if code == 0 and snapshot(out) == expected and groups(out) == expected_groups:
            bump("tar: Lanius create -> Lanius extract (xz)")
        else:
            fail(f"self xz round trip case={case}")
        shutil.rmtree(base)
    # Global pax header and explicit pax records written by Python.
    base = os.path.join(WORK, "global")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    archive = os.path.join(base, "g.tar")
    with tarfile.open(archive, "w", format=tarfile.PAX_FORMAT, pax_headers={"comment": "global"}) as t:
        info = tarfile.TarInfo("p" * 300)
        info.size = 3
        info.mtime = 1700000000.25
        info.uname = "u" * 40
        t.addfile(info, io.BytesIO(b"abc"))
    code, out, _ = run([TGZ, "-tf", archive])
    if code == 0 and out == b"p" * 300 + b"\n":
        bump("tar: pax global header + long path/uname/fractional mtime")
    else:
        fail(f"global pax rc={code} out={out[:40]!r}")
    shutil.rmtree(base)


def corrupt_group(rng):
    base = os.path.join(WORK, "corrupt")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as t:
        for i in range(4):
            info = tarfile.TarInfo(f"d/file{i}" + "q" * (150 * (i % 2)))
            data = rng.randbytes(700 * i)
            info.size = len(data)
            t.addfile(info, io.BytesIO(data))
    good = buf.getvalue()
    with tarfile.open(fileobj=io.BytesIO(good)) as t:
        headers = sorted({m.offset for m in t} | {m.offset_data - 512 for m in t})
    def attempt(blob, label, gz):
        archive = os.path.join(base, "a.tar" + (".gz" if gz else ""))
        with open(archive, "wb") as h:
            h.write(gzip.compress(blob, mtime=0) if gz == 1 else blob)
        out = os.path.join(base, "out")
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        code, _, _ = run([TGZ, "-xf", archive, "-C", out])
        try:
            with tarfile.open(archive, "r:*") as t:
                for m in t:
                    if m.isfile():
                        t.extractfile(m).read()
            python_ok = True
        except Exception:
            python_ok = False
        if code == 2 and os.listdir(out) == []:
            bump(f"reject: {label}" + (" (Python also rejects)" if not python_ok else " (Python tolerant)"))
        else:
            fail(f"{label} rc={code}")
    for i in range(10 if QUICK else 40):
        blob = bytearray(good)
        header = rng.choice(headers)
        blob[header + rng.randrange(148)] ^= 0x20
        attempt(bytes(blob), "header byte flip", 0)
        attempt(good[: rng.randrange(1, len(good) - 1024) // 512 * 512 + rng.randrange(512)], "truncated tar", 0)
    gz = bytearray(gzip.compress(good, mtime=0))
    for i in range(10 if QUICK else 40):
        blob = bytearray(gz)
        blob[-8 + rng.randrange(8)] ^= 1 << rng.randrange(8)
        archive = os.path.join(base, "bad.tgz")
        with open(archive, "wb") as h:
            h.write(blob)
        code, _, _ = run([TGZ, "-tzf", archive])
        if code == 2:
            bump("reject: gzip trailer (CRC32/ISIZE) flip")
        else:
            fail("gzip trailer flip accepted")
        blob = bytearray(gz)
        cut = rng.randrange(10, len(gz) - 1)
        with open(archive, "wb") as h:
            h.write(blob[:cut])
        code, _, _ = run([TGZ, "-tzf", archive])
        if code == 2:
            bump("reject: truncated gzip")
        else:
            fail("truncated gzip accepted")
    # xz-compressed tar: every flip or cut must be rejected before any output.
    xzs = [lzma.compress(good, preset=6), lzma.compress(good, check=lzma.CHECK_CRC32, preset=0)]
    for i in range(20 if QUICK else 80):
        stream = xzs[i % 2]
        blob = bytearray(stream)
        blob[rng.randrange(len(blob))] ^= 1 << rng.randrange(8)
        archive = os.path.join(base, "bad.txz")
        for label, data in (("xz byte flip", bytes(blob)), ("truncated xz", stream[:rng.randrange(1, len(stream))]),
                            ("xz trailing garbage", stream + b"\x01")):
            with open(archive, "wb") as h:
                h.write(data)
            out = os.path.join(base, "out")
            shutil.rmtree(out, ignore_errors=True)
            os.makedirs(out)
            code, _, _ = run([TGZ, "-xf", archive, "-C", out])
            try:
                python_ok = lzma.LZMADecompressor().decompress(data) == good
            except lzma.LZMAError:
                python_ok = False
            if code == 2 and os.listdir(out) == []:
                bump(f"reject: {label}" + (" (Python tolerant)" if python_ok else " (Python also rejects)"))
            else:
                fail(f"{label} rc={code}")
    for bad in ("../evil", "/abs/evil", "a/../../evil", "./../evil", "a/./b"):
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
            ok = tarfile.TarInfo("ok")
            t.addfile(ok, io.BytesIO(b""))
            info = tarfile.TarInfo(bad)
            info.size = 1
            t.addfile(info, io.BytesIO(b"x"))
        attempt(buf.getvalue(), "unsafe path", 0)
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        info = tarfile.TarInfo("abs-link")
        info.type = tarfile.SYMTYPE
        info.linkname = "/etc/passwd"
        t.addfile(info)
    attempt(buf.getvalue(), "absolute symlink target", 0)
    # Hand-built pax extension records that ext::pax must reject.
    def ext(records, flag=b"x"):
        info = tarfile.TarInfo("././@PaxHeader")
        info.type = flag
        info.size = len(records)
        block = info.tobuf(tarfile.USTAR_FORMAT)
        return block + records + b"\0" * ((512 - len(records) % 512) % 512)
    def member(name=b"m", data=b"xy"):
        info = tarfile.TarInfo(name.decode())
        info.size = len(data)
        return info.tobuf(tarfile.USTAR_FORMAT) + data + b"\0" * ((512 - len(data) % 512) % 512)
    end = b"\0" * 1024
    bad = {
        "pax record length too long": ext(b"99 path=a\n") + member() + end,
        "pax record without newline": ext(b"9 path=ab") + member() + end,
        "pax record without '='": ext(b"9 pathab\n") + member() + end,
        "pax record bad uid": ext(b"10 uid=1x\n") + member() + end,
        "pax negative mtime": ext(b"12 mtime=-1\n") + member() + end,
        "pax GNU.sparse key": ext(b"21 GNU.sparse.size=1\n") + member() + end,
        "pax size mismatch": ext(b"9 size=5\n") + member() + end,
        "two x headers in a row": ext(b"10 path=a\n") + ext(b"10 path=c\n") + member() + end,
        "x header before footer": member() + ext(b"10 path=a\n") + end,
        "second global header": ext(b"10 path=a\n", b"g") + ext(b"10 path=c\n", b"g") + member() + end,
    }
    for label, blob in bad.items():
        try:
            with tarfile.open(fileobj=io.BytesIO(blob)) as t:
                [m.name for m in t]
            python_ok = True
        except Exception:
            python_ok = False
        archive = os.path.join(base, "p.tar")
        with open(archive, "wb") as h:
            h.write(blob)
        code, out, _ = run([TGZ, "-tf", archive])
        if code == 2 and out == b"":
            bump(f"reject: {label}" + (" (Python also rejects)" if not python_ok else " (Python tolerant)"))
        else:
            fail(f"{label} rc={code} out={out!r}")
    good_pax = ext(b"13 path=long\n" + b"30 mtime=1700000000.123456789\n" + b"8 uid=7\n" + b"10 gname=\n") + member() + end
    code, out, _ = run([TGZ, "-tf", os.path.join(base, "p.tar")])
    with open(os.path.join(base, "p.tar"), "wb") as h:
        h.write(good_pax)
    code, out, _ = run([TGZ, "-tf", os.path.join(base, "p.tar")])
    if code == 0 and out == b"long\n":
        bump("pax: hand-built path/mtime/uid/empty-value records")
    else:
        fail(f"hand-built pax rc={code} out={out!r}")
    shutil.rmtree(base)


def stream_group():
    """A tgz pipeline over a 96 MiB tree must not hold the archive or a member."""
    base = os.path.join(WORK, "stream")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(os.path.join(base, "src", "big"))
    os.makedirs(os.path.join(base, "out"))
    block = random.Random(7).randbytes(1 << 20)
    with open(os.path.join(base, "src", "big", "a.bin"), "wb") as h:
        for i in range(64):
            h.write(block)
    with open(os.path.join(base, "src", "big", "b.txt"), "wb") as h:
        h.write(b"lanius streaming\n" * (2 << 20))
    del block
    # Measure from a fresh, small interpreter so forked children do not
    # inherit this process's resident pages.
    probe = """
import resource, subprocess, sys
tgz, src, out = sys.argv[1:]
create = subprocess.Popen([tgz, "-czf", "-", "-C", src, "big"], stdout=subprocess.PIPE)
extract = subprocess.Popen([tgz, "-xzf", "-", "-C", out], stdin=create.stdout)
create.stdout.close()
print(extract.wait(timeout=240), create.wait(timeout=240), resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)
"""
    measured = subprocess.run([sys.executable, "-I", "-c", probe, TGZ, os.path.join(base, "src"), os.path.join(base, "out")], capture_output=True, text=True, timeout=280)
    a, b, peak = (int(x) for x in measured.stdout.split())
    rc = (a, b)
    same = snapshot(os.path.join(base, "src")) == snapshot(os.path.join(base, "out"))
    print(f"stream: 96 MiB pipeline rc={rc} peak child RSS {peak} KiB")
    if rc == (0, 0) and same and peak < 32768:
        bump("stream: 96 MiB czf | xzf pipeline under 32 MiB RSS")
    else:
        fail(f"stream pipeline rc={rc} same={same} peak={peak}")
    shutil.rmtree(base)


def guard_group():
    base = os.path.join(WORK, "guard")
    shutil.rmtree(base, ignore_errors=True)
    outside = os.path.join(base, "outside")
    os.makedirs(outside)
    with open(os.path.join(outside, "keep"), "wb") as h:
        h.write(b"keep")
    def archive(entries):
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as t:
            for name, kind, value in entries:
                info = tarfile.TarInfo(name)
                if kind == "f":
                    info.size = len(value)
                    t.addfile(info, io.BytesIO(value))
                else:
                    info.type = tarfile.SYMTYPE if kind == "l" else tarfile.LNKTYPE
                    info.linkname = value
                    t.addfile(info)
        path = os.path.join(base, "g.tar")
        with open(path, "wb") as h:
            h.write(buf.getvalue())
        return path
    def untouched():
        return os.listdir(outside) == ["keep"] and open(os.path.join(outside, "keep"), "rb").read() == b"keep"
    cases = [
        ("existing symlinked parent", [("evil/x", "f", b"x")], lambda out: os.symlink(outside, os.path.join(out, "evil")), 2),
        ("existing symlink leaf is replaced, not followed", [("keep", "f", b"new")], lambda out: os.symlink(os.path.join(outside, "keep"), os.path.join(out, "keep")), 0),
        ("archive symlink then member through it", [("s", "l", "../outside"), ("s/x", "f", b"x")], None, 2),
        ("hard link through a symlinked parent", [("s", "l", "../outside"), ("h", "h", "s/keep")], None, 2),
        ("hard link to a member", [("a", "f", b"data"), ("b", "h", "a")], None, 0),
    ]
    for label, entries, prepare, status in cases:
        out = os.path.join(base, "out")
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        if prepare:
            prepare(out)
        code, _, _ = run([TGZ, "-xf", archive(entries), "-C", out])
        ok = code == status and untouched()
        if ok and status == 0 and label.startswith("existing"):
            ok = not os.path.islink(os.path.join(out, "keep")) and open(os.path.join(out, "keep"), "rb").read() == b"new"
        if ok and label == "hard link to a member":
            ok = os.stat(os.path.join(out, "a")).st_ino == os.stat(os.path.join(out, "b")).st_ino
        if ok:
            bump("guard: " + label)
        else:
            fail(f"guard {label} rc={code}")
    shutil.rmtree(base)


rng = random.Random(20261031)
stream_group()
guard_group()
codec_group(rng)
tar_group(rng)
corrupt_group(rng)
total = 0
for key in sorted(counts):
    print(f"{counts[key]:6d}  {key}")
    if "(skipped)" not in key:
        total += counts[key]
print(f"{total:6d}  total agreeing cases; {len(failures)} failures")
sys.exit(1 if failures else 0)
