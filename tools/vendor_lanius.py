#!/usr/bin/env python3
"""Vendor a package's reachable Lanius sources using the compiler's resolver.

This is source distribution tooling. Module resolution and package validation
remain in `laniusc package lock`; library behavior remains in the copied sources.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time


REPOSITORY = Path(__file__).resolve().parent.parent
MAX_FILES = 4096
MAX_BYTES = 64 * 1024 * 1024
MAX_NOTICES = 64
MAX_PAYLOAD_BYTES = MAX_BYTES + MAX_NOTICES * 1024 * 1024 + 1024 * 1024
NOTICES = (
    "LICENSE-MIT",
    "LICENSE-APACHE",
    "data/unicode/17.0.0/LICENSE.txt",
    "third_party/rust-dec2flt/LICENSE-MIT",
    "third_party/rust-dec2flt/LICENSE-APACHE",
    "third_party/rust-dec2flt/NOTICE.md",
)


class VendorError(Exception):
    pass


def open_regular(path: Path):
    # O_NONBLOCK also applies through a symlink to a FIFO. Check the opened
    # descriptor before reading, so a notice cannot hang waiting for a writer.
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise VendorError(f"not a regular file: {path}")
        return os.fdopen(descriptor, "rb")
    except BaseException:
        os.close(descriptor)
        raise


def fnv1a64(data: bytes) -> str:
    digest = 0xCBF29CE484222325
    for byte in data:
        digest = ((digest ^ byte) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return f"fnv1a64:{digest:016x}"


def lock(compiler: str, manifest: Path, output: Path, deadline: float) -> dict:
    remaining = min(30.0, deadline - time.monotonic())
    if remaining <= 0:
        raise subprocess.TimeoutExpired(compiler, 0)
    result = subprocess.run(
        [compiler, "package", "lock", "--manifest", str(manifest), "-o", str(output)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=remaining,
        check=False,
    )
    if result.returncode:
        raise VendorError(
            "package lock failed: " + result.stderr.decode("utf-8", errors="replace").strip()
        )
    document = json.loads(output.read_text())
    if (document.get("version") != 1
            or document.get("inputs", {}).get("digest_algorithm") != "lanius-fnv1a64-v1"):
        raise VendorError("unsupported compiler package lock version or digest algorithm")
    return document


def relative_path(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if (not value or not path.parts or path.is_absolute() or ".." in path.parts
            or path.as_posix() != value or "\\" in value
            or any(ord(char) < 32 or ord(char) == 127 for char in value)):
        raise VendorError(f"invalid inventory path {value!r}")
    return path


def regular_file(root: Path, relative: str) -> Path:
    parts = relative_path(relative).parts
    current = root
    for part in parts:
        current /= part
        if current.is_symlink():
            raise VendorError(f"symlink in bundle path {relative!r}")
    if not current.is_file():
        raise VendorError(f"missing regular bundle file {relative!r}")
    return current


def verify(directory: Path) -> tuple[int, int]:
    if directory.is_symlink() or not directory.is_dir():
        raise VendorError("bundle must be an existing directory, not a symlink")
    with open_regular(regular_file(directory, "SHA256SUMS")) as handle:
        raw = handle.read(8 * 1024 * 1024 + 1)
    if len(raw) > 8 * 1024 * 1024:
        raise VendorError("bundle inventory exceeds 8 MiB")
    inventory = raw.decode("utf-8")
    entries: dict[str, str] = {}
    for line in inventory.splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise VendorError("invalid SHA256SUMS record")
        digest, name = match.groups()
        relative_path(name)
        if name == "SHA256SUMS" or name in entries:
            raise VendorError(f"duplicate or self-referential inventory path {name!r}")
        entries[name] = digest
        if len(entries) > MAX_FILES + MAX_NOTICES + 3:
            raise VendorError("bundle payload file limit exceeded")
    if not entries or list(entries) != sorted(entries):
        raise VendorError("inventory must be nonempty and sorted")
    actual: set[str] = set()
    total = 0
    for parent, directories, files in os.walk(directory, followlinks=False):
        for name in directories + files:
            path = Path(parent) / name
            if path.is_symlink():
                raise VendorError(f"symlink in bundle {path.relative_to(directory)}")
        for name in files:
            path = Path(parent) / name
            relative = path.relative_to(directory).as_posix()
            if relative == "SHA256SUMS":
                continue
            actual.add(relative)
            if relative not in entries:
                raise VendorError(f"unlisted bundle file {relative!r}")
            digest = hashlib.sha256()
            with open_regular(regular_file(directory, relative)) as handle:
                while chunk := handle.read(64 * 1024):
                    total += len(chunk)
                    if total > MAX_PAYLOAD_BYTES:
                        raise VendorError("bundle payload byte limit exceeded")
                    digest.update(chunk)
            if digest.hexdigest() != entries[relative]:
                raise VendorError(f"content mismatch for {relative!r}")
    if actual != entries.keys():
        raise VendorError(f"missing bundle files: {sorted(entries.keys() - actual)!r}")
    if "lanius.package.json" not in entries or "BUNDLE.txt" not in entries:
        raise VendorError("bundle metadata is missing")
    return len(entries), total


def source_plan(document: dict, max_files: int, max_bytes: int) -> list[tuple[Path, str, dict]]:
    files = document["inputs"]["files"]
    identities = document["source_identities"]["files"]
    if len(files) > max_files:
        raise VendorError(f"source file limit exceeded ({len(files)} > {max_files})")
    inputs = {(row["library_id"], row["path"]): row for row in files}
    if len(inputs) != len(files) or len(identities) != len(files):
        raise VendorError("inconsistent package source inventory")
    roots = [Path(root) for root in document["roots"]]
    plan = []
    seen: set[str] = set()
    total = 0
    for identity in identities:
        library = identity["library_id"]
        index = identity["source_root_index"]
        relative = relative_path(identity["source_root_relative_path"])
        if library == 0 and index == 0 and document.get("stdlib_root"):
            root = Path(document["stdlib_root"])
            destination = "stdlib/" + relative.as_posix()
        elif library == 1 and 0 <= index < len(roots):
            root = roots[index]
            destination = f"sources/{index:04d}/" + relative.as_posix()
        else:
            raise VendorError("unsupported package library or source root identity")
        source = Path(identity["path"])
        if not source.is_absolute() or source != root.joinpath(*relative.parts):
            raise VendorError("package source path does not match its root identity")
        if source.resolve() != source or not source.is_file():
            raise VendorError("package source changed identity after resolution")
        row = inputs.pop((library, str(source)), None)
        if row is None or destination in seen:
            raise VendorError("inconsistent package source identities")
        if not isinstance(row["byte_len"], int) or row["byte_len"] < 0:
            raise VendorError("invalid package source length")
        total += row["byte_len"]
        if total > max_bytes:
            raise VendorError(f"source byte limit exceeded ({total} > {max_bytes})")
        seen.add(destination)
        plan.append((source, destination, row))
    if inputs:
        raise VendorError("package source identities omit input files")
    return sorted(plan, key=lambda item: item[1])


def vendor(manifest: Path, output: Path, compiler: str, notices: list[Path],
           max_files: int, max_bytes: int) -> tuple[int, int]:
    deadline = time.monotonic() + 85.0
    manifest = manifest.resolve(strict=True)
    output = output.absolute()
    # Reserve a fresh directory before copying. Never merge with or overwrite
    # an existing directory, symlink or file. The caller owns this directory
    # exclusively until the command returns; metadata is published last.
    output.mkdir(parents=False, exist_ok=False)
    try:
        with tempfile.TemporaryDirectory(prefix="lanius-vendor-") as scratch:
            temporary = Path(scratch)
            original = lock(compiler, manifest, temporary / "original.lock.json", deadline)
            plan = source_plan(original, max_files, max_bytes)
            for source, relative, row in plan:
                if time.monotonic() >= deadline:
                    raise subprocess.TimeoutExpired("vendor", 85)
                # A bounded read prevents a concurrently grown source from
                # defeating the already checked snapshot byte limit.
                with open_regular(source) as handle:
                    data = handle.read(row["byte_len"] + 1)
                if len(data) != row["byte_len"] or fnv1a64(data) != row["digest"]:
                    raise VendorError(f"source changed after package resolution: {source}")
                destination = output / relative
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(data)
            roots = [f"sources/{index:04d}" for index in range(len(original["roots"]))]
            for root in roots:
                (output / root).mkdir(parents=True, exist_ok=True)
            entry = next((relative for source, relative, _ in plan
                          if str(source) == original["entry"]), None)
            if entry is None:
                raise VendorError("package entry is absent from source inventory")
            relocated = {"package": original["package"], "roots": roots, "entry": entry}
            if original.get("stdlib_root"):
                (output / "stdlib").mkdir(exist_ok=True)
                relocated["stdlib_root"] = "stdlib"
            result_manifest = output / "lanius.package.json"
            result_manifest.write_text(json.dumps(relocated, indent=2) + "\n")
            resolved = lock(compiler, result_manifest, temporary / "relocated.lock.json", deadline)
            copied = {relative for _, relative, _ in plan}
            reached = {Path(row["path"]).relative_to(output.resolve()).as_posix()
                       for row in resolved["inputs"]["files"]}
            if reached != copied:
                raise VendorError("relocated package resolves a different source closure")
            all_notices = [(REPOSITORY / name) for name in NOTICES] + notices
            if len(all_notices) > MAX_NOTICES:
                raise VendorError("at most 64 license notices may be included")
            for index, notice in enumerate(all_notices):
                # Source notices are small, independently bounded artifacts.
                with open_regular(notice) as handle:
                    data = handle.read(1024 * 1024 + 1)
                if len(data) > 1024 * 1024:
                    raise VendorError(f"license notice exceeds 1 MiB: {notice}")
                destination = output / f"notices/{index:04d}.txt"
                destination.parent.mkdir(exist_ok=True)
                destination.write_bytes(data)
            source_bytes = sum(row["byte_len"] for _, _, row in plan)
            (output / "BUNDLE.txt").write_text(
                "Lanius source bundle 1\n"
                f"package={original['package']}\n"
                f"compiler_version={original['compiler_version']}\n"
                f"language_edition={original['language_edition']}\n"
                f"source_files={len(plan)}\nsource_bytes={source_bytes}\n"
                "Only compiler-resolved reachable sources are included.\n"
                "Sources and embedded notices are unchanged.\n"
                "notices/ contains repository licenses and supplied notices.\n"
                "Generate a fresh package lock after relocation; locks use absolute paths.\n"
                "Compile with --package-manifest lanius.package.json.\n"
                "SHA256SUMS detects changes; it does not authenticate this bundle.\n"
            )
            payloads = sorted((path for path in output.rglob("*") if path.is_file()),
                              key=lambda path: path.relative_to(output).as_posix())
            inventory = "".join(
                f"{hashlib.sha256(path.read_bytes()).hexdigest()}  "
                f"{path.relative_to(output).as_posix()}\n" for path in payloads
            )
            (output / "SHA256SUMS").write_text(inventory)
            verify(output)
            return len(plan), source_bytes
    except BaseException:
        shutil.rmtree(output)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path, metavar="BUNDLE",
                        help="check the complete immutable bundle inventory without compiling")
    parser.add_argument("--manifest", type=Path, help="existing compiler package manifest")
    parser.add_argument("--out", type=Path, help="new bundle directory; parent must exist")
    parser.add_argument("--compiler", default=os.environ.get("LANIUSC", "laniusc"))
    parser.add_argument("--notice", type=Path, action="append", default=[],
                        help="additional license/notice to include (repeatable)")
    parser.add_argument("--max-files", type=int, default=MAX_FILES)
    parser.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    args = parser.parse_args()
    if args.verify:
        if args.manifest or args.out or args.notice:
            parser.error("--verify cannot be combined with --manifest, --out or --notice")
    elif not args.manifest or not args.out:
        parser.error("--manifest and --out are required when creating a bundle")
    if not (1 <= args.max_files <= MAX_FILES and 1 <= args.max_bytes <= MAX_BYTES):
        parser.error("limits must be positive and cannot exceed 4096 files / 64 MiB")
    def expired(_signum, _frame):
        raise subprocess.TimeoutExpired("source distribution", 90)
    previous_alarm = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 90.0)
    try:
        if args.verify:
            count, size = verify(args.verify)
            print(f"verified {count} payload files ({size} bytes)")
        else:
            count, size = vendor(args.manifest, args.out, args.compiler, args.notice,
                                 args.max_files, args.max_bytes)
            print(f"vendored {count} source files ({size} bytes) to {args.out}")
    except subprocess.TimeoutExpired as error:
        print(f"vendor: timed out: {error.cmd}", file=sys.stderr)
        return 124
    except (VendorError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"vendor: {error}", file=sys.stderr)
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_alarm)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
