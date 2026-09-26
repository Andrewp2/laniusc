mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn path_lexical_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    for name in [
        "path_bytes",
        "path_components",
        "path_separator_kind",
        "path_constants",
    ] {
        let entry = root.join(format!("tests/fixtures/stdlib_host/{name}.lani"));
        let stdlib_root = stdlib_root.clone();
        let bytes = common::run_gpu_codegen_with_timeout(name, move || {
            pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
        })
        .unwrap_or_else(|err| panic!("{name}: compile: {err}"));

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
fn executable_path_predicates_have_runtime_cases() {
    let unverified = [
        "path_contract_metadata_is_available",
        "path_lexical_byte_helpers_are_available",
        "path_allocation_api_is_executable",
        "path_allocation_api_is_blocked",
        "path_allocation_api_is_known_but_unbound",
        "path_allocation_api_requires_allocator",
        "path_host_normalization_is_executable",
        "path_host_normalization_is_blocked",
        "path_host_normalization_is_known_but_unbound",
        "path_host_normalization_requires_runtime_binding",
        "path_unix_separator_byte",
        "path_windows_separator_byte",
        "path_extension_separator_byte",
        "path_drive_separator_byte",
        "path_nul_byte",
    ];
    let cases = format!(
        "{}{}{}",
        include_str!("fixtures/stdlib_host/path_bytes.lani"),
        include_str!("fixtures/stdlib_host/path_components.lani"),
        include_str!("fixtures/stdlib_host/path_separator_kind.lani")
    );
    let mut covered = 0;
    for line in include_str!("../stdlib/std/path.lani").lines() {
        let Some(tail) = line.strip_prefix("pub fn ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("path function has a name");
        if unverified.contains(&name) {
            continue;
        }
        let call = format!("std::path::{name}(");
        assert!(cases.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 32);

    let constants = include_str!("fixtures/stdlib_host/path_constants.lani");
    let mut constant_count = 0;
    for line in include_str!("../stdlib/std/path.lani").lines() {
        let Some(tail) = line.strip_prefix("pub const ") else {
            continue;
        };
        let name = tail
            .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_'))
            .next()
            .expect("path constant has a name");
        let reference = format!("std::path::{name}");
        assert!(
            constants.contains(&reference),
            "{reference} lacks a runtime case"
        );
        constant_count += 1;
    }
    assert_eq!(constant_count, 17);
}
