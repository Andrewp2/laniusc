#!/usr/bin/env python3

from __future__ import annotations

import json
import random
import tempfile
import unittest
from pathlib import Path

from generate_typical_project import generate
from run_typical_lanius_matrix import benchmark_edit_variants, daemon_commands
from typical_project_constructs import ARCHETYPES, archetype_for_module
from typical_project_model import LANGUAGES, build_project, project_tree, render_project


class TypicalProjectModelTests(unittest.TestCase):
    def test_compiler_matrix_uses_checked_same_size_edits(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as temporary:
            root = Path(temporary)
            project = root / "typical-project-6"
            generate(project, 6, 19)
            edits = benchmark_edit_variants(Path.cwd(), project, 4)
            self.assertEqual(len(edits), 4)
            self.assertEqual(len({edit["new"] for edit in edits}), 4)
            for index, edit in enumerate(edits):
                self.assertNotEqual(edit["old"], edit["new"])
                self.assertEqual(len(edit["old"].encode()), len(edit["new"].encode()))
                if index:
                    self.assertEqual(edit["old"], edits[index - 1]["new"])

            requests = daemon_commands(Path.cwd(), project, "x86_64", 3)["lanius"][
                "requests"
            ]
            measured = [
                request for request in requests if request["id"].startswith("edit-")
            ]
            self.assertEqual(len(measured), 4)
            self.assertEqual(measured[0]["id"], "edit-warmup")
            self.assertEqual(measured[0]["benchmark_source_edit"], edits[0])
            self.assertEqual(measured[1]["benchmark_source_edit"], edits[1])
            self.assertEqual(requests[-2]["id"], "restore-source")

    def test_generation_is_deterministic(self) -> None:
        first = build_project(91, 12)
        second = build_project(91, 12)
        self.assertEqual(first, second)
        for language in LANGUAGES:
            self.assertEqual(
                render_project(language, first), render_project(language, second)
            )

    def test_requested_file_count_is_exact_including_one_file(self) -> None:
        for file_count in (1, 7, 100):
            project = build_project(22, file_count)
            self.assertEqual(project.structure()["source_file_count"], file_count)
            for language in LANGUAGES:
                suffix = {
                    "c": ".c",
                    "cpp": ".cpp",
                    "rust": ".rs",
                    "zig": ".zig",
                    "lanius": ".lani",
                }[language]
                rendered_count = sum(
                    path.endswith(suffix) for path in render_project(language, project)
                )
                self.assertEqual(rendered_count, file_count, language)

    def test_typical_project_has_real_structure_without_padding(self) -> None:
        project = build_project(87, 100)
        structure = project.structure()
        self.assertTrue(structure["all_modules_reachable"])
        self.assertFalse(structure["contains_padding"])
        self.assertGreaterEqual(structure["dependency_depth"], 3)
        self.assertGreater(structure["dependency_edge_count"], 100)
        self.assertLessEqual(structure["maximum_dependency_fanout"], 10)
        self.assertGreaterEqual(structure["module_line_summary"]["p50"], 50)
        self.assertLessEqual(structure["module_line_summary"]["p50"], 400)
        self.assertGreaterEqual(structure["module_line_summary"]["p90"], 300)
        self.assertLessEqual(structure["module_line_summary"]["p90"], 1800)
        rendered = "\n".join(render_project("rust", project).values())
        self.assertIn("compute_fee", rendered)
        self.assertIn("validate_window", rendered)
        self.assertNotIn("padding", rendered.lower())

    def test_archetypes_follow_declared_weights_after_small_project_breadth(
        self,
    ) -> None:
        project = build_project(87, 100)
        counts = project.structure()["archetype_counts"]
        self.assertEqual(set(counts), set(ARCHETYPES))
        self.assertEqual([archetype_for_module(i) for i in range(6)], list(ARCHETYPES))
        profile = json.loads(
            Path(__file__).with_name("typical_construct_profile.json").read_text()
        )
        for archetype in ARCHETYPES:
            self.assertLessEqual(
                abs(counts[archetype] - profile["archetypes"][archetype]["weight"]),
                1,
                archetype,
            )

    def test_six_file_lanius_project_contains_every_promised_common_construct(
        self,
    ) -> None:
        project = build_project(19, 6)
        structure = project.structure()
        self.assertTrue(structure["required_constructs_covered"])
        self.assertEqual(structure["missing_required_constructs"], [])
        self.assertFalse(structure["rare_frontend_constructs_covered"])
        self.assertIn("trait", structure["missing_rare_frontend_constructs"])
        self.assertTrue(structure["runtime_facilities_covered"])
        self.assertEqual(structure["missing_runtime_facilities"], [])
        source = "\n".join(render_project("lanius", project).values())
        required_syntax = {
            "while": "while (",
            "for_range": "for ",
            "struct": "struct ServiceState",
            "inherent_impl": "impl ServiceState",
            "enum": "enum Adjustment",
            "match": "match (",
            "generic_struct": "struct Envelope<T>",
            "generic_function": "fn unwrap<T>",
            "type_alias": "type SummaryScore",
            "const_item": "const SUMMARY_OFFSET",
            "array_literal": "[seed,",
            "break": "break;",
            "continue": "continue;",
            "recursion": "return decay(",
            "method_call": ".adjusted(",
        }
        for construct, marker in required_syntax.items():
            self.assertIn(marker, source, construct)

        runtime_use_sites = {
            "stdio": "std::io::print_i32(total)",
            "filesystem": 'std::fs::open_read_path("lanius/main.lani")',
            "environment": "std::env::current_dir_len()",
            "process_args": "std::process::argc()",
            "process_exit": "std::process::exit(0)",
            "random": "std::random::secure_u32()",
            "time": "std::time::unix_seconds()",
            "allocation": "alloc::allocator::alloc(capacity, 8)",
        }
        for facility, marker in runtime_use_sites.items():
            self.assertIn(marker, source, facility)

    def test_hundred_file_project_contains_every_rare_frontend_construct(self) -> None:
        project = build_project(19, 100)
        structure = project.structure()
        self.assertTrue(structure["rare_frontend_constructs_covered"])
        self.assertEqual(structure["missing_rare_frontend_constructs"], [])
        source = "\n".join(render_project("lanius", project).values())
        required_syntax = {
            "trait": "trait ScorePolicy<T>",
            "trait_impl": "impl ScorePolicy<i32> for i32",
            "public_trait_method": "pub fn score_policy(value: T)",
            "where_clause": "where T: ScorePolicy<T>",
            "const_generic": "<const N: usize>",
            "reference_type": "fn borrowed_marker(&self)",
            "slice_type": "values: [i32]",
            "extern_abi": 'extern "lanius_std" fn argc()',
            "string_literal": 'let label: str = "module-',
            "char_literal": "let delimiter: char = ':';",
            "float_literal": "let ratio: f32 = 1.25;",
            "extern_without_abi": "extern fn unbound_probe()",
            "void_function": "fn record_positive(value: i32) {",
            "bare_return": "return;",
            "inferred_local": "let inferred = +(seed);",
            "if_without_else": "if (value > 0) {",
            "group_expression": "let grouped: i32 = ((inferred));",
            "empty_call": "zero_value()",
            "operator_assignments": "value <<= 1;",
            "primitive_types": "let tiny: u8 = 1;",
            "for_iterable_path": "for value in values {",
            "trailing_parameter": "fn trailing_sum(left: i32, right: i32,)",
            "trailing_call_argument": "trailing_sum(seed, 0,)",
            "multiple_generic_parameters": "struct GenericPair<Left, Right,>",
            "multiple_type_arguments": "GenericPair<i32, bool,>",
            "generic_type_alias": "type GenericIdentity<Value,> = Value;",
            "empty_tuple_pattern": "Empty() -> 0,",
            "pattern_trailing_comma": "Value(inner,) -> inner,",
            "multiple_where_predicates": "Right: BoundScorePolicy<Right,>, {",
            "multiple_type_bounds": "+ PairBoundPolicy<Left, Right,>",
            "uninitialized_typed_local": "let deferred: i32;",
            "public_impl_method": "pub fn statement_value(self)",
            "postfix_call_member": "make_statement_record(0).value",
            "public_const": "pub const PUBLIC_ZERO: i32 = 0;",
            "public_type_alias": "pub type PublicScore = i32;",
            "public_struct": "pub struct PublicRecord",
            "public_enum": "pub enum PublicChoice",
            "public_trait": "pub trait PublicPolicy<T>",
            "public_impl": "pub impl PublicRecord",
            "public_extern": 'pub extern "lanius_std" fn argc()',
            "empty_array_literal": "let empty_values: [i32; 0] = [];",
            "empty_struct_declaration": "struct EmptyRecord {}",
        }
        for construct, marker in required_syntax.items():
            self.assertIn(marker, source, construct)

        active_use_sites = {
            "trait_bound": "rare_construct_score(seed)",
            "generic_bound_call": "preserve_scored(seed)",
            "const_generic_call": "first_const_generic(const_values)",
            "reference_method_call": "borrowed.borrowed_marker()",
            "slice_call": "first_slice(slice_values)",
            "extern_call": "observed_argc: i32 = argc()",
            "literal_call": "literal_metadata()",
            "language_forms_call": "language_forms(seed)",
            "operator_forms_call": "operator_forms(seed)",
            "primitive_forms_call": "primitive_forms()",
            "generic_arity_call": "generic_arity(seed)",
            "pattern_list_forms_call": "pattern_list_forms(seed)",
            "bound_list_forms_call": "bound_list_forms(seed)",
            "statement_postfix_forms_call": "statement_postfix_forms(seed)",
            "public_items_call": "public_items(seed)",
            "empty_aggregates_call": "empty_aggregates(seed)",
        }
        for construct, marker in active_use_sites.items():
            self.assertIn(marker, source, construct)

    def test_ten_thousand_file_graph_is_bounded_and_reachable(self) -> None:
        children, roots, _depths = project_tree(10_000, random.Random(4))
        reached = set()
        pending = list(roots)
        while pending:
            index = pending.pop()
            if index not in reached:
                reached.add(index)
                pending.extend(children[index])
        self.assertEqual(len(reached), 10_000)
        self.assertEqual(len(roots), 5)
        self.assertLessEqual(max(map(len, children)), 4)

    def test_manifest_is_an_auditable_representative_workload(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            manifest = generate(root, 6, 19)
            on_disk = json.loads((root / "manifest.json").read_text())
            self.assertEqual(manifest, on_disk)
            self.assertTrue(manifest["representative_workload"])
            self.assertEqual(
                manifest["classification"], "corpus_calibrated_typical_project"
            )
            self.assertEqual(
                manifest["expected_stdout"], f"{build_project(19, 6).evaluate()}\n"
            )
            for language in LANGUAGES:
                self.assertEqual(
                    manifest["languages"][language]["source_file_count"], 6
                )
                self.assertGreater(manifest["languages"][language]["source_bytes"], 0)


if __name__ == "__main__":
    unittest.main()
