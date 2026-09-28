mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_wide_signed_ranges_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let module = std::fs::read_to_string(root.join("stdlib/core/wide_i64_range.lani"))
        .expect("read signed wide ranges");
    let entry = root.join("tests/fixtures/stdlib_foundation/core_wide_i64_range.lani");
    let fixture = std::fs::read_to_string(&entry).expect("read runtime fixture");
    let free_names: Vec<_> = module
        .lines()
        .filter_map(|line| line.strip_prefix("pub fn "))
        .map(|declaration| declaration.split('(').next().expect("function name"))
        .collect();
    assert_eq!(free_names.len(), 19);
    for name in free_names {
        assert!(
            fixture.contains(&format!("core::wide_i64_range::{name}(")),
            "{name} lacks a runtime call"
        );
    }
    assert_eq!(
        module
            .lines()
            .filter(|line| line.starts_with("    pub fn "))
            .count(),
        14
    );
    for (receiver, name) in [
        ("half", "start"),
        ("half", "end"),
        ("half", "is_empty"),
        ("half", "contains"),
        ("half", "overlaps"),
        ("inclusive", "start"),
        ("inclusive", "end"),
        ("inclusive", "is_empty"),
        ("inclusive", "contains"),
        ("inclusive", "overlaps"),
        ("from", "start"),
        ("from", "contains"),
        ("to", "end"),
        ("to", "contains"),
    ] {
        assert!(
            fixture.contains(&format!("{receiver}.{name}(")),
            "{receiver}.{name} lacks a runtime call"
        );
    }
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("signed wide ranges", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile signed wide ranges");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("signed wide ranges", "wide_i64_range", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
