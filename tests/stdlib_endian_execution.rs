mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn caller_backed_endian_reads_and_writes_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, exit_code, stdout) in [
        (
            "core_endian",
            "tests/fixtures/stdlib_foundation/core_endian.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_endian_matrix",
            "tests/fixtures/stdlib_foundation/core_endian_matrix.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_endian_read_bounds",
            "tests/fixtures/stdlib_foundation/core_endian_read_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_endian_write_bounds",
            "tests/fixtures/stdlib_foundation/core_endian_write_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "packet_header_sum",
            "sample_programs/packet_header_sum.lani",
            0,
            b"67\n".as_slice(),
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
fn every_public_endian_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/endian.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_endian.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("endian function has a name");
        let call = format!("core::endian::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 8);
}
