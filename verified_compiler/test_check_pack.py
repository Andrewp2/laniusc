#!/usr/bin/env python3
"""Focused tests for generated-pack scheduling and freshness."""

import os
from pathlib import Path
import tempfile
import unittest

from check_pack import generated_dependencies, is_fresh, unit_directories


class PackCheckerTests(unittest.TestCase):
    def test_units_are_checked_in_numeric_order(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            closure = root / "SelfClosure"
            for name in ("Unit10", "Unit2", "Unit1", "Notes"):
                (closure / name).mkdir(parents=True)

            self.assertEqual(
                [path.name for path in unit_directories(root)],
                ["Unit1", "Unit2", "Unit10"],
            )

    def test_validity_depends_on_both_independent_proof_phases(self):
        root = Path("/generated")
        source = root / "SelfClosure/Unit3/Valid.lean"

        self.assertEqual(
            generated_dependencies(root, source),
            [root / "SelfClosure/Unit3/Nodes.olean",
             root / "SelfClosure/Unit3/Metadata.olean"],
        )

    def test_freshness_invalidates_when_a_dependency_is_newer(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "View.lean"
            dependency = root / "Data.olean"
            boundary = root / "ParseChunks.olean"
            output = root / "View.olean"
            for path in (source, dependency, boundary, output):
                path.touch()
            os.utime(source, (1, 1))
            os.utime(dependency, (2, 2))
            os.utime(boundary, (3, 3))
            os.utime(output, (4, 4))
            self.assertTrue(is_fresh(output, source, [dependency], boundary))

            os.utime(dependency, (5, 5))
            self.assertFalse(is_fresh(output, source, [dependency], boundary))


if __name__ == "__main__":
    unittest.main()
