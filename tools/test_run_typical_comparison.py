#!/usr/bin/env python3

import tempfile
import unittest
from pathlib import Path

from run_typical_comparison import (
    command_for,
    entry_source,
    lanes_for,
    parse_languages,
    source_language,
)


class TypicalComparisonTests(unittest.TestCase):
    def test_tcc_is_a_c_toolchain_with_one_honestly_named_lane(self) -> None:
        self.assertEqual(parse_languages("tcc"), ("tcc",))
        self.assertEqual(source_language("tcc"), "c")
        self.assertEqual(lanes_for("tcc"), ("default",))
        self.assertEqual(lanes_for("c"), ("o0", "optimized"))

    def test_tcc_uses_the_c_entry_source(self) -> None:
        project = Path("project")
        self.assertEqual(entry_source(project, "tcc"), project / "c/src/main.c")

    def test_tcc_compiles_all_c_sources_in_one_process(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            source_root = project / "c/src"
            source_root.mkdir(parents=True)
            (source_root / "second.c").write_text("int second(void) { return 2; }\n")
            (source_root / "main.c").write_text("int main(void) { return 0; }\n")

            command, cwd, artifact, _ = command_for(project, "tcc", "default", 0, 1)

            self.assertEqual(command[:4], ["tcc", "-std=c11", "-Iinclude", "-o"])
            self.assertEqual(command[5:], ["src/main.c", "src/second.c"])
            self.assertEqual(cwd, project / "c")
            self.assertEqual(artifact, project / "c/typical-project-tcc")

    def test_tcc_can_use_an_extracted_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            source_root = project / "c/src"
            source_root.mkdir(parents=True)
            (source_root / "main.c").write_text("int main(void) { return 0; }\n")

            command, _, _, _ = command_for(
                project,
                "tcc",
                "default",
                0,
                1,
                "/opt/tcc/bin/tcc",
                Path("/opt/tcc/lib/tcc"),
            )

            self.assertEqual(
                command[:2],
                ["/opt/tcc/bin/tcc", "-B/opt/tcc/lib/tcc"],
            )


if __name__ == "__main__":
    unittest.main()
