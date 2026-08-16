import unittest
from collections import defaultdict, deque

from lanius_perf import (
    execution_graph,
    single_file_comparison_group,
    typical_project_comparison_group,
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
            [{"label": "a", "passes": 2}, {"label": "b", "passes": 1}],
            [],
        )

        self.assertEqual([node["execution_count"] for node in graph["nodes"]], [2, 1])
        self.assertEqual(graph["edges"][0]["source"], "type_check:0@untracked")
        self.assertEqual(graph["edges"][0]["target"], "type_check:1@untracked")

    def test_omits_declared_operations_that_did_not_execute(self):
        compiler_graphs = [{
            "label": "lowering",
            "nodes": [
                {"id": 0, "name": "used", "phase": "x86_lowering", "dispatch_domain": "x86_instructions"},
                {"id": 1, "name": "unused", "phase": "wasm_lowering", "dispatch_domain": "wasm_instructions"},
            ],
            "edges": [],
        }]

        graph = execution_graph(compiler_graphs, [{"label": "used", "passes": 3}], [])

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
                {"label": "a", "passes": 1},
                {"label": "b", "passes": 1},
                {"label": "c", "passes": 1},
            ],
            [
                {"index": 0, "label": "frontend", "passes": ["a", "b"]},
                {"index": 1, "label": "backend", "passes": ["c"]},
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
            [{"label": "registered", "passes": 1}],
            [
                {"index": 0, "label": "lexer", "passes": ["lex.first", "lex.last"]},
                {"index": 1, "label": "typecheck", "passes": ["registered"]},
                {"index": 2, "label": "linker", "passes": []},
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
            [{"label": "clear", "passes": 2}, {"label": "emit", "passes": 2}],
            [
                {"index": 0, "label": "unit 0", "passes": ["clear", "emit"]},
                {"index": 1, "label": "unit 1", "passes": ["clear", "emit"]},
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
            [
                {"label": "types.clear", "passes": 1},
                {"label": "types.finish", "passes": 1},
                {"label": "codegen.clear", "passes": 1},
                {"label": "codegen.emit", "passes": 1},
            ],
            [{
                "index": 0,
                "label": "compile",
                "passes": ["types.clear", "types.finish", "codegen.clear", "codegen.emit"],
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
            [
                {"label": f"{prefix}.{index}", "passes": 1}
                for prefix in ("type", "lower")
                for index in range(3)
            ],
            [{
                "index": 0,
                "label": "compile",
                "passes": [
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
            single_file_comparison_group(1_000_000),
            "compiler-stress/comparative-single-file/mixed-function-sizes/1000000",
        )

    def test_typical_project_group_identifies_generator_version_seed_and_file_count(self):
        self.assertEqual(
            typical_project_comparison_group(100, 20260808),
            "typical-project/v1/seed-20260808/files-100",
        )


if __name__ == "__main__":
    unittest.main()
