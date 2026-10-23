#!/usr/bin/env python3
"""Check the vendored Unicode source bytes; not a runtime library dependency."""
import gzip
import hashlib
import json
from pathlib import Path


def main():
    root = Path(__file__).resolve().parents[2] / "data/unicode/17.0.0"
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest["unicode_version"] != "17.0.0":
        raise ValueError("unexpected Unicode data version")
    for item in manifest["files"]:
        path = root / item["file"]
        if not path.resolve().is_relative_to(root.resolve()):
            raise ValueError("data path escapes versioned directory")
        if not item["url"].startswith("https://www.unicode.org/Public/17.0.0/ucd/"):
            raise ValueError("unexpected data source")
        packed = path.read_bytes()
        raw = gzip.decompress(packed)
        if hashlib.sha256(packed).hexdigest() != item["gzip_sha256"]:
            raise ValueError(f"compressed checksum mismatch: {path}")
        if len(raw) != item["bytes"] or hashlib.sha256(raw).hexdigest() != item["sha256"]:
            raise ValueError(f"source checksum mismatch: {path}")
    license_bytes = (root / "LICENSE.txt").read_bytes()
    if hashlib.sha256(license_bytes).hexdigest() != manifest["license_sha256"]:
        raise ValueError("Unicode license checksum mismatch")
    print(f"Unicode 17.0.0: {len(manifest['files'])} source files and license verified")


if __name__ == "__main__":
    main()
