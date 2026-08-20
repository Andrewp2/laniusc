import json
import tempfile
import unittest
from pathlib import Path

from perf_model import (
    count_sloc,
    distribution,
    source_facts,
    serialize_document,
    summarize,
    validate_execution_graph,
    validate_gpu_memory_timeline,
    validate_document,
    validate_nsight_profile,
    validate_profile_storage,
)


class PerfModelTests(unittest.TestCase):
    def test_gpu_memory_timeline_requires_monotonic_physical_points(self):
        timeline = {
            "physical_residency": {
                "points": [
                    {"start_ms": 1.0, "bytes": 10, "allocations": 1},
                    {"start_ms": 2.0, "bytes": 20, "allocations": 2},
                ],
            },
            "graph_managed_working_set": {
                "intervals": [{"start_ms": 1.0, "duration_ms": 2.0, "bytes": 8}],
            },
        }
        validate_gpu_memory_timeline("example", timeline)
        timeline["physical_residency"]["points"][1]["start_ms"] = 0.5
        with self.assertRaisesRegex(ValueError, "invalid GPU memory point"):
            validate_gpu_memory_timeline("example", timeline)

    def test_canonical_serializer_keeps_telemetry_records_to_one_line(self):
        document = {
            "profile": {
                "execution_graph": {
                    "edges": [
                        {"source": "a", "target": "b", "dependencies": [{"resource": "x"}]},
                        {"source": "b", "target": "c", "dependencies": [{"resource": "y"}]},
                    ]
                },
                "events": [
                    {"name": "a", "duration_ms": 1.0},
                    {"name": "b", "duration_ms": 2.0},
                ],
            }
        }

        encoded = serialize_document(document)

        self.assertEqual(json.loads(encoded), document)
        self.assertEqual(sum('"source":' in line for line in encoded.splitlines()), 2)
        self.assertEqual(sum('"duration_ms":' in line for line in encoded.splitlines()), 2)

    def test_profile_rejects_pass_breakdown_duplicated_by_execution_graph(self):
        with self.assertRaisesRegex(ValueError, "duplicates raw pass breakdown"):
            validate_profile_storage(
                "example",
                {"response": {"recorded_compute_pass_breakdown": [{"label": "pass"}]}},
            )

    def test_canonical_document_rejects_obsolete_metadata_names(self):
        document = {"legacy_template": ["gcc"]}
        with self.assertRaisesRegex(ValueError, "obsolete metadata key 'legacy_template'"):
            validate_document(document)

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

    def test_nsight_profile_requires_a_contiguous_cumulative_time_axis(self):
        profile = {
            "schema": "lanius.nsight-gpu-profile.v1",
            "event_count": 2,
            "unique_pass_count": 1,
            "labeled_gpu_time_ms": 3.0,
            "events": [
                {"event_index": 0, "gpu_start_ms": 0.0, "time_ms": 1.0},
                {"event_index": 1, "gpu_start_ms": 1.0, "time_ms": 2.0},
            ],
            "passes": [{"pass_name": "example"}],
        }
        validate_nsight_profile("example", profile)
        profile["events"][1]["gpu_start_ms"] = 1.5
        with self.assertRaisesRegex(ValueError, "discontinuous Nsight time axis"):
            validate_nsight_profile("example", profile)

    def test_execution_graph_must_be_acyclic(self):
        graph = {
            "coverage": {
                "declared_operations": 2,
                "executed_operation_labels": 2,
                "matched_operation_labels": 2,
                "unregistered_operation_labels": 0,
                "recorded_operations": 2,
                "matched_recorded_operations": 2,
                "recorded_compute_passes": 1,
                "submissions_without_operations": 0,
            },
            "submissions": [],
            "nodes": [
                {
                    "id": "a", "kind": "declared_operation", "graph": "g", "name": "a", "phase": "type_check",
                    "dispatch_domain": "types", "declaration_index": 0,
                    "execution_count": 1,
                    "submissions": [],
                },
                {
                    "id": "b", "kind": "declared_operation", "graph": "g", "name": "b", "phase": "type_check",
                    "dispatch_domain": "types", "declaration_index": 1,
                    "execution_count": 1,
                    "submissions": [],
                },
            ],
            "edges": [{
                "source": "a", "target": "b",
                "kind": "resource_dependency",
                "dependencies": [{"resource": "types", "hazard": "read_after_write"}],
            }],
        }
        validate_execution_graph("example", graph)
        graph["edges"].append({
            "source": "b", "target": "a",
            "kind": "resource_dependency",
            "dependencies": [{"resource": "scratch", "hazard": "write_after_read"}],
        })
        with self.assertRaisesRegex(ValueError, "contains a cycle"):
            validate_execution_graph("example", graph)


if __name__ == "__main__":
    unittest.main()
