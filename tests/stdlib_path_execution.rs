mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

#[test]
fn imported_no_argument_byte_and_bool_returns_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("tests/fixtures/stdlib_host/repro_path_no_arg_root");
    for name in ["repro_path_byte_return", "repro_path_capability_return"] {
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
fn path_lexical_helpers_execute_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    for name in [
        "path_bytes",
        "path_components",
        "path_separator_kind",
        "path_constants",
        "path_full_components",
        "path_windows_portable_utf8",
        "path_last_component",
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
fn path_extension_sample_executes_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/path_extension_lowercase.lani");
    let stdlib_root = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("path_extension_lowercase", move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib_root))
    })
    .expect("compile path extension sample");
    #[cfg(all(unix, target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output(
            "path_extension_lowercase",
            "path_extension_lowercase",
            &bytes,
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(output.stdout, b"txt\n");
        assert!(output.stderr.is_empty());
    }
    #[cfg(not(all(unix, target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn path_view_length_overclaims_trap_on_x86() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let stdlib_root = root.join("stdlib");
    for name in [
        "path_full_component_bounds",
        "path_windows_portable_bounds",
        "path_last_component_bounds",
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
            assert_eq!(output.status.code(), Some(101), "{name}: {output:?}");
        }
        #[cfg(not(all(unix, target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn public_path_functions_have_runtime_cases() {
    let cases = format!(
        "{}{}{}{}{}{}",
        include_str!("fixtures/stdlib_host/path_bytes.lani"),
        include_str!("fixtures/stdlib_host/path_components.lani"),
        include_str!("fixtures/stdlib_host/path_separator_kind.lani"),
        include_str!("fixtures/stdlib_host/path_full_components.lani"),
        include_str!("fixtures/stdlib_host/path_windows_portable_utf8.lani"),
        include_str!("fixtures/stdlib_host/path_last_component.lani")
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
        let call = format!("std::path::{name}(");
        assert!(cases.contains(&call), "{call} lacks a runtime case");
        covered += 1;
    }
    assert_eq!(covered, 38);

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
