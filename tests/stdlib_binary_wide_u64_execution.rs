mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_wide_binary_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let module = std::fs::read_to_string(root.join("stdlib/core/binary_wide_u64.lani"))
        .expect("read wide binary helpers");
    let entry = root.join("tests/fixtures/stdlib_foundation/core_binary_wide_u64.lani");
    let fixture = std::fs::read_to_string(&entry).expect("read runtime fixture");
    let names: Vec<_> = module
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 6);
    for name in names {
        assert!(
            fixture.contains(&format!("core::binary_wide_u64::{name}(")),
            "{name} lacks a runtime call"
        );
    }
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide binary", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile two-word binary helpers");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide binary", "binary_wide_u64", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn overstated_binary_view_traps_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/core_binary_wide_u64_bounds.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide binary bounds", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile overstated two-word binary view");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("wide binary bounds", "binary_wide_u64_bounds", &bytes);
        assert_eq!(output.status.code(), Some(101), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
