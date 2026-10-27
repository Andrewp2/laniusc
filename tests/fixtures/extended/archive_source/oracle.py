"""Independent finite TAR/ZIP fixtures for the actual Lanius Prepared owner.

This is test transport, not a library serialization API. Archives are built by
Python's tarfile/zipfile or explicit public-format records; their destinations,
payloads, failures, source ownership and host inactivity are checked separately.
"""
import io
import os
from pathlib import Path
import select
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import zipfile
import zlib

import ledger

MAGIC = 1095910227
U64 = (1 << 64) - 1
DEFAULTS = dict(max_archive=32760, max_entry=4096, max_total=16384,
                zip_work=1000000, metadata_work=1000000, max_owned_bytes=1048576,
                max_entries=8, max_nodes=16, max_path_bytes=255,
                max_component_bytes=255, max_depth=16,
                max_stored_path_bytes=1024, max_work=1000000)
FIELDS = tuple(DEFAULTS)


def signed32(value):
    assert 0 <= value <= 0xffffffff, value
    return value if value < 0x80000000 else value - (1 << 32)


def signed64(value):
    return value if value < (1 << 63) else value - (1 << 64)


def manifest(name, data=b"", directory=False, **metadata):
    return dict(name=name, data=data, directory=directory, **metadata)


def tar_archive(entries):
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w", format=tarfile.USTAR_FORMAT,
                      encoding="utf-8", errors="surrogateescape") as archive:
        for entry in entries:
            item = tarfile.TarInfo(entry["name"].decode("utf-8", "surrogateescape"))
            item.type = entry.get("tar_type", tarfile.DIRTYPE if entry["directory"] else tarfile.REGTYPE)
            item.size = len(entry["data"])
            if item.type in (tarfile.LNKTYPE, tarfile.SYMTYPE):
                item.linkname = "destination"
            archive.addfile(item, io.BytesIO(entry["data"]))
        # TarFile.close pads to its blocking factor. Retain exactly two complete
        # footer records, so a valid one-member archive fits the strided fixture.
        end = output.tell()
    result = output.getvalue()[:end + 1024]
    assert len(result) % 512 == 0 and result[end:] == bytes(1024)
    return result


def tar_patch(archive, offset, field, value):
    result = bytearray(archive)
    start, count = field
    assert len(value) == count
    result[offset + start:offset + start + count] = value
    result[offset + 148:offset + 156] = b"        "
    checksum = sum(result[offset:offset + 512])
    result[offset + 148:offset + 156] = f"{checksum:06o}\0 ".encode("ascii")
    return bytes(result)


def zip_archive(entries):
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w") as archive:
        for entry in entries:
            item = zipfile.ZipInfo(entry["name"].decode("utf-8"))
            item.create_system = entry.get("creator", 3)
            item.external_attr = entry.get("attrs", (0o40755 << 16) | 0x10 if entry["directory"] else 0o100644 << 16)
            item.compress_type = entry.get("method", zipfile.ZIP_STORED)
            item.extra = entry.get("extra", b"")
            archive.writestr(item, entry["data"])
    return output.getvalue()


def zip_raw(entries):
    """Explicit APPNOTE records allow byte names and independent creator fields."""
    output, central = bytearray(), bytearray()
    for entry in entries:
        name, data = entry["name"], entry["data"]
        method = entry.get("method", 0)
        if method == 8:
            encoder = zlib.compressobj(wbits=-15)
            encoded = encoder.compress(data) + encoder.flush()
        else:
            assert method == 0
            encoded = data
        crc = entry.get("crc", zlib.crc32(data))
        local_extra, extra = entry.get("local_extra", b""), entry.get("extra", b"")
        offset = len(output)
        flags = entry.get("flags", 0)
        output.extend(struct.pack("<I5H3I2H", 0x04034b50, 20, flags, method, 0, 0,
                                  crc, len(encoded), len(data), len(name), len(local_extra)))
        output.extend(name + local_extra + encoded)
        creator = entry.get("made_by", (3 << 8) | 20)
        attrs = entry.get("attrs", (0o40755 << 16) | 0x10 if entry["directory"] else 0o100644 << 16)
        central.extend(struct.pack("<I6H3I5H2I", 0x02014b50, creator, 20, flags, method, 0, 0,
                                   crc, len(encoded), len(data), len(name), len(extra), 0, 0, 0,
                                   attrs, offset))
        central.extend(name + extra)
    directory = len(output)
    output.extend(central)
    output.extend(struct.pack("<I4H2IH", 0x06054b50, 0, 0, len(entries), len(entries),
                              len(central), directory, 0))
    return bytes(output)


def extra(identifier, data):
    return struct.pack("<HH", identifier, len(data)) + data


def namespace(entries):
    """Expected first-seen path tree; deliberately no planner resource algorithm."""
    rows, by_path, members = [], {}, []
    for ordinal, entry in enumerate(entries):
        path = entry["name"][:-1] if entry["directory"] and entry["name"].endswith(b"/") else entry["name"]
        pieces, parent = path.split(b"/"), -1
        for depth, component in enumerate(pieces, 1):
            prefix = b"/".join(pieces[:depth])
            final = depth == len(pieces)
            if prefix not in by_path:
                by_path[prefix] = len(rows)
                rows.append(dict(parent=parent, kind=int(entry["directory"]) if final else 1,
                                 explicit=int(final), ordinal=ordinal if final else -1,
                                 depth=depth, path=prefix, component=component))
            elif final:
                row = rows[by_path[prefix]]
                assert row["kind"] == 1 and entry["directory"] and not row["explicit"]
                row.update(explicit=1, ordinal=ordinal)
            parent = by_path[prefix]
        members.append(parent)
    return rows, members


def read_exact(fd, count, deadline):
    output = bytearray()
    while len(output) < count:
        remaining = deadline - time.monotonic()
        assert remaining > 0, ("archive probe read deadline", len(output), count)
        ready, _, _ = select.select([fd], [], [], remaining)
        assert ready, ("archive probe read timeout", len(output), count)
        chunk = os.read(fd, count - len(output))
        assert chunk, ("archive probe premature EOF", len(output), count)
        output.extend(chunk)
    return bytes(output)


def write_exact(fd, data, deadline):
    at = 0
    while at < len(data):
        remaining = deadline - time.monotonic()
        assert remaining > 0, ("archive probe write deadline", at, len(data))
        _, ready, _ = select.select([], [fd], [], remaining)
        assert ready, ("archive probe write timeout", at, len(data))
        count = os.write(fd, data[at:at + 4096])
        assert count > 0
        at += count


def read_frame(fd, deadline):
    prefix = read_exact(fd, 4, deadline)
    count, = struct.unpack("<I", prefix)
    assert count <= 32768, ("oversize archive probe frame", count)
    body = read_exact(fd, count, deadline)
    return body, prefix + body


def parse_header(body):
    assert len(body) >= 160
    values = struct.unpack_from("<20Q", body)
    assert values[0:2] == (MAGIC, 1)
    names = ("magic", "phase", "pid", "cause", "detail", "ordinal", "length", "stride", "start",
             "node_width", "member_width", "reserved", "members", "node_count", "total", "metadata",
             "work", "sealed", "live", "verify")
    header = dict(zip(names, values))
    for name in ("ordinal", "start"):
        header[name] = signed32(header[name])
    header["stride"] = signed64(header["stride"])
    at, nodes, members = 160, [], []
    for _ in range(header["node_count"]):
        assert at + 56 <= len(body)
        parent, kind, explicit, ordinal, depth, plen, clen = struct.unpack_from("<7Q", body, at)
        at += 56
        assert plen + clen <= len(body) - at
        nodes.append(dict(parent=signed32(parent), kind=kind, explicit=explicit,
                          ordinal=signed32(ordinal), depth=depth, path=body[at:at + plen],
                          component=body[at + plen:at + plen + clen]))
        at += plen + clen
    for _ in range(header["members"]):
        assert at + 64 <= len(body)
        node, kind, tag, size, compressed, stride, creator, attrs = struct.unpack_from("<8Q", body, at)
        members.append(dict(node=node, kind=kind, tag=tag, size=size, compressed=compressed,
                            stride=signed64(stride), creator=creator, attrs=attrs))
        at += 64
    assert at == len(body), (at, len(body))
    return header, nodes, members


class Suite:
    def __init__(self, executable, group):
        self.executable = Path(executable).resolve()
        self.directory = Path(tempfile.mkdtemp(prefix=f"lanius-archive-source-{group}-"))
        self.profile = ledger.TRUSTED.verified_sites(self.executable, self.directory)
        self.deadline = time.monotonic() + 75
        self.count = 0
        print(f"evidence={self.directory}", flush=True)

    def run(self, label, archive, entries=(), *, format=0, layout=0, verify=True,
            invalid=0, limits=None, error=None, no_alloc=False, injection=None,
            payload_errors=None, baseline_attempts=None):
        assert time.monotonic() < self.deadline, "archive-source group deadline"
        assert len(archive) <= 32760 and (layout != 2 or len(archive) <= 4090)
        settings = dict(DEFAULTS, **(limits or {}))
        zip_metadata = []
        if format == 1 and error is None:
            with zipfile.ZipFile(io.BytesIO(archive)) as independent:
                zip_metadata = independent.infolist()
            assert len(zip_metadata) == len(entries)
        words = [format, layout, int(verify), len(archive), invalid] + [settings[name] for name in FIELDS]
        request = struct.pack("<18Q", *(value & U64 for value in words)) + archive
        directory = self.directory / f"{self.count:03d}-{label}"
        directory.mkdir()
        cwd = directory / "guard"
        cwd.mkdir()
        (cwd / "sentinel").write_bytes(b"unchanged\0\xff")
        (cwd / "directory").mkdir()
        snapshot = sorted((str(path.relative_to(cwd)), path.read_bytes() if path.is_file() else None)
                          for path in cwd.rglob("*"))
        trace = directory / "syscalls.log"
        command = ["strace", "--kill-on-exit", "-qq", "-xx", "-i", "-s", "4096",
                   "-o", str(trace), "-e", "trace=" + ledger.TRACE]
        if injection is not None:
            command += ["-e", f"inject=mmap:error=ENOMEM:when={injection}"]
        command.append(str(self.executable))
        (directory / "request.bin").write_bytes(request)
        (directory / "command.txt").write_text(repr(command) + "\n")
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, cwd=cwd)
        deadline = min(self.deadline, time.monotonic() + 7)
        emitted = bytearray()
        try:
            write_exact(process.stdin.fileno(), request, deadline)
            body, raw = read_frame(process.stdout.fileno(), deadline)
            emitted.extend(raw)
            header, nodes, members = parse_header(body)
            assert header["pid"] > 0 and header["length"] == len(archive), header
            assert (header["stride"] == 1) if layout != 2 else (header["stride"] not in (0, 1)), header
            expected_start = (0, 7, 3)[layout]
            if invalid == 1:
                expected_start = -1
            if invalid == 3:
                expected_start = 0x7fffffff
            assert header["start"] == expected_start, header
            if error is None:
                assert header["cause"] == 0 and header["sealed"] == header["live"] == 1, header
                expected_nodes, expected_members = namespace(entries)
                assert nodes == expected_nodes, (label, nodes, expected_nodes)
                assert len(members) == len(entries), (label, members, entries)
                assert header["total"] == sum(len(entry["data"]) for entry in entries), header
                for ordinal, (member, entry) in enumerate(zip(members, entries)):
                    assert member["node"] == expected_members[ordinal]
                    assert member["kind"] == int(entry["directory"]) and member["tag"] == format, member
                    assert member["size"] == len(entry["data"]) and member["stride"] == header["stride"], member
                    if format == 0:
                        assert member["compressed"] == len(entry["data"]) and member["creator"] == member["attrs"] == 0
                    else:
                        assert member["compressed"] == zip_metadata[ordinal].compress_size, member
                        assert member["creator"] == entry.get("made_by", (entry.get("creator", 3) << 8) | 20), member
                        assert member["attrs"] == entry.get("attrs", (0o40755 << 16) | 0x10 if entry["directory"] else 0o100644 << 16), member
                expected_reserve = (settings["max_nodes"] * header["node_width"] + settings["max_stored_path_bytes"]
                                    + settings["max_entries"] * (4 + header["member_width"]))
                assert header["reserved"] == expected_reserve, (header, expected_reserve)
                expected_metadata = sum(len(entry["name"]) * 2 + 1 for entry in entries)
                if format == 1:
                    expected_metadata = sum(4 * (len(entry.get("extra", b"")) +
                                                 len(entry.get("local_extra", entry.get("extra", b""))))
                                            + len(entry["name"]) + 1 for entry in entries)
                assert header["metadata"] == expected_metadata, (header, expected_metadata)
            else:
                assert (header["cause"], header["detail"]) == error[:2], (label, header, error)
                if len(error) == 3 and error[2] is not None:
                    assert header["ordinal"] == error[2], (label, header, error)
                assert header["live"] == header["sealed"] == 0 and not nodes and not members, header
            prefix = self.checkpoint(trace, emitted, deadline)
            admitted = ledger.source(prefix, self.profile)
            ledger.no_host_effects(admitted["events"])
            ledger.process_owners(header["pid"], admitted["live"])
            assert sum(admitted["live"].values()) == (header["reserved"] if error is None else 0), (header, admitted)
            if no_alloc:
                assert not admitted["attempts"], (label, admitted)
            if injection is not None:
                reached = [item for item in admitted["events"] if "INJECTED" in item["result"]]
                assert len(reached) == 1 and reached[0]["name"] == "mmap" and reached[0]["ordinal"] == injection, reached
                assert reached[0]["result"].split()[:2] == ["-1", "ENOMEM"], reached
                actual = admitted["attempts"]
                assert len(actual) <= len(baseline_attempts)
                for index, item in enumerate(actual):
                    old = baseline_attempts[index]
                    assert (item["ip"], item["args"], item["ordinal"]) == (old["ip"], old["args"], old["ordinal"]), (item, old)
                assert actual[-1]["ordinal"] == injection and "INJECTED" in actual[-1]["result"], actual
            write_exact(process.stdin.fileno(), b"A", deadline)
            if error is None and verify:
                for index, entry in enumerate(entries):
                    payload, raw = read_frame(process.stdout.fileno(), deadline)
                    emitted.extend(raw)
                    assert len(payload) >= 24
                    ordinal, code, count = struct.unpack_from("<3Q", payload)
                    assert ordinal == index and count == len(payload) - 24, payload
                    expected_error = (payload_errors or {}).get(index, 0)
                    assert code == expected_error, (label, index, code, expected_error)
                    assert payload[24:] == (b"" if code else entry["data"]), (label, index, payload)
            released, raw = read_frame(process.stdout.fileno(), deadline)
            emitted.extend(raw)
            assert released == struct.pack("<3Q", MAGIC, 3, header["pid"]), released
            prefix = self.checkpoint(trace, emitted, deadline)
            final = ledger.source(prefix, self.profile)
            ledger.no_host_effects(final["events"])
            assert not final["live"], ("source owner survived explicit destroy", final)
            ranges = ledger.process_owners(header["pid"], {})
            for pointer, count in admitted["live"].items():
                assert not any(start < pointer + count and pointer < end for start, end in ranges), (
                    "destroyed source mapping still present in process", pointer, count, ranges)
            # The trusted final ledger independently checks matching release size,
            # address, verified post-IP and allocation flags before process exit.
            ledger.TRUSTED.source_maps(prefix, self.profile, directory)
            write_exact(process.stdin.fileno(), b"A", deadline)
            process.stdin.close()
            process.stdin = None
            rest, stderr = process.communicate(timeout=max(0.01, deadline - time.monotonic()))
            assert process.returncode == 0 and not rest and not stderr, (process.returncode, rest, stderr)
            assert sorted((str(path.relative_to(cwd)), path.read_bytes() if path.is_file() else None)
                          for path in cwd.rglob("*")) == snapshot, "archive preparation changed host namespace"
            (directory / "stdout.bin").write_bytes(emitted)
            (directory / "stderr.bin").write_bytes(stderr)
            self.count += 1
            return dict(header=header, nodes=nodes, members=members, admitted=admitted, final=final)
        except BaseException:
            (directory / "stdout-prefix.bin").write_bytes(emitted)
            if process.poll() is None:
                process.kill()
            try:
                extra, stderr = process.communicate(timeout=2)
                (directory / "stdout-tail.bin").write_bytes(extra)
                (directory / "stderr.bin").write_bytes(stderr)
            except (ValueError, subprocess.TimeoutExpired):
                pass
            print(f"FAILED label={label} evidence={directory}", file=sys.stderr, flush=True)
            raise

    @staticmethod
    def checkpoint(trace, output, deadline):
        while True:
            try:
                return ledger.output_prefix(trace.read_text(), bytes(output))
            except (ledger.CheckpointPending, FileNotFoundError):
                assert time.monotonic() < deadline, "trace checkpoint deadline"
                time.sleep(0.002)


def tar_cases(suite):
    binary = bytes(range(256)) + b"\0\xfftail"
    single = [manifest(b"raw-\xff", binary)]
    for layout in range(3):
        suite.run(f"binary-layout-{layout}", tar_archive(single), single, layout=layout)
    mixed = [manifest(b"d/a", b"a\0b"), manifest(b"d/", directory=True), manifest(b"d/b", b"second"), manifest(b"empty", b"")]
    suite.run("implied-explicit-coalescing", tar_archive(mixed), mixed, layout=1)
    suite.run("empty", tar_archive([]), [])
    long_path = b"p" * 90 + b"/" + b"n" * 90
    rows = [manifest(long_path, b"ustar-prefix")]
    suite.run("ustar-prefix", tar_archive(rows), rows)
    base = tar_archive([manifest(b"first", b"one"), manifest(b"later", b"two")])
    bad = bytearray(base); bad[1024] ^= 1
    suite.run("later-checksum", bytes(bad), error=(11, 4, 1))
    suite.run("later-missing-footer", base[:-1024], error=(11, 3, 2))
    bad = bytearray(base); bad[-1] = 1
    suite.run("later-footer", bytes(bad), error=(11, 3, 2))
    suite.run("trailing-garbage", base + b"x" + bytes(511), error=(11, 12, 2))
    directory = [manifest(b"hint/", directory=True)]
    hinted = tar_patch(tar_archive(directory), 0, (124, 12), b"00000000123\0")
    suite.run("directory-size-is-only-hint", hinted, directory)
    for name, detail in ((b"../escape", 4), (b"/absolute", 3), (b"x\\y", 3),
                         (b"C:drive", 3), (b"a//b", 4), (b"a/./b", 4)):
        rows = [manifest(b"first", b"one"), manifest(name, b"bad")]
        suite.run("late-path-" + str(detail) + "-" + name.hex(), tar_archive(rows), error=(9, detail, 1))
    for label, rows, detail in (
        ("duplicate", [manifest(b"x"), manifest(b"x")], 10),
        ("file-ancestor", [manifest(b"x"), manifest(b"x/y")], 11),
        ("directory-file", [manifest(b"x/", directory=True), manifest(b"x")], 11)):
        suite.run(label, tar_archive(rows), error=(9, detail, 1))
    for kind in (tarfile.LNKTYPE, tarfile.SYMTYPE, tarfile.CHRTYPE, tarfile.BLKTYPE, tarfile.FIFOTYPE, tarfile.CONTTYPE):
        rows = [manifest(b"first"), manifest(b"special", tar_type=kind)]
        suite.run("late-type-" + kind.hex(), tar_archive(rows), error=(10, 2, 1))


def zip_cases(suite):
    rows = [manifest(b"d/a", bytes(range(256)), method=zipfile.ZIP_DEFLATED),
            manifest(b"d/", directory=True), manifest(b"empty", b""), manifest(b"stored", b"raw\0\xff")]
    suite.run("zipfile-mixed", zip_archive(rows), rows, format=1)
    raw = [manifest(b"raw-\xff", b"\0\xffbinary", made_by=20, attrs=0x20)]
    for layout in range(3):
        suite.run(f"raw-layout-{layout}", zip_raw(raw), raw, format=1, layout=layout)
    suite.run("empty", zip_raw([]), [], format=1)
    extras = extra(0x5455, b"\x01" + bytes(4)) + extra(0x7875, b"\x01\x01\x07\x01\x08")
    # The ignored Unicode alternative must never become the destination path.
    extras += extra(0x7075, b"\x01" + bytes(4) + b"../../ignored")
    raw = [manifest(b"canonical", b"yes", extra=extras, local_extra=extras)]
    suite.run("allowed-ignored-extras", zip_raw(raw), raw, format=1)
    for label, patch, expected in (
        ("creator", dict(made_by=0x1314), (10, 1, 1)),
        ("symlink", dict(attrs=0o120777 << 16), (10, 2, 1)),
        ("volume", dict(made_by=20, attrs=0x08), (10, 2, 1)),
        ("contradictory", dict(attrs=0o40755 << 16), (10, 3, 1)),
        ("unsupported-extra", dict(extra=extra(0xcafe, b"")), (10, 4, 1)),
        ("duplicate-extra", dict(extra=extra(0x5455, b"\0") * 2), (10, 5, 1)),
        ("malformed-timestamp", dict(local_extra=extra(0x5455, b"\x01")), (10, 5, 1))):
        rows = [manifest(b"first", b"yes"), manifest(b"later", b"", **patch)]
        suite.run("late-profile-" + label, zip_raw(rows), format=1, error=expected)
    rows = [manifest(b"d/", b"not-empty", directory=True)]
    suite.run("directory-data", zip_raw(rows), format=1, error=(10, 6, 0))
    for name, detail in ((b"../escape", 4), (b"/absolute", 3), (b"C:drive", 3),
                         (b"x\\y", 3), (b"nul\0name", 3), (b"a//b", 4)):
        rows = [manifest(b"first"), manifest(name)]
        suite.run("late-path-" + name.hex(), zip_raw(rows), format=1, error=(9, detail, 1))
    for label, rows, detail in (
        ("duplicate", [manifest(b"x"), manifest(b"x")], 10),
        ("ancestor", [manifest(b"x"), manifest(b"x/y")], 11),
        ("directory-file", [manifest(b"x/", directory=True), manifest(b"x")], 11)):
        suite.run(label, zip_raw(rows), format=1, error=(9, detail, 1))
    rows = [manifest(b"first", b"yes"), manifest(b"later", b"data")]
    base = zip_raw(rows)
    bad = bytearray(base)
    central = bad.index(b"PK\x01\x02", bad.index(b"PK\x01\x02") + 4)
    bad[central + 16] ^= 1  # Later central CRC disagrees with its local record.
    suite.run("later-central-mismatch", bytes(bad), format=1, error=(12, 9, -1), no_alloc=True)
    corrupt = bytearray(base)
    corrupt[30 + len(rows[0]["name"])] ^= 1
    suite.run("declared-crc-is-not-payload-validation", bytes(corrupt), rows, format=1,
              payload_errors={0: 21})
    empty_dir = [manifest(b"empty/", directory=True, crc=1)]
    suite.run("empty-directory-crc-still-required", zip_raw(empty_dir), empty_dir, format=1,
              payload_errors={0: 21})


def limit_cases(suite):
    for format, build in ((0, tar_archive), (1, zip_raw)):
        rows = [manifest(b"d/a", b"1234"), manifest(b"d/", directory=True)]
        archive = build(rows)
        prefix = "tar-" if format == 0 else "zip-"
        normal = suite.run(prefix + "baseline", archive, rows, format=format)
        for invalid in (1, 2, 3):
            suite.run(prefix + "invalid-view-" + str(invalid), archive, format=format,
                      invalid=invalid, error=(1, 0, -1), no_alloc=True)
        for key in ("max_archive", "max_entry"):
            suite.run(prefix + "negative-" + key, archive, format=format,
                      limits={key: -1}, error=(2, 0, -1), no_alloc=True)
        for key, value in (("max_entries", -1), ("max_nodes", -1), ("max_component_bytes", 256)):
            suite.run(prefix + "invalid-plan-" + key, archive, format=format,
                      limits={key: value}, error=(9, 2, -1), no_alloc=True)
        suite.run(prefix + "exact-archive", archive, rows, format=format, limits={"max_archive": len(archive)})
        suite.run(prefix + "over-archive", archive, format=format,
                  limits={"max_archive": len(archive) - 1}, error=(3, 0, -1), no_alloc=True)
        suite.run(prefix + "exact-entry-total-count", archive, rows, format=format,
                  limits={"max_entry": 4, "max_total": 4, "max_entries": 2})
        for key, value, tar_error, zip_error in (
            ("max_entry", 3, (4, 0, 0), (12, 3, -1)),
            ("max_total", 3, (5, 0, 0), (12, 4, -1)),
            ("max_entries", 1, (4, 0, 1), (12, 3, -1))):
            suite.run(prefix + "over-" + key, archive, format=format, limits={key: value},
                      error=tar_error if format == 0 else zip_error, no_alloc=format == 1)
        for key, reported, detail in (("metadata_work", "metadata", 0), ("max_work", "work", 9)):
            exact = normal["header"][reported]
            suite.run(prefix + "exact-" + key, archive, rows, format=format, limits={key: exact})
            suite.run(prefix + "over-" + key, archive, format=format, limits={key: exact - 1},
                      error=(6, 0, None) if detail == 0 else (9, 9, None))
        reserve = normal["header"]["reserved"]
        suite.run(prefix + "exact-owned", archive, rows, format=format, limits={"max_owned_bytes": reserve})
        suite.run(prefix + "over-owned", archive, format=format,
                  limits={"max_owned_bytes": reserve - 1}, error=(7, 0, -1), no_alloc=True)
        for key, value, detail in (("max_path_bytes", 2, 3), ("max_component_bytes", 0, 4),
                                   ("max_depth", 1, 5), ("max_nodes", 1, 7),
                                   ("max_stored_path_bytes", 3, 8)):
            suite.run(prefix + "plan-bound-" + key, archive, format=format,
                      limits={key: value}, error=(9, detail, 0))
        empty = build([])
        suite.run(prefix + "zero-capacity-empty", empty, [], format=format,
                  limits={"max_entries": 0, "max_nodes": 0, "max_stored_path_bytes": 0,
                          "max_owned_bytes": 0, "max_entry": 0, "max_total": 0, "max_work": 1})
        suite.run(prefix + "empty-still-reserves-configured-capacities", empty, format=format,
                  limits={"max_owned_bytes": reserve - 1}, error=(7, 0, -1), no_alloc=True)
        if format == 1:
            suite.run("zip-structural-work-independent", archive, format=1,
                      limits={"zip_work": 0}, error=(12, 5, -1), no_alloc=True)
            suite.run("zip-metadata-work-independent", archive, format=1,
                      limits={"metadata_work": 0}, error=(6, 0, 0))


def allocation_cases(suite):
    reached = 0
    for format, build in ((0, tar_archive), (1, zip_raw)):
        rows = [manifest(b"d/a", b"abc"), manifest(b"d/", directory=True)]
        archive = build(rows)
        base = suite.run(f"baseline-{format}", archive, rows, format=format, verify=False)
        attempts = base["admitted"]["attempts"]
        expected_lengths = [DEFAULTS["max_nodes"] * base["header"]["node_width"],
                            DEFAULTS["max_stored_path_bytes"], DEFAULTS["max_entries"] * 4,
                            DEFAULTS["max_entries"] * base["header"]["member_width"]]
        assert [item["length"] for item in attempts] == expected_lengths, attempts
        for index, attempt in enumerate(attempts):
            suite.run(f"reached-source-oom-{format}-{index}", archive, format=format, verify=False,
                      injection=attempt["ordinal"], baseline_attempts=attempts,
                      error=(9, 12, -1) if index < 3 else (8, 0, -1))
            reached += 1
    print(f"reached-source-allocation-failures={reached}", flush=True)


def controls():
    count = ledger.controls()
    rows = [manifest(b"d/a", b"one\0\xff"), manifest(b"d/", directory=True), manifest(b"empty")]
    archive = tar_archive(rows)
    with tarfile.open(fileobj=io.BytesIO(archive), encoding="utf-8", errors="surrogateescape") as parsed:
        assert [item.name.rstrip("/").encode() for item in parsed] == [b"d/a", b"d", b"empty"]
    count += 1
    for build in (zip_archive, zip_raw):
        archive = build(rows)
        with zipfile.ZipFile(io.BytesIO(archive)) as parsed:
            assert [parsed.read(item) for item in parsed.infolist()] == [row["data"] for row in rows]
        count += 1
    nodes, members = namespace(rows)
    assert [row["path"] for row in nodes] == [b"d", b"d/a", b"empty"] and members == [1, 0, 2]
    assert nodes[0]["explicit"] == 1 and nodes[0]["ordinal"] == 1
    count += 1
    for method in (0, 8):
        data = [manifest(b"binary", bytes(range(256)), method=method)]
        with zipfile.ZipFile(io.BytesIO(zip_raw(data))) as parsed:
            assert parsed.read("binary") == data[0]["data"]
        count += 1
    corrupt = bytearray(zip_raw([manifest(b"crc", b"actual")]))
    corrupt[33] ^= 1
    with zipfile.ZipFile(io.BytesIO(corrupt)) as parsed:
        try:
            parsed.read("crc")
        except zipfile.BadZipFile:
            count += 1
        else:
            raise AssertionError("independent ZIP integrity control accepted changed payload")
    print(f"PASS archive-source all CPU controls={count}")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "controls":
        controls()
        return
    assert len(sys.argv) == 3, "oracle.py tar|zip|limits|allocations EXECUTABLE; or controls"
    group, executable = sys.argv[1:]
    functions = dict(tar=tar_cases, zip=zip_cases, limits=limit_cases, allocations=allocation_cases)
    assert group in functions
    suite = Suite(executable, group)
    functions[group](suite)
    print(f"PASS archive-source group={group} process-cases={suite.count}", flush=True)


if __name__ == "__main__":
    main()
