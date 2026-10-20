#!/usr/bin/env python3

import unittest
from pathlib import Path

from run_compiler_stress_matrix import (
    FASTEST_BASIS,
    FASTEST_LANE,
    compiler_commands,
    lanes_for,
    materialize,
    parse_external_compilers,
    parse_pareas_timings,
    source_language,
)


class CompilerStressMatrixTests(unittest.TestCase):
    def test_external_compilers_can_be_frozen_for_a_lanius_only_rerun(self) -> None:
        self.assertEqual(parse_external_compilers("none"), ())

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


    def test_added_compilers_and_their_lanes(self) -> None:
        self.assertEqual(
            parse_external_compilers("d,ldc,go,v,vx,tsc,tsrs"),
            ("d", "ldc", "go", "v", "vx", "tsc", "tsrs"),
        )
        self.assertEqual(lanes_for("tsc"), ("check_emit",))
        self.assertEqual(lanes_for("tsrs"), ("check_emit",))
        for language in ("d", "ldc", "go", "v", "vx"):
            self.assertEqual(lanes_for(language), ("o0", "optimized"))
        self.assertEqual(source_language("ldc"), "d")
        self.assertEqual(source_language("tsrs"), "ts")
        self.assertEqual(source_language("go"), "go")

    def test_added_compiler_commands(self) -> None:
        commands = compiler_commands(Path("repo"), toolchains=Path("/tc"))
        self.assertEqual(commands["o0"]["go"][1:3], ["build", "-gcflags=-N -l"])
        self.assertNotIn("-gcflags=-N -l", commands["optimized"]["go"])
        self.assertIn("-inline", commands["optimized"]["d"])
        self.assertNotIn("-O", commands["o0"]["d"])
        self.assertEqual(commands["optimized"]["ldc"][1:3], ["-O3", "-release"])
        self.assertIn("-prod", commands["optimized"]["v"])
        self.assertNotIn("-prod", commands["o0"]["v"])
        self.assertEqual(commands["check_emit"]["tsc"][-2:], commands["check_emit"]["tsrs"][-2:])
        compile_step, link_step = materialize(
            commands["optimized"]["vx"], Path("/s/scaling.vx"), Path("/b/out"), Path("/b/w")
        )
        self.assertEqual(compile_step[1:], ["-O2", "-c", "/s/scaling.vx", "-o", "/b/w/scaling.o"])
        self.assertIn("/b/w/scaling.o", link_step)
        self.assertEqual(link_step[link_step.index("-o") + 1], "/b/out")

    def test_fastest_lane_covers_every_external_compiler_but_pareas(self) -> None:
        commands = compiler_commands(Path("repo"), toolchains=Path("/tc"))
        self.assertEqual(set(commands[FASTEST_LANE]), set(FASTEST_BASIS))
        self.assertNotIn("pareas", FASTEST_BASIS)
        self.assertNotIn(FASTEST_LANE, lanes_for("c"))
        self.assertIn("-gcflags=-N -l -c=16", commands[FASTEST_LANE]["go"])
        compile_step, _ = materialize(
            commands[FASTEST_LANE]["vx"], Path("/s/scaling.vx"), Path("/b/out"), Path("/b/w")
        )
        self.assertEqual(compile_step[1:4], ["-O0", "-j", "16"])

    def test_tcc_library_path_is_optional(self) -> None:
        commands = compiler_commands(
            Path("repo"),
            tcc="/v/tcc.exe",
            tcc_runtime_path=Path("/v/lib/tcc"),
            tcc_library_path=Path("/v/lib/tcc"),
        )
        self.assertEqual(commands["default"]["tcc"][:3], ["/v/tcc.exe", "-B/v/lib/tcc", "-L/v/lib/tcc"])


if __name__ == "__main__":
    unittest.main()
