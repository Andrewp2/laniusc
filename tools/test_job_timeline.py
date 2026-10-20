#!/usr/bin/env python3
"""Tests for tools/job_timeline.py and tools/window_busy.py on a synthetic trace (CPU only)."""
import json
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from job_timeline import analyze, load, report  # noqa: E402
from window_busy import windows  # noqa: E402

LANES = {1: "host.daemon", 2: "host.compiler", 3: "host.readback", 4: "host.submit", 5: "gpu.frontend",
         6: "specialization"}


def span(tid, name, ts, dur, cat=None):
    e = {"ph": "X", "tid": tid, "name": name, "ts": ts * 1000, "dur": dur * 1000}
    if cat:
        e["cat"] = cat
    return e


# A 100 ms job (ms): compiler stamp 0-10; submit 10-12 with the GPU starting at 11; GPU busy
# 11-40 under a readback 12-45, so 5 ms of that wait is GPU idle; nothing traced 45-60 while the
# GPU runs 50-55; a specialization span 60-90; then nothing traced 90-100.
SPANS = [
    span(1, "daemon.job.j1", 0, 100),
    span(2, "compile.source-pack.record.parser_capacity_retry", 0, 10),
    span(4, "submit", 10, 2),
    span(5, "pass_a", 11, 29, "gpu"),
    span(3, "type_check.call_inference", 12, 33),
    span(5, "pass_b", 50, 5, "gpu"),
    span(6, "prepare", 60, 30),
]


def write_trace(directory):
    events = [{"ph": "M", "name": "thread_name", "tid": t, "args": {"name": n}} for t, n in LANES.items()]
    path = pathlib.Path(directory) / "trace.json"
    path.write_text(json.dumps({"traceEvents": events + SPANS}))
    return str(path)


class JobTimelineTests(unittest.TestCase):
    def setUp(self):
        with tempfile.TemporaryDirectory() as directory:
            self.lanes, self.spans = load(write_trace(directory))

    def test_idle_under_submit_and_readback(self):
        r = analyze(self.lanes, self.spans, "j1", 0.5)
        self.assertAlmostEqual(r["wall"], 100000)
        self.assertAlmostEqual(r["busy"], 34000)
        self.assertAlmostEqual(r["idle_submit"], 1000)
        self.assertAlmostEqual(r["idle_readback"], 5000)

    def test_unspanned_intervals_count_the_specialization_lane_as_spanned(self):
        r = analyze(self.lanes, self.spans, "j1", 0.5)
        holes = [(h["start"] / 1000, h["dur"] / 1000, h["gpu_busy"] / 1000) for h in r["holes"]]
        self.assertEqual(holes, [(45.0, 15.0, 5.0), (90.0, 10.0, 0.0)])
        self.assertEqual(r["holes"][0]["after"], "type_check.call_inference")
        self.assertEqual(r["holes"][0]["before"], "prepare")
        text = "\n".join(report("j1", r, 0.5))
        self.assertIn("(submit + map-wait GPU idle) / GPU busy = 0.18", text)
        self.assertIn("intervals under no host span >= 0.5 ms: 2, 25.0 ms", text)

    def test_windows(self):
        rows = windows(self.lanes, self.spans, "j1", ["compile:0:45", "spec:45:100"])
        self.assertEqual([r["name"] for r in rows], ["compile", "spec"])
        self.assertAlmostEqual(rows[0]["gpu_busy"], 29.0)
        self.assertAlmostEqual(rows[0]["readback"], 33.0)
        self.assertEqual(rows[0]["readbacks"], 1)
        self.assertAlmostEqual(rows[0]["submit"], 2.0)
        self.assertAlmostEqual(rows[1]["gpu_busy"], 5.0)
        self.assertEqual(rows[1]["readbacks"], 0)


if __name__ == "__main__":
    unittest.main()
