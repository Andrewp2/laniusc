mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn memory_helpers_and_slice_intrinsics_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for name in [
        "core_mem_metadata",
        "core_mem_values",
        "core_mem_intrinsics",
        "core_mem_typed_slice_intrinsic",
        "core_mem_generic_slice",
        "repro_generic_slice_return_context",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(unix, target_arch = "x86_64"))]
        {
            let output = common::run_x86_64_elf_output(name, name, &bytes);
            assert_eq!(output.status.code(), Some(0), "{name}: {output:?}");
            assert!(output.stdout.is_empty(), "{name}: unexpected stdout");
            assert!(output.stderr.is_empty(), "{name}: unexpected stderr");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn generic_slice_constructor_rejects_invalid_lengths_and_indices() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    for (name, expected_code, expected_signal) in [
        ("core_mem_generic_slice_negative", None, Some(4)),
        ("core_mem_generic_slice_oob", Some(101), None),
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
        let stdlib_root = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|error| panic!("{name}: compile: {error}"));

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::process::ExitStatusExt;

            let output = if expected_signal.is_some() {
                common::run_x86_64_elf_output_expecting_signal(name, name, &bytes)
            } else {
                common::run_x86_64_elf_output(name, name, &bytes)
            };
            assert_eq!(output.status.code(), expected_code, "{name}: {output:?}");
            assert_eq!(
                output.status.signal(),
                expected_signal,
                "{name}: {output:?}"
            );
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, expected_code, expected_signal);
    }
}

#[test]
fn every_public_memory_function_has_a_runtime_case() {
    let source = include_str!("../stdlib/core/mem.lani");
    let metadata = include_str!("fixtures/stdlib_foundation/core_mem_metadata.lani");
    let values = include_str!("fixtures/stdlib_foundation/core_mem_values.lani");
    let generic_slice = include_str!("fixtures/stdlib_foundation/core_mem_generic_slice.lani");
    let mut covered = 0;
    for line in source.lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("memory function has a name");
        let call = format!("core::mem::{name}(");
        assert!(
            metadata.contains(&call) || values.contains(&call) || generic_slice.contains(&call),
            "{call} lacks a runtime case"
        );
        covered += 1;
    }
    assert_eq!(covered, 19);
}
