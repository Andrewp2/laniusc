mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_wide_bit_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let module = std::fs::read_to_string(root.join("stdlib/core/wide_u64_bits.lani"))
        .expect("read wide bit helpers");
    let entry = root.join("tests/fixtures/stdlib_foundation/core_wide_u64_bits.lani");
    let fixture = std::fs::read_to_string(&entry).expect("read runtime fixture");
    let names: Vec<_> = module
        .lines()
        .filter_map(|line| line.trim().strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(names.len(), 12);
    for name in names {
        assert!(
            fixture.contains(&format!("core::wide_u64_bits::{name}(")),
            "{name} lacks a runtime call"
        );
    }

    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("wide bits", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile two-word wide bit helpers");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("wide bits", "wide_u64_bits", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
