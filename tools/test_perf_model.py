import tempfile
import unittest
from pathlib import Path

from perf_model import count_sloc, distribution, source_facts, summarize


class PerfModelTests(unittest.TestCase):
    def test_distribution_retains_mean_median_mad_and_histogram(self):
        result = distribution([1.0, 2.0, 3.0, 100.0])
        self.assertEqual(result["median"], 2.5)
        self.assertEqual(result["mean"], 26.5)
        self.assertEqual(result["mad"], 1.0)
        self.assertEqual(sum(result["histogram"]["counts"]), 4)

    def test_throughput_is_computed_per_sample_before_taking_median(self):
        result = summarize(
            [{"wall_ms": 1.0}, {"wall_ms": 2.0}, {"wall_ms": 4.0}],
            {"bytes": 1_000, "sloc": 100},
        )
        self.assertEqual(result["median_bytes_per_second"], 500_000.0)
        self.assertEqual(result["median_sloc_per_second"], 50_000.0)

    def test_sloc_ignores_blank_and_comment_only_lines(self):
        self.assertEqual(
            count_sloc(["", "// comment", "/* block", "end */", "let x = 1; // value"]),
            1,
        )

    def test_source_facts_are_derived_from_the_written_sources(self):
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            source = root / "main.lani"
            source.write_text("// heading\nfn main() {\n  return;\n}\n")
            facts = source_facts([source], root)
        self.assertEqual(facts["files"], 1)
        self.assertEqual(facts["sloc"], 3)
        self.assertEqual(facts["bytes"], 35)


if __name__ == "__main__":
    unittest.main()
