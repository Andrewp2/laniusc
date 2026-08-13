#!/usr/bin/env python3

import unittest

from tools.summarize_nsight_gpu_trace import (
    compiler_phase,
    compiler_stage,
    parser_hir_stage,
    summarize_stages,
)


class NsightCompilerStageTests(unittest.TestCase):
    def test_backend_phases_are_not_reported_as_other(self) -> None:
        self.assertEqual(compiler_phase("lir.semantic.project"), "semantic_lir")
        self.assertEqual(compiler_phase("lir.target.schedule.scatter"), "target_lir")
        self.assertEqual(compiler_phase("lir.x86.emit"), "x86_codegen")
        self.assertEqual(compiler_phase("artifact.x86.object.bytes"), "x86_codegen")
        self.assertEqual(compiler_phase("lir.wasm.emit"), "wasm_codegen")
        self.assertEqual(compiler_phase("parser_hir_literal_values"), "parser_hir")
        self.assertEqual(compiler_phase("source_file_token_end"), "parser_hir")

    def test_x86_pipeline_has_distinct_stages(self) -> None:
        expected = {
            "lir.x86.lifetime.collect": "x86.lifetime_analysis",
            "lir.x86.location.assign": "x86.register_allocation",
            "lir.x86.resolve": "x86.operand_resolution",
            "lir.x86.scatter": "x86.instruction_lowering",
            "lir.x86.byte_count": "x86.byte_sizing",
            "lir.x86.artifact.layout": "x86.executable_layout",
            "lir.x86.emit": "x86.machine_byte_emission",
            "lir.x86.runtime.emit": "x86.runtime_emission",
            "artifact.x86.object.relocations": "x86.object_projection",
        }
        self.assertEqual({name: compiler_stage(name) for name in expected}, expected)

    def test_parser_pipeline_has_distinct_stages(self) -> None:
        expected = {
            "parser.tokens_to_kinds.pass": "parser.token_classification",
            "brackets_01_scan_inblock": "parser.delimiter_matching",
            "parser.tokens.type_path_context.scan": "parser.syntax_contexts",
            "pack_varlen": "parser.production_parsing_and_packing",
            "tree_depth_step": "parser.raw_tree_recovery",
            "parser.semantic-nav.batch": "hir.semantic_navigation_batch",
            "hir_semantic_parent_step": "hir.semantic_parents",
            "hir_semantic_child_index_rank_step": "hir.semantic_child_indices",
            "hir_type_root_owner_step": "hir.declaration_and_type_relations",
            "hir_match_arm_owner_step": "hir.expression_and_control_relations",
            "hir_struct_field_links": "hir.aggregate_relations",
            "hir_canonical_predicate_relations_step": "hir.canonical_relationships",
            "hir_canonical_core": "hir.canonical_core_compaction",
            "hir_canonical_param_scatter": "hir.canonical_side_tables",
        }
        self.assertEqual({name: parser_hir_stage(name) for name in expected}, expected)

    def test_stage_summary_preserves_time_and_event_count(self) -> None:
        events = [
            ("lir.x86.emit", 2.0),
            ("lir.x86.emit", 3.0),
            ("lir.x86.lifetime.collect", 1.0),
        ]
        rows = {row["stage"]: row for row in summarize_stages(events)}
        self.assertEqual(rows["x86.machine_byte_emission"]["event_count"], 2)
        self.assertEqual(rows["x86.machine_byte_emission"]["total_time_ms"], 5.0)
        self.assertEqual(rows["x86.machine_byte_emission"]["first_event_index"], 0)
        self.assertEqual(rows["x86.machine_byte_emission"]["last_event_index"], 1)
        self.assertEqual(sum(row["total_time_ms"] for row in rows.values()), 6.0)


if __name__ == "__main__":
    unittest.main()
