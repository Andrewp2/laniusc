mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_float_method_return_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_imported_f32_method.lani");
    let stdlib_root = root.join("tests/fixtures/stdlib_foundation/repro_imported_f32_method_root");
    let bytes = common::run_gpu_codegen_with_timeout("imported f32 method return", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile imported f32 method return");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "imported f32 method return",
            "imported_f32_method",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn imported_float_range_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let module = std::fs::read_to_string(root.join("stdlib/core/range_f32.lani"))
        .expect("read floating range module");
    let entry = root.join("tests/fixtures/stdlib_foundation/range_f32.lani");
    let fixture = std::fs::read_to_string(&entry).expect("read floating range fixture");
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
    let bytes = common::run_gpu_codegen_with_timeout("floating range methods", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile floating range methods");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("floating range methods", "range_f32_methods", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn floating_window_program_uses_imported_range_method() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/floating_window_total.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("floating window sample", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile floating window sample");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "floating window sample",
            "floating_window_total_methods",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"2\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
