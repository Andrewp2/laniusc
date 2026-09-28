mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn signed_varints_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, stdout) in [
        (
            "core_varint_i32",
            "tests/fixtures/stdlib_foundation/core_varint_i32.lani",
            b"".as_slice(),
        ),
        (
            "core_varint_i32_matrix",
            "tests/fixtures/stdlib_foundation/core_varint_i32_matrix.lani",
            b"".as_slice(),
        ),
        (
            "core_varint_wide_i64",
            "tests/fixtures/stdlib_foundation/core_varint_wide_i64.lani",
            b"".as_slice(),
        ),
        (
            "varint_signed_frame_sum",
            "sample_programs/varint_signed_frame_sum.lani",
            b"-4294967321\n".as_slice(),
        ),
    ] {
        let entry = root.join(source);
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert_eq!(output.stdout, stdout, "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, stdout);
    }
}

#[test]
fn every_public_signed_varint_function_has_a_runtime_case() {
    for (module, source, fixture) in [
        (
            "core::varint_i32",
            include_str!("../stdlib/core/varint_i32.lani"),
            include_str!("fixtures/stdlib_foundation/core_varint_i32.lani"),
        ),
        (
            "core::varint_wide_i64",
            include_str!("../stdlib/core/varint_wide_i64.lani"),
            include_str!("fixtures/stdlib_foundation/core_varint_wide_i64.lani"),
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
                .expect("signed varint function has a name");
            let call = format!("{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
            count += 1;
        }
        assert_eq!(count, 6, "{module} public function count changed");
    }
}
