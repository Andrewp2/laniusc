//! Item imports, local inference and `?` through the real standard library.

use crate::common;

use std::path::PathBuf;

use laniusc_compiler::compiler::{
    compile_entry_to_wasm_with_stdlib,
    compile_entry_to_x86_64_with_stdlib,
};

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
        "distinct_types_reject_ref_method.lani",
    ] {
        assert_rejected(fixture, &["LNC0006", DISTINCT]);
    }
}

const ELSE_IF: &str = "1\n2\n3\n4\n5\n4\n3\n0\n1432\n10\n11\n12\n";

const LENGTHS: &str = "15\n3\n6\n5\n0\n6\n3\n3\n3\n2\n3\n";

#[test]
fn slice_len_and_string_len_count_elements_and_bytes() {
    let fixture = "length_builtins.lani";
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(String::from_utf8_lossy(&output.stdout), LENGTHS, "{output:?}");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn slice_len_and_string_len_count_on_wasm() {
    common::require_node();
    let fixture = "length_builtins.lani";
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    let wasm = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_wasm_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let stdout = common::run_wasm_main_with_node("language ergonomics", "length_builtins", &wasm);
    assert_eq!(stdout, LENGTHS);
}

#[test]
fn else_if_chains_take_the_first_true_arm() {
    let fixture = "else_if.lani";
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(String::from_utf8_lossy(&output.stdout), ELSE_IF, "{output:?}");
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn else_if_chains_take_the_first_true_arm_on_wasm() {
    common::require_node();
    let fixture = "else_if.lani";
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/language").join(fixture);
    let stdlib_root = root.join("stdlib");
    let wasm = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(compile_entry_to_wasm_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let stdout = common::run_wasm_main_with_node("language ergonomics", "else_if", &wasm);
    assert_eq!(stdout, ELSE_IF);
}

#[test]
fn else_takes_a_block_or_an_if_statement() {
    assert_rejected("else_if_without_parentheses.lani", &["LNC0016", "expected `(`"]);
    assert_rejected("else_without_block.lani", &["LNC0016", "expected `{` or keyword `if`"]);
    assert_rejected("else_if_integer_condition.lani", &["LNC0006", "expects bool"]);
    assert_rejected("else_if_arm_scope.lani", &["LNC0005", "not found in this scope"]);
}

/// Runs a fixture that ends in a trap and returns its output.
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn trap_output(fixture: &str) -> std::process::Output {
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    common::run_x86_64_elf_output_expecting_signal("language ergonomics", fixture, &bytes)
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn a_trap_writes_its_reason_to_standard_error() {
    use std::os::unix::process::ExitStatusExt;

    for (fixture, stdout, stderr, code) in [
        ("trap_index.lani", "2\n", "lanius: index out of range\n", 101),
        ("trap_shift.lani", "8\n", "lanius: shift amount out of range\n", 102),
        ("trap_divide_by_zero.lani", "-4\n3\n", "lanius: division by zero\n", 103),
        ("trap_divide_overflow.lani", "2147483647\n", "lanius: division overflow\n", 104),
    ] {
        let output = trap_output(fixture);
        assert_eq!(String::from_utf8_lossy(&output.stdout), stdout, "{fixture}: {output:?}");
        assert_eq!(String::from_utf8_lossy(&output.stderr), stderr, "{fixture}: {output:?}");
        assert_eq!(output.status.code(), Some(code), "{fixture}: {output:?}");
    }

    let output = trap_output("trap_assert.lani");
    assert_eq!(String::from_utf8_lossy(&output.stdout), "3\n", "{output:?}");
    assert_eq!(
        String::from_utf8_lossy(&output.stderr),
        "lanius: assertion failed\n",
        "{output:?}"
    );
    assert_eq!(output.status.signal(), Some(4), "{output:?}");
}

#[test]
fn text_helpers_convert_literals_and_write_whole_values() {
    let fixture = "text_helpers.lani";
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            "12\nhello, world\nhello\nworld\nname: Lanius\n6\n5\n100\n4\n\
             -1234567890123 18446744073709551615\n",
            "{output:?}"
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn length_builtins_reject_an_argument_of_another_type() {
    assert_rejected(
        "slice_len_of_integer.lani",
        &["LNC0006", "`slice_len` takes a slice or an array; this value is `i32`"],
    );
    assert_rejected(
        "slice_len_of_text.lani",
        &["LNC0006", "this value is `str`", "`string_len(text)` counts the bytes"],
    );
    assert_rejected(
        "string_len_of_array.lani",
        &["LNC0006", "`string_len` takes a `str`", "`slice_len(values)` counts the elements"],
    );
    assert_rejected(
        "slice_len_two_arguments.lani",
        &["LNC0027", "takes exactly one argument"],
    );
}

#[test]
fn call_ptr_calls_the_function_at_an_address() {
    assert_exit("call_ptr.lani", 77);
}

#[test]
fn call_ptr_takes_the_entry_and_three_pointers() {
    assert_rejected(
        "call_ptr_three_arguments.lani",
        &["LNC0027", "`call_ptr` takes exactly four arguments"],
    );
    assert_rejected(
        "call_ptr_integer_argument.lani",
        &["LNC0006", "value type is i32 but this context expects ptr"],
    );
}

#[test]
fn print_rejects_a_value_it_cannot_write() {
    assert_rejected(
        "print_text.lani",
        &["LNC0006", "this value is `str`", "std::io::println"],
    );
    assert_rejected("print_wide_integer.lani", &["LNC0006", "this value is `i64`", "as i32"]);
    assert_rejected("print_two_arguments.lani", &["LNC0027", "takes exactly one argument"]);
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

#[test]
fn mut_references_write_through_to_the_caller() {
    assert_exit("mut_refs.lani", 0);
}

#[test]
fn a_mut_argument_must_not_alias_another_reference_argument() {
    let shared = "same value as a `&mut` argument";
    assert_rejected("mut_alias_arguments.lani", &["LNC0006", shared]);
    assert_rejected("mut_alias_receiver.lani", &["LNC0006", shared]);
}

#[test]
fn block_arms_run_statements_and_return() {
    assert_exit("block_arms.lani", 0);
}

#[test]
fn a_block_arm_must_not_fall_through() {
    assert_rejected("block_arm_falls_through.lani", &["LNC0006", "the end of this block arm can be reached"]);
}

#[test]
fn a_block_arm_can_end_in_break_or_continue() {
    assert_exit("block_arm_loop_exits.lani", 0);
    assert_rejected("block_arm_loop_exit_not_return.lani", &["LNC0006", "block_arm_loop_exit_not_return.lani:2"]);
}

#[test]
fn a_match_that_covers_every_value_compiles() {
    assert_exit("match_exhaustive.lani", 78);
}

#[test]
fn a_match_must_have_an_arm_for_every_variant() {
    let missing = &["LNC0077", "match is not exhaustive", "at least one value has no arm"];
    assert_rejected("match_missing_variant.lani", missing);
    assert_rejected("match_missing_variant.lani", &["match_missing_variant.lani:4"]);
    assert_rejected("match_repeated_variant.lani", missing);
    assert_rejected("match_missing_imported_variant.lani", missing);
    assert_rejected("match_missing_bool.lani", missing);
}

#[test]
fn a_match_must_cover_the_variants_inside_a_payload() {
    let missing = &["LNC0077", "match is not exhaustive", "at least one value has no arm"];
    assert_rejected("match_missing_nested_variant.lani", missing);
    assert_rejected("match_missing_nested_variant.lani", &["match_missing_nested_variant.lani:5"]);
    assert_rejected("match_missing_deep_variant.lani", missing);
    assert_rejected("match_literal_payload_without_wildcard.lani", missing);
}

#[test]
fn an_arm_that_splits_two_payload_columns_covers_nothing() {
    assert_rejected(
        "match_two_refutable_columns.lani",
        &["LNC0077", "at least one value has no arm", "together cover one payload"],
    );
}

#[test]
fn a_match_on_literals_needs_a_wildcard_arm() {
    assert_rejected("match_literals_without_wildcard.lani", &["LNC0077", "has no `_` arm"]);
}

#[test]
fn an_arm_pattern_must_be_a_variant_a_literal_or_a_wildcard() {
    let expected = &["LNC0077", "invalid match pattern", "this is not an enum variant"];
    assert_rejected("match_pattern_not_a_variant.lani", expected);
    assert_rejected("match_pattern_not_a_variant.lani", &["match_pattern_not_a_variant.lani:5"]);
    assert_rejected("match_pattern_unknown_variant.lani", expected);
}

#[test]
fn closures_capture_locals_and_implement_the_callback_traits() {
    assert_exit("closure.lani", 77);
}

#[test]
fn closures_copy_bracketed_and_generic_types() {
    assert_exit("closure_types.lani", 67);
}

#[test]
fn a_move_closure_is_a_value_that_a_struct_stores() {
    assert_exit("closure_move.lani", 44);
}

#[test]
fn a_stored_callback_holds_any_move_closure_of_its_signature() {
    let fixture = "closure_stored.lani";
    let bytes = compile(fixture).unwrap_or_else(|error| panic!("{fixture}: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", fixture, &bytes);
        assert_eq!(String::from_utf8_lossy(&output.stdout), "101\n7\n", "{fixture}");
        assert_eq!(output.status.code(), Some(120), "{fixture}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn a_block_closure_without_a_result_type_returns_nothing() {
    assert_exit("closure_unit.lani", 0);
    assert_rejected(
        "closure_unit_returns_value.lani",
        &["LNC0006", "value type is i32 but this context expects void", "closure_unit_returns_value.lani:10:41"],
    );
}

#[test]
fn a_stored_callback_needs_a_written_result_type() {
    assert_rejected("closure_stored_expression.lani", &["LNC0008", "unsatisfied trait bound"]);
}

#[test]
fn a_closure_does_not_capture_a_local_of_another_function() {
    assert_rejected("closure_scope.lani", &["LNC0005", "unresolved identifier", "closure_scope.lani:11:31"]);
}

#[test]
fn closures_in_two_files_of_a_program_are_rewritten_together() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("tests/fixtures/language/closure_modules");
    let entry = fixture.join("app/main.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![fixture],
    };
    let bytes = common::run_gpu_codegen_with_timeout("closure_modules", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("closure_modules: {error}"));
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("language ergonomics", "closure_modules", &bytes);
        assert_eq!(output.status.code(), Some(35), "{output:?}");
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn a_closure_needs_one_typed_parameter_or_none() {
    assert_rejected(
        "closure_untyped_parameter.lani",
        &["LNC0078", "invalid closure", "a closure parameter needs a type", "closure_untyped_parameter.lani:6:18"],
    );
    assert_rejected("closure_two_parameters.lani", &["LNC0078", "a closure takes one parameter with a type"]);
    assert_rejected(
        "closure_result_type_without_block.lani",
        &["LNC0078", "a closure with a result type needs a body in braces"],
    );
}

#[test]
fn a_closure_captures_only_locals_with_a_declared_type() {
    assert_rejected(
        "closure_untyped_capture.lani",
        &["LNC0078", "which has no declared type", "closure_untyped_capture.lani:7:31"],
    );
    assert_rejected("closure_self.lani", &["LNC0078", "a closure cannot use `self`", "closure_self.lani:8:35"]);
    assert_rejected("closure_nested.lani", &["LNC0078", "a closure cannot contain another closure"]);
}

#[test]
fn an_error_in_a_closure_body_points_at_the_body() {
    assert_rejected(
        "closure_body_error.lani",
        &["LNC0005", "unresolved identifier", "closure_body_error.lani:7:40"],
    );
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
