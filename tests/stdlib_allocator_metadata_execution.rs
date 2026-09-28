mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn allocator_metadata_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/allocator_metadata.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("allocator_metadata", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("allocator_metadata: compile: {error}"));

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("allocator_metadata", "allocator_metadata", &bytes);
        assert_eq!(
            output.status.code(),
            Some(0),
            "allocator_metadata: {output:?}"
        );
        assert!(output.stdout.is_empty(), "unexpected stdout");
        assert!(output.stderr.is_empty(), "unexpected stderr");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_allocator_metadata_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/alloc/allocator.lani");
    let fixture = include_str!("fixtures/stdlib_foundation/allocator_metadata.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("allocator metadata function has a name");
        let call = format!("alloc::allocator::{name}(");
        assert!(fixture.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 32);
}
