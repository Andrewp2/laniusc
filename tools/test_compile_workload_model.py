#!/usr/bin/env python3
"""Focused contracts for the comparative compiler workload model."""

import unittest

from compile_workload_model import WORKLOAD_PROFILES, build_workload, evaluate, render
from generate_compile_scaling_sources import largest_workload_that_fits


class WorkloadModelTests(unittest.TestCase):
    def test_profiles_are_deterministic_and_fully_reachable(self) -> None:
        for profile in WORKLOAD_PROFILES:
            first = build_workload(19, 256, profile)
            second = build_workload(19, 256, profile)
            self.assertEqual(first, second)
            self.assertEqual(first.function_count, first.structure()["reachable_function_count"])
            self.assertIsInstance(evaluate(first), int)

    def test_typical_profile_keeps_the_common_function_small(self) -> None:
        summary = build_workload(19, 4096, "typical").structure()[
            "function_body_line_summary"
        ]
        self.assertLessEqual(summary["p50"], 10)
        self.assertLessEqual(summary["p90"], 40)
        self.assertGreater(summary["max"], summary["p99"])

    def test_long_tail_contains_very_large_functions_only_at_project_scale(self) -> None:
        small = build_workload(19, 64, "long-tail").structure()
        large = build_workload(19, 4096, "long-tail").structure()
        self.assertNotIn("very_large", small["leaf_size_class_counts"])
        self.assertGreater(large["leaf_size_class_counts"].get("very_large", 0), 0)
        self.assertGreater(large["function_body_line_summary"]["max"], 8_000)

    def test_profile_size_solver_leaves_little_comment_padding(self) -> None:
        for profile in WORKLOAD_PROFILES:
            for target_bytes in (100_000, 1_000_000):
                leaf_count = largest_workload_that_fits(19, target_bytes, profile)
                source_bytes = len(
                    render("lanius", build_workload(19, leaf_count, profile)).encode()
                )
                self.assertLess(target_bytes - source_bytes, target_bytes // 50)

    def test_adding_a_leaf_increases_every_rendered_source(self) -> None:
        for profile in WORKLOAD_PROFILES:
            smaller = build_workload(23, 64, profile)
            larger = build_workload(23, 65, profile)
            for language in ("rust", "c", "cpp", "zig", "lanius"):
                self.assertGreater(len(render(language, larger)), len(render(language, smaller)))


if __name__ == "__main__":
    unittest.main()
