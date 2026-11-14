//! The tests of the compiler, the command line and the sample programs, built as one test binary.
//!
//! Each module below is one file in `tests/`. Cargo does not discover test
//! files in this package, so a new file runs only after it is listed here.
//! `every_test_file_is_in_a_suite` in `compiler.rs` fails for a file that no
//! suite lists.

#[path = "../common/mod.rs"]
pub mod common;

#[path = "../benchmark_artifacts.rs"]
mod benchmark_artifacts;
#[path = "../bounded_entry_compilation.rs"]
mod bounded_entry_compilation;
#[path = "../call_inference_convergence.rs"]
mod call_inference_convergence;
#[path = "../cast_expression.rs"]
mod cast_expression;
#[path = "../cli_daemon.rs"]
mod cli_daemon;
#[path = "../cli_diagnostics.rs"]
mod cli_diagnostics;
#[path = "../cli_formatter.rs"]
mod cli_formatter;
#[path = "../cli_help.rs"]
mod cli_help;
#[path = "../cli_lsp.rs"]
mod cli_lsp;
#[path = "../cli_package_manifest.rs"]
mod cli_package_manifest;
#[path = "../cli_source_pack_contract.rs"]
mod cli_source_pack_contract;
#[path = "../cli_stdlib_root.rs"]
mod cli_stdlib_root;
#[path = "../cli_version.rs"]
mod cli_version;
#[path = "../cli_wasm_execution.rs"]
mod cli_wasm_execution;
#[path = "../codegen_array_slice_fields.rs"]
mod codegen_array_slice_fields;
#[path = "../codegen_wasm.rs"]
mod codegen_wasm;
#[path = "../codegen_x86.rs"]
mod codegen_x86;
#[path = "../codegen_x86_properties.rs"]
mod codegen_x86_properties;
#[path = "../compiler_array_repeat_context_execution.rs"]
mod compiler_array_repeat_context_execution;
#[path = "../compiler_defect_fixtures_execution.rs"]
mod compiler_defect_fixtures_execution;
#[path = "../compiler_empty_body_execution.rs"]
mod compiler_empty_body_execution;
#[path = "../compiler_empty_enum_layout_execution.rs"]
mod compiler_empty_enum_layout_execution;
#[path = "../compiler_generic_impl_forwarding_execution.rs"]
mod compiler_generic_impl_forwarding_execution;
#[path = "../compiler_generic_types_execution.rs"]
mod compiler_generic_types_execution;
#[path = "../compiler_structural_clone_result_execution.rs"]
mod compiler_structural_clone_result_execution;
#[path = "../compiler_trait_return_context_execution.rs"]
mod compiler_trait_return_context_execution;
#[path = "../filesystem_operations_execution.rs"]
mod filesystem_operations_execution;
#[path = "../format_log_execution.rs"]
mod format_log_execution;
#[path = "../formatter.rs"]
mod formatter;
#[path = "../generated_scaling.rs"]
mod generated_scaling;
#[path = "../imported_concrete_method_execution.rs"]
mod imported_concrete_method_execution;
#[path = "../language_ergonomics_execution.rs"]
mod language_ergonomics_execution;
#[path = "../language_tour.rs"]
mod language_tour;
#[path = "../lexer_dot_frontier.rs"]
mod lexer_dot_frontier;
#[path = "../lexer_parser_feature_flags.rs"]
mod lexer_parser_feature_flags;
#[path = "../library_csv_report_execution.rs"]
mod library_csv_report_execution;
#[path = "../library_distribution_execution.rs"]
mod library_distribution_execution;
#[path = "../library_sdk_execution.rs"]
mod library_sdk_execution;
#[path = "../library_window_report_execution.rs"]
mod library_window_report_execution;
#[path = "../machine_syntax.rs"]
mod machine_syntax;
#[path = "../machines_execution.rs"]
mod machines_execution;
#[path = "../module_visibility.rs"]
mod module_visibility;
#[path = "../native_c_callback_execution.rs"]
mod native_c_callback_execution;
#[path = "../native_c_contract.rs"]
mod native_c_contract;
#[path = "../native_c_dynamic_link_execution.rs"]
mod native_c_dynamic_link_execution;
#[path = "../native_c_elaboration.rs"]
mod native_c_elaboration;
#[path = "../native_c_execution.rs"]
mod native_c_execution;
#[path = "../native_c_float_execution.rs"]
mod native_c_float_execution;
#[path = "../native_c_record_execution.rs"]
mod native_c_record_execution;
#[path = "../native_c_storage_execution.rs"]
mod native_c_storage_execution;
#[path = "../optimizer_semantics.rs"]
mod optimizer_semantics;
#[path = "../package_manifest.rs"]
mod package_manifest;
#[path = "../parser_generated_program_fuzz.rs"]
mod parser_generated_program_fuzz;
#[path = "../parser_hir_call_handoff_invariants.rs"]
mod parser_hir_call_handoff_invariants;
#[path = "../parser_hir_index_handoff_invariants.rs"]
mod parser_hir_index_handoff_invariants;
#[path = "../parser_hir_match_arm_handoff_invariants.rs"]
mod parser_hir_match_arm_handoff_invariants;
#[path = "../parser_hir_match_payload_handoff_invariants.rs"]
mod parser_hir_match_payload_handoff_invariants;
#[path = "../parser_hir_readback_context.rs"]
mod parser_hir_readback_context;
#[path = "../parser_hir_record_invariants.rs"]
mod parser_hir_record_invariants;
#[path = "../parser_hir_records.rs"]
mod parser_hir_records;
#[path = "../parser_hir_type_handoff_invariants.rs"]
mod parser_hir_type_handoff_invariants;
#[path = "../parser_nonresident.rs"]
mod parser_nonresident;
#[path = "../path_execution.rs"]
mod path_execution;
#[path = "../randomness_execution.rs"]
mod randomness_execution;
#[path = "../raytracer_acceptance.rs"]
mod raytracer_acceptance;
#[path = "../sample_program_manifest.rs"]
mod sample_program_manifest;
#[path = "../sample_programs_stdin_execution.rs"]
mod sample_programs_stdin_execution;
#[path = "../sample_programs_wasm.rs"]
mod sample_programs_wasm;
#[path = "../sample_programs_x86.rs"]
mod sample_programs_x86;
#[path = "../sample_sort_rows_edit_execution.rs"]
mod sample_sort_rows_edit_execution;
#[path = "../source_pack_package_boundaries.rs"]
mod source_pack_package_boundaries;
#[path = "../time_execution.rs"]
mod time_execution;
#[path = "../type_checker_generics.rs"]
mod type_checker_generics;
#[path = "../type_checker_modules.rs"]
mod type_checker_modules;
#[path = "../type_checker_scope.rs"]
mod type_checker_scope;
#[path = "../type_checker_semantics.rs"]
mod type_checker_semantics;
#[path = "../type_checker_variant_type_collision.rs"]
mod type_checker_variant_type_collision;
#[path = "../x86_jump_checker.rs"]
mod x86_jump_checker;

#[test]
fn every_test_file_is_in_a_suite() {
    let listed = [
        include_str!("compiler.rs"),
        include_str!("stdlib.rs"),
        include_str!("extended.rs"),
    ]
    .concat();
    let tests = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("tests");
    let mut unlisted = Vec::new();
    for entry in std::fs::read_dir(&tests).expect("read tests/") {
        let name = entry.expect("read tests/ entry").file_name();
        let name = name.to_string_lossy().into_owned();
        if name.ends_with(".rs") && !listed.contains(&format!("#[path = \"../{name}\"]")) {
            unlisted.push(name);
        }
    }
    unlisted.sort();
    assert!(
        unlisted.is_empty(),
        "list these files in a suite under tests/suites/: {unlisted:?}"
    );
}
