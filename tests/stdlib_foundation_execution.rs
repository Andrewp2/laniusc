mod common;

use laniusc_compiler::compiler::{
    compile_entry_to_x86_64_with_stdlib,
    compile_source_to_x86_64_with_gpu_codegen,
};

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
            "option_result_i32",
            "tests/fixtures/stdlib_foundation/option_result_i32.lani",
            0,
            b"",
        ),
        (
            "option_result_u32",
            "tests/fixtures/stdlib_foundation/option_result_u32.lani",
            0,
            b"",
        ),
        (
            "option_result_u8",
            "tests/fixtures/stdlib_foundation/option_result_u8.lani",
            0,
            b"",
        ),
        (
            "option_result_i8",
            "tests/fixtures/stdlib_foundation/option_result_i8.lani",
            0,
            b"",
        ),
        (
            "option_result_i16",
            "tests/fixtures/stdlib_foundation/option_result_i16.lani",
            0,
            b"",
        ),
        (
            "option_result_u16",
            "tests/fixtures/stdlib_foundation/option_result_u16.lani",
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
            "core_u8_complete",
            "tests/fixtures/stdlib_foundation/core_u8_complete.lani",
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
            "core_slice_u8",
            "tests/fixtures/stdlib_foundation/core_slice_u8.lani",
            0,
            b"",
        ),
        (
            "core_slice_u8_complete",
            "tests/fixtures/stdlib_foundation/core_slice_u8_complete.lani",
            0,
            b"",
        ),
        (
            "core_slice_u16",
            "tests/fixtures/stdlib_foundation/core_slice_u16.lani",
            0,
            b"",
        ),
        (
            "core_slice_u16_complete",
            "tests/fixtures/stdlib_foundation/core_slice_u16_complete.lani",
            0,
            b"",
        ),
        (
            "core_slice_u16_bounds",
            "tests/fixtures/stdlib_foundation/core_slice_u16_bounds.lani",
            101,
            b"",
        ),
        (
            "core_slice_u32",
            "tests/fixtures/stdlib_foundation/core_slice_u32.lani",
            0,
            b"",
        ),
        (
            "core_slice_u32_complete",
            "tests/fixtures/stdlib_foundation/core_slice_u32_complete.lani",
            0,
            b"",
        ),
        (
            "slice_unsigned_sort_exhaustive",
            "tests/fixtures/stdlib_foundation/slice_unsigned_sort_exhaustive.lani",
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
            "core_range_u8",
            "tests/fixtures/stdlib_foundation/range_u8.lani",
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
            "core_range_i8",
            "tests/fixtures/stdlib_foundation/range_i8.lani",
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
            "core_range_u16",
            "tests/fixtures/stdlib_foundation/range_u16.lani",
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
            "core_range_i16",
            "tests/fixtures/stdlib_foundation/range_i16.lani",
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
            "core_hash_i32",
            "tests/fixtures/stdlib_foundation/core_hash_i32.lani",
            0,
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
            "vec_i32",
            "tests/fixtures/stdlib_foundation/vec_i32.lani",
            0,
            b"",
        ),
        (
            "vec_u32",
            "tests/fixtures/stdlib_foundation/vec_u32.lani",
            0,
            b"",
        ),
        (
            "vector_unsigned_checksum",
            "sample_programs/vector_unsigned_checksum.lani",
            0,
            b"4\n",
        ),
        (
            "vector_square_sum",
            "sample_programs/vector_square_sum.lani",
            0,
            b"285\n",
        ),
    ];

    for &(name, path, expected_exit, expected_stdout) in cases {
        let entry = root.join(path);
        let stdlib_root = stdlib_root.clone();
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{name}: compile: {err}"));

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
fn legacy_scalar_functions_execute_on_x86() {
    let bool_source = include_str!("../stdlib/bool.lani");
    let i32_source = include_str!("../stdlib/i32.lani");
    let main_source = include_str!("fixtures/stdlib_foundation/legacy_scalars_main.lani");
    for library in [bool_source, i32_source] {
        for line in library.lines() {
            let Some(tail) = line.trim_start().strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            assert!(
                main_source.contains(&format!("{name}(")),
                "{name} lacks a runtime case"
            );
        }
    }
    let source = format!("{bool_source}\n{i32_source}\n{main_source}");
    let bytes = common::run_gpu_codegen_with_timeout("legacy_scalars", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("compile legacy scalar functions");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("legacy_scalars", "legacy_scalars", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn legacy_i32x4_functions_execute_on_x86() {
    let library = include_str!("../stdlib/array_i32_4.lani");
    let main_source = include_str!("fixtures/stdlib_foundation/legacy_i32x4_main.lani");
    for line in library.lines() {
        let Some(tail) = line.trim_start().strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("public function has a name");
        assert!(
            main_source.contains(&format!("{name}(")),
            "{name} lacks a runtime case"
        );
    }
    let source = format!("{library}\n{main_source}");
    let bytes = common::run_gpu_codegen_with_timeout("legacy_i32x4", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("compile legacy i32x4 functions");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("legacy_i32x4", "legacy_i32x4", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

// Guard the runtime fixtures against a newly added public helper going
// unexercised. The fixtures themselves still provide the behavior assertions.
#[test]
fn executable_core_function_surface_has_runtime_cases() {
    let modules = [
        (
            "i32",
            include_str!("../stdlib/core/i32.lani"),
            include_str!("fixtures/stdlib_foundation/core_i32_complete.lani"),
        ),
        (
            "u8",
            include_str!("../stdlib/core/u8.lani"),
            include_str!("fixtures/stdlib_foundation/core_u8_complete.lani"),
        ),
        (
            "u32",
            include_str!("../stdlib/core/u32.lani"),
            include_str!("fixtures/stdlib_foundation/core_u32_complete.lani"),
        ),
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
            "f32",
            include_str!("../stdlib/core/f32.lani"),
            include_str!("fixtures/stdlib_foundation/core_f32.lani"),
        ),
        (
            "byte",
            include_str!("../stdlib/core/byte.lani"),
            include_str!("fixtures/stdlib_foundation/number_byte.lani"),
        ),
        (
            "number_i32",
            include_str!("../stdlib/core/number_i32.lani"),
            include_str!("fixtures/stdlib_foundation/number_byte.lani"),
        ),
        (
            "number_i8",
            include_str!("../stdlib/core/number_i8.lani"),
            include_str!("fixtures/stdlib_foundation/number_i8.lani"),
        ),
        (
            "number_i16",
            include_str!("../stdlib/core/number_i16.lani"),
            include_str!("fixtures/stdlib_foundation/number_i16.lani"),
        ),
        (
            "number_u16",
            include_str!("../stdlib/core/number_u16.lani"),
            include_str!("fixtures/stdlib_foundation/number_u16.lani"),
        ),
        (
            "number_u32",
            include_str!("../stdlib/core/number_u32.lani"),
            include_str!("fixtures/stdlib_foundation/number_u32.lani"),
        ),
        (
            "decimal",
            include_str!("../stdlib/core/decimal.lani"),
            include_str!("fixtures/stdlib_foundation/core_decimal.lani"),
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
            "range_u8",
            include_str!("../stdlib/core/range_u8.lani"),
            include_str!("fixtures/stdlib_foundation/range_u8.lani"),
        ),
        (
            "range_i8",
            include_str!("../stdlib/core/range_i8.lani"),
            include_str!("fixtures/stdlib_foundation/range_i8.lani"),
        ),
        (
            "range_u16",
            include_str!("../stdlib/core/range_u16.lani"),
            include_str!("fixtures/stdlib_foundation/range_u16.lani"),
        ),
        (
            "range_i16",
            include_str!("../stdlib/core/range_i16.lani"),
            include_str!("fixtures/stdlib_foundation/range_i16.lani"),
        ),
        (
            "slice",
            include_str!("../stdlib/core/slice.lani"),
            include_str!("fixtures/stdlib_foundation/range_slice.lani"),
        ),
        (
            "slice_u8",
            include_str!("../stdlib/core/slice_u8.lani"),
            include_str!("fixtures/stdlib_foundation/core_slice_u8.lani"),
        ),
        (
            "slice_u16",
            include_str!("../stdlib/core/slice_u16.lani"),
            include_str!("fixtures/stdlib_foundation/core_slice_u16.lani"),
        ),
        (
            "slice_u32",
            include_str!("../stdlib/core/slice_u32.lani"),
            include_str!("fixtures/stdlib_foundation/core_slice_u32.lani"),
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
            let call = format!("core::{module}::{name}(");
            let covered = fixture.contains(&call)
                || module == "range_u8"
                    && include_str!("fixtures/stdlib_foundation/core_range_u8_aggregate.lani")
                        .contains(&call)
                || module == "range_i8"
                    && include_str!("fixtures/stdlib_foundation/core_range_i8_aggregate.lani")
                        .contains(&call)
                || module == "range_u16"
                    && include_str!("fixtures/stdlib_foundation/core_range_u16_aggregate.lani")
                        .contains(&call)
                || module == "range_i16"
                    && include_str!("fixtures/stdlib_foundation/core_range_i16_aggregate.lani")
                        .contains(&call)
                || module == "slice_u8"
                    && include_str!("fixtures/stdlib_foundation/core_slice_u8_complete.lani")
                        .contains(&call)
                || module == "slice_u16"
                    && include_str!("fixtures/stdlib_foundation/core_slice_u16_complete.lani")
                        .contains(&call)
                || module == "slice_u32"
                    && include_str!("fixtures/stdlib_foundation/core_slice_u32_complete.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_sequence.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_subsequence.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_compaction.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_copy_nonoverlapping.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_partition_search.lani")
                        .contains(&call)
                || module == "slice"
                    && include_str!("fixtures/stdlib_foundation/slice_insert.lani").contains(&call);
            assert!(covered, "{module}::{name} lacks a runtime case");
            count += 1;
        }
        assert!(count > 0, "{module} has no public functions to audit");
    }

    let range_cases = format!(
        "{}{}{}",
        include_str!("fixtures/stdlib_foundation/range_slice.lani"),
        include_str!("fixtures/stdlib_foundation/core_unbounded_ranges.lani"),
        include_str!("fixtures/stdlib_foundation/core_u32_ranges.lani")
    );
    let mut range_count = 0;
    for line in include_str!("../stdlib/core/range.lani").lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("range function has a name");
        let call = format!("core::range::{name}(");
        assert!(
            range_cases.contains(&call),
            "core::range::{name} lacks a runtime case"
        );
        range_count += 1;
    }
    assert!(range_count > 0);

    let number_byte = include_str!("fixtures/stdlib_foundation/number_byte.lani");
    for module in ["byte", "number_i32"] {
        for name in ["MIN", "MAX"] {
            let reference = format!("core::{module}::{name}");
            assert!(
                number_byte.contains(&reference),
                "{reference} lacks a runtime case"
            );
        }
    }
    for name in ["MIN", "MAX"] {
        let reference = format!("core::number_u32::{name}");
        assert!(
            include_str!("fixtures/stdlib_foundation/number_u32.lani").contains(&reference),
            "{reference} lacks a runtime case"
        );
    }
    assert!(
        include_str!("fixtures/stdlib_foundation/core_f32.lani").contains("core::f32::ZERO"),
        "core::f32::ZERO lacks a runtime case"
    );
    assert!(
        include_str!("fixtures/stdlib_foundation/core_f32.lani").contains("core::f32::ONE"),
        "core::f32::ONE lacks a runtime case"
    );

    let hash_fixture = include_str!("fixtures/stdlib_foundation/core_hash_i32.lani");
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
    assert_eq!(hash_count, 1);

    let i32_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_i32.lani");
    let u8_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_u8.lani");
    let i8_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_i8.lani");
    let i16_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_i16.lani");
    let u16_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_u16.lani");
    let u32_result_fixture = include_str!("fixtures/stdlib_foundation/option_result_u32.lani");
    for (module, source, fixture, expected_count) in [
        (
            "option_i32",
            include_str!("../stdlib/core/option_i32.lani"),
            i32_result_fixture,
            12,
        ),
        (
            "result_i32",
            include_str!("../stdlib/core/result_i32.lani"),
            i32_result_fixture,
            10,
        ),
        (
            "option_u8",
            include_str!("../stdlib/core/option_u8.lani"),
            u8_result_fixture,
            12,
        ),
        (
            "result_u8",
            include_str!("../stdlib/core/result_u8.lani"),
            u8_result_fixture,
            10,
        ),
        (
            "option_i8",
            include_str!("../stdlib/core/option_i8.lani"),
            i8_result_fixture,
            12,
        ),
        (
            "result_i8",
            include_str!("../stdlib/core/result_i8.lani"),
            i8_result_fixture,
            10,
        ),
        (
            "option_i16",
            include_str!("../stdlib/core/option_i16.lani"),
            i16_result_fixture,
            12,
        ),
        (
            "result_i16",
            include_str!("../stdlib/core/result_i16.lani"),
            i16_result_fixture,
            10,
        ),
        (
            "option_u16",
            include_str!("../stdlib/core/option_u16.lani"),
            u16_result_fixture,
            12,
        ),
        (
            "result_u16",
            include_str!("../stdlib/core/result_u16.lani"),
            u16_result_fixture,
            10,
        ),
        (
            "option_u32",
            include_str!("../stdlib/core/option_u32.lani"),
            u32_result_fixture,
            12,
        ),
        (
            "result_u32",
            include_str!("../stdlib/core/result_u32.lani"),
            u32_result_fixture,
            10,
        ),
    ] {
        let mut count = 0;
        for line in source.lines() {
            let Some(tail) = line.strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            let call = format!("core::{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
            count += 1;
        }
        assert_eq!(count, expected_count);
    }

    for (module, vector_source, vector_fixture) in [
        (
            "vec_i32",
            include_str!("../stdlib/std/vec_i32.lani"),
            include_str!("fixtures/stdlib_foundation/vec_i32.lani"),
        ),
        (
            "vec_u32",
            include_str!("../stdlib/std/vec_u32.lani"),
            include_str!("fixtures/stdlib_foundation/vec_u32.lani"),
        ),
    ] {
        let mut vector_function_count = 0;
        for line in vector_source.lines() {
            let Some(tail) = line.strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public vector function has a name");
            let call = format!("std::{module}::{name}(");
            assert!(vector_fixture.contains(&call), "{call} lacks a runtime case");
            vector_function_count += 1;
        }
        assert_eq!(vector_function_count, 12);
        assert!(vector_fixture.contains(&format!("std::{module}::MAX_CAPACITY")));
    }
}
