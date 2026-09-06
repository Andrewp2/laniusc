#!/usr/bin/env python3
"""Focused tests for extractor bootstrap configuration."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parent.parent
BOOTSTRAP = ROOT / "verified_compiler/bootstrap.py"


class BootstrapTests(unittest.TestCase):
    def test_independent_parse_output_capacity_overrides(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            subprocess.run(
                [sys.executable, str(BOOTSTRAP), "--prepare-only", "--surface",
                 "--output-dir", str(output), "--scale", "2",
                 "--workspace-words", "101", "--record-words", "202",
                 "--node-words", "303", "--output-words", "404"],
                cwd=ROOT, check=True, capture_output=True, text=True,
            )
            source = (output / "extractor.lani").read_text()

            self.assertIn("workspace, 101, records, 202", source)
            self.assertIn("offsets, 303, 1024", source)
            self.assertIn("output, 404", source)
            self.assertNotIn("@", source)


if __name__ == "__main__":
    unittest.main()
