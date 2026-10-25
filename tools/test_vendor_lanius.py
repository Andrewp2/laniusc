#!/usr/bin/env python3
"""Focused invariants for the source distribution tool (no GPU required)."""
import hashlib
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import vendor_lanius as vendor


class VendorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def inventory(self):
        records = []
        for path in sorted(self.root.rglob("*"),
                           key=lambda path: path.relative_to(self.root).as_posix()):
            if path.is_file() and path.name != "SHA256SUMS":
                records.append(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  "
                               f"{path.relative_to(self.root).as_posix()}\n")
        (self.root / "SHA256SUMS").write_text("".join(records))

    def minimal_bundle(self):
        (self.root / "lanius.package.json").write_text("{}\n")
        (self.root / "BUNDLE.txt").write_text("test bundle\n")
        (self.root / "entry.lani").write_text("module app::main; fn main() { return 0; }\n")
        self.inventory()

    def test_published_fnv1a_vectors(self):
        self.assertEqual(vendor.fnv1a64(b""), "fnv1a64:cbf29ce484222325")
        self.assertEqual(vendor.fnv1a64(b"a"), "fnv1a64:af63dc4c8601ec8c")
        self.assertEqual(vendor.fnv1a64(b"foobar"), "fnv1a64:85944171f73967e8")

    def test_file_and_nested_module_paths_have_one_inventory_order(self):
        self.minimal_bundle()
        nested = self.root / "sources/0000/app"
        nested.mkdir(parents=True)
        nested.with_suffix(".lani").write_text("module app;\n")
        (nested / "main.lani").write_text("module app::main;\n")
        self.inventory()
        self.assertEqual(vendor.verify(self.root)[0], 5)

    def test_nonregular_notice_rejected_without_waiting_for_writer(self):
        fifo = self.root / "notice-fifo"
        os.mkfifo(fifo)
        with self.assertRaisesRegex(vendor.VendorError, "not a regular file"):
            vendor.open_regular(fifo)
        with self.assertRaisesRegex(vendor.VendorError, "not a regular file"):
            vendor.open_regular(self.root)

    def test_valid_inventory_and_all_content_mutations(self):
        self.minimal_bundle()
        count, size = vendor.verify(self.root)
        self.assertEqual(count, 3)
        self.assertGreater(size, 0)
        entry = self.root / "entry.lani"
        original = entry.read_bytes()
        for index in range(len(original)):
            modified = bytearray(original)
            modified[index] ^= 1
            entry.write_bytes(modified)
            with self.assertRaisesRegex(vendor.VendorError, "content mismatch"):
                vendor.verify(self.root)
        entry.write_bytes(original)
        self.assertEqual(vendor.verify(self.root), (count, size))

    def test_added_and_missing_sources_are_rejected(self):
        self.minimal_bundle()
        extra = self.root / "new.lani"
        extra.write_text("module hidden::new;\n")
        with self.assertRaisesRegex(vendor.VendorError, "unlisted"):
            vendor.verify(self.root)
        extra.unlink()
        (self.root / "entry.lani").unlink()
        with self.assertRaisesRegex(vendor.VendorError, "missing bundle files"):
            vendor.verify(self.root)

    def test_symlinked_files_and_directories_are_rejected(self):
        self.minimal_bundle()
        entry = self.root / "entry.lani"
        entry.unlink()
        entry.symlink_to("BUNDLE.txt")
        with self.assertRaisesRegex(vendor.VendorError, "symlink"):
            vendor.verify(self.root)
        entry.unlink()
        (self.root / "linked-dir").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(vendor.VendorError, "symlink"):
            vendor.verify(self.root)

    def test_inventory_paths_cannot_escape_or_duplicate(self):
        self.minimal_bundle()
        for path in ("../secret", "/etc/passwd", "a/../../b", "a//b", "a/./b", "a\\b"):
            with self.assertRaises(vendor.VendorError, msg=path):
                vendor.relative_path(path)
        original = (self.root / "SHA256SUMS").read_text()
        (self.root / "SHA256SUMS").write_text(original + original.splitlines(True)[-1])
        with self.assertRaisesRegex(vendor.VendorError, "duplicate"):
            vendor.verify(self.root)

    def test_verification_bounds_payload_reads(self):
        self.minimal_bundle()
        with patch.object(vendor, "MAX_PAYLOAD_BYTES", 2):
            with self.assertRaisesRegex(vendor.VendorError, "byte limit"):
                vendor.verify(self.root)

    def plan_document(self):
        source = self.root / "src/app/main.lani"
        source.parent.mkdir(parents=True)
        source.write_text("module app::main; fn main() { return 0; }\n")
        data = source.read_bytes()
        document = {
            "roots": [str(self.root / "src")],
            "inputs": {"files": [{"library_id": 1, "path": str(source),
                                    "byte_len": len(data), "digest": vendor.fnv1a64(data)}]},
            "source_identities": {"files": [{"library_id": 1, "path": str(source),
                "source_root_index": 0, "source_root_relative_path": "app/main.lani"}]},
        }
        return document

    def test_source_plan_preserves_identity_and_enforces_limits(self):
        document = self.plan_document()
        plan = vendor.source_plan(document, 1, 100)
        self.assertEqual(plan[0][1], "sources/0000/app/main.lani")
        with self.assertRaisesRegex(vendor.VendorError, "file limit"):
            vendor.source_plan(document, 0, 100)
        with self.assertRaisesRegex(vendor.VendorError, "byte limit"):
            vendor.source_plan(document, 1, 1)
        identity = document["source_identities"]["files"][0]
        identity["source_root_relative_path"] = "../escape.lani"
        with self.assertRaisesRegex(vendor.VendorError, "invalid inventory path"):
            vendor.source_plan(document, 1, 100)

    def test_existing_output_is_never_modified(self):
        manifest = self.root / "input.json"
        manifest.write_text("{}")
        output = self.root / "owned"
        output.mkdir()
        marker = output / "keep"
        marker.write_text("original")
        with self.assertRaises(FileExistsError):
            vendor.vendor(manifest, output, "must-not-run", [], 1, 100)
        self.assertEqual(marker.read_text(), "original")
        self.assertEqual(list(output.iterdir()), [marker])

    def test_lock_failure_removes_only_new_output(self):
        manifest = self.root / "input.json"
        manifest.write_text("{}")
        output = self.root / "new"
        with patch.object(vendor, "lock", side_effect=vendor.VendorError("deliberate")):
            with self.assertRaisesRegex(vendor.VendorError, "deliberate"):
                vendor.vendor(manifest, output, "unused", [], 1, 100)
        self.assertFalse(output.exists())
        self.assertEqual(manifest.read_text(), "{}")


if __name__ == "__main__":
    unittest.main()
