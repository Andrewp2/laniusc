import re
import tempfile
import unittest
from pathlib import Path

from generate_generic_workload import Step, build_area
from generate_stdlib_workload import (
    BACKLOG_KINDS,
    STEP_KINDS,
    Set,
    Vec,
    build_workload,
    evaluate_step,
    expected_stdout,
    kinds_for,
    largest_workload_that_fits,
    render_single_file,
    render_step,
    statistics,
    write_probes,
)


class ContainerModelTests(unittest.TestCase):
    """The models follow stdlib/core/vec.lani and set.lani: failures change nothing."""

    def test_vec_operations_that_fail_return_the_vector_unchanged(self):
        full = Vec(2, [1, 2])
        self.assertEqual(full.try_push(3).items, [1, 2])
        self.assertEqual(full.try_insert(0, 3).items, [1, 2])
        self.assertEqual(full.try_remove(2).items, [1, 2])
        self.assertEqual(full.try_swap(0, 2).items, [1, 2])
        self.assertEqual(full.try_set(-1, 9).items, [1, 2])
        self.assertEqual(full.truncate(2).items, [1, 2])
        self.assertEqual(full.truncate(-1).items, [1, 2])
        self.assertEqual(Vec(2).try_pop().items, [])

    def test_vec_operations_that_succeed(self):
        v = Vec(4, [1, 2, 3])
        self.assertEqual(v.try_insert(3, 4).items, [1, 2, 3, 4])
        self.assertEqual(v.try_insert(1, 9).items, [1, 9, 2, 3])
        self.assertEqual(v.try_remove(0).items, [2, 3])
        self.assertEqual(v.try_swap(0, 2).items, [3, 2, 1])
        self.assertEqual(v.reverse().truncate(1).items, [3])
        self.assertEqual(v.get_or(3, 7), 7)
        self.assertIsNone(Vec(4).last())
        self.assertEqual(v.items, [1, 2, 3])  # value semantics

    def test_set_keeps_insertion_order_and_ignores_present_items(self):
        s = Set(3).try_insert(5).try_insert(1).try_insert(5).try_insert(2).try_insert(4)
        self.assertEqual(s.items, [5, 1, 2])
        self.assertEqual(s.try_remove(5).items, [1, 2])
        self.assertEqual(s.try_remove(9).items, [5, 1, 2])
        self.assertTrue(s.try_remove(1).is_subset(s))
        self.assertFalse(s.is_subset(s.try_remove(1)))
        self.assertEqual(s.position_or(9, -1), -1)


class StepTests(unittest.TestCase):
    def test_every_kind_renders_and_keeps_values_in_range(self):
        area = build_area(7, 0)
        record = area.records[0]
        kinds = {**STEP_KINDS, **BACKLOG_KINDS}
        for kind, (_, _, needs_record) in sorted(kinds.items()):
            for c in range(64):
                step = Step(kind, 1000 + c, 3000 - c, c * 977, record if needs_record else None,
                            area.records[1] if needs_record else None)
                lines = render_step(area, step, 0)
                self.assertTrue(lines, kind)
                for value, x in ((0, 0), (4095, 4095), (1234, 77)):
                    result = evaluate_step(step, value, x)
                    self.assertTrue(0 <= result <= 4095, (kind, c, value, x, result))

    def test_stdlib_calls_name_existing_core_items(self):
        # Every core:: call in a rendered program is one of the pilot API's functions.
        api = {
            "vec": {"from_storage", "from_array", "len", "capacity", "is_empty", "is_full", "try_push",
                    "try_pop", "get", "get_or", "first", "last", "try_set", "try_insert", "try_remove",
                    "try_swap", "reverse", "truncate", "clear"},
            "set": {"from_storage", "len", "capacity", "is_empty", "contains", "position_or", "get",
                    "at_or", "try_insert", "try_remove", "clear", "is_subset"},
            "pair": {"new", "first", "second", "swap", "zip"},
            "option": {"Some", "None", "is_some", "is_none", "unwrap_or", "or", "and", "xor", "flatten"},
            "result": {"Ok", "Err", "is_ok", "is_err", "unwrap_or", "unwrap_err_or", "or", "and"},
        }
        kinds = kinds_for(True)
        source = render_single_file(build_workload(7, 200, kinds))
        for module, name in re.findall(r"\bcore::(\w+)::(\w+)\s*\(", source):
            self.assertIn(name, api[module], f"core::{module}::{name}")


class ProgramTests(unittest.TestCase):
    def test_is_deterministic_and_exactly_the_target_size(self):
        kinds = kinds_for(False)
        leaves = largest_workload_that_fits(7, 80_000, kinds)
        first = render_single_file(build_workload(7, leaves, kinds), 80_000)
        second = render_single_file(build_workload(7, leaves, kinds), 80_000)

        self.assertEqual(first, second)
        self.assertEqual(len(first.encode()), 80_000)
        self.assertTrue(first.startswith("module bench::stdlib_generic;\n\nimport core::option;"))

    def test_expected_stdout_is_area_checksums_then_their_masked_total(self):
        workload = build_workload(7, 100, kinds_for(False))
        lines = [int(line) for line in expected_stdout(workload).splitlines()]

        self.assertEqual(len(lines), len(workload.areas) + 1)
        self.assertTrue(all(0 <= value <= 4095 for value in lines))
        self.assertEqual(lines[-1], sum(lines[:-1]) & 4095)

    def test_type_pool_reduces_specializations(self):
        kinds = kinds_for(False)
        wide = build_workload(7, 300, kinds)
        narrow = build_workload(7, 300, kinds, type_pool=4)
        wide_stats = statistics(render_single_file(wide), wide)
        narrow_stats = statistics(render_single_file(narrow), narrow)

        self.assertLess(narrow_stats["generic_body_specializations"], wide_stats["generic_body_specializations"])

    def test_record_keys_only_with_backlog(self):
        default = render_single_file(build_workload(7, 200, kinds_for(False)))
        backlog = render_single_file(build_workload(7, 200, kinds_for(True)))

        self.assertNotIn("core::set::Key for", default)
        self.assertIn("pub impl core::set::Key for", backlog)

    def test_probes_cover_every_kind_with_an_expectation(self):
        with tempfile.TemporaryDirectory() as directory:
            kinds = kinds_for(False)
            write_probes(Path(directory), 7, kinds)
            probes = sorted(Path(directory).glob("*.lani"))

            self.assertEqual(len(probes), len(kinds) + 1)
            for probe in probes:
                self.assertRegex(probe.read_text().splitlines()[0], r"^// expect: \d+$")


if __name__ == "__main__":
    unittest.main()
