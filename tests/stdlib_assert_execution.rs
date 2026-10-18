mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str, entry: &std::path::Path) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    let entry = entry.to_path_buf();
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .unwrap_or_else(|error| panic!("{name}: compile: {error}"))
}

#[test]
fn all_public_assert_helpers_continue_when_their_conditions_hold() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/repro_assert_pass.lani");
    let bytes = compile_fixture("assert pass", &entry);

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("assert pass", "assert_pass", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_assert_helper_terminates_on_a_failed_condition() {
    for (name, invocation) in [
        ("is_true", "test::assert::is_true(false);"),
        ("is_false", "test::assert::is_false(true);"),
        ("eq_i32", "test::assert::eq_i32(7, 8);"),
        ("ne_i32", "test::assert::ne_i32(7, 7);"),
        ("lt_i32", "test::assert::lt_i32(8, 7);"),
        ("le_i32", "test::assert::le_i32(8, 7);"),
        ("gt_i32", "test::assert::gt_i32(7, 8);"),
        ("ge_i32", "test::assert::ge_i32(7, 8);"),
    ] {
        let entry = common::TempArtifact::new("laniusc_assert", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\nimport test::assert;\nfn main() -> i32 {{\n    {invocation}\n    return 0;\n}}\n"
        ));
        let bytes = compile_fixture(name, entry.path());

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::process::ExitStatusExt;

            let output = common::run_x86_64_elf_output_expecting_signal(name, name, &bytes);
            assert_eq!(output.status.signal(), Some(4), "{name}: {output:?}");
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}
