import json
import tempfile
import unittest
from pathlib import Path

from trace_phases import Job, inference_rounds, load_trace, report

LANES = {1: "host.daemon", 2: "host.compiler", 3: "host.readback", 4: "host.submit", 5: "gpu.frontend",
         6: "specialization"}


def span(tid: int, name: str, ts: float, dur: float) -> dict:
    return {"ph": "X", "tid": tid, "name": name, "ts": ts * 1000, "dur": dur * 1000}


def trace_file(directory: str, spans: list) -> str:
    events = [{"ph": "M", "name": "thread_name", "tid": tid, "args": {"name": name}} for tid, name in LANES.items()]
    path = Path(directory) / "trace.json"
    path.write_text(json.dumps({"traceEvents": events + spans}))
    return str(path)


# One 100 ms job (times in ms): the original compile 0-30 with a call-inference wait
# 10-20 the GPU fills, a 30-40 gap with a discovery readback 32-33 and no other span,
# one replay 40-90 with a canonical wait 50-70 the GPU half fills, then a 10 ms tail.
SPANS = [
    span(1, "daemon.job.primer", -50, 40),
    span(3, "type_check.call_inference", -40, 1),
    span(1, "daemon.job.measured", 0, 100),
    span(2, "compile.source-pack.record.parser_capacity_retry", 0, 0),
    span(2, "compile.source-pack.record.downstream.typecheck", 2, 25),
    span(4, "type-check call inference", 8, 2),
    span(3, "type_check.call_inference", 10, 10),
    span(5, "type_check.calls.literal_contexts", 9, 11),
    span(2, "compile.source-pack.finish.wasm_object", 30, 0),
    span(3, "generic call rows", 32, 1),
    span(2, "compile.source-pack.record.parser_capacity_retry", 40, 0),
    span(3, "type_check.canonical.counts.readback", 50, 20),
    span(5, "hir_canonical_core", 50, 10),
    span(2, "compile.source-pack.finish.wasm_object", 90, 0),
]


class TracePhasesTests(unittest.TestCase):
    def test_splits_a_job_into_original_replays_and_gaps(self):
        with tempfile.TemporaryDirectory() as directory:
            lanes, spans = load_trace(trace_file(directory, SPANS))
        job = Job(lanes, spans, "measured")

        self.assertEqual(job.blocks, [(0, 30000), (40000, 90000)])
        self.assertEqual(job.gaps(), [(30000, 40000), (90000, 100000)])
        original = job.partition([job.blocks[0]])
        self.assertAlmostEqual(original["wait: call inference"], 10.0)
        self.assertAlmostEqual(original["submit"], 2.0)
        self.assertAlmostEqual(original["record.downstream.typecheck"], 13.0)
        self.assertAlmostEqual(original["no host span"], 5.0)
        self.assertEqual(job.readback_rows([job.blocks[0]])["call inference"], [1, 10.0, 10.0])
        self.assertEqual(job.readback_rows(job.blocks[1:])["canonical rounds"], [1, 20.0, 10.0])
        gaps = job.partition(job.gaps())
        self.assertAlmostEqual(gaps["no host span"], 19.0)
        self.assertAlmostEqual(gaps["wait: generic call discovery"], 1.0)
        self.assertAlmostEqual(job.gpu_busy(job.blocks[1:]), 10.0)

    def test_report_and_rounds_skip_earlier_jobs(self):
        with tempfile.TemporaryDirectory() as directory:
            lanes, spans = load_trace(trace_file(directory, SPANS))
            stderr = Path(directory) / "daemon.stderr"
            stderr.write_text("[typecheck.call_inference] round=1 changed=0\n"
                              "[typecheck.call_inference] round=1 changed=7\n"
                              "[typecheck.call_inference] round=2 changed=0\n")
            job = Job(lanes, spans, None)
            rounds = inference_rounds(str(stderr), job, spans)
        text = "\n".join(report(job, rounds, 10))

        self.assertEqual(job.name, "measured")
        self.assertEqual(rounds, [7])
        self.assertIn("job `measured`: 100.0 ms; original compile 30.0 ms, 1 replays 50.0 ms, gaps 20.0 ms", text)
        self.assertIn("call-inference rounds: 1, changed per round: 7", text)
        self.assertIn("## replays (per replay of 1): 50.0 ms wall, GPU busy 10.0 ms", text)

    def test_edit_job_copy_run_starts_at_the_reused_stamp(self):
        # An edit job's copy run reuses the parser capacity; the 30-40 gap is specialization work.
        spans = [
            span(1, "daemon.job.edit", 0, 100),
            span(2, "compile.source-pack.record.parser_capacity_retry", 0, 0),
            span(2, "compile.source-pack.finish.wasm_object", 30, 0),
            span(6, "prepare", 30, 10),
            span(2, "compile.source-pack.record.parser_capacity_reused", 40, 0),
            span(2, "compile.source-pack.finish.wasm_object", 90, 0),
        ]
        with tempfile.TemporaryDirectory() as directory:
            lanes, spans = load_trace(trace_file(directory, spans))
        job = Job(lanes, spans, "edit")

        self.assertEqual(job.blocks, [(0, 30000), (40000, 90000)])
        gaps = job.partition(job.gaps())
        self.assertAlmostEqual(gaps["specialization.prepare"], 10.0)
        self.assertAlmostEqual(gaps["no host span"], 10.0)


if __name__ == "__main__":
    unittest.main()
