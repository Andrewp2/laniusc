mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_character_range_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let module = std::fs::read_to_string(root.join("stdlib/core/range_char.lani"))
        .expect("read character range module");
    let entry = root.join("tests/fixtures/stdlib_foundation/range_char.lani");
    let fixture = std::fs::read_to_string(&entry).expect("read character range fixture");
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
        ("closed", "start"),
        ("closed", "end"),
        ("closed", "is_empty"),
        ("closed", "contains"),
        ("closed", "overlaps"),
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
    let bytes = common::run_gpu_codegen_with_timeout("character range methods", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile character range methods");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("character range methods", "range_char_methods", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
