#!/usr/bin/env python3

import json
import tempfile
import unittest
from pathlib import Path

from run_typical_comparison import (
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


if __name__ == "__main__":
    unittest.main()
