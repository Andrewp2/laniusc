mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn caller_backed_crc32_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, exit_code) in [("core_crc32", 0), ("core_crc32_bounds", 101)] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(exit_code), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = (bytes, exit_code);
    }
}

#[test]
fn every_public_crc32_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/crc32.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/core_crc32.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("CRC-32 function has a name");
        let call = format!("core::crc32::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 3);
}
