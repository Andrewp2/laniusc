#!/usr/bin/env python3

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from run_compiler_stress_matrix import (
    available_compilers,
    available_lanes,
    collect_provenance,
    compiler_commands,
    lanes_for,
    materialize,
    parse_external_compilers,
    parse_pareas_timings,
    run_external,
    source_language,
    source_path,
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

    def test_tcc_library_path_is_optional(self) -> None:
        commands = compiler_commands(
            Path("repo"),
            tcc="/v/tcc.exe",
            tcc_runtime_path=Path("/v/lib/tcc"),
            tcc_library_path=Path("/v/lib/tcc"),
        )
        self.assertEqual(commands["default"]["tcc"][:3], ["/v/tcc.exe", "-B/v/lib/tcc", "-L/v/lib/tcc"])

    def test_moonbit_has_native_lanes_and_a_js_lane(self) -> None:
        self.assertEqual(parse_external_compilers("moonbit"), ("moonbit",))
        self.assertEqual(lanes_for("moonbit"), ("o0", "optimized", "js"))
        self.assertEqual(source_language("moonbit"), "moonbit")
        commands = compiler_commands(Path("repo"))
        self.assertEqual(commands["o0"]["moonbit"], ["moon", "build", "--target", "native", "--debug"])
        self.assertEqual(commands["optimized"]["moonbit"], ["moon", "build", "--target", "native", "--release"])
        self.assertEqual(commands["js"]["moonbit"], ["moon", "build", "--target", "js", "--release"])

    def test_missing_moon_drops_moonbit_with_a_message(self) -> None:
        stderr = io.StringIO()
        with mock.patch("moonbit_project.moon_available", return_value=False):
            with contextlib.redirect_stderr(stderr):
                compilers = available_compilers(("c", "moonbit", "go"))
        self.assertEqual(compilers, ("c", "go"))
        self.assertIn("moon not found; install MoonBit to include it", stderr.getvalue())

    def test_missing_node_drops_only_the_moonbit_js_lane(self) -> None:
        stderr = io.StringIO()
        with mock.patch("run_compiler_stress_matrix.shutil.which", return_value=None):
            with contextlib.redirect_stderr(stderr):
                lanes = available_lanes("moonbit", lanes_for("moonbit"))
        self.assertEqual(lanes, ("o0", "optimized"))
        self.assertIn("node not found", stderr.getvalue())
        self.assertEqual(available_lanes("c", ("o0", "optimized")), ("o0", "optimized"))

    def test_moonbit_builds_a_project_materialized_in_the_sample_workdir(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            size_dir = root / "sources/seed-20/1000"
            size_dir.mkdir(parents=True)
            source_text = "fn main {\n    println(7)\n}\n"
            (size_dir / "scaling.mbt").write_text(source_text)
            self.assertEqual(source_path(root / "sources", 20, "moonbit"), size_dir / "scaling.mbt")
            templates = compiler_commands(Path("repo"))
            for lane, artifact_tail, validator in (
                ("o0", "_build/native/debug/build/main/main.exe", "validate_executable"),
                ("js", "_build/js/release/build/main/main.js", "validate_javascript"),
            ):
                timing = {"wall_ms": 1.0, "compiler_ms": None}
                with mock.patch("run_compiler_stress_matrix.compile_process", return_value=dict(timing)) as compile_process, \
                        mock.patch(f"run_compiler_stress_matrix.{validator}", return_value="7\n") as validate:
                    _, stdout, (_, artifact) = run_external(
                        "moonbit", lane, 20, templates, root / "sources",
                        root / "bin", root, None, {20: "7\n"},
                    )
                workdir = root / f"bin/moonbit-{lane}-20.work"
                command, cwd = compile_process.call_args.args[:2]
                self.assertEqual(command, templates[lane]["moonbit"])
                self.assertEqual(cwd, workdir)
                self.assertEqual((workdir / "main/main.mbt").read_text(), source_text)
                self.assertIn('pkgtype(kind: "executable")', (workdir / "main/moon.pkg").read_text())
                self.assertTrue((workdir / "moon.mod").is_file())
                self.assertEqual(artifact, workdir / artifact_tail)
                validate.assert_called_once_with(artifact, "7\n")
                self.assertEqual(stdout, "7\n")

    def test_moonbit_provenance_records_moon_version_all(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            moon = Path(temporary) / "moon"
            moon.write_text("#!/bin/sh\nprintf 'moon 0.1.test\\nmoonc v0.test\\n'\n")
            moon.chmod(0o755)
            commands = compiler_commands(Path("repo"))
            for lane in lanes_for("moonbit"):
                commands[lane]["moonbit"] = [str(moon), *commands[lane]["moonbit"][1:]]
            repo = Path(__file__).resolve().parents[1]
            provenance = collect_provenance(repo, commands, ("moonbit",), include_lanius=False)
            self.assertEqual(provenance["tools"][str(moon)]["language"], "moonbit")
            self.assertEqual(
                provenance["tools"][str(moon)]["version"], "moon 0.1.test; moonc v0.test"
            )


if __name__ == "__main__":
    unittest.main()
