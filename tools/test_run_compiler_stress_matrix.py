#!/usr/bin/env python3

import unittest
from pathlib import Path

from run_compiler_stress_matrix import (
    compiler_commands,
    lanes_for,
    parse_external_compilers,
    parse_pareas_timings,
)


class CompilerStressMatrixTests(unittest.TestCase):
    def test_tcc_has_one_default_lane(self) -> None:
        self.assertEqual(parse_external_compilers("tcc"), ("tcc",))
        self.assertEqual(lanes_for("tcc"), ("default",))
        self.assertEqual(lanes_for("c"), ("o0", "optimized"))

    def test_pareas_has_one_cuda_lane_and_profiled_command(self) -> None:
        self.assertEqual(parse_external_compilers("pareas"), ("pareas",))
        self.assertEqual(lanes_for("pareas"), ("cuda",))
        commands = compiler_commands(Path("repo"), pareas="/opt/pareas")
        self.assertEqual(
            commands["cuda"]["pareas"],
            ["/opt/pareas", "-p", "1", "{source}", "-o", "{output}"],
        )

    def test_pareas_profile_is_frontend_and_backend_not_context_init(self) -> None:
        timings = parse_pareas_timings(
            "context init: 201990µs\nfrontend: 3325µs\nbackend: 2507µs\n"
        )
        self.assertEqual(
            timings,
            {
                "context_init_ms": 201.99,
                "frontend_ms": 3.325,
                "backend_ms": 2.507,
            },
        )

    def test_tcc_command_supports_an_extracted_runtime(self) -> None:
        commands = compiler_commands(
            Path("repo"),
            tcc="/opt/tcc/bin/tcc",
            tcc_runtime_path=Path("/opt/tcc/lib/tcc"),
        )
        self.assertEqual(
            commands["default"]["tcc"],
            [
                "/opt/tcc/bin/tcc",
                "-B/opt/tcc/lib/tcc",
                "-std=c11",
                "{source}",
                "-o",
                "{output}",
            ],
        )


if __name__ == "__main__":
    unittest.main()
