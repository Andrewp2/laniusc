mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn caller_backed_varints_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, exit_code, stdout) in [
        (
            "core_varint",
            "tests/fixtures/stdlib_foundation/core_varint.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_varint_matrix",
            "tests/fixtures/stdlib_foundation/core_varint_matrix.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_varint_wide_min",
            "tests/fixtures/stdlib_foundation/core_varint_wide_min.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_varint_read_bounds",
            "tests/fixtures/stdlib_foundation/core_varint_read_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_varint_write_bounds",
            "tests/fixtures/stdlib_foundation/core_varint_write_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_varint_wide_read_bounds",
            "tests/fixtures/stdlib_foundation/core_varint_wide_read_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_varint_wide_write_bounds",
            "tests/fixtures/stdlib_foundation/core_varint_wide_write_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "varint_frame_sum",
            "sample_programs/varint_frame_sum.lani",
            0,
            b"4294967606\n".as_slice(),
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
            assert_eq!(output.status.code(), Some(exit_code), "{name}: {output:?}");
            assert_eq!(output.stdout, stdout, "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, exit_code, stdout);
    }
}

#[test]
fn every_public_varint_function_has_a_runtime_case() {
    let fixture = include_str!("fixtures/stdlib_foundation/core_varint.lani");
    for (module, source) in [
        ("core::varint", include_str!("../stdlib/core/varint.lani")),
        (
            "core::varint_wide_u64",
            include_str!("../stdlib/core/varint_wide_u64.lani"),
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
                .expect("varint function has a name");
            let call = format!("{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
            count += 1;
        }
        assert_eq!(count, 6, "{module} public function count changed");
    }
}
