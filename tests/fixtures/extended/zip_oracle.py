"""Python zipfile oracle for the zip sample (sample_programs/library/zip.lani).

usage: python3 -I zip_oracle.py ZIP WORKDIR [--quick]

Both directions: archives the sample writes are read back with zipfile (and
`unzip -t` when it is installed), and archives zipfile writes (stored and
deflated, every compresslevel, streamed with data descriptors, forced
ZIP64, more than 65535 entries, comments, empty members) are listed and
extracted by the sample. Malformed input (unsafe names, unsupported
methods, encryption, truncation at every length and random byte flips)
must give exit 2 and never a signal or a hang. Every case is seeded.
Prints one count line per group and exits nonzero on any disagreement.
"""
import calendar, hashlib, io, os, random, shutil, stat, struct, subprocess, sys, time, zipfile, zlib

ZIP, WORK = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
QUICK = "--quick" in sys.argv
UNZIP = shutil.which("unzip")
os.makedirs(WORK, exist_ok=True)
counts = {}
failures = []


def bump(key, n=1):
    counts[key] = counts.get(key, 0) + n


def fail(msg):
    failures.append(msg)
    if len(failures) < 20:
        print("FAIL", msg, file=sys.stderr)


def run(argv, data=b"", cwd=None, timeout=60):
    try:
        p = subprocess.run(argv, input=data, capture_output=True, timeout=timeout, cwd=cwd)
    except subprocess.TimeoutExpired:
        return -999, b"", b"timeout"
    return p.returncode, p.stdout, p.stderr


def content(rng, size):
    kind = rng.randrange(4)
    if kind == 0:
        return rng.randbytes(size)
    if kind == 1:
        words = [b"lanius", b"shrike", b"zip", b"deflate", b"\n", b" ", b"0123"]
        return b"".join(rng.choice(words) for _ in range(size // 3 + 1))[:size]
    if kind == 2:
        return bytes([rng.randrange(3)]) * size
    seed = rng.randbytes(rng.randrange(1, 200))
    return (seed * (size // len(seed) + 1))[:size]


# ---------------------------------------------------------------- trees
def make_tree(root, rng, case):
    os.makedirs(root)
    alphabet = "abcdefghijklmnopqrstuvwxyz0123456789_-."
    def name():
        r = rng.random()
        if r < 0.1:
            return "ü名" + "".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 8)))
        n = "".join(rng.choice(alphabet) for _ in range(rng.randrange(1, 12)))
        return n if n not in (".", "..") else n + "x"
    dirs = [""]
    for _ in range(rng.randrange(1, 6)):
        d = os.path.join(rng.choice(dirs), name())
        if os.path.exists(os.path.join(root, d)):
            continue
        os.makedirs(os.path.join(root, d))
        os.chmod(os.path.join(root, d), rng.choice([0o755, 0o700, 0o775]))
        dirs.append(d)
    files = []
    for _ in range(rng.randrange(1, 6 if QUICK else 12)):
        f = os.path.join(rng.choice(dirs), name())
        full = os.path.join(root, f)
        if os.path.exists(full):
            continue
        size = rng.choice([0, 1, 2, 3, 258, 32768, 32769, 65536, 65537, rng.randrange(0, 200000)])
        with open(full, "wb") as h:
            h.write(content(rng, size))
        os.chmod(full, rng.choice([0o644, 0o600, 0o755, 0o640]))
        files.append(f)
    if files and rng.random() < 0.5:
        link = os.path.join(rng.choice(dirs), "ln_" + str(case))
        if not os.path.lexists(os.path.join(root, link)):
            os.symlink(os.path.basename(rng.choice(files)), os.path.join(root, link))
    # Fixed, distinct mtimes (even seconds, the DOS resolution).
    stamp = 1600000000 + case * 1000
    for base, ds, fs in os.walk(root, topdown=False):
        for n in fs + ds:
            stamp += 2
            os.utime(os.path.join(base, n), (stamp, stamp), follow_symlinks=False)
    os.utime(root, (stamp + 2, stamp + 2))


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


def zip_view(path):
    """What zipfile sees: name -> (kind, data hash or target, mode, mtime)."""
    out = {}
    with zipfile.ZipFile(path) as z:
        bad = z.testzip()
        if bad is not None:
            raise ValueError("testzip " + bad)
        for info in z.infolist():
            mode = info.external_attr >> 16
            when = calendar.timegm(info.date_time + (0, 0, 0))
            data = z.read(info)
            name = info.filename.rstrip("/")
            if info.is_dir():
                out[name] = ("d", stat.S_IMODE(mode), when)
            elif stat.S_ISLNK(mode):
                out[name] = ("l", data.decode())
            else:
                out[name] = ("f", hashlib.sha256(data).hexdigest(), stat.S_IMODE(mode), when)
    return out


def tree_view(root, top):
    # The archive's view of the tree: names under top, DOS times in UTC.
    out = {top: ("d",) + snapshot_dir(root)}
    for rel, value in snapshot(root).items():
        out[top + "/" + rel] = value
    return out


def snapshot_dir(root):
    st = os.lstat(root)
    return (stat.S_IMODE(st.st_mode), int(st.st_mtime))


# ---------------------------------------------------------------- sample writes, zipfile reads
def write_group(rng):
    cases = 10 if QUICK else 40
    flags = [[], ["-L", "0"], ["-L", "1"], ["-L", "2"], ["-L", "3"], ["-0"], ["--zip64"], ["-L", "1", "--zip64"], ["-0", "--zip64"]]
    for case in range(cases):
        base = os.path.join(WORK, f"w{case}")
        shutil.rmtree(base, ignore_errors=True)
        os.makedirs(base)
        make_tree(os.path.join(base, "tree"), rng, case)
        option = flags[case % len(flags)]
        archive = os.path.join(base, "a.zip")
        piped = case % 3 == 0
        if piped:
            code, out, err = run([ZIP, "-c", "-f", "-", "tree"] + option, cwd=base)
            if code == 0:
                with open(archive, "wb") as h:
                    h.write(out)
        else:
            code, _, err = run([ZIP, "-c", "-f", "a.zip", "tree"] + option, cwd=base)
        label = " ".join(option) or "default"
        if code != 0:
            fail(f"write {case} {option} rc={code} {err[:200]}")
            continue
        expected = tree_view(os.path.join(base, "tree"), "tree")
        try:
            seen = zip_view(archive)
        except Exception as error:
            fail(f"write {case} {option}: zipfile {error}")
            continue
        if seen != expected:
            fail(f"write {case} {option}: zipfile view differs {sorted(set(seen.items()) ^ set(expected.items()))[:4]}")
            continue
        with zipfile.ZipFile(archive) as z:
            infos = z.infolist()
            descriptors = all(i.flag_bits & 8 for i in infos)
            zip64 = "--zip64" in option
            versions = all((i.extract_version >= 45) == zip64 for i in infos)
            stored = all(i.compress_type == zipfile.ZIP_STORED for i in infos if "-0" in option or i.file_size == 0 or i.is_dir())
            deflated = "-0" in option or all(i.compress_type == zipfile.ZIP_DEFLATED for i in infos if i.file_size > 0 and not i.is_dir() and not stat.S_ISLNK(i.external_attr >> 16))
        if not (descriptors and versions and stored and deflated):
            fail(f"write {case} {option}: flags/version/method {descriptors} {versions} {stored} {deflated}")
            continue
        bump("write: zipfile reads the sample's archive (" + label + (", piped" if piped else "") + ")")
        if UNZIP:
            code, out, err = run([UNZIP, "-tq", archive])
            if code != 0:
                fail(f"write {case} unzip -t rc={code} {out[:200]}")
                continue
            bump("write: unzip -t accepts it")
        # And the sample's own extraction restores the tree exactly.
        out = os.path.join(base, "out")
        os.makedirs(out)
        code, _, err = run([ZIP, "-x", "-f", archive, "-C", out])
        if code != 0 or snapshot(os.path.join(out, "tree")) != snapshot(os.path.join(base, "tree")) or snapshot_dir(os.path.join(out, "tree")) != snapshot_dir(os.path.join(base, "tree")):
            fail(f"write {case} round trip rc={code} {err[:200]}")
            continue
        bump("write: sample round trip restores data, modes, links and mtimes")
        shutil.rmtree(base)


# ---------------------------------------------------------------- zipfile writes, sample reads
class Unseekable(io.RawIOBase):
    """A write-only stream without tell/seek: zipfile then writes data descriptors."""
    def __init__(self):
        self.parts = []
    def writable(self):
        return True
    def write(self, b):
        self.parts.append(bytes(b))
        return len(b)
    def value(self):
        return b"".join(self.parts)


def py_archive(rng, case, streamed, force64):
    # (name, data or None for a directory, method, level, mode, date_time)
    members = []
    for index in range(rng.randrange(1, 10)):
        name = rng.choice(["a", "b/c", "dir/sub/f", "ü名/x", "e"]) + str(index)
        when = (2020 + case % 7, 1 + case % 12, 1 + case % 28, case % 24, case % 60, (case * 2) % 60)
        if rng.random() < 0.15:
            members.append((name + "/", None, zipfile.ZIP_STORED, 0, 0o755, when))
            continue
        size = rng.choice([0, 0, 1, 100, 32768, 70000, rng.randrange(0, 150000)])
        method = rng.choice([zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED, zipfile.ZIP_DEFLATED])
        members.append((name, content(rng, size), method, rng.randrange(0, 10), rng.choice([0o644, 0o600, 0o755]), when))
    sink = Unseekable() if streamed else io.BytesIO()
    with zipfile.ZipFile(sink, "w") as z:
        if rng.random() < 0.3:
            # zipfile cannot reopen the second (it takes the comment's
            # signature for the end record); the sample checks the length.
            z.comment = rng.choice([b"comment", b"PK\x05\x06 looks like an end record", b"x" * rng.randrange(1, 300)])
        for name, data, method, level, mode, when in members:
            info = zipfile.ZipInfo(name, date_time=when)
            info.create_system = 3
            if data is None:
                info.external_attr = (0o40000 | mode) << 16 | 0x10
                z.writestr(info, b"")
                continue
            info.compress_type = method
            info.external_attr = (0o100000 | mode) << 16
            if method == zipfile.ZIP_DEFLATED:
                # Python 3.13 renamed _compresslevel to compress_level.
                for attribute in ("compress_level", "_compresslevel"):
                    try:
                        setattr(info, attribute, level)
                    except AttributeError:
                        pass
            with z.open(info, "w", force_zip64=force64) as h:
                h.write(data)
    raw = sink.value() if streamed else sink.getvalue()
    return raw, members


def read_group(rng):
    cases = 12 if QUICK else 60
    for case in range(cases):
        streamed = case % 2 == 1
        force64 = case % 3 == 2
        raw, members = py_archive(rng, case, streamed, force64)
        base = os.path.join(WORK, f"r{case}")
        shutil.rmtree(base, ignore_errors=True)
        os.makedirs(base)
        archive = os.path.join(base, "p.zip")
        with open(archive, "wb") as h:
            h.write(raw)
        label = ("streamed" if streamed else "seekable") + (", forced ZIP64" if force64 else "")
        code, out, err = run([ZIP, "-t", "-f", archive])
        names = [m[0] for m in members]
        # zipfile keeps duplicate names; so does the listing.
        if code != 0 or out.decode("utf-8", "surrogateescape").split("\n")[:-1] != names:
            fail(f"read {case} ({label}) list rc={code} {err[:200]}")
            continue
        bump("read: listing matches zipfile (" + label + ")")
        if len(set(n.rstrip("/") for n in names)) != len(names):
            continue
        out_dir = os.path.join(base, "out")
        os.makedirs(out_dir)
        code, _, err = run([ZIP, "-x", "-f", archive, "-C", out_dir])
        ok = code == 0
        for name, data, method, level, mode, when in members if ok else []:
            path = os.path.join(out_dir, name)
            st = os.lstat(path)
            if data is None:
                ok = ok and stat.S_ISDIR(st.st_mode)
            else:
                ok = ok and stat.S_ISREG(st.st_mode) and open(path, "rb").read() == data
            ok = ok and stat.S_IMODE(st.st_mode) == mode and int(st.st_mtime) == calendar.timegm(when + (0, 0, 0))
        if not ok:
            fail(f"read {case} ({label}) extract rc={code} {err[:200]}")
            continue
        bump("read: extraction matches the data, modes and times zipfile wrote (" + label + ")")
        shutil.rmtree(base)


def many_group():
    # More than 65535 entries needs the ZIP64 end records in both directions.
    count = 65600
    base = os.path.join(WORK, "many")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(os.path.join(base, "m"))
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for index in range(count):
            z.writestr(f"m/{index}", b"" if index % 7 else str(index).encode())
    archive = os.path.join(base, "py.zip")
    with open(archive, "wb") as h:
        h.write(buf.getvalue())
    code, out, err = run([ZIP, "-t", "-f", archive], timeout=120)
    if code == 0 and out.decode().split("\n")[:-1] == [f"m/{i}" for i in range(count)]:
        bump("many: sample lists zipfile's 65600-entry ZIP64 archive")
    else:
        fail(f"many: list rc={code} {err[:200]}")
    for index in range(count):
        with open(os.path.join(base, "m", f"{index:05d}"), "wb") as h:
            if index % 1000 == 0:
                h.write(b"x" * index)
    ours = os.path.join(base, "ours.zip")
    code, _, err = run([ZIP, "-c", "-f", ours, "m"], cwd=base, timeout=120)
    try:
        with zipfile.ZipFile(ours) as z:
            infos = z.infolist()
            ok = code == 0 and len(infos) == count + 1 and z.testzip() is None and z.read("m/02000") == b"x" * 2000
            with open(ours, "rb") as h:
                h.seek(-22, 2)
                tail = h.read()
            ok = ok and tail[:4] == b"PK\x05\x06" and struct.unpack("<H", tail[10:12])[0] == 0xFFFF
    except Exception as error:
        ok = False
        err = str(error).encode()
    if ok:
        bump("many: zipfile reads the sample's 65601-entry archive (ZIP64 end records)")
    else:
        fail(f"many: write rc={code} {err[:200]}")
    shutil.rmtree(base)


# ---------------------------------------------------------------- refusals
def guard_group():
    base = os.path.join(WORK, "guard")
    shutil.rmtree(base, ignore_errors=True)
    outside = os.path.join(base, "outside")
    os.makedirs(outside)
    with open(os.path.join(outside, "keep"), "wb") as h:
        h.write(b"keep")
    def archive(entries, method=zipfile.ZIP_DEFLATED):
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", method) as z:
            for name, kind, value in entries:
                info = zipfile.ZipInfo(name)
                info.create_system = 3
                info.compress_type = method
                info.external_attr = ((0o120777 if kind == "l" else 0o100644) << 16)
                z.writestr(info, value)
        return buf.getvalue()
    def untouched():
        return os.listdir(outside) == ["keep"] and open(os.path.join(outside, "keep"), "rb").read() == b"keep"
    def patched(raw, offset_of, value):
        data = bytearray(raw)
        for at in offset_of(data):
            data[at:at + len(value)] = value
        return bytes(data)
    def headers(data, signature):
        at = -1
        while True:
            at = data.find(signature, at + 1)
            if at < 0:
                return
            yield at
    plain = archive([("a", "f", b"data" * 100)])
    def reversed_directory(raw):
        # The same members with the central headers in reverse order.
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            infos = z.infolist()
            start = z.start_dir
        end = raw.rindex(b"PK\x05\x06")
        directory = raw[start:end]
        headers, at = [], 0
        for info in infos:
            n, m, k = struct.unpack("<HHH", directory[at + 28:at + 34])
            headers.append(directory[at:at + 46 + n + m + k])
            at += 46 + n + m + k
        return raw[:start] + b"".join(reversed(headers)) + raw[end:]
    cases = [
        ("parent traversal", archive([("../outside/x", "f", b"x")]), None, 2),
        ("nested traversal", archive([("a/../../outside/x", "f", b"x")]), None, 2),
        ("absolute name", archive([("/abs", "f", b"x")]), None, 2),
        ("backslash name", archive([("a\\..\\b", "f", b"x")]), None, 2),
        # zipfile cuts names at NUL, so patch one in.
        ("NUL in name", patched(archive([("aQb", "f", b"x")]), lambda d: [a + 1 for a in headers(d, b"aQb")], b"\x00"), None, 2),
        ("archive symlink then member through it", archive([("s", "l", b"../outside"), ("s/x", "f", b"x")]), None, 2),
        ("absolute symlink target", archive([("s", "l", b"/etc")]), None, 2),
        ("existing symlinked parent", archive([("evil/x", "f", b"x")]), lambda out: os.symlink(outside, os.path.join(out, "evil")), 2),
        ("existing symlink leaf is replaced, not followed", archive([("keep", "f", b"new")]), lambda out: os.symlink(os.path.join(outside, "keep"), os.path.join(out, "keep")), 0),
        ("bzip2 method", archive([("a", "f", b"data")], zipfile.ZIP_BZIP2), None, 2),
        ("lzma method", archive([("a", "f", b"data")], zipfile.ZIP_LZMA), None, 2),
        # Set the encrypted bit in both headers.
        ("encrypted flag", patched(plain, lambda d: [a + 6 for a in headers(d, b"PK\x03\x04")] + [a + 8 for a in headers(d, b"PK\x01\x02")], b"\x01\x00"), None, 2),
        ("central CRC changed", patched(plain, lambda d: [a + 16 for a in headers(d, b"PK\x01\x02")], b"\x00\x00\x00\x00"), None, 2),
        ("stored size mismatch", patched(archive([("a", "f", b"data")], zipfile.ZIP_STORED), lambda d: [a + 24 for a in headers(d, b"PK\x01\x02")], b"\x05"), None, 2),
        ("local name differs", patched(plain, lambda d: [a + 30 for a in headers(d, b"PK\x03\x04")], b"b"), None, 2),
        ("prefix before the archive", b"junk" + plain, None, 2),
        ("not a zip", b"hello world\n" * 10, None, 2),
        ("empty file", b"", None, 2),
        ("empty archive", archive([]), None, 0),
        ("central order differs from local order", reversed_directory(archive([(f"m{i}", "f", bytes([i]) * i) for i in range(9)])), None, 0),
        ("two headers share one local header", patched(archive([("a", "f", b"x"), ("b", "f", b"x")]), lambda d: [list(headers(d, b"PK\x01\x02"))[1] + 42], b"\x00\x00\x00\x00"), None, 2),
    ]
    for label, raw, prepare, status in cases:
        out = os.path.join(base, "out")
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        if prepare:
            prepare(out)
        path = os.path.join(base, "g.zip")
        with open(path, "wb") as h:
            h.write(raw)
        code, _, err = run([ZIP, "-x", "-f", path, "-C", out])
        ok = code == status and untouched()
        if ok and status == 2 and "symlink" not in label:
            # Validation precedes output: nothing was written.
            ok = os.listdir(out) == []
        if ok and label.startswith("existing symlink leaf"):
            ok = not os.path.islink(os.path.join(out, "keep")) and open(os.path.join(out, "keep"), "rb").read() == b"new"
        if ok:
            bump("guard: " + label)
        else:
            fail(f"guard {label} rc={code} {err[:200]}")
    for argv in ([ZIP, "-t", "-f", "-"], [ZIP, "-t", "-L", "2", "-f", "x.zip"], [ZIP, "-c", "-0", "-L", "1", "-f", "x.zip", "a"], [ZIP, "-c", "-f", "x.zip"], [ZIP, "-x"]):
        code, _, _ = run(argv, cwd=base)
        if code == 2:
            bump("guard: usage errors exit 2")
        else:
            fail(f"guard usage {argv[1:]} rc={code}")
    shutil.rmtree(base)


# ---------------------------------------------------------------- fuzzing
def zipfile_accepts(raw):
    try:
        with zipfile.ZipFile(io.BytesIO(raw)) as z:
            return z.testzip() is None, z.namelist()
    except Exception:
        return False, None


def fuzz_group(rng):
    base = os.path.join(WORK, "fuzz")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(os.path.join(base, "src", "d"))
    with open(os.path.join(base, "src", "d", "text"), "wb") as h:
        h.write(b"lanius zip fuzz " * 40)
    with open(os.path.join(base, "src", "empty"), "wb") as h:
        pass
    with open(os.path.join(base, "src", "rand"), "wb") as h:
        h.write(rng.randbytes(300))
    seeds = []
    for option in ([], ["-0"], ["--zip64"]):
        code, out, err = run([ZIP, "-c", "-f", "-", "src"] + option, cwd=base)
        if code != 0:
            fail(f"fuzz seed {option} rc={code}")
            return
        seeds.append(("sample " + (" ".join(option) or "deflate"), out))
    raw, _ = py_archive(random.Random(7), 3, True, True)
    seeds.append(("zipfile streamed ZIP64", raw))
    path = os.path.join(base, "f.zip")
    def probe(data, label, extract=False):
        with open(path, "wb") as h:
            h.write(data)
        argv = [ZIP, "-t", "-f", path]
        if extract:
            out = os.path.join(base, "out")
            shutil.rmtree(out, ignore_errors=True)
            os.makedirs(out)
            argv = [ZIP, "-x", "-f", path, "-C", out]
        code, stdout, err = run(argv, timeout=20)
        if code not in (0, 2):
            fail(f"fuzz {label} rc={code} {err[:200]}")
            return None
        return code, stdout
    for name, raw in seeds:
        # Every truncation is a clean error: the end record is at the end.
        step = 1 if len(raw) < 4000 else max(1, len(raw) // 2000)
        clean = 0
        for cut in range(0, len(raw), step):
            got = probe(raw[:cut], f"{name} cut {cut}")
            if got is None:
                continue
            if got[0] != 2:
                fail(f"fuzz {name} truncated to {cut} accepted")
                continue
            clean += 1
        bump(f"fuzz: truncations rejected cleanly ({name})", clean)
        flips = 150 if QUICK else 600
        accepted = rejected = 0
        for index in range(flips):
            data = bytearray(raw)
            for _ in range(rng.choice([1, 1, 2, 4])):
                at = rng.randrange(len(data))
                data[at] ^= 1 << rng.randrange(8)
            data = bytes(data)
            got = probe(data, f"{name} flip {index}", extract=index % 10 == 0)
            if got is None:
                continue
            if got[0] == 0:
                # Accepted flips must be ones zipfile also reads the same way.
                ok, names = zipfile_accepts(data)
                if index % 10 != 0 and (not ok or got[1].decode("utf-8", "surrogateescape").split("\n")[:-1] != names):
                    kept = os.path.join(WORK, f"fuzz-disagree-{len(failures)}.zip")
                    with open(kept, "wb") as h:
                        h.write(data)
                    fail(f"fuzz {name} flip {index} accepted, zipfile ok={ok}; kept {kept}")
                    continue
                accepted += 1
            else:
                rejected += 1
        bump(f"fuzz: byte flips handled ({name})", accepted + rejected)
        counts[f"fuzz: byte flips rejected ({name})"] = rejected
    shutil.rmtree(base)


def big_group():
    # A sparse 4.2 GiB file: ZIP64 sizes in the descriptor and central header.
    base = os.path.join(WORK, "big")
    shutil.rmtree(base, ignore_errors=True)
    os.makedirs(base)
    size = (1 << 32) + 123457
    with open(os.path.join(base, "big"), "wb") as h:
        h.seek(size - 5)
        h.write(b"tail\n")
    archive = os.path.join(base, "big.zip")
    started = time.time()
    code, _, err = run([ZIP, "-c", "-L", "1", "-f", archive, "big"], cwd=base, timeout=280)
    ok = code == 0
    if ok:
        with zipfile.ZipFile(archive) as z:
            info = z.getinfo("big")
            ok = info.file_size == size and info.extract_version >= 45
            crc = 0
            with z.open(info) as h:
                while True:
                    block = h.read(1 << 24)
                    if not block:
                        break
                    crc = zlib.crc32(block, crc)
            ok = ok and crc == info.CRC
    if ok:
        bump(f"big: zipfile reads a 4 GiB + 123457 B member ({time.time() - started:.0f} s)")
    else:
        fail(f"big rc={code} {err[:200]}")
    shutil.rmtree(base)


rng = random.Random(20261101)
guard_group()
write_group(rng)
read_group(rng)
fuzz_group(rng)
if not QUICK:
    many_group()
if "--big" in sys.argv:
    big_group()
total = 0
for key in sorted(counts):
    print(f"{counts[key]:6d}  {key}")
    if "rejected (" not in key:
        total += counts[key]
print(f"{total:6d}  total agreeing cases; {len(failures)} failures")
sys.exit(1 if failures else 0)
