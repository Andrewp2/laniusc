#!/usr/bin/env python3

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from generate_typical_project import generate
from run_typical_comparison import (
    LANES,
    available_languages,
    command_for,
    entry_source,
    lanes_for,
    parse_tcc_parallel_shards,
    parse_languages,
    partition_tcc_sources,
    source_language,
    tcc_lanes,
    write_canonical_tcc_results,
)


class TypicalComparisonTests(unittest.TestCase):
    def test_tcc_is_a_c_toolchain_with_one_honestly_named_lane(self) -> None:
        self.assertEqual(parse_languages("tcc"), ("tcc",))
        self.assertEqual(source_language("tcc"), "c")
        self.assertEqual(lanes_for("tcc"), ("default",))
        self.assertEqual(lanes_for("c"), ("o0", "optimized"))

    def test_parallel_tcc_lanes_are_explicit_and_selectable(self) -> None:
        shards = parse_tcc_parallel_shards("8,16,32")
        self.assertEqual(shards, (8, 16, 32))
        self.assertEqual(
            tcc_lanes(shards),
            ("default", "parallel-8", "parallel-16", "parallel-32"),
        )
        self.assertEqual(tcc_lanes(shards, include_serial=False), tcc_lanes(shards)[1:])

    def test_tcc_source_partitions_preserve_order_and_balance_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sources = []
            for index, size in enumerate((10, 20, 30, 40, 50, 60)):
                source = root / f"{index}.c"
                source.write_bytes(b"x" * size)
                sources.append(source)
            shards = partition_tcc_sources(sources, 3)

            self.assertEqual([source for shard in shards for source in shard], sources)
            self.assertEqual(len(shards), 3)
            self.assertTrue(all(shards))

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

    def test_parallel_tcc_uses_a_clean_ninja_partial_link_graph(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            project = Path(temporary)
            source_root = project / "c/src"
            source_root.mkdir(parents=True)
            for index in range(4):
                (source_root / f"{index}.c").write_text(f"int f{index}(void) {{ return {index}; }}\n")

            command, cwd, artifact, _ = command_for(
                project,
                "tcc",
                "parallel-2",
                0,
                1,
                "/opt/tcc/bin/tcc",
                Path("/opt/tcc/lib/tcc"),
            )

            self.assertEqual(command, ["ninja", "-f", "build-tcc-parallel-2.ninja", "-j", "2"])
            self.assertEqual(cwd, project / "c")
            self.assertEqual(artifact, project / "c/typical-project-tcc-parallel-2")
            graph = (project / "c/build-tcc-parallel-2.ninja").read_text()
            self.assertIn("-r -o $out $in", graph)
            self.assertIn("build typical-project-tcc-parallel-2: tcc_link", graph)

    def test_tcc_results_are_written_in_the_canonical_viewer_schema(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            source_root = repo / "target/typical-project-100/c/src"
            source_root.mkdir(parents=True)
            (source_root / "main.c").write_text("int main(void) { return 0; }\n")
            raw_output = repo / "raw.json"
            raw_output.write_text("{}\n")
            result_root = repo / "results"
            samples = [
                {
                    "file_count": 100,
                    "language": "tcc",
                    "lane": "default",
                    "sample": index,
                    "wall_ms": wall_ms,
                    "command": ["tcc", "src/main.c", "-o", "program"],
                }
                for index, wall_ms in enumerate((2.0, 4.0))
            ]
            machine = {
                "platform": "test-platform",
                "logical_cpus": 8,
                "gpu": "test-gpu",
                "versions": {"tcc": "tcc version test"},
            }

            paths = write_canonical_tcc_results(
                repo, result_root, raw_output, [100], 20260808, samples, machine
            )

            self.assertEqual(paths, [result_root / "frozen-typical-project-100-files-tcc.json"])
            result = json.loads(paths[0].read_text())
            self.assertEqual(result["schema"], "lanius.performance-run.v1")
            self.assertEqual(
                result["workload"]["comparison_group"],
                "typical-project/v1/seed-20260808/files-100",
            )
            measurement = result["measurements"][0]
            self.assertEqual(measurement["compiler"]["name"], "tcc")
            self.assertEqual(measurement["summary"]["wall_ms"]["median"], 3.0)
            self.assertNotIn("file_records", measurement["source"])

            parallel_samples = [
                {
                    "file_count": 100,
                    "language": "tcc",
                    "lane": "parallel-4",
                    "sample": index,
                    "wall_ms": wall_ms,
                    "command": ["ninja", "-f", "build-tcc-parallel-4.ninja", "-j", "4"],
                }
                for index, wall_ms in enumerate((1.0, 2.0))
            ]
            write_canonical_tcc_results(
                repo, result_root, raw_output, [100], 20260808, parallel_samples, machine
            )
            updated = json.loads(paths[0].read_text())
            self.assertEqual(
                [item["configuration"] for item in updated["measurements"]],
                ["default", "parallel-4"],
            )


    def test_moonbit_is_a_native_language_with_the_standard_lanes(self) -> None:
        self.assertEqual(parse_languages("c,moonbit"), ("c", "moonbit"))
        self.assertEqual(source_language("moonbit"), "moonbit")
        self.assertEqual(lanes_for("moonbit"), LANES)
        self.assertEqual(
            entry_source(Path("project"), "moonbit"),
            Path("project/moonbit/main/main.mbt"),
        )

    def test_moonbit_cleans_untimed_then_builds_the_native_backend(self) -> None:
        project = Path("project")
        for lane, flag, profile in (
            ("o0", "--debug", "debug"),
            ("optimized", "--release", "release"),
        ):
            with mock.patch("run_typical_comparison.run_checked") as run_checked:
                command, cwd, artifact, _ = command_for(project, "moonbit", lane, 0, 1)
            run_checked.assert_called_once()
            self.assertEqual(run_checked.call_args.args[:2], (["moon", "clean"], project / "moonbit"))
            self.assertEqual(command, ["moon", "build", "--target", "native", flag])
            self.assertEqual(cwd, project / "moonbit")
            self.assertEqual(
                artifact,
                project / f"moonbit/_build/native/{profile}/build/main/main.exe",
            )

    def test_missing_moon_skips_moonbit_with_a_message(self) -> None:
        stderr = io.StringIO()
        with mock.patch("moonbit_project.moon_available", return_value=False):
            with contextlib.redirect_stderr(stderr):
                languages = available_languages(("c", "moonbit", "rust"))
        self.assertEqual(languages, ("c", "rust"))
        self.assertIn("moon not found; install MoonBit to include it", stderr.getvalue())
        with mock.patch("moonbit_project.moon_available", return_value=True):
            self.assertEqual(available_languages(("moonbit",)), ("moonbit",))

    def test_generated_moonbit_project_is_one_package_per_module(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = generate(root, 6, 19)
            moonbit = root / "moonbit"
            self.assertEqual(
                (moonbit / "moon.mod").read_text(),
                'name = "lanius/typical"\nversion = "0.1.0"\n',
            )
            main_package = (moonbit / "main/moon.pkg").read_text()
            self.assertIn('pkgtype(kind: "executable")', main_package)
            self.assertIn('"moonbitlang/core/env",', main_package)
            self.assertFalse(list(moonbit.rglob("moon.pkg.json")))
            sources = sorted(moonbit.rglob("*.mbt"))
            self.assertEqual(len(sources), 6)
            self.assertEqual(manifest["languages"]["moonbit"]["source_file_count"], 6)
            for source in sources:
                package = source.parent
                self.assertTrue((package / "moon.pkg").is_file(), package)
                text = source.read_text()
                self.assertFalse(
                    [line for line in text.splitlines() if line.rstrip().endswith(";")],
                    source,
                )
                for imported in (package / "moon.pkg").read_text().splitlines():
                    name = imported.strip().strip('",')
                    if name.startswith("lanius/typical/"):
                        dependency = name.removeprefix("lanius/typical/")
                        self.assertTrue((moonbit / dependency).is_dir(), dependency)
                        self.assertIn(f"@{dependency}.", text)
            entry = (moonbit / "main/main.mbt").read_text()
            self.assertEqual(entry.count("fn main {"), 1)
            self.assertIn("println(total)", entry)
            self.assertIn("@env.args()", entry)
            self.assertEqual(
                manifest["commands"]["moonbit"]["build"],
                ["moon", "build", "--target", "native", "--debug"],
            )


if __name__ == "__main__":
    unittest.main()
