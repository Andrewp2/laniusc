#!/usr/bin/env python3
"""Package or verify a relocatable Linux development SDK; never build a compiler."""

from __future__ import annotations

import argparse
import ctypes
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

# Installed verification must not create an unlisted __pycache__ directory.
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parent.parent
MAX_FILES = 8192
MAX_BYTES = 512 * 1024 * 1024
MAX_MANIFEST = 8 * 1024 * 1024
OVERRIDE = "LANIUS_SHADER_ARTIFACT_ROOT"
TOOLS = ("build_lanius_sdk.py", "pin_laniusc.py", "lanius_sdk_launchers.py",
         "lanius_sdk_payload.py", "lanius-test", "vendor_lanius.py")
EXECUTABLES = {"bin/laniusc", "bin/lanius-test", "bin/lanius-vendor",
               "bin/lanius-sdk-verify", "libexec/laniusc",
               *("share/lanius/tools/" + name for name in TOOLS)}
REQUIRED = EXECUTABLES | {"SDK.txt", "shaders/artifacts.env",
                        "share/lanius/LICENSE-MIT", "share/lanius/LICENSE-APACHE",
                        "share/lanius/calculator.package.json",
                        "share/lanius/docs/library-sdk.md"}
SDK_TEXT = """Lanius development SDK

This is an alpha development snapshot, not a stable production release.
Use bin/laniusc with explicit --stdlib-root share/lanius/stdlib and
--source-root share/lanius/extended as appropriate. Compiler arguments and
version output are unchanged. Read share/lanius/docs/library-sdk.md first.
Move the complete SDK directory; keep generated outputs and caches outside it.
bin/lanius-sdk-verify checks the complete immutable payload without executing it.
SHA256SUMS detects changes; it does not authenticate the SDK or its origin.
SDK.json records supplied compiler bytes separately from source provenance.
Host GPU drivers, loader and selected native libraries remain external.
"""


class SdkError(RuntimeError):
    pass


def pin(target_dir: Path, profile: str, output: Path) -> Path:
    # Build-only imports keep installed verification limited to this script
    # and Python's standard library; no other payload module is executed.
    from pin_laniusc import PinError, pin as snapshot_build
    try:
        return snapshot_build(target_dir, profile, output)
    except PinError as error:
        raise SdkError(str(error)) from error


def populate_payload(source_root: Path, stage: Path, cargo_metadata: Path,
                     rust_sysroot: Path) -> dict:
    from lanius_sdk_payload import populate_payload as populate
    return populate(source_root, stage, cargo_metadata, rust_sysroot)


def install_launchers(stage: Path) -> None:
    from lanius_sdk_launchers import install_launchers as install
    install(stage)


def relative_path(value: str) -> PurePosixPath:
    if not isinstance(value, str):
        raise SdkError("inventory path must be a string")
    path = PurePosixPath(value)
    if (not value or not path.parts or path.is_absolute() or ".." in path.parts
            or path.as_posix() != value or "\\" in value
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise SdkError(f"unsafe inventory path {value!r}")
    return path


def regular(path: Path) -> os.stat_result:
    # Checking each component also rejects a symlink through an ancestor.
    for current in (path, *path.parents):
        if current.is_symlink():
            raise SdkError(f"symlink input or payload: {path}")
    info = path.stat()
    if not stat.S_ISREG(info.st_mode):
        raise SdkError(f"not a regular file: {path}")
    return info


def opened_regular(path: Path):
    regular(path)
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        if not stat.S_ISREG(os.fstat(descriptor).st_mode):
            raise SdkError(f"not a regular file: {path}")
        return os.fdopen(descriptor, "rb")
    except BaseException:
        os.close(descriptor)
        raise


def read_bounded(path: Path, maximum: int = MAX_MANIFEST) -> bytes:
    with opened_regular(path) as stream:
        data = stream.read(maximum + 1)
    if len(data) > maximum:
        raise SdkError(f"file exceeds {maximum} byte limit: {path}")
    return data


def snapshot(path: Path) -> dict:
    before = regular(path)
    digest = hashlib.sha256()
    size = 0
    with opened_regular(path) as stream:
        while data := stream.read(1024 * 1024):
            size += len(data)
            if size > MAX_BYTES:
                raise SdkError(f"file exceeds payload byte limit: {path}")
            digest.update(data)
    after = regular(path)
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_mode)
    if identity(before) != identity(after) or size != after.st_size:
        raise SdkError(f"input changed while reading: {path}")
    return {"path": str(path), "size": size, "mtime_ns": after.st_mtime_ns,
            "device": after.st_dev, "inode": after.st_ino,
            "sha256": digest.hexdigest(), "mode": stat.S_IMODE(after.st_mode)}


def unchanged(old: dict) -> None:
    new = snapshot(Path(old["path"]))
    for key in ("size", "mtime_ns", "device", "inode", "sha256"):
        if old[key] != new[key]:
            raise SdkError(f"input changed during SDK creation: {old['path']}")
    if "mode" in old and old["mode"] != new["mode"]:
        raise SdkError(f"input mode changed during SDK creation: {old['path']}")


def tree_files(root: Path) -> list[Path]:
    if root.is_symlink() or not root.is_dir():
        raise SdkError(f"expected real directory: {root}")
    files = []
    total = 0
    for parent, directories, names in os.walk(root, followlinks=False):
        for name in directories:
            path = Path(parent) / name
            if path.is_symlink() or not path.is_dir():
                raise SdkError(f"non-directory or symlink in payload: {path}")
        for name in names:
            path = Path(parent) / name
            info = regular(path)
            relative_path(path.relative_to(root).as_posix())
            files.append(path)
            total += info.st_size
            if len(files) > MAX_FILES or total > MAX_BYTES:
                raise SdkError("SDK payload file or byte limit exceeded")
    return sorted(files, key=lambda p: p.relative_to(root).as_posix())


def json_document(raw: bytes) -> object:
    def unique(rows):
        result = {}
        for key, value in rows:
            if key in result:
                raise SdkError(f"duplicate JSON field {key!r}")
            result[key] = value
        return result
    return json.loads(raw, object_pairs_hook=unique,
                      parse_constant=lambda value: (_ for _ in ()).throw(SdkError(f"invalid JSON {value}")))


def canonical(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=True, sort_keys=True,
                      separators=(",", ":"), allow_nan=False).encode("utf-8")


def publish(stage: Path, output: Path) -> None:
    # Linux renameat2's NOREPLACE flag closes the check/rename race without
    # replacing a directory another process created while we were packaging.
    library = ctypes.CDLL(None, use_errno=True)
    try:
        rename = library.renameat2
    except AttributeError as error:
        raise SdkError("SDK publication requires Linux renameat2") from error
    rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p,
                       ctypes.c_uint]
    rename.restype = ctypes.c_int
    if rename(-100, os.fsencode(stage), -100, os.fsencode(output), 1):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), str(output))


def validate_shaders(root: Path) -> dict:
    files = {p.relative_to(root).as_posix(): p for p in tree_files(root)}
    if "artifacts.env" not in files:
        raise SdkError("missing shader artifacts.env")
    fields = {}
    for line in read_bounded(files["artifacts.env"]).decode("utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator or not key or key in fields:
            raise SdkError("malformed or duplicate shader metadata")
        fields[key] = value
    if not re.fullmatch(r"[0-9a-f]{16}", fields.get("digest", "")):
        raise SdkError("invalid shader digest")
    spv = {name[:-4] for name in files if name.endswith(".spv")}
    reflection = {name[:-13] for name in files if name.endswith(".reflect.json")}
    if not spv or spv != reflection:
        raise SdkError("missing shader/reflection pair")
    if fields.get("count") != str(len(spv)):
        raise SdkError("shader count does not match metadata")
    expected = {"artifacts.env"} | {key + ending for key in spv
                                              for ending in (".spv", ".reflect.json", ".stamp")}
    if set(files) - expected:
        raise SdkError("unexpected shader artifact file")
    value = 0xcbf29ce484222325
    def update(data):
        nonlocal value
        for byte in data:
            value = ((value ^ byte) * 0x100000001b3) & 0xffffffffffffffff
    maximum = 0
    maximum_names = []
    # build.rs visits source filenames, whose suffix participates in sorting.
    for key in sorted(spv, key=lambda name: name + ".slang"):
        code_size = regular(files[key + ".spv"]).st_size
        with opened_regular(files[key + ".spv"]) as stream:
            header = stream.read(20)
        if (code_size < 20 or code_size % 4 or header[:4] != b"\x03\x02\x23\x07"
                or int.from_bytes(header[12:16], "little") == 0 or header[16:20] != b"\0\0\0\0"):
            raise SdkError(f"malformed SPIR-V header: {key}")
        raw = read_bounded(files[key + ".reflect.json"])
        document = json_document(raw)
        # Match build.rs/reflection_names.rs: only named, bound top-level
        # parameters participate. Packaging does not impose a new schema.
        parameters = document.get("parameters", []) if isinstance(document, dict) else []
        if not isinstance(parameters, list):
            parameters = []
        names = set()
        for parameter in parameters:
            if (not isinstance(parameter, dict) or not isinstance(parameter.get("name"), str)
                    or not ("binding" in parameter or "bindings" in parameter)):
                continue
            name = parameter["name"]
            if name in names:
                raise SdkError(f"duplicate shader reflection binding: {key}: {name}")
            names.add(name)
        update(key.encode("utf-8"))
        update(b"\0")
        with opened_regular(files[key + ".spv"]) as stream:
            read = 0
            while chunk := stream.read(1024 * 1024):
                read += len(chunk)
                if read > code_size:
                    raise SdkError(f"shader changed while reading: {key}")
                update(chunk)
            if read != code_size:
                raise SdkError(f"shader changed while reading: {key}")
        update(b"\0")
        update(raw)
        update(b"\xff")
        if code_size > maximum:
            maximum, maximum_names = code_size, [key]
        elif code_size == maximum:
            maximum_names.append(key)
    if f"{value:016x}" != fields["digest"]:
        raise SdkError("shader bytes do not match declared digest")
    if (fields.get("max_spv_bytes") != str(maximum)
            or fields.get("max_spv_name") not in maximum_names):
        raise SdkError("shader maximum does not match metadata")
    guard = fields.get("size_guard_status")
    if guard == "enforced":
        try:
            limit = int(fields["size_guard_max_bytes"])
        except (KeyError, ValueError) as error:
            raise SdkError("invalid shader size guard") from error
        if limit <= 0 or maximum > limit:
            raise SdkError("shader exceeds declared size guard")
    elif guard != "disabled":
        raise SdkError("invalid shader size guard status")
    return {"digest": fields["digest"], "count": len(spv)}


def version(command: Path, shaders: Path) -> str:
    result = subprocess.run([str(command), "--version"], capture_output=True,
                            timeout=30, env={**os.environ, OVERRIDE: str(shaders)})
    if result.returncode:
        raise SdkError(f"compiler version probe failed ({result.returncode})")
    if len(result.stdout) > MAX_MANIFEST or len(result.stderr) > MAX_MANIFEST:
        raise SdkError("compiler version output exceeds metadata limit")
    return result.stdout.decode("utf-8")


def reported_digest(text: str) -> str:
    values = [line.partition(":")[2].strip() for line in text.splitlines()
              if line.partition(":")[0].strip() == "shader-artifact-digest"]
    if len(values) != 1:
        raise SdkError("compiler version must report one shader digest")
    return values[0]


def file_records(directory: Path) -> list[dict]:
    records = []
    for path in tree_files(directory):
        name = path.relative_to(directory).as_posix()
        if name in ("SDK.json", "SHA256SUMS"):
            continue
        info = snapshot(path)
        records.append({"path": name, "size": info["size"], "sha256": info["sha256"],
                        "mode": info["mode"]})
    return records


def verify(directory: Path) -> tuple[int, int]:
    directory = Path(directory).absolute()
    actual = tree_files(directory)
    inventory = read_bounded(directory / "SHA256SUMS").decode("utf-8")
    entries = {}
    for line in inventory.splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            raise SdkError("malformed SHA256SUMS record")
        digest, name = match.groups()
        relative_path(name)
        if name == "SHA256SUMS" or name in entries:
            raise SdkError("duplicate or self-referential inventory entry")
        entries[name] = digest
        if len(entries) > MAX_FILES:
            raise SdkError("inventory file limit exceeded")
    if not entries or list(entries) != sorted(entries):
        raise SdkError("inventory must be nonempty and sorted")
    names = {p.relative_to(directory).as_posix() for p in actual} - {"SHA256SUMS"}
    if names != set(entries):
        raise SdkError("SDK has missing or extra payload files")
    metadata = json_document(read_bounded(directory / "SDK.json"))
    if not isinstance(metadata, dict) or metadata.get("schema") != "lanius.sdk.v1":
        raise SdkError("unsupported SDK metadata")
    if (not isinstance(metadata.get("profile"), str)
            or not re.fullmatch(r"[A-Za-z0-9_-]+", metadata["profile"])
            or not isinstance(metadata.get("payload"), dict)):
        raise SdkError("malformed SDK metadata")
    records = file_records(directory)
    if metadata.get("files") != records:
        raise SdkError("SDK payload bytes, sizes or modes changed")
    if not REQUIRED <= {row["path"] for row in records}:
        raise SdkError("SDK required payload is missing")
    for prefix in ("share/lanius/stdlib/", "share/lanius/extended/"):
        if not any(row["path"].startswith(prefix) and row["path"].endswith(".lani")
                   for row in records):
            raise SdkError(f"SDK library sources are missing: {prefix}")
    for row in records:
        expected_mode = 0o755 if row["path"] in EXECUTABLES else 0o644
        if row["mode"] != expected_mode:
            raise SdkError(f"invalid payload mode: {row['path']}")
    for name in ("SDK.json", "SHA256SUMS"):
        if stat.S_IMODE(regular(directory / name).st_mode) != 0o644:
            raise SdkError(f"invalid metadata mode: {name}")
    content_id = "sha256:" + hashlib.sha256(canonical(records)).hexdigest()
    if metadata.get("content_id") != content_id:
        raise SdkError("SDK content identity mismatch")
    digest_by_name = {row["path"]: row["sha256"] for row in records}
    digest_by_name["SDK.json"] = snapshot(directory / "SDK.json")["sha256"]
    if entries != digest_by_name:
        raise SdkError("SDK inventory hash mismatch")
    if metadata.get("binary_sha256") != digest_by_name["libexec/laniusc"]:
        raise SdkError("SDK compiler identity mismatch")
    shaders = validate_shaders(directory / "shaders")
    if metadata.get("shader_digest") != shaders["digest"] or metadata.get("shader_count") != shaders["count"]:
        raise SdkError("SDK shader identity mismatch")
    if not isinstance(metadata.get("compiler_version"), str) or reported_digest(metadata["compiler_version"]) != shaders["digest"]:
        raise SdkError("SDK recorded version mismatch")
    return len(entries), sum(regular(directory / name).st_size for name in entries)


def build(target_dir: Path, profile: str, output: Path, cargo_metadata: Path,
          rust_sysroot: Path, source_root: Path = ROOT) -> dict:
    target_dir, output, source_root = (Path(p).absolute() for p in (target_dir, output, source_root))
    if not re.fullmatch(r"[A-Za-z0-9_-]+", profile):
        raise SdkError("profile must be a single directory name")
    if output.exists() or output.is_symlink():
        raise SdkError(f"output already exists: {output}")
    if not output.parent.is_dir() or output.parent.is_symlink():
        raise SdkError("output parent must be an existing real directory")
    binary = target_dir / profile / "laniusc"
    binary_state = snapshot(binary)
    if not binary_state["mode"] & 0o111:
        raise SdkError("compiler binary is not executable")
    shader_root = target_dir / "laniusc-shader-artifacts" / profile / "shaders"
    shaders = validate_shaders(shader_root)
    shader_states = [snapshot(path) for path in tree_files(shader_root)]
    if (len(shader_states) + 1 > MAX_FILES
            or binary_state["size"] + sum(row["size"] for row in shader_states) > MAX_BYTES):
        raise SdkError("compiler snapshot exceeds payload limit")
    library_names = {name: {p.relative_to(source_root / name).as_posix()
                            for p in tree_files(source_root / name)}
                     for name in ("stdlib", "extended")}
    stage = Path(tempfile.mkdtemp(prefix="." + output.name + ".staging-", dir=output.parent))
    try:
        # Fresh directory prevents pin()'s reuse path from trusting an older pin.
        with tempfile.TemporaryDirectory(prefix=".sdk-pin-", dir=output.parent) as pins:
            wrapper = pin(target_dir, profile, Path(pins))
            pinned = wrapper.parent
            (stage / "libexec").mkdir()
            shutil.move(str(pinned / "bin" / "laniusc"), stage / "libexec" / "laniusc")
            shutil.move(str(pinned / "shaders"), stage / "shaders")
        if snapshot(stage / "libexec" / "laniusc")["sha256"] != binary_state["sha256"]:
            raise SdkError("compiler changed before snapshot")
        if {p.relative_to(stage / "shaders").as_posix() for p in tree_files(stage / "shaders")} != {
                Path(row["path"]).relative_to(shader_root).as_posix() for row in shader_states}:
            raise SdkError("shader tree changed before snapshot")
        for old in shader_states:
            copied = stage / "shaders" / Path(old["path"]).relative_to(shader_root)
            if snapshot(copied)["sha256"] != old["sha256"]:
                raise SdkError("shader changed before snapshot")
        payload = dict(populate_payload(source_root, stage, Path(cargo_metadata), Path(rust_sysroot)))
        payload.pop("source_inputs", None)
        inputs = payload.pop("source_snapshots", [])
        helper_dir = stage / "share" / "lanius" / "tools"
        helper_dir.mkdir(parents=True, exist_ok=True)
        for name in TOOLS:
            source = source_root / "tools" / name
            old = snapshot(source)
            shutil.copyfile(source, helper_dir / name)
            if snapshot(helper_dir / name)["sha256"] != old["sha256"]:
                raise SdkError(f"helper changed during copy: {name}")
            inputs.append(old)
        install_launchers(stage)
        (stage / "SDK.txt").write_text(SDK_TEXT, encoding="utf-8")
        for path in tree_files(stage):
            path.chmod(0o755 if path.relative_to(stage).as_posix() in EXECUTABLES else 0o644)
        # A successful empty-override probe closes pin's permissive exit check.
        with tempfile.TemporaryDirectory(prefix=".sdk-empty-", dir=output.parent) as empty:
            if reported_digest(version(stage / "libexec" / "laniusc", Path(empty))) != "unknown":
                raise SdkError("compiler ignores shader override")
        text = version(stage / "bin" / "laniusc", Path("/nonexistent-sdk-override"))
        if reported_digest(text) != shaders["digest"]:
            raise SdkError("SDK launcher does not select the bundled shaders")
        records = file_records(stage)
        metadata = {"schema": "lanius.sdk.v1", "profile": profile,
                    "binary_sha256": binary_state["sha256"],
                    "shader_digest": shaders["digest"], "shader_count": shaders["count"],
                    "compiler_version": text, "payload": payload, "files": records,
                    "build_inputs": {"binary": str(binary), "shaders": str(shader_root),
                                     "target_dir": str(target_dir)},
                    "initial_sdk_path": str(output),
                    "content_id": "sha256:" + hashlib.sha256(canonical(records)).hexdigest()}
        raw = json.dumps(metadata, ensure_ascii=True, sort_keys=True, indent=2, allow_nan=False) + "\n"
        if len(raw.encode("utf-8")) > MAX_MANIFEST:
            raise SdkError("SDK metadata exceeds manifest limit")
        (stage / "SDK.json").write_text(raw, encoding="utf-8")
        (stage / "SDK.json").chmod(0o644)
        rows = [(row["path"], row["sha256"]) for row in records]
        rows.append(("SDK.json", snapshot(stage / "SDK.json")["sha256"]))
        inventory = "".join(f"{digest}  {name}\n" for name, digest in sorted(rows))
        if len(inventory.encode("utf-8")) > MAX_MANIFEST:
            raise SdkError("SDK inventory exceeds manifest limit")
        (stage / "SHA256SUMS").write_text(inventory, encoding="utf-8")
        (stage / "SHA256SUMS").chmod(0o644)
        verify(stage)
        unchanged(binary_state)
        if {p.relative_to(shader_root).as_posix() for p in tree_files(shader_root)} != {
                Path(row["path"]).relative_to(shader_root).as_posix() for row in shader_states}:
            raise SdkError("shader tree changed during SDK creation")
        for old in [*shader_states, *inputs]:
            unchanged(old)
        for name, expected in library_names.items():
            if {p.relative_to(source_root / name).as_posix()
                    for p in tree_files(source_root / name)} != expected:
                raise SdkError(f"library source tree changed during SDK creation: {name}")
        if output.exists() or output.is_symlink():
            raise SdkError("output appeared during SDK creation")
        publish(stage, output)
        return metadata
    except BaseException:
        shutil.rmtree(stage, ignore_errors=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", type=Path, metavar="SDK")
    parser.add_argument("--target-dir", type=Path)
    parser.add_argument("--profile", help="build profile (default: debug)")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--cargo-metadata", type=Path)
    parser.add_argument("--rust-sysroot", type=Path)
    args = parser.parse_args()
    if args.verify:
        if any((args.target_dir, args.profile, args.out, args.cargo_metadata, args.rust_sysroot)):
            parser.error("--verify cannot be combined with build inputs")
    elif not all((args.target_dir, args.out, args.cargo_metadata, args.rust_sysroot)):
        parser.error("build requires --target-dir, --out, --cargo-metadata and --rust-sysroot")
    def expired(_signal, _frame):
        raise subprocess.TimeoutExpired("SDK packaging", 90)
    previous = signal.signal(signal.SIGALRM, expired)
    signal.setitimer(signal.ITIMER_REAL, 90)
    try:
        if args.verify:
            count, size = verify(args.verify)
            print(f"verified {count} payload files ({size} bytes)")
        else:
            metadata = build(args.target_dir, args.profile or "debug", args.out, args.cargo_metadata, args.rust_sysroot)
            print(f"created development SDK {metadata['content_id']} at {args.out}")
    except subprocess.TimeoutExpired as error:
        print(f"sdk: timed out: {error.cmd}", file=sys.stderr)
        return 124
    except (SdkError, OSError, ValueError, KeyError, TypeError) as error:
        print(f"sdk: {error}", file=sys.stderr)
        return 1
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
