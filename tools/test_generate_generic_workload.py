import re
import tempfile
import unittest
from pathlib import Path

from generate_generic_workload import (
    build_workload,
    expected_stdout,
    kinds_for,
    largest_workload_that_fits,
    render_project,
    render_single_file,
    statistics,
    write_probes,
)


class SingleFileTests(unittest.TestCase):
    def test_is_deterministic_and_exactly_the_target_size(self):
        kinds = kinds_for(False)
        leaves = largest_workload_that_fits(7, 60_000, kinds)
        first = render_single_file(build_workload(7, leaves, kinds), 60_000)
        second = render_single_file(build_workload(7, leaves, kinds), 60_000)

        self.assertEqual(first, second)
        self.assertEqual(len(first.encode()), 60_000)
        self.assertTrue(first.startswith("module bench::generic;"))

    def test_expected_stdout_is_area_checksums_then_their_masked_total(self):
        workload = build_workload(7, 100, kinds_for(False))
        lines = [int(line) for line in expected_stdout(workload).splitlines()]

        self.assertEqual(len(lines), len(workload.areas) + 1)
        self.assertTrue(all(0 <= value <= 4095 for value in lines))
        self.assertEqual(lines[-1], sum(lines[:-1]) & 4095)

    def test_type_pool_reduces_distinct_instantiations(self):
        kinds = kinds_for(False)
        wide = build_workload(7, 200, kinds)
        narrow = build_workload(7, 200, kinds, type_pool=4)
        wide_stats = statistics({"generic.lani": render_single_file(wide)}, wide)
        narrow_stats = statistics({"generic.lani": render_single_file(narrow)}, narrow)

        self.assertLess(narrow_stats["generic_body_specializations"], wide_stats["generic_body_specializations"])
        self.assertLess(narrow_stats["distinct_concrete_type_applications"],
                        wide_stats["distinct_concrete_type_applications"])

    def test_backlog_kinds_are_opt_in(self):
        self.assertNotIn("twice_bound", kinds_for(False))
        self.assertIn("twice_bound", kinds_for(True))


class ProjectTests(unittest.TestCase):
    def test_main_imports_the_library_and_every_area_module(self):
        workload = build_workload(7, 100, kinds_for(False))
        sources = render_project(workload)
        main = sources["lanius/main.lani"]

        self.assertIn("lanius/src/gen/lib.lani", sources)
        self.assertTrue(sources["lanius/src/gen/lib.lani"].startswith("module gen::lib;"))
        areas = [path for path in sources if path.startswith("lanius/src/gen/") and not path.endswith("/lib.lani")]
        self.assertEqual(len(areas), len(workload.areas))
        for path in areas:
            module = Path(path).stem
            self.assertIn(f"import gen::{module};", main)
            self.assertTrue(sources[path].startswith(f"module gen::{module};"))

    def test_area_modules_only_import_earlier_areas(self):
        # Seed 20 with the full profile picked records of later areas, and the
        # project failed with an import cycle (LNC0002).
        workload = build_workload(20, 928, kinds_for(False), acyclic_areas=True)
        sources = render_project(workload)
        order = {area.name: area.index for area in workload.areas}
        for path, text in sources.items():
            module = Path(path).stem
            if module not in order:
                continue
            for imported in re.findall(r"(?m)^import gen::(\w+);", text):
                if imported in order:
                    self.assertLess(order[imported], order[module], f"{module} imports {imported}")


class ProbeTests(unittest.TestCase):
    def test_every_probe_states_a_matrix_exit_code(self):
        with tempfile.TemporaryDirectory() as directory:
            write_probes(Path(directory), 7, kinds_for(False))
            probes = sorted(Path(directory).glob("g_*.lani"))

            self.assertGreater(len(probes), 10)
            for probe in probes:
                match = re.match(r"// expect: (\d+)\n", probe.read_text())
                self.assertIsNotNone(match, probe.name)
                self.assertLess(int(match.group(1)), 128)


if __name__ == "__main__":
    unittest.main()
