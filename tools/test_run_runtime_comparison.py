#!/usr/bin/env python3

import contextlib
import io
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from run_runtime_comparison import (
    LANGUAGE_LANES,
    MOONBIT_IMPORTS,
    WORKLOADS,
    available_lanes,
    command_map,
    compile_lane,
    source_name,
    summarize,
)


class RuntimeComparisonTests(unittest.TestCase):
    def test_moonbit_lanes_cover_native_debug_release_and_js(self) -> None:
        self.assertEqual(
            [lane for language, lane in LANGUAGE_LANES if language == "moonbit"],
            ["debug", "optimized", "js"],
        )
        self.assertEqual(source_name("array_walk", "moonbit"), "array_walk.mbt")

    def test_every_workload_has_a_moonbit_twin(self) -> None:
        for workload in WORKLOADS.values():
            sources = workload.sources(5)
            source = sources["moonbit"]
            self.assertIn(f"fn {workload.name}(", source)
            self.assertIn("fn main {", source)
            self.assertIn("@env.args().length()", source)
            self.assertIn(f"println({workload.name}(5 + argc, argc))", source)
            self.assertFalse(
                [line for line in source.splitlines() if line.rstrip().endswith(";")],
                workload.name,
            )
            for constant in re.findall(r"% (\d+)", sources["c"]):
                self.assertIn(f"% {constant}", source, (workload.name, constant))

    def test_moonbit_twins_print_the_expected_checksum(self) -> None:
        for workload in WORKLOADS.values():
            # integer_mix needs enough iterations for its lanes to vary.
            iterations = 3000 if workload.name == "integer_mix" else 37
            stdout = run_moonbit_subset(workload.sources(iterations)["moonbit"])
            self.assertEqual(stdout, workload.expected_stdout(iterations), workload.name)

    def test_moonbit_commands_build_the_project_in_the_build_directory(self) -> None:
        repo = Path("/repo")
        bin_dir = repo / "target/runtime-comparison/integer_mix"
        commands = command_map(repo, repo / "benchmark_artifacts/x", bin_dir, "integer_mix")
        moonbit = commands["moonbit"]
        project = "target/runtime-comparison/integer_mix/moonbit"
        self.assertEqual(moonbit["debug"]["compile"], ["moon", "build", "--target", "native", "--debug"])
        self.assertEqual(moonbit["optimized"]["compile"], ["moon", "build", "--target", "native", "--release"])
        self.assertEqual(moonbit["js"]["compile"], ["moon", "build", "--target", "js", "--release"])
        for lane in moonbit.values():
            self.assertEqual(lane["cwd"], project)
        self.assertEqual(
            moonbit["optimized"]["artifact"],
            [
                f"{project}/_build/native/release/build/main/main.exe",
                f"{project}/target/native/release/build/main/main.exe",
            ],
        )
        self.assertEqual(
            moonbit["optimized"]["run"],
            ["target/runtime-comparison/integer_mix/moonbit-optimized"],
        )
        self.assertEqual(
            moonbit["js"]["run"],
            ["node", "target/runtime-comparison/integer_mix/moonbit-js.js"],
        )
        self.assertEqual(MOONBIT_IMPORTS, ("moonbitlang/core/env",))

    def test_missing_moon_skips_every_moonbit_lane_with_a_message(self) -> None:
        commands = command_map(Path("/repo"), Path("/repo/out"), Path("/repo/bin"), "integer_mix")
        stderr = io.StringIO()
        with mock.patch("moonbit_project.moon_available", return_value=False):
            with contextlib.redirect_stderr(stderr):
                lanes = available_lanes(commands)
        self.assertEqual(lanes, tuple(lane for lane in LANGUAGE_LANES if lane[0] != "moonbit"))
        self.assertIn("moon not found; install MoonBit to include it", stderr.getvalue())

    def test_missing_node_skips_only_the_moonbit_js_lane(self) -> None:
        commands = command_map(Path("/repo"), Path("/repo/out"), Path("/repo/bin"), "integer_mix")
        stderr = io.StringIO()
        with mock.patch("moonbit_project.moon_available", return_value=True), \
                mock.patch("run_runtime_comparison.tool_available", return_value=False):
            with contextlib.redirect_stderr(stderr):
                lanes = available_lanes(commands)
        self.assertEqual(lanes, tuple(lane for lane in LANGUAGE_LANES if lane != ("moonbit", "js")))
        self.assertIn("node not found", stderr.getvalue())

    def test_compile_lane_copies_the_artifact_moon_wrote(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary)
            bin_dir = repo / "bin"
            commands = command_map(repo, repo / "out", bin_dir, "integer_mix")
            command = commands["moonbit"]["optimized"]
            # An older toolchain layout: only the target/ candidate exists.
            legacy = repo / command["artifact"][1]
            legacy.parent.mkdir(parents=True)
            legacy.write_text("binary")
            with mock.patch("run_runtime_comparison.run_checked") as run_checked:
                compile_lane(command, repo)
            run_checked.assert_called_once_with(command["compile"], repo / command["cwd"], None)
            self.assertEqual((repo / command["output"]).read_text(), "binary")
            with mock.patch("run_runtime_comparison.run_checked"):
                legacy.unlink()
                with self.assertRaisesRegex(RuntimeError, "wrote no artifact"):
                    compile_lane(command, repo)

    def test_summary_covers_only_the_lanes_that_ran(self) -> None:
        lanes = (("c", "debug"), ("lanius", "default"))
        samples = [
            {"language": language, "lane": lane, "wall_ms": wall_ms}
            for (language, lane), wall_ms in zip(lanes, (4.0, 2.0))
        ]
        rows = summarize(samples, lanes)
        self.assertEqual([(row["language"], row["lane"]) for row in rows], list(lanes))
        self.assertEqual(rows[0]["lanius_speedup"], 2.0)


def run_moonbit_subset(source: str) -> str:
    """Execute a runtime twin by translating its MoonBit subset to Python.

    The twins use one statement per line, braces at line ends, and Int values
    that never wrap or go negative under % and /, so the translation is exact.
    `@env.args()` is the native argv: just the program.
    """
    lines = []
    body_indent = None
    for raw in source.splitlines():
        line = raw.rstrip()
        stripped = line.strip()
        indent = line[: len(line) - len(line.lstrip())]
        if not stripped or stripped.startswith("//"):
            continue
        if stripped == "}":
            if indent == "" and lines and body_indent is not None:
                # A function body ends with its result expression.
                last = lines[-1]
                if last.startswith(body_indent) and not last[len(body_indent):].startswith(" "):
                    expression = last.strip()
                    if not re.match(r"(if|while|else|return)\b|\w+ = ", expression):
                        lines[-1] = f"{body_indent}return {expression}"
            continue
        if match := re.fullmatch(r"fn (\w+)\((.*)\) -> Int \{", stripped):
            parameters = ", ".join(
                part.split(":")[0].strip() for part in match.group(2).split(",")
            )
            lines.append(f"def {match.group(1)}({parameters}):")
            body_indent = "    "
            continue
        if stripped == "fn main {":
            lines.append("def main():")
            continue
        if stripped == "} else {":
            lines.append(f"{indent}else:")
            continue
        if match := re.fullmatch(r"(if|while) (.*) \{", stripped):
            lines.append(f"{indent}{match.group(1)} {match.group(2)}:")
            continue
        stripped = re.sub(r"^let (?:mut )?(\w+)(?: : [\w\[\]]+)? = ", r"\1 = ", stripped)
        stripped = re.sub(
            r"if (.+?) \{ (.+?) \} else \{ (.+?) \}", r"(\2 if \1 else \3)", stripped
        )
        stripped = stripped.replace("@env.args().length()", "1").replace(" / ", " // ")
        stripped = stripped.replace("println(", "print(")
        if "{" in stripped or "}" in stripped:
            raise AssertionError(f"untranslated MoonBit line: {raw!r}")
        lines.append(indent + stripped)
    namespace: dict[str, object] = {}
    stdout = io.StringIO()
    with contextlib.redirect_stdout(stdout):
        exec("\n".join(lines) + "\nmain()\n", namespace)
    return stdout.getvalue()


if __name__ == "__main__":
    unittest.main()
