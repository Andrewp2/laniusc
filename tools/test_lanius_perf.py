import unittest
from argparse import Namespace
from collections import defaultdict, deque

from lanius_perf import (
    CANONICAL_SINGLE_FILE_PRESET,
    annotate_timeline_event,
    custom_workload_warning,
    execution_graph,
    require_complete_execution_graph,
    resolve_workload_spec,
    single_file_comparison_group,
    timeline_compiler_phase,
    timeline_execution_domain,
    typical_project_comparison_group,
    workload_run_id,
)
from perf_model import validate_execution_graph


def graph_depths(graph):
    outgoing = defaultdict(list)
    indegree = {node["id"]: 0 for node in graph["nodes"]}
    depth = {node["id"]: 0 for node in graph["nodes"]}
    for edge in graph["edges"]:
        outgoing[edge["source"]].append(edge["target"])
        indegree[edge["target"]] += 1
    ready = deque(node_id for node_id, count in indegree.items() if count == 0)
    visited = 0
    while ready:
        source = ready.popleft()
        visited += 1
        for target in outgoing[source]:
            depth[target] = max(depth[target], depth[source] + 1)
            indegree[target] -= 1
            if indegree[target] == 0:
                ready.append(target)
    if visited != len(graph["nodes"]):
        raise AssertionError("test graph contains a cycle")
    return depth


class ExecutionGraphTests(unittest.TestCase):
    def test_uses_declared_dependencies_and_execution_counts(self):
        compiler_graphs = [{
            "label": "type_check",
            "nodes": [
                {"id": 0, "name": "a", "phase": "type_check", "dispatch_domain": "tokens"},
                {"id": 1, "name": "b", "phase": "type_check", "dispatch_domain": "types"},
            ],
            "edges": [{
                "source": 0,
                "target": 1,
                "dependencies": [{"resource": "types", "hazard": "read_after_write"}],
            }],
        }]
        graph = execution_graph(
            compiler_graphs,
            [{
                "index": 0,
                "label": "compile",
                "passes": ["physical.batch"],
                "operations": ["a", "a", "b"],
            }],
        )

        self.assertEqual([node["execution_count"] for node in graph["nodes"]], [2, 1])
        self.assertEqual(graph["edges"][0]["source"], "type_check:0@0")
        self.assertEqual(graph["edges"][0]["target"], "type_check:1@0")
        self.assertEqual(graph["coverage"]["recorded_compute_passes"], 1)
        self.assertEqual(graph["coverage"]["recorded_operations"], 3)
        require_complete_execution_graph(graph)

    def test_rejects_unregistered_operations(self):
        graph = execution_graph(
            [{
                "label": "g",
                "nodes": [
                    {"id": 0, "name": "declared", "phase": "parse", "dispatch_domain": "tokens"},
                ],
                "edges": [],
            }],
            [{
                "index": 0,
                "label": "frontend",
                "passes": ["physical.frontend"],
                "operations": ["declared", "escaped"],
            }],
        )

        with self.assertRaisesRegex(RuntimeError, "escaped"):
            require_complete_execution_graph(graph)

    def test_rejects_submission_without_operations(self):
        graph = execution_graph(
            [],
            [{"index": 0, "label": "frontend", "passes": ["physical.frontend"], "operations": []}],
        )

        with self.assertRaisesRegex(RuntimeError, "submissions contain no declared operations"):
            require_complete_execution_graph(graph)

    def test_omits_declared_operations_that_did_not_execute(self):
        compiler_graphs = [{
            "label": "lowering",
            "nodes": [
                {"id": 0, "name": "used", "phase": "x86_lowering", "dispatch_domain": "x86_instructions"},
                {"id": 1, "name": "unused", "phase": "wasm_lowering", "dispatch_domain": "wasm_instructions"},
            ],
            "edges": [],
        }]

        graph = execution_graph(compiler_graphs, [{
            "index": 0,
            "label": "compile",
            "passes": ["physical.batch"],
            "operations": ["used", "used", "used"],
        }])

        self.assertEqual([node["name"] for node in graph["nodes"]], ["used"])

    def test_connects_adjacent_compute_submission_boundaries(self):
        compiler_graphs = [{
            "label": "g",
            "nodes": [
                {"id": 0, "name": "a", "phase": "type_check", "dispatch_domain": "types"},
                {"id": 1, "name": "b", "phase": "type_check", "dispatch_domain": "types"},
                {"id": 2, "name": "c", "phase": "type_check", "dispatch_domain": "types"},
            ],
            "edges": [],
        }]
        graph = execution_graph(
            compiler_graphs,
            [
                {
                    "index": 0,
                    "label": "frontend",
                    "passes": ["physical.frontend"],
                    "operations": ["a", "b"],
                },
                {
                    "index": 1,
                    "label": "backend",
                    "passes": ["physical.backend"],
                    "operations": ["c"],
                },
            ],
        )

        submit_edge = next(edge for edge in graph["edges"] if edge["kind"] == "submit_order")
        self.assertEqual(submit_edge["source"], "g:1@0")
        self.assertEqual(submit_edge["target"], "g:2@1")
        self.assertEqual(graph["nodes"][1]["submissions"], [0])
        self.assertEqual(graph["nodes"][2]["submissions"], [1])

    def test_adds_truthful_endpoints_for_unregistered_and_empty_submissions(self):
        graph = execution_graph(
            [{
                "label": "g",
                "nodes": [
                    {"id": 0, "name": "registered", "phase": "type_check", "dispatch_domain": "types"},
                ],
                "edges": [],
            }],
            [
                {
                    "index": 0,
                    "label": "lexer",
                    "passes": ["physical.lexer"],
                    "operations": ["lex.first", "lex.last"],
                },
                {
                    "index": 1,
                    "label": "typecheck",
                    "passes": ["physical.typecheck"],
                    "operations": ["registered"],
                },
                {"index": 2, "label": "linker", "passes": [], "operations": []},
            ],
        )

        submissions = graph["submissions"]
        self.assertEqual(graph["nodes"][-3]["name"], "lex.first")
        self.assertEqual(graph["nodes"][-2]["name"], "lex.last")
        self.assertEqual(graph["nodes"][-1]["kind"], "empty_submission")
        submit_edges = [edge for edge in graph["edges"] if edge["kind"] == "submit_order"]
        self.assertEqual(
            [(edge["source"], edge["target"]) for edge in submit_edges],
            [
                (submissions[0]["last_node"], submissions[1]["first_node"]),
                (submissions[1]["last_node"], submissions[2]["first_node"]),
            ],
        )

    def test_repeated_operations_are_distinct_nodes_per_submission(self):
        graph = execution_graph(
            [{
                "label": "g",
                "nodes": [
                    {"id": 0, "name": "clear", "phase": "type_check", "dispatch_domain": "types"},
                    {"id": 1, "name": "emit", "phase": "type_check", "dispatch_domain": "types"},
                ],
                "edges": [{
                    "source": 0,
                    "target": 1,
                    "dependencies": [{"resource": "types", "hazard": "read_after_write"}],
                }],
            }],
            [
                {
                    "index": 0,
                    "label": "unit 0",
                    "passes": ["physical.unit-0"],
                    "operations": ["clear", "emit"],
                },
                {
                    "index": 1,
                    "label": "unit 1",
                    "passes": ["physical.unit-1"],
                    "operations": ["clear", "emit"],
                },
            ],
        )

        self.assertEqual(
            [node["id"] for node in graph["nodes"]],
            ["g:0@0", "g:0@1", "g:1@0", "g:1@1"],
        )
        validate_execution_graph("example", graph)
        depths = graph_depths(graph)
        self.assertLess(depths["g:1@0"], depths["g:0@1"])

    def test_final_codegen_emit_has_greatest_topological_depth(self):
        graph = execution_graph(
            [
                {
                    "label": "type_check",
                    "nodes": [
                        {"id": 0, "name": "types.clear", "phase": "type_check", "dispatch_domain": "types"},
                        {"id": 1, "name": "types.finish", "phase": "type_check", "dispatch_domain": "types"},
                    ],
                    "edges": [{
                        "source": 0,
                        "target": 1,
                        "dependencies": [{"resource": "types", "hazard": "read_after_write"}],
                    }],
                },
                {
                    "label": "codegen.lowering",
                    "nodes": [
                        {"id": 0, "name": "codegen.clear", "phase": "x86_lowering", "dispatch_domain": "x86_instructions"},
                        {"id": 1, "name": "codegen.emit", "phase": "artifact", "dispatch_domain": "artifact_bytes"},
                    ],
                    "edges": [{
                        "source": 0,
                        "target": 1,
                        "dependencies": [{"resource": "artifact", "hazard": "read_after_write"}],
                    }],
                },
            ],
            [{
                "index": 0,
                "label": "compile",
                "passes": ["physical.compile"],
                "operations": ["types.clear", "types.finish", "codegen.clear", "codegen.emit"],
            }],
        )

        validate_execution_graph("example", graph)
        depths = graph_depths(graph)
        deepest = max(depths, key=depths.get)
        self.assertEqual(deepest, "codegen.lowering:1@0")

    def test_stage_transition_uses_one_boundary_instead_of_all_to_all_edges(self):
        def independent_nodes(prefix, phase):
            return [
                {
                    "id": index,
                    "name": f"{prefix}.{index}",
                    "phase": phase,
                    "dispatch_domain": "items",
                }
                for index in range(3)
            ]

        graph = execution_graph(
            [
                {"label": "type_check", "nodes": independent_nodes("type", "type_check"), "edges": []},
                {"label": "lowering", "nodes": independent_nodes("lower", "x86_lowering"), "edges": []},
            ],
            [{
                "index": 0,
                "label": "compile",
                "passes": ["physical.compile"],
                "operations": [
                    *(f"type.{index}" for index in range(3)),
                    *(f"lower.{index}" for index in range(3)),
                ],
            }],
        )

        boundaries = [node for node in graph["nodes"] if node["kind"] == "stage_boundary"]
        stage_edges = [edge for edge in graph["edges"] if edge["kind"] == "stage_order"]
        self.assertEqual(len(boundaries), 1)
        self.assertEqual(boundaries[0]["execution_count"], 0)
        self.assertEqual(len(stage_edges), 6)
        self.assertEqual(
            {edge["target"] for edge in stage_edges if edge["source"].startswith("type_check:")},
            {boundaries[0]["id"]},
        )
        self.assertEqual(
            {edge["source"] for edge in stage_edges if edge["target"].startswith("lowering:")},
            {boundaries[0]["id"]},
        )
        validate_execution_graph("example", graph)


class ComparisonGroupTests(unittest.TestCase):
    def test_single_file_group_identifies_generator_profile_and_size(self):
        self.assertEqual(
            single_file_comparison_group(
                1_000_000, "pareas-common-subset", tuple(range(20, 40))
            ),
            "compiler-stress/comparative-single-file/pareas-common-subset/"
            "1000000/seeds-20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39",
        )

    def test_typical_project_group_identifies_generator_version_seed_and_file_count(self):
        self.assertEqual(
            typical_project_comparison_group(100, 20260808),
            "typical-project/v1/seed-20260808/files-100",
        )

    def test_canonical_preset_fixes_the_full_comparison_corpus(self):
        spec = resolve_workload_spec(
            Namespace(
                preset=CANONICAL_SINGLE_FILE_PRESET,
                workload=None,
                custom_size=None,
                files=None,
                seed=None,
                samples=None,
            )
        )

        self.assertEqual(spec.target_bytes, 1_000_000)
        self.assertEqual(spec.profile, "pareas-common-subset")
        self.assertEqual(spec.seeds, tuple(range(20, 40)))
        self.assertEqual(spec.primer_seed, 19)
        self.assertEqual(spec.sample_count, 20)

    def test_preset_rejects_workload_overrides(self):
        with self.assertRaisesRegex(ValueError, "fixes its workload"):
            resolve_workload_spec(
                Namespace(
                    preset=CANONICAL_SINGLE_FILE_PRESET,
                    workload=None,
                    custom_size=1_048_576,
                    files=None,
                    seed=None,
                    samples=None,
                )
            )

    def test_custom_single_file_size_is_explicit_and_warns_near_preset(self):
        spec = resolve_workload_spec(
            Namespace(
                preset=None,
                workload="single-file",
                custom_size=1_048_576,
                files=None,
                seed=None,
                samples=7,
            )
        )

        self.assertEqual(spec.target_bytes, 1_048_576)
        self.assertEqual(spec.sample_count, 7)
        self.assertIn("will not use the frozen comparison corpus", custom_workload_warning(spec))
        self.assertEqual(
            workload_run_id(spec, "x86_64"),
            "single-file-custom-1048576-seed-20260808-x86_64",
        )

    def test_single_file_without_custom_size_points_to_preset(self):
        with self.assertRaisesRegex(ValueError, "--preset single-file-1mb"):
            resolve_workload_spec(
                Namespace(
                    preset=None,
                    workload="single-file",
                    custom_size=None,
                    files=None,
                    seed=None,
                    samples=None,
                )
            )


class TimelineClassificationTests(unittest.TestCase):
    def test_classifies_execution_independently_from_trace_lane(self):
        self.assertEqual(timeline_execution_domain("gpu", "gpu.frontend"), "gpu_execution")
        self.assertEqual(timeline_execution_domain("host", "host.submit"), "queue_submission")
        self.assertEqual(
            timeline_execution_domain("host", "host.readback"), "host_readback_wait"
        )
        self.assertEqual(timeline_execution_domain("host", "host.lexer"), "host_orchestration")

    def test_classifies_compiler_phase_from_operation_name(self):
        cases = {
            "lex.source-pack.count_boundary": "lexing",
            "dfa_01_scan_inblock": "lexing",
            "pair_02_scan_block_totals": "lexing",
            "compact_boundaries[KEPT]": "lexing",
            "tokens_build": "lexing",
            "parser.recorded-ll1-hir.status": "parsing_hir",
            "compile.source-pack.record.typecheck": "type_checking",
            "typecheck.expression_types.done": "type_checking",
            "typecheck.visible.hir_decl_scope_tree.done": "type_checking",
            "compile.source-pack.record.lowering": "lowering",
            "lowering.semantic.done": "lowering",
            "semantic-interface artifact": "semantic_interface",
            "semantic_interface.done": "semantic_interface",
            "codegen.x86.link.page": "x86_emission",
            "codegen.x86.lowering.done": "x86_emission",
            "codegen.x86.emission.done": "x86_emission",
            "codegen.wasm.lowering.done": "wasm_emission",
            "codegen.wasm.emission.done": "wasm_emission",
            "artifact.status_readback.done": "artifact_emission",
            "compile.source-pack.finish.wasm_object": "wasm_emission",
            "compile.source-pack.record_more": "orchestration",
        }
        for name, phase in cases.items():
            with self.subTest(name=name):
                self.assertEqual(timeline_compiler_phase(name), phase)

    def test_annotation_preserves_raw_trace_fields(self):
        event = {
            "name": "compile.source-pack.record_more",
            "category": "host",
            "lane": "host.lexer",
        }
        annotate_timeline_event(event)
        self.assertEqual(event["phase"], "orchestration")
        self.assertEqual(event["execution_domain"], "host_orchestration")
        self.assertEqual(event["lane"], "host.lexer")


if __name__ == "__main__":
    unittest.main()
