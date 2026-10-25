#!/usr/bin/env python3
"""Import or verify the exact TOML 1.1 fixtures from a pinned official release.

This tool only copies and hashes test data. It does not parse TOML or provide
library behavior. Download the source archive explicitly, then pass --import.
"""

import argparse
import hashlib
import io
import json
from pathlib import Path
import tarfile


ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / "data/toml-test/v2.2.0"
VERSION = "v2.2.0"
COMMIT = "ce08da1ddb075d1c7596d663c7fcba9a2ae02c5c"
ARCHIVE_SHA256 = "fdab2779b3902eb08030f389a5d53e95c5b49404149ac6f2eda5227a5363c232"
FILES_MANIFEST_SHA256 = "9999389d82f382c917eb6d3b045dbf931158d30ecff908093c76a7bbf94ba6bb"
INDEX = "files-toml-1.1.0"
COUNTS = {"valid": 214, "invalid": 467, "expected": 214}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def verify_manifest_anchor(files):
    serialized = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    assert digest(serialized) == FILES_MANIFEST_SHA256, "file manifest differs from the pinned official corpus"


def validate_index(data):
    files = data.decode("utf-8").splitlines()
    assert len(files) == len(set(files)), "upstream index has duplicates"
    assert all(Path(name).parts[0] in ("valid", "invalid") for name in files)
    assert all(".." not in Path(name).parts for name in files)
    valid = [name for name in files if name.startswith("valid/") and name.endswith(".toml")]
    invalid = [name for name in files if name.startswith("invalid/") and name.endswith(".toml")]
    expected = [name for name in files if name.endswith(".json")]
    assert {"valid": len(valid), "invalid": len(invalid), "expected": len(expected)} == COUNTS
    assert {name[:-5] for name in valid} == {name[:-5] for name in expected}
    assert len(files) == sum(COUNTS.values())
    # Explicitly require the 1.1 changes: x/e escapes, optional seconds, and
    # multiline/trailing-comma inline tables, together with the spec examples.
    assert "valid/datetime/no-seconds.toml" in files
    assert "valid/inline-table/newline.toml" in files
    assert any(name.startswith("valid/spec-1.1.0/") for name in files)
    return files


def import_archive(path):
    archive = path.read_bytes()
    assert digest(archive) == ARCHIVE_SHA256, "source archive does not match the pinned release"
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
        prefix = "toml-test-2.2.0/"

        def read(name):
            file = source.extractfile(prefix + name)
            assert file is not None, name
            return file.read()

        index = read("tests/" + INDEX)
        files = validate_index(index)
        copied = {"LICENSE": read("LICENSE"), INDEX: index}
        copied.update({"tests/" + name: read("tests/" + name) for name in files})
        DESTINATION.mkdir(parents=True, exist_ok=True)
        for name, content in copied.items():
            output = DESTINATION / name
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(content)
        metadata = {
            "repository": "https://github.com/toml-lang/toml-test",
            "release": VERSION,
            "commit": COMMIT,
            "archive_url": "https://codeload.github.com/toml-lang/toml-test/tar.gz/refs/tags/v2.2.0",
            "archive_sha256": ARCHIVE_SHA256,
            "toml_version": "1.1.0",
            "index": INDEX,
            "counts": COUNTS,
            "files_sha256": {name: digest(content) for name, content in sorted(copied.items())},
        }
        verify_manifest_anchor(metadata["files_sha256"])
        (DESTINATION / "SOURCE.json").write_text(json.dumps(metadata, indent=2) + "\n")


def verify():
    metadata = json.loads((DESTINATION / "SOURCE.json").read_text())
    assert metadata["release"] == VERSION and metadata["commit"] == COMMIT
    assert metadata["archive_sha256"] == ARCHIVE_SHA256
    assert metadata["toml_version"] == "1.1.0" and metadata["index"] == INDEX
    assert metadata["counts"] == COUNTS
    verify_manifest_anchor(metadata["files_sha256"])
    files = validate_index((DESTINATION / INDEX).read_bytes())
    expected = {"LICENSE", INDEX} | {"tests/" + name for name in files}
    assert set(metadata["files_sha256"]) == expected, "manifest must cover every indexed file"
    actual = {str(path.relative_to(DESTINATION)) for path in DESTINATION.rglob("*") if path.is_file()}
    assert actual == expected | {"SOURCE.json"}, "unexpected or missing vendored files"
    for name, expected_hash in metadata["files_sha256"].items():
        assert digest((DESTINATION / name).read_bytes()) == expected_hash, name
    print(f"toml-test {VERSION} TOML 1.1.0: {COUNTS['valid']} valid, {COUNTS['invalid']} invalid; exact hashes verified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--import", dest="archive", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    if args.archive:
        import_archive(args.archive)
    verify()
