#!/usr/bin/env python3

import tempfile
import unittest
from pathlib import Path

import moonbit_project


class MoonbitProjectTests(unittest.TestCase):
    def test_single_file_project_uses_the_current_manifest_formats(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            entry = moonbit_project.write_single_file_project(
                root, "fn main {\n  println(1)\n}\n", ("moonbitlang/core/env",)
            )
            self.assertEqual(entry, root / "main/main.mbt")
            self.assertEqual(entry.read_text(), "fn main {\n  println(1)\n}\n")
            self.assertEqual(
                (root / "moon.mod").read_text(),
                'name = "lanius/bench"\nversion = "0.1.0"\n',
            )
            self.assertEqual(
                (root / "main/moon.pkg").read_text(),
                'import {\n  "moonbitlang/core/env",\n}\n\npkgtype(kind: "executable")\n',
            )
            self.assertFalse((root / "moon.mod.json").exists())
            self.assertFalse((root / "main/moon.pkg.json").exists())

    def test_library_package_without_imports_is_empty(self) -> None:
        self.assertEqual(moonbit_project.package_manifest(()), "")

    def test_build_commands_name_backend_and_profile(self) -> None:
        self.assertEqual(
            moonbit_project.build_command("native", "release"),
            ["moon", "build", "--target", "native", "--release"],
        )
        self.assertEqual(
            moonbit_project.build_command("wasm-gc", "debug", "/opt/moon"),
            ["/opt/moon", "build", "--target", "wasm-gc", "--debug"],
        )
        with self.assertRaises(ValueError):
            moonbit_project.build_command("llvm", "release")
        with self.assertRaises(ValueError):
            moonbit_project.build_command("native", "fast")

    def test_artifact_prefers_build_dir_and_falls_back_to_target(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            current = root / "_build/native/debug/build/main/main.exe"
            legacy = root / "target/native/debug/build/main/main.exe"
            self.assertEqual(moonbit_project.artifact_candidates(root, "native", "debug"), [current, legacy])
            self.assertEqual(moonbit_project.artifact_path(root, "native", "debug"), current)
            legacy.parent.mkdir(parents=True)
            legacy.write_text("")
            self.assertEqual(moonbit_project.artifact_path(root, "native", "debug"), legacy)
            self.assertEqual(
                moonbit_project.artifact_path(root, "js", "release"),
                root / "_build/js/release/build/main/main.js",
            )

    def test_missing_moon_reports_missing(self) -> None:
        missing = "/nonexistent/moon"
        self.assertFalse(moonbit_project.moon_available(missing))
        self.assertEqual(moonbit_project.version(missing), "missing")
        self.assertEqual(
            moonbit_project.MISSING_MESSAGE,
            "moon not found; install MoonBit to include it",
        )


if __name__ == "__main__":
    unittest.main()
