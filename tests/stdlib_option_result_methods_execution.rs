mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn concrete_option_result_methods_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let fixture_path = root.join("tests/fixtures/stdlib_foundation/option_result_i32.lani");
    let fixture = std::fs::read_to_string(&fixture_path).expect("read option/result fixture");
    for module in ["option_i32", "result_i32"] {
        let source = std::fs::read_to_string(root.join(format!("stdlib/core/{module}.lani")))
            .expect("read option/result module");
        assert_eq!(
            source
                .lines()
                .filter(|line| line.starts_with("    pub fn "))
                .count(),
            8,
            "{module}: receiver method count changed"
        );
    }
    for (receiver, method) in [
        ("present", "is_some"),
        ("absent", "is_none"),
        ("present", "contains"),
        ("present", "unwrap_or"),
        ("present", "or"),
        ("present", "and"),
        ("present", "xor"),
        ("present", "ok_or"),
        ("success", "is_ok"),
        ("failure", "is_err"),
        ("success", "contains"),
        ("failure", "contains_err"),
        ("success", "unwrap_or"),
        ("failure", "unwrap_err_or"),
        ("success", "or"),
        ("success", "and"),
    ] {
        assert!(
            fixture.contains(&format!("{receiver}.{method}(")),
            "{receiver}.{method} lacks a runtime call"
        );
    }
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("option/result methods", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(
            &fixture_path,
            &stdlib_root,
        ))
    })
    .expect("compile option/result methods");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output =
            common::run_x86_64_elf_output("option/result methods", "option_result_methods", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn option_result_program_uses_methods() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/option_result_helpers.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("option/result program", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile option/result program");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "option/result program",
            "option_result_methods_program",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"38\n");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}
