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
fn panic_metadata_reports_executable_traps_and_unbound_hooks() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/stdlib_foundation/core_panic_metadata.lani");
    let bytes = compile_fixture("panic metadata", &entry);

    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let output = common::run_x86_64_elf_output("panic metadata", "panic_metadata", &bytes);
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stdout.is_empty() && output.stderr.is_empty());
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn panic_and_unreachable_trap_instead_of_returning() {
    for (name, invocation) in [
        ("panic", "core::panic::panic();"),
        ("unreachable", "core::panic::unreachable();"),
    ] {
        let entry = common::TempArtifact::new("laniusc_panic", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\nimport core::panic;\nfn main() -> i32 {{\n    {invocation}\n    return 0;\n}}\n"
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

// `core::panic::panic()` returns `!`, so it can stand in a generic match arm
// of any type: unwrap returns the payload of Some and traps on None.
#[test]
fn generic_unwrap_with_panic_arm_returns_some_and_traps_on_none() {
    for (name, value, exit_code) in [("unwrap_some", "Some(42)", Some(42)), ("unwrap_none", "None", None)] {
        let entry = common::TempArtifact::new("laniusc_panic", name, Some("lani"));
        entry.write_str(&format!(
            "module app::main;\nimport core::panic;\nenum Opt<T> {{ Some(T), None }}\n\
             fn unwrap<T>(value: Opt<T>) -> T {{\n    \
             return match (value) {{ Some(inner) -> inner, None -> core::panic::panic() }};\n}}\n\
             fn main() -> i32 {{\n    let a: Opt<i32> = {value};\n    return unwrap(a);\n}}\n"
        ));
        let bytes = compile_fixture(name, entry.path());

        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            use std::os::unix::process::ExitStatusExt;

            if let Some(code) = exit_code {
                let output = common::run_x86_64_elf_output(name, name, &bytes);
                assert_eq!(output.status.code(), Some(code), "{name}: {output:?}");
            } else {
                let output = common::run_x86_64_elf_output_expecting_signal(name, name, &bytes);
                assert_eq!(output.status.signal(), Some(4), "{name}: {output:?}");
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = (bytes, exit_code);
    }
}
