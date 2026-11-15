#!/usr/bin/env python3
"""Capture-completeness regressions; no GPU or Nsight installation needed."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from tools.validate_nsight_capture import validate


class CaptureCoverageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.export = self.root / "BASE_UNLOCKED"
        self.export.mkdir()
        (self.export / "REPRO_INFO.xls").write_text(
            "Start After\tNGFX SDK Controlled\nLimited To\tNGFX SDK Controlled\n")
        self.receipt = {
            "schema": "lanius.nsight-workload.v1", "token": "test",
            "complete": True, "sdk_start": 0, "sdk_stop": 0,
            "capture_elapsed_ms": 500,
        }
        self.write_receipt()
        self.write_events(["lanius.capture.test.begin", "lexer", "link", "lanius.capture.test.end"])
        (self.root / "nsight.log").write_text("Succeeded to export data:\n")

    def write_receipt(self):
        (self.root / "workload-complete.json").write_text(json.dumps(self.receipt))

    def write_events(self, names):
        (self.export / "D3DPERF_EVENTS.xls").write_text(
            "event_text\ttime_ms\n" + "".join(f"{name}\t0.1\n" for name in names))

    def test_complete_workload(self):
        result = validate(self.root, "test", 9999)
        self.assertTrue(result["complete"])
        self.assertEqual(result["labeled_events"], 2)

    def test_missing_reversed_duplicate_and_leaked_work(self):
        for names in [
            ["lanius.capture.test.begin", "lexer"],
            ["link", "lanius.capture.test.end"],
            ["lanius.capture.test.end", "lexer", "lanius.capture.test.begin"],
            ["lanius.capture.test.begin", "lanius.capture.test.begin", "link", "lanius.capture.test.end"],
            ["warmup", "lanius.capture.test.begin", "link", "lanius.capture.test.end"],
            ["lanius.capture.test.begin", "link", "lanius.capture.test.end", "next build"],
            ["lanius.capture.test.begin", "lanius.capture.test.end"],
        ]:
            with self.subTest(names=names), self.assertRaises(ValueError):
                self.write_events(names)
                validate(self.root, "test", 9999)

    def test_success_exit_and_markers_do_not_excuse_lost_data(self):
        for warning in ["TARGET WARNING: Timestamp overflow. Trace may be missing some data.",
                        "Events dropped", "event buffer too small", "trace truncated"]:
            with self.subTest(warning=warning), self.assertRaisesRegex(ValueError, "lost trace data"):
                (self.root / "nsight.log").write_text(f"{warning}\nSucceeded to export data:\n")
                validate(self.root, "test", 9999)

    def test_completion_is_fresh_and_within_the_limit(self):
        for change in [{"token": "old"}, {"complete": False}, {"sdk_start": 6},
                       {"sdk_stop": 6}, {"capture_elapsed_ms": 9999},
                       {"capture_elapsed_ms": float("nan")}]:
            with self.subTest(change=change), self.assertRaises(ValueError):
                original = self.receipt.copy()
                self.receipt.update(change)
                self.write_receipt()
                self.receipt = original
                validate(self.root, "test", 9999)
        (self.root / "workload-complete.json").unlink()
        with self.assertRaises(FileNotFoundError):
            validate(self.root, "test", 9999)

    def test_time_window_is_not_a_workload_boundary(self):
        (self.export / "REPRO_INFO.xls").write_text(
            "Start After\tElapsed Time 15000 ms\nLimited To\tMax Duration\n")
        with self.assertRaisesRegex(ValueError, "not bounded by SDK"):
            validate(self.root, "test", 9999)


class WrapperTests(unittest.TestCase):
    def test_wrapper_rejects_partial_capture_even_when_ngfx_exits_zero(self):
        wrapper = Path(__file__).resolve().parent / "run_nsight_gpu_trace.sh"
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            sdk = root / "sdk"
            sdk.mkdir()
            (sdk / "NGFX_GPUTrace_Vulkan.h").touch()
            cc = root / "cc"
            cc.write_text("#!/bin/sh\nexit 0\n")
            cc.chmod(0o755)
            ngfx = root / "ngfx"
            ngfx.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
assert "--start-with-ngfx-sdk" in sys.argv
assert "--stop-with-ngfx-sdk" in sys.argv
assert not any(a.startswith("--start-after-") or a.startswith("--limit-to-") for a in sys.argv)
root = pathlib.Path(os.environ["LANIUS_NGFX_COMPLETION_FILE"]).parent
token = os.environ["LANIUS_NGFX_CAPTURE_TOKEN"]
(root / "workload-complete.json").write_text(json.dumps({"schema":"lanius.nsight-workload.v1",
    "token":token,"complete":True,"sdk_start":0,"sdk_stop":0,"capture_elapsed_ms":100}))
export = root / "BASE_UNLOCKED"
export.mkdir()
(export / "REPRO_INFO.xls").write_text("Start After\\tNGFX SDK Controlled\\nLimited To\\tNGFX SDK Controlled\\n")
names = [f"lanius.capture.{token}.begin", "compile", "link"]
if os.environ.get("COMPLETE") == "1": names.append(f"lanius.capture.{token}.end")
(export / "D3DPERF_EVENTS.xls").write_text("event_text\\ttime_ms\\n" + "".join(n+"\\t1\\n" for n in names))
print("Succeeded to export data:")
''')
            ngfx.chmod(0o755)
            env = {key: value for key, value in os.environ.items() if not key.startswith("LANIUS_NGFX_")}
            env.update(LANIUS_NGFX_BIN=str(ngfx), LANIUS_NGFX_SDK_INCLUDE=str(sdk), CC=str(cc))
            for complete in (False, True):
                directory = root / str(complete)
                command = [str(wrapper), "--output-dir", str(directory), "--", "/bin/true"]
                result = subprocess.run(command, env={**env, "COMPLETE": str(int(complete))}, capture_output=True, text=True)
                self.assertEqual(result.returncode == 0, complete, result.stdout + result.stderr)
                self.assertEqual((directory / "coverage.json").exists(), complete)
                # Old markers/receipt cannot validate a later launch.
                again = subprocess.run(command, env=env, capture_output=True, text=True)
                self.assertNotEqual(again.returncode, 0)
                self.assertIn("must be empty", again.stderr)
            for setting in ("LANIUS_NGFX_START_SUBMIT", "LANIUS_NGFX_LIMIT_SUBMITS"):
                result = subprocess.run([str(wrapper), "--dry-run", "--", "/bin/true"],
                    env={**env, setting: "0"}, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("cannot prove full coverage", result.stderr)


if __name__ == "__main__":
    unittest.main()
