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
            "core_f32",
            "tests/fixtures/stdlib_foundation/core_f32.lani",
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
            "range_slice",
            "tests/fixtures/stdlib_foundation/range_slice.lani",
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
            "core_array_i32_4_scalar",
            "tests/fixtures/stdlib_foundation/core_array_i32_4_scalar.lani",
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
            "portable_window_checksum",
            "sample_programs/portable_window_checksum.lani",
            0,
            b"96\n",
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
fn legacy_i32_power_boundaries_execute_on_x86() {
    let source = format!(
        "{}\nfn main() -> i32 {{\n\
         if (!lstd_i32_is_power_of_two(1073741824) || lstd_i32_is_power_of_two(2147483647)) {{ return 1; }}\n\
         if (lstd_i32_next_power_of_two(7) != 8 || lstd_i32_next_power_of_two(2147483647) != 0) {{ return 2; }}\n\
         return 0;\n}}",
        include_str!("../stdlib/i32.lani")
    );
    let bytes = common::run_gpu_codegen_with_timeout("legacy_i32_power_boundaries", move || {
        pollster::block_on(compile_source_to_x86_64_with_gpu_codegen(&source))
    })
    .expect("compile legacy i32 power boundaries");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "legacy_i32_power_boundaries",
            "legacy_i32_power_boundaries",
            &bytes,
        );
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
            "number_u32",
            include_str!("../stdlib/core/number_u32.lani"),
            include_str!("fixtures/stdlib_foundation/number_u32.lani"),
        ),
        (
            "slice",
            include_str!("../stdlib/core/slice.lani"),
            include_str!("fixtures/stdlib_foundation/range_slice.lani"),
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
            assert!(
                fixture.contains(&call),
                "{module}::{name} lacks a runtime case"
            );
            count += 1;
        }
        assert!(count > 0, "{module} has no public functions to audit");
    }

    let range_cases = format!(
        "{}{}",
        include_str!("fixtures/stdlib_foundation/range_slice.lani"),
        include_str!("fixtures/stdlib_foundation/core_unbounded_ranges.lani")
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
}
