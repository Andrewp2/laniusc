mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn utf16_byte_views_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, source, expected_exit) in [
        (
            "core_utf16_bytes_complete",
            "tests/fixtures/stdlib_foundation/core_utf16_bytes_complete.lani",
            0,
        ),
        (
            "core_utf16_bytes_bounds",
            "tests/fixtures/stdlib_foundation/core_utf16_bytes_bounds.lani",
            101,
        ),
    ] {
        let entry = root.join(source);
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(
                output.status.code(),
                Some(expected_exit),
                "{name}: {output:?}"
            );
            assert!(output.stdout.is_empty(), "{name}: {output:?}");
            assert!(output.stderr.is_empty(), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, expected_exit);
    }
}

#[test]
fn every_utf16_byte_function_has_an_executable_case() {
    let source = include_str!("../stdlib/core/utf16_bytes.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_utf16_bytes_complete.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("UTF-16 byte function has a name");
        let call = format!("core::utf16_bytes::{name}(");
        assert!(fixture.contains(&call), "{call} lacks an executable case");
        covered += 1;
    }
    assert_eq!(covered, 19);
}
