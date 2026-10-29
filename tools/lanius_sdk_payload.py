"""Copy the source, documentation and notice inputs of a development SDK.

This module never invokes Cargo, a compiler or a payload program. The caller
owns a fresh staging directory and final inventory/publication. Notice inputs
describe a conservative dependency set, not the provenance of the binary.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import re
import stat
import subprocess
from urllib.parse import quote, unquote, urlsplit


MAX_INPUT_BYTES = 8 * 1024 * 1024
MAX_RUST_COPYRIGHT_BYTES = 32 * 1024 * 1024
MAX_INPUT_FILES = 8192
MAX_PAYLOAD_BYTES = 512 * 1024 * 1024
SOURCE_NOTICES = (
    "LICENSE-MIT", "LICENSE-APACHE", "data/unicode/17.0.0/LICENSE.txt",
    "third_party/rust-dec2flt/LICENSE-MIT",
    "third_party/rust-dec2flt/LICENSE-APACHE", "third_party/rust-dec2flt/NOTICE.md",
)
DOC_SEEDS = (
    "docs/library-sdk.md", "docs/library-distribution.md",
    "docs/library-overview.md", "docs/library-roadmap.md",
    "docs/library-dependencies.md", "docs/library-api-conventions.md",
    "docs/library-api-reference.md", "docs/stdlib-development.md",
    "stdlib/README.md", "extended/README.md",
)
EXAMPLES = {
    "calculator": "sample_programs/library/expr_calc.lani",
    "hash": "sample_programs/library/openssl_hash.lani",
    "suite": "sample_programs/library/sdk_suite.lani",
}
NOTICE_PREFIXES = ("license", "licence", "copying", "notice", "copyright")
DOC_HEADER = (
    "> SDK documentation snapshot. Local library sources and contract guides are\n"
    "> included. Online evidence links refer to the recorded repository revision.\n"
    "> Historical checkout commands and build artifacts are not installed SDK\n"
    "> workflows; see the SDK guide for installed commands.\n\n"
)


class PayloadError(ValueError):
    pass


def _relative(value: str) -> str:
    path = PurePosixPath(value)
    if (not value or path.is_absolute() or ".." in path.parts
            or path.as_posix() != value or "\\" in value
            or any(ord(c) < 32 or ord(c) == 127 for c in value)):
        raise PayloadError(f"unsafe payload path: {value!r}")
    return value


def _no_symlinks(path: Path) -> None:
    for part in (path, *path.parents):
        if part.is_symlink():
            raise PayloadError(f"symlink input path: {path}")


def _signature(info: os.stat_result) -> tuple:
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


class _Inputs:
    def __init__(self) -> None:
        self.records: dict[Path, dict] = {}
        self.signatures: dict[Path, tuple] = {}
        self.limits: dict[Path, int] = {}

    def read(self, path: Path, maximum: int = MAX_INPUT_BYTES) -> bytes:
        path = path.absolute()
        _no_symlinks(path)
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
            before = os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):
                raise PayloadError(f"input is not a regular file: {path}")
            if before.st_size > maximum:
                raise PayloadError(f"input exceeds {maximum} bytes: {path}")
            data = stream.read(maximum + 1)
            after = os.fstat(stream.fileno())
        if (len(data) > maximum or _signature(before) != _signature(after)
                or _signature(after) != _signature(path.stat(follow_symlinks=False))):
            raise PayloadError(f"input changed while reading: {path}")
        digest = hashlib.sha256(data).hexdigest()
        record = {"path": str(path), "size": len(data), "mtime_ns": after.st_mtime_ns,
                  "device": after.st_dev, "inode": after.st_ino, "sha256": digest}
        if path in self.records and self.records[path] != record:
            raise PayloadError(f"input changed during snapshot: {path}")
        self.records[path] = record
        self.signatures[path] = _signature(after)
        self.limits[path] = maximum
        if len(self.records) > MAX_INPUT_FILES:
            raise PayloadError("payload inputs exceed 8192 files")
        return data

    def verify(self) -> None:
        for path in sorted(self.records):
            if _signature(path.stat(follow_symlinks=False)) != self.signatures[path]:
                raise PayloadError(f"input changed during snapshot: {path}")
            self.read(path, self.limits[path])


def _files(root: Path) -> list[Path]:
    _no_symlinks(root)
    if not root.is_dir():
        raise PayloadError(f"missing directory: {root}")
    result = []
    for parent, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            item = Path(parent) / name
            mode = item.lstat().st_mode
            if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)):
                raise PayloadError(f"nonregular or symlink input: {item}")
        result.extend(Path(parent) / name for name in names)
        if len(result) > 200000:
            raise PayloadError(f"source scan exceeds 200000 files: {root}")
    return sorted(result)


class _Output:
    def __init__(self, root: Path) -> None:
        self.root = root
        existing = _files(root)
        self.count = len(existing)
        self.size = sum(p.stat().st_size for p in existing)
        self.reserve(0, 0)

    def reserve(self, count: int, size: int) -> None:
        if self.count + count > MAX_INPUT_FILES or self.size + size > MAX_PAYLOAD_BYTES:
            raise PayloadError("SDK payload exceeds 8192 files or 512 MiB")
        self.count += count
        self.size += size

    def __truediv__(self, name: str) -> Path:
        return self.root / name


def _write(stage: _Output, relative: str, data: bytes) -> None:
    destination = stage / _relative(relative)
    stage.reserve(1, len(data))
    destination.parent.mkdir(parents=True, exist_ok=True)
    _no_symlinks(destination.parent)
    with destination.open("xb") as stream:
        stream.write(data)
    destination.chmod(0o644)


def _json(stage: Path, relative: str, value) -> None:
    _write(stage, relative, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode())


def _git(root: Path, *args: str, optional: bool = False) -> bytes:
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True,
                            timeout=10, check=False)
    if result.returncode and not optional:
        raise PayloadError("git metadata failed: " + result.stderr.decode(errors="replace").strip())
    return b"" if result.returncode else result.stdout


def _repository_url(remote: str) -> str | None:
    match = re.fullmatch(r"(?:git@github\.com:|https://github\.com/)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?", remote)
    return "https://github.com/" + match[1] if match else None


def _markdown_links(text: str):
    """Yield inline/reference destinations outside fenced and inline code.

    The shipped source uses ordinary Markdown links. Reject local HTML links
    instead of silently leaving unsupported references in an offline snapshot.
    """
    offset = 0
    fence = None
    for line in text.splitlines(keepends=True):
        marker = re.match(r"^\s{0,3}(`{3,}|~{3,})", line)
        if marker:
            token = marker[1]
            if fence is None:
                fence = token
            elif token[0] == fence[0] and len(token) >= len(fence):
                fence = None
            offset += len(line)
            continue
        if fence:
            offset += len(line)
            continue
        masked = re.sub(r"(`+)(.*?)\1", lambda m: " " * len(m[0]), line)
        if re.search(r'<(?:a|img)\b[^>]*(?:href|src)\s*=\s*["\'](?![a-z]+:|#)', masked, re.I):
            raise PayloadError("local HTML documentation links are unsupported")
        for match in re.finditer(r"!?\[[^\]\n]*\]\((<[^>\n]+>|[^\s()]+)(?:\s+\"[^\"\n]*\")?\)", masked):
            yield offset + match.start(1), offset + match.end(1), line[match.start(1):match.end(1)]
        match = re.match(r"^\s{0,3}\[[^\]\n]+\]:\s*(<[^>\n]+>|\S+)", masked)
        if match:
            yield offset + match.start(1), offset + match.end(1), line[match.start(1):match.end(1)]
        offset += len(line)


def _local_link(source: str, destination: str) -> tuple[str, str] | None:
    value = destination[1:-1] if destination.startswith("<") else destination
    split = urlsplit(value)
    if split.scheme or split.netloc or not split.path:
        return None
    if split.path.startswith("/"):
        return ("", value)
    path = posixpath.normpath(posixpath.join(posixpath.dirname(source), unquote(split.path)))
    if path.startswith("../") or path == "..":
        return ("", value)
    _relative(path)
    suffix = ("?" + split.query if split.query else "") + ("#" + split.fragment if split.fragment else "")
    return path, suffix


def _documentation(root: Path, stage: Path, inputs: _Inputs, included: set[str],
                   revision: str, repository: str | None, tracked: set[str], changed: set[str]) -> dict:
    metadata = json.loads(inputs.read(root / "tools/library_reference_metadata.json"))
    seeds = set(DOC_SEEDS)
    for module in metadata["modules"].values():
        seeds.update(module.get("guides", []))
    seeds.update(p.relative_to(root).as_posix() for p in _files(root / "docs/api") if p.suffix == ".md")
    texts = {}
    pending = set(seeds)
    while pending:
        name = min(pending)
        pending.remove(name)
        _relative(name)
        if name in texts:
            continue
        if not (name.startswith("docs/") and name.endswith(".md") or name in DOC_SEEDS):
            raise PayloadError(f"unexpected documentation seed: {name}")
        text = inputs.read(root / name).decode("utf-8")
        texts[name] = text
        for _, _, destination in _markdown_links(text):
            local = _local_link(name, destination)
            if local and local[0].startswith("docs/") and local[0].endswith(".md"):
                pending.add(local[0])
    local_paths = included | texts.keys() | {"docs/sdk-unbundled-references.json"}
    online = unbundled = 0
    boundaries = []
    for name, text in sorted(texts.items()):
        replacements = []
        for start, end, destination in _markdown_links(text):
            local = _local_link(name, destination)
            if not local:
                continue
            path, suffix = local
            if path in local_paths or (path and any(p.startswith(path + "/") for p in local_paths)):
                continue
            unpublished = path in changed or any(p.startswith(path + "/") for p in changed)
            if repository and not unpublished and path in tracked:
                result = f"{repository}/blob/{revision}/{quote(path, safe='/')}{suffix}"
                online += 1
            elif repository and not unpublished and path and any(p.startswith(path + "/") for p in tracked):
                result = f"{repository}/tree/{revision}/{quote(path, safe='/')}{suffix}"
                online += 1
            else:
                # Preserve link syntax without making a false online-evidence
                # claim. The landing section explains these indexed references.
                result = posixpath.relpath("docs/library-sdk.md", posixpath.dirname(name)) + "#documentation-boundaries"
                boundaries.append({"document": name, "reference": destination})
                unbundled += 1
            replacements.append((start, end, result))
        for start, end, replacement in reversed(replacements):
            text = text[:start] + replacement + text[end:]
        _write(stage, "share/lanius/" + name, (DOC_HEADER + text).encode())
    _json(stage, "share/lanius/docs/sdk-unbundled-references.json", boundaries)
    return {"seed_files": len(seeds), "markdown_files": len(texts),
            "online_references": online, "unbundled_references": unbundled,
            "unbundled_index": "share/lanius/docs/sdk-unbundled-references.json",
            "policy": "Local payload links remain offline; omitted committed evidence links use source revision. Unpublished artifacts link to the SDK boundary and are indexed."}


def _notices(root: Path, stage: Path, inputs: _Inputs, metadata_path: Path, sysroot: Path) -> dict:
    metadata_bytes = inputs.read(metadata_path)
    metadata = json.loads(metadata_bytes)
    packages = metadata.get("packages")
    if not isinstance(packages, list) or not 1 <= len(packages) <= 2048:
        raise PayloadError("Cargo metadata must contain 1..2048 packages")
    # Cargo's selected resolution may exclude other targets and disabled features.
    # Require the whole supplied graph, and disclose every other locked identity.
    import tomllib
    lock = inputs.read(root / "Cargo.lock")
    locked = tomllib.loads(lock.decode("utf-8")).get("package", [])
    lock_ids = {(p["name"], p["version"], p.get("source")) for p in locked}
    selected_ids = {(p["name"], p["version"], p.get("source")) for p in packages}
    package_ids = {p["id"] for p in packages}
    nodes = metadata.get("resolve", {}).get("nodes", [])
    node_ids = {n["id"] for n in nodes}
    workspace_ids = set(metadata.get("workspace_members", [])) | set(metadata.get("workspace_default_members", []))
    resolution_root = metadata.get("resolve", {}).get("root")
    if resolution_root is not None:
        workspace_ids.add(resolution_root)
    if not workspace_ids <= package_ids:
        raise PayloadError("Cargo metadata omits a selected workspace or root package")
    if not nodes or len(nodes) != len(node_ids) or node_ids != package_ids:
        raise PayloadError("Cargo metadata must include every selected resolve node exactly once")
    if any(dep not in package_ids for n in nodes for dep in n.get("dependencies", [])):
        raise PayloadError("Cargo resolution references an omitted package")
    if any(dep["pkg"] not in package_ids for n in nodes for dep in n.get("deps", [])):
        raise PayloadError("Cargo resolution references an omitted dependency")
    if not selected_ids <= lock_ids or not lock_ids:
        raise PayloadError("Cargo metadata identities do not match the source lockfile")
    outside_resolution = [
        {"name": name, "version": version, "source": source}
        for name, version, source in sorted(lock_ids - selected_ids, key=lambda p: (p[0], p[1], p[2] or ""))
    ]
    _write(stage, "notices/cargo/Cargo.lock", lock)
    overlay_path = root / "data/sdk-notices/provenance.json"
    overlay = {}
    if overlay_path.exists() or overlay_path.is_symlink():
        raw = inputs.read(overlay_path)
        manifest = json.loads(raw)
        if manifest.get("format_version") != 1:
            raise PayloadError("unsupported SDK notice overlay version")
        for package in manifest["packages"]:
            key = (package["name"], package["version"])
            if key in overlay:
                raise PayloadError(f"duplicate notice overlay: {key}")
            overlay[key] = package
        _write(stage, "notices/cargo/upstream-provenance.json", raw)
    rows = []
    gaps = []
    used_overlay = set()
    identities = set()
    for package in sorted(packages, key=lambda p: (p["name"], p["version"], p.get("id", ""))):
        name, version = package["name"], package["version"]
        identity = package.get("id", name + "@" + version)
        if identity in identities:
            raise PayloadError(f"duplicate Cargo package: {identity}")
        identities.add(identity)
        if not all(isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_.+-]+", value)
                   for value in (name, version)):
            raise PayloadError("unsafe Cargo package name or version")
        key = name + "-" + version + "-" + hashlib.sha256(identity.encode()).hexdigest()[:8]
        base = "notices/cargo/packages/" + key
        path = Path(package["manifest_path"])
        if not path.is_absolute() or path.name != "Cargo.toml":
            raise PayloadError(f"invalid Cargo manifest path: {path}")
        manifest_data = inputs.read(path)
        _write(stage, base + "/Cargo.toml", manifest_data)
        files = []
        if package.get("source") is None and path.is_relative_to(root):
            files = ["share/lanius/LICENSE-MIT", "share/lanius/LICENSE-APACHE"]
        else:
            selected = {p for p in _files(path.parent) if p.name.lower().startswith(NOTICE_PREFIXES)}
            license_file = package.get("license_file")
            if license_file:
                license_path = Path(license_file)
                if not license_path.is_absolute():
                    license_path = path.parent / _relative(license_file)
                if not license_path.is_relative_to(path.parent):
                    raise PayloadError(f"license file escapes crate: {license_path}")
                selected.add(license_path)
            for source in sorted(selected):
                relative = source.relative_to(path.parent).as_posix()
                destination = base + "/files/" + _relative(relative)
                _write(stage, destination, inputs.read(source))
                files.append(destination)
        if (name, version) in overlay:
            used_overlay.add((name, version))
            for item in overlay[(name, version)]["files"]:
                relative = _relative(item["path"])
                data = inputs.read(root / "data/sdk-notices" / relative)
                if hashlib.sha256(data).hexdigest() != item["sha256"]:
                    raise PayloadError(f"notice overlay digest mismatch: {relative}")
                destination = base + "/upstream/" + relative
                _write(stage, destination, data)
                files.append(destination)
        if not files:
            gaps.append({"name": name, "version": version,
                         "declared_license": package.get("license"),
                         "reason": "No license/notice file found; Cargo.toml is retained."})
        rows.append({"id": identity, "name": name, "version": version,
                     "source": package.get("source"), "declared_license": package.get("license"),
                     "manifest": base + "/Cargo.toml", "notices": files})
    if used_overlay != overlay.keys():
        raise PayloadError("notice overlay contains packages absent from supplied Cargo metadata")
    cargo_index = {"format_version": 1, "provenance": "Supplied Cargo metadata and source lockfile; conservative notice inputs, not proven binary build identity.",
                   "metadata_sha256": hashlib.sha256(metadata_bytes).hexdigest(),
                   "lock_sha256": hashlib.sha256(lock).hexdigest(), "packages": rows, "gaps": gaps,
                   "locked_outside_supplied_resolution": outside_resolution}
    _json(stage, "notices/cargo/index.json", cargo_index)
    toolchain = sysroot / "share/doc/rust"
    rust_paths = [toolchain / "COPYRIGHT.html", toolchain / "COPYRIGHT-library.html"]
    license_paths = _files(toolchain / "licenses")
    if not license_paths:
        raise PayloadError("Rust sysroot licenses directory is empty")
    rust_paths.extend(license_paths)
    rust_rows = []
    for source in sorted(rust_paths):
        relative = source.relative_to(sysroot).as_posix()
        maximum = MAX_RUST_COPYRIGHT_BYTES if source in (toolchain / "COPYRIGHT.html", toolchain / "COPYRIGHT-library.html") else MAX_INPUT_BYTES
        data = inputs.read(source, maximum)
        destination = "notices/rust/" + relative
        _write(stage, destination, data)
        rust_rows.append({"path": destination, "sha256": hashlib.sha256(data).hexdigest()})
    _json(stage, "notices/rust/index.json", {"format_version": 1,
          "provenance": "Supplied Rust sysroot copyright and license inputs; not proven binary toolchain identity.",
          "files": rust_rows})
    return {"cargo_packages": len(rows), "cargo_index": "notices/cargo/index.json",
            "cargo_metadata_sha256": cargo_index["metadata_sha256"],
            "cargo_lock_sha256": cargo_index["lock_sha256"],
            "rust_notice_files": len(rust_rows), "rust_index": "notices/rust/index.json",
            "overlay_packages": len(used_overlay), "gaps": gaps,
            "locked_outside_supplied_resolution": len(outside_resolution),
            "provenance": "Notice input inventory only; separate from supplied compiler binary identity."}


def populate_payload(source_root: Path, stage: Path, cargo_metadata: Path, rust_sysroot: Path) -> dict:
    root, stage = Path(source_root).absolute(), Path(stage).absolute()
    _no_symlinks(root)
    _no_symlinks(stage)
    if not stage.is_dir():
        raise PayloadError("payload stage must already be a directory")
    if Path(_git(root, "rev-parse", "--show-toplevel").decode().strip()) != root:
        raise PayloadError("source_root must be the Git repository root")
    stage = _Output(stage)
    inputs = _Inputs()
    revision = _git(root, "rev-parse", "HEAD").decode().strip()
    if not re.fullmatch(r"[0-9a-f]{40,64}", revision):
        raise PayloadError("invalid source revision")
    status_before = _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    repository = _repository_url(_git(root, "remote", "get-url", "origin", optional=True).decode().strip())
    tracked = set(_git(root, "ls-tree", "-rz", "--name-only", revision).decode().split("\0")) - {""}
    changed = set(_git(root, "diff", "HEAD", "--name-only", "-z", "--no-renames").decode().split("\0")) - {""}
    included = set(SOURCE_NOTICES)
    source_count = source_bytes = support_count = 0
    for directory in ("stdlib", "extended"):
        for path in _files(root / directory):
            name = path.relative_to(root).as_posix()
            included.add(name)
            if name in ("stdlib/README.md", "extended/README.md"):
                continue  # Included in the documentation link closure below.
            if path.suffix not in (".lani", ".bash"):
                raise PayloadError(f"unexpected library payload file: {name}")
            data = inputs.read(path)
            _write(stage, "share/lanius/" + name, data)
            if path.suffix == ".lani":
                source_count += 1
                source_bytes += len(data)
            else:
                support_count += 1
    for name in SOURCE_NOTICES:
        _write(stage, "share/lanius/" + name, inputs.read(root / name))
    examples = {}
    for name, source in EXAMPLES.items():
        entry = f"examples/{name}/app/main.lani"
        _write(stage, "share/lanius/" + entry, inputs.read(root / source))
        manifest = {"package": "sdk." + name, "roots": ["extended", "examples/" + name],
                    "stdlib_root": "stdlib", "entry": entry}
        manifest_path = name + ".package.json"
        _json(stage, "share/lanius/" + manifest_path, manifest)
        included.update((entry, manifest_path))
        examples[name] = {"source": source, "entry": "share/lanius/" + entry,
                          "manifest": "share/lanius/" + manifest_path}
    documents = _documentation(root, stage, inputs, included, revision, repository, tracked, changed)
    notices = _notices(root, stage, inputs, Path(cargo_metadata), Path(rust_sysroot).absolute())
    inputs.verify()
    if revision != _git(root, "rev-parse", "HEAD").decode().strip() or status_before != _git(root, "status", "--porcelain=v1", "-z", "--untracked-files=all"):
        raise PayloadError("source revision or dirty state changed during snapshot")
    return {"source": {"revision": revision, "dirty": bool(status_before), "repository": repository,
                       "status_sha256": hashlib.sha256(status_before).hexdigest(),
                       "identity_scope": "Library/document source snapshot; not compiler binary build provenance."},
            "libraries": {"source_files": source_count, "source_bytes": source_bytes, "support_files": support_count},
            "documentation": documents, "examples": examples, "notices": notices,
            "source_inputs": [str(p) for p in sorted(inputs.records)],
            "source_snapshots": [inputs.records[p] for p in sorted(inputs.records)]}
