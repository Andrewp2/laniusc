#!/usr/bin/env python3
"""Tests for the helpers of tools/startup_bench.py and tools/prime_probe.py (no daemon, no GPU)."""
import os
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from prime_probe import created_anything, group_creations, schedule  # noqa: E402
from startup_bench import daemon_env, parse_args, summary, thread_states  # noqa: E402


class StartupBenchTests(unittest.TestCase):
    def test_env_substitutes_the_tag(self):
        env = daemon_env({"A": "1"}, ["LANIUS_PERFETTO_TRACE=/x/{tag}.json", "B=c=d"], "run3")
        self.assertEqual(env, {"A": "1", "LANIUS_PERFETTO_TRACE": "/x/run3.json", "B": "c=d"})

    def test_summary(self):
        self.assertEqual(summary([690, 658, 656, 696, 675], [773.3, 756.7]),
                         "SUMMARY ready median 675 ms max 696 ms ['690', '658', '656', '696', '675']; "
                         "first job median 765.0 ms ['773.3', '756.7']")
        self.assertNotIn("first job", summary([1.0], []))

    def test_thread_states_of_this_process(self):
        states = thread_states(os.getpid())
        self.assertTrue(states)
        (name, state, _), ticks = next(iter(states.items()))
        self.assertTrue(name)
        self.assertIn(state[0], "RSDTtZXIPWK")
        self.assertGreaterEqual(sum(ticks), 0)

    def test_default_stdlib_root_is_the_repo_stdlib(self):
        a = parse_args(["--laniusc", "x", "--out", "y"])
        self.assertEqual(pathlib.Path(a.stdlib_root), pathlib.Path(__file__).resolve().parents[1] / "stdlib")


class PrimeProbeTests(unittest.TestCase):
    def test_groups_creations_by_label_prefix(self):
        response = {"resource_creation_breakdown": {
            "buffers": [{"label": "type_check.interface.decls.rows", "created": 2},
                        {"label": "type_check.interface.decls.keys", "created": 3},
                        {"label": "readback.gather", "created": 1}],
            "bind_groups": [{"label": "program_evidence.bindings.a.b", "created": 4}]}}
        bufs, bgs = group_creations(response)
        self.assertEqual(bufs, {"type_check.interface.decls": 5, "readback.gather": 1})
        self.assertEqual(bgs, {"program_evidence.bindings.a": 4})
        self.assertEqual(group_creations({}), ({}, {}))

    def test_created_anything(self):
        self.assertTrue(created_anything({"resources_created_during_job": {"bind_groups": 1}}))
        self.assertFalse(created_anything({"resources_created_during_job": {"buffers": 0}}))

    def test_schedule_follows_lanius_perf(self):
        seeds = schedule()
        self.assertEqual(seeds[0], (20, "prime", 6))
        self.assertEqual(seeds[20], (19, "prime", 6))
        self.assertEqual(seeds[21:], [(20, "measure", 1), (21, "measure", 1), (22, "measure", 1)])


if __name__ == "__main__":
    unittest.main()
