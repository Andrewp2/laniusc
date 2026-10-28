//! Item imports, local inference and `?` through the real standard library.

mod common;

use std::path::PathBuf;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile(fixture: &str) -> Result<Vec<u8>, String> {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .map_err(|error| error.to_string())
}

fn assert_exit(fixture: &str, code: i32) {
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(output.status.code(), Some(code), "{fixture}: {output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = (bytes, code);
}

fn assert_rejected(fixture: &str, expected: &[&str]) {
    let error = compile(fixture).expect_err(fixture);
    for text in expected {
        assert!(error.contains(text), "{fixture}: expected `{text}` in:\n{error}");
    }
}

#[test]
fn item_imports_name_single_declarations() {
    assert_exit("item_import.lani", 7);
}

#[test]
fn an_item_import_takes_precedence_over_module_imports() {
    assert_exit("item_import_selects.lani", 7);
}

#[test]
fn an_item_import_makes_only_its_item_visible() {
    assert_rejected("item_import_only.lani", &["LNC0005", "unresolved identifier"]);
}

#[test]
fn a_name_from_two_module_imports_is_reported_as_ambiguous() {
    assert_rejected(
        "ambiguous_import.lani",
        &["LNC0005", "ambiguous imported name", "import std::stream::copy;"],
    );
}

#[test]
fn try_returns_the_error_or_unwraps_the_value() {
    assert_exit("try_result.lani", 245);
}

#[test]
fn try_keeps_the_error_and_changes_the_payload_type() {
    assert_exit("try_payload_change.lani", 97);
}

#[test]
fn try_in_a_generic_body_unwraps_an_aggregate_payload() {
    assert_exit("try_generic_aggregate.lani", 49);
}

#[test]
fn try_passes_an_aggregate_payload_as_a_call_argument() {
    assert_exit("try_aggregate_argument.lani", 127);
}

#[test]
fn try_needs_a_result_or_option_operand() {
    assert_rejected(
        "try_not_result.lani",
        &["LNC0006", "`?` needs a `core::result::Result` or `core::option::Option` value"],
    );
}

#[test]
fn try_never_converts_the_error_type() {
    assert_rejected(
        "try_error_mismatch.lani",
        &["LNC0006", "`?` returns this error from a function whose result type differs"],
    );
}

#[test]
fn try_on_an_option_needs_an_option_result() {
    assert_rejected(
        "try_option_in_result.lani",
        &["LNC0006", "`?` returns this error from a function whose result type differs"],
    );
}

#[test]
fn a_bound_infers_the_item_type_of_enumerate_from() {
    assert_exit("bound_enumerate.lani", 68);
}

#[test]
fn bounds_infer_map_types_from_a_local_mapper() {
    assert_exit("bound_map.lani", 18);
}

#[test]
fn bounds_infer_the_item_and_error_types_of_a_transfer() {
    assert_exit("bound_transfer.lani", 15);
}

#[test]
fn bound_inference_follows_a_chain_of_inferred_results() {
    assert_exit("bound_chain.lani", 20);
}

#[test]
fn a_bound_without_an_implementation_infers_nothing() {
    assert_rejected("bound_no_implementation.lani", &["LNC0006"]);
}

#[test]
fn a_bound_with_two_matching_implementations_infers_nothing() {
    assert_rejected("bound_two_implementations.lani", &["LNC0006"]);
}

#[test]
fn an_explicit_argument_that_contradicts_the_implementation_is_rejected() {
    assert_rejected("bound_conflicting_claim.lani", &["LNC0008"]);
}

#[test]
fn a_receiving_type_that_contradicts_the_implementation_is_rejected() {
    assert_rejected("bound_conflicting_result.lani", &["LNC0008"]);
}

#[test]
fn a_nested_variant_pattern_checks_its_payload_and_falls_through() {
    assert_exit("nested_patterns.lani", 0);
}

#[test]
fn nested_patterns_match_imported_and_generic_variants() {
    assert_exit("nested_patterns_imported.lani", 0);
}

#[test]
fn a_static_bound_call_fills_a_generic_record_field() {
    assert_exit("static_bound_call_in_record_field.lani", 0);
}

#[test]
fn a_receiver_binding_types_a_literal_argument() {
    assert_exit("receiver_binds_literal_argument.lani", 0);
}

#[test]
fn distinct_types_mix_with_themselves_literals_and_casts() {
    assert_exit("distinct_types_accept.lani", 0);
    assert_exit("distinct_types_methods.lani", 0);
}

#[test]
fn distinct_types_reject_values_of_another_type() {
    const DISTINCT: &str = "this value's distinct type differs from the one expected here";
    for fixture in [
        "distinct_types_reject_let.lani",
        "distinct_types_reject_call.lani",
        "distinct_types_reject_binary.lani",
        "distinct_types_reject_return.lani",
        "distinct_types_reject_assign.lani",
        "distinct_types_reject_field.lani",
        "distinct_types_reject_method.lani",
    ] {
        assert_rejected(fixture, &["LNC0006", DISTINCT]);
    }
}

#[test]
fn requires_clauses_that_hold_let_the_body_run() {
    assert_exit("requires_holds.lani", 0);
}

#[test]
fn a_broken_requires_clause_traps_before_the_body() {
    let bytes = compile("requires_fails.lani").unwrap_or_else(|error| panic!("{error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        use std::os::unix::process::ExitStatusExt;
        let output = common::run_x86_64_elf_output_expecting_signal(
            "language ergonomics",
            "requires_fails",
            &bytes,
        );
        assert_eq!(String::from_utf8_lossy(&output.stdout), "4\n", "{output:?}");
        assert_eq!(output.status.signal(), Some(4), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn a_requires_condition_must_be_bool() {
    assert_rejected("requires_not_bool.lani", &["LNC0006"]);
}

// The resident workspace is sized by the largest unit checked so far; this
// preserved program's imports are larger than it. Name lookup must use the
// scope tree's published layout, not one derived from this unit's tokens.
#[test]
fn name_lookup_uses_the_scope_tree_layout_of_a_larger_workspace() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("tests/fixtures/stdlib_compiler_state/cli_match_shadow");
    let entry = fixture.join("original.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixture.join("extended")],
    };
    common::run_gpu_codegen_with_timeout("cli_match_shadow", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("cli_match_shadow/original.lani: {error}"));
}
