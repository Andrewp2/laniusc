mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn concrete_wide_unsigned_option_result_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/option_result_wide_u64.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("option_result_wide_u64", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile concrete two-word unsigned Option and Result");

    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("option_result_wide_u64", "complete", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty(), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn every_public_wide_unsigned_option_result_function_has_a_runtime_case() {
    let fixture = include_str!("fixtures/stdlib_foundation/option_result_wide_u64.lani");
    for (module, source, expected_count) in [
        (
            "core::option_wide_u64",
            include_str!("../stdlib/core/option_wide_u64.lani"),
            12,
        ),
        (
            "core::result_wide_u64",
            include_str!("../stdlib/core/result_wide_u64.lani"),
            10,
        ),
    ] {
        let mut covered = 0;
        for line in source.lines() {
            let Some(tail) = line.strip_prefix("pub fn ") else {
                continue;
            };
            let name = tail
                .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
                .next()
                .expect("public function has a name");
            let call = format!("{module}::{name}(");
            assert!(fixture.contains(&call), "{call} lacks a runtime case");
            covered += 1;
        }
        assert_eq!(covered, expected_count, "{module}");
    }
}
