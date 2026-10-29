mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

#[test]
fn imported_generic_slice_claims_execute_and_reject_inconsistent_types() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice.lani");
    let bytes = common::run_gpu_codegen_with_timeout("generic_slice", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported generic slices at two element widths");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("generic_slice", "generic_slice", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;

    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_signed.lani");
    let bytes = common::run_gpu_codegen_with_timeout("generic_slice_signed", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("specialize the original signed slice stride reproduction");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("generic_slice_signed", "generic_slice_signed", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;

    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_two_valid.lani");
    let bytes = common::run_gpu_codegen_with_timeout("generic_slice_two_views", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("infer one T from two matching imported [T] arguments");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "generic_slice_two_views",
            "generic_slice_two_views",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;

    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_mismatch.lani");
    common::run_gpu_codegen_with_timeout("generic_slice_mismatch", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("a bool fallback must not match an imported [u8] element type");

    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_inference.lani");
    let bytes = common::run_gpu_codegen_with_timeout("generic_slice_inference", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("infer T from an imported [T] parameter");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "generic_slice_inference",
            "generic_slice_inference",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;

    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_root");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_generic_slice_two_mismatch.lani");
    common::run_gpu_codegen_with_timeout("generic_slice_two_view_mismatch", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("two imported [T] parameters must have matching element types");
}

#[test]
fn imported_bool_constructor_rejects_integer_argument() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_option_bool_wrong_arg.lani");
    let error = common::run_gpu_codegen_with_timeout("option_bool_wrong_arg", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect_err("an i32 argument must not satisfy an imported bool parameter");
    assert!(error.to_string().contains("type mismatch"), "{error}");
}

#[cfg(all(unix, target_arch = "x86_64"))]
#[test]
fn stdlib_helpers_execute_after_parser_workspace_shrinks() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (entry, expected) in [
        ("character_inventory", "3\n"),
        ("halfword_window_total", "32786\n"),
        ("character_inventory", "3\n"),
        ("halfword_window_total", "32786\n"),
    ] {
        let entry_path = root.join(format!("sample_programs/{entry}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(entry, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(
                &entry_path,
                &stdlib_root,
            ))
        })
        .unwrap_or_else(|error| panic!("compile {entry} in a reused parser workspace: {error}"));
        let output = common::run_x86_64_elf_output(entry, entry, &bytes);
        assert_eq!(output.status.code(), Some(0), "{entry}: {output:?}");
        assert_eq!(output.stdout, expected.as_bytes(), "{entry}: {output:?}");
        assert!(output.stderr.is_empty(), "{entry}: {output:?}");
    }
}

// Each fixture returns its first failing assertion number. The bounds fixture
// instead confirms that a caller overclaiming the slice length traps.
#[test]
fn portable_stdlib_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    let cases: &[(&str, &str, i32, &[u8])] = &[
        (
            "core_bool",
            "tests/fixtures/stdlib_foundation/core_bool.lani",
            0,
            b"",
        ),
        (
            "core_target_metadata",
            "tests/fixtures/stdlib_foundation/core_target_metadata.lani",
            0,
            b"",
        ),
        (
            "core_runtime_metadata",
            "tests/fixtures/stdlib_foundation/core_runtime_metadata.lani",
            0,
            b"",
        ),
        (
            "test_harness_metadata",
            "tests/fixtures/stdlib_foundation/test_harness_metadata.lani",
            0,
            b"",
        ),
        (
            "std_host_metadata",
            "tests/fixtures/stdlib_foundation/std_host_metadata.lani",
            0,
            b"",
        ),
        (
            "std_net_metadata",
            "tests/fixtures/stdlib_foundation/std_net_metadata.lani",
            0,
            b"",
        ),
        (
            "std_thread_metadata",
            "tests/fixtures/stdlib_foundation/std_thread_metadata.lani",
            0,
            b"",
        ),
        (
            "std_gpu_metadata",
            "tests/fixtures/stdlib_foundation/std_gpu_metadata.lani",
            0,
            b"",
        ),
        (
            "std_process_metadata",
            "tests/fixtures/stdlib_foundation/std_process_metadata.lani",
            0,
            b"",
        ),
        (
            "std_env_metadata",
            "tests/fixtures/stdlib_foundation/std_env_metadata.lani",
            0,
            b"",
        ),
        (
            "std_io_metadata",
            "tests/fixtures/stdlib_foundation/std_io_metadata.lani",
            0,
            b"",
        ),
        (
            "std_fs_metadata",
            "tests/fixtures/stdlib_foundation/std_fs_metadata.lani",
            0,
            b"",
        ),
        (
            "std_random_metadata",
            "tests/fixtures/stdlib_foundation/std_random_metadata.lani",
            0,
            b"",
        ),
        (
            "process_exit",
            "sample_programs/process_exit.lani",
            7,
            b"0\n",
        ),
        (
            "imported_bool_comparison_arg",
            "tests/fixtures/stdlib_foundation/repro_option_bool_comparison_arg.lani",
            0,
            b"",
        ),
        (
            "core_bits",
            "tests/fixtures/stdlib_foundation/core_bits.lani",
            0,
            b"",
        ),
        (
            "core_char",
            "tests/fixtures/stdlib_foundation/core_char.lani",
            0,
            b"",
        ),
        (
            "core_utf8",
            "tests/fixtures/stdlib_foundation/core_utf8.lani",
            0,
            b"",
        ),
        (
            "core_utf8_bytes",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes.lani",
            0,
            b"",
        ),
        (
            "core_utf8_bytes_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes_bounds.lani",
            101,
            b"",
        ),
        (
            "core_decimal",
            "tests/fixtures/stdlib_foundation/core_decimal.lani",
            0,
            b"",
        ),
        (
            "core_hex",
            "tests/fixtures/stdlib_foundation/core_hex.lani",
            0,
            b"",
        ),
        (
            "core_binary",
            "tests/fixtures/stdlib_foundation/core_binary.lani",
            0,
            b"",
        ),
        (
            "core_f32",
            "tests/fixtures/stdlib_foundation/core_f32.lani",
            0,
            b"",
        ),
        (
            "f32_unordered_branch",
            "tests/fixtures/stdlib_foundation/repro_f32_unordered.lani",
            2,
            b"",
        ),
        (
            "f32_unordered_values",
            "tests/fixtures/stdlib_foundation/f32_unordered_values.lani",
            0,
            b"",
        ),
        (
            "number_byte",
            "tests/fixtures/stdlib_foundation/number_byte.lani",
            0,
            b"",
        ),
        (
            "number_u32",
            "tests/fixtures/stdlib_foundation/number_u32.lani",
            0,
            b"",
        ),
        (
            "number_i16",
            "tests/fixtures/stdlib_foundation/number_i16.lani",
            0,
            b"",
        ),
        (
            "number_i8",
            "tests/fixtures/stdlib_foundation/number_i8.lani",
            0,
            b"",
        ),
        (
            "number_u16",
            "tests/fixtures/stdlib_foundation/number_u16.lani",
            0,
            b"",
        ),
        (
            "range_slice",
            "tests/fixtures/stdlib_foundation/range_slice.lani",
            0,
            b"",
        ),
        (
            "core_option_result",
            "tests/fixtures/stdlib_foundation/core_option_result.lani",
            0,
            b"",
        ),
        (
            "option_generic_scalar_predicates",
            "tests/fixtures/stdlib_foundation/option_generic_scalar_predicates.lani",
            0,
            b"",
        ),
        (
            "core_i32_complete",
            "tests/fixtures/stdlib_foundation/core_i32_complete.lani",
            0,
            b"",
        ),
        (
            "core_i16_complete",
            "tests/fixtures/stdlib_foundation/core_i16_complete.lani",
            0,
            b"",
        ),
        (
            "core_i8_complete",
            "tests/fixtures/stdlib_foundation/core_i8_complete.lani",
            0,
            b"",
        ),
        (
            "core_u8_complete",
            "tests/fixtures/stdlib_foundation/core_u8_complete.lani",
            0,
            b"",
        ),
        (
            "core_u16_complete",
            "tests/fixtures/stdlib_foundation/core_u16_complete.lani",
            0,
            b"",
        ),
        (
            "core_u32_complete",
            "tests/fixtures/stdlib_foundation/core_u32_complete.lani",
            0,
            b"",
        ),
        (
            "slice_sequence",
            "tests/fixtures/stdlib_foundation/slice_sequence.lani",
            0,
            b"",
        ),
        (
            "core_slice",
            "tests/fixtures/stdlib_foundation/core_slice.lani",
            0,
            b"",
        ),
        (
            "core_slice_record_bounds",
            "tests/fixtures/stdlib_foundation/core_slice_record_bounds.lani",
            101,
            b"",
        ),
        (
            "slice_unsigned_sort_exhaustive",
            "tests/fixtures/stdlib_foundation/slice_unsigned_sort_exhaustive.lani",
            0,
            b"",
        ),
        (
            "slice_signed_sort_exhaustive",
            "tests/fixtures/stdlib_foundation/slice_signed_sort_exhaustive.lani",
            0,
            b"",
        ),
        (
            "slice_subsequence",
            "tests/fixtures/stdlib_foundation/slice_subsequence.lani",
            0,
            b"",
        ),
        (
            "slice_copy_nonoverlapping",
            "tests/fixtures/stdlib_foundation/slice_copy_nonoverlapping.lani",
            0,
            b"",
        ),
        (
            "slice_compaction",
            "tests/fixtures/stdlib_foundation/slice_compaction.lani",
            0,
            b"",
        ),
        (
            "slice_partition_search",
            "tests/fixtures/stdlib_foundation/slice_partition_search.lani",
            0,
            b"",
        ),
        (
            "slice_insert",
            "tests/fixtures/stdlib_foundation/slice_insert.lani",
            0,
            b"",
        ),
        (
            "slice_sort_exhaustive_small",
            "tests/fixtures/stdlib_foundation/slice_sort_exhaustive_small.lani",
            0,
            b"",
        ),
        (
            "core_range_methods",
            "tests/fixtures/stdlib_foundation/core_range_methods.lani",
            0,
            b"",
        ),
        (
            "core_unbounded_ranges",
            "tests/fixtures/stdlib_foundation/core_unbounded_ranges.lani",
            0,
            b"",
        ),
        (
            "core_u32_ranges",
            "tests/fixtures/stdlib_foundation/core_u32_ranges.lani",
            0,
            b"",
        ),
        (
            "core_range",
            "tests/fixtures/stdlib_foundation/core_range.lani",
            0,
            b"",
        ),
        (
            "core_range_u8_aggregate",
            "tests/fixtures/stdlib_foundation/core_range_u8_aggregate.lani",
            0,
            b"",
        ),
        (
            "core_range_i8_aggregate",
            "tests/fixtures/stdlib_foundation/core_range_i8_aggregate.lani",
            0,
            b"",
        ),
        (
            "core_range_u16_aggregate",
            "tests/fixtures/stdlib_foundation/core_range_u16_aggregate.lani",
            0,
            b"",
        ),
        (
            "core_range_i16_aggregate",
            "tests/fixtures/stdlib_foundation/core_range_i16_aggregate.lani",
            0,
            b"",
        ),
        (
            "core_array_i32_4_complete",
            "tests/fixtures/stdlib_foundation/core_array_i32_4_complete.lani",
            0,
            b"",
        ),
        (
            "core_array_i32_4_bounds",
            "tests/fixtures/stdlib_foundation/core_array_i32_4_bounds.lani",
            101,
            b"",
        ),
        (
            "core_array_u8_4",
            "tests/fixtures/stdlib_foundation/core_array_u8_4.lani",
            0,
            b"",
        ),
        (
            "core_array_u8_4_bounds",
            "tests/fixtures/stdlib_foundation/core_array_u8_4_bounds.lani",
            101,
            b"",
        ),
        (
            "core_mem_values",
            "tests/fixtures/stdlib_foundation/core_mem_values.lani",
            0,
            b"",
        ),
        (
            "core_mem_intrinsics",
            "tests/fixtures/stdlib_foundation/core_mem_intrinsics.lani",
            0,
            b"",
        ),
        (
            "core_hash",
            "tests/fixtures/stdlib_foundation/core_hash.lani",
            0,
            b"",
        ),
        (
            "core_hash_bounds",
            "tests/fixtures/stdlib_foundation/core_hash_bounds.lani",
            101,
            b"",
        ),
        (
            "slice_bounds",
            "tests/fixtures/stdlib_foundation/slice_bounds.lani",
            101,
            b"",
        ),
        (
            "slice_insert_bounds",
            "tests/fixtures/stdlib_foundation/slice_insert_bounds.lani",
            101,
            b"",
        ),
        (
            "portable_window_checksum",
            "sample_programs/portable_window_checksum.lani",
            0,
            b"96\n",
        ),
        (
            "character_inventory",
            "sample_programs/character_inventory.lani",
            0,
            b"3\n",
        ),
        (
            "option_result_helpers",
            "sample_programs/option_result_helpers.lani",
            0,
            b"38\n",
        ),
        (
            "hex_packet_checksum",
            "sample_programs/hex_packet_checksum.lani",
            0,
            b"28\n",
        ),
        (
            "halfword_window_total",
            "sample_programs/halfword_window_total.lani",
            0,
            b"32786\n",
        ),
        (
            "boolean_window_checksum",
            "sample_programs/boolean_window_checksum.lani",
            0,
            b"3\n",
        ),
        (
            "floating_window_total",
            "sample_programs/floating_window_total.lani",
            0,
            b"2\n",
        ),
        (
            "utf8_text_report",
            "sample_programs/utf8_text_report.lani",
            0,
            b"A\xc2\xa2A\xc2\xa2B5\n",
        ),
        (
            "vector_unsigned_checksum",
            "sample_programs/vector_unsigned_checksum.lani",
            0,
            b"4\n",
        ),
        (
            "vector_byte_checksum",
            "sample_programs/vector_byte_checksum.lani",
            0,
            b"4\n",
        ),
        (
            "vector_signed_byte_sum",
            "sample_programs/vector_signed_byte_sum.lani",
            0,
            b"1\n",
        ),
        (
            "vector_halfword_checksum",
            "sample_programs/vector_halfword_checksum.lani",
            0,
            b"4\n",
        ),
        (
            "vector_signed_halfword_sum",
            "sample_programs/vector_signed_halfword_sum.lani",
            0,
            b"1\n",
        ),
        (
            "vector_true_count",
            "sample_programs/vector_true_count.lani",
            0,
            b"2\n",
        ),
        (
            "std_vec",
            "tests/fixtures/stdlib_foundation/std_vec.lani",
            0,
            b"eps\nalpha\ntwo\n",
        ),
        (
            "std_vec_order",
            "tests/fixtures/stdlib_foundation/std_vec_order.lani",
            0,
            b"",
        ),
        (
            "std_vec_at_out_of_range",
            "tests/fixtures/stdlib_foundation/std_vec_at_out_of_range.lani",
            101,
            b"",
        ),
        (
            "vector_square_sum",
            "sample_programs/vector_square_sum.lani",
            0,
            b"285\n",
        ),
        (
            "vector_edit_checksum",
            "sample_programs/vector_edit_checksum.lani",
            0,
            b"19\n",
        ),
    ];

    for &(name, path, expected_exit, expected_stdout) in cases {
        let entry = root.join(path);
        let stdlib_root = stdlib_root.clone();
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{name}: compile: {err:?}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            assert_eq!(output.stdout, expected_stdout, "{name}: stdout");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_exit, expected_stdout);
    }
}

#[test]
fn executable_core_function_surface_has_runtime_cases() {
    let decimal_fixtures = format!(
        "{}\n{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_decimal.lani"),
        include_str!("fixtures/stdlib_foundation/core_decimal_native.lani"),
        include_str!("fixtures/stdlib_foundation/decimal_parse_input.lani"),
        include_str!("fixtures/stdlib_foundation/decimal_format_input.lani"),
    );
    let float_fixtures = format!(
        "{}\n{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_f32.lani"),
        include_str!("fixtures/stdlib_foundation/float_model.lani"),
        include_str!("fixtures/stdlib_foundation/float_clamp_panic.lani"),
        include_str!("fixtures/stdlib_foundation/float_bits.lani"),
    );
    let slice_fixtures = format!(
        "{}\n{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_slice.lani"),
        include_str!("fixtures/stdlib_foundation/core_slice_view.lani"),
        include_str!("fixtures/stdlib_foundation/slice_view_model.lani"),
        include_str!("fixtures/stdlib_foundation/slice_ordering/contracts.lani"),
    );
    let bitset_fixtures = format!(
        "{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_bitset.lani"),
        include_str!("fixtures/stdlib_foundation/bitset_view_contracts.lani"),
        include_str!("fixtures/stdlib_foundation/bitset_owned_smoke.lani"),
    );
    let endian_fixtures = format!(
        "{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_endian.lani"),
        include_str!("fixtures/stdlib_foundation/native_endian/contracts.lani"),
    );
    let modules = [
        (
            "array_i32_4",
            include_str!("../stdlib/core/array_i32_4.lani"),
            include_str!("fixtures/stdlib_foundation/core_array_i32_4_complete.lani"),
        ),
        (
            "array_u8_4",
            include_str!("../stdlib/core/array_u8_4.lani"),
            include_str!("fixtures/stdlib_foundation/core_array_u8_4.lani"),
        ),
        (
            "bits",
            include_str!("../stdlib/core/bits.lani"),
            include_str!("fixtures/stdlib_foundation/core_bits.lani"),
        ),
        (
            "bitset",
            include_str!("../stdlib/core/bitset.lani"),
            bitset_fixtures.as_str(),
        ),
        (
            "base64",
            include_str!("../stdlib/core/base64.lani"),
            include_str!("fixtures/stdlib_foundation/core_base64.lani"),
        ),
        (
            "endian",
            include_str!("../stdlib/core/endian.lani"),
            endian_fixtures.as_str(),
        ),
        (
            "bool",
            include_str!("../stdlib/core/bool.lani"),
            include_str!("fixtures/stdlib_foundation/core_bool.lani"),
        ),
        (
            "char",
            include_str!("../stdlib/core/char.lani"),
            include_str!("fixtures/stdlib_foundation/core_char.lani"),
        ),
        (
            "utf8",
            include_str!("../stdlib/core/utf8.lani"),
            include_str!("fixtures/stdlib_foundation/core_utf8.lani"),
        ),
        (
            "utf8_view",
            include_str!("../stdlib/core/utf8_view.lani"),
            include_str!("fixtures/stdlib_foundation/core_utf8_byte_search.lani"),
        ),
        (
            "f32",
            include_str!("../stdlib/core/f32.lani"),
            float_fixtures.as_str(),
        ),
        (
            "f64",
            include_str!("../stdlib/core/f64.lani"),
            float_fixtures.as_str(),
        ),
        (
            "decimal",
            include_str!("../stdlib/core/decimal.lani"),
            decimal_fixtures.as_str(),
        ),
        (
            "hex",
            include_str!("../stdlib/core/hex.lani"),
            include_str!("fixtures/stdlib_foundation/core_hex.lani"),
        ),
        (
            "binary",
            include_str!("../stdlib/core/binary.lani"),
            include_str!("fixtures/stdlib_foundation/core_binary.lani"),
        ),
        (
            "slice",
            include_str!("../stdlib/core/slice.lani"),
            slice_fixtures.as_str(),
        ),
    ];

    for (module, source, fixture) in modules {
        let mut count = 0;
        for line in source.lines() {
            let Some(tail) = line.trim_start().strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            let call = if line.starts_with("pub fn ") {
                format!("core::{module}::{name}(")
            } else {
                format!(".{name}(")
            };
            let covered = fixture.contains(&call)
                // Explicit generic calls have `<...>` before the opening
                // parenthesis. This is a source inventory anchor; the
                // registered execution gates verify their runtime behavior.
                || fixture.contains(&format!("{}<", call.trim_end_matches('(')))
                // Associated factories have no receiver dot. Their runtime
                // fixtures call Type::factory rather than module::factory.
                || !line.starts_with("pub fn ")
                    && fixture.contains(&format!("::{name}("))
                || module == "utf8"
                    && include_str!("fixtures/stdlib_foundation/core_utf8_bytes.lani")
                        .contains(&call)
                || module == "utf8_view"
                    && include_str!("fixtures/stdlib_foundation/core_utf8_byte_append.lani")
                        .contains(&call)
                || module == "utf8_view"
                    && include_str!("fixtures/stdlib_foundation/core_utf8_byte_edit.lani")
                        .contains(&call);
            assert!(covered, "{module}::{name} lacks a runtime case");
            count += 1;
        }
        assert!(count > 0, "{module} has no public functions to audit");
    }

    // core_range calls every core::range function and method; the methods
    // are checked by name after a `.`.
    let range_cases = include_str!("fixtures/stdlib_foundation/core_range.lani");
    let (mut range_functions, mut range_methods) = (0, 0);
    for line in include_str!("../stdlib/core/range.lani").lines() {
        let (tail, prefix) = if let Some(tail) = line.strip_prefix("pub fn ") {
            range_functions += 1;
            (tail, "core::range::")
        } else if let Some(tail) = line.strip_prefix("    pub fn ") {
            range_methods += 1;
            (tail, ".")
        } else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("range function has a name");
        let call = format!("{prefix}{name}(");
        assert!(
            range_cases.contains(&call),
            "core::range {call} lacks a runtime case"
        );
    }
    assert_eq!((range_functions, range_methods), (20, 15));

    assert!(
        include_str!("fixtures/stdlib_foundation/core_f32.lani").contains("core::f32::ZERO"),
        "core::f32::ZERO lacks a runtime case"
    );
    assert!(
        include_str!("fixtures/stdlib_foundation/core_f32.lani").contains("core::f32::ONE"),
        "core::f32::ONE lacks a runtime case"
    );

    let hash_fixture = include_str!("fixtures/stdlib_foundation/core_hash.lani");
    let mut hash_count = 0;
    for line in include_str!("../stdlib/core/hash.lani").lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("hash function has a name");
        let call = format!("core::hash::{name}(");
        assert!(hash_fixture.contains(&call), "{call} lacks a runtime case");
        hash_count += 1;
    }
    assert_eq!(hash_count, 12);

    // Call-name inventory across the old and current executing producers.
    // This bookkeeping check does not itself establish runtime behavior.
    let option_result_fixture = format!(
        "{}\n{}\n{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/core_option_result.lani"),
        include_str!("fixtures/stdlib_foundation/option_bool.lani"),
        include_str!("fixtures/stdlib_foundation/option_generic_scalar_predicates.lani"),
        include_str!("fixtures/stdlib_foundation/option_generic_scalar_payload_functions.lani"),
        include_str!("fixtures/stdlib_foundation/outcome_composition/contracts.lani"),
    );
    for (module, source, expected_functions, expected_methods) in [
        ("option", include_str!("../stdlib/core/option.lani"), 14, 12),
        ("result", include_str!("../stdlib/core/result.lani"), 11, 11),
    ] {
        let mut functions = 0;
        let mut methods = 0;
        for line in source.lines() {
            let (tail, call) = if let Some(tail) = line.strip_prefix("pub fn ") {
                functions += 1;
                (tail, format!("core::{module}::"))
            } else if let Some(tail) = line.strip_prefix("    pub fn ") {
                methods += 1;
                (tail, ".".to_string())
            } else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            let generic_call = format!("{call}{name}<");
            let call = format!("{call}{name}(");
            assert!(
                option_result_fixture.contains(&call)
                    || option_result_fixture.contains(&generic_call),
                "core::{module} {call} lacks a runtime case"
            );
        }
        assert_eq!(
            (functions, methods),
            (expected_functions, expected_methods),
            "core::{module}"
        );
    }

    let io_fixtures = format!(
        "{}\n{}\n{}",
        include_str!("fixtures/stdlib_foundation/std_io_metadata.lani"),
        include_str!("fixtures/stdlib_host/std_io_lines.lani"),
        include_str!("fixtures/stdlib_host/std_io_flush_print.lani"),
    );
    for (module, source, fixture, expected_functions, expected_constants) in [
        (
            "core::target",
            include_str!("../stdlib/core/target.lani"),
            include_str!("fixtures/stdlib_foundation/core_target_metadata.lani"),
            19,
            17,
        ),
        (
            "core::runtime",
            include_str!("../stdlib/core/runtime.lani"),
            include_str!("fixtures/stdlib_foundation/core_runtime_metadata.lani"),
            63,
            42,
        ),
        (
            "test::harness",
            include_str!("../stdlib/test/harness.lani"),
            include_str!("fixtures/stdlib_foundation/test_harness_metadata.lani"),
            31,
            7,
        ),
        (
            "std::host",
            include_str!("../stdlib/std/host.lani"),
            include_str!("fixtures/stdlib_foundation/std_host_metadata.lani"),
            15,
            4,
        ),
        (
            "std::net",
            include_str!("../stdlib/std/net.lani"),
            include_str!("fixtures/stdlib_foundation/std_net_metadata.lani"),
            64,
            6,
        ),
        (
            "std::thread",
            include_str!("../stdlib/std/thread.lani"),
            include_str!("fixtures/stdlib_foundation/std_thread_metadata.lani"),
            32,
            6,
        ),
        (
            "std::gpu",
            include_str!("../stdlib/std/gpu.lani"),
            include_str!("fixtures/stdlib_foundation/std_gpu_metadata.lani"),
            44,
            6,
        ),
        (
            "std::process",
            include_str!("../stdlib/std/process.lani"),
            include_str!("fixtures/stdlib_foundation/std_process_metadata.lani"),
            44,
            12,
        ),
        (
            "std::env",
            include_str!("../stdlib/std/env.lani"),
            include_str!("fixtures/stdlib_foundation/std_env_metadata.lani"),
            54,
            13,
        ),
        (
            "std::io",
            include_str!("../stdlib/std/io.lani"),
            io_fixtures.as_str(),
            54,
            12,
        ),
        (
            "std::fs",
            include_str!("../stdlib/std/fs.lani"),
            include_str!("fixtures/stdlib_foundation/std_fs_metadata.lani"),
            67,
            18,
        ),
        (
            "std::random",
            include_str!("../stdlib/std/random.lani"),
            include_str!("fixtures/stdlib_foundation/std_random_metadata.lani"),
            28,
            8,
        ),
    ] {
        let mut function_count = 0;
        let mut constant_count = 0;
        for line in source.lines() {
            if let Some(tail) = line.strip_prefix("pub fn ") {
                let name = tail
                    .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                    .next()
                    .expect("public function has a name");
                let call = format!("{module}::{name}(");
                assert!(fixture.contains(&call), "{call} lacks a runtime case");
                function_count += 1;
            }
            if let Some(tail) = line.strip_prefix("pub const ") {
                let name = tail
                    .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                    .next()
                    .expect("public constant has a name");
                let path = format!("{module}::{name}");
                assert!(fixture.contains(&path), "{path} lacks a runtime case");
                constant_count += 1;
            }
        }
        assert_eq!(
            function_count, expected_functions,
            "{module} function count"
        );
        assert_eq!(
            constant_count, expected_constants,
            "{module} constant count"
        );
    }

    let vector_fixtures = [
        include_str!("fixtures/stdlib_foundation/std_vec.lani"),
        include_str!("fixtures/stdlib_foundation/std_vec_order.lani"),
        include_str!("fixtures/stdlib_foundation/std_vec_growth_failure.lani"),
    ];
    for line in include_str!("../stdlib/std/vec.lani").lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public vector function has a name");
        let call = format!("std::vec::{name}(");
        assert!(
            vector_fixtures
                .iter()
                .any(|fixture| fixture.contains(&call)),
            "{call} lacks a runtime case"
        );
    }
}
