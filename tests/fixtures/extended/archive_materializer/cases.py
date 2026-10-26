"""Independent archive producers and explicitly declared namespace fixtures.

Python's tarfile/zipfile/zlib are test producers only. Extraction always runs in
the compiled Lanius owner; the host never supplies materializer behavior.
"""
import io
import os
import socket
import stat
import struct
import tarfile
import zipfile
import zlib

DATA = b"\0\xff\x80a\r\n"
LARGE = bytes(range(256)) * 40 + b"bounded archive data\n" * 300
OLD = b"untouched-existing\0\xff"


def file(name, data=DATA, method="stored", **options):
    return dict(name=name if isinstance(name, bytes) else name.encode(),
                data=data, kind="file", method=method, **options)


def directory(name):
    return dict(name=name if isinstance(name, bytes) else name.encode(), data=b"", kind="dir", method="stored")


def ustar(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT,
                      encoding="utf-8", errors="surrogateescape") as archive:
        for entry in entries:
            item = tarfile.TarInfo(entry["name"].decode("utf-8", "surrogateescape"))
            item.mode, item.uid, item.gid, item.mtime = 0o777, 123, 456, 123456
            item.type = tarfile.DIRTYPE if entry["kind"] == "dir" else tarfile.REGTYPE
            item.size = len(entry["data"])
            archive.addfile(item, io.BytesIO(entry["data"]))
        end = archive.offset
    # Keep the required two zero blocks; omit tarfile's optional record padding.
    return output.getvalue()[:end + 1024]


def python_zip(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for entry in entries:
            item = zipfile.ZipInfo(entry["name"].decode("ascii"))
            item.create_system, item.create_version, item.extract_version = 3, 20, 20
            mode = 0o40777 if entry["kind"] == "dir" else 0o100777
            item.external_attr = mode << 16 | (16 if entry["kind"] == "dir" else 0)
            archive.writestr(item, entry["data"], compress_type=zipfile.ZIP_DEFLATED)
    return output.getvalue()


def raw_zip(entries):
    """Classic records around established zlib output; no new codec or CRC."""
    output, central = bytearray(), bytearray()
    for entry in entries:
        data, name, method = entry["data"], entry["name"], entry["method"]
        compressed, number = data, 0
        if method != "stored":
            number = 8
            compressor = zlib.compressobj(wbits=-15, strategy=zlib.Z_FIXED if method == "fixed" else zlib.Z_DEFAULT_STRATEGY)
            compressed = compressor.compress(data) + compressor.flush()
            if method == "fixed" and data:
                assert compressed[0] >> 1 & 3 == 1, "fixture did not produce a fixed block"
            if method == "broken":
                compressed = b"\x07"  # Reserved DEFLATE block type, not a decoder implementation.
        checksum = zlib.crc32(data) ^ int(entry.get("bad_crc", False))
        offset = len(output)
        needed = 20 if number == 8 or entry["kind"] == "dir" else 10
        output.extend(struct.pack("<I5H3I2H", 0x04034B50, needed, 0, number, 0, 0,
                                  checksum, len(compressed), len(data), len(name), 0))
        output.extend(name)
        output.extend(compressed)
        mode = 0o40777 if entry["kind"] == "dir" else 0o100777
        attributes = mode << 16 | (16 if entry["kind"] == "dir" else 0)
        central.extend(struct.pack("<I6H3I5H2I", 0x02014B50, 0x0314, needed, 0, number, 0, 0,
                                   checksum, len(compressed), len(data), len(name), 0, 0, 0, 0, attributes, offset))
        central.extend(name)
    start = len(output)
    output.extend(central)
    output.extend(struct.pack("<I4H2IH", 0x06054B50, 0, 0, len(entries), len(entries), len(central), start, 0))
    return bytes(output)


def manifest(entries):
    expected = {}
    for entry in entries:
        name = entry["name"].removesuffix(b"/") if entry["kind"] == "dir" else entry["name"]
        components = name.split(b"/")
        for length in range(1, len(components)):
            expected[b"/".join(components[:length])] = ("dir", b"")
        expected[name] = (entry["kind"], entry["data"])
    return expected


def snapshot(root):
    """lstat every object; never follow a link or open FIFO/socket/device data."""
    root = os.fsencode(root)
    found = {}
    def visit(directory, prefix=b""):
        for name in sorted(os.listdir(directory)):
            path, relative = os.path.join(directory, name), prefix + name
            value = os.lstat(path)
            kind = "dir" if stat.S_ISDIR(value.st_mode) else "file" if stat.S_ISREG(value.st_mode) else "symlink" if stat.S_ISLNK(value.st_mode) else "fifo" if stat.S_ISFIFO(value.st_mode) else "socket" if stat.S_ISSOCK(value.st_mode) else "other"
            data = open(path, "rb").read() if kind == "file" else os.readlink(path) if kind == "symlink" else b""
            found[relative] = dict(kind=kind, data=data.hex(), mode=stat.S_IMODE(value.st_mode),
                                   uid=value.st_uid, gid=value.st_gid, inode=value.st_ino, links=value.st_nlink)
            if kind == "dir":
                visit(path, relative + b"/")
    visit(root)
    return found


def assert_manifest(root, entries, *, prior=None):
    actual, expected = snapshot(root), manifest(entries)
    for name, (kind, data) in expected.items():
        assert name in actual and actual[name]["kind"] == kind, (name, actual)
        assert actual[name]["data"] == data.hex(), (name, actual[name], data)
        if prior is None or name not in prior:
            assert actual[name]["mode"] == (0o700 if kind == "dir" else 0o600), (name, actual[name])
    assert set(actual) == set(expected) | set(prior or {}), (actual, expected, prior)
    if prior:
        for name, value in prior.items():
            before, after = dict(value), dict(actual[name])
            if value["kind"] == "dir":
                # Creating subdirectories legitimately changes a parent's nlink.
                before.pop("links"); after.pop("links")
            assert after == before, ("preexisting object changed", name, actual[name], value)


def setup_conflict(cwd, name, kind):
    target, outside = os.path.join(os.fsencode(cwd), b"root", name), os.path.join(os.fsencode(cwd), b"outside")
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if kind == "file":
        open(target, "wb").write(OLD)
    elif kind == "symlink":
        os.symlink(outside, target)
    elif kind == "fifo":
        os.mkfifo(target)
    elif kind == "socket":
        owner = socket.socket(socket.AF_UNIX)
        owner.bind(target)
        owner.close()
    elif kind == "hardlink":
        os.link(outside, target)
    elif kind == "dir":
        os.mkdir(target, 0o751)
    else:
        raise AssertionError(kind)


def controls():
    count = 0
    entries = [file("a/b", DATA), directory("a/")]
    tar = ustar(entries)
    with tarfile.open(fileobj=io.BytesIO(tar)) as archive:
        assert archive.getnames() == ["a/b", "a"]
        assert archive.extractfile("a/b").read() == DATA
    count += 1
    for method in ("stored", "fixed", "dynamic"):
        values = [file("a/b", LARGE, method), directory("a/")]
        encoded = raw_zip(values)
        with zipfile.ZipFile(io.BytesIO(encoded)) as archive:
            assert archive.read("a/b") == LARGE and archive.read("a/") == b""
        count += 1
    encoded = python_zip([file("dynamic", LARGE)])
    with zipfile.ZipFile(io.BytesIO(encoded)) as archive:
        item = archive.getinfo("dynamic")
        at = item.header_offset + 30 + len(item.filename.encode()) + len(item.extra)
        assert encoded[at] >> 1 & 3 == 2, "Python zipfile fixture needs an actual dynamic block"
        assert archive.read("dynamic") == LARGE
    count += 1
    assert manifest(entries) == {b"a": ("dir", b""), b"a/b": ("file", DATA)}
    count += 1
    return count
