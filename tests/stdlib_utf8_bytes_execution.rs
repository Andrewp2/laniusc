mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_entry(name: &str, path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib_root = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[test]
fn byte_backed_utf8_operations_execute_on_x86() {
    for (name, path, exit_code, stdout) in [
        (
            "core_utf8_bytes",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_bytes_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_bytes_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_search",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_search.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_search_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_search_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_append",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_append.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_append_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_append_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_edit",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_edit.lani",
            0,
            b"".as_slice(),
        ),
        (
            "core_utf8_byte_edit_bounds",
            "tests/fixtures/stdlib_foundation/core_utf8_byte_edit_bounds.lani",
            101,
            b"".as_slice(),
        ),
        (
            "utf8_text_report",
            "sample_programs/utf8_text_report.lani",
            0,
            b"A\xc2\xa2A\xc2\xa2B5\n".as_slice(),
        ),
    ] {
        let bytes = compile_entry(name, path);
        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(exit_code), "{name}: {output:?}");
            assert_eq!(output.stdout, stdout, "{name}: stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, exit_code);
    }
}
